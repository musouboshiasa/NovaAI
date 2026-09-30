import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { Constants } from '../common/Constants';
import { Logger } from '../common/Logger';

export type HeaderMap = Record<string, string>;

/** 流式回调 */
export interface StreamCallbacks {
  /** 收到正文增量（已按 UTF-8 解码，保证字符完整） */
  onText: (text: string) => void;
  /** 收到响应头 */
  onHeaders?: (statusCode: number, headers: HeaderMap) => void;
  /** 正常结束（HTTP 200） */
  onDone: () => void;
  /** 失败；statusCode 为 -1 表示网络层异常 */
  onFail: (message: string, statusCode: number) => void;
}

/** 可取消的请求句柄 */
export class AbortHandle {
  private request: http.HttpRequest | null = null;
  private cancelled: boolean = false;

  attach(req: http.HttpRequest): void {
    this.request = req;
    if (this.cancelled) {
      this.destroyNow();
    }
  }

  isCancelled(): boolean {
    return this.cancelled;
  }

  cancel(): void {
    if (this.cancelled) {
      return;
    }
    this.cancelled = true;
    this.destroyNow();
  }

  private destroyNow(): void {
    const req: http.HttpRequest | null = this.request;
    if (req === null) {
      return;
    }
    try {
      req.off('dataReceive');
      req.off('dataEnd');
      req.off('headersReceive');
      req.destroy();
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Logger.warn('destroy request failed: ' + err.message);
    }
    this.request = null;
  }
}

/**
 * HTTP 客户端：封装 @ohos.net.http 的流式（requestInStream）与普通请求
 *
 * 说明：不同版本实现中「响应码 promise」与「dataReceive 事件」的先后顺序并不一致，
 * 因此这里做成了顺序无关的实现：响应码未知时先缓存正文，确定后再回放或当作错误体。
 */
export class HttpClient {
  static mergeHeaders(base: HeaderMap, extra: HeaderMap): HeaderMap {
    const out: HeaderMap = {};
    const keys: string[] = Object.keys(base);
    for (let i = 0; i < keys.length; i++) {
      out[keys[i]] = base[keys[i]];
    }
    const keys2: string[] = Object.keys(extra);
    for (let i = 0; i < keys2.length; i++) {
      out[keys2[i]] = extra[keys2[i]];
    }
    return out;
  }

  /** 发起流式 POST 请求 */
  static postStream(url: string, headers: HeaderMap, body: string, cb: StreamCallbacks): AbortHandle {
    const handle: AbortHandle = new AbortHandle();
    const req: http.HttpRequest = http.createHttp();
    handle.attach(req);

    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    /** -1 表示响应码未知 */
    let statusCode: number = -1;
    let ended: boolean = false;
    let finished: boolean = false;
    const pending: string[] = [];
    let pendingChars: number = 0;
    let errorBody: string = '';

    const route = (text: string): void => {
      if (statusCode === -1) {
        pending.push(text);
        pendingChars += text.length;
        return;
      }
      if (statusCode === 200) {
        cb.onText(text);
        return;
      }
      if (errorBody.length < 8192) {
        errorBody += text;
      }
    };

    const settle = (): void => {
      if (finished || !ended || statusCode === -1) {
        return;
      }
      finished = true;
      if (handle.isCancelled()) {
        cb.onDone();
        return;
      }
      if (statusCode === 200) {
        // 回放因响应码未知而缓存的正文
        for (let i = 0; i < pending.length; i++) {
          cb.onText(pending[i]);
        }
        pending.length = 0;
        cb.onDone();
      } else {
        let detail: string = '';
        for (let i = 0; i < pending.length; i++) {
          detail += pending[i];
        }
        if (detail.length === 0) {
          detail = errorBody;
        }
        pending.length = 0;
        cb.onFail(ErrorParser.humanize(detail, statusCode), statusCode);
      }
    };

    req.on('headersReceive', (h: Object) => {
      const map: HeaderMap = {};
      try {
        const raw: HeaderMap = h as HeaderMap;
        const ks: string[] = Object.keys(raw);
        for (let i = 0; i < ks.length; i++) {
          map[ks[i].toLowerCase()] = String(raw[ks[i]]);
        }
      } catch (e) {
        Logger.warn('parse headers failed');
      }
      if (cb.onHeaders !== undefined) {
        cb.onHeaders(statusCode, map);
      }
    });

    req.on('dataReceive', (data: ArrayBuffer) => {
      if (handle.isCancelled() || finished) {
        return;
      }
      let text: string = '';
      try {
        text = decoder.decodeToString(new Uint8Array(data), { stream: true });
      } catch (e) {
        Logger.warn('decode chunk failed');
        return;
      }
      if (text.length === 0) {
        return;
      }
      route(text);
    });

    req.on('dataEnd', () => {
      ended = true;
      settle();
    });

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: Constants.CONNECT_TIMEOUT_MS,
      readTimeout: Constants.READ_TIMEOUT_MS
    };

    req.requestInStream(url, options).then((code: number) => {
      statusCode = code;
      settle();
    }).catch((e: BusinessError) => {
      if (handle.isCancelled() || finished) {
        return;
      }
      finished = true;
      const msg: string = (e !== undefined && e.message !== undefined) ? e.message : '网络请求失败';
      cb.onFail(ErrorParser.humanize(msg, -1), -1);
    });

    return handle;
  }

  /** 普通（非流式）POST，返回响应文本 */
  static async postJson(url: string, headers: HeaderMap, body: string): Promise<string> {
    const req: http.HttpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: Constants.CONNECT_TIMEOUT_MS,
      readTimeout: Constants.READ_TIMEOUT_MS
    };
    try {
      const resp: http.HttpResponse = await req.request(url, options);
      const text: string = typeof resp.result === 'string' ? resp.result as string : JSON.stringify(resp.result);
      if (resp.responseCode !== 200) {
        throw new Error(ErrorParser.humanize(text, resp.responseCode));
      }
      return text;
    } finally {
      req.destroy();
    }
  }

  /** 普通 GET，返回响应文本 */
  /**
   * GET 并返回响应文本。
   * timeoutMs 可选：联网搜索这类"慢一点就没意义"的请求需要更短的超时，
   * 否则不可达的后端会干等 30 秒才失败。
   */
  static async getJson(url: string, headers: HeaderMap, timeoutMs: number = 0): Promise<string> {
    const req: http.HttpRequest = http.createHttp();
    const ct: number = timeoutMs > 0 ? timeoutMs : Constants.CONNECT_TIMEOUT_MS;
    const rt: number = timeoutMs > 0 ? timeoutMs : 60000;
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: ct,
      readTimeout: rt
    };
    try {
      const resp: http.HttpResponse = await req.request(url, options);
      const text: string = typeof resp.result === 'string' ? resp.result as string : JSON.stringify(resp.result);
      if (resp.responseCode !== 200) {
        throw new Error(ErrorParser.humanize(text, resp.responseCode));
      }
      return text;
    } finally {
      req.destroy();
    }
  }
}

/** 错误信息人性化：把各家 API 的错误 JSON 转成可读文本 */
export class ErrorParser {
  static humanize(raw: string, statusCode: number): string {
    const trimmed: string = (raw === undefined || raw === null) ? '' : raw.trim();
    let detail: string = trimmed;
    if (trimmed.startsWith('{')) {
      try {
        const obj: Record<string, Object> = JSON.parse(trimmed) as Record<string, Object>;
        const errObj: Object | undefined = obj.error;
        if (errObj !== undefined && errObj !== null) {
          const e: Record<string, Object> = errObj as Record<string, Object>;
          const m: Object | undefined = e.message;
          if (m !== undefined && m !== null) {
            detail = String(m);
          }
        } else if (obj.message !== undefined) {
          detail = String(obj.message);
        }
      } catch (e) {
        detail = trimmed;
      }
    }
    if (detail.length > 600) {
      detail = detail.substring(0, 600) + '…';
    }
    const hint: string = ErrorParser.hintFor(statusCode);
    if (hint.length > 0) {
      return detail.length > 0 ? (hint + '\n' + detail) : hint;
    }
    return detail.length > 0 ? detail : '请求失败';
  }

  static hintFor(statusCode: number): string {
    if (statusCode === 400) {
      return '请求格式错误（400）';
    }
    if (statusCode === 401) {
      return 'API Key 无效或未配置（401）';
    }
    if (statusCode === 402) {
      return '账户余额不足（402），请前往服务商充值';
    }
    if (statusCode === 403) {
      return '无权访问该资源（403）';
    }
    if (statusCode === 404) {
      return '接口或模型不存在（404），请检查 Base URL 与模型名';
    }
    if (statusCode === 422) {
      return '请求参数非法（422）';
    }
    if (statusCode === 429) {
      return '请求过于频繁或超出并发限制（429），请稍后重试';
    }
    if (statusCode === 500) {
      return '服务端错误（500），请稍后重试';
    }
    if (statusCode === 503) {
      return '服务器过载（503），请稍后重试';
    }
    if (statusCode === -1) {
      return '网络异常';
    }
    return '';
  }
}

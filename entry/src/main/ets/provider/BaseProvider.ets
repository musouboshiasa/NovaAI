import { Protocol, Role } from '../common/Constants';
import { ChatMessage, ModelInfo, ProviderConfig, RequestContext, Usage, emptyUsage, ToolCall, BalanceInfo } from '../model/Types';
import {
  WireChatRequest, WireChunk, WireContentPart, WireMessage, WireToolCall, WireTool, WireFunctionDef, WireObjectSchema, WireUsage
} from '../model/Wire';
import { SseEvent } from '../net/SseParser';
import { HeaderMap } from '../net/HttpClient';
import { Utils } from '../common/Utils';
import { Tools, ToolDef } from '../service/Tools';

/** 将要发出的 HTTP 请求 */
export class ProviderRequest {
  url: string = '';
  headers: HeaderMap = {};
  body: string = '';
}

/** 流式输出汇聚器：把各协议的事件统一成 content / reasoning / toolcalls / usage */
export class StreamSink {
  content: string = '';
  reasoning: string = '';
  usage: Usage = emptyUsage();
  finishReason: string = '';
  completed: boolean = false;
  errored: boolean = false;
  errorMessage: string = '';
  /** 工具调用按 index 累积 */
  toolCalls: ToolCall[] = [];
  private startedAny: boolean = false;

  firstDelta: boolean = false;

  onReasoning: (t: string) => void = () => {};
  onContent: (t: string) => void = () => {};
  onToolCalls: (calls: ToolCall[]) => void = () => {};
  onUsage: (u: Usage) => void = () => {};

  pushReasoning(t: string): void {
    if (t === undefined || t === null || t.length === 0) {
      return;
    }
    this.reasoning += t;
    this.firstDelta = true;
    this.onReasoning(t);
  }

  pushContent(t: string): void {
    if (t === undefined || t === null || t.length === 0) {
      return;
    }
    this.content += t;
    this.firstDelta = true;
    this.onContent(t);
  }

  /** 合并工具调用增量（OpenAI 风格按 index 分片返回） */
  mergeToolCallDelta(index: number, id: string, name: string, argsDelta: string): void {
    while (this.toolCalls.length <= index) {
      const t: ToolCall = new ToolCall();
      this.toolCalls.push(t);
    }
    const tc: ToolCall = this.toolCalls[index];
    if (id !== undefined && id !== null && id.length > 0) {
      tc.id = id;
    }
    if (name !== undefined && name !== null && name.length > 0) {
      tc.name = name;
    }
    if (argsDelta !== undefined && argsDelta !== null && argsDelta.length > 0) {
      tc.arguments += argsDelta;
    }
    this.firstDelta = true;
    this.onToolCalls(this.toolCalls);
  }

  applyUsage(w: WireUsage | null | undefined): void {
    const u: Usage = BaseProvider.normalizeUsage(w);
    this.usage = u;
    this.onUsage(u);
  }

  markError(msg: string): void {
    this.errored = true;
    this.errorMessage = msg;
  }
}

/** 抽象的协议实现 */
export abstract class BaseProvider {
  abstract protocol(): string;

  /** 构建对话请求 */
  abstract buildChat(ctx: RequestContext): ProviderRequest;

  /** 消费一个 SSE 事件 */
  abstract consume(evt: SseEvent, sink: StreamSink): void;

  /** 是否为「结束」事件（非 data:[DONE] 语义，例如 Responses/Anthropic 的终态事件） */
  isTerminalEvent(evt: SseEvent): boolean {
    return evt.isDone();
  }

  /** 非流式响应解析（默认按 Chat Completions 处理，其它协议可覆写） */
  consumeFull(text: string, sink: StreamSink): void {
    const chunk: WireChunk | null = Utils.tryParse<WireChunk | null>(text, null);
    if (chunk === null) {
      sink.markError('无法解析服务端响应');
      sink.completed = true;
      return;
    }
    if (chunk.error !== undefined && chunk.error !== null) {
      sink.markError(chunk.error.message !== undefined && chunk.error.message !== null
        ? chunk.error.message : 'API 返回错误');
      sink.completed = true;
      return;
    }
    if (chunk.usage !== undefined && chunk.usage !== null) {
      sink.applyUsage(chunk.usage);
    }
    const choices = chunk.choices;
    if (choices !== undefined && choices !== null && choices.length > 0) {
      const ch = choices[0];
      const msg: WireMessage | undefined = ch.message;
      if (msg !== undefined && msg !== null) {
        if (msg.reasoning_content !== undefined && msg.reasoning_content !== null) {
          sink.pushReasoning(msg.reasoning_content);
        }
        const c = msg.content;
        if (typeof c === 'string') {
          sink.pushContent(c as string);
        }
        const tcs = msg.tool_calls;
        if (tcs !== undefined && tcs !== null) {
          for (let i = 0; i < tcs.length; i++) {
            const t: WireToolCall = tcs[i];
            const idx: number = (t.index !== undefined && t.index !== null) ? t.index : i;
            const id: string = (t.id !== undefined && t.id !== null) ? t.id : '';
            let name: string = '';
            let a: string = '';
            if (t.function !== undefined && t.function !== null) {
              name = t.function.name !== undefined && t.function.name !== null ? t.function.name : '';
              a = t.function.arguments !== undefined && t.function.arguments !== null ? t.function.arguments : '';
            }
            sink.mergeToolCallDelta(idx, id, name, a);
          }
        }
      }
      if (ch.finish_reason !== undefined && ch.finish_reason !== null) {
        sink.finishReason = ch.finish_reason;
      }
    }
    sink.completed = true;
  }

  /** 是否支持 FIM 补全 */
  supportsFim(): boolean {
    return false;
  }

  /** 构建 FIM 请求 */
  buildFim(ctx: RequestContext): ProviderRequest {
    const r: ProviderRequest = new ProviderRequest();
    return r;
  }

  /** 消费 FIM 事件 */
  consumeFim(evt: SseEvent, sink: StreamSink): void {
  }

  /** 是否支持余额查询 */
  supportsBalance(): boolean {
    return false;
  }

  async fetchBalance(cfg: ProviderConfig): Promise<BalanceInfo> {
    const b: BalanceInfo = new BalanceInfo();
    b.error = '该服务商不支持余额查询';
    return b;
  }

  /** 拉取模型列表 */
  async fetchModels(cfg: ProviderConfig): Promise<ModelInfo[]> {
    const list: ModelInfo[] = [];
    return list;
  }

  /* ===================== 公共工具方法 ===================== */

  static normalizeUsage(w: WireUsage | null | undefined): Usage {
    const u: Usage = emptyUsage();
    if (w === null || w === undefined) {
      return u;
    }
    const prompt: number = BaseProvider.pickNum(w.prompt_tokens, w.input_tokens);
    const completion: number = BaseProvider.pickNum(w.completion_tokens, w.output_tokens);
    u.promptTokens = prompt;
    u.completionTokens = completion;
    const total: number | undefined = w.total_tokens;
    u.totalTokens = (total === undefined || total === null) ? (prompt + completion) : total;

    let cached: number | undefined = w.prompt_cache_hit_tokens;
    if (cached === undefined || cached === null) {
      const pd = w.prompt_tokens_details !== undefined ? w.prompt_tokens_details : w.input_tokens_details;
      if (pd !== undefined && pd !== null) {
        cached = pd.cached_tokens;
      }
    }
    u.cacheHitTokens = (cached === undefined || cached === null) ? 0 : cached;
    const miss: number | undefined = w.prompt_cache_miss_tokens;
    u.cacheMissTokens = (miss === undefined || miss === null) ? Math.max(0, prompt - u.cacheHitTokens) : miss;

    const cd = w.completion_tokens_details !== undefined ? w.completion_tokens_details : w.output_tokens_details;
    if (cd !== undefined && cd !== null && cd.reasoning_tokens !== undefined && cd.reasoning_tokens !== null) {
      u.reasoningTokens = cd.reasoning_tokens;
    }
    return u;
  }

  private static pickNum(a: number | undefined, b: number | undefined): number {
    if (a !== undefined && a !== null) {
      return a;
    }
    if (b !== undefined && b !== null) {
      return b;
    }
    return 0;
  }

  /** 解析 stop 字符串（按换行拆分，最多 16 个） */
  static parseStop(raw: string): string[] {
    const out: string[] = [];
    if (raw === undefined || raw === null || raw.trim().length === 0) {
      return out;
    }
    const parts: string[] = raw.split('\n');
    for (let i = 0; i < parts.length && out.length < 16; i++) {
      const s: string = parts[i].trim();
      if (s.length > 0) {
        out.push(s);
      }
    }
    return out;
  }

  /** 构造认证头 */
  static authHeaders(cfg: ProviderConfig): HeaderMap {
    const h: HeaderMap = {};
    h['Content-Type'] = 'application/json';
    h['Accept'] = 'text/event-stream';
    h['Authorization'] = 'Bearer ' + cfg.apiKey;
    if (cfg.extraHeaders !== undefined && cfg.extraHeaders !== null && cfg.extraHeaders.trim().length > 0) {
      try {
        const extra: Record<string, string> = JSON.parse(cfg.extraHeaders) as Record<string, string>;
        const ks: string[] = Object.keys(extra);
        for (let i = 0; i < ks.length; i++) {
          h[ks[i]] = String(extra[ks[i]]);
        }
      } catch (e) {
        // 忽略非法的自定义头
      }
    }
    return h;
  }

  /** 拼接 URL */
  static joinUrl(base: string, path: string): string {
    let b: string = base;
    while (b.length > 0 && b.charAt(b.length - 1) === '/') {
      b = b.substring(0, b.length - 1);
    }
    return b + path;
  }

  /** 把内部消息转换成 Chat Completions 的 wire 消息 */
  static toWireMessages(ctx: RequestContext, allowVision: boolean, echoReasoning: boolean): WireMessage[] {
    const out: WireMessage[] = [];
    if (ctx.systemPrompt !== undefined && ctx.systemPrompt !== null && ctx.systemPrompt.length > 0) {
      const sys: WireMessage = { role: 'system', content: ctx.systemPrompt };
      out.push(sys);
    }
    const msgs: ChatMessage[] = ctx.messages;
    for (let i = 0; i < msgs.length; i++) {
      const m: ChatMessage = msgs[i];
      if (m.role === Role.USER) {
        const hasImg: boolean = allowVision && m.attachments.length > 0;
        if (hasImg) {
          const parts: WireContentPart[] = [];
          if (m.content.length > 0) {
            const tp: WireContentPart = { type: 'text', text: m.content };
            parts.push(tp);
          }
          for (let k = 0; k < m.attachments.length; k++) {
            const ip: WireContentPart = { type: 'image_url', image_url: { url: m.attachments[k].dataUrl } };
            parts.push(ip);
          }
          const wm: WireMessage = { role: 'user', content: parts };
          out.push(wm);
        } else {
          const wm: WireMessage = { role: 'user', content: m.content };
          out.push(wm);
        }
      } else if (m.role === Role.ASSISTANT) {
        const wm: WireMessage = { role: 'assistant', content: m.content };
        if (echoReasoning && m.reasoning.length > 0) {
          wm.reasoning_content = m.reasoning;
        }
        if (m.toolCalls.length > 0) {
          const tcs: WireToolCall[] = [];
          for (let k = 0; k < m.toolCalls.length; k++) {
            const t: ToolCall = m.toolCalls[k];
            const wt: WireToolCall = { id: t.id, type: 'function', function: { name: t.name, arguments: t.arguments } };
            tcs.push(wt);
          }
          wm.tool_calls = tcs;
        }
        out.push(wm);
        // 工具结果作为独立的 tool 消息
        for (let k = 0; k < m.toolCalls.length; k++) {
          const t: ToolCall = m.toolCalls[k];
          if (t.result !== undefined && t.result !== null && t.result.length > 0) {
            const tm: WireMessage = { role: 'tool', tool_call_id: t.id, content: t.result };
            out.push(tm);
          }
        }
      }
    }
    // 前缀续写：最后一条 assistant 消息带 prefix
    if (ctx.prefixMode && out.length > 0) {
      const last: WireMessage = out[out.length - 1];
      if (last.role === 'assistant') {
        last.prefix = true;
      }
    }
    return out;
  }

  /** 依据配置构建 tools 数组 */
  static buildTools(enableTools: boolean): WireTool[] {
    const out: WireTool[] = [];
    if (!enableTools) {
      return out;
    }
    const defs: ToolDef[] = Tools.definitions();
    for (let i = 0; i < defs.length; i++) {
      const d: ToolDef = defs[i];
      const schema: WireObjectSchema | null = Utils.tryParse<WireObjectSchema | null>(d.parametersJson, null);
      const fn: WireFunctionDef = { name: d.name, description: d.description };
      if (schema !== null) {
        fn.parameters = schema as Object;
      }
      const t: WireTool = { type: 'function', function: fn };
      out.push(t);
    }
    return out;
  }

  /** 把 reasoning / thinking 参数写入请求（DeepSeek 风格） */
  static applyDeepSeekThinking(req: WireChatRequest, level: string): void {
    if (level === 'off') {
      req.thinking = { type: 'disabled' };
      return;
    }
    if (level === 'auto') {
      return; // 交给服务端默认（enabled + high）
    }
    req.thinking = { type: 'enabled' };
    req.reasoning_effort = level;
  }

  /** 解析一段 JSON 文本 */
  static parseJsonText<T>(text: string): T | null {
    try {
      return JSON.parse(text) as T;
    } catch (e) {
      return null;
    }
  }

  /** 解析单个 SSE data 行为 JSON */
  static parseJson<T>(evt: SseEvent): T | null {
    if (evt.data.length === 0 || evt.isDone()) {
      return null;
    }
    try {
      return JSON.parse(evt.data) as T;
    } catch (e) {
      return null;
    }
  }
}

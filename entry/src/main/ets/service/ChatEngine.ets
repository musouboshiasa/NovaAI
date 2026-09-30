import { Logger } from '../common/Logger';
import { RequestContext, ToolCall } from '../model/Types';
import { SseParser, SseEvent } from '../net/SseParser';
import { AbortHandle, HttpClient, StreamCallbacks, ErrorParser } from '../net/HttpClient';
import { BaseProvider, ProviderRequest, StreamSink } from '../provider/BaseProvider';
import { ProviderFactory } from '../provider/ProviderFactory';
import { Tools } from './Tools';

/** 完成回调 */
export interface ChatCompletionHandlers {
  onDone: (sink: StreamSink) => void;
  onFail: (message: string) => void;
}

/**
 * 对话引擎：统一驱动 流式 / 非流式 请求，并处理工具调用的自动回环
 */
export class ChatEngine {
  private static activeHandles: AbortHandle[] = [];

  /** 记录所有在途请求，便于全局取消 */
  private static track(h: AbortHandle): void {
    ChatEngine.activeHandles.push(h);
  }

  private static untrack(h: AbortHandle): void {
    const idx: number = ChatEngine.activeHandles.indexOf(h);
    if (idx >= 0) {
      ChatEngine.activeHandles.splice(idx, 1);
    }
  }

  static cancelAll(): void {
    for (let i = 0; i < ChatEngine.activeHandles.length; i++) {
      ChatEngine.activeHandles[i].cancel();
    }
    ChatEngine.activeHandles = [];
  }

  /**
   * 执行一次请求
   * @param useFim 是否使用 FIM 补全端点
   */
  static run(ctx: RequestContext, sink: StreamSink, handlers: ChatCompletionHandlers, useFim: boolean): AbortHandle {
    const provider: BaseProvider = ProviderFactory.create(useFim ? 'chat_completions' : ctx.provider.protocol);
    let request: ProviderRequest;
    if (useFim) {
      request = provider.buildFim(ctx);
    } else {
      request = provider.buildChat(ctx);
    }
    Logger.info('request -> ' + request.url + ' model=' + ctx.model
      + ' stream=' + ctx.params.stream + ' fim=' + useFim
      + ' thinking=' + ctx.params.thinking + ' tools=' + ctx.params.enableTools
      + ' msgCount=' + ctx.messages.length);

    if (!ctx.params.stream) {
      const handle: AbortHandle = new AbortHandle();
      ChatEngine.track(handle);
      HttpClient.postJson(request.url, request.headers, request.body).then((text: string) => {
        ChatEngine.untrack(handle);
        try {
          if (useFim) {
            provider.consumeFim(new SseEvent('', text), sink);
          } else {
            provider.consumeFull(text, sink);
          }
        } catch (e) {
          const err = e as Error;
          sink.markError('解析响应失败: ' + err.message);
        }
        ChatEngine.postProcess(ctx, sink, handlers, useFim);
      }).catch((e: Error) => {
        ChatEngine.untrack(handle);
        handlers.onFail(ErrorParser.humanize(e.message, -1));
      });
      return handle;
    }

    const parser: SseParser = new SseParser((evt: SseEvent) => {
      if (evt.isDone()) {
        sink.completed = true;
        return;
      }
      try {
        if (useFim) {
          provider.consumeFim(evt, sink);
        } else {
          provider.consume(evt, sink);
        }
      } catch (e) {
        const err = e as Error;
        Logger.error('consume event failed: ' + err.message);
      }
    });

    let handleRef: AbortHandle | null = null;
    const cb: StreamCallbacks = {
      onText: (text: string) => {
        parser.feed(text);
      },
      onDone: () => {
        parser.flush();
        sink.completed = true;
        if (handleRef !== null) {
          ChatEngine.untrack(handleRef);
        }
        ChatEngine.postProcess(ctx, sink, handlers, useFim);
      },
      onFail: (message: string, statusCode: number) => {
        if (handleRef !== null) {
          ChatEngine.untrack(handleRef);
        }
        handlers.onFail(message);
      }
    };

    handleRef = HttpClient.postStream(request.url, request.headers, request.body, cb);
    ChatEngine.track(handleRef);
    return handleRef;
  }

  /** 处理工具调用回环与最终回调 */
  private static postProcess(ctx: RequestContext, sink: StreamSink, handlers: ChatCompletionHandlers, useFim: boolean): void {
    if (sink.errored) {
      handlers.onFail(sink.errorMessage);
      return;
    }
    handlers.onDone(sink);
  }

  /**
   * 本地执行一批工具调用
   */
  static executeTools(calls: ToolCall[]): ToolCall[] {
    const out: ToolCall[] = [];
    for (let i = 0; i < calls.length; i++) {
      const c: ToolCall = new ToolCall();
      c.id = calls[i].id;
      c.name = calls[i].name;
      c.arguments = calls[i].arguments;
      c.result = Tools.execute(c.name, c.arguments);
      c.status = 'done';
      out.push(c);
    }
    return out;
  }
}

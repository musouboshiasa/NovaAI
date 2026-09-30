import { Protocol } from '../common/Constants';
import { BalanceInfo, ModelInfo, ProviderConfig, RequestContext } from '../model/Types';
import {
  WireBalance, WireChatRequest, WireChunk, WireContentPart, WireFimChunk, WireFimRequest, WireMessage,
  WireModel, WireModelList, WireStreamOptions, WireTool, WireToolCall
} from '../model/Wire';
import { SseEvent } from '../net/SseParser';
import { HttpClient, ErrorParser } from '../net/HttpClient';
import { BaseProvider, ProviderRequest, StreamSink } from './BaseProvider';
import { Constants } from '../common/Constants';

/**
 * OpenAI 兼容的 /chat/completions 协议实现
 * 同时覆盖 DeepSeek（含 thinking / reasoning_content）与 OpenAI 系列
 */
export class ChatCompletionsProvider extends BaseProvider {
  protocol(): string {
    return Protocol.CHAT_COMPLETIONS;
  }

  buildChat(ctx: RequestContext): ProviderRequest {
    const cfg: ProviderConfig = ctx.provider;
    const isDeepSeek: boolean = cfg.flavor === 'deepseek';
    const isOpenAI: boolean = cfg.flavor === 'openai';
    const allowVision: boolean = ChatCompletionsProvider.modelSupportsVision(ctx.model, cfg);
    const toolsEnabled: boolean = ctx.params.enableTools;
    // 文档规定：带 tools 的请求必须完整回传历史 reasoning_content
    const echoReasoning: boolean = toolsEnabled;

    const messages: WireMessage[] = BaseProvider.toWireMessages(ctx, allowVision, echoReasoning);
    const req: WireChatRequest = { model: ctx.model, messages: messages };

    if (ctx.params.stream) {
      req.stream = true;
      const so: WireStreamOptions = { include_usage: true };
      req.stream_options = so;
    }

    if (ctx.params.maxTokens > 0) {
      if (isOpenAI) {
        req.max_completion_tokens = ctx.params.maxTokens;
      } else {
        req.max_tokens = ctx.params.maxTokens;
      }
    }

    // 思考模式
    const level: string = ctx.params.thinking;
    const thinkingOn: boolean = level !== 'off' && level !== 'none';
    if (isDeepSeek) {
      BaseProvider.applyDeepSeekThinking(req, level);
    } else if (isOpenAI) {
      if (level === 'off' || level === 'none') {
        req.reasoning_effort = 'minimal';
      } else if (level !== 'auto') {
        req.reasoning_effort = ChatCompletionsProvider.mapEffortOpenAI(level);
      }
    } else {
      if (level !== 'auto' && level !== 'off') {
        req.reasoning_effort = level;
      }
    }

    // 采样参数：DeepSeek 思考模式下 temperature 无效，仍发送以兼容其它端点
    const sendTemperature: boolean = !(isOpenAI && thinkingOn && ChatCompletionsProvider.isOpenAIReasoning(ctx.model));
    if (ctx.params.temperature !== 1.0 && sendTemperature) {
      req.temperature = ctx.params.temperature;
    }
    if (ctx.params.topP !== 1.0) {
      req.top_p = ctx.params.topP;
    }
    const stop: string[] = BaseProvider.parseStop(ctx.params.stop);
    if (stop.length > 0) {
      req.stop = stop;
    }
    if (ctx.params.jsonMode) {
      req.response_format = { type: 'json_object' };
    }
    if (ctx.params.logprobs) {
      req.logprobs = true;
      if (ctx.params.topLogprobs > 0) {
        req.top_logprobs = Math.min(20, ctx.params.topLogprobs);
      }
    }
    if (isDeepSeek && ctx.params.userId.length > 0) {
      req.user_id = ctx.params.userId;
    } else if (isOpenAI && ctx.params.userId.length > 0) {
      req.user = ctx.params.userId;
    }
    if (ctx.params.frequencyPenalty !== 0 && !isDeepSeek) {
      req.frequency_penalty = ctx.params.frequencyPenalty;
    }
    if (ctx.params.presencePenalty !== 0 && !isDeepSeek) {
      req.presence_penalty = ctx.params.presencePenalty;
    }
    if (toolsEnabled) {
      const tools: WireTool[] = BaseProvider.buildTools(true);
      if (tools.length > 0) {
        req.tools = tools;
        req.tool_choice = 'auto';
      }
    }

    const p: ProviderRequest = new ProviderRequest();
    p.url = BaseProvider.joinUrl(cfg.baseUrl, '/chat/completions');
    if (ctx.prefixMode && cfg.betaBaseUrl.length > 0) {
      p.url = BaseProvider.joinUrl(cfg.betaBaseUrl, '/chat/completions');
    }
    p.headers = BaseProvider.authHeaders(cfg);
    p.body = JSON.stringify(req);
    return p;
  }

  supportsFim(): boolean {
    return true;
  }

  buildFim(ctx: RequestContext): ProviderRequest {
    const cfg: ProviderConfig = ctx.provider;
    const base: string = cfg.betaBaseUrl.length > 0 ? cfg.betaBaseUrl : cfg.baseUrl;
    const req: WireFimRequest = { model: ctx.model, prompt: ctx.suffix };
    // 约定：FIM 模式下 ctx.suffix 承载 prompt，ctx.systemPrompt 承载 suffix
    req.prompt = ctx.suffix;
    if (ctx.systemPrompt.length > 0) {
      req.suffix = ctx.systemPrompt;
    }
    if (ctx.params.maxTokens > 0) {
      req.max_tokens = Math.min(4096, ctx.params.maxTokens);
    }
    if (ctx.params.temperature !== 1.0) {
      req.temperature = ctx.params.temperature;
    }
    if (ctx.params.stream) {
      req.stream = true;
      const so: WireStreamOptions = { include_usage: true };
      req.stream_options = so;
    }
    req.thinking = { type: 'disabled' };
    const p: ProviderRequest = new ProviderRequest();
    p.url = BaseProvider.joinUrl(base, '/completions');
    p.headers = BaseProvider.authHeaders(cfg);
    p.body = JSON.stringify(req);
    return p;
  }

  consumeFim(evt: SseEvent, sink: StreamSink): void {
    const chunk: WireFimChunk | null = BaseProvider.parseJson<WireFimChunk>(evt);
    if (chunk === null) {
      return;
    }
    if (chunk.usage !== undefined && chunk.usage !== null) {
      sink.applyUsage(chunk.usage);
    }
    const choices = chunk.choices;
    if (choices === undefined || choices === null) {
      return;
    }
    for (let i = 0; i < choices.length; i++) {
      const c = choices[i];
      if (c.text !== undefined && c.text !== null && c.text.length > 0) {
        sink.pushContent(c.text);
      }
      if (c.finish_reason !== undefined && c.finish_reason !== null) {
        sink.finishReason = c.finish_reason;
      }
    }
  }

  consume(evt: SseEvent, sink: StreamSink): void {
    if (evt.isDone()) {
      sink.completed = true;
      return;
    }
    const chunk: WireChunk | null = BaseProvider.parseJson<WireChunk>(evt);
    if (chunk === null) {
      return;
    }
    if (chunk.error !== undefined && chunk.error !== null) {
      const msg: string = chunk.error.message !== undefined && chunk.error.message !== null
        ? chunk.error.message : 'API 返回错误';
      sink.markError(msg);
      return;
    }
    const usage = chunk.usage;
    if (usage !== undefined && usage !== null) {
      sink.applyUsage(usage);
    }
    const choices = chunk.choices;
    if (choices === undefined || choices === null || choices.length === 0) {
      return;
    }
    const ch = choices[0];
    if (ch.finish_reason !== undefined && ch.finish_reason !== null && ch.finish_reason.length > 0) {
      sink.finishReason = ch.finish_reason;
    }
    const delta = ch.delta;
    if (delta !== undefined && delta !== null) {
      if (delta.reasoning_content !== undefined && delta.reasoning_content !== null) {
        sink.pushReasoning(delta.reasoning_content);
      }
      if (delta.reasoning !== undefined && delta.reasoning !== null) {
        sink.pushReasoning(delta.reasoning);
      }
      if (delta.content !== undefined && delta.content !== null) {
        sink.pushContent(delta.content);
      }
      const tcs = delta.tool_calls;
      if (tcs !== undefined && tcs !== null) {
        for (let i = 0; i < tcs.length; i++) {
          const tc: WireToolCall = tcs[i];
          const idx: number = (tc.index !== undefined && tc.index !== null) ? tc.index : i;
          const id: string = (tc.id !== undefined && tc.id !== null) ? tc.id : '';
          let name: string = '';
          let args: string = '';
          if (tc.function !== undefined && tc.function !== null) {
            name = tc.function.name !== undefined && tc.function.name !== null ? tc.function.name : '';
            args = tc.function.arguments !== undefined && tc.function.arguments !== null ? tc.function.arguments : '';
          }
          sink.mergeToolCallDelta(idx, id, name, args);
        }
      }
    }
  }

  supportsBalance(): boolean {
    return true;
  }

  async fetchBalance(cfg: ProviderConfig): Promise<BalanceInfo> {
    const out: BalanceInfo = new BalanceInfo();
    try {
      const h = BaseProvider.authHeaders(cfg);
      h['Accept'] = 'application/json';
      const text: string = await HttpClient.getJson(BaseProvider.joinUrl(cfg.baseUrl, '/user/balance'), h);
      const w: WireBalance = JSON.parse(text) as WireBalance;
      out.isAvailable = w.is_available === true;
      const infos = w.balance_infos;
      if (infos !== undefined && infos !== null && infos.length > 0) {
        const e = infos[0];
        out.currency = e.currency !== undefined && e.currency !== null ? e.currency : 'CNY';
        out.totalBalance = e.total_balance !== undefined && e.total_balance !== null ? e.total_balance : '0';
        out.grantedBalance = e.granted_balance !== undefined && e.granted_balance !== null ? e.granted_balance : '0';
        out.toppedUpBalance = e.topped_up_balance !== undefined && e.topped_up_balance !== null ? e.topped_up_balance : '0';
      }
      out.fetchedAt = Date.now();
    } catch (e) {
      const err = e as Error;
      out.error = ErrorParser.humanize(err.message, -1);
    }
    return out;
  }

  async fetchModels(cfg: ProviderConfig): Promise<ModelInfo[]> {
    const out: ModelInfo[] = [];
    try {
      const h = BaseProvider.authHeaders(cfg);
      h['Accept'] = 'application/json';
      const text: string = await HttpClient.getJson(BaseProvider.joinUrl(cfg.baseUrl, '/models'), h);
      const list: WireModelList = JSON.parse(text) as WireModelList;
      const data = list.data;
      if (data === undefined || data === null) {
        return out;
      }
      for (let i = 0; i < data.length; i++) {
        const m: WireModel = data[i];
        if (m.id === undefined || m.id === null) {
          continue;
        }
        const info: ModelInfo = new ModelInfo();
        info.id = m.id;
        info.label = (m.name !== undefined && m.name !== null && m.name.length > 0) ? m.name : m.id;
        info.providerId = cfg.id;
        info.contextWindow = (m.context_window !== undefined && m.context_window !== null)
          ? m.context_window : Constants.FALLBACK_CONTEXT_WINDOW;
        info.maxOutputTokens = (m.max_output_tokens !== undefined && m.max_output_tokens !== null)
          ? m.max_output_tokens : Constants.FALLBACK_MAX_OUTPUT;
        const mods = m.input_modalities;
        info.supportsVision = mods !== undefined && mods !== null && mods.indexOf('image') >= 0;
        const eff = m.effort;
        if (eff !== undefined && eff !== null) {
          info.supportsThinking = true;
          if (eff.supported_levels !== undefined && eff.supported_levels !== null) {
            info.effortLevels = eff.supported_levels;
          }
          if (eff.default_level !== undefined && eff.default_level !== null) {
            info.defaultEffort = eff.default_level;
          }
        }
        out.push(info);
      }
    } catch (e) {
      const err = e as Error;
      throw new Error(ErrorParser.humanize(err.message, -1));
    }
    return out;
  }

  static mapEffortOpenAI(level: string): string {
    if (level === 'low') {
      return 'low';
    }
    if (level === 'max') {
      return 'high';
    }
    if (level === 'high') {
      return 'high';
    }
    return 'medium';
  }

  static isOpenAIReasoning(model: string): boolean {
    const m: string = model.toLowerCase();
    return m.startsWith('o1') || m.startsWith('o3') || m.startsWith('o4') || m.startsWith('gpt-5');
  }

  static modelSupportsVision(model: string, cfg: ProviderConfig): boolean {
    const m: string = model.toLowerCase();
    if (cfg.flavor === 'deepseek') {
      return m === 'deepseek-flash' || m.indexOf('vision') >= 0;
    }
    return m.indexOf('gpt-4o') >= 0 || m.indexOf('gpt-4.1') >= 0 || m.indexOf('gpt-5') >= 0
      || m.indexOf('o3') >= 0 || m.indexOf('o4') >= 0 || m.indexOf('vision') >= 0
      || m.indexOf('vl') >= 0 || m.indexOf('gemini') >= 0 || m.indexOf('claude') >= 0;
  }
}

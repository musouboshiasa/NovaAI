import { Protocol } from '../common/Constants';
import { ModelInfo, ProviderConfig, RequestContext } from '../model/Types';
import {
  WireAnthropicContent, WireAnthropicEvent, WireAnthropicMessage, WireAnthropicRequest, WireAnthropicSource,
  WireContentPart, WireModel, WireModelList
} from '../model/Wire';
import { SseEvent } from '../net/SseParser';
import { BaseProvider, ProviderRequest, StreamSink } from './BaseProvider';
import { HeaderMap } from '../net/HttpClient';
import { Utils } from '../common/Utils';
import { Constants } from '../common/Constants';

/** Anthropic 非流式完整响应 */
interface WireAnthropicFullResponse {
  id?: string;
  model?: string;
  stop_reason?: string;
  content?: WireAnthropicContent[];
  usage?: WireAnthropicUsageLike;
}

interface WireAnthropicUsageLike {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}

/**
 * Anthropic Messages 协议实现
 * 用于 DeepSeek 的 Anthropic 兼容端点（https://api.deepseek.com/anthropic）
 * 以及 Anthropic 官方 / 任何兼容网关
 */
export class AnthropicProvider extends BaseProvider {
  protocol(): string {
    return Protocol.ANTHROPIC;
  }

  buildChat(ctx: RequestContext): ProviderRequest {
    const cfg: ProviderConfig = ctx.provider;
    const msgs: WireAnthropicMessage[] = [];
    for (let i = 0; i < ctx.messages.length; i++) {
      const m = ctx.messages[i];
      const role: string = m.role === 'assistant' ? 'assistant' : 'user';
      if (m.attachments !== undefined && m.attachments.length > 0 && role === 'user') {
        const blocks: WireAnthropicContent[] = [];
        if (m.content.length > 0) {
          const t: WireAnthropicContent = { type: 'text', text: m.content };
          blocks.push(t);
        }
        for (let k = 0; k < m.attachments.length; k++) {
          const a = m.attachments[k];
          const comma: number = a.dataUrl.indexOf(',');
          const meta: string = comma > 0 ? a.dataUrl.substring(5, comma) : 'image/png;base64';
          const semi: number = meta.indexOf(';');
          const mediaType: string = semi > 0 ? meta.substring(0, semi) : 'image/png';
          const data: string = comma > 0 ? a.dataUrl.substring(comma + 1) : '';
          const src: WireAnthropicSource = { type: 'base64', media_type: mediaType, data: data };
          const img: WireAnthropicContent = { type: 'image', source: src };
          blocks.push(img);
        }
        const wm: WireAnthropicMessage = { role: role, content: blocks };
        msgs.push(wm);
      } else {
        const wm: WireAnthropicMessage = { role: role, content: m.content };
        msgs.push(wm);
      }
    }

    const maxTokens: number = ctx.params.maxTokens > 0 ? ctx.params.maxTokens : 4096;
    const req: WireAnthropicRequest = { model: ctx.model, max_tokens: maxTokens, messages: msgs };
    if (ctx.systemPrompt.length > 0) {
      req.system = ctx.systemPrompt;
    }
    if (ctx.params.stream) {
      req.stream = true;
    }
    if (ctx.params.temperature !== 1.0) {
      req.temperature = ctx.params.temperature;
    }
    if (ctx.params.topP !== 1.0) {
      req.top_p = ctx.params.topP;
    }
    const stop: string[] = BaseProvider.parseStop(ctx.params.stop);
    if (stop.length > 0) {
      req.stop_sequences = stop;
    }
    const level: string = ctx.params.thinking;
    if (level === 'off' || level === 'none') {
      req.thinking = { type: 'disabled' };
    } else if (level !== 'auto') {
      req.thinking = { type: 'enabled' };
    }

    const p: ProviderRequest = new ProviderRequest();
    p.url = BaseProvider.joinUrl(cfg.baseUrl, '/v1/messages');
    // Anthropic 使用 x-api-key 而非 Authorization
    const h: HeaderMap = {};
    h['Content-Type'] = 'application/json';
    h['Accept'] = 'text/event-stream';
    h['x-api-key'] = cfg.apiKey;
    h['anthropic-version'] = '2023-06-01';
    if (cfg.extraHeaders !== undefined && cfg.extraHeaders !== null && cfg.extraHeaders.trim().length > 0) {
      const extra: HeaderMap | null = Utils.tryParse<HeaderMap | null>(cfg.extraHeaders, null);
      if (extra !== null) {
        const ks: string[] = Object.keys(extra);
        for (let i = 0; i < ks.length; i++) {
          h[ks[i]] = String(extra[ks[i]]);
        }
      }
    }
    p.headers = h;
    p.body = JSON.stringify(req);
    return p;
  }

  isTerminalEvent(evt: SseEvent): boolean {
    if (evt.isDone()) {
      return true;
    }
    return evt.name === 'message_stop';
  }

  consume(evt: SseEvent, sink: StreamSink): void {
    if (evt.isDone()) {
      sink.completed = true;
      return;
    }
    const e: WireAnthropicEvent | null = BaseProvider.parseJson<WireAnthropicEvent>(evt);
    if (e === null) {
      return;
    }
    const type: string = (evt.name !== undefined && evt.name.length > 0) ? evt.name
      : (e.type !== undefined && e.type !== null ? e.type : '');

    if (type === 'message_start') {
      const m = e.message;
      if (m !== undefined && m !== null && m.usage !== undefined && m.usage !== null) {
        sink.usage.promptTokens = m.usage.input_tokens !== undefined && m.usage.input_tokens !== null ? m.usage.input_tokens : 0;
        sink.usage.cacheHitTokens = m.usage.cache_read_input_tokens !== undefined && m.usage.cache_read_input_tokens !== null
          ? m.usage.cache_read_input_tokens : 0;
        sink.usage.cacheMissTokens = Math.max(0, sink.usage.promptTokens - sink.usage.cacheHitTokens);
        sink.usage.totalTokens = sink.usage.promptTokens;
        sink.onUsage(sink.usage);
      }
      return;
    }
    if (type === 'content_block_start') {
      const cb = e.content_block;
      if (cb !== undefined && cb !== null && cb.type === 'tool_use') {
        const idx: number = (e.index !== undefined && e.index !== null) ? e.index : 0;
        sink.mergeToolCallDelta(idx, cb.id !== undefined && cb.id !== null ? cb.id : '',
          cb.name !== undefined && cb.name !== null ? cb.name : '', '');
      }
      return;
    }
    if (type === 'content_block_delta') {
      const d = e.delta;
      if (d === undefined || d === null) {
        return;
      }
      if (d.type === 'text_delta' && d.text !== undefined && d.text !== null) {
        sink.pushContent(d.text);
      } else if (d.type === 'thinking_delta' && d.thinking !== undefined && d.thinking !== null) {
        sink.pushReasoning(d.thinking);
      } else if (d.type === 'input_json_delta' && d.partial_json !== undefined && d.partial_json !== null) {
        const idx: number = (e.index !== undefined && e.index !== null) ? e.index : 0;
        sink.mergeToolCallDelta(idx, '', '', d.partial_json);
      }
      return;
    }
    if (type === 'message_delta') {
      const d = e.delta;
      if (d !== undefined && d !== null && d.stop_reason !== undefined && d.stop_reason !== null) {
        sink.finishReason = d.stop_reason;
      }
      if (e.usage !== undefined && e.usage !== null) {
        const o: number = e.usage.output_tokens !== undefined && e.usage.output_tokens !== null ? e.usage.output_tokens : 0;
        sink.usage.completionTokens = o;
        sink.usage.totalTokens = sink.usage.promptTokens + o;
        sink.onUsage(sink.usage);
      }
      return;
    }
    if (type === 'message_stop') {
      sink.completed = true;
      return;
    }
    if (type === 'error') {
      let msg: string = '请求出错';
      if (e.error !== undefined && e.error !== null && e.error.message !== undefined && e.error.message !== null) {
        msg = e.error.message;
      }
      sink.markError(msg);
      sink.completed = true;
    }
  }

  consumeFull(text: string, sink: StreamSink): void {
    const r = BaseProvider.parseJsonText<WireAnthropicFullResponse>(text);
    if (r === null) {
      sink.markError('无法解析响应');
      sink.completed = true;
      return;
    }
    const blocks = r.content;
    if (blocks !== undefined && blocks !== null) {
      for (let i = 0; i < blocks.length; i++) {
        const b: WireAnthropicContent = blocks[i];
        if (b.type === 'text' && b.text !== undefined && b.text !== null) {
          sink.pushContent(b.text);
        } else if (b.type === 'thinking' && b.text !== undefined && b.text !== null) {
          sink.pushReasoning(b.text);
        }
      }
    }
    if (r.usage !== undefined && r.usage !== null) {
      const prompt: number = r.usage.input_tokens !== undefined && r.usage.input_tokens !== null ? r.usage.input_tokens : 0;
      const out: number = r.usage.output_tokens !== undefined && r.usage.output_tokens !== null ? r.usage.output_tokens : 0;
      sink.usage.promptTokens = prompt;
      sink.usage.completionTokens = out;
      sink.usage.totalTokens = prompt + out;
      sink.usage.cacheHitTokens = r.usage.cache_read_input_tokens !== undefined && r.usage.cache_read_input_tokens !== null
        ? r.usage.cache_read_input_tokens : 0;
      sink.usage.cacheMissTokens = Math.max(0, prompt - sink.usage.cacheHitTokens);
      sink.onUsage(sink.usage);
    }
    sink.finishReason = r.stop_reason !== undefined && r.stop_reason !== null ? r.stop_reason : 'stop';
    sink.completed = true;
  }

  async fetchModels(cfg: ProviderConfig): Promise<ModelInfo[]> {
    const out: ModelInfo[] = [];
    const p: RequestContext = new RequestContext();
    p.provider = cfg;
    const base: string = cfg.baseUrl;
    // Anthropic 兼容端点通常不提供 /models，此处回退到手动配置
    if (base.indexOf('api.anthropic.com') < 0) {
      throw new Error('该 Anthropic 兼容端点不提供模型列表接口');
    }
    return out;
  }
}

import { Protocol } from '../common/Constants';
import { ModelInfo, ProviderConfig, RequestContext, Usage } from '../model/Types';
import { WireModel, WireModelList, WireRespContent, WireRespEvent, WireRespInput, WireRespItem, WireRespRequest, WireRespResponse } from '../model/Wire';
import { SseEvent } from '../net/SseParser';
import { HttpClient, ErrorParser } from '../net/HttpClient';
import { BaseProvider, ProviderRequest, StreamSink } from './BaseProvider';
import { Constants } from '../common/Constants';

/**
 * OpenAI Responses API 实现
 * DeepSeek 与 OpenAI 均原生支持；流式为语义化 SSE（无 data:[DONE]）
 */
export class ResponsesProvider extends BaseProvider {
  protocol(): string {
    return Protocol.RESPONSES;
  }

  buildChat(ctx: RequestContext): ProviderRequest {
    const cfg: ProviderConfig = ctx.provider;
    const inputs: WireRespInput[] = [];
    for (let i = 0; i < ctx.messages.length; i++) {
      const m = ctx.messages[i];
      const role: string = m.role === 'assistant' ? 'assistant' : (m.role === 'system' ? 'system' : 'user');
      const inp: WireRespInput = { role: role, content: m.content };
      inputs.push(inp);
    }
    const req: WireRespRequest = { model: ctx.model, input: inputs };
    if (ctx.systemPrompt.length > 0) {
      req.instructions = ctx.systemPrompt;
    }
    if (ctx.params.stream) {
      req.stream = true;
    }
    if (ctx.params.maxTokens > 0) {
      req.max_output_tokens = ctx.params.maxTokens;
    }
    const level: string = ctx.params.thinking;
    if (level === 'off' || level === 'none') {
      req.reasoning = { effort: 'none' };
    } else if (level === 'auto') {
      // 使用服务端默认
    } else {
      req.reasoning = { effort: level === 'max' ? 'max' : level };
    }
    if (ctx.params.temperature !== 1.0) {
      req.temperature = ctx.params.temperature;
    }
    if (ctx.params.topP !== 1.0) {
      req.top_p = ctx.params.topP;
    }
    if (cfg.flavor === 'openai') {
      req.store = false;
    }

    const p: ProviderRequest = new ProviderRequest();
    p.url = BaseProvider.joinUrl(cfg.baseUrl, '/responses');
    p.headers = BaseProvider.authHeaders(cfg);
    p.body = JSON.stringify(req);
    return p;
  }

  isTerminalEvent(evt: SseEvent): boolean {
    if (evt.isDone()) {
      return true;
    }
    return evt.name === 'response.completed' || evt.name === 'response.failed'
      || evt.name === 'response.incomplete' || evt.name === 'error';
  }

  consume(evt: SseEvent, sink: StreamSink): void {
    if (evt.isDone()) {
      sink.completed = true;
      return;
    }
    const e: WireRespEvent | null = BaseProvider.parseJson<WireRespEvent>(evt);
    if (e === null) {
      return;
    }
    const type: string = (evt.name !== undefined && evt.name.length > 0) ? evt.name
      : (e.type !== undefined && e.type !== null ? e.type : '');

    if (type === 'response.output_text.delta') {
      if (e.delta !== undefined && e.delta !== null) {
        sink.pushContent(e.delta);
      }
      return;
    }
    if (type === 'response.reasoning_text.delta' || type === 'response.reasoning_summary_text.delta') {
      if (e.delta !== undefined && e.delta !== null) {
        sink.pushReasoning(e.delta);
      }
      return;
    }
    if (type === 'response.function_call_arguments.delta' || type === 'response.custom_tool_call_input.delta') {
      const idx: number = (e.output_index !== undefined && e.output_index !== null) ? e.output_index : 0;
      const delta: string = (e.delta !== undefined && e.delta !== null) ? e.delta : '';
      sink.mergeToolCallDelta(idx, '', '', delta);
      return;
    }
    if (type === 'response.output_item.added' || type === 'response.output_item.done') {
      const item = e.item;
      if (item !== undefined && item !== null && item.type === 'function_call') {
        const idx: number = (e.output_index !== undefined && e.output_index !== null) ? e.output_index : 0;
        const id: string = (item.call_id !== undefined && item.call_id !== null) ? item.call_id : '';
        const name: string = (item.name !== undefined && item.name !== null) ? item.name : '';
        sink.mergeToolCallDelta(idx, id, name, '');
      }
      return;
    }
    if (type === 'response.completed' || type === 'response.incomplete') {
      const resp = e.response;
      if (resp !== undefined && resp !== null) {
        if (resp.usage !== undefined && resp.usage !== null) {
          sink.applyUsage(resp.usage);
        }
        if (resp.status === 'incomplete') {
          sink.finishReason = 'length';
        } else {
          sink.finishReason = 'stop';
        }
        // 兜底：若没有收到任何增量，从完整输出中提取文本
        if (sink.content.length === 0 && resp.output !== undefined && resp.output !== null) {
          ResponsesProvider.extractText(resp, sink);
        }
      }
      sink.completed = true;
      return;
    }
    if (type === 'response.failed') {
      const resp = e.response;
      let msg: string = '响应生成失败';
      if (resp !== undefined && resp !== null && resp.error !== undefined && resp.error !== null
        && resp.error.message !== undefined && resp.error.message !== null) {
        msg = resp.error.message;
      }
      sink.markError(msg);
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
      return;
    }
  }

  consumeFull(text: string, sink: StreamSink): void {
    const r = BaseProvider.parseJsonText<WireRespResponse>(text);
    if (r !== null) {
      if (r.usage !== undefined && r.usage !== null) {
        sink.applyUsage(r.usage);
      }
      ResponsesProvider.extractText(r, sink);
      sink.finishReason = r.status === 'incomplete' ? 'length' : 'stop';
    } else {
      sink.markError('无法解析响应');
    }
    sink.completed = true;
  }

  private static extractText(resp: WireRespResponse, sink: StreamSink): void {
    const out = resp.output;
    if (out === undefined || out === null) {
      return;
    }
    for (let i = 0; i < out.length; i++) {
      const item: WireRespItem = out[i];
      if (item.type !== 'message') {
        continue;
      }
      const cs = item.content;
      if (cs === undefined || cs === null) {
        continue;
      }
      for (let k = 0; k < cs.length; k++) {
        const c: WireRespContent = cs[k];
        if (c.text !== undefined && c.text !== null) {
          sink.pushContent(c.text);
        }
      }
    }
  }

  async fetchModels(cfg: ProviderConfig): Promise<ModelInfo[]> {
    const out: ModelInfo[] = [];
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
      info.label = (m.name !== undefined && m.name !== null) ? m.name : m.id;
      info.providerId = cfg.id;
      info.contextWindow = (m.context_window !== undefined && m.context_window !== null)
        ? m.context_window : Constants.FALLBACK_CONTEXT_WINDOW;
      info.maxOutputTokens = (m.max_output_tokens !== undefined && m.max_output_tokens !== null)
        ? m.max_output_tokens : Constants.FALLBACK_MAX_OUTPUT;
      const mods = m.input_modalities;
      info.supportsVision = mods !== undefined && mods !== null && mods.indexOf('image') >= 0;
      out.push(info);
    }
    return out;
  }
}

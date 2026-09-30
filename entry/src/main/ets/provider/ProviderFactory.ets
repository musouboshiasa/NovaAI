import { Protocol } from '../common/Constants';
import { ProviderConfig } from '../model/Types';
import { BaseProvider } from './BaseProvider';
import { ChatCompletionsProvider } from './ChatCompletionsProvider';
import { ResponsesProvider } from './ResponsesProvider';
import { AnthropicProvider } from './AnthropicProvider';

/**
 * 协议注册表 + 内置服务商预设
 */
export class ProviderFactory {
  static create(protocol: string): BaseProvider {
    if (protocol === Protocol.RESPONSES) {
      return new ResponsesProvider();
    }
    if (protocol === Protocol.ANTHROPIC) {
      return new AnthropicProvider();
    }
    return new ChatCompletionsProvider();
  }

  static protocolLabel(protocol: string): string {
    if (protocol === Protocol.RESPONSES) {
      return 'Responses API';
    }
    if (protocol === Protocol.ANTHROPIC) {
      return 'Anthropic Messages';
    }
    if (protocol === Protocol.FIM) {
      return 'FIM 补全';
    }
    return 'Chat Completions';
  }

  /** 内置服务商预设 */
  static presets(): ProviderConfig[] {
    const out: ProviderConfig[] = [];
    out.push(ProviderFactory.deepseekChat());
    out.push(ProviderFactory.deepseekResponses());
    out.push(ProviderFactory.deepseekAnthropic());
    out.push(ProviderFactory.openaiChat());
    out.push(ProviderFactory.openaiResponses());
    return out;
  }

  static deepseekChat(): ProviderConfig {
    const c: ProviderConfig = new ProviderConfig();
    c.id = 'deepseek';
    c.name = 'DeepSeek';
    c.flavor = 'deepseek';
    c.protocol = Protocol.CHAT_COMPLETIONS;
    c.baseUrl = 'https://api.deepseek.com';
    c.betaBaseUrl = 'https://api.deepseek.com/beta';
    c.models = ['deepseek-flash', 'deepseek-v4-pro'];
    c.builtin = true;
    c.supportsBalance = true;
    c.supportsModelList = true;
    c.brandColor = '#4D6BFE';
    c.note = '官方 OpenAI 兼容接口，支持思考模式 / 上下文缓存 / 前缀续写 / FIM 补全';
    return c;
  }

  static deepseekResponses(): ProviderConfig {
    const c: ProviderConfig = new ProviderConfig();
    c.id = 'deepseek-responses';
    c.name = 'DeepSeek Responses';
    c.flavor = 'deepseek';
    c.protocol = Protocol.RESPONSES;
    c.baseUrl = 'https://api.deepseek.com';
    c.models = ['deepseek-flash', 'deepseek-v4-pro'];
    c.builtin = true;
    c.supportsBalance = true;
    c.brandColor = '#4D6BFE';
    c.note = 'DeepSeek 原生 Responses API（为 Codex 生态适配的无状态接口）';
    return c;
  }

  static deepseekAnthropic(): ProviderConfig {
    const c: ProviderConfig = new ProviderConfig();
    c.id = 'deepseek-anthropic';
    c.name = 'DeepSeek Anthropic';
    c.flavor = 'deepseek';
    c.protocol = Protocol.ANTHROPIC;
    c.baseUrl = 'https://api.deepseek.com/anthropic';
    c.models = ['deepseek-flash', 'deepseek-v4-pro'];
    c.builtin = true;
    c.brandColor = '#4D6BFE';
    c.note = 'Anthropic Messages 兼容端点，可直接接入 Claude Code 等工具链';
    return c;
  }

  static openaiChat(): ProviderConfig {
    const c: ProviderConfig = new ProviderConfig();
    c.id = 'openai';
    c.name = 'OpenAI';
    c.flavor = 'openai';
    c.protocol = Protocol.CHAT_COMPLETIONS;
    c.baseUrl = 'https://api.openai.com/v1';
    c.models = ['gpt-5', 'gpt-5-mini', 'gpt-4.1', 'gpt-4.1-mini', 'gpt-4o', 'gpt-4o-mini', 'o3', 'o4-mini'];
    c.builtin = true;
    c.supportsModelList = true;
    c.brandColor = '#10A37F';
    c.note = 'OpenAI 官方接口；也适用于任何 OpenAI 兼容网关（Azure / Ollama / vLLM / OpenRouter 等）';
    return c;
  }

  static openaiResponses(): ProviderConfig {
    const c: ProviderConfig = new ProviderConfig();
    c.id = 'openai-responses';
    c.name = 'OpenAI Responses';
    c.flavor = 'openai';
    c.protocol = Protocol.RESPONSES;
    c.baseUrl = 'https://api.openai.com/v1';
    c.models = ['gpt-5', 'gpt-5-mini', 'gpt-4.1', 'o3', 'o4-mini'];
    c.builtin = true;
    c.brandColor = '#10A37F';
    c.note = 'OpenAI 新一代 Responses API，支持推理摘要与内建工具';
    return c;
  }

  /** 新建一个自定义 OpenAI 兼容服务商 */
  static customCompatible(name: string, baseUrl: string, models: string[]): ProviderConfig {
    const c: ProviderConfig = new ProviderConfig();
    c.id = 'custom_' + Date.now().toString(36);
    c.name = name;
    c.flavor = 'generic';
    c.protocol = Protocol.CHAT_COMPLETIONS;
    c.baseUrl = baseUrl;
    c.models = models;
    c.brandColor = '#8B5CF6';
    c.note = '自定义 OpenAI 兼容端点';
    return c;
  }

  /** 新建一个自定义 Anthropic 兼容服务商 */
  static customAnthropic(name: string, baseUrl: string, models: string[]): ProviderConfig {
    const c: ProviderConfig = new ProviderConfig();
    c.id = 'custom_anthropic_' + Date.now().toString(36);
    c.name = name;
    c.flavor = 'anthropic';
    c.protocol = Protocol.ANTHROPIC;
    c.baseUrl = baseUrl;
    c.models = models;
    c.brandColor = '#D97757';
    c.note = '自定义 Anthropic 兼容端点';
    return c;
  }
}

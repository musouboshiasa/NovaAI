/**
 * 全局常量与默认配置
 */

export class Constants {
  static readonly APP_NAME_ZH: string = '星枢 AI';
  static readonly APP_NAME_EN: string = 'Nova AI';
  static readonly VERSION: string = '32-2-1';
  /** 开源仓库地址 */
  static readonly GITHUB_URL: string = 'https://github.com/musouboshiasa/NovaAI';
  /** 开源协议名称 */
  static readonly LICENSE_NAME: string = 'MIT License';
  static readonly LOG_TAG: string = 'NovaAI';

  /** 默认系统提示词 */
  static readonly DEFAULT_SYSTEM_PROMPT: string =
    '你是星枢 AI，一个运行在 HarmonyOS 上的智能助手。回答要准确、简洁、结构清晰，善用 Markdown 排版。';

  /** 网络超时 */
  static readonly CONNECT_TIMEOUT_MS: number = 30000;
  static readonly READ_TIMEOUT_MS: number = 300000;

  /** 流式刷新节流间隔（毫秒） */
  static readonly STREAM_FLUSH_MS: number = 60;

  /** 单会话最大消息数（防止内存膨胀） */
  static readonly MAX_MESSAGES_PER_SESSION: number = 400;

  /** 上下文窗口兜底值 */
  static readonly FALLBACK_CONTEXT_WINDOW: number = 65536;
  static readonly FALLBACK_MAX_OUTPUT: number = 8192;

  /** 宽屏断点（vp） */
  /** 联网搜索单次请求超时：搜索是交互式操作，超过这个时间就不值得等 */
  static readonly SEARCH_TIMEOUT_MS: number = 8000;

  static readonly BREAKPOINT_MEDIUM: number = 600;
  static readonly BREAKPOINT_LARGE: number = 840;
}

/** 协议类型 */
export enum Protocol {
  CHAT_COMPLETIONS = 'chat_completions',
  RESPONSES = 'responses',
  ANTHROPIC = 'anthropic',
  FIM = 'fim'
}

/** 消息状态 */
export enum MsgStatus {
  PENDING = 'pending',
  STREAMING = 'streaming',
  DONE = 'done',
  ERROR = 'error',
  STOPPED = 'stopped'
}

/** 消息角色 */
export enum Role {
  SYSTEM = 'system',
  USER = 'user',
  ASSISTANT = 'assistant',
  TOOL = 'tool'
}

/** 主题模式 */
export enum ThemeMode {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

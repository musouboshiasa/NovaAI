import { MsgStatus, Protocol, Role, ThemeMode } from '../common/Constants';

/** token 用量 */
export interface Usage {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  /** 缓存命中输入 token（DeepSeek 上下文硬盘缓存） */
  cacheHitTokens: number;
  /** 缓存未命中输入 token */
  cacheMissTokens: number;
  /** 思维链 token */
  reasoningTokens: number;
}

export function emptyUsage(): Usage {
  const u: Usage = {
    promptTokens: 0, completionTokens: 0, totalTokens: 0,
    cacheHitTokens: 0, cacheMissTokens: 0, reasoningTokens: 0
  };
  return u;
}

/** 工具调用 */
export class ToolCall {
  id: string = '';
  name: string = '';
  arguments: string = '';
  result: string = '';
  status: string = 'pending';
}

/** 附件（图片） */
export class Attachment {
  id: string = '';
  name: string = '';
  /** data:image/png;base64,xxx */
  dataUrl: string = '';
  mime: string = 'image/png';
  size: number = 0;
}

/** 一条聊天消息 */
@Observed
export class ChatMessage {
  id: string = '';
  role: string = Role.USER;
  content: string = '';
  reasoning: string = '';
  createdAt: number = 0;
  model: string = '';
  providerId: string = '';
  status: string = MsgStatus.DONE;
  error: string = '';
  usage: Usage | null = null;
  toolCalls: ToolCall[] = [];
  attachments: Attachment[] = [];
  /** 前缀续写标记（DeepSeek Beta prefix completion） */
  prefix: boolean = false;
  /** 首 token 延迟 */
  ttftMs: number = 0;
  /** 总耗时 */
  latencyMs: number = 0;
  /** 思维链展开状态 */
  reasoningExpanded: boolean = false;
  /** 是否完成 */
  finishReason: string = '';
  /** 本轮联网搜索用到的来源（仅助手消息有值） */
  sources: SearchResult[] = [];
  /** 搜索路由说明，例如「首选 Bing 不可用，已改用 DuckDuckGo」 */
  searchNote: string = '';
  /** 本轮的工作步骤时间线 */
  steps: WorkStep[] = [];
  /** 本轮开始时间戳，用于「工作中」状态实时计时 */
  runStartedAt: number = 0;
  /** 本轮总耗时（工具回环时跨多轮累计） */
  runMs: number = 0;

  static create(role: string, content: string, model: string, providerId: string): ChatMessage {
    const m: ChatMessage = new ChatMessage();
    m.id = 'm' + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
    m.role = role;
    m.content = content;
    m.createdAt = Date.now();
    m.model = model;
    m.providerId = providerId;
    m.status = MsgStatus.DONE;
    return m;
  }
}

/** 会话元数据 */
@Observed
export class SessionMeta {
  id: string = '';
  title: string = '新对话';
  updatedAt: number = 0;
  createdAt: number = 0;
  providerId: string = '';
  model: string = '';
  messageCount: number = 0;
  pinned: boolean = false;
}

/** 会话（完整） */
export class Session {
  meta: SessionMeta = new SessionMeta();
  messages: ChatMessage[] = [];
  systemPrompt: string = '';
}

/** 模型信息（来自 /models 或预设） */
export class ModelInfo {
  id: string = '';
  label: string = '';
  providerId: string = '';
  contextWindow: number = 0;
  maxOutputTokens: number = 0;
  supportsVision: boolean = false;
  supportsThinking: boolean = false;
  supportsTools: boolean = true;
  supportsFim: boolean = false;
  supportsResponses: boolean = false;
  /** 支持的 reasoning effort 级别 */
  effortLevels: string[] = [];
  defaultEffort: string = '';
  description: string = '';
}

/** 服务商配置 */
@Observed
export class ProviderConfig {
  id: string = '';
  name: string = '';
  /** 协议 */
  protocol: string = Protocol.CHAT_COMPLETIONS;
  /** 参数风格：deepseek / openai / anthropic / generic */
  flavor: string = 'generic';
  /** 主 base url */
  baseUrl: string = '';
  /** Beta base url（DeepSeek 的 /beta） */
  betaBaseUrl: string = '';
  apiKey: string = '';
  /** 附加请求头 JSON */
  extraHeaders: string = '';
  /** 可用模型（手动） */
  models: string[] = [];
  /** 是否内置 */
  builtin: boolean = false;
  /** 启用状态 */
  enabled: boolean = true;
  /** 是否支持余额查询 */
  supportsBalance: boolean = false;
  /** 是否支持模型列表拉取 */
  supportsModelList: boolean = true;
  /** 品牌色 */
  brandColor: string = '#4C6EF5';
  /** 备注 */
  note: string = '';
}

/** 推理参数 */
@Observed
export class InferenceParams {
  temperature: number = 1.0;
  topP: number = 1.0;
  maxTokens: number = 0;
  /** 0 表示不限制 */
  frequencyPenalty: number = 0;
  presencePenalty: number = 0;
  stop: string = '';
  /** 思考模式：off / auto / low / high / max */
  thinking: string = 'auto';
  /** 输出 JSON */
  jsonMode: boolean = false;
  /** 返回 logprobs */
  logprobs: boolean = false;
  topLogprobs: number = 0;
  /** user_id 隔离标识 */
  userId: string = '';
  stream: boolean = true;
  /** 是否启用内置工具 */
  enableTools: boolean = false;
  /** 是否联网搜索后再回答 */
  webSearch: boolean = false;
}

/** 应用设置 */
@Observed
export class AppSettings {
  themeMode: string = ThemeMode.DARK;
  followSystemDark: boolean = true;
  providers: ProviderConfig[] = [];
  activeProviderId: string = '';
  activeModel: string = '';
  params: InferenceParams = new InferenceParams();
  systemPrompt: string = '';
  sendOnEnter: boolean = true;
  showTokenStats: boolean = true;
  showCost: boolean = true;
  fontSize: number = 15;
  language: string = 'zh';
  hapticFeedback: boolean = true;
  autoTitle: boolean = true;
  streamOutput: boolean = true;
  /** 是否显示思维链 */
  showReasoning: boolean = true;
  /* ---------- 联网搜索 ---------- */
  /** 搜索后端：auto | bing | duckduckgo | searxng */
  webSearchBackend: string = 'auto';
  /** SearXNG 实例地址 */
  webSearchEndpoint: string = '';
  /** 注入的搜索结果条数 */
  webSearchMax: number = 5;
  /** 回答下方展示来源列表 */
  webSearchShowSources: boolean = true;
  /** 搜索地区：留空则跟随界面语言推导（zh-CN / en-US） */
  webSearchRegion: string = '';
  /** 各搜索后端的健康度记忆，持久化后重启即可直接择优 */
  searchHealth: BackendHealth[] = [];
  /** 是否展示 AI 工作过程（步骤 / 思维链 / 工具调用） */
  showSteps: boolean = true;
  /** 工作过程默认展开；默认折叠只显示「已完成 · N 秒」一行 */
  processDefaultOpen: boolean = false;
  /** 联网来源列表默认折叠；默认关闭（即默认展开，展开后可见标题与摘要） */
  sourcesDefaultCollapsed: boolean = false;
  /* ---------- 语音 ---------- */
  /** 语音功能总开关 */
  speechEnabled: boolean = true;
  /** 回复完成后自动朗读 */
  ttsAutoRead: boolean = false;
  /** 朗读语速 0.5 ~ 2.0 */
  ttsSpeed: number = 1.0;
  /** 发音人（离线引擎 0 为默认女声） */
  ttsPerson: number = 0;
  /** 语音识别语言 */
  speechLanguage: string = 'zh-CN';
  /** 识别完成后自动发送 */
  speechAutoSend: boolean = true;
}

/** 一条联网搜索结果 */
export class SearchResult {
  title: string = '';
  url: string = '';
  snippet: string = '';
  /** 来源站点，用于展示 */
  site: string = '';
}

/** 联网搜索配置 */
export class SearchConfig {
  /** auto | bing | duckduckgo | searxng */
  backend: string = 'auto';
  /** searxng 实例地址 */
  endpoint: string = '';
  /** 返回条数 */
  maxResults: number = 5;
  /** 地区（Bing mkt） */
  region: string = 'zh-CN';
}

/** 搜索后端健康度（进程内记忆，用于自动择优） */
export class BackendHealth {
  backend: string = '';
  /** 最近一次是否成功 */
  ok: boolean = false;
  /** 最近一次成功耗时毫秒 */
  ms: number = 0;
  /** 连续失败次数 */
  failures: number = 0;
  /** 冷却截止时间戳；大于当前时间表示暂时不再尝试 */
  cooldownUntil: number = 0;
  /** 是否测过 */
  tested: boolean = false;
  /** 最近一次成功的时间戳，用于判断记忆是否还新鲜 */
  checkedAt: number = 0;
}

/**
 * 一轮回答中的一个「工作步骤」。
 * 把搜索 / 思考 / 工具调用 / 生成回答串成一条可读的时间线，
 * 让用户看清 AI 到底做了哪些事、各花了多久。
 */
export class WorkStep {
  /** search | think | tool | answer */
  kind: string = '';
  /** 步骤标题，如「联网搜索」「调用 calculate」 */
  title: string = '';
  /** 补充说明，如搜索词、工具参数摘要、结果条数 */
  detail: string = '';
  /** 结果摘要（工具调用返回的内容） */
  result: string = '';
  /** 耗时毫秒 */
  ms: number = 0;
  /** running | done | failed */
  status: string = 'done';
  /** 开始时间戳，用于排序 */
  startedAt: number = 0;
}

/** 一次联网搜索的结果与路由信息 */
export class SearchOutcome {
  results: SearchResult[] = [];
  /** 实际使用的后端；空表示全部失败 */
  backend: string = '';
  /** 是否发生了降级（实际用的不是用户首选） */
  fellBack: boolean = false;
  /** 用户首选后端（auto 模式为 'auto'） */
  preferred: string = '';
}

/** 单个搜索后端的连通性测试结果 */
export class SearchTestResult {
  /** bing | duckduckgo | searxng */
  backend: string = '';
  /** 是否连通并解析成功 */
  ok: boolean = false;
  /** 解析出的结果条数 */
  count: number = 0;
  /** 耗时毫秒 */
  ms: number = 0;
  /** 失败原因（ok=false 时有值） */
  error: string = '';
  /** 首条结果标题，便于确认返回内容是否合理 */
  sample: string = '';
  /** 是否被跳过（例如 SearXNG 未配置地址） */
  skipped: boolean = false;
}

/** 全文搜索结果 */
export class SearchHit {
  sessionId: string = '';
  title: string = '';
  updatedAt: number = 0;
  /** 命中总数 */
  matchCount: number = 0;
  /** 命中位置摘要（含 … 省略号） */
  snippet: string = '';
  /** 摘要所属角色 */
  role: string = '';
  /** 是否命中标题 */
  inTitle: boolean = false;
}

/** 余额 */
@Observed
export class BalanceInfo {
  isAvailable: boolean = false;
  currency: string = 'CNY';
  totalBalance: string = '0';
  grantedBalance: string = '0';
  toppedUpBalance: string = '0';
  fetchedAt: number = 0;
  error: string = '';
}

/** 流式回调事件 */
export interface StreamEvents {
  onStart: () => void;
  onReasoning: (delta: string) => void;
  onContent: (delta: string) => void;
  onToolCall: (call: ToolCall) => void;
  onUsage: (usage: Usage) => void;
  onFinish: (reason: string) => void;
  onError: (message: string) => void;
}

/** 请求上下文 */
export class RequestContext {
  provider: ProviderConfig = new ProviderConfig();
  model: string = '';
  messages: ChatMessage[] = [];
  systemPrompt: string = '';
  params: InferenceParams = new InferenceParams();
  /** FIM 补全的 suffix */
  suffix: string = '';
  /** 前缀续写 */
  prefixMode: boolean = false;
}


/** 会话索引项（持久化结构） */
export interface SessionIndexEntry {
  id: string;
  title: string;
  updatedAt: number;
  createdAt: number;
  providerId: string;
  model: string;
  messageCount: number;
  pinned: boolean;
}

/** 会话索引文件 */
export interface SessionIndexFile {
  version: number;
  activeId: string;
  entries: SessionIndexEntry[];
}

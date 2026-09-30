/**
 * 各协议线上报文（wire format）类型定义
 * 覆盖 OpenAI Chat Completions / Responses / Anthropic Messages / DeepSeek FIM
 */

/* ============ 通用消息内容分段 ============ */

export interface WireImageUrl {
  url: string;
  detail?: string;
}

/** 统一的内容分段（text / image_url / file） */
export interface WireContentPart {
  type: string;
  text?: string;
  image_url?: WireImageUrl;
  file_id?: string;
  file_data?: string;
  filename?: string;
}

/** 工具参数的 JSON Schema（简化结构） */
export interface WireParamDef {
  type?: string;
  description?: string;
  enum?: string[];
  items?: Object;
  properties?: Object;
  required?: string[];
}

export interface WireObjectSchema {
  type?: string;
  properties?: WireParamDef;
  required?: string[];
  additionalProperties?: boolean;
}

export interface WireToolCallFunction {
  name: string;
  arguments: string;
}

export interface WireToolCall {
  index?: number;
  id?: string;
  type?: string;
  function: WireToolCallFunction;
}

export interface WireMessage {
  role: string;
  content?: string | WireContentPart[];
  name?: string;
  reasoning_content?: string;
  prefix?: boolean;
  tool_calls?: WireToolCall[];
  tool_call_id?: string;
}

/* ============ 请求 ============ */

export interface WireStreamOptions {
  include_usage: boolean;
}

export interface WireResponseFormat {
  type: string;
}

export interface WireThinking {
  type: string;
}

export interface WireFunctionDef {
  name: string;
  description?: string;
  parameters?: Object;
  strict?: boolean;
}

export interface WireTool {
  type: string;
  function: WireFunctionDef;
}

export interface WireChatRequest {
  model: string;
  messages: WireMessage[];
  stream?: boolean;
  stream_options?: WireStreamOptions;
  max_tokens?: number;
  max_completion_tokens?: number;
  temperature?: number;
  top_p?: number;
  stop?: string[];
  response_format?: WireResponseFormat;
  logprobs?: boolean;
  top_logprobs?: number;
  user_id?: string;
  user?: string;
  thinking?: WireThinking;
  reasoning_effort?: string;
  reasoning?: WireReasoning;
  tools?: WireTool[];
  tool_choice?: string;
  frequency_penalty?: number;
  presence_penalty?: number;
  n?: number;
}

export interface WireReasoning {
  effort?: string;
  summary?: string;
}

/* ============ 响应（Chat Completions） ============ */

export interface WireDelta {
  role?: string;
  content?: string | null;
  reasoning_content?: string | null;
  reasoning?: string | null;
  tool_calls?: WireToolCall[];
}

export interface WireChoice {
  index?: number;
  delta?: WireDelta;
  message?: WireMessage;
  finish_reason?: string | null;
  logprobs?: Object | null;
}

export interface WirePromptDetails {
  cached_tokens?: number;
  audio_tokens?: number;
}

export interface WireCompletionDetails {
  reasoning_tokens?: number;
  audio_tokens?: number;
  accepted_prediction_tokens?: number;
  rejected_prediction_tokens?: number;
}

export interface WireUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  input_tokens?: number;
  output_tokens?: number;
  prompt_tokens_details?: WirePromptDetails;
  completion_tokens_details?: WireCompletionDetails;
  input_tokens_details?: WirePromptDetails;
  output_tokens_details?: WireCompletionDetails;
  prompt_cache_hit_tokens?: number;
  prompt_cache_miss_tokens?: number;
}

export interface WireChunk {
  id?: string;
  object?: string;
  created?: number;
  model?: string;
  choices?: WireChoice[];
  usage?: WireUsage | null;
  error?: WireError;
}

export interface WireErrorBody {
  message?: string;
  type?: string;
  param?: string | null;
  code?: string | null;
}

export interface WireError {
  error?: WireErrorBody;
  code?: string;
  message?: string;
}

/* ============ 模型列表 ============ */

export interface WireEffort {
  supported_levels?: string[];
  default_level?: string;
}

export interface WireModel {
  id?: string;
  object?: string;
  owned_by?: string;
  name?: string;
  context_window?: number;
  max_output_tokens?: number;
  input_modalities?: string[];
  output_modalities?: string[];
  effort?: WireEffort;
  created?: number;
}

export interface WireModelList {
  object?: string;
  data?: WireModel[];
}

/* ============ 余额 ============ */

export interface WireBalanceEntry {
  currency?: string;
  total_balance?: string;
  granted_balance?: string;
  topped_up_balance?: string;
}

export interface WireBalance {
  is_available?: boolean;
  balance_infos?: WireBalanceEntry[];
}

/* ============ FIM 补全 ============ */

export interface WireFimRequest {
  model: string;
  prompt: string;
  suffix?: string;
  max_tokens?: number;
  temperature?: number;
  top_p?: number;
  stop?: string[];
  echo?: boolean;
  logprobs?: number;
  stream?: boolean;
  stream_options?: WireStreamOptions;
  thinking?: WireThinking;
}

export interface WireFimChoice {
  index?: number;
  text?: string;
  finish_reason?: string | null;
}

export interface WireFimChunk {
  id?: string;
  object?: string;
  model?: string;
  choices?: WireFimChoice[];
  usage?: WireUsage | null;
  error?: WireError;
}

/* ============ Responses API ============ */

export interface WireRespTextFormat {
  type?: string;
  format?: WireRespFormatBody;
}

export interface WireRespFormatBody {
  type?: string;
  name?: string;
  schema?: Object;
  strict?: boolean;
}

export interface WireRespInput {
  type?: string;
  role?: string;
  content?: string;
}

export interface WireRespRequest {
  model: string;
  input: WireRespInput[];
  instructions?: string;
  stream?: boolean;
  max_output_tokens?: number;
  temperature?: number;
  top_p?: number;
  reasoning?: WireReasoning;
  text?: WireRespTextFormat;
  tools?: Object[];
  tool_choice?: string;
  store?: boolean;
  user?: string;
}

export interface WireRespEvent {
  type?: string;
  delta?: string;
  sequence_number?: number;
  item_id?: string;
  output_index?: number;
  content_index?: number;
  text?: string;
  arguments?: string;
  name?: string;
  call_id?: string;
  item?: WireRespItem;
  response?: WireRespResponse;
  error?: WireErrorBody;
}

export interface WireRespItem {
  id?: string;
  type?: string;
  role?: string;
  name?: string;
  arguments?: string;
  call_id?: string;
  content?: WireRespContent[];
  summary?: WireRespContent[];
}

export interface WireRespContent {
  type?: string;
  text?: string;
}

export interface WireRespResponse {
  id?: string;
  status?: string;
  model?: string;
  output?: WireRespItem[];
  usage?: WireUsage;
  incomplete_details?: WireRespIncomplete;
  error?: WireErrorBody;
}

export interface WireRespIncomplete {
  reason?: string;
}

/* ============ Anthropic Messages ============ */

export interface WireAnthropicContent {
  type: string;
  text?: string;
  source?: WireAnthropicSource;
  id?: string;
  name?: string;
  input?: Object;
  tool_use_id?: string;
  content?: string;
}

export interface WireAnthropicSource {
  type: string;
  media_type?: string;
  data?: string;
  url?: string;
}

export interface WireAnthropicMessage {
  role: string;
  content: string | WireAnthropicContent[];
}

export interface WireAnthropicThinking {
  type?: string;
  budget_tokens?: number;
}

export interface WireAnthropicRequest {
  model: string;
  max_tokens: number;
  messages: WireAnthropicMessage[];
  system?: string;
  stream?: boolean;
  temperature?: number;
  top_p?: number;
  stop_sequences?: string[];
  thinking?: WireAnthropicThinking;
  tools?: Object[];
  tool_choice?: Object;
  metadata?: Object;
}

export interface WireAnthropicEvent {
  type?: string;
  index?: number;
  delta?: WireAnthropicDelta;
  content_block?: WireAnthropicContent;
  message?: WireAnthropicMessageResp;
  usage?: WireAnthropicUsage;
  error?: WireErrorBody;
}

export interface WireAnthropicDelta {
  type?: string;
  text?: string;
  thinking?: string;
  partial_json?: string;
  stop_reason?: string;
}

export interface WireAnthropicMessageResp {
  id?: string;
  model?: string;
  stop_reason?: string;
  usage?: WireAnthropicUsage;
}

export interface WireAnthropicUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}

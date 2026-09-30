import { display, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Themes, Palette, Dim, Font } from '../theme/Theme';
import { Constants, MsgStatus, Role, ThemeMode } from '../common/Constants';
import { Utils } from '../common/Utils';
import { Logger } from '../common/Logger';
import {
  AppSettings, Attachment, BalanceInfo, ChatMessage, InferenceParams, ProviderConfig, RequestContext, SearchHit, Session, SessionMeta,
  SessionIndexEntry, SessionIndexFile, SearchConfig, SearchResult, SearchOutcome, SearchTestResult, ToolCall, WorkStep
} from '../model/Types';
import { StorageService } from '../service/StorageService';
import { ChatEngine } from '../service/ChatEngine';
import { ImagePicker } from '../service/ImagePicker';
import { SpeechService, AsrHandlers, TtsHandlers } from '../service/SpeechService';
import { SearchService } from '../service/SearchService';
import { StreamSink } from '../provider/BaseProvider';
import { AbortHandle } from '../net/HttpClient';
import { ProviderFactory } from '../provider/ProviderFactory';
import { Sidebar } from '../view/Sidebar';
import { MessageList } from '../view/MessageList';
import { Composer } from '../view/Composer';
import { ModelPicker } from '../view/ModelPicker';
import { SettingsPage } from '../view/SettingsPage';
import { FimPage } from '../view/FimPage';
import { IconBtn, Pill } from '../view/Common';

@Entry
@Component
struct Index {
  @StorageLink('colorMode') colorMode: number = -1;
  @State settings: AppSettings = StorageService.defaultSettings();
  @State params: InferenceParams = new InferenceParams();
  @State sessions: SessionMeta[] = [];
  @State messages: ChatMessage[] = [];
  @State activeSessionId: string = '';
  @State inputText: string = '';
  @State attachments: Attachment[] = [];
  @State generating: boolean = false;
  @State isWide: boolean = false;
  @State route: string = 'chat';
  @State drawerOpen: boolean = false;
  @State showModelSheet: boolean = false;
  @State streamTick: number = 0;
  @State msgCount: number = 0;
  @State balance: BalanceInfo = new BalanceInfo();
  @State balanceLoading: boolean = false;
  @State modelLoading: boolean = false;
  @State modelError: string = '';
  @State showRename: boolean = false;
  @State renameText: string = '';
  @State renameTargetId: string = '';
  @State ready: boolean = false;
  /* ---------- 语音 ---------- */
  /** 正在语音识别 */
  @State listening: boolean = false;
  /** 识别中的实时音量 0~1 */
  @State micLevel: number = 0;
  /** 正在朗读的消息 id */
  @State speakingId: string = '';
  /* ---------- 搜索 ---------- */
  @State @Watch('onSearchKeyword') searchKeyword: string = '';
  @State searchHits: SearchHit[] = [];
  /**
   * 消息状态变更信号（思维链展开/收起、流式结束、来源到达等）。
   *
   * ArkUI V1 下 @ObjectLink 对 @Observed 对象的属性变更不一定会触发子组件重渲染，
   * 而 streamTick 在 MessageList.build() 中未被引用、依赖追踪会跳过整棵子树。
   * 所以用一个显式递增的 tick 逐层传下去，由 @Watch 同步到局部 @State 来保证刷新。
   */
  @State msgTick: number = 0;
  /* ---------- 联网搜索 ---------- */
  /** 正在联网检索 */
  @State searching: boolean = false;
  /** 本轮的搜索结果，beginRun 时注入 system prompt */
  private pendingSources: SearchResult[] = [];
  /** 本轮搜索的路由说明（降级时才有内容） */
  private pendingSearchNote: string = '';
  /* ---------- 工作步骤时间线 ---------- */
  /** 搜索阶段产生的步骤，beginRun 时交给助手消息 */
  private pendingSteps: WorkStep[] = [];
  private stepThink: WorkStep | null = null;
  private stepAnswer: WorkStep | null = null;
  /** 本轮开始时间戳（工具回环共用同一个起点） */
  private turnStartedAt: number = 0;

  private newStep(kind: string, title: string, detail: string): WorkStep {
    const s: WorkStep = new WorkStep();
    s.kind = kind;
    s.title = title;
    s.detail = detail;
    s.startedAt = Date.now();
    s.status = 'running';
    return s;
  }

  private closeStep(s: WorkStep | null, result: string, ok: boolean): void {
    if (s === null) {
      return;
    }
    s.ms = Date.now() - s.startedAt;
    s.status = ok ? 'done' : 'failed';
    if (result.length > 0) {
      s.result = result;
    }
  }
  /** 搜索后端连通性测试 */
  @State searchTesting: boolean = false;
  @State searchTest: SearchTestResult[] = [];

  private flushTimer: number = -1;
  private handle: AbortHandle | null = null;
  private bufContent: string = '';
  private bufReasoning: string = '';
  private currentAssistant: ChatMessage | null = null;
  private loopCount: number = 0;
  private startedAt: number = 0;
  private displayListener: () => void = () => {};
  /** 开始识别前输入框已有的文本 */
  private speechBase: string = '';

  /* ===================== 生命周期 ===================== */

  aboutToAppear(): void {
    this.settings = StorageService.loadSettings();
    this.params = this.settings.params;
    // 恢复上次的搜索后端健康度，重启后第一次搜索即可直接择优
    SearchService.loadHealth(this.settings.searchHealth);
    this.loadSessions();
    this.updateLayout();
    this.displayListener = () => {
      this.updateLayout();
    };
    try {
      display.on('change', this.displayListener);
    } catch (e) {
      Logger.warn('display listener failed');
    }
    this.ready = true;
    // 启动时自动查询一次余额（若已配置 Key）
    this.refreshBalance(true);
  }

  aboutToDisappear(): void {
    SpeechService.stopSpeaking();
    SpeechService.shutdownAsr();
    SpeechService.shutdownTts();
    this.stopFlush();
    if (this.handle !== null) {
      this.handle.cancel();
      this.handle = null;
    }
    try {
      display.off('change', this.displayListener);
    } catch (e) {
    }
    this.saveCurrentSession();
  }

  onBackPress(): boolean {
    if (this.showRename) {
      this.showRename = false;
      return true;
    }
    if (this.showModelSheet) {
      this.showModelSheet = false;
      return true;
    }
    if (this.drawerOpen) {
      this.drawerOpen = false;
      return true;
    }
    if (this.route !== 'chat') {
      this.route = 'chat';
      return true;
    }
    return false;
  }

  /* ===================== 主题与布局 ===================== */

  private pal(): Palette {
    return Themes.of(this.isDarkNow());
  }

  /** 统一的轻提示（优先使用 UIContext 上的 PromptAction） */
  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (e) {
      this.toast(msg);
    }
  }

  private isDarkNow(): boolean {
    if (this.settings.themeMode === ThemeMode.DARK) {
      return true;
    }
    if (this.settings.themeMode === ThemeMode.LIGHT) {
      return false;
    }
    return this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private updateLayout(): void {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      // vp = px * 160 / densityDPI（避免使用已废弃的全局 px2vp）
      const density: number = d.densityDPI > 0 ? d.densityDPI : 480;
      const w: number = d.width * 160 / density;
      this.isWide = w >= Constants.BREAKPOINT_MEDIUM;
    } catch (e) {
      this.isWide = false;
    }
  }

  /* ===================== 会话管理 ===================== */

  private loadSessions(): void {
    const idx: SessionIndexFile = StorageService.loadIndex();
    const list: SessionMeta[] = [];
    for (let i = 0; i < idx.entries.length; i++) {
      const e: SessionIndexEntry = idx.entries[i];
      const m: SessionMeta = new SessionMeta();
      m.id = e.id;
      m.title = e.title;
      m.updatedAt = e.updatedAt;
      m.createdAt = e.createdAt;
      m.providerId = e.providerId;
      m.model = e.model;
      m.messageCount = e.messageCount;
      m.pinned = e.pinned === true;
      list.push(m);
    }
    this.sessions = list;

    let target: string = idx.activeId;
    if (target.length === 0 && list.length > 0) {
      target = list[0].id;
    }
    if (target.length > 0) {
      const s: Session | null = StorageService.loadSession(target);
      if (s !== null) {
        this.activeSessionId = target;
        this.messages = s.messages;
        this.msgCount = s.messages.length;
        if (s.systemPrompt !== undefined && s.systemPrompt !== null && s.systemPrompt.length > 0) {
          this.settings.systemPrompt = s.systemPrompt;
        }
        return;
      }
    }
    this.createSession(false);
  }

  private createSession(persist: boolean): void {
    if (persist) {
      this.saveCurrentSession();
    }
    const meta: SessionMeta = new SessionMeta();
    meta.id = Utils.uid('s');
    meta.title = '新对话';
    meta.createdAt = Date.now();
    meta.updatedAt = Date.now();
    meta.providerId = this.settings.activeProviderId;
    meta.model = this.settings.activeModel;
    meta.messageCount = 0;
    const list: SessionMeta[] = [meta];
    for (let i = 0; i < this.sessions.length; i++) {
      list.push(this.sessions[i]);
    }
    this.sessions = list;
    this.activeSessionId = meta.id;
    this.messages = [];
    this.msgCount = 0;
    this.drawerOpen = false;
    this.persistIndex();
  }

  private selectSession(id: string): void {
    if (id === this.activeSessionId) {
      this.drawerOpen = false;
      return;
    }
    this.saveCurrentSession();
    const s: Session | null = StorageService.loadSession(id);
    if (s === null) {
      this.toast('会话不存在或已损坏');
      return;
    }
    this.activeSessionId = id;
    this.messages = s.messages;
    this.msgCount = s.messages.length;
    this.drawerOpen = false;
    this.persistIndex();
  }

  private deleteSession(id: string): void {
    StorageService.deleteSession(id);
    const list: SessionMeta[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id !== id) {
        list.push(this.sessions[i]);
      }
    }
    this.sessions = list;
    if (this.activeSessionId === id) {
      this.activeSessionId = '';
      this.messages = [];
      this.msgCount = 0;
      if (list.length > 0) {
        this.selectSession(list[0].id);
      } else {
        this.createSession(false);
      }
    }
    this.persistIndex();
  }

  private togglePin(m: SessionMeta): void {
    const list: SessionMeta[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      const s: SessionMeta = this.sessions[i];
      if (s.id === m.id) {
        const n: SessionMeta = new SessionMeta();
        n.id = s.id;
        n.title = s.title;
        n.updatedAt = s.updatedAt;
        n.createdAt = s.createdAt;
        n.providerId = s.providerId;
        n.model = s.model;
        n.messageCount = s.messageCount;
        n.pinned = !s.pinned;
        list.push(n);
      } else {
        list.push(s);
      }
    }
    this.sessions = list;
    this.persistIndex();
  }

  private renameSession(id: string, title: string): void {
    const t: string = title.trim().length > 0 ? title.trim() : '未命名会话';
    const list: SessionMeta[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      const s: SessionMeta = this.sessions[i];
      if (s.id === id) {
        const n: SessionMeta = new SessionMeta();
        n.id = s.id;
        n.title = t;
        n.updatedAt = s.updatedAt;
        n.createdAt = s.createdAt;
        n.providerId = s.providerId;
        n.model = s.model;
        n.messageCount = s.messageCount;
        n.pinned = s.pinned;
        list.push(n);
      } else {
        list.push(s);
      }
    }
    this.sessions = list;
    this.persistIndex();
    const sess: Session | null = StorageService.loadSession(id);
    if (sess !== null) {
      sess.meta.title = t;
      StorageService.saveSession(sess);
    }
  }

  private persistIndex(): void {
    const entries: SessionIndexEntry[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      const s: SessionMeta = this.sessions[i];
      entries.push({
        id: s.id, title: s.title, updatedAt: s.updatedAt, createdAt: s.createdAt,
        providerId: s.providerId, model: s.model, messageCount: s.messageCount, pinned: s.pinned
      });
    }
    const file: SessionIndexFile = { version: 1, activeId: this.activeSessionId, entries: entries };
    StorageService.saveIndex(file);
  }

  private saveCurrentSession(): void {
    if (this.activeSessionId.length === 0) {
      return;
    }
    const meta: SessionMeta = new SessionMeta();
    meta.id = this.activeSessionId;
    meta.updatedAt = Date.now();
    meta.createdAt = Date.now();
    meta.providerId = this.settings.activeProviderId;
    meta.model = this.settings.activeModel;
    meta.messageCount = this.messages.length;
    let found: boolean = false;
    for (let i = 0; i < this.sessions.length; i++) {
      const s: SessionMeta = this.sessions[i];
      if (s.id === this.activeSessionId) {
        meta.title = s.title;
        meta.createdAt = s.createdAt;
        meta.pinned = s.pinned;
        found = true;
        break;
      }
    }
    if (!found) {
      meta.title = '新对话';
    }
    const sess: Session = new Session();
    sess.meta = meta;
    sess.messages = this.messages;
    sess.systemPrompt = this.settings.systemPrompt;
    StorageService.saveSession(sess);

    const list: SessionMeta[] = [];
    let replaced: boolean = false;
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === this.activeSessionId) {
        list.push(meta);
        replaced = true;
      } else {
        list.push(this.sessions[i]);
      }
    }
    if (!replaced) {
      list.unshift(meta);
    }
    this.sessions = list;
    this.persistIndex();
  }

  private autoTitle(text: string): void {
    if (!this.settings.autoTitle) {
      return;
    }
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === this.activeSessionId) {
        if (this.sessions[i].title === '新对话' || this.sessions[i].title.length === 0) {
          this.renameSession(this.activeSessionId, Utils.titleFrom(text));
        }
        return;
      }
    }
  }

  /* ===================== 发送与流式 ===================== */

  private activeProvider(): ProviderConfig {
    const list: ProviderConfig[] = this.settings.providers;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === this.settings.activeProviderId) {
        return list[i];
      }
    }
    if (list.length > 0) {
      return list[0];
    }
    return ProviderFactory.deepseekChat();
  }

  private pendingParams(): InferenceParams {
    const p: InferenceParams = new InferenceParams();
    p.temperature = this.params.temperature;
    p.topP = this.params.topP;
    p.maxTokens = this.params.maxTokens;
    p.frequencyPenalty = this.params.frequencyPenalty;
    p.presencePenalty = this.params.presencePenalty;
    p.stop = this.params.stop;
    p.thinking = this.params.thinking;
    p.jsonMode = this.params.jsonMode;
    p.logprobs = this.params.logprobs;
    p.topLogprobs = this.params.topLogprobs;
    p.userId = this.params.userId;
    p.stream = this.settings.streamOutput;
    p.enableTools = this.params.enableTools;
    p.webSearch = this.params.webSearch;
    return p;
  }

  /** 组装搜索配置（地区跟随界面语言） */
  private searchConfig(): SearchConfig {
    const c: SearchConfig = new SearchConfig();
    c.backend = this.settings.webSearchBackend;
    c.endpoint = this.settings.webSearchEndpoint;
    c.maxResults = this.settings.webSearchMax;
    c.region = this.settings.webSearchRegion.length > 0
      ? this.settings.webSearchRegion
      : SearchService.regionFor(this.settings.language);
    return c;
  }

  /** 依次测试三个搜索后端，结果展示在设置页 */
  private async runSearchTest(): Promise<void> {
    if (this.searchTesting) {
      return;
    }
    this.searchTesting = true;
    this.searchTest = [];
    // 用与界面语言匹配的查询词，顺便验证地区参数是否生效
    const probe: string = this.settings.language === 'en' ? 'HarmonyOS version' : '鸿蒙 版本';
    try {
      this.searchTest = await SearchService.testAll(this.searchConfig(), probe);
    } catch (e) {
      const err = e as Error;
      Logger.warn('search test failed: ' + err.message);
    }
    this.searchTesting = false;
    // 测试结果直接落盘，下次启动即已择优
    this.settings.searchHealth = SearchService.healthSnapshot();
    this.saveSettings();
  }

  private async doSend(): Promise<void> {
    if (this.generating || this.searching) {
      return;
    }
    const text: string = this.inputText.trim();
    const hasAtt: boolean = this.attachments.length > 0;
    if (text.length === 0 && !hasAtt) {
      return;
    }
    const provider: ProviderConfig = this.activeProvider();
    if (provider.apiKey.length === 0) {
      this.toast('请先在设置中填写 ' + provider.name + ' 的 API Key');
      this.route = 'settings';
      return;
    }
    const um: ChatMessage = ChatMessage.create(Role.USER, text, this.settings.activeModel, provider.id);
    um.attachments = this.attachments;
    this.messages.push(um);
    this.msgCount = this.messages.length;
    this.inputText = '';

    // 联网搜索：先检索，再把结果作为上下文注入
    this.pendingSources = [];
    this.pendingSearchNote = '';
    this.pendingSteps = [];
    this.turnStartedAt = Date.now();
    if (this.params.webSearch && text.length > 0) {
      this.searching = true;
      const ss: WorkStep = this.newStep('search', '联网搜索',
        '"' + (text.length > 30 ? text.substring(0, 30) : text) + '"');
      this.pendingSteps.push(ss);
      try {
        const outcome: SearchOutcome = await SearchService.search(this.searchConfig(), text);
        this.pendingSources = outcome.results;
        this.pendingSearchNote = SearchService.noteOf(outcome);
        if (this.pendingSearchNote.length > 0) {
          this.toast(this.pendingSearchNote);
        }
        if (this.pendingSources.length === 0) {
          this.toast('联网搜索没有返回结果，将直接回答');
        }
        ss.detail = ss.detail + ' → ' + this.pendingSources.length.toString() + ' 条'
          + (outcome.backend.length > 0 ? ('（' + SearchService.backendLabel(outcome.backend) + '）') : '');
        this.closeStep(ss, '', this.pendingSources.length > 0);
      } catch (e) {
        const err = e as Error;
        Logger.warn('web search failed: ' + err.message);
        this.toast('联网搜索失败：' + err.message);
        this.closeStep(ss, err.message, false);
      }
      this.searching = false;
      // 把这次搜索学到的健康度持久化
      this.settings.searchHealth = SearchService.healthSnapshot();
      this.saveSettings();
    }
    this.attachments = [];
    this.autoTitle(text.length > 0 ? text : '[图片]');
    this.loopCount = 0;
    this.beginRun();
  }

  private beginRun(): void {
    // 工具回环会重新进入 beginRun；先把上一条消息里仍未收尾的步骤结算掉，
    // 否则「思考」会永远停在 running、耗时显示为 0
    const prev: ChatMessage | null = this.currentAssistant;
    if (prev !== null) {
      for (let i = 0; i < prev.steps.length; i++) {
        if (prev.steps[i].status === 'running') {
          this.closeStep(prev.steps[i], '', true);
        }
      }
    }
    const provider: ProviderConfig = this.activeProvider();
    const asst: ChatMessage = new ChatMessage();
    asst.id = Utils.uid('m');
    asst.role = Role.ASSISTANT;
    asst.createdAt = Date.now();
    asst.model = this.settings.activeModel;
    asst.providerId = provider.id;
    asst.status = MsgStatus.STREAMING;
    asst.reasoningExpanded = true;
    // 承接搜索阶段记录的步骤（只给本轮第一条助手消息，避免工具回环时重复）
    for (let i = 0; i < this.pendingSteps.length; i++) {
      asst.steps.push(this.pendingSteps[i]);
    }
    this.pendingSteps = [];
    this.stepThink = null;
    this.stepAnswer = null;
    asst.runStartedAt = this.turnStartedAt;
    if (this.pendingSources.length > 0) {
      asst.sources = this.pendingSources;
      asst.searchNote = this.pendingSearchNote;
      Logger.info('injected ' + this.pendingSources.length + ' search results into system prompt'
        + (this.pendingSearchNote.length > 0 ? (' | ' + this.pendingSearchNote) : ''));
    }
    this.messages.push(asst);
    this.msgCount = this.messages.length;
    this.currentAssistant = asst;
    this.generating = true;
    this.bufContent = '';
    this.bufReasoning = '';
    this.startedAt = Date.now();

    const ctx: RequestContext = new RequestContext();
    ctx.provider = provider;
    ctx.model = this.settings.activeModel;
    // 注入联网搜索结果
    let sys: string = this.settings.systemPrompt;
    if (this.pendingSources.length > 0) {
      const injected: string = SearchService.formatForPrompt(this.pendingSources);
      sys = sys.length > 0 ? (sys + '\n\n' + injected) : injected;
    }
    ctx.systemPrompt = sys;
    ctx.params = this.pendingParams();
    const history: ChatMessage[] = [];
    for (let i = 0; i < this.messages.length - 1; i++) {
      history.push(this.messages[i]);
    }
    ctx.messages = history;

    const sink: StreamSink = new StreamSink();
    sink.onContent = (t: string) => {
      if (asst.ttftMs === 0) {
        asst.ttftMs = Date.now() - this.startedAt;
      }
      // 正文开始 → 思考步骤结束，开启「生成回答」步骤
      if (this.stepThink !== null && this.stepThink.status === 'running') {
        this.closeStep(this.stepThink, '', true);
      }
      if (this.stepAnswer === null) {
        this.stepAnswer = this.newStep('answer', '生成回答', '');
        asst.steps.push(this.stepAnswer);
        this.msgTick = this.msgTick + 1;
      }
      this.bufContent += t;
    };
    sink.onReasoning = (t: string) => {
      if (asst.ttftMs === 0) {
        asst.ttftMs = Date.now() - this.startedAt;
      }
      // 第一个推理增量到达时开启「思考」步骤
      if (this.stepThink === null) {
        this.stepThink = this.newStep('think', '思考', '');
        asst.steps.push(this.stepThink);
        this.msgTick = this.msgTick + 1;
      }
      this.bufReasoning += t;
    };
    sink.onUsage = (u) => {
      asst.usage = u;
    };

    this.startFlush();
    this.handle = ChatEngine.run(ctx, sink, {
      onDone: (s: StreamSink) => {
        this.finishRun(s);
      },
      onFail: (m: string) => {
        this.failRun(m);
      }
    }, false);
  }

  private startFlush(): void {
    this.stopFlush();
    this.flushTimer = setInterval(() => {
      this.flushBuffers();
    }, Constants.STREAM_FLUSH_MS);
  }

  private stopFlush(): void {
    if (this.flushTimer >= 0) {
      clearInterval(this.flushTimer);
      this.flushTimer = -1;
    }
  }

  private flushBuffers(): void {
    const a: ChatMessage | null = this.currentAssistant;
    if (a === null) {
      return;
    }
    let changed: boolean = false;
    if (this.bufContent.length > 0) {
      a.content = a.content + this.bufContent;
      this.bufContent = '';
      changed = true;
    }
    if (this.bufReasoning.length > 0) {
      a.reasoning = a.reasoning + this.bufReasoning;
      this.bufReasoning = '';
      changed = true;
    }
    if (changed) {
      this.streamTick = this.streamTick + 1;
    }
  }

  private finishRun(s: StreamSink): void {
    this.stopFlush();
    this.flushBuffers();
    const a: ChatMessage | null = this.currentAssistant;
    if (a === null) {
      this.generating = false;
      return;
    }
    a.latencyMs = Date.now() - this.startedAt;
    a.finishReason = s.finishReason;
    if (a.content.length === 0 && a.reasoning.length === 0 && !s.errored) {
      a.content = '（模型未返回内容）';
    }
    a.status = MsgStatus.DONE;
    if (a.reasoning.length > 0) {
      a.reasoningExpanded = false;
    }
    // 必须显式通知：状态从 STREAMING 变为 DONE 后子组件不会自动重渲染，
    // 思维链面板与联网来源列表都依赖这次刷新才会出现
    this.msgTick = this.msgTick + 1;
    Logger.info('chat finished: ' + a.latencyMs + 'ms ttft=' + a.ttftMs + 'ms finish=' + s.finishReason
      + ' contentLen=' + a.content.length + ' reasoningLen=' + a.reasoning.length
      + ' toolCalls=' + s.toolCalls.length
      + (a.usage !== null ? (' tokens(in=' + a.usage.promptTokens + ' out=' + a.usage.completionTokens
        + ' cacheHit=' + a.usage.cacheHitTokens + ' reasoning=' + a.usage.reasoningTokens + ')') : ' tokens=n/a'));

    // 工具调用回环
    if (s.toolCalls.length > 0 && this.params.enableTools && this.loopCount < 3) {
      const toolSteps: WorkStep[] = [];
      for (let i = 0; i < s.toolCalls.length; i++) {
        const tc: ToolCall = s.toolCalls[i];
        toolSteps.push(this.newStep('tool', '调用 ' + tc.name, Utils.summarizeArgs(tc.arguments)));
      }
      a.toolCalls = ChatEngine.executeTools(s.toolCalls);
      for (let i = 0; i < toolSteps.length; i++) {
        const r: string = i < a.toolCalls.length ? a.toolCalls[i].result : '';
        this.closeStep(toolSteps[i], r, true);
        a.steps.push(toolSteps[i]);
      }
      this.msgTick = this.msgTick + 1;
      this.streamTick = this.streamTick + 1;
      this.loopCount = this.loopCount + 1;
      this.saveCurrentSession();
      if (this.loopCount >= 3) {
        this.generating = false;
        return;
      }
      this.beginRun();
      return;
    }

    // 收尾工作步骤
    a.runMs = this.turnStartedAt > 0 ? (Date.now() - this.turnStartedAt) : a.latencyMs;
    this.closeStep(this.stepThink, '', true);
    if (this.stepAnswer !== null) {
      this.closeStep(this.stepAnswer,
        a.content.length.toString() + ' 字 · ' + (a.latencyMs / 1000).toFixed(1) + 's', true);
    }
    this.msgTick = this.msgTick + 1;

    this.generating = false;
    this.currentAssistant = null;
    this.saveCurrentSession();

    // 自动朗读本轮回复
    if (this.settings.ttsAutoRead && this.settings.speechEnabled && a.content.length > 0) {
      this.speakOrStop(a);
    }
  }

  private failRun(m: string): void {
    Logger.error('chat failed: ' + m);
    this.msgTick = this.msgTick + 1;
    this.stopFlush();
    this.flushBuffers();
    const a: ChatMessage | null = this.currentAssistant;
    if (a !== null) {
      a.status = MsgStatus.ERROR;
      a.error = m;
      a.latencyMs = Date.now() - this.startedAt;
    }
    this.generating = false;
    this.currentAssistant = null;
    this.saveCurrentSession();
  }

  private stopGenerating(): void {
    if (this.handle !== null) {
      this.handle.cancel();
      this.handle = null;
    }
    this.stopFlush();
    this.flushBuffers();
    const a: ChatMessage | null = this.currentAssistant;
    if (a !== null) {
      a.status = MsgStatus.STOPPED;
      a.latencyMs = Date.now() - this.startedAt;
    }
    this.generating = false;
    this.currentAssistant = null;
    this.saveCurrentSession();
  }

  /* ===================== 消息操作 ===================== */

  private indexOfMessage(m: ChatMessage): number {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].id === m.id) {
        return i;
      }
    }
    return -1;
  }

  private regenerate(m: ChatMessage): void {
    if (this.generating) {
      return;
    }
    const i: number = this.indexOfMessage(m);
    if (i < 0) {
      return;
    }
    const list: ChatMessage[] = [];
    for (let k = 0; k < i; k++) {
      list.push(this.messages[k]);
    }
    this.messages = list;
    this.msgCount = list.length;
    this.loopCount = 0;
    this.beginRun();
  }

  private editMessage(m: ChatMessage): void {
    if (this.generating) {
      return;
    }
    const i: number = this.indexOfMessage(m);
    if (i < 0) {
      return;
    }
    this.inputText = m.content;
    const list: ChatMessage[] = [];
    for (let k = 0; k < i; k++) {
      list.push(this.messages[k]);
    }
    this.messages = list;
    this.msgCount = list.length;
    this.saveCurrentSession();
  }

  private deleteMessage(m: ChatMessage): void {
    const i: number = this.indexOfMessage(m);
    if (i < 0) {
      return;
    }
    const list: ChatMessage[] = [];
    for (let k = 0; k < this.messages.length; k++) {
      if (k !== i) {
        list.push(this.messages[k]);
      }
    }
    this.messages = list;
    this.msgCount = list.length;
    this.saveCurrentSession();
  }

  private copyMessage(m: ChatMessage): void {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, m.content);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.toast('已复制到剪贴板');
    } catch (e) {
      this.toast('复制失败');
    }
  }

  private toggleReasoning(m: ChatMessage): void {
    m.reasoningExpanded = !m.reasoningExpanded;
    Logger.info('reasoning toggled: ' + m.id + ' -> ' + m.reasoningExpanded
      + ' (len=' + m.reasoning.length + ')');
    this.msgTick = this.msgTick + 1;
    this.saveCurrentSession();
  }

  private openLink(url: string): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      }).catch((e: BusinessError) => {
        this.toast('无法打开链接');
      });
    } catch (e) {
      this.toast('无法打开链接');
    }
  }

  /* ===================== 设置与网络 ===================== */

  private saveSettings(): void {
    this.settings.params = this.params;
    StorageService.saveSettings(this.settings);
    const list: ProviderConfig[] = this.settings.providers;
    for (let i = 0; i < list.length; i++) {
      const pr: ProviderConfig = list[i];
      if (pr.id === this.settings.activeProviderId) {
        const k: string = pr.apiKey;
        Logger.info('settings saved: provider=' + pr.id + ' model=' + this.settings.activeModel
          + ' base=' + pr.baseUrl
          + ' key=' + (k.length === 0 ? '(empty)' : (k.substring(0, 6) + '...len' + k.length)));
        return;
      }
    }
    Logger.info('settings saved: no active provider matched');
  }

  private switchModel(providerId: string, model: string): void {
    this.settings.activeProviderId = providerId;
    this.settings.activeModel = model;
    this.saveSettings();
    this.showModelSheet = false;
    this.toast('已切换到 ' + model);
  }

  private async refreshBalance(silent: boolean): Promise<void> {
    const p: ProviderConfig = this.activeProvider();
    if (!p.supportsBalance) {
      Logger.info('balance skipped: provider has no balance api');
      return;
    }
    if (p.apiKey.length === 0) {
      Logger.info('balance skipped: api key empty');
      return;
    }
    this.balanceLoading = true;
    Logger.info('balance request -> ' + p.baseUrl + '/user/balance');
    try {
      const provider = ProviderFactory.create(p.protocol);
      const b: BalanceInfo = await provider.fetchBalance(p);
      this.balance = b;
      if (b.error.length > 0) {
        Logger.warn('balance failed: ' + b.error);
      } else {
        Logger.info('balance ok: ' + b.currency + ' ' + b.totalBalance
          + ' (granted ' + b.grantedBalance + ' toppedUp ' + b.toppedUpBalance
          + ') available=' + b.isAvailable);
      }
      if (!silent && b.error.length > 0) {
        this.toast(b.error);
      }
    } catch (e) {
      const err = e as Error;
      Logger.warn('balance failed: ' + err.message);
    }
    this.balanceLoading = false;
  }

  private async refreshModels(providerId: string): Promise<void> {
    const list: ProviderConfig[] = this.settings.providers;
    let target: ProviderConfig | null = null;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === providerId) {
        target = list[i];
      }
    }
    if (target === null) {
      return;
    }
    if (target.apiKey.length === 0) {
      this.modelError = '请先填写 API Key';
      return;
    }
    this.modelLoading = true;
    this.modelError = '';
    try {
      const provider = ProviderFactory.create(target.protocol);
      const models = await provider.fetchModels(target);
      const ids: string[] = [];
      for (let i = 0; i < models.length; i++) {
        ids.push(models[i].id);
      }
      if (ids.length > 0) {
        target.models = ids;
        this.saveSettings();
        this.toast('已获取 ' + ids.length + ' 个模型');
      } else {
        this.modelError = '该端点未返回模型列表';
      }
    } catch (e) {
      const err = e as Error;
      this.modelError = err.message;
    }
    this.modelLoading = false;
  }

  private async pickImage(): Promise<void> {
    try {
      const atts: Attachment[] = await ImagePicker.pick(3);
      if (atts.length > 0) {
        const list: Attachment[] = [];
        for (let i = 0; i < this.attachments.length; i++) {
          list.push(this.attachments[i]);
        }
        for (let i = 0; i < atts.length; i++) {
          list.push(atts[i]);
        }
        this.attachments = list;
      }
    } catch (e) {
      this.toast('未选择图片');
    }
  }

  /* ===================== 语音 ===================== */

  /** 语音识别期间，把中间结果拼在开始识别时的已有文本之后 */
  private speechMerge(partial: string): string {
    const base: string = this.speechBase;
    if (base.length === 0) {
      return partial;
    }
    const sep: string = base.endsWith(' ') || base.endsWith('\n') ? '' : ' ';
    return base + sep + partial;
  }

  /** 点击麦克风：未在识别则开始，正在识别则结束并等待最终结果 */
  private async toggleMic(): Promise<void> {
    if (this.listening) {
      SpeechService.finishListening();
      this.listening = false;
      this.micLevel = 0;
      Logger.info('speech: user finished listening');
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const granted: boolean = await SpeechService.ensureMicPermission(ctx);
      if (!granted) {
        this.toast('需要麦克风权限才能语音输入');
        return;
      }
    } catch (e) {
      this.toast('无法获取麦克风权限');
      return;
    }
    this.speechBase = this.inputText;
    this.listening = true;
    this.micLevel = 0;
    const handlers: AsrHandlers = {
      onPartial: (t: string) => {
        this.inputText = this.speechMerge(t);
      },
      onFinal: (t: string) => {
        this.inputText = this.speechMerge(t);
        this.listening = false;
        this.micLevel = 0;
        Logger.info('speech final: ' + t.length + ' chars');
        if (this.settings.speechAutoSend && this.inputText.trim().length > 0) {
          this.doSend();
        }
      },
      onVolume: (v: number) => {
        this.micLevel = v;
      },
      onError: (m: string) => {
        this.listening = false;
        this.micLevel = 0;
        this.toast(m);
      }
    };
    await SpeechService.startListening(this.settings.speechLanguage, handlers);
  }

  /** 朗读 / 停止朗读某条助手消息 */
  private speakOrStop(m: ChatMessage): void {
    if (this.speakingId === m.id) {
      SpeechService.stopSpeaking();
      this.speakingId = '';
      return;
    }
    const targetId: string = m.id;
    this.speakingId = targetId;
    const handlers: TtsHandlers = {
      onStart: (id: string) => {},
      onDone: (id: string) => {
        if (this.speakingId === targetId) {
          this.speakingId = '';
        }
      },
      onError: (msg: string) => {
        if (this.speakingId === targetId) {
          this.speakingId = '';
        }
        this.toast(msg);
      }
    };
    SpeechService.speak(m.content, this.settings.ttsSpeed, this.settings.ttsPerson, handlers);
  }

  /* ===================== 搜索与导出 ===================== */

  /** 搜索词变化：重算正文命中 */
  private onSearchKeyword(): void {
    const kw: string = this.searchKeyword.trim();
    if (kw.length === 0) {
      this.searchHits = [];
      return;
    }
    this.searchHits = StorageService.searchSessions(StorageService.loadIndex(), kw, 8);
    Logger.info('search "' + kw + '" -> ' + this.searchHits.length + ' sessions');
  }

  private copyPlain(text: string): void {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(data);
    } catch (e) {
      Logger.warn('clipboard write failed');
    }
  }

  private exportStamp(): string {
    const d: Date = new Date();
    const p = (n: number): string => (n < 10 ? '0' + n.toString() : n.toString());
    return d.getFullYear().toString() + p(d.getMonth() + 1) + p(d.getDate())
      + '-' + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
  }

  /** 导出单个会话为 Markdown */
  private exportSessionMd(id: string): void {
    const idx: SessionIndexFile = StorageService.loadIndex();
    const ids: string[] = [id];
    const md: string = StorageService.exportMarkdown(idx, ids, this.settings.showReasoning);
    const path: string = StorageService.writeExport('nova-ai-' + this.exportStamp() + '.md', md);
    if (path.length === 0) {
      this.toast('导出失败，请检查存储权限');
      return;
    }
    this.copyPlain(md);
    this.toast('已导出 ' + md.length + ' 字符到 export 目录，并复制到剪贴板');
  }

  /** 导出全部会话为 Markdown */
  private exportAllMd(): void {
    const idx: SessionIndexFile = StorageService.loadIndex();
    const none: string[] = [];
    const md: string = StorageService.exportMarkdown(idx, none, this.settings.showReasoning);
    const path: string = StorageService.writeExport('nova-ai-all-' + this.exportStamp() + '.md', md);
    if (path.length === 0) {
      this.toast('导出失败，请检查存储权限');
      return;
    }
    this.copyPlain(md);
    Logger.info('export all: ' + idx.entries.length + ' sessions, ' + md.length + ' chars -> ' + path);
    this.toast('已导出 ' + idx.entries.length + ' 个会话到 export 目录，并复制到剪贴板');
  }

  private exportAll(): void {
    const idx: SessionIndexFile = StorageService.loadIndex();
    const json: string = StorageService.exportAll(idx);
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, json);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.toast('已复制 ' + json.length + ' 字符的会话数据到剪贴板');
    } catch (e) {
      this.toast('导出失败');
    }
  }

  private clearAll(): void {
    StorageService.deleteAllSessions();
    this.sessions = [];
    this.messages = [];
    this.msgCount = 0;
    this.activeSessionId = '';
    this.createSession(false);
    this.toast('已清空全部会话');
  }

  /* ===================== UI ===================== */

  build() {
    Stack() {
      Row() {
        if (this.isWide) {
          Sidebar({
            sessions: this.sessions,
            activeId: this.activeSessionId,
            dark: this.isDarkNow(),
            isWide: true,
            balanceText: this.balanceText(),
            balanceOk: this.balance.isAvailable,
            providerName: this.activeProvider().name,
            keyword: this.searchKeyword,
            searchHits: this.searchHits,
            onSelect: (id: string) => this.selectSession(id),
            onExportSession: (id: string) => this.exportSessionMd(id),
            onExportAll: () => this.exportAllMd(),
            onNew: () => this.createSession(true),
            onDelete: (id: string) => this.deleteSession(id),
            onRename: (m: SessionMeta) => this.beginRename(m),
            onPin: (m: SessionMeta) => this.togglePin(m),
            onOpenSettings: () => {
              this.route = 'settings';
            },
            onRefreshBalance: () => {
              this.refreshBalance(false);
            }
          })
            .width(300)
            .height('100%')
        }

        Column() {
          this.appBar()
          if (this.route === 'settings') {
            SettingsPage({
              settings: this.settings,
              params: this.params,
              dark: this.isDarkNow(),
              isWide: this.isWide,
              onClose: () => {
                this.route = 'chat';
              },
              onSave: () => this.saveSettings(),
              onAddProvider: () => this.addProvider(),
              onDeleteProvider: (id: string) => this.removeProvider(id),
              onExport: () => this.exportAll(),
              onClearAll: () => this.clearAll(),
              onTestProvider: (id: string) => this.testProvider(id),
              searchTesting: this.searchTesting,
              searchTest: this.searchTest,
              onTestSearch: () => {
                this.runSearchTest();
              },
              onOpenLink: (u: string) => this.openLink(u)
            })
              .layoutWeight(1)
          } else if (this.route === 'fim') {
            FimPage({
              dark: this.isDarkNow(),
              isWide: this.isWide,
              provider: this.activeProvider(),
              model: this.settings.activeModel,
              params: this.pendingParams(),
              onClose: () => {
                this.route = 'chat';
              }
            })
              .layoutWeight(1)
          } else {
            Column() {
              MessageList({
                messages: this.messages,
                dark: this.isDarkNow(),
                isWide: this.isWide,
                generating: this.generating,
                fontSize: this.settings.fontSize,
                showStats: this.settings.showTokenStats,
                showCost: this.settings.showCost,
                showReasoning: this.settings.showReasoning,
                showSteps: this.settings.showSteps,
                processDefaultOpen: this.settings.processDefaultOpen,
                sourcesDefaultCollapsed: this.settings.sourcesDefaultCollapsed,
                providerName: this.activeProvider().name,
                modelName: this.settings.activeModel,
                streamTick: this.streamTick,
                count: this.msgCount,
                speechEnabled: this.settings.speechEnabled,
                speakingId: this.speakingId,
                msgTick: this.msgTick,
                onSpeak: (m: ChatMessage) => this.speakOrStop(m),
                onCopy: (m: ChatMessage) => this.copyMessage(m),
                onRegenerate: (m: ChatMessage) => this.regenerate(m),
                onDelete: (m: ChatMessage) => this.deleteMessage(m),
                onEdit: (m: ChatMessage) => this.editMessage(m),
                onOpenLink: (u: string) => this.openLink(u),
                onToggleReasoning: (m: ChatMessage) => this.toggleReasoning(m),
                onPickSuggestion: (p: string) => {
                  this.inputText = p;
                  this.doSend();
                }
              })
                .layoutWeight(1)

              Composer({
                text: this.inputText,
                attachments: this.attachments,
                dark: this.isDarkNow(),
                generating: this.generating,
                isWide: this.isWide,
                params: this.params,
                modelName: this.settings.activeModel,
                canSend: this.inputText.trim().length > 0 || this.attachments.length > 0,
                speechEnabled: this.settings.speechEnabled,
                listening: this.listening,
                micLevel: this.micLevel,
                onSend: () => this.doSend(),
                onToggleMic: () => {
                  this.toggleMic();
                },
                onStop: () => this.stopGenerating(),
                onPickImage: () => this.pickImage(),
                onRemoveAttachment: (id: string) => this.removeAttachment(id),
                onOpenModelPicker: () => {
                  this.showModelSheet = true;
                },
                onOpenParams: () => {
                  this.route = 'settings';
                },
                onToggleThinking: () => this.cycleThinking(),
                onToggleTools: () => {
                  this.params.enableTools = !this.params.enableTools;
                  this.saveSettings();
                },
                webSearch: this.params.webSearch,
                searching: this.searching,
                onToggleWebSearch: () => {
                  this.params.webSearch = !this.params.webSearch;
                  this.saveSettings();
                  this.toast(this.params.webSearch ? '已开启联网搜索' : '已关闭联网搜索');
                }
              })
            }
            .layoutWeight(1)
            .width('100%')
          }
        }
        .layoutWeight(1)
        .height('100%')
        .backgroundColor(this.pal().bg)
      }
      .width('100%')
      .height('100%')

      // 抽屉遮罩（窄屏）
      if (!this.isWide && this.drawerOpen) {
        Row() {
          Sidebar({
            sessions: this.sessions,
            activeId: this.activeSessionId,
            dark: this.isDarkNow(),
            isWide: false,
            balanceText: this.balanceText(),
            balanceOk: this.balance.isAvailable,
            providerName: this.activeProvider().name,
            keyword: this.searchKeyword,
            searchHits: this.searchHits,
            onSelect: (id: string) => {
              this.drawerOpen = false;
              this.selectSession(id);
            },
            onExportSession: (id: string) => this.exportSessionMd(id),
            onExportAll: () => this.exportAllMd(),
            onNew: () => this.createSession(true),
            onDelete: (id: string) => this.deleteSession(id),
            onRename: (m: SessionMeta) => this.beginRename(m),
            onPin: (m: SessionMeta) => this.togglePin(m),
            onOpenSettings: () => {
              this.drawerOpen = false;
              this.route = 'settings';
            },
            onRefreshBalance: () => {
              this.refreshBalance(false);
            },
            onClose: () => {
              this.drawerOpen = false;
            }
          })
            .width(288)
            .height('100%')
            .shadow({ radius: 24, color: this.pal().shadow, offsetX: 4, offsetY: 0 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
      }

      // 重命名浮层
      if (this.showRename) {
        this.renameOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().bg)
    .bindSheet($$this.showModelSheet, this.modelSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      backgroundColor: this.pal().elevated,
      showClose: false,
      dragBar: true,
      onDisappear: () => {
        this.showModelSheet = false;
      }
    })
  }

  private balanceText(): string {
    if (this.balanceLoading) {
      return '查询中…';
    }
    if (this.balance.error.length > 0) {
      return '查询失败';
    }
    if (this.balance.fetchedAt === 0) {
      return '';
    }
    return '¥'.length > 0 && this.balance.currency === 'CNY'
      ? ('¥ ' + this.balance.totalBalance)
      : (this.balance.currency + ' ' + this.balance.totalBalance);
  }

  private removeAttachment(id: string): void {
    const list: Attachment[] = [];
    for (let i = 0; i < this.attachments.length; i++) {
      if (this.attachments[i].id !== id) {
        list.push(this.attachments[i]);
      }
    }
    this.attachments = list;
  }

  private cycleThinking(): void {
    const order: string[] = ['auto', 'off', 'low', 'high', 'max'];
    let idx: number = order.indexOf(this.params.thinking);
    idx = (idx + 1) % order.length;
    this.params.thinking = order[idx];
    this.saveSettings();
    this.toast('思考强度：' + order[idx]);
  }

  private beginRename(m: SessionMeta): void {
    this.renameTargetId = m.id;
    this.renameText = m.title;
    this.showRename = true;
  }

  private addProvider(): void {
    const p: ProviderConfig = ProviderFactory.customCompatible('自定义服务商', 'https://api.example.com/v1', ['model-name']);
    const list: ProviderConfig[] = [];
    for (let i = 0; i < this.settings.providers.length; i++) {
      list.push(this.settings.providers[i]);
    }
    list.push(p);
    this.settings.providers = list;
    this.saveSettings();
    this.toast('已添加，请填写 Base URL 与 API Key');
  }

  private removeProvider(id: string): void {
    const list: ProviderConfig[] = [];
    for (let i = 0; i < this.settings.providers.length; i++) {
      if (this.settings.providers[i].id !== id) {
        list.push(this.settings.providers[i]);
      }
    }
    this.settings.providers = list;
    if (this.settings.activeProviderId === id && list.length > 0) {
      this.settings.activeProviderId = list[0].id;
      this.settings.activeModel = list[0].models.length > 0 ? list[0].models[0] : '';
    }
    this.saveSettings();
  }

  private async testProvider(id: string): Promise<void> {
    const list: ProviderConfig[] = this.settings.providers;
    let target: ProviderConfig | null = null;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        target = list[i];
      }
    }
    if (target === null) {
      return;
    }
    if (target.apiKey.length === 0) {
      this.toast('请先填写 API Key');
      return;
    }
    this.modelLoading = true;
    try {
      const provider = ProviderFactory.create(target.protocol);
      const models = await provider.fetchModels(target);
      if (models.length > 0) {
        const ids: string[] = [];
        for (let i = 0; i < models.length; i++) {
          ids.push(models[i].id);
        }
        target.models = ids;
        this.saveSettings();
        this.toast('连接成功，可用模型 ' + ids.length + ' 个');
      } else {
        this.toast('连接成功');
      }
    } catch (e) {
      const err = e as Error;
      this.toast('连接失败：' + Utils.ellipsis(err.message, 60));
    }
    this.modelLoading = false;
  }

  /* ===================== 局部 UI ===================== */

  @Builder
  appBar() {
    Row({ space: 6 }) {
      if (!this.isWide) {
        IconBtn({
          icon: $r('app.media.ic_menu'), iconSize: 19, tint: this.pal().text,
          onTap: () => {
            this.drawerOpen = true;
          }
        })
      }

      Column({ space: 1 }) {
        Text(this.currentTitle())
          .fontSize(Font.base)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.activeProvider().name + ' · ' + (this.generating ? '生成中…' : '就绪'))
          .fontSize(Font.xs)
          .fontColor(this.generating ? this.pal().accent : this.pal().textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.route === 'chat') {
        IconBtn({
          icon: $r('app.media.ic_terminal'), iconSize: 18, tint: this.pal().textSecondary,
          onTap: () => {
            this.route = 'fim';
          }
        })
        IconBtn({
          icon: $r('app.media.ic_layers'), iconSize: 18, tint: this.pal().textSecondary,
          onTap: () => {
            this.showModelSheet = true;
          }
        })
        IconBtn({
          icon: $r('app.media.ic_newchat'), iconSize: 18, tint: this.pal().textSecondary,
          onTap: () => this.createSession(true)
        })
      }
      if (this.route === 'chat' || this.route === 'fim') {
        IconBtn({
          icon: $r('app.media.ic_settings'), iconSize: 18, tint: this.pal().textSecondary,
          onTap: () => {
            this.route = 'settings';
          }
        })
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 4, right: 6 })
    .backgroundColor(this.pal().bg)
  }

  private currentTitle(): string {
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === this.activeSessionId) {
        return this.sessions[i].title;
      }
    }
    return '新对话';
  }

  @Builder
  modelSheet() {
    Column() {
      ModelPicker({
        providers: this.settings.providers,
        activeProviderId: this.settings.activeProviderId,
        activeModel: this.settings.activeModel,
        dark: this.isDarkNow(),
        loading: this.modelLoading,
        errorText: this.modelError,
        onPick: (pid: string, m: string) => this.switchModel(pid, m),
        onRefreshModels: (pid: string) => {
          this.refreshModels(pid);
        },
        onClose: () => {
          this.showModelSheet = false;
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  renameOverlay() {
    Column() {
      Column({ space: 12 }) {
        Text('重命名会话')
          .fontSize(Font.md)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().text)
        TextInput({ text: this.renameText, placeholder: '输入新的标题' })
          .placeholderColor(this.pal().textTertiary)
          .fontColor(this.pal().text)
          .fontSize(Font.sm)
          .backgroundColor(this.pal().surfaceAlt)
          .borderRadius(Dim.r10)
          .height(44)
          .onChange((v: string) => {
            this.renameText = v;
          })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .backgroundColor(this.pal().surfaceAlt)
            .fontColor(this.pal().text)
            .fontSize(Font.sm)
            .onClick(() => {
              this.showRename = false;
            })
          Button('保存')
            .layoutWeight(1)
            .height(40)
            .backgroundColor(this.pal().accent)
            .fontColor('#FFFFFF')
            .fontSize(Font.sm)
            .onClick(() => {
              this.renameSession(this.renameTargetId, this.renameText);
              this.showRename = false;
            })
        }
        .width('100%')
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(18)
      .backgroundColor(this.pal().elevated)
      .borderRadius(Dim.r18)
      .border({ width: 1, color: this.pal().border })
      .shadow({ radius: 28, color: this.pal().shadow, offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pal().scrim)
    .onClick(() => {
      this.showRename = false;
    })
  }
}

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { AppSettings, BalanceInfo, ChatMessage, InferenceParams, ProviderConfig, SearchHit, Session, SessionMeta, SessionIndexEntry, SessionIndexFile, Usage } from '../model/Types';
import { Role } from '../common/Constants';
import { ChatMessage as CM } from '../model/Types';
import { Logger } from '../common/Logger';
import { Utils } from '../common/Utils';
import { ProviderFactory } from '../provider/ProviderFactory';
import { Constants } from '../common/Constants';

/**
 * 本地持久化：设置写入 config/settings.json，会话写入 sessions/*.json
 */
export class StorageService {
  private static root: string = '';
  private static ready: boolean = false;

  static init(context: common.Context): void {
    try {
      StorageService.root = context.filesDir;
      const cfgDir: string = StorageService.root + '/config';
      const sesDir: string = StorageService.root + '/sessions';
      if (!fs.accessSync(cfgDir)) {
        fs.mkdirSync(cfgDir, true);
      }
      if (!fs.accessSync(sesDir)) {
        fs.mkdirSync(sesDir, true);
      }
      StorageService.ready = true;
      Logger.info('storage ready at ' + StorageService.root);
    } catch (e) {
      const err = e as Error;
      Logger.error('storage init failed: ' + err.message);
      StorageService.ready = false;
    }
  }

  static isReady(): boolean {
    return StorageService.ready;
  }

  private static readText(path: string): string {
    if (!StorageService.ready || !fs.accessSync(path)) {
      return '';
    }
    let fd: fs.File | null = null;
    try {
      fd = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat: fs.Stat = fs.statSync(path);
      if (stat.size <= 0) {
        return '';
      }
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      const n: number = fs.readSync(fd.fd, buf);
      if (n <= 0) {
        return '';
      }
      const dec: util.TextDecoder = util.TextDecoder.create('utf-8');
      return dec.decodeToString(new Uint8Array(buf.slice(0, n)));
    } catch (e) {
      const err = e as Error;
      Logger.warn('read failed ' + path + ': ' + err.message);
      return '';
    } finally {
      if (fd !== null) {
        try {
          fs.closeSync(fd);
        } catch (e2) {
        }
      }
    }
  }

  private static writeText(path: string, text: string): boolean {
    if (!StorageService.ready) {
      return false;
    }
    let fd: fs.File | null = null;
    try {
      fd = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(fd.fd, text);
      return true;
    } catch (e) {
      const err = e as Error;
      Logger.error('write failed ' + path + ': ' + err.message);
      return false;
    } finally {
      if (fd !== null) {
        try {
          fs.closeSync(fd);
        } catch (e2) {
        }
      }
    }
  }

  private static removeFile(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      Logger.warn('unlink failed ' + path);
    }
  }

  private static settingsPath(): string {
    return StorageService.root + '/config/settings.json';
  }

  private static indexPath(): string {
    return StorageService.root + '/sessions/index.json';
  }

  private static sessionPath(id: string): string {
    return StorageService.root + '/sessions/' + id + '.json';
  }

  /* ===================== 设置 ===================== */

  static defaultSettings(): AppSettings {
    const s: AppSettings = new AppSettings();
    s.providers = ProviderFactory.presets();
    s.activeProviderId = 'deepseek';
    s.activeModel = 'deepseek-flash';
    s.params = new InferenceParams();
    s.systemPrompt = Constants.DEFAULT_SYSTEM_PROMPT;
    return s;
  }

  static loadSettings(): AppSettings {
    const text: string = StorageService.readText(StorageService.settingsPath());
    const def: AppSettings = StorageService.defaultSettings();
    if (text.length === 0) {
      return def;
    }
    const parsed: AppSettings | null = Utils.tryParse<AppSettings | null>(text, null);
    if (parsed === null || parsed === undefined) {
      return def;
    }
    return StorageService.mergeSettings(def, parsed);
  }

  /** 逐字段合并，保证新增字段有默认值，同时补齐内置服务商 */
  private static mergeSettings(def: AppSettings, saved: AppSettings): AppSettings {
    const out: AppSettings = def;
    if (saved.themeMode !== undefined && saved.themeMode !== null) {
      out.themeMode = saved.themeMode;
    }
    if (saved.followSystemDark !== undefined) {
      out.followSystemDark = saved.followSystemDark;
    }
    if (saved.systemPrompt !== undefined && saved.systemPrompt !== null) {
      out.systemPrompt = saved.systemPrompt;
    }
    if (saved.activeProviderId !== undefined && saved.activeProviderId !== null && saved.activeProviderId.length > 0) {
      out.activeProviderId = saved.activeProviderId;
    }
    if (saved.activeModel !== undefined && saved.activeModel !== null && saved.activeModel.length > 0) {
      out.activeModel = saved.activeModel;
    }
    if (saved.sendOnEnter !== undefined) {
      out.sendOnEnter = saved.sendOnEnter;
    }
    if (saved.showTokenStats !== undefined) {
      out.showTokenStats = saved.showTokenStats;
    }
    if (saved.showCost !== undefined) {
      out.showCost = saved.showCost;
    }
    if (saved.fontSize !== undefined && saved.fontSize > 0) {
      out.fontSize = saved.fontSize;
    }
    if (saved.language !== undefined && saved.language !== null) {
      out.language = saved.language;
    }
    if (saved.hapticFeedback !== undefined) {
      out.hapticFeedback = saved.hapticFeedback;
    }
    if (saved.autoTitle !== undefined) {
      out.autoTitle = saved.autoTitle;
    }
    if (saved.streamOutput !== undefined) {
      out.streamOutput = saved.streamOutput;
    }
    if (saved.showReasoning !== undefined) {
      out.showReasoning = saved.showReasoning;
    }
    // 推理参数
    const dp: InferenceParams = new InferenceParams();
    const sp: InferenceParams | undefined = saved.params;
    if (sp !== undefined && sp !== null) {
      if (sp.temperature !== undefined) {
        dp.temperature = sp.temperature;
      }
      if (sp.topP !== undefined) {
        dp.topP = sp.topP;
      }
      if (sp.maxTokens !== undefined) {
        dp.maxTokens = sp.maxTokens;
      }
      if (sp.frequencyPenalty !== undefined) {
        dp.frequencyPenalty = sp.frequencyPenalty;
      }
      if (sp.presencePenalty !== undefined) {
        dp.presencePenalty = sp.presencePenalty;
      }
      if (sp.stop !== undefined && sp.stop !== null) {
        dp.stop = sp.stop;
      }
      if (sp.thinking !== undefined && sp.thinking !== null) {
        dp.thinking = sp.thinking;
      }
      if (sp.jsonMode !== undefined) {
        dp.jsonMode = sp.jsonMode;
      }
      if (sp.logprobs !== undefined) {
        dp.logprobs = sp.logprobs;
      }
      if (sp.topLogprobs !== undefined) {
        dp.topLogprobs = sp.topLogprobs;
      }
      if (sp.userId !== undefined && sp.userId !== null) {
        dp.userId = sp.userId;
      }
      if (sp.stream !== undefined) {
        dp.stream = sp.stream;
      }
      if (sp.enableTools !== undefined) {
        dp.enableTools = sp.enableTools;
      }
      if (sp.webSearch !== undefined) {
        dp.webSearch = sp.webSearch;
      }
    }
    out.params = dp;

    /* ---------- 语音 ---------- */
    if (saved.speechEnabled !== undefined) {
      out.speechEnabled = saved.speechEnabled;
    }
    if (saved.ttsAutoRead !== undefined) {
      out.ttsAutoRead = saved.ttsAutoRead;
    }
    if (saved.ttsSpeed !== undefined && saved.ttsSpeed > 0) {
      out.ttsSpeed = saved.ttsSpeed;
    }
    if (saved.ttsPerson !== undefined) {
      out.ttsPerson = saved.ttsPerson;
    }
    if (saved.speechLanguage !== undefined && saved.speechLanguage !== null
      && saved.speechLanguage.length > 0) {
      out.speechLanguage = saved.speechLanguage;
    }
    if (saved.speechAutoSend !== undefined) {
      out.speechAutoSend = saved.speechAutoSend;
    }

    /* ---------- 联网搜索 ---------- */
    if (saved.webSearchBackend !== undefined && saved.webSearchBackend !== null
      && saved.webSearchBackend.length > 0) {
      out.webSearchBackend = saved.webSearchBackend;
    }
    if (saved.webSearchEndpoint !== undefined && saved.webSearchEndpoint !== null) {
      out.webSearchEndpoint = saved.webSearchEndpoint;
    }
    if (saved.webSearchMax !== undefined && saved.webSearchMax > 0) {
      out.webSearchMax = saved.webSearchMax;
    }
    if (saved.webSearchShowSources !== undefined) {
      out.webSearchShowSources = saved.webSearchShowSources;
    }
    if (saved.webSearchRegion !== undefined && saved.webSearchRegion !== null) {
      out.webSearchRegion = saved.webSearchRegion;
    }
    if (saved.searchHealth !== undefined && saved.searchHealth !== null) {
      out.searchHealth = saved.searchHealth;
    }
    if (saved.showSteps !== undefined) {
      out.showSteps = saved.showSteps;
    }
    if (saved.processDefaultOpen !== undefined) {
      out.processDefaultOpen = saved.processDefaultOpen;
    }
    if (saved.sourcesDefaultCollapsed !== undefined) {
      out.sourcesDefaultCollapsed = saved.sourcesDefaultCollapsed;
    }

    // 服务商：以保存的为准，但补齐缺失的内置服务商
    const savedProviders: ProviderConfig[] | undefined = saved.providers;
    if (savedProviders !== undefined && savedProviders !== null) {
      const merged: ProviderConfig[] = [];
      const builtins: ProviderConfig[] = ProviderFactory.presets();
      const usedIds: string[] = [];
      for (let i = 0; i < savedProviders.length; i++) {
        const p: ProviderConfig = StorageService.normalizeProvider(savedProviders[i]);
        merged.push(p);
        usedIds.push(p.id);
      }
      for (let i = 0; i < builtins.length; i++) {
        if (usedIds.indexOf(builtins[i].id) < 0) {
          merged.push(builtins[i]);
        }
      }
      out.providers = merged;
    }
    if (out.activeProviderId.length === 0 && out.providers.length > 0) {
      out.activeProviderId = out.providers[0].id;
    }
    return out;
  }

  private static normalizeProvider(p: ProviderConfig): ProviderConfig {
    const out: ProviderConfig = new ProviderConfig();
    out.id = p.id !== undefined && p.id !== null ? p.id : Utils.uid('p');
    out.name = p.name !== undefined && p.name !== null ? p.name : '未命名';
    out.flavor = p.flavor !== undefined && p.flavor !== null ? p.flavor : 'generic';
    out.protocol = p.protocol !== undefined && p.protocol !== null ? p.protocol : 'chat_completions';
    out.baseUrl = p.baseUrl !== undefined && p.baseUrl !== null ? p.baseUrl : '';
    out.betaBaseUrl = p.betaBaseUrl !== undefined && p.betaBaseUrl !== null ? p.betaBaseUrl : '';
    out.apiKey = p.apiKey !== undefined && p.apiKey !== null ? p.apiKey : '';
    out.extraHeaders = p.extraHeaders !== undefined && p.extraHeaders !== null ? p.extraHeaders : '';
    out.models = (p.models !== undefined && p.models !== null) ? p.models : [];
    out.builtin = p.builtin === true;
    out.enabled = p.enabled !== false;
    out.supportsBalance = p.supportsBalance === true;
    out.supportsModelList = p.supportsModelList !== false;
    out.brandColor = p.brandColor !== undefined && p.brandColor !== null ? p.brandColor : '#4C6EF5';
    out.note = p.note !== undefined && p.note !== null ? p.note : '';
    return out;
  }

  static saveSettings(s: AppSettings): void {
    StorageService.writeText(StorageService.settingsPath(), JSON.stringify(s));
  }

  /* ===================== 会话 ===================== */

  static loadIndex(): SessionIndexFile {
    const empty: SessionIndexFile = { version: 1, activeId: '', entries: [] };
    const text: string = StorageService.readText(StorageService.indexPath());
    if (text.length === 0) {
      return empty;
    }
    const parsed: SessionIndexFile | null = Utils.tryParse<SessionIndexFile | null>(text, null);
    if (parsed === null || parsed === undefined || parsed.entries === undefined) {
      return empty;
    }
    return parsed;
  }

  static saveIndex(idx: SessionIndexFile): void {
    StorageService.writeText(StorageService.indexPath(), JSON.stringify(idx));
  }

  static saveSession(session: Session): void {
    StorageService.writeText(StorageService.sessionPath(session.meta.id), JSON.stringify(session));
  }

  static loadSession(id: string): Session | null {
    const text: string = StorageService.readText(StorageService.sessionPath(id));
    if (text.length === 0) {
      return null;
    }
    const s: Session | null = Utils.tryParse<Session | null>(text, null);
    if (s === null || s === undefined) {
      return null;
    }
    if (s.messages === undefined || s.messages === null) {
      s.messages = [];
    }
    // 旧版本存档缺少后加的字段，这里统一补齐，避免读取到 undefined 后崩溃
    for (let i = 0; i < s.messages.length; i++) {
      const m: ChatMessage = s.messages[i];
      if (m.content === undefined || m.content === null) { m.content = ''; }
      if (m.reasoning === undefined || m.reasoning === null) { m.reasoning = ''; }
      if (m.error === undefined || m.error === null) { m.error = ''; }
      if (m.finishReason === undefined || m.finishReason === null) { m.finishReason = ''; }
      if (m.toolCalls === undefined || m.toolCalls === null) { m.toolCalls = []; }
      if (m.attachments === undefined || m.attachments === null) { m.attachments = []; }
      if (m.sources === undefined || m.sources === null) { m.sources = []; }
      if (m.searchNote === undefined || m.searchNote === null) { m.searchNote = ''; }
      if (m.steps === undefined || m.steps === null) { m.steps = []; }
      if (m.runStartedAt === undefined || m.runStartedAt === null) { m.runStartedAt = 0; }
      if (m.runMs === undefined || m.runMs === null) { m.runMs = 0; }
    }
    if (s.systemPrompt === undefined || s.systemPrompt === null) {
      s.systemPrompt = '';
    }
    return s;
  }

  static deleteSession(id: string): void {
    StorageService.removeFile(StorageService.sessionPath(id));
  }

  static deleteAllSessions(): void {
    StorageService.removeFile(StorageService.indexPath());
    try {
      const dir: string = StorageService.root + '/sessions';
      const names: string[] = fs.listFileSync(dir);
      for (let i = 0; i < names.length; i++) {
        if (names[i].endsWith('.json')) {
          StorageService.removeFile(dir + '/' + names[i]);
        }
      }
    } catch (e) {
      Logger.warn('clean sessions failed');
    }
  }

  /** 导出全部会话为 JSON 文本 */
  static exportAll(index: SessionIndexFile): string {
    const out: Session[] = [];
    for (let i = 0; i < index.entries.length; i++) {
      const s: Session | null = StorageService.loadSession(index.entries[i].id);
      if (s !== null) {
        out.push(s);
      }
    }
    return JSON.stringify(out);
  }

  /* ===================== 全文搜索 ===================== */

  /**
   * 在标题与消息正文里做不区分大小写的全文搜索。
   * 返回按命中次数降序、同次数按更新时间降序排列的结果。
   */
  static searchSessions(index: SessionIndexFile, keyword: string, limit: number): SearchHit[] {
    const kw: string = keyword.trim().toLowerCase();
    const hits: SearchHit[] = [];
    if (kw.length === 0) {
      return hits;
    }
    for (let i = 0; i < index.entries.length; i++) {
      const entry: SessionIndexEntry = index.entries[i];
      const session: Session | null = StorageService.loadSession(entry.id);
      if (session === null) {
        continue;
      }
      const hit: SearchHit = new SearchHit();
      hit.sessionId = entry.id;
      hit.title = entry.title;
      hit.updatedAt = entry.updatedAt;
      hit.inTitle = entry.title.toLowerCase().indexOf(kw) >= 0;
      if (hit.inTitle) {
        hit.matchCount = hit.matchCount + 1;
      }
      for (let m = 0; m < session.messages.length; m++) {
        const msg: ChatMessage = session.messages[m];
        const body: string = msg.role === Role.USER ? msg.content : (msg.content + ' ' + msg.reasoning);
        const lower: string = body.toLowerCase();
        let from: number = 0;
        let found: number = lower.indexOf(kw, from);
        while (found >= 0) {
          hit.matchCount = hit.matchCount + 1;
          if (hit.snippet.length === 0) {
            hit.snippet = StorageService.makeSnippet(body, found, kw.length);
            hit.role = msg.role;
          }
          from = found + kw.length;
          found = lower.indexOf(kw, from);
        }
      }
      if (hit.matchCount > 0) {
        hits.push(hit);
      }
    }
    hits.sort((a: SearchHit, b: SearchHit) => {
      if (b.matchCount !== a.matchCount) {
        return b.matchCount - a.matchCount;
      }
      return b.updatedAt - a.updatedAt;
    });
    return hits.slice(0, limit);
  }

  /** 取命中位置前后各若干字符，拼成带省略号的摘要 */
  private static makeSnippet(body: string, at: number, len: number): string {
    const before: number = 14;
    const after: number = 26;
    const flat: string = body.replace(/\s+/g, ' ').trim();
    // 原文被压缩过，位置需要按压缩后重新定位
    const kwRaw: string = body.substring(at, at + len);
    const pos: number = flat.toLowerCase().indexOf(kwRaw.toLowerCase());
    const p: number = pos >= 0 ? pos : 0;
    const s: number = Math.max(0, p - before);
    const e: number = Math.min(flat.length, p + len + after);
    let out: string = flat.substring(s, e);
    if (s > 0) {
      out = '…' + out;
    }
    if (e < flat.length) {
      out = out + '…';
    }
    return out;
  }

  /* ===================== 导出 ===================== */

  /** 单个会话转 Markdown */
  static sessionToMarkdown(s: Session, includeReasoning: boolean): string {
    const lines: string[] = [];
    const d: Date = new Date(s.meta.createdAt);
    lines.push('# ' + s.meta.title);
    lines.push('');
    lines.push('- 会话 ID：`' + s.meta.id + '`');
    lines.push('- 模型：`' + s.meta.model + '`');
    lines.push('- 创建时间：' + StorageService.stamp(d));
    lines.push('- 更新时间：' + StorageService.stamp(new Date(s.meta.updatedAt)));
    lines.push('- 消息数：' + s.messages.length.toString());
    lines.push('');
    if (s.systemPrompt.length > 0) {
      lines.push('> **系统提示词**：' + s.systemPrompt.replace(/\n/g, ' '));
      lines.push('');
    }
    lines.push('---');
    lines.push('');
    for (let i = 0; i < s.messages.length; i++) {
      const m: ChatMessage = s.messages[i];
      const who: string = m.role === Role.USER ? '🧑 用户' : (m.role === Role.ASSISTANT ? '🤖 助手' : ('🔧 ' + m.role));
      lines.push('## ' + who);
      lines.push('');
      lines.push('*' + StorageService.stamp(new Date(m.createdAt)) + '*');
      lines.push('');
      if (includeReasoning && m.reasoning.length > 0) {
        lines.push('<details><summary>思维链</summary>');
        lines.push('');
        lines.push(m.reasoning);
        lines.push('');
        lines.push('</details>');
        lines.push('');
      }
      lines.push(m.content.length > 0 ? m.content : '_（空）_');
      lines.push('');
      if (m.attachments.length > 0) {
        lines.push('附件：' + m.attachments.length.toString() + ' 个');
        lines.push('');
      }
      const u: Usage | null = m.usage;
      if (u !== null && (u.promptTokens > 0 || u.completionTokens > 0)) {
        lines.push('> tokens：输入 ' + u.promptTokens.toString() + ' / 输出 '
          + u.completionTokens.toString() + '（缓存命中 ' + u.cacheHitTokens.toString()
          + '，思考 ' + u.reasoningTokens.toString() + '）'
          + (m.latencyMs > 0 ? (' ｜ 首字 ' + m.ttftMs.toString() + 'ms ｜ 总 ' + m.latencyMs.toString() + 'ms') : ''));
        lines.push('');
      }
      lines.push('---');
      lines.push('');
    }
    return lines.join('\n');
  }

  /** 导出若干会话为 Markdown（不传 ids 表示全部） */
  static exportMarkdown(index: SessionIndexFile, ids: string[], includeReasoning: boolean): string {
    const parts: string[] = [];
    parts.push('# 星枢 AI 会话导出');
    parts.push('');
    parts.push('导出时间：' + StorageService.stamp(new Date()));
    parts.push('');
    const all: boolean = ids.length === 0;
    for (let i = 0; i < index.entries.length; i++) {
      const e: SessionIndexEntry = index.entries[i];
      if (!all && ids.indexOf(e.id) < 0) {
        continue;
      }
      const s: Session | null = StorageService.loadSession(e.id);
      if (s === null) {
        continue;
      }
      parts.push('');
      parts.push(StorageService.sessionToMarkdown(s, includeReasoning));
    }
    return parts.join('\n');
  }

  /**
   * 把文本写进沙箱导出目录，返回完整路径。
   * 之所以写沙箱而不是让用户选目录：不需要额外权限，且路径稳定可复现。
   */
  static writeExport(fileName: string, content: string): string {
    if (!StorageService.ready) {
      return '';
    }
    const dir: string = StorageService.root + '/export';
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const path: string = dir + '/' + fileName;
      StorageService.writeText(path, content);
      Logger.info('export written: ' + path + ' (' + content.length + ' bytes)');
      return path;
    } catch (e) {
      const err = e as Error;
      Logger.error('export failed: ' + err.message);
      return '';
    }
  }

  static exportDir(): string {
    return StorageService.root + '/export';
  }

  private static stamp(d: Date): string {
    const p = (n: number): string => (n < 10 ? '0' + n.toString() : n.toString());
    return d.getFullYear().toString() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate())
      + ' ' + p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
  }
}

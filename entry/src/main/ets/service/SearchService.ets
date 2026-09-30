import { HttpClient, HeaderMap } from '../net/HttpClient';
import { Logger } from '../common/Logger';
import { BackendHealth, SearchConfig, SearchOutcome, SearchResult, SearchTestResult } from '../model/Types';
import { Constants } from '../common/Constants';

/**
 * 联网搜索
 *
 * 三个后端都**不需要 API Key**：
 *  - bing        : cn.bing.com 的 RSS 输出（format=rss），返回干净 XML，最稳
 *  - duckduckgo  : lite.duckduckgo.com 的极简 HTML（部分网络不可达）
 *  - searxng     : 任意自建/公共 SearXNG 实例的 JSON 接口
 *
 * 搜索结果会被拼成一段带编号的上下文注入 system prompt，
 * 并在气泡下方以「来源」列表展示，便于核对。
 */
export class SearchService {
  private static readonly UA: string =
    'Mozilla/5.0 (HarmonyOS; NovaAI) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  static async search(cfg: SearchConfig, query: string): Promise<SearchOutcome> {
    const out: SearchOutcome = new SearchOutcome();
    out.preferred = cfg.backend;
    const q: string = query.trim();
    if (q.length === 0) {
      return out;
    }
    const order: string[] = SearchService.rankedOrder(cfg);
    Logger.info('search order=[' + order.join(' > ') + '] q="' + q.slice(0, 40)
      + '" max=' + cfg.maxResults + ' mkt=' + cfg.region);
    for (let i = 0; i < order.length; i++) {
      const b: string = order[i];
      const sub: SearchConfig = SearchService.withBackend(cfg, b);
      const t0: number = Date.now();
      try {
        const list: SearchResult[] = await SearchService.invoke(sub, b, q);
        if (list.length > 0) {
          SearchService.recordSuccess(b, Date.now() - t0);
          Logger.info('search ok via ' + b + ': ' + list.length + ' results in '
            + (Date.now() - t0) + 'ms');
          out.results = list;
          out.backend = b;
          // 用户显式指定了后端、但最终不是它 —— 说明发生了降级
          out.fellBack = cfg.backend !== 'auto' && cfg.backend.length > 0 && cfg.backend !== b;
          return out;
        }
        SearchService.recordFailure(b);
        Logger.warn('search ' + b + ' returned 0 results');
      } catch (e) {
        SearchService.recordFailure(b);
        Logger.warn('search ' + b + ' failed: ' + (e as Error).message);
      }
    }
    Logger.warn('search: all backends failed');
    return out;
  }

  /** 生成给用户看的路由说明；无异常时返回空串 */
  static noteOf(out: SearchOutcome): string {
    if (out.fellBack) {
      return '首选 ' + SearchService.backendLabel(out.preferred)
        + ' 不可用，本次改用 ' + SearchService.backendLabel(out.backend);
    }
    if (out.backend.length === 0) {
      return '联网搜索未成功，以下回答未使用搜索结果';
    }
    return '';
  }

  /* ------------------------- 后端健康度（进程内记忆） ------------------------- */

  private static health: BackendHealth[] = [];
  /** 失败后的冷却时长：期间不再尝试该后端 */
  private static readonly FAIL_COOLDOWN_MS: number = 3 * 60 * 1000;
  /** 健康度记忆的有效期：超过则视为未知，避免拿旧网络环境的结论误导排序 */
  private static readonly HEALTH_TTL_MS: number = 2 * 60 * 60 * 1000;

  private static healthOf(backend: string): BackendHealth {
    for (let i = 0; i < SearchService.health.length; i++) {
      if (SearchService.health[i].backend === backend) {
        return SearchService.health[i];
      }
    }
    const h: BackendHealth = new BackendHealth();
    h.backend = backend;
    SearchService.health.push(h);
    return h;
  }

  private static recordSuccess(backend: string, ms: number): void {
    const h: BackendHealth = SearchService.healthOf(backend);
    h.ok = true;
    h.ms = ms;
    h.failures = 0;
    h.cooldownUntil = 0;
    h.tested = true;
    h.checkedAt = Date.now();
  }

  private static recordFailure(backend: string): void {
    const h: BackendHealth = SearchService.healthOf(backend);
    h.ok = false;
    h.failures = h.failures + 1;
    h.tested = true;
    h.cooldownUntil = Date.now() + SearchService.FAIL_COOLDOWN_MS;
  }

  /** 供持久化与设置页展示 */
  static healthSnapshot(): BackendHealth[] {
    return SearchService.health;
  }

  /** 启动时载入上次记忆（逐字段拷贝，避免外部对象直接污染运行态） */
  static loadHealth(saved: BackendHealth[]): void {
    SearchService.health = [];
    if (saved === undefined || saved === null) {
      return;
    }
    for (let i = 0; i < saved.length; i++) {
      const s: BackendHealth = saved[i];
      const h: BackendHealth = new BackendHealth();
      h.backend = s.backend;
      h.ok = s.ok === true;
      h.ms = s.ms > 0 ? s.ms : 0;
      h.failures = s.failures > 0 ? s.failures : 0;
      h.cooldownUntil = s.cooldownUntil > 0 ? s.cooldownUntil : 0;
      h.tested = s.tested === true;
      h.checkedAt = s.checkedAt > 0 ? s.checkedAt : 0;
      SearchService.health.push(h);
    }
    Logger.info('search health restored: ' + SearchService.health.length + ' entries');
  }

  static clearHealth(): void {
    SearchService.health = [];
  }

  private static withBackend(cfg: SearchConfig, backend: string): SearchConfig {
    const c: SearchConfig = new SearchConfig();
    c.backend = backend;
    c.endpoint = cfg.endpoint;
    c.maxResults = cfg.maxResults;
    c.region = cfg.region;
    return c;
  }

  /** 分发到具体后端实现 */
  private static async invoke(cfg: SearchConfig, backend: string, q: string): Promise<SearchResult[]> {
    if (backend === 'duckduckgo') {
      return await SearchService.duckDuckGo(cfg, q);
    }
    if (backend === 'searxng') {
      return await SearchService.searxng(cfg, q);
    }
    return await SearchService.bing(cfg, q);
  }

  /**
   * 候选顺序（自动择优的核心）：
   *   1) 用户显式指定的后端 —— 但若正处于失败冷却，则跳过并说明
   *   2) 已知可用，按最近耗时从快到慢
   *   3) 从未测过的
   *   4) 处于冷却的 —— 放最后兜底，万一网络已经恢复
   *
   * 这样换网络环境（例如出国后 DuckDuckGo 变得可用）无需手动切换，
   * 一次成功就会把它排到前面。
   */
  static rankedOrder(cfg: SearchConfig): string[] {
    const all: string[] = ['bing', 'duckduckgo', 'searxng'];
    const usable: string[] = [];
    const unknown: string[] = [];
    const cooling: string[] = [];
    const now: number = Date.now();
    for (let i = 0; i < all.length; i++) {
      const b: string = all[i];
      // SearXNG 未配置地址直接排除
      if (b === 'searxng' && cfg.endpoint.trim().length === 0) {
        continue;
      }
      const h: BackendHealth = SearchService.healthOf(b);
      const stale: boolean = h.checkedAt > 0 && (now - h.checkedAt) > SearchService.HEALTH_TTL_MS;
      if (!h.tested || stale) {
        // 太久没验证过的记忆不再当依据，但冷却时间戳仍按绝对时间判断
        if (now < h.cooldownUntil) {
          cooling.push(b);
        } else {
          unknown.push(b);
        }
      } else if (now < h.cooldownUntil) {
        cooling.push(b);
      } else {
        usable.push(b);
      }
    }
    usable.sort((a: string, b: string) => SearchService.healthOf(a).ms - SearchService.healthOf(b).ms);

    const out: string[] = [];
    const explicit: string = cfg.backend;
    if (explicit.length > 0 && explicit !== 'auto') {
      const h: BackendHealth = SearchService.healthOf(explicit);
      if (now >= h.cooldownUntil) {
        out.push(explicit);
      } else {
        Logger.info('search: ' + explicit + ' 处于失败冷却中，改用自动择优');
      }
    }
    const rest: string[] = usable.concat(unknown).concat(cooling);
    for (let i = 0; i < rest.length; i++) {
      if (out.indexOf(rest[i]) < 0) {
        out.push(rest[i]);
      }
    }
    return out;
  }

  /**
   * 测试单个后端。
   * 刻意**不走 search()**，因为 search() 失败时会自动降级到 DuckDuckGo，
   * 那样就分不清到底是哪个后端真的可用。
   */
  static async testBackend(base: SearchConfig, backend: string, query: string): Promise<SearchTestResult> {
    const r: SearchTestResult = new SearchTestResult();
    r.backend = backend;
    const cfg: SearchConfig = new SearchConfig();
    cfg.backend = backend;
    cfg.endpoint = base.endpoint;
    cfg.maxResults = base.maxResults;
    cfg.region = base.region;

    if (backend === 'searxng' && cfg.endpoint.trim().length === 0) {
      r.skipped = true;
      r.error = '未配置实例地址';
      return r;
    }
    const t0: number = Date.now();
    try {
      let list: SearchResult[] = [];
      if (backend === 'duckduckgo') {
        list = await SearchService.duckDuckGo(cfg, query);
      } else if (backend === 'searxng') {
        list = await SearchService.searxng(cfg, query);
      } else {
        list = await SearchService.bing(cfg, query);
      }
      r.ms = Date.now() - t0;
      r.ok = list.length > 0;
      r.count = list.length;
      r.sample = list.length > 0 ? list[0].title : '';
      if (list.length === 0) {
        r.error = '连通但未解析出结果';
      }
      // 测试结果直接喂给健康度，测完就能自动择优
      if (r.ok) {
        SearchService.recordSuccess(backend, r.ms);
      } else {
        SearchService.recordFailure(backend);
      }
    } catch (e) {
      r.ms = Date.now() - t0;
      r.ok = false;
      r.error = (e as Error).message;
      SearchService.recordFailure(backend);
    }
    return r;
  }

  /** 依次测试全部后端（串行，避免并发请求被搜索引擎限流） */
  static async testAll(cfg: SearchConfig, query: string): Promise<SearchTestResult[]> {
    const backends: string[] = ['bing', 'duckduckgo', 'searxng'];
    const out: SearchTestResult[] = [];
    for (let i = 0; i < backends.length; i++) {
      const r: SearchTestResult = await SearchService.testBackend(cfg, backends[i], query);
      Logger.info('search test ' + backends[i] + ': ok=' + r.ok + ' count=' + r.count
        + ' ms=' + r.ms + (r.error.length > 0 ? (' err=' + r.error) : ''));
      out.push(r);
    }
    return out;
  }

  static backendLabel(b: string): string {
    if (b === 'auto') {
      return '自动';
    }
    if (b === 'duckduckgo') {
      return 'DuckDuckGo';
    }
    if (b === 'searxng') {
      return 'SearXNG';
    }
    return 'Bing';
  }

  /** 按界面语言给出 Bing 的地区参数 */
  static regionFor(language: string): string {
    if (language === 'en') {
      return 'en-US';
    }
    if (language === 'ja') {
      return 'ja-JP';
    }
    return 'zh-CN';
  }

  /* ------------------------- Bing RSS ------------------------- */

  private static async bing(cfg: SearchConfig, q: string): Promise<SearchResult[]> {
    const url: string = 'https://cn.bing.com/search?q=' + encodeURIComponent(q)
      + '&format=rss&count=' + cfg.maxResults.toString() + '&mkt=' + encodeURIComponent(cfg.region);
    const xml: string = await HttpClient.getJson(url, SearchService.headers(), Constants.SEARCH_TIMEOUT_MS);
    const out: SearchResult[] = [];
    const items: string[] = SearchService.splitBlocks(xml, '<item>', '</item>');
    for (let i = 0; i < items.length && out.length < cfg.maxResults; i++) {
      const block: string = items[i];
      const link: string = SearchService.tag(block, 'link');
      if (link.length === 0) {
        continue;
      }
      const r: SearchResult = new SearchResult();
      r.title = SearchService.clean(SearchService.tag(block, 'title'));
      r.url = SearchService.clean(link);
      r.snippet = SearchService.clean(SearchService.tag(block, 'description'));
      r.site = SearchService.hostOf(r.url);
      if (r.title.length > 0) {
        out.push(r);
      }
    }
    Logger.info('search bing: ' + out.length + ' results');
    return out;
  }

  /* ------------------------- DuckDuckGo Lite ------------------------- */

  private static async duckDuckGo(cfg: SearchConfig, q: string): Promise<SearchResult[]> {
    const url: string = 'https://lite.duckduckgo.com/lite/?q=' + encodeURIComponent(q);
    const html: string = await HttpClient.getJson(url, SearchService.headers(), Constants.SEARCH_TIMEOUT_MS);
    const out: SearchResult[] = [];
    // 结果链接形如 <a rel="nofollow" href="..." class='result-link'>标题</a>
    const linkRe: RegExp = /<a[^>]+class=['"]result-link['"][^>]*href=['"]([^'"]+)['"][^>]*>([\s\S]*?)<\/a>/g;
    const titles: string[] = [];
    const urls: string[] = [];
    let m: RegExpExecArray | null = linkRe.exec(html);
    let guard: number = 0;
    while (m !== null && guard < 100) {
      urls.push(SearchService.clean(m[1]));
      titles.push(SearchService.clean(m[2]));
      m = linkRe.exec(html);
      guard++;
    }
    const snippets: string[] = SearchService.splitBlocks(html, "class='result-snippet'", '</td>');
    for (let i = 0; i < urls.length && out.length < cfg.maxResults; i++) {
      const r: SearchResult = new SearchResult();
      r.title = titles[i];
      r.url = urls[i];
      r.snippet = i + 1 < snippets.length ? SearchService.clean(snippets[i + 1]) : '';
      r.site = SearchService.hostOf(r.url);
      if (r.title.length > 0 && r.url.indexOf('http') === 0) {
        out.push(r);
      }
    }
    Logger.info('search ddg: ' + out.length + ' results');
    return out;
  }

  /* ------------------------- SearXNG ------------------------- */

  private static async searxng(cfg: SearchConfig, q: string): Promise<SearchResult[]> {
    const base: string = cfg.endpoint.trim().replace(/\/+$/, '');
    if (base.length === 0) {
      throw new Error('未配置 SearXNG 实例地址');
    }
    const url: string = base + '/search?q=' + encodeURIComponent(q) + '&format=json';
    const text: string = await HttpClient.getJson(url, SearchService.headers(), Constants.SEARCH_TIMEOUT_MS);
    const out: SearchResult[] = [];
    const parsed: SearxResponse | null = SearchService.tryParse(text);
    if (parsed === null || parsed.results === undefined) {
      throw new Error('SearXNG 返回格式异常（需要开启 json 输出）');
    }
    for (let i = 0; i < parsed.results.length && out.length < cfg.maxResults; i++) {
      const it: SearxItem = parsed.results[i];
      const r: SearchResult = new SearchResult();
      r.title = SearchService.clean(it.title);
      r.url = SearchService.clean(it.url);
      r.snippet = SearchService.clean(it.content);
      r.site = SearchService.hostOf(r.url);
      if (r.title.length > 0 && r.url.indexOf('http') === 0) {
        out.push(r);
      }
    }
    Logger.info('search searxng: ' + out.length + ' results');
    return out;
  }

  private static tryParse(text: string): SearxResponse | null {
    try {
      return JSON.parse(text) as SearxResponse;
    } catch (e) {
      return null;
    }
  }

  /* ------------------------- 工具方法 ------------------------- */

  private static headers(): HeaderMap {
    const h: HeaderMap = {};
    h['User-Agent'] = SearchService.UA;
    h['Accept'] = 'text/html,application/xhtml+xml,application/xml,application/json;q=0.9,*/*;q=0.8';
    h['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
    return h;
  }

  /** 取出 start..end 之间的所有片段（不含标记本身） */
  private static splitBlocks(text: string, start: string, end: string): string[] {
    const out: string[] = [];
    let from: number = 0;
    let guard: number = 0;
    while (guard < 200) {
      const a: number = text.indexOf(start, from);
      if (a < 0) {
        break;
      }
      const b: number = text.indexOf(end, a + start.length);
      if (b < 0) {
        break;
      }
      out.push(text.substring(a + start.length, b));
      from = b + end.length;
      guard++;
    }
    return out;
  }

  /** 取 <tag>...</tag> 的内容（含 CDATA） */
  private static tag(block: string, name: string): string {
    const a: number = block.indexOf('<' + name + '>');
    if (a < 0) {
      return '';
    }
    const b: number = block.indexOf('</' + name + '>', a);
    if (b < 0) {
      return '';
    }
    let v: string = block.substring(a + name.length + 2, b);
    if (v.indexOf('<![CDATA[') === 0) {
      v = v.substring(9);
    }
    if (v.endsWith(']]>')) {
      v = v.substring(0, v.length - 3);
    }
    return v;
  }

  /** 去 HTML 标签 + 解实体 + 压缩空白 */
  static clean(raw: string): string {
    if (raw.length === 0) {
      return '';
    }
    let t: string = raw.replace(/<[^>]*>/g, ' ');
    t = SearchService.decodeEntities(t);
    t = t.replace(/\s+/g, ' ').trim();
    return t;
  }

  private static decodeEntities(t: string): string {
    let s: string = t;
    s = s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
    s = s.replace(/&#0?39;/g, "'").replace(/&apos;/g, "'").replace(/&nbsp;/g, ' ');
    s = s.replace(/&amp;/g, '&');
    s = s.replace(/&#x([0-9a-fA-F]+);/g, (full: string, hex: string) => {
      const code: number = Number.parseInt(hex, 16);
      return Number.isNaN(code) ? full : String.fromCharCode(code);
    });
    s = s.replace(/&#(\d+);/g, (full: string, dec: string) => {
      const code: number = Number.parseInt(dec, 10);
      return Number.isNaN(code) ? full : String.fromCharCode(code);
    });
    return s;
  }

  static hostOf(url: string): string {
    try {
      const i: number = url.indexOf('://');
      const rest: string = i >= 0 ? url.substring(i + 3) : url;
      const j: number = rest.indexOf('/');
      const host: string = j >= 0 ? rest.substring(0, j) : rest;
      return host.replace(/^www\./, '');
    } catch (e) {
      return '';
    }
  }

  /**
   * 把搜索结果拼成注入 system prompt 的上下文。
   * 明确要求模型基于这些资料作答并标注引用编号，减少幻觉。
   */
  static formatForPrompt(results: SearchResult[]): string {
    if (results.length === 0) {
      return '';
    }
    const parts: string[] = [];
    parts.push('以下是与用户问题相关的实时联网搜索结果（可能不完整，请结合常识判断）：');
    for (let i = 0; i < results.length; i++) {
      const r: SearchResult = results[i];
      parts.push('[' + (i + 1).toString() + '] ' + r.title);
      parts.push('    来源：' + r.site + '  ' + r.url);
      if (r.snippet.length > 0) {
        parts.push('    摘要：' + r.snippet);
      }
    }
    parts.push('');
    parts.push('回答要求：优先使用上述资料；引用时在句末标注 [编号]；'
      + '若资料不足以回答，请明确说明并给出你能确定的部分。');
    return parts.join('\n');
  }
}

/** SearXNG JSON 响应 */
interface SearxItem {
  title: string;
  url: string;
  content: string;
}

interface SearxResponse {
  results: SearxItem[];
}

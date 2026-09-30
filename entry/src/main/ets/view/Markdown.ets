/**
 * 轻量 Markdown 解析器（为 ArkUI 渲染优化）
 * 支持：标题 / 段落 / 围栏代码 / 有序无序列表 / 任务列表 / 引用 / 表格 / 分割线 / 图片
 * 行内：粗体 斜体 删除线 行内代码 链接 自动链接
 */

export class MdSpan {
  text: string = '';
  bold: boolean = false;
  italic: boolean = false;
  strike: boolean = false;
  code: boolean = false;
  link: string = '';
  image: string = '';
}

export class MdListItem {
  spans: MdSpan[] = [];
  marker: string = '';
  depth: number = 0;
  isTask: boolean = false;
  checked: boolean = false;
}

export class MdBlock {
  /** heading / paragraph / code / list / quote / table / divider */
  kind: string = '';
  level: number = 0;
  spans: MdSpan[] = [];
  lang: string = '';
  code: string = '';
  ordered: boolean = false;
  startIndex: number = 1;
  items: MdListItem[] = [];
  headers: string[] = [];
  rows: string[][] = [];
}

export class Markdown {
  static parse(src: string): MdBlock[] {
    const blocks: MdBlock[] = [];
    if (src === undefined || src === null || src.length === 0) {
      return blocks;
    }
    const lines: string[] = src.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    let i: number = 0;
    while (i < lines.length) {
      const line: string = lines[i];
      // 围栏代码
      const fence: string = Markdown.fenceOf(line);
      if (fence.length > 0) {
        const lang: string = line.trim().substring(fence.length).trim();
        const buf: string[] = [];
        i++;
        while (i < lines.length && Markdown.fenceOf(lines[i]) !== fence) {
          buf.push(lines[i]);
          i++;
        }
        if (i < lines.length) {
          i++;
        }
        const b: MdBlock = new MdBlock();
        b.kind = 'code';
        b.lang = lang;
        b.code = buf.join('\n');
        blocks.push(b);
        continue;
      }
      // 空行
      if (line.trim().length === 0) {
        i++;
        continue;
      }
      // 分割线
      if (Markdown.isDivider(line)) {
        const b: MdBlock = new MdBlock();
        b.kind = 'divider';
        blocks.push(b);
        i++;
        continue;
      }
      // 标题
      const h: number = Markdown.headingLevel(line);
      if (h > 0) {
        const b: MdBlock = new MdBlock();
        b.kind = 'heading';
        b.level = h;
        b.spans = Markdown.inline(line.trim().substring(h).trim());
        blocks.push(b);
        i++;
        continue;
      }
      // 表格
      if (line.indexOf('|') >= 0 && i + 1 < lines.length && Markdown.isTableSeparator(lines[i + 1])) {
        const headers: string[] = Markdown.splitRow(line);
        const rows: string[][] = [];
        i += 2;
        while (i < lines.length && lines[i].indexOf('|') >= 0 && lines[i].trim().length > 0) {
          rows.push(Markdown.splitRow(lines[i]));
          i++;
        }
        const b: MdBlock = new MdBlock();
        b.kind = 'table';
        b.headers = headers;
        b.rows = rows;
        blocks.push(b);
        continue;
      }
      // 引用
      if (line.trim().startsWith('>')) {
        const buf: string[] = [];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          buf.push(lines[i].trim().replace(/^>\s?/, ''));
          i++;
        }
        const b: MdBlock = new MdBlock();
        b.kind = 'quote';
        b.spans = Markdown.inline(buf.join('\n'));
        blocks.push(b);
        continue;
      }
      // 列表
      if (Markdown.listMatch(line) !== null) {
        const b: MdBlock = new MdBlock();
        b.kind = 'list';
        i = Markdown.parseList(lines, i, b);
        blocks.push(b);
        continue;
      }
      // 段落
      const buf: string[] = [];
      while (i < lines.length && lines[i].trim().length > 0
        && Markdown.fenceOf(lines[i]).length === 0
        && Markdown.headingLevel(lines[i]) === 0
        && !Markdown.isDivider(lines[i])
        && Markdown.listMatch(lines[i]) === null
        && !lines[i].trim().startsWith('>')) {
        buf.push(lines[i]);
        i++;
      }
      const b: MdBlock = new MdBlock();
      b.kind = 'paragraph';
      b.spans = Markdown.inline(buf.join('\n'));
      blocks.push(b);
    }
    return blocks;
  }

  private static fenceOf(line: string): string {
    const t: string = line.trim();
    if (t.startsWith('```')) {
      return '```';
    }
    if (t.startsWith('~~~')) {
      return '~~~';
    }
    return '';
  }

  private static headingLevel(line: string): number {
    const t: string = line.trim();
    let n: number = 0;
    while (n < t.length && t.charAt(n) === '#') {
      n++;
    }
    if (n >= 1 && n <= 6 && n < t.length && t.charAt(n) === ' ') {
      return n;
    }
    return 0;
  }

  private static isDivider(line: string): boolean {
    const t: string = line.trim();
    if (t.length < 3) {
      return false;
    }
    const c: string = t.charAt(0);
    if (c !== '-' && c !== '*' && c !== '_') {
      return false;
    }
    for (let i = 0; i < t.length; i++) {
      if (t.charAt(i) !== c) {
        return false;
      }
    }
    return true;
  }

  private static isTableSeparator(line: string): boolean {
    const t: string = line.trim();
    if (t.indexOf('-') < 0) {
      return false;
    }
    const cells: string[] = Markdown.splitRow(t);
    if (cells.length === 0) {
      return false;
    }
    for (let i = 0; i < cells.length; i++) {
      const c: string = cells[i].trim();
      if (!/^:?-{1,}:?$/.test(c)) {
        return false;
      }
    }
    return true;
  }

  private static splitRow(line: string): string[] {
    let t: string = line.trim();
    if (t.startsWith('|')) {
      t = t.substring(1);
    }
    if (t.endsWith('|')) {
      t = t.substring(0, t.length - 1);
    }
    return t.split('|').map((s: string) => s.trim());
  }

  private static listMatch(line: string): string | null {
    const m: RegExpMatchArray | null = line.match(/^(\s*)([-*+]|\d{1,9}[.)])\s+(.*)$/);
    if (m === null) {
      return null;
    }
    return m[0];
  }

  private static parseList(lines: string[], start: number, block: MdBlock): number {
    let i: number = start;
    let counter: number = -1;
    while (i < lines.length) {
      const m: RegExpMatchArray | null = lines[i].match(/^(\s*)([-*+]|\d{1,9}[.)])\s+(.*)$/);
      if (m === null) {
        // 列表项的续行
        if (lines[i].trim().length > 0 && block.items.length > 0 && /^\s{2,}/.test(lines[i])) {
          const last: MdListItem = block.items[block.items.length - 1];
          const extra: MdSpan[] = Markdown.inline(' ' + lines[i].trim());
          for (let k = 0; k < extra.length; k++) {
            last.spans.push(extra[k]);
          }
          i++;
          continue;
        }
        break;
      }
      const indent: number = m[1].length;
      const marker: string = m[2];
      const rest: string = m[3];
      const isOrdered: boolean = /^\d/.test(marker);
      if (counter < 0) {
        block.ordered = isOrdered;
        counter = isOrdered ? Number.parseInt(marker.replace(/[.)]/, ''), 10) : 1;
      }
      const item: MdListItem = new MdListItem();
      item.depth = Math.min(3, Math.floor(indent / 2));
      item.marker = marker;
      // 任务列表
      const task: RegExpMatchArray | null = rest.match(/^\[([ xX])\]\s+(.*)$/);
      if (task !== null) {
        item.isTask = true;
        item.checked = task[1].toLowerCase() === 'x';
        item.spans = Markdown.inline(task[2]);
      } else {
        item.spans = Markdown.inline(rest);
      }
      block.items.push(item);
      i++;
    }
    block.startIndex = counter > 0 ? counter : 1;
    return i;
  }

  /* ===================== 行内解析 ===================== */

  static inline(text: string): MdSpan[] {
    const spans: MdSpan[] = [];
    if (text === undefined || text === null || text.length === 0) {
      return spans;
    }
    let buf: string = '';
    let i: number = 0;
    const flush = (): void => {
      if (buf.length > 0) {
        const s: MdSpan = new MdSpan();
        s.text = buf;
        spans.push(s);
        buf = '';
      }
    };
    while (i < text.length) {
      const c: string = text.charAt(i);
      // 转义
      if (c === '\\' && i + 1 < text.length) {
        buf += text.charAt(i + 1);
        i += 2;
        continue;
      }
      // 换行 -> 空格
      if (c === '\n') {
        buf += '\n';
        i++;
        continue;
      }
      // 行内代码
      if (c === '`') {
        const end: number = text.indexOf('`', i + 1);
        if (end > i) {
          flush();
          const s: MdSpan = new MdSpan();
          s.text = text.substring(i + 1, end);
          s.code = true;
          spans.push(s);
          i = end + 1;
          continue;
        }
      }
      // 图片
      if (c === '!' && i + 1 < text.length && text.charAt(i + 1) === '[') {
        const close: number = text.indexOf('](', i + 2);
        if (close > 0) {
          const endParen: number = text.indexOf(')', close + 2);
          if (endParen > close) {
            flush();
            const s: MdSpan = new MdSpan();
            s.text = text.substring(i + 2, close);
            s.image = text.substring(close + 2, endParen).trim();
            spans.push(s);
            i = endParen + 1;
            continue;
          }
        }
      }
      // 链接
      if (c === '[') {
        const close: number = text.indexOf('](', i + 1);
        if (close > 0) {
          const endParen: number = text.indexOf(')', close + 2);
          if (endParen > close) {
            flush();
            const s: MdSpan = new MdSpan();
            s.text = text.substring(i + 1, close);
            s.link = text.substring(close + 2, endParen).trim();
            spans.push(s);
            i = endParen + 1;
            continue;
          }
        }
      }
      // 粗体
      if ((c === '*' || c === '_') && i + 1 < text.length && text.charAt(i + 1) === c) {
        const token: string = c + c;
        const end: number = text.indexOf(token, i + 2);
        if (end > i + 1) {
          flush();
          const inner: string = text.substring(i + 2, end);
          const sub: MdSpan[] = Markdown.inline(inner);
          for (let k = 0; k < sub.length; k++) {
            sub[k].bold = true;
            spans.push(sub[k]);
          }
          i = end + 2;
          continue;
        }
      }
      // 删除线
      if (c === '~' && i + 1 < text.length && text.charAt(i + 1) === '~') {
        const end: number = text.indexOf('~~', i + 2);
        if (end > i + 1) {
          flush();
          const s: MdSpan = new MdSpan();
          s.text = text.substring(i + 2, end);
          s.strike = true;
          spans.push(s);
          i = end + 2;
          continue;
        }
      }
      // 斜体
      if (c === '*' || c === '_') {
        const end: number = text.indexOf(c, i + 1);
        if (end > i + 1 && text.charAt(end - 1) !== ' ') {
          flush();
          const s: MdSpan = new MdSpan();
          s.text = text.substring(i + 1, end);
          s.italic = true;
          spans.push(s);
          i = end + 1;
          continue;
        }
      }
      // 自动链接
      if (c === 'h' && (text.startsWith('http://', i) || text.startsWith('https://', i))) {
        let end: number = i;
        while (end < text.length && !/\s/.test(text.charAt(end))) {
          end++;
        }
        let url: string = text.substring(i, end);
        while (url.length > 0 && /[),.;:!?]$/.test(url)) {
          url = url.substring(0, url.length - 1);
          end--;
        }
        flush();
        const s: MdSpan = new MdSpan();
        s.text = url;
        s.link = url;
        spans.push(s);
        i = end;
        continue;
      }
      buf += c;
      i++;
    }
    flush();
    return spans;
  }

  /** 提取纯文本（用于复制/摘要） */
  static plain(spans: MdSpan[]): string {
    let out: string = '';
    for (let i = 0; i < spans.length; i++) {
      out += spans[i].text;
    }
    return out;
  }
}

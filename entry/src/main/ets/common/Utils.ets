import { util } from '@kit.ArkTS';

export class Utils {
  private static seq: number = 0;

  /** 生成短唯一 ID */
  static uid(prefix: string = 'id'): string {
    Utils.seq = (Utils.seq + 1) % 100000;
    const t: number = Date.now();
    const r: number = Math.floor(Math.random() * 1679616);
    return prefix + '_' + t.toString(36) + '_' + r.toString(36) + '_' + Utils.seq.toString(36);
  }

  /** 时间格式化：HH:mm */
  static hhmm(ts: number): string {
    const d: Date = new Date(ts);
    const h: string = d.getHours().toString().padStart(2, '0');
    const m: string = d.getMinutes().toString().padStart(2, '0');
    return h + ':' + m;
  }

  /** 相对时间 */
  static relativeTime(ts: number): string {
    const diff: number = Date.now() - ts;
    if (diff < 60000) {
      return '刚刚';
    }
    if (diff < 3600000) {
      return Math.floor(diff / 60000) + ' 分钟前';
    }
    if (diff < 86400000) {
      return Math.floor(diff / 3600000) + ' 小时前';
    }
    if (diff < 604800000) {
      return Math.floor(diff / 86400000) + ' 天前';
    }
    const d: Date = new Date(ts);
    return (d.getMonth() + 1) + '月' + d.getDate() + '日';
  }

  /** 大数字紧凑显示 */
  /**
   * 把工具调用的 JSON 参数压成一行可读摘要，例如 `timezone=8, format=iso`。
   * 解析失败就直接返回原文的截断版本。
   */
  static summarizeArgs(raw: string): string {
    const text: string = raw.trim();
    if (text.length === 0) {
      return '';
    }
    try {
      const obj: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const keys: string[] = Object.keys(obj);
      if (keys.length === 0) {
        return '';
      }
      const parts: string[] = [];
      for (let i = 0; i < keys.length && i < 4; i++) {
        const v: string = JSON.stringify(obj[keys[i]]);
        parts.push(keys[i] + '=' + (v !== undefined && v.length > 24 ? (v.substring(0, 24) + '…') : v));
      }
      return parts.join(', ');
    } catch (e) {
      return text.length > 40 ? (text.substring(0, 40) + '…') : text;
    }
  }

  static compact(n: number): string {
    if (n < 1000) {
      return n.toString();
    }
    if (n < 1000000) {
      return (n / 1000).toFixed(n < 10000 ? 1 : 0) + 'K';
    }
    return (n / 1000000).toFixed(2) + 'M';
  }

  /** 粗略 token 估算（中英混合） */
  static estimateTokens(text: string): number {
    if (!text) {
      return 0;
    }
    let cjk: number = 0;
    let other: number = 0;
    for (let i = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      if (code >= 0x4E00 && code <= 0x9FFF) {
        cjk++;
      } else {
        other++;
      }
    }
    return Math.ceil(cjk * 0.75 + other / 3.6);
  }

  /** 字节数格式化 */
  static bytes(n: number): string {
    if (n < 1024) {
      return n + ' B';
    }
    if (n < 1048576) {
      return (n / 1024).toFixed(1) + ' KB';
    }
    return (n / 1048576).toFixed(2) + ' MB';
  }

  /** 安全 JSON 解析 */
  static tryParse<T>(text: string, fallback: T): T {
    try {
      const v: T = JSON.parse(text) as T;
      return v;
    } catch (e) {
      return fallback;
    }
  }

  /** 截断字符串 */
  static ellipsis(s: string, max: number): string {
    if (!s) {
      return '';
    }
    const clean: string = s.replace(/\s+/g, ' ').trim();
    return clean.length <= max ? clean : clean.substring(0, max) + '…';
  }

  /** 从文本生成会话标题 */
  static titleFrom(text: string): string {
    const t: string = Utils.ellipsis(text, 22);
    return t.length > 0 ? t : '新对话';
  }

  /** 转义 XML 特殊字符 */
  static escapeXml(s: string): string {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
  }

  /** base64 编码 ArrayBuffer */
  static base64Of(buf: ArrayBuffer): string {
    const helper: util.Base64Helper = new util.Base64Helper();
    return helper.encodeToStringSync(new Uint8Array(buf));
  }
}

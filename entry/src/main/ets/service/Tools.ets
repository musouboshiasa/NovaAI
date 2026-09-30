import { Logger } from '../common/Logger';

/** 工具定义 */
export class ToolDef {
  name: string;
  description: string;
  parametersJson: string;

  constructor(name: string, description: string, parametersJson: string) {
    this.name = name;
    this.description = description;
    this.parametersJson = parametersJson;
  }
}

/**
 * 内置工具（本地执行，用于演示与验证 Function Calling 全链路）
 */
export class Tools {
  static definitions(): ToolDef[] {
    const out: ToolDef[] = [];
    out.push(new ToolDef('get_current_time', '获取当前的日期与时间，可指定时区偏移（小时）。',
      '{"type":"object","properties":{"timezone_offset":{"type":"number","description":"相对 UTC 的时区偏移小时数，例如北京时间为 8"}},"required":[],"additionalProperties":false}'));
    out.push(new ToolDef('calculate', '计算一个数学表达式，支持 + - * / % ^ 与括号，以及 sqrt/abs/round/floor/ceil/log/ln/sin/cos/tan 等函数。',
      '{"type":"object","properties":{"expression":{"type":"string","description":"要计算的数学表达式，例如 (12+8)*3/4"}},"required":["expression"],"additionalProperties":false}'));
    out.push(new ToolDef('random_number', '在指定范围内生成一个随机整数。',
      '{"type":"object","properties":{"min":{"type":"number","description":"最小值（含）"},"max":{"type":"number","description":"最大值（含）"}},"required":["min","max"],"additionalProperties":false}'));
    out.push(new ToolDef('text_stats', '统计一段文本的字符数、词数与行数。',
      '{"type":"object","properties":{"text":{"type":"string","description":"需要统计的文本"}},"required":["text"],"additionalProperties":false}'));
    return out;
  }

  static isKnown(name: string): boolean {
    const defs: ToolDef[] = Tools.definitions();
    for (let i = 0; i < defs.length; i++) {
      if (defs[i].name === name) {
        return true;
      }
    }
    return false;
  }

  /** 执行工具，返回结果字符串 */
  static execute(name: string, argsJson: string): string {
    try {
      const args: Record<string, Object> = argsJson.trim().length > 0
        ? JSON.parse(argsJson) as Record<string, Object> : {};
      if (name === 'get_current_time') {
        return Tools.getCurrentTime(args);
      }
      if (name === 'calculate') {
        return Tools.calculate(args);
      }
      if (name === 'random_number') {
        return Tools.randomNumber(args);
      }
      if (name === 'text_stats') {
        return Tools.textStats(args);
      }
      return '{"error":"未知工具: ' + name + '"}';
    } catch (e) {
      const err = e as Error;
      Logger.warn('tool execute failed: ' + err.message);
      return '{"error":"工具执行失败: ' + err.message + '"}';
    }
  }

  private static num(args: Record<string, Object>, key: string, def: number): number {
    const v: Object | undefined = args[key];
    if (v === undefined || v === null) {
      return def;
    }
    const n: number = Number(v);
    return Number.isNaN(n) ? def : n;
  }

  private static str(args: Record<string, Object>, key: string): string {
    const v: Object | undefined = args[key];
    return (v === undefined || v === null) ? '' : String(v);
  }

  private static getCurrentTime(args: Record<string, Object>): string {
    const offset: number = Tools.num(args, 'timezone_offset', 8);
    const now: Date = new Date();
    const utc: number = now.getTime() + now.getTimezoneOffset() * 60000;
    const local: Date = new Date(utc + offset * 3600000);
    const iso: string = local.getFullYear() + '-' + Tools.pad(local.getMonth() + 1) + '-' + Tools.pad(local.getDate())
      + ' ' + Tools.pad(local.getHours()) + ':' + Tools.pad(local.getMinutes()) + ':' + Tools.pad(local.getSeconds());
    const week: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return '{"datetime":"' + iso + '","weekday":"' + week[local.getDay()] + '","timezone_offset":' + offset + '}';
  }

  private static pad(n: number): string {
    return n < 10 ? ('0' + n) : ('' + n);
  }

  private static calculate(args: Record<string, Object>): string {
    const expr: string = Tools.str(args, 'expression');
    if (expr.length === 0) {
      return '{"error":"expression 不能为空"}';
    }
    const value: number = new ExprParser(expr).parse();
    if (Number.isNaN(value) || !Number.isFinite(value)) {
      return '{"error":"无法计算该表达式"}';
    }
    return '{"expression":"' + expr.replace(/"/g, '\\"') + '","result":' + value + '}';
  }

  private static randomNumber(args: Record<string, Object>): string {
    const min: number = Math.ceil(Tools.num(args, 'min', 0));
    const max: number = Math.floor(Tools.num(args, 'max', 100));
    if (max < min) {
      return '{"error":"max 必须大于等于 min"}';
    }
    const v: number = min + Math.floor(Math.random() * (max - min + 1));
    return '{"min":' + min + ',"max":' + max + ',"value":' + v + '}';
  }

  private static textStats(args: Record<string, Object>): string {
    const t: string = Tools.str(args, 'text');
    const chars: number = t.length;
    const lines: number = t.length === 0 ? 0 : t.split('\n').length;
    const words: number = t.trim().length === 0 ? 0 : t.trim().split(/\s+/).length;
    const cjk: number = (t.match(/[\u4e00-\u9fff]/g) ?? []).length;
    return '{"chars":' + chars + ',"words":' + words + ',"lines":' + lines + ',"cjk_chars":' + cjk + '}';
  }

}

/**
 * 极简数学表达式解析器（递归下降）
 */
class ExprParser {
  private s: string = '';
  private i: number = 0;

  constructor(input: string) {
    this.s = input.replace(/\s+/g, '');
    this.i = 0;
  }

  parse(): number {
    const v: number = this.expr();
    return v;
  }

  private expr(): number {
    let v: number = this.term();
    while (this.i < this.s.length) {
      const c: string = this.s.charAt(this.i);
      if (c === '+') {
        this.i++;
        v += this.term();
      } else if (c === '-') {
        this.i++;
        v -= this.term();
      } else {
        break;
      }
    }
    return v;
  }

  private term(): number {
    let v: number = this.power();
    while (this.i < this.s.length) {
      const c: string = this.s.charAt(this.i);
      if (c === '*') {
        this.i++;
        v *= this.power();
      } else if (c === '/') {
        this.i++;
        v /= this.power();
      } else if (c === '%') {
        this.i++;
        v %= this.power();
      } else {
        break;
      }
    }
    return v;
  }

  private power(): number {
    const base: number = this.unary();
    if (this.i < this.s.length && this.s.charAt(this.i) === '^') {
      this.i++;
      const e: number = this.power();
      return Math.pow(base, e);
    }
    return base;
  }

  private unary(): number {
    if (this.i < this.s.length) {
      const c: string = this.s.charAt(this.i);
      if (c === '-') {
        this.i++;
        return -this.unary();
      }
      if (c === '+') {
        this.i++;
        return this.unary();
      }
    }
    return this.atom();
  }

  private atom(): number {
    if (this.i >= this.s.length) {
      return Number.NaN;
    }
    const c: string = this.s.charAt(this.i);
    if (c === '(') {
      this.i++;
      const v: number = this.expr();
      if (this.i < this.s.length && this.s.charAt(this.i) === ')') {
        this.i++;
      }
      return v;
    }
    if (/[0-9.]/.test(c)) {
      const start: number = this.i;
      while (this.i < this.s.length && /[0-9.]/.test(this.s.charAt(this.i))) {
        this.i++;
      }
      return Number.parseFloat(this.s.substring(start, this.i));
    }
    if (/[a-zA-Z]/.test(c)) {
      const start: number = this.i;
      while (this.i < this.s.length && /[a-zA-Z0-9_]/.test(this.s.charAt(this.i))) {
        this.i++;
      }
      const name: string = this.s.substring(start, this.i).toLowerCase();
      if (name === 'pi') {
        return Math.PI;
      }
      if (name === 'e') {
        return Math.E;
      }
      let arg: number = 0;
      if (this.i < this.s.length && this.s.charAt(this.i) === '(') {
        this.i++;
        arg = this.expr();
        if (this.i < this.s.length && this.s.charAt(this.i) === ')') {
          this.i++;
        }
      }
      return ExprParser.apply(name, arg);
    }
    this.i++;
    return Number.NaN;
  }

  private static apply(name: string, v: number): number {
    if (name === 'sqrt') {
      return Math.sqrt(v);
    }
    if (name === 'abs') {
      return Math.abs(v);
    }
    if (name === 'round') {
      return Math.round(v);
    }
    if (name === 'floor') {
      return Math.floor(v);
    }
    if (name === 'ceil') {
      return Math.ceil(v);
    }
    if (name === 'log') {
      return Math.log10(v);
    }
    if (name === 'ln') {
      return Math.log(v);
    }
    if (name === 'exp') {
      return Math.exp(v);
    }
    if (name === 'sin') {
      return Math.sin(v);
    }
    if (name === 'cos') {
      return Math.cos(v);
    }
    if (name === 'tan') {
      return Math.tan(v);
    }
    if (name === 'pow') {
      return v;
    }
    return Number.NaN;
  }
}

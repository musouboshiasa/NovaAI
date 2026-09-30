/**
 * Server-Sent Events 增量解析器
 * 严格遵循 WHATWG SSE 规范，同时兼容 DeepSeek 的 ": keep-alive" 注释行
 */

export class SseEvent {
  /** event: 字段，缺省为空串 */
  readonly name: string;
  /** data: 字段拼接结果 */
  readonly data: string;

  constructor(name: string, data: string) {
    this.name = name;
    this.data = data;
  }

  isDone(): boolean {
    return this.data === '[DONE]';
  }

  isKeepAlive(): boolean {
    return this.data.length === 0 && this.name.length === 0;
  }
}

export class SseParser {
  private buffer: string = '';
  private eventName: string = '';
  private dataLines: string[] = [];
  private listener: (evt: SseEvent) => void;
  private done: boolean = false;

  constructor(listener: (evt: SseEvent) => void) {
    this.listener = listener;
  }

  /** 喂入一段已解码的文本（可跨 chunk 边界） */
  feed(chunk: string): void {
    if (this.done || chunk.length === 0) {
      return;
    }
    this.buffer += chunk;
    let idx: number = this.buffer.indexOf('\n');
    while (idx >= 0) {
      let line: string = this.buffer.substring(0, idx);
      this.buffer = this.buffer.substring(idx + 1);
      if (line.length > 0 && line.charCodeAt(line.length - 1) === 13) {
        line = line.substring(0, line.length - 1);
      }
      this.handleLine(line);
      if (this.done) {
        return;
      }
      idx = this.buffer.indexOf('\n');
    }
  }

  /** 流结束，冲刷剩余内容 */
  flush(): void {
    if (this.done) {
      return;
    }
    if (this.buffer.length > 0) {
      let line: string = this.buffer;
      if (line.charCodeAt(line.length - 1) === 13) {
        line = line.substring(0, line.length - 1);
      }
      this.buffer = '';
      this.handleLine(line);
    }
    this.dispatch();
  }

  private handleLine(line: string): void {
    if (line.length === 0) {
      this.dispatch();
      return;
    }
    // 注释行（保活心跳）
    if (line.charCodeAt(0) === 58) {
      return;
    }
    const colon: number = line.indexOf(':');
    let field: string = '';
    let value: string = '';
    if (colon < 0) {
      field = line;
    } else {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.length > 0 && value.charCodeAt(0) === 32) {
        value = value.substring(1);
      }
    }
    if (field === 'data') {
      this.dataLines.push(value);
    } else if (field === 'event') {
      this.eventName = value;
    }
  }

  private dispatch(): void {
    if (this.dataLines.length === 0 && this.eventName.length === 0) {
      return;
    }
    const data: string = this.dataLines.join('\n');
    const name: string = this.eventName;
    this.dataLines = [];
    this.eventName = '';
    const evt: SseEvent = new SseEvent(name, data);
    if (evt.isDone()) {
      this.done = true;
    }
    this.listener(evt);
  }
}

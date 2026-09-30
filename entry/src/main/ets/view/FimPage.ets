import { Themes, Palette, Dim, Font } from '../theme/Theme';
import { RequestContext, InferenceParams, ProviderConfig } from '../model/Types';
import { ChatEngine } from '../service/ChatEngine';
import { StreamSink } from '../provider/BaseProvider';
import { AbortHandle } from '../net/HttpClient';
import { IconBtn, Pill } from './Common';
import { Utils } from '../common/Utils';

/**
 * FIM 补全工作台（DeepSeek Beta /beta/completions）
 * 给定前缀与后缀，让模型补全中间部分 —— 最适合代码/文本插入场景
 */
@Component
export struct FimPage {
  @Prop dark: boolean = true;
  @Prop isWide: boolean = false;
  @Prop provider: ProviderConfig = new ProviderConfig();
  @Prop model: string = '';
  @Prop params: InferenceParams = new InferenceParams();
  @State prefix: string = 'def fib(n):\n';
  @State suffix: string = '\n    return fib(n-1) + fib(n-2)';
  @State output: string = '';
  @State running: boolean = false;
  @State errorText: string = '';
  @State usageText: string = '';

  onClose: () => void = () => {};
  private handle: AbortHandle | null = null;

  private pal(): Palette {
    return Themes.of(this.dark);
  }

  private run(): void {
    if (this.running) {
      return;
    }
    if (this.provider.apiKey.length === 0) {
      this.errorText = '请先在设置中填写该服务商的 API Key';
      return;
    }
    this.errorText = '';
    this.output = '';
    this.usageText = '';
    this.running = true;

    const ctx: RequestContext = new RequestContext();
    ctx.provider = this.provider;
    ctx.model = this.model;
    ctx.suffix = this.prefix;
    ctx.systemPrompt = this.suffix;
    ctx.params = this.params;
    ctx.params.stream = true;

    const sink: StreamSink = new StreamSink();
    sink.onContent = (t: string) => {
      this.output += t;
    };
    sink.onUsage = (u) => {
      this.usageText = '输入 ' + u.promptTokens + ' · 输出 ' + u.completionTokens + ' tokens';
    };

    this.handle = ChatEngine.run(ctx, sink, {
      onDone: (s: StreamSink) => {
        this.running = false;
        if (s.finishReason.length > 0) {
          this.usageText += ' · ' + s.finishReason;
        }
      },
      onFail: (m: string) => {
        this.running = false;
        this.errorText = m;
      }
    }, true);
  }

  private stop(): void {
    if (this.handle !== null) {
      this.handle.cancel();
      this.handle = null;
    }
    this.running = false;
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        IconBtn({ icon: $r('app.media.ic_arrow_left'), iconSize: 18, tint: this.pal().text, onTap: () => this.onClose() })
        Column({ space: 1 }) {
          Text('FIM 代码补全').fontSize(Font.lg).fontWeight(FontWeight.Bold).fontColor(this.pal().text)
          Text('Beta · /beta/completions · 仅非思考模式 · 上限 4K')
            .fontSize(Font.xs).fontColor(this.pal().textTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Pill({ label: this.model, fg: this.pal().accent, bg: this.pal().accentSoft, labelSize: 10 })
      }
      .width('100%')
      .padding({ left: 8, right: 14, top: 8, bottom: 10 })

      Scroll() {
        Column({ space: 12 }) {
          if (this.isWide) {
            Row({ space: 10 }) {
              this.editor('前缀 (prompt)', this.prefix, true)
              this.editor('后缀 (suffix)', this.suffix, false)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            this.editor('前缀 (prompt)', this.prefix, true)
            this.editor('后缀 (suffix)', this.suffix, false)
          }

          Row({ space: 10 }) {
            Row({ space: 8 }) {
              Image(this.running ? $r('app.media.ic_stop') : $r('app.media.ic_bolt'))
                .width(16).height(16).fillColor('#FFFFFF')
              Text(this.running ? '停止' : '补全').fontSize(Font.base).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
            }
            .height(42)
            .padding({ left: 20, right: 20 })
            .backgroundColor(this.running ? this.pal().error : this.pal().accent)
            .borderRadius(Dim.r12)
            .onClick(() => {
              if (this.running) {
                this.stop();
              } else {
                this.run();
              }
            })

            Text('约 ' + Utils.estimateTokens(this.prefix + this.suffix) + ' tokens 输入')
              .fontSize(Font.xs).fontColor(this.pal().textTertiary)
          }
          .width('100%')

          if (this.errorText.length > 0) {
            Text(this.errorText)
              .fontSize(Font.sm).fontColor(this.pal().error)
              .width('100%').padding(10)
              .backgroundColor('#14FF6B6B').borderRadius(Dim.r10)
          }

          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Image($r('app.media.ic_code')).width(15).height(15).fillColor(this.pal().accent)
              Text('补全结果').fontSize(Font.sm).fontColor(this.pal().text).fontWeight(FontWeight.Medium)
              Blank()
              Text(this.usageText).fontSize(Font.xs).fontColor(this.pal().textTertiary)
            }
            .width('100%')

            Scroll() {
              Text(this.output.length > 0 ? this.output : '点击「补全」查看模型生成的中间片段…')
                .fontSize(Font.mono)
                .fontFamily(Font.code)
                .fontColor(this.output.length > 0 ? this.pal().codeText : this.pal().textTertiary)
                .width('100%')
                .textAlign(TextAlign.Start)
                .copyOption(CopyOptions.LocalDevice)
                .padding(12)
            }
            .constraintSize({ minHeight: 140, maxHeight: 320 })
            .width('100%')
            .backgroundColor(this.pal().codeBg)
            .borderRadius(Dim.r12)
            .border({ width: 1, color: this.pal().border })
            .align(Alignment.TopStart)
          }
          .width('100%')

          Row().height(24)
        }
        .width('100%')
        .padding({ left: 14, right: 14 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().bg)
  }

  @Builder
  editor(title: string, value: string, isPrefix: boolean) {
    Column({ space: 5 }) {
      Text(title).fontSize(Font.xs).fontColor(this.pal().textTertiary)
      TextArea({ text: value, placeholder: isPrefix ? '# 在这里写下代码开头…' : '// 以及代码结尾…' })
        .placeholderColor(this.pal().textTertiary)
        .fontColor(this.pal().text)
        .fontSize(Font.mono)
        .backgroundColor(this.pal().surfaceAlt)
        .borderRadius(Dim.r10)
        .height(140)
        .onChange((v: string) => {
          if (isPrefix) {
            this.prefix = v;
          } else {
            this.suffix = v;
          }
        })
    }
    .layoutWeight(this.isWide ? 1 : 0)
    .width(this.isWide ? undefined : '100%')
    .alignItems(HorizontalAlign.Start)
  }
}

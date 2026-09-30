import { Themes, Palette, Dim, Font } from '../theme/Theme';
import { ChatMessage, SearchResult, ToolCall, Usage, WorkStep } from '../model/Types';
import { MsgStatus, Role } from '../common/Constants';
import { Utils } from '../common/Utils';
import { Pricing } from '../service/Pricing';
import { MarkdownView } from './MarkdownView';
import { IconBtn, Pill, TypingDots } from './Common';

/**
 * 消息气泡：用户消息右侧蓝底，AI 消息左侧卡片式
 * 含思维链折叠、工具调用、用量与成本、操作工具栏
 */
@Component
export struct MessageBubble {
  @ObjectLink msg: ChatMessage;
  @Prop dark: boolean = true;
  @Prop showStats: boolean = true;
  @Prop showCost: boolean = true;
  @Prop showReasoning: boolean = true;
  @Prop fontSize: number = 15;
  @Prop generating: boolean = false;
  /** 语音功能总开关 */
  @Prop speechEnabled: boolean = true;
  /** 当前正在朗读的消息 id（空表示没有） */
  @Prop speakingId: string = '';
  /** 消息状态变更信号；变化时把数据层状态同步到本地 @State，确保必然重渲染 */
  @Prop @Watch('onMsgTick') msgTick: number = 0;
  /** 思维链是否展开（本地状态，驱动渲染） */
  @State reasoningOpen: boolean = false;
  /** 是否展示 AI 工作过程 */
  @Prop showSteps: boolean = true;
  /** 工作过程默认展开（设置可调），默认折叠成一行「已完成 · N 秒」 */
  @Prop processDefaultOpen: boolean = false;
  /** 工作过程折叠区展开状态 */
  @State processOpen: boolean = false;
  /** 联网来源默认折叠（设置可调） */
  @Prop sourcesDefaultCollapsed: boolean = false;
  /** 来源列表展开状态 */
  @State sourcesOpen: boolean = true;
  onSpeak: (m: ChatMessage) => void = () => {};
  onCopy: (m: ChatMessage) => void = () => {};
  onRegenerate: (m: ChatMessage) => void = () => {};
  onDelete: (m: ChatMessage) => void = () => {};
  onEdit: (m: ChatMessage) => void = () => {};
  onOpenLink: (url: string) => void = () => {};
  onToggleReasoning: (m: ChatMessage) => void = () => {};

  /** 工作中状态的实时耗时。必须是 @State 才会触发重渲染 ——
   *  ArkUI 做的是元素级增量更新，直接在 build 里读 Date.now() 不会被追踪，
   *  表现为计时停在第一次渲染的数值上。 */
  @State elapsed: number = 0;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.reasoningOpen = this.msg.reasoningExpanded;
    this.processOpen = this.processDefaultOpen;
    this.sourcesOpen = !this.sourcesDefaultCollapsed;
    if (this.isWorking()) {
      this.startTimer();
    }
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  onMsgTick(): void {
    this.reasoningOpen = this.msg.reasoningExpanded;
    if (this.isWorking()) {
      this.startTimer();
    } else {
      this.stopTimer();
    }
  }

  private startTimer(): void {
    if (this.timerId !== -1) {
      return;
    }
    this.elapsed = this.msg.runStartedAt > 0 ? (Date.now() - this.msg.runStartedAt) : 0;
    this.timerId = setInterval(() => {
      if (!this.isWorking()) {
        this.stopTimer();
        return;
      }
      this.elapsed = this.msg.runStartedAt > 0 ? (Date.now() - this.msg.runStartedAt) : 0;
    }, 500);
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** 本轮是否仍在进行 */
  private isWorking(): boolean {
    return this.msg.status === MsgStatus.STREAMING || this.msg.status === MsgStatus.PENDING;
  }

  /** 是否有可折叠的工作过程 */
  private hasProcess(): boolean {
    return this.msg.steps.length > 0
      || (this.showReasoning && this.msg.reasoning.length > 0)
      || this.msg.toolCalls.length > 0;
  }

  /**
   * 折叠区标题：进行中显示「工作中 · 12.3 秒」，完成后显示「已完成 · 4 分 13 秒」。
   * 进行中用 runStartedAt 实时计时，驱动它刷新的是流式期间不断变化的 msgTick。
   */
  private processLabel(): string {
    if (this.isWorking()) {
      return '工作中' + (this.elapsed > 0 ? (' · ' + this.fmtDuration(this.elapsed)) : '');
    }
    let ms: number = this.msg.runMs;
    if (ms <= 0) {
      ms = this.totalStepMs();
    }
    if (ms <= 0) {
      ms = this.msg.latencyMs;
    }
    return '已完成' + (ms > 0 ? (' · ' + this.fmtDuration(ms)) : '');
  }

  private fmtDuration(ms: number): string {
    if (ms < 60000) {
      return (ms / 1000).toFixed(1) + ' 秒';
    }
    const total: number = Math.round(ms / 1000);
    return Math.floor(total / 60).toString() + ' 分 ' + (total % 60).toString() + ' 秒';
  }

  private pal(): Palette {
    return Themes.of(this.dark);
  }

  private isUser(): boolean {
    return this.msg.role === Role.USER;
  }

  build() {
    Column() {
      if (this.isUser()) {
        this.userRow()
      } else {
        this.aiRow()
      }
    }
    .width('100%')
    .alignItems(this.isUser() ? HorizontalAlign.End : HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

  /* ===================== 用户消息 ===================== */

  @Builder
  userRow() {
    Column() {
      if (this.msg.attachments.length > 0) {
        Row({ space: 6 }) {
          ForEach(this.msg.attachments, (a: AttachmentLike) => {
            Image(a.dataUrl)
              .width(84)
              .height(84)
              .objectFit(ImageFit.Cover)
              .borderRadius(Dim.r10)
              .border({ width: 1, color: this.pal().borderStrong })
          }, (a: AttachmentLike) => a.id)
        }
        .margin({ bottom: 6 })
        .justifyContent(FlexAlign.End)
      }

      if (this.msg.content.length > 0) {
        Text(this.msg.content)
          .fontSize(this.fontSize)
          .fontColor(this.pal().userBubbleText)
          .lineHeight(this.fontSize * 1.55)
          .textAlign(TextAlign.Start)
          .copyOption(CopyOptions.LocalDevice)
      }

      if (this.msg.prefix) {
        Row({ space: 4 }) {
          Image($r('app.media.ic_code')).width(11).height(11).fillColor(this.pal().userBubbleText)
          Text('前缀续写').fontSize(Font.xs).fontColor(this.pal().userBubbleText)
        }
        .margin({ top: 6 })
      }
    }
    .constraintSize({ maxWidth: '82%' })
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(this.pal().userBubble)
    .borderRadius({ topLeft: Dim.r18, topRight: Dim.r18, bottomLeft: Dim.r18, bottomRight: 6 })
    .shadow({ radius: 12, color: this.pal().shadow, offsetX: 0, offsetY: 3 })
    .gesture(LongPressGesture().onAction(() => this.onCopy(this.msg)))
  }

  /* ===================== AI 消息 ===================== */

  @Builder
  aiRow() {
    Column() {
      // 头部：模型 + 状态
      Row({ space: 6 }) {
        Image($r('app.media.ic_sparkle'))
          .width(12)
          .height(12)
          .fillColor(this.pal().accent)
        Text(this.msg.model.length > 0 ? this.msg.model : 'AI')
          .fontSize(Font.xs)
          .fontColor(this.pal().textTertiary)
        if (this.msg.status === MsgStatus.STREAMING) {
          Pill({ label: '生成中', fg: this.pal().accent, bg: this.pal().accentSoft, labelSize: 10 })
        } else if (this.msg.status === MsgStatus.STOPPED) {
          Pill({ label: '已停止', fg: this.pal().warning, bg: '#22F5B544', labelSize: 10 })
        } else if (this.msg.status === MsgStatus.ERROR) {
          Pill({ label: '失败', fg: this.pal().error, bg: '#22FF6B6B', labelSize: 10 })
        }
      }
      .margin({ bottom: 4, left: 2 })

      // 工作过程统一折叠区：步骤 / 思维链 / 工具调用
      if (this.showSteps && this.hasProcess()) {
        this.processPanel()
      }

      // 正文
      if (this.msg.content.length > 0) {
        MarkdownView({
          content: this.msg.content,
          dark: this.dark,
          baseFont: this.fontSize,
          onOpenLink: (u: string) => this.onOpenLink(u)
        })
      } else if (this.msg.status === MsgStatus.STREAMING && this.msg.reasoning.length === 0) {
        TypingDots({ color: this.pal().accent, dark: this.dark })
      }

      // 错误
      if (this.msg.status === MsgStatus.ERROR && this.msg.error.length > 0) {
        Row({ space: 8 }) {
          Image($r('app.media.ic_info')).width(15).height(15).fillColor(this.pal().error)
          Text(this.msg.error)
            .fontSize(Font.sm)
            .fontColor(this.pal().error)
            .layoutWeight(1)
            .copyOption(CopyOptions.LocalDevice)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#1AFF6B6B')
        .borderRadius(Dim.r10)
        .margin({ top: 6 })
        .alignItems(VerticalAlign.Top)
      }

      // 联网来源 / 搜索路由说明
      if ((this.msg.sources.length > 0 || this.msg.searchNote.length > 0)
        && this.msg.status !== MsgStatus.STREAMING) {
        this.sourcesPanel()
      }

      // 用量
      if (this.showStats && this.msg.usage !== null && this.msg.status !== MsgStatus.STREAMING) {
        this.usageRow()
      }

      // 操作
      if (this.msg.status !== MsgStatus.STREAMING) {
        this.actionRow()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 2, right: 2, top: 2, bottom: 4 })
  }

  private stepIcon(kind: string): Resource {
    if (kind === 'search') {
      return $r('app.media.ic_wifi');
    }
    if (kind === 'think') {
      return $r('app.media.ic_brain');
    }
    if (kind === 'tool') {
      return $r('app.media.ic_terminal');
    }
    return $r('app.media.ic_edit');
  }

  private stepColor(s: WorkStep): string {
    if (s.status === 'running') {
      return this.pal().accent;
    }
    if (s.status === 'failed') {
      return this.pal().error;
    }
    return this.pal().textSecondary;
  }

  /** 耗时格式化：<1s 用毫秒，否则用秒 */
  private fmtMs(ms: number): string {
    if (ms <= 0) {
      return '—';
    }
    if (ms < 1000) {
      return ms.toString() + 'ms';
    }
    return (ms / 1000).toFixed(1) + 's';
  }

  private totalStepMs(): number {
    let t: number = 0;
    for (let i = 0; i < this.msg.steps.length; i++) {
      t += this.msg.steps[i].ms;
    }
    return t;
  }

  /**
   * 工作过程统一折叠区。
   * 除正文外的所有过程信息（步骤 / 思维链 / 工具调用）都收进这里，
   * 折叠时只剩一行状态：进行中「工作中 · 12.3 秒」，完成后「已完成 · 4 分 13 秒」。
   */
  @Builder
  processPanel() {
    Column({ space: 0 }) {
      Row({ space: 7 }) {
        if (this.isWorking()) {
          TypingDots({ color: this.pal().accent, dark: this.dark })
        } else {
          Image($r('app.media.ic_check')).width(13).height(13).fillColor(this.pal().success)
        }
        Text(this.processLabel())
          .fontSize(Font.xs)
          .fontColor(this.isWorking() ? this.pal().accent : this.pal().textSecondary)
          .layoutWeight(1)
        Image(this.processOpen ? $r('app.media.ic_chevron_up') : $r('app.media.ic_chevron_right'))
          .width(13).height(13).fillColor(this.pal().textTertiary)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .onClick(() => {
        this.processOpen = !this.processOpen;
      })

      if (this.processOpen) {
        Divider().strokeWidth(1).color(this.pal().border)
        Column({ space: 10 }) {
          if (this.msg.steps.length > 0) {
            this.stepsBody()
          }
          if (this.showReasoning && this.msg.reasoning.length > 0) {
            this.reasoningPanel()
          }
          if (this.msg.toolCalls.length > 0) {
            this.toolPanel()
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 9, bottom: 10 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .backgroundColor(this.pal().surfaceAlt)
    .borderRadius(Dim.r12)
    .border({ width: 1, color: this.pal().border })
    .margin({ bottom: 8 })
    .clip(true)
  }

  /** 步骤清单本体（不含外框，供折叠区复用） */
  @Builder
  stepsBody() {
    Column({ space: 7 }) {
      ForEach(this.msg.steps, (s: WorkStep, idx: number) => {
            Row({ space: 8 }) {
              Image(this.stepIcon(s.kind))
                .width(12).height(12)
                .fillColor(this.stepColor(s))
                .margin({ top: 3 })
              Column({ space: 2 }) {
                Row({ space: 6 }) {
                  Text(s.title)
                    .fontSize(Font.xs)
                    .fontColor(this.pal().text)
                    .fontWeight(FontWeight.Medium)
                  Blank()
                  Text(s.status === 'running' ? '进行中' : this.fmtMs(s.ms))
                    .fontSize(Font.xs)
                    .fontColor(s.status === 'running' ? this.pal().accent : this.pal().textTertiary)
                }
                .width('100%')

                if (s.detail.length > 0) {
                  Text(s.detail)
                    .fontSize(Font.xs)
                    .fontColor(this.pal().textTertiary)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
                if (s.result.length > 0) {
                  Text('→ ' + s.result)
                    .fontSize(Font.xs)
                    .fontColor(this.pal().success)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
      }, (s: WorkStep, idx: number) => s.kind + '_' + idx.toString() + '_' + s.startedAt.toString())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  reasoningPanel() {
    Column() {
      Row({ space: 6 }) {
        Image($r('app.media.ic_brain'))
          .width(13)
          .height(13)
          .fillColor(this.pal().reasonText)
        Text('思维链')
          .fontSize(Font.xs)
          .fontColor(this.pal().reasonText)
        if (this.msg.usage !== null && this.msg.usage.reasoningTokens > 0) {
          Text('· ' + Utils.compact(this.msg.usage.reasoningTokens) + ' tokens')
            .fontSize(Font.xs)
            .fontColor(this.pal().textTertiary)
        }
        Blank()
        if (this.msg.status === MsgStatus.STREAMING && this.msg.content.length === 0) {
          TypingDots({ color: this.pal().reasonText, dark: this.dark })
        }
        Image(this.reasoningOpen ? $r('app.media.ic_chevron_up') : $r('app.media.ic_chevron_down'))
          .width(13)
          .height(13)
          .fillColor(this.pal().reasonText)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })

      if (this.reasoningOpen) {
        Divider().strokeWidth(1).color(this.pal().reasonBorder)
        Scroll() {
          Text(this.msg.reasoning)
            .fontSize(Font.sm)
            .fontColor(this.pal().reasonText)
            .lineHeight(Font.sm * 1.6)
            .padding({ left: 10, right: 10, top: 8, bottom: 10 })
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .constraintSize({ maxHeight: 260 })
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .backgroundColor(this.pal().reasonBg)
    .borderRadius(Dim.r12)
    .border({ width: 1, color: this.pal().reasonBorder })
    .margin({ bottom: 8 })
    .clip(true)
    .onClick(() => this.onToggleReasoning(this.msg))
  }

  /** 联网来源列表：可点击跳转 */
  @Builder
  sourcesPanel() {
    Column({ space: 5 }) {
      if (this.msg.sources.length > 0) {
        Row({ space: 5 }) {
          Image($r('app.media.ic_wifi')).width(12).height(12).fillColor(this.pal().accent)
          Text('联网来源 ' + this.msg.sources.length.toString() + ' 条')
            .fontSize(Font.xs)
            .fontColor(this.pal().accent)
            .layoutWeight(1)
          Image(this.sourcesOpen ? $r('app.media.ic_chevron_up') : $r('app.media.ic_chevron_down'))
            .width(12).height(12).fillColor(this.pal().accent)
        }
        .width('100%')
        .onClick(() => {
          this.sourcesOpen = !this.sourcesOpen;
        })
      }

      // 实际用的不是用户首选时给出说明，避免"我选了 A 怎么用了 B"的困惑
      if (this.msg.searchNote.length > 0) {
        Row({ space: 4 }) {
          Image($r('app.media.ic_info')).width(11).height(11).fillColor(this.pal().warning)
          Text(this.msg.searchNote)
            .fontSize(Font.xs)
            .fontColor(this.pal().warning)
            .layoutWeight(1)
        }
        .width('100%')
      }

      if (this.sourcesOpen) {
        ForEach(this.msg.sources, (s: SearchResult, idx: number) => {
          Row({ space: 6 }) {
            Text((idx + 1).toString())
              .fontSize(Font.xs)
              .fontColor(this.pal().accent)
              .width(14)
              .margin({ top: 2 })
            Column({ space: 2 }) {
              Text(s.title)
                .fontSize(Font.xs)
                .fontColor(this.pal().text)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              // 摘要：让用户不点开也能判断这条值不值得看
              if (s.snippet.length > 0) {
                Text(s.snippet)
                  .fontSize(Font.xs)
                  .fontColor(this.pal().textSecondary)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              Text(s.site)
                .fontSize(Font.xs)
                .fontColor(this.pal().textTertiary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ top: 5, bottom: 5 })
          .onClick(() => this.onOpenLink(s.url))
        }, (s: SearchResult, idx: number) => s.url + idx.toString())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(this.pal().surfaceAlt)
    .borderRadius(Dim.r10)
    .border({ width: 1, color: this.pal().border })
    .margin({ bottom: 8 })
  }

  @Builder
  toolPanel() {
    Column({ space: 6 }) {
      ForEach(this.msg.toolCalls, (t: ToolCall) => {
        Column() {
          Row({ space: 6 }) {
            Image($r('app.media.ic_terminal')).width(13).height(13).fillColor(this.pal().accent)
            Text(t.name)
              .fontSize(Font.xs)
              .fontColor(this.pal().accent)
              .fontFamily(Font.code)
            Blank()
            Image(t.status === 'done' ? $r('app.media.ic_check') : $r('app.media.ic_clock'))
              .width(12)
              .height(12)
              .fillColor(t.status === 'done' ? this.pal().success : this.pal().textTertiary)
          }
          .width('100%')

          if (t.arguments.length > 0) {
            Text(t.arguments)
              .fontSize(Font.xs)
              .fontColor(this.pal().textSecondary)
              .fontFamily(Font.code)
              .width('100%')
              .margin({ top: 4 })
              .copyOption(CopyOptions.LocalDevice)
          }
          if (t.result.length > 0) {
            Text(t.result)
              .fontSize(Font.xs)
              .fontColor(this.pal().textTertiary)
              .fontFamily(Font.code)
              .width('100%')
              .margin({ top: 3 })
              .copyOption(CopyOptions.LocalDevice)
          }
        }
        .width('100%')
        .padding(9)
        .backgroundColor(this.pal().surfaceAlt)
        .borderRadius(Dim.r10)
      }, (t: ToolCall) => t.id + t.status)
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  usageRow() {
    Row({ space: 8 }) {
      this.statItem('输入', Utils.compact(this.usage().promptTokens))
      this.statItem('输出', Utils.compact(this.usage().completionTokens))
      if (this.usage().cacheHitTokens > 0) {
        this.statItem('缓存命中', Utils.compact(this.usage().cacheHitTokens))
      }
      if (this.usage().reasoningTokens > 0) {
        this.statItem('思考', Utils.compact(this.usage().reasoningTokens))
      }
      if (this.showCost) {
        this.statItem('≈', Pricing.formatUsd(Pricing.estimate(this.msg.model, this.usage())))
      }
      if (this.msg.ttftMs > 0) {
        this.statItem('首字', (this.msg.ttftMs / 1000).toFixed(1) + 's')
      }
      if (this.msg.latencyMs > 0) {
        this.statItem('耗时', (this.msg.latencyMs / 1000).toFixed(1) + 's')
      }
    }
    .width('100%')
    .padding({ left: 2, top: 6, bottom: 2 })
  }

  private usage(): Usage {
    const u = this.msg.usage;
    if (u === null) {
      return emptyUsageLike();
    }
    return u;
  }

  @Builder
  statItem(k: string, v: string) {
    Row({ space: 3 }) {
      Text(k).fontSize(Font.xs).fontColor(this.pal().textTertiary)
      Text(v).fontSize(Font.xs).fontColor(this.pal().textSecondary)
    }
  }

  @Builder
  actionRow() {
    Row({ space: 2 }) {
      // 朗读：只对助手消息、且有正文时可用
      if (this.speechEnabled && !this.isUser() && this.msg.content.length > 0) {
        IconBtn({
          icon: this.speakingId === this.msg.id ? $r('app.media.ic_volume_off') : $r('app.media.ic_volume'),
          iconSize: 14,
          tint: this.speakingId === this.msg.id ? this.pal().accent : this.pal().textTertiary,
          pad: 6,
          onTap: () => this.onSpeak(this.msg)
        })
      }
      IconBtn({
        icon: $r('app.media.ic_copy'), iconSize: 14, tint: this.pal().textTertiary, pad: 6,
        onTap: () => this.onCopy(this.msg)
      })
      if (!this.isUser()) {
        IconBtn({
          icon: $r('app.media.ic_refresh'), iconSize: 14, tint: this.pal().textTertiary, pad: 6,
          disabled: this.generating,
          onTap: () => this.onRegenerate(this.msg)
        })
      }
      IconBtn({
        icon: $r('app.media.ic_edit'), iconSize: 14, tint: this.pal().textTertiary, pad: 6,
        onTap: () => this.onEdit(this.msg)
      })
      IconBtn({
        icon: $r('app.media.ic_trash'), iconSize: 14, tint: this.pal().textTertiary, pad: 6,
        onTap: () => this.onDelete(this.msg)
      })
    }
    .margin({ top: 2, left: -6 })
  }
}

/** 附件的最小接口，避免循环导入 */
interface AttachmentLike {
  id: string;
  dataUrl: string;
}

function emptyUsageLike(): Usage {
  const u: Usage = {
    promptTokens: 0, completionTokens: 0, totalTokens: 0,
    cacheHitTokens: 0, cacheMissTokens: 0, reasoningTokens: 0
  };
  return u;
}

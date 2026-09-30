import { Themes, Palette, Dim, Font } from '../theme/Theme';
import { ChatMessage } from '../model/Types';
import { MessageBubble } from './MessageBubble';
import { WelcomeView } from './WelcomeView';

/** 消息列表：自动吸底 + 空状态 */
@Component
export struct MessageList {
  @Link messages: ChatMessage[];
  @Prop dark: boolean = true;
  @Prop isWide: boolean = false;
  @Prop generating: boolean = false;
  @Prop fontSize: number = 15;
  @Prop showStats: boolean = true;
  @Prop showCost: boolean = true;
  @Prop showReasoning: boolean = true;
  /** 是否展示 AI 工作过程 */
  @Prop showSteps: boolean = true;
  /** 工作过程默认展开 */
  @Prop processDefaultOpen: boolean = false;
  /** 联网来源默认折叠 */
  @Prop sourcesDefaultCollapsed: boolean = false;
  @Prop providerName: string = '';
  @Prop modelName: string = '';
  /** 流式增量信号：仅在生成中才自动跟随到底部 */
  @Prop @Watch('onStreamTick') streamTick: number = 0;
  /** 消息条数变化：一定会跟随到底部 */
  @Prop @Watch('onCountChanged') count: number = 0;

  private scroller: Scroller = new Scroller();
  @State atBottom: boolean = true;
  private lastScroll: number = 0;

  /** 语音功能总开关 */
  @Prop speechEnabled: boolean = true;
  /** 正在朗读的消息 id */
  @Prop speakingId: string = '';
  /** 消息状态变更信号（透传给气泡，保证子组件重渲染） */
  @Prop msgTick: number = 0;

  onSpeak: (m: ChatMessage) => void = () => {};
  onCopy: (m: ChatMessage) => void = () => {};
  onRegenerate: (m: ChatMessage) => void = () => {};
  onDelete: (m: ChatMessage) => void = () => {};
  onEdit: (m: ChatMessage) => void = () => {};
  onOpenLink: (url: string) => void = () => {};
  onToggleReasoning: (m: ChatMessage) => void = () => {};
  onPickSuggestion: (prompt: string) => void = () => {};

  private pal(): Palette {
    return Themes.of(this.dark);
  }

  aboutToAppear(): void {
    // 首次布局完成后再吸底：mount 阶段列表还是空的，此刻 scrollEdge 不起作用，
    // 会导致打开历史会话时停在最旧的几条消息上
    setTimeout(() => {
      this.atBottom = true;
      this.lastScroll = 0;
      this.autoScroll();
    }, 150);
  }

  /** 滚动到底部（带节流） */
  private autoScroll(): void {
    if (!this.atBottom) {
      return;
    }
    const now: number = Date.now();
    if (now - this.lastScroll < 50) {
      return;
    }
    this.lastScroll = now;
    try {
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (e) {
    }
  }

  /**
   * 流式增量只应该在「正在生成」时把视图拉到底部。
   * 之前这里无条件滚动，导致点击「思维链」展开时 streamTick 递增，
   * 列表立刻弹到底部，用户根本看不到刚展开的思维链正文。
   */
  onStreamTick(): void {
    if (!this.generating) {
      return;
    }
    this.autoScroll();
  }

  /** 新增消息时跟随到底部 */
  onCountChanged(): void {
    this.autoScroll();
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      List({ scroller: this.scroller, space: 0 }) {
        if (this.messages.length === 0) {
          ListItem() {
            WelcomeView({
              dark: this.dark,
              providerName: this.providerName,
              modelName: this.modelName,
              isWide: this.isWide,
              onPick: (p: string) => this.onPickSuggestion(p)
            })
          }
        }

        ForEach(this.messages, (m: ChatMessage) => {
          ListItem() {
            MessageBubble({
              msg: m,
              dark: this.dark,
              showStats: this.showStats,
              showCost: this.showCost,
              showReasoning: this.showReasoning,
              showSteps: this.showSteps,
              processDefaultOpen: this.processDefaultOpen,
              sourcesDefaultCollapsed: this.sourcesDefaultCollapsed,
              fontSize: this.fontSize,
              generating: this.generating,
              speechEnabled: this.speechEnabled,
              speakingId: this.speakingId,
              msgTick: this.msgTick,
              onSpeak: (x: ChatMessage) => this.onSpeak(x),
              onCopy: (x: ChatMessage) => this.onCopy(x),
              onRegenerate: (x: ChatMessage) => this.onRegenerate(x),
              onDelete: (x: ChatMessage) => this.onDelete(x),
              onEdit: (x: ChatMessage) => this.onEdit(x),
              onOpenLink: (u: string) => this.onOpenLink(u),
              onToggleReasoning: (x: ChatMessage) => this.onToggleReasoning(x)
            })
          }
        }, (m: ChatMessage) => m.id)

        ListItem() {
          Row().height(6)
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(6)
      .onReachEnd(() => {
        this.atBottom = true;
      })
      .onScrollIndex((start: number, end: number) => {
        this.atBottom = end >= this.messages.length - 1;
      })

      if (!this.atBottom && this.messages.length > 0) {
        Stack() {
          Image($r('app.media.ic_chevron_down'))
            .width(17)
            .height(17)
            .fillColor(this.pal().text)
        }
        .width(38)
        .height(38)
        .backgroundColor(this.pal().elevated)
        .borderRadius(19)
        .border({ width: 1, color: this.pal().border })
        .shadow({ radius: 12, color: this.pal().shadow, offsetX: 0, offsetY: 3 })
        .margin({ right: 16, bottom: 14 })
        .onClick(() => {
          this.atBottom = true;
          try {
            this.scroller.scrollEdge(Edge.Bottom);
          } catch (e) {
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

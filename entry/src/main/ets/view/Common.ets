import { Themes, Palette, Dim, Font } from '../theme/Theme';

/** 通用图标按钮 */
@Component
export struct IconBtn {
  icon: Resource = $r('app.media.ic_sparkle');
  @Prop iconSize: number = 19;
  @Prop tint: string = '#FFFFFF';
  @Prop bg: string = '#00000000';
  @Prop pad: number = 8;
  @Prop radius: number = 12;
  @Prop disabled: boolean = false;
  onTap: () => void = () => {};

  build() {
    Stack() {
      Image(this.icon)
        .width(this.iconSize)
        .height(this.iconSize)
        .fillColor(this.tint)
        .objectFit(ImageFit.Contain)
    }
    .width(this.iconSize + this.pad * 2)
    .height(this.iconSize + this.pad * 2)
    .backgroundColor(this.bg)
    .borderRadius(this.radius)
    .opacity(this.disabled ? 0.35 : 1)
    .onClick(() => {
      if (!this.disabled) {
        this.onTap();
      }
    })
  }
}

/** 文字胶囊标签 */
@Component
export struct Pill {
  @Prop label: string = '';
  @Prop fg: string = '#FFFFFF';
  @Prop bg: string = '#22FFFFFF';
  @Prop strokeColor: string = '#00000000';
  @Prop labelSize: number = 11;
  @Prop icon: Resource | null = null;
  @Prop bold: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row({ space: 4 }) {
      if (this.icon !== null) {
        Image(this.icon)
          .width(this.labelSize + 3)
          .height(this.labelSize + 3)
          .fillColor(this.fg)
      }
      if (this.label.length > 0) {
        Text(this.label)
          .fontSize(this.labelSize)
          .fontColor(this.fg)
          .fontWeight(this.bold ? FontWeight.Medium : FontWeight.Normal)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.bg)
    .borderRadius(999)
    .border({ width: 1, color: this.strokeColor })
    .onClick(() => this.onTap())
  }
}

/** 卡片容器 */
@Component
export struct Card {
  @Prop dark: boolean = true;
  @Prop cardPadding: number = 14;
  @Prop radius: number = 16;
  @Prop bg: string = '';
  @Prop cardStroke: string = '';
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.cardPadding)
    .backgroundColor(this.bg.length > 0 ? this.bg : Themes.of(this.dark).surface)
    .borderRadius(this.radius)
    .border({ width: 1, color: this.cardStroke.length > 0 ? this.cardStroke : Themes.of(this.dark).border })
  }
}

/** 打字指示器 */
@Component
export struct TypingDots {
  @Prop color: string = '#9AA6BF';
  @Prop dark: boolean = true;
  @State phase: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval(() => {
      this.phase = (this.phase + 1) % 3;
    }, 320);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  build() {
    Row({ space: 5 }) {
      ForEach([0, 1, 2], (i: number) => {
        Circle()
          .width(7)
          .height(7)
          .fill(this.color)
          .opacity(this.phase === i ? 1 : 0.32)
          .animation({ duration: 220, curve: Curve.EaseInOut })
      }, (i: number) => 'dot' + i)
    }
    .height(20)
    .alignItems(VerticalAlign.Center)
  }
}

/** 空状态提示 */
@Component
export struct EmptyHint {
  @Prop dark: boolean = true;
  @Prop icon: Resource = $r('app.media.ic_sparkle');
  @Prop title: string = '';
  @Prop desc: string = '';

  build() {
    Column({ space: 10 }) {
      Image(this.icon)
        .width(34)
        .height(34)
        .fillColor(Themes.of(this.dark).textTertiary)
      Text(this.title)
        .fontSize(Font.base)
        .fontColor(Themes.of(this.dark).textSecondary)
      if (this.desc.length > 0) {
        Text(this.desc)
          .fontSize(Font.sm)
          .fontColor(Themes.of(this.dark).textTertiary)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding(28)
    .justifyContent(FlexAlign.Center)
  }
}

/** 细分割线 */
@Component
export struct HairLine {
  @Prop dark: boolean = true;
  @Prop lineMargin: number = 0;

  build() {
    Divider()
      .strokeWidth(1)
      .color(Themes.of(this.dark).border)
      .margin({ top: this.lineMargin, bottom: this.lineMargin })
  }
}

/** 页面小标题 */
@Component
export struct SectionTitle {
  @Prop dark: boolean = true;
  @Prop text: string = '';

  build() {
    Text(this.text)
      .fontSize(Font.sm)
      .fontColor(Themes.of(this.dark).textTertiary)
      .fontWeight(FontWeight.Medium)
      .margin({ top: Dim.s8, bottom: Dim.s6, left: Dim.s4 })
  }
}

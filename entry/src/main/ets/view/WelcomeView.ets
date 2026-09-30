import { Themes, Palette, Dim, Font } from '../theme/Theme';

export class Suggestion {
  title: string = '';
  desc: string = '';
  prompt: string = '';
  icon: Resource = $r('app.media.ic_sparkle');

  constructor(title: string, desc: string, prompt: string, icon: Resource) {
    this.title = title;
    this.desc = desc;
    this.prompt = prompt;
    this.icon = icon;
  }
}

/** 空会话欢迎页 */
@Component
export struct WelcomeView {
  @Prop dark: boolean = true;
  @Prop providerName: string = '';
  @Prop modelName: string = '';
  @Prop isWide: boolean = false;
  onPick: (prompt: string) => void = () => {};

  private pal(): Palette {
    return Themes.of(this.dark);
  }

  private suggestions(): Suggestion[] {
    const out: Suggestion[] = [];
    out.push(new Suggestion('深度思考', '让模型先推理再作答', '请一步步推理：一个农夫要带狼、羊、白菜过河，船只能带一样东西，怎么过？', $r('app.media.ic_brain')));
    out.push(new Suggestion('写代码', '生成并解释可运行代码', '用 ArkTS 写一个带缓存的双向链表 LRU，并逐行解释关键实现。', $r('app.media.ic_code')));
    out.push(new Suggestion('结构化输出', 'JSON 模式直接给出数据', '把「张三 28 岁，李四 34 岁」整理成 JSON 数组，字段为 name 和 age。', $r('app.media.ic_layers')));
    out.push(new Suggestion('长文总结', '利用 1M 上下文与缓存', '帮我设计一份《HarmonyOS 应用上架检查清单》，按类别分点列出。', $r('app.media.ic_file')));
    return out;
  }

  build() {
    Column() {
      Column({ space: 14 }) {
        // 品牌标识
        Stack() {
          Circle()
            .width(78)
            .height(78)
            .fill(this.pal().accentSoft)
          Image($r('app.media.ic_sparkle'))
            .width(40)
            .height(40)
            .fillColor(this.pal().accent)
        }

        Text('星枢 AI')
          .fontSize(Font.xxl)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)

        Text('HarmonyOS 原生 AI 助手 · 直连 DeepSeek 与 OpenAI')
          .fontSize(Font.sm)
          .fontColor(this.pal().textSecondary)
          .textAlign(TextAlign.Center)

        if (this.modelName.length > 0) {
          Row({ space: 6 }) {
            Circle().width(6).height(6).fill(this.pal().success)
            Text(this.providerName + ' · ' + this.modelName)
              .fontSize(Font.xs)
              .fontColor(this.pal().textTertiary)
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.pal().surfaceAlt)
          .borderRadius(999)
          .border({ width: 1, color: this.pal().border })
        }
      }
      .margin({ top: this.isWide ? 40 : 24, bottom: 26 })

      // 建议卡片
      if (this.isWide) {
        Row({ space: 10 }) {
          ForEach(this.suggestions(), (s: Suggestion) => {
            this.cardWide(s)
          }, (s: Suggestion) => s.title)
        }
        .width('100%')
      } else {
        Column({ space: 10 }) {
          ForEach(this.suggestions(), (s: Suggestion) => {
            this.cardTall(s)
          }, (s: Suggestion) => s.title)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 20 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  cardWide(s: Suggestion) {
    Column({ space: 8 }) {
      Image(s.icon).width(20).height(20).fillColor(this.pal().accent)
      Text(s.title)
        .fontSize(Font.sm).fontWeight(FontWeight.Medium).fontColor(this.pal().text).maxLines(1)
      Text(s.desc)
        .fontSize(Font.xs).fontColor(this.pal().textTertiary).maxLines(2).textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding(14)
    .backgroundColor(this.pal().surface)
    .borderRadius(Dim.r14)
    .border({ width: 1, color: this.pal().border })
    .onClick(() => this.onPick(s.prompt))
  }

  @Builder
  cardTall(s: Suggestion) {
    Row({ space: 12 }) {
      Stack() {
        Circle().width(34).height(34).fill(this.pal().accentSoft)
        Image(s.icon).width(18).height(18).fillColor(this.pal().accent)
      }
      Column({ space: 3 }) {
        Text(s.title).fontSize(Font.sm).fontWeight(FontWeight.Medium).fontColor(this.pal().text).maxLines(1)
        Text(s.desc).fontSize(Font.xs).fontColor(this.pal().textTertiary).maxLines(2)
          .textAlign(TextAlign.Start)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(13)
    .backgroundColor(this.pal().surface)
    .borderRadius(Dim.r14)
    .border({ width: 1, color: this.pal().border })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onPick(s.prompt))
  }
}

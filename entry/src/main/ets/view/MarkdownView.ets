import { Themes, Palette, Dim, Font } from '../theme/Theme';
import { Markdown, MdBlock, MdListItem, MdSpan } from './Markdown';
import { CodeBlock } from './CodeBlock';

/**
 * Markdown 渲染组件
 * 每个块都按 ArkUI 原生组件渲染，保证与系统字体/主题一致
 */
@Component
export struct MarkdownView {
  @Prop @Watch('onContentChanged') content: string = '';
  @Prop dark: boolean = true;
  @Prop baseFont: number = 15;
  @State blocks: MdBlock[] = [];
  onOpenLink: (url: string) => void = () => {};

  aboutToAppear(): void {
    this.rebuild();
  }

  onContentChanged(): void {
    this.rebuild();
  }

  private rebuild(): void {
    this.blocks = Markdown.parse(this.content);
  }

  private pal(): Palette {
    return Themes.of(this.dark);
  }

  build() {
    Column({ space: 2 }) {
      ForEach(this.blocks, (b: MdBlock, idx: number) => {
        if (b.kind === 'code') {
          CodeBlock({ code: b.code, lang: b.lang, dark: this.dark })
        } else if (b.kind === 'heading') {
          this.headingBlock(b)
        } else if (b.kind === 'list') {
          this.listBlock(b)
        } else if (b.kind === 'quote') {
          this.quoteBlock(b)
        } else if (b.kind === 'table') {
          this.tableBlock(b)
        } else if (b.kind === 'divider') {
          Divider()
            .strokeWidth(1)
            .color(this.pal().border)
            .margin({ top: 8, bottom: 8 })
        } else {
          this.paragraphBlock(b)
        }
      }, (b: MdBlock, idx: number) => idx + '_' + b.kind + '_' + b.code.length + '_' + b.spans.length)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /* ===================== 各类型块 ===================== */

  @Builder
  headingBlock(b: MdBlock) {
    Column() {
      this.spansText(b.spans, this.headingSize(b.level), this.pal().text, b.level <= 2 ? FontWeight.Bold : FontWeight.Medium)
    }
    .width('100%')
    .margin({ top: b.level <= 2 ? 12 : 9, bottom: b.level <= 2 ? 5 : 3 })
  }

  private headingSize(level: number): number {
    if (level === 1) {
      return this.baseFont + 7;
    }
    if (level === 2) {
      return this.baseFont + 4;
    }
    if (level === 3) {
      return this.baseFont + 2;
    }
    return this.baseFont + 1;
  }

  @Builder
  paragraphBlock(b: MdBlock) {
    Column() {
      this.spansText(b.spans, this.baseFont, this.pal().text, FontWeight.Normal)
    }
    .width('100%')
    .margin({ top: 3, bottom: 3 })
    .onClick(() => this.handleLinks(b.spans))
  }

  @Builder
  quoteBlock(b: MdBlock) {
    Row() {
      Column()
        .width(3)
        .borderRadius(2)
        .backgroundColor(this.pal().accent)
        .margin({ right: 10 })
        .alignSelf(ItemAlign.Stretch)
      Column() {
        this.spansText(b.spans, this.baseFont - 1, this.pal().textSecondary, FontWeight.Normal)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8, left: 2, right: 8 })
    .backgroundColor(this.pal().surfaceAlt)
    .borderRadius(Dim.r10)
    .margin({ top: 5, bottom: 5 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  listBlock(b: MdBlock) {
    Column({ space: 5 }) {
      ForEach(b.items, (it: MdListItem, i: number) => {
        Row() {
          if (it.isTask) {
            Stack() {
              if (it.checked) {
                Image($r('app.media.ic_check'))
                  .width(11)
                  .height(11)
                  .fillColor('#FFFFFF')
              }
            }
            .width(16)
            .height(16)
            .borderRadius(5)
            .backgroundColor(it.checked ? this.pal().accent : '#00000000')
            .border({ width: 1.4, color: it.checked ? this.pal().accent : this.pal().borderStrong })
            .margin({ right: 9, top: 2 })
          } else if (b.ordered) {
            Text((b.startIndex + i).toString() + '.')
              .fontSize(this.baseFont - 1)
              .fontColor(this.pal().textTertiary)
              .width(24)
              .textAlign(TextAlign.End)
              .margin({ right: 8 })
          } else {
            Column()
              .width(it.depth > 0 ? 5 : 6)
              .height(it.depth > 0 ? 5 : 6)
              .borderRadius(3)
              .backgroundColor(this.pal().accent)
              .margin({ right: 12, top: 9 })
          }
          Column() {
            this.spansText(it.spans, this.baseFont, this.pal().text, FontWeight.Normal)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 4 + it.depth * 16 })
        .alignItems(VerticalAlign.Top)
      }, (it: MdListItem, i: number) => 'li' + i)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 5, bottom: 5 })
  }

  @Builder
  tableBlock(b: MdBlock) {
    Scroll() {
      Column() {
        Row() {
          ForEach(b.headers, (h: string, i: number) => {
            Text(h)
              .fontSize(this.baseFont - 2)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal().text)
              .width(132)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }, (h: string, i: number) => 'th' + i)
        }
        .backgroundColor(this.pal().surfaceAlt)

        ForEach(b.rows, (row: string[], ri: number) => {
          Row() {
            ForEach(row, (cell: string, ci: number) => {
              Text(cell)
                .fontSize(this.baseFont - 2)
                .fontColor(this.pal().textSecondary)
                .width(132)
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .maxLines(4)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }, (cell: string, ci: number) => 'td' + ri + '_' + ci)
          }
          .border({ width: { top: 1 }, color: this.pal().border })
        }, (row: string[], ri: number) => 'tr' + ri)
      }
      .border({ width: 1, color: this.pal().border })
      .borderRadius(Dim.r10)
      .clip(true)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.TopStart)
    .margin({ top: 6, bottom: 6 })
  }

  /* ===================== 行内富文本 ===================== */

  @Builder
  spansText(spans: MdSpan[], size: number, color: string, weight: FontWeight) {
    Text() {
      ForEach(spans, (sp: MdSpan) => {
        if (sp.image.length > 0) {
          Span('[图片: ' + sp.text + ']')
            .fontSize(size - 1)
            .fontColor(this.pal().accent)
            .decoration({ type: TextDecorationType.Underline, color: this.pal().accent })
        } else {
          Span(sp.text)
            .fontSize(sp.code ? size - 1 : size)
            .fontColor(sp.code ? this.pal().inlineCodeText : (sp.link.length > 0 ? this.pal().accent : color))
            .fontWeight(sp.bold ? FontWeight.Bold : weight)
            .fontStyle(sp.italic ? FontStyle.Italic : FontStyle.Normal)
            .fontFamily(sp.code ? Font.code : 'HarmonyOS Sans')
            .decoration({
              type: sp.strike ? TextDecorationType.LineThrough
                : (sp.link.length > 0 ? TextDecorationType.Underline : TextDecorationType.None),
              color: sp.link.length > 0 ? this.pal().accent : color
            })
            .textBackgroundStyle(sp.code
              ? { color: this.pal().inlineCodeBg, radius: 5 }
              : { color: '#00000000', radius: 0 })
        }
      }, (sp: MdSpan, i: number) => 'sp' + i + sp.text.length)
    }
    .width('100%')
    .textAlign(TextAlign.Start)
    .lineHeight(size * 1.65)
    .copyOption(CopyOptions.LocalDevice)
    .wordBreak(WordBreak.BREAK_WORD)
  }

  private handleLinks(spans: MdSpan[]): void {
    const urls: string[] = [];
    for (let i = 0; i < spans.length; i++) {
      const u: string = spans[i].link.length > 0 ? spans[i].link : spans[i].image;
      if (u.length > 0 && urls.indexOf(u) < 0) {
        urls.push(u);
      }
    }
    if (urls.length === 0) {
      return;
    }
    this.onOpenLink(urls[0]);
  }
}

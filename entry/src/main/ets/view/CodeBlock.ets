import { Themes, Dim, Font } from '../theme/Theme';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

/** 代码块：语言标签 + 一键复制 + 横向滚动 */
@Component
export struct CodeBlock {
  @Prop code: string = '';
  @Prop lang: string = '';
  @Prop dark: boolean = true;
  @State copied: boolean = false;

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (e) {
      promptAction.showToast({ message: msg });
    }
  }

  private copy(): void {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.copied = true;
      setTimeout(() => {
        this.copied = false;
      }, 1400);
    } catch (e) {
      this.toast('复制失败');
    }
  }

  build() {
    Column() {
      Row() {
        Row({ space: 6 }) {
          Circle().width(6).height(6).fill(Themes.of(this.dark).accent)
          Text(this.lang.length > 0 ? this.lang : 'code')
            .fontSize(Font.xs)
            .fontColor(Themes.of(this.dark).textTertiary)
            .fontFamily(Font.code)
        }
        Blank()
        Row({ space: 4 }) {
          Image(this.copied ? $r('app.media.ic_check') : $r('app.media.ic_copy'))
            .width(13)
            .height(13)
            .fillColor(this.copied ? Themes.of(this.dark).success : Themes.of(this.dark).textTertiary)
          Text(this.copied ? '已复制' : '复制')
            .fontSize(Font.xs)
            .fontColor(this.copied ? Themes.of(this.dark).success : Themes.of(this.dark).textTertiary)
        }
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(8)
        .onClick(() => this.copy())
      }
      .width('100%')
      .padding({ left: 12, right: 8, top: 7, bottom: 7 })
      .backgroundColor(Themes.of(this.dark).codeHeader)

      Scroll() {
        Text(this.code)
          .fontSize(Font.mono)
          .fontFamily(Font.code)
          .fontColor(Themes.of(this.dark).codeText)
          .textAlign(TextAlign.Start)
          .padding(12)
          .copyOption(CopyOptions.LocalDevice)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .align(Alignment.TopStart)
    }
    .width('100%')
    .backgroundColor(Themes.of(this.dark).codeBg)
    .borderRadius(Dim.r12)
    .border({ width: 1, color: Themes.of(this.dark).border })
    .clip(true)
    .margin({ top: 6, bottom: 6 })
  }
}

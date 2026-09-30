import { Themes, Palette, Dim, Font } from '../theme/Theme';
import { Attachment, InferenceParams } from '../model/Types';
import { Utils } from '../common/Utils';
import { IconBtn, Pill } from './Common';

/** 输入区：自增高输入框 + 附件 + 发送/停止 + 快捷参数 */
@Component
export struct Composer {
  @Link text: string;
  @Link attachments: Attachment[];
  @Prop dark: boolean = true;
  @Prop generating: boolean = false;
  @Prop isWide: boolean = false;
  @Prop params: InferenceParams = new InferenceParams();
  @Prop modelName: string = '';
  @Prop canSend: boolean = true;
  /** 语音功能总开关 */
  @Prop speechEnabled: boolean = true;
  /** 正在识别 */
  @Prop listening: boolean = false;
  /** 实时音量 0~1，用于麦克风按钮的呼吸效果 */
  @Prop micLevel: number = 0;
  /** 联网搜索开关状态 */
  @Prop webSearch: boolean = false;
  /** 正在联网检索 */
  @Prop searching: boolean = false;

  onSend: () => void = () => {};
  onStop: () => void = () => {};
  onToggleMic: () => void = () => {};
  onPickImage: () => void = () => {};
  onRemoveAttachment: (id: string) => void = () => {};
  onOpenModelPicker: () => void = () => {};
  onOpenParams: () => void = () => {};
  onToggleThinking: () => void = () => {};
  onToggleTools: () => void = () => {};
  onToggleWebSearch: () => void = () => {};

  private pal(): Palette {
    return Themes.of(this.dark);
  }

  private thinkingLabel(): string {
    const t: string = this.params.thinking;
    if (t === 'off') {
      return '不思考';
    }
    if (t === 'auto') {
      return '自动';
    }
    return '思考:' + t;
  }

  build() {
    Column() {
      // 参数快捷条
      Scroll() {
        Row({ space: 6 }) {
          Pill({
            label: this.modelName.length > 0 ? this.modelName : '选择模型',
            fg: this.pal().accent,
            bg: this.pal().accentSoft,
            labelSize: 11,
            icon: $r('app.media.ic_sparkle'),
            onTap: () => this.onOpenModelPicker()
          })
          Pill({
            label: this.thinkingLabel(),
            fg: this.params.thinking === 'off' ? this.pal().textTertiary : this.pal().accent,
            bg: this.params.thinking === 'off' ? this.pal().surfaceAlt : this.pal().accentSoft,
            labelSize: 11,
            icon: $r('app.media.ic_brain'),
            onTap: () => this.onToggleThinking()
          })
          Pill({
            label: this.searching ? '搜索中…' : '联网',
            fg: this.webSearch ? this.pal().accent : this.pal().textTertiary,
            bg: this.webSearch ? this.pal().accentSoft : this.pal().surfaceAlt,
            labelSize: 11,
            icon: $r('app.media.ic_wifi'),
            onTap: () => this.onToggleWebSearch()
          })
          Pill({
            label: '工具',
            fg: this.params.enableTools ? this.pal().success : this.pal().textTertiary,
            bg: this.params.enableTools ? '#223DD68C' : this.pal().surfaceAlt,
            labelSize: 11,
            icon: $r('app.media.ic_terminal'),
            onTap: () => this.onToggleTools()
          })
          if (this.params.jsonMode) {
            Pill({ label: 'JSON', fg: this.pal().warning, bg: '#22F5B544', labelSize: 11, icon: $r('app.media.ic_layers'), onTap: () => this.onOpenParams() })
          }
          Pill({
            label: '参数',
            fg: this.pal().textSecondary,
            bg: this.pal().surfaceAlt,
            labelSize: 11,
            icon: $r('app.media.ic_settings'),
            onTap: () => this.onOpenParams()
          })
        }
        .padding({ left: 4, right: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .margin({ bottom: 8 })

      // 附件
      if (this.attachments.length > 0) {
        Row({ space: 8 }) {
          ForEach(this.attachments, (a: Attachment) => {
            Stack({ alignContent: Alignment.TopEnd }) {
              Image(a.dataUrl)
                .width(58)
                .height(58)
                .objectFit(ImageFit.Cover)
                .borderRadius(Dim.r10)
                .border({ width: 1, color: this.pal().border })
              Stack() {
                Image($r('app.media.ic_close')).width(10).height(10).fillColor('#FFFFFF')
              }
              .width(18)
              .height(18)
              .backgroundColor('#CC000000')
              .borderRadius(9)
              .margin({ top: -5, right: -5 })
              .onClick(() => this.onRemoveAttachment(a.id))
            }
          }, (a: Attachment) => a.id)
        }
        .width('100%')
        .margin({ bottom: 8 })
      }

      // 输入框
      Row({ space: 6 }) {
        IconBtn({
          icon: $r('app.media.ic_image'),
          iconSize: 19,
          tint: this.pal().textSecondary,
          pad: 8,
          onTap: () => this.onPickImage()
        })

        // 语音输入：点击开始 / 再点结束
        if (this.speechEnabled) {
          Stack() {
            // 呼吸光圈：随音量放大
            if (this.listening) {
              Stack()
                .width(30 + this.micLevel * 14)
                .height(30 + this.micLevel * 14)
                .borderRadius(22)
                .backgroundColor(this.pal().error)
                .opacity(0.18 + this.micLevel * 0.22)
            }
            Stack() {
              Image(this.listening ? $r('app.media.ic_waveform') : $r('app.media.ic_mic'))
                .width(18)
                .height(18)
                .fillColor(this.listening ? '#FFFFFF' : this.pal().textSecondary)
            }
            .width(30)
            .height(30)
            .backgroundColor(this.listening ? this.pal().error : '#00000000')
            .borderRadius(15)
          }
          .width(38)
          .height(38)
          .onClick(() => this.onToggleMic())
        }

        TextArea({
          text: this.text,
          placeholder: this.listening
            ? '正在聆听…'
            : ('发消息给 ' + (this.modelName.length > 0 ? this.modelName : 'AI') + '…')
        })
          .placeholderColor(this.listening ? this.pal().error : this.pal().textTertiary)
          .fontColor(this.pal().text)
          .fontSize(Font.base)
          .backgroundColor('#00000000')
          .borderRadius(0)
          .padding({ top: 9, bottom: 9 })
          .constraintSize({ minHeight: 40, maxHeight: 160 })
          .layoutWeight(1)
          .onChange((v: string) => {
            this.text = v;
          })
          .onSubmit(() => {
            if (this.canSend) {
              this.onSend();
            }
          })

        if (this.generating) {
          Stack() {
            Image($r('app.media.ic_stop')).width(17).height(17).fillColor('#FFFFFF')
          }
          .width(38)
          .height(38)
          .backgroundColor(this.pal().error)
          .borderRadius(19)
          .onClick(() => this.onStop())
        } else {
          Stack() {
            Image($r('app.media.ic_send'))
              .width(18)
              .height(18)
              .fillColor(this.canSend ? '#FFFFFF' : this.pal().textTertiary)
          }
          .width(38)
          .height(38)
          .backgroundColor(this.canSend ? this.pal().accent : this.pal().surfaceAlt)
          .borderRadius(19)
          .onClick(() => {
            if (this.canSend) {
              this.onSend();
            }
          })
        }
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 7, bottom: 7 })
      .backgroundColor(this.pal().inputBg)
      .borderRadius(this.isWide ? Dim.r20 : Dim.r20)
      .border({ width: 1, color: this.pal().border })

      // 底部提示
      Row({ space: 5 }) {
        if (this.searching) {
          Image($r('app.media.ic_wifi')).width(11).height(11).fillColor(this.pal().accent)
          Text('正在联网检索…')
            .fontSize(Font.xs)
            .fontColor(this.pal().accent)
        } else if (this.listening) {
          Image($r('app.media.ic_mic')).width(11).height(11).fillColor(this.pal().error)
          Text('正在聆听，说完点一下麦克风结束')
            .fontSize(Font.xs)
            .fontColor(this.pal().error)
        } else {
          Text(this.text.length > 0
            ? ('约 ' + Utils.estimateTokens(this.text) + ' tokens · ' + this.text.length + ' 字')
            : '内容由 AI 生成，请自行甄别')
            .fontSize(Font.xs)
            .fontColor(this.pal().textTertiary)
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 6 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 10 })
    .backgroundColor(this.pal().bg)
  }
}

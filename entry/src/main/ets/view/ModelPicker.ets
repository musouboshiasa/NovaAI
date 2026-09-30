import { Themes, Palette, Dim, Font } from '../theme/Theme';
import { ModelInfo, ProviderConfig } from '../model/Types';
import { ProviderFactory } from '../provider/ProviderFactory';
import { IconBtn, Pill } from './Common';

/** 模型选择面板：服务商切换 + 模型列表 + 自定义模型名 */
@Component
export struct ModelPicker {
  @Prop providers: ProviderConfig[] = [];
  @Prop activeProviderId: string = '';
  @Prop activeModel: string = '';
  @Prop dark: boolean = true;
  @Prop loading: boolean = false;
  @Prop errorText: string = '';
  @State customName: string = '';
  @State expandedProvider: string = '';

  onPick: (providerId: string, model: string) => void = () => {};
  onRefreshModels: (providerId: string) => void = () => {};
  onClose: () => void = () => {};

  private pal(): Palette {
    return Themes.of(this.dark);
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Image($r('app.media.ic_layers')).width(18).height(18).fillColor(this.pal().accent)
        Text('模型与服务商').fontSize(Font.lg).fontWeight(FontWeight.Bold).fontColor(this.pal().text).layoutWeight(1)
        if (this.loading) {
          LoadingProgress().width(18).height(18).color(this.pal().accent)
        }
        IconBtn({ icon: $r('app.media.ic_close'), iconSize: 16, tint: this.pal().textSecondary, onTap: () => this.onClose() })
      }
      .width('100%')
      .padding({ left: 18, right: 12, top: 14, bottom: 10 })

      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(Font.xs)
          .fontColor(this.pal().error)
          .width('100%')
          .padding({ left: 18, right: 18, bottom: 8 })
      }

      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.providers, (p: ProviderConfig) => {
            this.providerCard(p)
          }, (p: ProviderConfig) => p.id)
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 14 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().elevated)
  }

  @Builder
  providerCard(p: ProviderConfig) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Circle().width(9).height(9).fill(p.brandColor)
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(p.name).fontSize(Font.base).fontColor(this.pal().text).fontWeight(FontWeight.Medium)
            if (this.activeProviderId === p.id) {
              Pill({ label: '当前', fg: this.pal().accent, bg: this.pal().accentSoft, labelSize: 10 })
            }
          }
          Text(ProviderFactory.protocolLabel(p.protocol))
            .fontSize(Font.xs)
            .fontColor(this.pal().textTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (p.supportsModelList) {
          IconBtn({
            icon: $r('app.media.ic_refresh'),
            iconSize: 14,
            tint: this.pal().textTertiary,
            pad: 6,
            onTap: () => this.onRefreshModels(p.id)
          })
        }
        Image(this.expandedProvider === p.id ? $r('app.media.ic_chevron_up') : $r('app.media.ic_chevron_down'))
          .width(15)
          .height(15)
          .fillColor(this.pal().textTertiary)
      }
      .width('100%')
      .onClick(() => {
        this.expandedProvider = this.expandedProvider === p.id ? '' : p.id;
      })

      if (p.apiKey.length === 0 && !p.builtin) {
        Text('未配置 API Key')
          .fontSize(Font.xs)
          .fontColor(this.pal().warning)
      } else if (p.apiKey.length === 0 && p.builtin) {
        Text('尚未填写 API Key，请前往设置')
          .fontSize(Font.xs)
          .fontColor(this.pal().warning)
      }

      if (this.expandedProvider === p.id || (this.activeProviderId === p.id && this.expandedProvider === '')) {
        Column({ space: 5 }) {
          ForEach(p.models, (m: string) => {
            Row({ space: 8 }) {
              Text(m)
                .fontSize(Font.sm)
                .fontColor(this.activeModel === m && this.activeProviderId === p.id ? this.pal().accent : this.pal().text)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.activeModel === m && this.activeProviderId === p.id) {
                Image($r('app.media.ic_check')).width(15).height(15).fillColor(this.pal().accent)
              }
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 9, bottom: 9 })
            .backgroundColor(this.activeModel === m && this.activeProviderId === p.id ? this.pal().accentSoft : this.pal().surface)
            .borderRadius(Dim.r10)
            .onClick(() => this.onPick(p.id, m))
          }, (m: string) => p.id + ':' + m)

          if (p.models.length === 0) {
            Text('暂无模型，可点击刷新或手动输入模型名')
              .fontSize(Font.xs)
              .fontColor(this.pal().textTertiary)
              .width('100%')
              .padding({ top: 4, bottom: 4 })
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.pal().surface)
    .borderRadius(Dim.r14)
    .border({ width: 1, color: this.activeProviderId === p.id ? this.pal().accent : this.pal().border })
  }
}

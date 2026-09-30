import { Themes, Palette, Dim, Font } from '../theme/Theme';
import { SearchHit, SessionMeta } from '../model/Types';
import { Utils } from '../common/Utils';
import { IconBtn, Pill } from './Common';

/** 侧边栏：会话列表 + 品牌头部 + 底部设置入口 */
@Component
export struct Sidebar {
  @Link sessions: SessionMeta[];
  @Prop activeId: string = '';
  @Prop dark: boolean = true;
  @Prop isWide: boolean = false;
  @Prop balanceText: string = '';
  @Prop balanceOk: boolean = true;
  @Prop providerName: string = '';
  /** 全文搜索命中（标题 + 消息正文），由上层计算 */
  @Prop searchHits: SearchHit[] = [];
  /** 由上层持有，便于在输入时重算正文命中 */
  @Link keyword: string;

  onSelect: (id: string) => void = () => {};
  onExportSession: (id: string) => void = () => {};
  onExportAll: () => void = () => {};
  onNew: () => void = () => {};
  onDelete: (id: string) => void = () => {};
  onRename: (m: SessionMeta) => void = () => {};
  onPin: (m: SessionMeta) => void = () => {};
  onOpenSettings: () => void = () => {};
  onRefreshBalance: () => void = () => {};
  onClose: () => void = () => {};

  private pal(): Palette {
    return Themes.of(this.dark);
  }

  private filtered(): SessionMeta[] {
    const k: string = this.keyword.trim().toLowerCase();
    const list: SessionMeta[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      const s: SessionMeta = this.sessions[i];
      if (k.length === 0 || s.title.toLowerCase().indexOf(k) >= 0) {
        list.push(s);
      }
    }
    list.sort((a: SessionMeta, b: SessionMeta) => {
      if (a.pinned !== b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.updatedAt - a.updatedAt;
    });
    return list;
  }

  build() {
    Column() {
      // 头部
      Row({ space: 8 }) {
        Stack() {
          Circle().width(30).height(30).fill(this.pal().accentSoft)
          Image($r('app.media.ic_sparkle')).width(17).height(17).fillColor(this.pal().accent)
        }
        Column({ space: 1 }) {
          Text('星枢 AI').fontSize(Font.md).fontWeight(FontWeight.Bold).fontColor(this.pal().text)
          Text('HarmonyOS 客户端').fontSize(Font.xs).fontColor(this.pal().textTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (!this.isWide) {
          IconBtn({ icon: $r('app.media.ic_close'), iconSize: 16, tint: this.pal().textSecondary, onTap: () => this.onClose() })
        }
      }
      .width('100%')
      .padding({ left: 14, right: 10, top: 12, bottom: 10 })

      // 新建对话
      Row({ space: 8 }) {
        Image($r('app.media.ic_plus')).width(16).height(16).fillColor('#FFFFFF')
        Text('新建对话').fontSize(Font.base).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .height(42)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.pal().accent)
      .borderRadius(Dim.r12)
      .margin({ left: 12, right: 12, bottom: 10 })
      .onClick(() => this.onNew())

      // 搜索
      Row({ space: 8 }) {
        Image($r('app.media.ic_search')).width(15).height(15).fillColor(this.pal().textTertiary)
        TextInput({ text: this.keyword, placeholder: '搜索会话' })
          .placeholderColor(this.pal().textTertiary)
          .fontColor(this.pal().text)
          .fontSize(Font.sm)
          .backgroundColor('#00000000')
          .padding(0)
          .height(34)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.keyword = v;
          })
        if (this.keyword.trim().length > 0) {
          IconBtn({
            icon: $r('app.media.ic_close'), iconSize: 13, tint: this.pal().textTertiary, pad: 4,
            onTap: () => { this.keyword = ''; }
          })
        }
        IconBtn({
          icon: $r('app.media.ic_export'), iconSize: 15, tint: this.pal().textTertiary, pad: 4,
          onTap: () => this.onExportAll()
        })
      }
      .width('100%')
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.pal().surfaceAlt)
      .borderRadius(Dim.r10)
      .margin({ left: 12, right: 12, bottom: 8 })

      // 正文命中：搜索词出现在消息内容里
      if (this.keyword.trim().length > 0 && this.searchHits.length > 0) {
        Row({ space: 6 }) {
          Image($r('app.media.ic_search')).width(12).height(12).fillColor(this.pal().accent)
          Text('正文命中 ' + this.searchHits.length + ' 处')
            .fontSize(Font.xs).fontColor(this.pal().accent).layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 4 })

        List({ space: 2 }) {
          ForEach(this.searchHits, (h: SearchHit) => {
            ListItem() {
              this.hitRow(h)
            }
          }, (h: SearchHit) => h.sessionId + '_' + h.matchCount.toString())
        }
        .constraintSize({ maxHeight: 200 })
        .width('100%')
        .padding({ left: 8, right: 8 })
        .scrollBar(BarState.Off)
        .margin({ bottom: 6 })
      }

      // 列表
      List({ space: 2 }) {
        ForEach(this.filtered(), (m: SessionMeta) => {
          ListItem() {
            this.sessionRow(m)
          }
          .swipeAction({ end: this.swipeDelete(m) })
          .bindContextMenu(this.sessionMenu(m), ResponseType.LongPress)
        }, (m: SessionMeta) => m.id)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 8, right: 8 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 底部
      Column({ space: 8 }) {
        Divider().strokeWidth(1).color(this.pal().border)

        Row({ space: 8 }) {
          Image($r('app.media.ic_wallet')).width(15).height(15)
            .fillColor(this.balanceOk ? this.pal().success : this.pal().textTertiary)
          Column({ space: 1 }) {
            Text('账户余额').fontSize(Font.xs).fontColor(this.pal().textTertiary)
            Text(this.balanceText.length > 0 ? this.balanceText : '点击查询')
              .fontSize(Font.sm)
              .fontColor(this.pal().text)
              .fontWeight(FontWeight.Medium)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Image($r('app.media.ic_refresh')).width(14).height(14).fillColor(this.pal().textTertiary)
        }
        .width('100%')
        .padding(10)
        .backgroundColor(this.pal().surfaceAlt)
        .borderRadius(Dim.r12)
        .onClick(() => this.onRefreshBalance())

        Row({ space: 8 }) {
          Image($r('app.media.ic_settings')).width(18).height(18).fillColor(this.pal().textSecondary)
          Text('设置').fontSize(Font.base).fontColor(this.pal().text).layoutWeight(1)
          Text(this.providerName).fontSize(Font.xs).fontColor(this.pal().textTertiary)
          Image($r('app.media.ic_chevron_right')).width(14).height(14).fillColor(this.pal().textTertiary)
        }
        .width('100%')
        .padding(12)
        .borderRadius(Dim.r12)
        .onClick(() => this.onOpenSettings())
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 10 })
    }
    .height('100%')
    .backgroundColor(this.pal().surface)
    .border({ width: { right: this.isWide ? 1 : 0 }, color: this.pal().border })
  }

  @Builder
  swipeDelete(m: SessionMeta) {
    Row() {
      Image($r('app.media.ic_trash')).width(18).height(18).fillColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pal().error)
    .borderRadius(Dim.r12)
    .margin({ left: 6 })
    .onClick(() => this.onDelete(m.id))
  }

  /** 正文命中行：标题 + 摘要 + 命中次数 */
  @Builder
  hitRow(h: SearchHit) {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        Image(h.role === 'user' ? $r('app.media.ic_user') : $r('app.media.ic_sparkle'))
          .width(11).height(11)
          .fillColor(h.role === 'user' ? this.pal().textSecondary : this.pal().accent)
        Text(h.title)
          .fontSize(Font.xs)
          .fontColor(this.pal().text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(h.matchCount + ' 处')
          .fontSize(Font.xs)
          .fontColor(this.pal().accent)
      }
      .width('100%')

      Text(h.snippet.length > 0 ? h.snippet : '命中标题')
        .fontSize(Font.xs)
        .fontColor(this.pal().textTertiary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .backgroundColor(this.pal().surfaceAlt)
    .borderRadius(Dim.r10)
    .onClick(() => this.onSelect(h.sessionId))
  }

  /** 长按会话弹出的菜单 */
  @Builder
  sessionMenu(m: SessionMeta) {
    Menu() {
      MenuItem({ content: '重命名' })
        .onClick(() => this.onRename(m))
      MenuItem({ content: '导出为 Markdown' })
        .onClick(() => this.onExportSession(m.id))
      MenuItem({ content: m.pinned ? '取消置顶' : '置顶' })
        .onClick(() => this.onPin(m))
      MenuItem({ content: '删除' })
        .onClick(() => this.onDelete(m.id))
    }
  }

  @Builder
  sessionRow(m: SessionMeta) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        if (m.pinned) {
          Image($r('app.media.ic_pin')).width(11).height(11).fillColor(this.pal().accent)
        }
        Text(m.title)
          .fontSize(Font.sm)
          .fontColor(this.pal().text)
          .fontWeight(this.activeId === m.id ? FontWeight.Medium : FontWeight.Normal)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(Utils.relativeTime(m.updatedAt))
          .fontSize(Font.xs)
          .fontColor(this.pal().textTertiary)
      }
      .width('100%')

      Row({ space: 6 }) {
        Text(m.model.length > 0 ? m.model : '—')
          .fontSize(Font.xs)
          .fontColor(this.pal().textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        Text(m.messageCount + ' 条')
          .fontSize(Font.xs)
          .fontColor(this.pal().textTertiary)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .backgroundColor(this.activeId === m.id ? this.pal().accentSoft : '#00000000')
    .borderRadius(Dim.r12)
    .onClick(() => this.onSelect(m.id))
    .gesture(LongPressGesture().onAction(() => this.onRename(m)))
  }
}

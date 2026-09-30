import { Themes, Palette, Dim, Font, Themes as Th } from '../theme/Theme';
import { AppSettings, InferenceParams, ProviderConfig, SearchConfig, SearchTestResult } from '../model/Types';
import { SearchService } from '../service/SearchService';
import { ThemeMode } from '../common/Constants';
import { ProviderFactory } from '../provider/ProviderFactory';
import { Constants } from '../common/Constants';
import { IconBtn, Pill, SectionTitle } from './Common';
import { Utils } from '../common/Utils';

const THEME_OPTIONS: string[] = [ThemeMode.SYSTEM, ThemeMode.LIGHT, ThemeMode.DARK];
const THINKING_OPTIONS: string[] = ['auto', 'off', 'low', 'high', 'max'];
const PROTOCOLS: string[] = ['chat_completions', 'responses', 'anthropic'];
const FLAVORS: string[] = ['deepseek', 'openai', 'anthropic', 'generic'];

/** 可折叠设置分组容器 */
@Component
export struct SettingSection {
  @Prop dark: boolean = true;
  @Prop title: string = '';
  @Prop icon: Resource = $r('app.media.ic_info');
  @Prop expanded: boolean = false;
  onToggle: () => void = () => {};
  @BuilderParam content: () => void;

  build() {
    Column() {
      Row({ space: 8 }) {
        Image(this.icon).width(16).height(16).fillColor(Themes.of(this.dark).accent)
        Text(this.title)
          .fontSize(Font.base)
          .fontColor(Themes.of(this.dark).text)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Image(this.expanded ? $r('app.media.ic_chevron_up') : $r('app.media.ic_chevron_down'))
          .width(15).height(15).fillColor(Themes.of(this.dark).textTertiary)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 13, bottom: 13 })
      .onClick(() => this.onToggle())

      if (this.expanded) {
        Divider().strokeWidth(1).color(Themes.of(this.dark).border)
        Column() {
          this.content()
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 12 })
      }
    }
    .width('100%')
    .backgroundColor(Themes.of(this.dark).surface)
    .borderRadius(Dim.r14)
    .border({ width: 1, color: Themes.of(this.dark).border })
    .clip(true)
  }
}

/** 设置页 */
@Component
export struct SettingsPage {
  @ObjectLink settings: AppSettings;
  @ObjectLink params: InferenceParams;
  @Prop dark: boolean = true;
  @Prop isWide: boolean = false;
  @State expanded: string = 'appearance';

  onClose: () => void = () => {};
  onSave: () => void = () => {};
  onAddProvider: () => void = () => {};
  onDeleteProvider: (id: string) => void = () => {};
  onExport: () => void = () => {};
  onClearAll: () => void = () => {};
  onTestProvider: (id: string) => void = () => {};
  /** 搜索后端连通性测试 */
  @Prop searchTesting: boolean = false;
  @Prop searchTest: SearchTestResult[] = [];
  onTestSearch: () => void = () => {};

  private pal(): Palette {
    return Themes.of(this.dark);
  }

  private toggleSection(key: string): void {
    this.expanded = this.expanded === key ? '' : key;
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 8 }) {
        IconBtn({ icon: $r('app.media.ic_arrow_left'), iconSize: 18, tint: this.pal().text, onTap: () => this.onClose() })
        Text('设置').fontSize(Font.lg).fontWeight(FontWeight.Bold).fontColor(this.pal().text).layoutWeight(1)
        Text('自动保存').fontSize(Font.xs).fontColor(this.pal().textTertiary)
      }
      .width('100%')
      .padding({ left: 8, right: 14, top: 8, bottom: 8 })

      Scroll() {
        Column({ space: 10 }) {
          this.appearanceSection()
          this.speechSection()
          this.webSearchSection()
          this.chatSection()
          this.paramsSection()
          this.providersSection()
          this.dataSection()
          this.aboutSection()
          Row().height(30)
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().bg)
  }

  /* ===================== 通用外壳 ===================== */

  
  /**
   * 标签 + 说明，**只能放在 Row 里**。
   * 末尾的 .layoutWeight(1) 在 Row 中用于撑开、把右侧控件顶到最右边；
   * 若直接当作 Column 的子元素，它会吞掉整个纵向剩余空间，
   * 把后面的控件压成零高度（既不渲染也不出现在 UI 树里，且不报任何错）。
   * Column 里请改用 stackLabel()。
   */
  @Builder
  rowLabel(title: string, desc: string) {
    Column({ space: 2 }) {
      Text(title).fontSize(Font.sm).fontColor(this.pal().text)
      if (desc.length > 0) {
        Text(desc).fontSize(Font.xs).fontColor(this.pal().textTertiary)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  /** 供 Column 直接使用的标签：不带 layoutWeight，占满整行但不抢纵向空间 */
  @Builder
  stackLabel(title: string, desc: string) {
    Column({ space: 2 }) {
      Text(title).fontSize(Font.sm).fontColor(this.pal().text)
      if (desc.length > 0) {
        Text(desc).fontSize(Font.xs).fontColor(this.pal().textTertiary)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /* ===================== 外观 ===================== */

  @Builder
  appearanceSection() {
    SettingSection({
      dark: this.dark,
      title: '外观',
      icon: $r('app.media.ic_eye'),
      expanded: this.expanded === 'appearance',
      onToggle: () => this.toggleSection('appearance')
    }) {
      this.appearanceBody()
      }
  }

  @Builder
  appearanceBody() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        this.rowLabel('主题模式', this.settings.themeMode === ThemeMode.SYSTEM ? '跟随系统深浅色' : '')
        Row({ space: 4 }) {
          ForEach(THEME_OPTIONS, (o: string) => {
            Pill({
              label: o === 'system' ? '跟随' : (o === 'light' ? '亮色' : '暗色'),
              fg: this.settings.themeMode === o ? '#FFFFFF' : this.pal().textSecondary,
              bg: this.settings.themeMode === o ? this.pal().accent : this.pal().surfaceAlt,
              labelSize: 11,
              onTap: () => {
                this.settings.themeMode = o;
                this.onSave();
              }
            })
          }, (o: string) => o)
        }
      }
      .width('100%')

      Column({ space: 6 }) {
        Row() {
          this.rowLabel('正文字号', this.settings.fontSize + ' vp')
        }
        Slider({
          value: this.settings.fontSize,
          min: 12,
          max: 20,
          step: 1,
          style: SliderStyle.OutSet
        })
          .selectedColor(this.pal().accent)
          .trackColor(this.pal().surfaceAlt)
          .blockColor(this.pal().accent)
          .onChange((v: number) => {
            this.settings.fontSize = Math.round(v);
            this.onSave();
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  /* ===================== 语音 ===================== */

  @Builder
  speechSection() {
    SettingSection({
      dark: this.dark,
      title: '语音',
      icon: $r('app.media.ic_mic'),
      expanded: this.expanded === 'speech',
      onToggle: () => this.toggleSection('speech')
    }) {
      this.speechBody()
      }
  }

  @Builder
  speechBody() {
    Column({ space: 12 }) {
      Row() {
        this.rowLabel('离线语音', '朗读与语音输入均走端侧引擎（CoreSpeechKit），不消耗流量')
      }
      .width('100%')

      this.switchRow('启用语音功能', '输入框显示麦克风按钮，助手消息显示朗读按钮',
        this.settings.speechEnabled, (v: boolean) => {
          this.settings.speechEnabled = v;
          this.onSave();
        })

      this.switchRow('自动朗读回复', '每轮回答完成后自动播报',
        this.settings.ttsAutoRead, (v: boolean) => {
          this.settings.ttsAutoRead = v;
          this.onSave();
        })

      Column({ space: 4 }) {
        Row() {
          this.rowLabel('朗读语速', '0.5x ~ 2.0x')
          Text(this.settings.ttsSpeed.toFixed(1) + 'x')
            .fontSize(Font.xs).fontColor(this.pal().accent)
        }
        Slider({ value: this.settings.ttsSpeed, min: 0.5, max: 2, step: 0.1, style: SliderStyle.OutSet })
          .selectedColor(this.pal().accent).trackColor(this.pal().surfaceAlt).blockColor(this.pal().accent)
          .onChange((v: number) => {
            this.settings.ttsSpeed = Math.round(v * 10) / 10;
            this.onSave();
          })
      }
      .width('100%')

      this.switchRow('识别后自动发送', '说完直接发出去，不用再点发送',
        this.settings.speechAutoSend, (v: boolean) => {
          this.settings.speechAutoSend = v;
          this.onSave();
        })

      Column({ space: 6 }) {
        Row() {
          this.rowLabel('识别语言', '离线引擎支持的语言')
        }
        .width('100%')
        Row({ space: 6 }) {
          this.langChip('中文', 'zh-CN')
          this.langChip('English', 'en-US')
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  /* ===================== 联网搜索 ===================== */

  @Builder
  webSearchSection() {
    SettingSection({
      dark: this.dark,
      title: '联网搜索',
      icon: $r('app.media.ic_wifi'),
      expanded: this.expanded === 'search',
      onToggle: () => this.toggleSection('search')
    }) {
      this.webSearchBody()
      }
  }

  /** 自动模式下的当前候选顺序说明 */
  private autoHint(): string {
    const cfg: SearchConfig = new SearchConfig();
    cfg.backend = 'auto';
    cfg.endpoint = this.settings.webSearchEndpoint;
    cfg.maxResults = this.settings.webSearchMax;
    cfg.region = this.effectiveRegion();
    const order: string[] = SearchService.rankedOrder(cfg);
    if (order.length === 0) {
      return '没有可用的后端，请检查网络或配置 SearXNG 实例';
    }
    const labels: string[] = [];
    for (let i = 0; i < order.length; i++) {
      labels.push(SearchService.backendLabel(order[i]));
    }
    return '当前顺序：' + labels.join(' → ');
  }

  /**
   * 选项胶囊。
   * 这几个选项都是固定小集合，刻意**不用 ForEach 遍历数组字面量** ——
   * 实测 ForEach 套内联数组时会出现"容器占位但子节点不渲染"的情况
   * （语音分区的语言选择、联网分区的后端与地区选择都中过招）。
   */
  @Builder
  backendChip(label: string, value: string) {
    Text(label)
      .fontSize(Font.xs)
      .fontColor(this.settings.webSearchBackend === value ? '#FFFFFF' : this.pal().textSecondary)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.settings.webSearchBackend === value ? this.pal().accent : this.pal().surfaceAlt)
      .borderRadius(Dim.r20)
      .onClick(() => {
        this.settings.webSearchBackend = value;
        this.onSave();
      })
  }

  @Builder
  regionChip(label: string, value: string) {
    Text(label)
      .fontSize(Font.xs)
      .fontColor(this.effectiveRegion() === value ? '#FFFFFF' : this.pal().textSecondary)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.effectiveRegion() === value ? this.pal().accent : this.pal().surfaceAlt)
      .borderRadius(Dim.r20)
      .onClick(() => {
        this.settings.webSearchRegion = value;
        this.onSave();
      })
  }

  @Builder
  langChip(label: string, value: string) {
    Text(label)
      .fontSize(Font.xs)
      .fontColor(this.settings.speechLanguage === value ? '#FFFFFF' : this.pal().textSecondary)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.settings.speechLanguage === value ? this.pal().accent : this.pal().surfaceAlt)
      .borderRadius(Dim.r20)
      .onClick(() => {
        this.settings.speechLanguage = value;
        this.onSave();
      })
  }

  /** 当前生效的搜索地区（未显式设置时跟随界面语言） */
  private effectiveRegion(): string {
    if (this.settings.webSearchRegion.length > 0) {
      return this.settings.webSearchRegion;
    }
    return SearchService.regionFor(this.settings.language);
  }

  @Builder
  webSearchBody() {
    Column({ space: 12 }) {
      Row() {
        this.rowLabel('联网搜索', '开启后先检索网络，把结果作为上下文交给模型，并在回答下方列出来源。三个后端均无需 API Key。')
      }
      .width('100%')

      Column({ space: 6 }) {
        Row() {
          this.rowLabel('搜索后端', '「自动」会记住各后端的成败与耗时，优先用最快可用的那个')
        }
        .width('100%')
        Row({ space: 6 }) {
          this.backendChip('自动', 'auto')
          this.backendChip('Bing', 'bing')
          this.backendChip('DuckDuckGo', 'duckduckgo')
          this.backendChip('SearXNG', 'searxng')
        }
        .width('100%')

      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.settings.webSearchBackend === 'searxng') {
        Column({ space: 6 }) {
          Row() {
            this.rowLabel('SearXNG 实例', '例如 https://searx.be（需在实例设置里开启 json 输出）')
          }
          .width('100%')
          TextInput({ text: this.settings.webSearchEndpoint, placeholder: 'https://searx.example.com' })
            .placeholderColor(this.pal().textTertiary)
            .fontColor(this.pal().text)
            .fontSize(Font.sm)
            .backgroundColor(this.pal().surfaceAlt)
            .borderRadius(Dim.r10)
            .height(40)
            .onChange((v: string) => {
              this.settings.webSearchEndpoint = v;
              this.onSave();
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Column({ space: 6 }) {
        Row() {
          this.rowLabel('搜索地区', '影响 Bing 的市场参数（mkt），决定结果的语言与站点偏向')
        }
        .width('100%')
        Row({ space: 6 }) {
          this.regionChip('中国', 'zh-CN')
          this.regionChip('全球（英文）', 'en-US')
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Row() {
          this.rowLabel('注入条数', '结果越多上下文越长，也越费 token')
          Text(this.settings.webSearchMax.toString() + ' 条')
            .fontSize(Font.xs).fontColor(this.pal().accent)
        }
        Slider({ value: this.settings.webSearchMax, min: 3, max: 10, step: 1, style: SliderStyle.OutSet })
          .selectedColor(this.pal().accent).trackColor(this.pal().surfaceAlt).blockColor(this.pal().accent)
          .onChange((v: number) => {
            this.settings.webSearchMax = Math.round(v);
            this.onSave();
          })
      }
      .width('100%')

      this.switchRow('展示来源列表', '在回答下方列出引用来源，可点击打开',
        this.settings.webSearchShowSources, (v: boolean) => {
          this.settings.webSearchShowSources = v;
          this.onSave();
        })
      if (this.settings.webSearchShowSources) {
        this.switchRow('联网来源默认折叠', '关闭时直接展开来源列表（含标题与摘要），开启则折叠成一行',
          this.settings.sourcesDefaultCollapsed, (v: boolean) => {
            this.settings.sourcesDefaultCollapsed = v;
            this.onSave();
          })
      }

      // 连通性测试：逐个后端实打实请求一次，避免"配了但根本不通"
      Row({ space: 8 }) {
        Image($r('app.media.ic_refresh')).width(15).height(15)
          .fillColor(this.searchTesting ? this.pal().textTertiary : this.pal().accent)
        Text(this.searchTesting ? '正在测试三个后端…' : '测试搜索')
          .fontSize(Font.sm)
          .fontColor(this.searchTesting ? this.pal().textTertiary : this.pal().accent)
          .layoutWeight(1)
      }
      .width('100%')
      .height(42)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.searchTesting ? this.pal().surfaceAlt : this.pal().accentSoft)
      .borderRadius(Dim.r10)
      .onClick(() => {
        if (!this.searchTesting) {
          this.onTestSearch();
        }
      })

      if (this.settings.webSearchBackend === 'auto') {
        Row({ space: 6 }) {
          Image($r('app.media.ic_info')).width(12).height(12).fillColor(this.pal().textTertiary)
          Text(this.autoHint())
            .fontSize(Font.xs)
            .fontColor(this.pal().textTertiary)
            .layoutWeight(1)
        }
        .width('100%')
      }

      if (this.searchTest.length > 0) {
        Column({ space: 6 }) {
          ForEach(this.searchTest, (t: SearchTestResult) => {
            Row({ space: 8 }) {
              Text(t.skipped ? '—' : (t.ok ? '✓' : '✗'))
                .fontSize(Font.sm)
                .fontColor(t.skipped ? this.pal().textTertiary : (t.ok ? this.pal().success : this.pal().error))
                .width(14)
              Text(SearchService.backendLabel(t.backend))
                .fontSize(Font.xs)
                .fontColor(this.pal().text)
                .width(88)
              Column({ space: 1 }) {
                Text(t.skipped ? t.error
                  : (t.ok ? (t.count.toString() + ' 条 · ' + t.ms.toString() + 'ms') : t.error))
                  .fontSize(Font.xs)
                  .fontColor(t.ok ? this.pal().success : this.pal().warning)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                if (t.ok && t.sample.length > 0) {
                  Text(t.sample)
                    .fontSize(Font.xs)
                    .fontColor(this.pal().textTertiary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (t: SearchTestResult) => t.backend)
        }
        .width('100%')
        .padding(10)
        .backgroundColor(this.pal().surfaceAlt)
        .borderRadius(Dim.r10)
      }
    }
    .width('100%')
  }

  /* ===================== 对话 ===================== */

  @Builder
  chatSection() {
    SettingSection({
      dark: this.dark,
      title: '对话',
      icon: $r('app.media.ic_newchat'),
      expanded: this.expanded === 'chat',
      onToggle: () => this.toggleSection('chat')
    }) {
      this.chatBody()
      }
  }

  @Builder
  chatBody() {
    Column({ space: 12 }) {
      Column({ space: 6 }) {
        this.stackLabel('系统提示词', '定义 AI 的角色与行为')
        TextArea({ text: this.settings.systemPrompt, placeholder: '例如：你是一位严谨的技术顾问…' })
          .placeholderColor(this.pal().textTertiary)
          .fontColor(this.pal().text)
          .fontSize(Font.sm)
          .backgroundColor(this.pal().surfaceAlt)
          .borderRadius(Dim.r10)
          .height(96)
          .onChange((v: string) => {
            this.settings.systemPrompt = v;
            this.onSave();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.switchRow('显示工作过程', '把搜索 / 思考 / 工具调用收进一个折叠区，只留正文在外',
        this.settings.showSteps, (v: boolean) => {
          this.settings.showSteps = v;
          this.onSave();
        })
      if (this.settings.showSteps) {
        this.switchRow('工作过程默认展开', '关闭时默认折叠为一行「已完成 · N 秒」，点一下才展开',
          this.settings.processDefaultOpen, (v: boolean) => {
            this.settings.processDefaultOpen = v;
            this.onSave();
          })
      }
      this.switchRow('显示思维链', '展示模型的推理过程', this.settings.showReasoning, (v: boolean) => {
        this.settings.showReasoning = v;
        this.onSave();
      })
      this.switchRow('显示用量统计', 'tokens / 缓存命中 / 首字延迟', this.settings.showTokenStats, (v: boolean) => {
        this.settings.showTokenStats = v;
        this.onSave();
      })
      this.switchRow('显示费用估算', '根据官方单价本地折算', this.settings.showCost, (v: boolean) => {
        this.settings.showCost = v;
        this.onSave();
      })
      this.switchRow('流式输出', '逐字返回，可随时中断', this.settings.streamOutput, (v: boolean) => {
        this.settings.streamOutput = v;
        this.onSave();
      })
      this.switchRow('自动生成标题', '用首条消息作为会话标题', this.settings.autoTitle, (v: boolean) => {
        this.settings.autoTitle = v;
        this.onSave();
      })
    }
    .width('100%')
  }

  @Builder
  switchRow(title: string, desc: string, value: boolean, onChanged: (v: boolean) => void) {
    Row({ space: 10 }) {
      this.rowLabel(title, desc)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(this.pal().accent)
        .onChange((v: boolean) => onChanged(v))
    }
    .width('100%')
  }

  /* ===================== 生成参数 ===================== */

  @Builder
  paramsSection() {
    SettingSection({
      dark: this.dark,
      title: '生成参数',
      icon: $r('app.media.ic_bolt'),
      expanded: this.expanded === 'params',
      onToggle: () => this.toggleSection('params')
    }) {
      this.paramsBody()
      }
  }

  @Builder
  paramsBody() {
    Column({ space: 14 }) {
      Column({ space: 4 }) {
        Row() {
          this.rowLabel('Temperature', '越高越随机；DeepSeek 思考模式下不生效')
          Text(this.params.temperature.toFixed(1)).fontSize(Font.xs).fontColor(this.pal().accent)
        }
        Slider({ value: this.params.temperature, min: 0, max: 2, step: 0.1, style: SliderStyle.OutSet })
          .selectedColor(this.pal().accent).trackColor(this.pal().surfaceAlt).blockColor(this.pal().accent)
          .onChange((v: number) => {
            this.params.temperature = Math.round(v * 10) / 10;
            this.onSave();
          })
      }
      .width('100%')

      Column({ space: 4 }) {
        Row() {
          this.rowLabel('Top P', '思考模式下有效区间 0.95–1.0')
          Text(this.params.topP.toFixed(2)).fontSize(Font.xs).fontColor(this.pal().accent)
        }
        Slider({ value: this.params.topP, min: 0, max: 1, step: 0.05, style: SliderStyle.OutSet })
          .selectedColor(this.pal().accent).trackColor(this.pal().surfaceAlt).blockColor(this.pal().accent)
          .onChange((v: number) => {
            this.params.topP = Math.round(v * 100) / 100;
            this.onSave();
          })
      }
      .width('100%')

      Column({ space: 6 }) {
        this.stackLabel('最大输出 tokens', '0 表示使用服务端默认值（DeepSeek 上限 384K）')
        TextInput({ text: this.params.maxTokens > 0 ? this.params.maxTokens.toString() : '', placeholder: '默认' })
          .type(InputType.Number)
          .placeholderColor(this.pal().textTertiary)
          .fontColor(this.pal().text)
          .fontSize(Font.sm)
          .backgroundColor(this.pal().surfaceAlt)
          .borderRadius(Dim.r10)
          .height(40)
          .onChange((v: string) => {
            const n: number = Number.parseInt(v, 10);
            this.params.maxTokens = Number.isNaN(n) ? 0 : n;
            this.onSave();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        this.stackLabel('停止序列', '每行一个，最多 16 个')
        TextArea({ text: this.params.stop, placeholder: '每行一个停止词' })
          .placeholderColor(this.pal().textTertiary)
          .fontColor(this.pal().text)
          .fontSize(Font.sm)
          .backgroundColor(this.pal().surfaceAlt)
          .borderRadius(Dim.r10)
          .height(64)
          .onChange((v: string) => {
            this.params.stop = v;
            this.onSave();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        this.stackLabel('思考强度', 'auto 使用服务端默认（DeepSeek 默认 high）')
        Row({ space: 5 }) {
          ForEach(THINKING_OPTIONS, (o: string) => {
            Pill({
              label: o === 'auto' ? '自动' : (o === 'off' ? '关闭' : o),
              fg: this.params.thinking === o ? '#FFFFFF' : this.pal().textSecondary,
              bg: this.params.thinking === o ? this.pal().accent : this.pal().surfaceAlt,
              labelSize: 11,
              onTap: () => {
                this.params.thinking = o;
                this.onSave();
              }
            })
          }, (o: string) => 'th' + o)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        this.stackLabel('user_id 隔离标识', '用于内容安全 / KVCache 隔离，留空则不发送')
        TextInput({ text: this.params.userId, placeholder: '仅字母数字与 - _' })
          .placeholderColor(this.pal().textTertiary)
          .fontColor(this.pal().text)
          .fontSize(Font.sm)
          .backgroundColor(this.pal().surfaceAlt)
          .borderRadius(Dim.r10)
          .height(40)
          .onChange((v: string) => {
            this.params.userId = v;
            this.onSave();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.switchRow('JSON 输出模式', 'response_format = json_object', this.params.jsonMode, (v: boolean) => {
        this.params.jsonMode = v;
        this.onSave();
      })
      this.switchRow('返回 logprobs', '附带每个 token 的对数概率', this.params.logprobs, (v: boolean) => {
        this.params.logprobs = v;
        this.onSave();
      })
      this.switchRow('启用内置工具', '本地执行时间/计算/统计等函数（Function Calling）', this.params.enableTools, (v: boolean) => {
        this.params.enableTools = v;
        this.onSave();
      })
    }
    .width('100%')
  }

  /* ===================== 服务商 ===================== */

  @Builder
  providersSection() {
    SettingSection({
      dark: this.dark,
      title: '服务商与 API Key',
      icon: $r('app.media.ic_cloud'),
      expanded: this.expanded === 'providers',
      onToggle: () => this.toggleSection('providers')
    }) {
      this.providersBody()
      }
  }

  @Builder
  providersBody() {
    Column({ space: 10 }) {
      ForEach(this.settings.providers, (p: ProviderConfig) => {
        ProviderEditor({
          p: p,
          dark: this.dark,
          isActive: this.settings.activeProviderId === p.id,
          onSave: () => this.onSave(),
          onDelete: () => this.onDeleteProvider(p.id),
          onTest: () => this.onTestProvider(p.id)
        })
      }, (p: ProviderConfig) => p.id)

      Row({ space: 8 }) {
        Image($r('app.media.ic_plus')).width(15).height(15).fillColor(this.pal().accent)
        Text('添加自定义服务商').fontSize(Font.sm).fontColor(this.pal().accent)
      }
      .width('100%')
      .height(42)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.pal().accentSoft)
      .borderRadius(Dim.r12)
      .onClick(() => this.onAddProvider())
    }
    .width('100%')
  }

  /* ===================== 数据 / 关于 ===================== */

  @Builder
  dataSection() {
    SettingSection({
      dark: this.dark,
      title: '数据管理',
      icon: $r('app.media.ic_layers'),
      expanded: this.expanded === 'data',
      onToggle: () => this.toggleSection('data')
    }) {
      this.dataBody()
      }
  }

  @Builder
  dataBody() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_download')).width(15).height(15).fillColor(this.pal().textSecondary)
        Text('导出全部会话').fontSize(Font.sm).fontColor(this.pal().text).layoutWeight(1)
      }
      .width('100%')
      .height(42)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.pal().surfaceAlt)
      .borderRadius(Dim.r10)
      .onClick(() => this.onExport())

      Row({ space: 8 }) {
        Image($r('app.media.ic_trash')).width(15).height(15).fillColor(this.pal().error)
        Text('清空全部会话').fontSize(Font.sm).fontColor(this.pal().error).layoutWeight(1)
      }
      .width('100%')
      .height(42)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#14FF6B6B')
      .borderRadius(Dim.r10)
      .onClick(() => this.onClearAll())
    }
    .width('100%')
  }

  @Builder
  aboutSection() {
    SettingSection({
      dark: this.dark,
      title: '关于',
      icon: $r('app.media.ic_info'),
      expanded: this.expanded === 'about',
      onToggle: () => this.toggleSection('about')
    }) {
      Column({ space: 6 }) {
        this.infoRow('应用', '星枢 AI · Nova AI');
        this.infoRow('版本', Constants.VERSION);
        this.infoRow('运行平台', 'HarmonyOS 6.1.1 (API 24)');
        this.infoRow('支持协议', 'Chat Completions · Responses · Anthropic Messages · FIM');
        this.infoRow('支持服务商', 'DeepSeek · OpenAI · 任意兼容端点');
        Text('本应用直接与模型服务商通信，不经过任何中间服务器，API Key 仅保存在本机应用沙箱内。')
          .fontSize(Font.xs)
          .fontColor(this.pal().textTertiary)
          .margin({ top: 6 })
      }
      .width('100%')
      }
  }

  @Builder
  infoRow(k: string, v: string) {
    Row() {
      Text(k).fontSize(Font.sm).fontColor(this.pal().textSecondary).width(84)
      Text(v).fontSize(Font.sm).fontColor(this.pal().text).layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }
}

/** 单个服务商的编辑卡片 */
@Component
export struct ProviderEditor {
  @ObjectLink p: ProviderConfig;
  @Prop dark: boolean = true;
  @Prop isActive: boolean = false;
  @State showKey: boolean = false;
  onSave: () => void = () => {};
  onDelete: () => void = () => {};
  onTest: () => void = () => {};

  private pal(): Palette {
    return Themes.of(this.dark);
  }

  build() {
    Column({ space: 9 }) {
      Row({ space: 8 }) {
        Circle().width(9).height(9).fill(this.p.brandColor)
        Text(this.p.name).fontSize(Font.sm).fontColor(this.pal().text).fontWeight(FontWeight.Medium).layoutWeight(1)
        if (this.isActive) {
          Pill({ label: '使用中', fg: this.pal().accent, bg: this.pal().accentSoft, labelSize: 10 })
        }
        if (!this.p.builtin) {
          IconBtn({ icon: $r('app.media.ic_trash'), iconSize: 13, tint: this.pal().error, pad: 5, onTap: () => this.onDelete() })
        }
      }
      .width('100%')

      if (this.p.note.length > 0) {
        Text(this.p.note).fontSize(Font.xs).fontColor(this.pal().textTertiary).width('100%')
      }

      // API Key
      Row({ space: 6 }) {
        TextInput({ text: this.p.apiKey, placeholder: 'sk-…' })
          .type(this.showKey ? InputType.Normal : InputType.Password)
          .placeholderColor(this.pal().textTertiary)
          .fontColor(this.pal().text)
          .fontSize(Font.sm)
          .backgroundColor(this.pal().surfaceAlt)
          .borderRadius(Dim.r10)
          .height(40)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.p.apiKey = v;
            this.onSave();
          })
        IconBtn({
          icon: this.showKey ? $r('app.media.ic_lock') : $r('app.media.ic_eye'),
          iconSize: 15,
          tint: this.pal().textSecondary,
          onTap: () => {
            this.showKey = !this.showKey;
          }
        })
      }
      .width('100%')

      // Base URL
      Column({ space: 4 }) {
        Text('Base URL').fontSize(Font.xs).fontColor(this.pal().textTertiary)
        TextInput({ text: this.p.baseUrl, placeholder: 'https://api.example.com/v1' })
          .placeholderColor(this.pal().textTertiary)
          .fontColor(this.pal().text)
          .fontSize(Font.xs)
          .backgroundColor(this.pal().surfaceAlt)
          .borderRadius(Dim.r10)
          .height(38)
          .onChange((v: string) => {
            this.p.baseUrl = v;
            this.onSave();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 协议
      Column({ space: 4 }) {
        Text('协议').fontSize(Font.xs).fontColor(this.pal().textTertiary)
        Row({ space: 5 }) {
          ForEach(PROTOCOLS, (o: string) => {
            Pill({
              label: ProviderFactory.protocolLabel(o),
              fg: this.p.protocol === o ? '#FFFFFF' : this.pal().textSecondary,
              bg: this.p.protocol === o ? this.pal().accent : this.pal().surfaceAlt,
              labelSize: 10,
              onTap: () => {
                this.p.protocol = o;
                this.onSave();
              }
            })
          }, (o: string) => 'pr' + o)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 参数风格
      Column({ space: 4 }) {
        Text('参数风格').fontSize(Font.xs).fontColor(this.pal().textTertiary)
        Row({ space: 5 }) {
          ForEach(FLAVORS, (o: string) => {
            Pill({
              label: o,
              fg: this.p.flavor === o ? '#FFFFFF' : this.pal().textSecondary,
              bg: this.p.flavor === o ? this.pal().accent : this.pal().surfaceAlt,
              labelSize: 10,
              onTap: () => {
                this.p.flavor = o;
                this.onSave();
              }
            })
          }, (o: string) => 'fl' + o)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 模型列表
      Column({ space: 4 }) {
        Text('模型（每行一个）').fontSize(Font.xs).fontColor(this.pal().textTertiary)
        TextArea({ text: this.p.models.join('\n'), placeholder: 'deepseek-flash' })
          .placeholderColor(this.pal().textTertiary)
          .fontColor(this.pal().text)
          .fontSize(Font.xs)
          .backgroundColor(this.pal().surfaceAlt)
          .borderRadius(Dim.r10)
          .height(76)
          .onChange((v: string) => {
            const list: string[] = [];
            const parts: string[] = v.split('\n');
            for (let i = 0; i < parts.length; i++) {
              const s: string = parts[i].trim();
              if (s.length > 0) {
                list.push(s);
              }
            }
            this.p.models = list;
            this.onSave();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: 8 }) {
        Pill({
          label: '测试连通性',
          fg: this.pal().accent,
          bg: this.pal().accentSoft,
          labelSize: 11,
          icon: $r('app.media.ic_bolt'),
          onTap: () => this.onTest()
        })
        Pill({
          label: this.p.enabled ? '已启用' : '已停用',
          fg: this.p.enabled ? this.pal().success : this.pal().textTertiary,
          bg: this.pal().surfaceAlt,
          labelSize: 11,
          onTap: () => {
            this.p.enabled = !this.p.enabled;
            this.onSave();
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.pal().surfaceAlt)
    .borderRadius(Dim.r12)
    .border({ width: 1, color: this.isActive ? this.pal().accent : this.pal().border })
    .alignItems(HorizontalAlign.Start)
  }
}

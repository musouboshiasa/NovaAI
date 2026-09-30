# 星枢 AI · Nova AI

> 一个原生 **HarmonyOS** AI 客户端 —— 同时适配 **DeepSeek 全系能力**与 **OpenAI 系列协议**，
> 支持手机、平板、2in1，横竖屏自适应。

<p>
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue.svg">
  <img alt="platform" src="https://img.shields.io/badge/platform-HarmonyOS%206.1.1%20(API%2024)-green.svg">
  <img alt="language" src="https://img.shields.io/badge/language-ArkTS-orange.svg">
</p>

---

## 关于本项目的来源

**本项目由 DeepSeek 生成。**

从需求分析、架构设计、ArkTS 编码，到真机联调与问题排查，全部借助 **DeepSeek** 完成；
应用内运行的模型同样默认使用 DeepSeek。可以说这既是一个 DeepSeek 客户端，
本身也是用 DeepSeek 造出来的。

---

## 功能一览

### 服务商与协议

| 能力 | 说明 |
| --- | --- |
| 协议 | OpenAI Chat Completions · OpenAI/DeepSeek Responses · Anthropic Messages |
| FIM 补全 | DeepSeek `/beta/completions`，支持 Chat Prefix Completion |
| 服务商 | DeepSeek / OpenAI 内置预设，也可添加任意兼容端点 |
| 切换 | 运行时切换服务商与模型，配置独立保存、互不干扰 |

### 对话

- **流式输出**：SSE 增量渲染，可随时停止
- **思维链**：完整展示推理过程与 token 用量
- **工作过程折叠区**：搜索 / 思考 / 工具调用统一收纳，进行中显示「工作中 · N 秒」，
  完成后显示「已完成 · N 秒」，默认折叠（设置可调）
- **Markdown 渲染**：标题、列表、表格、代码块、行内代码
- **多模态**：图片附件（DeepSeek 视觉模型）
- **Function Calling**：内置本地工具，多轮工具回环
- **会话管理**：多会话、自动标题、搜索、导出 Markdown

### 联网搜索

| 能力 | 说明 |
| --- | --- |
| 免密钥后端 | Bing RSS · DuckDuckGo · SearXNG（自建） |
| **自动择优** | 记忆各后端成败与耗时，按「已知可用（快→慢）→ 未测过 → 失败冷却中」排序 |
| 记忆持久化 | 健康度落盘，重启后第一次搜索即可直接择优；超过 2 小时视为过期 |
| 降级透明 | 实际用的不是首选时，在回答下方标注「首选 X 不可用，本次改用 Y」 |
| 连通性测试 | 设置页「测试搜索」逐后端实打实请求，给出条数 / 耗时 / 首条标题 |
| 结果注入 | 搜索结果作为上下文交给模型，答案带 `[n]` 引用 |
| 来源列表 | 每条带 2 行摘要，可直接判断是否值得点开 |

### 离线语音

基于 **HarmonyOS CoreSpeechKit**，朗读与语音输入**全部在端侧完成，不消耗流量**：

- 文字转语音：可调语速 0.5x–2.0x，回答完成自动播报
- 语音识别：16k 单声道，识别后可选自动发送

### 界面

- **深浅色主题**：跟随系统 / 浅色 / 深色
- **横竖屏自适应**：手机窄屏单栏，平板/2in1 宽屏分栏
- **字号可调**、触感反馈
- 原生 ArkUI 绘制，无第三方 UI 依赖

### 隐私

- **不经过任何中间服务器**：应用直连模型服务商
- **API Key 只存在本机应用沙箱内**，不上传、不外发
- 无埋点、无统计、无广告

---

## 安装与使用

### 直接安装（推荐）

到 [Releases](https://github.com/musouboshiasa/NovaAI/releases) 下载 **未签名 HAP**：

> `NovaAI-<版本>-unsigned.hap`

未签名包无法直接安装，需先用 **DevEco Studio** 自动签名：

1. DevEco Studio 打开本工程，等待 Sync 完成
2. `File → Project Structure → Signing Configs` 勾选 **Automatically generate signature**
3. 连接设备后点击运行，或使用 `hdc install` 安装已签名的 HAP

### 从源码构建

环境要求：

- DevEco Studio **6.1.1** 及以上
- HarmonyOS SDK **API 24**（6.1.1）

```powershell
# Windows
.\build.ps1              # 构建 debug 未签名 HAP
.\build.ps1 -Release     # 构建 release 未签名 HAP
.\build.ps1 -Clean       # 先清理
```

产物位于：

```
entry/build/default/outputs/default/entry-default-unsigned.hap
```

### 本地运行（无需设备）

用 DevEco Studio 打开工程，打开 `entry/src/main/ets/pages/Index.ets`，
点击编辑器右上角的 **Previewer** 图标即可在 PC 上直接渲染运行。

### 首次配置

打开应用 → **设置 → 服务商与 API Key** → 填入你的 API Key。

---

## 项目结构

```
entry/src/main/ets/
├── common/        常量、工具、主题
├── model/         数据模型（消息、会话、设置、搜索结果）
├── net/           HTTP / SSE 底层
├── provider/      各协议适配（Chat Completions / Responses / Anthropic / FIM）
├── service/       ChatEngine、StorageService、SearchService、SpeechService
├── view/          UI 组件（消息气泡、输入框、设置页…）
└── pages/         Index 主页面
```

---

## 已知限制

- 未签名 HAP 需要自行签名后才能安装（见上文）
- SearXNG 需自建实例，且实例须开启 JSON 输出
- 联网搜索的可用后端取决于所在网络环境，可用「测试搜索」确认
- 语音功能依赖华为 CoreSpeechKit，仅 HarmonyOS 设备可用

---

## 开源协议

本项目采用 [MIT License](LICENSE) 开源。

```
MIT License · Copyright (c) 2026 musouboshiasa
```

---

## 致谢

- 模型能力由 **DeepSeek** 提供
- 本项目由 **DeepSeek** 生成

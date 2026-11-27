# Local-Harness 2.0

一个完全离线的本地大模型聊天客户端，面向 Windows。

模型以 GGUF 格式放在本机，推理由 llama.cpp 完成，对话、记忆、配置文件都不离开硬盘。断网可用，关闭程序即全部结束。

2.0 把整个桌面端从 Python + tkinter 迁移到 Godot 4.7，界面重写，能力改为插件制。

---

## 界面重写

旧版界面由 tkinter 绘制，无法呈现圆角、内嵌表格与图片。模型输出的 Markdown 只能以原文显示：表格是一串竖线，加粗是星号，公式是反斜杠。

2.0 的界面全部重画：深色底、左侧三栏（品牌与新建 / 会话列表 / 快捷区），层次依靠明度差而非分割线。

输出渲染相应补齐：

- 标题、加粗、斜体、行内代码、代码块、引用、有序与无序列表
- 表格按表格绘制，含表头底色、隔行背景与单元格边框
- 图片以缩略图内嵌，点击调用系统看图程序
- 公式支持常见 LaTeX 子集：`E=mc²`、上下标、希腊字母，独立公式的分式为上下结构加分数线
- 链接可点击

---

## 插件制

主程序只负责对话、启动模型、管理插件。其余能力全部由插件提供，共 13 个，各自托管在独立仓库，可在设置内一键安装、卸载、热加载。

插件的界面由插件自己实现（`ui.gd`），主程序只提供控件积木：卡片、滑块、下拉、表格、按钮、文件选择。因此各插件界面互不相同，卸载时随插件一并移除。

界面以无需编程知识为前提设计。以「智能压缩上下文」为例：

- 三个数字：当前消息条数、估算占用、触发阈值
- 一个下拉：不自动 / 用到 50% / 70% / 85%
- 一个滑块：最近保留几轮原话
- 一个按钮：立即压缩，结果显示在按钮下方

不需要了解参数名，也不需要填写数字。记忆系统同理：条目数、存储位置、一张列出时间与内容的表，以及清空按钮。

权限按工具粒度控制，分为只读、会产生操作、高危三组。被关闭的工具不会进入模型的工具清单，即使模型发起调用也会被宿主拒绝。

---

## 性能

旧版长期使用后逐渐变慢，原因是每次重启模型服务都会残留一个 `llama-server` 进程，实测累积到 16 个、占用 7.89 GB 内存。

2.0 的处理：

- 启动、重启、退出时按端口清理残留进程，实测由 16 个降为 1 个
- 执行命令、截图、OCR、联网等耗时操作转移到工作线程。实测一条耗时 3.7 秒的命令执行期间，界面主循环仍在运行，约 140 帧/秒
- 流式输出按 90 毫秒节流，长回答不再随长度增加而变慢
- 请求上下文只携带最近 24 条消息，单条上限 4000 字，工具结果进入上下文时截断至 2000 字
- 长会话切换时分批渲染：先绘制最近 14 条，其余逐帧补齐

体检数据（同机实测）：冷启动到模型就绪 8.6 秒，界面就绪 2 毫秒；渲染 60 条消息 175 毫秒；常驻内存约 265 MB。

---

## 中文环境

Windows 的 `cmd` 以 GBK 解释命令行，中文参数在其中会损坏。2.0 的做法：

- 命令写入 UTF-16 编码的 PowerShell 脚本执行，中文参数与输出保持原样
- 网页抓取先读取响应声明的字符集，GB18030 页面按对应编码解码
- 搜索在 DuckDuckGo 不可达时切换至 Bing 中国
- OCR 默认使用简体中文引擎
- 语音朗读优先选择中文音色

---

## 模型适配

读取 GGUF 文件头即可获得架构、参数量、层数、原生上下文、注意头与 KV 头数量，据此结合本机显存与内存计算：

- 可放入显存的层数
- 建议上下文长度（不超过模型原生值，上限 32768）
- 建议线程数
- 内存不足时的明确提示

每个模型的适配结果单独保存（`user://models/models.json`），更换模型即更换整套参数。参数优先级为：当前模型的覆盖值 > 自动检测结果 > 全局默认值。

支持识别 130B 级别模型。若本机资源不足，界面会给出所需与可用内存的具体数字，不会尝试加载后卡死。

---

## 安装

1. 解压 `LocalHarness-2.0.0-win64.zip`
2. 将 GGUF 模型放入 `model/` 目录（内置 CUDA / Vulkan / CPU 三套推理后端，自动选择可用者）
3. 运行 `LocalHarness.exe`
4. 在设置中安装所需插件

数据目录：`%APPDATA%\Godot\app_userdata\Local-Harness\`，包含会话、配置、插件、截图与记忆，可整体备份或迁移。

---

## 已知限制

- 识图的「描述画面」需要视觉模型（GGUF + mmproj），未配置时退回系统 OCR
- 语音识别依赖 Windows 已安装对应语言的识别组件；朗读功能开箱可用
- 子智能体会额外加载一份模型，内存较小的机器不宜使用
- 公式支持常见 LaTeX 子集，并非完整 TeX
- 表格不支持单元格合并
- 平台支持：本版仅支持 Windows。Linux 版已下架，暂不提供；受资金限制，macOS 与鸿蒙 OS 暂不适配

---

## 许可

GPL-3.0。主程序与每个插件仓库根目录均包含完整 `LICENSE`。

---

# Local-Harness 2.0 (English)

An offline desktop client for local large language models, for Windows.

Models are stored locally in GGUF format, inference runs on llama.cpp, and conversations, memory and configuration never leave the disk. It works without a network connection, and closing the application ends everything.

Version 2.0 moves the desktop client from Python + tkinter to Godot 4.7. The interface was rewritten and every capability became a plugin.

**Interface.** The previous tkinter window could not render rounded corners, tables or images, so Markdown arrived as source text. The new interface is drawn from scratch with a dark palette and a three-part sidebar layered by brightness rather than separators. Output now renders headings, bold, italics, inline code, code blocks, quotes and lists; tables are drawn as tables with a header row and alternating backgrounds; images appear as thumbnails that open in the system viewer; a subset of LaTeX renders, including stacked fractions, roots, superscripts and Greek letters.

**Plugins.** The host only chats, launches the model and manages plugins. Thirteen plugins in separate repositories provide everything else and can be installed, removed and hot-loaded from Settings. Each plugin implements its own `ui.gd`; the host supplies building blocks — cards, sliders, dropdowns, tables, buttons, file pickers. Interfaces are designed to be used without programming knowledge: the compaction plugin exposes three numbers, a dropdown for the trigger threshold, a slider for retained turns and a single button.

**Performance.** Slowness after long use came from leftover `llama-server` processes — sixteen of them, holding 7.89 GB. They are now reaped by port on start, restart and exit (measured: sixteen down to one). Slow tools run off the UI thread (the main loop kept running at roughly 140 fps during a 3.7-second command), streaming is throttled, request context is trimmed, and long conversations render in batches.

**Chinese environments.** Commands travel through a UTF-16 PowerShell script so `cmd`'s GBK decoding cannot damage them; pages are decoded by their declared charset; search falls back to Bing; OCR defaults to Simplified Chinese; speech prefers a Chinese voice.

**Model fitting.** GGUF headers provide architecture, parameter count, layer count, native context and attention layout. Combined with available VRAM and RAM, the client derives the number of layers to offload, a context size, thread count and an explicit warning when memory is insufficient. Fit settings are stored per model and take precedence over global defaults. Models at the 130B scale are recognised; if the machine cannot hold one, the interface states the required and available memory instead of attempting to load it.

**Install.** Unzip, place GGUF models in `model/`, run `LocalHarness.exe`, then install plugins from Settings. All data lives in `%APPDATA%\Godot\app_userdata\Local-Harness\`.

**Platform.** Windows only. The Linux build has been withdrawn and is no longer available; macOS and HarmonyOS are not supported for the time being, due to funding constraints.

**License.** GPL-3.0, with the full text in `LICENSE` here and in every plugin repository.

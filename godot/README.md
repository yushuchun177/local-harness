# Local-Harness · Godot 版

把原来的 Windows tkinter 版 `local-harness` 移植到 **Godot 4.7**，界面全部重做。
只做 Windows。Linux 版已下架；受资金限制，macOS 与鸿蒙 OS 暂不适配。

## 和原版的区别

| | tkinter 原版 | Godot 版 |
| --- | --- | --- |
| 后端对接 | 直接驱动 `llama-cli.exe` 的 stdin/stdout，靠 `\n> ` 和 `[ Prompt:` 判断边界 | 起 `llama-server.exe`，走 HTTP + SSE 流式取 token |
| 界面 | ttk 原生控件，深色主题 | 自绘：侧栏 + 气泡 + 输入区，圆角、层次色、右对齐用户气泡 |
| 历史 | 自己拼 `/read` 喂给 llama-cli | 标准 messages 数组，服务端套模型自带的 chat template（`--jinja`） |
| 模型切换 | 重启进程 | 重启服务端进程 |

用 llama-server 的原因：Godot 里没有可靠的管道读子进程输出的方式，
而 HTTP/SSE 是它原生擅长的，也不用再处理 llama-cli 的 ANSI 与提示符噪音。

## 目录

```
project.godot          工程配置（Compatibility 渲染、1280x820）
scripts/app.gd         全局单例：配置、模型扫描、后端探测、服务端生命周期、SSE 解析、会话存储
ui/main.tscn           主场景（只有一个 Control 挂脚本）
ui/main.gd             界面全部代码搭建：侧栏 / 顶栏 / 气泡 / 输入区 / 设置面板
ui/icon.svg            应用图标
```

## 运行

```powershell
# 开发运行（编辑器里也行）
& "D:\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe" --path D:\Godot\projects\local-harness
```

程序会在这些位置找模型和后端：

- 程序目录（导出后是 exe 所在目录）
- 编辑器运行时用 `D:/LocalHarness/local-harness-1.3.0-含6模型`
- 也可以在 `user://config.json` 里写 `app_dir`

后端目录名：`llama`（CPU）、`llama-cuda`、`llama-vulkan`，每个里面要有 `llama-server.exe`。

## 已实现

- 模型自动发现（过滤 mmproj / 向量模型 / 分片）、默认挑 Qwen3-0.6B 级
- 后端自动选择：有显卡且支持张量核心 → CUDA；否则 Vulkan；再否则 CPU
- 服务端生命周期：启动 → `/health` 轮询 → 就绪；切模型/改设置自动重启
- 流式对话、气泡渲染、用户消息右对齐、生成状态与速度统计
- 多会话：新建、切换、右键删除、搜索、自动命名
- 设置面板（居中）：后端、GPU 层数、上下文、温度、回复上限、系统提示词
- 可折叠侧栏（左上 ☰）、对话名称显示在消息区上方
- 无分隔线布局：窗口底色 #0b0d12，侧栏 / 顶栏是圆角淡色卡片，靠色差分层；输入区与消息区同底色
- 底部一行：上下文/速度 · 加速方式 · 模型选择；右下角半透明「由 Godot 开发」
- 关闭 Godot 启动画面（project.godot 里 boot_splash/show_image=false）
- 自定义称呼：设置里可改「你的称呼」和「AI 的名字」，气泡署名、输入框提示、系统提示词同步生效
- 设置面板底部有「开源协议」：本程序 GPL-3.0、Godot MIT、llama.cpp MIT，可点链接或「查看完整许可」看全文（LICENSES/ 目录）
- 中文字体走 `C:/Windows/Fonts/msyh.ttc`，没有则退回默认字体

## 导出注意

LICENSES/*.txt 是非资源文件，导出时要在这里加过滤器：项目 → 导出 → 资源 → 过滤器里填 *.txt，否则 exe 里读不到许可全文。



### 交互细节

- 搜索框同时匹配**标题和正文**（记得说过的话也能找到）
- 会话右键 → **重命名 / 删除**（删除有确认弹窗）
- 发送后自动把该会话置顶；新对话会复用已有的空会话，不会堆一串「新对话」
- 侧栏折叠状态记在 config.json，重启保持
- 快捷键：`Ctrl+N` 新对话、`Ctrl+F` 搜索、`Ctrl+,` 设置、`Esc` 关闭最上层弹窗

## 插件（独立仓库，应用内远程安装）

插件不随程序发布。主程序「设置 → 插件管理」读索引仓库
[localharness-plugins](https://github.com/yushuchun177/localharness-plugins) 的 `index.json`，
再从各插件自己的仓库下载 zip、解压到 `user://plugins/<id>/` 并热加载。

| 插件 | 仓库 | 工具数 |
| --- | --- | --- |
| 终端 | localharness-plugin-terminal | 1 |
| 网页搜索与获取 | localharness-plugin-web | 2 |
| 记忆系统 | localharness-plugin-memory | 3 |
| 操作电脑 | localharness-plugin-control | 6 |
| 截图 | localharness-plugin-screenshot | 1 |
| 上下文洞察 | localharness-plugin-insights | 2 |
| 智能压缩上下文 | localharness-plugin-compact | 2 |
| 子智能体 | localharness-plugin-subagent | 1 |
| 识图 | localharness-plugin-vision | 3 |
| 语音输入 | localharness-plugin-voice | 3 |
| 自动化任务 | localharness-plugin-automation | 3 |
| 远程操作 | localharness-plugin-remote | 4 |
| OAR 智能体 | localharness-plugin-oar | 3 |

写插件的约定见 [docs/PLUGINS.md](docs/PLUGINS.md)。
## 待办

- Markdown 渲染（代码块、粗体）——现在是纯文本
- 上下文压缩（原版有，Godot 版还没搬）
- 思考模型（Qwen3）的 `--reasoning` 展示
- 导出 exe：需要先装 Godot 导出模板（约 1GB），之后 `项目 → 导出 → Windows Desktop`
- 窗口图标 / 标题（现在跑的是 DEBUG 版，导出后自动正常）

## 技术备注

- 关键坑：字符变量不能叫 `_input`，会和 Godot 的 `_input(event)` 回调冲突，整棵 UI 直接不显示
- `PanelContainer` 没有 `max_size_flags` 属性，写了会中断建树
- `str(null)` 在 GDScript 里是 `"<null>"`，SSE 里 `delta.content` 为 null 时必须先判 `TYPE_STRING`，否则气泡开头会出现 `<null>`
- 气泡宽度用「可伸缩空白 + stretch_ratio 0.28/0.72」控制，不用手算像素










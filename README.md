# Local-Harness

**完全离线的本地大模型聊天客户端，Windows 桌面版。**

模型（GGUF）放在本机，推理由 llama.cpp 完成，对话、记忆、配置都不离开硬盘。
断网可用，关闭程序即全部结束。

当前版本：**2.1.0**（Godot 4.7；窗口自适应、模型文件夹导入）

支持 **130B 及以下（含）** 的模型（0.3B–130B），按 GGUF 文件头自动适配。

---

## 下载

[**Releases → v2.1.0**](https://github.com/yushuchun177/local-harness/releases/tag/v2.0.0)

| 文件 | 说明 |
| --- | --- |
| `LocalHarness-2.1.0-win64.zip` | 解压即用，双击 `LocalHarness.exe` |
| `LocalHarness-2.1.0-src.zip` | 源码包（不含模型） |

安装步骤：

1. 解压到任意目录
2. 把 GGUF 模型放进 `model/`
3. 双击 `LocalHarness.exe`
4. 设置 → 插件管理 → 刷新 → 安装需要的插件

包内自带 CPU 与 Vulkan 两套推理后端。想用 CUDA，把 `llama-cuda` 目录放到 exe 同级即可（CUDA 版约 1.3 GB，未随包附带）。

---

## 这一版

### 面向非程序员

能以点选、滑块、按钮解决的地方，不出现参数名。例如「智能压缩上下文」：
三个数字（消息条数 / 估算占用 / 触发阈值）、一个下拉（不自动 / 50% / 70% / 85%）、
一个滑块（保留几轮）、一个按钮（现在压缩，结果显示在下方）。

### 输出能读了

真加粗、分级标题、列表、引用、代码块；**表格按表格绘制**（表头底色、隔行背景、单元格边框）；
**图片内嵌**缩略图，点开用系统看图；**公式**渲染成分式与根号（常见 LaTeX 子集）。

### 能力来自插件

主程序只负责对话、启动模型、管理插件。13 个插件各自独立仓库，可在应用内安装、卸载、热加载。
插件自带界面代码（`ui.gd`），主程序只提供控件积木，因此各插件界面互不相同。

工具权限按粒度控制，分只读 / 会产生操作 / 高危三组；被关闭的工具不会进入模型工具清单，
模型强行调用也会被拒绝。

### 中文是默认

命令经 UTF-16 PowerShell 脚本执行（绕开 `cmd` 的 GBK）；网页按声明编码解码；
搜索在 DuckDuckGo 不可达时切 Bing；OCR 默认简体中文；朗读优先中文音色。

### 模型自动适配

读取 GGUF 文件头得到层数、参数量、原生上下文、注意力结构，结合显存与内存算出：
GPU 层数、上下文长度、线程数，并在内存不足时给出具体所需/可用数字。
适配结果按模型分别保存，优先级为：本模型覆盖值 > 自动检测 > 全局默认。

### 稳定性

- 启动/重启/退出按端口清理残留 `llama-server`（曾累积 16 个、占用 7.89 GB）
- 慢操作（命令、截图、OCR、联网）在工作线程执行，界面保持响应
- 流式输出节流，长回答不随长度变慢
- 上下文只带最近 24 条、单条上限 4000 字

同机体检：冷启动到模型就绪 8.6 秒，界面就绪 2 毫秒，渲染 60 条消息 175 毫秒。

---

## 仓库结构

```
godot/          2.0 源码（Godot 4.7 工程）
plugins 仓库    13 个插件，各自独立：
                github.com/yushuchun177/localharness-plugin-<id>
索引仓库        github.com/yushuchun177/localharness-plugins
                （应用从这里读取插件列表）
```

1.x 的 Python 实现已从本仓库移除（可在提交历史中查看）。

## 插件

| 插件 | 仓库 |
| --- | --- |
| 终端 | [localharness-plugin-terminal](https://github.com/yushuchun177/localharness-plugin-terminal) |
| 网页搜索与获取 | [localharness-plugin-web](https://github.com/yushuchun177/localharness-plugin-web) |
| 记忆系统 | [localharness-plugin-memory](https://github.com/yushuchun177/localharness-plugin-memory) |
| 操作电脑 | [localharness-plugin-control](https://github.com/yushuchun177/localharness-plugin-control) |
| 截图 | [localharness-plugin-screenshot](https://github.com/yushuchun177/localharness-plugin-screenshot) |
| 识图 | [localharness-plugin-vision](https://github.com/yushuchun177/localharness-plugin-vision) |
| 语音输入 | [localharness-plugin-voice](https://github.com/yushuchun177/localharness-plugin-voice) |
| 上下文洞察 | [localharness-plugin-insights](https://github.com/yushuchun177/localharness-plugin-insights) |
| 智能压缩上下文 | [localharness-plugin-compact](https://github.com/yushuchun177/localharness-plugin-compact) |
| 子智能体 | [localharness-plugin-subagent](https://github.com/yushuchun177/localharness-plugin-subagent) |
| 自动化任务 | [localharness-plugin-automation](https://github.com/yushuchun177/localharness-plugin-automation) |
| 远程操作 | [localharness-plugin-remote](https://github.com/yushuchun177/localharness-plugin-remote) |
| OAR 智能体 | [localharness-plugin-oar](https://github.com/yushuchun177/localharness-plugin-oar) |

每个仓库都包含完整 GPL-3.0 `LICENSE` 与中英双语 `README`。

## 从源码运行

需要 Godot 4.7：

```
Godot_v4.7.2-stable_win64.exe --path godot/
```

或打开 `godot/project.godot` 按 F5。模型目录放在工程同级或「设置 → 模型」里指定。

## 数据目录

```
%APPDATA%\Godot\app_userdata\Local-Harness\
```

会话、配置、插件、截图、记忆都在这里，可整体备份或迁移。

## 平台

仅 Windows。

Linux 版已下架，暂不提供；受资金限制，macOS 与鸿蒙 OS 暂不适配。

## 已知限制

- 识图「描述画面」需视觉模型（GGUF + mmproj），未配置时退回系统 OCR
- 语音识别依赖 Windows 已安装对应语言的识别组件
- 子智能体会额外加载一份模型，内存较小机器不宜使用
- 公式支持常见 LaTeX 子集，并非完整 TeX
- 表格不支持单元格合并

## 许可

GPL-3.0，完整文本见 [LICENSE](LICENSE)。

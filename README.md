# Local-Harness

面向 [llama.cpp](https://github.com/ggml-org/llama.cpp) 的图形化 Harness 调度工具：把模型加载、参数配置和多轮对话收进一个窗口，不用敲终端命令行。

> **本项目不捆绑、不附带任何 GGUF 模型权重。**
> 模型需要自行下载后导入；仓库与发布包中只有程序本体和 llama.cpp 运行文件，没有模型文件。

![界面](docs/screenshots/chat-dark.png)

## 简介

Local-Harness 是 llama.cpp 的桌面端外壳：负责调起 `llama-cli`、读取 GGUF 元数据、维护上下文与对话记录、把流式输出呈现为对话界面。目标是降低本地大模型的使用门槛——选模型、调参数、开始对话，都在界面里完成。

程序在本机运行，不联网、不需要账号，模型与对话记录都留在本地目录。

## 功能

**模型**

- 支持任意 llama.cpp 可加载的 GGUF 模型，兼容 Qwen 系列及 Llama、Mistral、Gemma、Phi、DeepSeek、Yi、GLM、MiniCPM、SmolLM 等
- 直接读取 GGUF 元数据：模型名称、架构、原生上下文上限；界面中「上下文」滑块的取值上限即模型自身的原生上限
- 自动识别并过滤非对话模型（mmproj、视觉投影、向量化与重排模型）以及分片文件的多余分片

**对话**

- 流式输出，逐字呈现，生成过程中可随时停止
- 多会话管理：新建、重命名、删除会话，可删除单条消息
- 支持思考型模型（如 Qwen3）：思考过程不混入回答正文

**上下文**

- 自动上下文摘要压缩：对话达到触发阈值后，在下一轮提问前把较早的历史压缩成摘要，保留最近若干轮原话
- 触发阈值按 1024 token 一档自由调节：**1024 / 2048 / 3072 / 4096，默认 2048**
- 可在设置中关闭自动压缩

**参数与界面**

- 温度、上下文窗口、回复上限均可在界面直接调节（输入数值或拖动滑块），修改即时生效
- 深色 / 浅色主题切换；参数与会话随程序目录保存，绿色免安装

## 使用须知

**1. 必须自行准备模型（本程序不包含任何模型）**

本项目不提供、不附带、不内置任何 GGUF 模型权重。下载安装包后只有一个空程序，需要自行获取 `.gguf` 模型文件才能对话。

模型权重由各自的发布方授权（例如 Qwen 系列为 Apache-2.0），请遵守相应许可；模型许可与本项目无关，本项目只负责在本机调用。

**2. 导入模型的两种方式**

- 把 `.gguf` 文件放进程序目录下的 `model\` 文件夹，重启程序后出现在顶部模型下拉框中
- 或点击顶部「导入」，选择一个存放模型的文件夹，程序会记住该路径

模型来源示例：Hugging Face、ModelScope 等平台上的 GGUF 量化版本（文件名以 `.gguf` 结尾）。分片模型只需放入第一片（`xxx-00001-of-00002.gguf`），其余分片放在同一目录即可。

**3. 运行环境与目录**

- Windows 10 / 11，64 位（x64 CPU，需支持 SSE4.2）
- 纯 CPU 推理，不要求独立显卡；内存建议：0.4B–1B 模型 4GB 起，1.5B–2B 8GB，3B–4B 16GB

```
local-harness.exe      主程序
_internal\             运行库（勿删改）
llama\                 llama.cpp 运行文件（llama-cli.exe 及依赖 DLL）
model\                 自备的 .gguf 模型
chats\                 对话记录（自动生成）
config.json            界面与参数设置（自动生成）
```

**4. 其它说明**

- 程序目录可整体拷贝到其它电脑或 U 盘使用，`model\` 一并带走即可
- 删除 `chats\` 中的文件即删除对应会话；删除 `config.json` 恢复默认设置

## 使用手册（多语言）

| 语言 | 手册 |
| --- | --- |
| 简体中文 | [docs/manual/zh-CN.md](docs/manual/zh-CN.md) |
| English | [docs/manual/en.md](docs/manual/en.md) |
| 繁體中文 | [docs/manual/zh-TW.md](docs/manual/zh-TW.md) |
| 日本語 | [docs/manual/ja.md](docs/manual/ja.md) |
| Русский | [docs/manual/ru.md](docs/manual/ru.md) |
| Español | [docs/manual/es.md](docs/manual/es.md) |
| Français | [docs/manual/fr.md](docs/manual/fr.md) |
| Deutsch | [docs/manual/de.md](docs/manual/de.md) |

手册涵盖：安装与启动、准备模型、界面说明、参数、上下文压缩、快捷键、数据与备份、常见问题、许可证。索引见 [docs/manual/README.md](docs/manual/README.md)。

## 兼容性

- 模型：所有 llama.cpp 支持的 GGUF 模型。已验证：Qwen3-0.6B、Qwen3-1.7B、Qwen2.5-1.5B、Qwen2.5-3B、Llama-3.2-1B、SmolLM2-360M
- llama.cpp：启动前探测可执行文件支持的参数，兼容不同版本的 llama.cpp
- 系统：Windows 10 / 11 x64

## 许可证

本项目以 **GNU General Public License v3.0（GPLv3）** 发布，完整条款见 [LICENSE](LICENSE)。

- 允许打包成二进制形式分发（例如打包为 exe 提供下载）
- 但只要分发本程序（无论源码还是打包后的二进制），就必须同时提供完整的对应源代码
- 二次修改后再分发，仍须保持开源，并同样以 GPLv3 授权
- 本程序不提供任何担保

GGUF 模型权重不属于本项目，遵循各自发布方的许可，不受本项目的 GPLv3 约束。

## 第三方组件

- [llama.cpp](https://github.com/ggml-org/llama.cpp)：MIT License

# Local-Harness 2.0 — 源码包（不含模型）

完整源码，**不含任何 GGUF 模型**，也不含编译好的 exe。模型体积大且各有各的许可，需自行准备。

## 支持平台

仅 Windows。Linux 版已下架；受资金限制，macOS 与鸿蒙 OS 暂不适配。

## 目录

```
project.godot      Godot 工程（Godot 4.7 打开）
scripts/           主程序脚本：配置、模型管理、Markdown、公式渲染、GGUF 解析…
ui/                界面：主窗口、设置面板
plugins/           13 个插件源码，随程序发布
docs/              发布说明、插件开发指南
LICENSES/          第三方许可
tools/             开发用检查脚本
```

## 运行

已安装 Godot 4.7：

```
Godot_v4.7.2-stable_win64.exe --path <本目录>
```

或用 Godot 打开 `project.godot`，按 F5。

## 模型

在源码目录旁准备：

```
<任意目录>/
├── model/          ← GGUF 放这里
├── llama-cuda/     ← CUDA 版 llama-server（可选）
├── llama-vulkan/   ← Vulkan 版（可选）
└── llama/          ← CPU 版（可选）
```

也可在「设置 → 模型」里把程序目录指向已有位置。

## 数据目录

`%APPDATA%\Godot\app_userdata\Local-Harness\` —— 会话、配置、插件、截图、记忆都在这里。

## 许可

GPL-3.0，完整文本见 `LICENSES/`。

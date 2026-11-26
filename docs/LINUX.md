# local-harness · Linux 说明

Windows 上双击 `local-harness.exe` 就行了；Linux 上没有 exe，用的是同一个 Python 包，
走**终端界面**（`local_harness.cli`）。图形界面在 Linux 上也能跑，但需要桌面环境 +
`python3-tk`，服务器上通常没有，所以以终端为主。

## 一、准备

```bash
sudo apt update && sudo apt install -y python3 python3-pip   # Debian/Ubuntu
# 图形界面才需要：sudo apt install -y python3-tk
```

本程序只用 Python 标准库（终端模式**零第三方依赖**），不用 pip 装东西。

## 二、放两样东西

```
local-harness/
├── run.sh
├── setup.sh               ← 云 GPU 上一键装：拉 llama.cpp CUDA 版 + 小模型
├── local_harness/          ← 源码（或 pip 安装后的包）
├── llama/                  ← CPU 后端：llama-cli（Linux 版，没有 .exe）
├── llama-cuda/             ← NVIDIA 后端：llama-cli + libggml-cuda.so
├── llama-vulkan/           ← 通用显卡后端（可选）
└── model/                  ← 你的 .gguf
```

最快的路子是直接用发布页里的 `local-harness-1.3.0-linux-x64.tar.gz`，
里面已经把 `llama/`（CPU）和 `llama-cuda/`（CUDA 12.8）都放好了：

```bash
tar xzf local-harness-1.3.0-linux-x64.tar.gz
cd local-harness-1.3.0-linux-x64
./run.sh --list
```

自己装 llama.cpp 也行（以 b12728 为例）：

```bash
# CPU
wget https://github.com/ggml-org/llama.cpp/releases/download/b12728/llama-b12728-bin-ubuntu-x64.tar.gz
# CUDA 12.8（需要系统里有 libcudart.so.12；没有的话见下面"CUDA 运行时"）
wget https://github.com/ggml-org/llama.cpp/releases/download/b12728/llama-b12728-bin-ubuntu-cuda-12.8-x64.tar.gz
```

解压后把目录改名成 `llama/` 或 `llama-cuda/` 放进程序目录，确认 `llama-cli` 有执行权限：

```bash
chmod +x llama*/llama-cli
```

### CUDA 运行时

llama.cpp 的 Linux CUDA 包**不带** `libcudart.so.12` / `libcublas.so.12`，要系统里有。
没有的话最省事的办法是 pip 装（不用装整套 CUDA Toolkit）：

```bash
pip install nvidia-cuda-runtime-cu12 nvidia-cublas-cu12
```

`run.sh` 会自动把 pip 里这两个库的路径加进 `LD_LIBRARY_PATH`；
`setup.sh` 检测到缺库时也会自动帮你装。

## 三、跑起来

```bash
./run.sh --list            # 先看看检测结果
./run.sh                   # 开始聊天（自动挑后端，有 CUDA 就上 CUDA）
```

常用的组合：

```bash
# 全部层放显卡 + 张量核心（NVIDIA，计算能力 >= 7.0 才有效）
./run.sh --backend cuda --gpu-layers -1 --tensor-core

# 显存不够：只放 20 层，剩下的留给 CPU（组合使用）
./run.sh --backend cuda --gpu-layers 20

# 纯 CPU
./run.sh --backend cpu

# 指定模型和上下文
./run.sh -m /root/autodl-tmp/Qwen3-0.6B-Q8_0.gguf -c 8192
```

`--list` 会打印：显卡型号 / 显存 / 计算能力 / 是否支持张量核心 / 每个后端的路径 / 找到的模型。

## 四、参数速查

| 参数 | 说明 |
| --- | --- |
| `--backend auto\|cpu\|cuda\|vulkan\|hip` | 用哪个后端，默认 auto |
| `--gpu-layers N` | -1 全部层（默认）、0 纯 CPU、N 表示显卡 + CPU 混合 |
| `--tensor-core` | 启用张量核心内核（CUDA 走 `GGML_CUDA_FORCE_MMQ=1`） |
| `--flash-attn` | 启用 FlashAttention |
| `-m` / `-c` / `-t` / `-n` | 模型 / 上下文 / 温度 / 最大生成长度 |
| `--list` | 只打印检测结果，不进对话 |

对话里输 `/help` 看内置命令，`/exit` 退出。

## 五、常见问题

**提示找不到 llama-cli** —— 目录名必须是 `llama`、`llama-cuda`、`llama-vulkan` 之一，
里面要有可执行的 `llama-cli`（`chmod +x` 一下），或者用 `--cli /绝对路径` 指定。

**选了 cuda 但速度跟 CPU 一样** —— 说明 CUDA 没真正生效（缺 `libcudart` 等依赖时会静默退回 CPU）。
用 `nvidia-smi` 确认卡在，再看 `./run.sh --list` 里 CUDA 是否被识别。

**张量核心没反应** —— 需要：NVIDIA 卡、计算能力 ≥ 7.0、CUDA 后端、`--tensor-core` 四个条件同时满足。
`--list` 会直接告诉你卡的计算能力和支持情况。

**显存不够 OOM** —— 把 `--gpu-layers` 从 `-1` 改成具体层数（如 20、12），剩下的放 CPU。

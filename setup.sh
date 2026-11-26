#!/usr/bin/env bash
# local-harness · 一键装到云 GPU 机器（AutoDL / 阿里云 / 腾讯云 等 Linux）
#
#   bash setup.sh                       # 默认装到当前目录，用 CUDA 12.8 后端
#   bash setup.sh /root/autodl-tmp/lh   # 指定安装目录
#
# 会做三件事：
#   1. 下载 llama.cpp 的 Linux CUDA 版（含 llama-cli）
#   2. 下载一个 0.6B 的小模型（够跑通；想换大的自己放 model/ 里）
#   3. 跑一次 --list 验证
#
# 网络走 gh-proxy / hf-mirror，国内可直接跑。

set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$HERE}"
TAG="b12728"
PROXY="https://gh-proxy.com/https://github.com/ggml-org/llama.cpp/releases/download"

echo "==> 安装目录：$DEST"
cd "$DEST"

mkdir -p llama-cuda model

if [ ! -x llama-cuda/llama-cli ]; then
  echo "==> 下载 llama.cpp CUDA 12.8 版（约 210MB）"
  curl -L --retry 3 --retry-all-errors -o /tmp/llama-cuda.tar.gz \
    "$PROXY/$TAG/llama-$TAG-bin-ubuntu-cuda-12.8-x64.tar.gz"
  tar xzf /tmp/llama-cuda.tar.gz -C /tmp
  # 压缩包里是一层目录
  mv /tmp/llama-$TAG-bin-ubuntu-cuda-12.8-x64/* llama-cuda/ 2>/dev/null || true
  chmod +x llama-cuda/llama-cli llama-cuda/llama-tokenize 2>/dev/null || true
  rm -f /tmp/llama-cuda.tar.gz
fi

if [ ! -f model/Qwen3-0.6B-Q8_0.gguf ]; then
  echo "==> 下载 Qwen3-0.6B（约 610MB）"
  curl -L --retry 3 -o model/Qwen3-0.6B-Q8_0.gguf \
    "https://hf-mirror.com/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf"
fi

echo "==> 检查 CUDA 运行时"
if ! ldconfig -p 2>/dev/null | grep -q libcudart.so.12; then
  echo "    系统里没有 libcudart.so.12，用 pip 装一份到 Python 环境（约 300MB）"
  python3 -m pip install -q nvidia-cuda-runtime-cu12 nvidia-cublas-cu12 || \
    echo "    pip 安装失败，可以手动装 CUDA 12 运行时"
fi

echo "==> 验证"
./run.sh --list || python3 -m local_harness.cli --list

cat <<'EOF'

装好了。试试：

  ./run.sh                                            # 自动挑后端，开始聊天
  ./run.sh --backend cuda --gpu-layers -1 --tensor-core   # 全部层 + 张量核心
  ./run.sh --list                                     # 看检测结果

想换成更大的模型，把 .gguf 放进 model/ 或：
  ./run.sh -m /root/autodl-tmp/你的模型.gguf -c 8192
EOF

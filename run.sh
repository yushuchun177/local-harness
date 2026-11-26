#!/usr/bin/env bash
# local-harness · Linux / macOS 启动脚本
#
# 用法：
#   ./run.sh                 终端对话（自动挑显卡后端）
#   ./run.sh --list          看看检测到什么卡、什么后端、什么模型
#   ./run.sh --backend cuda --tensor-core --gpu-layers -1
#
# 依赖：python3（3.8+）。终端模式不需要 tkinter。

set -e
cd "$(dirname "$0")"

PY="${PYTHON:-python3}"
if ! command -v "$PY" >/dev/null 2>&1; then
  echo "找不到 python3，请先安装（Ubuntu/Debian: sudo apt install python3）" >&2
  exit 1
fi

# CUDA 版 llama.cpp 需要 libcudart.so.12 / libcublas.so.12。
# 系统里没有时，pip 装的 nvidia-* 轮子里带着，这里自动补进 LD_LIBRARY_PATH。
if [ -d llama-cuda ] && ! ldconfig -p 2>/dev/null | grep -q libcudart.so.12; then
  NV_LIBS="$("$PY" - <<'PY' 2>/dev/null || true
import glob, os, site
paths = []
for base in site.getsitepackages() + [site.getusersitepackages()]:
    paths += glob.glob(os.path.join(base, "nvidia", "*", "lib"))
print(":".join(sorted(set(paths))))
PY
)"
  if [ -n "$NV_LIBS" ]; then
    export LD_LIBRARY_PATH="$NV_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi
fi

exec "$PY" -m local_harness.cli "$@"

#!/usr/bin/env bash
# local-harness · Linux / macOS 启动脚本
#
# 用法：
#   ./run.sh                 终端对话（自动挑显卡后端）
#   ./run.sh --list          看看检测到什么卡、什么后端、什么模型
#   ./run.sh --backend cuda --tensor-core --gpu-layers -1
#
# 依赖：python3（3.8+）、python3-tk（只有图形界面才需要，终端模式不需要）

set -e
cd "$(dirname "$0")"

PY="${PYTHON:-python3}"
if ! command -v "$PY" >/dev/null 2>&1; then
  echo "找不到 python3，请先安装（Ubuntu/Debian: sudo apt install python3）" >&2
  exit 1
fi

exec "$PY" -m local_harness.cli "$@"

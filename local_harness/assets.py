# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""在程序所在目录附近查找 llama-cli 和 GGUF 模型。"""

import os
import re
import sys


def base_dir():
    """程序所在的真实目录。PyInstaller 打包后是 exe 所在目录，不是临时解包目录。"""
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    # 开发时不打包：从本文件往上两级就是项目根（localchat/localchat/assets.py）
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def bundle_dir():
    """单文件 exe 解包出来的临时目录（onedir 版就是程序目录）。

    单文件打包时 llama\\ 和 model\\ 被塞进了 exe，运行时解包到这里，
    所以找运行库和模型要在这里找；config.json、chats 仍然在 exe 旁边。
    """
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass and os.path.isdir(meipass):
        return meipass
    return base_dir()


def _walk(base, depth=3):
    """按层遍历，限制深度，避免在别的盘里乱翻。"""
    base = os.path.abspath(base)
    root_depth = base.rstrip("\\/").count(os.sep)
    for cur, dirs, files in os.walk(base):
        if cur.rstrip("\\/").count(os.sep) - root_depth >= depth:
            dirs[:] = []
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        yield cur, files


# Windows 的 llama.cpp 是 llama-cli.exe，Linux / macOS 没有扩展名。
# 三个名字都认，这样同一个程序目录在哪个系统上都能找到。
LLAMA_NAMES = ("llama-cli.exe", "llama-cli", "llama.exe", "main.exe", "main")

# 这些不是"能聊天"的模型：视觉投影、向量化模型、重排模型
_SKIP_HINTS = (
    "mmproj", "projector", "clip", "vision", "embed", "embedding",
    "bge-", "gte-", "e5-", "nomic-embed", "rerank", "bce-", "m3e",
)

# 分片文件的第二片起（llama.cpp 只需要第一片，会自动找其余的）
_SPLIT_RE = re.compile(r"-(\d{5})-of-(\d{5})\.gguf$", re.I)

MIN_MODEL_MB = 20


def is_chat_model(path):
    """粗筛：这个 .gguf 值不值得放进模型下拉框。"""
    name = os.path.basename(path).lower()
    if not name.endswith(".gguf"):
        return False
    if any(h in name for h in _SKIP_HINTS):
        return False
    m = _SPLIT_RE.search(name)
    if m and m.group(1) != "00001":
        return False
    try:
        if os.path.getsize(path) < MIN_MODEL_MB * 1048576:
            return False
    except OSError:
        return False
    return True


def find_llama_cli(explicit=None, backend=None):
    """找 llama.cpp 的命令行主程序。

    backend 给定时只看那个后端的目录（llama-cuda / llama-vulkan / llama），
    否则按 CUDA → Vulkan → 其它 的顺序挑第一个能用的。
    """
    if explicit:
        p = os.path.abspath(explicit)
        if os.path.isfile(p):
            return p

    base = bundle_dir()
    gpu_dirs = ("llama-cuda", "llama-vulkan", "llama-rocm", "llama-hip")

    if backend:
        subs = []
        if backend == "cpu":
            subs = ["llama", ""]
        elif backend in ("cuda", "vulkan", "hip"):
            subs = ["llama-" + backend, "llama-rocm" if backend == "hip" else ""]
        subs += ["", "bin", "llama.cpp", os.path.join("llama", "bin")]
    else:
        # 有显卡后端就优先用，没有就退回 llama\
        subs = list(gpu_dirs) + ["", "llama", "bin", "llama.cpp", os.path.join("llama", "bin")]

    # 常见位置优先（单文件打包时这里就是 _MEIPASS）
    for sub in subs:
        for name in LLAMA_NAMES:
            p = os.path.join(base, sub, name) if sub else os.path.join(base, name)
            if os.path.isfile(p):
                return p

    # 再按层扫
    for cur, files in _walk(base):
        for name in LLAMA_NAMES:
            if name in files:
                return os.path.join(cur, name)

    # onedir 版里 exe 旁边也算一遍
    if base != base_dir():
        for sub in ("", "llama", os.path.join("llama", "bin")):
            for name in LLAMA_NAMES:
                p = os.path.join(base_dir(), sub, name) if sub else os.path.join(base_dir(), name)
                if os.path.isfile(p):
                    return p
    return None


def find_model(explicit=None, extra_dirs=None):
    """找 GGUF 模型文件。有多个时挑最大的那个。"""
    if explicit:
        p = os.path.abspath(explicit)
        if os.path.isfile(p):
            return p
    models = find_all_models(extra_dirs=extra_dirs)
    return models[0]["path"] if models else None


def find_all_models(extra_dirs=None):
    """列出所有可用模型，给界面切换用。

    extra_dirs: 用户额外导入的文件夹列表。返回 [{path, label, sizeMB}, ...]，
    大模型在前。
    """
    from . import gguf

    seen = set()
    paths = []

    def add(p):
        p = os.path.abspath(p)
        if p in seen:
            return
        if not is_chat_model(p):
            return
        seen.add(p)
        paths.append(p)

    # 1) 程序目录下 model/ models/ 及附近几层；单文件版再看解包目录
    for base in (base_dir(), bundle_dir()):
        if not os.path.isdir(base):
            continue
        for cur, files in _walk(base, depth=2):
            for f in files:
                if f.lower().endswith(".gguf"):
                    add(os.path.join(cur, f))

    # 2) 用户额外导入的文件夹（直接放 .gguf，或再套一层子目录）
    for d in extra_dirs or []:
        if not d or not os.path.isdir(d):
            continue
        for root, dirs, files in os.walk(d):
            rel = os.path.relpath(root, d)
            depth = 0 if rel == "." else rel.count(os.sep) + 1
            if depth > 1:
                dirs[:] = []
            for f in files:
                if f.lower().endswith(".gguf"):
                    add(os.path.join(root, f))

    paths.sort(key=lambda p: os.path.getsize(p), reverse=True)

    out = []
    for p in paths:
        try:
            size = os.path.getsize(p) / 1048576
        except OSError:
            size = 0
        out.append(
            {
                "path": p,
                "label": gguf.model_label(p),
                "sizeMB": round(size),
            }
        )
    return out

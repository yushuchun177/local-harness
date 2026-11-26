# -*- coding: utf-8 -*-
"""打一个 Linux 版发布包（tar.gz）：源码 + run.sh + llama(CPU) + llama-cuda。

Windows 上打包要手动设置可执行位，否则 Linux 解压后 llama-cli / run.sh 没有 x 权限。
"""

import os
import shutil
import tarfile
import time

SRC = r"D:\minimind\localchat"
DL = r"D:\minimind\_linux"
STAGE = os.path.join(DL, "local-harness-1.3.0-linux-x64")
OUT = r"D:\minimind\dist\local-harness-1.3.0-linux-x64.tar.gz"

# 只带运行需要的东西
TOP_FILES = ["run.sh", "setup.sh", "README.md", "LICENSE", "requirements.txt", "使用说明.txt"]
MODULES = [
    "__init__.py", "assets.py", "brand.py", "cli.py", "compressor.py", "config.py",
    "devices.py", "engine.py", "gguf.py", "gui.py", "session.py", "store.py",
    "style.py", "ui.py",
]
DOCS = ["LINUX.md"]

# llama.cpp 包里不用带的工具
DROP = {
    "llama.exe", "llama-connect", "llama-server", "llama-bench", "llama-batched-bench",
    "llama-completion", "llama-fit-params", "llama-gemma3-cli", "llama-gguf-split",
    "llama-imatrix", "llama-llava-cli", "llama-minicpmv-cli", "llama-mtmd-cli",
    "llama-mtmd-debug", "llama-perplexity", "llama-quantize", "llama-qwen2vl-cli",
    "llama-results", "llama-tts", "ggml-rpc-server",
}
DROP_LIB_SUBSTR = ("llama-bench-impl", "llama-connect-", "llama-perplexity-impl",
                   "llama-quantize-impl", "llama-completion-impl", "llama-fit-params-impl",
                   "llama-batched-bench-impl")

EXEC = {"run.sh", "setup.sh", "llama-cli", "llama-tokenize", "llama-server"}


def stage():
    if os.path.isdir(STAGE):
        shutil.rmtree(STAGE)
    os.makedirs(STAGE)

    for name in TOP_FILES:
        p = os.path.join(SRC, name)
        if os.path.isfile(p):
            shutil.copy2(p, os.path.join(STAGE, name))

    pkg = os.path.join(STAGE, "local_harness")
    os.makedirs(pkg)
    for m in MODULES:
        p = os.path.join(SRC, "local_harness", m)
        if os.path.isfile(p):
            shutil.copy2(p, os.path.join(pkg, m))

    docs = os.path.join(STAGE, "docs")
    os.makedirs(docs)
    for d in DOCS:
        p = os.path.join(SRC, "docs", d)
        if os.path.isfile(p):
            shutil.copy2(p, os.path.join(docs, d))

    for archive, sub in (("llama-linux-cpu.tar.gz", "llama"),
                         ("llama-linux-cuda.tar.gz", "llama-cuda")):
        src = os.path.join(DL, archive)
        if not os.path.isfile(src):
            print("缺:", archive)
            continue
        tmp = os.path.join(DL, "_x_" + sub)
        if os.path.isdir(tmp):
            shutil.rmtree(tmp)
        os.makedirs(tmp)
        with tarfile.open(src, "r:gz") as t:
            t.extractall(tmp)
        # 压缩包里通常只有一层目录
        inner = tmp
        entries = os.listdir(tmp)
        if len(entries) == 1 and os.path.isdir(os.path.join(tmp, entries[0])):
            inner = os.path.join(tmp, entries[0])
        dst = os.path.join(STAGE, sub)
        shutil.copytree(inner, dst)
        # 清理不要的工具
        for root, dirs, files in os.walk(dst):
            for f in files:
                base, ext = os.path.splitext(f)
                if f in DROP or base in DROP or any(s in f for s in DROP_LIB_SUBSTR):
                    os.remove(os.path.join(root, f))
        shutil.rmtree(tmp)
        print("放入:", sub)

    os.makedirs(os.path.join(STAGE, "model"), exist_ok=True)
    with open(os.path.join(STAGE, "model", "把模型放这里.txt"), "w", encoding="utf-8") as f:
        f.write("把 .gguf 模型放进这个目录，或者用 ./run.sh -m /路径/模型.gguf 指定。\n")


def pack():
    if os.path.exists(OUT):
        os.remove(OUT)
    t0 = time.time()
    with tarfile.open(OUT, "w:gz", compresslevel=6) as t:
        base = os.path.dirname(STAGE)
        for root, dirs, files in os.walk(STAGE):
            dirs.sort()
            for name in sorted(files):
                full = os.path.join(root, name)
                rel = os.path.relpath(full, base).replace(os.sep, "/")
                info = t.gettarinfo(full, arcname=rel)
                if name in EXEC or name in ("run.sh",):
                    info.mode = 0o755
                else:
                    info.mode = 0o644
                if name.endswith(".so") or ".so." in name:
                    info.mode = 0o644
                with open(full, "rb") as f:
                    t.addfile(info, f)
    print("打包完成 %.1f 分钟 -> %s（%.1f MB）" % (
        (time.time() - t0) / 60, OUT, os.path.getsize(OUT) / 1048576))


if __name__ == "__main__":
    stage()
    pack()

# -*- coding: utf-8 -*-
"""把仓库要发布的源码收集到一个干净目录（不含模型、exe、构建产物）。

用法：
    python tools/make_repo.py            # 输出到 ..\\local-harness-repo
    python tools/make_repo.py D:\\tmp\\repo

这样仓库里只有源码和文档，模型动辄几 GB，不进版本库。
"""

import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(os.path.dirname(ROOT), "local-harness-repo")

FILES = [
    "LICENSE",
    "README.md",
    ".gitignore",
    "使用说明.txt",
    "requirements.txt",
    "main.py",
    "main_gui.py",
    "build_gui.spec",
    "build_onefile.spec",
    "version_gui.txt",
]

DIRS = ["local_harness", "tools"]

ASSET_FILES = ["app.png", "app.ico", "app64.b64", "splash.png"]

SKIP_SUFFIX = (".pyc", ".pyo")

# 一次性迁移/截图脚本，不往仓库里放
SKIP_FILES = {"rename_app.py", "shot_about.py", "push_github.py", "make_release.py"}


def copy_tree(src, dst):
    for base, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d not in ("__pycache__", ".git")]
        rel = os.path.relpath(base, src)
        target = os.path.join(dst, rel) if rel != "." else dst
        os.makedirs(target, exist_ok=True)
        for f in files:
            if f.endswith(SKIP_SUFFIX) or f in SKIP_FILES:
                continue
            shutil.copy2(os.path.join(base, f), os.path.join(target, f))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)

    for name in FILES:
        src = os.path.join(ROOT, name)
        if os.path.isfile(src):
            shutil.copy2(src, os.path.join(out, name))
        else:
            print("跳过（不存在）:", name)

    for name in DIRS:
        src = os.path.join(ROOT, name)
        if os.path.isdir(src):
            copy_tree(src, os.path.join(out, name))

    # 图标与启动画面（源码要能重建 exe）
    assets_out = os.path.join(out, "assets")
    os.makedirs(assets_out, exist_ok=True)
    for name in ASSET_FILES:
        src = os.path.join(ROOT, "assets", name)
        if os.path.isfile(src):
            shutil.copy2(src, os.path.join(assets_out, name))

    # 截图（有就带上）
    shots = os.path.join(ROOT, "dist", "上架素材")
    dst_shots = os.path.join(out, "docs", "screenshots")
    if os.path.isdir(shots):
        os.makedirs(dst_shots, exist_ok=True)
        mapping = {
            "01-欢迎-深色.png": "welcome-dark.png",
            "02-对话-深色.png": "chat-dark.png",
            "03-对话-浅色.png": "chat-light.png",
            "04-关于.png": "about.png",
        }
        for src_name, dst_name in mapping.items():
            p = os.path.join(shots, src_name)
            if os.path.isfile(p):
                shutil.copy2(p, os.path.join(dst_shots, dst_name))

    total = 0
    count = 0
    for base, _dirs, files in os.walk(out):
        for f in files:
            total += os.path.getsize(os.path.join(base, f))
            count += 1
    print("仓库目录: %s（%d 个文件，%.2f MB）" % (out, count, total / 1048576.0))


if __name__ == "__main__":
    main()

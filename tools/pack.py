# -*- coding: utf-8 -*-
# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""打包绿色版：生成 pack\\local-harness-<版本>\\，可选打 zip。

用法：
    python tools/pack.py            # 只生成目录
    python tools/pack.py --zip      # 同时打 dist\\local-harness-<版本>-Windows-x64.zip
"""

import json
import os
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VERSION = "1.2.0"
NAME = "local-harness-%s" % VERSION

BUILT = os.path.join(ROOT, "distgui", "local-harness")
DIST = os.path.join(ROOT, "dist")
SRC_LLAMA = os.path.join(DIST, "local-harness", "llama")
STAGE = os.path.join(ROOT, "pack", NAME)

# 只保留跑对话需要的东西，其余 llama.cpp 小工具不进包
DROP = {
    "llama.exe", "llama-connect.exe", "llama-server.exe", "llama-bench.exe",
    "llama-batched-bench.exe", "llama-completion.exe", "llama-fit-params.exe",
    "llama-gemma3-cli.exe", "llama-gguf-split.exe", "llama-imatrix.exe",
    "llama-llava-cli.exe", "llama-minicpmv-cli.exe", "llama-mtmd-cli.exe",
    "llama-mtmd-debug.exe", "llama-perplexity.exe", "llama-quantize.exe",
    "llama-qwen2vl-cli.exe", "llama-results.exe", "llama-tts.exe",
    "ggml-rpc-server.exe",
    "llama-batched-bench-impl.dll",
    # 注意：llama-server-impl.dll 不能删——llama-cli-impl.dll 直接依赖它
    "llama-connect.dll", "llama-bench-impl.dll",
    "llama-completion-impl.dll", "llama-fit-params-impl.dll",
    "llama-perplexity-impl.dll", "llama-quantize-impl.dll",
}

MODEL_NOTE = """把 .gguf 模型文件放到这个目录里。

推荐（按电脑配置挑一个）：
  Qwen3-0.6B-Q8_0.gguf             约 640MB   最轻快，办公本可跑
  Qwen3-1.7B-Q8_0.gguf             约 1.8GB   更聪明，8GB 内存够用
  qwen2.5-3b-instruct-q4_k_m.gguf  约 2.1GB   建议 16GB 内存

放好之后重开程序，顶部模型下拉框里就能选到。
"""

CONFIG = {
    "ctx": 4096,
    "temp": 0.7,
    "max_tokens": 512,
    "threads": 0,
    "system": "你是一个中文助手，请始终用简体中文回答，回答简洁明了。",
    "dark": True,
    "model": "",
    "reasoning": False,
    "model_dirs": [],
    "window": {"w": 1080, "h": 720},
    "compress_enabled": True,
    "compress_threshold": 2048,
    "compress_step": 1024,
    "compress_keep": 4,
}


def write_text(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    do_zip = "--zip" in sys.argv

    exe = os.path.join(BUILT, "local-harness.exe")
    if not os.path.exists(exe):
        sys.exit("先打包 exe：pyinstaller build_gui.spec --distpath distgui")
    if not os.path.isdir(SRC_LLAMA):
        sys.exit("找不到 llama 目录：%s" % SRC_LLAMA)

    if os.path.isdir(STAGE):
        shutil.rmtree(STAGE)
    os.makedirs(STAGE)

    # 1) 程序 + 运行时
    shutil.copy2(exe, STAGE)
    shutil.copytree(
        os.path.join(BUILT, "_internal"), os.path.join(STAGE, "_internal")
    )

    # 2) llama.cpp（精简）
    dst_llama = os.path.join(STAGE, "llama")
    os.makedirs(dst_llama)
    kept = 0
    for name in sorted(os.listdir(SRC_LLAMA)):
        if name in DROP:
            continue
        src = os.path.join(SRC_LLAMA, name)
        if os.path.isfile(src):
            shutil.copy2(src, dst_llama)
            kept += 1

    # 3) 模型目录、说明、默认配置、图标
    os.makedirs(os.path.join(STAGE, "model"))
    write_text(os.path.join(STAGE, "model", "把模型放这里.txt"), MODEL_NOTE)
    shutil.copy2(os.path.join(ROOT, "使用说明.txt"), STAGE)
    write_text(
        os.path.join(STAGE, "config.json"),
        json.dumps(CONFIG, ensure_ascii=False, indent=2),
    )
    os.makedirs(os.path.join(STAGE, "chats"))
    os.makedirs(os.path.join(STAGE, "assets"))
    shutil.copy2(os.path.join(ROOT, "assets", "app.ico"), os.path.join(STAGE, "assets"))

    # 4) 多语言使用手册
    manual_src = os.path.join(ROOT, "docs", "manual")
    if os.path.isdir(manual_src):
        manual_dst = os.path.join(STAGE, "manual")
        os.makedirs(manual_dst)
        for name in sorted(os.listdir(manual_src)):
            if name.endswith(".md"):
                shutil.copy2(os.path.join(manual_src, name), manual_dst)

    total = 0
    for base, _dirs, files in os.walk(STAGE):
        for f in files:
            total += os.path.getsize(os.path.join(base, f))
    print("已生成 %s（%.1f MB，llama 保留 %d 个文件）" % (STAGE, total / 1048576.0, kept))

    # 4) zip
    if do_zip:
        zip_path = os.path.join(DIST, "%s-Windows-x64.zip" % NAME)
        if os.path.exists(zip_path):
            os.remove(zip_path)
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for base, _dirs, files in os.walk(STAGE):
                for f in files:
                    full = os.path.join(base, f)
                    rel = os.path.relpath(full, os.path.dirname(STAGE))
                    z.write(full, rel)
        print("已压缩 %s（%.1f MB）" % (zip_path, os.path.getsize(zip_path) / 1048576.0))


if __name__ == "__main__":
    main()

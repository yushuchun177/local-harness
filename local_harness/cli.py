# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""命令行入口：解析参数、找到资源、交给界面。"""

import argparse
import os
import sys

from . import __version__
from .assets import base_dir, find_llama_cli, find_model, find_all_models


def build_parser():
    p = argparse.ArgumentParser(
        prog="localchat",
        description="local-harness —— 纯终端对话，完全离线，不联网。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
例子：
  localchat                             用默认参数启动
  localchat --ctx 8192                  上下文开到 8192
  localchat --temp 0.3 --max-tokens 1024  更保守、更长回答
  localchat --model 别的.gguf            指定模型
  localchat --list                      看看找到了哪些模型
""",
    )
    p.add_argument("-m", "--model", help="GGUF 模型路径（默认自动找）")
    p.add_argument("--cli", help="llama-cli 路径（默认自动找）")
    p.add_argument(
        "-c", "--ctx", type=int, default=4096, help="上下文长度，默认 4096"
    )
    p.add_argument(
        "-t", "--temp", type=float, default=0.7, help="温度 0~2，默认 0.7"
    )
    p.add_argument(
        "-n", "--max-tokens", type=int, default=512, help="单次最多生成多少 token，默认 512"
    )
    p.add_argument(
        "--threads", type=int, default=None, help="CPU 线程数，默认用满逻辑核心"
    )
    p.add_argument(
        "--reasoning", action="store_true", help="打开模型的思考模式（默认关闭）"
    )
    p.add_argument("-s", "--system", default=None, help="系统提示词")
    p.add_argument(
        "--timeout", type=int, default=180, help="模型加载超时秒数，默认 180"
    )
    p.add_argument("--list", action="store_true", help="列出找到的模型和 llama-cli")
    p.add_argument("-v", "--version", action="version", version="%(prog)s " + __version__)
    return p


def main(argv=None):
    parser = build_parser()
    opts = parser.parse_args(argv)

    if opts.list:
        print("程序目录：" + base_dir())
        cli = find_llama_cli(opts.cli)
        print("llama-cli：" + (cli if cli else "（没找到）"))
        models = find_all_models()
        if models:
            print("模型：")
            for m in models:
                print("  %6.0f MB  %s" % (os.path.getsize(m) / 1048576, m))
        else:
            print("模型：（没找到 .gguf）")
        return 0

    # 定位资源
    cli = find_llama_cli(opts.cli)
    if not cli:
        return _fail(
            "找不到 llama-cli 主程序。",
            [
                "应该放在程序目录下的 llama\\ 里，例如：",
                "  " + os.path.join(base_dir(), "llama", "llama-cli.exe"),
                "",
                "也可以用 --cli 手动指定路径。",
            ],
        )

    model = find_model(opts.model)
    if not model:
        return _fail(
            "找不到 .gguf 模型文件。",
            [
                "应该放在程序目录下的 model\\ 里，例如：",
                "  " + os.path.join(base_dir(), "model", "Qwen3-0.6B-Q8_0.gguf"),
                "",
                "也可以用 --model 手动指定路径。",
            ],
        )

    opts.cli = cli
    opts.model = model

    # 参数边界
    if opts.ctx < 128:
        return _fail("上下文至少要 128。", [])
    if not (0.0 <= opts.temp <= 5.0):
        return _fail("温度应该在 0 到 5 之间。", [])
    if opts.max_tokens < 1:
        return _fail("最大生成至少 1 个 token。", [])

    from .ui import main as ui_main

    return ui_main(opts)


def _fail(title, lines):
    print()
    print(title)
    print("-" * 50)
    for line in lines:
        print(line)
    print()
    try:
        input("按回车退出…")
    except Exception:
        pass
    return 1


if __name__ == "__main__":
    sys.exit(main())

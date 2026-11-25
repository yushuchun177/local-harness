# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""启动入口。PyInstaller 打包时把它作为脚本目标。"""

import sys


def _force_utf8_console():
    """把 Windows 控制台切成 UTF-8，否则中文全是乱码、还会在特殊符号上崩。

    打包成 exe 后，Python 默认按系统 ANSI 代码页（中文系统是 GBK）编解码，
    遇到 '›' 或生僻字就抛 UnicodeEncodeError。这里统一改成 UTF-8。
    """
    if sys.platform == "win32":
        try:
            import ctypes

            k = ctypes.windll.kernel32
            # 65001 = UTF-8
            k.SetConsoleOutputCP(65001)
            k.SetConsoleCP(65001)
        except Exception:
            pass

    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    # stdin 也要设，否则中文输入会被当成别的编码解析出代理字符
    try:
        sys.stdin.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


_force_utf8_console()

from local_harness.cli import main  # noqa: E402  必须在编码设置之后导入

if __name__ == "__main__":
    sys.exit(main())

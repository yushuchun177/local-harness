# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""图形界面启动入口（给 PyInstaller 的脚本目标）。"""

import os
import sys


def _setup():
    if sys.platform == "win32":
        try:
            import ctypes

            k = ctypes.windll.kernel32
            k.SetConsoleOutputCP(65001)
            k.SetConsoleCP(65001)
        except Exception:
            pass
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    try:
        sys.stdin.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


_setup()

from local_harness.gui import App  # noqa: E402


def _close_splash():
    """单文件版带启动画面时，主窗口起来就把画面关掉。"""
    if not os.environ.get("_PYI_SPLASH_IPC"):
        return          # 没打包启动画面，import 它会打一堆无用的报错
    try:
        import pyi_splash  # type: ignore

        pyi_splash.close()
    except Exception:
        pass


def main():
    app = App()
    app.root.after(80, _close_splash)
    app.root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())

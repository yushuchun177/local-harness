# -*- coding: utf-8 -*-
# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""预览/截图用：起一个 App，打开指定对话框，保持若干秒。

用法：python tools/preview.py about|settings|welcome|loading  [秒数]
"""

import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from local_harness.gui import App  # noqa: E402


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "about"
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 12.0

    app = App()
    # 预览界面时不需要真的加载模型，把启动流程取消掉
    try:
        app.root.after_cancel(app._boot_job)
    except Exception:
        pass
    app.root.update()

    if what == "light":
        app.root.after(200, app.toggle_theme)

    if what in ("about", "settings"):
        app.root.after(300, app.open_about if what == "about" else app.open_settings)
    elif what == "loading":
        app.root.after(300, lambda: app._show_loading_card("Qwen3 1.7B · Q8_0 · 上下文 8192"))
    elif what == "guide":
        app.root.after(300, lambda: app._show_guide_card(
            "还没有模型文件",
            [
                "程序目录下的 model\\ 里需要放 .gguf 模型文件。",
                "推荐 Qwen3-0.6B（约 640MB，轻快）或 Qwen3-1.7B（约 1.8GB，更聪明）。",
            ],
            [("打开 model 文件夹", lambda: None, False), ("导入模型文件夹", lambda: None, True)],
        ))
    elif what == "chat":
        def fake():
            app._hide_welcome()
            app._add_bubble("user", "帮我用一句话说明，为什么本地运行的模型更安全？")
            app._add_bubble(
                "assistant",
                "因为模型、对话记录和推理过程全部留在你自己的电脑里，"
                "既不上传云端，也不需要登录账号，断网也能照常用。",
            )
            app._add_bubble("user", "那它会记得我说过的话吗？")
            b = app._add_bubble("assistant", "会。当前对话的上下文会一直保留，")
            b.append("超出上下文窗口后才会自动压缩成摘要。")
            b.finalize_height()
            b.set_meta("42 字")
            app._scroll_bottom()
        app.root.after(400, fake)
    elif what == "guide":
        app.root.after(300, lambda: app._show_guide_card(
            "还没有模型文件",
            [
                "程序目录下的 model\\ 里需要放 .gguf 模型文件。",
                "推荐 Qwen3-0.6B（约 640MB，轻快）或 Qwen3-1.7B（约 1.8GB，更聪明）。",
            ],
            [("打开 model 文件夹", lambda: None, False), ("导入模型文件夹", lambda: None, True)],
        ))

    end = time.time() + secs
    while time.time() < end:
        app.root.update()
        time.sleep(0.02)
    try:
        app.session.stop()
    except Exception:
        pass
    app.root.destroy()


if __name__ == "__main__":
    main()

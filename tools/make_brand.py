# -*- coding: utf-8 -*-
# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""生成 localchat/brand.py（把 64×64 图标 base64 嵌进去）。"""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

b64 = io.open(os.path.join(ROOT, "assets", "app64.b64"), encoding="ascii").read().strip()
lines = "\n".join('    "%s"' % b64[i:i + 76] for i in range(0, len(b64), 76))

TEMPLATE = '''# -*- coding: utf-8 -*-
"""品牌信息：名称、版本、图标。图标是 64×64 PNG 的 base64，直接交给 tk。"""

APP_NAME = "本地千问"
APP_EN = "LocalChat"
VERSION = "1.1.0"
BUILD = "2026.11"
TAGLINE = "完全离线的本地 AI 对话"
SUBTITLE = "模型、对话、数据都留在这台电脑里"

ICON_PNG_B64 = (
{lines}
)


def window_icon(root):
    """给窗口和任务栏设置图标；失败就算了，不影响启动。"""
    try:
        import tkinter as tk

        img = tk.PhotoImage(data=ICON_PNG_B64)
        root.iconphoto(True, img)
        root._icon_ref = img          # 别被垃圾回收
        return img
    except Exception:
        return None


def version_text():
    return "%s %s" % (APP_NAME, VERSION)
'''

src = TEMPLATE.replace("{lines}", lines)
path = os.path.join(ROOT, "localchat", "brand.py")
with io.open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("written", path, len(src))

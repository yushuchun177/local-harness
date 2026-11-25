# -*- coding: utf-8 -*-
# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""品牌信息：名称、版本、图标。图标是 64×64 PNG 的 base64，直接交给 tk。"""

APP_NAME = "local-harness"
APP_EN = "local-harness"
VERSION = "1.2.0"
BUILD = "2026.11"
TAGLINE = "完全离线的本地大模型对话"
SUBTITLE = "模型、对话、数据都留在这台电脑里"

ICON_PNG_B64 = (
    "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAEJUlEQVR42u2b62sTWRjG/Q/mD/K+"
    "6nrb1dXW1lbrqPXS2ouuu2q91PsusiAIwuIHdUBbRFxMVQTx8kEQwS8blpW9odJUbRubOqZN2iZp"
    "fTxv1kjsO03PmZmY6Uwf+JFkppz3eZ5kAk1yZsyY1rSk1PwzNIEuCAnCAniM8Edv5FFzLXjTT+81"
    "gSHAFIM8a07D6wJzCobPQd51W+EbT44ZAvgEQyl8w4lRQwCfIVfCjuOjugA+pfDlUH8sowlMAXwK"
    "ZZv4jbHuaMYQwOdYXwrbj6Q1AQICfxVsO5zWBQgIukUBqZAAASHECtjamgoLEBDCrIAth0YQJFgB"
    "tQdHYJemEyO4cjuDf16ModiiGTSLZjrxzArYfGAYdrjwWxrJoff40qKZNNuub1bApv3DUKXjfgal"
    "Fnmw450VsLFlCCqcv5aCV0ReVP07KqD+6FBJXvaFLgfy5KgAfV8SsrTf9M6znxN5UsnACtiwNwlZ"
    "/no26rkCyJNKBlZAzZ4EZPGqVDKwAtb/mIAsXpVKBlbAuh8GIYtXpZKBFVC9exCyeFUqGVgBVd8P"
    "QJbJ9PBJEotrIphZ1pm9pcf5GkiMoeVUNHueoPt0TGUNK6lkKFoB3dHMJ+M56DEdz+nMxf7PzhN0"
    "TGUN1wtYuysOWQrp96fDLBxBx3NqPNzDztMxlTWspJKBFVC5Mw5ZvFqASgZWQEXzO8gymcYHzA83"
    "UcDx4SZbw0oqGVgBa5reQRYZXb0Vx4WrZvbWSv+9SGXPE3TfzhrjpZKBFVDeaEIWr0olAyugrMGE"
    "LF6VSgaLAt5CFu8WIJ+BFbB6Rz9kica8998geVLJwApYVd8PWR48HvFcAeRJJQMr4Lu6GGQ5eDru"
    "uQLIk0oGVsDK7TGo8Oe/ac+EJy+q/lkBK7b1QYWqXTH09pX+vYA8kBdV/6yAb7f2QZXaln487yrd"
    "R+M0mzzY8c4K+GbLG9ihsjmG9hsJDCbHvlhwmkUzabZd364VkM+9R8Nyz1wkkw1gh5ZfTLjhlRWw"
    "vDYKp5DBSb/JuZtEReMbuDHPCayAZZujcEpbR6Lgy/b4WRNuzHEDVsDSTb1wSluH9eeFf/ydQnlD"
    "FG7McAtWwJKNvXDK5RAv4Fz7ANxY221YAYv1Hjglv4BnkTTqW/vgxrrFgBXw9YYeOOXS9f8LuH4n"
    "gdV1vXBjzWJhUUA3nPJrWxxHzryFG2sVG1bAoprusAABgf9IauH61yEBAgL/mdyCda91AQKCblWA"
    "9lX1KwQBymr5e+H5Va8MAXzOxPsGxElt3tqXpgA+xaSMBfcMiD/S51a+hB+hbFK7RuZWdhkC+Ay1"
    "fUNzKroMAXyCYWvn2Ow1EV1gCjBFIe/2ts3llaDNKo8YAkwxDPLu2g7SWeWdoohOfWZZZ0gQtvr+"
    "vsSQpxB5JK/Tm52nJacPnl0ETkUgDbIAAAAASUVORK5CYII="
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

# -*- coding: utf-8 -*-
# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""鐢熸垚鍗曟枃浠剁増鐨勫惎鍔ㄧ敾闈?assets/splash.png锛堟繁鑹插崱鐗?+ 灞呬腑鍥炬爣锛夈€?
鐢ㄦ硶锛歱ython tools/make_splash.py
"""

import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import make_icon  # noqa: E402

W, H = 480, 260
BG = (0x21, 0x23, 0x27)
LOGO = 88
LOGO_X = (W - LOGO) // 2
LOGO_Y = 46


def write_png(path, w, h, rgba):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += rgba[y * w * 4:(y + 1) * w * 4]

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


def main():
    canvas = bytearray()
    for _y in range(H):
        for _x in range(W):
            canvas += bytes(BG) + b"\xff"

    logo = make_icon.rgba(LOGO)
    for y in range(LOGO):
        for x in range(LOGO):
            i = (y * LOGO + x) * 4
            a = logo[i + 3]
            if not a:
                continue
            dx, dy = LOGO_X + x, LOGO_Y + y
            j = (dy * W + dx) * 4
            for k in range(3):
                canvas[j + k] = (logo[i + k] * a + canvas[j + k] * (255 - a)) // 255

    out = os.path.join(ROOT, "assets", "splash.png")
    write_png(out, W, H, bytes(canvas))
    print("wrote", out)


if __name__ == "__main__":
    main()


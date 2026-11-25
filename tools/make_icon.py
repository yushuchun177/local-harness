# -*- coding: utf-8 -*-
# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""生成应用图标：圆角方块 + 聊天气泡，输出 PNG/ICO（纯标准库）。

用法：python tools/make_icon.py
产物：
    assets/app.ico          给 exe 用（16/24/32/48/64/128/256）
    assets/app.png          256×256 透明背景
    assets/app64.b64        64×64 PNG 的 base64，贴到 brand.py 里给窗口图标用
"""

import base64
import math
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ASSETS = os.path.join(ROOT, "assets")

TOP = (0x6F, 0x87, 0xFF)      # 渐变上
BOTTOM = (0x3B, 0x53, 0xE0)   # 渐变下
WHITE = (0xFF, 0xFF, 0xFF)
DOT = (0x3B, 0x53, 0xE0)


def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _rrect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    if x0 + r <= x <= x1 - r or y0 + r <= y <= y1 - r:
        return True
    cx = x0 + r if x < x0 + r else x1 - r
    cy = y0 + r if y < y0 + r else y1 - r
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def _circle(x, y, cx, cy, r):
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def _tri(x, y, ax, ay, bx, by, cx, cy):
    d1 = (x - bx) * (ay - by) - (ax - bx) * (y - by)
    d2 = (x - cx) * (by - cy) - (bx - cx) * (y - cy)
    d3 = (x - ax) * (cy - ay) - (cx - ax) * (y - ay)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def _sample(x, y, s):
    """s 是设计尺寸（256 基准），返回该点的 RGBA。"""
    k = s / 256.0
    # 底板
    if not _rrect(x, y, 8 * k, 8 * k, 248 * k, 248 * k, 54 * k):
        return (0, 0, 0, 0)
    base = _lerp(TOP, BOTTOM, min(1.0, max(0.0, (y - 8 * k) / (240 * k))))

    # 气泡（白色圆角矩形 + 左下小尾巴）
    in_bubble = _rrect(x, y, 52 * k, 60 * k, 204 * k, 170 * k, 34 * k)
    if not in_bubble:
        in_bubble = _tri(
            x, y,
            78 * k, 158 * k,
            78 * k, 200 * k,
            120 * k, 170 * k,
        )
    if in_bubble:
        # 三个圆点：对话中的样子
        for cx in (94, 128, 162):
            if _circle(x, y, cx * k, 115 * k, 11.5 * k):
                return DOT[0], DOT[1], DOT[2], 255
        return WHITE[0], WHITE[1], WHITE[2], 255

    return base[0], base[1], base[2], 255


def rgba(size, ss=4):
    """抗锯齿渲染，返回纯 RGBA 字节（size*size*4），不带 PNG 行过滤字节。"""
    px = bytearray()
    inv = 1.0 / (ss * ss)
    for j in range(size):
        for i in range(size):
            r = g = b = a = 0
            for sy in range(ss):
                for sx in range(ss):
                    x = i + (sx + 0.5) / ss
                    y = j + (sy + 0.5) / ss
                    cr, cg, cb, ca = _sample(x, y, size)
                    r += cr * ca
                    g += cg * ca
                    b += cb * ca
                    a += ca
            if a:
                px += bytes((int(r / a), int(g / a), int(b / a), int(a * inv)))
            else:
                px += b"\x00\x00\x00\x00"
    return bytes(px)


def render(size, ss=4):
    """PNG 用的行数据：每行前面加一个过滤字节 0。"""
    raw = rgba(size, ss)
    row = size * 4
    out = bytearray()
    for j in range(size):
        out.append(0)
        out += raw[j * row:(j + 1) * row]
    return bytes(out)


def png_bytes(size):
    raw = render(size)
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def dib_bytes(size):
    """ICO 里用的 BMP 数据：BITMAPINFOHEADER + BGRA 倒序 + AND 掩码。"""
    rgba = render(size)
    header = struct.pack(
        "<IiiHHIIiiII",
        40, size, size * 2, 1, 32, 0, len(rgba), 0, 0, 0, 0,
    )
    rows = []
    for y in range(size - 1, -1, -1):
        row = bytearray()
        for x in range(size):
            i = (y * size + x) * 4
            r, g, b, a = rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    # AND 掩码：全 0 表示按 alpha 通道走
    mask_row = ((size + 31) // 32) * 4
    mask = bytes(mask_row * size)
    return header + b"".join(rows) + mask


def ico_bytes(sizes):
    images = [dib_bytes(s) for s in sizes]
    out = struct.pack("<HHH", 0, 1, len(sizes))
    offset = 6 + 16 * len(sizes)
    entries = b""
    for s, data in zip(sizes, images):
        entries += struct.pack(
            "<BBBBHHII",
            0 if s >= 256 else s,
            0 if s >= 256 else s,
            0, 0, 1, 32, len(data), offset,
        )
        offset += len(data)
    return out + entries + b"".join(images)


def main():
    os.makedirs(ASSETS, exist_ok=True)
    png256 = png_bytes(256)
    with open(os.path.join(ASSETS, "app.png"), "wb") as f:
        f.write(png256)
    with open(os.path.join(ASSETS, "app.ico"), "wb") as f:
        f.write(ico_bytes([16, 24, 32, 48, 64, 128, 256]))
    b64 = base64.b64encode(png_bytes(64)).decode("ascii")
    with open(os.path.join(ASSETS, "app64.b64"), "w", encoding="ascii") as f:
        f.write(b64)
    print("wrote assets/app.png, assets/app.ico, assets/app64.b64 (%d b64 chars)" % len(b64))


if __name__ == "__main__":
    main()

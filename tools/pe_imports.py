# -*- coding: utf-8 -*-
# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""列出 PE 文件导入的 DLL，用来看缺了什么依赖。"""
import struct
import sys


def imports(path):
    data = open(path, "rb").read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    assert data[pe:pe + 4] == b"PE\0\0", "not PE"
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    dd = opt + (112 if magic == 0x20B else 96)
    imp_rva, imp_size = struct.unpack_from("<II", data, dd + 8)
    if not imp_rva:
        return []
    # 节表
    secs = []
    so = opt + struct.unpack_from("<H", data, pe + 20)[0]
    for i in range(nsec):
        s = so + 40 * i
        name = data[s:s + 8].rstrip(b"\0").decode("ascii", "replace")
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, s + 8)
        secs.append((name, vaddr, max(vsize, rawsize), rawptr))

    def off(rva):
        for _n, va, sz, rp in secs:
            if va <= rva < va + sz:
                return rp + (rva - va)
        return None

    base = off(imp_rva)
    out = []
    i = 0
    while True:
        entry = base + 20 * i
        name_rva = struct.unpack_from("<I", data, entry + 12)[0]
        if not name_rva:
            break
        o = off(name_rva)
        end = data.index(b"\0", o)
        out.append(data[o:end].decode("ascii", "replace"))
        i += 1
    return out


if __name__ == "__main__":
    for p in sys.argv[1:]:
        try:
            print(p, "->", ", ".join(imports(p)))
        except Exception as e:
            print(p, "ERR", e)

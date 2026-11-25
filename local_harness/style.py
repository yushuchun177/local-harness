# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""深色/浅色两套配色。

对齐 DeepSeek 客户端观感：
  深色：中性炭灰底，克制的蓝紫强调色，气泡低对比
  浅色：纯白底，浅灰分层，同样的蓝紫强调色
"""

DARK = {
    # 背景层次：页面 > 侧栏 > 卡片/输入 > hover
    "bg":        "#212327",   # 主背景（DeepSeek 深色是中性炭灰）
    "bg_alt":    "#1a1c1f",   # 侧栏，比主背景更深
    "bg_input":  "#2b2e34",   # 输入框
    "bg_user":   "#2f3542",   # 用户气泡（低饱和蓝灰）
    "bg_bot":    "#2b2e34",   # 助手气泡
    "bg_hover":  "#2a2e35",
    "bg_active": "#343945",
    "fg":        "#e5e7eb",
    "fg_dim":    "#9ca3af",
    "fg_faint":  "#6b7280",
    "line":      "#30343b",
    # DeepSeek 的蓝偏紫
    "accent":    "#4d6bfe",
    "accent_hi": "#6b85ff",
    "danger":    "#e05b5b",
    "ok":        "#43a37a",
    "sel":       "#354060",
    # 思考/压缩标记
    "think":     "#8b93a1",
}

LIGHT = {
    "bg":        "#ffffff",
    "bg_alt":    "#f7f8fa",
    "bg_input":  "#f3f4f6",
    "bg_user":   "#e8edff",
    "bg_bot":    "#f3f4f6",
    "bg_hover":  "#eceef1",
    "bg_active": "#e1e7fb",
    "fg":        "#1f2328",
    "fg_dim":    "#606a76",
    "fg_faint":  "#9aa3af",
    "line":      "#e5e7eb",
    "accent":    "#4d6bfe",
    "accent_hi": "#3554e8",
    "danger":    "#d64545",
    "ok":        "#2e8b57",
    "sel":       "#d8e0ff",
    "think":     "#8a93a0",
}


def theme(dark):
    return DARK if dark else LIGHT

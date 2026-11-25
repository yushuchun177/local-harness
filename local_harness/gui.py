# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""图形界面：主窗口。

布局参考 DeepSeek 客户端：
    顶部栏  模型选择 · 参数 · 主题切换
    左侧栏  对话历史
    中间    消息气泡流式区
    底部    输入框
"""

import math
import os
import queue
import sys
import threading
import time
import tkinter as tk
import tkinter.font as tkfont
from tkinter import ttk, messagebox, simpledialog, filedialog

from . import gguf
from .assets import base_dir, find_all_models, find_llama_cli
from .brand import (
    APP_NAME,
    BUILD,
    ICON_PNG_B64,
    SUBTITLE,
    TAGLINE,
    VERSION,
    window_icon,
)
from .config import Config
from .engine import LlamaError, clean_text
from .session import ChatSession
from .store import Store
from .style import theme

APP_TITLE = APP_NAME
FONT_UI = ("Microsoft YaHei UI", 10)
FONT_UI_S = ("Microsoft YaHei UI", 9)
FONT_TITLE = ("Microsoft YaHei UI", 11, "bold")
FONT_CHAT = ("Microsoft YaHei UI", 10)
FONT_HERO = ("Microsoft YaHei UI", 21, "bold")
FONT_CARD = ("Microsoft YaHei UI", 12, "bold")

# 欢迎页的示例问题：点一下就直接问
SAMPLE_PROMPTS = [
    ("帮我写一段自我介绍", "帮我写一段 100 字以内的自我介绍，语气轻松一点"),
    ("用大白话解释概念", "用大白话解释一下什么是「上下文窗口」，举个生活里的例子"),
    ("帮我看看代码", "帮我检查这段代码有没有明显问题：\n\n"),
    ("安排一个计划", "帮我安排一个三天的学习计划，每天两小时，从零开始学做家常菜"),
]


class Bubble(tk.Frame):
    """一条消息气泡。

    参照 DeepSeek 客户端：
      · 用户消息靠右，助手消息靠左
      · 气泡不铺满整行，按内容宽度但有上限
      · 左侧一个小圆头像
    """

    def __init__(self, parent, role, text, dark, on_copy=None, on_delete=None, max_px=0):
        super().__init__(parent)
        self.role = role
        self.dark = dark
        self.max_px = max_px
        text = clean_text(text)
        self._text = text
        self.on_copy = on_copy
        self.on_delete = on_delete

        t = theme(dark)
        self.configure(bg=t["bg"])

        is_user = role == "user"
        side = "right" if is_user else "left"
        anchor = "e" if is_user else "w"

        # 一行：头像 + 气泡列。用 grid 保证对齐且不铺满整行。
        self.columnconfigure(0, weight=1)
        row = tk.Frame(self, bg=t["bg"])
        row.grid(row=0, column=0, sticky=anchor)

        avatar_bg = t["accent"] if is_user else t["bg_active"]
        avatar_fg = "#ffffff" if is_user else t["fg_dim"]
        avatar = tk.Label(
            row,
            text="你" if is_user else "问",
            font=("Microsoft YaHei UI", 9, "bold"),
            fg=avatar_fg,
            bg=avatar_bg,
            width=2,
            height=2,
            relief="flat",
        )
        # 用户：气泡在左、头像在右；助手：头像在左、气泡在右
        col = tk.Frame(row, bg=t["bg"])
        if is_user:
            col.pack(side="left")
            avatar.pack(side="right", padx=(8, 2), pady=(2, 0))
        else:
            avatar.pack(side="left", padx=(2, 8), pady=(2, 0))
            col.pack(side="right")

        # 气泡本体：Text 给合理宽度，不 fill、不 expand，
        # 这样气泡按内容宽度显示，而不是铺满整行。
        self.body = tk.Text(
            col,
            wrap="word",
            font=FONT_CHAT,
            bg=t["bg_user"] if is_user else t["bg_bot"],
            fg=t["fg"],
            bd=0,
            padx=14,
            pady=10,
            height=1,
            width=62,
            cursor="arrow",
            highlightthickness=0,
            spacing1=1,
            spacing3=1,
        )
        self.body.pack(anchor=anchor)
        self.body.insert("1.0", text)
        self.body.configure(state="disabled")
        self._last_w = 0
        self.body.bind("<Configure>", self._on_body_configure)
        self._autosize()

        # 底部信息行
        self.meta = tk.Label(col, text="", font=FONT_UI_S, fg=t["fg_faint"], bg=t["bg"])
        self.meta.pack(anchor=anchor, pady=(2, 0))

        self._bind_copy()
        self._row = row
        self._col = col
        self._avatar = avatar
        self._is_user = is_user

    def restyle(self, dark):
        """主题切换时给这条气泡换色，不重建。"""
        self.dark = dark
        t = theme(dark)
        self.configure(bg=t["bg"])
        self._row.configure(bg=t["bg"])
        self._col.configure(bg=t["bg"])
        self.body.configure(
            bg=t["bg_user"] if self._is_user else t["bg_bot"],
            fg=t["fg"],
        )
        self.meta.configure(bg=t["bg"], fg=t["fg_faint"])
        self._avatar.configure(
            bg=t["accent"] if self._is_user else t["bg_active"],
            fg="#ffffff" if self._is_user else t["fg_dim"],
        )

    def _bind_copy(self):
        t = theme(self.dark)
        menu = tk.Menu(self, tearoff=0)

        def copy_all():
            self.clipboard_clear()
            self.clipboard_append(self._text)

        def copy_sel():
            try:
                sel = self.body.get("sel.first", "sel.last")
            except tk.TclError:
                return
            self.clipboard_clear()
            self.clipboard_append(sel)

        menu.add_command(label="复制全部", command=copy_all)
        menu.add_command(label="复制选中", command=copy_sel)
        if self.on_delete:
            menu.add_separator()
            menu.add_command(label="删除本条", command=self.on_delete)
        self.menu = menu

        def popup(e):
            menu.tk_popup(e.x_root, e.y_root)
            return "break"

        for w in (self.body, self.meta):
            w.bind("<Button-3>", popup)

    def _autosize(self):
        """按【显示行数】算高度。index() 返回的是逻辑行，
        自动折行的长文本会被算成 1 行，气泡就只有一行高，内容被裁掉。

        两个坑：
          · 气泡刚建出来、还没上屏时宽度是 1 像素，会把每个字算成一行；
          · Tk 的 displaylines 数的是"折行次数"，单行文本返回空。
        所以宽度没就绪就等一帧，行数统一按 折行数 + 1 算。
        """
        self._hug_width()
        try:
            self.update_idletasks()
        except Exception:
            pass
        if self.body.winfo_width() <= 1:
            self._autosize_later()
            return
        try:
            c = self.body.count("1.0", "end-1c", "displaylines")
            lines = (int(c[0]) if c else 0) + 1
        except Exception:
            try:
                lines = int(str(self.body.index("end-1c")).split(".")[0])
            except Exception:
                lines = 1
        lines = max(1, min(lines, 60))
        if int(self.body.cget("height")) != lines:
            self.body.configure(height=lines)

    def _hug_width(self):
        """气泡宽度跟着内容走：短消息就是小气泡，长消息最宽按窗口的 3/4。

        Tk 里 Text 的 width 单位是"字符"，而一个字符的像素宽 = 字体里 "0" 的宽度，
        不是汉字的宽度。用汉字宽度去除会算窄一半，气泡里的字就会硬折行。
        """
        try:
            fnt = tkfont.Font(font=self.body.cget("font"))
            unit = max(1, fnt.measure("0"))
            widest = 0
            for line in (self._text or "").split("\n"):
                widest = max(widest, fnt.measure(line))
            w = int(math.ceil(widest / float(unit))) + 1
            cap_chars = 62
            if getattr(self, "max_px", 0):
                cap_chars = max(16, int(self.max_px / float(unit)))
            w = max(6, min(w, cap_chars))
        except Exception:
            return
        if int(self.body.cget("width")) != w:
            self.body.configure(width=w)

    def _autosize_later(self):
        if getattr(self, "_size_job", None):
            return

        def run():
            self._size_job = None
            self._autosize()

        try:
            self._size_job = self.after(25, run)
        except Exception:
            self._size_job = None

    def _on_body_configure(self, e):
        """宽度变了（第一次上屏、或者字号变化）才重算，避免自己改高度触发死循环。"""
        if e.width == getattr(self, "_last_w", 0):
            return
        self._last_w = e.width
        self._autosize()

    def append(self, text):
        self._text += text
        self.body.configure(state="normal")
        self.body.insert("end", text)
        self.body.configure(state="disabled")
        # 流式追加时高度变化频繁，节流：只在跨行时才重算高度
        self._append_len = getattr(self, "_append_len", 0) + len(text)
        if self._append_len >= 80:
            self._append_len = 0
            self._autosize()
        self.body.see("end")

    def finalize_height(self):
        """流式结束/一次性插入后，强制重算一次高度。"""
        self._append_len = 0
        self._autosize()

    def set_meta(self, text):
        t = theme(self.dark)
        self.meta.configure(text=text, fg=t["fg_faint"])

    def set_text(self, text):
        self._text = text
        self.body.configure(state="normal")
        self.body.delete("1.0", "end")
        self.body.insert("1.0", text)
        self.body.configure(state="disabled")
        self._autosize()


class App:
    def __init__(self):
        self.base = base_dir()
        self.cfg = Config(self.base)
        self.store = Store(self.base)

        self.dark = bool(self.cfg.get("dark"))
        self.t = theme(self.dark)

        self.llama_cli = find_llama_cli()
        self.models = find_all_models(extra_dirs=self.cfg.get("model_dirs") or [])

        self.session = None
        self.current_chat = None
        self.generating = False
        self.stop_flag = threading.Event()
        self.ui_queue = queue.Queue()

        # 上下文压缩插件
        self.compressor = None
        self._compressing = False
        self._token_count = 0
        # 压缩完补发那一问时，不能立刻再压缩一次，否则会无限循环
        self._skip_compress_once = False

        self._build_root()
        self._build_style()
        self._build_topbar()
        self._build_body()
        self._build_input()

        self._load_model_info()
        self._refresh_chat_list()
        self._show_welcome()

        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.root.after(50, self._pump)
        self._boot_job = self.root.after(100, self._boot)

    # ============================================================ 窗口
    def _build_root(self):
        w = self.cfg.get("window") or {"w": 1080, "h": 720}
        self.root = tk.Tk()
        self.root.title("%s %s" % (APP_NAME, VERSION))
        self.root.geometry("%dx%d" % (w.get("w", 1080), w.get("h", 720)))
        self.root.minsize(900, 620)
        self.root.configure(bg=self.t["bg"])
        try:
            self.root.tk.call("tk", "scaling", 1.25)
        except Exception:
            pass
        window_icon(self.root)
        try:
            self.logo_img = tk.PhotoImage(data=ICON_PNG_B64)      # 64px
            self.logo_small = self.logo_img.subsample(2)          # 32px
            self.logo_big = self.logo_img.zoom(2).subsample(2)    # 64px，清晰一点
        except Exception:
            self.logo_img = self.logo_small = self.logo_big = None

    def _build_style(self):
        t = self.t
        s = ttk.Style(self.root)
        try:
            s.theme_use("clam")
        except Exception:
            pass

        s.configure(".", background=t["bg"], foreground=t["fg"], font=FONT_UI)
        s.configure("TFrame", background=t["bg"])
        s.configure("TLabel", background=t["bg"], foreground=t["fg"], font=FONT_UI)
        s.configure("Dim.TLabel", background=t["bg"], foreground=t["fg_dim"], font=FONT_UI_S)
        s.configure("Top.TFrame", background=t["bg_alt"])
        s.configure("Side.TFrame", background=t["bg_alt"])

        s.configure(
            "TButton",
            background=t["bg_input"],
            foreground=t["fg"],
            borderwidth=0,
            focusthickness=0,
            padding=(10, 5),
            font=FONT_UI_S,
        )
        s.map(
            "TButton",
            background=[("active", t["bg_hover"]), ("pressed", t["bg_active"])],
            foreground=[("disabled", t["fg_faint"])],
        )

        s.configure(
            "Accent.TButton",
            background=t["accent"],
            foreground="#ffffff",
            borderwidth=0,
            padding=(12, 5),
            font=FONT_UI_S,
        )
        s.map(
            "Accent.TButton",
            background=[("active", t["accent_hi"]), ("disabled", t["bg_input"])],
            foreground=[("disabled", t["fg_faint"])],
        )

        s.configure(
            "TCombobox",
            fieldbackground=t["bg_input"],
            background=t["bg_input"],
            foreground=t["fg"],
            arrowcolor=t["fg_dim"],
            borderwidth=0,
            padding=4,
        )
        s.map(
            "TCombobox",
            fieldbackground=[("readonly", t["bg_input"])],
            foreground=[("readonly", t["fg"])],
            selectbackground=[("readonly", t["bg_input"])],
            selectforeground=[("readonly", t["fg"])],
        )

        s.configure("TSeparator", background=t["line"])

        # 顶部栏那种"低调"按钮：无底色，hover 才浮出来
        s.configure(
            "Ghost.TButton",
            background=t["bg_alt"],
            foreground=t["fg_dim"],
            borderwidth=0,
            focusthickness=0,
            padding=(9, 4),
            font=FONT_UI_S,
        )
        s.map(
            "Ghost.TButton",
            background=[("active", t["bg_hover"]), ("pressed", t["bg_active"])],
            foreground=[("active", t["fg"])],
        )

        # 欢迎页的示例问题小卡片
        s.configure(
            "Chip.TButton",
            background=t["bg_input"],
            foreground=t["fg"],
            borderwidth=0,
            focusthickness=0,
            padding=(14, 9),
            font=FONT_UI_S,
            anchor="w",
        )
        s.map(
            "Chip.TButton",
            background=[("active", t["bg_active"])],
            foreground=[("active", t["fg"])],
        )

        s.configure("Card.TFrame", background=t["bg_bot"])

        s.configure(
            "Vertical.TScrollbar",
            background=t["bg_active"],
            troughcolor=t["bg"],
            bordercolor=t["bg"],
            lightcolor=t["bg_active"],
            darkcolor=t["bg_active"],
            borderwidth=0,
            arrowcolor=t["fg_faint"],
            width=8,
        )
        s.map(
            "Vertical.TScrollbar",
            background=[("active", t["bg_hover"]), ("pressed", t["bg_hover"])],
        )
        # 去掉两头的箭头，只留一条细滚动条（clam 默认带箭头，看着很旧）
        try:
            s.layout(
                "Vertical.TScrollbar",
                [
                    (
                        "Vertical.Scrollbar.trough",
                        {
                            "sticky": "ns",
                            "children": [
                                ("Vertical.Scrollbar.thumb", {"expand": "1", "sticky": "nswe"})
                            ],
                        },
                    )
                ],
            )
        except Exception:
            pass

    # ============================================================ 顶部栏
    def _build_topbar(self):
        t = self.t
        # 两层：第一行 = 模型 + 主题/设置；第二行 = 三个参数滑块
        bar = tk.Frame(self.root, bg=t["bg_alt"])
        bar._zone = "top"
        bar.pack(side="top", fill="x")

        # ---- 第一行 ----
        row1 = tk.Frame(bar, bg=t["bg_alt"])
        row1._zone = "top"
        row1.pack(fill="x", padx=14, pady=(8, 2))

        tk.Label(row1, text="模型", font=FONT_UI_S, fg=t["fg_dim"], bg=t["bg_alt"]).pack(
            side="left", padx=(0, 6)
        )
        self.model_var = tk.StringVar()
        self.model_box = ttk.Combobox(
            row1,
            textvariable=self.model_var,
            state="readonly",
            width=30,
            font=FONT_UI_S,
        )
        self.model_box.pack(side="left")
        self.model_box.bind("<<ComboboxSelected>>", self._on_model_change)

        # 导入模型按钮
        ttk.Button(
            row1, text="导入", width=5, style="Ghost.TButton", command=self.import_model_folder
        ).pack(side="left", padx=(6, 0))

        right = tk.Frame(row1, bg=t["bg_alt"])
        right._zone = "top"
        right.pack(side="right")

        self.theme_btn = ttk.Button(
            right, text=self._theme_btn_label(), width=7, style="Ghost.TButton",
            command=self.toggle_theme,
        )
        self.theme_btn.pack(side="right", padx=(4, 0))

        ttk.Button(
            right, text="设置", width=6, style="Ghost.TButton", command=self.open_settings
        ).pack(side="right", padx=(4, 0))

        ttk.Button(
            right, text="关于", width=6, style="Ghost.TButton", command=self.open_about
        ).pack(side="right", padx=(4, 0))

        # ---- 第二行：参数 ----
        row2 = tk.Frame(bar, bg=t["bg_alt"])
        row2._zone = "top"
        row2.pack(fill="x", padx=14, pady=(2, 8))

        self._param_group(row2, "温度", "temp", 0.0, 2.0, 0.05, 7.0)
        self._param_group(row2, "上下文", "ctx", 512, 32768, 512, 9.0)
        self._param_group(row2, "回复上限", "max_tokens", 64, 8192, 64, 8.0)

        # 思考模式开关（靠右）
        self.reasoning_var = tk.BooleanVar(value=bool(self.cfg.get("reasoning")))
        reason_cb = tk.Checkbutton(
            row2,
            text="思考模式",
            variable=self.reasoning_var,
            command=self._on_reasoning_toggle,
            font=FONT_UI_S,
            fg=t["fg_dim"],
            bg=t["bg_alt"],
            activebackground=t["bg_alt"],
            selectcolor=t["bg_input"],
            bd=0,
            highlightthickness=0,
        )
        reason_cb.pack(side="right", padx=(10, 0))

        # 分隔线
        tk.Frame(self.root, bg=t["line"], height=1).pack(side="top", fill="x")

    def _param_group(self, parent, label, key, lo, hi, step, width):
        """一个"标签 + 数值 + 滑块"的组合，紧凑地横排在顶部栏。"""
        t = self.t
        wrap = tk.Frame(parent, bg=t["bg_alt"])
        wrap._zone = "top"
        wrap.pack(side="left", padx=(0, 14))

        top = tk.Frame(wrap, bg=t["bg_alt"])
        top._zone = "top"
        top.pack(fill="x")
        tk.Label(top, text=label, font=FONT_UI_S, fg=t["fg_dim"], bg=t["bg_alt"]).pack(
            side="left"
        )
        # 数值框：点击可直接输入，滑块拖动时实时刷新
        val = tk.Entry(
            top,
            font=FONT_UI_S,
            fg=t["fg"],
            bg=t["bg_input"],
            insertbackground=t["accent"],
            width=7,
            justify="right",
            relief="flat",
            bd=0,
            highlightthickness=0,
        )
        val.pack(side="left", padx=(4, 0))
        val.bind("<Return>", lambda e, k=key: self._on_param_typed(k))
        val.bind("<FocusOut>", lambda e, k=key: self._on_param_typed(k))

        var = tk.DoubleVar(value=float(self.cfg.get(key)))
        slider = tk.Scale(
            wrap,
            from_=lo,
            to=hi,
            resolution=step,
            orient="horizontal",
            variable=var,
            showvalue=False,
            length=int(width * 12),
            width=8,
            bg=t["bg_alt"],
            fg=t["fg"],
            troughcolor=t["bg_input"],
            activebackground=t["accent"],
            highlightthickness=0,
            bd=0,
            sliderrelief="flat",
            command=lambda v, k=key: self._on_param(k, v),
        )
        slider._zone = "top"
        slider.pack()

        setattr(self, "_slider_" + key, slider)
        setattr(self, "_var_" + key, var)
        setattr(self, "_lbl_" + key, val)
        setattr(self, "_lo_" + key, lo)
        setattr(self, "_hi_" + key, hi)
        self._update_param_label(key)
        return wrap

    def _update_param_label(self, key):
        v = getattr(self, "_var_" + key).get()
        lbl = getattr(self, "_lbl_" + key)
        if key == "temp":
            text = "%.2f" % v
        else:
            text = str(int(v))
        # 只有焦点不在输入框时才覆盖，避免打字打到一半被滑块刷新打断
        try:
            if self.root.focus_get() is not lbl:
                lbl.delete(0, "end")
                lbl.insert(0, text)
        except Exception:
            lbl.delete(0, "end")
            lbl.insert(0, text)

    def _on_param_typed(self, key):
        """用户在数值框里手动输入后按回车/失焦。"""
        lbl = getattr(self, "_lbl_" + key)
        raw = lbl.get().strip()
        if not raw:
            self._update_param_label(key)  # 空输入回退到当前值
            return
        try:
            v = float(raw)
        except ValueError:
            self._update_param_label(key)
            return
        lo = getattr(self, "_lo_" + key)
        hi = getattr(self, "_hi_" + key)
        v = max(lo, min(hi, v))
        if key != "temp":
            v = int(v)
        # 同步滑块、变量、配置
        getattr(self, "_var_" + key).set(float(v))
        self._apply_param(key, v)

    def _on_param(self, key, value):
        if key == "temp":
            v = float(value)
        else:
            v = int(float(value))
        self._apply_param(key, v)

    def _apply_param(self, key, v):
        """应用参数值：更新标签、配置、会话。"""
        self._update_param_label(key)
        self.cfg.set(key, v, save=False)
        self._cfg_dirty = True

        # 让新参数立刻作用到正在运行的会话。
        # 温度、max_tokens 都是 generate() 的调用参数，改完下一问就生效；
        # ctx 要让模型重启才生效，所以只改配置，等提示后由用户决定。
        if self.session:
            if key == "temp":
                self.session.temp = v
            elif key == "max_tokens":
                self.session.max_tokens = v
            elif key == "ctx":
                # ctx 是启动时参数，必须重启进程才生效。
                # 拖动时不要每次都重启，等松手 800ms 后再重建。
                self.session.ctx = v
                self._ctx_pending_restart = True

        if not hasattr(self, "_save_timer"):
            self._save_timer = None
        if self._save_timer:
            try:
                self.root.after_cancel(self._save_timer)
            except Exception:
                pass
        self._save_timer = self.root.after(800, self._flush_cfg)

    def _on_reasoning_toggle(self):
        """思考模式开关：改配置，重启会话生效。"""
        v = bool(self.reasoning_var.get())
        self.cfg.set("reasoning", v)
        if self.session:
            self.session.reasoning = v
            if self.current_chat and not self.generating:
                self._restart_for_context(
                    (self.current_chat.get("messages") or []), None
                )
                self._set_status(
                    "思考模式已%s，正在重启模型…" % ("开启" if v else "关闭")
                )

    def _flush_cfg(self):
        self._save_timer = None
        self.cfg.save()

        # 上下文滑块停下来了，重建会话让它生效（保留当前对话）
        if getattr(self, "_ctx_pending_restart", False):
            self._ctx_pending_restart = False
            if self.session and self.current_chat and not self.generating:
                self._restart_for_context(
                    (self.current_chat.get("messages") or []), None
                )
                self._set_status("上下文已调整为 %d，正在重启模型…" % int(self.cfg.get("ctx")))

    # ============================================================ 主体
    def _build_body(self):
        t = self.t
        body = tk.Frame(self.root, bg=t["bg"])
        body.pack(side="top", fill="both", expand=True)

        # 左侧栏
        self.side = tk.Frame(body, bg=t["bg_alt"], width=210)
        self.side._zone = "side"
        self.side.pack(side="left", fill="y")
        self.side.pack_propagate(False)

        head = tk.Frame(self.side, bg=t["bg_alt"])
        head._zone = "side"
        head.pack(fill="x", padx=14, pady=(14, 10))

        brand = tk.Frame(head, bg=t["bg_alt"])
        brand._zone = "side"
        brand.pack(fill="x")

        if self.logo_small is not None:
            tk.Label(brand, image=self.logo_small, bg=t["bg_alt"]).pack(
                side="left", padx=(0, 8)
            )

        name_col = tk.Frame(brand, bg=t["bg_alt"])
        name_col._zone = "side"
        name_col.pack(side="left", fill="x", expand=True)

        tk.Label(
            name_col, text=APP_NAME, font=FONT_CARD, fg=t["fg"], bg=t["bg_alt"]
        ).pack(anchor="w")
        tk.Label(
            name_col,
            text="v%s · 完全离线" % VERSION,
            font=FONT_UI_S,
            fg=t["fg_faint"],
            bg=t["bg_alt"],
        ).pack(anchor="w")

        self.new_btn = ttk.Button(
            head, text="＋ 新对话", style="Accent.TButton", command=self.new_chat
        )
        self.new_btn.pack(fill="x", pady=(12, 0), ipady=3)

        # 列表容器
        listwrap = tk.Frame(self.side, bg=t["bg_alt"])
        listwrap._zone = "side"
        listwrap.pack(fill="both", expand=True, padx=(8, 4), pady=(0, 8))

        self.side_canvas = tk.Canvas(
            listwrap, bg=t["bg_alt"], bd=0, highlightthickness=0
        )
        self.side_canvas._zone = "side"
        self.side_canvas.pack(side="left", fill="both", expand=True)
        sb = ttk.Scrollbar(listwrap, orient="vertical", command=self.side_canvas.yview)
        sb.pack(side="right", fill="y")
        self.side_canvas.configure(yscrollcommand=sb.set)

        self.chat_list = tk.Frame(self.side_canvas, bg=t["bg_alt"])
        self._side_win = self.side_canvas.create_window(
            (0, 0), window=self.chat_list, anchor="nw"
        )
        self.chat_list.bind(
            "<Configure>",
            lambda e: self.side_canvas.configure(scrollregion=self.side_canvas.bbox("all")),
        )
        self.side_canvas.bind(
            "<Configure>",
            lambda e: self.side_canvas.itemconfigure(self._side_win, width=e.width),
        )
        self.side_canvas.bind_all("<MouseWheel>", self._on_side_wheel, add="+")

        # 竖分隔线
        tk.Frame(body, bg=t["line"], width=1).pack(side="left", fill="y")

        # 聊天区
        chatwrap = tk.Frame(body, bg=t["bg"])
        chatwrap.pack(side="left", fill="both", expand=True)

        self.chat_canvas = tk.Canvas(chatwrap, bg=t["bg"], bd=0, highlightthickness=0)
        self.chat_canvas.pack(side="left", fill="both", expand=True)
        csb = ttk.Scrollbar(chatwrap, orient="vertical", command=self.chat_canvas.yview)
        csb.pack(side="right", fill="y")
        self.chat_canvas.configure(yscrollcommand=csb.set)

        self.msg_frame = tk.Frame(self.chat_canvas, bg=t["bg"])
        self._msg_win = self.chat_canvas.create_window(
            (0, 0), window=self.msg_frame, anchor="nw", width=1
        )
        self.msg_frame.bind("<Configure>", self._on_msg_configure)
        self.chat_canvas.bind("<Configure>", self._on_chat_resize)
        self.chat_canvas.bind("<MouseWheel>", self._on_chat_wheel)

    def _on_msg_configure(self, e):
        self.chat_canvas.configure(scrollregion=self.chat_canvas.bbox("all"))
        self._fit_msg_height()

    def _on_chat_resize(self, e):
        self.chat_canvas.itemconfigure(self._msg_win, width=e.width)
        self._fit_msg_height()

    def _fit_msg_height(self):
        """让消息区至少和可视区域一样高：内容少的时候欢迎页才能垂直居中。"""
        try:
            h = max(self.chat_canvas.winfo_height(), self.msg_frame.winfo_reqheight())
            if getattr(self, "_msg_h", None) != h:
                self._msg_h = h
                self.chat_canvas.itemconfigure(self._msg_win, height=h)
                self.chat_canvas.configure(scrollregion=self.chat_canvas.bbox("all"))
        except Exception:
            pass

    def _on_chat_wheel(self, e):
        self.chat_canvas.yview_scroll(int(-e.delta / 120), "units")

    def _on_side_wheel(self, e):
        try:
            x, y = self.root.winfo_pointerxy()
            w = self.root.winfo_containing(x, y)
            p = w
            while p is not None:
                if p is self.side_canvas:
                    self.side_canvas.yview_scroll(int(-e.delta / 120), "units")
                    return
                p = getattr(p, "master", None)
        except Exception:
            pass

    # ============================================================ 输入区
    def _build_input(self):
        t = self.t
        tk.Frame(self.root, bg=t["line"], height=1).pack(side="top", fill="x")

        wrap = tk.Frame(self.root, bg=t["bg"])
        wrap.pack(side="bottom", fill="x", padx=0, pady=0)

        box = tk.Frame(wrap, bg=t["bg_input"], bd=0)
        box.pack(fill="x", padx=18, pady=12)

        self.input = tk.Text(
            box,
            height=2,
            wrap="word",
            font=FONT_CHAT,
            bg=t["bg_input"],
            fg=t["fg"],
            insertbackground=t["accent"],
            bd=0,
            padx=12,
            pady=10,
            highlightthickness=0,
        )
        self.input.pack(side="left", fill="both", expand=True)
        self.input.bind("<Return>", self._on_return)
        self.input.bind("<Shift-Return>", self._on_shift_return)
        self.input.bind("<KeyPress>", self._autogrow)

        # placeholder：空时显示灰色提示，聚焦/输入时消失
        self._placeholder = "说点什么…（Ctrl+L 清空）"
        self._input_empty = True
        self.input.insert("1.0", self._placeholder)
        self.input.configure(fg=t["fg_faint"])
        self.input.bind("<FocusIn>", self._on_input_focus_in)
        self.input.bind("<FocusOut>", self._on_input_focus_out)

        btns = tk.Frame(box, bg=t["bg_input"])
        btns.pack(side="right", padx=(6, 8))

        # 同一个位置：平时是"发送"，生成中变成"停止"（DeepSeek 的做法）
        self.action_btn = ttk.Button(
            btns, text="发送 ↑", width=8, style="Accent.TButton", command=self._on_action
        )
        self.action_btn.pack(side="top", pady=(6, 3))
        # 兼容旧代码里对 send_btn / stop_btn 的引用
        self.send_btn = self.action_btn
        self.stop_btn = self.action_btn

        self.hint = tk.Label(
            wrap,
            text="Enter 发送 · Shift+Enter 换行 · Ctrl+Enter 发送 · Esc 停止",
            font=FONT_UI_S,
            fg=t["fg_faint"],
            bg=t["bg"],
        )
        self.hint.pack(pady=(0, 2))

        # 状态行：左=模型/运行状态，右=token 占用，两个独立标签
        status_row = tk.Frame(wrap, bg=t["bg"])
        status_row.pack(fill="x", padx=20, pady=(0, 6))

        self.status_lbl = tk.Label(
            status_row,
            text="",
            font=FONT_UI_S,
            fg=t["fg_dim"],
            bg=t["bg"],
            anchor="w",
        )
        self.status_lbl.pack(side="left")

        self.token_lbl = tk.Label(
            status_row,
            text="",
            font=FONT_UI_S,
            fg=t["fg_faint"],
            bg=t["bg"],
            anchor="e",
        )
        self.token_lbl.pack(side="right")

        self._bind_shortcuts()

    def _autogrow(self, e=None):
        try:
            lines = int(self.input.index("end-1c").split(".")[0])
        except Exception:
            return
        want = max(2, min(lines, 8))
        if int(self.input.cget("height")) != want:
            self.input.configure(height=want)

    def _on_return(self, e):
        self.send()
        return "break"

    def _on_shift_return(self, e):
        if getattr(self, "_input_empty", False):
            self._clear_placeholder()
        self.input.insert("insert", "\n")
        self._autogrow()
        return "break"

    # ---- placeholder ----
    def _clear_placeholder(self):
        if getattr(self, "_input_empty", False):
            self.input.delete("1.0", "end")
            self.input.configure(fg=self.t["fg"])
            self._input_empty = False

    def _show_placeholder(self):
        if self.input.get("1.0", "end").strip() == "":
            self.input.delete("1.0", "end")
            self.input.insert("1.0", self._placeholder)
            self.input.configure(fg=self.t["fg_faint"])
            self._input_empty = True

    def _on_input_focus_in(self, e):
        self._clear_placeholder()

    def _on_input_focus_out(self, e):
        if self.input.get("1.0", "end").strip() == "":
            self._show_placeholder()

    def _get_input_text(self):
        if getattr(self, "_input_empty", False):
            return ""
        return self.input.get("1.0", "end").strip()

    def _bind_shortcuts(self):
        """全局快捷键。"""
        self.root.bind("<Control-n>", lambda e: self.new_chat() or "break")
        self.root.bind("<Control-N>", lambda e: self.new_chat() or "break")
        self.root.bind("<Escape>", lambda e: self._on_escape())
        self.root.bind("<Control-Return>", lambda e: self._on_ctrl_enter())
        self.root.bind("<Control-KeyPress-l>", lambda e: self._on_clear_input())

    def _on_escape(self):
        if self.generating:
            self.stop_gen()
        return "break"

    def _on_ctrl_enter(self):
        self.send()
        return "break"

    def _on_clear_input(self):
        self.input.delete("1.0", "end")
        self.input.configure(height=2)
        self._input_empty = False
        return "break"

    # ============================================================ 启动
    def _boot(self):
        """首次启动：加载模型，恢复上次的对话。"""
        if not self.llama_cli:
            self._show_guide_card(
                "缺少 llama.cpp 运行文件",
                [
                    "程序需要同目录下的 llama\\ 文件夹（llama-cli.exe 和配套 DLL）。",
                    "把 llama.cpp 的 Windows 版解压后放进程序目录即可。",
                ],
                [
                    ("打开程序目录", lambda: self._open_folder(self.base), False),
                    ("重新检测", self._rescan_and_boot, True),
                ],
            )
            return
        if not self.models:
            self._show_guide_card(
                "还没有模型文件",
                [
                    "程序目录下的 model\\ 里需要放 .gguf 模型文件。",
                    "推荐 Qwen3-0.6B（约 640MB，轻快）或 Qwen3-1.7B（约 1.8GB，更聪明）。",
                ],
                [
                    ("打开 model 文件夹", lambda: self._open_folder(self._model_dir()), False),
                    ("导入模型文件夹", self.import_model_folder, True),
                ],
            )
            return

        saved = self.cfg.get("model")
        paths = [m["path"] for m in self.models]
        self._model_paths = paths

        # 顶部下拉框显示模型名
        labels = [m["label"] for m in self.models]
        self.model_box["values"] = labels
        idx = 0
        if saved and saved in paths:
            idx = paths.index(saved)
        self.model_box.current(idx)
        self._current_model = paths[idx]

        self._start_session(then=self._restore_last_chat)

    def _rescan_and_boot(self):
        """重新扫描 llama.cpp 和模型，再走一遍启动流程。"""
        self.llama_cli = find_llama_cli()
        self.models = find_all_models(extra_dirs=self.cfg.get("model_dirs") or [])
        self._boot()

    def _open_folder(self, path):
        try:
            os.makedirs(path, exist_ok=True)
        except Exception:
            pass
        try:
            os.startfile(path)
        except Exception as e:
            messagebox.showwarning(APP_TITLE, "打不开文件夹：\n%s" % e)

    def _model_dir(self):
        return os.path.join(self.base, "model")

    def open_about(self):
        AboutDialog(self)

    def _load_model_info(self):
        self._model_meta = {}

    def _on_model_change(self, e=None):
        idx = self.model_box.current()
        if idx < 0 or idx >= len(self._model_paths):
            return
        path = self._model_paths[idx]
        if path == getattr(self, "_current_model", None):
            return
        self._current_model = path
        # 单文件版内置的模型在临时解包目录里，路径每次都变，别存进配置
        self.cfg.set("model", "" if self._is_bundled_model(path) else path)
        self._start_session()

    def _is_bundled_model(self, path):
        try:
            from .assets import bundle_dir

            bundle = os.path.abspath(bundle_dir())
            return os.path.abspath(path).startswith(bundle) and bundle != os.path.abspath(self.base)
        except Exception:
            return False

    # ============================================================ 导入模型
    def import_model_folder(self):
        """选择文件夹导入新模型。"""
        folder = filedialog.askdirectory(
            title="选择包含 .gguf 模型的文件夹",
            initialdir=os.path.expanduser("~"),
            parent=self.root,
        )
        if not folder:
            return
        folder = os.path.abspath(folder)

        # 扫描该文件夹里有没有 gguf
        found = []
        for root, dirs, files in os.walk(folder):
            rel = os.path.relpath(root, folder)
            depth = 0 if rel == "." else rel.count(os.sep) + 1
            if depth > 1:
                dirs[:] = []
            for f in files:
                if f.lower().endswith(".gguf"):
                    found.append(os.path.join(root, f))

        if not found:
            messagebox.showwarning(
                APP_TITLE,
                "这个文件夹里没有找到 .gguf 模型文件。\n\n"
                "GGUF 是 llama.cpp 使用的模型格式（例如 Qwen3-0.6B-Q8_0.gguf）。\n"
                "可以从 ModelScope / HuggingFace 下载，文件名以 .gguf 结尾。",
            )
            return

        # 记到配置里（去重）
        dirs = list(self.cfg.get("model_dirs") or [])
        if folder not in dirs:
            dirs.append(folder)
        self.cfg.set("model_dirs", dirs)

        # 重新扫描模型列表
        self._reload_models(select=folder)

        names = "\n".join("  · " + os.path.basename(p) for p in found[:8])
        more = "" if len(found) <= 8 else "\n  · …（共 %d 个）" % len(found)
        messagebox.showinfo(
            APP_TITLE,
            "已导入 %d 个模型：\n%s%s\n\n"
            "已加入模型下拉框，选择后即可使用。"
            % (len(found), names, more),
        )

    def _reload_models(self, select=None):
        """重新扫描所有模型并刷新下拉框。select=文件夹路径则优先选中该文件夹里的模型。"""
        self.models = find_all_models(extra_dirs=self.cfg.get("model_dirs") or [])
        if not self.models:
            return
        paths = [m["path"] for m in self.models]
        labels = [m["label"] for m in self.models]
        self._model_paths = paths
        self.model_box["values"] = labels

        # 决定选中哪个
        idx = 0
        if select:
            # 选中导入文件夹里最大的那个模型
            for i, p in enumerate(paths):
                if os.path.dirname(p).startswith(select):
                    idx = i
                    break
        self.model_box.current(idx)

    def _remove_model_dir(self, folder):
        """从配置里移除一个导入的文件夹。"""
        dirs = list(self.cfg.get("model_dirs") or [])
        if folder in dirs:
            dirs.remove(folder)
            self.cfg.set("model_dirs", dirs)
        self._reload_models()

    # ============================================================ 会话
    def _start_session(self, then=None):
        """（重新）启动 llama-cli 进程。"""
        if not self.llama_cli or not getattr(self, "_current_model", None):
            return

        ctx = int(self.cfg.get("ctx"))
        native = self._native_ctx(self._current_model)
        if native:
            # 滑块上限跟着模型走，实际值不能超过原生上限
            if ctx > native:
                ctx = native
                self.cfg.set("ctx", ctx, save=False)
                self._var_ctx.set(native)

        if self.session:
            self.session.stop()

        self.session = ChatSession(
            cli=self.llama_cli,
            model=self._current_model,
            ctx=ctx,
            temp=float(self.cfg.get("temp")),
            max_tokens=int(self.cfg.get("max_tokens")),
            threads=int(self.cfg.get("threads") or 0),
            system=self.cfg.get("system"),
            reasoning=bool(self.cfg.get("reasoning")),
        )

        self._set_status("正在加载模型…")
        label = gguf.model_label(self._current_model)
        if not (self.current_chat and self.current_chat.get("messages")):
            self._show_loading_card("%s · 上下文 %d" % (label, ctx))

        def work():
            try:
                self.session.start(timeout=180)
                self.ui_queue.put(("ready", None))
            except LlamaError as e:
                self.ui_queue.put(("error", str(e)))
            except Exception as e:
                self.ui_queue.put(("error", str(e)))

        threading.Thread(target=work, daemon=True).start()
        if then:
            self._pending_after_ready = then
        else:
            self._pending_after_ready = None

    def _native_ctx(self, path):
        if not hasattr(self, "_native_cache"):
            self._native_cache = {}
        if path not in self._native_cache:
            self._native_cache[path] = gguf.native_context(path)
        return self._native_cache[path]

    # ============================================================ 压缩插件
    def _ensure_compressor(self):
        """按当前模型和配置拿到（或重建）压缩器。"""
        from .compressor import ContextCompressor

        if not self.llama_cli or not getattr(self, "_current_model", None):
            return None
        step = int(self.cfg.get("compress_step") or 1024)
        threshold = int(self.cfg.get("compress_threshold") or 2048)
        # 阈值只有 1024 / 2048 / 3072 / 4096 四档，旧配置超出范围就收回来
        threshold = max(step, min(step * 4, threshold))
        now = (
            self._current_model,
            threshold,
            step,
            int(self.cfg.get("compress_keep") or 4),
        )
        if getattr(self, "_compressor_key", None) != now:
            self.compressor = ContextCompressor(
                cli=self.llama_cli,
                model=self._current_model,
                threshold=now[1],
                step=now[2],
                keep_recent=now[3],
            )
            self._compressor_key = now
        return self.compressor

    def _maybe_compress(self, chat):
        """在下一轮提问开始前压缩。返回是否发生了压缩。

        这一步会同步跑一次 tokenize（几十毫秒），
        真要压缩时才开子进程做摘要（几秒），通过 UI 队列反馈。
        """
        if self._skip_compress_once:
            self._skip_compress_once = False
            return False
        if not self.cfg.get("compress_enabled", True):
            return False
        if self._compressing:
            return False
        messages = (chat or {}).get("messages") or []
        if len(messages) < 4:
            return False

        comp = self._ensure_compressor()
        if not comp:
            return False

        try:
            n = comp.count_messages(messages)
        except Exception:
            n = None
        self._token_count = n or 0
        step = int(self.cfg.get("compress_step") or 1024)
        threshold = max(step, min(step * 4, int(self.cfg.get("compress_threshold") or 2048)))
        if n is None or n < threshold:
            return False

        # 需要压缩：开后台线程做摘要，避免卡住界面
        self._compressing = True
        self._set_status("上下文 %d tokens，正在压缩…" % n)
        self.ui_queue.put(("compress_start", None))

        def work():
            try:
                new_msgs, before, after = comp.compress(
                    messages, system=self.cfg.get("system") or ""
                )
                self.ui_queue.put(
                    ("compress_done", (chat, new_msgs, before, after))
                )
            except Exception as e:
                self.ui_queue.put(("compress_failed", str(e)))

        threading.Thread(target=work, daemon=True).start()
        return True

    def _on_ready(self):
        n = self._native_ctx(self._current_model)
        # 上下文滑块上限 = 模型原生上限
        try:
            slider = self._slider_ctx
            if n and n > 1024:
                slider.configure(to=n)
            slider.set(int(self.cfg.get("ctx")) if not n else min(int(self.cfg.get("ctx")), n))
            self._update_param_label("ctx")
        except Exception:
            pass

        label = gguf.model_label(self._current_model)
        ctx = int(self.cfg.get("ctx"))
        native_txt = (" 原生 %d" % n) if n else ""
        self._set_status("%s · 上下文 %d%s" % (label, ctx, native_txt))
        # token 占用走右侧独立标签
        if self.current_chat:
            self._update_token_count(self.current_chat)

        fn = getattr(self, "_pending_after_ready", None)
        self._pending_after_ready = None
        if fn:
            fn()

        # 模型加载期间用户提前输入的问题，现在自动发出去
        if getattr(self, "_pending_question", None) and not self.generating:
            q = self._pending_question
            self._pending_question = None
            self.input.delete("1.0", "end")
            self.input.insert("1.0", q)
            self.send()

    # ============================================================ 对话
    def _restore_last_chat(self):
        chats = self.store.list_chats()
        if chats:
            self._open_chat(chats[0])
        else:
            self.new_chat(initial=True)

    def new_chat(self, initial=False):
        if self.generating:
            return
        chat = self.store.new_chat(model=self._current_model or "")
        self.current_chat = chat
        self._clear_messages()
        self.store.save_chat(chat)
        self._refresh_chat_list()
        if self.session:
            # 新对话要清掉模型上下文
            self._restart_for_context([], None)
        if not initial:
            self.input.focus_set()

    def _open_chat(self, chat):
        if self.generating:
            return
        full = self.store.load_chat(chat["id"]) or chat
        self.current_chat = full
        self._clear_messages()

        for m in full.get("messages") or []:
            self._add_bubble(m.get("role"), m.get("content") or "", msg_obj=m)

        if self.session:
            self._restart_for_context(full.get("messages") or [], None)

        self._refresh_chat_list()
        self._scroll_bottom()

    def _restart_for_context(self, messages, then):
        """重启进程并注入历史，保证上下文和界面一致。"""
        def work():
            try:
                self.session.start(timeout=180)
                if messages:
                    self.session.restore_history(messages)
                self.ui_queue.put(("ready", None))
            except LlamaError as e:
                self.ui_queue.put(("error", str(e)))
            except Exception as e:
                self.ui_queue.put(("error", str(e)))

        self._set_status("正在重建上下文…")
        self._pending_after_ready = then
        threading.Thread(target=work, daemon=True).start()

    def _clear_messages(self):
        self._clear_state_cards()
        for w in self.msg_frame.winfo_children():
            w.destroy()
        self._bubbles = []
        self._show_welcome()

    # ============================================================ 空状态卡片
    def _clear_state_cards(self):
        """清掉欢迎页/加载页这些"临时卡片"，并停掉点点动画。"""
        for attr in ("_welcome", "_state_card"):
            w = getattr(self, attr, None)
            if w is not None:
                try:
                    w.destroy()
                except Exception:
                    pass
                setattr(self, attr, None)
        job = getattr(self, "_dots_job", None)
        if job:
            try:
                self.root.after_cancel(job)
            except Exception:
                pass
            self._dots_job = None

    def _card_frame(self):
        """统一的占位卡片：水平垂直都居中。"""
        self._clear_state_cards()
        t = self.t
        card = tk.Frame(self.msg_frame, bg=t["bg"])
        card.pack(fill="both", expand=True)
        inner = tk.Frame(card, bg=t["bg"])
        inner.pack(expand=True)
        self._state_card = card
        return inner

    def _animate_dots(self):
        if getattr(self, "_state_card", None) is None:
            return
        lbl = getattr(self, "_loading_title", None)
        if lbl is None or not lbl.winfo_exists():
            return
        self._dots = (getattr(self, "_dots", 0) + 1) % 4
        lbl.configure(text="正在加载模型" + "·" * self._dots)

        def tick():
            self._dots_job = None
            self._animate_dots()

        try:
            self._dots_job = self.root.after(420, tick)
        except Exception:
            self._dots_job = None

    def _show_loading_card(self, detail=""):
        t = self.t
        inner = self._card_frame()
        if self.logo_big is not None:
            tk.Label(inner, image=self.logo_big, bg=t["bg"]).pack(pady=(0, 16))
        self._loading_title = tk.Label(
            inner, text="正在加载模型", font=FONT_CARD, fg=t["fg"], bg=t["bg"]
        )
        self._loading_title.pack()
        if detail:
            tk.Label(
                inner,
                text=detail,
                font=FONT_UI,
                fg=t["fg_dim"],
                bg=t["bg"],
                wraplength=560,
                justify="center",
            ).pack(pady=(10, 0))
        tk.Label(
            inner,
            text="模型越大会越慢一点；加载期间可以先打字，就绪后会自动发送",
            font=FONT_UI_S,
            fg=t["fg_faint"],
            bg=t["bg"],
        ).pack(pady=(14, 0))
        self._dots = 0
        self._animate_dots()

    def _show_guide_card(self, title, lines, buttons):
        """缺文件时的引导页：说明 + 一组按钮。buttons = [(文字, 回调, 是否主按钮)]"""
        t = self.t
        inner = self._card_frame()
        if self.logo_big is not None:
            tk.Label(inner, image=self.logo_big, bg=t["bg"]).pack(pady=(0, 14))
        tk.Label(inner, text=title, font=FONT_CARD, fg=t["fg"], bg=t["bg"]).pack()
        body = tk.Frame(inner, bg=t["bg"])
        body.pack(pady=(14, 0))
        for line in lines:
            tk.Label(
                body,
                text=line,
                font=FONT_UI,
                fg=t["fg_dim"],
                bg=t["bg"],
                justify="left",
                anchor="w",
            ).pack(anchor="w", pady=2)
        row = tk.Frame(inner, bg=t["bg"])
        row.pack(pady=(18, 0))
        for text, cmd, primary in buttons:
            ttk.Button(
                row,
                text=text,
                style="Accent.TButton" if primary else "TButton",
                command=cmd,
            ).pack(side="left", padx=6)

    def _show_welcome(self):
        """没有消息时的首页：品牌 + 示例问题。"""
        t = self.t
        inner = self._card_frame()
        self._welcome = getattr(self, "_state_card", None)

        if self.logo_big is not None:
            tk.Label(inner, image=self.logo_big, bg=t["bg"]).pack(pady=(0, 18))

        tk.Label(
            inner, text=APP_NAME, font=FONT_HERO, fg=t["fg"], bg=t["bg"]
        ).pack()
        tk.Label(
            inner, text=TAGLINE, font=FONT_UI, fg=t["fg_dim"], bg=t["bg"]
        ).pack(pady=(8, 0))
        tk.Label(
            inner, text=SUBTITLE, font=FONT_UI_S, fg=t["fg_faint"], bg=t["bg"]
        ).pack(pady=(4, 0))

        chips = tk.Frame(inner, bg=t["bg"])
        chips.pack(pady=(26, 0))
        for i, (label, prompt) in enumerate(SAMPLE_PROMPTS):
            b = ttk.Button(
                chips,
                text=label,
                style="Chip.TButton",
                width=22,
                command=lambda p=prompt: self._use_sample(p),
            )
            b.grid(row=i // 2, column=i % 2, padx=5, pady=5, sticky="ew")
        chips.columnconfigure(0, weight=1)
        chips.columnconfigure(1, weight=1)

        label = gguf.model_label(getattr(self, "_current_model", None))
        model_txt = ("当前模型：%s" % label) if label else ""
        tk.Label(
            inner,
            text=model_txt,
            font=FONT_UI_S,
            fg=t["fg_faint"],
            bg=t["bg"],
        ).pack(pady=(24, 0))

    def _use_sample(self, prompt):
        """点示例问题：填进输入框并定位光标，让用户可以改完再发。"""
        self.input.configure(state="normal")
        self.input.delete("1.0", "end")
        self.input.insert("1.0", prompt)
        self._input_empty = False
        t = self.t
        self.input.configure(fg=t["fg"])
        self.input.focus_set()
        self.input.mark_set("insert", "end")
        self._autogrow()

    def _hide_welcome(self):
        self._clear_state_cards()

    def _add_bubble(self, role, text, msg_obj=None):
        self._hide_welcome()
        text = clean_text(text or "")

        # 删除回调：从当前对话里摘掉这条消息
        on_delete = None
        if msg_obj is not None and self.current_chat is not None:
            def make_delete(m=msg_obj):
                def _del():
                    self._delete_message(m)
                return _del
            on_delete = make_delete()

        b = Bubble(
            self.msg_frame, role, text, self.dark, on_delete=on_delete,
            max_px=self._bubble_max_px(),
        )
        b.pack(fill="x", padx=22, pady=(10, 2))
        if not hasattr(self, "_bubbles"):
            self._bubbles = []
        self._bubbles.append(b)
        return b

    def _bubble_max_px(self):
        """气泡最宽占聊天区的多少像素（留出头像和边距）。"""
        try:
            w = self.chat_canvas.winfo_width()
        except Exception:
            w = 0
        if w < 200:
            w = 840
        return int(w * 0.72)

    def _delete_message(self, msg_obj):
        """删除一条消息，同步更新对话记录和界面。"""
        chat = self.current_chat
        if not chat:
            return
        msgs = chat.get("messages") or []
        if msg_obj not in msgs:
            return
        if not messagebox.askyesno(APP_TITLE, "删除这条消息？"):
            return
        msgs.remove(msg_obj)
        self.store.save_chat(chat)
        # 重建整个消息区（消息少，代价可接受）
        self._clear_messages()
        for m in msgs:
            self._add_bubble(m.get("role"), m.get("content") or "", msg_obj=m)
        self._refresh_chat_list()
        self._scroll_bottom()

    # ============================================================ 发送
    def send(self):
        if self.generating:
            return
        text = self._get_input_text()
        if not text:
            return
        if not self.session or not self.session.alive:
            # 模型还在加载：把问题留在输入框里，等就绪后自动发
            self._pending_question = text
            self._set_status("模型加载中，问题已排队，就绪后自动发送…")
            return

        self.input.delete("1.0", "end")
        self.input.configure(height=2)
        self._input_empty = False

        chat = self.current_chat or self.store.new_chat()
        self.current_chat = chat

        # 在下一轮开始前判断是否需要压缩。
        # 若触发，本轮先不发送，等压缩完成后由 _on_compress_done 重启会话再发。
        if self._maybe_compress(chat):
            self._pending_question = text
            return

        user_msg = {"role": "user", "content": text}
        self._add_bubble("user", text, msg_obj=user_msg)
        chat.setdefault("messages", []).append(user_msg)
        if chat.get("title") in ("", "新对话", None):
            chat["title"] = self.store.auto_title(chat["messages"])
        chat["model"] = self._current_model or ""
        self.store.save_chat(chat)
        self._refresh_chat_list()

        bot = self._add_bubble("assistant", "")
        bot.set_meta("正在输入…")
        self._scroll_bottom()

        self.generating = True
        self.stop_flag.clear()
        self._stopped_manually = False
        self._set_action(stopping=True)
        self._set_status("生成中…")

        started = time.time()
        first = [None]
        acc = [""]
        last_tick = [0]

        def on_token(chunk):
            if first[0] is None:
                first[0] = time.time()
            acc[0] += chunk
            # 每 0.3 秒刷一次 meta，避免过于频繁
            now = time.time()
            if now - last_tick[0] >= 0.3:
                last_tick[0] = now
                n = len(acc[0])
                el = now - started
                rate = n / el if el > 0 else 0
                self.ui_queue.put(("progress", (bot, n, el, rate)))
            self.ui_queue.put(("token", (bot, chunk)))

        def work():
            try:
                self.session.ask(text, on_token, timeout=1800)
                self.ui_queue.put(("done", (bot, started, first[0], acc[0])))
            except Exception as e:
                self.ui_queue.put(("failed", (bot, str(e))))

        threading.Thread(target=work, daemon=True).start()

    def _set_action(self, stopping):
        """同一个按钮在"发送"和"停止"之间切换。"""
        if not hasattr(self, "action_btn"):
            return
        if stopping:
            self.action_btn.configure(text="停止 ■", style="TButton")
        else:
            self.action_btn.configure(text="发送 ↑", style="Accent.TButton")
        self.action_btn.state(["!disabled"])

    def _on_action(self):
        if self.generating or self._compressing:
            self.stop_gen()
        else:
            self.send()

    def stop_gen(self):
        if not self.generating:
            return
        self.stop_flag.set()
        self._stopped_manually = True
        if self.session and self.session.chat:
            try:
                self.session.chat.stop_event.set()
            except Exception:
                pass
        self._set_status("已停止")

    def _on_done(self, bot, started, first, text):
        self.generating = False
        self._set_action(stopping=False)

        text = clean_text(text)
        elapsed = time.time() - started
        n = len(text)
        if getattr(self, "_stopped_manually", False):
            bot.set_meta("已停止")
        else:
            bot.set_meta("%d 字" % n)
        bot.finalize_height()

        chat = self.current_chat
        if chat is not None:
            asst_msg = {"role": "assistant", "content": text}
            chat.setdefault("messages", []).append(asst_msg)
            self.store.save_chat(chat)
            self._refresh_chat_list()

        label = gguf.model_label(self._current_model)
        self._update_token_count(chat)
        self._set_status("%s · 就绪" % label)
        self._scroll_bottom()

    def _update_token_count(self, chat=None):
        """数一下当前对话的 token，显示在右侧 token 标签。"""
        if not self.cfg.get("compress_enabled", True):
            self._set_token_display("")
            return ""
        chat = chat if chat is not None else self.current_chat
        if not chat:
            self._set_token_display("")
            return ""
        comp = self._ensure_compressor()
        if not comp:
            self._set_token_display("")
            return ""
        try:
            n = comp.count_messages(chat.get("messages") or [])
        except Exception:
            return ""
        if n is None:
            return ""
        self._token_count = n
        th = int(self.cfg.get("compress_threshold") or 2048)
        pct = int(n * 100 / th) if th else 0
        self._set_token_display("上下文 %d/%d tokens (%d%%)" % (n, th, pct))
        return " · 上下文 %d/%d tokens (%d%%)" % (n, th, pct)

    def _on_failed(self, bot, err):
        self.generating = False
        self._set_action(stopping=False)
        bot.set_text("（出错了）" + err)
        self._set_status("出错")

    # ------------------------------------------------------------ 压缩回调
    def _on_compress_done(self, chat, new_msgs, before, after):
        """压缩完成：写回对话、重建上下文、补发刚才那一问。"""
        self._compressing = False
        question = getattr(self, "_pending_question", None)
        self._pending_question = None

        if chat is not None:
            chat["messages"] = new_msgs
            self.current_chat = chat
            self.store.save_chat(chat)

            # 界面：把旧气泡换成一条压缩标记 + 摘要
            self._clear_messages()
            mark = self._add_bubble(
                "assistant",
                "〔上下文已压缩〕%d → %d tokens，保留最近 %d 轮原话。\n\n%s"
                % (
                    before,
                    after,
                    getattr(self.compressor, "kept_rounds", int(self.cfg.get("compress_keep") or 4)),
                    (new_msgs[0].get("content") or "").replace(
                        "（以下是之前对话的摘要）\n", ""
                    ),
                ),
            )
            mark.set_meta("压缩完成")
            for m in new_msgs[2:]:
                self._add_bubble(m.get("role"), m.get("content") or "")
            self._refresh_chat_list()

        self._set_action(stopping=False)
        label = gguf.model_label(self._current_model)
        self._set_status("上下文已压缩 %d → %d tokens" % (before, after))

        if question:
            # 用新上下文重启进程，注入摘要，然后自动补发问题
            def then():
                self._skip_compress_once = True
                self.input.delete("1.0", "end")
                self.input.insert("1.0", question)
                self.send()

            self._restart_for_context(new_msgs, then)
        else:
            self._scroll_bottom()

    def _on_compress_failed(self, err):
        self._compressing = False
        question = getattr(self, "_pending_question", None)
        self._pending_question = None
        self._set_action(stopping=False)
        self._set_status("压缩失败：" + str(err)[:60])
        if question:
            self.input.delete("1.0", "end")
            self.input.insert("1.0", question)

    # ============================================================ 队列
    def _pump(self):
        try:
            while True:
                kind, payload = self.ui_queue.get_nowait()
                if kind == "token":
                    bot, chunk = payload
                    bot.append(chunk)
                    self._scroll_bottom_if_near()
                elif kind == "progress":
                    bot, n, el, rate = payload
                    bot.set_meta("%d 字" % n)
                elif kind == "ready":
                    self._on_ready()
                elif kind == "error":
                    self._set_status("加载失败")
                    messagebox.showerror(APP_TITLE, str(payload))
                elif kind == "done":
                    self._on_done(*payload)
                elif kind == "failed":
                    self._on_failed(*payload)
                elif kind == "compress_start":
                    # 压缩期间禁用按钮：停止只能中断生成，中断不了压缩
                    self.action_btn.configure(text="压缩中…", style="TButton")
                    self.action_btn.state(["disabled"])
                elif kind == "compress_done":
                    self._on_compress_done(*payload)
                elif kind == "compress_failed":
                    self._on_compress_failed(payload)
        except queue.Empty:
            pass
        self.root.after(40, self._pump)

    # ============================================================ 滚动
    def _scroll_bottom(self):
        self.root.update_idletasks()
        self.chat_canvas.yview_moveto(1.0)
        self._update_scroll_hint()

    def _scroll_bottom_if_near(self):
        """智能滚动：只有用户本来就在底部附近才自动滚，上翻时不打扰。"""
        try:
            lo, hi = self.chat_canvas.yview()
            if hi >= 0.92:
                self.chat_canvas.yview_moveto(1.0)
                self._update_scroll_hint()
            else:
                # 用户在上翻：显示"回到底部"提示
                self._show_scroll_hint(True)
        except Exception:
            pass

    def _update_scroll_hint(self):
        self._show_scroll_hint(False)

    def _show_scroll_hint(self, show):
        try:
            lo, hi = self.chat_canvas.yview()
            at_bottom = hi >= 0.98
        except Exception:
            at_bottom = True
        should_show = show and not at_bottom
        btn = getattr(self, "_scroll_btn", None)
        if should_show:
            if btn is None:
                btn = tk.Button(
                    self.chat_canvas,
                    text="↓ 回到底部",
                    font=FONT_UI_S,
                    command=self._scroll_bottom,
                    bg=self.t["bg_active"],
                    fg=self.t["fg"],
                    activebackground=self.t["bg_hover"],
                    activeforeground=self.t["fg"],
                    bd=0,
                    highlightthickness=0,
                    padx=10,
                    pady=4,
                    cursor="hand2",
                )
                self._scroll_btn = btn
                self._scroll_win = self.chat_canvas.create_window(
                    (10, 10), window=btn, anchor="se"
                )
            self._place_scroll_btn()
        else:
            if btn is not None:
                try:
                    btn.destroy()
                except Exception:
                    pass
                self._scroll_btn = None

    def _place_scroll_btn(self):
        try:
            w = self.chat_canvas.winfo_width()
            self.chat_canvas.coords(self._scroll_win, w - 16, 16)
        except Exception:
            pass

    # ============================================================ 侧栏
    def _refresh_chat_list(self):
        t = self.t
        for w in self.chat_list.winfo_children():
            w.destroy()

        chats = self.store.list_chats()
        cur_id = (self.current_chat or {}).get("id")

        for c in chats:
            active = c["id"] == cur_id
            bg = t["bg_active"] if active else t["bg_alt"]
            row = tk.Frame(self.chat_list, bg=bg, cursor="hand2")
            row.pack(fill="x", pady=1, padx=2)

            inner = tk.Frame(row, bg=bg)
            inner.pack(fill="x", padx=8, pady=6)

            title = c["title"] or "未命名"
            lbl = tk.Label(
                inner,
                text=title,
                font=FONT_UI_S,
                fg=t["fg"] if active else t["fg_dim"],
                bg=bg,
                anchor="w",
                justify="left",
                wraplength=150,
            )
            lbl.pack(side="left", fill="x", expand=True)

            del_btn = tk.Label(
                inner, text="×", font=("Microsoft YaHei UI", 11), fg=t["fg_faint"], bg=bg, cursor="hand2"
            )
            del_btn.pack(side="right", padx=(4, 0))

            def on_enter(e, r=row, i=inner, l=lbl, d=del_btn, b=bg):
                if not active:
                    r.configure(bg=t["bg_hover"])
                    i.configure(bg=t["bg_hover"])
                    l.configure(bg=t["bg_hover"])
                    d.configure(bg=t["bg_hover"])

            def on_leave(e, r=row, i=inner, l=lbl, d=del_btn, b=bg):
                r.configure(bg=b)
                i.configure(bg=b)
                l.configure(bg=b)
                d.configure(bg=b)

            for w in (row, inner, lbl):
                w.bind("<Enter>", on_enter)
                w.bind("<Leave>", on_leave)
                w.bind("<Button-1>", lambda e, c=c: self._open_chat(c))
                w.bind("<Button-3>", lambda e, c=c: self._chat_menu(e, c))

            del_btn.bind("<Button-1>", lambda e, c=c: self._delete_chat(c))
            del_btn.bind("<Enter>", lambda e, d=del_btn: d.configure(fg=t["danger"]))
            del_btn.bind("<Leave>", lambda e, d=del_btn: d.configure(fg=t["fg_faint"]))

    def _chat_menu(self, event, chat):
        """侧栏对话的右键菜单。"""
        t = self.t
        menu = tk.Menu(self.root, tearoff=0)
        menu.add_command(
            label="重命名", command=lambda: self._rename_chat(chat)
        )
        menu.add_command(
            label="删除", command=lambda: self._delete_chat(chat)
        )
        try:
            menu.tk_popup(event.x_root, event.y_root)
        finally:
            menu.grab_release()

    def _rename_chat(self, chat):
        """弹出对话框重命名对话。"""
        cur = chat.get("title") or "未命名"
        new = simpledialog.askstring(
            "重命名对话", "新名称：", initialvalue=cur, parent=self.root
        )
        if not new or not new.strip():
            return
        chat["title"] = new.strip()
        self.store.save_chat(chat)
        self._refresh_chat_list()

    def _delete_chat(self, chat):
        title = chat.get("title") or "这条对话"
        if not messagebox.askyesno(APP_TITLE, "删除「%s」？" % title):
            return
        self.store.delete_chat(chat["id"])
        if self.current_chat and self.current_chat.get("id") == chat["id"]:
            self.current_chat = None
            self._clear_messages()
        self._refresh_chat_list()

    # ============================================================ 主题
    def _theme_btn_label(self):
        """显示当前主题 + 目标，如 '🌙 深色'（当前深色，点击切浅色）。"""
        if self.dark:
            return "深色"
        return "浅色"

    def toggle_theme(self):
        self.dark = not self.dark
        self.cfg.set("dark", self.dark)
        self._apply_theme()

    def _apply_theme(self):
        """主题切换：增量重绘所有控件，不整窗销毁（避免闪屏和丢失输入焦点）。"""
        self.t = theme(self.dark)
        self.root.configure(bg=self.t["bg"])

        # ttk 控件（按钮、下拉框、滚动条）的颜色来自 style，必须重配一次
        try:
            self._build_style()
        except Exception:
            pass

        # 递归重绘标准控件
        self._restyle(self.root)

        # 气泡有独立的换色逻辑
        for b in getattr(self, "_bubbles", []):
            try:
                b.restyle(self.dark)
            except Exception:
                pass

        try:
            self.theme_btn.configure(text=self._theme_btn_label())
        except Exception:
            pass

        # 侧栏列表重新生成（颜色跟随主题）
        self._refresh_chat_list()
        self._scroll_bottom()

    def _restyle(self, widget):
        """递归给 tk 控件上色。"""
        t = self.t
        wcls = widget.winfo_class()

        try:
            zone = getattr(widget, "_zone", None)
            if wcls in ("Tk", "Frame"):
                if zone == "top" or zone == "side":
                    widget.configure(bg=t["bg_alt"])
                else:
                    widget.configure(bg=t["bg"])
            elif wcls == "Label":
                widget.configure(bg=t["bg_alt"] if zone in ("top", "side") else t["bg"], fg=t["fg"])
            elif wcls == "Checkbutton":
                widget.configure(
                    bg=t["bg_alt"] if zone == "top" else t["bg"],
                    activebackground=t["bg_alt"] if zone == "top" else t["bg"],
                    selectcolor=t["bg_input"],
                    fg=t["fg_dim"],
                )
            elif wcls == "Text":
                widget.configure(bg=t["bg_input"], fg=t["fg"])
            elif wcls == "Canvas":
                widget.configure(bg=t["bg_alt"] if zone == "side" else t["bg"])
            elif wcls == "Scale":
                widget.configure(
                    bg=t["bg_alt"] if zone == "top" else t["bg"],
                    fg=t["fg"],
                    troughcolor=t["bg_input"],
                    activebackground=t["accent"],
                )
        except Exception:
            pass

        for child in widget.winfo_children():
            self._restyle(child)

    # ============================================================ 设置
    def open_settings(self):
        SettingsDialog(self)

    # ============================================================ 状态
    def _set_status(self, text):
        try:
            self.status_lbl.configure(text=text)
        except Exception:
            pass

    def _set_token_display(self, text):
        try:
            self.token_lbl.configure(text=text)
        except Exception:
            pass

    # ============================================================ 关闭
    def on_close(self):
        try:
            w, h = self.root.winfo_width(), self.root.winfo_height()
            self.cfg.set("window", {"w": w, "h": h}, save=False)
            self.cfg.save()
        except Exception:
            pass
        # 参数也存一次
        try:
            for key in ("temp", "ctx", "max_tokens"):
                self.cfg.set(key, getattr(self, "_var_" + key).get(), save=False)
            self.cfg.save()
        except Exception:
            pass
        if self.session:
            self.session.stop()
        self.root.destroy()


class AboutDialog(tk.Toplevel):
    """关于：版本、当前模型、许可说明。"""

    def __init__(self, app):
        super().__init__(app.root)
        self.app = app
        t = app.t
        self.t = t
        self.title("关于 %s" % APP_NAME)
        self.configure(bg=t["bg"])
        self.resizable(False, False)
        self.transient(app.root)
        self.grab_set()

        pad = 26
        head = tk.Frame(self, bg=t["bg"])
        head.pack(fill="x", padx=pad, pady=(pad, 0))
        if getattr(app, "logo_img", None) is not None:
            tk.Label(head, image=app.logo_img, bg=t["bg"]).pack(side="left", padx=(0, 14))

        col = tk.Frame(head, bg=t["bg"])
        col.pack(side="left")
        tk.Label(
            col, text="%s %s" % (APP_NAME, VERSION), font=FONT_CARD, fg=t["fg"], bg=t["bg"]
        ).pack(anchor="w")
        tk.Label(
            col, text=TAGLINE, font=FONT_UI, fg=t["fg_dim"], bg=t["bg"]
        ).pack(anchor="w", pady=(4, 0))
        tk.Label(
            col, text="构建 %s" % BUILD, font=FONT_UI_S, fg=t["fg_faint"], bg=t["bg"]
        ).pack(anchor="w")

        # 信息表
        info = tk.Frame(self, bg=t["bg"])
        info.pack(fill="x", padx=pad, pady=(20, 0))

        model = gguf.model_label(getattr(app, "_current_model", None)) or "未加载"
        arch = gguf.architecture(getattr(app, "_current_model", None)) or "—"
        native = gguf.native_context(getattr(app, "_current_model", None)) or 0
        rows = [
            ("当前模型", model),
            ("模型架构", arch),
            ("原生上下文", ("%d tokens" % native) if native else "该模型未声明"),
            ("当前上下文", "%s tokens" % int(app.cfg.get("ctx") or 0)),
            ("回复上限", "%s tokens" % int(app.cfg.get("max_tokens") or 0)),
            ("llama.cpp", os.path.basename(app.llama_cli or "未找到")),
            ("数据目录", app.base),
        ]
        for k, v in rows:
            row = tk.Frame(info, bg=t["bg"])
            row.pack(fill="x", pady=3)
            tk.Label(
                row, text=k, font=FONT_UI_S, fg=t["fg_faint"], bg=t["bg"], width=9, anchor="w"
            ).pack(side="left")
            tk.Label(
                row, text=v, font=FONT_UI_S, fg=t["fg"], bg=t["bg"], anchor="w",
                justify="left", wraplength=380,
            ).pack(side="left", fill="x", expand=True)

        tk.Frame(self, bg=t["line"], height=1).pack(fill="x", padx=pad, pady=(16, 0))

        note = (
            "本程序是自由软件，以 GNU 通用公共许可证第 3 版（GPLv3）发布："
            "可以自由使用、修改、再分发，且不提供任何担保。\n"
            "运行库 llama.cpp 使用 MIT 许可；模型文件由各自发布方授权（Qwen 系列为 Apache-2.0），"
            "本程序不附带模型。\n"
            "所有推理都在本机完成：没有账号、没有网络请求，对话只存在程序目录里。"
        )
        tk.Label(
            self, text=note, font=FONT_UI_S, fg=t["fg_dim"], bg=t["bg"],
            justify="left", anchor="w", wraplength=470,
        ).pack(fill="x", padx=pad, pady=(12, 0))

        btns = tk.Frame(self, bg=t["bg"])
        btns.pack(fill="x", padx=pad, pady=(20, pad))
        ttk.Button(
            btns, text="查看许可", style="Ghost.TButton", command=self._show_license
        ).pack(side="left")
        ttk.Button(
            btns, text="打开数据目录", style="Ghost.TButton",
            command=lambda: app._open_folder(app.base),
        ).pack(side="left", padx=8)
        ttk.Button(
            btns, text="复制信息", style="Ghost.TButton", command=self._copy
        ).pack(side="left", padx=8)
        ttk.Button(
            btns, text="关闭", style="Accent.TButton", command=self.destroy
        ).pack(side="right")

        self.update_idletasks()
        w = max(520, self.winfo_reqwidth())
        h = self.winfo_reqheight()
        x = app.root.winfo_x() + (app.root.winfo_width() - w) // 2
        y = app.root.winfo_y() + (app.root.winfo_height() - h) // 2
        self.geometry("%dx%d+%d+%d" % (w, h, max(0, x), max(0, y)))
        self._info_text = "\n".join("%s：%s" % (k, v) for k, v in rows)

    def _copy(self):
        try:
            self.clipboard_clear()
            self.clipboard_append(
                "%s %s\n%s\n%s\n%s"
                % (APP_NAME, VERSION, TAGLINE, self._info_text, "-" * 30)
            )
        except Exception:
            pass

    def _show_license(self):
        """打开程序目录里的 LICENSE（GPLv3 全文）。"""
        path = os.path.join(self.app.base, "LICENSE")
        if not os.path.isfile(path):
            messagebox.showinfo(
                APP_TITLE,
                "本程序以 GNU GPL v3 发布。\n"
                "完整条款见项目主页的 LICENSE 文件：\n"
                "https://www.gnu.org/licenses/gpl-3.0.txt",
            )
            return
        try:
            os.startfile(path)
        except Exception as e:
            messagebox.showwarning(APP_TITLE, "打不开 LICENSE：%s" % e)


class SettingsDialog(tk.Toplevel):
    """设置：系统提示词、线程数、默认参数。"""

    def __init__(self, app):
        super().__init__(app.root)
        self.app = app
        t = app.t
        self.t = t

        self.title("设置")
        self.configure(bg=t["bg"])
        self.geometry("620x680")
        self.resizable(False, False)
        self.transient(app.root)
        self.grab_set()

        pad = 18

        tk.Label(
            self, text="系统提示词", font=FONT_TITLE, fg=t["fg"], bg=t["bg"]
        ).pack(anchor="w", padx=pad, pady=(pad, 4))
        tk.Label(
            self,
            text="每次启动模型时作为人设/规则注入。改了之后点保存会重启模型。",
            font=FONT_UI_S,
            fg=t["fg_dim"],
            bg=t["bg"],
        ).pack(anchor="w", padx=pad, pady=(0, 8))

        self.sys_text = tk.Text(
            self,
            height=7,
            wrap="word",
            font=FONT_CHAT,
            bg=t["bg_input"],
            fg=t["fg"],
            insertbackground=t["accent"],
            bd=0,
            padx=10,
            pady=8,
            highlightthickness=0,
        )
        self.sys_text.pack(fill="x", padx=pad)
        self.sys_text.insert("1.0", app.cfg.get("system") or "")

        # 线程
        row = tk.Frame(self, bg=t["bg"])
        row.pack(fill="x", padx=pad, pady=(14, 0))
        tk.Label(row, text="CPU 线程", font=FONT_UI, fg=t["fg"], bg=t["bg"]).pack(side="left")

        self.thread_var = tk.StringVar(
            value=str(app.cfg.get("threads") or os.cpu_count() or 4)
        )
        sp = tk.Spinbox(
            row,
            from_=1,
            to=os.cpu_count() or 8,
            textvariable=self.thread_var,
            width=5,
            font=FONT_UI_S,
            bg=t["bg_input"],
            fg=t["fg"],
            bd=0,
            highlightthickness=0,
        )
        sp.pack(side="left", padx=(10, 6))
        tk.Label(
            row,
            text="（本机 %d 核）" % (os.cpu_count() or 0),
            font=FONT_UI_S,
            fg=t["fg_faint"],
            bg=t["bg"],
        ).pack(side="left")

        # ---- 上下文压缩 ----
        sep = tk.Frame(self, bg=t["line"], height=1)
        sep.pack(fill="x", padx=pad, pady=(16, 12))

        tk.Label(
            self, text="上下文压缩", font=FONT_TITLE, fg=t["fg"], bg=t["bg"]
        ).pack(anchor="w", padx=pad)

        tk.Label(
            self,
            text="对话达到阈值后，在下一轮提问前自动把旧历史压成摘要。\n"
                 "压缩会临时开一个模型进程做总结，需要几秒。",
            font=FONT_UI_S,
            fg=t["fg_dim"],
            bg=t["bg"],
            justify="left",
        ).pack(anchor="w", padx=pad, pady=(4, 6))

        crow = tk.Frame(self, bg=t["bg"])
        crow.pack(fill="x", padx=pad)

        self.compress_var = tk.BooleanVar(value=bool(app.cfg.get("compress_enabled", True)))
        tk.Checkbutton(
            crow,
            text="启用自动压缩",
            variable=self.compress_var,
            font=FONT_UI_S,
            fg=t["fg"],
            bg=t["bg"],
            selectcolor=t["bg_input"],
            activebackground=t["bg"],
            bd=0,
            highlightthickness=0,
        ).pack(side="left")

        # 阈值滑块：1024 tokens 一档，可选 1024 / 2048 / 3072 / 4096
        thresh = tk.Frame(self, bg=t["bg"])
        thresh.pack(fill="x", padx=pad, pady=(8, 0))
        tk.Label(
            thresh, text="触发阈值", font=FONT_UI_S, fg=t["fg_dim"], bg=t["bg"]
        ).pack(side="left")

        step = int(app.cfg.get("compress_step") or 1024)
        cur = int(app.cfg.get("compress_threshold") or 2048)
        cur = max(step, min(step * 4, cur))
        self.thresh_var = tk.IntVar(value=cur)
        self.thresh_lbl = tk.Label(
            thresh, text=str(self.thresh_var.get()), font=FONT_UI_S,
            fg=t["accent"], bg=t["bg"], width=7
        )
        self.thresh_lbl.pack(side="right")

        tslider = tk.Scale(
            self,
            from_=step,
            to=step * 4,
            resolution=step,
            orient="horizontal",
            variable=self.thresh_var,
            showvalue=False,
            length=490,
            width=8,
            bg=t["bg"],
            fg=t["fg"],
            troughcolor=t["bg_input"],
            activebackground=t["accent"],
            highlightthickness=0,
            bd=0,
            sliderrelief="flat",
            command=lambda v: self.thresh_lbl.configure(text=str(int(float(v)))),
        )
        tslider.pack(padx=pad, pady=(2, 0))
        tk.Label(
            self,
            text="1024 tokens 一档，可选 1024 / 2048 / 3072 / 4096（默认 2048）",
            font=FONT_UI_S,
            fg=t["fg_faint"],
            bg=t["bg"],
        ).pack(anchor="w", padx=pad)

        # 保留最近几轮
        keeprow = tk.Frame(self, bg=t["bg"])
        keeprow.pack(fill="x", padx=pad, pady=(10, 0))
        tk.Label(
            keeprow, text="保留最近", font=FONT_UI_S, fg=t["fg_dim"], bg=t["bg"]
        ).pack(side="left")
        self.keep_var = tk.StringVar(value=str(app.cfg.get("compress_keep") or 4))
        keep_sp = tk.Spinbox(
            keeprow,
            from_=0,
            to=20,
            textvariable=self.keep_var,
            width=5,
            font=FONT_UI_S,
            bg=t["bg_input"],
            fg=t["fg"],
            bd=0,
            highlightthickness=0,
        )
        keep_sp.pack(side="left", padx=(8, 6))
        tk.Label(
            keeprow,
            text="轮原话（压缩时自动调整以保证降到阈值以下）",
            font=FONT_UI_S,
            fg=t["fg_faint"],
            bg=t["bg"],
        ).pack(side="left")

        # ---- 已导入的模型文件夹 ----
        dirs = app.cfg.get("model_dirs") or []
        if dirs:
            sep2 = tk.Frame(self, bg=t["line"], height=1)
            sep2.pack(fill="x", padx=pad, pady=(16, 10))
            tk.Label(
                self, text="已导入的模型文件夹", font=FONT_TITLE, fg=t["fg"], bg=t["bg"]
            ).pack(anchor="w", padx=pad)

            for d in dirs:
                drow = tk.Frame(self, bg=t["bg"])
                drow.pack(fill="x", padx=pad, pady=2)
                tk.Label(
                    drow, text=d, font=FONT_UI_S, fg=t["fg_dim"], bg=t["bg"],
                    anchor="w",
                ).pack(side="left", fill="x", expand=True)
                rm = tk.Label(
                    drow, text="移除", font=FONT_UI_S, fg=t["danger"], bg=t["bg"],
                    cursor="hand2",
                )
                rm.pack(side="right")
                rm.bind("<Button-1>", lambda e, f=d: self._rm_dir(f))

        # 说明
        info = tk.Frame(self, bg=t["bg"])
        info.pack(fill="x", padx=pad, pady=(14, 0))
        native = app._native_ctx(app._current_model) if hasattr(app, "_current_model") else None
        lines = [
            "模型      " + (gguf.model_label(app._current_model) if hasattr(app, "_current_model") else "-"),
            "原生上下文 " + (("%d tokens" % native) if native else "未知"),
            "配置文件   " + app.cfg.path,
            "对话目录   " + app.store.dir,
        ]
        for ln in lines:
            tk.Label(
                info, text=ln, font=FONT_UI_S, fg=t["fg_dim"], bg=t["bg"], anchor="w"
            ).pack(fill="x")

        # 按钮
        btns = tk.Frame(self, bg=t["bg"])
        btns.pack(side="bottom", fill="x", padx=pad, pady=pad)

        ttk.Button(btns, text="取消", width=8, command=self.destroy).pack(side="right")
        ttk.Button(
            btns, text="保存", width=8, style="Accent.TButton", command=self.save
        ).pack(side="right", padx=(0, 8))

    def _rm_dir(self, folder):
        """移除一个导入的模型文件夹，并原地刷新列表。"""
        app = self.app
        app._remove_model_dir(folder)
        # 关掉当前设置窗口再重开，反映最新目录列表
        try:
            self.grab_release()
        except Exception:
            pass
        self.destroy()
        app.open_settings()

    def save(self):
        app = self.app
        text = self.sys_text.get("1.0", "end").strip()
        old_sys = app.cfg.get("system") or ""
        try:
            threads = int(self.thread_var.get())
        except ValueError:
            threads = os.cpu_count() or 4

        app.cfg.set("system", text, save=False)
        app.cfg.set("threads", threads, save=False)
        app.cfg.set("compress_enabled", bool(self.compress_var.get()), save=False)
        step = int(app.cfg.get("compress_step") or 1024)
        th = max(step, min(step * 4, int(self.thresh_var.get())))
        app.cfg.set("compress_threshold", th, save=False)
        app.cfg.set("compress_step", step, save=False)
        try:
            app.cfg.set("compress_keep", int(self.keep_var.get()), save=False)
        except ValueError:
            pass
        app.cfg.save()

        # 压缩器参数变了就重建
        app._compressor_key = None

        self.destroy()

        changed = (text != old_sys) or (threads != (app.cfg.get("threads") or 0))
        if text != old_sys:
            # 系统提示词影响启动参数，必须重启模型
            if app.session:
                app.session.system = text
                app.session.threads = threads
            app._restart_for_context(
                (app.current_chat or {}).get("messages") or [], None
            )
        elif app.session:
            app.session.threads = threads

# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""对话会话：把 engine 的流式回调接到界面，并管理历史重建。

一个 ChatSession 对应 llama-cli 的一个进程。
切换对话时，用 /read 把旧消息重新喂进去，这样模型就能接着之前的话题聊。
"""

import os
import tempfile
import threading
import time

from .engine import LlamaChat, LlamaError, clean_text


class ChatSession:
    """一次 llama-cli 进程 + 它承载的对话。"""

    def __init__(self, cli, model, ctx, temp, max_tokens, threads, system, reasoning=False):
        self.cli = cli
        self.model = model
        self.ctx = ctx
        self.temp = temp
        self.max_tokens = max_tokens
        self.threads = threads
        self.system = system
        self.reasoning = reasoning
        self.chat = None
        self._lock = threading.RLock()
        self._tmp_files = []

    # ------------------------------------------------------------ 起
    def start(self, timeout=180):
        self.stop()
        self.chat = LlamaChat(
            cli_path=self.cli,
            model_path=self.model,
            ctx_size=self.ctx,
            temperature=self.temp,
            max_new_tokens=self.max_tokens,
            threads=self.threads or None,
            reasoning=self.reasoning,
            system_prompt=self.system or None,
        )
        self.chat.start(timeout=timeout)

    def stop(self):
        if self.chat:
            try:
                self.chat.stop()
            except Exception:
                pass
            self.chat = None
        self._cleanup_tmp()

    @property
    def alive(self):
        return bool(self.chat is not None and self.chat.can_ask)

    # ------------------------------------------------------------ 重建历史
    def restore_history(self, messages):
        """把已有消息通过 /read 注入模型上下文。

        llama-cli 的 /read 读的是纯文本，直接塞进去会被当成新的用户输入。
        但实测能延续话题，所以按 "用户: xxx / 助手: xxx" 的格式写文件。
        只用最近若干条，避免超出上下文。
        """
        if not messages:
            return
        if not self.alive:
            return

        # 留够生成空间：历史最多占 ctx 的一半
        budget = max(512, int(self.ctx * 0.5))
        lines = []
        used = 0
        for m in reversed(messages):
            role = "用户" if m.get("role") == "user" else "助手"
            text = clean_text(m.get("content") or "").replace("\n", " ").strip()
            if not text:
                continue
            line = "%s: %s" % (role, text)
            # 粗略估计：中文约 1 字 1 token，英文约 4 字符 1 token
            cost = len(line)
            if used + cost > budget:
                break
            lines.append(line)
            used += cost
        lines.reverse()
        if not lines:
            return

        fd, path = tempfile.mkstemp(suffix=".txt", prefix="history-")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))
            self._tmp_files.append(path)
            # /read 会立刻把内容加进上下文，并打印一行确认
            self.chat.proc.stdin.write(("/read " + path + "\n").encode("utf-8"))
            self.chat.proc.stdin.flush()
            # 等它读完，避免和接下来的提问抢管道
            time.sleep(0.35)
        except Exception:
            pass

    def _cleanup_tmp(self):
        for p in self._tmp_files:
            try:
                os.remove(p)
            except Exception:
                pass
        self._tmp_files = []

    # ------------------------------------------------------------ 提问
    def ask(self, text, on_token, timeout=900):
        if not self.alive:
            raise LlamaError("模型进程没有运行")
        try:
            self.chat.stop_event.clear()
        except Exception:
            pass
        return self.chat.ask(text, on_token=on_token, timeout=timeout)

    def stop_generation(self):
        if self.chat:
            try:
                self.chat.stop_event.set()
            except Exception:
                pass

    @property
    def last_stats(self):
        return self.chat.last_stats if self.chat else None

    # ------------------------------------------------------------ 换模型/参数
    def needs_restart(self, ctx=None, temp=None, max_tokens=None, system=None, model=None, reasoning=None):
        """这些参数只能在启动时确定，变了就得重启进程。"""
        if ctx is not None and ctx != self.ctx:
            return True
        if temp is not None and abs(temp - self.temp) > 1e-9:
            return True
        if max_tokens is not None and max_tokens != self.max_tokens:
            return True
        if system is not None and system != self.system:
            return True
        if model is not None and model != self.model:
            return True
        if reasoning is not None and reasoning != self.reasoning:
            return True
        return False

    def update(self, ctx=None, temp=None, max_tokens=None, system=None, model=None, reasoning=None):
        if ctx is not None:
            self.ctx = ctx
        if temp is not None:
            self.temp = temp
        if max_tokens is not None:
            self.max_tokens = max_tokens
        if system is not None:
            self.system = system
        if model is not None:
            self.model = model
        if reasoning is not None:
            self.reasoning = reasoning

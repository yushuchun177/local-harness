# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""上下文压缩插件。

原理：
  · 用 llama-tokenize 精确数出每条消息的 token 数
  · 对话累积到阈值（默认 2048，刻度 1024 可调）时，在下一轮提问前触发压缩
  · 压缩 = 让模型自己把历史总结成一段简短的"记忆"，然后用这段记忆替换旧消息
  · 保留最近 N 轮原话不压缩，保证眼前的上下文连贯

压缩本身也是一次普通的 llama-cli 提问（走 stdin/stdout 管道），
不联网、不起服务、不开浏览器。
"""

import os
import re
import subprocess
import sys
import tempfile
import threading

from .engine import LlamaChat, LlamaError


# 给模型做压缩时的提示词
COMPRESS_PROMPT = """请把下面的对话历史压缩成一段简洁的中文摘要，用于让另一个 AI 继续这段对话。

要求：
1. 保留所有人名、地名、数字、日期、决定和待办事项
2. 保留用户的人设、偏好和明确说过的约束
3. 按时间顺序写成 3-8 句话，不要用列表符号
4. 只输出摘要本身，不要任何解释、前言或引号

对话历史：
{history}

摘要："""


def count_tokens(cli_dir, model, text):
    """用 llama-tokenize 精确计数。返回 token 数；失败返回 None。"""
    tok = os.path.join(cli_dir, "llama-tokenize.exe")
    if not os.path.isfile(tok):
        return None

    flags = 0
    if sys.platform == "win32":
        flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

    nf = None
    path = None
    try:
        fd, path = tempfile.mkstemp(suffix=".txt", prefix="tok-")
        nf = os.fdopen(fd, "w", encoding="utf-8")
        nf.write(text)
        nf.close()
        nf = None

        p = subprocess.run(
            # llama-tokenize 不支持 --no-warmup，传了会直接报 invalid argument
            [tok, "-m", model, "-f", path, "--log-disable"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=60,
            creationflags=flags,
        )
        out = p.stdout.decode("utf-8", "replace")
        # 每个 token 一行形如 " 58695 -> '中国'"
        n = len(re.findall(r"^\s*\d+\s+->", out, re.M))
        return n if n > 0 else None
    except Exception:
        return None
    finally:
        if nf:
            try:
                nf.close()
            except Exception:
                pass
        if path:
            try:
                os.remove(path)
            except Exception:
                pass


class ContextCompressor:
    """负责判断何时压缩、执行压缩、写回对话。"""

    def __init__(self, cli, model, threshold=2048, step=1024, keep_recent=4):
        self.cli = cli
        self.model = model
        self.threshold = int(threshold)
        self.step = int(step)           # 刻度：阈值滑块每格 1024
        self.keep_recent = int(keep_recent)
        self.cli_dir = os.path.dirname(cli) or "."
        self._lock = threading.RLock()
        self.last_count = 0
        self.last_compress = 0

    # ------------------------------------------------------------ 计数
    def count_messages(self, messages):
        """把消息列表按压缩格式拼起来数 token。"""
        text = "\n".join(
            "%s: %s"
            % ("用户" if m.get("role") == "user" else "助手", (m.get("content") or "").strip())
            for m in messages
            if m.get("content")
        )
        return count_tokens(self.cli_dir, self.model, text)

    def count_text(self, text):
        return count_tokens(self.cli_dir, self.model, text or "")

    # ------------------------------------------------------------ 判断
    def needs_compress(self, messages):
        with self._lock:
            n = self.count_messages(messages)
            self.last_count = n or 0
            if n is None:
                return False
            return n >= self.threshold

    # ------------------------------------------------------------ 压缩
    def compress(self, messages, system=""):
        """返回压缩后的消息列表。

        前部历史 -> 一条摘要；最近若干轮原样保留。
        保留轮数会动态调整：如果压缩后仍超阈值，就少留几轮，
        保证结果真的降下来（否则下一轮又会立刻触发压缩）。
        """
        with self._lock:
            msgs = list(messages or [])
            if len(msgs) < 4:
                return msgs, 0, 0

            before = self.count_messages(msgs) or 0
            target = max(1, int(self.threshold * 0.7))  # 压到阈值的 70% 以下才算成功

            # 先用【固定文本】估算摘要本身的开销，不重复调用模型
            # 摘要通常 100-300 token，这里按 250 估
            SUMMARY_COST = 250

            keep = min(self.keep_recent, len(msgs) - 2)
            best = None
            while keep >= 0:
                cut = max(1, len(msgs) - keep)
                old = msgs[:cut]
                recent = msgs[cut:]

                recent_cost = 0
                for m in recent:
                    c = self.count_text((m.get("content") or "").strip()) or 0
                    recent_cost += c
                estimate = SUMMARY_COST + recent_cost
                if estimate < target or keep == 0:
                    best = (old, recent, keep)
                    break
                keep -= 1

            if best is None:
                best = (msgs[:-2], msgs[-2:], 2)

            old, recent, keep = best
            history_text = "\n".join(
                "%s: %s"
                % ("用户" if m.get("role") == "user" else "助手", (m.get("content") or "").strip())
                for m in old
                if m.get("content")
            )

            prompt = COMPRESS_PROMPT.format(history=history_text)
            summary = self._ask_summary(prompt, system)
            if not summary:
                return msgs, before, before

            summary = self._fit_summary(summary, max(600, self.threshold // 2))

            new_msgs = [
                {"role": "user", "content": "（以下是之前对话的摘要）\n" + summary},
                {"role": "assistant", "content": "好的，我已记住这段摘要，会据此继续对话。"},
            ] + recent

            after = self.count_messages(new_msgs) or 0
            self.last_compress = before - after
            self.kept_rounds = keep
            return new_msgs, before, after

    def _ask_summary(self, prompt, system=""):
        """开一个临时 llama-cli 进程做摘要（复用同一套管道逻辑）。"""
        ch = None
        fd, path = tempfile.mkstemp(suffix=".txt", prefix="compress-")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(prompt)

            ch = LlamaChat(
                cli_path=self.cli,
                model_path=self.model,
                ctx_size=max(2048, min(self.threshold, 8192)),
                temperature=0.2,          # 摘要要稳，不要发挥
                max_new_tokens=512,
                threads=None,
                reasoning=False,
                system_prompt=system or "你是对话摘要助手。",
            )
            ch.start(timeout=180)

            # /read 把摘要提示词塞进上下文，再问一句让它输出
            ch.proc.stdin.write(("/read " + path + "\n").encode("utf-8"))
            ch.proc.stdin.flush()
            import time
            time.sleep(0.4)

            out = ch.ask("请只输出上面要求的摘要。", on_token=None, timeout=600)
            return self._clean(out)
        except Exception:
            return None
        finally:
            if ch:
                try:
                    ch.stop()
                except Exception:
                    pass
            try:
                os.remove(path)
            except Exception:
                pass

    def _fit_summary(self, text, budget):
        """摘要太长就按句子截，保证不把压缩后的上下文又撑爆。"""
        parts = re.split(r"(?<=[。！？.!?])", text)
        out = []
        used = 0
        for part in parts:
            c = self.count_text(part) or 0
            if used + c > budget and out:
                break
            out.append(part)
            used += c
        return "".join(out).strip()

    @staticmethod
    def _clean(text):
        """去掉模型爱加的引号、标题、前缀。"""
        s = (text or "").strip()
        for pre in ("摘要：", "摘要:", "总结：", "总结:"):
            if s.startswith(pre):
                s = s[len(pre):].strip()
        s = s.strip('"').strip("'").strip("《》").strip()
        s = re.sub(r"^```[^\n]*\n?", "", s)
        s = re.sub(r"\n?```$", "", s)
        return s.strip()

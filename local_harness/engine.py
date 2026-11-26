# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""通过子进程 stdin/stdout 管道驱动 llama.cpp。

llama-cli 以交互模式常驻，实测输出结构：

    Loading model...
    <ASCII 横幅>
    build      : b12728-...
    model      : ...

    available commands:
      /exit or Ctrl+C     stop or exit
      ...
      /glob <pattern>     add text files using globbing pattern

    > <回答正文，流式吐出>

    [ Prompt: 107.3 t/s | Generation: 24.7 t/s ]

    >

三条关键事实：
  · 提示符 `> ` 后面不带换行，回答直接接在它同一行。
  · 一轮结束的唯一标志是行首出现 `[ Prompt:` / `[prompt:`。
  · 启动就绪的唯一可靠信号是 `\\n> ` 序列；横幅里 `/read <file>`
    虽然也含 `> `，但它前面不是换行，所以不会误判。

正文的行首留几个字符做前瞻（判断是不是结束标记），一旦确定不是，
立刻转入直通模式，逐字符输出，保证流式手感。
"""

import os
import re
import subprocess
import sys
import threading
import time

S_BANNER = "banner"
S_IDLE = "idle"
S_GEN = "gen"
S_PERF = "perf"

PROMPT = "\n> "
END_MARKS = ("[ Prompt:", "[prompt:")
THINK_START = "[Start thinking]"
THINK_END = "[End thinking]"
SKIP_MARKS = (THINK_START, THINK_END)


class LlamaError(RuntimeError):
    pass


_FLAG_CACHE = {}


def _probe_flags(cli_path):
    """探测这个 llama-cli 支持哪些长开关（`--help` 里出现过的）。

    探测失败返回空集合，调用方据此"不过滤"，保持老行为。
    """
    try:
        st = os.stat(cli_path)
        key = (cli_path, int(st.st_mtime), st.st_size)
    except OSError:
        return set()
    hit = _FLAG_CACHE.get(key)
    if hit is not None:
        return hit

    flags = set()
    try:
        rc_flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        proc = subprocess.run(
            [cli_path, "--help"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=25,
            creationflags=rc_flags,
        )
        text = proc.stdout.decode("utf-8", "replace")
        # 帮助里长开关和短开关是并排写的：`-sys, --system-prompt`
        flags = set(re.findall(r"(?<![\w-])(--[a-z][a-z0-9-]+|-[a-zA-Z][a-z0-9-]*)", text))
    except Exception:
        flags = set()
    _FLAG_CACHE[key] = flags
    return flags


class AnsiFilter:
    """逐字符吃掉 ANSI 转义序列，让气泡里只剩正文。

    要处理三种东西：

      1. 完整转义序列：ESC [ ... 终止字节（颜色、清行等），ESC ] ... BEL/ST。
      2. 只剩尾巴的 SGR 片段：`[0m`、`[35m`、`[1;31m`。这类是 ESC 在
         管道/复制层丢了一半留下的，光按 ESC 切不够。
      3. 其他控制字符（退格、响铃等）—— 气泡里不该出现。

    SGR 片段本身长得像正文，所以不能见 `[` 就丢：只有 `[` 后面全是数字和
    分号、并以 `m` 收尾的才丢；`[1]`、`[ Prompt:`、`[链接]` 原样放行。
    """

    TEXT = 0
    ESC = 1       # 刚吃到 ESC
    ESC_ONE = 2   # ESC ( / ESC ) 之后还要再吃一个字符
    CSI = 3       # ESC [ ... 参数，直到终止字节
    OSC = 4       # ESC ] ... 直到 BEL 或 ST
    BRACKET = 5   # 正文里的 '['
    SGR = 6       # '[' 后面一直是数字/分号

    MAX_SGR = 12

    def __init__(self):
        self.state = self.TEXT
        self._buf = ""

    def feed(self, text):
        out = []
        for ch in text:
            piece = self._one(ch)
            if piece:
                out.append(piece)
        return "".join(out)

    def flush(self):
        """流结束时把攒着的东西放出来：攒着的 `[`、`[12` 是正文。"""
        rest = self._buf
        self._buf = ""
        self.state = self.TEXT
        return rest

    # ------------------------------------------------------------------
    def _one(self, ch):
        st = self.state

        if st == self.TEXT:
            if ch == "\x1b":
                self.state = self.ESC
                return ""
            if ch == "[":
                self.state = self.BRACKET
                self._buf = "["
                return ""
            if ch in ("\n", "\t"):
                return ch
            if ch < " " or ch == "\x7f":
                return ""
            return ch

        if st == self.ESC:
            if ch == "[":
                self.state = self.CSI
                return ""
            if ch == "]":
                self.state = self.OSC
                return ""
            if ch in "()*+#%":
                self.state = self.ESC_ONE
                return ""
            # ESC 7 / ESC = / ESC \ 这类两字符序列，连着 ESC 一起丢
            self.state = self.TEXT
            return ""

        if st == self.ESC_ONE:
            self.state = self.TEXT
            return ""

        if st == self.CSI:
            if "\x40" <= ch <= "\x7e":
                self.state = self.TEXT
            return ""

        if st == self.OSC:
            if ch == "\x07":
                self.state = self.TEXT
            elif ch == "\x1b":
                self.state = self.ESC
            return ""

        if st == self.BRACKET:
            if ch.isdigit() or ch == ";":
                self._buf += ch
                self.state = self.SGR
                return ""
            if ch == "m":
                self._buf = ""
                self.state = self.TEXT
                return ""
            self.state = self.TEXT
            head = self._buf
            self._buf = ""
            return head + self._one(ch)

        # SGR
        if ch.isdigit() or ch == ";":
            self._buf += ch
            if len(self._buf) > self.MAX_SGR:
                self.state = self.TEXT
                head = self._buf
                self._buf = ""
                return head
            return ""
        if ch == "m":
            self._buf = ""
            self.state = self.TEXT
            return ""
        self.state = self.TEXT
        head = self._buf
        self._buf = ""
        return head + self._one(ch)


# 各种模型自带的控制标记，漏到正文里就该清掉
_CTRL_TOKEN_RE = re.compile(
    r"<\|[A-Za-z_]{2,32}\|>"                      # <|im_end|> <|eot_id|> <|endoftext|>
    r"|</?s>|<s>"                                 # SentencePiece 的 bos/eos
    r"|</?(?:start_of_turn|end_of_turn)>"         # Gemma
    r"|<(?:bos|eos|unk|pad)>",
    re.I,
)


def clean_text(text):
    """把一整段文本洗成气泡里该有的样子。

    去掉 ANSI 转义序列、残留的颜色码片段和控制字符、模型自带的控制标记，
    再压掉开头空行和三行以上的连续空行。读旧对话记录时也过一遍。
    """
    if not text:
        return ""
    f = AnsiFilter()
    out = f.feed(text) + f.flush()
    out = out.replace("\r\n", "\n").replace("\r", "\n")
    out = _CTRL_TOKEN_RE.sub("", out)
    out = re.sub(r"(?:\n[ \t]*){3,}", "\n\n", out)   # 三行以上空行压成一行
    return out.strip("\n")


class LlamaChat:
    """一个 llama-cli 子进程 + 一层流式过滤。"""
    def __init__(
        self,
        cli_path,
        model_path,
        ctx_size=4096,
        temperature=0.7,
        max_new_tokens=512,
        threads=None,
        reasoning=False,
        system_prompt=None,
        extra_args=None,
        gpu_layers=0,
        flash_attn=False,
        tensor_core=False,
        tensor_split=None,
    ):
        self.cli_path = cli_path
        self.model_path = model_path
        self.ctx_size = ctx_size
        self.temperature = temperature
        self.max_new_tokens = max_new_tokens
        self.threads = threads or (os.cpu_count() or 4)
        self.reasoning = reasoning
        self.system_prompt = system_prompt
        self.extra_args = list(extra_args or [])
        # 卸载到显卡的层数：0 = 纯 CPU，-1 = 全部层，其它为具体层数（CPU+GPU 混合）
        self.gpu_layers = gpu_layers
        self.flash_attn = flash_attn
        self.tensor_core = tensor_core
        self.tensor_split = tensor_split

        self.proc = None

        self._state = S_BANNER
        self._tail = ""       # BANNER / PERF：用来匹配 "\n> " 的滑动尾巴
        self._buf = ""        # GEN：行首还没定性的字符
        self._started = False # GEN：本行是否已过行首判定
        self._skip = False    # GEN：当前行整行丢弃
        self._thinking = False  # 正在思考块内（跨行丢弃，直到 [End thinking]）

        self._turn = None
        self._ansi = AnsiFilter()
        self._ready = threading.Event()
        self._start_err = None
        self._dec = b""
        self._last_stats = None
        # 上一轮最后一次收到数据的时刻：某些 llama.cpp 版本没有 "[ Prompt:" 收尾行，
        # 靠"安静了很久"来判定这一轮结束。
        self._quiet_since = time.time()
        # 界面上的"停止"按这个：置位后当前这一轮的等待循环会提前退出
        self.stop_event = threading.Event()
        # Popen 一返回 proc 就非空，但那只是进程起来了，模型还没加载完。
        # 必须用这个标记区分"进程中有了"和"可以提问了"。
        self.ready = False

    # ------------------------------------------------------------ 参数
    def supported_flags(self):
        """问一下这个 llama-cli 认哪些开关。

        用户自带的 llama.cpp 可能是老版本：`--reasoning`、`--log-disable`
        这类新开关不存在，带上它们进程直接报错退出。所以先 `--help` 探一遍，
        只把我们确认支持的开关加进去。
        """
        return _probe_flags(self.cli_path)

    def args(self):
        ok = self.supported_flags()

        def want(*names):
            """names 里有一个受支持就返回那个名字，都不支持返回 None。"""
            for n in names:
                if not ok or n in ok:
                    return n
            return None

        a = [
            self.cli_path,
            "-m", self.model_path,
            "-c", str(self.ctx_size),
            "-n", str(self.max_new_tokens),
            "-t", str(self.threads),
            "--temp", str(self.temperature),
        ]
        for flag in ("--simple-io", "--no-warmup", "--no-perf", "--log-disable"):
            if want(flag):
                a.append(flag)
        if self.system_prompt:
            flag = want("-sys", "--system-prompt")
            if flag:
                a += [flag, self.system_prompt]
        if not self.reasoning:
            flag = want("--reasoning")
            if flag:
                a += [flag, "off"]
        elif want("--reasoning"):
            a += ["--reasoning", "on"]

        # ---- 显卡加速 ----
        ngl = int(self.gpu_layers or 0)
        flag = want("-ngl", "--n-gpu-layers", "-gpu-layers")
        if flag:
            # 必须显式给 0：新版本 llama-cli 默认 -ngl 99，
            # 不传就等于"全部层上显卡"，选"纯 CPU"时会失效。
            a += [flag, str(0 if ngl == 0 else (999 if ngl < 0 else ngl))]
        ts = self.tensor_split
        if ts and ngl:
            flag = want("-ts", "--tensor-split")
            if flag:
                a += [flag, ts]
        if self.flash_attn:
            flag = want("-fa", "--flash-attn")
            if flag:
                a += [flag, "on"]

        a += self.extra_args
        return a

    def env(self):
        """子进程环境变量：张量核心 / CUDA 相关开关从这里下发。"""
        e = dict(os.environ)
        if self.tensor_core and self.gpu_layers:
            # llama.cpp 没有独立的"张量核心开关"：
            # 强制走 MMQ 量化内核（mma 指令）并配合 FlashAttention 的 fp16 矩阵乘，
            # 在计算能力 >= 7.0 的卡上就会用到 Tensor Core。
            e["GGML_CUDA_FORCE_MMQ"] = "1"
            e["GGML_CUBLAS_FORCE_F16"] = "1"
        return e

    # ------------------------------------------------------------ 生命周期
    def start(self, timeout=180):
        flags = 0
        if sys.platform == "win32":
            flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

        try:
            self.proc = subprocess.Popen(
                self.args(),
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                bufsize=0,
                cwd=os.path.dirname(self.cli_path) or None,
                creationflags=flags,
                env=self.env(),
            )
        except FileNotFoundError:
            raise LlamaError("找不到 llama-cli 主程序：\n" + self.cli_path)
        except OSError as e:
            raise LlamaError("启动 llama-cli 失败：%s" % e)

        proc = self.proc
        threading.Thread(target=self._reader, args=(proc,), daemon=True).start()

        if not self._ready.wait(timeout):
            self.stop()
            raise LlamaError(
                "模型加载超时（%d 秒）。\n可能模型文件损坏，或内存不足。" % timeout
            )
        if self._start_err:
            self.stop()
            raise LlamaError(self._start_err)

    def stop(self):
        p = self.proc
        self.proc = None
        if p is None:
            return
        try:
            if p.poll() is None:
                try:
                    p.stdin.write(b"/exit\n")
                    p.stdin.flush()
                except Exception:
                    pass
                try:
                    p.wait(timeout=3)
                except Exception:
                    p.kill()
        except Exception:
            pass

    @property
    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    @property
    def can_ask(self):
        """模型真正加载完之后才能提问，光有进程不算。"""
        return self.ready and self.alive

    # ------------------------------------------------------------ 读线程
    def _reader(self, proc):
        try:
            while True:
                chunk = proc.stdout.read(1)
                if not chunk:
                    break
                self._dec += chunk
                text = self._decode()
                if not text:
                    continue
                text = self._ansi.feed(text)
                if not text:
                    continue
                for ch in text:
                    self._feed(ch)
        except Exception:
            pass

        if self._turn is not None:
            self._finish_turn()
        if self._state == S_BANNER and not self._ready.is_set():
            self._start_err = (
                "llama-cli 在加载模型时退出了。\n"
                "可能是模型文件损坏、参数不兼容，或内存不足。"
            )
        self._ready.set()

    def _decode(self):
        buf = self._dec
        if not buf:
            return ""
        try:
            s = buf.decode("utf-8")
            self._dec = b""
            return s
        except UnicodeDecodeError:
            # 只留可能是半个字符的尾巴
            if len(buf) > 4:
                s = buf.decode("utf-8", "replace")
                self._dec = b""
                return s
            return ""

    # ------------------------------------------------------------ 状态机
    def _feed(self, ch):
        if ch == "\r":
            return
        self._quiet_since = time.time()

        if self._state in (S_BANNER, S_PERF):
            self._tail = (self._tail + ch)[-8:]
            if self._tail.endswith(PROMPT):
                self._tail = ""
                self._state = S_IDLE
                self.ready = True
                self._ready.set()
            return

        # 收到第一个正文驱动字符，进入生成态
        if self._state == S_IDLE:
            self._state = S_GEN
            self._buf = ""
            self._started = False
            self._skip = False
            self._thinking = False

        # ---- S_GEN ----
        if ch == "\n":
            if self._skip:
                pass                      # 整行丢弃，什么也不输出
            elif self._thinking:
                pass                      # 思考块里的空行，同样丢弃
            elif not self._started:
                if self._buf:
                    self._emit(self._buf)
            self._buf = ""
            self._started = False
            self._skip = False
            if not self._skip and not self._thinking:
                self._emit("\n")
            return

        # 思考块内：只看是否遇到结束标记
        if self._thinking:
            self._buf += ch
            if self._buf.endswith(THINK_END):
                self._thinking = False
                self._buf = ""
                self._skip = False
            elif len(self._buf) > len(THINK_END):
                self._buf = self._buf[-len(THINK_END):]  # 只留末尾做匹配
            return

        if self._skip:
            return

        if self._started:
            self._emit(ch)
            return

        # 行首前瞻
        self._buf += ch

        for m in END_MARKS:
            if self._buf.startswith(m):
                self._buf = ""
                self._state = S_PERF
                self._tail = ""
                self._finish_turn()
                return
        if self._buf.startswith(THINK_START):
            self._buf = ""
            self._thinking = True
            return
        if self._buf.startswith(THINK_END):
            self._buf = ""
            self._skip = True
            return

        # 还可能构成标记，继续攒
        if any(m.startswith(self._buf) for m in END_MARKS + SKIP_MARKS):
            return

        # 确定不是标记：吐出去，之后本行直通
        text = self._buf
        self._buf = ""
        self._started = True
        self._emit(text)

    def _emit(self, text):
        t = self._turn
        if t is None or t["done"] or not text:
            return
        text = self._squeeze(t, text)
        if not text:
            return
        if t["first"] is None:
            t["first"] = time.time()
        t["n"] += len(text)
        t["parts"].append(text)
        cb = t["on_token"]
        if cb:
            try:
                cb(text)
            except Exception:
                pass

    @staticmethod
    def _squeeze(t, text):
        """压掉开头的空行和无意义的连续空行，不然气泡里一片空白。"""
        out = []
        nl = t["nl"]
        for ch in text:
            if ch == "\n":
                nl += 1
                if nl > 2:
                    continue
                out.append(ch)
            else:
                nl = 0
                out.append(ch)
        t["nl"] = nl
        return "".join(out)

    def _finish_turn(self):
        t = self._turn
        if t is not None and not t["done"]:
            t["done"] = True
            t["end"] = time.time()

    def _stop_generation(self):
        """中断当前生成。

        llama-cli 没有"停一半"的协议，最可靠的办法是给它一个换行把它从
        生成里踢出来，然后立刻收尾。之后下一轮照常可用。
        """
        if self.proc is None:
            return
        try:
            self.proc.stdin.write(b"\n")
            self.proc.stdin.flush()
        except Exception:
            pass
        self._finish_turn()
        self.stop_event.clear()

    # ------------------------------------------------------------ 对外
    def ask(self, prompt, on_token=None, timeout=900):
        if not self.can_ask:
            raise LlamaError("模型还没准备好，请稍等。")

        self._turn = {
            "parts": [],
            "on_token": on_token,
            "done": False,
            "first": None,
            "end": None,
            "start": time.time(),
            "n": 0,
            "nl": 2,   # 开头不许留空行：连续空行上限 2 个换行
        }
        self._state = S_GEN
        self._buf = ""
        self._started = False
        self._skip = False
        self._thinking = False
        self._tail = ""
        self._quiet_since = time.time()

        try:
            self.proc.stdin.write((prompt.replace("\n", " ") + "\n").encode("utf-8"))
            self.proc.stdin.flush()
        except Exception as e:
            self._turn = None
            raise LlamaError("写入 llama-cli 失败：%s" % e)

        deadline = time.time() + timeout
        while time.time() < deadline:
            if self._turn is None or self._turn["done"]:
                break
            if not self.alive:
                break
            # 界面按了"停止"
            if self.stop_event.is_set():
                self._stop_generation()
                break
            # 兜底：没有收尾标记的实现（或模型），靠"安静下来"判定结束
            t = self._turn
            if t and t["n"] > 0 and time.time() - self._quiet_since > 6.0:
                self._finish_turn()
                break
            time.sleep(0.02)

        t = self._turn
        self._turn = None
        if t is None:
            return ""

        text = "".join(t["parts"]).strip()
        self._last_stats = {
            "chars": t["n"],
            "secs": round((t["end"] or time.time()) - t["start"], 2),
            "first": round(t["first"] - t["start"], 2) if t["first"] else None,
            "timed_out": not t["done"],
        }
        return text

    @property
    def last_stats(self):
        return self._last_stats

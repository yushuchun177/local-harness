# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""纯终端对话界面。"""

import os
import sys
import time

from .engine import LlamaChat, LlamaError


def _ensure_utf8():
    """保证标准输出能写 UTF-8，中文和表格符号不会崩。"""
    if sys.platform == "win32":
        try:
            import ctypes
            ctypes.windll.kernel32.SetConsoleOutputCP(65001)
            ctypes.windll.kernel32.SetConsoleCP(65001)
        except Exception:
            pass
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    try:
        sys.stdin.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


_ensure_utf8()


# ---------------------------------------------------------------- 终端颜色
def _enable_ansi():
    if sys.platform != "win32":
        return True
    try:
        import ctypes
        k = ctypes.windll.kernel32
        h = k.GetStdHandle(-11)
        mode = ctypes.c_uint32()
        if not k.GetConsoleMode(h, ctypes.byref(mode)):
            return False
        k.SetConsoleMode(h, mode.value | 0x0004)
        return True
    except Exception:
        return False


ANSI = _enable_ansi()


def c(code, text):
    if not ANSI:
        return text
    return "\033[%sm%s\033[0m" % (code, text)


DIM = "90"
BOLD = "1"
CYAN = "36"
GREEN = "32"
YELLOW = "33"
RED = "31"
GREY = "38;5;245"


HELP = """\
命令：
  /help          显示这份帮助
  /clear         清空对话上下文（会重新加载模型）
  /stats         显示当前参数
  /exit          退出

直接输入问题，按回车发送。
一次只能输入一行；回答较长时，进程会一直输出到你按回车或它自己收尾。
"""


class App:
    def __init__(self, opts):
        self.opts = opts
        self.chat = None
        self.turns = 0

    # ------------------------------------------------------------ 启动
    def run(self):
        o = self.opts
        self.banner()

        print(c(DIM, "正在启动 llama.cpp…"))
        t0 = time.time()

        cfg = dict(
            ctx_size=o.ctx,
            temperature=o.temp,
            max_new_tokens=o.max_tokens,
            threads=o.threads,
            reasoning=o.reasoning,
            system_prompt=o.system,
            gpu_layers=getattr(o, "gpu_layers", 0) if getattr(o, "backend", "cpu") != "cpu" else 0,
            flash_attn=bool(getattr(o, "flash_attn", False)),
            tensor_core=bool(getattr(o, "tensor_core", False)),
        )
        accel = self._accel_line(o)
        if accel:
            print(c(DIM, accel))
        try:
            self.chat = self._spawn(cfg)
        except LlamaError as e:
            self.fatal(str(e))
            return 1

        dt = time.time() - t0
        print(c(GREEN, "就绪") + c(DIM, "（%.1f 秒）" % dt))
        print(c(DIM, "输入 /help 看命令，/exit 退出。窗口大小建议拉宽一些。"))
        print()

        try:
            self.loop()
        except KeyboardInterrupt:
            print()
        finally:
            if self.chat:
                print(c(DIM, "正在关闭…"))
                self.chat.stop()
        return 0

    def _spawn(self, cfg):
        ch = LlamaChat(self.opts.cli, self.opts.model, **cfg)
        ch.start(timeout=self.opts.timeout)
        return ch

    def _accel_line(self, o):
        """启动时打一行：用的哪个后端、多少层、张量核心开没开。"""
        backend = getattr(o, "backend", "cpu")
        if backend == "cpu":
            return "加速：CPU"
        ngl = int(getattr(o, "gpu_layers", -1))
        name = {"cuda": "CUDA", "vulkan": "Vulkan", "hip": "HIP"}.get(backend, backend)
        if ngl < 0:
            layers = "全部层"
        elif ngl == 0:
            layers = "0 层"
        else:
            layers = "%d 层 + CPU" % ngl
        bits = ["加速：" + name, layers]
        if getattr(o, "tensor_core", False):
            bits.append("张量核心开")
        if getattr(o, "flash_attn", False):
            bits.append("FlashAttention")
        return " · ".join(bits)

    # ------------------------------------------------------------ 主循环
    def loop(self):
        while True:
            try:
                line = input(c(CYAN, "你") + c(DIM, " > ") )
            except EOFError:
                print()
                return
            text = line.strip()
            if not text:
                continue

            if text.startswith("/"):
                if self.command(text):
                    return
                continue

            self.ask(text)

    def ask(self, text):
        print(c(GREEN, "AI") + c(DIM, " > "), end="", flush=True)

        started = time.time()
        first = [None]

        def on_token(t):
            if first[0] is None:
                first[0] = time.time()
            sys.stdout.write(t)
            sys.stdout.flush()

        try:
            answer = self.chat.ask(text, on_token=on_token)
        except LlamaError as e:
            print()
            print(c(RED, "出错：" + str(e)))
            return

        elapsed = time.time() - started
        print()

        if not answer:
            print(c(YELLOW, "（没有收到内容）"))
            print()
            return

        # 底部一行元信息
        n = self.chat.last_stats["chars"] if self.chat.last_stats else len(answer)
        ttfb = (first[0] - started) if first[0] else 0
        rate = n / elapsed if elapsed > 0 else 0
        print(
            c(
                GREY,
                "  %d 字 · %.1f 秒 · 首字节 %.2f 秒 · %.1f 字/秒"
                % (n, elapsed, ttfb, rate),
            )
        )
        print()
        self.turns += 1

    # ------------------------------------------------------------ 命令
    def command(self, text):
        """返回 True 表示要退出。"""
        cmd = text.split()[0].lower()

        if cmd in ("/exit", "/quit", "/q"):
            return True

        if cmd in ("/help", "/h", "/?"):
            print()
            print(HELP)
            return False

        if cmd == "/clear":
            print(c(DIM, "清空上下文，重启模型进程…"))
            if self.chat:
                self.chat.stop()
            cfg = dict(
                ctx_size=self.opts.ctx,
                temperature=self.opts.temp,
                max_new_tokens=self.opts.max_tokens,
                threads=self.opts.threads,
                reasoning=self.opts.reasoning,
                system_prompt=self.opts.system,
            )
            try:
                self.chat = self._spawn(cfg)
                self.turns = 0
                print(c(GREEN, "已清空。"))
            except LlamaError as e:
                self.fatal(str(e))
                return True
            print()
            return False

        if cmd == "/stats":
            o = self.opts
            print()
            print(c(BOLD, "当前参数"))
            print("  模型      " + os.path.basename(o.model))
            print("  llama-cli " + o.cli)
            print("  上下文    %d tokens" % o.ctx)
            print("  温度      %.2f" % o.temp)
            print("  最大生成  %d tokens" % o.max_tokens)
            print("  线程      %d" % (o.threads or (os.cpu_count() or 4)))
            print("  思考模式  " + ("开" if o.reasoning else "关"))
            print("  已聊      %d 轮" % self.turns)
            print()
            return False

        print(c(YELLOW, "没有这个命令：" + cmd))
        print(c(DIM, "输入 /help 看看有哪些。"))
        print()
        return False

    # ------------------------------------------------------------ 界面
    def banner(self):
        o = self.opts
        print()
        print(c(BOLD, "  local-harness") + c(DIM, "  ·  纯终端，完全离线"))
        print(c(DIM, "  " + "-" * 52))
        print(c(DIM, "  模型    ") + os.path.basename(o.model))
        print(
            c(DIM, "  参数    ")
            + "上下文 %d · 温度 %.2f · 最多 %d tokens"
            % (o.ctx, o.temp, o.max_tokens)
        )
        print()

    def fatal(self, msg):
        print()
        print(c(RED, "启动失败"))
        print(c(DIM, "  " + "-" * 52))
        for line in msg.splitlines():
            print("  " + line)
        print()
        print(c(DIM, "排查看这里："))
        print(c(DIM, "  · llama-cli 是否在程序目录下的 llama\\ 里"))
        print(c(DIM, "  · .gguf 模型是否在程序目录下的 model\\ 里"))
        print(c(DIM, "  · 内存是否够（0.6B 的 Q8 约需 1.5GB）"))
        print()


def main(opts):
    app = App(opts)
    try:
        return app.run()
    except KeyboardInterrupt:
        print()
        return 130

# -*- coding: utf-8 -*-
"""多模型冒烟测试：每个模型跑一轮，看回答是否干净、是否正常收尾。"""

import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from local_harness.engine import LlamaChat  # noqa: E402
from local_harness import assets, gguf  # noqa: E402
from local_harness.config import Config  # noqa: E402

PROMPT = "用一句话介绍你自己"


def run(cli, model):
    label = gguf.model_label(model)
    print("=" * 60)
    print("模型:", label, "| arch:", gguf.architecture(model), "| 原生 ctx:", gguf.native_context(model))
    chat = LlamaChat(
        cli, model, ctx_size=2048, max_new_tokens=96, threads=4,
        system_prompt="你是一个中文助手，回答简短。", reasoning=False,
    )
    t0 = time.time()
    try:
        chat.start(timeout=240)
    except Exception as e:
        print("  启动失败:", e)
        return False
    print("  加载 %.1fs" % (time.time() - t0))
    got = []
    t1 = time.time()
    text = chat.ask(PROMPT, on_token=got.append, timeout=300)
    stamp = time.time() - t1
    stats = chat.last_stats or {}
    chat.stop()
    print("  %.1fs 收尾=%s 字数=%d" % (stamp, "正常" if not stats.get("timed_out") else "超时/兜底", len(text)))
    print("  回答:", repr(text[:120]))
    bad = [c for c in text if c < " " and c not in "\n\t"]
    print("  控制字符:", bad, "| 残留标记:", "<|" in text or "\x1b" in text)
    return bool(text) and not bad


def main():
    cli = assets.find_llama_cli()
    if not cli:
        sys.exit("找不到 llama-cli")
    models = [
        m["path"]
        for m in assets.find_all_models(
            extra_dirs=Config(assets.base_dir()).get("model_dirs") or []
        )
    ]
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    if only:
        models = [m for m in models if only.lower() in m.lower()]
    print("共 %d 个模型，CLI=%s" % (len(models), cli))
    ok = 0
    for m in models:
        try:
            if run(cli, m):
                ok += 1
        except Exception as e:
            print("  异常:", e)
    print("\n通过 %d / %d" % (ok, len(models)))


if __name__ == "__main__":
    main()

# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""配置持久化：存在程序目录下的 config.json。

绿色便携版的关键：配置跟着程序走，拷到 U 盘也带着走。
"""

import json
import os
import threading

CONFIG_NAME = "config.json"

DEFAULTS = {
    "ctx": 4096,
    "temp": 0.7,
    "max_tokens": 512,
    "threads": 0,            # 0 = 自动
    "system": "你是一个中文助手，请始终用简体中文回答，回答简洁明了。",
    "dark": True,
    "model": "",             # 空 = 自动挑一个
    "reasoning": False,      # 思考模式（Qwen3 等支持 reasoning 的模型）
    "model_dirs": [],        # 用户额外导入的模型文件夹（绝对路径列表）
    "window": {"w": 1080, "h": 720},
    # 上下文压缩
    "compress_enabled": True,
    "compress_threshold": 2048,   # 达到这个 token 数就压缩
    "compress_step": 1024,        # 阈值滑块的刻度
    "compress_keep": 4,           # 最近保留几轮原话
}


class Config:
    """读写 config.json，线程安全。"""

    def __init__(self, base_dir):
        self.path = os.path.join(base_dir, CONFIG_NAME)
        self.data = dict(DEFAULTS)
        self._lock = threading.RLock()
        self.load()

    # ------------------------------------------------------------ 读
    def load(self):
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                loaded = json.load(f)
        except Exception:
            return
        if not isinstance(loaded, dict):
            return
        with self._lock:
            for k, default in DEFAULTS.items():
                if k not in loaded:
                    continue
                v = loaded[k]
                if isinstance(default, dict):
                    if isinstance(v, dict):
                        merged = dict(default)
                        merged.update(v)
                        self.data[k] = merged
                elif isinstance(default, bool):
                    self.data[k] = bool(v)
                elif isinstance(default, int):
                    try:
                        self.data[k] = int(v)
                    except (TypeError, ValueError):
                        pass
                elif isinstance(default, float):
                    try:
                        self.data[k] = float(v)
                    except (TypeError, ValueError):
                        pass
                elif isinstance(default, list):
                    if isinstance(v, list):
                        self.data[k] = [x for x in v if isinstance(x, str)]
                else:
                    if isinstance(v, str):
                        self.data[k] = v

    # ------------------------------------------------------------ 写
    def save(self):
        with self._lock:
            snapshot = json.loads(json.dumps(self.data))
        tmp = self.path + ".tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(snapshot, f, ensure_ascii=False, indent=2)
            os.replace(tmp, self.path)
        except Exception:
            try:
                if os.path.exists(tmp):
                    os.remove(tmp)
            except Exception:
                pass

    # ------------------------------------------------------------ 取值
    def get(self, key, default=None):
        with self._lock:
            if key in self.data:
                return self.data[key]
            if default is not None:
                return default
            return DEFAULTS.get(key)

    def set(self, key, value, save=True):
        with self._lock:
            self.data[key] = value
        if save:
            self.save()

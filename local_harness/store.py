# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""对话记录的存取。

每个对话一个 JSON 文件，放在程序目录的 chats\\ 下。
绿色版把整个目录拷走，历史对话也跟着走。
"""

import json
import os
import re
import threading
import time
import uuid


def _safe_name(title, fallback="新对话"):
    """把标题变成一个能当文件名的短串。"""
    s = re.sub(r"[\\/:*?\"<>|\r\n\t]", "", title or "").strip()
    s = s[:24]
    return s or fallback


class Store:
    """管理 chats 目录下的对话文件。"""

    def __init__(self, base_dir):
        self.dir = os.path.join(base_dir, "chats")
        self._lock = threading.RLock()
        try:
            os.makedirs(self.dir, exist_ok=True)
        except Exception:
            pass

    # ------------------------------------------------------------ 列表
    def list_chats(self):
        """返回 [{id, title, updated, messages, model}, ...]，按更新时间倒序。"""
        out = []
        try:
            names = os.listdir(self.dir)
        except Exception:
            return out

        for name in names:
            if not name.endswith(".json"):
                continue
            path = os.path.join(self.dir, name)
            try:
                with open(path, "r", encoding="utf-8") as f:
                    d = json.load(f)
            except Exception:
                continue
            if not isinstance(d, dict):
                continue
            out.append(
                {
                    "id": d.get("id") or name[:-5],
                    "title": d.get("title") or "未命名",
                    "updated": d.get("updated") or 0,
                    "messages": d.get("messages") or [],
                    "model": d.get("model") or "",
                }
            )
        out.sort(key=lambda c: c["updated"], reverse=True)
        return out

    # ------------------------------------------------------------ 读一个
    def load_chat(self, chat_id):
        path = os.path.join(self.dir, chat_id + ".json")
        try:
            with open(path, "r", encoding="utf-8") as f:
                d = json.load(f)
            if isinstance(d, dict):
                return d
        except Exception:
            pass
        return None

    # ------------------------------------------------------------ 存
    def save_chat(self, chat):
        with self._lock:
            cid = chat.get("id")
            if not cid:
                cid = uuid.uuid4().hex[:12]
                chat["id"] = cid
            chat["updated"] = time.time()
            path = os.path.join(self.dir, cid + ".json")
            tmp = path + ".tmp"
            try:
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump(chat, f, ensure_ascii=False, indent=1)
                os.replace(tmp, path)
                return cid
            except Exception:
                try:
                    if os.path.exists(tmp):
                        os.remove(tmp)
                except Exception:
                    pass
                return cid

    # ------------------------------------------------------------ 删
    def delete_chat(self, chat_id):
        path = os.path.join(self.dir, chat_id + ".json")
        try:
            os.remove(path)
            return True
        except Exception:
            return False

    # ------------------------------------------------------------ 新建
    def new_chat(self, model=""):
        return {
            "id": uuid.uuid4().hex[:12],
            "title": "新对话",
            "created": time.time(),
            "updated": time.time(),
            "model": model,
            "messages": [],
        }

    def auto_title(self, messages):
        """拿第一条用户消息当标题。"""
        for m in messages:
            if m.get("role") == "user":
                t = (m.get("content") or "").strip().replace("\n", " ")
                if t:
                    return t[:20]
        return "新对话"

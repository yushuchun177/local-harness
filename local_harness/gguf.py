# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""读取 GGUF 文件头里的元数据。

只为了拿一个数：模型原生支持的上下文长度（context_length）。
界面上的"上下文"滑块上限就用它，这样用户能一路拉满到模型真正的能力边界。
"""

import struct

# GGUF 值类型
T_UINT8, T_INT8, T_UINT16, T_INT16 = 0, 1, 2, 3
T_UINT32, T_INT32, T_FLOAT32, T_BOOL = 4, 5, 6, 7
T_STRING, T_ARRAY, T_UINT64, T_INT64, T_FLOAT64 = 8, 9, 10, 11, 12

_SCALAR = {
    T_UINT8: ("<B", 1),
    T_INT8: ("<b", 1),
    T_UINT16: ("<H", 2),
    T_INT16: ("<h", 2),
    T_UINT32: ("<I", 4),
    T_INT32: ("<i", 4),
    T_FLOAT32: ("<f", 4),
    T_BOOL: ("<?", 1),
    T_UINT64: ("<Q", 8),
    T_INT64: ("<q", 8),
    T_FLOAT64: ("<d", 8),
}

# 不同架构声明上下文长度用的键尾
_CTX_SUFFIXES = (
    ".context_length",
    ".n_ctx_train",
    ".max_position_embeddings",
    ".max_seq_len",
    ".n_ctx",
)


def _has_wanted(meta):
    """架构、名字、上下文都拿到了就别再往下读了。"""
    if "general.architecture" not in meta or "general.name" not in meta:
        return False
    return any(k.endswith(_CTX_SUFFIXES) for k in meta)


class _Reader:
    def __init__(self, f):
        self.f = f

    def take(self, n):
        b = self.f.read(n)
        if len(b) != n:
            raise EOFError("文件提前结束")
        return b

    def u32(self):
        return struct.unpack("<I", self.take(4))[0]

    def u64(self):
        return struct.unpack("<Q", self.take(8))[0]

    def string(self):
        n = self.u64()
        if n > 1 << 20:          # 元数据里不会有这么长的字符串
            raise ValueError("字符串过长，可能不是 GGUF")
        return self.take(n).decode("utf-8", "replace")

    def skip(self, n):
        self.f.seek(n, 1)


def read_metadata(path, limit_keys=2000):
    """返回 {key: value}，只解析标量和字符串，数组跳过。

    注意：数组里的字符串必须逐个读过去（合并词表动辄几十万条），
    不能按条数截断，否则后面的键全部错位。

    我们只关心架构、名字、上下文长度这几个键，它们都在文件头前面，
    拿到就可以停，不用为几十万条词表付时间。
    """
    out = {}
    with open(path, "rb") as f:
        magic = f.read(4)
        if magic != b"GGUF":
            raise ValueError("不是 GGUF 文件")
        r = _Reader(f)
        r.u32()                     # version
        r.u64()                     # tensor count
        kv_count = r.u64()

        n = min(kv_count, limit_keys)
        for _ in range(n):
            key = r.string()
            vtype = r.u32()

            if vtype in _SCALAR:
                fmt, size = _SCALAR[vtype]
                out[key] = struct.unpack(fmt, r.take(size))[0]
            elif vtype == T_STRING:
                out[key] = r.string()
            elif vtype == T_ARRAY:
                itype = r.u32()
                count = r.u64()
                if count > 50000000:      # 明显不对，别把文件读到天荒地老
                    break
                if itype in _SCALAR:
                    r.skip(_SCALAR[itype][1] * count)
                elif itype == T_STRING:
                    for _ in range(count):
                        r.string()
                else:
                    # 数组套数组这种少见情况：放弃继续解析
                    break
            else:
                break

            if key == "general.architecture" or key.endswith(_CTX_SUFFIXES):
                if _has_wanted(out):
                    break
    return out


_META_CACHE = {}


def _metadata_cached(path):
    """同一个文件别反复解析：界面要名字、要上下文、要架构，会问三次。"""
    import os

    try:
        st = os.stat(path)
        key = (os.path.abspath(path), int(st.st_mtime), st.st_size)
    except OSError:
        return {}
    if key not in _META_CACHE:
        if len(_META_CACHE) > 16:
            _META_CACHE.clear()
        try:
            _META_CACHE[key] = read_metadata(path)
        except Exception:
            _META_CACHE[key] = {}
    return _META_CACHE[key]


_CTX_KEYS = (
    ".context_length",
    ".n_ctx_train",
    ".max_position_embeddings",
    ".max_seq_len",
    ".n_ctx",
)


def native_context(path):
    """模型声明的原生上下文长度；读不到就返回 None。

    不同架构（llama / qwen / gemma / phi / deepseek…）用的键名不一样，
    按优先级依次找，最后再兜底扫任何带 context_length 的键。
    """
    try:
        meta = read_metadata(path)
    except Exception:
        return None

    for suffix in _CTX_KEYS:
        for k, v in meta.items():
            if k.endswith(suffix) and isinstance(v, int) and v > 0:
                return v
    for k, v in meta.items():
        if "context_length" in k and isinstance(v, int) and v > 0:
            return v
    return None


def architecture(path):
    """GGUF 里的 general.architecture，例如 llama / qwen2 / gemma3。"""
    try:
        meta = read_metadata(path)
    except Exception:
        return ""
    return str(meta.get("general.architecture") or "")


def general_name(path):
    """GGUF 里的 general.name（比文件名准，缺了就是空串）。"""
    try:
        meta = read_metadata(path)
    except Exception:
        return ""
    return str(meta.get("general.name") or "")


# 常见的模型家族：小写前缀 -> 显示写法
_FAMILIES = {
    "llama": "Llama", "llama2": "Llama 2", "llama3": "Llama 3",
    "codellama": "CodeLlama", "tinyllama": "TinyLlama",
    "qwen": "Qwen", "qwen2": "Qwen2", "qwen2.5": "Qwen2.5", "qwen3": "Qwen3",
    "mistral": "Mistral", "mixtral": "Mixtral", "mistral-nemo": "Mistral Nemo",
    "gemma": "Gemma", "gemma2": "Gemma 2", "gemma3": "Gemma 3",
    "phi": "Phi", "phi2": "Phi-2", "phi3": "Phi-3", "phi4": "Phi-4",
    "deepseek": "DeepSeek", "deepseek2": "DeepSeek", "deepseek-coder": "DeepSeek Coder",
    "yi": "Yi", "glm": "GLM", "chatglm": "ChatGLM", "glm4": "GLM-4",
    "baichuan": "Baichuan", "internlm": "InternLM", "internlm2": "InternLM2",
    "minicpm": "MiniCPM", "smollm": "SmolLM", "smollm2": "SmolLM2",
    "falcon": "Falcon", "mamba": "Mamba", "rwkv": "RWKV", "olmo": "OLMo",
    "granite": "Granite", "nemotron": "Nemotron", "exaone": "EXAONE",
    "command-r": "Command R", "starcoder": "StarCoder", "starcoder2": "StarCoder2",
    "hermes": "Hermes", "dolphin": "Dolphin", "solar": "SOLAR", "aya": "AYA",
    "vicuna": "Vicuna", "wizardlm": "WizardLM", "zephyr": "Zephyr",
    "openchat": "OpenChat", "starling": "Starling", "nous": "Nous",
    "tulu": "Tulu", "openhermes": "OpenHermes", "orca": "Orca",
    "smaug": "Smaug", "zephyr": "Zephyr", "yi": "Yi", "exaone": "EXAONE",
}

_QUANT_RE = r"(?i)^(?:iq\d+[_a-z0-9]*|q\d+(?:[_a-z0-9]+)*|bf16|fp16|f16|fp32|f32|f64|q8_0)$"
_FILLER = {
    "gguf", "instruct", "chat", "it", "base", "hf", "uncased", "cased",
    "gguf", "the", "model", "assistant", "preview", "gguf4", "text",
}
# 零散单词的显示写法（文件名里通常是小写）
_WORDS = {
    "coder": "Coder", "mini": "mini", "nemo": "Nemo", "r1": "R1",
    "thinking": "Thinking", "vision": "Vision", "math": "Math",
    "code": "Code", "v2": "v2", "v3": "v3", "lite": "Lite",
    "edge": "Edge", "small": "Small", "medium": "Medium", "large": "Large",
    "tiny": "Tiny", "micro": "Micro",
}


def _pretty_tokens(stem):
    """把 qwen2.5-3b-instruct 这种拆成 ['Qwen2.5', '3B']，尽量通用。"""
    import re

    # 小数点不拆（0.6B / v1.0），其余的 - _ . 空格都当分隔
    tokens = [t for t in re.split(r"[-_\s]+|\.(?!\d)", stem) if t]
    out = []
    for tok in tokens:
        low = tok.lower()
        if low == "of" or re.match(r"^\d{5}$", low):
            continue                       # 分片文件的 00001-of-00002
        if low in _FILLER:
            continue
        if low in _FAMILIES:
            out.append(_FAMILIES[low])
            continue
        if low in _WORDS:
            out.append(_WORDS[low])
            continue
        # 家族 + 尺寸连写：qwen3、gemma2b 之类
        m = re.match(r"^([a-z][a-z-]*?)(\d+(?:\.\d+)?)(b|m|k)$", low)
        if m and m.group(1) in _FAMILIES:
            out.append("%s %s%s" % (_FAMILIES[m.group(1)], m.group(2), m.group(3).upper()))
            continue
        # 参数量：3b / 0.6B / 360m / 7B
        m = re.match(r"^(\d+(?:\.\d+)?)(b|m)$", low)
        if m:
            out.append(m.group(1) + m.group(2).upper())
            continue
        # 版本号：v1.0 / 2.5
        if re.match(r"^v?\d+(\.\d+)+$", low):
            out.append(tok[1:] if low.startswith("v") else tok)
            continue
        if re.match(r"^\d+$", low) and out:
            out.append(tok)               # Llama 3 这种裸版本号
            continue
        out.append(tok)
    return out


def model_label(path):
    """模型名，用于界面显示。

    先看 GGUF 里的 general.name（最准），没有就用文件名。
    任何模型的命名风格都能收拾成人看得懂的样子：
        qwen3-1.7b-q8_0.gguf          -> Qwen3 1.7B · Q8_0
        TinyLlama-1.1B-Chat-v1.0.Q4_K_M.gguf -> TinyLlama 1.1B 1.0 · Q4_K_M
        gemma-2-2b-it-Q8_0.gguf       -> Gemma 2 2B · Q8_0
    """
    import os
    import re

    if not path:
        return ""
    base = os.path.basename(str(path))
    stem = re.sub(r"\.gguf$", "", base, flags=re.I)

    # 量化标记：Q4_K_M、Q8_0、IQ3_XS、fp16 之类
    quant = ""
    m = re.search(r"(?i)[-_.](iq\d+[_a-z0-9]*|q\d+[_a-z0-9]*|bf16|fp16|f16|fp32|f32)$", stem)
    if m and re.match(_QUANT_RE, m.group(1)):
        quant = m.group(1).upper()
        stem = stem[: m.start()]

    name = general_name(path)
    name_tokens = _pretty_tokens(name) if name else []
    stem_tokens = _pretty_tokens(stem)
    # general.name 有时是训练配方的完整写法
    # （SmolLM2-360M-8k-Lc100K-Mix1-Ep2），太长就改用文件名
    if name_tokens and len(name_tokens) <= 4:
        tokens = name_tokens
    else:
        tokens = stem_tokens or name_tokens
    if not tokens:
        tokens = [base]

    label = " ".join(tokens).strip()
    # 去掉重复词（"Llama Llama"）
    parts = []
    for t in label.split():
        if not parts or parts[-1].lower() != t.lower():
            parts.append(t)
    label = " ".join(parts)

    if quant and quant.lower() not in label.lower():
        label += " · " + quant
    return label


def model_summary(path):
    """一条模型的关键信息：显示名、原生上下文、架构。"""
    return {
        "label": model_label(path),
        "ctx": native_context(path),
        "arch": architecture(path),
    }

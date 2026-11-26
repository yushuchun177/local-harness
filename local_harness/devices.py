# -*- coding: utf-8 -*-
# =============================================================================
# local-harness — 完全离线的本地大模型对话程序
# Copyright (C) 2026 local-harness contributors
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# 第 3 版（或你选择的任何更新版本）的条款重新发布和/或修改它。
# 本程序按“没有任何担保”发布，完整条款见项目根目录的 LICENSE 文件。
# =============================================================================
"""探测推理后端与显卡，给界面提供"能用什么加速"的事实。

后端就是不同编译版本的 llama-cli，各自放在程序目录下：

    llama\\          CPU
    llama-cuda\\     CUDA（NVIDIA，需要 cudart DLL）
    llama-vulkan\\   Vulkan（几乎所有显卡）
    llama-hip\\      HIP / ROCm（AMD）

显卡信息用 nvidia-smi 读（NVIDIA），拿不到就退回 WMI 的名字。
"张量核心"是硬件特性：计算能力 >= 7.0 的 NVIDIA 卡（Volta 及以后）才有，
llama.cpp 里没有独立开关，靠 MMQ / FlashAttention 的 fp16 矩阵乘用上它。
"""

import os
import subprocess

# 后端名 -> 程序目录下可能的文件夹
BACKEND_DIRS = {
    "cpu": ("llama",),
    "cuda": ("llama-cuda",),
    "vulkan": ("llama-vulkan",),
    "hip": ("llama-hip", "llama-rocm"),
}

BACKEND_LABELS = {
    "cpu": "CPU（纯处理器）",
    "cuda": "CUDA（NVIDIA）",
    "vulkan": "Vulkan（通用显卡）",
    "hip": "HIP / ROCm（AMD）",
}

LLAMA_NAMES = ("llama-cli.exe", "llama-cli", "llama.exe", "main.exe", "main")

# Volta 起才有 Tensor Core
TENSOR_CORE_MIN_CC = 7.0


def _run(cmd, timeout=8):
    try:
        out = subprocess.run(
            cmd,
            capture_output=True,
            timeout=timeout,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        return out.stdout.decode("utf-8", "replace")
    except Exception:
        return ""


def nvidia_smi_path():
    """Windows 在 System32，Linux 在 PATH 里；两边都找一下。"""
    for p in (
        os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), "System32", "nvidia-smi.exe"),
        "/usr/bin/nvidia-smi",
        "/usr/local/bin/nvidia-smi",
        "nvidia-smi",
    ):
        if p in ("nvidia-smi", "/usr/bin/nvidia-smi", "/usr/local/bin/nvidia-smi"):
            if p == "nvidia-smi" or os.path.isfile(p):
                return p
        elif os.path.isfile(p):
            return p
    return None


# 老驱动不支持 `--query-gpu=compute_cap` 时，用型号名估算计算能力。
# 顺序有讲究：先匹配更具体的型号，避免 "RTX 4090" 被 40xx 提前吃掉。
_CC_BY_NAME = [
    # 长的、具体的型号放前面，避免 "A100" 被 "A10" 抢先匹配
    ("A100", 8.0), ("A800", 8.0), ("A30", 8.0),
    ("H100", 9.0), ("H200", 9.0), ("H800", 9.0),
    ("GTX 16", 7.5),
    ("RTX 20", 7.5), ("RTX 20 SUPER", 7.5),
    ("RTX 30", 8.6),
    ("RTX 40", 8.9),
    ("RTX 50", 12.0),
    ("RTX A", 8.6), ("A40", 8.6), ("A10", 8.6), ("A16", 8.6),
    ("L40", 8.9), ("L20", 8.9), ("L4", 8.9),
    ("V100", 7.0), ("T4", 7.5), ("P100", 6.0), ("P40", 6.1), ("P4", 6.1),
    ("GTX 10", 6.1), ("MX1", 6.1), ("MX2", 6.1), ("MX3", 6.1), ("MX4", 6.1),
    ("GTX 9", 5.2),
]


def compute_by_name(name):
    """从显卡型号猜计算能力；猜不到返回 0.0。"""
    up = (name or "").upper()
    for key, cc in _CC_BY_NAME:
        if key in up:
            return cc
    return 0.0


def nvidia_gpus():
    """[{name, vram_mb, compute, driver, tensor_cores}]，没有 NVIDIA 卡就是空列表。

    先按 4 个字段查（含 compute_cap）；老驱动不支持这个字段会直接报错、
    一行数据都不返回，这时退化成 3 个字段查，再用型号名估算计算能力。
    """
    smi = nvidia_smi_path()
    if not smi:
        return []

    rows = []
    out = _run([smi, "--query-gpu=name,memory.total,compute_cap,driver_version",
                "--format=csv,noheader"])
    for line in out.splitlines():
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 4:
            continue
        try:
            float(parts[2])
        except Exception:
            continue                      # 不是数字（可能整行是报错信息）
        rows.append(parts)

    if not rows:
        out = _run([smi, "--query-gpu=name,memory.total,driver_version",
                    "--format=csv,noheader"])
        for line in out.splitlines():
            parts = [p.strip() for p in line.split(",")]
            if len(parts) < 3:
                continue
            if "not a valid field" in line or "Field" in parts[0]:
                continue
            rows.append([parts[0], parts[1], "", parts[2]])

    gpus = []
    for parts in rows:
        name = parts[0]
        try:
            vram = int(float(parts[1].split()[0]))
        except Exception:
            vram = 0
        cc = 0.0
        if parts[2]:
            try:
                cc = float(parts[2])
            except Exception:
                cc = 0.0
        if cc <= 0:
            cc = compute_by_name(name)     # 老驱动兜底
        gpus.append(
            {
                "name": name,
                "vram_mb": vram,
                "compute": cc,
                "driver": parts[3],
                "tensor_cores": cc >= TENSOR_CORE_MIN_CC,
            }
        )
    return gpus



def wmi_gpu_names():
    """没有 nvidia-smi 时的兜底：只拿得到名字。

    Windows 走 WMI，Linux 走 lspci。
    """
    if os.name == "nt":
        out = _run([
            "powershell", "-NoProfile", "-Command",
            "(Get-CimInstance Win32_VideoController).Name",
        ])
    else:
        out = _run(["sh", "-c", "lspci 2>/dev/null | grep -Ei 'vga|3d|display' | cut -d: -f3-"])
    return [l.strip() for l in out.splitlines() if l.strip()]


def find_backends(base_dir):
    """{后端名: llama-cli 路径}，只返回真的存在的。"""
    found = {}
    for name, dirs in BACKEND_DIRS.items():
        for sub in dirs:
            for exe in LLAMA_NAMES:
                p = os.path.join(base_dir, sub, exe) if sub else os.path.join(base_dir, exe)
                if os.path.isfile(p):
                    found[name] = p
                    break
            if name in found:
                break
    return found


def _cuda_runtime_ok(cuda_cli):
    """CUDA 版能不能真的跑起来。

    Windows：官方包里 cudart / cuBLAS 是分开的 DLL，缺了就静默退回 CPU，
              所以要看到 cudart64_*.dll 才算齐。
    Linux：  ggml-cuda.so 会去链系统里的 libcudart（镜像我装好了 CUDA），
              只要 libggml-cuda.so 在就算可用；再顺手看看有没有 libcudart.so。
    """
    d = os.path.dirname(cuda_cli)
    is_win = os.name == "nt"
    try:
        names = [n.lower() for n in os.listdir(d)]
    except Exception:
        return False

    if is_win:
        return any(n.startswith("cudart") and n.endswith(".dll") for n in names)

    has_cuda_lib = any("ggml-cuda" in n and (n.endswith(".so") or ".so." in n) for n in names)
    if not has_cuda_lib:
        return False
    # 有系统的 libcudart 或者包内自带都行；没有也先按可用处理，
    # 真正跑不起来时 --list-devices 会暴露出来。
    return True


def detect(base_dir, extra_dirs=None):
    """一次拿全：后端、显卡、张量核心、建议。

    返回：
        backends      {名字: 路径}
        gpus          [显卡信息]
        tensor_core   本机是否有张量核心
        recommended   建议默认用哪个后端
        notes         [给界面显示的一句话说明]
    """
    backends = find_backends(base_dir)
    for d in extra_dirs or []:
        if d and os.path.isdir(d):
            backends.update(find_backends(d))

    gpus = nvidia_gpus()
    if not gpus:
        names = wmi_gpu_names()
        if names:
            gpus = [
                {"name": n, "vram_mb": 0, "compute": 0.0, "driver": "", "tensor_cores": False}
                for n in names
                if "microsoft" not in n.lower() and "virtual" not in n.lower()
            ]

    tensor_core = any(g.get("tensor_cores") for g in gpus)
    has_gpu = bool(gpus)
    cuda_ok = "cuda" in backends and _cuda_runtime_ok(backends["cuda"])

    # "自动"的优先顺序：
    #   · 显卡有张量核心（>= 7.0）且 CUDA 版可用 → CUDA，这是唯一能用上 Tensor Core 的路径
    #   · 否则 Vulkan（自带运行库、NVIDIA/AMD/Intel 都能用，最不容易翻车）
    #   · 再否则 CUDA / HIP / CPU
    if tensor_core and cuda_ok:
        recommended = "cuda"
    elif "vulkan" in backends and has_gpu:
        recommended = "vulkan"
    elif cuda_ok:
        recommended = "cuda"
    elif "cuda" in backends and not cuda_ok:
        recommended = "cpu"
    elif "hip" in backends and has_gpu:
        recommended = "hip"
    else:
        recommended = "cpu"

    notes = []
    if not has_gpu:
        notes.append("没有检测到独立显卡，只能走 CPU。")
    for g in gpus:
        if g.get("compute"):
            notes.append(
                "%s：显存 %d MB，计算能力 %.1f，%s张量核心"
                % (g["name"], g["vram_mb"], g["compute"], "" if g["tensor_cores"] else "不支持")
            )
        else:
            notes.append("%s（驱动信息读不到，按常规显卡处理）" % g["name"])
    if has_gpu and "cuda" not in backends and "vulkan" not in backends:
        notes.append("有显卡，但程序目录里没有 GPU 版 llama.cpp（llama-cuda\\ 或 llama-vulkan\\），暂时只能用 CPU。")
    if "cuda" in backends and not cuda_ok:
        notes.append("CUDA 版缺少 cudart / cuBLAS 运行库，启动后会退回 CPU；先用 Vulkan 或补上 DLL。")
    if tensor_core and "cuda" not in backends:
        notes.append("显卡支持张量核心，但这台机器上没有 llama-cuda\\，只有 CUDA 后端才能用上。")
    elif tensor_core and not cuda_ok:
        notes.append("显卡支持张量核心，但 llama-cuda\\ 缺运行库，装上 cudart / cuBLAS 后才能启用。")

    return {
        "backends": backends,
        "gpus": gpus,
        "tensor_core": tensor_core,
        "cuda_ready": cuda_ok,
        "recommended": recommended,
        "notes": notes,
    }


def gpu_layers_for(model_size_mb, vram_mb):
    """按显存粗略估算能卸载多少层（给界面一个默认值）。

    llama.cpp 需要显存放模型的一部分 + KV cache；这里保守地留 800MB 给
    KV cache 和上下文，剩余显存按模型大小折算层数，最少 1 层。
    """
    if not vram_mb or not model_size_mb:
        return 0
    usable = max(0, vram_mb - 800)
    if usable <= 0:
        return 0
    ratio = usable / float(model_size_mb)
    if ratio >= 1.0:
        return -1          # 全部放得下
    # 常见模型层数在 24~48 之间，按比例给个整数
    est = int(round(ratio * 32))
    return max(1, min(est, 31))

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

LLAMA_NAMES = ("llama-cli.exe", "llama.exe", "main.exe")

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
    for p in (
        os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), "System32", "nvidia-smi.exe"),
        "nvidia-smi",
    ):
        if p == "nvidia-smi" or os.path.isfile(p):
            return p
    return None


def nvidia_gpus():
    """[{name, vram_mb, compute, driver, tensor_cores}]，没有 NVIDIA 卡就是空列表。"""
    smi = nvidia_smi_path()
    if not smi:
        return []
    out = _run([smi, "--query-gpu=name,memory.total,compute_cap,driver_version",
                "--format=csv,noheader"])
    gpus = []
    for line in out.splitlines():
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 4:
            continue
        try:
            vram = int(float(parts[1].split()[0]))
        except Exception:
            vram = 0
        try:
            cc = float(parts[2])
        except Exception:
            cc = 0.0
        gpus.append(
            {
                "name": parts[0],
                "vram_mb": vram,
                "compute": cc,
                "driver": parts[3],
                "tensor_cores": cc >= TENSOR_CORE_MIN_CC,
            }
        )
    return gpus


def wmi_gpu_names():
    """没装 nvidia-smi 时的兜底：只拿得到名字。"""
    out = _run([
        "powershell", "-NoProfile", "-Command",
        "(Get-CimInstance Win32_VideoController).Name",
    ])
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
    """CUDA 版是否需要、且已带上 cudart DLL。"""
    d = os.path.dirname(cuda_cli)
    try:
        for name in os.listdir(d):
            low = name.lower()
            if low.startswith("cudart") and low.endswith(".dll"):
                return True
    except Exception:
        pass
    return False


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

    # "自动"的优先顺序：Vulkan > CUDA > HIP > CPU
    # Vulkan 版自带运行库、NVIDIA/AMD/Intel 都能用，最不容易翻车；
    # CUDA 版需要额外的 cudart DLL，放不平就会静默退回 CPU，所以排在后面。
    if "vulkan" in backends and has_gpu:
        recommended = "vulkan"
    elif "cuda" in backends and any(g.get("compute") for g in gpus):
        recommended = "cuda"
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
    if "cuda" in backends and not _cuda_runtime_ok(backends["cuda"]):
        notes.append("CUDA 版缺少 cudart 运行库，启动后会退回 CPU；先用 Vulkan 或补上 cudart DLL。")
    if tensor_core and "cuda" not in backends:
        notes.append("显卡支持张量核心，但需要 CUDA 版 llama.cpp 才能用上。")

    return {
        "backends": backends,
        "gpus": gpus,
        "tensor_core": tensor_core,
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

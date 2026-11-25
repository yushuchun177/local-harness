# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller 打包配置 —— 单文件 exe（绿色版，一个文件就够）。

和 build_gui.spec 的区别：这个把 _internal、llama\\ 全部塞进 exe，
运行时解包到临时目录（sys._MEIPASS）。config.json 和 chats\\ 仍然落在
exe 旁边，所以换电脑照样是一个文件夹拷走。

用法：

    pyinstaller build_onefile.spec --noconfirm --distpath distone

产物约 48MB，只含程序本体与 llama.cpp 运行文件。**不打包任何模型权重**：
用户自行下载 .gguf 放到 exe 旁边的 model\\ 目录，或用界面里的「导入」选文件夹。
这是项目的硬性约定 —— 发布版本永远不附带模型。

环境变量 LOCALCHAT_SPLASH=0 可以关掉启动画面（默认带）。
"""

import os

ROOT = os.getcwd()


def _pick_llama_dir():
    """优先用 tools/pack.py 精简过的那份 llama（26 个文件），省 25MB 体积。"""
    for rel in (os.path.join("pack", "local-harness-1.2.0", "llama"), "llama"):
        p = os.path.join(ROOT, rel)
        if os.path.isdir(p) and os.path.isfile(os.path.join(p, "llama-cli.exe")):
            return p
    raise SystemExit("找不到 llama 目录（llama-cli.exe）")


LLAMA_DIR = _pick_llama_dir()
WANT_SPLASH = os.environ.get("LOCALCHAT_SPLASH", "1") == "1"
SPLASH_PNG = os.path.join(ROOT, "assets", "splash.png")

EXCLUDES = [
    "unittest", "doctest", "pydoc", "pdb", "bdb",
    "test", "idlelib", "turtledemo", "turtle",
    "setuptools", "pip", "pkg_resources", "distutils", "ensurepip", "venv",
    "numpy", "pandas", "matplotlib", "PIL", "scipy",
    "sqlite3", "dbm", "shelve", "lib2to3",
    "curses", "wsgiref", "cgi", "cgitb",
    "asyncio", "concurrent", "multiprocessing",
    "ssl", "socketserver", "http.server", "http.client",
    "xmlrpc", "xml.dom", "xml.etree", "xml.parsers",
    "logging.handlers", "logging.config",
]

# llama.cpp 运行文件：原样塞进 exe 的 llama\ 目录（不走 binaries，避免依赖扫描）
extra = []
for name in sorted(os.listdir(LLAMA_DIR)):
    src = os.path.join(LLAMA_DIR, name)
    if os.path.isfile(src):
        extra.append((src, os.path.join("llama")))

a = Analysis(
    ["main_gui.py"],
    pathex=[],
    binaries=[],
    datas=extra,
    hiddenimports=["tkinter", "tkinter.ttk", "tkinter.messagebox",
                   "tkinter.simpledialog", "tkinter.filedialog"],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=EXCLUDES,
    noarchive=False,
    optimize=1,
)

pyz = PYZ(a.pure)

if WANT_SPLASH and os.path.isfile(SPLASH_PNG):
    splash = Splash(
        SPLASH_PNG,
        binaries=a.binaries,
        datas=a.datas,
        text_pos=(24, 250),
        text_size=10,
        text_color="#9ca3af",
        text_default="正在启动，第一次打开要先解压，请稍候…",
        minify_script=True,
        always_on_top=True,
    )
else:
    splash = None

# 单文件：把 binaries/datas 直接交给 EXE，不建 COLLECT
exe_args = [pyz, a.scripts, a.binaries, a.datas]
if splash is not None:
    exe_args.append(splash)
exe_args.append([])

exe = EXE(
    *exe_args,
    name="local-harness",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon="assets/app.ico",
    version="version_gui.txt",
)

# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller 打包配置 —— 图形界面版（local-harness Desktop）。

产物是绿色目录：dist\\local-harness桌面版\\
    local-harness.exe      主程序（GUI，双击直接开窗口）
    _internal\\       运行时（含 tcl/tk）
    llama\\           llama.cpp 主程序与 DLL（自己放）
    model\\           所有 .gguf 模型（自己放）

llama.cpp 和模型都不打进 exe：
  · 模型动辄几 GB，打包进去会变成巨型 exe
  · 换模型时直接替换文件即可
  · exe 本体只有几 MB

注意：GUI 版依赖 tkinter，excludes 里绝不能排除 tkinter/tcl/tk。
PyInstaller 的 hook-tkinter 会自动把 tcl8.6/tk8.6 收进 _internal。

用法（在 localchat 目录下）：
    pyinstaller build_gui.spec --noconfirm
"""

# GUI 版只排除明确用不到的大件，保留 tkinter/tcl/tk
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


a = Analysis(
    ["main_gui.py"],
    pathex=[],
    binaries=[],
    datas=[],
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

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="local-harness",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,             # GUI：不弹黑色命令行窗口
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon="assets/app.ico",
    version="version_gui.txt",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="local-harness",
)

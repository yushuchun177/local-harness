# 插件开发说明（Local-Harness · Godot 版）

每个插件是一个**独立的 GitHub 仓库**，主程序不内置任何插件，靠
「设置 → 插件管理」从 `localharness-plugins` 的 `index.json` 拉列表，
再从各插件自己的仓库下载 zip，解压到 `user://plugins/<id>/` 并热加载。

## 目录结构

```
<插件目录>/
├── manifest.json     清单
└── main.gd           extends Node，实现 run(tool, args) -> {ok, output}
```

## manifest.json

```json
{
  "id": "terminal",
  "name": "终端",
  "name_en": "Terminal",
  "version": "0.1.0",
  "description": "一句话说明",
  "description_en": "One line",
  "author": "yushuchun177",
  "tools": [
    {
      "name": "terminal_run",
      "description": "给模型看的说明，越具体越好",
      "params": {"command": "string，要执行的命令"},
      "dangerous": true
    }
  ]
}
```

`id` 决定安装目录名，务必和仓库名后缀一致（`localharness-plugin-<id>`）。

## main.gd

```gdscript
extends Node

func run(tool: String, args: Dictionary) -> Dictionary:
    match tool:
        "echo":
            return {"ok": true, "output": str(args.get("text", ""))}
    return {"ok": false, "output": "未知工具：%s" % tool}
```

- 返回 `{"ok": bool, "output": String}`，`output` 会作为工具结果喂回模型（建议 < 8000 字）
- 插件是 `Node`，会被 `add_child` 到 `Plugins` 单例下，可以放自己的状态变量

## 三条硬性注意（踩过的坑）

1. **别直接写 `App` / `I18N` 这些自动加载名**。插件是从 `user://` 动态加载的，
   编译期解析不到全局单例，会报 `Identifier not found: App`。要用运行时取：

   ```gdscript
   func _app() -> Node:
       var ml := Engine.get_main_loop()
       return ml.root.get_node_or_null("/root/App") if ml else null
   ```

2. **显式写类型**。本工程把 GDScript 的"从 Variant 推断类型"警告当作错误，
   `var x := a if cond else b`、`var n := max(0, y)` 这种三元/内建函数会直接编译失败：

   ```gdscript
   var pct: float = 0.0 if ctx <= 0 else float(used) / float(ctx) * 100.0
   var cut: int = max(0, msgs.size() - keep * 2)
   ```

3. **字符串里别再套双引号写 lambda**：`"".join(msgs.map(func(m): return str(m.get("content", ""))))`
   会因为内层 `"` 提前结束字符串。用循环拼。

## 调用协议（为什么任意模型都能用）

主程序把所有已装插件的工具写进系统提示，模型要调用时输出：

```
```tool
{"name":"terminal_run","args":{"command":"dir"}}
```
```

宿主解析、执行、把结果作为下一轮 `user` 消息喂回去，最多 `工具轮次` 步
（设置里可调，0 = 关闭）。这样不依赖模型的 function calling 支持。

## 发布

```bash
python tools/publish_plugins.py
```

扫描 `lh-plugins-src/*/manifest.json`，逐个建仓库、写文件，最后重建
`localharness-plugins/index.json`。索引优先走 jsDelivr（raw.githubusercontent
有几分钟 CDN 缓存，会把新插件挡住）。
## 中文优先（Windows 上的三个必踩坑）

1. **cmd 的命令行是 GBK**：把含中文的命令直接交给 `cmd.exe /c`，中文会先被 GBK 解码坏掉。
   做法是把命令写进 **UTF-16LE + BOM 的 .ps1**，由 PowerShell 转交给 cmd（`chcp 65001` 打头），
   输出再写成 UTF-8 文件读回来。
2. **PowerShell 5.1 按 ANSI 读无 BOM 的 .ps1**：反引号和引号会被吃掉，WinRT 调用直接报
   “找不到路径/类型”。所有 .ps1 一律 UTF-16LE + BOM。
3. **网页编码**：百度/新浪这类是 GB18030，用 `WebClient` 先探测 `charset=` 再决定解码，
   否则抓回来全是乱码；搜索优先 DuckDuckGo，不通自动换 Bing 中国站。

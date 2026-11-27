# 插件 SDK —— 给插件作者的全部自由度

Local-Harness（Godot 版）的插件就是一个目录，里面几个文件，**主程序不认识你的业务**，
只提供扩展点和积木。你能自定义到什么程度，看下面。

```
plugins/<id>/
├── manifest.json   清单：元信息 / 设置项 / 命令 / 工具
├── main.gd         extends Node：工具实现、命令实现、生命周期钩子
├── ui.gd           extends VBoxContainer：这个插件自己的设置界面（想怎么排就怎么排）
└── README.md       使用说明（会渲染在设置页里，支持 Markdown + 表格 + 图片 + 公式）
```

---

## 1. manifest.json

```json
{
  "id": "terminal",
  "name": "终端",
  "name_en": "Terminal",
  "version": "0.1.0",
  "description": "一句话说明",
  "description_en": "One line",
  "author": "yushuchun177",
  "homepage": "https://github.com/you/repo",

  "requires": { "os": "Windows 10+", "deps": ["PowerShell"],
                "disk": "< 1 MB", "memory": "约 10 MB", "network": false },

  "settings": [
    { "key": "timeout", "label": "默认超时（秒）", "type": "int",
      "default": 30, "min": 1, "max": 600, "unit": "秒",
      "help": "命令超过这个时间会被强制结束" }
  ],

  "commands": [
    { "name": "sh", "description": "执行一条命令", "usage": "/sh dir" }
  ],

  "tools": [
    { "name": "terminal_run", "description": "给模型看的说明",
      "level": "danger", "needs": ["启动进程", "读写文件"],
      "dangerous": true,
      "params": { "command": "string，要执行的命令" } }
  ]
}
```

`level` 决定它在设置页里落到哪一组：

| level | 界面分组 | 含义 |
| --- | --- | --- |
| `read` | 🟢 只读能力 | 不会改动任何东西 |
| `act` | 🟡 会产生操作 | 会读写、联网、占用设备 |
| `danger` | 🔴 高危能力 | 会操作系统，建议只开需要的 |

`needs` 会显示成「需要：屏幕 / 键盘 / 联网」的小标签，让用户知道代价。

---

## 2. main.gd —— 工具、命令、钩子

```gdscript
extends Node

# ① 工具：模型调用
func run(tool: String, args: Dictionary) -> Dictionary:
    match tool:
        "echo":
            return {"ok": true, "output": str(args.get("text", ""))}
    return {"ok": false, "output": "未知工具"}

# ② 斜杠命令：用户在输入框打 /name 参数
func on_command(cmd: String, args: String) -> Dictionary:
    return run("echo", {"text": args})

# ③ 生命周期 / 钩子（都可选）
func on_user_message(text: String) -> String:
    # 返回非空字符串时，会作为提示附加到这一轮上下文
    return ""

func on_turn_end(reply: String) -> void:
    # 一轮回答结束（可以记日志、发通知、写文件）
    pass
```

### 读自己的设置

```gdscript
func _pref(key: String, def):
    var ml := Engine.get_main_loop()
    var prefs = ml.root.get_node_or_null("/root/PluginPrefs")
    return prefs.get_value("你的插件id", key, def) if prefs != null else def
```

### 用主程序的能力

```gdscript
var app = Engine.get_main_loop().root.get_node_or_null("/root/App")
app.current_model        # 当前模型路径
app.chats                # 所有会话
app.save_current()       # 保存当前会话
app.PORT                 # 本地 llama-server 端口（可以直接 curl 它）
```

**注意**：插件是运行时从 `user://` 加载的，直接写 `App` / `PluginUI` 这类自动加载名会在
编译期报「Identifier not found」。一律走 `/root/xxx`。

---

## 3. ui.gd —— 你自己的设置界面

```gdscript
extends VBoxContainer

func build(plugin_id: String) -> void:
    add_theme_constant_override("separation", 12)
    add_child(PluginUI.plugin_header(plugin_id))      # 名称/版本/作者/仓库/启用数
    add_child(PluginUI.overview(plugin_id))           # 平台/依赖/占用/联网/工具数
    add_child(PluginUI.data_card("我存的东西", "存在 xxx", ["列1", "列2"], rows, "空状态"))
    add_child(PluginUI.command_section(plugin_id))    # 你提供的 /命令
    add_child(PluginUI.settings_section(plugin_id))   # manifest 里的 settings 自动渲染
    add_child(PluginUI.permissions_section(plugin_id))# 工具权限（三级分组）
    add_child(PluginUI.doc_section(plugin_id))        # README
```

这些都是**积木**，可以只用其中几个、可以自己用 Godot 原生控件随便画——整个页面就是你的
Control 树，主程序只负责把它挂到窗口里。

### 可用的积木（PluginUI）

| 方法 | 用途 |
| --- | --- |
| `plugin_header(id)` | 标题行：描述 / 作者 / 版本 / x/y 能力已开启 / 仓库按钮 |
| `overview(id)` | 概览卡：平台、依赖、占用空间、内存、联网、工具数 |
| `data_card(title, note, headers, rows, empty_text)` | **数据表**：真表格，带表头/斑马纹；用来展示“我存了什么、存在哪” |
| `settings_section(id)` | 按 manifest settings 生成控件（带默认值/范围/单位/恢复默认） |
| `permissions_section(id)` | 工具权限，按 read/act/danger 分组 + 需要什么 |
| `command_section(id)` | 列出你的 /命令 |
| `doc_section(id)` | README，支持 Markdown、表格、图片、公式 |
| `section(text)` / `hint(text)` / `label(text,size,color)` | 文字 |
| `int_field/str_field/bool_field(...)` | 单个设置项（自定义布局时用） |
| `perm_row(tool,label,desc,danger)` | 单个权限开关 |

---

## 4. 渲染能力（README、工具输出、聊天都支持）

| 语法 | 效果 |
| --- | --- |
| `**加粗**` `*斜体*` | 加粗 / 斜体（真加粗字体） |
| `` `代码` ``、```` ``` ```` 代码块 | 等宽 + 深色底 |
| `# 标题` | 分级标题 |
| `- 列表` / `1. 列表` | 缩进列表 |
| `> 引用` | 左侧竖线变淡 |
| `\| a \| b \|` + 分隔行 | **真表格**（表头底色 + 斑马纹 + 单元格边框） |
| `[文字](url)` / 裸链接 | 蓝色可点 |
| `![说明](C:/x.png)` 或一行图片路径 | **内嵌缩略图**，点开用系统看图 |
| `$E=mc^2$` | 行内公式（上标/下标/希腊字母） |
| `$$\frac{a}{b}$$` | 独立公式：真分数（上下结构 + 分数线）、根号 |

---

## 5. 自由度清单

- **界面**：整页自己画，想加标签页、图表、输入框都行
- **命令**：`/xxx` 直接跑，不经过模型
- **工具**：任意数量、任意参数，模型按提示词协议调用
- **数据**：自己决定存什么（`user://` 下随便写），并能在设置页里列出来
- **权限**：每个工具独立开关，主程序负责从提示词里剔除并拒绝调用
- **钩子**：`on_user_message` / `on_turn_end` / `on_load` / `on_unload`
- **复用主程序**：会话、模型、端口、设置、插件注册表都能拿

---

## 6. 发布

```bash
python tools/publish_plugins.py
```

扫描 `lh-plugins-src/*/manifest.json`，逐个建仓库、写 `manifest.json` / `main.gd` /
`ui.gd` / `README.md`，最后重建 `localharness-plugins/index.json`。

用户在主程序「设置 → 插件管理」里点安装，就会从你自己的仓库下载 zip、解压到
`user://plugins/<id>/` 并热加载。索引优先读 `raw.githubusercontent.com`（带时间戳绕缓存），
失败再走 gh-proxy / jsDelivr。

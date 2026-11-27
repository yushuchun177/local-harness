extends Node
## Plugins —— 插件宿主。
##
## 每个插件是一个独立目录（可以单独发布成 GitHub 仓库），结构固定：
##   <插件目录>/
##     manifest.json   {id,name,version,description,author,tools:[...]}
##     main.gd         extends Node；实现 run(tool_name, args) -> Dictionary
##
## 目录搜索顺序：user://plugins（用户自己装的，优先）、res://plugins（随程序打包）。
## 同名插件先出现的生效。
##
## 工具调用协议：为了让任意 GGUF 模型都能用（包括不会 function calling 的小模型），
## 统一走提示词协议——模型输出一行 ```tool {"name":"x","args":{...}}```，
## 宿主解析后执行，把结果作为下一轮上下文喂回去。

signal tools_changed

const SEARCH_DIRS := ["user://plugins", "res://plugins"]

var loaded: Array = []          # [{manifest, node, dir}]


func _ready() -> void:
	load_all()


func load_all() -> void:
	for p in loaded:
		if is_instance_valid(p["node"]):
			p["node"].queue_free()
	loaded.clear()
	for base in SEARCH_DIRS:
		_scan(base)
	tools_changed.emit()


func _scan(base: String) -> void:
	var d := DirAccess.open(base)
	if d == null:
		return
	d.list_dir_begin()
	var sub := d.get_next()
	while sub != "":
		if d.current_is_dir():
			_load_one(base.path_join(sub), sub)
		sub = d.get_next()
	d.list_dir_end()


func _load_one(dir: String, id_hint: String) -> void:
	var mpath := dir.path_join("manifest.json")
	if not FileAccess.file_exists(mpath):
		return
	var mf := FileAccess.open(mpath, FileAccess.READ)
	if mf == null:
		return
	var parsed = JSON.parse_string(mf.get_as_text())
	if not (parsed is Dictionary):
		push_warning("插件清单解析失败：%s" % mpath)
		return
	for p in loaded:
		if str(p["manifest"].get("id", "")) == str(parsed.get("id", id_hint)):
			return
	var spath := dir.path_join("main.gd")
	# 打包成 exe 后脚本是 .remap，FileAccess 看不到，用 ResourceLoader 判断
	var exists := FileAccess.file_exists(spath) or ResourceLoader.exists(spath)
	if not exists:
		push_warning("插件缺少 main.gd：%s" % dir)
		return
	var script: Script = load(spath)
	if script == null or not script.can_instantiate():
		push_warning("插件脚本无法实例化（多半是语法错误）：%s" % spath)
		return
	var node: Node = script.new()
	node.name = "plugin_" + str(parsed.get("id", id_hint))
	if not node.has_method("run"):
		push_warning("插件没有 run()：%s" % dir)
		node.queue_free()
		return
	add_child(node)
	loaded.append({"manifest": parsed, "node": node, "dir": dir})


# ---------------------------------------------------------------- 工具
func tools() -> Array:
	var out: Array = []
	for p in loaded:
		var m: Dictionary = p["manifest"]
		for t in m.get("tools", []):
			if not PluginPrefs.tool_enabled(str(t.get("name", ""))):
				continue
			var item: Dictionary = t.duplicate(true)
			item["plugin"] = str(m.get("id", ""))
			item["plugin_name"] = str(m.get("name", m.get("id", "")))
			out.append(item)
	return out


## 某个插件的工具（不受权限开关影响，详情页要用它列开关）
func tools_of(plugin_id: String) -> Array:
	for p in loaded:
		if str(p["manifest"].get("id", "")) == plugin_id:
			var out: Array = []
			for t in p["manifest"].get("tools", []):
				var item: Dictionary = t.duplicate(true)
				item["plugin"] = plugin_id
				out.append(item)
			return out
	return []


func find_plugin(plugin_id: String) -> Dictionary:
	for p in loaded:
		if str(p["manifest"].get("id", "")) == plugin_id:
			return p
	return {}


## 插件的使用说明（安装目录里的 README.md）
func readme_of(plugin_id: String) -> String:
	var p := find_plugin(plugin_id)
	if p.is_empty():
		return ""
	var path := str(p["dir"]).path_join("README.md")
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


## 插件可配置项（manifest 里的 settings 数组）
func settings_of(plugin_id: String) -> Array:
	var p := find_plugin(plugin_id)
	if p.is_empty():
		return []
	return p["manifest"].get("settings", [])


func find_tool(name: String) -> Dictionary:
	for p in loaded:
		for t in p["manifest"].get("tools", []):
			if str(t.get("name", "")) == name:
				return {"plugin": p, "tool": t}
	return {}


func invoke(name: String, args: Dictionary) -> Dictionary:
	if not PluginPrefs.tool_enabled(name):
		return {"ok": false, "output": "工具 %s 已被用户在插件权限里关闭" % name}
	var hit := find_tool(name)
	if hit.is_empty():
		return {"ok": false, "output": "没有这个工具：%s" % name}
	var node: Node = hit["plugin"]["node"]
	if not is_instance_valid(node):
		return {"ok": false, "output": "插件已卸载"}
	var res = node.run(name, args)
	if res is Dictionary:
		return res
	return {"ok": true, "output": str(res)}


# ---------------------------------------------------------------- 提示词
func describe_for_prompt() -> String:
	var ts := tools()
	if ts.is_empty():
		return ""
	var lines: PackedStringArray = []
	lines.append("你可以调用下面这些工具。需要工具时，只输出一行，格式严格为：")
	lines.append("```tool")
	lines.append("{\"name\": \"工具名\", \"args\": {\"参数\": \"值\"}}")
	lines.append("```")
	lines.append("不要在同一轮里既调用工具又写回答；拿到工具结果后再继续。")
	lines.append("")
	lines.append("可用工具：")
	for t in ts:
		var params: Dictionary = t.get("params", {})
		var ps: PackedStringArray = []
		for k in params.keys():
			ps.append("%s(%s)" % [k, params[k]])
		lines.append("- %s —— %s  参数：%s" % [t["name"], t.get("description", ""), ", ".join(ps)])
	return "\n".join(lines)


## 从模型输出里找出工具调用；没有就返回 {}
func extract_call(text: String) -> Dictionary:
	var t := text
	var idx := t.find("```tool")
	if idx >= 0:
		var start := t.find("\n", idx)
		if start < 0:
			return {}
		var end := t.find("```", start)
		if end < 0:
			return {}
		var body := t.substr(start + 1, end - start - 1).strip_edges()
		var obj = JSON.parse_string(body)
		if obj is Dictionary and obj.has("name"):
			return {"name": str(obj["name"]), "args": obj.get("args", {})}
	# 退化：整段就是一个 JSON 对象
	var s := t.strip_edges()
	if s.begins_with("{") and s.ends_with("}"):
		var o = JSON.parse_string(s)
		if o is Dictionary and o.has("name"):
			return {"name": str(o["name"]), "args": o.get("args", {})}
	return {}


## 把工具调用块从正文里去掉，只留给人看的文字
func strip_calls(text: String) -> String:
	var out := text
	while true:
		var idx := out.find("```tool")
		if idx < 0:
			break
		var end := out.find("```", idx + 7)
		if end < 0:
			break
		out = out.substr(0, idx) + out.substr(end + 3)
	return out.strip_edges()

# ---------------------------------------------------------------- 扩展点
## 全部插件的斜杠命令：[{plugin, name, description, usage}]
func commands() -> Array:
	var out: Array = []
	for p in loaded:
		var m: Dictionary = p["manifest"]
		for c in m.get("commands", []):
			var item: Dictionary = c.duplicate(true)
			item["plugin"] = str(m.get("id", ""))
			item["plugin_name"] = str(m.get("name", ""))
			out.append(item)
	return out


func find_command(name: String) -> Dictionary:
	var key := name.strip_edges().trim_prefix("/")
	for c in commands():
		if str(c.get("name", "")) == key:
			return c
	return {}


## 执行斜杠命令：插件实现 on_command(name, args) -> String 或 {ok, output}
func run_command(name: String, args: String) -> Dictionary:
	var c := find_command(name)
	if c.is_empty():
		return {"ok": false, "output": "没有这个命令：/%s" % name}
	if not PluginPrefs.tool_enabled("/" + str(c["name"])):
		return {"ok": false, "output": "命令 /%s 被你在权限里关掉了" % str(c["name"])}
	var p := find_plugin(str(c["plugin"]))
	if p.is_empty():
		return {"ok": false, "output": "插件未加载"}
	var node: Node = p["node"]
	if not node.has_method("on_command"):
		return {"ok": false, "output": "插件没有实现 on_command"}
	var res = node.call("on_command", str(c["name"]), args)
	if res is Dictionary:
		return res
	return {"ok": true, "output": str(res)}


## 广播一条用户消息给所有插件；返回需要追加到消息前面的提示（可空）
func notify_user_message(text: String) -> String:
	var notes: PackedStringArray = []
	for p in loaded:
		var node: Node = p["node"]
		if node.has_method("on_user_message"):
			var r = node.call("on_user_message", text)
			if r is String and str(r) != "":
				notes.append(str(r))
	return "\n".join(notes)


## 一轮回答结束的通知
func notify_turn_end(text: String) -> void:
	for p in loaded:
		var node: Node = p["node"]
		if node.has_method("on_turn_end"):
			node.call("on_turn_end", text)

# ---------------------------------------------------------------- 异步执行
## 在后台线程跑工具，主线程每帧检查，界面不会卡住。
## 大多数插件用的是 OS/FileAccess/Image/JSON，这些在子线程里是安全的。
var _async_result: Dictionary = {}
var _async_busy: bool = false


func invoke_async(name: String, args: Dictionary) -> Dictionary:
	if not PluginPrefs.tool_enabled(name):
		return {"ok": false, "output": "工具 %s 已被用户在插件权限里关闭" % name}
	var hit := find_tool(name)
	if hit.is_empty():
		return {"ok": false, "output": "没有这个工具：%s" % name}
	var node: Node = hit["plugin"]["node"]
	if not is_instance_valid(node):
		return {"ok": false, "output": "插件已卸载"}

	# 只有声明了 async 的慢工具才丢线程；纯内存操作的留在主线程
	# （它们要读 /root/App 这类场景树节点，子线程里不允许）
	var tool_meta: Dictionary = hit["tool"]
	if not bool(tool_meta.get("async", false)):
		return invoke(name, args)

	_async_result = {}
	var th := Thread.new()
	var callable := Callable(self, "_thread_run_tool").bind(node, name, args)
	if th.start(callable) != OK:
		th.wait_to_finish()
		return invoke(name, args)
	# 主线程轮询，期间界面照常刷新
	var t0 := Time.get_ticks_msec()
	var timeout_ms := 180000
	while th.is_alive():
		if Time.get_ticks_msec() - t0 > timeout_ms:
			th.wait_to_finish()
			return {"ok": false, "output": "工具执行超过 %d 秒，已放弃等待" % int(timeout_ms / 1000)}
		await get_tree().process_frame
	th.wait_to_finish()
	return _async_result.duplicate(true)


func _thread_run_tool(node: Node, name: String, args: Dictionary) -> void:
	var res = node.run(name, args)
	if res is Dictionary:
		_async_result = res
	else:
		_async_result = {"ok": true, "output": str(res)}

## 斜杠命令的后台版本（命令里可能调工具，比如 /shot 要截屏几秒）
func run_command_async(name: String, args: String) -> Dictionary:
	var c := find_command(name)
	if c.is_empty():
		return {"ok": false, "output": "没有这个命令：/%s" % name}
	if not PluginPrefs.tool_enabled("/" + str(c["name"])):
		return {"ok": false, "output": "命令 /%s 被你在权限里关掉了" % str(c["name"])}
	var p := find_plugin(str(c["plugin"]))
	if p.is_empty():
		return {"ok": false, "output": "插件未加载"}
	var node: Node = p["node"]
	if not node.has_method("on_command"):
		return {"ok": false, "output": "插件没有实现 on_command"}

	_async_result = {}
	var th := Thread.new()
	var callable := Callable(self, "_thread_run_command").bind(node, str(c["name"]), args)
	if th.start(callable) != OK:
		th.wait_to_finish()
		return run_command(name, args)
	var t0 := Time.get_ticks_msec()
	while th.is_alive():
		if Time.get_ticks_msec() - t0 > 180000:
			th.wait_to_finish()
			return {"ok": false, "output": "命令执行超时"}
		await get_tree().process_frame
	th.wait_to_finish()
	return _async_result.duplicate(true)


func _thread_run_command(node: Node, cmd: String, args: String) -> void:
	var res = node.call("on_command", cmd, args)
	if res is Dictionary:
		_async_result = res
	else:
		_async_result = {"ok": true, "output": str(res)}



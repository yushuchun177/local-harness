extends Node
## PluginPrefs —— 插件权限与设置（每个插件自己的开关和参数）。
##
## 存在 user://plugin_settings.json：
##   { "tools": { "terminal_run": true, ... },        # 工具级权限
##     "values": { "terminal": { "timeout": 30 } } }  # 插件自己的设置
##
## 约定：
##   - 工具权限默认 **开启**，只有用户明确关掉才写 false；
##   - 危险工具（manifest 里 "dangerous": true）在界面上标红，但仍然默认开，
##     因为用户装插件就是为了用它；关掉后既不出现在提示词里，调用也会被拒。
##   - 插件里通过 `/root/PluginPrefs`.get_value("自己id", "key", 默认值) 读设置。

const STORE := "user://plugin_settings.json"

var _data: Dictionary = {"tools": {}, "values": {}}


func _ready() -> void:
	_load()


func _load() -> void:
	var f := FileAccess.open(STORE, FileAccess.READ)
	if f == null:
		return
	var obj = JSON.parse_string(f.get_as_text())
	if obj is Dictionary:
		_data["tools"] = obj.get("tools", {})
		_data["values"] = obj.get("values", {})


func _save() -> void:
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data, "  "))


# ---------------------------------------------------------------- 权限
func tool_enabled(tool_name: String) -> bool:
	var t: Dictionary = _data.get("tools", {})
	if not t.has(tool_name):
		return true
	return bool(t[tool_name])


func set_tool_enabled(tool_name: String, on: bool) -> void:
	var t: Dictionary = _data.get("tools", {})
	t[tool_name] = on
	_data["tools"] = t
	_save()


## 某个插件下所有工具的开关状态
func plugin_tool_states(plugin_id: String) -> Dictionary:
	var out: Dictionary = {}
	if Plugins == null:
		return out
	for t in Plugins.tools_of(plugin_id):
		out[str(t.get("name", ""))] = tool_enabled(str(t.get("name", "")))
	return out


# ---------------------------------------------------------------- 设置值
func get_value(plugin_id: String, key: String, default_value = "") -> Variant:
	var v: Dictionary = _data.get("values", {})
	var pv: Dictionary = v.get(plugin_id, {})
	return pv.get(key, default_value)


func set_value(plugin_id: String, key: String, value) -> void:
	var v: Dictionary = _data.get("values", {})
	var pv: Dictionary = v.get(plugin_id, {})
	pv[key] = value
	v[plugin_id] = pv
	_data["values"] = v
	_save()


func reset_plugin(plugin_id: String) -> void:
	var v: Dictionary = _data.get("values", {})
	v.erase(plugin_id)
	_data["values"] = v
	_save()

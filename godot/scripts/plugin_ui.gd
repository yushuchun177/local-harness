extends Node
## PluginUI —— 插件设置界面的积木库（插件自己调、自己排版）。
##
## 目标：让每个插件的设置页都有"正经插件"的样子：
##   头部（名称/版本/作者/仓库/启用状态）
##   概览（平台 / 依赖 / 占用 / 联网 / 工具数）
##   行为参数（带默认值、范围、单位、说明、恢复默认）
##   能力权限（按 只读 / 会产生操作 / 高危 分组，标出需要什么系统能力）
##   使用说明（轻量 Markdown 渲染）
##
## 这些都是"积木"，插件的 ui.gd 决定用哪些、怎么排。

const PANEL := Color("#141821")
const PANEL2 := Color("#1b202b")
const LINE := Color("#232936")
const TEXT := Color("#e6eaf2")
const DIM := Color("#93a0b4")
const FAINT := Color("#5d6a7e")
const ACCENT := Color("#5b8def")
const WARN := Color("#e0a458")
const DANGER := Color("#e06c75")
const OK := Color("#57c08a")

var _font: FontFile


func _ready() -> void:
	for p in ["C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf"]:
		if FileAccess.file_exists(p):
			_font = FontFile.new()
			_font.load_dynamic_font(p)
			return


func face(size: int, bold := false) -> Font:
	if _font == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.variation_embolden = 0.6 if bold else 0.0
	return fv


func style(bg: Color, radius := 8, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func label(text: String, size := 12, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", face(size))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func hint(text: String) -> Label:
	var l := label(text, 10, FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func section(text: String, color := TEXT) -> Label:
	var l := label(text, 13, color)
	return l


func _card(bg := PANEL) -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", style(bg, 10, LINE))
	return c


# ---------------------------------------------------------------- 头部
func plugin_header(plugin_id: String) -> Control:
	var p: Dictionary = Plugins.find_plugin(plugin_id)
	var m: Dictionary = p.get("manifest", {}) if not p.is_empty() else {}
	var tools_list: Array = Plugins.tools_of(plugin_id)
	var on := 0
	for t in tools_list:
		if PluginPrefs.tool_enabled(str(t.get("name", ""))):
			on += 1

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var desc := label(str(m.get("description", "")), 11, DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(300, 0)
	left.add_child(desc)
	left.add_child(label("作者 %s  ·  v%s" % [str(m.get("author", "?")), str(m.get("version", "?"))], 10, FAINT))
	row.add_child(left)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.add_child(label("%d/%d 项能力已开启" % [on, tools_list.size()], 11,
		OK if on > 0 else DANGER))
	row.add_child(right)

	if str(m.get("homepage", "")) != "":
		var repo := Button.new()
		repo.text = "仓库 ↗"
		repo.focus_mode = Control.FOCUS_NONE
		repo.custom_minimum_size = Vector2(76, 26)
		repo.add_theme_font_override("font", face(11))
		repo.add_theme_font_size_override("font_size", 11)
		repo.add_theme_stylebox_override("normal", style(PANEL2, 8, LINE))
		repo.add_theme_stylebox_override("hover", style(Color("#232c3b"), 8, ACCENT))
		repo.add_theme_color_override("font_color", DIM)
		var url := str(m.get("homepage", ""))
		repo.pressed.connect(func(): OS.shell_open(url))
		right.add_child(repo)

	return row


# ---------------------------------------------------------------- 概览
func overview(plugin_id: String) -> Control:
	var p: Dictionary = Plugins.find_plugin(plugin_id)
	var m: Dictionary = p.get("manifest", {}) if not p.is_empty() else {}
	var req: Dictionary = m.get("requires", {})
	var tools_list: Array = Plugins.tools_of(plugin_id)

	var card := _card()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(section("概览"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	var rows := [
		["平台", str(req.get("os", "全平台"))],
		["依赖", ", ".join(req.get("deps", [])) if not req.get("deps", []).is_empty() else "无"],
		["占用空间", str(req.get("disk", "?"))],
		["内存", str(req.get("memory", "?"))],
		["联网", "需要联网" if bool(req.get("network", false)) else "纯本地"],
		["工具数", "%d 个（%d 个可用）" % [tools_list.size(), _enabled_count(tools_list)]],
	]
	for r in rows:
		grid.add_child(label(str(r[0]), 11, FAINT))
		grid.add_child(label(str(r[1]), 11, DIM))
	v.add_child(grid)
	return card


func _enabled_count(tools_list: Array) -> int:
	var n := 0
	for t in tools_list:
		if PluginPrefs.tool_enabled(str(t.get("name", ""))):
			n += 1
	return n


# ---------------------------------------------------------------- 行为参数
func settings_section(plugin_id: String) -> Control:
	var settings: Array = Plugins.settings_of(plugin_id)
	if settings.is_empty():
		return _card_with_text("行为参数", "这个插件没有可调参数，装上就能用。")
	var card := _card()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(section("行为参数"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var reset := Button.new()
	reset.text = "恢复默认"
	reset.focus_mode = Control.FOCUS_NONE
	reset.custom_minimum_size = Vector2(80, 24)
	reset.add_theme_font_override("font", face(10))
	reset.add_theme_font_size_override("font_size", 10)
	reset.add_theme_stylebox_override("normal", style(PANEL2, 7, LINE))
	reset.add_theme_stylebox_override("hover", style(Color("#232c3b"), 7, ACCENT))
	reset.add_theme_color_override("font_color", DIM)
	reset.pressed.connect(func():
		PluginPrefs.reset_plugin(plugin_id)
		# 重新构建整个设置窗
		var root: Node = Engine.get_main_loop().root.get_node_or_null("/root/Main")
		if root != null and root.has_method("_reopen_plugin_panel"):
			root.call("_reopen_plugin_panel", plugin_id))
	head.add_child(reset)
	v.add_child(head)

	for item in settings:
		v.add_child(_setting_row(plugin_id, item))
	return card


func _card_with_text(title: String, text: String) -> Control:
	var card := _card()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	v.add_child(section(title))
	v.add_child(hint(text))
	return card


func _setting_row(plugin_id: String, item: Dictionary) -> Control:
	var key := str(item.get("key", ""))
	var typ := str(item.get("type", "string"))
	var default_value = item.get("default", "")
	var unit := str(item.get("unit", ""))
	var mn = item.get("min", 0)
	var mx = item.get("max", 1000000)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lab := label(str(item.get("label", key)), 12, TEXT)
	lab.custom_minimum_size = Vector2(180, 0)
	row.add_child(lab)

	if typ == "int":
		var sp := SpinBox.new()
		sp.min_value = float(mn)
		sp.max_value = float(mx)
		sp.step = 1
		sp.value = float(PluginPrefs.get_value(plugin_id, key, default_value))
		sp.custom_minimum_size = Vector2(120, 28)
		sp.value_changed.connect(func(v: float):
			PluginPrefs.set_value(plugin_id, key, int(v)))
		row.add_child(sp)
		row.add_child(label(("默认 %d%s" % [int(default_value), unit]), 10, FAINT))
		row.add_child(label(("范围 %d–%d" % [int(mn), int(mx)]), 10, FAINT))
	elif typ == "bool":
		var cb := CheckBox.new()
		cb.button_pressed = bool(PluginPrefs.get_value(plugin_id, key, default_value))
		cb.toggled.connect(func(on: bool):
			PluginPrefs.set_value(plugin_id, key, on))
		row.add_child(cb)
	else:
		var ed := LineEdit.new()
		ed.text = str(PluginPrefs.get_value(plugin_id, key, default_value))
		ed.placeholder_text = str(item.get("placeholder", ""))
		ed.add_theme_font_override("font", face(12))
		ed.add_theme_font_size_override("font_size", 12)
		ed.add_theme_stylebox_override("normal", style(PANEL2, 8, LINE))
		ed.add_theme_color_override("font_color", TEXT)
		ed.add_theme_color_override("font_placeholder_color", FAINT)
		ed.custom_minimum_size = Vector2(0, 28)
		ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ed.text_changed.connect(func(t: String):
			PluginPrefs.set_value(plugin_id, key, t))
		row.add_child(ed)
		if str(default_value) != "":
			row.add_child(label("默认 %s" % str(default_value), 10, FAINT))
	box.add_child(row)
	var help := str(item.get("help", ""))
	if help != "":
		box.add_child(hint(help))
	return box


# ---------------------------------------------------------------- 能力权限
const LEVEL_TITLE := {
	"read": "只读能力（不会改动任何东西）",
	"act": "会产生操作（会读/写、会联网、会占用设备）",
	"danger": "高危能力（会操作你的系统，建议只开需要的）",
}
const LEVEL_COLOR := {"read": OK, "act": WARN, "danger": DANGER}
const LEVEL_ORDER := ["read", "act", "danger"]


func permissions_section(plugin_id: String) -> Control:
	var card := _card()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	v.add_child(section("能力与权限"))
	v.add_child(hint("关掉的工具不会出现在模型提示词里，调用会被主程序拒绝；改动立即生效"))

	var tools_list: Array = Plugins.tools_of(plugin_id)
	for lv in LEVEL_ORDER:
		var group: Array = []
		for t in tools_list:
			if str(t.get("level", "act")) == lv:
				group.append(t)
		if group.is_empty():
			continue
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		head.add_child(label("●", 10, LEVEL_COLOR[lv]))
		head.add_child(label(LEVEL_TITLE[lv], 11, LEVEL_COLOR[lv]))
		v.add_child(head)
		for t in group:
			v.add_child(_tool_row(t))
	return card


func _tool_row(t: Dictionary) -> Control:
	var tname := str(t.get("name", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cb := CheckBox.new()
	cb.button_pressed = PluginPrefs.tool_enabled(tname)
	cb.toggled.connect(func(on: bool):
		PluginPrefs.set_tool_enabled(tname, on))
	row.add_child(cb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(label(tname, 12, TEXT))
	col.add_child(hint(str(t.get("description", ""))))
	var needs: Array = t.get("needs", [])
	if not needs.is_empty():
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation", 4)
		chips.add_child(label("需要：", 10, FAINT))
		for n in needs:
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", style(Color("#1f2530"), 6))
			chip.add_child(label(str(n), 9, DIM))
			chips.add_child(chip)
		col.add_child(chips)
	row.add_child(col)
	return row


# ---------------------------------------------------------------- 说明文档
func doc_section(plugin_id: String) -> Control:
	var card := _card()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	v.add_child(section("使用说明"))
	var doc := RichTextLabel.new()
	doc.bbcode_enabled = true
	doc.fit_content = true
	doc.scroll_active = false
	doc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	doc.custom_minimum_size = Vector2(0, 40)
	doc.add_theme_font_override("normal_font", face(11))
	doc.add_theme_font_override("bold_font", face(11, true))
	doc.add_theme_font_override("mono_font", face(10))
	doc.add_theme_font_override("italics_font", face(11))
	doc.add_theme_font_size_override("normal_font_size", 11)
	doc.add_theme_font_size_override("bold_font_size", 11)
	doc.add_theme_font_size_override("mono_font_size", 10)
	doc.add_theme_font_size_override("italics_font_size", 11)
	doc.add_theme_color_override("default_color", Color(0.74, 0.78, 0.86))
	var text := Plugins.readme_of(plugin_id)
	doc.text = MD.to_bb(text) if text.strip_edges() != "" else "（这个插件没有附带说明文件）"
	doc.meta_clicked.connect(func(url: String): OS.shell_open(url))
	v.add_child(doc)
	return card


## 很轻的 Markdown → BBCode：标题、加粗、行内代码、列表
func md_to_bb(md: String) -> String:
	var out: PackedStringArray = []
	for raw in md.split("\n"):
		var line := raw.strip_edges(false, true)
		if line.begins_with("### "):
			out.append("[font_size=12][b]%s[/b][/font_size]" % _inline(line.substr(4)))
		elif line.begins_with("## "):
			out.append("[font_size=13][b]%s[/b][/font_size]" % _inline(line.substr(3)))
		elif line.begins_with("# "):
			out.append("[font_size=15][b]%s[/b][/font_size]" % _inline(line.substr(2)))
		elif line.begins_with("- "):
			out.append("    • %s" % _inline(line.substr(2)))
		elif line.begins_with("  - "):
			out.append("        · %s" % _inline(line.substr(4)))
		elif line.begins_with("```"):
			continue
		else:
			out.append(_inline(line))
	return "\n".join(out)


func _inline(s: String) -> String:
	var t := s
	var re_b := RegEx.new()
	re_b.compile("\\*\\*([^*]+)\\*\\*")
	t = re_b.sub(t, "[b]$1[/b]", true)
	var re_c := RegEx.new()
	re_c.compile("`([^`]+)`")
	t = re_c.sub(t, "[code]$1[/code]", true)
	return t


## 没有 ui.gd 的插件兜底
func fallback(plugin_id: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(hint("这个插件没有自带设置界面，下面是它的概览、权限和说明。"))
	v.add_child(overview(plugin_id))
	v.add_child(permissions_section(plugin_id))
	v.add_child(doc_section(plugin_id))
	return v


# ---------------------------------------------------------------- 兼容旧接口
func title(text: String) -> Label:
	return label(text, 14, TEXT)


func section_old(text: String) -> Label:
	return section(text)


func int_field(plugin_id: String, key: String, label_text: String, default_value: int, help := "") -> Control:
	return _setting_row(plugin_id, {"key": key, "label": label_text, "type": "int",
		"default": default_value, "help": help})


func str_field(plugin_id: String, key: String, label_text: String, default_value: String, help := "") -> Control:
	return _setting_row(plugin_id, {"key": key, "label": label_text, "type": "string",
		"default": default_value, "help": help})


func bool_field(plugin_id: String, key: String, label_text: String, default_value: bool, help := "") -> Control:
	return _setting_row(plugin_id, {"key": key, "label": label_text, "type": "bool",
		"default": default_value, "help": help})


func perm_row(tool_name: String, label_text: String, desc: String, dangerous := false) -> Control:
	return _tool_row({"name": tool_name, "description": desc, "level": "danger" if dangerous else "act"})


func perm_section(plugin_id: String) -> Control:
	return permissions_section(plugin_id)


func readme_box(plugin_id: String) -> Control:
	return doc_section(plugin_id)

# ---------------------------------------------------------------- 数据卡片
## 展示插件存了什么：标题 + 存储位置 + 表格（或空状态）
func data_card(title: String, note: String, headers: Array, rows: Array, empty_text: String) -> Control:
	var card := _card()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(section(title))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(label("%d 条" % rows.size(), 10, FAINT))
	v.add_child(head)

	if note != "":
		v.add_child(hint(note))

	if rows.is_empty():
		var empty := label(empty_text, 11, FAINT)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(empty)
		return card

	var panel := PanelContainer.new()
	var st := style(Color("#12161e"), 8, LINE)
	st.content_margin_left = 0
	st.content_margin_right = 0
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", st)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(panel)

	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(grid)

	# 表头
	for h in headers:
		grid.add_child(_cell(str(h), true, 0))
	# 内容
	for ri in rows.size():
		var row: Array = rows[ri]
		for ci in headers.size():
			var text := str(row[ci]) if ci < row.size() else ""
			grid.add_child(_cell(text, false, ri))
	return card


func _cell(text: String, header: bool, row_index: int) -> Control:
	var cell := PanelContainer.new()
	var bg := Color("#1b2130") if header else (Color("#151a24") if row_index % 2 == 1 else Color("#12161e"))
	var cs := StyleBoxFlat.new()
	cs.bg_color = bg
	cs.set_corner_radius_all(0)
	cs.content_margin_left = 9
	cs.content_margin_right = 9
	cs.content_margin_top = 5
	cs.content_margin_bottom = 5
	cell.add_theme_stylebox_override("panel", cs)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := label(text, 10, TEXT if header else DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(90, 0)
	cell.add_child(l)
	return cell


# ---------------------------------------------------------------- 命令
## 列出这个插件提供的 /命令
func command_section(plugin_id: String) -> Control:
	var cmds: Array = []
	for c in Plugins.commands():
		if str(c.get("plugin", "")) == plugin_id:
			cmds.append(c)
	var card := _card()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(section("快捷命令"))
	if cmds.is_empty():
		v.add_child(hint("这个插件没有提供 /命令。"))
		return card
	v.add_child(hint("在输入框里打 /命令 就能直接用，不经过模型"))
	for c in cmds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var code := label("/" + str(c.get("name", "")), 12, Color("#7fb0ff"))
		code.custom_minimum_size = Vector2(120, 0)
		row.add_child(code)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(label(str(c.get("description", "")), 11, TEXT))
		var usage := str(c.get("usage", ""))
		if usage != "":
			col.add_child(hint(usage))
		row.add_child(col)
		v.add_child(row)
	return card

# ---------------------------------------------------------------- 便民控件
## 一个"大开关"：左边标题+说明，右边开关。给不懂参数的人用。
func big_toggle(plugin_id: String, key: String, title: String, desc: String, default_value: bool,
		on_change := Callable()) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(label(title, 13, TEXT))
	var d := hint(desc)
	col.add_child(d)
	row.add_child(col)

	var cb := CheckBox.new()
	cb.button_pressed = bool(PluginPrefs.get_value(plugin_id, key, default_value))
	cb.custom_minimum_size = Vector2(48, 0)
	cb.toggled.connect(func(on: bool):
		PluginPrefs.set_value(plugin_id, key, on)
		if on_change.is_valid():
			on_change.call(on))
	row.add_child(cb)
	return row


## 预设选择：给几个"人话选项"，不用填数字
func choice_row(plugin_id: String, key: String, title: String, options: Array,
		default_value: String, desc := "", on_change := Callable()) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(label(title, 13, TEXT))
	if desc != "":
		col.add_child(hint(desc))
	row.add_child(col)

	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(170, 30)
	ob.add_theme_font_override("font", face(12))
	ob.add_theme_font_size_override("font_size", 12)
	ob.add_theme_stylebox_override("normal", style(PANEL2, 8, LINE))
	ob.add_theme_color_override("font_color", TEXT)
	var cur := str(PluginPrefs.get_value(plugin_id, key, default_value))
	var sel := 0
	for i in options.size():
		var opt: Dictionary = options[i]
		ob.add_item(str(opt.get("label", opt.get("value", ""))))
		if str(opt.get("value", "")) == cur:
			sel = i
	ob.select(sel)
	ob.item_selected.connect(func(i: int):
		var v := str(options[i].get("value", ""))
		PluginPrefs.set_value(plugin_id, key, v)
		if on_change.is_valid():
			on_change.call(v))
	row.add_child(ob)
	return row


## 滑块：带当前值和单位，比 SpinBox 好懂
func slider_row(plugin_id: String, key: String, title: String, min_v: float, max_v: float,
		step: float, unit: String, default_value: float, desc := "") -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var l := label(title, 13, TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	var val := label("", 12, ACCENT)
	head.add_child(val)
	box.add_child(head)

	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step
	sl.custom_minimum_size = Vector2(0, 22)
	sl.value = float(PluginPrefs.get_value(plugin_id, key, default_value))
	sl.value_changed.connect(func(v: float):
		PluginPrefs.set_value(plugin_id, key, v)
		val.text = ("%d %s" % [int(v), unit]).strip_edges())
	val.text = ("%d %s" % [int(sl.value), unit]).strip_edges()
	box.add_child(sl)
	if desc != "":
		box.add_child(hint(desc))
	return box


## 一键操作：点一下就跑，结果直接显示在下面
func action_row(title: String, desc: String, button_text: String, callback: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(label(title, 13, TEXT))
	if desc != "":
		col.add_child(hint(desc))
	row.add_child(col)

	var out_label := label("", 11, DIM)
	out_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var b := Button.new()
	b.text = button_text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(110, 32)
	b.add_theme_font_override("font", face(12, true))
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_stylebox_override("normal", style(ACCENT, 8))
	b.add_theme_stylebox_override("hover", style(ACCENT.lightened(0.1), 8))
	b.add_theme_color_override("font_color", Color("#0b1220"))
	b.pressed.connect(func():
		b.disabled = true
		b.text = "执行中…"
		out_label.text = ""
		var res = await callback.call()
		b.disabled = false
		b.text = button_text
		if res is Dictionary:
			out_label.text = ("✓ " if res.get("ok", false) else "✗ ") + str(res.get("output", ""))
			out_label.add_theme_color_override("font_color", OK if res.get("ok", false) else DANGER)
		else:
			out_label.text = str(res))
	row.add_child(b)
	box.add_child(row)
	box.add_child(out_label)
	return box


## 状态数字条：一眼看出"现在什么情况"
func stats_row(items: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for it in items:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", style(PANEL2, 8, LINE))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		card.add_child(v)
		var value := label(str(it.get("value", "—")), 16, ACCENT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(value)
		var name := label(str(it.get("label", "")), 10, FAINT)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(name)
		row.add_child(card)
	return row


## 选文件（比如选一张图给识图插件）
func file_pick_row(title: String, desc: String, filters: PackedStringArray, on_pick: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(label(title, 13, TEXT))
	if desc != "":
		col.add_child(hint(desc))
	row.add_child(col)
	var path_label := label("（还没选）", 11, FAINT)
	var b := Button.new()
	b.text = "选择文件…"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(100, 30)
	b.add_theme_font_override("font", face(12))
	b.add_theme_stylebox_override("normal", style(PANEL2, 8, LINE))
	b.add_theme_color_override("font_color", TEXT)
	b.pressed.connect(func():
		var dlg := FileDialog.new()
		dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.filters = filters
		dlg.size = Vector2i(760, 520)
		add_child(dlg)
		dlg.file_selected.connect(func(p: String):
			path_label.text = p
			on_pick.call(p)
			dlg.queue_free())
		dlg.canceled.connect(func(): dlg.queue_free())
		dlg.popup_centered())
	row.add_child(b)
	row.add_child(path_label)
	box.add_child(row)
	return box

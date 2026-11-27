extends Control
## 主界面 —— 全部用代码搭建，方便统一改配色与间距。
##
## 布局：
##   ┌────────────┬──────────────────────────────────────────┐
##   │ 侧栏 264px │ 顶栏：模型 / 后端 / 状态                  │
##   │ 品牌       ├──────────────────────────────────────────┤
##   │ 新对话     │ 消息区（气泡）                            │
##   │ 搜索       │                                          │
##   │ 会话列表   ├──────────────────────────────────────────┤
##   │ 设置       │ 输入区：多行输入 + 发送                   │
##   └────────────┴──────────────────────────────────────────┘

const BG := Color("#0b0d12")
const PANEL := Color("#141821")
const PANEL2 := Color("#1b202b")
const LINE := Color("#232936")
const TEXT := Color("#e6eaf2")
const DIM := Color("#93a0b4")
const FAINT := Color("#5d6a7e")
const ACCENT := Color("#5b8def")
const USER_BG := Color("#22314b")
const AI_BG := Color("#171c25")
const DANGER := Color("#e05a5a")

var font_ui: FontFile
var font_bold: FontFile

var _msg_box: VBoxContainer
var _msg_scroll: ScrollContainer
var _composer: TextEdit
var _send_btn: Button
var _chat_list: VBoxContainer
var _search: LineEdit
var _model_btn: OptionButton
var _backend_chip: Label
var _status_lbl: Label
var _footer: Label
var _sidebar: PanelContainer
var _chat_title: Label
var _toggle_btn: Button
var _sidebar_open: bool = true

var _settings_layer: ColorRect
var _license_layer: ColorRect = null
var _stream_raw: String = ""
var _last_render_ms: int = 0
var _stream_col: VBoxContainer = null
var _stream_label: RichTextLabel = null
var _waiting: bool = false
var _agent_abort: bool = false
var _agent_running: bool = false


func _ready() -> void:
	_load_fonts()
	_build_ui()
	_connect_app()

	App.server_state.connect(_on_server_state)
	App.chat_delta.connect(_on_delta)
	App.chat_done.connect(_on_done)
	App.chat_failed.connect(_on_failed)

	_refresh_chat_list()
	if App.chats.is_empty():
		App.new_chat()
	_refresh_chat_list()
	_open_chat(0)
	_refresh_header()
	# 调试/自动化：-- --tool <工具名> 直接执行一个插件工具然后退出
	var serve_port := _requested_serve()
	if serve_port > 0:
		_run_serve_mode(serve_port)
		return
	var panel_pid := OS.get_environment("LH_PLUGIN_PANEL")
	if panel_pid != "":
		_open_plugin_panel.call_deferred(panel_pid)
	if OS.get_cmdline_user_args().has("--asynctest"):
		_run_asynctest()
		return
	var cli := OS.get_cmdline_user_args()
	if cli.size() >= 2 and cli[0] == "--cmd":
		var res := Plugins.run_command(cli[1], cli[2] if cli.size() > 2 else "")
		print("[cmd] /%s -> ok=%s" % [cli[1], res.get("ok", false)])
		print(str(res.get("output", "")))
		get_tree().quit(0)
		return
	if OS.get_cmdline_user_args().has("--bench"):
		_run_bench()
		return
	if OS.get_cmdline_user_args().has("--modeltest"):
		_run_modeltest()
		return
	if OS.get_cmdline_user_args().has("--mdtest"):
		_run_mdtest()
		return
	var tool_name := _requested_tool()
	if tool_name != "":
		_run_tool_and_quit(tool_name)
		return
	App.start_server()
	_composer.grab_focus()
	# 调试用：启动时直接打开设置面板
	if OS.get_environment("LH_OPEN_SETTINGS") == "1" \
			or FileAccess.file_exists(IO_MARKER):
		_open_settings.call_deferred()


## 用来做 UI 截图验证的标记文件（跑测试时创建，正常使用不存在）
const IO_MARKER := "res://.open_settings"


# ---------------------------------------------------------------- 字体
func _load_fonts() -> void:
	var candidates := [
		"C:/Windows/Fonts/msyh.ttc",
		"C:/Windows/Fonts/msyh.ttf",
		"C:/Windows/Fonts/simhei.ttf",
	]
	for p in candidates:
		if FileAccess.file_exists(p):
			font_ui = FontFile.new()
			font_ui.load_dynamic_font(p)
			break


func _f(size: int, bold := false) -> Font:
	var f: Font = font_ui
	if f == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = font_ui
	fv.variation_embolden = 0.6 if bold else 0.0
	fv.spacing_glyph = 0
	return fv


# ---------------------------------------------------------------- 基础控件
func _style(bg: Color, radius := 10, border := Color.TRANSPARENT, bw := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _label(text: String, size := 14, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _f(size))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _f(14, accent))
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 38)
	if accent:
		b.add_theme_stylebox_override("normal", _style(ACCENT, 9))
		b.add_theme_stylebox_override("hover", _style(ACCENT.lightened(0.08), 9))
		b.add_theme_stylebox_override("pressed", _style(ACCENT.darkened(0.12), 9))
		b.add_theme_color_override("font_color", Color("#0b1220"))
		b.add_theme_color_override("font_hover_color", Color("#0b1220"))
	else:
		b.add_theme_stylebox_override("normal", _style(PANEL2, 9, LINE))
		b.add_theme_stylebox_override("hover", _style(PANEL2.lightened(0.06), 9, LINE))
		b.add_theme_stylebox_override("pressed", _style(PANEL2.darkened(0.1), 9, LINE))
		b.add_theme_color_override("font_color", TEXT)
	return b


# ---------------------------------------------------------------- 布局
func _build_ui() -> void:
	_sidebar_open = bool(App.cfg.get("sidebar_open", true))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bgroot := ColorRect.new()
	bgroot.color = BG
	bgroot.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bgroot)

	# 整体留一圈内边距，让侧栏成为一张浮起来的圆角卡片
	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 12)
	outer.add_theme_constant_override("margin_top", 12)
	outer.add_theme_constant_override("margin_right", 12)
	outer.add_theme_constant_override("margin_bottom", 8)
	add_child(outer)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	outer.add_child(root)

	root.add_child(_build_sidebar())
	root.add_child(_build_main())


func _build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(264, 0) if _sidebar_open else Vector2(0, 0)
	panel.visible = _sidebar_open
	panel.clip_contents = true
	_sidebar = panel
	# 圆角卡片 + 纯色差，不再用 1px 边框
	var st := _style(PANEL, 16)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 16
	st.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", st)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	# ---------------- 第一块：品牌 + 新对话 ----------------
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 10)
	var mark := PanelContainer.new()
	mark.custom_minimum_size = Vector2(32, 32)
	var ms := _style(ACCENT, 8)
	ms.content_margin_left = 0
	ms.content_margin_right = 0
	ms.content_margin_top = 0
	ms.content_margin_bottom = 0
	mark.add_theme_stylebox_override("panel", ms)
	var ml := _label("LH", 13, Color("#0b1220"))
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_child(ml)
	brand.add_child(mark)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 0)
	bcol.add_child(_label("Local Harness", 15, TEXT))
	bcol.add_child(_label(I18N.t("tagline"), 11, FAINT))
	brand.add_child(bcol)
	v.add_child(brand)

	var nb := _button(I18N.t("new_chat"), true)
	nb.pressed.connect(_on_new_chat)
	v.add_child(nb)

	# ---------------- 第二块：搜索 + 会话列表（占大头） ----------------
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(_label(I18N.t("chat_section"), 11, FAINT))
	v.add_child(head)

	_search = LineEdit.new()
	_search.placeholder_text = I18N.t("search_ph")
	_search.add_theme_font_override("font", _f(12))
	_search.add_theme_font_size_override("font_size", 12)
	_search.add_theme_stylebox_override("normal", _style(PANEL2, 9, LINE))
	_search.add_theme_stylebox_override("focus", _style(PANEL2, 9, ACCENT))
	_search.add_theme_color_override("font_color", TEXT)
	_search.add_theme_color_override("font_placeholder_color", FAINT)
	_search.custom_minimum_size = Vector2(0, 32)
	_search.text_changed.connect(func(_t): _refresh_chat_list())
	v.add_child(_search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_chat_list = VBoxContainer.new()
	_chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_chat_list)
	v.add_child(scroll)

	# ---------------- 第三块：快捷入口（紧凑，固定在底部） ----------------
	var quick_box := VBoxContainer.new()
	quick_box.add_theme_constant_override("separation", 6)

	# 折叠标题：小三角 + 名称 + 数量
	plugins_open = bool(App.cfg.get("plugins_open", true))
	var head_btn := Button.new()
	head_btn.focus_mode = Control.FOCUS_NONE
	head_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head_btn.custom_minimum_size = Vector2(0, 24)
	head_btn.add_theme_font_override("font", _f(11))
	head_btn.add_theme_font_size_override("font_size", 11)
	head_btn.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0), 6))
	head_btn.add_theme_stylebox_override("hover", _style(Color("#1a2130"), 6))
	head_btn.add_theme_stylebox_override("pressed", _style(Color("#1e2635"), 6))
	head_btn.add_theme_color_override("font_color", DIM)
	head_btn.add_theme_color_override("font_hover_color", TEXT)
	_plugin_toggle = head_btn
	head_btn.pressed.connect(_toggle_plugins_open)
	quick_box.add_child(head_btn)
	_refresh_plugin_toggle()

	var grid_scroll := ScrollContainer.new()
	grid_scroll.custom_minimum_size = Vector2(0, 88)
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.visible = plugins_open
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid_scroll.add_child(grid)
	quick_box.add_child(grid_scroll)
	_plugin_grid = grid_scroll

	for p in Plugins.loaded:
		var pid := str(p["manifest"].get("id", ""))
		var pname := str(p["manifest"].get("name", pid))
		var chip := _button(pname, false)
		chip.custom_minimum_size = Vector2(96, 28)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_font_size_override("font_size", 11)
		chip.clip_text = true
		chip.tooltip_text = I18N.t("quick_plugin_tip") % pname
		chip.pressed.connect(func(): _open_plugin_panel(pid))
		grid.add_child(chip)
	if Plugins.loaded.is_empty():
		grid.add_child(_label(I18N.t("quick_empty"), 11, FAINT))

	# 模型快捷入口：显示当前模型，点了直接去模型页
	var mchip := Button.new()
	mchip.focus_mode = Control.FOCUS_NONE
	mchip.custom_minimum_size = Vector2(0, 32)
	mchip.clip_text = true
	mchip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	mchip.add_theme_font_override("font", _f(11))
	mchip.add_theme_font_size_override("font_size", 11)
	mchip.add_theme_stylebox_override("normal", _style(PANEL2, 9, LINE))
	mchip.add_theme_stylebox_override("hover", _style(Color("#1a2130"), 9, LINE))
	mchip.add_theme_color_override("font_color", DIM)
	mchip.pressed.connect(func(): _open_settings("model"))
	_model_chip = mchip
	quick_box.add_child(mchip)

	v.add_child(quick_box)
	_refresh_model_chip()

	# 设置（保持不变，放最下面）
	var sb := _button(I18N.t("settings"), false)
	sb.pressed.connect(_open_settings)
	v.add_child(sb)

	return panel


## 插件区的折叠/展开
func _toggle_plugins_open() -> void:
	plugins_open = not plugins_open
	App.set_cfg("plugins_open", plugins_open)
	if _plugin_grid != null:
		_plugin_grid.visible = plugins_open
	_refresh_plugin_toggle()


func _refresh_plugin_toggle() -> void:
	if _plugin_toggle == null:
		return
	var arrow := "▼" if plugins_open else "▶"
	_plugin_toggle.text = "%s  %s  (%d)" % [arrow, I18N.t("quick_section"), Plugins.loaded.size()]


## 侧栏底部的模型快捷入口文字
func _refresh_model_chip() -> void:
	if _model_chip == null:
		return
	var label := App.current_model.get_file().get_basename()
	if label == "":
		label = I18N.t("no_model")
	_model_chip.text = "⚙  %s  ·  %s" % [label, App.backend_text()]


# ---------------------------------------------------------------- 插件快捷面板
## 独立的一套小面板（和设置面板不共用样式），列出该插件的工具，
## 点一下就能直接执行，结果显示在对话里。
var _model_chip: Button = null
var _plugin_toggle: Button = null
var _plugin_grid: Control = null
var plugins_open: bool = true
var _quick_layer: ColorRect = null


func _open_plugin_panel(plugin_id: String) -> void:
	if _quick_layer != null:
		return
	var p: Dictionary = Plugins.find_plugin(plugin_id)
	if p.is_empty():
		_toast(I18N.t("quick_missing"))
		return
	var m: Dictionary = p["manifest"]

	var layer := ColorRect.new()
	layer.color = Color(0, 0, 0, 0.6)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_quick_layer = layer

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(760, 600)
	card.add_theme_stylebox_override("panel", _style(Color("#101319"), 16, Color("#2a3446")))
	center.add_child(card)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 14)
	card.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)

	# 标题栏
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(_label("◆", 12, ACCENT))
	top.add_child(_label(str(m.get("name", plugin_id)), 17, TEXT))
	top.add_child(_label("v" + str(m.get("version", "?")), 11, FAINT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var close := _button("✕", false)
	close.custom_minimum_size = Vector2(34, 28)
	close.pressed.connect(func():
		layer.queue_free()
		_quick_layer = null)
	top.add_child(close)
	v.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)

	# ① 插件自己的设置界面（插件目录里的 ui.gd）
	var ui_path := str(p.get("dir", "")).path_join("ui.gd")
	var hosted := false
	if FileAccess.file_exists(ui_path):
		var scr = load(ui_path)
		if scr is GDScript and scr.can_instantiate():
			var node = scr.new()
			if node is Control and node.has_method("build"):
				var ctl: Control = node
				ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				body.add_child(ctl)
				ctl.call("build", plugin_id)
				hosted = true
			else:
				node.queue_free()
	if not hosted:
		var fb = PluginUI.fallback(plugin_id)
		if fb is Control:
			(fb as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_child(fb)

	body.add_child(_label(I18N.t("quick_hint"), 10, FAINT))


## 执行工具：无参数直接跑，有参数先弹一个输入框
func _run_quick_tool(tool_name: String, tool: Dictionary, layer: ColorRect) -> void:
	if not PluginPrefs.tool_enabled(tool_name):
		_toast(I18N.t("quick_denied"))
		return
	var params: Dictionary = tool.get("params", {})
	if params.is_empty():
		layer.queue_free()
		_quick_layer = null
		_invoke_quick(tool_name, {})
		return
	var keys: Array = params.keys()
	var first := str(keys[0])
	_prompt("%s  ·  %s" % [tool_name, str(params[first])], "", func(text: String):
		var args := {}
		if text.strip_edges() != "":
			args[first] = text.strip_edges()
		layer.queue_free()
		_quick_layer = null
		_invoke_quick(tool_name, args))


func _invoke_quick(tool_name: String, args: Dictionary) -> void:
	_toast(I18N.t("quick_running") % tool_name)
	var res := Plugins.invoke(tool_name, args)
	var ok := bool(res.get("ok", false))
	_add_tool_chip("◆ %s" % tool_name)
	_add_tool_chip(str(res.get("output", "")).substr(0, 600))
	_toast(I18N.t("quick_done") if ok else I18N.t("quick_fail"))


func _build_main() -> Control:
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)

	# 顶栏：折叠按钮 + 对话名称 + 状态（透明底，不留分隔线）
	var head := PanelContainer.new()
	var hs := _style(Color("#12151d"), 14)
	hs.content_margin_left = 14
	hs.content_margin_right = 16
	hs.content_margin_top = 8
	hs.content_margin_bottom = 8
	head.add_theme_stylebox_override("panel", hs)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	head.add_child(hbox)

	_toggle_btn = _button("☰", false)
	_toggle_btn.custom_minimum_size = Vector2(34, 30)
	_toggle_btn.tooltip_text = I18N.t("collapse")
	_toggle_btn.pressed.connect(_toggle_sidebar)
	hbox.add_child(_toggle_btn)

	_chat_title = _label(I18N.t("chat_untitled"), 15, TEXT)
	_chat_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_chat_title)

	_status_lbl = _label("", 12, DIM)
	hbox.add_child(_status_lbl)

	var by := _label(I18N.t("credit"), 10, Color(0.62, 0.66, 0.74, 0.45))
	hbox.add_child(by)

	_model_btn = OptionButton.new()
	_model_btn.custom_minimum_size = Vector2(220, 30)
	# 不抢键盘焦点：否则在输入框里打字会被下拉框当成首字母跳转，模型就莫名换了
	_model_btn.focus_mode = Control.FOCUS_NONE
	_model_btn.add_theme_font_override("font", _f(12))
	_model_btn.add_theme_font_size_override("font_size", 12)
	_model_btn.add_theme_stylebox_override("normal", _style(PANEL2, 8, LINE))
	_model_btn.add_theme_stylebox_override("hover", _style(PANEL2.lightened(0.06), 8, LINE))
	_model_btn.add_theme_stylebox_override("pressed", _style(PANEL2, 8, ACCENT))
	_model_btn.add_theme_color_override("font_color", TEXT)
	_model_btn.item_selected.connect(_on_model_selected)

	_backend_chip = _label("", 12, ACCENT)
	var chip_panel := PanelContainer.new()
	var cs := _style(Color("#1a2436"), 8, Color("#2c4b7a"))
	cs.content_margin_top = 5
	cs.content_margin_bottom = 5
	chip_panel.add_theme_stylebox_override("panel", cs)
	chip_panel.add_child(_backend_chip)

	main.add_child(head)

	# 消息区
	_msg_scroll = ScrollContainer.new()
	_msg_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_msg_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 28)
	pad.add_theme_constant_override("margin_right", 28)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_box = VBoxContainer.new()
	_msg_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_box.add_theme_constant_override("separation", 14)
	pad.add_child(_msg_box)
	_msg_scroll.add_child(pad)
	main.add_child(_msg_scroll)

	# 输入区：和消息区同一个底色，只靠输入框自身的卡片做层次
	var comp := PanelContainer.new()
	var cps := StyleBoxEmpty.new()
	cps.content_margin_left = 8
	cps.content_margin_right = 8
	cps.content_margin_top = 10
	cps.content_margin_bottom = 2
	comp.add_theme_stylebox_override("panel", cps)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	comp.add_child(cv)

	# 输入框：文本铺满，发送按钮迷你化叠在右下角
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, 76)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_composer = TextEdit.new()
	_composer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_composer.placeholder_text = I18N.t("composer_ph") % App.assistant_name()
	_composer.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_composer.add_theme_font_override("font", _f(14))
	_composer.add_theme_font_size_override("font_size", 14)
	# 右边多留一点内边距，打字不会跑到按钮底下
	var ns := _style(PANEL2, 10, LINE)
	ns.content_margin_right = 46
	var fs := _style(PANEL2, 10, ACCENT)
	fs.content_margin_right = 46
	_composer.add_theme_stylebox_override("normal", ns)
	_composer.add_theme_stylebox_override("focus", fs)
	_composer.add_theme_color_override("font_color", TEXT)
	_composer.add_theme_color_override("font_placeholder_color", FAINT)
	_composer.add_theme_color_override("caret_color", ACCENT)
	_composer.gui_input.connect(_on_composer_key)
	row.add_child(_composer)

	_send_btn = Button.new()
	_send_btn.text = "↑"
	_send_btn.tooltip_text = I18N.t("send_tip")
	_send_btn.focus_mode = Control.FOCUS_NONE
	_send_btn.add_theme_font_override("font", _f(16, true))
	_send_btn.add_theme_font_size_override("font_size", 16)
	var bn := _style(ACCENT, 8)
	bn.content_margin_left = 0
	bn.content_margin_right = 0
	bn.content_margin_top = 0
	bn.content_margin_bottom = 0
	_send_btn.add_theme_stylebox_override("normal", bn)
	_send_btn.add_theme_stylebox_override("hover", _style(ACCENT.lightened(0.08), 8))
	_send_btn.add_theme_stylebox_override("pressed", _style(ACCENT.darkened(0.12), 8))
	_send_btn.add_theme_stylebox_override("disabled", _style(Color("#2a3446"), 8))
	_send_btn.add_theme_color_override("font_color", Color("#0b1220"))
	_send_btn.add_theme_color_override("font_hover_color", Color("#0b1220"))
	_send_btn.add_theme_color_override("font_disabled_color", Color("#5d6a7e"))
	# 锚在输入框右下角
	_send_btn.anchor_left = 1.0
	_send_btn.anchor_top = 1.0
	_send_btn.anchor_right = 1.0
	_send_btn.anchor_bottom = 1.0
	_send_btn.offset_left = -38
	_send_btn.offset_top = -38
	_send_btn.offset_right = -8
	_send_btn.offset_bottom = -8
	_send_btn.pressed.connect(_on_send)
	row.add_child(_send_btn)
	cv.add_child(row)

	# 输入框下方一行：左边上下文/速度，右边加速方式 + 模型选择
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	_footer = _label("", 11, FAINT)
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_footer)
	bottom.add_child(chip_panel)
	bottom.add_child(_model_btn)
	cv.add_child(bottom)


	main.add_child(comp)

	return main


# ---------------------------------------------------------------- 会话列表
func _refresh_chat_list() -> void:
	# 先把旧项真正摘掉再释放，否则同一帧里新旧会重复显示
	for c in _chat_list.get_children():
		_chat_list.remove_child(c)
		c.queue_free()
	var q := _search.text.strip_edges().to_lower() if _search else ""
	var shown := 0
	for i in App.chats.size():
		var chat: Dictionary = App.chats[i]
		var title := str(chat.get("title", I18N.t("chat_untitled")))
		if q != "" and not _chat_matches(chat, q):
			continue
		var b := Button.new()
		b.text = title
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.tooltip_text = "%d 条消息" % chat.get("messages", []).size()
		b.add_theme_font_override("font", _f(13))
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(0, 34)
		var normal := _style(PANEL if i != App.current_chat else Color("#1e2635"), 8)
		normal.content_margin_left = 10
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", _style(Color("#1a2130"), 8))
		b.add_theme_stylebox_override("pressed", _style(Color("#1e2635"), 8))
		b.add_theme_color_override("font_color", TEXT if i == App.current_chat else DIM)
		b.pressed.connect(_open_chat.bind(i))
		b.gui_input.connect(_on_chat_click.bind(i, b))
		_chat_list.add_child(b)
		shown += 1
	if shown == 0:
		var msg := I18N.t("empty_chat") if q == "" else I18N.t("chat_no_match")
		var empty := _label(msg, 12, FAINT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_chat_list.add_child(empty)


## 标题或任意一条消息命中就算匹配
func _chat_matches(chat: Dictionary, q: String) -> bool:
	if str(chat.get("title", "")).to_lower().find(q) >= 0:
		return true
	for m in chat.get("messages", []):
		if str(m.get("content", "")).to_lower().find(q) >= 0:
			return true
	return false


## 左键打开，右键弹菜单（重命名 / 删除）
func _on_chat_click(event: InputEvent, idx: int, node: Button) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var menu := PopupMenu.new()
	menu.add_item(I18N.t("chat_menu_rename"), 0)
	menu.add_item(I18N.t("chat_menu_delete"), 1)
	# 跟深色界面统一，别用默认的浅色主题
	var mp := _style(PANEL, 8, LINE)
	mp.content_margin_left = 6
	mp.content_margin_right = 6
	mp.content_margin_top = 6
	mp.content_margin_bottom = 6
	menu.add_theme_stylebox_override("panel", mp)
	menu.add_theme_stylebox_override("hover", _style(Color("#1e2635"), 6))
	menu.add_theme_color_override("font_color", TEXT)
	menu.add_theme_color_override("font_hover_color", TEXT)
	menu.add_theme_color_override("font_disabled_color", FAINT)
	if _f(13) != null:
		menu.add_theme_font_override("font", _f(13))
		menu.add_theme_font_size_override("font_size", 13)
	add_child(menu)
	menu.id_pressed.connect(func(id: int):
		menu.queue_free()
		if id == 0:
			_rename_chat(idx, node)
		else:
			_delete_chat(idx))
	var at := Vector2i(node.get_screen_position() + Vector2(0, 34))
	menu.popup(Rect2i(at, Vector2i(150, 0)))


func _rename_chat(idx: int, node: Button) -> void:
	if idx < 0 or idx >= App.chats.size():
		return
	var cur := str(App.chats[idx].get("title", ""))
	_prompt(I18N.t("chat_menu_rename"), cur, func(v: String):
		var t := v.strip_edges()
		if t == "":
			return
		App.chats[idx]["title"] = t
		App.save_chat(idx)
		_refresh_chat_list()
		if idx == App.current_chat:
			_chat_title.text = t)


func _delete_chat(idx: int) -> void:
	if idx < 0 or idx >= App.chats.size():
		return
	var t := str(App.chats[idx].get("title", ""))
	_confirm(I18N.t("chat_menu_delete"), "%s\n「%s」" % [I18N.t("chat_delete_confirm"), t], func():
		App.delete_chat(idx)
		if App.chats.is_empty():
			App.new_chat()
		App.current_chat = clampi(App.current_chat, 0, App.chats.size() - 1)
		_refresh_chat_list()
		_open_chat(App.current_chat))


# ---------------------------------------------------------------- 消息渲染
func _open_chat(idx: int) -> void:
	if idx < 0 or idx >= App.chats.size():
		return
	App.current_chat = idx
	if _chat_title:
		_chat_title.text = str(App.chats[idx].get("title", I18N.t("chat_untitled")))
	for c in _msg_box.get_children():
		c.queue_free()
	_stream_label = null
	var chat: Dictionary = App.chats[idx]
	var visible: Array = []
	for m in chat.get("messages", []):
		# hidden = 工具调用协议的内部记录，不显示在界面上
		if bool(m.get("hidden", false)):
			continue
		visible.append(m)
	# 先画最近 14 条，剩下的分帧补上：长会话切换不卡
	var first := maxi(0, visible.size() - 14)
	for i in range(first, visible.size()):
		var m: Dictionary = visible[i]
		_add_bubble(str(m.get("role", "user")), str(m.get("content", "")), false)
	_refresh_chat_list()
	_scroll_to_bottom()
	if first > 0:
		_fill_older_messages.call_deferred(visible, first)


func _add_bubble(role: String, text: String, animate := true) -> RichTextLabel:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)
	var is_user := role == "user"

	# 两侧留白用可伸缩的空白实现：气泡最多占约 72% 宽度
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = 0.28
	if is_user:
		row.add_child(spacer)

	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_stretch_ratio = 0.72
	var bs := _style(USER_BG if is_user else AI_BG, 14,
		Color(0, 0, 0, 0) if is_user else LINE)
	bs.content_margin_left = 16
	bs.content_margin_right = 16
	bs.content_margin_top = 11
	bs.content_margin_bottom = 11
	bubble.add_theme_stylebox_override("panel", bs)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	bubble.add_child(col)

	var who := _label(App.user_name() if is_user else App.assistant_name(), 11,
		Color("#8fb0e8") if is_user else FAINT)
	col.add_child(who)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	col.add_child(content)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("normal_font", _f(14))
	body.add_theme_font_override("bold_font", _f(14, true))
	body.add_theme_font_override("italics_font", _f(14))
	body.add_theme_font_override("mono_font", _f(13))
	body.add_theme_font_size_override("normal_font_size", 14)
	body.add_theme_font_size_override("bold_font_size", 14)
	body.add_theme_font_size_override("italics_font_size", 14)
	body.add_theme_font_size_override("mono_font_size", 13)
	body.add_theme_color_override("default_color", TEXT)
	body.add_theme_color_override("font_color", TEXT)
	body.text = MD.plain(_sanitize(text)) if is_user else MD.to_bb(_sanitize(text))
	body.meta_clicked.connect(func(url: String): OS.shell_open(url))
	content.add_child(body)
	# 历史消息（非流式）用 MDView 渲染，表格/图片/公式才出得来
	if not animate:
		body.visible = false
		var view := MDView.build(_sanitize(text), 14)
		content.add_child(view)
	else:
		_stream_col = content

	row.add_child(bubble)
	if not is_user:
		row.add_child(spacer)

	_msg_box.add_child(row)
	if animate:
		_scroll_to_bottom()
	if not is_user:
		_stream_label = body
	return body


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if _msg_scroll:
		_msg_scroll.scroll_vertical = int(_msg_scroll.get_v_scroll_bar().max_value)


# ---------------------------------------------------------------- 发送
func _on_send() -> void:
	# 生成中再点一次 = 停止
	if _waiting:
		_agent_abort = true
		App.cancel_chat()
		return
	var text := _composer.text.strip_edges()
	if text == "" or not App.chat_ready():
		return
	_composer.text = ""
	# 斜杠命令：/shot、/mem 这类交给插件执行，不进模型
	if text.begins_with("/"):
		_run_slash_command(text)
		return
	var chat: Dictionary = App.chats[App.current_chat]
	var msgs: Array = chat.get("messages", [])
	msgs.append({"role": "user", "content": text})
	if str(chat.get("title", "")) == I18N.t("chat_untitled"):
		chat["title"] = text.substr(0, 24)
		if _chat_title:
			_chat_title.text = str(chat["title"])
	App.save_current()
	_promote_current_chat()
	# 渲染
	_add_bubble("user", text)
	_waiting = true
	_set_send_enabled(false)
	_run_agent(chat, msgs)


## Agent 循环：模型要工具就执行，把结果喂回去，直到它给出最终回答
## 用提示词协议，所以任意 GGUF 模型都能用（不需要 function calling 支持）
func _run_agent(chat: Dictionary, msgs: Array) -> void:
	var steps: int = int(App.cfg.get("max_steps", 4))
	var final_text := ""
	_agent_abort = false
	_agent_running = true
	for step in steps:
		if _agent_abort:
			break
		_stream_raw = ""
		_add_bubble("assistant", "")
		var payload := _build_payload(msgs)
		var r: Dictionary = await App.run_turn(payload)
		if _agent_abort:
			break
		if not r.get("ok", false):
			_on_failed(str(r.get("error", "生成失败")))
			return
		var txt: String = str(r.get("text", ""))
		var call := Plugins.extract_call(txt)
		if call.is_empty():
			final_text = Plugins.strip_calls(txt)
			break
		# 这一轮是工具调用：把刚才那个空气泡换成一枚工具芯片
		_remove_last_bubble()
		_stream_label = null
		var tool_name := str(call.get("name", ""))
		var args: Dictionary = call.get("args", {})
		var step_no: int = step + 1
		_add_tool_chip("🛠 第 %d/%d 步 · %s  %s" % [step_no, steps, tool_name,
			JSON.stringify(args).substr(0, 140)])
		var res: Dictionary = await Plugins.invoke_async(tool_name, args)
		var out := str(res.get("output", ""))
		_add_tool_chip(("✓ " if res.get("ok", false) else "✗ ") + out.substr(0, 400))
		msgs.append({"role": "assistant", "content": txt, "hidden": true})
		var ctx_out := out if out.length() <= 2000 else out.substr(0, 2000) + "\n…（已截断）"
		msgs.append({"role": "user", "content": "工具 %s 的结果：\n%s" % [tool_name, ctx_out], "hidden": true})
		_footer.text = "第 %d/%d 步 · %d 个工具可用" % [step_no, steps, Plugins.tools().size()]

	if final_text != "" and not _agent_abort:
		# 最后一轮已经流式渲染过，这里只补一条记录
		msgs.append({"role": "assistant", "content": final_text})
		_finish_stream_into_view()
		App.save_current()
		_refresh_chat_list()
	_agent_running = false
	_waiting = false
	_set_send_enabled(true)
	_refresh_header()


func _build_payload(msgs: Array) -> Array:
	var payload: Array = []
	var sys := App.system_with_names()
	var tools := Plugins.describe_for_prompt()
	if tools != "":
		sys = sys + "\n\n" + tools
	if sys.strip_edges() != "":
		payload.append({"role": "system", "content": sys})
	var start := maxi(0, msgs.size() - 24)
	for i in range(start, msgs.size()):
		var m: Dictionary = msgs[i]
		var content := str(m.get("content", ""))
		if content.length() > 4000:
			content = content.substr(0, 4000) + "\n…（已截断）"
		payload.append({"role": m["role"], "content": content})
	return payload


func _set_send_enabled(on: bool) -> void:
	# 生成中它变成"停止"键（■），点了会中断 Agent 循环
	_send_btn.disabled = false
	_send_btn.text = "↑" if on else "■"
	_send_btn.tooltip_text = I18N.t("send_tip") if on else I18N.t("stop_tip")


func _on_delta(text: String) -> void:
	if _stream_label == null:
		return
	_stream_raw += text
	# 节流：Markdown 转 BBCode 是 O(n)，每个 chunk 都转会卡死
	var now := Time.get_ticks_msec()
	if now - _last_render_ms < 90:
		return
	_last_render_ms = now
	if _stream_raw.length() > 3000:
		# 长回复先按纯文本刷，结束时再整体排版
		_stream_label.text = MD.plain(_stream_raw)
	else:
		_stream_label.text = MD.to_bb(_stream_raw)
		_scroll_to_bottom()


func _on_done(stats: Dictionary) -> void:
	if _agent_running:
		# 工具循环还在跑：这一轮的文字由 _run_agent 统一收尾，避免记两条
		_footer.text = "%.0f 字 · %.1f 秒 · %.1f 字/秒" % [
			stats.get("chars", 0), stats.get("secs", 0), stats.get("cps", 0)]
		return
	_waiting = false
	_set_send_enabled(true)
	var chat: Dictionary = App.chats[App.current_chat]
	var msgs: Array = chat.get("messages", [])
	var last := ""
	if _stream_label:
		last = _stream_label.text
	msgs.append({"role": "assistant", "content": last})
	App.save_current()
	_refresh_chat_list()
	_footer.text = "%.0f 字 · %.1f 秒 · %.1f 字/秒" % [
		stats.get("chars", 0), stats.get("secs", 0), stats.get("cps", 0)]
	_finish_stream_into_view()


func _on_failed(msg: String) -> void:
	_waiting = false
	_set_send_enabled(true)
	if _stream_label:
		_stream_label.text += "\n[color=#e05a5a]（%s）[/color]" % msg


func _toggle_sidebar() -> void:
	_sidebar_open = not _sidebar_open
	App.set_cfg("sidebar_open", _sidebar_open)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _sidebar_open:
		_sidebar.visible = true
		tw.tween_property(_sidebar, "custom_minimum_size:x", 264.0, 0.18)
	else:
		tw.tween_property(_sidebar, "custom_minimum_size:x", 0.0, 0.18)
		tw.tween_callback(func(): _sidebar.visible = false)


func _on_new_chat() -> void:
	# 已经有一个空的「新对话」就切过去，别一直堆
	for i in App.chats.size():
		var c: Dictionary = App.chats[i]
		if str(c.get("title", "")) == I18N.t("chat_untitled") and c.get("messages", []).is_empty():
			if i != 0:
				App.chats.remove_at(i)
				App.chats.insert(0, c)
			_open_chat(0)
			_composer.grab_focus()
			return
	App.new_chat()
	_refresh_chat_list()
	_open_chat(0)
	_composer.grab_focus()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		# 关掉最上面那层弹窗
		var closed := false
		for child in get_children():
			if child is ColorRect and child.mouse_filter == Control.MOUSE_FILTER_STOP:
				child.queue_free()
				closed = true
		if _settings_layer:
			_settings_layer.queue_free()
			_settings_layer = null
			closed = true
		if _plugin_layer:
			_plugin_layer.queue_free()
			_plugin_layer = null
			closed = true
		if closed:
			get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed:
		match event.keycode:
			KEY_N:
				_on_new_chat()
				get_viewport().set_input_as_handled()
			KEY_F:
				if not _sidebar_open:
					_toggle_sidebar()
				_search.grab_focus()
				get_viewport().set_input_as_handled()
			KEY_COMMA:
				_open_settings()
				get_viewport().set_input_as_handled()
			KEY_ENTER:
				_on_send()
				get_viewport().set_input_as_handled()


## 去掉模型输出里混进来的占位符（旧版本 `str(null)` 变成的 "<null>"）
func _sanitize(t: String) -> String:
	var s := t
	while s.begins_with("<null>"):
		s = s.substr(6)
	if s.begins_with("null>"):
		s = s.substr(5)
	return s
## 走输入框自己的 gui_input，而不是全局 _input，避免焦点不在输入框时误触发。
func _on_composer_key(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ENTER and not event.shift_pressed:
		_on_send()
		_composer.accept_event()


# ---------------------------------------------------------------- 顶栏 / 服务
var _model_sig: String = ""


func _refresh_header() -> void:
	var sig := "%d|%s|%s" % [App.models.size(), App.current_model, str(App.cfg.get("lang", "zh"))]
	if sig != _model_sig:
		_model_sig = sig
		_model_btn.clear()
		for i in App.models.size():
			_model_btn.add_item(App.models[i]["label"])
			if App.models[i]["path"] == App.current_model:
				_model_btn.select(i)
		if App.models.is_empty():
			_model_btn.add_item(I18N.t("no_model"))
	_backend_chip.text = App.backend_text()
	var gpu := ""
	if not App.gpu.is_empty():
		gpu = " · %s" % str(App.gpu.get("name", ""))
	var prof: Dictionary = App.profile_for()
	var ctx_now := int(prof.get("ctx", App.cfg.get("ctx", 4096)))
	_footer.text = (I18N.t("footer_ctx") % ctx_now) + gpu
	_refresh_model_chip()


func _on_model_selected(idx: int) -> void:
	if idx < 0 or idx >= App.models.size():
		return
	App.current_model = App.models[idx]["path"]
	App.set_cfg("model", App.current_model)
	_refresh_header()
	App.restart_server()


func _on_server_state(state: String) -> void:
	match state:
		"starting":
			_status_lbl.text = I18N.t("status_loading")
			_status_lbl.add_theme_color_override("font_color", DIM)
		"ready":
			_status_lbl.text = I18N.t("status_ready")
			_status_lbl.add_theme_color_override("font_color", Color("#57c08a"))
		"error":
			_status_lbl.text = I18N.t("status_failed")
			_status_lbl.add_theme_color_override("font_color", DANGER)
		_:
			_status_lbl.text = I18N.t("status_stopped")
			_status_lbl.add_theme_color_override("font_color", FAINT)


func _connect_app() -> void:
	pass


# ---------------------------------------------------------------- 设置面板
func _open_settings_legacy() -> void:
	if _settings_layer:
		return
	var layer := ColorRect.new()
	layer.color = Color(0, 0, 0, 0.62)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_settings_layer = layer

	# 用 CenterContainer 居中，跟着窗口尺寸自动调整，不再手算偏移
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var dlg := PanelContainer.new()
	dlg.custom_minimum_size = Vector2(560, 0)
	dlg.add_theme_stylebox_override("panel", _style(PANEL, 16, LINE))
	center.add_child(dlg)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 18)
	dlg.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pad.add_child(v)
	v.add_child(_label("设置", 18, TEXT))
	v.add_child(_label("改完点保存，模型会自动重启", 12, FAINT))

	# 后端
	var brow := HBoxContainer.new()
	brow.add_child(_label("加速后端", 13, DIM))
	var bsp := Control.new()
	bsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(bsp)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(190, 32)
	var keys := ["auto", "cpu", "cuda", "vulkan"]
	var names := ["自动", "CPU", "CUDA", "Vulkan"]
	for i in keys.size():
		opt.add_item(names[i])
		if str(App.cfg.get("backend", "auto")) == keys[i]:
			opt.select(i)
	opt.add_theme_font_override("font", _f(13))
	opt.add_theme_stylebox_override("normal", _style(PANEL2, 8, LINE))
	opt.add_theme_color_override("font_color", TEXT)
	brow.add_child(opt)
	v.add_child(brow)

	# GPU 层数
	var lrow := HBoxContainer.new()
	lrow.add_child(_label("GPU 层数", 13, DIM))
	var lsp := Control.new()
	lsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(lsp)
	var spin := SpinBox.new()
	spin.min_value = -1
	spin.max_value = 200
	spin.value = int(App.cfg.get("gpu_layers", -1))
	spin.custom_minimum_size = Vector2(120, 32)
	spin.add_theme_font_override("font", _f(13))
	lrow.add_child(spin)
	lrow.add_child(_label("-1 全部层 / 0 纯 CPU", 11, FAINT))
	v.add_child(lrow)

	# 上下文
	var crow := HBoxContainer.new()
	crow.add_child(_label("上下文", 13, DIM))
	var csp := Control.new()
	csp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(csp)
	var ctx_spin := SpinBox.new()
	ctx_spin.min_value = 512
	ctx_spin.max_value = 65536
	ctx_spin.step = 512
	ctx_spin.value = int(App.cfg.get("ctx", 4096))
	ctx_spin.custom_minimum_size = Vector2(120, 32)
	ctx_spin.add_theme_font_override("font", _f(13))
	crow.add_child(ctx_spin)
	v.add_child(crow)

	# 温度 / 回复上限
	var trow := HBoxContainer.new()
	trow.add_child(_label("温度", 13, DIM))
	var tsp := Control.new()
	tsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tsp)
	var temp_spin := SpinBox.new()
	temp_spin.min_value = 0.0
	temp_spin.max_value = 2.0
	temp_spin.step = 0.05
	temp_spin.value = float(App.cfg.get("temp", 0.7))
	temp_spin.custom_minimum_size = Vector2(100, 32)
	trow.add_child(temp_spin)
	trow.add_child(_label("   回复上限", 13, DIM))
	var max_spin := SpinBox.new()
	max_spin.min_value = 64
	max_spin.max_value = 8192
	max_spin.step = 64
	max_spin.value = int(App.cfg.get("max_tokens", 512))
	max_spin.custom_minimum_size = Vector2(110, 32)
	trow.add_child(max_spin)
	v.add_child(trow)

	# 插件 / 工具轮次
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 10)
	prow.add_child(_label("工具轮次", 13, DIM))
	var steps_spin := SpinBox.new()
	steps_spin.min_value = 0
	steps_spin.max_value = 12
	steps_spin.value = int(App.cfg.get("max_steps", 4))
	steps_spin.custom_minimum_size = Vector2(80, 30)
	prow.add_child(steps_spin)
	prow.add_child(_label("（连续调用工具的上限，0 = 关闭）", 11, FAINT))
	var psp := Control.new()
	psp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(psp)
	var pbtn := _button("插件管理…", false)
	pbtn.custom_minimum_size = Vector2(112, 30)
	pbtn.pressed.connect(_open_plugins)
	prow.add_child(pbtn)
	v.add_child(prow)

	# 称呼
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	nrow.add_child(_label("你的称呼", 13, DIM))
	var u_edit := LineEdit.new()
	u_edit.text = App.user_name()
	u_edit.custom_minimum_size = Vector2(120, 30)
	u_edit.add_theme_font_override("font", _f(13))
	u_edit.add_theme_stylebox_override("normal", _style(PANEL2, 8, LINE))
	u_edit.add_theme_color_override("font_color", TEXT)
	nrow.add_child(u_edit)
	nrow.add_child(_label("    AI 的名字", 13, DIM))
	var a_edit := LineEdit.new()
	a_edit.text = App.assistant_name()
	a_edit.custom_minimum_size = Vector2(140, 30)
	a_edit.add_theme_font_override("font", _f(13))
	a_edit.add_theme_stylebox_override("normal", _style(PANEL2, 8, LINE))
	a_edit.add_theme_color_override("font_color", TEXT)
	nrow.add_child(a_edit)
	var nsp := Control.new()
	nsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(nsp)
	v.add_child(nrow)

	# 系统提示词
	v.add_child(_label("系统提示词", 13, DIM))
	var sys := TextEdit.new()
	sys.text = str(App.cfg.get("system", ""))
	sys.custom_minimum_size = Vector2(0, 92)
	sys.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	sys.add_theme_font_override("font", _f(13))
	sys.add_theme_stylebox_override("normal", _style(PANEL2, 9, LINE))
	sys.add_theme_color_override("font_color", TEXT)
	v.add_child(sys)

	# 开源协议（GPLv3 要求分发时必须声明许可并给出源码）
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	v.add_child(sep)

	var lic_head := HBoxContainer.new()
	lic_head.add_theme_constant_override("separation", 8)
	lic_head.add_child(_label("开源协议", 13, DIM))
	var sp_l := Control.new()
	sp_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lic_head.add_child(sp_l)
	var view_btn := _button("查看完整许可", false)
	view_btn.custom_minimum_size = Vector2(112, 28)
	view_btn.pressed.connect(_show_licenses)
	lic_head.add_child(view_btn)
	v.add_child(lic_head)

	var lic := RichTextLabel.new()
	lic.bbcode_enabled = true
	lic.fit_content = true
	lic.scroll_active = false
	lic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lic.add_theme_font_override("normal_font", _f(10))
	lic.add_theme_font_override("bold_font", _f(10, true))
	lic.add_theme_font_size_override("normal_font_size", 10)
	lic.add_theme_font_size_override("bold_font_size", 10)
	lic.add_theme_constant_override("line_separation", 1)
	lic.add_theme_color_override("default_color", Color(0.55, 0.6, 0.68, 0.8))
	lic.text = (
		"[color=#9aa6b8]本程序[/color] Local-Harness · [b]GPL-3.0[/b] · "
		+ "[url=https://github.com/yushuchun177/local-harness]源码[/url]\n"
		+ "[color=#9aa6b8]引擎[/color] Godot Engine 4.7.2 · MIT · "
		+ "[url=https://godotengine.org/license]版权[/url]\n"
		+ "[color=#9aa6b8]推理[/color] llama.cpp · MIT · "
		+ "[url=https://github.com/ggml-org/llama.cpp]项目[/url]\n"
		+ "[color=#9aa6b8]模型[/color] 由各自发布方授权（本程序不附带模型权重）"
	)
	lic.meta_clicked.connect(func(url: String): OS.shell_open(url))
	v.add_child(lic)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(sp2)
	var cancel := _button("取消")
	cancel.custom_minimum_size = Vector2(88, 36)
	cancel.pressed.connect(_close_settings)
	btns.add_child(cancel)
	var ok := _button("保存", true)
	ok.custom_minimum_size = Vector2(88, 36)
	ok.pressed.connect(func():
		App.set_cfg("backend", keys[opt.selected])
		App.set_cfg("gpu_layers", int(spin.value))
		App.set_cfg("ctx", int(ctx_spin.value))
		App.set_cfg("temp", float(temp_spin.value))
		App.set_cfg("max_tokens", int(max_spin.value))
		App.set_cfg("system", sys.text)
		App.set_cfg("max_steps", int(steps_spin.value))
		App.set_cfg("user_name", u_edit.text.strip_edges())
		App.set_cfg("assistant_name", a_edit.text.strip_edges())
		_composer.placeholder_text = I18N.t("composer_ph") % App.assistant_name()
		_close_settings()
		_refresh_header()
		App.restart_server())
	btns.add_child(ok)
	v.add_child(btns)


func _close_settings() -> void:
	if _settings_layer:
		_settings_layer.queue_free()
		_settings_layer = null


## 完整许可文本：三个标签页，内容来自 LICENSES/ 目录
func _show_licenses() -> void:
	if _license_layer:
		return
	var layer := ColorRect.new()
	layer.color = Color(0, 0, 0, 0.7)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_license_layer = layer

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var dlg := PanelContainer.new()
	dlg.custom_minimum_size = Vector2(760, 560)
	dlg.add_theme_stylebox_override("panel", _style(PANEL, 16, LINE))
	center.add_child(dlg)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 16)
	dlg.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)
	v.add_child(_label("开源协议", 18, TEXT))

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_override("font", _f(12))
	tabs.add_theme_color_override("font_selected_color", TEXT)
	tabs.add_theme_color_override("font_unselected_color", DIM)
	v.add_child(tabs)

	for item in [["GPL-3.0（本程序）", "res://LICENSES/GPL-3.0.txt"],
			["MIT（Godot 引擎）", "res://LICENSES/MIT-Godot.txt"],
			["MIT（llama.cpp）", "res://LICENSES/MIT-llama.cpp.txt"]]:
		var scroll := ScrollContainer.new()
		scroll.name = str(item[0])
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var txt := Label.new()
		txt.text = _read_text(str(item[1]))
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.add_theme_font_override("font", _f(11))
		txt.add_theme_font_size_override("font_size", 11)
		txt.add_theme_color_override("font_color", Color(0.82, 0.85, 0.9, 0.9))
		scroll.add_child(txt)
		tabs.add_child(scroll)

	var row := HBoxContainer.new()
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var close := _button("关闭", true)
	close.custom_minimum_size = Vector2(96, 34)
	close.pressed.connect(func():
		if _license_layer:
			_license_layer.queue_free()
			_license_layer = null)
	row.add_child(close)
	v.add_child(row)


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "（找不到 %s）" % path
	return f.get_as_text()

# ---------------------------------------------------------------- 工具气泡
func _remove_last_bubble() -> void:
	var kids := _msg_box.get_children()
	if kids.size() > 0:
		var last: Node = kids[kids.size() - 1]
		_msg_box.remove_child(last)
		last.queue_free()


## 工具调用/结果的小芯片，弱化显示
func _add_tool_chip(text: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs := _style(PANEL2, 8)
	cs.content_margin_left = 10
	cs.content_margin_right = 10
	cs.content_margin_top = 5
	cs.content_margin_bottom = 5
	chip.add_theme_stylebox_override("panel", cs)
	var l := _label(text, 11, Color(0.62, 0.68, 0.78, 0.95))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	chip.add_child(l)
	row.add_child(chip)
	_msg_box.add_child(row)
	_scroll_to_bottom()


# ---------------------------------------------------------------- 插件管理
var _plugin_layer: ColorRect = null


func _open_plugins() -> void:
	if _plugin_layer:
		return
	var layer := ColorRect.new()
	layer.color = Color(0, 0, 0, 0.68)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_plugin_layer = layer

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var dlg := PanelContainer.new()
	dlg.custom_minimum_size = Vector2(720, 540)
	dlg.add_theme_stylebox_override("panel", _style(PANEL, 16, LINE))
	center.add_child(dlg)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 16)
	dlg.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)

	var head := HBoxContainer.new()
	head.add_child(_label("插件", 18, TEXT))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hsp)
	var refresh := _button("刷新列表", false)
	refresh.custom_minimum_size = Vector2(96, 30)
	head.add_child(refresh)
	v.add_child(head)

	var status := _label("正在获取插件索引…", 11, FAINT)
	v.add_child(status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list_box := VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(list_box)
	v.add_child(scroll)

	var row := HBoxContainer.new()
	row.add_child(_label("插件来自各自独立的 GitHub 仓库，装到 user://plugins/ 后立即生效", 10, FAINT))
	var rsp := Control.new()
	rsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rsp)
	var close := _button("关闭", true)
	close.custom_minimum_size = Vector2(96, 34)
	close.pressed.connect(func():
		if _plugin_layer:
			_plugin_layer.queue_free()
			_plugin_layer = null)
	row.add_child(close)
	v.add_child(row)

	refresh.pressed.connect(func(): _fill_plugin_list(list_box, status))
	_fill_plugin_list(list_box, status)


func _fill_plugin_list(list_box: VBoxContainer, status: Label) -> void:
	for c in list_box.get_children():
		c.queue_free()
	status.text = "正在获取插件索引…"
	var ok: bool = await PluginStore.fetch_index()
	if not ok:
		status.text = "索引获取失败（GitHub 连不上时请用代理）"
		return
	status.text = "共 %d 个插件" % PluginStore.catalog.size()
	for item in PluginStore.catalog:
		var id := str(item.get("id", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		var installed := PluginStore.installed_version(id)
		var title := "%s  v%s" % [str(item.get("name", id)), str(item.get("version", "?"))]
		if installed != "":
			title += "   · 已安装 v%s" % installed
		col.add_child(_label(title, 13, TEXT))
		col.add_child(_label(str(item.get("description", "")), 11, DIM))
		row.add_child(col)

		if installed == "":
			var b := _button("安装", true)
			b.custom_minimum_size = Vector2(78, 30)
			b.pressed.connect(func(): _plugin_action(id, item, status))
			row.add_child(b)
		else:
			var u := _button("重装", false)
			u.custom_minimum_size = Vector2(66, 30)
			u.pressed.connect(func(): _plugin_action(id, item, status))
			row.add_child(u)
			var d := _button("卸载", false)
			d.custom_minimum_size = Vector2(66, 30)
			d.pressed.connect(func():
				PluginStore.uninstall(id)
				_fill_plugin_list(list_box, status))
			row.add_child(d)
		list_box.add_child(row)


func _plugin_action(id: String, item: Dictionary, status: Label) -> void:
	status.text = "正在安装 %s…" % id
	var ok: bool = await PluginStore.install(item)
	if ok:
		status.text = "%s 安装完成，当前共 %d 个工具" % [id, Plugins.tools().size()]
	else:
		status.text = "%s 安装失败" % id

# ---------------------------------------------------------------- 设置（新面板）
const SETTINGS_SCRIPT := "res://ui/settings_panel.gd"


func _open_settings(tab := "", detail := "") -> void:
	if _settings_layer:
		return
	var layer := ColorRect.new()
	layer.color = Color(0, 0, 0, 0.68)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_settings_layer = layer

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel: PanelContainer = load(SETTINGS_SCRIPT).new()
	center.add_child(panel)
	panel.setup(App, func():
		_close_settings()
		_rebuild_ui()
		_toast(I18N.t("settings_saved"))
		App.after_settings_saved())
	if tab != "":
		panel.call("_show_tab", tab)
	if detail != "":
		panel.call("_open_detail", detail)

# ---------------------------------------------------------------- 自动化钩子
## godot --headless --path . -- --tool compact_read [--args {"keep":2}]
func _requested_tool() -> String:
	var cli := OS.get_cmdline_user_args()
	for i in cli.size():
		if cli[i] == "--tool" and i + 1 < cli.size():
			return cli[i + 1]
	return ""


func _tool_args() -> Dictionary:
	# 命令行传 JSON 容易被 shell 吃掉引号，所以也支持环境变量
	var env := OS.get_environment("LH_TOOL_ARGS")
	if env.strip_edges() != "":
		var obj = JSON.parse_string(env)
		if obj is Dictionary:
			return obj
	var cli := OS.get_cmdline_user_args()
	for i in cli.size():
		if cli[i] == "--args" and i + 1 < cli.size():
			var obj = JSON.parse_string(cli[i + 1])
			if obj is Dictionary:
				return obj
	return {}


func _run_tool_and_quit(tool_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var res := Plugins.invoke(tool_name, _tool_args())
	print("[tool] %s -> ok=%s" % [tool_name, res.get("ok", false)])
	print(str(res.get("output", "")))
	get_tree().quit(0)

func _requested_serve() -> int:
	var cli := OS.get_cmdline_user_args()
	for i in cli.size():
		if cli[i] == "--serve" and i + 1 < cli.size():
			return int(cli[i + 1])
	return 0


## 常驻模式：开模型 + 开远程端点，用来做跨进程联调
func _run_serve_mode(port: int) -> void:
	App.start_server()
	await get_tree().create_timer(1.0).timeout
	var res := Plugins.invoke("remote_serve", {"port": port})
	print("[serve] " + str(res.get("output", "")))

# ---------------------------------------------------------------- 小弹窗
## 输入框弹窗：用于重命名
func _prompt(title: String, default_text: String, on_ok: Callable) -> void:
	var layer := ColorRect.new()
	layer.color = Color(0, 0, 0, 0.6)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var dlg := PanelContainer.new()
	dlg.custom_minimum_size = Vector2(380, 0)
	dlg.add_theme_stylebox_override("panel", _style(PANEL, 14, LINE))
	center.add_child(dlg)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 14)
	dlg.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)
	v.add_child(_label(title, 14, TEXT))

	var edit := LineEdit.new()
	edit.text = default_text
	edit.add_theme_font_override("font", _f(13))
	edit.add_theme_font_size_override("font_size", 13)
	edit.add_theme_stylebox_override("normal", _style(PANEL2, 8, LINE))
	edit.add_theme_color_override("font_color", TEXT)
	edit.custom_minimum_size = Vector2(0, 32)
	v.add_child(edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var cancel := _button(I18N.t("cancel"), false)
	cancel.custom_minimum_size = Vector2(80, 32)
	cancel.pressed.connect(func(): layer.queue_free())
	row.add_child(cancel)
	var ok := _button(I18N.t("save"), true)
	ok.custom_minimum_size = Vector2(80, 32)
	ok.pressed.connect(func():
		var val := edit.text
		layer.queue_free()
		on_ok.call(val))
	row.add_child(ok)
	v.add_child(row)

	edit.text_submitted.connect(func(t: String):
		layer.queue_free()
		on_ok.call(t))
	edit.call_deferred("grab_focus")
	edit.call_deferred("select_all")


## 确认弹窗：用于删除
func _confirm(title: String, text: String, on_ok: Callable) -> void:
	var layer := ColorRect.new()
	layer.color = Color(0, 0, 0, 0.6)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var dlg := PanelContainer.new()
	dlg.custom_minimum_size = Vector2(400, 0)
	dlg.add_theme_stylebox_override("panel", _style(PANEL, 14, LINE))
	center.add_child(dlg)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 14)
	dlg.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pad.add_child(v)
	v.add_child(_label(title, 14, TEXT))
	var body := _label(text, 12, DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(340, 0)
	v.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var cancel := _button(I18N.t("cancel"), false)
	cancel.custom_minimum_size = Vector2(80, 32)
	cancel.pressed.connect(func(): layer.queue_free())
	row.add_child(cancel)
	var ok := _button(I18N.t("delete"), true)
	ok.custom_minimum_size = Vector2(80, 32)
	ok.pressed.connect(func():
		layer.queue_free()
		on_ok.call())
	row.add_child(ok)
	v.add_child(row)


## 发完消息把当前会话挪到列表最上面
func _promote_current_chat() -> void:
	if App.current_chat <= 0 or App.current_chat >= App.chats.size():
		return
	var c: Dictionary = App.chats[App.current_chat]
	App.chats.remove_at(App.current_chat)
	App.chats.insert(0, c)
	App.current_chat = 0

# ---------------------------------------------------------------- 提示条
var _toast_node: PanelContainer = null


## 底部浮出的短提示，2 秒后自动消失
func _toast(text: String) -> void:
	if _toast_node != null and is_instance_valid(_toast_node):
		_toast_node.queue_free()
		_toast_node = null
	var chip := PanelContainer.new()
	var st := _style(Color("#1e2635"), 10, ACCENT)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	chip.add_theme_stylebox_override("panel", st)
	chip.add_child(_label(text, 12, TEXT))
	chip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	chip.offset_left = -120
	chip.offset_right = 120
	chip.offset_top = -66
	chip.offset_bottom = -30
	add_child(chip)
	_toast_node = chip
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(chip, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func():
		if is_instance_valid(chip):
			chip.queue_free())


## 语言切换后整块重建界面（文字都是构建时写死的）
func _rebuild_ui() -> void:
	var cur := App.current_chat
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_settings_layer = null
	_plugin_layer = null
	_toast_node = null
	_stream_label = null
	_waiting = false
	_agent_running = false
	_build_ui()
	_refresh_header()
	if App.chats.size() > 0:
		_open_chat(clampi(cur, 0, App.chats.size() - 1))
	# 重建后把服务状态显示补回来，否则右上角是空的
	if App.provider() == "api":
		_on_server_state("ready" if App.chat_ready() else "starting")
	elif App.server_up:
		_on_server_state("ready")
	else:
		_on_server_state("starting")
	_composer.grab_focus()


func _on_language_changed(_lang: String) -> void:
	_rebuild_ui()
	_toast(I18N.t("settings_saved") if _toast_node == null else "")


## 插件设置里点了「恢复默认」：关掉重开，让控件回到默认值
func _reopen_plugin_panel(plugin_id: String) -> void:
	if _quick_layer != null:
		_quick_layer.queue_free()
		_quick_layer = null
	_open_plugin_panel(plugin_id)

## 一轮生成结束：把流式用的富文本换成 MDView（支持表格/图片）
func _finish_stream_into_view() -> void:
	if _stream_col == null or not is_instance_valid(_stream_col):
		return
	for c in _stream_col.get_children():
		_stream_col.remove_child(c)
		c.queue_free()
	var view := MDView.build(_sanitize(_stream_raw), 14)
	_stream_col.add_child(view)
	_stream_label = null
	_stream_col = null
	_scroll_to_bottom()

## 调试：渲染一段 Markdown 并打印控件树（验证表格/公式/图片块解析）
func _run_mdtest() -> void:
	var sample := """# 标题

| 猫粮 | 价格 | 蛋白质 |
| --- | --- | --- |
| A | 49.99 | 22% |
| B | 59.99 | 28% |

质能方程 $E=mc^2$，分式 $$\\frac{a+b}{c}$$ 也要能看。

$$
\\frac{1}{2} \\times \\sqrt{x^2 + y^2}
$$

![图](C:/nonexist.png)
"""
	var node := MDView.build(sample, 14)
	add_child(node)
	await get_tree().process_frame
	await get_tree().process_frame
	_dump(node, 0)
	print("[mdtest] 完成")
	get_tree().quit(0)


func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	if n is RichTextLabel:
		var rt: RichTextLabel = n
		print("%sRichText: %s" % [pad, rt.text.replace("\n", " ⏎ ").substr(0, 160)])
	elif n is Label:
		print("%sLabel: %s" % [pad, (n as Label).text])
	elif n is GridContainer:
		print("%sGrid(%d cols, %d cells)" % [pad, (n as GridContainer).columns, n.get_child_count()])
	elif n is TextureRect:
		print("%sTexture %s" % [pad, str((n as TextureRect).texture)])
	else:
		print("%s%s" % [pad, n.get_class()])
	for c in n.get_children():
		_dump(c, depth + 1)


## 执行 /命令：结果以气泡形式写进当前会话
func _run_slash_command(text: String) -> void:
	var body := text.substr(1)
	var parts := body.split(" ", false, 1)
	var cmd := parts[0] if parts.size() > 0 else ""
	var args := parts[1].strip_edges() if parts.size() > 1 else ""
	if cmd == "":
		_toast("输入 /命令名，例如 /shot 或 /mem 要记住的话")
		return
	var chat: Dictionary = App.chats[App.current_chat]
	var msgs: Array = chat.get("messages", [])
	msgs.append({"role": "user", "content": text})
	_add_bubble("user", text)
	_waiting = true
	_set_send_enabled(false)
	var res: Dictionary = await Plugins.run_command_async(cmd, args)
	var out := str(res.get("output", ""))
	var ok := bool(res.get("ok", false))
	_add_bubble("assistant", ("✅ " if ok else "⚠️ ") + out)
	msgs.append({"role": "assistant", "content": out, "hidden": true})
	App.save_current()
	_refresh_chat_list()
	_waiting = false
	_set_send_enabled(true)
	_toast(("命令 /%s 执行完成" % cmd) if ok else ("命令 /%s 失败" % cmd))


## 调试：慢工具执行期间主循环是否还在转（帧数明显大于 0 说明界面没卡死）
func _run_asynctest() -> void:
	var f0 := Engine.get_process_frames()
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = await Plugins.invoke_async("terminal_run", {"command": "ping -n 6 127.0.0.1"})
	var frames := Engine.get_process_frames() - f0
	print("[asynctest] 耗时 %d ms，主循环帧数 %d，工具 ok=%s" % [
		Time.get_ticks_msec() - t0, frames, result.get("ok", false)])
	print(str(result.get("output", "")).substr(0, 160))
	get_tree().quit(0)


## 调试：打印每个模型的自动检测结果
func _run_modeltest() -> void:
	var vram := int(App.gpu.get("vram_mb", 0))
	var info := OS.get_memory_info()
	var ram := int(float(info.get("physical", 0)) / 1048576.0)
	print("[modeltest] 显存 %d MB，内存 %d MB，CPU %d 线程" % [vram, ram, OS.get_processor_count()])
	for m in App.models:
		var t0 := Time.get_ticks_msec()
		print("—— %s" % str(m["label"]))
		var p: Dictionary = GGUF.effective(str(m["path"]), vram, ram)
		print("   （解析耗时 %d ms）" % (Time.get_ticks_msec() - t0))
		print("   %s · %s · 参数 %d · 层 %d · 原生上下文 %d · 模板 %s" % [
			p["family"], p["quant"], p["params"], p["layers"], p["native_ctx"], p["template_kind"]])
		print("   文件 %d MB · 每 token KV %d 字节 · 推荐 ngl=%d ctx=%d 线程=%d" % [
			p["size_mb"], p["kv_per_token"], p["ngl"], p["ctx"], p["threads"]])
		if str(p["note"]) != "":
			print("   提示：%s" % str(p["note"]))
	print("[modeltest] 完成")
	get_tree().quit(0)


## 体检：启动耗时 / 渲染耗时 / 工具线程响应 / 内存
func _run_bench() -> void:
	var t_start := Time.get_ticks_usec()
	print("=== Local-Harness 体检 ===")
	print("启动到界面就绪：%.0f ms" % ((Time.get_ticks_usec() - t_start) / 1000.0))

	# 1) 渲染 60 条气泡
	_add_bubble("user", "渲染测试开始", false)
	var t1 := Time.get_ticks_usec()
	for i in 60:
		_add_bubble("assistant", "第 %d 条：**加粗** 与 `代码` 和 | 表格 | 混排" % i, false)
	var render_ms := (Time.get_ticks_usec() - t1) / 1000.0
	print("渲染 60 条气泡：%.0f ms（每条 %.1f ms）" % [render_ms, render_ms / 60.0])

	# 2) 60 条都切到 MDView（表格/公式路径）
	var t2 := Time.get_ticks_usec()
	for i in 20:
		var n := MDView.build("| 列A | 列B |\n| --- | --- |\n| %d | $x^2$ |" % i, 14)
		add_child(n)
		n.queue_free()
	print("渲染 20 个含表格+公式的块：%.0f ms" % ((Time.get_ticks_usec() - t2) / 1000.0))

	# 3) 工具线程：慢命令期间主循环帧数
	var f0 := Engine.get_process_frames()
	var t3 := Time.get_ticks_usec()
	var res: Dictionary = await Plugins.invoke_async("terminal_run", {"command": "ping -n 4 127.0.0.1"})
	var frames := Engine.get_process_frames() - f0
	var tool_ms := (Time.get_ticks_usec() - t3) / 1000.0
	print("工具执行 %.0f ms 期间主循环 %d 帧（%.0f fps）→ %s" % [
		tool_ms, frames, frames * 1000.0 / max(tool_ms, 1.0), "不卡" if frames > 20 else "可能卡住"])

	# 4) 进程与内存
	var info := OS.get_memory_info()
	print("本进程内存：%.0f MB（静态内存）" % (float(OS.get_static_memory_usage()) / 1048576.0))
	print("系统可用内存：%.0f MB / 总计 %.0f MB" % [
		float(info.get("free", 0)) / 1048576.0, float(info.get("physical", 0)) / 1048576.0])
	print("插件 %d 个，工具 %d 个，会话 %d 个" % [Plugins.loaded.size(), Plugins.tools().size(), App.chats.size()])

	# 5) 模型档案解析耗时
	var t5 := Time.get_ticks_usec()
	for m in App.models:
		GGUF.profile(str(m["path"]), int(App.gpu.get("vram_mb", 0)), 16384)
	print("解析 %d 个模型档案：%.0f ms" % [App.models.size(), (Time.get_ticks_usec() - t5) / 1000.0])

	print("=== 体检结束 ===")
	get_tree().quit(0)


## 把更早的消息一条条插到最前面（不阻塞界面）
func _fill_older_messages(visible: Array, count: int) -> void:
	var made := 0
	for i in range(count - 1, -1, -1):
		var m: Dictionary = visible[i]
		var body := _add_bubble(str(m.get("role", "user")), str(m.get("content", "")), false)
		var row: Node = body
		while row != null and not (row is HBoxContainer):
			row = row.get_parent()
		if row != null:
			_msg_box.move_child(row, 0)
		made += 1
		if made % 3 == 0:
			await get_tree().process_frame

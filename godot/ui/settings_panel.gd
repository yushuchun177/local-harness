extends PanelContainer
## SettingsPanel —— 设置面板：左侧四个分类（通用 / 模型 / 插件管理 / 开源协议）。
##
## 独立成文件，main.gd 只负责盖一层半透明遮罩把它放进来。

const BG := Color("#0b0d12")
const PANEL := Color("#141821")
const PANEL2 := Color("#1b202b")
const LINE := Color("#232936")
const TEXT := Color("#e6eaf2")
const DIM := Color("#93a0b4")
const FAINT := Color("#5d6a7e")
const ACCENT := Color("#5b8def")

var app: Node
var on_close: Callable = Callable()
var font: FontFile

var tab: String = "general"
var draft: Dictionary = {}   # 所有分类的编辑值都先存这里
var _content: VBoxContainer
var _tab_buttons: Dictionary = {}
var _status: Label

# 控件引用（保存时读取）
var _lang_box: OptionButton
var _user_edit: LineEdit
var _ai_edit: LineEdit
var _sys_edit: TextEdit
var _steps_spin: SpinBox
var _src_box: OptionButton
var _model_box: OptionButton
var _backend_box: OptionButton
var _layers_spin: SpinBox
var _ctx_spin: SpinBox
var _temp_spin: SpinBox
var _max_spin: SpinBox
var _api_base: LineEdit
var _api_key: LineEdit
var _api_model: LineEdit
var _vision_model: LineEdit
var _vision_mmproj: LineEdit
var _api_list: OptionButton
var _license_layer: ColorRect = null


func setup(app_node: Node, close_cb: Callable) -> void:
	app = app_node
	on_close = close_cb
	draft = app.cfg.duplicate(true)
	_load_font()
	add_theme_stylebox_override("panel", _style(PANEL, 16, LINE))
	custom_minimum_size = Vector2(860, 600)
	_build()
	var want := OS.get_environment("LH_TAB")
	if want != "":
		tab = want
	var detail := OS.get_environment("LH_PLUGIN_DETAIL")
	if detail != "":
		tab = "plugins"
	_show_tab(tab)
	if detail != "":
		_open_detail(detail)


# ---------------------------------------------------------------- 基础
func _load_font() -> void:
	for p in ["C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf"]:
		if FileAccess.file_exists(p):
			font = FontFile.new()
			font.load_dynamic_font(p)
			return


func _f(size: int, bold := false) -> Font:
	if font == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = font
	fv.variation_embolden = 0.6 if bold else 0.0
	return fv


func _style(bg: Color, radius := 10, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _label(text: String, size := 13, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _f(size))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, accent := false, small := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _f(12 if small else 13, accent))
	b.add_theme_font_size_override("font_size", 12 if small else 13)
	b.custom_minimum_size = Vector2(0, 28 if small else 34)
	if accent:
		b.add_theme_stylebox_override("normal", _style(ACCENT, 8))
		b.add_theme_stylebox_override("hover", _style(ACCENT.lightened(0.08), 8))
		b.add_theme_color_override("font_color", Color("#0b1220"))
		b.add_theme_color_override("font_hover_color", Color("#0b1220"))
	else:
		b.add_theme_stylebox_override("normal", _style(PANEL2, 8, LINE))
		b.add_theme_stylebox_override("hover", _style(PANEL2.lightened(0.06), 8, LINE))
		b.add_theme_color_override("font_color", TEXT)
	return b


func _edit(text: String, ph := "") -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = ph
	e.add_theme_font_override("font", _f(12))
	e.add_theme_font_size_override("font_size", 12)
	e.add_theme_stylebox_override("normal", _style(PANEL2, 8, LINE))
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", FAINT)
	e.custom_minimum_size = Vector2(0, 30)
	return e


# ---------------------------------------------------------------- 布局
func _build() -> void:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 12)
	add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	v.add_child(body)

	# 左侧分类
	var rail := VBoxContainer.new()
	rail.custom_minimum_size = Vector2(168, 0)
	rail.add_theme_constant_override("separation", 6)
	body.add_child(rail)
	for key in ["general", "model", "plugins", "license"]:
		var b := Button.new()
		b.text = I18N.t("tab_" + key)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_override("font", _f(13))
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _style(Color("#12151d"), 10))
		b.add_theme_stylebox_override("hover", _style(Color("#1a2130"), 10))
		b.add_theme_stylebox_override("pressed", _style(Color("#1e2635"), 10))
		b.add_theme_color_override("font_color", DIM)
		b.pressed.connect(_show_tab.bind(key))
		_tab_buttons[key] = b
		rail.add_child(b)

	# 右侧内容
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	body.add_child(scroll)

	# 底部
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	_status = _label("", 11, FAINT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_status)
	var cancel := _button(I18N.t("cancel"))
	cancel.custom_minimum_size = Vector2(92, 34)
	cancel.pressed.connect(_close)
	bottom.add_child(cancel)
	var save := _button(I18N.t("save"), true)
	save.custom_minimum_size = Vector2(92, 34)
	save.pressed.connect(_save)
	bottom.add_child(save)
	v.add_child(bottom)


func _show_tab(key: String) -> void:
	_capture()
	tab = key
	for k in _tab_buttons.keys():
		var b: Button = _tab_buttons[k]
		var on: bool = (k == key)
		b.add_theme_stylebox_override("normal", _style(Color("#1e2635") if on else Color("#12151d"), 10))
		b.add_theme_color_override("font_color", TEXT if on else DIM)
	for c in _content.get_children():
		c.queue_free()
	match key:
		"general":
			_build_general()
		"model":
			_build_model()
		"plugins":
			_build_plugins()
		"license":
			_build_license()


# ---------------------------------------------------------------- 通用
func _build_general() -> void:
	_content.add_child(_label(I18N.t("tab_general"), 17, TEXT))
	_content.add_child(_label(I18N.t("hint_save"), 11, FAINT))

	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 10)
	lrow.add_child(_label(I18N.t("general_lang"), 13, DIM))
	_lang_box = OptionButton.new()
	_lang_box.add_item("简体中文")
	_lang_box.add_item("English")
	_lang_box.select(1 if str(draft.get("lang", "zh")) == "en" else 0)
	_lang_box.custom_minimum_size = Vector2(160, 30)
	_lang_box.add_theme_font_override("font", _f(12))
	_lang_box.add_theme_stylebox_override("normal", _style(PANEL2, 8, LINE))
	_lang_box.add_theme_color_override("font_color", TEXT)
	lrow.add_child(_lang_box)
	_content.add_child(lrow)

	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 10)
	nrow.add_child(_label(I18N.t("general_user"), 13, DIM))
	_user_edit = _edit(str(draft.get("user_name", "你")))
	_user_edit.custom_minimum_size = Vector2(130, 30)
	nrow.add_child(_user_edit)
	nrow.add_child(_label("   " + I18N.t("general_ai"), 13, DIM))
	_ai_edit = _edit(str(draft.get("assistant_name", "助手")))
	_ai_edit.custom_minimum_size = Vector2(130, 30)
	nrow.add_child(_ai_edit)
	_content.add_child(nrow)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	srow.add_child(_label(I18N.t("general_steps"), 13, DIM))
	_steps_spin = SpinBox.new()
	_steps_spin.min_value = 0
	_steps_spin.max_value = 12
	_steps_spin.value = int(draft.get("max_steps", 4))
	_steps_spin.custom_minimum_size = Vector2(80, 30)
	srow.add_child(_steps_spin)
	srow.add_child(_label(I18N.t("general_steps_hint"), 11, FAINT))
	_content.add_child(srow)

	_content.add_child(_label(I18N.t("general_system"), 13, DIM))
	_sys_edit = TextEdit.new()
	_sys_edit.text = str(draft.get("system", ""))
	_sys_edit.custom_minimum_size = Vector2(0, 110)
	_sys_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_sys_edit.add_theme_font_override("font", _f(12))
	_sys_edit.add_theme_stylebox_override("normal", _style(PANEL2, 9, LINE))
	_sys_edit.add_theme_color_override("font_color", TEXT)
	_content.add_child(_sys_edit)


# ---------------------------------------------------------------- 模型
func _build_model() -> void:
	_content.add_child(_label(I18N.t("tab_model"), 17, TEXT))

	# 来源：本地 / 在线。选哪个就只展开哪一块
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	srow.add_child(_label(I18N.t("model_source"), 13, DIM))
	_src_box = OptionButton.new()
	_src_box.add_item(I18N.t("source_local"))
	_src_box.add_item(I18N.t("source_api"))
	_src_box.select(1 if str(draft.get("provider", "local")) == "api" else 0)
	_src_box.custom_minimum_size = Vector2(180, 30)
	_src_box.add_theme_font_override("font", _f(12))
	_src_box.add_theme_stylebox_override("normal", _style(PANEL2, 8, LINE))
	_src_box.add_theme_color_override("font_color", TEXT)
	srow.add_child(_src_box)
	_content.add_child(srow)

	var local_group := VBoxContainer.new()
	local_group.add_theme_constant_override("separation", 8)
	_content.add_child(local_group)

	var api_group := VBoxContainer.new()
	api_group.add_theme_constant_override("separation", 8)
	_content.add_child(api_group)

	# ---------------- 本地 llama.cpp ----------------
	local_group.add_child(_section_head(I18N.t("source_local")))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 10)
	mrow.add_child(_label(I18N.t("model_pick"), 13, DIM))
	_model_box = OptionButton.new()
	_model_box.custom_minimum_size = Vector2(280, 30)
	_model_box.add_theme_font_override("font", _f(12))
	_model_box.add_theme_stylebox_override("normal", _style(PANEL2, 8, LINE))
	_model_box.add_theme_color_override("font_color", TEXT)
	for i in app.models.size():
		_model_box.add_item(app.models[i]["label"])
		if app.models[i]["path"] == str(draft.get("model", app.current_model)):
			_model_box.select(i)
	mrow.add_child(_model_box)
	local_group.add_child(mrow)

	local_group.add_child(_model_dirs_block())
	local_group.add_child(_model_profile_card())

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	brow.add_child(_label(I18N.t("model_backend"), 13, DIM))
	_backend_box = OptionButton.new()
	var keys := ["auto", "cpu", "cuda", "vulkan"]
	var names := ["自动", "CPU", "CUDA", "Vulkan"] if I18N.lang == "zh" else ["Auto", "CPU", "CUDA", "Vulkan"]
	for i in keys.size():
		_backend_box.add_item(names[i])
		if str(draft.get("backend", "auto")) == keys[i]:
			_backend_box.select(i)
	_backend_box.custom_minimum_size = Vector2(140, 30)
	_backend_box.add_theme_font_override("font", _f(12))
	_backend_box.add_theme_stylebox_override("normal", _style(PANEL2, 8, LINE))
	_backend_box.add_theme_color_override("font_color", TEXT)
	brow.add_child(_backend_box)
	brow.add_child(_label("   " + I18N.t("model_layers"), 13, DIM))
	_layers_spin = SpinBox.new()
	_layers_spin.min_value = -1
	_layers_spin.max_value = 200
	_layers_spin.value = int(draft.get("gpu_layers", -1))
	_layers_spin.custom_minimum_size = Vector2(80, 30)
	_layers_spin.tooltip_text = "-1 = 按模型自动（推荐）"
	brow.add_child(_layers_spin)
	local_group.add_child(brow)

	# ---------------- 在线 API ----------------
	api_group.add_child(_section_head(I18N.t("source_api")))
	api_group.add_child(_label(I18N.t("api_hint"), 11, FAINT))

	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 10)
	arow.add_child(_label(I18N.t("api_base"), 13, DIM))
	_api_base = _edit(str(draft.get("api_base", "")), I18N.t("api_base_ph"))
	_api_base.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(_api_base)
	api_group.add_child(arow)

	var krow := HBoxContainer.new()
	krow.add_theme_constant_override("separation", 10)
	krow.add_child(_label(I18N.t("api_key"), 13, DIM))
	_api_key = _edit(str(draft.get("api_key", "")), I18N.t("api_key_ph"))
	_api_key.secret = true
	_api_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	krow.add_child(_api_key)
	api_group.add_child(krow)

	var mrow2 := HBoxContainer.new()
	mrow2.add_theme_constant_override("separation", 10)
	mrow2.add_child(_label(I18N.t("api_model"), 13, DIM))
	_api_model = _edit(str(draft.get("api_model", "")), I18N.t("api_model_ph"))
	_api_model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow2.add_child(_api_model)
	var fetch := _button(I18N.t("api_fetch"), false, true)
	fetch.custom_minimum_size = Vector2(110, 28)
	fetch.pressed.connect(_fetch_models)
	mrow2.add_child(fetch)
	api_group.add_child(mrow2)

	# ---------------- 通用：上下文 / 温度 / 回复上限 ----------------
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 10)
	prow.add_child(_label(I18N.t("model_ctx"), 13, DIM))
	_ctx_spin = SpinBox.new()
	_ctx_spin.min_value = 512
	_ctx_spin.max_value = 65536
	_ctx_spin.step = 512
	_ctx_spin.value = int(draft.get("ctx", 4096))
	_ctx_spin.custom_minimum_size = Vector2(100, 30)
	prow.add_child(_ctx_spin)
	prow.add_child(_label("   " + I18N.t("model_temp"), 13, DIM))
	_temp_spin = SpinBox.new()
	_temp_spin.min_value = 0.0
	_temp_spin.max_value = 2.0
	_temp_spin.step = 0.05
	_temp_spin.value = float(draft.get("temp", 0.7))
	_temp_spin.custom_minimum_size = Vector2(80, 30)
	prow.add_child(_temp_spin)
	prow.add_child(_label("   " + I18N.t("model_maxtok"), 13, DIM))
	_max_spin = SpinBox.new()
	_max_spin.min_value = 64
	_max_spin.max_value = 8192
	_max_spin.step = 64
	_max_spin.value = int(draft.get("max_tokens", 512))
	_max_spin.custom_minimum_size = Vector2(90, 30)
	prow.add_child(_max_spin)
	_content.add_child(prow)

	# 折叠：选哪个来源就只展开哪一块
	var apply_fold := func():
		var online: bool = _src_box.selected == 1
		local_group.visible = not online
		api_group.visible = online
		_ctx_spin.visible = not online
	_src_box.item_selected.connect(func(_i: int): apply_fold.call())
	apply_fold.call()


## 小标题：— 本地 llama.cpp —
func _section_head(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var left := ColorRect.new()
	left.color = LINE
	left.custom_minimum_size = Vector2(14, 1)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	row.add_child(_label(text, 12, FAINT))
	var right := ColorRect.new()
	right.color = LINE
	right.custom_minimum_size = Vector2(14, 1)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	return row


func _fetch_models() -> void:
	_status.text = I18N.t("api_fetch") + "…"
	app.set_cfg("api_base", _api_base.text.strip_edges())
	app.set_cfg("api_key", _api_key.text.strip_edges())
	var list: Array = await app.fetch_api_models()
	_api_list.clear()
	if list.is_empty():
		_status.text = "× " + I18N.t("api_fetch")
		return
	for id in list:
		_api_list.add_item(str(id))
	_status.text = "%d models" % list.size()


# ---------------------------------------------------------------- 插件
var _plugin_query: String = ""
var _plugin_box: VBoxContainer = null


func _build_plugins() -> void:
	_content.add_child(_label(I18N.t("tab_plugins"), 17, TEXT))
	_content.add_child(_label(I18N.t("plugins_note"), 10, FAINT))

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	var search := _edit(_plugin_query, I18N.t("plugins_search_ph"))
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(t: String):
		_plugin_query = t
		_render_plugins())
	srow.add_child(search)
	var refresh := _button(I18N.t("plugins_refresh"), false, true)
	refresh.pressed.connect(func(): _show_tab("plugins"))
	srow.add_child(refresh)
	_content.add_child(srow)

	_content.add_child(_label(I18N.t("plugins_tools") % Plugins.tools().size(), 11, FAINT))

	_plugin_box = VBoxContainer.new()
	_plugin_box.add_theme_constant_override("separation", 8)
	_content.add_child(_plugin_box)
	_fetch_then_render()


func _fetch_then_render() -> void:
	_status.text = I18N.t("plugins_loading")
	var ok: bool = await PluginStore.fetch_index()
	if not ok:
		_status.text = I18N.t("plugins_failed")
	_render_plugins()


## 只渲染，不联网；搜索框每次输入都走这里
func _render_plugins() -> void:
	var box := _plugin_box
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	var q := _plugin_query.strip_edges().to_lower()
	var items: Array = []
	for it in PluginStore.catalog:
		if q == "":
			items.append(it)
			continue
		var hay := (str(it.get("name", "")) + str(it.get("name_en", "")) + str(it.get("description", ""))
			+ str(it.get("description_en", "")) + str(it.get("id", ""))).to_lower()
		if hay.find(q) >= 0:
			items.append(it)
	_status.text = I18N.t("plugins_count") % items.size()
	for item in items:
		var id := str(item.get("id", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		var installed := PluginStore.installed_version(id)
		var disp := str(item.get("name_en", item.get("name", id))) if I18N.lang == "en" else str(item.get("name", id))
		var title := "%s  v%s" % [disp, str(item.get("version", "?"))]
		if installed != "":
			title += "   · v" + installed
		col.add_child(_label(title, 13, TEXT))
		var desc := str(item.get("description_en", item.get("description", ""))) if I18N.lang == "en" else str(item.get("description", ""))
		col.add_child(_label(desc, 10, DIM))
		row.add_child(col)
		if installed == "":
			var b := _button(I18N.t("plugins_install"), true, true)
			b.custom_minimum_size = Vector2(76, 28)
			b.pressed.connect(func(): _do_install(id, item, box))
			row.add_child(b)
		else:
			var u := _button(I18N.t("plugins_reinstall"), false, true)
			u.custom_minimum_size = Vector2(70, 28)
			u.pressed.connect(func(): _do_install(id, item, box))
			row.add_child(u)
			var d := _button(I18N.t("plugins_remove"), false, true)
			d.custom_minimum_size = Vector2(66, 28)
			d.pressed.connect(func():
				PluginStore.uninstall(id)
				_show_tab("plugins"))
			row.add_child(d)
		box.add_child(row)


func _do_install(id: String, item: Dictionary, box: VBoxContainer) -> void:
	_status.text = I18N.t("plugins_installing") % id
	var ok: bool = await PluginStore.install(item)
	if ok:
		_status.text = I18N.t("plugins_done") % [id, Plugins.tools().size()]
	else:
		_status.text = I18N.t("plugins_fail") % id
	# 整页重绘，顺便刷新工具数量
	_show_tab("plugins")


# ---------------------------------------------------------------- 协议
func _build_license() -> void:
	_content.add_child(_label(I18N.t("license_title"), 17, TEXT))
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rich.add_theme_font_override("normal_font", _f(12))
	rich.add_theme_font_size_override("normal_font_size", 12)
	rich.add_theme_color_override("default_color", Color(0.62, 0.68, 0.78))
	var links := "[url=https://github.com/yushuchun177/local-harness]source[/url]" if I18N.lang == "en" \
		else "[url=https://github.com/yushuchun177/local-harness]源码[/url]"
	rich.text = I18N.t("license_intro") % ["Local-Harness", "4.7.2"]
	rich.meta_clicked.connect(func(u: String): OS.shell_open(u))
	_content.add_child(rich)
	var b := _button(I18N.t("license_view"), false)
	b.custom_minimum_size = Vector2(140, 32)
	b.pressed.connect(_show_licenses)
	_content.add_child(b)


func _show_licenses() -> void:
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
	dlg.custom_minimum_size = Vector2(720, 520)
	dlg.add_theme_stylebox_override("panel", _style(PANEL, 16, LINE))
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
	v.add_child(_label(I18N.t("license_title"), 16, TEXT))

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_override("font", _f(12))
	v.add_child(tabs)
	for item in [["GPL-3.0", "res://LICENSES/GPL-3.0.txt"],
			["MIT · Godot", "res://LICENSES/MIT-Godot.txt"],
			["MIT · llama.cpp", "res://LICENSES/MIT-llama.cpp.txt"]]:
		var sc := ScrollContainer.new()
		sc.name = str(item[0])
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var t := Label.new()
		var f := FileAccess.open(str(item[1]), FileAccess.READ)
		t.text = f.get_as_text() if f else "missing: " + str(item[1])
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_theme_font_override("font", _f(10))
		t.add_theme_font_size_override("font_size", 10)
		t.add_theme_color_override("font_color", Color(0.82, 0.85, 0.9, 0.9))
		sc.add_child(t)
		tabs.add_child(sc)

	var row := HBoxContainer.new()
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var close := _button(I18N.t("close"), true)
	close.custom_minimum_size = Vector2(90, 32)
	close.pressed.connect(func():
		layer.queue_free()
		_license_layer = null)
	row.add_child(close)
	v.add_child(row)


# ---------------------------------------------------------------- 保存
## 把当前可见控件里的值收进 draft（切页/保存前都调用）
func _capture() -> void:
	if _lang_box != null:
		draft["lang"] = "en" if _lang_box.selected == 1 else "zh"
	if _user_edit != null:
		draft["user_name"] = _user_edit.text.strip_edges()
	if _ai_edit != null:
		draft["assistant_name"] = _ai_edit.text.strip_edges()
	if _sys_edit != null:
		draft["system"] = _sys_edit.text
	if _steps_spin != null:
		draft["max_steps"] = int(_steps_spin.value)
	if _src_box != null:
		draft["provider"] = "api" if _src_box.selected == 1 else "local"
	if _model_box != null and _model_box.selected >= 0 and _model_box.selected < app.models.size():
		draft["model"] = str(app.models[_model_box.selected]["path"])
	if _backend_box != null and _backend_box.selected >= 0:
		draft["backend"] = ["auto", "cpu", "cuda", "vulkan"][_backend_box.selected]
	if _layers_spin != null:
		draft["gpu_layers"] = int(_layers_spin.value)
	if _ctx_spin != null:
		draft["ctx"] = int(_ctx_spin.value)
	if _temp_spin != null:
		draft["temp"] = float(_temp_spin.value)
	if _max_spin != null:
		draft["max_tokens"] = int(_max_spin.value)
	if _api_base != null:
		draft["api_base"] = _api_base.text.strip_edges()
	if _api_key != null:
		draft["api_key"] = _api_key.text.strip_edges()
	if _api_model != null:
		draft["api_model"] = _api_model.text.strip_edges()
	if _vision_model != null:
		draft["vision_model"] = _vision_model.text.strip_edges()
	if _vision_mmproj != null:
		draft["vision_mmproj"] = _vision_mmproj.text.strip_edges()


func _save() -> void:
	_capture()
	var keys := ["lang", "user_name", "assistant_name", "system", "max_steps",
		"provider", "model", "backend", "gpu_layers", "ctx", "temp", "max_tokens",
		"api_base", "api_key", "api_model", "vision_model", "vision_mmproj"]
	for k in keys:
		if draft.has(k):
			app.set_cfg(k, draft[k])
	app.current_model = str(app.cfg.get("model", app.current_model))
	I18N.set_lang(str(app.cfg.get("lang", "zh")))
	_close()
	if app.has_method("after_settings_saved"):
		app.after_settings_saved()


func _close() -> void:
	if on_close.is_valid():
		on_close.call()

# ---------------------------------------------------------------- 插件详情
## 详情页 = 插件自带的 ui.gd + 主程序提供的外框（返回按钮 / 标题）。
## 界面内容是插件写的，主程序不认识任何插件的配置项。
func _open_detail(plugin_id: String) -> void:
	for c in _content.get_children():
		c.queue_free()
	var p: Dictionary = Plugins.find_plugin(plugin_id)
	var m: Dictionary = p.get("manifest", {}) if not p.is_empty() else {}

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var back := _button(I18N.t("plugins_back"), false, true)
	back.custom_minimum_size = Vector2(72, 28)
	back.pressed.connect(func(): _show_tab("plugins"))
	head.add_child(back)
	head.add_child(_label("%s  v%s" % [str(m.get("name", plugin_id)), str(m.get("version", "?"))], 17, TEXT))
	_content.add_child(head)

	var ui_path := str(p.get("dir", "")).path_join("ui.gd")
	var hosted := false
	if FileAccess.file_exists(ui_path):
		var scr = load(ui_path)
		if scr is GDScript and scr.can_instantiate():
			var node = scr.new()
			if node is Control and node.has_method("build"):
				var ctl: Control = node
				ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_content.add_child(ctl)
				ctl.call("build", plugin_id)
				hosted = true
			else:
				node.queue_free()
	if not hosted:
		var fb = PluginUI.fallback(plugin_id)
		if fb is Control:
			(fb as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_content.add_child(fb)

# ---------------------------------------------------------------- 模型自动适配
## 用 GGUF 元数据 + 本机显存内存，算出这个模型该用多少层、多大上下文。
## 结论只对这个模型生效，存在 user://models/models.json 里。
func _model_profile_card() -> Control:
	var prof: Dictionary = app.profile_for()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(Color("#12161e"), 10, LINE))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_label(I18N.t("profile_title"), 13, TEXT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_label("仅对当前模型生效", 10, FAINT))
	v.add_child(head)

	if prof.is_empty():
		v.add_child(_label("还没选模型，或者这个 GGUF 读不出元数据。", 11, FAINT))
		return card

	var params_yi := float(prof["params"]) / 100000000.0
	var kv_kb := int(prof["kv_per_token"]) / 1024
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 3)
	var rows := [
		["架构", str(prof["family"]), "量化", str(prof["quant"])],
		["参数量", "%.1f 亿" % params_yi, "层数", str(prof["layers"])],
		["原生上下文", str(prof["native_ctx"]), "文件大小", "%d MB" % int(prof["size_mb"])],
		["每 token 缓存", "%d KB" % kv_kb, "推荐线程", str(prof["rec_threads"])],
	]
	for r in rows:
		for i in 4:
			grid.add_child(_label(str(r[i]), 11, FAINT if i % 2 == 0 else DIM))
	v.add_child(grid)

	# 推荐值 + 一键适配
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 10)
	var rec := _label("推荐：GPU 层数 %d / 上下文 %d" % [int(prof["rec_ngl"]), int(prof["rec_ctx"])], 11, DIM)
	rec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(rec)
	var use := _button("按推荐适配", true, true)
	use.custom_minimum_size = Vector2(110, 28)
	use.pressed.connect(func():
		app.set_cfg("gpu_layers", int(prof["rec_ngl"]))
		app.set_cfg("ctx", int(prof["rec_ctx"]))
		app.set_model_override({"ngl": int(prof["rec_ngl"]), "ctx": int(prof["rec_ctx"])})
		_status.text = "已按推荐适配，保存后生效")
	act.add_child(use)
	v.add_child(act)

	# 支持范围写清楚
	v.add_child(_label("适配范围：130B 及以下（含）模型，按 GGUF 文件头自动计算", 10, DIM))

	if str(prof.get("note", "")) != "":
		var note := _label("⚠ " + str(prof["note"]), 10, Color("#e0a458"))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(note)

	if bool(prof.get("has_override", false)):
		v.add_child(_label("这个模型已经单独适配过（覆盖了自动推荐）", 10, FAINT))
	return card

# ---------------------------------------------------------------- 模型文件夹
## 导入任意目录（可多个），加完立刻扫描并自动适配
func _model_dirs_block() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(Color("#12161e"), 10, LINE))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_label("模型文件夹", 13, TEXT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_label("%d 个模型" % app.models.size(), 10, FAINT))
	v.add_child(head)
	v.add_child(_label("可以放在任意位置，导入后自动扫描、自动适配（不用配置参数）", 10, FAINT))

	# 已有目录
	var dirs: Array = app.cfg.get("model_dirs", [])
	var default_dir: String = app.base_dir.path_join("model")
	var shown: Array = [default_dir]
	shown.append_array(dirs)
	for d in shown:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var p := _label(str(d), 10, DIM)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.clip_text = true
		p.tooltip_text = str(d)
		row.add_child(p)
		var cnt := 0
		for m in app.models:
			if str(m["path"]).begins_with(str(d)):
				cnt += 1
		row.add_child(_label("%d 个" % cnt, 10, FAINT))
		if str(d) != default_dir:
			var rm := _button("移除", false, false)
			rm.custom_minimum_size = Vector2(52, 24)
			rm.add_theme_font_size_override("font_size", 10)
			rm.pressed.connect(func():
				app.remove_model_dir(str(d))
				_rebuild_current_tab())
			row.add_child(rm)
		v.add_child(row)

	# 按钮行
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	var add_btn := _button("＋ 添加文件夹…", true, true)
	add_btn.custom_minimum_size = Vector2(130, 30)
	add_btn.pressed.connect(func():
		var dlg := FileDialog.new()
		dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.title = "选择放 GGUF 模型的文件夹"
		dlg.size = Vector2i(820, 560)
		add_child(dlg)
		dlg.dir_selected.connect(func(p: String):
			var res: Dictionary = app.add_model_dir(p)
			dlg.queue_free()
			_status.text = str(res.get("output", ""))
			_rebuild_current_tab())
		dlg.canceled.connect(func(): dlg.queue_free())
		dlg.popup_centered())
	btns.add_child(add_btn)

	var rescan := _button("重新扫描", false, true)
	rescan.custom_minimum_size = Vector2(90, 30)
	rescan.pressed.connect(func():
		var n: int = app.rescan_models()
		_status.text = "扫描完成，共 %d 个模型" % n
		_rebuild_current_tab())
	btns.add_child(rescan)
	v.add_child(btns)

	return card


## 重建当前标签页（导入/移除后刷新列表）
func _rebuild_current_tab() -> void:
	_capture()
	for c in _content.get_children():
		c.queue_free()
	match tab:
		"general":
			_build_general()
		"model":
			_build_model()
		"plugins":
			_build_plugins()
		"license":
			_build_license()


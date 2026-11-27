extends Node
## MDView —— 把 Markdown 渲染成真正的控件（支持表格和图片）。
##
## RichTextLabel 画不了表格，也没法插图，所以这里按"块"来拆：
##   普通段落 → RichTextLabel（走 MD.to_bb 的轻量格式）
##   表格      → GridContainer + 单元格底色（真表格，不是空格凑的）
##   图片      → TextureRect 缩略图（本地文件），点一下用系统看图打开
##   代码块    → 深色底 + 等宽字体
##
## 用法：var node := MDView.build(text, 14)

const TEXT := Color("#e6eaf2")
const DIM := Color("#93a0b4")
const LINE := Color("#232936")
const PANEL2 := Color("#1b202b")
const ACCENT := Color("#5b8def")
const CODE_BG := Color("#161b24")

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


func style(bg: Color, radius := 8, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
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


# ---------------------------------------------------------------- 入口
func build(md: String, size := 14) -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)

	var lines := md.split("\n")
	var i := 0
	var text_buf: PackedStringArray = []

	while i < lines.size():
		var line := lines[i]
		var trimmed := line.strip_edges()

		# 代码块
		if trimmed.begins_with("```"):
			_flush_text(root, text_buf, size)
			var code: PackedStringArray = []
			i += 1
			while i < lines.size() and not lines[i].strip_edges().begins_with("```"):
				code.append(lines[i])
				i += 1
			i += 1
			root.add_child(_code_block(code, size))
			continue

		# 图片：独立成行的 ![alt](path)
		var img := _parse_image(trimmed)
		if img.size() == 2:
			_flush_text(root, text_buf, size)
			root.add_child(_image_block(img[0], img[1]))
			i += 1
			continue

		# 独立公式 $$...$$
		if trimmed.begins_with("$$"):
			_flush_text(root, text_buf, size)
			var body := ""
			if trimmed.length() > 4 and trimmed.ends_with("$$"):
				body = trimmed.substr(2, trimmed.length() - 4)
				i += 1
			else:
				i += 1
				while i < lines.size() and lines[i].strip_edges() != "$$":
					body += lines[i] + " "
					i += 1
				i += 1
			root.add_child(MathRender.block(body, size + 1))
			continue

		# 表格：当前行有 |，下一行是分隔行
		if trimmed.begins_with("|") and i + 1 < lines.size() and _is_table_sep(lines[i + 1]):
			_flush_text(root, text_buf, size)
			var rows: Array = [_split_row(line)]
			i += 2
			while i < lines.size() and lines[i].strip_edges().begins_with("|"):
				rows.append(_split_row(lines[i]))
				i += 1
			root.add_child(_table(rows, size))
			continue

		# 裸图片路径（截图工具会返回"路径：C:/...png"）
		if _looks_like_image_path(trimmed):
			_flush_text(root, text_buf, size)
			root.add_child(_image_block("", trimmed))
			i += 1
			continue

		text_buf.append(line)
		i += 1

	_flush_text(root, text_buf, size)
	return root


func _flush_text(root: VBoxContainer, buf: PackedStringArray, size: int) -> void:
	if buf.is_empty():
		return
	var joined := "\n".join(buf).strip_edges()
	buf.clear()
	if joined.strip_edges() == "":
		return
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_override("normal_font", face(size))
	l.add_theme_font_override("bold_font", face(size, true))
	l.add_theme_font_override("mono_font", face(size - 1))
	l.add_theme_font_override("italics_font", face(size))
	l.add_theme_font_size_override("normal_font_size", size)
	l.add_theme_font_size_override("bold_font_size", size)
	l.add_theme_font_size_override("mono_font_size", size - 1)
	l.add_theme_font_size_override("italics_font_size", size)
	l.add_theme_color_override("default_color", TEXT)
	l.text = _with_math(MD.to_bb(joined))
	l.meta_clicked.connect(func(url: String): OS.shell_open(url))
	root.add_child(l)


# ---------------------------------------------------------------- 代码块
func _code_block(lines: PackedStringArray, size: int) -> Control:
	var panel := PanelContainer.new()
	var st := style(CODE_BG, 8, LINE)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", st)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var l := RichTextLabel.new()
	l.bbcode_enabled = false
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_font_override("normal_font", face(size - 1))
	l.add_theme_font_size_override("normal_font_size", size - 1)
	l.add_theme_color_override("default_color", Color("#c8d3e0"))
	l.text = "\n".join(lines)
	panel.add_child(l)
	return panel


# ---------------------------------------------------------------- 表格
func _is_table_sep(line: String) -> bool:
	var t := line.strip_edges()
	if not t.begins_with("|"):
		return false
	var re := RegEx.new()
	re.compile("^\\|?[\\s:|-]+\\|?$")
	return re.search(t) != null and (t.contains("---") or t.contains("-"))


func _split_row(line: String) -> Array:
	var t := line.strip_edges()
	if t.begins_with("|"):
		t = t.substr(1)
	if t.ends_with("|"):
		t = t.substr(0, t.length() - 1)
	var cells: Array = []
	for c in t.split("|"):
		cells.append(c.strip_edges())
	return cells


func _table(rows: Array, size: int) -> Control:
	var panel := PanelContainer.new()
	var st := style(Color("#12161e"), 8, LINE)
	st.content_margin_left = 0
	st.content_margin_right = 0
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", st)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cols := 0
	for r in rows:
		cols = max(cols, (r as Array).size())
	if cols == 0:
		return panel

	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(grid)

	for ri in rows.size():
		var row: Array = rows[ri]
		for ci in cols:
			var cell := PanelContainer.new()
			var bg := Color("#1b2130") if ri == 0 else (Color("#151a24") if ri % 2 == 1 else Color("#12161e"))
			var cs := StyleBoxFlat.new()
			cs.bg_color = bg
			cs.set_corner_radius_all(0)
			cs.content_margin_left = 10
			cs.content_margin_right = 10
			cs.content_margin_top = 6
			cs.content_margin_bottom = 6
			cell.add_theme_stylebox_override("panel", cs)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var text := str(row[ci]) if ci < row.size() else ""
			var l := RichTextLabel.new()
			l.bbcode_enabled = true
			l.fit_content = true
			l.scroll_active = false
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(70, 0)
			l.add_theme_font_override("normal_font", face(size - 2))
			l.add_theme_font_override("bold_font", face(size - 2, true))
			l.add_theme_font_size_override("normal_font_size", size - 2)
			l.add_theme_font_size_override("bold_font_size", size - 2)
			l.add_theme_color_override("default_color", TEXT if ri == 0 else DIM)
			var shown := MD.to_bb(text)
			if ri == 0:
				shown = "[b]%s[/b]" % shown
			l.text = shown
			cell.add_child(l)
			grid.add_child(cell)
	return panel


# ---------------------------------------------------------------- 图片
func _parse_image(line: String) -> Array:
	var re := RegEx.new()
	re.compile("^!\\[([^\\]]*)\\]\\(([^)]+)\\)$")
	var m := re.search(line)
	if m == null:
		return []
	return [m.get_string(1), m.get_string(2)]


func _looks_like_image_path(line: String) -> bool:
	var t := line.strip_edges()
	# 形如 "路径：C:/x/y.png" 或直接一行图片路径
	for ext in [".png", ".jpg", ".jpeg", ".webp", ".bmp"]:
		if t.to_lower().ends_with(ext):
			return FileAccess.file_exists(_strip_prefix(t))
	var idx := t.find("：")
	if idx >= 0:
		var p := t.substr(idx + 1).strip_edges()
		for ext in [".png", ".jpg", ".jpeg", ".webp", ".bmp"]:
			if p.to_lower().ends_with(ext) and FileAccess.file_exists(p):
				return true
	# "路径：xxx.png"（识别图/截图返回的格式）
	var idx2 := t.find(":")
	if idx2 >= 0 and not t.begins_with("http"):
		var p2 := t.substr(idx2 + 1).strip_edges()
		for ext in [".png", ".jpg", ".jpeg", ".webp", ".bmp"]:
			if p2.to_lower().ends_with(ext) and FileAccess.file_exists(p2):
				return true
	return false


func _strip_prefix(t: String) -> String:
	var idx := t.find("：")
	if idx >= 0:
		return t.substr(idx + 1).strip_edges()
	var idx2 := t.find(": ")
	if idx2 >= 0:
		return t.substr(idx2 + 2).strip_edges()
	return t


func _image_block(alt: String, path_or_url: String) -> Control:
	var p := _strip_prefix(path_or_url)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", style(Color("#0f131a"), 8, LINE))
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(holder)

	if p.begins_with("http"):
		holder.add_child(_label("图片链接：" + p, 11, DIM))
		box.add_child(_link_button(p))
		return box

	if not FileAccess.file_exists(p):
		holder.add_child(_label("（图片不存在：%s）" % p, 11, DIM))
		return box

	var img := Image.new()
	if img.load(p) != OK:
		holder.add_child(_label("（无法读取图片：%s）" % p, 11, DIM))
		return box
	var w := img.get_width()
	var h := img.get_height()
	var max_w := 360
	if w > max_w:
		var scale := float(max_w) / float(w)
		img.resize(int(w * scale), int(h * scale), Image.INTERPOLATE_BILINEAR)

	var tex := ImageTexture.create_from_image(img)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(mini(w, max_w), int(float(mini(w, max_w)) * h / max(w, 1)))
	tr.tooltip_text = "%s（%d×%d，点击用系统看图打开）" % [p, w, h]
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			OS.shell_open(p))
	holder.add_child(tr)
	if alt != "":
		box.add_child(_label(alt, 10, DIM))
	return box


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", face(size))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _link_button(url: String) -> Button:
	var b := Button.new()
	b.text = "打开图片 ↗"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(100, 26)
	b.add_theme_font_override("font", face(11))
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color("#7fb0ff"))
	b.pressed.connect(func(): OS.shell_open(url))
	return b


## 把 $...$ 的行内公式换成 MathRender 渲染后的 BBCode
func _with_math(bb: String) -> String:
	var out := ""
	var i := 0
	while i < bb.length():
		# $$...$$ 整段公式（出现在句子中间的时候）
		if bb.substr(i, 2) == "$$":
			var j2 := bb.find("$$", i + 2)
			if j2 > i:
				var latex2 := bb.substr(i + 2, j2 - i - 2)
				out += "[color=#cfe0ff]" + MathRender.inline(latex2) + "[/color]"
				i = j2 + 2
				continue
		if bb[i] == "$":
			var j := bb.find("$", i + 1)
			if j > i:
				var latex := bb.substr(i + 1, j - i - 1)
				out += "[color=#cfe0ff]" + MathRender.inline(latex) + "[/color]"
				i = j + 1
				continue
		out += bb[i]
		i += 1
	return out

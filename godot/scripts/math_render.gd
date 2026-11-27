extends Node
## MathRender —— 轻量公式渲染（不是完整 LaTeX，但常见的够用）。
##
## 支持：
##   $...$ 行内公式、$$...$$ 独立公式
##   \frac{a}{b} 真·上下分式（独立公式里画成分数线）
##   \sqrt{x}、x^2、x_i、希腊字母、\times \le \ge \ne \approx \infty \sum \int \to …
##
## 做法：
##   行内 → BBCode 字符串（上标下标尽量用 Unicode 字符，实在没有就 ^(...) 表示）
##   独立 → 控件树（分式用 VBox + 一条横线，看起来就是分数）

const SYMBOLS := {
	"alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
	"zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
	"lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ",
	"sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "chi": "χ",
	"psi": "ψ", "omega": "ω",
	"Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Pi": "Π",
	"Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
	"times": "×", "div": "÷", "pm": "±", "mp": "∓", "cdot": "·",
	"le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠",
	"approx": "≈", "equiv": "≡", "propto": "∝", "infty": "∞",
	"sum": "∑", "prod": "∏", "int": "∫", "partial": "∂", "nabla": "∇",
	"to": "→", "rightarrow": "→", "leftarrow": "←", "Rightarrow": "⇒",
	"leftrightarrow": "↔", "in": "∈", "notin": "∉", "subset": "⊂",
	"cup": "∪", "cap": "∩", "forall": "∀", "exists": "∃", "angle": "∠",
	"degree": "°", "circ": "∘", "ldots": "…", "cdots": "⋯",
	"quad": " ", "qquad": "  ", "left": "", "right": "",
}

const SUP := {
	"0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶",
	"7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽",
	")": "⁾", "n": "ⁿ", "i": "ⁱ", "x": "ˣ", "y": "ʸ", "a": "ᵃ", "b": "ᵇ",
	"c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "k": "ᵏ", "m": "ᵐ", "p": "ᵖ", "t": "ᵗ",
	"T": "ᵀ", " ": " ", ".": "˙",
}

const SUB := {
	"0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆",
	"7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍",
	")": "₎", "a": "ₐ", "e": "ₑ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "n": "ₙ",
	"o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ",
	"x": "ₓ",
}


# ---------------------------------------------------------------- 行内
## 返回可以塞进 RichTextLabel 的 BBCode
func inline(latex: String) -> String:
	return _inline_str(latex.strip_edges())


func _inline_str(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		var ch := s[i]
		if ch == "\\":
			# 命令
			var j := i + 1
			var name := ""
			while j < s.length() and s[j] >= "a" and s[j] <= "z" or (j < s.length() and s[j] >= "A" and s[j] <= "Z"):
				name += s[j]
				j += 1
			if name == "" and j < s.length():
				out += s[j]       # \{ \} \, 之类
				i = j + 1
				continue
			if name == "frac":
				var a := _read_group(s, j)
				var b := _read_group(s, a[1])
				out += "%s/%s" % [_inline_str(a[0]), _inline_str(b[0])]
				i = b[1]
				continue
			if name == "sqrt":
				var a2 := _read_group(s, j)
				out += "√(%s)" % _inline_str(a2[0])
				i = a2[1]
				continue
			out += str(SYMBOLS.get(name, name))
			i = j
			continue
		if ch == "^" or ch == "_":
			var g := _read_group(s, i + 1)
			var body := _inline_str(g[0])
			var map: Dictionary = SUP if ch == "^" else SUB
			var mapped := ""
			var ok := true
			for c in body:
				if map.has(c):
					mapped += map[c]
				else:
					ok = false
					break
			if ok and body.length() > 0:
				out += mapped
			else:
				out += ("^" if ch == "^" else "_") + "(" + body + ")"
			i = g[1]
			continue
		out += ch
		i += 1
	return out


## 读一个 {..} 或单个字符，返回 [内容, 新位置]
func _read_group(s: String, start: int) -> Array:
	var i := start
	while i < s.length() and s[i] == " ":
		i += 1
	if i >= s.length():
		return ["", i]
	if s[i] == "{":
		var depth := 0
		var j := i
		var body := ""
		while j < s.length():
			if s[j] == "{":
				depth += 1
				if depth > 1:
					body += s[j]
			elif s[j] == "}":
				depth -= 1
				if depth == 0:
					return [body, j + 1]
				body += s[j]
			else:
				body += s[j]
			j += 1
		return [body, j]
	# 单个 token
	if s[i] == "\\":
		var j2 := i + 1
		while j2 < s.length() and ((s[j2] >= "a" and s[j2] <= "z") or (s[j2] >= "A" and s[j2] <= "Z")):
			j2 += 1
		return [s.substr(i, j2 - i), j2]
	return [s[i], i + 1]


# ---------------------------------------------------------------- 独立公式
func block(latex: String, size := 15) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)

	_fill_block(row, latex.strip_edges(), size)
	return box


func _fill_block(row: HBoxContainer, s: String, size: int) -> void:
	var text_buf := ""
	var i := 0
	while i < s.length():
		var ch := s[i]
		if ch == "\\":
			var j := i + 1
			var name := ""
			while j < s.length() and ((s[j] >= "a" and s[j] <= "z") or (s[j] >= "A" and s[j] <= "Z")):
				name += s[j]
				j += 1
			if name == "frac":
				var a := _read_group(s, j)
				var b := _read_group(s, a[1])
				_flush(row, text_buf, size)
				text_buf = ""
				row.add_child(_fraction(a[0], b[0], size))
				i = b[1]
				continue
			if name == "sqrt":
				var a2 := _read_group(s, j)
				_flush(row, text_buf, size)
				text_buf = ""
				row.add_child(_sqrt(a2[0], size))
				i = a2[1]
				continue
			text_buf += str(SYMBOLS.get(name, name))
			i = j
			continue
		if ch == "^" or ch == "_":
			var g := _read_group(s, i + 1)
			text_buf += ("^" if ch == "^" else "_") + _inline_str(g[0])
			i = g[1]
			continue
		text_buf += ch
		i += 1
	_flush(row, text_buf, size)


func _flush(row: HBoxContainer, text: String, size: int) -> void:
	if text.strip_edges() == "":
		return
	var l := _label(text, size)
	row.add_child(l)


func _fraction(num: String, den: String, size: int) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.alignment = BoxContainer.ALIGNMENT_CENTER

	var top := _label(_inline_str(num), size)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(top)

	var line := ColorRect.new()
	line.color = Color("#c9d3e0")
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)

	var bottom := _label(_inline_str(den), size)
	bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(bottom)
	return v


func _sqrt(inner: String, size: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	h.add_child(_label("√", size + 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var body := _label(_inline_str(inner), size)
	v.add_child(body)
	var bar := ColorRect.new()
	bar.color = Color("#c9d3e0")
	bar.custom_minimum_size = Vector2(0, 1)
	v.add_child(bar)
	h.add_child(v)
	return h


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	var p := "C:/Windows/Fonts/msyh.ttc"
	if FileAccess.file_exists(p):
		var f := FontFile.new()
		f.load_dynamic_font(p)
		l.add_theme_font_override("font", f)
	return l

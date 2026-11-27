extends Node
## MD —— 轻量 Markdown → BBCode，供聊天气泡和插件说明共用。
##
## 目标：模型输出的 `**加粗**`、`# 标题`、`- 列表`、`代码` 能真的渲染出来，
## 同时把用户/模型文本里的 `[` 转义掉，防止被当成 BBCode 标签吃掉。
##
## 用法：
##   MD.to_bb(text)       转成 BBCode（用于 RichTextLabel.bbcode_enabled = true）
##   MD.plain(text)       只转义、不加任何格式

const CODE_BG := "#161b24"


## 只做转义（用户消息、代码内容用）
func plain(s: String) -> String:
	return s.replace("[", "[lb]")


## 完整渲染
func to_bb(s: String) -> String:
	var out: PackedStringArray = []
	var in_code := false
	for raw in s.split("\n"):
		var line := raw
		# 代码围栏
		if line.strip_edges().begins_with("```"):
			if in_code:
				out.append("[/code][/bgcolor]")
			else:
				out.append("[bgcolor=%s][code]" % CODE_BG)
			in_code = not in_code
			continue
		if in_code:
			# 代码块里的内容原样保留，只转义
			out.append(plain(line))
			continue

		out.append(_line_bb(line))
	if in_code:
		out.append("[/code][/bgcolor]")
	return "\n".join(out)


func _line_bb(line: String) -> String:
	var t := line
	# 标题
	if t.begins_with("### "):
		return "[font_size=14][b]%s[/b][/font_size]" % _inline(t.substr(4))
	if t.begins_with("## "):
		return "[font_size=16][b]%s[/b][/font_size]" % _inline(t.substr(3))
	if t.begins_with("# "):
		return "[font_size=18][b]%s[/b][/font_size]" % _inline(t.substr(2))
	# 列表
	if t.begins_with("- ") or t.begins_with("* "):
		return "    • %s" % _inline(t.substr(2))
	# 有序列表
	var re_ol := RegEx.new()
	re_ol.compile("^(\\d+)\\.\\s+(.*)$")
	var m := re_ol.search(t)
	if m:
		return "    %s. %s" % [m.get_string(1), _inline(m.get_string(2))]
	# 引用
	if t.begins_with("> "):
		return "[color=#8a97ab]│ %s[/color]" % _inline(t.substr(2))
	return _inline(t)


## 行内：先抓链接 → 转义 → 行内代码 → 加粗/斜体 → 还原链接
func _inline(s: String) -> String:
	# 1) 先把 [文字](url) 换成占位符（此时还没转义，正则能匹配到方括号）
	var links: Array = []
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "[":
			var close := s.find("](", i + 1)
			if close > i:
				var end_paren := s.find(")", close + 2)
				if end_paren > close:
					var text := s.substr(i + 1, close - i - 1)
					var url := s.substr(close + 2, end_paren - close - 2)
					if url.begins_with("http"):
						links.append([text, url])
						out += "\u0002%d\u0002" % (links.size() - 1)
						i = end_paren + 1
						continue
		out += s[i]
		i += 1

	# 2) 转义剩下的方括号
	var t := out.replace("[", "[lb]")

	# 3) 行内代码
	var codes: Array = []
	var res := ""
	var k := 0
	while k < t.length():
		if t[k] == "`":
			var j := t.find("`", k + 1)
			if j > k:
				codes.append(t.substr(k + 1, j - k - 1))
				res += "\u0001%d\u0001" % (codes.size() - 1)
				k = j + 1
				continue
		res += t[k]
		k += 1
	t = res

	# 3.5) 裸链接自动转（URL 里没有方括号，安全）
	var url_res := ""
	var u := 0
	while u < t.length():
		if t.substr(u, 4) == "http":
			var stop := u
			while stop < t.length() and t[stop] != " " and t[stop] != "\n" and t[stop] != "\u0001" and t[stop] != "\u0002":
				stop += 1
			var raw_url := t.substr(u, stop - u)
			# 去掉尾巴上的标点
			while raw_url.length() > 0 and ".,，。)）]".find(raw_url[raw_url.length() - 1]) >= 0:
				raw_url = raw_url.substr(0, raw_url.length() - 1)
			links.append([raw_url, raw_url])
			url_res += "\u0002%d\u0002" % (links.size() - 1)
			u += raw_url.length()
			continue
		url_res += t[u]
		u += 1
	t = url_res

	# 4) 加粗 / 斜体
	var re_b := RegEx.new()
	re_b.compile("\\*\\*([^*]+)\\*\\*")
	t = re_b.sub(t, "[b]$1[/b]", true)
	var re_i := RegEx.new()
	re_i.compile("(^|[^*])\\*([^*\\n]+)\\*")
	t = re_i.sub(t, "$1[i]$2[/i]", true)

	# 5) 还原行内代码
	for c in range(codes.size() - 1, -1, -1):
		t = t.replace("\u0001%d\u0001" % c, "[code]%s[/code]" % str(codes[c]))

	# 6) 还原链接
	for l in range(links.size() - 1, -1, -1):
		var text: String = str(links[l][0]).replace("[", "[lb]")
		var url: String = str(links[l][1]).replace("[", "%5B").replace("]", "%5D")
		t = t.replace("\u0002%d\u0002" % l,
			"[url=%s][color=#7fb0ff]%s[/color][/url]" % [url, text])

	return t


## 估算去掉标记后的纯文本（有时需要）
func strip(s: String) -> String:
	return s.replace("**", "").replace("`", "")


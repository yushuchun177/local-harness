extends Node
## GGUF —— 读 GGUF 文件头里的元数据，并据此算出这台机器该怎么跑这个模型。
##
## 只读元数据（不读张量），所以再大的模型也是毫秒级。
## 得到的信息：
##   架构 / 名字 / 参数量 / 量化类型 / 原生上下文 / 层数 / 注意力头 / KV 头 / 词向量维度
##   以及 chat_template 长什么样（判断 ChatML / Llama3 / Qwen3 这类）
##
## 再结合本机显存、内存、CPU 线程，算出"推荐 GPU 层数 / 上下文 / 线程数"。
## 每个模型各自一份配置（按路径+大小做 key），互不影响。

const MAGIC := "GGUF"

# 元数据类型
const T_UINT8 := 0
const T_INT8 := 1
const T_UINT16 := 2
const T_INT16 := 3
const T_UINT32 := 4
const T_INT32 := 5
const T_FLOAT32 := 6
const T_BOOL := 7
const T_STRING := 8
const T_ARRAY := 9
const T_UINT64 := 10
const T_INT64 := 11
const T_FLOAT64 := 12


## 解析一个 GGUF 文件，返回元数据字典；失败返回 {}
func read_meta(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var magic := f.get_buffer(4).get_string_from_ascii()
	if magic != MAGIC:
		return {}
	var version := f.get_32()
	if version < 2 or version > 3:
		return {}
	var tensor_count := f.get_64()
	var kv_count := f.get_64()

	var meta: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	var read := 0
	var guard := 0
	while read < kv_count and f.get_position() < f.get_length():
		guard += 1
		if guard > kv_count + 10:
			break
		if Time.get_ticks_msec() - t0 > 500:
			# 大模型的词表能有好几 MB，别为了几个字段卡住界面
			break
		var key := _read_string(f)
		if key == "":
			break
		var vtype := f.get_32()
		var value = _read_value(f, vtype, 0)
		meta[key] = value
		read += 1
		# 需要的几个字段拿到就够了，词表那些几百 KB 的数组不用读
		var arch_now := str(meta.get("general.architecture", ""))
		if arch_now != "" \
				and meta.has("%s.block_count" % arch_now) \
				and meta.has("%s.context_length" % arch_now) \
				and meta.has("%s.embedding_length" % arch_now) \
				and meta.has("%s.attention.head_count" % arch_now) \
				and meta.has("%s.attention.head_count_kv" % arch_now) \
				and meta.has("general.name"):
			break

	meta["__version"] = version
	meta["__tensors"] = tensor_count
	meta["__size"] = f.get_length()
	return meta


func _read_string(f: FileAccess) -> String:
	var n := f.get_64()
	if n <= 0:
		return ""
	if n > 1048576:
		# 超长字符串（词表之类）不读进来，直接跳过
		f.seek(f.get_position() + n)
		return ""
	return f.get_buffer(n).get_string_from_utf8()


func _read_value(f: FileAccess, vtype: int, depth: int):
	match vtype:
		T_UINT8:
			return f.get_8()
		T_INT8:
			return f.get_8()
		T_UINT16:
			return f.get_16()
		T_INT16:
			return f.get_16()
		T_UINT32:
			return f.get_32()
		T_INT32:
			return f.get_32()
		T_FLOAT32:
			return f.get_float()
		T_BOOL:
			return f.get_8() != 0
		T_STRING:
			return _read_string(f)
		T_ARRAY:
			var elem := f.get_32()
			var count := f.get_64()
			if count > 5000000:
				f.seek(f.get_length())
				return []
			# 数组只对我们关心的小数组取值，避免把 token 词表整个读进来
			if count > 4096:
				var per := _elem_size(elem)
				if per > 0:
					f.seek(f.get_position() + per * count)
				else:
					for i in count:
						_skip_value(f, elem)
				return []
			var arr: Array = []
			for i in count:
				arr.append(_read_value(f, elem, depth + 1))
			return arr
		T_UINT64:
			return f.get_64()
		T_INT64:
			return f.get_64()
		T_FLOAT64:
			return f.get_double()
	# 未知类型：停在这里，别继续错位读
	push_warning("[GGUF] 未知元数据类型 %d" % vtype)
	f.seek(f.get_length())
	return 0


func _skip_value(f: FileAccess, t: int) -> void:
	match t:
		T_STRING:
			var n := f.get_64()
			if n > 0:
				f.seek(f.get_position() + n)
		T_ARRAY:
			var elem := f.get_32()
			var count := f.get_64()
			for i in count:
				_skip_value(f, elem)
		_:
			var per := _elem_size(t)
			if per > 0:
				f.seek(f.get_position() + per)


func _elem_size(t: int) -> int:
	match t:
		T_UINT8, T_INT8, T_BOOL:
			return 1
		T_UINT16, T_INT16:
			return 2
		T_UINT32, T_INT32, T_FLOAT32:
			return 4
		T_UINT64, T_INT64, T_FLOAT64:
			return 8
	return 0


# ---------------------------------------------------------------- 解析成"人话"
## 把元数据整理成模型档案
var _cache: Dictionary = {}


func profile(path: String, vram_mb: int = 0, ram_mb: int = 0) -> Dictionary:
	var ckey := "%s|%d|%d" % [path, vram_mb, ram_mb]
	if _cache.has(ckey):
		return _cache[ckey].duplicate(true)
	var meta := read_meta(path)
	var size_mb := 0
	if FileAccess.file_exists(path):
		var probe := FileAccess.open(path, FileAccess.READ)
		if probe != null:
			size_mb = int(probe.get_length() / 1048576.0)

	var arch := str(meta.get("general.architecture", ""))
	var name := str(meta.get("general.name", path.get_file().get_basename()))
	var file_type := int(meta.get("general.file_type", -1))
	var layers := int(meta.get("%s.block_count" % arch, 0))
	var heads := int(meta.get("%s.attention.head_count" % arch, 0))
	var kv_heads := int(meta.get("%s.attention.head_count_kv" % arch, heads))
	var embd := int(meta.get("%s.embedding_length" % arch, 0))
	var native_ctx := int(meta.get("%s.context_length" % arch, 0))
	var tmpl := str(meta.get("tokenizer.chat_template", ""))

	# 量化：先看元数据，再退回文件名
	var quant := _quant_name(file_type)
	if quant == "未知":
		var low := path.to_lower()
		for pair in [["q8_0", "Q8_0"], ["q6_k", "Q6_K"], ["q5_k_m", "Q5_K_M"], ["q5_k_s", "Q5_K_S"],
				["q4_k_m", "Q4_K_M"], ["q4_k_s", "Q4_K_S"], ["q4_0", "Q4_0"], ["q3_k_m", "Q3_K_M"],
				["q2_k", "Q2_K"], ["f16", "F16"], ["bf16", "BF16"]]:
			if low.find(str(pair[0])) >= 0:
				quant = str(pair[1])
				break

	# 参数量：元数据没有就按量化位数估
	var params := int(meta.get("general.parameter_count", 0))
	if params <= 0 and size_mb > 0:
		var bits := 4.5
		match quant:
			"Q2_K":
				bits = 2.6
			"Q3_K_S", "Q3_K_M", "Q3_K_L":
				bits = 3.4
			"Q4_0", "Q4_1", "Q4_K_S", "Q4_K_M":
				bits = 4.5
			"Q5_0", "Q5_1", "Q5_K_S", "Q5_K_M":
				bits = 5.5
			"Q6_K":
				bits = 6.6
			"Q8_0":
				bits = 8.5
			"F16", "BF16":
				bits = 16.0
			"F32":
				bits = 32.0
		params = int(float(size_mb) * 1048576.0 * 8.0 / bits)

	var family := _detect_family(path, meta, tmpl)
	var kv_per_tok := _kv_bytes(layers, heads, kv_heads, embd)
	var need_mb := size_mb
	if native_ctx > 0:
		need_mb = size_mb + int(kv_per_tok * float(native_ctx) / 1048576.0)

	var rec := _recommend(size_mb, kv_per_tok, native_ctx, layers, vram_mb, ram_mb)

	var prof := {
		"path": path,
		"name": name,
		"arch": arch,
		"family": family,
		"quant": quant,
		"params": params,
		"layers": layers,
		"heads": heads,
		"kv_heads": kv_heads,
		"embd": embd,
		"native_ctx": native_ctx,
		"size_mb": size_mb,
		"kv_per_token": kv_per_tok,
		"need_mb_full_ctx": need_mb,
		"template_kind": _template_kind(tmpl),
		"rec_ngl": rec["ngl"],
		"rec_ctx": rec["ctx"],
		"rec_threads": rec["threads"],
		"fits_ram": rec["fits_ram"],
		"fits_vram": rec["fits_vram"],
		"note": rec["note"],
	}
	_cache[ckey] = prof
	return prof.duplicate(true)


func _detect_family(path: String, meta: Dictionary, tmpl: String) -> String:
	var n := path.to_lower()
	if n.find("qwen3") >= 0 or str(meta.get("general.name", "")).to_lower().find("qwen3") >= 0:
		return "Qwen3"
	if n.find("qwen") >= 0:
		return "Qwen"
	if n.find("llama-3") >= 0 or n.find("llama3") >= 0:
		return "Llama 3"
	if n.find("gemma") >= 0:
		return "Gemma"
	if n.find("phi") >= 0:
		return "Phi"
	if n.find("deepseek") >= 0:
		return "DeepSeek"
	if n.find("mistral") >= 0:
		return "Mistral"
	if n.find("smollm") >= 0:
		return "SmolLM"
	var arch := str(meta.get("general.architecture", ""))
	return arch if arch != "" else "未知"


func _quant_name(file_type: int) -> String:
	# llama.cpp 的 general.file_type 枚举
	var names := {
		0: "F32", 1: "F16", 2: "Q4_0", 3: "Q4_1", 7: "Q8_0", 8: "Q5_0", 9: "Q5_1",
		10: "Q2_K", 11: "Q3_K_S", 12: "Q3_K_M", 13: "Q3_K_L", 14: "Q4_K_S",
		15: "Q4_K_M", 16: "Q5_K_S", 17: "Q5_K_M", 18: "Q6_K", 19: "IQ2_XXS",
		20: "IQ2_XS", 21: "Q2_K_S", 22: "IQ3_XS", 23: "IQ3_XXS", 24: "IQ1_S",
		25: "IQ4_NL", 26: "IQ3_S", 27: "IQ3_M", 28: "IQ2_S", 29: "IQ2_M",
		30: "IQ4_XS", 31: "IQ1_M", 32: "BF16",
	}
	return str(names.get(file_type, "未知"))


## 每个 token 的 KV cache 字节数（K 和 V 各一份，默认 f16 = 2 字节）
func _kv_bytes(layers: int, heads: int, kv_heads: int, embd: int) -> int:
	if layers <= 0 or heads <= 0 or embd <= 0:
		return 0
	var head_dim: int = int(float(embd) / float(heads))
	var kv: int = 2 * layers * max(kv_heads, 1) * head_dim * 2
	return kv


## 根据显存 / 内存 / 层数给出推荐值
func _recommend(size_mb: int, kv_per_tok: int, native_ctx: int, layers: int, vram_mb: int, ram_mb: int) -> Dictionary:
	var threads := clampi(OS.get_processor_count() - 1, 2, 32)
	var ctx := native_ctx if native_ctx > 0 else 4096
	# 上下文别超过 32768，除非模型原生就更长且内存够
	ctx = mini(ctx, 32768)

	var per_layer_mb := 0.0
	if layers > 0:
		per_layer_mb = float(size_mb) / float(layers)

	# 显存装得下多少层（留 15% 余量给上下文和驱动）
	var ngl := 0
	if vram_mb > 0 and per_layer_mb > 0.0:
		var usable := float(vram_mb) * 0.85
		ngl = int(usable / per_layer_mb)
		ngl = clampi(ngl, 0, layers)

	# 全量权重 + 上下文放不进内存 → 提示
	var need := size_mb + int(float(kv_per_tok * ctx) / 1048576.0)
	var fits_ram := ram_mb == 0 or need <= int(float(ram_mb) * 0.8)
	var note := ""
	if ram_mb > 0 and not fits_ram:
		note = "内存可能不够（需要约 %d MB，可用 %d MB）。建议换更小的量化，或者把上下文调小。" % [
			need, int(float(ram_mb) * 0.8)]
	elif size_mb > 40000:
		note = "这是超大模型（%d GB），需要大内存机器；显存不够的部分会跑到内存里，速度会明显下降。" % int(size_mb / 1024)

	return {
		"ngl": ngl,
		"ctx": ctx,
		"threads": threads,
		"fits_ram": fits_ram,
		"fits_vram": vram_mb > 0 and ngl >= layers,
		"note": note,
	}


func _template_kind(tmpl: String) -> String:
	if tmpl == "":
		return "无模板"
	if tmpl.find("im_start") >= 0:
		return "ChatML"
	if tmpl.find("start_header_id") >= 0:
		return "Llama 3"
	if tmpl.find("enable_thinking") >= 0:
		return "Qwen3（带思考）"
	if tmpl.find("<|user|>") >= 0:
		return "Gemma/Phi 风格"
	return "自定义"


# ---------------------------------------------------------------- 每个模型自己的配置
const STORE := "user://models/models.json"


func _key(path: String) -> String:
	var size := 0
	if FileAccess.file_exists(path):
		size = int(FileAccess.open(path, FileAccess.READ).get_length())
	return "%s|%d" % [path.get_file(), size]


func load_profiles() -> Dictionary:
	var f := FileAccess.open(STORE, FileAccess.READ)
	if f == null:
		return {}
	var obj = JSON.parse_string(f.get_as_text())
	return obj if obj is Dictionary else {}


func get_override(path: String) -> Dictionary:
	var all := load_profiles()
	return all.get(_key(path), {})


func set_override(path: String, values: Dictionary) -> void:
	var all := load_profiles()
	var k := _key(path)
	var cur: Dictionary = all.get(k, {})
	for key in values.keys():
		cur[key] = values[key]
	all[k] = cur
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all, "  "))


## 综合"自动检测 + 用户覆盖"得到最终参数
func effective(path: String, vram_mb: int, ram_mb: int) -> Dictionary:
	var p := profile(path, vram_mb, ram_mb)
	var ov := get_override(path)
	var ngl := int(ov.get("ngl", p["rec_ngl"]))
	var ctx := int(ov.get("ctx", p["rec_ctx"]))
	var threads := int(ov.get("threads", p["rec_threads"]))
	p["ngl"] = ngl
	p["ctx"] = ctx
	p["threads"] = threads
	p["auto_ngl"] = p["rec_ngl"]
	p["auto_ctx"] = p["rec_ctx"]
	p["has_override"] = not ov.is_empty()
	return p


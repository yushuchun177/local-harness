extends Node
## App —— 全局状态：设置、模型、后端、llama-server 生命周期、流式对话。
##
## 与 Windows 版（tkinter + llama-cli 管道）不同，Godot 版走 llama-server：
## 起一个本地进程，用 HTTP + SSE 流式拿 token。好处是不用处理管道里
## 逐字节的 ANSI 控制序列，界面也不会被模型的杂项输出污染。

signal server_state(state: String)          # stopped / starting / ready / error
signal chat_delta(text: String)             # 流式增量
signal chat_done(stats: Dictionary)         # 这一轮结束（含速度）
signal chat_failed(msg: String)

const ACCENT := Color("#5b8def")
const PORT := 18765

var base_dir: String = ""
var cfg: Dictionary = {}
var models: Array = []                      # [{path,label,size_mb}]
var backends: Dictionary = {}               # {cpu: path, cuda: path, ...}
var gpu: Dictionary = {}                    # {name, vram_mb, compute, tensor_cores}
var current_model: String = ""
var current_backend: String = "cpu"
var server_pid: int = -1
var server_up: bool = false

var chats: Array = []                       # [{id,title,messages,updated}]
var current_chat: int = -1

var _health_tries: int = 0
var _client: HTTPClient = null
var _buf: String = ""
var _streaming: bool = false
var _t0: float = 0.0
var _chars: int = 0
var _last_text: String = ""
var _health_req: HTTPRequest


func _ready() -> void:
	_load_config()
	base_dir = _resolve_base_dir()
	_scan_models()
	_scan_backends()
	_detect_gpu()
	_load_chats()
	_health_req = HTTPRequest.new()
	_health_req.timeout = 2.0
	_health_req.request_completed.connect(_on_health_done)
	add_child(_health_req)


# ---------------------------------------------------------------- 路径与配置
func _resolve_base_dir() -> String:
	var cands: Array = []
	if cfg.has("app_dir") and cfg["app_dir"] != "":
		cands.append(cfg["app_dir"])
	if OS.has_feature("editor"):
		cands.append("D:/LocalHarness/local-harness-1.3.0-含6模型")
	cands.append(OS.get_executable_path().get_base_dir())
	cands.append(OS.get_executable_path().get_base_dir().path_join("local-harness"))
	for c in cands:
		if DirAccess.dir_exists_absolute(c.path_join("model")):
			return c
	return cands[0] if cands.size() > 0 else OS.get_executable_path().get_base_dir()


func _config_path() -> String:
	return "user://config.json"


func _load_config() -> void:
	var f := FileAccess.open(_config_path(), FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			cfg = parsed
	if cfg.is_empty():
		cfg = {
			"model": "",
			"backend": "auto",
			"gpu_layers": -1,
			"ctx": 4096,
			"temp": 0.7,
			"max_tokens": 512,
			"threads": 0,
			"system": "你是一个中文助手，请始终用简体中文回答，回答简洁明了。",
			"user_name": "你",
			"assistant_name": "助手",
			"dark": true,
			"lang": "zh",
			"provider": "local",
			"api_base": "",
			"api_key": "",
			"api_model": "",
			"max_steps": 4,
		}


func save_config() -> void:
	var f := FileAccess.open(_config_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cfg, "  "))


func set_cfg(k: String, v) -> void:
	cfg[k] = v
	save_config()


## 用户希望 AI 怎么称呼自己
func user_name() -> String:
	var n := str(cfg.get("user_name", "")).strip_edges()
	return n if n != "" else "你"


## AI 自己的名字
func assistant_name() -> String:
	var n := str(cfg.get("assistant_name", "")).strip_edges()
	return n if n != "" else "助手"


## 发给模型时把称呼规则并进系统提示词（已经写过就不重复加）
func system_with_names() -> String:
	var base := str(cfg.get("system", "")).strip_edges()
	var rule := "你的名字是「%s」，称呼用户为「%s」。" % [assistant_name(), user_name()]
	if base.find(rule) >= 0:
		return base
	return (rule + "\n" + base).strip_edges()


# ---------------------------------------------------------------- 模型
const _SKIP_HINTS := ["mmproj", "projector", "clip", "vision", "embed", "embedding",
	"bge-", "gte-", "e5-", "nomic-embed", "rerank", "bce-", "m3e"]


func _is_chat_model(name: String, size_mb: float) -> bool:
	var low := name.to_lower()
	if not low.ends_with(".gguf"):
		return false
	for h in _SKIP_HINTS:
		if low.find(h) >= 0:
			return false
	if size_mb < 20.0:
		return false
	# 分片文件的第二片起
	var re := RegEx.new()
	re.compile("-(\\d{5})-of-(\\d{5})\\.gguf$")
	var m := re.search(low)
	if m and int(m.get_string(1)) > 1:
		return false
	return true


func _scan_models() -> void:
	models.clear()
	var dirs: Array = [base_dir.path_join("model")]
	for d in cfg.get("model_dirs", []):
		var p := str(d)
		if p != "" and not dirs.has(p):
			dirs.append(p)
	for dir in dirs:
		_scan_model_dir(str(dir))
	models.sort_custom(func(a, b): return a["size_mb"] < b["size_mb"])
	# 默认挑一个 0.6B 左右、质量够用的；没有就退到最小的
	var preferred := ""
	for m in models:
		var low: String = str(m["path"]).to_lower()
		if low.find("qwen3-0.6b") >= 0 or low.find("qwen3-1.7b") >= 0:
			preferred = m["path"]
			break
	if current_model == "" and models.size() > 0:
		var want: String = str(cfg.get("model", ""))
		current_model = preferred if preferred != "" else models[0]["path"]
		for m in models:
			if m["path"] == want or m["label"] == want:
				current_model = m["path"]
		cfg["model"] = current_model


## 扫一个目录（含一层子目录，方便放 gguf 的收藏包）
func _scan_model_dir(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			# 子目录也看一眼（很多模型包会套一层）
			var sub := DirAccess.open(dir.path_join(name))
			if sub != null:
				sub.list_dir_begin()
				var sn := sub.get_next()
				while sn != "":
					if not sub.current_is_dir():
						_add_model(dir.path_join(name).path_join(sn))
					sn = sub.get_next()
				sub.list_dir_end()
		else:
			_add_model(dir.path_join(name))
		name = d.get_next()
	d.list_dir_end()


func _add_model(full: String) -> void:
	if not full.to_lower().ends_with(".gguf"):
		return
	for m in models:
		if str(m["path"]) == full:
			return
	var size := 0.0
	var f := FileAccess.open(full, FileAccess.READ)
	if f != null:
		size = float(f.get_length()) / 1048576.0
	if _is_chat_model(full.get_file(), size):
		models.append({"path": full, "label": _pretty_name(full.get_file()), "size_mb": size})


# ---------------------------------------------------------------- 导入模型文件夹
## 把一个目录加入搜索列表，立刻重扫并自动适配
func add_model_dir(path: String) -> Dictionary:
	var p := path.strip_edges().replace("\\", "/")
	if p == "":
		return {"ok": false, "output": "路径为空"}
	if not DirAccess.dir_exists_absolute(p):
		return {"ok": false, "output": "这个目录不存在：%s" % p}
	var saved: Array = cfg.get("model_dirs", [])
	if saved.has(p):
		_scan_models()
		return {"ok": true, "output": "这个文件夹已经在列表里了，已重新扫描"}
	saved.append(p)
	cfg["model_dirs"] = saved
	save_config()
	_scan_models()
	if current_model == "" and models.size() > 0:
		current_model = models[0]["path"]
		cfg["model"] = current_model
	return {"ok": true, "output": "已导入：找到 %d 个模型（共 %d 个）" % [_count_in(p), models.size()]}


func _count_in(dir: String) -> int:
	var n := 0
	for m in models:
		if str(m["path"]).begins_with(dir):
			n += 1
	return n


func remove_model_dir(path: String) -> void:
	var saved: Array = cfg.get("model_dirs", [])
	saved.erase(path)
	cfg["model_dirs"] = saved
	save_config()
	_scan_models()


## 重新扫描全部目录（导入后、放下新模型后）
func rescan_models() -> int:
	_scan_models()
	return models.size()


func _pretty_name(file: String) -> String:
	var n := file.get_basename()
	n = n.replace("_", " ").replace("-", " ")
	n = n.replace("instruct", "").replace("Instruct", "")
	return n.strip_edges()


func model_label() -> String:
	for m in models:
		if m["path"] == current_model:
			return m["label"]
	return "未选择模型"


# ---------------------------------------------------------------- 后端 / 显卡
const _BACKEND_DIRS := {"cpu": "llama", "cuda": "llama-cuda", "vulkan": "llama-vulkan"}


func _scan_backends() -> void:
	backends.clear()
	for key in _BACKEND_DIRS.keys():
		var exe: String = base_dir.path_join(_BACKEND_DIRS[key]).path_join("llama-server.exe")
		if FileAccess.file_exists(exe):
			backends[key] = exe


func _detect_gpu() -> void:
	gpu = {}
	var out: Array = []
	var code := OS.execute("nvidia-smi",
		PackedStringArray(["--query-gpu=name,memory.total,compute_cap", "--format=csv,noheader"]),
		out)
	if code != 0 or out.size() == 0:
		return
	var line := str(out[0]).strip_edges()
	var parts := line.split(",")
	if parts.size() < 3:
		return
	var cc := parts[2].strip_edges().to_float()
	gpu = {
		"name": parts[0].strip_edges(),
		"vram_mb": parts[1].strip_edges().to_float(),
		"compute": cc,
		"tensor_cores": cc >= 7.0,
	}


func effective_backend() -> String:
	var want: String = str(cfg.get("backend", "auto"))
	if want != "auto" and backends.has(want):
		return want
	var has_gpu: bool = not gpu.is_empty()
	if has_gpu and backends.has("cuda") and bool(gpu.get("tensor_cores", false)):
		return "cuda"
	if has_gpu and backends.has("vulkan"):
		return "vulkan"
	if has_gpu and backends.has("cuda"):
		return "cuda"
	if backends.has("cpu"):
		return "cpu"
	return backends.keys()[0] if backends.size() > 0 else "cpu"


func backend_text() -> String:
	var b := effective_backend()
	var names: Dictionary = {"cpu": "CPU", "cuda": "CUDA", "vulkan": "Vulkan"}
	var label: String = str(names.get(b, b))
	if b == "cpu":
		return label
	var ngl: int = int(cfg.get("gpu_layers", -1))
	if ngl < 0:
		return label + " · 全部层"
	if ngl == 0:
		return label
	return "%s · %d 层" % [label, ngl]


# ---------------------------------------------------------------- 服务端
## 当前模型（或指定模型）的自动适配结果：GGUF 元数据 + 本机显存/内存 + 用户覆盖
func profile_for(path := "") -> Dictionary:
	var p := path if path != "" else current_model
	if p == "":
		return {}
	var vram := int(gpu.get("vram_mb", 0))
	var info := OS.get_memory_info()
	var ram := int(float(info.get("physical", 0)) / 1048576.0)
	return GGUF.effective(p, vram, ram)


## 保存"这个模型"的覆盖参数（别的模型不受影响）
func set_model_override(values: Dictionary) -> void:
	if current_model == "":
		return
	GGUF.set_override(current_model, values)


func server_args() -> PackedStringArray:
	var prof := profile_for()
	var ov := GGUF.get_override(current_model) if current_model != "" else {}
	var ngl: int = 0
	var b := effective_backend()
	if b != "cpu":
		ngl = int(ov.get("ngl", -1))
		if ngl < 0:
			# 自动：用检测出来的推荐层数（每个模型各自算）
			ngl = int(prof.get("ngl", 0)) if not prof.is_empty() else 999
			if ngl <= 0:
				ngl = int(cfg.get("gpu_layers", -1))
			if ngl <= 0:
				ngl = 999
	var threads := int(cfg.get("threads", 0))
	if threads <= 0:
		threads = int(prof.get("threads", 0)) if not prof.is_empty() else 4
	if threads <= 0:
		threads = 4
	var ctx := int(ov.get("ctx", 0))
	if ctx <= 0:
		ctx = int(prof.get("ctx", 0)) if not prof.is_empty() else 0
	if ctx <= 0:
		ctx = int(cfg.get("ctx", 4096))
	var args := PackedStringArray([
		"-m", current_model,
		"-c", str(ctx),
		"-t", str(threads),
		"-ngl", str(ngl),
		"--host", "127.0.0.1",
		"--port", str(PORT),
		"--temp", str(float(cfg.get("temp", 0.7))),
		"--no-warmup",
		"--jinja",          # 用模型自带的 chat template，Qwen3 这类才不会冒出 <null>
	])
	return args


var _launch_sig: String = ""
var _killed_orphans: bool = false


## 影响模型进程的参数指纹：只有这些变了才需要重启服务
func _launch_sig_now() -> String:
	return "%s|%s|%s|%s|%s" % [
		current_model, str(cfg.get("backend", "auto")),
		str(cfg.get("gpu_layers", -1)), str(cfg.get("ctx", 4096)), provider()]


## 设置保存后由面板调用：该重启就重启，不该重启就不打扰
func after_settings_saved() -> void:
	if _launch_sig_now() != _launch_sig:
		restart_server()

func start_server() -> void:
	if provider() == "api":
		# 走在线 API：不需要本地模型进程
		stop_server()
		server_state.emit("ready")
		return
	if current_model == "":
		server_state.emit("error")
		return
	stop_server()
	kill_orphan_servers()
	current_backend = effective_backend()
	var exe: String = backends.get(current_backend, "")
	if exe == "":
		server_state.emit("error")
		return
	_launch_sig = _launch_sig_now()
	server_state.emit("starting")
	server_pid = OS.create_process(exe, server_args(), false)
	if server_pid <= 0:
		server_state.emit("error")
		return
	server_up = false
	_health_tries = 0
	_try_health()


func _try_health() -> void:
	if server_up or _health_tries > 240:
		if _health_tries > 240:
			server_state.emit("error")
		return
	_health_tries += 1
	var url := "http://127.0.0.1:%d/health" % PORT
	var err := _health_req.request(url)
	if err != OK:
		_retry_health_later()


func _retry_health_later() -> void:
	if server_up:
		return
	if _health_tries > 240:
		server_state.emit("error")
		return
	var t := get_tree().create_timer(0.3)
	t.timeout.connect(_try_health)


func _on_health_done(_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if code == 200:
		server_up = true
		server_state.emit("ready")
	else:
		_retry_health_later()


## 杀掉我们自己的 llama-server 残留进程（端口 18765/18766/18767）。
## 重启服务、退出程序、启动时都会调用：之前每次重启都可能留下一个，
## 堆到十几个就把内存吃光了，表现就是"卡死"。
func kill_orphan_servers() -> int:
	var ps_path := OS.get_temp_dir().path_join("lh_kill_llama.ps1")
	var out_path := OS.get_temp_dir().path_join("lh_kill_llama.txt")
	var script := """
$n = 0
Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match '--port (18765|18766|18767)' } |
  ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    $n++
  }
Set-Content -Path 'OUTFILE' -Value $n -Encoding utf8
""".replace("OUTFILE", out_path.replace("'", "''"))
	var f := FileAccess.open(ps_path, FileAccess.WRITE)
	if f == null:
		return 0
	# PowerShell 5.1 读无 BOM 的脚本会乱码，写成 UTF-16LE + BOM
	f.store_buffer(PackedByteArray([0xFF, 0xFE]))
	f.store_buffer(script.to_utf16_buffer())
	f.close()
	var out: Array = []
	OS.execute("powershell.exe",
		PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ps_path]),
		out, true)
	DirAccess.remove_absolute(ps_path)
	var killed := 0
	if FileAccess.file_exists(out_path):
		var rf := FileAccess.open(out_path, FileAccess.READ)
		if rf:
			killed = int(rf.get_as_text().strip_edges())
		DirAccess.remove_absolute(out_path)
	if killed > 0:
		print("[app] 清理了 %d 个残留的 llama-server 进程" % killed)
	server_pid = -1
	server_up = false
	return killed


func stop_server() -> void:
	if server_pid > 0:
		OS.kill(server_pid)
		server_pid = -1
	# 只杀自己那个可能不够：重启多次会留下孤儿进程
	if _killed_orphans == false:
		_killed_orphans = true
		kill_orphan_servers()
		_killed_orphans = false
	server_up = false
	server_state.emit("stopped")


func restart_server() -> void:
	start_server()


# ---------------------------------------------------------------- 对话
## 当前用本地 llama-server 还是在线 API
func provider() -> String:
	return str(cfg.get("provider", "local"))


func api_base() -> String:
	return str(cfg.get("api_base", "")).strip_edges()


func api_model() -> String:
	return str(cfg.get("api_model", "")).strip_edges()


## 当前配置能不能直接聊：本地看服务端，API 看地址+模型名
func chat_ready() -> bool:
	if provider() == "api":
		return api_base() != "" and api_model() != ""
	return server_up


## 把 https://host:port/v1 拆成 HTTPClient 需要的几段
func _parse_base(url: String) -> Dictionary:
	var u := url.strip_edges()
	var tls := false
	if u.begins_with("https://"):
		tls = true
		u = u.substr(8)
	elif u.begins_with("http://"):
		u = u.substr(7)
	u = u.trim_suffix("/")
	var path_prefix := ""
	var slash := u.find("/")
	if slash >= 0:
		path_prefix = u.substr(slash)
		u = u.substr(0, slash)
	var host := u
	var port := 443 if tls else 80
	var colon := u.rfind(":")
	if colon > 0:
		host = u.substr(0, colon)
		port = int(u.substr(colon + 1))
	return {"host": host, "port": port, "tls": tls, "prefix": path_prefix}


func ask(messages: Array) -> bool:
	if not chat_ready():
		return false
	var use_api := provider() == "api"
	var body := JSON.stringify({
		"messages": messages,
		"stream": true,
		"temperature": float(cfg.get("temp", 0.7)),
		"max_tokens": int(cfg.get("max_tokens", 512)),
	})
	if not use_api:
		# 本地模板用模型的 chat template；API 端不接受这个字段
		var obj = JSON.parse_string(body)
		obj["chat_template_kwargs"] = {"enable_thinking": false}
		body = JSON.stringify(obj)

	_client = HTTPClient.new()
	var host := "127.0.0.1"
	var port := PORT
	var tls := false
	if use_api:
		var p := _parse_base(api_base())
		host = p["host"]
		port = p["port"]
		tls = p["tls"]
		_api_path = str(p["prefix"]) + "/chat/completions"
	else:
		_api_path = "/v1/chat/completions"

	var err := OK
	if tls:
		var tls_opt := TLSOptions.client()
		err = _client.connect_to_host(host, port, tls_opt)
	else:
		err = _client.connect_to_host(host, port)
	if err != OK:
		chat_failed.emit("连不上服务")
		return false

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Content-Length: %d" % body.to_utf8_buffer().size(),
	])
	if use_api:
		var key := str(cfg.get("api_key", "")).strip_edges()
		if key != "":
			headers.append("Authorization: Bearer " + key)

	_api_mode = use_api
	_streaming = true
	_buf = ""
	_chars = 0
	_last_text = ""
	_t0 = Time.get_ticks_msec() / 1000.0
	set_process(true)
	_pending_body = body
	_pending_headers = headers
	_state = S_CONNECTING
	return true


var _api_mode: bool = false
var _api_path: String = "/v1/chat/completions"


## 在线 API：列出 {base}/models 里的模型 id
func fetch_api_models() -> Array:
	var base := api_base()
	if base == "":
		return []
	var url := base.rstrip("/") + "/models"
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	var headers := PackedStringArray(["Accept: application/json"])
	var key := str(cfg.get("api_key", "")).strip_edges()
	if key != "":
		headers.append("Authorization: Bearer " + key)
	var err := req.request(url, headers)
	if err != OK:
		req.queue_free()
		return []
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[1]) != 200:
		return []
	var obj = JSON.parse_string(res[3].get_string_from_utf8())
	var out: Array = []
	if obj is Dictionary and obj.has("data"):
		for m in obj["data"]:
			if m is Dictionary and m.has("id"):
				out.append(str(m["id"]))
	out.sort()
	return out


var _pending_body: String = ""
var _pending_headers: PackedStringArray
var _state: int = 0
const S_IDLE := 0
const S_CONNECTING := 1
const S_REQUESTING := 2
const S_BODY := 3


func _process(_dt: float) -> void:
	if not _streaming or _client == null:
		return
	_client.poll()
	match _state:
		S_CONNECTING:
			var st := _client.get_status()
			if st == HTTPClient.STATUS_CONNECTED:
				var err := _client.request(HTTPClient.METHOD_POST, _api_path,
					_pending_headers, _pending_body)
				if err != OK:
					_finish_error("请求发送失败")
					return
				_state = S_BODY
			elif st == HTTPClient.STATUS_CANT_CONNECT or st == HTTPClient.STATUS_CONNECTION_ERROR:
				_finish_error("服务端连接断开")
		S_BODY:
			var st2 := _client.get_status()
			if st2 == HTTPClient.STATUS_BODY:
				var chunk := _client.read_response_body_chunk()
				if chunk.size() > 0:
					_feed(chunk.get_string_from_utf8())
			elif st2 == HTTPClient.STATUS_DISCONNECTED:
				_finish_ok()
			elif st2 == HTTPClient.STATUS_CONNECTION_ERROR:
				_finish_error("生成中断")


func _feed(text: String) -> void:
	_buf += text
	while true:
		var idx := _buf.find("\n")
		if idx < 0:
			break
		var line := _buf.substr(0, idx).strip_edges()
		_buf = _buf.substr(idx + 1)
		if line.begins_with("data: "):
			var payload := line.substr(6)
			if payload == "[DONE]":
				_finish_ok()
				return
			var obj = JSON.parse_string(payload)
			if obj is Dictionary and obj.has("choices"):
				var ch: Array = obj["choices"]
				if ch.size() > 0 and ch[0].has("delta"):
					var d: Dictionary = ch[0]["delta"]
					# content 可能是 null（思考内容在别的字段里），str(null) 会变成 "<null>"
					if d.has("content") and typeof(d["content"]) == TYPE_STRING:
						var piece: String = d["content"]
						if piece != "":
							_chars += piece.length()
							_last_text += piece
							chat_delta.emit(piece)


func _finish_ok() -> void:
	if not _streaming:
		return
	_streaming = false
	_state = S_IDLE
	if _client:
		_client.close()
		_client = null
	var dt := Time.get_ticks_msec() / 1000.0 - _t0
	chat_done.emit({"secs": dt, "chars": _chars,
		"cps": (float(_chars) / dt) if dt > 0.0 else 0.0})


func _finish_error(msg: String) -> void:
	_streaming = false
	_state = S_IDLE
	if _client:
		_client.close()
		_client = null
	chat_failed.emit(msg)


## 打断当前生成（Agent 循环里的"停止"按钮用这个）
func cancel_chat() -> void:
	if not _streaming:
		return
	_streaming = false
	_state = S_IDLE
	set_process(false)
	if _client != null:
		_client.close()
		_client = null
	chat_failed.emit("已停止")


func is_streaming() -> bool:
	return _streaming


## 跑一轮对话并等它结束（工具循环用）。返回 {"ok": bool, "text": String}
func run_turn(messages: Array) -> Dictionary:
	if not ask(messages):
		return {"ok": false, "text": "", "error": "模型未就绪"}
	while _streaming:
		await get_tree().process_frame
		await get_tree().create_timer(0.01).timeout
	return {"ok": true, "text": _last_text}


# ---------------------------------------------------------------- 会话存储
func _chats_dir() -> String:
	return "user://chats"


func _load_chats() -> void:
	chats.clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_chats_dir()))
	var d := DirAccess.open(_chats_dir())
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.ends_with(".json"):
			var f := FileAccess.open(_chats_dir().path_join(n), FileAccess.READ)
			if f:
				var obj = JSON.parse_string(f.get_as_text())
				if obj is Dictionary:
					chats.append(obj)
		n = d.get_next()
	d.list_dir_end()
	chats.sort_custom(func(a, b): return float(a.get("updated", 0)) > float(b.get("updated", 0)))


func new_chat() -> Dictionary:
	var c := {
		"id": str(Time.get_unix_time_from_system()) + str(randi() % 1000),
		"title": "新对话",
		"messages": [],
		"updated": Time.get_unix_time_from_system(),
	}
	chats.insert(0, c)
	current_chat = 0
	_save_chat(c)
	return c


func _save_chat(c: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_chats_dir()))
	var f := FileAccess.open(_chats_dir().path_join(str(c["id"]) + ".json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(c, "  "))


## 保存指定会话（重命名等操作用，不依赖 current_chat）
func save_chat(idx: int) -> void:
	if idx < 0 or idx >= chats.size():
		return
	chats[idx]["updated"] = Time.get_unix_time_from_system()
	_save_chat(chats[idx])

func save_current() -> void:
	if current_chat >= 0 and current_chat < chats.size():
		chats[current_chat]["updated"] = Time.get_unix_time_from_system()
		_save_chat(chats[current_chat])


func delete_chat(idx: int) -> void:
	if idx < 0 or idx >= chats.size():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		_chats_dir().path_join(str(chats[idx]["id"]) + ".json")))
	chats.remove_at(idx)
	if current_chat >= chats.size():
		current_chat = chats.size() - 1








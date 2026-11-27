extends Node
## PluginStore —— 插件市场的"远程下载 + 自动部署"。
##
## 插件不随程序发布，而是从各自的 GitHub 仓库下载 zip 解压到 user://plugins/<id>/，
## 装完立刻热加载，不用重启。
##
## 索引文件放在 localharness-plugins 仓库的 index.json：
##   {"plugins": [{"id": "terminal", "name": "终端", "version": "0.1.0",
##                 "description": "...", "repo": "user/repo",
##                 "zip": "https://codeload.github.com/user/repo/zip/refs/heads/main"}]}
##
## 国内直连 raw.githubusercontent 常常不通，所以每个地址都有 gh-proxy 备选。

signal index_ready(items: Array, error: String)
signal install_progress(id: String, stage: String)
signal install_done(id: String, ok: bool, message: String)

const INDEX = "yushuchun177/localharness-plugins"


## 索引地址：raw.githubusercontent 会按 CDN 缓存旧文件，所以带分钟级时间戳当缓存键
## （jsDelivr 对 gh 文件会忽略查询串，只放最后当兜底）。
func _index_urls() -> Array:
	var bump := int(Time.get_unix_time_from_system() / 60)
	return [
		"https://raw.githubusercontent.com/%s/main/index.json?v=%d" % [INDEX, bump],
		"https://gh-proxy.com/https://raw.githubusercontent.com/%s/main/index.json?v=%d" % [INDEX, bump],
		"https://cdn.jsdelivr.net/gh/%s@main/index.json" % INDEX,
	]

var catalog: Array = []
var busy: bool = false


func _http() -> HTTPRequest:
	var r := HTTPRequest.new()
	r.timeout = 30.0
	add_child(r)
	return r


## 拉取索引；返回是否成功
func fetch_index() -> bool:
	if busy:
		return false
	busy = true
	var err_msg := ""
	for url in _index_urls():
		var req := _http()
		var err := req.request(url)
		if err != OK:
			req.queue_free()
			err_msg = "请求失败（%d）" % err
			continue
		var res: Array = await req.request_completed
		var code: int = res[1]
		var body: PackedByteArray = res[3]
		req.queue_free()
		if code == 200:
			var obj = JSON.parse_string(body.get_string_from_utf8())
			if obj is Dictionary and obj.has("plugins"):
				catalog = obj["plugins"]
				busy = false
				index_ready.emit(catalog, "")
				return true
			err_msg = "索引格式不对"
		else:
			err_msg = "HTTP %d" % code
	busy = false
	index_ready.emit([], err_msg)
	return false


func installed_version(id: String) -> String:
	for p in Plugins.loaded:
		if str(p["manifest"].get("id", "")) == id:
			return str(p["manifest"].get("version", ""))
	return ""


func install(item: Dictionary) -> bool:
	if busy:
		return false
	var id := str(item.get("id", ""))
	if id == "":
		return false
	busy = true
	install_progress.emit(id, "下载中…")

	var zip_path := "user://_plugin_%s.zip" % id
	var urls: Array = []
	if item.has("zip"):
		urls.append(str(item["zip"]))
	if item.has("repo"):
		urls.append("https://gh-proxy.com/https://codeload.github.com/%s/zip/refs/heads/main" % str(item["repo"]))
		urls.append("https://codeload.github.com/%s/zip/refs/heads/main" % str(item["repo"]))

	var ok := false
	for url in urls:
		var req := _http()
		req.download_file = zip_path
		var err := req.request(url)
		if err != OK:
			req.queue_free()
			continue
		var res: Array = await req.request_completed
		var code: int = res[1]
		req.queue_free()
		print("[plugin] %s ← %s : HTTP %d" % [id, url, code])
		if code == 200 and FileAccess.file_exists(zip_path):
			ok = true
			break

	if not ok:
		busy = false
		install_done.emit(id, false, "下载失败，检查网络或代理")
		return false

	install_progress.emit(id, "解压中…")
	var extracted := _extract(zip_path, id)
	print("[plugin] %s 解压结果: %s" % [id, extracted])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zip_path))
	busy = false
	if not extracted:
		install_done.emit(id, false, "解压失败")
		return false

	install_progress.emit(id, "加载中…")
	Plugins.load_all()
	var now := installed_version(id)
	if now == "":
		install_done.emit(id, false, "装好了但加载失败（看日志）")
		return false
	install_done.emit(id, true, "已安装 v%s" % now)
	return true


## GitHub 的 zip 里套了一层 <repo>-main/，把它剥掉再放到 user://plugins/<id>/
func _extract(zip_path: String, id: String) -> bool:
	var zr := ZIPReader.new()
	if zr.open(ProjectSettings.globalize_path(zip_path)) != OK:
		return false
	var dest := "user://plugins".path_join(id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	var files := zr.get_files()
	var wrote := 0
	for f in files:
		if f.ends_with("/"):
			continue
		var rel := f
		var slash := rel.find("/")
		if slash >= 0:
			rel = rel.substr(slash + 1)
		if rel == "":
			continue
		var out_path := dest.path_join(rel)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
		var data := zr.read_file(f)
		var w := FileAccess.open(out_path, FileAccess.WRITE)
		if w:
			w.store_buffer(data)
			w.close()
			wrote += 1
	zr.close()
	return wrote > 0 and FileAccess.file_exists(dest.path_join("manifest.json"))


func uninstall(id: String) -> void:
	var dir := "user://plugins".path_join(id)
	_rm_tree(ProjectSettings.globalize_path(dir))
	Plugins.load_all()


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full := path.path_join(n)
		if d.current_is_dir():
			_rm_tree(full)
		else:
			DirAccess.remove_absolute(full)
		n = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)



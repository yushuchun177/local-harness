extends SceneTree
## 临时诊断脚本：逐个加载 user://plugins/*/main.gd，打印能不能实例化。

func _init() -> void:
	var base := "user://plugins"
	var d := DirAccess.open(base)
	if d == null:
		print("no plugins dir")
		quit()
		return
	d.list_dir_begin()
	var sub := d.get_next()
	while sub != "":
		if d.current_is_dir():
			var path := base.path_join(sub).path_join("main.gd")
			if FileAccess.file_exists(path):
				var scr = load(path)
				var info := "?"
				if scr is GDScript:
					info = "base=%s can_instantiate=%s" % [scr.get_instance_base_type(), scr.can_instantiate()]
				print("%-10s %s" % [sub, info])
		sub = d.get_next()
	d.list_dir_end()
	quit()

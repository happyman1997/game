class_name ToolCommon
extends RefCounted
## Общее для инструментов командной строки: загрузка модов (встроенных и из
## папки игрока) и разбор аргументов вида --key value / --flag.


static func args() -> Dictionary:
	var out := {"_": []}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var s: String = a[i]
		if s.begins_with("--"):
			var key := s.substr(2)
			if i + 1 < a.size() and not a[i + 1].begins_with("--"):
				out[key] = a[i + 1]
				i += 1
			else:
				out[key] = true
		else:
			out._.append(s)
		i += 1
	return out


## Движок со всеми модами. opts: mods (строка "core,my_mod" — только эти), lang.
static func engine(opts: Dictionary = {}) -> GameEngine:
	var issues := []
	var pkgs := Platform.load_mod_packages(issues)
	var enabled: Variant = null
	if opts.get("mods") is String:
		enabled = Array(str(opts.mods).split(",", false))
	var e := GameEngine.create(pkgs, {"enabled": enabled, "lang": opts.get("lang", "ru"), "default_localization": Platform.default_localization()})
	e.issues.append_array(issues)
	return e

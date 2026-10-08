class_name Platform
extends RefCounted
## Всё, что связано с диском: настройки, папки игрока, моды и сохранения.
## Папка игрока — «Документы/Crown and Dynasty»: в ней mods/ (свои моды
## и замены встроенных) и save games/ (сохранения).

const FOLDER := "Crown and Dynasty"
const SETTINGS_PATH := "user://settings.cfg"

static var _cfg: ConfigFile


# ------------------------------------------------------------ настройки

static func _settings() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(SETTINGS_PATH)
	return _cfg


static func setting(key: String, fallback: Variant = null) -> Variant:
	var c := _settings()
	if not c.has_section_key("game", key):
		return fallback
	return c.get_value("game", key)


static func set_setting(key: String, value: Variant) -> void:
	var c := _settings()
	if value == null:
		if c.has_section_key("game", key):
			c.erase_section_key("game", key)
	else:
		c.set_value("game", key, value)
	c.save(SETTINGS_PATH)


# ------------------------------------------------------------ папки

static func user_dir() -> String:
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var base := docs.path_join(FOLDER) if docs != "" else ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(base)
	return base


static func folder(kind: String) -> String:
	var p := ""
	match kind:
		"mods": p = user_dir().path_join("mods")
		"saves": p = user_dir().path_join("save games")
		"user": p = user_dir()
		"builtin_mods": return ProjectSettings.globalize_path("res://mods")
		"cache": p = ProjectSettings.globalize_path("user://cache")
	if p != "":
		DirAccess.make_dir_recursive_absolute(p)
	return p


static func open_folder(kind: String) -> void:
	OS.shell_open(folder(kind))


# ------------------------------------------------------------ моды

## Встроенные моды (res://mods) и моды игрока: мод игрока с тем же id
## заменяет встроенный.
static func load_mod_packages(issues: Array) -> Array:
	var out: Array = []
	var by_id := {}
	for pkg in ModPackage.scan_dir("res://mods", "builtin", "встроенный", issues):
		by_id[pkg.id] = out.size()
		out.append(pkg)
	var user_mods := folder("mods")
	if DirAccess.dir_exists_absolute(user_mods):
		for pkg in ModPackage.scan_dir(user_mods, "folder", user_mods, issues):
			if by_id.has(pkg.id):
				out[by_id[pkg.id]] = pkg
			else:
				by_id[pkg.id] = out.size()
				out.append(pkg)
	return out


## Встроенные тексты интерфейса (locale/<язык>/*.yaml).
static func default_localization() -> Dictionary:
	var defaults := {}
	for lang in DirAccess.get_directories_at("res://locale"):
		defaults[lang] = []
		for f in DirAccess.get_files_at("res://locale/" + lang):
			f = f.trim_suffix(".remap")
			if f.ends_with(".yaml"):
				var text := FileAccess.get_file_as_string("res://locale/%s/%s" % [lang, f])
				defaults[lang].append(Yaml.parse(text, f).value)
	return defaults


# ------------------------------------------------------------ сохранения

static func _slot_file(slot: String) -> String:
	var safe := slot.validate_filename()
	return folder("saves").path_join(safe + ".sav")


static func _meta_file(slot: String) -> String:
	return folder("saves").path_join(slot.validate_filename() + ".meta.json")


## Список сохранений (новые сверху): [{slot, name, date, player, saved_at, time}].
static func list_saves() -> Array:
	var dir := folder("saves")
	var out := []
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".sav"):
			continue
		var slot := f.trim_suffix(".sav")
		var meta := {"slot": slot, "name": slot, "date": "", "player": "", "saved_at": ""}
		var mtext := FileAccess.get_file_as_string(_meta_file(slot))
		if mtext != "":
			var parsed: Variant = JSON.parse_string(mtext)
			if parsed is Dictionary:
				meta.merge(parsed, true)
		meta.slot = slot
		meta.time = FileAccess.get_modified_time(dir.path_join(f))
		out.append(meta)
	out.sort_custom(func(a, b): return a.time > b.time)
	return out


static func read_save(slot: String) -> Variant:
	var f := FileAccess.open_compressed(_slot_file(slot), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	return f.get_as_text()


static func write_save(meta: Dictionary, json: String) -> Error:
	var slot: String = meta.slot
	var f := FileAccess.open_compressed(_slot_file(slot), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(json)
	f.close()
	var m := FileAccess.open(_meta_file(slot), FileAccess.WRITE)
	if m != null:
		m.store_string(JSON.stringify(meta, "  "))
	return OK


static func delete_save(slot: String) -> void:
	DirAccess.remove_absolute(_slot_file(slot))
	DirAccess.remove_absolute(_meta_file(slot))

class_name ModPackage
extends RefCounted
## Мод: описание (mod.json) + источник файлов.
##
## mod.json:
##   id, name ({ru, en} или строка), version, description, author,
##   dependencies — без них мод не работает (грузятся раньше),
##   load_after — если указанные моды включены, грузиться после них,
##   priority — меньше раньше (у core = -100),
##   data — папки данных (по умолчанию ["data"]),
##   localization — папка локализации (по умолчанию "localization"),
##   scripts — GDScript-файлы с функцией init(api),
##   default_enabled, tags.

var manifest: Dictionary
var source: ModSource
## Человекочитаемое происхождение: «встроенный» или путь к папке.
var origin: String


func _init(m: Dictionary, s: ModSource, o: String) -> void:
	manifest = m
	source = s
	origin = o


var id: String:
	get:
		return str(manifest.get("id", ""))


func display_name(lang: String) -> String:
	return _text(manifest.get("name", id), lang)


func description(lang: String) -> String:
	return _text(manifest.get("description", ""), lang)


static func _text(v: Variant, lang: String) -> String:
	if v is Dictionary:
		if v.has(lang):
			return str(v[lang])
		if v.has("en"):
			return str(v["en"])
		return str(v.values()[0]) if not v.is_empty() else ""
	return str(v) if v != null else ""


## Находит моды (подпапки с mod.json) в папке.
static func scan_dir(dir: String, kind: String, origin_label: String, issues: Array) -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var names := Array(DirAccess.get_directories_at(dir))
	names.sort()
	for n in names:
		var root: String = dir.trim_suffix("/") + "/" + n
		var mpath = root + "/mod.json"
		if not FileAccess.file_exists(mpath):
			continue
		var r := FormatRegistry.create_default().parse(FileAccess.get_file_as_string(mpath), mpath)
		if not r.ok or not (r.value is Dictionary):
			issues.append({"mod": n, "level": "error", "message": "Не удалось прочитать mod.json: " + str(r.error)})
			continue
		var m: Dictionary = r.value
		if not m.has("id"):
			m["id"] = n
		out.append(ModPackage.new(m, ModSource.new(root, kind), origin_label if origin_label != "" else root))
	return out

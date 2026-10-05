class_name ModSource
extends RefCounted
## Папка мода: встроенная (res://mods/…) или на диске (Документы/…/mods/…).
## Пути файлов — относительно корня мода, через «/».

var root: String
var kind: String


func _init(dir: String, source_kind: String = "folder") -> void:
	root = dir.trim_suffix("/")
	kind = source_kind


func list_files() -> PackedStringArray:
	var out := PackedStringArray()
	_walk(root, "", out)
	out.sort()
	return out


func _walk(dir: String, rel: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		# В экспортированной игре скрипты лежат как .gd.remap / .gdc — показываем исходное имя.
		var name := f.trim_suffix(".remap")
		if name.ends_with(".gdc"):
			name = name.trim_suffix(".gdc") + ".gd"
		if name.ends_with(".import"):
			continue
		var p := (rel + "/" + name) if rel != "" else name
		if not out.has(p):
			out.append(p)
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		_walk(dir + "/" + d, (rel + "/" + d) if rel != "" else d, out)


func full_path(path: String) -> String:
	return root + "/" + path


func exists(path: String) -> bool:
	return FileAccess.file_exists(full_path(path))


## Текст файла или null, если его не удалось прочитать.
func read_text(path: String) -> Variant:
	var f := FileAccess.open(full_path(path), FileAccess.READ)
	if f == null:
		return null
	return f.get_as_text()


## Загружает GDScript мода. Возвращает экземпляр скрипта или строку с ошибкой.
func load_script(path: String) -> Variant:
	var full := full_path(path)
	var script: Script = null
	if full.begins_with("res://"):
		script = load(full) as Script
	else:
		var text: Variant = read_text(path)
		if text == null:
			return "не найден файл " + path
		var gd := GDScript.new()
		gd.source_code = text
		gd.resource_path = full
		var err := gd.reload()
		if err != OK:
			return "ошибка компиляции %s (код %d)" % [path, err]
		script = gd
	if script == null:
		return "не удалось загрузить " + path
	if not script.can_instantiate():
		return "скрипт %s не может быть создан" % path
	return script.new()

class_name ContentStore
extends RefCounted
## Хранилище контента — результат слияния данных всех модов.
##
## Каждый файл данных — это словарь «тип контента → { id → определение }»:
##
##   traits:
##     brave: { ... }
##   events:
##     my_mod.0001: { ... }
##
## Типы-«синглтоны» (defines, map) — это один словарь, а не коллекция.
## Неизвестные типы тоже сохраняются: так мод может завести свой тип
## контента и читать его из скрипта через content.all("мой_тип").

const SINGLETON_TYPES := ["defines", "map"]

var _collections := {}
var _singletons := {}
## "тип/id" → список модов, которые определили или изменили запись.
var provenance := {}


## Возвращает текст ошибки или "".
func merge_section(type: String, data: Variant, mod_id: String) -> String:
	if type in SINGLETON_TYPES:
		var merged: Variant = Data.deep_merge(_singletons.get(type, {}), data)
		_singletons[type] = {} if Data.is_delete(merged) else merged
		_track(type, "*", mod_id)
		return ""
	if not (data is Dictionary):
		return "Раздел \"%s\" должен быть словарём id → определение" % type
	var col: Dictionary = _collection(type)
	for id in data:
		var def: Variant = data[id]
		var merged: Variant = Data.deep_merge(col.get(id), def if def != null else {})
		if Data.is_delete(merged):
			col.erase(id)
		else:
			if merged is Dictionary:
				merged["id"] = str(id)
			col[str(id)] = merged
		_track(type, str(id), mod_id)
	return ""


func _track(type: String, id: String, mod_id: String) -> void:
	var k := type + "/" + id
	var l: Array = provenance.get(k, [])
	if not l.has(mod_id):
		l.append(mod_id)
	provenance[k] = l


func _collection(type: String) -> Dictionary:
	if not _collections.has(type):
		_collections[type] = {}
	return _collections[type]


func get_def(type: String, id: Variant) -> Variant:
	if id == null:
		return null
	var col: Variant = _collections.get(type)
	if col == null:
		return null
	return col.get(id)


func has(type: String, id: Variant) -> bool:
	return id != null and _collections.has(type) and _collections[type].has(id)


func set_def(type: String, id: String, def: Variant) -> void:
	if def is Dictionary:
		def["id"] = id
	_collection(type)[id] = def


func remove(type: String, id: String) -> void:
	if _collections.has(type):
		_collections[type].erase(id)


func all(type: String) -> Array:
	return _collections[type].values() if _collections.has(type) else []


func ids(type: String) -> Array:
	return _collections[type].keys() if _collections.has(type) else []


## Сама коллекция (id → определение) — для изменения из скриптов модов.
func collection(type: String) -> Dictionary:
	return _collection(type)


func singleton(type: String) -> Dictionary:
	if not _singletons.has(type):
		_singletons[type] = {}
	return _singletons[type]


func set_singleton(type: String, value: Dictionary) -> void:
	_singletons[type] = value


func types() -> Array:
	return _collections.keys() + _singletons.keys()

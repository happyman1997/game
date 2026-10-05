class_name Registry
extends RefCounted
## Универсальный реестр «id → объект». Почти всё расширяемое в движке
## (триггеры, эффекты, системы, алгоритмы наследования, режимы карты)
## хранится в таких реестрах, поэтому мод может добавить или заменить
## любой элемент одной строкой.

var kind: String
var _map := {}
var _owners := {}


func _init(k: String = "") -> void:
	kind = k


func register(id: String, item: Variant, owner: String = "") -> Registry:
	_map[id] = item
	if owner != "":
		_owners[id] = owner
	return self


func get_item(id: String) -> Variant:
	return _map.get(id)


func require(id: String) -> Variant:
	if not _map.has(id):
		push_error("%s: \"%s\" не зарегистрирован" % [kind, id])
		return null
	return _map[id]


func has(id: String) -> bool:
	return _map.has(id)


func remove(id: String) -> bool:
	_owners.erase(id)
	return _map.erase(id)


func owner_of(id: String) -> String:
	return _owners.get(id, "")


func ids() -> Array:
	return _map.keys()


func values() -> Array:
	return _map.values()


func size() -> int:
	return _map.size()

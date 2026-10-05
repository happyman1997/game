class_name ScriptContext
extends RefCounted
## Контекст выполнения скрипта: корневой скоуп (root), сохранённые
## скоупы (scope:имя), сохранённые значения и предыдущий скоуп (prev).
## Скоуп — словарь {"type": "character", "id": "ch12"}.

var game: Game
var root: Dictionary
var scopes: Dictionary
var values := {}
var prev: Variant = null
var depth := 0
## Режим описания: эффекты не применяются.
var describing := false


func _init(g: Game, r: Dictionary, sc: Dictionary = {}) -> void:
	game = g
	root = r
	scopes = sc.duplicate()


static func make(g: Game, r: Dictionary, sc: Dictionary = {}) -> ScriptContext:
	return ScriptContext.new(g, r, sc)


static func char_ref(id: String) -> Dictionary:
	return {"type": "character", "id": id}


static func title_ref(id: String) -> Dictionary:
	return {"type": "title", "id": id}


static func prov_ref(id: String) -> Dictionary:
	return {"type": "province", "id": id}


static func same_scope(a: Variant, b: Variant) -> bool:
	return a != null and b != null and a.type == b.type and a.id == b.id


static func is_yes(v: Variant) -> bool:
	return (v is bool and v) or (v is String and (v == "yes" or v == "true")) or (v is int and v == 1)

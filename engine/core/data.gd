class_name Data
extends RefCounted
## Работа с данными модов: глубокое слияние с директивами, копирование,
## приведение чисел после JSON.
##
## По умолчанию словари сливаются рекурсивно, а списки и скаляры
## заменяются. Директивы:
##   $replace: true      — заменить словарь целиком, а не сливать
##   $delete: true       — удалить запись/поле
##   { $append: [...] }  — дописать элементы в конец списка
##   { $prepend: [...] } — дописать в начало списка
##   { $remove: [...] }  — удалить элементы (по значению или по полю id)

## Маркер удаления, который возвращает deep_merge.
const DELETE := &"__delete__"


static func clone(v: Variant) -> Variant:
	if v is Dictionary or v is Array:
		return v.duplicate(true)
	return v


static func _is_array_op(v: Variant) -> bool:
	if not (v is Dictionary) or v.is_empty():
		return false
	for k in v:
		if not (k == "$append" or k == "$prepend" or k == "$remove"):
			return false
	return true


static func _same_item(a: Variant, b: Variant) -> bool:
	if typeof(a) == typeof(b) and a == b:
		return true
	if a is Dictionary and b is Dictionary and b.has("id"):
		return a.get("id") == b.get("id")
	if a is Dictionary and b is String:
		return a.get("id") == b
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return JSON.stringify(a) == JSON.stringify(b)


static func _strip_directives(v: Variant) -> Variant:
	if v is Array:
		var out := []
		for x in v:
			out.append(_strip_directives(x))
		return out
	if v is Dictionary:
		var out := {}
		for k in v:
			if k == "$replace" or k == "$delete":
				continue
			out[k] = _strip_directives(v[k])
		return out
	return v


static func deep_merge(base: Variant, patch: Variant) -> Variant:
	if patch is Dictionary:
		if patch.get("$delete") == true:
			return DELETE
		if _is_array_op(patch):
			var arr: Array = base.duplicate() if base is Array else []
			if patch.has("$remove"):
				var rem: Array = patch["$remove"] if patch["$remove"] is Array else [patch["$remove"]]
				arr = arr.filter(func(x): return not rem.any(func(r): return _same_item(x, r)))
			if patch.has("$prepend"):
				arr = clone(patch["$prepend"]) + arr
			if patch.has("$append"):
				arr = arr + clone(patch["$append"])
			return arr
		if patch.get("$replace") == true or not (base is Dictionary):
			return _strip_directives(clone(patch))
		var out: Dictionary = base.duplicate(true)
		for k in patch:
			if k == "$replace" or k == "$delete":
				continue
			var v: Variant = deep_merge(base.get(k), patch[k])
			if typeof(v) == TYPE_STRING_NAME and v == DELETE:
				out.erase(k)
			else:
				out[k] = v
		return out
	return clone(patch)


static func is_delete(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING_NAME and v == DELETE


## JSON в Godot читает все числа как float; целые значения возвращаем в int,
## чтобы идентификаторы и индексы оставались целыми.
static func ints_from_json(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		if f == floorf(f) and absf(f) < 9.0e15:
			return int(f)
		return f
	if v is Array:
		for i in v.size():
			v[i] = ints_from_json(v[i])
		return v
	if v is Dictionary:
		for k in v.keys():
			v[k] = ints_from_json(v[k])
		return v
	return v


static func as_array(v: Variant) -> Array:
	if v == null:
		return []
	if v is Array:
		return v
	return [v]


static func num(v: Variant, fallback: float = 0.0) -> float:
	if v is int or v is float:
		return float(v)
	if v is bool:
		return 1.0 if v else 0.0
	if v is String and v.is_valid_float():
		return float(v)
	return fallback

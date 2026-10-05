class_name HookBus
extends RefCounted
## Шина хуков. Через неё движок оповещает моды о событиях мира
## («персонаж умер», «началась война», «наступил новый месяц»...),
## а моды могут вмешиваться: отменять действия (veto) или
## добавлять свои значения (collect).
##
## Обработчик — Callable(payload: Dictionary) -> Variant.
## Ошибка в обработчике мода не роняет игру: GDScript прерывает только
## этот обработчик, остальные продолжают работать.

var _handlers := {}


## Подписка. Возвращает Callable для отписки.
func on(hook_name: String, fn: Callable, priority: int = 0, owner: String = "") -> Callable:
	var list: Array = _handlers.get(hook_name, [])
	list.append({"fn": fn, "priority": priority, "owner": owner})
	list.sort_custom(func(a, b): return a.priority > b.priority)
	_handlers[hook_name] = list
	return func(): off(hook_name, fn)


func off(hook_name: String, fn: Callable) -> void:
	if not _handlers.has(hook_name):
		return
	_handlers[hook_name] = _handlers[hook_name].filter(func(e): return e.fn != fn)


func has(hook_name: String) -> bool:
	return not _handlers.get(hook_name, []).is_empty()


func emit(hook_name: String, payload: Dictionary = {}) -> void:
	for e in _handlers.get(hook_name, []):
		e.fn.call(payload)


## Возвращает false, если хотя бы один обработчик вернул false.
func veto(hook_name: String, payload: Dictionary = {}) -> bool:
	for e in _handlers.get(hook_name, []):
		var r: Variant = e.fn.call(payload)
		if r is bool and r == false:
			return false
	return true


## Собирает все не-null результаты обработчиков.
func collect(hook_name: String, payload: Dictionary = {}) -> Array:
	var out := []
	for e in _handlers.get(hook_name, []):
		var r: Variant = e.fn.call(payload)
		if r != null:
			out.append(r)
	return out


func names() -> Array:
	return _handlers.keys()

class_name EngineFeature
extends RefCounted
## Механика движка (образ жизни, совет, темница…). Каждая механика —
## отдельный модуль:
##   register_script(engine) — триггеры/эффекты/значения скриптового языка
##     (регистрируются всегда, чтобы данные модов проверялись и не ломались,
##     даже если механика отключена);
##   install(engine) — системы, хуки, поставщики модификаторов; вызывается,
##     только если механика включена.
## Отключить механику: defines.disabled_features: [council, ...].
## Записи контента с полем requires_feature: <id> удаляются, если механика
## отключена.

var id := ""
var doc := ""


func register_script(_engine: GameEngine) -> void:
	pass


func install(_engine: GameEngine) -> void:
	pass


## Суммирует блок модификаторов, где значения — числа или скриптовые значения.
static func eval_modifiers(ctx: ScriptContext, scope: Dictionary, mods: Variant) -> Dictionary:
	var out := {}
	if not (mods is Dictionary):
		return out
	for k in mods:
		var v: Variant = mods[k]
		out[k] = float(v) if (v is int or v is float) else Interp.eval_value(ctx, scope, v)
	return out

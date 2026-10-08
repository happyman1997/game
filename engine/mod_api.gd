class_name ModApi
extends RefCounted
## API, которое получает GDScript-скрипт мода в функции init(api).
##
##   extends RefCounted
##
##   func init(api: ModApi) -> void:
##       api.effect("my_effect", {"apply": func(ctx, scope, arg): ...})
##       api.add_system({"id": "my_system", "order": 100, "on_month": func(game): ...})
##       api.on("character.death", func(p): print(p.character.name))
##       api.ui.map_modes.register("my_mode", {"id": "my_mode", "name": "Мой режим", "color": func(game, prov): return Color.RED})
##
## Логика мира доступна через глобальные классы движка: Chars, Titles,
## Succession, Economy, Military, Wars, Opinion, Stats, Interp, ScriptContext…

var mod: Dictionary
var engine: GameEngine
var owner: String


func _init(e: GameEngine, manifest: Dictionary) -> void:
	engine = e
	mod = manifest
	owner = str(manifest.get("id", "unknown"))


var content: ContentStore:
	get:
		return engine.content

var loc: Localization:
	get:
		return engine.loc

var formats: FormatRegistry:
	get:
		return engine.formats

var ui: UiRegistry:
	get:
		return engine.ui

var hooks: HookBus:
	get:
		return engine.hooks

## Реестры мира: succession_algorithms, cb_targets, interaction_targets,
## interaction_deciders, modifier_providers, province_modifier_providers,
## opinion_providers, content_validators.
var registries: Dictionary:
	get:
		return engine.registries()


func defines() -> Dictionary:
	return engine.content.singleton("defines")


# ------------------------------------------------------------ скриптовый язык

func trigger(tname: String, def: Dictionary) -> void:
	engine.scripting.triggers.register(tname, def, owner)


func effect(ename: String, def: Dictionary) -> void:
	engine.scripting.effects.register(ename, def, owner)


func value(vname: String, def: Dictionary) -> void:
	engine.scripting.values.register(vname, def, owner)


func link(lname: String, def: Dictionary) -> void:
	engine.scripting.links.register(lname, def, owner)


func list(lname: String, def: Dictionary) -> void:
	engine.scripting.lists.register(lname, def, owner)


func constant(cname: String, v: float) -> void:
	engine.scripting.constants.register(cname, v, owner)


# ------------------------------------------------------------ хуки

func on(hook_name: String, fn: Callable, priority: int = 0) -> Callable:
	return engine.hooks.on(hook_name, fn, priority, owner)


func emit(hook_name: String, payload: Dictionary = {}) -> void:
	engine.hooks.emit(hook_name, payload)


# ------------------------------------------------------------ системы

func add_system(s: Dictionary) -> void:
	engine.systems.register(s.id, s, owner)


## Заменить часть полей системы (например, только on_month).
func replace_system(id: String, patch: Dictionary) -> void:
	var prev: Variant = engine.systems.get_item(id)
	var s: Dictionary = prev.duplicate() if prev != null else {"order": 100}
	s.merge(patch, true)
	s["id"] = id
	engine.systems.register(id, s, owner)


func remove_system(id: String) -> void:
	engine.systems.remove(id)


func get_system(id: String) -> Variant:
	return engine.systems.get_item(id)


func list_systems() -> Array:
	return engine.systems.ids()


# ------------------------------------------------------------ механики

## Установить свою механику (EngineFeature) или заменить встроенную.
func add_feature(f: EngineFeature) -> void:
	engine.features.register(f.id, f, owner)
	f.register_script(engine)
	f.install(engine)
	engine.installed_features[f.id] = true


func has_feature(id: String) -> bool:
	return engine.has_feature(id)


func list_features() -> Array:
	return engine.features.ids()


func log(msg: Variant) -> void:
	print("[%s] %s" % [owner, msg])

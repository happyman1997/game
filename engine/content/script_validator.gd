class_name ScriptValidator
extends RefCounted
## Проверка скриптовых блоков: неизвестные триггеры, эффекты и ссылки
## на несуществующие записи контента. Механики и моды добавляют свои
## проверки через engine.content_validators: Callable(engine, validator).

const TRIGGER_CONTROL := ["AND", "and", "OR", "or", "NOT", "not", "NOR", "nor", "NAND", "always", "exists", "is", "this", "custom_tooltip", "custom_description", "desc", "text"]
const EFFECT_CONTROL := ["if", "else_if", "else", "effect", "hidden_effect", "then", "custom_tooltip", "limit", "random", "random_list", "save_scope_as", "save_scope_value_as", "trigger_event"]
const LOGIC := ["AND", "and", "OR", "or", "NOT", "not", "NOR", "nor", "NAND"]

## Аргументы-ссылки на контент: has_trait: brave → traits/brave должна существовать.
const ARG_REFS := {
	"has_trait": ["traits", ""], "add_trait": ["traits", ""], "remove_trait": ["traits", ""],
	"has_modifier": ["modifiers", ""], "add_modifier": ["modifiers", "id"], "remove_modifier": ["modifiers", ""],
	"add_province_modifier": ["modifiers", "id"],
	"add_opinion": ["opinion_modifiers", "modifier"], "reverse_add_opinion": ["opinion_modifiers", "modifier"],
	"has_building": ["buildings", ""], "add_building": ["buildings", ""],
	"culture": ["cultures", ""], "faith": ["faiths", ""], "change_culture": ["cultures", ""], "change_faith": ["faiths", ""],
	"set_succession_law": ["succession_laws", ""],
	"has_perk": ["perks", ""], "add_perk": ["perks", ""], "has_focus": ["focuses", ""], "set_focus": ["focuses", ""],
	"has_secret": ["secret_types", ""], "has_realm_law": ["realm_laws", ""], "set_realm_law": ["realm_laws", ""],
	"add_regiment": ["regiment_types", ""], "has_regiment": ["regiment_types", ""],
}

var issues: Array = []
var engine: GameEngine


func _init(e: GameEngine) -> void:
	engine = e


## Предупреждение от проверки механики или мода.
func issue(message: String, level: String = "warning") -> void:
	issues.append({"level": level, "message": message})


## Проверка ссылки на запись контента.
func ref(type: String, id: Variant, where: String) -> void:
	if id == null:
		return
	if not engine.content.has(type, str(id)):
		issue("%s: ссылка на несуществующий %s/%s" % [where, type, id])


## Проверка скриптового значения (только ссылок на триггеры внутри limit).
func value(expr: Variant, where: String) -> void:
	if not (expr is Dictionary):
		return
	for k in expr:
		if k == "limit":
			trigger(expr[k], where)
		elif k in ["if", "add", "multiply", "subtract"]:
			for x in Data.as_array(expr[k]):
				value(x, where)


func _warn(where: String, msg: String) -> void:
	var mods: Array = engine.content.provenance.get(where.split(" ")[0], [])
	issues.append({"level": "warning", "mod": mods[mods.size() - 1] if not mods.is_empty() else null, "message": "%s: %s" % [where, msg]})


func _check_arg_refs(key: String, arg: Variant, where: String) -> void:
	if not ARG_REFS.has(key):
		return
	var spec: Array = ARG_REFS[key]
	var vals := []
	if spec[1] != "" and arg is Dictionary:
		vals = [arg.get(spec[1])]
	else:
		vals = Data.as_array(arg)
	for x in vals:
		if not (x is String) or x == "yes" or x == "no" or x.contains(":") or x.contains("."):
			continue
		if spec[0] == "opinion_modifiers" and x == "generic":
			continue
		if not engine.content.has(spec[0], x):
			_warn(where, "%s: нет %s/%s" % [key, spec[0], x])


func _is_path_key(key: String) -> bool:
	var r := engine.scripting
	if key.begins_with("scope:") or key.begins_with("title:") or key.begins_with("character:") or key.begins_with("province:"):
		return true
	if key == "root" or key == "prev" or key == "this":
		return true
	if key.contains("."):
		var first := key.split(".")[0]
		return _is_path_key(first) or r.links.has(first)
	return r.links.has(key)


func _is_value_key(key: String) -> bool:
	var i := key.find("(")
	var vname := key.substr(0, i) if i >= 0 else key
	return engine.scripting.values.has(vname) or engine.content.has("script_values", vname) or vname.begins_with("var:") or vname.begins_with("global_var:")


func trigger(block: Variant, where: String) -> void:
	if block == null or block is bool:
		return
	if block is String:
		if block != "yes" and block != "no" and not engine.content.has("scripted_triggers", block):
			_warn(where, "неизвестный триггер \"%s\"" % block)
		return
	if block is Array:
		for b in block:
			trigger(b, where)
		return
	if not (block is Dictionary):
		return
	var r := engine.scripting
	for k in block:
		var v: Variant = block[k]
		if k in LOGIC:
			trigger(v, where)
			continue
		if k == "custom_tooltip" or k == "custom_description":
			if v is Dictionary:
				trigger(v.get("trigger"), where)
			continue
		if k in TRIGGER_CONTROL:
			continue
		if k.begins_with("any_") and r.lists.has(k.substr(4)):
			if v is Dictionary:
				var rest: Dictionary = v.duplicate()
				rest.erase("count")
				rest.erase("percent")
				trigger(rest, where)
			continue
		if r.triggers.has(k) or engine.content.has("scripted_triggers", k):
			_check_arg_refs(k, v, where)
			continue
		if _is_value_key(k):
			continue
		if _is_path_key(k):
			if v is Dictionary or v is Array:
				trigger(v, where)
			continue
		_warn(where, "неизвестный триггер \"%s\"" % k)


func effect(block: Variant, where: String) -> void:
	if block == null:
		return
	if block is String:
		if not engine.content.has("scripted_effects", block) and not engine.scripting.effects.has(block):
			_warn(where, "неизвестный эффект \"%s\"" % block)
		return
	if block is Array:
		for b in block:
			effect(b, where)
		return
	if not (block is Dictionary):
		return
	var r := engine.scripting
	for k in block:
		var v: Variant = block[k]
		if k == "if" or k == "else_if":
			for b in Data.as_array(v):
				if not (b is Dictionary):
					continue
				trigger(b.get("limit"), where)
				effect(b.get("then"), where)
				effect(b.get("else"), where)
				var rest: Dictionary = b.duplicate()
				for x in ["limit", "then", "else", "else_if"]:
					rest.erase(x)
				effect(rest, where)
				if b.get("else_if") != null:
					effect({"else_if": b.else_if}, where)
			continue
		if k in ["else", "effect", "hidden_effect", "then"]:
			effect(v, where)
			continue
		if k == "random":
			if v is Dictionary:
				var rest: Dictionary = v.duplicate()
				rest.erase("chance")
				effect(rest, where)
			continue
		if k == "random_list":
			var items: Array = v if v is Array else (v.values() if v is Dictionary else [])
			for it in items:
				if not (it is Dictionary):
					continue
				if v is Array:
					trigger(it.get("trigger"), where)
					var rest: Dictionary = it.duplicate()
					for x in ["weight", "trigger", "effect"]:
						rest.erase(x)
					effect(it.get("effect", rest), where)
				else:
					effect(it, where)
			continue
		if k == "custom_tooltip":
			if v is Dictionary:
				effect(v.get("effect"), where)
			continue
		if k == "trigger_event":
			var id: Variant = v if v is String else (v.get("id") if v is Dictionary else null)
			if id != null and not engine.content.has("events", id):
				_warn(where, "trigger_event: нет события \"%s\"" % id)
			continue
		if k in EFFECT_CONTROL:
			continue
		var iter := false
		for p in ["every_", "random_", "ordered_"]:
			if k.begins_with(p) and r.lists.has(k.substr(p.length())):
				iter = true
		if iter:
			if v is Dictionary:
				trigger(v.get("limit"), where)
				var rest: Dictionary = v.duplicate()
				for x in ["limit", "weight", "order_by", "max", "position"]:
					rest.erase(x)
				effect(rest, where)
			continue
		if r.effects.has(k) or engine.content.has("scripted_effects", k):
			_check_arg_refs(k, v, where)
			continue
		if _is_path_key(k):
			effect(v, where)
			continue
		_warn(where, "неизвестный эффект \"%s\"" % k)

class_name Interp
extends RefCounted
## Интерпретатор скриптового языка данных.
##
## Триггер — словарь условий (все должны выполняться):
##   { is_adult: yes, gold: ">= 100", liege: { has_trait: brave }, OR: [...] }
## Эффект — словарь или список команд:
##   [ { add_gold: 50 }, { if: { limit: {...}, then: {...}, else: {...} } } ]
## Значение — число, путь ("scope:actor.diplomacy") или словарь
##   { value: 10, add: [...], multiply: 2, if: { limit: ..., add: 5 }, min: 0 }

const MAX_DEPTH := 60

const PREFIXED := {
	"character:": "character",
	"title:": "title",
	"province:": "province",
	"dynasty:": "dynasty",
	"war:": "war",
	"scheme:": "scheme",
}

const OP_ALIASES := {
	"gte": ">=", "gt": ">", "lte": "<=", "lt": "<", "eq": "==", "ne": "!=",
	">=": ">=", ">": ">", "<=": "<=", "<": "<", "==": "==", "=": "==", "!=": "!=",
	"min": ">=", "max": "<=",
}

static var _cmp_re: RegEx
static var _name_re: RegEx


static func _re_cmp() -> RegEx:
	if _cmp_re == null:
		_cmp_re = RegEx.create_from_string("^\\s*(>=|<=|==|!=|>|<|=)\\s*(.+)$")
	return _cmp_re


static func _re_name() -> RegEx:
	if _name_re == null:
		_name_re = RegEx.create_from_string("^([\\w:]+)(?:\\((.*)\\))?$")
	return _name_re


## Тело именованного блока (scripted_trigger/effect/script_value): поле field или вся запись без id.
static func body_of(def: Variant, field: String) -> Variant:
	if not (def is Dictionary):
		return def
	if def.has(field):
		return def[field]
	var rest: Dictionary = def.duplicate()
	rest.erase("id")
	rest.erase("desc")
	return rest


# ---------------------------------------------------------------- пути

## Разбивает "scope:a.liege.opinion(scope:b.father)" по точкам вне скобок.
## Кэши разбора строк скриптов: строк в контенте конечное число, а
## разбор (регулярные выражения, split) — самая частая работа интерпретатора.
static var _split_cache := {}
static var _name_cache := {}
static var _cmp_cache := {}
static var _path_kind := {}


static func split_path(path: String) -> PackedStringArray:
	var hit: Variant = _split_cache.get(path)
	if hit != null:
		return hit
	var r := _split_path_raw(path)
	if _split_cache.size() > 20000:
		_split_cache.clear()
	_split_cache[path] = r
	return r


static func _split_path_raw(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if path.find("(") < 0:
		for s in path.split("."):
			var t := s.strip_edges()
			if t != "":
				out.append(t)
		return out
	var depth := 0
	var cur := ""
	for c in path:
		if c == "(":
			depth += 1
		if c == ")":
			depth -= 1
		if c == "." and depth == 0:
			if cur.strip_edges() != "":
				out.append(cur.strip_edges())
			cur = ""
		else:
			cur += c
	if cur.strip_edges() != "":
		out.append(cur.strip_edges())
	return out


static func step_scope(ctx: ScriptContext, cur: Variant, seg: String, first: bool) -> Variant:
	var game := ctx.game
	if seg == "root":
		return ctx.root
	if seg == "this":
		return cur
	if seg == "prev":
		return ctx.prev
	if seg.begins_with("scope:"):
		return ctx.scopes.get(seg.substr(6))
	for p in PREFIXED:
		if seg.begins_with(p):
			var ref := {"type": PREFIXED[p], "id": seg.substr(p.length())}
			return ref if game.exists(ref) else null
	var link: Variant = game.engine.scripting.links.get_item(seg)
	if link != null:
		if cur == null:
			return null
		if link.has("from") and not link.from.has(cur.type):
			return null
		return link.resolve.call(ctx, cur)
	if first and game.state.titles.has(seg):
		return {"type": "title", "id": seg}
	if first and game.state.characters.has(seg):
		return {"type": "character", "id": seg}
	return null


static func is_scope_start(ctx: ScriptContext, seg: String) -> bool:
	if seg == "root" or seg == "this" or seg == "prev" or seg.begins_with("scope:"):
		return true
	for p in PREFIXED:
		if seg.begins_with(p):
			return true
	return ctx.game.engine.scripting.links.has(seg)


## Разрешает путь к скоупу: "scope:actor.liege", "root.primary_title", "title:k_england".
static func resolve_scope(ctx: ScriptContext, scope: Variant, path: Variant) -> Variant:
	if path == null:
		return null
	if path is Dictionary:
		if path.get("type") is String and path.get("id") is String:
			return path
		return null
	if not (path is String or path is StringName):
		return null
	var segs := split_path(str(path))
	var cur: Variant = scope
	for i in segs.size():
		cur = step_scope(ctx, cur, segs[i], i == 0)
		if cur == null:
			return null
	return cur


# ---------------------------------------------------------------- значения

## parts — необязательный массив, куда складываются слагаемые [{label, value}] для подсказок.
static func eval_value(ctx: ScriptContext, scope: Variant, expr: Variant, parts: Variant = null) -> float:
	if expr == null:
		return 0.0
	if expr is int or expr is float:
		return float(expr)
	if expr is bool:
		return 1.0 if expr else 0.0
	if expr is String or expr is StringName:
		return _eval_value_path(ctx, scope, str(expr))
	if expr is Array:
		var s := 0.0
		for e in expr:
			s += eval_value(ctx, scope, e)
		return s
	if expr is Dictionary:
		return _apply_value_ops(ctx, scope, 0.0, expr, parts)
	return 0.0


static func _apply_value_ops(ctx: ScriptContext, scope: Variant, start: float, ops: Dictionary, parts: Variant = null) -> float:
	var v := start
	var game := ctx.game
	for k in ops:
		var arg: Variant = ops[k]
		match k:
			"value", "base":
				v = eval_value(ctx, scope, arg)
				if parts != null and ops.get("desc") == null and v != 0.0:
					parts.append({"label": game.text(ops.get("base_desc", "ui.base_value")), "value": v})
			"add", "subtract":
				for it in Data.as_array(arg):
					var x: float
					if it is Dictionary and (it.has("limit") or it.has("trigger")):
						if not eval_trigger(ctx, scope, it.get("limit", it.get("trigger"))):
							continue
						x = eval_value(ctx, scope, it.get("value", 0))
					elif it is Dictionary and it.has("value") and it.has("desc"):
						x = eval_value(ctx, scope, it.value)
					else:
						x = eval_value(ctx, scope, it)
					if k == "subtract":
						x = -x
					v += x
					if parts != null and it is Dictionary and it.get("desc") != null and x != 0.0:
						parts.append({"label": game.text(it.desc), "value": x})
			"multiply":
				v *= eval_value(ctx, scope, arg)
			"divide":
				var d := eval_value(ctx, scope, arg)
				v = 0.0 if d == 0.0 else v / d
			"min":
				v = maxf(v, eval_value(ctx, scope, arg))
			"max":
				v = minf(v, eval_value(ctx, scope, arg))
			"round":
				if ScriptContext.is_yes(arg):
					v = roundf(v)
			"floor":
				if ScriptContext.is_yes(arg):
					v = floorf(v)
			"ceil":
				if ScriptContext.is_yes(arg):
					v = ceilf(v)
			"abs":
				if ScriptContext.is_yes(arg):
					v = absf(v)
			"if":
				for b in Data.as_array(arg):
					if not (b is Dictionary):
						continue
					if not eval_trigger(ctx, scope, b.get("limit")):
						continue
					var rest: Dictionary = b.duplicate()
					rest.erase("limit")
					rest.erase("desc")
					var before := v
					v = _apply_value_ops(ctx, scope, v, rest)
					if parts != null and b.get("desc") != null and v != before:
						parts.append({"label": game.text(b.desc), "value": v - before})
			"desc", "base_desc":
				pass
			_:
				game.script_error("Неизвестная операция значения \"%s\"" % k)
	return v


static func _eval_value_path(ctx: ScriptContext, scope: Variant, s: String) -> float:
	# Числа в строках («10», « -2.5») разбираем один раз.
	var num: Variant = _path_kind.get(s)
	if num is float:
		return num
	var trimmed := s.strip_edges()
	if trimmed == "":
		return 0.0
	if trimmed.is_valid_float():
		if _path_kind.size() < 20000:
			_path_kind[s] = float(trimmed)
		return float(trimmed)
	var game := ctx.game
	var reg := game.engine.scripting
	if reg.constants.has(trimmed):
		return float(reg.constants.get_item(trimmed))
	if trimmed.begins_with("scope:") and not trimmed.contains(".") and ctx.values.has(trimmed.substr(6)):
		return float(ctx.values[trimmed.substr(6)])
	if trimmed.begins_with("defines."):
		var cur: Variant = game.defines
		for p in trimmed.substr(8).split("."):
			cur = cur.get(p) if cur is Dictionary else null
		return float(cur) if (cur is int or cur is float) else 0.0
	if trimmed.begins_with("-"):
		return -_eval_value_path(ctx, scope, trimmed.substr(1))
	var segs := split_path(trimmed)
	var cur: Variant = scope
	for i in segs.size() - 1:
		cur = step_scope(ctx, cur, segs[i], i == 0)
		if cur == null:
			return 0.0
	var last = segs[segs.size() - 1]
	if last.begins_with("scope:") and ctx.values.has(last.substr(6)):
		return float(ctx.values[last.substr(6)])
	return get_named_value(ctx, cur, last)


static func get_named_value(ctx: ScriptContext, scope: Variant, name_with_arg: String) -> float:
	var game := ctx.game
	var parsed: Variant = _name_cache.get(name_with_arg)
	if parsed == null:
		var m := _re_name().search(name_with_arg)
		parsed = [m.get_string(1), m.get_string(2)] if m != null else []
		if _name_cache.size() > 20000:
			_name_cache.clear()
		_name_cache[name_with_arg] = parsed
	if parsed.is_empty():
		game.script_error("Некорректное имя значения \"%s\"" % name_with_arg)
		return 0.0
	var vname: String = parsed[0]
	var arg_path: String = parsed[1]
	if vname.begins_with("var:"):
		var holder: Variant = game.state.global_vars
		if scope != null and scope.type == "character" and game.ch(scope.id) != null:
			holder = game.ch(scope.id).vars
		elif scope != null and scope.type == "province" and game.state.provinces.has(scope.id):
			holder = game.state.provinces[scope.id].vars
		return Data.num(holder.get(vname.substr(4)))
	if vname.begins_with("global_var:"):
		return Data.num(game.state.global_vars.get(vname.substr(11)))
	var def: Variant = game.engine.scripting.values.get_item(vname)
	if def != null:
		if scope == null:
			return 0.0
		if def.has("scopes") and not def.scopes.has(scope.type):
			return 0.0
		var arg: Variant = resolve_scope(ctx, scope, arg_path) if arg_path != "" else null
		return float(def["get"].call(ctx, scope, arg))
	var sv: Variant = game.content.get_def("script_values", vname)
	if sv != null:
		if scope == null:
			return 0.0
		if not (sv is Dictionary):
			return eval_value(ctx, scope, sv)
		var expr: Dictionary = sv.duplicate()
		expr.erase("id")
		return eval_value(ctx, scope, expr)
	game.script_error("Неизвестное значение \"%s\"" % vname)
	return 0.0


static func has_named_value(ctx: ScriptContext, vname: String) -> bool:
	return ctx.game.engine.scripting.values.has(vname) or ctx.game.content.has("script_values", vname) or vname.begins_with("var:") or vname.begins_with("global_var:")


static func _strip_call(key: String) -> String:
	var i := key.find("(")
	return key.substr(0, i) if i >= 0 else key


## Сравнивает число с условием: 5 (≥5), ">= 3", "< scope:x.gold", { gte: 1, lt: 10 }, yes/no.
static func compare(ctx: ScriptContext, scope: Variant, actual: float, cond: Variant) -> bool:
	if cond is int or cond is float:
		return actual >= float(cond)
	if cond is bool or (cond is String and (cond == "yes" or cond == "no")):
		return (actual != 0.0) == ScriptContext.is_yes(cond)
	if cond is String or cond is StringName:
		var cs := str(cond)
		var parsed: Variant = _cmp_cache.get(cs)
		if parsed == null:
			var m := _re_cmp().search(cs)
			parsed = [m.get_string(1), m.get_string(2)] if m != null else []
			if _cmp_cache.size() > 20000:
				_cmp_cache.clear()
			_cmp_cache[cs] = parsed
		if parsed.is_empty():
			return actual >= eval_value(ctx, scope, cond)
		return _cmp_op(parsed[0], actual, eval_value(ctx, scope, parsed[1]))
	if cond is Dictionary:
		for op in cond:
			var norm: Variant = OP_ALIASES.get(op)
			if norm == null:
				continue
			if not _cmp_op(norm, actual, eval_value(ctx, scope, cond[op])):
				return false
		return true
	return false


static func _cmp_op(op: String, a: float, b: float) -> bool:
	match op:
		">=": return a >= b
		">": return a > b
		"<=": return a <= b
		"<": return a < b
		"=", "==": return absf(a - b) < 1e-9
		"!=": return absf(a - b) >= 1e-9
	return false


# ---------------------------------------------------------------- триггеры

static func eval_trigger(ctx: ScriptContext, scope: Variant, block: Variant) -> bool:
	if block == null:
		return true
	if block is bool:
		return block
	if block is String or block is StringName:
		if block == "yes" or block == "no":
			return block == "yes"
		var st: Variant = ctx.game.content.get_def("scripted_triggers", str(block))
		if st != null:
			return eval_trigger(ctx, scope, body_of(st, "trigger"))
		ctx.game.script_error("Неизвестный триггер \"%s\"" % block)
		return false
	if block is Array:
		for b in block:
			if not eval_trigger(ctx, scope, b):
				return false
		return true
	if not (block is Dictionary):
		return false
	if ctx.depth > MAX_DEPTH:
		ctx.game.script_error("Слишком глубокая рекурсия в триггере")
		return false
	for key in block:
		if not eval_trigger_key(ctx, scope, key, block[key]):
			return false
	return true


static func _or_block(ctx: ScriptContext, scope: Variant, arg: Variant) -> bool:
	if arg is Array:
		for b in arg:
			if eval_trigger(ctx, scope, b):
				return true
		return false
	if arg is Dictionary:
		for k in arg:
			if eval_trigger_key(ctx, scope, k, arg[k]):
				return true
		return false
	return eval_trigger(ctx, scope, arg)


static func _trigger_in(ctx: ScriptContext, from: Variant, sub: Variant, block: Variant) -> bool:
	var prev: Variant = ctx.prev
	ctx.prev = from
	ctx.depth += 1
	var r := eval_trigger(ctx, sub, block)
	ctx.prev = prev
	ctx.depth -= 1
	return r


static func _effect_in(ctx: ScriptContext, from: Variant, sub: Variant, block: Variant) -> void:
	var prev: Variant = ctx.prev
	ctx.prev = from
	ctx.depth += 1
	run_effect(ctx, sub, block)
	ctx.prev = prev
	ctx.depth -= 1


const _SPECIAL_TRIGGER_KEYS := {
	"AND": true, "and": true, "OR": true, "or": true, "NOT": true, "not": true, "NAND": true, "NOR": true, "nor": true,
	"always": true, "exists": true, "is": true, "this": true, "custom_tooltip": true, "custom_description": true,
	"desc": true, "text": true,
}


static func eval_trigger_key(ctx: ScriptContext, scope: Variant, key: String, arg: Variant) -> bool:
	if _SPECIAL_TRIGGER_KEYS.has(key):
		return _special_trigger(ctx, scope, key, arg)
	# Быстрый путь: зарегистрированный триггер (самый частый случай).
	var fast: Variant = ctx.game.engine.scripting.triggers._map.get(key)
	if fast != null and not key.begins_with("any_"):
		if fast.has("scopes") and (scope == null or not fast.scopes.has(scope.type)):
			return false
		return fast.eval.call(ctx, scope, arg)
	return _registered_trigger(ctx, scope, key, arg)


static func _special_trigger(ctx: ScriptContext, scope: Variant, key: String, arg: Variant) -> bool:
	var game := ctx.game
	match key:
		"AND", "and":
			return eval_trigger(ctx, scope, arg)
		"OR", "or":
			return _or_block(ctx, scope, arg)
		"NOT", "not", "NAND":
			return not eval_trigger(ctx, scope, arg)
		"NOR", "nor":
			return not _or_block(ctx, scope, arg)
		"always":
			return ScriptContext.is_yes(arg)
		"exists":
			if (arg is bool and arg) or (arg is String and arg == "yes"):
				return game.exists(scope)
			return resolve_scope(ctx, scope, arg) != null
		"is", "this":
			return ScriptContext.same_scope(scope, resolve_scope(ctx, scope, arg))
		"custom_tooltip", "custom_description":
			return eval_trigger(ctx, scope, arg.get("trigger")) if arg is Dictionary else true
		"desc", "text":
			return true
	return true


static func _registered_trigger(ctx: ScriptContext, scope: Variant, key: String, arg: Variant) -> bool:
	var game := ctx.game
	var reg := game.engine.scripting
	if key.begins_with("scope:") and not key.contains("."):
		var sname := key.substr(6)
		if ctx.values.has(sname):
			return compare(ctx, scope, float(ctx.values[sname]), arg)
		var sub: Variant = ctx.scopes.get(sname)
		if sub == null:
			return false
		return _trigger_in(ctx, scope, sub, arg)
	if key.begins_with("any_"):
		var lst: Variant = reg.lists.get_item(key.substr(4))
		if lst != null:
			return _eval_any(ctx, scope, lst.list.call(ctx, scope), arg)
	var trig: Variant = reg.triggers.get_item(key)
	if trig != null:
		if trig.has("scopes") and (scope == null or not trig.scopes.has(scope.type)):
			return false
		return trig.eval.call(ctx, scope, arg)
	var st: Variant = game.content.get_def("scripted_triggers", key)
	if st != null:
		var r := eval_trigger(ctx, scope, body_of(st, "trigger"))
		return r if (ScriptContext.is_yes(arg) or arg == null) else not r
	var link: Variant = reg.links.get_item(key)
	if link != null:
		if scope == null or (link.has("from") and not link.from.has(scope.type)):
			return false
		var sub: Variant = link.resolve.call(ctx, scope)
		if sub == null:
			return false
		return _trigger_in(ctx, scope, sub, arg)
	if has_named_value(ctx, _strip_call(key)):
		# Параметризованное значение: opinion: { target: scope:actor, value: ">= 10" }
		if arg is Dictionary and arg.has("target"):
			var t: Variant = resolve_scope(ctx, scope, arg.target)
			if t == null:
				return false
			var def: Variant = reg.values.get_item(key)
			var actual: float = float(def["get"].call(ctx, scope, t)) if def != null else 0.0
			return compare(ctx, scope, actual, arg.get("value", ">= 0"))
		return compare(ctx, scope, get_named_value(ctx, scope, key), arg)
	if key.contains(".") or is_scope_start(ctx, key):
		var segs := split_path(key)
		var last = segs[segs.size() - 1]
		if has_named_value(ctx, _strip_call(last)):
			return compare(ctx, scope, _eval_value_path(ctx, scope, key), arg)
		var sub: Variant = resolve_scope(ctx, scope, key)
		if sub == null:
			return false
		return _trigger_in(ctx, scope, sub, arg)
	game.script_error("Неизвестный триггер \"%s\"" % key)
	return false


static func _eval_any(ctx: ScriptContext, scope: Variant, items: Array, arg: Variant) -> bool:
	var cond: Variant = arg
	var count: Variant = ">= 1"
	var percent: Variant = null
	if arg is Dictionary:
		cond = arg.duplicate()
		cond.erase("count")
		cond.erase("percent")
		if arg.has("count"):
			count = arg["count"]
		percent = arg.get("percent")
	elif ScriptContext.is_yes(arg):
		cond = {}
	var n := 0
	for it in items:
		if _trigger_in(ctx, scope, it, cond):
			n += 1
	if count is String and count == "all":
		return n == items.size()
	if percent != null:
		return compare(ctx, scope, (float(n) / items.size()) if items.size() > 0 else 0.0, percent)
	return compare(ctx, scope, n, count)


# ---------------------------------------------------------------- эффекты

static func run_effect(ctx: ScriptContext, scope: Variant, block: Variant) -> void:
	if block == null:
		return
	if ctx.depth > MAX_DEPTH:
		ctx.game.script_error("Слишком глубокая рекурсия в эффекте")
		return
	var pairs := flatten_effects(block)
	var if_state := 0 # 0 — нет, 1 — сработал, 2 — не сработал
	for pair in pairs:
		var key: String = pair[0]
		var arg: Variant = pair[1]
		if key == "if":
			if_state = 1 if _run_if(ctx, scope, arg) else 2
			continue
		if key == "else_if":
			if if_state == 2:
				if_state = 1 if _run_if(ctx, scope, arg) else 2
			continue
		if key == "else":
			if if_state == 2:
				run_effect(ctx, scope, arg)
			if_state = 0
			continue
		if_state = 0
		run_effect_key(ctx, scope, key, arg)


## Блок эффектов → список пар [ключ, аргумент].
static func flatten_effects(block: Variant) -> Array:
	var out := []
	if block is Array:
		for b in block:
			out.append_array(flatten_effects(b))
	elif block is String or block is StringName:
		out.append([str(block), "yes"])
	elif block is Dictionary:
		for k in block:
			out.append([str(k), block[k]])
	return out


static func _without(d: Dictionary, keys: Array) -> Dictionary:
	var out := d.duplicate()
	for k in keys:
		out.erase(k)
	return out


static func _run_if(ctx: ScriptContext, scope: Variant, arg: Variant) -> bool:
	if not (arg is Dictionary):
		return false
	if eval_trigger(ctx, scope, arg.get("limit")):
		run_effect(ctx, scope, arg.get("then"))
		run_effect(ctx, scope, _without(arg, ["limit", "then", "else", "else_if"]))
		return true
	if arg.get("else_if") != null:
		for b in Data.as_array(arg.else_if):
			if _run_if(ctx, scope, b):
				return true
	if arg.has("else"):
		run_effect(ctx, scope, arg["else"])
		return true
	return false


## {limit, weight, order_by, max, effects}
static func _iterator_parts(arg: Variant) -> Dictionary:
	if not (arg is Dictionary):
		return {"effects": arg}
	var rest := _without(arg, ["limit", "weight", "order_by", "max", "position", "effect"])
	return {
		"limit": arg.get("limit"),
		"weight": arg.get("weight"),
		"order_by": arg.get("order_by"),
		"max": arg.get("max"),
		"effects": [arg["effect"], rest] if arg.has("effect") else rest,
	}


static func run_effect_key(ctx: ScriptContext, scope: Variant, key: String, arg: Variant) -> void:
	var game := ctx.game
	var reg := game.engine.scripting
	match key:
		"effect", "hidden_effect", "then":
			run_effect(ctx, scope, arg)
			return
		"custom_tooltip":
			if arg is Dictionary and arg.get("effect") != null:
				run_effect(ctx, scope, arg.effect)
			return
		"limit":
			return
		"random":
			var a: Dictionary = arg if arg is Dictionary else {"chance": 50}
			var rest := _without(a, ["chance"])
			if game.rng.next() * 100.0 < eval_value(ctx, scope, a.get("chance")):
				run_effect(ctx, scope, rest.get("effect", rest))
			return
		"random_list":
			var opts := random_list_options(ctx, scope, arg)
			var pick: Variant = game.rng.weighted(opts, func(o): return o.weight)
			if pick != null:
				run_effect(ctx, scope, pick.effect)
			return
		"save_scope_as":
			ctx.scopes[str(arg)] = scope
			return
		"save_scope_value_as":
			if arg is Dictionary:
				ctx.values[str(arg.get("name"))] = eval_value(ctx, scope, arg.get("value"))
			return
		"trigger_event":
			var spec: Dictionary = {"id": str(arg)} if not (arg is Dictionary) else arg
			game.events.trigger(str(spec.id), scope, ctx.scopes, GameDate.duration_days(spec))
			return
	if key.begins_with("scope:") and not key.contains("."):
		var sub: Variant = ctx.scopes.get(key.substr(6))
		if sub != null:
			_effect_in(ctx, scope, sub, arg)
		return
	for prefix in ["every_", "random_", "ordered_"]:
		if not key.begins_with(prefix):
			continue
		var lst: Variant = reg.lists.get_item(key.substr(prefix.length()))
		if lst == null:
			continue
		var parts := _iterator_parts(arg)
		var items: Array = lst.list.call(ctx, scope).filter(func(it): return _trigger_in(ctx, scope, it, parts.get("limit")))
		if prefix == "every_":
			for it in items:
				_effect_in(ctx, scope, it, parts.effects)
		elif prefix == "random_":
			var it: Variant
			if parts.get("weight") != null:
				it = game.rng.weighted(items, func(i): return eval_value(ctx, i, parts.weight))
			else:
				it = game.rng.pick(items)
			if it != null:
				_effect_in(ctx, scope, it, parts.effects)
		else:
			var ob: Variant = parts.get("order_by")
			var scored = items.map(func(it): return {"it": it, "v": eval_value(ctx, it, ob if ob != null else 0)})
			scored.sort_custom(func(a, b): return a.v > b.v)
			var n = int(eval_value(ctx, scope, parts.max)) if parts.get("max") != null else 1
			for i in mini(n, scored.size()):
				_effect_in(ctx, scope, scored[i].it, parts.effects)
		return
	var eff: Variant = reg.effects.get_item(key)
	if eff != null:
		if eff.has("scopes") and (scope == null or not eff.scopes.has(scope.type)):
			game.script_error("Эффект \"%s\" нельзя применить к скоупу типа %s" % [key, scope.type if scope != null else "null"])
			return
		eff.apply.call(ctx, scope, arg)
		return
	var se: Variant = game.content.get_def("scripted_effects", key)
	if se != null:
		if ScriptContext.is_yes(arg) or arg == null:
			run_effect(ctx, scope, body_of(se, "effect"))
		return
	if reg.links.has(key) or key.contains(".") or is_scope_start(ctx, key):
		var sub: Variant = resolve_scope(ctx, scope, key)
		if sub != null:
			_effect_in(ctx, scope, sub, arg)
		return
	game.script_error("Неизвестный эффект \"%s\"" % key)


## [{weight, effect}]
static func random_list_options(ctx: ScriptContext, scope: Variant, arg: Variant) -> Array:
	var out := []
	if arg is Array:
		for o in arg:
			if not (o is Dictionary) or not eval_trigger(ctx, scope, o.get("trigger")):
				continue
			out.append({
				"weight": eval_value(ctx, scope, o.get("weight", 1)),
				"effect": o["effect"] if o.has("effect") else _without(o, ["weight", "trigger", "effect"]),
			})
	elif arg is Dictionary:
		# Стиль CK3: { "50": {...}, "25": {...} }
		for w in arg:
			out.append({"weight": Data.num(w), "effect": arg[w]})
	return out


# ---------------------------------------------------------------- описания

## Человекочитаемое описание эффекта для подсказок: [{text, depth}].
## Ничего не меняет в мире и не трогает генератор случайных чисел;
## ветки if вычисляются по текущему состоянию.
static func describe_effect(ctx: ScriptContext, scope: Variant, block: Variant, depth: int = 0, out: Array = []) -> Array:
	if block == null or ctx.depth > MAX_DEPTH:
		return out
	var game := ctx.game
	var reg := game.engine.scripting
	var prev_describing := ctx.describing
	ctx.describing = true
	var if_state := 0
	for pair in flatten_effects(block):
		var key: String = pair[0]
		var arg: Variant = pair[1]
		if key == "if":
			if_state = 1 if _describe_if(ctx, scope, arg, depth, out) else 2
			continue
		if key == "else_if":
			if if_state == 2:
				if_state = 1 if _describe_if(ctx, scope, arg, depth, out) else 2
			continue
		if key == "else":
			if if_state == 2:
				describe_effect(ctx, scope, arg, depth, out)
			if_state = 0
			continue
		if_state = 0
		match key:
			"hidden_effect", "limit", "save_scope_as", "save_scope_value_as", "trigger_event":
				continue
			"effect", "then":
				describe_effect(ctx, scope, arg, depth, out)
				continue
			"custom_tooltip":
				out.append({"text": game.text(arg.get("text") if arg is Dictionary else arg, ctx), "depth": depth})
				continue
			"random":
				var a: Dictionary = arg if arg is Dictionary else {"chance": 50}
				var rest := _without(a, ["chance"])
				out.append({"text": game.loc.t("fx.random", {"chance": roundi(eval_value(ctx, scope, a.get("chance")))}), "depth": depth})
				describe_effect(ctx, scope, rest.get("effect", rest), depth + 1, out)
				continue
			"random_list":
				var opts := random_list_options(ctx, scope, arg)
				var total := 0.0
				for o in opts:
					total += o.weight
				if total == 0.0:
					total = 1.0
				out.append({"text": game.loc.t("fx.random_list"), "depth": depth})
				for o in opts:
					out.append({"text": game.loc.t("fx.random", {"chance": roundi(o.weight / total * 100.0)}), "depth": depth + 1})
					describe_effect(ctx, scope, o.effect, depth + 2, out)
				continue
		if key.begins_with("scope:") and not key.contains("."):
			var sub: Variant = ctx.scopes.get(key.substr(6))
			if sub != null:
				_describe_in_scope(ctx, scope, sub, arg, depth, out)
			continue
		var handled := false
		for prefix in ["every_", "random_", "ordered_"]:
			if not key.begins_with(prefix):
				continue
			var lname := key.substr(prefix.length())
			var lst: Variant = reg.lists.get_item(lname)
			if lst == null:
				continue
			var parts := _iterator_parts(arg)
			var items: Array = lst.list.call(ctx, scope).filter(func(it): return _trigger_in(ctx, scope, it, parts.get("limit")))
			handled = true
			if items.is_empty():
				break
			out.append({"text": game.loc.t("fx.iter." + prefix.trim_suffix("_"), {"list": game.loc.t_or("list." + lname, lname), "n": items.size()}), "depth": depth})
			var prev: Variant = ctx.prev
			ctx.prev = scope
			ctx.depth += 1
			describe_effect(ctx, items[0], parts.effects, depth + 1, out)
			ctx.prev = prev
			ctx.depth -= 1
			break
		if handled:
			continue
		var eff: Variant = reg.effects.get_item(key)
		if eff != null:
			var d: Variant = eff.describe.call(ctx, scope, arg) if eff.has("describe") else _default_describe(ctx, key, arg)
			if d != null:
				for t in Data.as_array(d):
					if t != null and str(t) != "":
						out.append({"text": str(t), "depth": depth})
			continue
		var se: Variant = game.content.get_def("scripted_effects", key)
		if se != null:
			if se is Dictionary and se.get("desc") != null:
				out.append({"text": game.text(se.desc, ctx), "depth": depth})
			else:
				describe_effect(ctx, scope, body_of(se, "effect"), depth, out)
			continue
		var sub2: Variant = resolve_scope(ctx, scope, key)
		if sub2 != null:
			_describe_in_scope(ctx, scope, sub2, arg, depth, out)
	ctx.describing = prev_describing
	return out


static func _describe_if(ctx: ScriptContext, scope: Variant, arg: Variant, depth: int, out: Array) -> bool:
	if not (arg is Dictionary):
		return false
	if eval_trigger(ctx, scope, arg.get("limit")):
		describe_effect(ctx, scope, arg.get("then"), depth, out)
		describe_effect(ctx, scope, _without(arg, ["limit", "then", "else", "else_if"]), depth, out)
		return true
	if arg.get("else_if") != null:
		for b in Data.as_array(arg.else_if):
			if _describe_if(ctx, scope, b, depth, out):
				return true
	if arg.has("else"):
		describe_effect(ctx, scope, arg["else"], depth, out)
		return true
	return false


static func _describe_in_scope(ctx: ScriptContext, from: Variant, sub: Variant, arg: Variant, depth: int, out: Array) -> void:
	if ScriptContext.same_scope(sub, from):
		describe_effect(ctx, sub, arg, depth, out)
		return
	var inner := []
	var prev: Variant = ctx.prev
	ctx.prev = from
	ctx.depth += 1
	describe_effect(ctx, sub, arg, depth + 1, inner)
	ctx.prev = prev
	ctx.depth -= 1
	if inner.is_empty():
		return
	out.append({"text": ctx.game.scope_name(sub) + ":", "depth": depth})
	out.append_array(inner)


static func _default_describe(ctx: ScriptContext, key: String, arg: Variant) -> Variant:
	var k := "fx." + key
	if not ctx.game.loc.has(k):
		return null
	return ctx.game.loc.t(k, {"value": "" if (arg is Dictionary or arg is Array) else _arg_text(arg)})


static func _arg_text(arg: Variant) -> String:
	if arg is float and arg == floorf(arg):
		return str(int(arg))
	if arg is bool:
		return "true" if arg else "false"
	return str(arg)


## Описания невыполненных условий верхнего уровня (для подсказок).
static func failed_triggers(ctx: ScriptContext, scope: Variant, block: Variant) -> Array:
	var out := []
	if block == null:
		return out
	var pairs := []
	if block is Array:
		for b in block:
			if b is Dictionary:
				for k in b:
					pairs.append([k, b[k]])
	elif block is Dictionary:
		for k in block:
			pairs.append([k, block[k]])
	var game := ctx.game
	for pair in pairs:
		var key: String = pair[0]
		var arg: Variant = pair[1]
		if key == "custom_tooltip" or key == "custom_description":
			if arg is Dictionary and not eval_trigger(ctx, scope, arg.get("trigger")):
				out.append(game.text(arg.get("text"), ctx))
			continue
		if eval_trigger_key(ctx, scope, key, arg):
			continue
		var trig: Variant = game.engine.scripting.triggers.get_item(key)
		var d: Variant = trig.describe.call(ctx, scope, arg) if (trig != null and trig.has("describe")) else null
		if d != null and str(d) != "":
			out.append(str(d))
		else:
			var lk := "tr." + key
			if game.loc.has(lk):
				out.append(game.loc.t(lk, {"value": "" if (arg is Dictionary or arg is Array) else _arg_text(arg)}))
			else:
				out.append("%s: %s" % [key, JSON.stringify(arg) if (arg is Dictionary or arg is Array) else _arg_text(arg)])
	return out

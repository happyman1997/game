class_name Checks
extends RefCounted
## Проверка: шанс удачи складывается из основы и факторов — навыков, перков,
## вещей, черт, советников, — а исход один из трёх: удача, частичный успех
## или провал. Разбор шанса виден в подсказке до того, как решаешься, а
## игроку — и в сообщении об исходе. Так «браться может каждый, а выходит
## по-разному»: неумелого ждёт провал, а не просто меньшая цифра.
##
## Эффект check (в решениях, взаимодействиях, событиях):
##   check:
##     id: <проверка>          — основа и факторы из checks.<id> (необязательно;
##                               своё поле в эффекте важнее)
##     name: <ключ или текст>   — как назвать проверку в сообщении
##     skill: learning          — главный навык (удачи и неудачи — механика momentum)
##     base: 20                 — основа, %
##     add: [ { desc, limit, value } ]   — факторы, как в ai_accept
##     partial_band: 15         — ширина полосы частичного успеха, % (по
##                               умолчанию defines.checks.partial_band)
##     min: 5, max: 95          — пределы шанса удачи (defines.checks.min/max)
##     success: { ... }  partial: { ... }  failure: { ... }   — исходы
## Без блока partial полосы нет — только удача и провал. Стресс мешает:
## каждая полная сотня — минус defines.checks.stress_penalty.
## Значение check_chance(<id>) — шанс удачи по проверке checks.<id> (для ИИ).
## Хук check — {character, id, skill, chance, result: success|partial|failure}.


## Полное описание проверки: checks.<id>, поверх — поля из эффекта.
static func spec(game: Game, arg: Variant) -> Dictionary:
	if not (arg is Dictionary):
		var named: Variant = game.content.get_def("checks", str(arg))
		return named if named is Dictionary else {}
	if arg.get("id") == null:
		return arg
	var base: Variant = game.content.get_def("checks", str(arg.id))
	var out: Dictionary = base.duplicate() if base is Dictionary else {}
	for k in arg:
		out[k] = arg[k]
	return out


## Шансы исходов в процентах: {success, partial, failure, parts}; parts —
## разбор шанса удачи [{label, value}].
static func odds(ctx: ScriptContext, scope: Variant, sp: Dictionary) -> Dictionary:
	var game := ctx.game
	var parts := []
	var v := Interp.eval_value(ctx, scope, {"value": sp.get("base", 0), "base_desc": "check.base", "add": sp.get("add", [])}, parts)
	var c: Variant = game.ch(scope.id) if scope is Dictionary and scope.get("type") == "character" else null
	if c != null:
		var pen := floorf(float(c.stress) / 100.0) * game.def_num("checks.stress_penalty", 10)
		if pen > 0.0:
			v -= pen
			parts.append({"label": game.loc.t("check.stress"), "value": -pen})
	var lo := Data.num(sp.get("min"), game.def_num("checks.min", 5))
	var hi := Data.num(sp.get("max"), game.def_num("checks.max", 95))
	var s := clampf(roundf(v), lo, hi)
	var band := 0.0
	if sp.get("partial") != null:
		band = minf(100.0 - s, Data.num(sp.get("partial_band"), game.def_num("checks.partial_band", 15)))
	return {"success": s, "partial": band, "failure": 100.0 - s - band, "parts": parts}


## Бросок: удача, частичный успех или провал — и его исход.
static func run(ctx: ScriptContext, scope: Variant, arg: Variant) -> String:
	var game := ctx.game
	var sp := spec(game, arg)
	var o := odds(ctx, scope, sp)
	var r := game.rng.next() * 100.0
	var result := "failure"
	if r < o.success:
		result = "success"
	elif r < o.success + o.partial:
		result = "partial"
	ctx.values["check_result"] = {"success": 2.0, "partial": 1.0, "failure": 0.0}[result]
	Interp.run_effect(ctx, scope, sp.get(result))
	var cid: Variant = scope.get("id") if scope is Dictionary else null
	game.emit("check", {"character": cid, "id": str(sp.get("id", "")), "skill": str(sp.get("skill", "")), "chance": o.success, "result": result})
	# весть — тому, кто проверялся, или игроку, по чьей воле (событие о его человеке)
	var rid: Variant = ctx.root.get("id") if ctx.root is Dictionary and ctx.root.get("type") == "character" else null
	if (cid != null and game.is_player(str(cid))) or (rid != null and game.is_player(str(rid))):
		var what := game.text(sp.get("name"), ctx) if sp.get("name") != null else game.loc.t("check.generic")
		game.message(game.loc.t("msg.roll_" + result, {"what": what, "chance": roundi(o.success)}),
			{"success": "good", "partial": "info", "failure": "bad"}[result], scope)
	return result


## Описание для подсказки: шансы, разбор, что будет при каждом исходе.
static func describe(ctx: ScriptContext, scope: Variant, arg: Variant, depth: int, out: Array) -> void:
	var game := ctx.game
	var sp := spec(game, arg)
	var o := odds(ctx, scope, sp)
	var head := game.loc.t("fx.check_odds", {"chance": roundi(o.success)}) if o.partial <= 0.0 \
		else game.loc.t("fx.check_odds_partial", {"chance": roundi(o.success), "partial": roundi(o.partial)})
	out.append({"text": head, "depth": depth})
	for p in o.parts:
		out.append({"text": "%s %s" % [p.label, ("+%d" % roundi(p.value)) if p.value > 0 else str(roundi(p.value))], "depth": depth + 1})
	for k in ["success", "partial", "failure"]:
		if sp.get(k) == null:
			continue
		out.append({"text": game.loc.t("fx.check_" + k), "depth": depth})
		Interp.describe_effect(ctx, scope, sp.get(k), depth + 1, out)

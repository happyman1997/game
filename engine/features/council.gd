class_name Council
extends EngineFeature
## Совет правителя: должности (канцлер, казначей, маршал, тайный советник,
## духовник), у каждой — набор задач. Задача даёт сюзерену модификаторы,
## зависящие от навыка советника, и может каждый месяц с некоторым шансом
## запускать эффект (например, развить провинцию или раскрыть заговор).
##
## Данные:
##   council_positions: { skill, icon, order, is_shown, candidate }
##   council_tasks:     { position, icon, default, liege_modifiers, monthly_chance, monthly_effect, ai_will_do }
##   defines.council:   { councillor_opinion, ai_replace_skill_gap, dismiss_opinion_modifier }
## Скоупы задач: root = scope:councillor, scope:liege.
## Состояние: liege.council = { должность: {holder, task, since} }.

const OWNER := "core/council"


func _init() -> void:
	id = "council"
	doc = "Совет: должности, задачи и их эффекты"


static func positions(game: Game) -> Array:
	return game.engine.sorted_content("council_positions")


static func tasks_of(game: Game, position: String) -> Array:
	return game.engine.content_where("council_tasks", "position", position)


static func default_task(game: Game, position: String) -> Variant:
	var tasks := tasks_of(game, position)
	for t in tasks:
		if t.get("default", false):
			return t.id
	return tasks[0].id if not tasks.is_empty() else null


static func is_position_shown(game: Game, liege: Dictionary, pos: Dictionary) -> bool:
	if liege.titles.is_empty():
		return false
	var ctx := ScriptContext.make(game, {"type": "character", "id": liege.id}, {"liege": {"type": "character", "id": liege.id}})
	return Interp.eval_trigger(ctx, ctx.root, pos.get("is_shown"))


static func seat_of(liege: Dictionary, pos: String) -> Variant:
	return liege.council.get(pos) if liege.get("council") != null else null


## Должность персонажа в совете сюзерена: {liege, position} или null.
static func position_of(game: Game, c: Dictionary) -> Variant:
	var l: Variant = game.ch(c.liege)
	if l != null and l.get("council") != null:
		for pos in l.council:
			if l.council[pos].get("holder") == c.id:
				return {"liege": l, "position": pos}
	# супруг правителя может заседать и не будучи его придворным
	for s in c.spouses:
		var sp: Variant = game.ch(s)
		if sp != null and sp.get("council") != null:
			for pos in sp.council:
				if sp.council[pos].get("holder") == c.id:
					return {"liege": sp, "position": pos}
	return null


## Может ли персонаж занять должность в совете сюзерена.
static func can_hold_seat(game: Game, liege: Dictionary, cand: Dictionary, pos_id: String) -> bool:
	var pos: Variant = game.content.get_def("council_positions", pos_id)
	if pos == null or not Chars.is_alive(cand) or cand.id == liege.id or cand.get("prison") != null or not Chars.is_adult(game, cand):
		return false
	if not (cand.liege == liege.id or liege.spouses.has(cand.id)):
		return false
	if liege.get("council") != null:
		for p in liege.council:
			if p != pos_id and liege.council[p].get("holder") == cand.id:
				return false
	var ctx := ScriptContext.make(game, {"type": "character", "id": cand.id}, {"liege": {"type": "character", "id": liege.id}, "councillor": {"type": "character", "id": cand.id}})
	return Interp.eval_trigger(ctx, ctx.root, pos.get("candidate"))


static func candidates(game: Game, liege: Dictionary, pos_id: String) -> Array:
	var pos: Variant = game.content.get_def("council_positions", pos_id)
	if pos == null:
		return []
	var pool := {}
	for c in game.courtiers_of(liege.id) + game.vassals_of(liege.id):
		pool[c.id] = c
	for s in liege.spouses:
		var sp: Variant = game.ch(s)
		if sp != null:
			pool[sp.id] = sp
	var out := pool.values().filter(func(c): return can_hold_seat(game, liege, c, pos_id))
	var sk: String = str(pos.get("skill"))
	Data.sort_by(out, func(c): return Stats.skill(game, c, sk), true)
	return out


static func appoint(game: Game, liege: Dictionary, pos_id: String, cand_id: String) -> bool:
	var cand: Variant = game.ch(cand_id)
	if cand == null or not can_hold_seat(game, liege, cand, pos_id):
		return false
	if liege.get("council") == null:
		liege["council"] = {}
	var prev: Variant = liege.council.get(pos_id)
	if prev != null and prev.get("holder") == cand_id:
		return false
	if prev != null and prev.get("holder") != null:
		dismiss(game, liege, pos_id, true)
	var task: Variant = prev.get("task") if prev != null else null
	liege.council[pos_id] = {"holder": cand_id, "task": task if task != null else default_task(game, pos_id), "since": game.date}
	_invalidate(game, liege)
	game.emit("council.appointed", {"liege": liege, "position": pos_id, "councillor": cand})
	return true


## Снять советника.
static func dismiss(game: Game, liege: Dictionary, pos_id: String, replaced: bool = false) -> void:
	var seat: Variant = seat_of(liege, pos_id)
	if seat == null or seat.get("holder") == null:
		return
	var c: Variant = game.ch(seat.holder)
	seat.holder = null
	seat.since = null
	var mod: String = str(game.def_val("council.dismiss_opinion_modifier", "dismissed_from_council"))
	if c != null and Chars.is_alive(c) and game.content.has("opinion_modifiers", mod):
		Opinion.add_opinion(game, c, liege, mod)
	_invalidate(game, liege)
	game.emit("council.dismissed", {"liege": liege, "position": pos_id, "councillor": c, "replaced": replaced})


static func set_task(game: Game, liege: Dictionary, pos_id: String, task: String) -> bool:
	var t: Variant = game.content.get_def("council_tasks", task)
	if t == null or t.get("position") != pos_id:
		return false
	if liege.get("council") == null:
		liege["council"] = {}
	if not liege.council.has(pos_id):
		liege.council[pos_id] = {"holder": null, "task": null, "since": null}
	liege.council[pos_id].task = task
	_invalidate(game, liege)
	return true


static func _invalidate(game: Game, liege: Dictionary) -> void:
	game.month_cache.erase("council:" + liege.id)
	game.stat_cache.erase(liege.id)
	for k in game.stat_cache.keys():
		if k.begins_with("op:"):
			game.stat_cache.erase(k)


static func _seat_context(game: Game, liege: Dictionary, holder: String) -> ScriptContext:
	return ScriptContext.make(game, {"type": "character", "id": holder}, {"liege": {"type": "character", "id": liege.id}, "councillor": {"type": "character", "id": holder}})


## Модификаторы, которые совет даёт сюзерену (по должностям): [{label, modifiers}].
static func council_modifiers(game: Game, liege: Dictionary) -> Array:
	var out := []
	if liege.get("council") == null:
		return out
	for pos_id in liege.council:
		var seat: Dictionary = liege.council[pos_id]
		if seat.get("holder") == null or seat.get("task") == null or not game.is_alive(seat.holder):
			continue
		var t: Variant = game.content.get_def("council_tasks", seat.task)
		if t == null or t.get("liege_modifiers") == null:
			continue
		var ctx := _seat_context(game, liege, seat.holder)
		out.append({"label": "%s: %s" % [game.name_of("council_positions", pos_id), game.name_of("council_tasks", t.id)], "modifiers": EngineFeature.eval_modifiers(ctx, ctx.root, t.liege_modifiers)})
	return out


## Шанс (в %) ежемесячного эффекта задачи.
static func task_monthly_chance(game: Game, liege: Dictionary, pos_id: String) -> float:
	var seat: Variant = seat_of(liege, pos_id)
	if seat == null or seat.get("holder") == null or seat.get("task") == null:
		return 0.0
	var t: Variant = game.content.get_def("council_tasks", seat.task)
	if t == null or t.get("monthly_effect") == null:
		return 0.0
	var ctx := _seat_context(game, liege, seat.holder)
	return clampf(Interp.eval_value(ctx, ctx.root, t.get("monthly_chance", 100)), 0.0, 100.0)


static func _ai_pick_task(game: Game, liege: Dictionary, pos_id: String) -> Variant:
	var best: Variant = null
	var bv := -INF
	var ctx := ScriptContext.make(game, {"type": "character", "id": liege.id}, {"liege": {"type": "character", "id": liege.id}})
	for t in tasks_of(game, pos_id):
		var v: float = Interp.eval_value(ctx, ctx.root, t.ai_will_do) if t.get("ai_will_do") != null else (10.0 if t.get("default", false) else 5.0)
		if best == null or v > bv:
			best = t.id
			bv = v
	return best


## ИИ (и первичное заполнение для всех) — занять пустые места лучшими кандидатами.
static func fill(game: Game, liege: Dictionary, replace: bool = false) -> void:
	var gap := game.def_num("council.ai_replace_skill_gap", 4)
	for pos in positions(game):
		if not is_position_shown(game, liege, pos):
			continue
		var seat: Variant = seat_of(liege, pos.id)
		var cur: Variant = game.ch(seat.get("holder")) if seat != null else null
		if cur != null and not replace:
			continue
		var best: Variant = null
		for c in candidates(game, liege, pos.id):
			if cur == null or c.id != cur.id:
				best = c
				break
		if best == null:
			continue
		var sk: String = str(pos.get("skill"))
		if cur != null and Stats.skill(game, best, sk) < Stats.skill(game, cur, sk) + gap:
			continue
		appoint(game, liege, pos.id, best.id)


static func monthly(game: Game) -> void:
	var month: int = GameDate.parts(game.date).m
	for liege in game.rulers().duplicate():
		if liege.death != null:
			continue
		# проверка мест
		if liege.get("council") != null:
			for pos_id in liege.council:
				var seat: Dictionary = liege.council[pos_id]
				if seat.get("holder") == null:
					continue
				var c: Variant = game.ch(seat.holder)
				if c == null or not can_hold_seat(game, liege, c, pos_id):
					seat.holder = null
					seat.since = null
					_invalidate(game, liege)
		var is_player := game.is_player(liege.id)
		if not liege.flags.has("council_init"):
			liege.flags["council_init"] = 0
			fill(game, liege)
		elif not is_player and liege.get("prison") == null:
			fill(game, liege, month == 1)
			for pos in positions(game):
				var seat: Variant = seat_of(liege, pos.id)
				if seat != null and seat.get("holder") != null and game.rng.chance(0.1):
					var t: Variant = _ai_pick_task(game, liege, pos.id)
					if t != null and t != seat.get("task"):
						set_task(game, liege, pos.id, t)
		# ежемесячные эффекты задач и «пульс» советников для событий
		if liege.get("council") == null:
			continue
		for pos_id in liege.council.keys():
			var seat: Dictionary = liege.council[pos_id]
			if seat.get("holder") == null:
				continue
			game.on_action("on_councillor_pulse", {"type": "character", "id": seat.holder}, {"liege": {"type": "character", "id": liege.id}})
			if seat.get("task") == null or seat.get("holder") == null:
				continue
			var t: Variant = game.content.get_def("council_tasks", seat.task)
			if t == null or t.get("monthly_effect") == null:
				continue
			if game.rng.next() * 100.0 >= task_monthly_chance(game, liege, pos_id):
				continue
			var ctx := _seat_context(game, liege, seat.holder)
			Interp.run_effect(ctx, ctx.root, t.monthly_effect)
			game.emit("council.task_fired", {"liege": liege, "position": pos_id, "task": t.id})


## Раскрыть случайную нераскрытую враждебную интригу против персонажа или его близких.
static func discover_scheme_against(game: Game, c: Dictionary) -> bool:
	var protected_ids := {c.id: true}
	for x in c.spouses + c.children:
		protected_ids[x] = true
	var hidden = game.state.schemes.values().filter(func(s):
		var d: Variant = game.content.get_def("schemes", s.type)
		return not s.discovered and protected_ids.has(s.target) and d != null and d.get("category") == "hostile")
	var s: Variant = game.rng.pick(hidden)
	if s == null:
		return false
	s.discovered = true
	var def: Variant = game.content.get_def("schemes", s.type)
	var ctx := Schemes.scheme_context(game, s)
	Interp.run_effect(ctx, ctx.root, def.get("on_discovered") if def != null else null)
	game.emit("scheme.discovered", {"scheme": s})
	return true


func install(engine: GameEngine) -> void:
	engine.systems.register("council", {"id": "council", "order": 15, "on_month": Council.monthly}, OWNER)
	engine.modifier_providers.register("council", {"fn": func(game: Game, c: Dictionary) -> Variant:
		if c.get("council") == null:
			return null
		return game.cached_monthly("council:" + c.id, func(): return Council.council_modifiers(game, c))
	}, OWNER)
	engine.opinion_providers.register("council", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		if b.get("council") == null:
			return null
		for pos in b.council:
			if b.council[pos].get("holder") == a.id:
				var v := game.def_num("council.councillor_opinion", 10)
				return {"label": game.loc.t("opinion.on_council"), "value": v} if v != 0.0 else null
		return null
	}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	r.triggers.register("is_councillor", {"scopes": CH, "doc": "Заседает в совете (yes) или на должности: is_councillor: marshal",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var pos: Variant = Council.position_of(ctx.game, c) if c != null else null
			if (arg is String and arg == "no") or (arg is bool and not arg):
				return pos == null
			return pos != null and (arg == null or ScriptContext.is_yes(arg) or pos.position == arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_councillor.not" if ((arg is String and arg == "no") or (arg is bool and not arg)) else "tr.is_councillor"),
	}, OWNER)
	r.triggers.register("has_council_task", {"scopes": CH, "doc": "Сюзерен: на какой-то должности выбрана задача",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c == null or c.get("council") == null:
				return false
			for pos in c.council:
				if c.council[pos].get("holder") != null and c.council[pos].get("task") == arg:
					return true
			return false,
	}, OWNER)
	r.values.register("council_size", {"scopes": CH, "doc": "Число занятых мест в совете", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		if c == null or c.get("council") == null:
			return 0.0
		return float(Data.count(c.council.values(), func(x): return x.get("holder") != null and ctx.game.is_alive(x.holder)))
	}, OWNER)
	for pos in engine.content.all("council_positions"):
		var pid: String = pos.id
		r.links.register(pid, {"from": CH, "doc": "Советник на должности " + pid, "resolve": func(ctx, s):
			var c: Variant = ch.call(ctx, s)
			if c == null or c.get("council") == null or not c.council.has(pid):
				return null
			var h: Variant = c.council[pid].get("holder")
			return {"type": "character", "id": h} if (h != null and ctx.game.is_alive(h)) else null
		}, OWNER)
	r.lists.register("councillor", {"from": CH, "doc": "Члены совета", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		if c == null or c.get("council") == null:
			return []
		var out := []
		for x in c.council.values():
			if x.get("holder") != null and ctx.game.is_alive(x.holder):
				out.append({"type": "character", "id": x.holder})
		return out
	}, OWNER)
	r.lists.register("neighboring_county", {"from": CH, "doc": "Чужие графства, граничащие с державой", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		if c == null:
			return []
		var g: Game = ctx.game
		var mine := {}
		for x in Titles.realm_counties(g, c):
			mine[x] = true
		var out := {}
		for p in mine:
			for n in g.engine.neighbors(p):
				if not mine.has(n) and g.state.titles.has(n) and g.state.titles[n].holder != null:
					out[n] = true
		return out.keys().map(func(x): return {"type": "title", "id": x})
	}, OWNER)
	r.effects.register("discover_scheme_against", {"scopes": CH, "doc": "Раскрыть случайную враждебную интригу против персонажа или его семьи",
		"apply": func(ctx, s, _arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				Council.discover_scheme_against(ctx.game, c),
		"describe": func(ctx, _s, _arg): return ctx.game.loc.t("fx.discover_scheme_against"),
	}, OWNER)
	r.effects.register("appoint_councillor", {"scopes": CH, "doc": "Назначить в совет: { position, who }",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var who: Variant = ch.call(ctx, Interp.resolve_scope(ctx, s, arg.get("who"))) if arg is Dictionary else null
			if c != null and who != null:
				Council.appoint(ctx.game, c, str(arg.get("position")), who.id),
	}, OWNER)

	engine.content_validators.register("council", func(e: GameEngine, v: ScriptValidator):
		for p in e.content.all("council_positions"):
			if not e.content.has("skills", p.get("skill")):
				v.issue("council_positions/%s: нет навыка \"%s\"" % [p.id, p.get("skill")])
			v.trigger(p.get("is_shown"), "council_positions/%s is_shown" % p.id)
			v.trigger(p.get("candidate"), "council_positions/%s candidate" % p.id)
		for t in e.content.all("council_tasks"):
			v.ref("council_positions", t.get("position"), "council_tasks/" + t.id)
			v.effect(t.get("monthly_effect"), "council_tasks/%s monthly_effect" % t.id)
	, OWNER)

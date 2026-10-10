class_name Spirit
extends EngineFeature
## Состояние духа. Стресс — не просто минус: от него зависит, каким человек
## становится. Долгое спокойствие — «Безмятежность» (учится легче, но
## беспечен), средний стресс — «порыв» по характеру (гневливый впадает в
## ярость, параноик не спит, честолюбец одержим: сильные стороны и слабые),
## от сотни — надлом (штраф навыкам и срывы — как раньше).
##
##   spirit_states: { <id>: { icon, order, stress: [мин, макс], months,
##                            traits: [...], modifiers } }
##     stress — в каких пределах стресса состояние возможно; months — сколько
##     месяцев подряд нужно продержаться в них (безмятежность); traits — для
##     кого (хотя бы одна черта; без поля — для всех). Берётся первое
##     подходящее по order.
##   defines.spirit: { calm_max, recover_below, hardened_trait, shattered_trait,
##                     pulse_min_stress, pulse_chance_player, pulse_chance_ai,
##                     pulse_calm_mult }
## Закалка: кто пережил надлом (стресс от 100) и пришёл в себя (ниже
## recover_below), получает hardened_trait; надлом закалённого — shattered_trait.
## Раз в месяц правитель со стрессом от pulse_min_stress (или безмятежный)
## может попасть в событие on_action on_spirit_pulse.
## Состояние: c.vars.spirit = id, c.vars.calm = месяцы спокойствия,
## c.vars.broke = был надлом.

const OWNER := "core/spirit"


func _init() -> void:
	id = "spirit"
	doc = "Состояние духа: безмятежность, порывы по характеру, надлом и закалка"


## Заранее разобранные данные: {states: [[id, мин, макс, месяцев, черты]], числа defines}.
static func _plan(game: Game) -> Dictionary:
	var hit: Variant = game.engine.cache.get("spirit:plan")
	if hit != null:
		return hit
	var defs: Array = game.content.all("spirit_states").duplicate()
	Data.sort_by(defs, func(d): return Data.num(d.get("order"), 99))
	var states := []
	for d in defs:
		var r: Array = Data.as_array(d.get("stress"))
		states.append([str(d.id), Data.num(r[0]) if r.size() >= 2 else -INF, Data.num(r[1]) if r.size() >= 2 else INF,
			int(Data.num(d.get("months"))), Data.as_array(d.get("traits"))])
	hit = {
		"states": states,
		"adult_days": roundi(game.def_num("character.adult_age", 16) * GameDate.DAYS_PER_YEAR),
		"calm_max": game.def_num("spirit.calm_max", 10),
		"recover_below": game.def_num("spirit.recover_below", 50),
		"hardened": str(game.def_val("spirit.hardened_trait", "hardened")),
		"shattered": str(game.def_val("spirit.shattered_trait", "shattered")),
		"pulse_min": game.def_num("spirit.pulse_min_stress", 30),
		"pulse_player": game.def_num("spirit.pulse_chance_player", 0.12),
		"pulse_ai": game.def_num("spirit.pulse_chance_ai", 0.03),
		"pulse_calm": game.def_num("spirit.pulse_calm_mult", 0.25),
	}
	game.engine.cache["spirit:plan"] = hit
	return hit


static func state_of(c: Variant) -> Variant:
	return c.vars.get("spirit") if c is Dictionary else null


## Подходящее состояние при стрессе s и спокойствии calm месяцев.
static func _pick(plan: Dictionary, c: Dictionary, s: float, calm: int) -> Variant:
	for st in plan.states:
		if s < st[1] or s > st[2] or calm < st[3]:
			continue
		var tr: Array = st[4]
		if not tr.is_empty():
			var ok := false
			for t in tr:
				if c.traits.has(t):
					ok = true
					break
			if not ok:
				continue
		return st[0]
	return null


static func monthly_char(game: Game, c: Dictionary) -> void:
	var plan := _plan(game)
	if c.death != null or game.date - int(c.birth) < int(plan.adult_days):
		return
	var s := float(c.stress)
	var calm := int(c.vars.get("calm", 0))
	if s <= plan.calm_max:
		calm = mini(calm + 1, 999)
		c.vars["calm"] = calm
	elif calm > 0:
		calm = 0
		c.vars.erase("calm")
	# закалка: надлом и выход из него
	if s >= 100.0:
		if not c.vars.has("broke"):
			c.vars["broke"] = true
			if c.traits.has(plan.hardened):
				Chars.remove_trait(game, c, plan.hardened)
				_give(game, c, plan.shattered, "msg.spirit_shattered")
	elif s < plan.recover_below and c.vars.has("broke"):
		c.vars.erase("broke")
		if not c.traits.has(plan.hardened) and not c.traits.has(plan.shattered):
			_give(game, c, plan.hardened, "msg.spirit_hardened")
	var nxt: Variant = _pick(plan, c, s, calm)
	var cur: Variant = state_of(c)
	if nxt != cur:
		if nxt == null:
			c.vars.erase("spirit")
		else:
			c.vars["spirit"] = nxt
		game.stat_cache.erase(c.id)
		if nxt != null and game.is_player(c.id):
			game.message(game.loc.t("msg.spirit_state", {"name": game.name_of("spirit_states", str(nxt))}), "event", {"type": "character", "id": c.id})
		game.emit("spirit.changed", {"character": c, "state": nxt, "previous": cur})
	# события духа: правитель в порыве, надломе или безмятежности
	if c.titles.is_empty() or c.get("prison") != null:
		return
	if s < plan.pulse_min and nxt == null:
		return
	var ch: float = plan.pulse_player if game.is_player(c.id) else plan.pulse_ai
	if s < plan.pulse_min:
		ch *= plan.pulse_calm
	if game.rng.chance(ch):
		game.on_action("on_spirit_pulse", {"type": "character", "id": c.id})


static func _give(game: Game, c: Dictionary, t: String, msg: String) -> void:
	if not game.content.has("traits", t) or not Chars.add_trait(game, c, t):
		return
	if game.is_player(c.id):
		game.message(game.loc.t(msg), "good" if msg == "msg.spirit_hardened" else "bad", {"type": "character", "id": c.id})
	game.emit("spirit." + ("hardened" if msg == "msg.spirit_hardened" else "shattered"), {"character": c})


func install(engine: GameEngine) -> void:
	engine.systems.register("spirit", {"id": "spirit", "order": 12, "on_character_month": Spirit.monthly_char}, OWNER)
	engine.modifier_providers.register("spirit", {"fn": func(game: Game, c: Dictionary) -> Variant:
		var sid: Variant = c.vars.get("spirit")
		if sid == null:
			return null
		var d: Variant = game.content.get_def("spirit_states", sid)
		if d == null or not (d.get("modifiers") is Dictionary):
			return null
		var sname: String = sid
		return [{"label": func(): return game.name_of("spirit_states", sname), "modifiers": d.modifiers}]
	}, OWNER)
	engine.content_validators.register("spirit", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("spirit_states"):
			for t in Data.as_array(d.get("traits")):
				v.ref("traits", t, "spirit_states/" + d.id)
			var r: Variant = d.get("stress")
			if r != null and (not (r is Array) or r.size() != 2):
				v.issue("spirit_states/%s: stress — [мин, макс]" % d.id)
		for k in ["hardened_trait", "shattered_trait"]:
			var t: Variant = e.content.singleton("defines").get("spirit", {}).get(k)
			if t != null:
				v.ref("traits", t, "defines.spirit." + k)
	)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	r.triggers.register("spirit_state", {"scopes": CH, "doc": "Состояние духа (id из spirit_states, список или yes/no)", "eval": func(ctx, s, arg):
		var st: Variant = Spirit.state_of(ctx.game.ch(s.id))
		if arg is bool or (arg is String and (arg == "yes" or arg == "no")):
			return (st != null) == ScriptContext.is_yes(arg)
		return st != null and Data.as_array(arg).has(st),
		"describe": func(ctx, _s, arg):
			if arg is bool or (arg is String and (arg == "yes" or arg == "no")):
				return null
			return ctx.game.loc.t("tr.spirit_state", {"value": " / ".join(Data.as_array(arg).map(func(x): return ctx.game.name_of("spirit_states", x)))}),
	}, OWNER)
	r.values.register("calm_months", {"scopes": CH, "doc": "Сколько месяцев подряд стресс почти нулевой", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return Data.num(c.vars.get("calm")) if c != null else 0.0
	}, OWNER)

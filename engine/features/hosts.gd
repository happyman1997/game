class_name Hosts
extends EngineFeature
## Воинства — специализации войска: какое это войско.
##
## У правителя одно воинство (c.host = {id, devotion, since}) из
## army_specializations (common/hosts.yaml): что оно умеет в бою (abilities —
## умения, которые исполняет ядро сражений или Battle), кто в него идёт
## (особые отряды с can_recruit: { has_host: … }), что ему нужно, чтобы
## оставаться собой (keep — условия раз в месяц, on — события: победа,
## поражение, сведённый лес). Стойкость (devotion) падает до нуля — воинство
## распадается. Силы вождя (вера, тёмный договор, магия, родство) действуют
## через воинство, без нажатий в бою.

const OWNER := "core/hosts"
## Умения, которые читает ядро сражений (Side.host).
const CORE := ["levy_hold", "terror", "guard", "ambush", "slip", "spells"]
const FLAGS := ["levy_hold", "guard", "slip", "pack_leader"]
const ALL := ["levy_hold", "terror", "guard", "ambush", "slip", "spells", "bane", "morale", "pursuit", "pack_leader", "rise", "allies_dread"]


func _init() -> void:
	id = "hosts"
	doc = "Воинства: специализация войска — умения в бою, особые отряды, стойкость"


static func _n(game: Game, key: String, fallback: float) -> float:
	return game.def_num("hosts." + key, fallback)


static func defs(game: Game) -> Array:
	return game.engine.sorted_content("army_specializations")


static func def_of(game: Game, hid: Variant) -> Variant:
	return game.content.get_def("army_specializations", hid) if hid != null else null


static func host_of(c: Variant) -> Variant:
	return c.get("host") if c is Dictionary and c.get("host") is Dictionary else null


## Определение действующего воинства правителя (стойкость выше нуля) или null.
static func active(game: Game, c: Variant) -> Variant:
	var h: Variant = host_of(c)
	if h == null or float(h.get("devotion", 0.0)) <= 0.0:
		return null
	return def_of(game, h.id)


static func _ctx(game: Game, c: Dictionary) -> ScriptContext:
	return ScriptContext.make(game, {"type": "character", "id": c.id})


static func is_potential(game: Game, c: Dictionary, d: Dictionary) -> bool:
	if c.titles.is_empty():
		return false
	var ctx := _ctx(game, c)
	return Interp.eval_trigger(ctx, ctx.root, d.get("potential"))


static func available(game: Game, c: Dictionary) -> Array:
	return defs(game).filter(func(d): return is_potential(game, c, d))


static func adopt_blockers(game: Game, c: Dictionary, d: Dictionary) -> Array:
	var out := []
	if c.titles.is_empty():
		out.append(game.loc.t("tr.is_ruler"))
	var h: Variant = host_of(c)
	if h != null and h.id == d.id:
		out.append(game.loc.t("host.already"))
	var ctx := _ctx(game, c)
	out.append_array(Interp.failed_triggers(ctx, ctx.root, d.get("can_adopt")))
	out.append_array(Economy.cost_blockers(game, c, d.get("cost", {}) if d.get("cost") is Dictionary else {}))
	return out


## Собрать воинство (прежнее распадается).
static func adopt(game: Game, c: Dictionary, hid: String, free := false) -> bool:
	var d: Variant = def_of(game, hid)
	if d == null or (not free and not adopt_blockers(game, c, d).is_empty()):
		return false
	if not free:
		var cost: Dictionary = d.get("cost", {}) if d.get("cost") is Dictionary else {}
		if Data.num(cost.get("gold")) > 0.0:
			Treasury.add(game, c, -Data.num(cost.gold), "war")
		c.prestige = float(c.prestige) - Data.num(cost.get("prestige"))
		c.piety = float(c.piety) - Data.num(cost.get("piety"))
	if host_of(c) != null:
		dissolve(game, c, "replaced")
	c["host"] = {"id": hid, "devotion": Data.num(d.get("devotion"), _n(game, "start_devotion", 60.0)), "since": game.date}
	game.touch(c)
	game.stat_cache.erase(c.id)
	if d.get("on_adopt") != null:
		var ctx := _ctx(game, c)
		Interp.run_effect(ctx, ctx.root, d.on_adopt)
	game.emit("host.adopted", {"character": c, "host": hid})
	game.notify("army")
	return true


## Воинство распадается: why — replaced, devotion, abandoned.
static func dissolve(game: Game, c: Dictionary, why: String) -> void:
	var h: Variant = host_of(c)
	if h == null:
		return
	c.erase("host")
	game.touch(c)
	game.stat_cache.erase(c.id)
	if why != "replaced" and game.is_player(c.id):
		game.message(game.loc.t("msg.host_dissolved." + why, {"host": game.name_of("army_specializations", h.id)}), "bad")
	game.emit("host.dissolved", {"character": c, "host": h.id, "why": why})
	game.notify("army")


static func change_devotion(game: Game, c: Dictionary, delta: float, key: String = "") -> void:
	var h: Variant = host_of(c)
	if h == null or delta == 0.0:
		return
	h.devotion = clampf(float(h.devotion) + delta, 0.0, _n(game, "max_devotion", 100.0))
	game.touch(c)
	if float(h.devotion) <= 0.0:
		dissolve(game, c, "devotion")


## Изменение стойкости за месяц по правилам keep: [{key, value}].
static func keep_parts(game: Game, c: Dictionary, d: Dictionary) -> Array:
	var out := []
	var ctx := _ctx(game, c)
	for rule in Data.as_array(d.get("keep")):
		if not (rule is Dictionary):
			continue
		if rule.get("trigger") != null and not Interp.eval_trigger(ctx, ctx.root, rule.trigger):
			continue
		out.append({"key": str(rule.get("key", "")), "value": Data.num(rule.get("monthly"))})
	return out


static func on_event(game: Game, c: Variant, ev: String) -> void:
	if not (c is Dictionary):
		return
	var h: Variant = host_of(c)
	if h == null:
		return
	var d: Variant = def_of(game, h.id)
	if d == null or not (d.get("on") is Dictionary) or d.on.get(ev) == null:
		return
	change_devotion(game, c, Data.num(d.on[ev]), ev)


static func monthly_char(game: Game, c: Dictionary) -> void:
	if c.titles.is_empty():
		return
	var h: Variant = host_of(c)
	if h != null:
		var d: Variant = def_of(game, h.id)
		if d == null:
			c.erase("host")
			return
		var delta := 0.0
		for p in keep_parts(game, c, d):
			delta += float(p.value)
		change_devotion(game, c, delta, "keep")
		return
	# ИИ собирает воинство, если оно ему по пути и по карману
	if not game.ai_controls(c.id) or not game.rng.chance(_n(game, "ai_adopt_chance", 0.04)):
		return
	var ctx := _ctx(game, c)
	var opts := []
	for d in available(game, c):
		if not adopt_blockers(game, c, d).is_empty():
			continue
		var w := maxf(0.0, Interp.eval_value(ctx, ctx.root, d.ai_will_do) if d.get("ai_will_do") != null else 10.0)
		if w > 0.0:
			opts.append({"d": d, "w": w})
	var pick: Variant = game.rng.weighted(opts, func(o): return o.w)
	if pick != null:
		adopt(game, c, str(pick.d.id))


# ------------------------------------------------------------ бой

## Действует ли умение: when (на правителя, scope:enemy, scope:location),
## enemy (на вражеского вождя), where (местность графства боя).
static func _applies(game: Game, c: Dictionary, spec: Variant, enemy: Variant, loc: Variant) -> bool:
	if not (spec is Dictionary):
		return true
	var sc := {}
	if enemy is Dictionary:
		sc["enemy"] = {"type": "character", "id": enemy.id}
	if loc != null:
		sc["location"] = {"type": "province", "id": str(loc)}
	if spec.get("when") != null:
		var ctx := ScriptContext.make(game, {"type": "character", "id": c.id}, sc)
		if not Interp.eval_trigger(ctx, ctx.root, spec.when):
			return false
	if spec.get("enemy") != null:
		if not (enemy is Dictionary):
			return false
		var ectx := ScriptContext.make(game, {"type": "character", "id": enemy.id}, {"enemy": {"type": "character", "id": c.id}})
		if not Interp.eval_trigger(ectx, ectx.root, spec.enemy):
			return false
	if spec.get("where") is Dictionary:
		if loc == null or not game.land().ready():
			return false
		var share := 0.0
		for t in Data.as_array(spec.where.get("terrain")):
			share += game.land().share(str(loc), str(t))
		if share < Data.num(spec.where.get("share"), 0.3):
			return false
	return true


static func _value(game: Game, c: Dictionary, key: String, spec: Variant) -> float:
	var v: Variant = spec.get("value") if spec is Dictionary else spec
	if v == null:
		return 1.0 if key in FLAGS else 0.0
	if v is bool:
		return 1.0 if v else 0.0
	if v is String and ScriptContext.is_yes(v):
		return 1.0
	var ctx := _ctx(game, c)
	return Interp.eval_value(ctx, ctx.root, v)


## Умения воинства правителя в этом бою: {умение: значение} (только действующие).
static func abilities(game: Game, c: Variant, enemy: Variant = null, loc: Variant = null) -> Dictionary:
	var out := {}
	if not (c is Dictionary):
		return out
	var d: Variant = active(game, c)
	if d == null or not (d.get("abilities") is Dictionary):
		return out
	for k in d.abilities:
		var spec: Variant = d.abilities[k]
		if not _applies(game, c, spec, enemy, loc):
			continue
		var v := _value(game, c, str(k), spec)
		if v != 0.0:
			out[str(k)] = v
	return out


## Для ядра: умения стороны (Side.host).
static func core_input(ab: Dictionary) -> Dictionary:
	var h := {}
	for k in CORE:
		if ab.has(k):
			h[k] = (ab[k] != 0.0) if k in FLAGS else ab[k]
	return h


## Вождь стороны: хозяин самой большой армии.
static func lead_owner(game: Game, armies: Array) -> Variant:
	var best: Variant = null
	for a in armies:
		if best == null or int(a.size) > int(best.size):
			best = a
	return game.ch(best.owner) if best != null else null


## После боя: стойкость от победы и поражения, павшие встают (rise).
static func after_battle(game: Game, report: Dictionary, loc: String) -> void:
	for side in 2:
		if side >= report.sides.size():
			continue
		var s: Dictionary = report.sides[side]
		var won := int(report.winner) == side
		var lead: Variant = game.ch(s.get("host_owner"))
		if lead == null:
			continue
		on_event(game, lead, "battle_won" if won else "battle_lost")
		var rise := float(s.get("rise", 0.0))
		if rise <= 0.0:
			continue
		var dead := float(report.lost[0]) + float(report.lost[1])
		var n := roundi(dead * rise * (1.0 if won else 0.5))
		if n <= 0:
			continue
		var army: Variant = null
		for aid in Data.as_array(s.get("armies")):
			var a: Variant = game.state.armies.get(aid)
			if a != null and a.owner == lead.id and (army == null or int(a.size) > int(army.size)):
				army = a
		if army == null:
			continue
		army.size = int(army.size) + n
		army.max_size = int(army.max_size) + n
		report.events.append({"day": int(report.days), "kind": "risen", "side": side, "n": n})
		game.emit("host.risen", {"character": lead, "army": army, "n": n})


## Стойкость правителя с землёй и лесом: сведённый лес (forest_felled).
static func _on_land_work(game: Game, p: Dictionary) -> void:
	var works: Array = Data.as_array(game.def_val("hosts.forest_works", []))
	if not works.has(str(p.get("work"))):
		return
	on_event(game, game.ch(p.get("by")), "forest_felled")


func install(engine: GameEngine) -> void:
	engine.systems.register("hosts", {"id": "hosts", "order": 55, "on_character_month": Hosts.monthly_char}, OWNER)
	engine.hooks.on("battle", func(p):
		if p.get("report") is Dictionary:
			Hosts.after_battle(p.game, p.report, str(p.location))
	, -25, OWNER)
	engine.hooks.on("land.work_done", func(p): Hosts._on_land_work(p.game, p), 0, OWNER)
	# характеристики воинства (modifiers) — правителю, пока оно стоит
	engine.modifier_providers.register("hosts", {"fn": func(game: Game, c: Dictionary) -> Variant:
		var d: Variant = Hosts.active(game, c)
		if d == null or not (d.get("modifiers") is Dictionary) or d.modifiers.is_empty():
			return null
		var hid: String = d.id
		return [{"label": func(): return game.name_of("army_specializations", hid), "modifiers": d.modifiers}]
	}, OWNER)
	engine.content_validators.register("army_specializations", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("army_specializations"):
			var w := "army_specializations/" + str(d.id)
			v.trigger(d.get("potential"), w + " potential")
			v.trigger(d.get("can_adopt"), w + " can_adopt")
			if d.get("abilities") is Dictionary:
				for k in d.abilities:
					if not str(k) in Hosts.ALL:
						v.issue(w + ": нет такого умения — " + str(k))
					var spec: Variant = d.abilities[k]
					if spec is Dictionary:
						v.trigger(spec.get("when"), w + " abilities." + str(k) + ".when")
						v.trigger(spec.get("enemy"), w + " abilities." + str(k) + ".enemy")
			for rule in Data.as_array(d.get("keep")):
				if rule is Dictionary:
					v.trigger(rule.get("trigger"), w + " keep")
	, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	r.triggers.register("has_host", {"scopes": CH, "doc": "Воинство правителя (действующее): has_host: sun_host (или yes)", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		var d: Variant = Hosts.active(ctx.game, c) if c != null else null
		if ScriptContext.is_yes(arg):
			return d != null
		if str(arg) == "no":
			return d == null
		return d != null and d.id == str(arg),
	}, OWNER)
	r.triggers.register("is_strongest_of_court", {"scopes": CH, "doc": "Доблестью не уступает никому из своих рыцарей и придворных", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c == null:
			return not ScriptContext.is_yes(arg)
		var mine := Stats.skill(ctx.game, c, "prowess")
		var pool: Array = ctx.game.courtiers_of(c.id)
		if ctx.game.engine.has_feature("knights"):
			pool = pool + Knights.knights_of(ctx.game, c)
		var yes := true
		for x in pool:
			if x.id != c.id and Chars.is_alive(x) and Chars.is_adult(ctx.game, x) and Stats.skill(ctx.game, x, "prowess") > mine:
				yes = false
				break
		return yes == ScriptContext.is_yes(arg),
	}, OWNER)
	r.values.register("host_devotion", {"scopes": CH, "doc": "Стойкость воинства правителя (0 — нет воинства)", "get": func(ctx, s, _a):
		var h: Variant = Hosts.host_of(ctx.game.ch(s.id))
		return float(h.devotion) if h != null else 0.0,
	}, OWNER)
	r.effects.register("set_host", {"scopes": CH, "doc": "Собрать воинство даром (none — распустить): set_host: forest_host",
		"apply": func(ctx, s, arg):
			var c: Variant = ctx.game.ch(s.id)
			if c == null:
				return
			if str(arg) == "none":
				Hosts.dissolve(ctx.game, c, "abandoned")
			else:
				Hosts.adopt(ctx.game, c, str(arg), true),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.set_host", {"value": ctx.game.name_of("army_specializations", str(arg))}),
	}, OWNER)
	r.effects.register("add_host_devotion", {"scopes": CH, "doc": "Изменить стойкость воинства: add_host_devotion: 10",
		"apply": func(ctx, s, arg):
			var c: Variant = ctx.game.ch(s.id)
			if c != null:
				Hosts.change_devotion(ctx.game, c, Data.num(arg), "effect"),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.add_host_devotion", {"value": Builtins.signed(Data.num(arg))}),
	}, OWNER)

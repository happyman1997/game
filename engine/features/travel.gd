class_name Travel
extends EngineFeature
## Путники и шайки. Люди с поручениями идут по карте на самом деле: путь —
## по клеткам от сердца графства до сердца (по дорогам быстрее, Land), в
## день — defines.travel.speed «цены пути»; на месте живут срок поручения и
## идут назад, исход решается по возвращении (Missions). Нет пути по суше
## (за морем) — поручение идёт по-старому, сроком.
##
## Шайки (bands) — сущности на карте: логово в клетке, угодья — radius
## клеток вокруг. Путник в чужих угодьях может на них наткнуться (шанс
## encounter_chance в день, один раз на шайку): схватка с врагом шайки
## (foes, Duels); отбился — шайка слабеет (strength — сколько поражений
## выдержит), пал — как повезёт в схватке. Шайка бьёт подать графства
## (modifiers), живёт years лет или пока её не разобьют. Появляется от
## событий и войны (эффект spawn_band) и от природы (spawn: раз в год шанс
## для графства, где довольно её местности). Разбить шайку — поручение с
## on_arrive: { scope:target: { fight_band: yes } } (охота).
##
## Караваны: посад (район market) уровня N раз в months_per_level / N
## месяцев отправляет караван к другому посаду не дальше max_cost «цены
## пути» (не к врагу); караван идёт по дорогам и, дойдя, приносит владельцам
## обоих концов доход (статья «Торговля»): тем больше, чем крупнее посады и
## длиннее путь, а по тракту у обоих — ещё больше. Шайка в угодьях может
## караван разграбить — и сама крепнет.
##
## Данные:
##   bands.<id>: { icon, foe, lair: [местности или группы], radius, years,
##     strength, encounter_chance, modifiers: { … },
##     spawn: { chance, terrain: { местность: доля }, trigger } }  — природа (в год; root — графство)
##   defines.travel: { speed }
##   defines.caravans: { months_per_level, max_cost, base_value, value_per_level,
##     long_days, road_bonus, origin_share }
## Состояние: state.travelers {id: {id, kind, who, route, step, budget, phase,
##   home, dest, stay_until, met}}, state.bands {id: {id, kind, cell, province,
##   strength, until}}. Хуки: travel.arrived {traveler}, band.spawned {band},
##   band.encounter {character, band, won}, band.gone {band, why},
##   caravan.arrived {from, to, value}, caravan.robbed {from, to, band}.

const OWNER := "core/travel"


func _init() -> void:
	id = "travel"
	doc = "Путники идут по карте по клеткам; шайки на дорогах и встречи с ними"


static func travelers(game: Game) -> Dictionary:
	if not (game.state.get("travelers") is Dictionary):
		game.state["travelers"] = {}
	return game.state.travelers


static func bands(game: Game) -> Dictionary:
	if not (game.state.get("bands") is Dictionary):
		game.state["bands"] = {}
	return game.state.bands


static func _new_id(game: Game, prefix: String) -> String:
	var n := int(game.state.get("next_id", 1))
	game.state["next_id"] = n + 1
	return "%s%d" % [prefix, n]


# ------------------------------------------------------------ путь

## Отправить путника из клетки from в to. Возвращает id или "" (нет пути).
static func depart(game: Game, kind: String, who: Variant, from: int, to: int, extra: Dictionary = {}) -> String:
	var land := game.land()
	if not land.ready() or from < 0 or to < 0:
		return ""
	var route: PackedInt32Array = land.core.find_path(from, to) if from != to else PackedInt32Array([from])
	if route.is_empty():
		return ""
	var tid := _new_id(game, "tr")
	var t := {"id": tid, "kind": kind, "who": who, "route": Array(route), "step": 0, "budget": 0.0,
		"phase": "out", "home": from, "dest": to, "stay_until": 0, "met": {}}
	t.merge(extra, true)
	travelers(game)[tid] = t
	return tid


## Дней пути по маршруту (по цене клеток и скорости).
static func route_days(game: Game, route: Array) -> int:
	var land := game.land()
	var cost := 0.0
	for i in range(1, route.size()):
		cost += (float(land.core.cell_cost(int(route[i - 1]))) + float(land.core.cell_cost(int(route[i])))) * 0.5
	return ceili(cost / maxf(0.1, game.def_num("travel.speed", 3.0)))


## Где путник сейчас (клетка).
static func cell_of(t: Dictionary) -> int:
	var r: Array = t.route
	return int(r[clampi(int(t.step), 0, r.size() - 1)]) if not r.is_empty() else -1


## Точка на карте (между клетками — по пройденной доле шага).
static func position(game: Game, t: Dictionary) -> Vector2:
	var land := game.land()
	var r: Array = t.route
	if r.is_empty():
		return Vector2.ZERO
	var i := clampi(int(t.step), 0, r.size() - 1)
	var a: Vector2 = land.core.cell_center(int(r[i]))
	if t.phase == "stay" or i + 1 >= r.size():
		return a
	var b: Vector2 = land.core.cell_center(int(r[i + 1]))
	var c := (float(land.core.cell_cost(int(r[i]))) + float(land.core.cell_cost(int(r[i + 1])))) * 0.5
	return a.lerp(b, clampf(float(t.budget) / maxf(0.01, c), 0.0, 1.0))


static func remove(game: Game, tid: Variant) -> void:
	if tid != null:
		travelers(game).erase(tid)


## Путник поручения этого персонажа (или null).
static func of_agent(game: Game, cid: String) -> Variant:
	for t in travelers(game).values():
		if t.kind == "mission" and t.who == cid:
			return t
	return null


## Каждый день: путники идут, приходят, встречают шайки.
static func daily(game: Game) -> void:
	var all := travelers(game)
	if all.is_empty():
		return
	var land := game.land()
	var speed := game.def_num("travel.speed", 3.0)
	for tid in all.keys():
		var t: Variant = all.get(tid)
		if t == null:
			continue
		if t.phase == "stay":
			if game.date >= int(t.stay_until):
				_head_home(game, t)
			continue
		# задержали в пути (вмешательство в чужое дело)
		if t.get("wait_until") != null and game.date < int(t.wait_until):
			continue
		var r: Array = t.route
		t.budget = float(t.budget) + speed
		while int(t.step) + 1 < r.size():
			var a := int(r[int(t.step)])
			var b := int(r[int(t.step) + 1])
			var c := (float(land.core.cell_cost(a)) + float(land.core.cell_cost(b))) * 0.5
			if float(t.budget) < c:
				break
			t.budget = float(t.budget) - c
			t.step = int(t.step) + 1
		_meet_bands(game, t)
		if not all.has(tid):
			continue
		if int(t.step) + 1 >= r.size():
			t.budget = 0.0
			_arrive(game, t)


static func _arrive(game: Game, t: Dictionary) -> void:
	game.emit("travel.arrived", {"traveler": t})
	if t.kind == "caravan":
		remove(game, t.id)
		_trade(game, t)
		return
	if t.kind != "mission":
		remove(game, t.id)
		return
	var agent: Variant = game.ch(t.who)
	var m: Variant = Missions.of(agent)
	if agent == null or m == null:
		remove(game, t.id)
		return
	if t.phase == "out":
		t.phase = "stay"
		t.stay_until = game.date + int(t.get("stay_days", 30))
		Missions.on_arrive(game, agent)
	else:
		remove(game, t.id)
		Missions.resolve(game, agent)


## Срок на месте вышел — домой (к нынешнему сердцу покровителя).
static func _head_home(game: Game, t: Dictionary) -> void:
	var home := int(t.home)
	if t.kind == "mission":
		var agent: Variant = game.ch(t.who)
		var m: Variant = Missions.of(agent)
		var patron: Variant = game.ch(str(m.patron)) if m != null and m.get("patron") != null else null
		var cap: Variant = Titles.capital_of(game, patron) if patron != null and not patron.titles.is_empty() else null
		if cap != null and game.land().seat(cap) >= 0:
			home = game.land().seat(cap)
	var here := cell_of(t)
	var route: PackedInt32Array = game.land().core.find_path(here, home) if here != home else PackedInt32Array([here])
	if route.is_empty():
		route = PackedInt32Array([here])
	t.route = Array(route)
	t.step = 0
	t.budget = 0.0
	t.phase = "back"
	t.met = {}


# ------------------------------------------------------------ шайки

static func band_def(game: Game, b: Dictionary) -> Variant:
	return game.content.get_def("bands", str(b.kind))


## Завести шайку в графстве: логово — в клетке её местности (или любой).
static func spawn_band(game: Game, kind: String, pid: String, by: Variant = null) -> Variant:
	var d: Variant = game.content.get_def("bands", kind)
	var land := game.land()
	if d == null or not land.ready() or land.count(pid) == 0:
		return null
	var cells := land.cells(pid)
	var fit := []
	for c in cells:
		if land.matches(land.terrain_at(c), d.get("lair", [])):
			fit.append(c)
	if fit.is_empty():
		fit = Array(cells)
	var bid := _new_id(game, "band")
	var b := {"id": bid, "kind": kind, "cell": int(game.rng.pick(fit)), "province": pid,
		"strength": int(Data.num(d.get("strength"), 3)), "until": game.date + roundi(Data.num(d.get("years"), 8) * 365.0), "by": by}
	bands(game)[bid] = b
	game.stat_cache.erase("prov:" + pid)
	game.emit("band.spawned", {"band": b})
	var t: Variant = game.state.titles.get(pid)
	var holder: Variant = game.ch(t.holder) if t != null else null
	if holder != null:
		game.mark_chars_dirty([holder.id])
		if game.is_player(holder.id):
			game.message(game.loc.t("msg.band_spawned", {"place": game.scope_name({"type": "province", "id": pid}), "band": game.name_of("bands", kind)}),
				"bad", {"type": "province", "id": pid})
	return b


static func remove_band(game: Game, bid: String, why: String) -> void:
	var b: Variant = bands(game).get(bid)
	if b == null:
		return
	bands(game).erase(bid)
	game.stat_cache.erase("prov:" + str(b.province))
	var t: Variant = game.state.titles.get(b.province)
	if t != null and t.holder != null:
		game.mark_chars_dirty([t.holder])
	game.emit("band.gone", {"band": b, "why": why})


## Шайки графства.
static func bands_in(game: Game, pid: String) -> Array:
	return bands(game).values().filter(func(b): return b.province == pid)


## Шайки, в чьих угодьях клетка.
static func bands_near(game: Game, cell: int) -> Array:
	var out := []
	var land := game.land()
	for b in bands(game).values():
		var d: Variant = band_def(game, b)
		if d != null and int(land.core.hex_distance(cell, int(b.cell))) <= int(Data.num(d.get("radius"), 2)):
			out.append(b)
	return out


static func _meet_bands(game: Game, t: Dictionary) -> void:
	if bands(game).is_empty() or t.get("escort", false):
		return
	if t.kind == "caravan":
		_rob(game, t)
		return
	if t.kind != "mission":
		return
	var cell := cell_of(t)
	for b in bands_near(game, cell):
		if t.met.has(b.id):
			continue
		var d: Variant = band_def(game, b)
		if not game.rng.chance(Data.num(d.get("encounter_chance"), 15) / 100.0):
			continue
		t.met[b.id] = true
		var agent: Variant = game.ch(t.who)
		if agent == null or not Chars.is_alive(agent):
			return
		var won := fight(game, agent, b)
		var m: Variant = Missions.of(agent)
		var patron: Variant = game.ch(str(m.patron)) if m != null and m.get("patron") != null else null
		if patron != null and game.is_player(patron.id):
			game.message(game.loc.t("msg.band_met_won" if won else "msg.band_met_lost", {"agent": game.scope_name({"type": "character", "id": agent.id}),
				"band": game.name_of("bands", str(b.kind)), "place": game.scope_name({"type": "province", "id": b.province})}),
				"good" if won else "bad", {"type": "character", "id": agent.id})
		if not Chars.is_alive(agent):
			return


## Схватка персонажа с шайкой: победил — шайка слабеет (или разбита).
static func fight(game: Game, c: Dictionary, b: Dictionary) -> bool:
	var d: Variant = band_def(game, b)
	var foe := str(d.get("foe", "bandit")) if d != null else "bandit"
	var w := Duels.duel(game, c, null, {"foe": foe, "kind": "mortal"})
	var won: bool = not w.is_empty() and w.id == c.id
	if won:
		b.strength = int(b.strength) - 1
		if int(b.strength) <= 0:
			remove_band(game, b.id, "beaten")
	game.emit("band.encounter", {"character": c, "band": b, "won": won})
	return won


## Раз в год: шайки, чей срок вышел, расходятся; природа заводит новых.
static func yearly(game: Game) -> void:
	for b in bands(game).values().duplicate():
		if game.date >= int(b.until):
			remove_band(game, b.id, "gone")
	var land := game.land()
	if not land.ready():
		return
	for d in game.content.all("bands"):
		var sp: Variant = d.get("spawn")
		if not (sp is Dictionary):
			continue
		var chance := Data.num(sp.get("chance"), 0.0)
		for pid in game.state.provinces:
			var ok := true
			if sp.get("terrain") is Dictionary:
				for t in sp.terrain:
					if land.share(pid, t) < Data.num(sp.terrain[t]):
						ok = false
						break
			if not ok or not bands_in(game, pid).is_empty() or not game.rng.chance(chance):
				continue
			if sp.get("trigger") != null:
				var ctx := ScriptContext.make(game, {"type": "province", "id": pid})
				if not Interp.eval_trigger(ctx, ctx.root, sp.trigger):
					continue
			spawn_band(game, str(d.id), pid)


# ------------------------------------------------------------ караваны

static func _market(game: Game, pid: String) -> int:
	return Districts.level(game, pid, "market") if game.engine.has_feature("districts") else 0


static func _top(game: Game, pid: String) -> Variant:
	var t: Variant = game.state.titles.get(pid)
	var h: Variant = game.ch(t.holder) if t != null else null
	return Titles.top_liege(game, h) if h != null else null


## Раз в месяц: посады отправляют караваны.
static func monthly(game: Game) -> void:
	var land := game.land()
	if not land.ready() or not game.engine.has_feature("districts"):
		return
	var markets := []
	for pid in game.state.provinces:
		var lv := _market(game, pid)
		if lv > 0 and land.seat(pid) >= 0 and game.state.titles.get(pid) != null and game.state.titles[pid].holder != null:
			markets.append([pid, lv])
	if markets.size() < 2:
		return
	var per := maxf(1.0, game.def_num("caravans.months_per_level", 12))
	var max_cost := game.def_num("caravans.max_cost", 140)
	for m in markets:
		if not game.rng.chance(float(m[1]) / per):
			continue
		var from: String = m[0]
		var a := land.seat(from)
		var at: Vector2 = land.core.cell_center(a)
		var top_a: Variant = _top(game, from)
		var cands := []
		for o in markets:
			if o[0] == from:
				continue
			var d: float = (land.core.cell_center(land.seat(o[0])) as Vector2).distance_to(at)
			# по прямой не дальше пути, который караван осилит
			if d > max_cost * land.core.cell_size() * 1.7320508 * 0.9:
				continue
			var top_b: Variant = _top(game, o[0])
			if top_a != null and top_b != null and top_a.id != top_b.id and Wars.is_at_war_with(game, top_a.id, top_b.id):
				continue
			cands.append(o)
		var pick: Variant = game.rng.weighted(cands, func(o): return float(o[1]))
		if pick == null:
			continue
		var b := land.seat(pick[0])
		var cost: float = land.core.path_cost(a, b)
		if cost < 0.0 or cost > max_cost:
			continue
		depart(game, "caravan", null, a, b, {"from": from, "to": pick[0], "levels": int(m[1]) + int(pick[1])})


## Караван дошёл: доход обоим концам.
static func _trade(game: Game, t: Dictionary) -> void:
	var days := float(route_days(game, t.route))
	var v := (game.def_num("caravans.base_value", 6) + game.def_num("caravans.value_per_level", 4) * float(t.get("levels", 2))) \
		* clampf(days / maxf(1.0, game.def_num("caravans.long_days", 20)), 0.6, 2.0)
	var land := game.land()
	if land.seat_road(str(t.get("from", ""))) in ["road", "paved"] and land.seat_road(str(t.get("to", ""))) in ["road", "paved"]:
		v *= 1.0 + game.def_num("caravans.road_bonus", 0.25)
	var share := game.def_num("caravans.origin_share", 0.5)
	for pair in [[t.get("from"), share], [t.get("to"), 1.0 - share]]:
		var ti: Variant = game.state.titles.get(pair[0]) if pair[0] != null else null
		var h: Variant = game.ch(ti.holder) if ti != null else null
		if h != null and Chars.is_alive(h):
			Treasury.add(game, h, v * float(pair[1]), "trade")
	game.emit("caravan.arrived", {"from": t.get("from"), "to": t.get("to"), "value": v})


## Шайка в угодьях может разграбить караван — и крепнет.
static func _rob(game: Game, t: Dictionary) -> void:
	for b in bands_near(game, cell_of(t)):
		if t.met.has(b.id):
			continue
		t.met[b.id] = true
		var d: Variant = band_def(game, b)
		if not game.rng.chance(Data.num(d.get("encounter_chance"), 15) / 100.0):
			continue
		remove(game, t.id)
		b.strength = mini(int(b.strength) + 1, int(Data.num(d.get("strength"), 3)) + 2)
		game.emit("caravan.robbed", {"from": t.get("from"), "to": t.get("to"), "band": b})
		for pid in [t.get("from"), t.get("to")]:
			var ti: Variant = game.state.titles.get(pid) if pid != null else null
			if ti != null and ti.holder != null and game.is_player(ti.holder):
				game.message(game.loc.t("msg.caravan_robbed", {"from": game.scope_name({"type": "province", "id": t.get("from")}),
					"to": game.scope_name({"type": "province", "id": t.get("to")}), "band": game.name_of("bands", str(b.kind)),
					"place": game.scope_name({"type": "province", "id": b.province})}), "bad", {"type": "province", "id": b.province})
				break
		return


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("travel", {"id": "travel", "order": 17, "on_day": Travel.daily, "on_month": Travel.monthly, "on_year": Travel.yearly}, OWNER)
	# шайка бьёт подать графства, где её логово
	engine.province_modifier_providers.register("bands", {"fn": func(game: Game, pid: String) -> Variant:
		var all := Travel.bands(game)
		if all.is_empty():
			return null
		var out := {}
		for b in all.values():
			if b.province != pid:
				continue
			var d: Variant = Travel.band_def(game, b)
			if d != null and d.get("modifiers") is Dictionary:
				for k in d.modifiers:
					out[k] = float(out.get(k, 0.0)) + Data.num(d.modifiers[k])
		return out if not out.is_empty() else null
	}, OWNER)
	engine.content_validators.register("bands", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("bands"):
			var w := "bands/" + str(d.id)
			v.ref("foes", d.get("foe"), w + " foe")
			for t in Data.as_array(d.get("lair")):
				Biomes._ref_terrain_or_group(e, v, t, w + " lair")
	, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var PR := ["province"]
	r.triggers.register("has_band", {"scopes": PR, "doc": "В графстве логово шайки: has_band: yes | <вид шайки>", "eval": func(ctx, s, arg):
		var list := Travel.bands_in(ctx.game, s.id)
		if arg is String and arg != "yes" and arg != "no":
			return list.any(func(b): return b.kind == arg)
		return (not list.is_empty()) == ScriptContext.is_yes(arg)
	}, OWNER)
	r.effects.register("spawn_band", {"scopes": PR, "doc": "Завести шайку в графстве: spawn_band: outlaws",
		"apply": func(ctx, s, arg):
			var by: Variant = ctx.root.id if ctx.root.get("type") == "character" else null
			Travel.spawn_band(ctx.game, str(arg), s.id, by),
		"describe": func(ctx, s, arg):
			return ctx.game.loc.t("fx.spawn_band", {"place": ctx.game.scope_name(s), "band": ctx.game.name_of("bands", str(arg))}),
	}, OWNER)
	r.effects.register("fight_band", {"scopes": PR, "doc": "root (персонаж) бьётся с шайкой графства (самой сильной): fight_band: yes | { rout: yes } (rout — победа разгоняет шайку совсем)",
		"apply": func(ctx, s, arg):
			var c: Variant = ctx.game.ch(ctx.root.id) if ctx.root.get("type") == "character" else null
			var list := Travel.bands_in(ctx.game, s.id)
			if c == null or list.is_empty():
				return
			list.sort_custom(func(a, b): return int(a.strength) > int(b.strength))
			var b: Dictionary = list[0]
			var won := Travel.fight(ctx.game, c, b)
			if won and arg is Dictionary and ScriptContext.is_yes(arg.get("rout", false)) and Travel.bands(ctx.game).has(b.id):
				Travel.remove_band(ctx.game, b.id, "beaten")
			ctx.values["band_won"] = 1.0 if won else 0.0,
		"describe": func(ctx, s, _a):
			return ctx.game.loc.t("fx.fight_band", {"place": ctx.game.scope_name(s)}),
	}, OWNER)
	r.effects.register("remove_bands", {"scopes": PR, "doc": "Разогнать все шайки графства: remove_bands: yes",
		"apply": func(ctx, s, _a):
			for b in Travel.bands_in(ctx.game, s.id):
				Travel.remove_band(ctx.game, b.id, "beaten"),
		"describe": func(ctx, s, _a):
			return ctx.game.loc.t("fx.remove_bands", {"place": ctx.game.scope_name(s)}),
	}, OWNER)

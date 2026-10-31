class_name Wilds
extends EngineFeature
## Дикие земли и истощение армий.
## Графство без владельца — дикая земля: его не берут войной, а заселяют
## (эффект gain_title из решения; список wild_county — ничейные графства у
## границ державы). Армии в провинции с модификатором attrition (из
## модификаторов провинции или поля attrition местности) каждый месяц теряют
## эту долю воинов — так пепельные бури губят походы через пепелище.
## Хук army.attrition — {army, location, lost}.

const OWNER := "core/wilds"


func _init() -> void:
	id = "wilds"
	doc = "Дикие земли без владельцев и истощение армий"


## Доля воинов, которую армия теряет за месяц в провинции.
static func attrition_at(game: Game, prov_id: String) -> float:
	var a := Stats.prov_stat(game, prov_id, "attrition")
	a += game.terrain_num(prov_id, "attrition")
	# дорога через сердце графства — войску легче (roads.<id>.attrition_mult)
	var road := game.land().seat_road(prov_id) if game.land().ready() else ""
	if road != "":
		var rd: Variant = game.content.get_def("roads", road)
		if rd != null:
			a *= maxf(0.0, 1.0 + Data.num(rd.get("attrition_mult")))
	return clampf(a, 0.0, 0.9)


static func monthly(game: Game) -> void:
	for a in game.state.armies.values().duplicate():
		var att := attrition_at(game, a.location)
		if att <= 0.0 or int(a.size) <= 0:
			continue
		var owner: Variant = game.ch(a.owner)
		if owner != null:
			att *= maxf(0.0, 1.0 + Stats.stat(game, owner, "attrition_mult"))
			if att <= 0.0:
				continue
		var lost := maxi(1, roundi(float(a.size) * att))
		Military._distribute([a], lost, float(a.size))
		game.emit("army.attrition", {"army": a, "location": a.location, "lost": lost})
		if game.is_player(a.owner):
			game.message(game.loc.t("msg.attrition", {"n": lost, "place": game.scope_name({"type": "province", "id": a.location})}), "bad",
				{"type": "province", "id": a.location}, [a.owner])
		if int(a.size) <= 0:
			Military.disband_army(game, a.id)


## Ничейные графства у границ державы персонажа.
static func wild_counties_near(game: Game, c: Dictionary) -> Array:
	var mine := {}
	for x in Titles.realm_counties(game, c):
		mine[x] = true
	var out := {}
	for p in mine:
		for n in game.engine.neighbors(p):
			if not mine.has(n) and game.state.titles.has(n) and game.state.titles[n].holder == null and game.state.provinces.has(n):
				out[n] = true
	return out.keys()


func install(engine: GameEngine) -> void:
	engine.systems.register("wilds", {"id": "wilds", "order": 35, "on_month": Wilds.monthly}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	r.lists.register("wild_county", {"from": ["character"], "doc": "Ничейные графства у границ державы", "list": func(ctx, s):
		var c: Variant = ctx.game.ch(s.id)
		if c == null:
			return []
		return Wilds.wild_counties_near(ctx.game, c).map(func(x): return {"type": "province", "id": x})
	}, OWNER)
	r.values.register("num_wild_counties", {"scopes": ["character"], "doc": "Число ничейных графств у границ державы", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return float(Wilds.wild_counties_near(ctx.game, c).size()) if c != null else 0.0
	}, OWNER)
	r.values.register("attrition", {"scopes": ["province"], "doc": "Доля воинов, которую армия теряет здесь за месяц", "get": func(ctx, s, _a):
		return Wilds.attrition_at(ctx.game, s.id)
	}, OWNER)

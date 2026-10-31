extends TestCase
## Путники и шайки: человек с поручением идёт по карте (туда, живёт на
## месте, назад) и исход решается по возвращении; за морем — сроком, как
## прежде; шайка бьёт подать графства, нападает на путников в своих угодьях;
## охотник разгоняет шайку; природа заводит волков в глуши; сохранение
## помнит путников и шайки.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _agent(g: Game, patron: Dictionary) -> Dictionary:
	return Chars.create_character(g, {"liege": patron.id, "age": 25, "culture": patron.culture, "faith": patron.faith, "female": false})


func _tick(g: Game, days: int) -> void:
	for i in days:
		g.state.pending_events.clear()
		g.state.pending_requests.clear()
		for f in Duels.pending(g).duplicate():
			Duels.dismiss(g, f.uid)
		g.tick()


## Цель посольства, до которой можно дойти по суше.
func _land_target(g: Game, h: Dictionary, a: Dictionary) -> Variant:
	var home := Missions._home_cell(g, h)
	for t in Missions.targets(g, "embassy", h, a):
		var dest := Missions._dest_cell(g, t.ref, home)
		if dest >= 0 and not g.land().core.find_path(home, dest).is_empty():
			return t.ref
	return null


func test_mission_walks_there_and_back() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var a := _agent(g, h)
	var target: Variant = _land_target(g, h, a)
	check(target != null, "есть правитель, к которому дойти по суше")
	Missions.start(g, "embassy", a, h, target)
	var m: Dictionary = Missions.of(a)
	check(m.get("trip") != null, "посол идёт по карте")
	var t: Dictionary = Travel.travelers(g)[m.trip]
	var start := Travel.position(g, t)
	_tick(g, 5)
	check(Travel.position(g, t) != start, "посол сдвинулся")
	# дойти до места
	t.step = t.route.size() - 1
	_tick(g, 1)
	check_eq(str(t.phase), "stay", "пришёл и живёт на месте")
	check(Missions.of(a) != null, "поручение ещё идёт")
	t.stay_until = g.date
	_tick(g, 1)
	check_eq(str(t.phase), "back", "идёт домой")
	t.step = t.route.size() - 1
	_tick(g, 1)
	check(Missions.of(a) == null, "вернулся — исход решён")
	check(not Travel.travelers(g).has(m.trip), "путника больше нет")


func test_overseas_goes_by_timer() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var a := _agent(g, h)
	var w := {"type": "character", "id": "william"}
	var home := Missions._home_cell(g, h)
	var dest := Missions._dest_cell(g, w, home)
	check(g.land().core.find_path(home, dest).is_empty(), "в Нормандию по суше не дойти")
	Missions.start(g, "embassy", a, h, w)
	var m: Dictionary = Missions.of(a)
	check(m.get("trip") == null, "за море — сроком, как прежде")
	m.until = g.date
	Missions.monthly_char(g, a)
	check(Missions.of(a) == null, "срок вышел — исход")


func test_band_hurts_county_and_meets_travelers() -> void:
	var g := _game()
	var tax := Economy.county_tax(g, "c_sussex")
	var b: Dictionary = Travel.spawn_band(g, "outlaws", "c_sussex")
	check(b != null and g.land().matches(g.land().terrain_at(int(b.cell)), "forest"), "логово разбойников — в лесу")
	g.stat_cache.clear()
	check(Economy.county_tax(g, "c_sussex") < tax, "шайка бьёт подать")
	var ctx := ScriptContext.make(g, {"type": "province", "id": "c_sussex"})
	check(Interp.eval_trigger(ctx, ctx.root, {"has_band": "outlaws"}), "условие has_band")
	# путник через угодья шайки
	var d: Dictionary = g.content.get_def("bands", "outlaws")
	var chance: Variant = d.encounter_chance
	d.encounter_chance = 100
	var met := [0]
	g.engine.hooks.on("band.encounter", func(_p): met[0] += 1, 0, "test")
	var h: Dictionary = g.ch("harold")
	var a := _agent(g, h)
	a.vars["mission"] = {"id": "glory_wandering", "patron": h.id, "target": null, "start": g.date, "until": g.date + 400}
	var tid := Travel.depart(g, "mission", a.id, int(b.cell), g.land().seat("c_sussex"))
	a.vars.mission["trip"] = tid
	_tick(g, 1)
	d.encounter_chance = chance
	check(met[0] == 1, "путник в угодьях наткнулся на шайку")
	_tick(g, 3)
	check(met[0] == 1, "с одной шайкой — одна встреча за путь")


func test_hunter_routs_band() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var routed := 0
	for i in 6:
		var b: Dictionary = Travel.spawn_band(g, "deserters", "c_kent")
		var a := _agent(g, h)
		a.skills.prowess = 30
		Missions.start(g, "hunt_band", a, h, {"type": "province", "id": "c_kent"})
		var m: Variant = Missions.of(a)
		var t: Dictionary = Travel.travelers(g)[m.trip]
		t.step = t.route.size() - 1
		Travel.daily(g)
		if not Travel.bands(g).has(b.id):
			routed += 1
		for x in Travel.bands_in(g, "c_kent"):
			Travel.remove_band(g, x.id, "test")
		if Missions.of(a) != null:
			Missions.finish(g, a, "recalled")
	check(routed >= 3, "сильный охотник чаще разгоняет шайку (%d из 6)" % routed)


func test_nature_spawns_wolves() -> void:
	var g := _game()
	var d: Dictionary = g.content.get_def("bands", "wolves")
	var sp: Dictionary = d.spawn
	var chance: Variant = sp.chance
	sp.chance = 1.0
	Travel.yearly(g)
	sp.chance = chance
	var wolves := Travel.bands(g).values().filter(func(b): return b.kind == "wolves")
	check(not wolves.is_empty(), "в глуши завелись волки (%d)" % wolves.size())
	for b in wolves:
		check(g.land().terrain_at(int(b.cell)) == "old_forest", "логово стаи — в дремучем лесу")
		break


func test_save_keeps_travelers_and_bands() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var a := _agent(g, h)
	var target: Variant = _land_target(g, h, a)
	Missions.start(g, "embassy", a, h, target)
	Travel.spawn_band(g, "wolves", "c_sussex")
	_tick(g, 3)
	var res := g.engine.load_game(SaveGame.serialize(g))
	check(res.error == "", res.error)
	var g2: Game = res.game
	check_eq(Travel.travelers(g2).size(), Travel.travelers(g).size(), "путники сохранились")
	check_eq(Travel.bands(g2).size(), Travel.bands(g).size(), "шайки сохранились")
	var a2: Dictionary = g2.ch(a.id)
	var t2: Dictionary = Travel.travelers(g2)[Missions.of(a2).trip]
	var step := int(t2.step)
	_tick(g2, 6)
	check(int(t2.step) > step, "путник идёт дальше после загрузки")


## Два посада с хозяевами — откуда и куда пустить караван.
func _two_markets(g: Game) -> Array:
	var out := []
	for pid in ["c_winchester", "c_london", "c_york", "c_kent", "c_sussex"]:
		if Districts.level(g, pid, "market") > 0 and g.land().seat(pid) >= 0:
			out.append(pid)
	return out


func test_markets_send_caravans() -> void:
	var g := _game()
	var ms := _two_markets(g)
	check(ms.size() >= 2, "есть посады: %s" % str(ms))
	var cfg: Dictionary = g.defines.caravans
	var per: Variant = cfg.months_per_level
	cfg.months_per_level = 1
	Travel.monthly(g)
	cfg.months_per_level = per
	var caravans := Travel.travelers(g).values().filter(func(t): return t.kind == "caravan")
	check(caravans.size() >= 5, "посады отправили караваны (%d)" % caravans.size())
	var c: Dictionary = caravans[0]
	check(c.get("from") != c.get("to") and Districts.level(g, str(c.to), "market") > 0, "караван идёт в другой посад")


func test_caravan_pays_both_ends() -> void:
	var g := _game()
	var ms := _two_markets(g)
	var a: String = ms[0]
	var b: String = ms[1]
	var land := g.land()
	var ha: Dictionary = g.ch(g.state.titles[a].holder)
	var hb: Dictionary = g.ch(g.state.titles[b].holder)
	var ga := float(ha.gold)
	var gb := float(hb.gold)
	var paid := [0.0]
	g.engine.hooks.on("caravan.arrived", func(p): paid[0] += float(p.value), 0, "test")
	var tid := Travel.depart(g, "caravan", null, land.seat(a), land.seat(b), {"from": a, "to": b, "levels": 2})
	var t: Dictionary = Travel.travelers(g)[tid]
	t.step = t.route.size() - 1
	Travel.daily(g)
	check(paid[0] > 0.0, "караван дошёл и принёс %.1f" % paid[0])
	check(float(ha.gold) > ga or ha.id == hb.id, "доход посаду, откуда караван")
	check(float(hb.gold) > gb, "и посаду, куда")
	check(not Travel.travelers(g).has(tid), "каравана больше нет")


func test_band_robs_caravan() -> void:
	var g := _game()
	var ms := _two_markets(g)
	var land := g.land()
	var band: Dictionary = Travel.spawn_band(g, "deserters", ms[0])
	band.cell = land.seat(ms[0])
	var d: Dictionary = g.content.get_def("bands", "deserters")
	var chance: Variant = d.encounter_chance
	d.encounter_chance = 100
	var robbed := [0]
	g.engine.hooks.on("caravan.robbed", func(_p): robbed[0] += 1, 0, "test")
	var s0 := int(band.strength)
	var tid := Travel.depart(g, "caravan", null, land.seat(ms[0]), land.seat(ms[1]), {"from": ms[0], "to": ms[1], "levels": 2})
	Travel.daily(g)
	d.encounter_chance = chance
	check(robbed[0] == 1 and not Travel.travelers(g).has(tid), "шайка разграбила караван")
	check(int(band.strength) > s0, "и окрепла")

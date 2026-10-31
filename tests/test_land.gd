extends TestCase
## Местность: нынешнее состояние земли меняет доход и рост; группа (гарь —
## тоже лес) работает для условий и полков; работа идёт месяцами, стоит
## золота и меняет землю, а летопись помнит автора; изнанка вырубки —
## недовольство графства и разливы у соседей; природа берёт своё (вырубка
## зарастает); война жжёт поля; столица в топи — лихорадка; ИИ берётся за
## землю; сохранение помнит землю.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _holder(g: Game, pid: String) -> Dictionary:
	return g.ch(g.state.titles[pid].holder)


func _to_month_end(g: Game, months: int) -> void:
	for d in months * 31:
		g.state.pending_events.clear()
		g.state.pending_requests.clear()
		g.tick()


func test_state_changes_income_and_group() -> void:
	var g := _game()
	check_eq(g.terrain_of("c_sussex"), "forest", "Суссекс в лесах")
	var before := Economy.county_tax(g, "c_sussex")
	Biomes.set_terrain(g, "c_sussex", "farmlands", "harold", "test")
	check(Economy.county_tax(g, "c_sussex") > before, "тучная пашня даёт больше, чем лес")
	Biomes.set_terrain(g, "c_sussex", "burnt_forest", null, "fire")
	var ctx := ScriptContext.make(g, {"type": "province", "id": "c_sussex"})
	check(Interp.eval_trigger(ctx, ctx.root, {"terrain": "forest"}), "гарь — тоже лес (группа)")
	check(not Interp.eval_trigger(ctx, ctx.root, {"terrain": "farmlands"}), "но не пашня")
	check(Interp.eval_trigger(ctx, ctx.root, {"terrain": ["hills", "forest"]}), "список местностей")
	var hist := Biomes.history_of(g, "c_sussex")
	check(hist.size() == 2 and hist[0][3] == "harold", "летопись помнит, кто менял землю")


func test_work_runs_and_has_consequences() -> void:
	var g := _game()
	var h := _holder(g, "c_sussex")
	h.gold = 500.0
	check(Biomes.blockers(g, h, "c_sussex", "drain_marsh").has("land.wrong_terrain"), "топь не осушить в лесу")
	var w: Dictionary = g.ch("william")
	check(Biomes.blockers(g, w, "c_sussex", "clear_forest").has("land.not_yours"), "чужую землю не тронуть")
	var gold := float(h.gold)
	check(Biomes.start(g, h, "c_sussex", "clear_forest"), "свести лес")
	check(float(h.gold) < gold, "работы стоят золота")
	check(Biomes.blockers(g, h, "c_sussex", "clear_forest").has("land.busy"), "вторую работу не начать")
	var ctx := ScriptContext.make(g, {"type": "province", "id": "c_sussex"})
	check(Interp.eval_trigger(ctx, ctx.root, {"has_land_work": "clear_forest"}), "условие has_land_work")
	# работа доходит до срока
	var flooded := []
	g.engine.hooks.on("land.changed", func(p): if p.cause == "clear_forest": flooded.append(p.province), 0, "test")
	var w2: Dictionary = Biomes.work_of(g, "c_sussex")
	w2.until = g.date
	Biomes.monthly(g)
	check_eq(g.terrain_of("c_sussex"), "clearing", "лес сведён — вырубка")
	check(Biomes.work_of(g, "c_sussex") == null, "работы окончены")
	check(flooded.has("c_sussex"), "перемена записана с причиной")
	var cops: Array = Data.as_array(g.state.provinces["c_sussex"].vars.get("copinions"))
	check(cops.any(func(x): return x.mod == "forest_felled"), "лесной народ ропщет")


func test_neighbors_get_flooded() -> void:
	var g := _game()
	var h := _holder(g, "c_sussex")
	h.gold = 500.0
	var lows := g.engine.neighbors("c_sussex").filter(func(n): return g.state.provinces.has(n) and g.terrain_group(g.terrain_of(n)) in ["farmlands", "plains", "wetlands"])
	check(not lows.is_empty(), "у Суссекса есть низинные соседи")
	var hits := 0
	for i in 30:
		Biomes.set_terrain(g, "c_sussex", "forest", null, "test")
		for n in lows:
			g.state.provinces[n].modifiers = g.state.provinces[n].modifiers.filter(func(m): return m.id != "flooding")
		Biomes.start(g, h, "c_sussex", "clear_forest")
		Biomes.work_of(g, "c_sussex").until = g.date
		Biomes.monthly(g)
		for n in lows:
			if g.state.provinces[n].modifiers.any(func(m): return m.id == "flooding"):
				hits += 1
		g.state.pending_events.clear()
		h.gold = 500.0
	check(hits > 0, "свёл лес — у соседей ниже разливы (%d)" % hits)


func test_nature_takes_back_clearing() -> void:
	var g := _game()
	Biomes.set_terrain(g, "c_sussex", "clearing", "harold", "clear_forest")
	var regrown := false
	for i in 200:
		Biomes._drift(g, "c_sussex")
		if g.terrain_of("c_sussex") == "forest":
			regrown = true
			break
	check(regrown, "нераспаханная вырубка зарастает лесом")
	check_eq(str(Biomes.history_of(g, "c_sussex")[-1][4]), "regrowth", "в летописи — заросло")


func test_war_burns_fields() -> void:
	var g := _game()
	var burnt := 0
	for i in 60:
		Biomes.set_terrain(g, "c_kent", "farmlands", null, "test")
		g.on_action("on_siege_won", {"type": "character", "id": "william"}, {"province": {"type": "province", "id": "c_kent"}, "defender": {"type": "character", "id": "harold"}})
		if g.terrain_of("c_kent") == "burnt":
			burnt += 1
	check(burnt > 0 and burnt < 30, "осаждающие иногда жгут поля (%d из 60)" % burnt)


func test_marsh_capital_fever() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var cap: Variant = Titles.capital_of(g, h)
	var hp := Stats.stat(g, h, "health")
	Biomes.set_terrain(g, str(cap), "wetlands", null, "test")
	g.stat_cache.clear()
	check(Stats.stat(g, h, "health") < hp, "столица в топи — лихорадка")


func test_ai_tends_land_and_save_keeps_it() -> void:
	var g := _game()
	g.state.player = null
	var started := [0]
	g.engine.hooks.on("land.work_started", func(_p): started[0] += 1, 0, "test")
	for c in g.rulers():
		c.gold = maxf(float(c.gold), 400.0)
	_to_month_end(g, 13)
	check(started[0] > 0, "ИИ берётся за свою землю (%d работ за год)" % started[0])
	Biomes.set_terrain(g, "c_sussex", "old_forest", "harold", "test")
	var res := g.engine.load_game(SaveGame.serialize(g))
	check(res.error == "", res.error)
	var g2: Game = res.game
	check_eq(g2.terrain_of("c_sussex"), "old_forest", "сохранение помнит землю")
	check_eq(Biomes.history_of(g2, "c_sussex").size(), Biomes.history_of(g, "c_sussex").size(), "и её летопись")

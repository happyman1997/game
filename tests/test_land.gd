extends TestCase
## Местность по клеткам: графство — смесь местностей (доли клеток), начало
## раскладывается из данных (поля у селения, лес по краям); доход, путь и
## полки — по долям; господствующая местность для условий; работа идёт
## участками и сама берётся за следующий, пока есть земля и золото или пока
## её не остановят; изнанка вырубки — недовольство графства и разливы у
## соседей; природа берёт своё по клеткам (вырубка зарастает); война жжёт
## часть полей; столица в топи — лихорадка; ИИ берётся за землю; сохранение
## помнит каждую клетку, старые сохранения раскладываются заново.


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


func _sum(m: Dictionary) -> float:
	var s := 0.0
	for k in m:
		s += float(m[k])
	return s


func test_mix_from_cells() -> void:
	var g := _game()
	var land := g.land()
	check(land.ready(), "ядро загружено")
	for pid in g.engine.map.provinces:
		if land.count(pid) == 0:
			check(false, "у %s нет клеток" % pid)
			return
	var m := land.mix("c_sussex")
	check(absf(_sum(m) - 1.0) < 0.001, "доли складываются в целое")
	check(m.size() >= 2, "Суссекс — не один лес: %s" % str(m))
	check_eq(g.terrain_of("c_sussex"), "forest", "господствует лес")
	check(land.share("c_sussex", "forest") >= 0.6, "лес с дремучим — больше половины")
	var ctx := ScriptContext.make(g, {"type": "province", "id": "c_sussex"})
	check(Interp.eval_trigger(ctx, ctx.root, {"terrain": "forest"}), "условие terrain — по господствующей")
	check(Interp.eval_trigger(ctx, ctx.root, {"has_terrain": "plains"}), "has_terrain — есть хоть клетка")
	check(not Interp.eval_trigger(ctx, ctx.root, {"has_terrain": "wetlands"}), "топи в Суссексе нет")
	check(Interp.eval_trigger(ctx, ctx.root, {"has_terrain": {"terrain": "forest", "above": 0.5}}), "has_terrain с долей")
	check(absf(Interp.eval_value(ctx, ctx.root, "terrain_share(forest)") - land.share("c_sussex", "forest")) < 0.001, "значение terrain_share")
	# полки и путь — по долям
	var pick: Variant = g.terrain_pick({"forest": 0.25}, "c_sussex", 0.0)
	check(absf(float(pick) - 0.25 * land.share("c_sussex", "forest")) < 0.001, "бонус полка по доле леса (%s)" % str(pick))
	check(g.terrain_num("c_sussex", "movement", 1.0) > 1.1 and g.terrain_num("c_sussex", "movement", 1.0) < 1.5, "путь по лесу — между полем и дремучим")


func test_land_changes_income() -> void:
	var g := _game()
	var before := Economy.county_tax(g, "c_sussex")
	var n := Biomes.set_terrain(g, "c_sussex", "farmlands", "harold", "test")
	check_eq(n, g.land().count("c_sussex"), "вся земля стала пашней")
	check(Economy.county_tax(g, "c_sussex") > before, "тучная пашня даёт больше, чем лес")
	check_eq(g.terrain_of("c_sussex"), "farmlands", "господствует пашня")
	# пожар — только участок леса
	Biomes.set_terrain(g, "c_sussex", "forest", null, "test")
	var burnt := Biomes.set_terrain(g, "c_sussex", "burnt_forest", null, "fire", ["forest"], 0.3)
	var share := g.land().share("c_sussex", "burnt_forest")
	check(burnt > 0 and share > 0.15 and share < 0.5, "пожар взял часть леса (%d%%)" % roundi(share * 100))
	check_eq(g.terrain_of("c_sussex"), "forest", "гарь — тоже лес (группа)")
	var hist := Biomes.history_of(g, "c_sussex")
	check(hist[0][3] == "harold" and int(hist[-1][5]) == burnt, "летопись помнит, кто и сколько клеток")


func test_work_goes_by_patches() -> void:
	var g := _game()
	var h := _holder(g, "c_sussex")
	h.gold = 500.0
	g.touch(h)
	Biomes.set_terrain(g, "c_sussex", "forest", null, "test")
	check(Biomes.blockers(g, h, "c_sussex", "drain_marsh").has("land.wrong_terrain"), "топь не осушить в лесу")
	var w0: Dictionary = g.ch("william")
	check(Biomes.blockers(g, w0, "c_sussex", "clear_forest").has("land.not_yours"), "чужую землю не тронуть")
	var gold := float(h.gold)
	check(Biomes.start(g, h, "c_sussex", "clear_forest"), "свести лес")
	check(float(h.gold) < gold, "участок стоит золота")
	var w: Dictionary = Biomes.work_of(g, "c_sussex")
	var patch := Data.as_array(w.cells)
	check_eq(patch.size(), Biomes.patch_size(g, "c_sussex", g.content.get_def("land_works", "clear_forest")), "участок — четверть графства")
	check(Biomes.blockers(g, h, "c_sussex", "clear_forest").has("land.busy"), "вторую работу не начать")
	var ctx := ScriptContext.make(g, {"type": "province", "id": "c_sussex"})
	check(Interp.eval_trigger(ctx, ctx.root, {"has_land_work": "clear_forest"}), "условие has_land_work")
	# участок дошёл до срока — клетки стали вырубкой, работа берётся за следующий
	w.until = g.date
	Biomes.monthly(g)
	for c in patch:
		check_eq(g.land().terrain_at(int(c)), "clearing", "клетка участка сведена")
	w = Biomes.work_of(g, "c_sussex")
	check(w != null and int(w.done) == 1, "работа идёт дальше — на следующий участок")
	check(not Data.as_array(w.cells).has(patch[0]), "новый участок — другие клетки")
	var cops: Array = Data.as_array(g.state.provinces["c_sussex"].vars.get("copinions"))
	check(cops.any(func(x): return x.mod == "forest_felled"), "лесной народ ропщет")
	# остановить после этого участка
	Biomes.set_repeat(g, "c_sussex", false)
	w.until = g.date
	Biomes.monthly(g)
	check(Biomes.work_of(g, "c_sussex") == null, "работа остановлена после участка")
	var share := g.land().share("c_sussex", "clearing")
	check(share > 0.3 and share < 0.8, "сведено два участка (%d%%)" % roundi(share * 100))


func test_work_ends_without_land_or_gold() -> void:
	var g := _game()
	var h := _holder(g, "c_sussex")
	h.gold = 500.0
	g.touch(h)
	Biomes.set_terrain(g, "c_sussex", "plains", null, "test")
	var cells := g.land().cells("c_sussex")
	g.land().change("c_sussex", PackedInt32Array([cells[0]]), "clearing")
	check(Biomes.start(g, h, "c_sussex", "plough"), "распахать единственную вырубку")
	Biomes.work_of(g, "c_sussex").until = g.date
	Biomes.monthly(g)
	check(Biomes.work_of(g, "c_sussex") == null, "земли больше нет — работа окончена")
	Biomes.set_terrain(g, "c_sussex", "forest", null, "test")
	check(Biomes.start(g, h, "c_sussex", "clear_forest"), "свести лес")
	h.gold = 0.0
	g.touch(h)
	Biomes.work_of(g, "c_sussex").until = g.date
	Biomes.monthly(g)
	check(Biomes.work_of(g, "c_sussex") == null, "нет золота — работа окончена")


func test_neighbors_get_flooded() -> void:
	var g := _game()
	var h := _holder(g, "c_sussex")
	var lows := g.engine.neighbors("c_sussex").filter(func(n): return g.state.provinces.has(n) and g.terrain_group(g.terrain_of(n)) in ["farmlands", "plains", "wetlands"])
	check(not lows.is_empty(), "у Суссекса есть низинные соседи")
	var hits := 0
	for i in 40:
		h.gold = 500.0
		g.touch(h)
		Biomes.set_terrain(g, "c_sussex", "forest", null, "test")
		for n in lows:
			g.state.provinces[n].modifiers = g.state.provinces[n].modifiers.filter(func(m): return m.id != "flooding")
		Biomes.start(g, h, "c_sussex", "clear_forest", false)
		Biomes.work_of(g, "c_sussex").until = g.date
		Biomes.monthly(g)
		for n in lows:
			if g.state.provinces[n].modifiers.any(func(m): return m.id == "flooding"):
				hits += 1
		g.state.pending_events.clear()
	check(hits > 0, "свёл лес — у соседей ниже разливы (%d)" % hits)


func test_nature_takes_back_clearing() -> void:
	var g := _game()
	Biomes.set_terrain(g, "c_sussex", "forest", null, "test")
	var cells := g.land().cells("c_sussex")
	g.land().change("c_sussex", PackedInt32Array([cells[0], cells[1], cells[2]]), "clearing")
	var start := g.land().share("c_sussex", "clearing")
	for i in 60:
		Biomes._drift(g, "c_sussex")
	check(g.land().share("c_sussex", "clearing") < start, "нераспаханная вырубка зарастает лесом")
	check_eq(str(Biomes.history_of(g, "c_sussex")[-1][4]), "regrowth", "в летописи — заросло")


func test_war_burns_part_of_fields() -> void:
	var g := _game()
	var burnt := 0
	var whole := 0
	for i in 60:
		Biomes.set_terrain(g, "c_kent", "farmlands", null, "test")
		g.on_action("on_siege_won", {"type": "character", "id": "william"}, {"province": {"type": "province", "id": "c_kent"}, "defender": {"type": "character", "id": "harold"}})
		var s := g.land().share("c_kent", "burnt")
		if s > 0.0:
			burnt += 1
		if s > 0.5:
			whole += 1
	check(burnt > 5 and burnt < 45, "осаждающие нередко жгут поля (%d из 60)" % burnt)
	check_eq(whole, 0, "но не всё графство разом")


func test_marsh_capital_fever() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var cap: Variant = Titles.capital_of(g, h)
	var hp := Stats.stat(g, h, "health")
	Biomes.set_terrain(g, str(cap), "wetlands", null, "test")
	g.stat_cache.clear()
	check(Stats.stat(g, h, "health") < hp, "столица в топи — лихорадка")


func test_ai_tends_land_and_save_keeps_cells() -> void:
	var g := _game()
	g.state.player = null
	var started := [0]
	g.engine.hooks.on("land.work_started", func(_p): started[0] += 1, 0, "test")
	for c in g.rulers():
		c.gold = maxf(float(c.gold), 400.0)
		g.touch(c)
	_to_month_end(g, 13)
	check(started[0] > 0, "ИИ берётся за свою землю (%d работ за год)" % started[0])
	Biomes.set_terrain(g, "c_sussex", "old_forest", "harold", "test", null, 0.5)
	var res := g.engine.load_game(SaveGame.serialize(g))
	check(res.error == "", res.error)
	var g2: Game = res.game
	check(g2.land().core.terrain_bytes() == g.land().core.terrain_bytes(), "сохранение помнит каждую клетку")
	check_eq(g2.land().mix("c_sussex"), g.land().mix("c_sussex"), "и доли графства")
	check_eq(Biomes.history_of(g2, "c_sussex").size(), Biomes.history_of(g, "c_sussex").size(), "и летопись земли")
	check(not g.state.has("land_cells"), "в живом состоянии клеток нет — они в ядре")


func test_old_save_reseeds_from_county_terrain() -> void:
	var g := _game()
	var st := g.state.duplicate(true)
	st.provinces["c_sussex"]["terrain"] = "wetlands"
	st.provinces["c_sussex"]["land_work"] = {"id": "drain_marsh", "by": "harold", "start": g.date, "until": g.date + 300, "months": 10}
	var json := JSON.stringify({"format": SaveGame.FORMAT, "version": 2, "state": st})
	var res := g.engine.load_game(json)
	check(res.error == "", res.error)
	var g2: Game = res.game
	check_eq(g2.terrain_of("c_sussex"), "wetlands", "старая местность графства — господствующая")
	check(g2.land().mix("c_sussex").size() > 1, "и разложена по клеткам")
	check(not g2.state.provinces["c_sussex"].has("terrain"), "старое поле убрано")
	check(not Data.as_array(Biomes.work_of(g2, "c_sussex").get("cells")).is_empty(), "старая работа продолжается участками")

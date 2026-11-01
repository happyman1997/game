extends TestCase
## Дороги по клеткам: сеть прокладывается в начале партии (тракты между
## столицами герцогств, тропы между соседями; через пепел — нет) и не зависит от зерна; путь
## войск — по клеткам, по тракту быстрее; работа «Проложить тракт»
## поднимает дороги графства; посад у тракта сильнее; осада портит дороги;
## сохранение помнит дороги, старое сохранение получает сеть заново.


func _game(seed := 5) -> Game:
	var g := TestEnv.engine().new_game("b1066", seed)
	g.state.player = "harold"
	return g


func _holder(g: Game, pid: String) -> Dictionary:
	return g.ch(g.state.titles[pid].holder)


func test_network_at_start() -> void:
	var g := _game()
	var land := g.land()
	var m := g.engine.map
	var missing := []
	for i in m.provinces.size():
		if m.impassable[i] == 1:
			continue
		var pid: String = m.provinces[i]
		var td: Variant = g.terrain_def(pid)
		if td != null and td.get("no_roads", false):
			check_eq(land.seat_road(pid), "", "через пепел дорог нет")
			continue
		if not m.land_neighbors.get(pid, []).is_empty() and land.seat_road(pid) == "":
			missing.append(pid)
	check(missing.size() <= 3, "почти у каждого графства с соседями по суше есть дорога у селения (без: %s)" % str(missing))
	var lv := {}
	var b: PackedByteArray = land.core.road_bytes()
	for i in b.size() / 2:
		if b[i * 2] > 0:
			lv[b[i * 2]] = int(lv.get(b[i * 2], 0)) + 1
	check(int(lv.get(1, 0)) > 500 and int(lv.get(2, 0)) > 200, "есть и тропы, и тракты: %s" % str(lv))
	var g2 := _game(9)
	check(g2.land().core.road_bytes() == land.core.road_bytes(), "сеть не зависит от зерна партии")


func test_travel_by_road_is_faster() -> void:
	var g := _game()
	var land := g.land()
	var a := "c_sussex"
	var n: String = ""
	for x in g.engine.map.land_neighbors[a]:
		if land.travel_cost(a, x) != null:
			n = x
			break
	check(n != "", "у Суссекса есть сосед по суше")
	var before: float = land.travel_cost(a, n)
	check(absf(Military.edge_cost(g, a, n) - before) < 0.001, "войска считают путь по клеткам")
	for pid in [a, n]:
		var cells := land.road_cells(pid, ["trail", "road"])
		Biomes.set_roads(g, pid, cells, "paved", null, "test")
	var after: float = land.travel_cost(a, n)
	check(after < before * 0.9, "по мостовой быстрее (%.1f → %.1f)" % [before, after])


func test_build_road_work() -> void:
	var g := _game()
	var pid := ""
	for x in ["c_sussex", "c_kent", "c_york", "c_winchester", "c_dorset", "c_devon"]:
		if not g.land().road_cells(x, ["trail"]).is_empty():
			pid = x
			break
	check(pid != "", "есть графство с тропами")
	var h := _holder(g, pid)
	h.gold = 1000.0
	g.touch(h)
	check(Biomes.works_here(g, pid).any(func(d): return d.id == "build_road"), "можно проложить тракт")
	check(Biomes.start(g, h, pid, "build_road"), "начать тракт")
	Biomes.work_of(g, pid).until = g.date
	Biomes.monthly(g)
	check(g.land().road_cells(pid, ["trail"]).is_empty(), "тропы графства стали трактом")
	check(Biomes.work_of(g, pid) == null, "дорога одна — работа окончена")
	check_eq(str(Biomes.history_of(g, pid)[-1][2]), "road", "в летописи — тракт")


func test_market_by_the_road() -> void:
	var g := _game()
	var pid := "c_winchester"
	var p: Dictionary = g.state.provinces[pid]
	if not (p.get("districts") is Dictionary) or not p.districts.has("market"):
		Districts.set_level(g, pid, "market", 1)
	var land := g.land()
	var seat := PackedInt32Array([land.seat(pid)])
	Biomes.set_roads(g, pid, seat, "trail", null, "test")
	g.month_cache.clear()
	g.day_cache.clear()
	var low := Districts.power(g, pid, "market")
	Biomes.set_roads(g, pid, seat, "paved", null, "test")
	g.month_cache.clear()
	g.day_cache.clear()
	var high := Districts.power(g, pid, "market")
	check(high > low, "посад у мостовой сильнее (%.2f → %.2f)" % [low, high])


func test_siege_breaks_roads() -> void:
	var g := _game()
	var land := g.land()
	var cells := land.road_cells("c_kent", ["trail", "road"])
	Biomes.set_roads(g, "c_kent", cells, "paved", null, "test")
	var n := Biomes.damage_roads(g, "c_kent", 1.0, "william", "war")
	check(n == cells.size(), "осада разбила мостовую (%d клеток)" % n)
	check(land.road_cells("c_kent", ["paved"]).is_empty(), "мостовой не осталось")
	var hits := 0
	for i in 20:
		Biomes.set_roads(g, "c_kent", cells, "road", null, "test")
		g.on_action("on_siege_won", {"type": "character", "id": "william"}, {"province": {"type": "province", "id": "c_kent"}, "defender": {"type": "character", "id": "harold"}})
		if not land.road_cells("c_kent", ["trail"]).is_empty():
			hits += 1
	check(hits > 10, "взятие графства портит тракт (%d из 20)" % hits)


func test_save_keeps_roads() -> void:
	var g := _game()
	var cells := g.land().road_cells("c_sussex", ["trail", "road"])
	Biomes.set_roads(g, "c_sussex", cells, "paved", null, "test")
	var res := g.engine.load_game(SaveGame.serialize(g))
	check(res.error == "", res.error)
	var g2: Game = res.game
	check(g2.land().core.road_bytes() == g.land().core.road_bytes(), "сохранение помнит дороги")
	check_eq(g2.land().seat_road("c_sussex"), "paved", "и мостовую в Суссексе")
	# сохранение без дорог (прежней версии) — сеть прокладывается заново
	SaveGame.serialize(g)
	var st := g.state.duplicate(true)
	g.land().save_into(st)
	st.land_cells.erase("roads")
	var res2 := g.engine.load_game(JSON.stringify({"format": SaveGame.FORMAT, "version": 2, "state": st}))
	var g3: Game = res2.game
	check(g3.land().seat_road("c_sussex") != "", "старое сохранение получило дороги")
	check(g3.land().core.terrain_bytes() == g.land().core.terrain_bytes(), "а земля осталась своя")

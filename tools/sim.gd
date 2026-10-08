extends SceneTree
## Безголовая симуляция для проверки баланса:
##   godot --headless --path . -s tools/sim.gd -- --years 50 --seed 1 [--verbose] [--mods core,my_mod] [--bookmark b1066]
## Печатает итоги по годам: живые персонажи, державы, войны, крупнейшие державы.


func _init() -> void:
	var a := ToolCommon.args()
	var e := ToolCommon.engine(a)
	var years := int(a.get("years", 10))
	var seed := int(a.get("seed", 1))
	var verbose: bool = a.has("verbose")
	var bm: String = a.get("bookmark", e.bookmarks()[0].id if not e.bookmarks().is_empty() else "")
	var g := e.new_game(bm, seed)
	var stats := {"deaths": 0, "wars": 0}
	e.hooks.on("character.death", func(_p): stats.deaths += 1)
	e.hooks.on("war.declared", func(_p): stats.wars += 1)
	var t0 := Time.get_ticks_msec()
	for y in years:
		var ty := Time.get_ticks_msec()
		for d in 365:
			while not g.state.pending_events.is_empty():
				g.events.choose(g.state.pending_events[0].uid, 0)
			g.state.pending_requests.clear()
			g.tick()
		var independents := g.rulers().filter(func(c): return c.liege == null)
		print("%d: персонажей %d, держав %d, войн %d, смертей %d, объявлено войн %d (%.1f с)" % [
			GameDate.parts(g.date).y, g.living().size(), independents.size(), g.state.wars.size(), stats.deaths, stats.wars,
			(Time.get_ticks_msec() - ty) / 1000.0])
		if verbose:
			var sized := independents.map(func(c): return [Titles.realm_counties(g, c).size(), c])
			sized.sort_custom(func(x, z): return x[0] > z[0])
			for item in sized.slice(0, 6):
				var c: Dictionary = item[1]
				print("    %-40s графств %3d, золото %6d" % [Titles.full_name(g, c.titles[0]), item[0], int(c.gold)])
	print("Всего: %.1f с на %d лет" % [(Time.get_ticks_msec() - t0) / 1000.0, years])
	quit()

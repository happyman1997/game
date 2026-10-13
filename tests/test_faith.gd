extends TestCase
## Единая вера Солнечного Императора: культы одной религии без священных
## войн между собой; священная война — только против еретиков.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func test_one_religion_many_cults() -> void:
	var g := _game()
	check(g.loc.raw("religion.solar") != null, "название религии")
	var used := {}
	for c in g.living():
		used[str(c.faith)] = true
	for f in g.content.all("faiths"):
		check_eq(str(f.get("religion")), "solar", "культ %s — в вере Солнечного Императора" % f.id)
		check(g.desc_of("faiths", f.id) != "", "описание культа %s" % f.id)
	for id in ["sun_rite", "wolf_cult", "ash_penitence", "ancestor_cult"]:
		check(used.has(id), "культ %s есть в мире" % id)


func _holy_targets(g: Game, r: Dictionary) -> Array:
	return Wars.available_war_targets(g, r).filter(func(t): return t.cb == "holy_war")


func test_holy_war_only_against_heretics() -> void:
	var g := _game()
	var kings: Array = g.rulers().filter(func(c): return c.liege == null)
	for r in kings:
		check(_holy_targets(g, r).is_empty(), "%s: культы не воюют друг с другом" % r.id)
	# еретик — законная цель и для единоверца
	var sven: Dictionary = g.ch("sweyn_estridsen")
	g.content.set_def("traits", "_test_heretic", {"heretic": true, "group": "_test"})
	sven.traits.append("_test_heretic")
	check(kings.any(func(r): return _holy_targets(g, r).any(func(t): return t.defender == "sweyn_estridsen")), "на еретика можно идти священной войной")
	var ctx := ScriptContext.make(g, {"type": "character", "id": "sweyn_estridsen"})
	check(Interp.eval_trigger(ctx, ctx.root, {"is_heretic": true}), "условие is_heretic")
	sven.traits.erase("_test_heretic")
	g.content.remove("traits", "_test_heretic")

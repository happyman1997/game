extends TestCase
## Фракции за закон: при выморочном праве бездетный вассал охотно идёт во
## фракцию наследных прав, принятые требования смягчают закон на ступень;
## всеобщий сбор и королевская десятина рождают свои фракции. События
## заговора: сюзерену — когда фракция собралась, вассалу-игроку —
## приглашение (вступить, отказаться или донести).


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _vassal(g: Game, liege: Dictionary) -> Dictionary:
	for v in g.vassals_of(liege.id):
		if Chars.is_adult(g, v) and v.get("prison") == null:
			return v
	return {}


func test_fief_rights_faction() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var def: Dictionary = g.content.get_def("factions", "fief_rights_faction")
	var v: Dictionary = {}
	for x in g.vassals_of(h.id):
		if Succession.alive_children(g, x).size() > 0:
			v = x
	check(not v.is_empty(), "есть вассал с детьми")
	check(not Factions.can_join(g, v, def, h), "без выморочного права фракции нет")
	Laws.change(g, h, "crown_authority_2", true)
	Laws.change(g, h, "fief_law_2", true)
	check(Factions.can_join(g, v, def, h), "при выморочном праве — можно вступить")
	var s0 := Factions.ai_join_score(g, v, def, h)
	for cid in v.children:
		var c: Variant = g.ch(cid)
		if c != null:
			c.death = g.date
	check(Factions.ai_join_score(g, v, def, h) > s0, "бездетный вступает охотнее")
	var f: Variant = Factions.create(g, "fief_rights_faction", v)
	check(f != null, "фракция создана")
	Factions.enforce_demands(g, f)
	check_eq(Laws.current(g, h, "fief_law").id, "fief_law_1", "требования приняты — выморочное право отменено")


func test_levy_and_zealots() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v := _vassal(g, h)
	Laws.change(g, h, "military_service_2", true)
	Laws.change(g, h, "church_law_2", true)
	check(Factions.can_join(g, v, g.content.get_def("factions", "levy_relief_faction"), h), "всеобщий сбор — фракция против")
	var zd: Dictionary = g.content.get_def("factions", "zealot_faction")
	check(Factions.can_join(g, v, zd, h) == (v.faith == h.faith), "ревнители — только единоверцы")
	var f: Variant = Factions.create(g, "levy_relief_faction", v)
	Factions.enforce_demands(g, f)
	check_eq(Laws.current(g, h, "military_service").id, "military_service_1", "сбор отменён")


func test_liege_learns_of_conspiracy() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v := _vassal(g, h)
	Opinion.add_opinion(g, v, h, "generic", -100)
	var f: Variant = Factions.create(g, "independence_faction", v)
	check(f != null, "фракция за независимость создана")
	var pe: Array = g.state.pending_events.filter(func(e): return e.event == "faction.0002")
	check(not pe.is_empty(), "игроку-сюзерену — событие «Заговор зреет»")


func test_vassal_invited() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var vs: Array = g.vassals_of(h.id).filter(func(x): return Chars.is_adult(g, x) and x.get("prison") == null)
	var me: Dictionary = vs[0]
	var plotter: Dictionary = vs[1]
	g.state.player = me.id
	Opinion.add_opinion(g, plotter, h, "generic", -100)
	var f: Variant = Factions.create(g, "independence_faction", plotter)
	check(f != null, "фракция создана")
	var pe: Array = g.state.pending_events.filter(func(e): return e.event == "faction.0003")
	check(not pe.is_empty(), "вассалу-игроку — приглашение")
	if not pe.is_empty():
		g.events.choose(pe[-1].uid, 2)
	check(Opinion.opinion(g, h, me) > Opinion.opinion(g, h, plotter), "донёс — сюзерен благодарен")
	check(Prison.has_imprisonment_reason(g, h, plotter), "и у него повод к темнице вожака")

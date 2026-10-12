extends TestCase
## Пепельные марки: правления, цверги, пепелище, реликвии и империя.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 11)
	g.state.player = "harold"
	return g


func test_realms_and_governments() -> void:
	var g := _game()
	check_eq(Governments.of(g, g.ch("gottfried_grandmaster")), "order", "орден")
	check_eq(Governments.of(g, g.ch("poppo_ukkena")), "people_republic", "Фрисия")
	check_eq(Governments.of(g, g.ch("ognedar_gorynichi")), "master_council", "цверги")
	check_eq(Governments.of(g, g.ch("adalbert_kronwald")), "feudal", "марка")
	# пепелище ничьё
	for c in ["c_sonnenstadt", "c_ash_waste", "c_charred_forest", "c_sun_road"]:
		check(g.state.titles[c].holder == null, c + " без владельца")
	check(g.state.titles["d_ash_heart"].holder == null, "герцогство пепелища без владельца")
	# особые постройки не занимают места
	check(Decisions.is_special_building(g, "imperial_regalia"), "регалии — особая постройка")
	check(g.state.provinces["c_kronhafen"].buildings.has("imperial_regalia"), "регалии в Кронхафене")
	check(Decisions.building_candidates(g, g.ch("adalbert_kronwald"), "c_kronhafen").all(func(it): return not it.def.get("special", false)),
		"особые постройки не строятся")
	# срок вожака из истории
	check(g.ch("poppo_ukkena").vars.has("term_start"), "у вожака Фрисии есть срок")


func test_dwarves() -> void:
	var g := _game()
	var og: Dictionary = g.ch("ognedar_gorynichi")
	check(og.traits.has("dwarf"), "цверг из истории получил расу от культуры")
	var kid := Chars.create_character(g, {"culture": "zwerg", "faith": "ancestor_cult", "age": 30, "liege": og.id})
	check(kid.traits.has("dwarf"), "новый цверг получил расу")
	check(not Chars.can_marry(g, kid, g.ch("irmgard_eisenwart")), "цверг не женится на человеке")
	# цверг стареет медленнее: 108 лет — как человек лет шестидесяти
	check(CoreSystems.effective_age(g, og) < 70.0, "долголетие цвергов")


func test_ash_attrition_and_settling() -> void:
	var g := _game()
	var w: Dictionary = g.ch("wolfram_wolfing")
	check(Wilds.wild_counties_near(g, w).has("c_ash_waste"), "Северная марка граничит с пепелищем")
	check(Wilds.attrition_at(g, "c_sonnenstadt") > 0.1, "пепельные бури")
	var a: Variant = Military.raise_army(g, w)
	a.location = "c_ash_waste"
	var before := int(a.size)
	Wilds.monthly(g)
	check(int(a.size) < before, "армия теряет людей в пепле")
	Military.disband_army(g, a.id)
	w.gold = 1000.0
	w.prestige = 1000.0
	var settle: Dictionary = g.content.get_def("decisions", "settle_ashlands")
	check(Decisions.take(g, settle, w), "заселение пепелища")
	check(Titles.domain_counties(g, w).any(func(c): return ["c_ash_waste", "c_sonnenstadt"].has(c)), "графство пепелища стало своим")


func test_crown_and_empire() -> void:
	var g := _game()
	var w: Dictionary = g.ch("wolfram_wolfing")
	Artifacts.give(g, "sun_crown", w)
	check(Stats.stat(g, w, "monthly_prestige") >= 3.0, "венец даёт престиж")
	var ad: Dictionary = g.ch("adalbert_kronwald")
	check(Wars.available_war_targets(g, ad, w.id).any(func(t): return t.cb == "crown_war"), "война за венец")
	var gm: Dictionary = g.ch(g.state.titles["k_ash_order"].holder)
	var order_cbs := Wars.available_war_targets(g, gm, w.id).map(func(t): return t.cb)
	check(order_cbs.has("ash_crusade"), "орден карает владельца венца")
	check(not order_cbs.has("claim") and not order_cbs.has("de_jure"), "орден не воюет за земли")
	# империя: Зонненштадт в домене и 20 графств
	for c in ["c_sonnenstadt", "c_kronhafen", "c_glockenfurt", "c_altenrhein", "c_silberau", "c_rosental", "c_nebelwald", "c_weinberg", "c_sternwald"]:
		Titles.transfer_title(g, c, w.id)
	w.gold = 1000.0
	w.prestige = 3000.0
	var rest: Dictionary = g.content.get_def("decisions", "restore_sun_empire")
	check(Decisions.can_take(g, rest, w), "можно возродить империю: %s" % [Decisions.blockers(g, rest, w)])
	Decisions.take(g, rest, w)
	check_eq(g.state.titles["e_sun_empire"].holder, w.id, "император")
	check(not g.state.provinces["c_sonnenstadt"].modifiers.any(func(m): return m.id == "ash_blight"), "порча снята")
	# венец — наследнику
	var heir: Variant = Succession.primary_heir(g, w)
	Succession.kill_character(g, w, "natural")
	check(heir != null and Artifacts.holder_of(g, "sun_crown") != null and Artifacts.holder_of(g, "sun_crown").id == heir.id, "венец перешёл наследнику")

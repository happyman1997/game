extends TestCase
## Смена правителя и посмертие: тень на троне, проверка нового государя,
## мощи праведника, пепел на роду, проклятие рода Наместника.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _ctx(g: Game, heir: String, pred: String) -> ScriptContext:
	return ScriptContext.make(g, {"type": "character", "id": heir}, {"predecessor": {"type": "character", "id": pred}})


func test_shadow_on_the_throne() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var heir: Dictionary = g.ch("william")
	Politics._set_dread(g, h, 66.0)
	var victim: Dictionary = g.vassals_of("harold")[0]
	Prison.imprison(g, h, victim)
	Prison.release(g, victim)
	Politics._set_dread(g, heir, 0.0)
	var ev: Dictionary = g.content.get_def("events", "succession.0010")
	var ctx := _ctx(g, "william", "harold")
	Interp.run_effect(ctx, ctx.root, ev.options[0].effect)
	check_eq(Politics.tier_level(g, heir), Politics.tier_level(g, h) - 1, "страх отца — ступенью ниже")
	check(Data.as_array(victim.vars.get("broken_by")).has("william"), "сломленные остаются сломленными")
	# распахнуть темницы
	var p: Dictionary = g.living().filter(func(c): return c.titles.is_empty() and Chars.is_adult(g, c) and c.id != "william")[0]
	Prison.imprison(g, heir, p)
	var k0 := Karma.value(heir)
	Interp.run_effect(ctx, ctx.root, ev.options[1].effect)
	check(p.get("prison") == null, "темницы распахнуты")
	check_eq(Politics.dread(heir), 0.0, "страх ушёл")
	check(Karma.value(heir) > k0, "шаг к Свету")


func test_testing_the_new_sovereign() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v: Dictionary = g.vassals_of("harold")[0]
	Chars.add_trait(g, v, "brave")
	g.events.fire("succession.0011", {"type": "character", "id": "harold"})
	var pe: Array = g.state.pending_events.filter(func(e): return e.event == "succession.0011")
	check_eq(pe.size(), 1, "дерзкий вассал проверяет нового государя")
	check(pe[0].scopes.has("challenger"), "кто бросает вызов")
	var ch: Dictionary = g.ch(pe[0].scopes.challenger.id)
	check_eq(Politics.stance(g, ch, h), "defiant", "бросает вызов дерзкий")


func test_afterlife_by_soul() -> void:
	var g := _game()
	var heir: Dictionary = g.ch("harold")
	var saint: Dictionary = g.ch("william")
	Karma.set_value(g, saint, 80.0)
	var n0 := Artifacts.items_of(g, heir).size()
	var dp0 := Data.num(g.state.dynasties.get(heir.dynasty, {}).get("prestige")) if g.state.get("dynasties") is Dictionary else 0.0
	g.on_action("on_inheritance", {"type": "character", "id": "harold"}, {"predecessor": {"type": "character", "id": "william"}})
	check(Artifacts.items_of(g, heir).size() > n0, "мощи праведника — роду")
	var sname := g.scope_name({"type": "character", "id": "william"}, "first_name")
	check(Artifacts.items_of(g, heir).any(func(it): return str(it.get("name", "")).contains(sname)), "реликварий с именем праведника")
	# пепел на роду
	var sinner: Dictionary = g.ch("philip")
	Karma.set_value(g, sinner, -80.0)
	Karma.set_value(g, heir, 0.0)
	g.on_action("on_inheritance", {"type": "character", "id": "harold"}, {"predecessor": {"type": "character", "id": "philip"}})
	check(Karma.value(heir) <= -25.0, "наследник пепельного начинает запятнанным (%.0f)" % Karma.value(heir))
	# Наместник Пепла: пепел забирает своё
	var vic: Dictionary = g.ch("sweyn_estridsen")
	Chars.add_trait(g, vic, "ash_viceroy")
	g.on_action("on_inheritance", {"type": "character", "id": "harold"}, {"predecessor": {"type": "character", "id": "sweyn_estridsen"}})
	var kin := g.living().filter(func(c): return c.dynasty == heir.dynasty)
	check(kin.all(func(c): return c.modifiers.any(func(m): return m.id == "ash_curse")), "проклятие на всём роду (%d)" % kin.size())

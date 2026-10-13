extends TestCase
## Путь Пепла (печати, договор и его тайна, Наместник, дорога назад) и
## Путь Света (обет, Живой святой, «Отмолить душу», крестовый поход).


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _choose(g: Game, ev: String, who: String, idx: int) -> void:
	g.events.fire(ev, {"type": "character", "id": who}, {}, true)
	var pe: Array = g.state.pending_events.filter(func(e): return e.event == ev)
	if pe.is_empty():
		return
	g.events.choose(pe[-1].uid, idx)


func _on_the_edge(g: Game, h: Dictionary) -> void:
	for t in ["compassionate"]:
		Chars.remove_trait(g, h, t)
	Chars.add_trait(g, h, "sadistic")
	Karma.set_value(g, h, -80.0)
	Politics._set_dread(g, h, 65.0)


func test_seals_break_from_sins() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_on_the_edge(g, h)
	for i in 40:
		Karma.add(g, h, -1.0, "murder")
	check(g.state.pending_events.any(func(e): return e.event == "ashpath.0001"), "грех на краю — шёпот Князя")


func test_ash_path() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_on_the_edge(g, h)
	var other: Dictionary = g.vassals_of("harold")[0]
	_choose(g, "ashpath.0001", "harold", 1)
	check(h.traits.has("ash_marked"), "ответил — меченый пеплом")
	check(not Chars.trait_visible(g, h, "ash_marked", other.id), "метку видят лишь посвящённые")
	check(Secrets.secrets_of(h).any(func(s): return s.type == "secret_ash_pact"), "тайна договора")
	# дар «Голос повелителя»: дерзких нет
	var bold: Dictionary = other
	Chars.add_trait(g, bold, "brave")
	check_eq(Politics.stance(g, bold, h), "defiant", "храбрец дерзок")
	_choose(g, "ashpath.0002", "harold", 1)
	check(h.traits.has("ash_pact") and h.traits.has("ash_voice"), "договор и дар")
	check_eq(Politics.stance(g, bold, h), "obedient", "перед голосом повелителя гнутся и храбрецы")
	# дорога назад до третьей печати — Пепелище
	var pil: Dictionary = g.content.get_def("decisions", "ash_pilgrimage")
	h.gold = 500.0
	check(Decisions.take(g, pil, h), "паломничество к Пепелищу")
	check(not h.traits.has("ash_marked") and not h.traits.has("ash_pact"), "Пепелище отпустило")


func test_exposed_pact_makes_heretic() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_on_the_edge(g, h)
	_choose(g, "ashpath.0001", "harold", 1)
	check(not Wars.is_heretic(g, h), "пока тайна — не еретик")
	var s: Variant = Secrets.secrets_of(h).filter(func(x): return x.type == "secret_ash_pact")[0]
	Secrets.expose(g, g.ch("william"), h, s)
	check(h.traits.has("ash_heretic") and Wars.is_heretic(g, h), "раскрытый договор — ересь")
	check(Chars.trait_visible(g, h, "ash_marked", "william"), "метку теперь видят все")


func test_viceroy() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	Chars.add_trait(g, h, "ash_viceroy")
	g.stat_cache.erase(h.id)
	Politics._set_dread(g, h, 10.0)
	Politics.monthly_char(g, h)
	check(Politics.dread(h) >= 60.0, "страх перед Наместником не ниже ужаса")
	check(Wars.is_heretic(g, h), "Наместник — еретик")
	# войско врага тает перед боем
	var army := {"owner": "william", "size": 1000, "location": h.capital}
	var mine := {"owner": "harold", "size": 1000, "location": h.capital}
	var plain := Military.army_strength(g, army, [])
	var vs := Military.army_strength(g, army, [mine])
	check(vs < plain, "войско врага тает (%d → %d)" % [plain, vs])
	var pil: Dictionary = g.content.get_def("decisions", "ash_pilgrimage")
	Karma.set_value(g, h, -80.0)
	check(not Decisions.is_shown(g, pil, h), "Наместнику дороги назад нет")


func test_light_path() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	Karma.set_value(g, h, 80.0)
	Chars.add_trait(g, h, "theologian")
	_choose(g, "lightpath.0001", "harold", 0)
	check(h.traits.has("living_saint"), "обет — Живой святой")
	# святой видит души и скрытые печати
	var w: Dictionary = g.ch("william")
	_on_the_edge(g, w)
	Chars.add_trait(g, w, "ash_marked")
	check(Karma.knows_exact(g, w, h), "святой видит чужую душу точно")
	check(Chars.trait_visible(g, w, "ash_marked", "harold"), "святой видит метку пепла")
	# отмолить душу
	h.piety = 500.0
	var def: Dictionary = g.content.get_def("interactions", "pray_for_soul")
	check(Interactions.is_shown(g, def, h, w), "можно отмолить душу")
	Interactions.execute(g, def, h, w)
	check(not w.traits.has("ash_marked"), "метка снята молитвой")
	# крестовый поход Света — на еретика, где бы он ни был
	Chars.add_trait(g, w, "ash_viceroy")
	var crus := Wars.available_war_targets(g, h).filter(func(t): return t.cb == "light_crusade")
	check(crus.any(func(t): return Data.as_array(t.counties).has(w.capital)), "крестовый поход на Наместника (и его укрывателя)")
	# тяжкий грех — и Свет уходит
	Karma.add(g, h, -40.0, "murder")
	check(not h.traits.has("living_saint"), "грех снял святость")

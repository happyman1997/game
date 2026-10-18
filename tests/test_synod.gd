extends TestCase
## Собор: созыв, голоса и их вес, голос игрока, склонение голосов, указы
## (десятина, Божий мир), анафема и примирение, отлучение тирана, канонизация;
## событие созыва и позиция сюзерена, к которой склоняются вассалы.

const HT := "d_sun_throne"


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _call(g: Game, qid: String) -> Dictionary:
	var head: Dictionary = g.ch(g.state.titles[HT].holder)
	check(Synod.call_synod(g, HT, head, qid), "Собор созван: " + qid)
	return Synod.state_of(g, HT).active


## Все голосующие обещают голосовать так (кроме цели вопроса).
func _sway_all(g: Game, a: Dictionary, vote: int) -> void:
	var head: Dictionary = g.ch(g.state.titles[HT].holder)
	for v in Synod.voters(g, head):
		if a.get("target") == null or v.c.id != a.target:
			a.sway[v.c.id] = vote
	a.erase("preview")


func _convene(g: Game) -> Dictionary:
	var head: Dictionary = g.ch(g.state.titles[HT].holder)
	return Synod.convene(g, HT, head)


func test_voters_and_player_vote() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Dictionary = g.ch(g.state.titles[HT].holder)
	var vs := Synod.voters(g, head)
	check(vs.size() >= 10, "на Соборе много голосов (%d)" % vs.size())
	check(not vs.any(func(v): return Wars.is_heretic(g, v.c)), "еретики не голосуют")
	check(not vs.any(func(v): return v.c.id == head.id), "Великий Светоч сам не голосует")
	h.piety = 2000.0
	g.stat_cache.erase(h.id)
	check(Synod.vote_weight(g, h, head) > Synod.vote_weight(g, g.ch(vs[-1].c.id), head) - 10.0, "вес голоса — по благочестию")
	var a := _call(g, "tithe")
	# за два месяца до Собора игроку приходит голосование
	g.state.date = int(a.convene) - 30
	Synod.monthly(g)
	var pe: Array = g.state.pending_events.filter(func(e): return e.event == "synod.0001")
	check(not pe.is_empty(), "игрок голосует в событии")
	if not pe.is_empty():
		g.events.choose(pe[-1].uid, 0)
	check_eq(int(a.votes.get("harold", 0)), 1, "голос игрока — «за»")


func test_tithe_decree() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Dictionary = g.ch(g.state.titles[HT].holder)
	var tax0 := Stats.stat(g, h, "tax_mult")
	var inc0 := Stats.stat(g, head, "monthly_income")
	var a := _call(g, "tithe")
	_sway_all(g, a, 1)
	var r := _convene(g)
	check(r.passed, "десятина принята (за %d, против %d)" % [r["for"], r.against])
	check(Synod.has_decree(g, h, "tithe"), "указ действует")
	g.stat_cache.clear()
	check(Stats.stat(g, h, "tax_mult") < tax0, "единоверцы отдают долю податей")
	check(Stats.stat(g, head, "monthly_income") > inc0, "Храм богатеет")
	check(Synod.state_of(g, HT).active == null and int(Synod.state_of(g, HT).next) > g.date + 2000, "следующий Собор — через годы")
	# указ истекает
	g.state.date += 21 * 365
	Synod.monthly(g)
	check(not Synod.has_decree(g, h, "tithe"), "указ истёк")


func test_anathema_and_reconcile() -> void:
	var g := _game()
	var a := _call(g, "anathema")
	a.target_faith = "wolf_cult"
	_sway_all(g, a, 1)
	var r := _convene(g)
	check(r.passed, "анафема принята")
	check(Temple.faith_heretic(g, "wolf_cult"), "Культ Волка — ересь")
	var wolf: Variant = null
	for c in g.rulers():
		if c.faith == "wolf_cult":
			wolf = c
			break
	check(wolf != null and Wars.is_heretic(g, wolf), "волчий правитель — еретик")
	# примирение с Восточным обрядом
	var gero: Dictionary = g.ch("gero_eisenwart")
	var b := _call(g, "reconcile")
	b.target_faith = "east_rite"
	_sway_all(g, b, 1)
	_convene(g)
	check(not Wars.is_heretic(g, gero), "Восточный обряд принят обратно в Свет")


func test_rejected_question() -> void:
	var g := _game()
	var a := _call(g, "peace_of_the_sun")
	_sway_all(g, a, -1)
	var r := _convene(g)
	check(not r.passed, "Собор может и отвергнуть")
	check(not Synod.has_decree(g, g.ch("harold"), "peace_of_the_sun"), "указа нет")


func test_peace_of_the_sun() -> void:
	var g := _game()
	var a := _call(g, "peace_of_the_sun")
	_sway_all(g, a, 1)
	_convene(g)
	var h: Dictionary = g.ch("harold")
	check(Synod.has_decree(g, h, "peace_of_the_sun"), "Божий мир")
	# ИИ реже воюет с единоверцами
	var other: Dictionary = g.ch("philip")
	var m: Variant = Synod._ai_war_will({"game": g, "attacker": h, "defender": other})
	check(m != null and float(m) < 1.0, "ИИ реже нападает на единоверца")
	# нарушитель теряет благочестие
	var t: Variant = null
	for x in Wars.available_war_targets(g, h):
		var d: Dictionary = g.ch(x.defender)
		if not Wars.is_heretic(g, d) and Temple.head_of(g, d) != null:
			t = x
			break
	if t != null:
		var p0 := float(h.piety)
		Wars.declare_war(g, h, t)
		check(float(h.piety) < p0, "нарушил Божий мир — грех перед Храмом")


func test_excommunicate_tyrant() -> void:
	var g := _game()
	var head: Dictionary = g.ch(g.state.titles[HT].holder)
	var tyrant: Dictionary = g.ch("philip")
	tyrant.piety = -500.0
	Politics._set_dread(g, tyrant, 95.0)
	g.stat_cache.clear()
	var a := _call(g, "excommunicate_tyrant")
	check_eq(str(a.target), "philip", "на Соборе обличают самого грозного")
	_sway_all(g, a, 1)
	_convene(g)
	check(tyrant.modifiers.any(func(m): return m.id == "cast_out_of_light"), "Собор отлучил тирана")


func test_canonize() -> void:
	var g := _game()
	var head: Dictionary = g.ch(g.state.titles[HT].holder)
	var saint: Dictionary = g.ch("malcolm")
	Karma.set_value(g, saint, 85.0)
	var ctx := ScriptContext.make(g, {"type": "character", "id": saint.id})
	Interp.run_effect(ctx, ctx.root, {"death": {"reason": "natural"}})
	var arts0: int = Artifacts.items_of(g, head).size() if g.engine.has_feature("artifacts") else 0
	var a := _call(g, "canonize")
	check_eq(str(a.target), "malcolm", "праведника предлагают канонизировать")
	_sway_all(g, a, 1)
	_convene(g)
	check(saint.flags.has("canonized"), "объявлен святым")
	if g.engine.has_feature("artifacts"):
		check(Artifacts.items_of(g, head).size() > arts0, "мощи хранит Храм")


func test_sway_interaction() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Dictionary = g.ch(g.state.titles[HT].holder)
	var a := _call(g, "tithe")
	var voter: Variant = null
	for v in Synod.voters(g, head):
		if v.c.id != h.id and Chars.is_close_family(g, h, v.c) == false and v.c.liege == h.id:
			voter = v.c
			break
	if voter == null:
		voter = Synod.voters(g, head).filter(func(v): return v.c.id != h.id)[0].c
	Opinion.add_opinion(g, voter, h, "temple_gift", 80)
	g.stat_cache.clear()
	h.gold = 1000.0
	var def: Dictionary = g.content.get_def("interactions", "synod_sway_for")
	var res := Interactions.execute(g, def, h, voter)
	check(res == "accepted" or res == "pending", "голос склоняют (%s)" % res)
	if res == "accepted":
		check_eq(int(a.sway.get(voter.id, 0)), 1, "правитель обещал голосовать «за»")


func test_call_event_and_liege_stance() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Dictionary = g.ch(g.state.titles[HT].holder)
	var a := _call(g, "tithe")
	# игрок узнаёт о созыве сразу и может объявить позицию
	var pe: Array = g.state.pending_events.filter(func(e): return e.event == "synod.0002")
	check(not pe.is_empty(), "игроку — событие созыва")
	var v: Variant = null
	for x in g.vassals_of(h.id):
		if Synod.is_voter(g, x, head) and Synod.vote_weight(g, x, head) > 0.0:
			v = x
			break
	check(v != null, "у Гарольда есть голосующий вассал")
	var p0 := Synod.preference(g, v, head, a)
	if not pe.is_empty():
		g.events.choose(pe[-1].uid, 0)
	check_eq(int(a.stances.get("harold", 0)), 1, "Гарольд объявил: «за»")
	var p1 := Synod.preference(g, v, head, a)
	check(p1 - p0 >= 7.0, "вассал склонился к слову сюзерена (%.1f → %.1f)" % [p0, p1])
	# ИИ-сюзерены с твёрдым убеждением тоже объявляют позицию
	check(a.stances.keys().any(func(id): return id != "harold"), "ИИ-сюзерены объявили позицию: %d" % a.stances.size())


func test_synod_more_often() -> void:
	var g := _game()
	check(g.def_num("synod.years_max", 15) <= 9, "Собор — не реже раза в 9 лет")
	check(Data.num(g.def_val("synod.first_years", [3, 6])[1]) <= 4, "первый — в первые 4 года")

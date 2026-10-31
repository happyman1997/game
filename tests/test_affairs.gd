extends TestCase
## Дела: свои и чужие дела видно одним списком; помощь ускоряет чужое дело
## и сближает; вред идёт проверкой и может раскрыться; в одно дело
## вмешиваются раз; послу к тебе можно помочь, путника — задержать; стройку
## — поджечь; ИИ вмешивается сам.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


## Графство в державе Гарольда у другого владельца — и его владелец.
func _vassal_county(g: Game) -> Array:
	var h: Dictionary = g.ch("harold")
	for pid in Titles.realm_counties(g, h):
		var t: Dictionary = g.state.titles[pid]
		if t.holder != null and t.holder != h.id and g.land().count(pid) > 4:
			return [pid, g.ch(t.holder)]
	return []


func _start_work(g: Game, pid: String, c: Dictionary) -> String:
	c.gold = 500.0
	for d in Biomes.works_here(g, pid):
		if Biomes.blockers(g, c, pid, d.id).is_empty() and Biomes.start(g, c, pid, d.id):
			return str(d.id)
	return ""


func test_mine_and_others() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	check(_start_work(g, "c_sussex", h) != "", "Гарольд начал работы в Суссексе")
	var vc := _vassal_county(g)
	check(not vc.is_empty(), "есть вассал с графством")
	check(_start_work(g, vc[0], vc[1]) != "", "вассал начал работы")
	var vis := Affairs.visible_to(g, h)
	check(vis.mine.any(func(a): return a.key == "work:c_sussex"), "свои работы — в своих делах")
	check(vis.others.any(func(a): return a.key == "work:" + vc[0] and a.actor == vc[1].id), "работы вассала — в чужих делах рядом")
	check(not vis.others.any(func(a): return a.kind == "scheme"), "чужих интриг не видно")


func test_help_hastens_and_endears() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var vc := _vassal_county(g)
	_start_work(g, vc[0], vc[1])
	var w: Dictionary = Biomes.work_of(g, vc[0])
	var until := int(w.until)
	var op := Opinion.opinion(g, vc[1], h)
	h.gold = 500.0
	check_eq(Affairs.meddle(g, h, "work:" + vc[0], "send_workers"), "help", "помог людьми")
	check(int(w.until) < until, "участок пойдёт быстрее (%d → %d)" % [until, int(w.until)])
	check(Opinion.opinion(g, vc[1], h) > op, "вассал запомнил добром")
	var a: Dictionary = Affairs.find(g, "work:" + vc[0])
	check(Affairs.blockers(g, h, a, g.content.get_def("interventions", "spoil_works")).has("affairs.already"), "в одно дело — один раз")


func test_hinder_by_check_and_exposure() -> void:
	var delayed := 0
	var exposed := 0
	for i in 8:
		var g := _game()
		var h: Dictionary = g.ch("harold")
		var vc := _vassal_county(g)
		_start_work(g, vc[0], vc[1])
		var w: Dictionary = Biomes.work_of(g, vc[0])
		var until := int(w.until)
		h.gold = 500.0
		h.skills.intrigue = 40
		var seen := [false]
		g.engine.hooks.on("affair.meddled", func(p): seen[0] = p.discovered, 0, "test")
		var res := Affairs.meddle(g, h, "work:" + vc[0], "spoil_works")
		check(res in ["success", "partial", "failure"], "вред — проверкой (%s)" % res)
		if int(w.until) > until:
			delayed += 1
		if seen[0]:
			exposed += 1
			check(Opinion.has_opinion_modifier(vc[1], h, "meddled_in_my_affairs"), "раскрыли — хозяин запомнил")
	check(delayed >= 6, "искусный вредитель затягивает работы (%d из 8)" % delayed)
	check(exposed <= 4, "и редко попадается (%d из 8)" % exposed)


func test_envoy_to_me_and_traveler() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	# посол к Гарольду от правителя, до которого можно дойти по суше
	var sender: Variant = null
	var agent: Variant = null
	for r in g.rulers():
		if r.id == h.id or r.liege != null:
			continue
		var home := Missions._home_cell(g, r)
		var dest := Missions._dest_cell(g, {"type": "character", "id": h.id}, home)
		if home >= 0 and dest >= 0 and not g.land().core.find_path(home, dest).is_empty():
			sender = r
			break
	check(sender != null, "есть правитель, чей посол дойдёт до Гарольда по суше")
	agent = Chars.create_character(g, {"liege": sender.id, "age": 30, "culture": sender.culture, "faith": sender.faith, "female": false})
	Missions.start(g, "embassy", agent, sender, {"type": "character", "id": h.id})
	var vis := Affairs.visible_to(g, h)
	var a: Variant = null
	for x in vis.others:
		if x.key == "mission:" + agent.id:
			a = x
	check(a != null and a.get("to_me", false), "посол к Гарольду — в чужих делах, «к вам»")
	h.gold = 500.0
	check_eq(Affairs.meddle(g, h, a.key, "honor_envoy"), "help", "принял с почётом")
	check_eq(Data.num(Missions.of(agent).get("aid")), 15.0, "послу — к проверке +15")


func test_fire_the_works() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var vc := _vassal_county(g)
	var p: Dictionary = g.state.provinces[vc[0]]
	p.construction = {"building": "market", "done": g.date + 300, "days": 300, "by": vc[1].id}
	h.gold = 500.0
	h.skills.intrigue = 40
	var done := int(p.construction.done)
	var res := Affairs.meddle(g, h, "build:" + vc[0], "fire_the_works")
	if res in ["success", "partial"]:
		check(int(p.construction.done) > done, "стройка отошла назад")
	else:
		check_eq(int(p.construction.done), done, "провал — стройка цела")


func test_ai_meddles() -> void:
	var g := _game()
	g.state.player = null
	var n := [0]
	g.engine.hooks.on("affair.meddled", func(_p): n[0] += 1, 0, "test")
	for c in g.rulers():
		c.gold = maxf(float(c.gold), 600.0)
		var dom := Titles.domain_counties(g, c)
		if not dom.is_empty():
			_start_work(g, dom[0], c)
	for m in 12:
		for c in g.rulers():
			Affairs.monthly_char(g, c)
		g.state.date += 30
	check(n[0] > 0, "ИИ вмешивается в чужие дела (%d за год)" % n[0])

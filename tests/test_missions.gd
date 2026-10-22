extends TestCase
## Поручения: кого можно отправить; посольство ко двору соседа — человек в
## отъезде (не рыцарь, не в совете), по возвращении проверка и её исход;
## погибший в пути — весть покровителю; отзыв; сын просится в мир.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _agent(g: Game, patron: Dictionary) -> Dictionary:
	for c in g.courtiers_of(patron.id):
		if Chars.is_adult(g, c) and c.get("prison") == null and Council.position_of(g, c) == null:
			return c
	var c := Chars.create_character(g, {"culture": patron.culture, "faith": patron.faith, "age": 24, "female": false})
	c.liege = patron.id
	g.mark_chars_dirty([c.id, patron.id])
	return c


func _run_months(g: Game, n: int) -> void:
	for d in n * 31:
		while not g.state.pending_events.is_empty():
			g.events.choose(g.state.pending_events[0].uid, 0)
		g.tick()


func test_who_can_go() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var a := _agent(g, h)
	check(Missions.can_go(g, "embassy", a, h), "придворный может ехать послом")
	check(not Missions.can_go(g, "embassy", h, h), "сам себя не отправишь")
	var w: Dictionary = g.ch("william")
	check(not Missions.can_go(g, "embassy", w, h), "чужой правитель — не ваш человек")
	var kid := Chars.create_character(g, {"culture": h.culture, "faith": h.faith, "age": 8, "female": false})
	kid.liege = h.id
	g.mark_chars_dirty([kid.id, h.id])
	check(not Missions.can_go(g, "embassy", kid, h), "ребёнка не отправить")


func test_embassy_round_trip() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var a := _agent(g, h)
	var def: Dictionary = g.content.get_def("interactions", "mission_embassy")
	check(Interactions.is_shown(g, def, h, a), "взаимодействие «Посольство» есть у придворного")
	var opts := Interactions.target_options(g, def, h, a)
	check(not opts.is_empty(), "есть к кому ехать")
	var tgt: Dictionary = opts[0].ref
	h.gold = 500.0
	check_eq(Interactions.execute(g, def, h, a, {"target": tgt}), "accepted", "посол отправлен")
	check(Missions.is_away(a), "посол в отъезде")
	check(not Knights.is_candidate(g, h, a), "в отъезде — не рыцарь")
	var ctx := ScriptContext.make(g, {"type": "character", "id": a.id}, {"patron": {"type": "character", "id": h.id}, "target": tgt, "agent": {"type": "character", "id": a.id}})
	var o := Checks.odds(ctx, ctx.root, g.content.get_def("missions", "embassy").check)
	check(o.parts.size() >= 2, "разбор шанса посла: основа, речистость, слава")
	var results := []
	g.engine.hooks.on("mission.ended", func(p): results.append(p.result), 0, "test")
	Missions.of(a).until = g.date
	Missions.monthly_char(g, a)
	check(not Missions.is_away(a), "посол вернулся")
	check(results.size() == 1 and results[0] in ["success", "partial", "failure"], "исход посольства: %s" % [results])
	var t: Dictionary = g.ch(tgt.id)
	check(["embassy_goodwill", "embassy_courtesy", "embassy_insult"].any(func(m): return Opinion.has_opinion_modifier(t, h, m)), "хозяин запомнил посольство")


func test_death_and_recall() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var a := _agent(g, h)
	Missions.start(g, "glory_wandering", a, h)
	var ended := []
	g.engine.hooks.on("mission.ended", func(p): ended.append(p.result), 0, "test")
	Succession.kill_character(g, a)
	check(ended.has("dead"), "погиб в пути — поручение кончилось")
	var b := _agent(g, h)
	Missions.start(g, "pilgrimage", b, h)
	var recall: Dictionary = g.content.get_def("interactions", "mission_recall")
	check(Interactions.is_shown(g, recall, h, b), "можно отозвать")
	Interactions.execute(g, recall, h, b)
	check(not Missions.is_away(b) and ended.has("recalled"), "отозван")


func test_patron_heir_takes_over() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var a := _agent(g, h)
	Missions.start(g, "pilgrimage", a, h)
	var heir: Variant = Succession.primary_heir(g, h)
	Succession.kill_character(g, h)
	if heir != null:
		check_eq(str(Missions.of(a).patron), str(heir.id), "служит наследнику")


func test_son_asks_to_see_the_world() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var son := Chars.create_character(g, {"culture": h.culture, "faith": h.faith, "age": 18, "female": false, "father": h.id})
	son.liege = h.id
	son.skills["prowess"] = 12
	son.traits.append("brave")
	g.mark_chars_dirty([son.id, h.id])
	g.state.player = null
	check(g.events.fire("mission.0020", {"type": "character", "id": h.id}), "сын просится в мир")
	check(son.vars.has("mission") or Opinion.has_opinion_modifier(son, h, "forbade_wandering"), "отпустили — или не пустили, и сын запомнил")


func test_ai_sends_people() -> void:
	var g := _game()
	g.state.player = null
	var sent := [0]
	g.engine.hooks.on("mission.started", func(_p): sent[0] += 1, 0, "test")
	_run_months(g, 12)
	check(sent[0] > 0, "ИИ отправляет людей с поручениями (%d за год)" % sent[0])

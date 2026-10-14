extends TestCase
## ИИ живёт по тем же правилам: нрав ведёт руку (жестокий сажает и казнит,
## праведный милует), события страха приходят и к ИИ, Пути открыты шире,
## а о грозных и святых соседях игроку приходят вести.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _set_traits(g: Game, c: Dictionary, add: Array, remove: Array) -> void:
	for t in remove:
		Chars.remove_trait(g, c, t)
	for t in add:
		Chars.add_trait(g, c, t)
	g.stat_cache.erase(c.id)


func _will(g: Game, id: String, actor: Dictionary, recipient: Dictionary) -> float:
	var def: Dictionary = g.content.get_def("interactions", id)
	var ctx := Interactions.context(g, def, actor, recipient)
	return Interp.eval_value(ctx, ctx.root, def.ai_will_do)


## Правитель ИИ с хотя бы одним взрослым вассалом не из семьи.
func _ai_lord(g: Game) -> Dictionary:
	for c in g.rulers():
		if g.is_player(c.id) or c.liege != null:
			continue
		var vs: Array = g.vassals_of(c.id).filter(func(v): return Chars.is_adult(g, v) and not Chars.is_close_family(g, c, v))
		if not vs.is_empty():
			return c
	return {}


func test_cruel_ai_imprisons_and_executes() -> void:
	var g := _game()
	var lord := _ai_lord(g)
	check(not lord.is_empty(), "нашёлся правитель ИИ с вассалами")
	var v: Dictionary = g.vassals_of(lord.id).filter(func(x): return Chars.is_adult(g, x) and not Chars.is_close_family(g, lord, x))[0]
	Opinion.add_opinion(g, v, lord, "tyranny", -40)
	g.stat_cache.erase("op:%s>%s" % [v.id, lord.id])
	_set_traits(g, lord, ["sadistic"], ["compassionate", "forgiving", "just", "kind"])
	var cruel := _will(g, "imprison", lord, v)
	check(cruel > 0.0, "садист сажает неугодного и без вины (%.0f)" % cruel)
	_set_traits(g, lord, ["compassionate"], ["sadistic", "callous", "wrathful", "vengeful", "paranoid"])
	check_eq(_will(g, "imprison", lord, v), 0.0, "сострадательный без вины не сажает")
	# казнь пленника: жестокий хочет, праведный — нет
	Prison.imprison(g, lord, v)
	_set_traits(g, lord, ["sadistic"], ["compassionate"])
	check(_will(g, "execute_prisoner", lord, v) > 0.0, "садист казнит пленника")
	_set_traits(g, lord, ["compassionate"], ["sadistic"])
	check_eq(_will(g, "execute_prisoner", lord, v), 0.0, "сострадательный не казнит")
	check(_will(g, "release_prisoner", lord, v) > 0.0, "праведный милует")


func test_dread_events_reach_ai() -> void:
	var g := _game()
	var lord := _ai_lord(g)
	Politics._set_dread(g, lord, 45.0)
	var def: Dictionary = g.content.get_def("events", "dread.0002")
	var ctx := ScriptContext.make(g, {"type": "character", "id": lord.id})
	check(g.events.can_fire(def, {"type": "character", "id": lord.id}, ctx), "«Дары без повода» приходят и к ИИ")
	check(g.events.fire("dread.0002", {"type": "character", "id": lord.id}), "событие страха срабатывает у ИИ")


func test_paths_open_wider() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	# Пепел: садист с пепельной душой — уже без ужаса
	_set_traits(g, h, ["sadistic"], ["compassionate"])
	Karma.set_value(g, h, -80.0)
	for i in 40:
		Karma.add(g, h, -1.0, "murder")
	check(g.state.pending_events.any(func(e): return e.event == "ashpath.0001"), "шёпот Князя садисту без ужаса")
	# Свет: ревностный с солнечной душой — без Стезы Светоча
	var g2 := _game()
	var m: Dictionary = g2.ch("harold")
	_set_traits(g2, m, ["zealous"], ["theologian", "sadistic", "callous"])
	Karma.set_value(g2, m, 80.0)
	for i in 40:
		Karma.add(g2, m, 1.0, "alms")
	check(g2.state.pending_events.any(func(e): return e.event == "lightpath.0001"), "ревностного зовёт Обет Солнцу")


func test_world_news() -> void:
	var g := _game()
	var king: Variant = null
	for c in g.rulers():
		if not g.is_player(c.id) and c.liege == null and Titles.primary_tier(g, c) >= 3:
			king = c
			break
	check(king != null, "есть король ИИ")
	var n0: int = g.state.messages.size()
	Politics._set_dread(g, king, 65.0)
	Politics._check_tier(g, king)
	var news: Array = g.state.messages.slice(n0).filter(func(m): return str(m.text).contains(Chars.full_name(g, king, false)) or str(m.text).contains(str(king.name)))
	check(not news.is_empty(), "весть об ужасе в землях короля")
	# Обет Солнцу у ИИ — весть всему миру
	var n1: int = g.state.messages.size()
	g.events.fire("lightpath.0001", {"type": "character", "id": king.id}, {}, true)
	check(king.traits.has("living_saint") or king.flags.has("declined_vow"), "ИИ ответил на зов")
	if king.traits.has("living_saint"):
		check(g.state.messages.size() > n1, "весть о Живом святом")


func test_dungeon_holds_fear_only_to_horror() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	for p in ["stern_gaze", "bloody_justice", "dungeon_dread"]:
		Lifestyles.unlock_perk(g, h, p, true)
	g.stat_cache.erase(h.id)
	var jailed := 0
	for c in g.living():
		if jailed >= 5:
			break
		if c.id != h.id and c.titles.is_empty() and Chars.is_adult(g, c) and c.get("prison") == null and not Chars.is_close_family(g, h, c):
			if Prison.imprison(g, h, c):
				jailed += 1
	check_eq(Prison.prisoners_of(g, h.id).size(), 5, "пять пленников")
	Politics._set_dread(g, h, 30.0)
	Politics.monthly_char(g, h)
	check(Politics.dread(h) > 30.0, "темница внушает страх (%.1f)" % Politics.dread(h))
	Politics._set_dread(g, h, 58.0)
	for i in 6:
		Politics.monthly_char(g, h)
	check(Politics.dread(h) <= 60.0, "темница держит лишь до ужаса (%.1f)" % Politics.dread(h))
	# у порога ступень не дрожит: месяц за месяцем — тот же ужас
	var changes := [0]
	var fn := g.engine.hooks.on("politics.dread_tier", func(p): if p.character.id == h.id: changes[0] += 1)
	for i in 12:
		Politics.monthly_char(g, h)
	g.engine.hooks.off("politics.dread_tier", fn)
	check_eq(changes[0], 0, "ступень у порога не прыгает")
	check_eq(Politics.tier_level(g, h), 3, "держится ужас")

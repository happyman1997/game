extends TestCase
## Автопилот: ИИ ведёт персонажа игрока по тем же правилам, что всех, а
## игрок остаётся игроком (его события, сообщения). Замер интереса
## (tools/fun_probe.gd) собирает показатели такой партии.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.select_player("harold")
	return g


func test_player_stays_player() -> void:
	var g := _game()
	check(g.is_player("harold") and not g.ai_controls("harold"), "без автопилота за игрока решает он сам")
	check(g.ai_controls("philip"), "за остальных — ИИ")
	g.autopilot = true
	check(g.is_player("harold") and g.ai_controls("harold"), "на автопилоте игрок остаётся игроком, но решает ИИ")
	check_eq(g.state.player_dynasty, g.ch("harold").dynasty, "род игрока запомнен")


func test_events_chosen_by_ai_chance() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var tgt := {"type": "character", "id": h.id}
	Chars.remove_trait(g, h, "ill")
	g.state.pending_events.clear()
	check(g.events.fire("health.0001", tgt, {}, true), "событие сработало")
	check(g.state.pending_events.size() == 1 and g.state.pending_events[0].event == "health.0001", "игроку — окно с выбором")
	g.state.pending_events.clear()
	g.autopilot = true
	Chars.remove_trait(g, h, "ill")
	var fired := []
	var cb := func(p): fired.append(p)
	g.engine.hooks.on("event.fired", cb)
	g.events.fire("health.0001", tgt, {}, true)
	g.engine.hooks.off("event.fired", cb)
	check(g.state.pending_events.is_empty(), "на автопилоте окно не ждёт игрока")
	check(not fired.is_empty() and fired[-1].get("option") != null, "вариант выбран")
	check(not fired.is_empty() and Data.as_array(fired[-1].get("weights")).size() >= 2, "веса вариантов видны замеру")


func test_requests_answered_by_ai() -> void:
	var g := _game()
	var def := {"id": "test_ask", "ai_accept": {"value": 10},
		"on_accept": [{"scope:recipient": {"set_flag": "test_asked"}}]}
	var philip: Dictionary = g.ch("philip")
	var h: Dictionary = g.ch("harold")
	check_eq(Interactions.execute(g, def, philip, h), "pending", "игроку — запрос")
	g.state.pending_requests.clear()
	g.autopilot = true
	check_eq(Interactions.execute(g, def, philip, h), "accepted", "на автопилоте отвечает ИИ")
	check(h.flags.has("test_asked"), "согласие исполнено")


func test_autopilot_rules_the_realm() -> void:
	var g := _game()
	check(not g.state.pending_events.is_empty(), "игрока уже ждёт окно начала партии")
	g.autopilot = true
	var probe := FunProbe.new(g, 1, 5)
	for d in 365:
		g.tick()
		probe.day()
	probe.finish()
	var h: Dictionary = g.ch("harold")
	check(g.state.pending_events.is_empty() and g.state.pending_requests.is_empty(), "ничто не ждёт ответа игрока")
	check(Lifestyles.state_of(h).focus != null, "образ жизни выбран")
	var m := probe.metrics()
	check(probe.snapshots.size() >= 2, "годовые срезы сняты")
	for k in ["novelty.distinct", "rhythm.choices_per_year", "rhythm.longest_quiet_months", "agency.deeds_per_year",
			"snowball.world_max_share", "late.hoard_months", "threat.defensive_wars"]:
		check(m.has(k), "показатель " + k)
	check(probe.windows + int(m["agency.deeds_per_year"]) + probe.call_days.size() > 0, "за год игрок что-то увидел или сделал")
	var j: Variant = JSON.parse_string(JSON.stringify(probe.to_json()))
	check(j is Dictionary, "итог сохраняется в JSON")
	if j is Dictionary:
		var again := FunProbe.from_json(j).metrics()
		check(m.keys().all(func(k): return again.has(k) and is_equal_approx(float(again[k]), float(m[k]))), "показатели пересчитываются из JSON")

extends TestCase
## Казна: всё золото идёт через Treasury.add и попадает в книгу по статьям —
## строки дохода каждый месяц, стройка, золото из скриптов по источнику;
## книга хранит 12 месяцев и даёт прогноз. ИИ копит на нужную стройку и не
## тратит отложенное на крупное.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _ledger_sum(g: Game, c: Dictionary) -> float:
	var s := 0.0
	for x in Treasury.months(g, c):
		for k in x.v:
			s += float(x.v[k])
	return s


func test_monthly_lines_and_balance() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var gold0 := float(h.gold)
	for i in 31:
		g.tick()
	var cur: Dictionary = Treasury.months(g, h)[0].v
	var all := Treasury.totals(g, h, 12, true)
	check(all.has("domain_tax") and float(all.domain_tax) > 0.0, "налоги с домена — своя статья: %s" % [all.keys()])
	check(Treasury.is_regular(h, "domain_tax"), "и она ежемесячная")
	check(absf(_ledger_sum(g, h) - (float(h.gold) - gold0)) < 0.01, "книга сходится с казной: %.2f против %.2f" % [_ledger_sum(g, h), float(h.gold) - gold0])
	check(cur is Dictionary, "текущий месяц есть")


func test_one_off_categories() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	h.gold = 1000.0
	check(Decisions.start_building(g, h, "c_winchester", "walls"), "стены заложены")
	var t := Treasury.totals(g, h)
	check(float(t.get("construction", 0.0)) < 0.0, "стройка — статья «Стройка»")
	check(not Treasury.is_regular(h, "construction"), "разовая")
	# золото из скриптов — по источнику
	var ctx := ScriptContext.make(g, {"type": "character", "id": "harold"})
	ctx.values["__src"] = "event:test.1"
	Interp.run_effect(ctx, ctx.root, {"add_gold": 25})
	check_eq(float(Treasury.totals(g, h).get("events", 0.0)), 25.0, "золото из события — «События»")
	ctx.values["__src"] = "on_action:on_siege_won"
	Interp.run_effect(ctx, ctx.root, {"add_gold": 40})
	check_eq(float(Treasury.totals(g, h).get("loot", 0.0)), 40.0, "добыча осады — «Добыча» (defines.treasury.sources)")
	# выкуп: платит один, получает другой — оба в «Выкупах»
	var w: Dictionary = g.ch("william")
	ctx.values["__src"] = "interaction:demand_ransom"
	ctx.scopes["payee"] = {"type": "character", "id": "william"}
	Interp.run_effect(ctx, ctx.root, {"pay_gold": {"target": "scope:payee", "value": 30}})
	check_eq(float(Treasury.totals(g, h).get("ransom", 0.0)), -30.0, "заплативший — в минусе по выкупам")
	check_eq(float(Treasury.totals(g, w).get("ransom", 0.0)), 30.0, "получивший — в плюсе")


func test_history_and_forecast() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	# 14 месяцев по записи в месяц, один месяц — пропущен
	for k in 15:
		g.state.date = int(g.state.date) + 31
		if k != 7:
			Treasury.add(g, h, 1.0, "events")
	var ms := Treasury.months(g, h)
	check(ms.size() <= 13, "книга помнит год и текущий месяц (%d)" % ms.size())
	check(ms.size() >= 12, "и не теряет месяцы (%d)" % ms.size())
	check(not ms[1].get("current", false) and ms[0].get("current", false), "сначала текущий, потом закрытые")
	check(ms.any(func(x): return x.v.is_empty()), "пропущенный месяц — пустой, но на месте")
	check_eq(float(Treasury.totals(g, h, 12, true).get("events", 0.0)), 12.0, "за 12 месяцев и текущий — 12 записей (одна пропущена)")
	# расход больше дохода — прогноз говорит, когда казна опустеет: долг
	# ломбарду (−2,5 в месяц) у безземельного с 10 золотыми — на 4 месяца
	var x: Variant = null
	for c in g.living():
		if c.titles.is_empty() and Chars.is_adult(g, c):
			x = c
			break
	x.gold = 10.0
	x.modifiers.append({"id": "lombard_debt", "expires": null})
	g.stat_cache.erase(x.id)
	var fc := Treasury.forecast(g, x)
	check(is_equal_approx(float(fc.monthly), -2.5), "сальдо −2,5 (%.2f)" % float(fc.monthly))
	check_eq(int(fc.months_left), 4, "казны хватит на 4 месяца")


func test_ai_saves_for_goal() -> void:
	var g := _game()
	var p: Dictionary = g.ch("philip")
	var pid := "c_paris"
	var lvl := Districts.level(g, pid, "market")
	check(lvl >= 1 and lvl < 3, "у Парижа посад можно поднять (уровень %d)" % lvl)
	var cost := 0.0
	for x in Districts.candidates(g, p, pid):
		if x.def.id == "market" and x.level == lvl + 1:
			cost = float(x.cost.gold)
	check(cost > 100.0, "подъём посада дорогой (%.0f)" % cost)
	p.gold = 50.0
	p.vars["ai_goal"] = {"kind": "district", "id": "market", "province": pid, "level": lvl + 1, "cost": cost, "since": g.date}
	g.state.provinces[pid].construction = null
	Ai._consider_building(g, p)
	check(Ai.goal_of(g, p) != null and g.state.provinces[pid].construction == null, "денег нет — копит, не строит")
	check(not Ai.can_spend(g, p, 45.0), "крупная трата не трогает отложенное")
	check(Ai.can_spend(g, p, 5.0), "мелочь можно")
	p.gold = cost + 100.0
	check(Ai.can_spend(g, p, 50.0), "когда хватает и на цель — можно")
	Ai._consider_building(g, p)
	var cons: Variant = g.state.provinces[pid].construction
	check(cons is Dictionary and cons.get("district") == "market", "накопил — поднимает посад")
	check(Ai.goal_of(g, p) == null, "цель снята")
	check(float(Treasury.totals(g, p).get("construction", 0.0)) <= -cost + 0.5, "трата — в книге как стройка")


func test_ai_goal_dropped_when_gone() -> void:
	var g := _game()
	var p: Dictionary = g.ch("philip")
	# графство не его — цель снимается
	p.vars["ai_goal"] = {"kind": "building", "id": "walls", "province": "c_winchester", "level": 0, "cost": 100.0, "since": g.date}
	Ai._consider_building(g, p)
	check(Ai.goal_of(g, p) == null or Ai.goal_of(g, p).province != "c_winchester", "чужое графство — цель снята")

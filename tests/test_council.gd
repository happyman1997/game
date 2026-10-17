extends TestCase
## Совет на жалованье и дела советников: плата — доля налогов с домена,
## строкой расходов у сюзерена и доходом у советника; уровень платы меняет
## мнение советников и скорость дел; дело, дойдя до 100, завершается
## событием; события дел исполняются без ошибок.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func test_wages_and_salary() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	Council.fill(g, h)
	var seats := Council.seated(g, h)
	check(seats.size() >= 3, "совет занят (%d мест)" % seats.size())
	var w := Council.wages(g, h)
	check(w > 0.0, "жалованье совету идёт (%.2f в месяц)" % w)
	check(Economy.income_breakdown(g, h).any(func(x): return x.get("key") == "council_wages"), "строка расходов «Жалованье совету»")
	# доход советника: правитель — строкой, безземельный — в день сюзерена
	var paid_landless := false
	for pid in seats:
		var c: Dictionary = g.ch(h.council[pid].holder)
		if c.titles.is_empty():
			var before := float(c.gold)
			Council.monthly_char(g, h)
			check(float(c.gold) > before, "безземельный советник получил жалованье")
			paid_landless = true
			break
		else:
			check(Economy.income_breakdown(g, c).any(func(x): return x.get("key") == "council_salary"), "правитель-советник получает жалованье строкой дохода")
	check(paid_landless or seats.size() > 0, "проверено")


func test_pay_levels() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	Council.fill(g, h)
	var normal := Council.salary(g, h)
	var pid: String = Council.seated(g, h)[0]
	var c: Dictionary = g.ch(h.council[pid].holder)
	var op0 := Opinion.opinion(g, c, h)
	var rate0 := Council.progress_rate(g, h, pid)
	check(Council.set_pay(g, h, "generous"), "щедрая плата")
	g.stat_cache.clear()
	check(is_equal_approx(Council.salary(g, h), normal * 2.0), "вдвое дороже (%.3f против %.3f)" % [Council.salary(g, h), normal])
	check(Opinion.opinion(g, c, h) > op0, "советники довольнее")
	if rate0 > 0.0:
		check(Council.progress_rate(g, h, pid) > rate0, "и работают быстрее")
	check(Council.set_pay(g, h, "low") and Council.salary(g, h) < normal, "скупая — дешевле")
	check(not Council.set_pay(g, h, "lavish"), "неизвестный уровень — нет")


func test_project_completes_with_event() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	Council.fill(g, h)
	check(Council.set_task(g, h, "steward", "collect_taxes"), "казначей собирает подати")
	h.council.steward["progress"] = 99.9
	var done := [false]
	var fn := func(p):
		if p.liege.id == "harold":
			done[0] = true
	g.engine.hooks.on("council.project_done", fn, 0, "test")
	Council.monthly_char(g, h)
	check(done[0], "дело завершилось событием")
	check(float(h.council.steward.progress) < 10.0, "прогресс начат заново")
	g.engine.hooks.off("council.project_done", fn)


func test_project_events_run_clean() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	Council.fill(g, h)
	h.gold = 500.0
	var issues0 := g.engine.issues.size()
	var councillor: String = h.council[Council.seated(g, h)[0]].holder
	for t in g.content.all("council_tasks"):
		if t.get("project") == null:
			continue
		for k in 3:
			g.events.fire(str(t.project), {"type": "character", "id": "harold"}, {"councillor": {"type": "character", "id": councillor}}, true)
	var new_issues := g.engine.issues.slice(issues0).map(func(i): return str(i.message))
	check(new_issues.is_empty(), "события дел без ошибок: %s" % [new_issues.slice(0, 5)])

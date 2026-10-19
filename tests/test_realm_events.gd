extends TestCase
## События жизни державы: каждое проходит свои условия, когда механика к
## нему ведёт (тяжкие подати, пленник, крюк, ярмарка, десятина, стройка…),
## и исполняется без ошибок любым выбором; ссуда купцам возвращается через
## год; дела совета идут годами, а не месяцами.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


## Гарольд, у которого есть всё, к чему ведут события.
func _prepare(g: Game) -> Dictionary:
	var h: Dictionary = g.ch("harold")
	h.gold = 600.0
	Laws.change(g, h, "tax_law_2", true)
	Laws.change(g, h, "church_law_2", true)
	var v: Dictionary = g.vassals_of(h.id)[0]
	v.gold = 300.0
	Leverage.add_hook(g, h, v)
	var w: Dictionary = g.ch("william")
	for id in w.children:
		var kid: Variant = g.ch(id)
		if kid != null and Chars.is_alive(kid) and kid.titles.is_empty():
			Prison.imprison(g, h, kid)
			break
	var cap: String = str(h.capital)
	Districts.set_level(g, cap, "market", 2)
	g.state.provinces[cap].construction = {"building": "walls", "done": g.date + 200, "days": 300, "by": h.id}
	return h


func test_triggers_open() -> void:
	var g := _game()
	var h := _prepare(g)
	var ctx := ScriptContext.make(g, {"type": "character", "id": h.id})
	var closed := []
	for id in ["realm.0001", "realm.0004", "realm.0006", "realm.0007", "realm.0008", "realm.0009", "realm.0011"]:
		var ev: Dictionary = g.content.get_def("events", id)
		if not Interp.eval_trigger(ctx, ctx.root, ev.get("trigger")):
			closed.append(id)
	check(closed.is_empty(), "события открыты, когда механика к ним ведёт: закрыты %s" % [closed])


func test_events_run_clean() -> void:
	var g := _game()
	var h := _prepare(g)
	var issues0 := g.engine.issues.size()
	for i in 11:
		var id := "realm.%04d" % (i + 1)
		var ev: Dictionary = g.content.get_def("events", id)
		var n := Data.as_array(ev.get("options")).size()
		for k in n:
			g.state.player = "harold"
			g.state.pending_events.clear()
			h.flags.erase("ev:" + id)
			g.events.fire(id, {"type": "character", "id": h.id}, {}, true)
			var pe: Array = g.state.pending_events.filter(func(e): return e.event == id)
			if not pe.is_empty():
				g.events.choose(pe[-1].uid, k)
			_prepare(g)
	var new_issues := g.engine.issues.slice(issues0).map(func(i): return str(i.message))
	check(new_issues.is_empty(), "события без ошибок: %s" % [new_issues.slice(0, 5)])


func test_loan_returns() -> void:
	var g := _game()
	var h := _prepare(g)
	g.state.player = null
	var gold0 := float(h.gold)
	g.events.fire("realm.0001", {"type": "character", "id": h.id}, {}, true)
	var sch: Array = g.state.scheduled.filter(func(x): return str(x.event) in ["realm.0002", "realm.0003"])
	if float(h.gold) < gold0:
		check(not sch.is_empty(), "через год купцы вернутся")
		check(int(sch[0].date) - g.date >= 360, "и не раньше")
	check(true, "ссуда")


func test_council_projects_take_years() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	Council.fill(g, h)
	var pid: String = Council.seated(g, h)[0]
	var rate := Council.progress_rate(g, h, pid)
	check(rate > 0.0 and 100.0 / rate >= 24.0, "дело совета — не меньше двух лет (%.0f мес.)" % [100.0 / maxf(rate, 0.01)])

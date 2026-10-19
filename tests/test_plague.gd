extends TestCase
## Мор (мод plague): переболевшее графство не заражается снова, пока не
## прошли последствия, — волна выгорает; вспышка в любом графстве домена
## игрока приходит событием с этим графством; за 30 лет мор не охватывает мир.

const PLAGUE := "res://mods/plague/scripts/main.gd"


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func test_immunity() -> void:
	var g := _game()
	var P: Variant = load(PLAGUE)
	var pid: String = Titles.domain_counties(g, g.ch("harold"))[0]
	g.state.provinces[pid].modifiers.append({"id": "plague_aftermath", "expires": g.date + 365})
	P.infect(g, pid, "bubonic_plague")
	check(not P.state_of(g).infected.has(pid), "переболевшее графство не заражается")


func test_outbreak_event_in_domain() -> void:
	var g := _game()
	var P: Variant = load(PLAGUE)
	var h: Dictionary = g.ch("harold")
	var pid: String = ""
	for c in Titles.domain_counties(g, h):
		if c != str(h.capital):
			pid = c
			break
	if pid == "":
		pid = str(h.capital)
	P.infect(g, pid, "camp_fever")
	var pe: Array = g.state.pending_events.filter(func(e): return e.event == "plague.0001")
	check(not pe.is_empty(), "вспышка в графстве домена — событие игроку")
	if not pe.is_empty():
		h.gold = 200.0
		g.events.choose(pe[-1].uid, 0)
		check(g.state.provinces[pid].modifiers.any(func(m): return m.id == "quarantine"), "карантин — в том самом графстве")


func test_waves_burn_out() -> void:
	var worst := 0
	for seed in [1, 2, 3]:
		var g := TestEnv.engine().new_game("b1066", seed)
		g.quiet = true
		var P: Variant = load(PLAGUE)
		for m in 360:
			g.state.date = int(g.state.date) + 30
			P._monthly(g)
		worst = maxi(worst, int(P.state_of(g).outbreaks))
	check(worst < 150, "мор не охватывает мир: худший мир — %d вспышек за 30 лет" % worst)

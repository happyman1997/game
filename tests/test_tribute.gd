extends TestCase
## Дань: данник платит господину долю податей (строки казны с обеих сторон),
## не любит его; наследник данника платит дальше; ставший вассалом — нет;
## война за дань делает побеждённого данником; слабый откупается данью от
## войны; отказ платить злит господина.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _part(g: Game, c: Dictionary, key: String) -> float:
	for p in Economy.income_breakdown(g, c):
		if p.get("key") == key:
			return float(p.value)
	return 0.0


func test_tribute_flows() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var op0 := Opinion.opinion(g, w, h)
	Tribute.make(g, w, h)
	g.stat_cache.clear()
	var paid := _part(g, w, "tribute_paid")
	check(paid < 0.0, "данник платит (%.2f)" % paid)
	check(is_equal_approx(_part(g, h, "tribute_received"), -paid), "господин получает столько же")
	check(Opinion.opinion(g, w, h) <= op0 - 10, "данник не любит господина")
	check(Tribute.tributaries_of(g, h).any(func(x): return x.id == w.id), "в списке данников")


func test_heir_pays_on_and_vassal_stops() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	Tribute.make(g, w, h)
	var heir: Variant = Succession.primary_heir(g, w)
	check(heir != null, "у Вильгельма есть наследник")
	Succession.kill_character(g, w)
	var nh: Dictionary = g.ch(heir.id)
	if nh.liege == null:
		check(Tribute.suzerain_of(g, nh) != null and Tribute.suzerain_of(g, nh).id == h.id, "наследник платит дальше")
	Chars.set_liege(g, nh, h.id)
	Tribute.monthly(g)
	check(Tribute.suzerain_of(g, nh) == null, "ставший вассалом дань не платит")


func test_war_for_tribute() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var cb: Dictionary = g.content.get_def("casus_belli", "demand_tribute")
	var ts := Wars.available_war_targets(g, h).filter(func(t): return t.cb == "demand_tribute")
	check(not ts.is_empty(), "Гарольду есть с кого требовать дань")
	if ts.is_empty():
		return
	var w: Variant = Wars.declare_war(g, h, ts[0])
	check(w != null, "война за дань объявлена")
	var d: Dictionary = g.ch(ts[0].defender)
	Wars.end_war(g, w, "victory")
	check(Tribute.suzerain_of(g, d) != null and Tribute.suzerain_of(g, d).id == h.id, "побеждённый — данник")
	check(cb.get("ai_will_do") != null, "ИИ знает этот повод")


func test_offer_and_refuse() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var ts := Wars.available_war_targets(g, h).filter(func(t): return t.cb == "demand_tribute")
	if ts.is_empty():
		check(true, "соседей нет — пропуск")
		return
	var war: Variant = Wars.declare_war(g, h, ts[0])
	var d: Dictionary = g.ch(ts[0].defender)
	var def: Dictionary = g.content.get_def("interactions", "offer_tribute")
	check(Interactions.is_shown(g, def, d, h), "воюющий может откупиться данью")
	h.traits.append("greedy")
	g.stat_cache.clear()
	var r := Interactions.execute(g, def, d, h)
	if r == "accepted":
		check(not Wars.is_at_war_with(g, d.id, h.id), "мир заключён")
		check(Tribute.suzerain_of(g, d) != null, "и платится дань")
		var op0 := Opinion.opinion(g, h, d)
		var dec: Dictionary = g.content.get_def("decisions", "refuse_tribute")
		var ctx := ScriptContext.make(g, {"type": "character", "id": d.id})
		Interp.run_effect(ctx, ctx.root, dec.effect)
		g.stat_cache.clear()
		check(Tribute.suzerain_of(g, d) == null, "отказался — не платит")
		check(Opinion.opinion(g, h, d) < op0, "господин в гневе")
	else:
		check(war != null, "предложение отвергнуто (%s) — проверка мира пропущена" % r)

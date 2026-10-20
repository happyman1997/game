extends TestCase
## Формы службы вассала: ратная — больше войск, меньше податей; денежная —
## наоборот; храбрый и умелый в войне охотнее соглашается на ратную, трус —
## на денежную; возврат к обычной службе не обижает и не радует.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _fresh(g: Game) -> void:
	g.stat_cache.clear()
	g.month_cache.clear()
	g.day_cache.clear()


func test_sword_and_coin() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v: Dictionary = g.vassals_of(h.id)[0]
	var tax0 := Economy.vassal_tax_to(g, h, v)
	var lev0 := Economy.vassal_levy_to(g, h, v)
	Politics.set_obligation(g, v, "sword_service")
	_fresh(g)
	check(Economy.vassal_levy_to(g, h, v) > lev0 and Economy.vassal_tax_to(g, h, v) < tax0, "ратная служба: войск больше, податей меньше")
	Politics.set_obligation(g, v, "coin_service")
	_fresh(g)
	check(Economy.vassal_tax_to(g, h, v) > tax0 and Economy.vassal_levy_to(g, h, v) < lev0, "денежная: податей больше, войск меньше")


func test_who_agrees() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v: Dictionary = g.vassals_of(h.id)[0]
	var sword: Dictionary = g.content.get_def("interactions", "ask_sword_service")
	var coin: Dictionary = g.content.get_def("interactions", "ask_coin_service")
	v.traits = v.traits.filter(func(t): return t not in ["brave", "craven", "content", "greedy"])
	v.traits.append("brave")
	g.stat_cache.clear()
	var brave_sword := float(Interactions.acceptance(g, sword, h, v).total)
	var brave_coin := float(Interactions.acceptance(g, coin, h, v).total)
	v.traits.erase("brave")
	v.traits.append("craven")
	g.stat_cache.clear()
	var craven_sword := float(Interactions.acceptance(g, sword, h, v).total)
	var craven_coin := float(Interactions.acceptance(g, coin, h, v).total)
	check(brave_sword > craven_sword, "храбрый охотнее идёт на ратную службу (%.0f против %.0f)" % [brave_sword, craven_sword])
	check(craven_coin > brave_coin, "трус охотнее откупается (%.0f против %.0f)" % [craven_coin, brave_coin])


func test_restore_neutral() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v: Dictionary = g.vassals_of(h.id)[0]
	Politics.set_obligation(g, v, "coin_service")
	var op0 := Opinion.opinion(g, v, h)
	var def: Dictionary = g.content.get_def("interactions", "restore_obligations")
	check_eq(Interactions.execute(g, def, h, v), "accepted", "вернули обычную службу")
	g.stat_cache.clear()
	check_eq(Politics.obligation_of(g, v).id, "standard", "служба обычная")
	check(absi(Opinion.opinion(g, v, h) - op0) <= 5, "без обид и благодарностей (кроме самой выгоды денежной службы)")

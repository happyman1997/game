extends TestCase
## Применения крюков: предложения «по крюку» видны только при крюке на
## получателя, принимаются без отказа и расходуют крюк (сильный — уходит на
## перерыв); золото должника идёт в книгу статьёй «Крюки»; ополчение
## одалживается на два года; по крюку должник выходит из фракции; ИИ сам
## пользуется крюками.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _vassal(g: Game, liege: Dictionary) -> Dictionary:
	for v in g.vassals_of(liege.id):
		if Chars.is_adult(g, v) and v.get("prison") == null:
			return v
	return {}


func test_demand_gold_weak_hook() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v := _vassal(g, h)
	check(not v.is_empty(), "у Гарольда есть вассал")
	var def: Dictionary = g.content.get_def("interactions", "hook_demand_gold")
	check(not Interactions.is_shown(g, def, h, v), "без крюка — не видно")
	Leverage.add_hook(g, h, v)
	v.gold = 300.0
	check(Interactions.is_shown(g, def, h, v), "с крюком — видно")
	check(Interactions.acceptance(g, def, h, v).auto, "отказать нельзя")
	var hg := float(h.gold)
	var op0 := Opinion.opinion(g, v, h)
	check_eq(Interactions.execute(g, def, h, v), "accepted", "исполнено")
	check(is_equal_approx(float(h.gold) - hg, 99.0), "треть казны должника (%.1f)" % [float(h.gold) - hg])
	check(is_equal_approx(float(v.gold), 201.0), "у должника убыло")
	check(is_equal_approx(float(Treasury.totals(g, h).get("hooks", 0.0)), 99.0), "в книге — статья «Крюки»")
	check(Leverage.hook_on(g, h, v.id) == null, "слабый крюк израсходован")
	check(not Interactions.is_shown(g, def, h, v), "и предложение снова скрыто")
	check(Opinion.opinion(g, v, h) < op0, "должник обижен")


func test_strong_hook_cooldown_and_levies() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v := _vassal(g, h)
	Leverage.add_hook(g, h, v, true)
	var def: Dictionary = g.content.get_def("interactions", "hook_demand_levies")
	check_eq(Interactions.execute(g, def, h, v), "accepted", "ополчение затребовано")
	g.stat_cache.clear()
	check(v.modifiers.any(func(m): return m.id == "levies_lent"), "у должника — «Ополчение отдано»")
	check(h.modifiers.any(func(m): return m.id == "levies_borrowed"), "у вас — «Чужое ополчение»")
	check(Leverage.hook_on(g, h, v.id) != null, "сильный крюк остаётся")
	check(not Interactions.blockers(g, def, h, v).is_empty(), "но уходит на перерыв")


func test_leave_faction() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v := _vassal(g, h)
	var def: Dictionary = g.content.get_def("interactions", "demand_leave_faction")
	var f := {"id": g.new_id("fac"), "type": g.content.all("factions")[0].id, "target": h.id, "leader": v.id, "members": [v.id], "claimant": null, "discontent": 0.0, "created": g.date, "ultimatum": false}
	g.state.factions[f.id] = f
	Leverage.add_hook(g, h, v)
	check(Interactions.is_shown(g, def, h, v), "член фракции против вас — видно")
	check(Interactions.hook_available(g, def, h, v), "можно надавить крюком")
	check_eq(Interactions.execute(g, def, h, v, {"use_hook": true}), "accepted", "исполнено")
	check(Leverage.hook_on(g, h, v.id) == null, "крюк израсходован")
	check(Factions.faction_of(g, v) == null, "должник вышел из фракции")


func test_ai_uses_hooks() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var v := _vassal(g, h)
	v.gold = 400.0
	h.gold = 10.0
	Leverage.add_hook(g, h, v)
	var used := [false]
	var fn := func(p):
		if p.interaction == "hook_demand_gold" and p.actor == h.id:
			used[0] = true
	g.engine.hooks.on("interaction", fn, 0, "test")
	for k in 40:
		if used[0]:
			break
		Ai._consider_interactions(g, h)
	g.engine.hooks.off("interaction", fn)
	check(used[0], "бедный ИИ требует золото по крюку")
	check(Leverage.hook_on(g, h, v.id) == null, "крюк израсходован")

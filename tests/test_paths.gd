extends TestCase
## Стези с развилкой: вершине хватает любой из веток, вторая ветка дороже;
## правила бывших призваний живут в перках (Реформатор, Объединитель), а
## торговый договор и посредничество открыты любому правителю.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _perks(g: Game, c: Dictionary, ids: Array) -> void:
	for pid in ids:
		Lifestyles.unlock_perk(g, c, pid, true)
	g.stat_cache.erase(c.id)
	g.month_cache.erase("lifestyle:" + c.id)


func test_apex_by_either_branch() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var apex: Dictionary = g.content.get_def("perks", "iron_fist")
	_perks(g, h, ["stern_gaze", "bloody_justice"])
	check(not Lifestyles.requirements_met(g, h, apex), "без конца ветки вершина закрыта")
	_perks(g, h, ["scourge"])
	check(Lifestyles.requirements_met(g, h, apex), "ветка «Кровь» ведёт к вершине")
	var h2: Dictionary = g.ch("william")
	_perks(g, h2, ["stern_gaze", "dungeon_dread", "menace"])
	check(Lifestyles.requirements_met(g, h2, apex), "ветка «Темница» — тоже")


func test_second_branch_costs_more() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_perks(g, h, ["stern_gaze", "bloody_justice"])
	var same := Lifestyles.perk_cost(g, h, "martial_lifestyle", g.content.get_def("perks", "scourge"))
	var other := Lifestyles.perk_cost(g, h, "martial_lifestyle", g.content.get_def("perks", "dungeon_dread"))
	check(other > same, "вторая ветка дороже (%d против %d)" % [other, same])
	var trees := Lifestyles.trees_of(g, "martial_lifestyle")
	var ty: Array = trees.filter(func(t): return t.tree == "tyranny")
	check(ty.size() == 1 and ty[0].branches.size() == 2 and ty[0].apex.size() == 1, "у Тирана корень, две ветки и вершина")


func test_every_core_path_branches() -> void:
	var g := _game()
	for l in ["diplomacy_lifestyle", "martial_lifestyle", "stewardship_lifestyle", "intrigue_lifestyle", "learning_lifestyle"]:
		for t in Lifestyles.trees_of(g, l):
			check(t.root.size() == 1 and t.branches.size() == 2 and t.apex.size() == 1, "стезя %s ветвится" % t.tree)
			for b in t.branches:
				check(g.loc.raw("perk_branch.%s_%s" % [t.tree, b]) != null, "название ветки %s_%s" % [t.tree, b])


func test_reformer_calms_vassals() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	check_eq(Stats.raw_stat(g, h, "law_no_resentment"), 0.0, "без перка законы обижают")
	_perks(g, h, ["efficient_rule", "tax_collectors", "reformer"])
	check(Stats.raw_stat(g, h, "law_no_resentment") > 0.0, "Реформатор: законы не обижают вассалов")


func test_unifier_wins_hearts() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	_perks(g, h, ["regal_bearing", "peacemaker", "unifier"])
	var ctx := ScriptContext.make(g, {"type": "character", "id": h.id}, {"enemy": {"type": "character", "id": w.id}})
	g.on_action("on_war_won", ctx.root, ctx.scopes)
	check(Opinion.has_opinion_modifier(w, h, "respects_unifier"), "побеждённый уважает Объединителя")


func test_statecraft_open_to_all() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var pact: Dictionary = g.content.get_def("interactions", "trade_pact")
	check(Interactions.is_shown(g, pact, h, w), "торговый договор — любому правителю")
	var arch: Dictionary = g.content.get_def("decisions", "search_archives")
	check(Decisions.is_shown(g, arch, h), "архивы — любому правителю")
	# посредничество слушают охотнее, если посредник речист
	var med: Dictionary = g.content.get_def("interactions", "mediate_peace")
	h.skills["diplomacy"] = 4
	g.stat_cache.clear()
	var low := float(Interactions.acceptance(g, med, h, w).total)
	h.skills["diplomacy"] = 20
	g.stat_cache.clear()
	var high := float(Interactions.acceptance(g, med, h, w).total)
	check(high > low, "красноречие посредника помогает (%.0f против %.0f)" % [high, low])

extends TestCase
## Ключи: вершинное действие видно всем, но заперто, пока нет ни одного
## ключа; к нему ведёт несколько дорог (перк, страх, деяния, вещь). Базовые
## действия открыты всем: условия займа и исход подкупа — от того, кто берётся.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _fresh(g: Game) -> void:
	g.stat_cache.clear()
	g.month_cache.clear()
	g.day_cache.clear()


func _locked(g: Game, def: Dictionary, c: Dictionary) -> bool:
	var ctx := Decisions.context(g, c)
	return not Keys.opened(ctx, ctx.root, def)


func test_execution_has_many_keys() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var def: Dictionary = g.content.get_def("decisions", "public_execution")
	check(Decisions.is_shown(g, def, h), "казнь видна и без перка")
	check(_locked(g, def, h), "но заперта")
	var bl := Decisions.blockers(g, def, h)
	check(not bl.is_empty() and str(bl[0]).contains("«"), "в причинах — список ключей: %s" % [bl])
	check(not Decisions.can_take(g, def, h), "ИИ не возьмёт без ключа")
	# страх — ключ
	Politics.add_dread(g, h, 100)
	_fresh(g)
	check(not _locked(g, def, h), "ужас открывает казнь")
	# деяния — тоже ключ
	var w: Dictionary = g.ch("william")
	check(_locked(g, def, w), "Вильгельм пока без ключа")
	Deeds.record(g, w, "executions", 3)
	check(not _locked(g, def, w), "три казни за жизнь — ключ")
	# и перк
	var t: Dictionary = g.ch("tostig")
	Lifestyles.unlock_perk(g, t, "bloody_justice", true)
	check(not _locked(g, def, t), "«Кровавый суд» — ключ")


func test_banner_opens_muster() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var def: Dictionary = g.content.get_def("decisions", "grand_muster")
	h.prestige = 0.0
	_fresh(g)
	check(_locked(g, def, h), "смотр заперт")
	Artifacts.create(g, "banner", "common", h)
	_fresh(g)
	check(not _locked(g, def, h), "боевое знамя — ключ к смотру")


func test_loan_terms_depend_on_who() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var loan: Dictionary = g.content.get_def("decisions", "take_loan")
	check(Decisions.is_shown(g, loan, h), "заём открыт всем")
	check(Decisions.take(g, loan, h), "заём взят")
	var harsh: bool = h.modifiers.any(func(m): return m.id == "loan_debt_harsh")
	var w: Dictionary = g.ch("william")
	Lifestyles.unlock_perk(g, w, "great_administrator", true)
	check(Decisions.take(g, loan, w), "казначей тоже берёт")
	check(harsh or h.modifiers.any(func(m): return m.id == "lombard_debt"), "без связей — кабала или обычные (менялы в домене)")
	check(w.modifiers.any(func(m): return m.id == "loan_debt_fair"), "Великому казначею — льготные")
	check(not Decisions.can_take(g, loan, w), "второй заём — после первого")


func test_open_actions_need_no_perk() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v: Dictionary = g.vassals_of(h.id)[0]
	for id in ["intimidate", "bribe"]:
		check(Interactions.is_shown(g, g.content.get_def("interactions", id), h, v), "«%s» — открыто всем" % id)
	check(Decisions.is_shown(g, g.content.get_def("decisions", "royal_progress"), h), "объезд — открыт всем")


func test_honest_refuse_bribes() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var bribe: Dictionary = g.content.get_def("interactions", "bribe")
	var v: Dictionary = g.vassals_of(h.id)[0]
	v.traits = v.traits.filter(func(t): return t != "greedy")
	v.traits.append("honest")
	_fresh(g)
	var ctx := ScriptContext.make(g, {"type": "character", "id": h.id}, {"actor": {"type": "character", "id": h.id}, "recipient": {"type": "character", "id": v.id}})
	var spec: Dictionary = Interp.flatten_effects(bribe.on_accept)[0][1]
	var o := Checks.odds(ctx, ctx.root, spec)
	check(o.success <= 10.0, "честного не подкупить (%.0f%%)" % o.success)

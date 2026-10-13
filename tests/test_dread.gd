extends TestCase
## Грозная слава: ступени страха и их правила, кто боится (покорные,
## сломленные, дерзкие), ходоки из графств, черта «Садист».


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _set_dread(g: Game, c: Dictionary, v: float) -> void:
	Politics._set_dread(g, c, v)


func test_tiers_and_their_rules() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	check_eq(Politics.tiers(g).size(), 5, "пять ступеней")
	check_eq(Politics.tier_level(g, h), 0, "в начале — спокойствие")
	check_eq(Politics.complaint_mult(g, h), 1.0, "жалобы идут свободно")
	var tax0 := Stats.stat(g, h, "vassal_tax_mult")
	_set_dread(g, h, 45)
	check_eq(g.content.get_def("dread_tiers", Politics.tier_of(g, h).id).id, "fear", "45 — страх")
	check(Stats.stat(g, h, "vassal_tax_mult") > tax0, "при страхе вассалы платят исправнее")
	check(absf(Politics.complaint_mult(g, h) - 0.25) < 0.01, "жалобы вчетверо реже")
	var ctx := ScriptContext.make(g, {"type": "character", "id": "harold"})
	check(Interp.eval_trigger(ctx, ctx.root, {"dread_tier": ">= unease"}), "условие dread_tier: >= unease")
	check(not Interp.eval_trigger(ctx, ctx.root, {"dread_tier": "horror"}), "не ужас")
	Interp.run_effect(ctx, ctx.root, {"raise_dread_tier": 1})
	check(Interp.eval_trigger(ctx, ctx.root, {"dread_tier": "horror"}), "эффект raise_dread_tier: ступенью выше")
	check_eq(Politics.complaint_mult(g, h), 0.0, "при ужасе ходоков нет")
	# террор приносит прозвище «Грозный»
	h.nickname = null
	h.vars.erase("nick_id")
	_set_dread(g, h, 90)
	check_eq(str(h.vars.get("nick_id")), "terrible", "прозвище «Грозный»")
	# Государь слушает народ и при опасении
	_set_dread(g, h, 25)
	Lifestyles.unlock_perk(g, h, "regal_bearing", true)
	g.stat_cache.erase(h.id)
	check_eq(Politics.complaint_mult(g, h), 1.0, "Государю жалуются и при опасении")


func test_who_fears() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_set_dread(g, h, 30)
	var vs: Array = g.vassals_of("harold").filter(func(v): return Politics.stance(g, v, h) == "obedient")
	check(not vs.is_empty(), "есть покорный вассал")
	var v: Dictionary = vs[0]
	check_eq(Politics.felt_level(g, v), 1, "покорный чувствует опасение")
	# дерзкий: храбрец не боится
	Chars.add_trait(g, v, "brave")
	check_eq(Politics.stance(g, v, h), "defiant", "храбрый — дерзкий")
	check_eq(Politics.fear_of_liege(g, v), 0.0, "дерзкий не боится")
	Chars.remove_trait(g, v, "brave")
	# сломленный: побывал в темнице — боится сильнее и во фракции не идёт
	Prison.imprison(g, h, v)
	Prison.release(g, v)
	check_eq(Politics.stance(g, v, h), "broken", "после темницы — сломленный")
	check(Politics.fear_of_liege(g, v) > Politics.dread(h), "сломленный боится сильнее")
	check_eq(Politics.felt_level(g, v), 2, "сломленный чувствует ступенью выше")
	var fdef: Dictionary = g.content.get_def("factions", "independence_faction")
	check(not Factions.can_join(g, v, fdef, h), "сломленный не вступает во фракции")
	# кровник казнённого — дерзкий
	var w: Dictionary = vs[1] if vs.size() > 1 else vs[0]
	if w.id != v.id:
		Opinion.add_opinion(g, w, h, "executed_relative")
		check_eq(Politics.stance(g, w, h), "defiant", "кровник казнённого — дерзкий")


func test_factions_under_fear() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var fdef: Dictionary = g.content.get_def("factions", "independence_faction")
	var vs: Array = g.vassals_of("harold").filter(func(v): return Politics.stance(g, v, h) == "obedient" and Factions.can_join(g, v, fdef, h))
	check(vs.size() >= 2, "есть покорные вассалы")
	check(Factions.can_create(g, vs[0], fdef, h), "при спокойствии фракцию может основать любой")
	_set_dread(g, h, 25)
	check(not Factions.can_create(g, vs[0], fdef, h), "при опасении покорный не зачинает фракцию")
	check(Factions.can_join(g, vs[0], fdef, h), "но вступить может")
	# террор: фракции распадаются, остаются дерзкие
	_set_dread(g, h, 0)
	var f: Variant = Factions.create(g, "independence_faction", vs[0])
	check(f != null, "фракция создана")
	Factions.join(g, vs[1], f)
	var bold: Dictionary = vs[1]
	Chars.add_trait(g, bold, "brave")
	_set_dread(g, h, 90)
	Politics.monthly_char(g, h)
	check(Factions.faction_of(g, vs[0]) == null, "покорный покинул фракцию при терроре")
	check(Factions.faction_of(g, bold) != null, "дерзкий остался")


func test_petitioners_from_county() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var cid: String = Titles.domain_counties(g, h).filter(func(x): return x != h.capital)[0]
	Populace.add_county_opinion(g, cid, "emergency_taxes_levied", -40)
	Populace._forget(g, cid)
	check(Populace.opinion(g, cid) <= -10, "графство недовольно (%d)" % Populace.opinion(g, cid))
	check_eq(Populace.grievance(g, cid), "taxes", "причина — подати")
	check_eq(Populace.complaining_county(g, h), cid, "ходоки придут из него")
	var pctx := ScriptContext.make(g, {"type": "province", "id": cid})
	check(Interp.eval_trigger(pctx, pctx.root, {"county_grievance": "taxes"}), "условие county_grievance")
	# ходоки: событие игроку
	g.on_action("on_county_complaint", {"type": "character", "id": "harold"}, {"province": {"type": "province", "id": cid}})
	var pe: Array = g.state.pending_events.filter(func(e): return e.event == "populace.0010")
	check_eq(pe.size(), 1, "событие «Ходоки из графства»")
	var op0 := Populace.opinion(g, cid)
	g.events.choose(pe[0].uid, 0)
	Populace._forget(g, cid)
	check(Populace.opinion(g, cid) > op0, "выслушанное графство довольнее")
	check(g.state.provinces[cid].modifiers.any(func(m): return str(m.id).begins_with("tax_relief")), "подати облегчены")
	check(Deeds.count(h, "judgments") >= 1, "суд записан в летопись")
	# обещать дважды — обманутые надежды
	var ctx := ScriptContext.make(g, {"type": "character", "id": "harold"}, {"province": {"type": "province", "id": cid}})
	var opt: Dictionary = g.content.get_def("events", "populace.0010").options[2]
	Interp.run_effect(ctx, ctx.root, opt.effect)
	Interp.run_effect(ctx, ctx.root, opt.effect)
	check(Data.as_array(g.state.provinces[cid].vars.get("copinions")).any(func(e): return e.mod == "broken_promises"), "второе обещание — обманутые надежды")
	# при ужасе ходоки не приходят
	_set_dread(g, h, 65)
	g.state.provinces[cid].vars.erase("complaint_cd")
	for i in 40:
		Populace.monthly_char(g, h)
	check_eq(g.state.pending_events.filter(func(e): return e.event == "populace.0010").size(), 0, "при ужасе жалоб нет")


func test_sadist() -> void:
	var g := _game()
	var d: Variant = g.content.get_def("traits", "sadistic")
	check(d != null and d.category == "personality", "садист — обычная черта характера")
	check(Data.as_array(d.opposites).has("compassionate"), "противоположность сострадательному")
	var h: Dictionary = g.ch("harold")
	for t in ["compassionate", "forgiving", "just"]:
		Chars.remove_trait(g, h, t)
	Chars.add_trait(g, h, "sadistic")
	check(Personality.stress_for(g, h, "execute_prisoner") < 0.0, "казнь садисту в радость")
	check(Personality.stress_for(g, h, "release_prisoner") > 0.0, "милость тяготит")
	check(Personality.stress_for(g, h, "drive_away_petitioners") < 0.0, "прогнать ходоков — по душе")

extends TestCase
## Детство и воспитание, регентство, династия: известность, наследия, глава
## рода, младшие ветви, лишение наследства.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _run_months(g: Game, months: int) -> void:
	for _i in months * 30:
		g.state.pending_events.clear()
		g.state.pending_requests.clear()
		g.tick()


func test_childhood_and_guardian() -> void:
	var g := _game()
	var will: Dictionary = g.ch("william")
	var kid := Chars.create_character(g, {"culture": "norman", "faith": "catholic", "age": 7, "female": false, "father": will.id, "liege": will.id, "dynasty": will.dynasty})
	# характер складывается к совершеннолетию
	var personality: Array = kid.traits.filter(func(t): return g.content.get_def("traits", t).get("category") == "personality")
	check(personality.is_empty(), "у ребёнка нет черт характера")
	Upbringing.monthly_char(g, kid)
	check(Upbringing.childhood_trait(g, kid) != null, "детская черта в возрасте воспитания")
	check(Upbringing.focus_of(g, kid) != null, "направление воспитания по склонности")
	check(Upbringing.in_education(g, kid), "семилетний — в учении")
	check(Upbringing.can_manage(g, will, kid), "отец-правитель распоряжается воспитанием")
	# опекун: кандидаты отсортированы по навыку в направлении
	Upbringing.set_focus(g, kid, "martial")
	var cands := Upbringing.guardian_candidates(g, will, kid)
	check(not cands.is_empty(), "есть кандидаты в опекуны")
	if cands.size() > 1:
		check(Stats.skill(g, cands[0], "martial") >= Stats.skill(g, cands[1], "martial"), "кандидаты по навыку")
	var no_g := Upbringing.monthly_gain(g, kid)
	Upbringing.set_guardian(g, kid, cands[0])
	check(Upbringing.guardian_of(g, kid) == cands[0], "опекун назначен")
	check(Upbringing.wards_of(g, cands[0]).has(kid), "ребёнок среди воспитанников")
	check(Upbringing.monthly_gain(g, kid) > no_g, "с опекуном учение быстрее")
	check(Opinion.opinion(g, kid, cands[0]) > Opinion.opinion(g, kid, g.ch("harold")) - 100, "мнение считается")
	# скриптом: триггеры и эффекты
	var ctx := ScriptContext.make(g, {"type": "character", "id": kid.id})
	check(Interp.eval_trigger(ctx, ctx.root, {"has_guardian": true, "education_focus": "martial", "in_education": true}), "триггеры воспитания")
	Interp.run_effect(ctx, ctx.root, {"add_education_points": 30})
	check(Upbringing.points_of(g, kid) >= 30.0, "эффект add_education_points")


func test_coming_of_age_education() -> void:
	var g := _game()
	var will: Dictionary = g.ch("william")
	var kid := Chars.create_character(g, {"culture": "norman", "faith": "catholic", "age": 15, "female": false, "father": will.id, "liege": will.id, "dynasty": will.dynasty})
	Upbringing.monthly_char(g, kid)
	Upbringing.set_focus(g, kid, "stewardship")
	kid.vars["edu_points"] = 400.0
	var gdn: Dictionary = Upbringing.guardian_candidates(g, will, kid)[0]
	Upbringing.set_guardian(g, kid, gdn)
	# вырос — через месяц после шестнадцатилетия
	kid.birth = g.date - 16 * GameDate.DAYS_PER_YEAR - 10
	CoreSystems._demography_char(g, kid)
	check(kid.flags.has("adult"), "совершеннолетие отмечено")
	check(kid.traits.has("education_stewardship_4"), "много очков — высший уровень образования в направлении")
	check(Upbringing.childhood_trait(g, kid) == null, "детская черта ушла")
	var personality: Array = kid.traits.filter(func(t): return g.content.get_def("traits", t).get("category") == "personality")
	check_eq(personality.size(), int(g.def_num("character.personality_traits", 3)), "характер сложился")
	check(Upbringing.guardian_of(g, kid) == null, "опекунство кончилось")
	check(kid.opinions.has(gdn.id), "память об опекуне")
	# взрослые с начала партии не «взрослеют» заново
	var adult_count := 0
	g.engine.hooks.on("character.coming_of_age", func(_p): adult_count += 1)
	_run_months(g, 1)
	check(adult_count < 10, "совершеннолетие не срабатывает для всех взрослых")


func test_regency() -> void:
	var g := _game()
	var will: Dictionary = g.ch("william")
	var heir := Chars.create_character(g, {"culture": "norman", "faith": "catholic", "age": 8, "female": false, "father": will.id, "liege": will.id, "dynasty": will.dynasty})
	# мальчик получает графство и становится правителем-ребёнком
	var county: String = Titles.domain_counties(g, will)[-1]
	Titles.transfer_title(g, county, heir.id)
	check(Upbringing.needs_regent(g, heir), "правителю-ребёнку нужен регент")
	Upbringing.monthly_char(g, heir)
	var r: Variant = Upbringing.regent_of(g, heir)
	check(r != null, "регент назначен")
	check(Upbringing.regency_of(g, r).id == heir.id, "регент знает своего правителя")
	var mods := Upbringing.regency_modifiers(g, heir)
	check(mods.has("vassal_opinion") and mods.has("tax_mult"), "регентство влияет на державу")
	check(Stats.stat_breakdown(g, heir, "tax_mult").any(func(p): return str(p.label).contains(Chars.char_name(g, r))), "регент в разбивке налога")
	# вырос — регентство кончается
	heir.birth = g.date - 17 * GameDate.DAYS_PER_YEAR
	heir.flags["adult"] = 0
	Upbringing.monthly_char(g, heir)
	check(Upbringing.regent_of(g, heir) == null, "регентство окончено")


func test_dynasty_renown_and_legacies() -> void:
	var g := _game()
	var will: Dictionary = g.ch("william")
	var root: Variant = Chars.dynasty_root(g, will.dynasty)
	check(Dynasties.is_head(g, will), "Вильгельм — глава рода")
	var before := Dynasties.renown_total(g, root)
	Dynasties.monthly_char(g, will)
	check(Dynasties.renown_total(g, root) > before, "правитель рода приносит известность")
	# ИИ-глава сам тратит известность на наследия
	check(not Dynasties.owned(g, root).is_empty(), "ИИ-глава открыл наследие")
	# деяние приносит известность
	var r0 := Dynasties.renown(g, root)
	Deeds.record(g, will, "wars_won")
	check(Dynasties.renown(g, root) > r0, "победа в войне — известность рода")
	# наследие: нужна известность и предыдущий уровень
	check(not Dynasties.legacy_blockers(g, will, "blood_2").is_empty(), "второй уровень — после первого")
	Chars.add_dynasty_renown(g, will.dynasty, 5000)
	var cost := Dynasties.legacy_cost(g, root)
	var r1 := Dynasties.renown(g, root)
	check(Dynasties.unlock(g, will, "blood_1"), "наследие открыто")
	check(is_equal_approx(Dynasties.renown(g, root), r1 - cost), "известность потрачена")
	check(Dynasties.legacy_cost(g, root) > cost, "следующее дороже")
	check(Dynasties.has_legacy(g, root, "blood_1"), "наследие у рода")
	# модификаторы наследия у всех членов рода
	var kin: Variant = null
	for m in Dynasties.members(g, root):
		if m.id != will.id:
			kin = m
	if kin != null:
		g.stat_cache.clear()
		check(Stats.stat_breakdown(g, kin, "health").any(func(p): return float(p.value) == 0.5), "наследие действует на родича")
	# не глава — не может
	if kin != null:
		check(not Dynasties.legacy_blockers(g, kin, "blood_2").is_empty(), "открывает только глава")
	check(Dynasties.level(g, root) >= 2, "уровень славы растёт с известностью")


func test_cadet_house_and_disinherit() -> void:
	var g := _game()
	var will: Dictionary = g.ch("william")
	var robert: Variant = null
	for cid in will.children:
		var c: Variant = g.ch(cid)
		if c != null and c.death == null and not c.titles.is_empty():
			robert = c
	if robert == null:
		robert = g.ch(will.children[0])
		Titles.transfer_title(g, Titles.domain_counties(g, will)[-1], robert.id)
	var old_dyn: Variant = robert.dynasty
	check(not Dynasties.is_house_head(g, robert), "младший сын — не глава дома")
	var house: Variant = Dynasties.found_house(g, robert)
	check(house != null and robert.dynasty == house.id, "основан дом")
	check(Chars.dynasty_root(g, robert.dynasty) == old_dyn, "корень — прежний род")
	check(Chars.same_dynasty(g, robert, will), "один род с младшей ветвью")
	check(Dynasties.is_house_head(g, robert), "основатель — глава дома")
	check(Dynasties.head_of(g, old_dyn).id == will.id, "глава рода прежний")
	check(Dynasties.members(g, old_dyn).has(robert), "ветвь — среди членов рода")
	check(Coa.dynasty_spec(g, house.id) is Dictionary, "у дома герб с отличием")
	var ctx := ScriptContext.make(g, {"type": "character", "id": robert.id})
	check(Interp.eval_trigger(ctx, ctx.root, {"dynasty": old_dyn, "is_cadet_house": true}), "триггеры династии видят ветвь")
	# лишение наследства
	var heirs := Succession.heirs_of(g, will)
	check(not heirs.is_empty(), "у Вильгельма есть наследники")
	var first: Dictionary = g.ch(heirs[0])
	Dynasties.disinherit(g, first, true)
	check(not Succession.heirs_of(g, will).has(first.id), "лишённый наследства выпал из линии")
	Dynasties.disinherit(g, first, false)
	check(Succession.heirs_of(g, will).has(first.id), "восстановлен в правах")
	# смерть главы — главенство переходит
	Succession.kill_character(g, will, "natural")
	var nh: Variant = Dynasties.head_of(g, old_dyn)
	check(nh != null and nh.id != will.id and Chars.same_dynasty(g, nh, robert), "новый глава рода")

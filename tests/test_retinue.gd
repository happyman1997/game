extends TestCase
## Дружина: отряды с именами и опытом; опыт — от боя (сражённые, победа),
## ранг и капитан усиливают отряд, пополнение разбавляет опыт; капитаны —
## живые люди и могут пасть; в долгах дружина уходит, ветераны с капитаном —
## вольной ротой; после смерти господина недовольные ветераны уходят.
## Наёмные роты: найм, плата, армия, уход без платы и по сроку, ИИ нанимает.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _report(a: Dictionary, r: Dictionary, won: bool, men: int, left: int, kills: int) -> Dictionary:
	return {"winner": 0 if won else 1, "days": 3, "events": [], "start": [men, men], "lost": [men - left, 0], "morale": [30, 10],
		"units": [[{"key": a.id + ":" + str(r.id), "type": r.type, "men": men, "left": left, "kills": kills, "reg": r.id}], []],
		"sides": [{"owners": [a.owner], "commander": null}, {"owners": [], "commander": null}]}


func test_names_and_start() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var regs := Regiments.regs_of(h)
	check(not regs.is_empty(), "у Гарольда есть отряды")
	var names := {}
	for r in regs:
		check(r.get("name") is Array and r.name.size() == 2, "у отряда есть имя")
		var nm := Retinue.name_of(g, r)
		check(nm != "" and not nm.contains("regiment_name"), "имя читается: %s" % nm)
		check(not names.has(nm), "имена отрядов одного хозяина не повторяются (%s)" % nm)
		names[nm] = true
		check(float(r.get("xp", -1)) >= 0.0 and float(r.xp) <= 200.0, "стартовый опыт в пределах")
	var comps: Array = Mercenaries.all(g).values()
	check(comps.size() == g.content.all("mercenary_companies").size(), "роты мира созданы (%d)" % comps.size())
	for m in comps:
		var cap: Variant = g.ch(m.captain)
		check(cap != null and Chars.is_alive(cap) and cap.flags.get("merc_captain") == m.id, "%s: капитан — живой человек" % m.id)
		check(Mercenaries.men_of(g, m) > 0 and Mercenaries.avg_xp(g, m) > 0.0, "%s: отряды с опытом" % m.id)
		check(Mercenaries.name_of(g, m) != "" and not Mercenaries.name_of(g, m).contains("mercenary_company"), "имя роты читается")
	# новый отряд тоже получает имя
	var r2: Variant = Regiments.recruit(g, h, "light_footmen", true)
	check(r2.get("name") is Array and float(r2.xp) == 0.0, "новобранцы с именем и без опыта")


func test_xp_rank_and_chronicle() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var a: Variant = Military.raise_army(g, h)
	var r: Dictionary = Regiments.regs_of(h)[0]
	r.xp = 90.0
	var rep := _report(a, r, true, 100, 80, 60)
	Retinue.after_battle(g, rep, "c_kent")
	# 12 за бой + 18 за победу + 60 × 60/100
	check_eq(float(r.xp), 90.0 + 12.0 + 18.0 + 36.0, "опыт от боя, победы и сражённых")
	check_eq(int(r.battles), 1, "счёт боёв")
	check_eq(int(r.kills), 60, "счёт сражённых")
	check(Data.as_array(r.chronicle).size() == 1 and r.chronicle[0].won and int(r.chronicle[0].lost) == 20, "запись в летописи")
	check_eq(str(Retinue.rank_of(g, r).id), "seasoned", "отряд стал бывалым")
	check(rep.events.any(func(e): return e.kind == "rank_up" and e.b == "seasoned"), "в отчёте — новый ранг")
	check(r.chronicle[0].get("rank") == "seasoned", "в летописи — новый ранг")
	# поражение без сечи учит меньше
	var x0 := float(r.xp)
	var rep2 := _report(a, r, false, 80, 70, 0)
	rep2.days = 0
	rep2.events = [{"kind": "refused", "side": 0}]
	Retinue.after_battle(g, rep2, "c_kent")
	check(absf(float(r.xp) - x0 - 12.0 * 0.4) < 0.01, "отход без сечи — малый опыт")
	# летопись не длиннее предела
	for i in 15:
		Retinue.after_battle(g, _report(a, r, true, 80, 80, 1), "c_kent")
	check_eq(Data.as_array(r.chronicle).size(), int(g.def_num("regiments.chronicle_max", 10)), "летопись — последние бои")


func test_rank_and_captain_in_battle() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var a: Variant = Military.raise_army(g, h)
	var r: Dictionary = Regiments.regs_of(h)[0]
	r.xp = 0.0
	r.captain = null
	var unit := func() -> Dictionary:
		for u in Battle._units(g, [a], "c_kent"):
			if str(u.key) == a.id + ":" + str(r.id):
				return u
		return {}
	var base: Dictionary = unit.call()
	check(not base.is_empty(), "отряд — войско в бою")
	r.xp = 600.0
	var vet: Dictionary = unit.call()
	check(absf(float(vet.quality) / float(base.quality) - 1.25) < 0.001, "прославленные бьют на четверть сильнее")
	check_eq(float(vet.morale) - float(base.morale), 12.0, "и крепче духом")
	var cands := Retinue.captain_candidates(g, h, r.id)
	check(not cands.is_empty(), "есть кого поставить капитаном")
	check(not cands.any(func(x): return x.id == h.id), "сам господин — не капитан")
	var cap: Dictionary = cands[0]
	cap.skills.prowess = 15
	cap.skills.martial = 10
	g.touch(cap)
	g.stat_cache.erase(cap.id)
	check(Retinue.set_captain(g, h, r.id, cap.id), "капитан поставлен")
	var led: Dictionary = unit.call()
	var qp := Stats.skill(g, cap, "prowess") * g.def_num("regiments.captain_prowess", 0.012)
	check(absf(float(led.quality) / float(vet.quality) - (1.0 + minf(0.25, qp))) < 0.001, "капитан прибавляет силы по доблести")
	check(absf(float(led.morale) - float(vet.morale) - Stats.skill(g, cap, "martial") * 0.6) < 0.001, "и духа по военному делу")
	# капитан другого отряда не ставится второй раз
	var r2: Dictionary = Regiments.regs_of(h)[1]
	check(not Retinue.captain_candidates(g, h, r2.id).any(func(x): return x.id == cap.id), "один капитан — один отряд")
	# ушёл со двора — больше не капитан
	cap.liege = "william"
	g.touch(cap)
	check(Retinue.captain_of(g, h, r) == null, "ушедший со двора не командует отрядом")


func test_captain_can_fall() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var a: Variant = Military.raise_army(g, h)
	var r: Dictionary = Regiments.regs_of(h)[0]
	var cap: Dictionary = Retinue.captain_candidates(g, h, r.id)[0]
	Retinue.set_captain(g, h, r.id, cap.id)
	g.defines.regiments["captain_death"] = 100.0
	var rep := _report(a, r, false, 100, 30, 5)
	Retinue.after_battle(g, rep, "c_kent")
	check(cap.death != null, "капитан пал с отрядом")
	check(rep.events.any(func(e): return e.kind == "captain_fell" and e.a == cap.id), "в отчёте — гибель капитана")
	check(r.get("captain") == null, "место капитана свободно")


func test_reinforce_dilutes_and_upkeep() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var r: Dictionary = Regiments.regs_of(h)[0]
	var mx := int(Data.num(g.content.get_def("regiment_types", r.type).size))
	r.size = mx / 2
	r.xp = 400.0
	var before := int(r.size)
	Regiments.monthly_char(g, h)
	var after := int(r.size)
	check(after > before, "отряд пополнился")
	var keep := g.def_num("regiments.reinforce_keep", 0.3)
	check(absf(float(r.xp) - 400.0 * (before + (after - before) * keep) / after) < 0.01, "новобранцы разбавляют опыт (%.1f)" % float(r.xp))
	# прославленным пополняться легче, но и платить больше
	r.size = mx / 2
	r.xp = 700.0
	var up0 := Regiments.upkeep(g, h)
	r.xp = 0.0
	var up1 := Regiments.upkeep(g, h)
	check(up0 > up1, "прославленным платят больше (%.2f > %.2f)" % [up0, up1])
	r.xp = 700.0
	before = int(r.size)
	Regiments.monthly_char(g, h)
	check(int(r.size) - before > roundi(mx * g.def_num("regiments.reinforce_rate", 0.1)), "к прославленным идут охотнее")


func test_ai_captains() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	for r in Regiments.regs_of(h):
		r.captain = null
	for x in Retinue.captain_candidates(g, h):
		x.skills.prowess = 12
		x.skills.martial = 10
		g.touch(x)
		g.stat_cache.erase(x.id)
	Retinue.monthly_char(g, h)
	check(Regiments.regs_of(h).any(func(r): return Retinue.captain_of(g, h, r) != null), "ИИ ставит капитанов")


func test_mercenaries_hire_fee_and_leave() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	h.gold = 5000.0
	g.touch(h)
	var a: Variant = Military.raise_army(g, h)
	var size0 := int(a.size)
	var own0 := Regiments.own_count(h)
	var m: Dictionary = Mercenaries.all(g).values()[0]
	var cost := Mercenaries.hire_cost(g, m)
	var men := Mercenaries.men_of(g, m)
	check(cost > 0.0 and Mercenaries.fee(g, m) > 0.0, "найм и плата стоят денег")
	check(Mercenaries.hire(g, h, m.id), "рота нанята")
	check_eq(m.employer, h.id, "рота служит Гарольду")
	check(absf(float(h.gold) - (5000.0 - cost)) < 0.01, "плата за найм")
	check_eq(Regiments.own_count(h), own0, "наёмники — вне предела отрядов")
	check(Regiments.regs_of(h).filter(func(r): return r.get("merc") == m.id).size() == Mercenaries.regiments_of(g, m).size(), "отряды роты в дружине")
	check_eq(int(a.size), size0 + men, "рота догнала армию")
	check(Economy.income_breakdown(g, h).any(func(x): return x.get("key") == "mercenary_fees"), "плата роте — строка в доходах")
	check(not Mercenaries.hire(g, g.ch("william"), m.id), "занятую роту не нанять")
	# в долгах рота уходит
	h.gold = -10.0
	g.touch(h)
	Mercenaries.monthly(g)
	check(m.employer == null, "без платы рота ушла")
	check(not Regiments.regs_of(h).any(func(r): return r.get("merc") == m.id), "отряды роты ушли из дружины")
	check_eq(int(a.size), size0, "и из армии")
	check_eq(Mercenaries.men_of(g, m), men, "рота вернулась целой")
	# срок вышел, войны нет — уходит
	h.gold = 5000.0
	g.touch(h)
	check(Mercenaries.hire(g, h, m.id), "снова нанята")
	g.state.date = int(m.until) + 1
	Mercenaries.monthly(g)
	check(m.employer == null, "срок службы вышел")


func test_ai_hires_when_weaker() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var ts := Wars.available_war_targets(g, w, h.id)
	var war: Variant = Wars.declare_war(g, w, ts[0])
	check(war != null, "война объявлена")
	# Гарольд слаб и богат
	for r in Regiments.regs_of(h).duplicate():
		Regiments.disband(g, h, r.id)
	h.gold = 20000.0
	g.touch(h)
	g.defines.mercenaries["ai_hire_chance"] = 1.0
	g.defines.mercenaries["ai_hire_ratio"] = 100.0
	Mercenaries.ai_monthly_char(g, h)
	check(not Mercenaries.hired_by(g, h.id).is_empty(), "слабый на войне нанимает роту")


func test_unpaid_retinue_leaves() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var regs := Regiments.regs_of(h)
	var r: Dictionary = regs[0]
	r.xp = 400.0
	var cap: Dictionary = Retinue.captain_candidates(g, h, r.id)[0]
	Retinue.set_captain(g, h, r.id, cap.id)
	var nm := Retinue.name_of(g, r)
	var n0 := Regiments.own_count(h)
	h.gold = -100.0
	g.touch(h)
	for i in int(g.def_num("regiments.unpaid_months", 3)):
		Retinue.monthly_char(g, h)
	check_eq(Regiments.own_count(h), n0 - 1, "в долгах отряд ушёл")
	var free: Array = Mercenaries.all(g).values().filter(func(m): return m.get("free_from") == h.id)
	check(free.size() == 1 and Mercenaries.name_of(g, free[0]) == nm, "ветераны с капитаном ушли вольной ротой «%s»" % nm)
	check(cap.liege == null and cap.flags.get("merc_captain") == free[0].id, "капитан ушёл с ними")
	h.gold = 100.0
	g.touch(h)
	Retinue.monthly_char(g, h)
	check(not h.flags.has("retinue_unpaid"), "заплатили — ропот стих")


func test_veterans_leave_disliked_heir() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var r: Dictionary = Regiments.regs_of(h)[0]
	r.xp = 300.0
	var cap: Dictionary = Retinue.captain_candidates(g, h, r.id)[0]
	Retinue.set_captain(g, h, r.id, cap.id)
	var heir: Dictionary = g.ch("william")
	g.defines.regiments["desert_opinion"] = 1000.0
	Retinue.on_succession(g, h, heir)
	check(not Regiments.regs_of(h).any(func(x): return x.id == r.id), "ветераны не пошли за наследником")
	check(Mercenaries.all(g).values().any(func(m): return m.get("free_from") == h.id), "и стали вольной ротой")
	# по нраву — идут (новый мир: числа defines кешируются)
	var g2 := _game()
	var h2: Dictionary = g2.ch("harold")
	var r2: Dictionary = Regiments.regs_of(h2)[0]
	r2.xp = 300.0
	var cap2: Dictionary = Retinue.captain_candidates(g2, h2, r2.id)[0]
	Retinue.set_captain(g2, h2, r2.id, cap2.id)
	g2.defines.regiments["desert_opinion"] = -1000.0
	Retinue.on_succession(g2, h2, g2.ch("william"))
	check(Regiments.regs_of(h2).any(func(x): return x.id == r2.id), "расположенные к наследнику остаются")


func test_battle_report_and_save() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var ts := Wars.available_war_targets(g, w, h.id)
	var war: Variant = Wars.declare_war(g, w, ts[0])
	var aw: Variant = Military.raise_army(g, w)
	var ah: Variant = Military.raise_army(g, h)
	ah.location = aw.location
	var xp0 := {}
	for c in [h, w]:
		for r in Regiments.regs_of(c):
			xp0[r.id] = float(r.get("xp", 0.0))
	var seen := [null]
	g.engine.hooks.on("battle", func(p): seen[0] = p.get("report"), 0, "test")
	Military._resolve_battles(g)
	var rep: Variant = seen[0]
	check(rep != null, "бой состоялся")
	var named := 0
	var killers := 0
	for side in rep.units:
		for u in side:
			if u.get("reg") != null:
				named += 1
				check(u.get("name") is Array and u.get("rank") != null, "отряд в отчёте — с именем и рангом")
				if float(u.get("kills", 0)) > 0.0:
					killers += 1
	check(named > 0, "отряды дружины в отчёте (%d)" % named)
	check(killers > 0, "отряды разили врагов")
	var grew := false
	for c in [h, w]:
		for r in Regiments.regs_of(c):
			if xp0.has(r.id) and float(r.get("xp", 0.0)) > xp0[r.id]:
				grew = true
	check(grew, "отряды набрались опыта")
	var res := g.engine.load_game(SaveGame.serialize(g))
	check(res.error == "", res.error)
	var g2: Game = res.game
	check_eq(Mercenaries.all(g2).size(), Mercenaries.all(g).size(), "роты переживают сохранение")
	var h2: Dictionary = g2.ch("harold")
	if not Regiments.regs_of(h).is_empty():
		check_eq(float(Regiments.regs_of(h2)[0].get("xp", 0.0)), float(Regiments.regs_of(h)[0].get("xp", 0.0)), "опыт отрядов переживает сохранение")

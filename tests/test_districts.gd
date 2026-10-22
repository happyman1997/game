extends TestCase
## Районы: районы владений даром, участки по развитию, сила района (уровень ×
## место: местность, граница, торговые пути), постройки в районах и их бонусы
## с силой, места по уровню, стройка и подъём района, содержание, ежегодные
## эффекты построек, перенос старых построек, ИИ строит районы.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func test_holding_districts_and_plots() -> void:
	var g := _game()
	var p: Dictionary = g.state.provinces["c_winchester"]
	check(p.districts.has("citadel") and p.districts.has("market") and p.districts.has("temple_quarter"), "замок, город и храм дают детинец, посад и соборную сторону")
	check_eq(Districts.used_plots(g, "c_winchester"), 0, "районы владений участков не занимают")
	check_eq(Districts.plots(g, "c_winchester"), 2, "участки: 1 + развитие/10")
	# старые постройки перенесены в районы
	var k: Dictionary = g.state.provinces["c_kronhafen"]
	check(k.buildings.has("market") and Districts.buildings_in(g, "c_kronhafen", "market").has("market"), "рынок Кронхафена стоит в посаде")


func test_power_scales_buildings() -> void:
	var g := _game()
	var pid := "c_winchester"
	var p: Dictionary = g.state.provinces[pid]
	var tax0 := Economy.county_tax(g, pid)
	p.buildings.append("market")
	g.stat_cache.clear()
	var tax1 := Economy.county_tax(g, pid)
	check(tax1 > tax0, "рынок поднял подати")
	var pw1 := Districts.power(g, pid, "market")
	Districts.set_level(g, pid, "market", 3)
	var pw3 := Districts.power(g, pid, "market")
	check(pw3 > pw1 * 2.0, "уровень III втрое… почти: сила %.2f → %.2f" % [pw1, pw3])
	var tax3 := Economy.county_tax(g, pid)
	check(tax3 - tax0 > (tax1 - tax0) * 2.0, "сила района умножила бонус рынка (%.2f → %.2f)" % [tax1 - tax0, tax3 - tax0])
	# торговые пути: посады соседей прибавляют силы
	var parts := Districts.power_parts(g, pid, "market").map(func(x): return str(x.label))
	check(parts.any(func(l): return l.contains("Торговые пути")), "торговые пути в силе посада: %s" % [parts])


func test_terrain_and_border() -> void:
	var g := _game()
	# горы Гвинеда: детинец сильнее (и граница с Англией)
	var pw := Districts.power(g, "c_gwynedd", "citadel")
	check(pw > 1.3, "детинец в горах и на рубеже сильнее (%.2f)" % pw)
	# угодья на пашнях сильнее, чем на холмах
	Districts.set_level(g, "c_winchester", "fields", 1)
	Districts.set_level(g, "c_gwynedd", "fields", 1)
	check(Districts.power(g, "c_winchester", "fields") > 1.0, "пашни Винчестера — сильные угодья")


func test_slots_and_found_district() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var pid := "c_winchester"
	h.gold = 5000.0
	check(Decisions.start_building(g, h, pid, "walls"), "стены в детинце")
	g.state.provinces[pid].construction.done = g.date
	Decisions.daily_construction(g)
	var bl := Decisions.building_candidates(g, h, pid).filter(func(x): return x.def.id == "barracks")
	check(not bl.is_empty() and bl[0].blockers.size() > 0, "в детинце I одно место — оно занято")
	# заложить угодья: участок есть
	check(Districts.start(g, h, pid, "fields"), "заложены угодья")
	check_eq(Districts.free_plots(g, pid), 1, "стройка занимает участок")
	g.state.provinces[pid].construction.done = g.date
	Decisions.daily_construction(g)
	check_eq(Districts.level(g, pid, "fields"), 1, "угодья готовы")
	# подъём детинца — второе место
	check(Districts.start(g, h, pid, "citadel"), "детинец поднимают")
	g.state.provinces[pid].construction.done = g.date
	Decisions.daily_construction(g)
	check_eq(Districts.level(g, pid, "citadel"), 2, "детинец II")
	check_eq(Districts.slots(g, pid, "citadel"), 2, "два места")
	check(Districts.upkeep(g, h) > 0.0, "районы II стоят содержания")
	check(Economy.income_breakdown(g, h).any(func(x): return str(x.label) == g.loc.t("ui.district_upkeep")), "содержание — строка в доходах")


func test_yearly_buildings() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var pid := "c_winchester"
	var p: Dictionary = g.state.provinces[pid]
	p.buildings.append("fairground")
	p.buildings.append("hospice")
	g.stat_cache.clear()
	var gold0 := float(h.gold)
	var k0 := Karma.value(h) if g.engine.has_feature("karma") else 0.0
	Districts.yearly(g)
	check(float(h.gold) > gold0, "ярмарка принесла золото (%.1f)" % (float(h.gold) - gold0))
	if g.engine.has_feature("karma"):
		check(Karma.value(h) > k0, "странноприимный дом — Свет на душу")


func test_money_changer_eases_loan() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var loan: Dictionary = g.content.get_def("decisions", "take_loan")
	for c in [h, w]:
		for cid in Titles.domain_counties(g, c):
			g.state.provinces[cid].buildings.erase("money_changer")
	g.state.provinces["c_winchester"].buildings.append("money_changer")
	check(Decisions.take(g, loan, h) and Decisions.take(g, loan, w), "заём открыт всем")
	check(h.modifiers.any(func(m): return m.id == "lombard_debt"), "с меняльным двором — обычные условия")
	check(w.modifiers.any(func(m): return m.id == "loan_debt_harsh"), "без связей — кабала")


func test_ai_builds_districts() -> void:
	var g := _game()
	var h: Dictionary = g.ch("philip")
	h.gold = 3000.0
	var before := 0
	for cid in Titles.domain_counties(g, h):
		before += int(g.state.provinces[cid].construction != null)
	for i in 40:
		Ai._consider_building(g, h)
		for cid in Titles.domain_counties(g, h):
			var p: Dictionary = g.state.provinces[cid]
			if p.construction != null:
				p.construction.done = g.date
		Decisions.daily_construction(g)
	var levels := 0
	var builds := 0
	for cid in Titles.domain_counties(g, h):
		var p: Dictionary = g.state.provinces[cid]
		builds += p.buildings.size()
		for did in p.districts:
			levels += int(p.districts[did])
	check(builds > 0, "ИИ строит в районах (%d построек)" % builds)
	check(levels > Titles.domain_counties(g, h).size() * 2, "и закладывает или поднимает районы (сумма уровней %d)" % levels)


func test_great_works() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	h.gold = 5000.0
	var pid := "c_winchester"
	var p: Dictionary = g.state.provinces[pid]
	var mint := func(where: String) -> Variant:
		var xs := Decisions.building_candidates(g, h, where).filter(func(x): return x.def.id == "mint")
		return xs[0] if not xs.is_empty() else null
	# монетный двор: посад III и гильдия
	check(mint.call(pid) == null or not mint.call(pid).blockers.is_empty(), "без посада III монетного двора нет")
	Districts.set_level(g, pid, "market", 3)
	p.buildings.append("guild_hall")
	check(mint.call(pid) != null and mint.call(pid).blockers.is_empty(), "посад III с гильдией — можно ставить")
	g.stat_cache.clear()
	var inc0 := Stats.stat(g, h, "monthly_income")
	check(Decisions.start_building(g, h, pid, "mint"), "монетный двор заложен")
	# второй в той же державе — нельзя, пока стоит или строится первый
	var other := ""
	for cid in Titles.domain_counties(g, h):
		if cid != pid:
			other = cid
			break
	Districts.set_level(g, other, "market", 3)
	g.state.provinces[other].buildings.append("guild_hall")
	check(mint.call(other) != null and not mint.call(other).blockers.is_empty(), "монетный двор — один на державу")
	check_eq(Decisions.unique_taken(g, "mint", "realm", h), pid, "занят Винчестером")
	p.construction.done = g.date
	Decisions.daily_construction(g)
	check(p.buildings.has("mint"), "монетный двор построен")
	# великая стройка от силы района не зависит
	check_eq(Districts.building_scale(g, pid, "mint"), 1.0, "scale: no — множитель 1")
	g.stat_cache.clear()
	var inc := Stats.stat(g, h, "monthly_income")
	check(inc >= inc0 + 2.0 - 0.01, "монетный двор: +2 в месяц (%.2f → %.2f)" % [inc0, inc])
	Districts.set_level(g, pid, "market", 1)
	g.stat_cache.clear()
	check(is_equal_approx(Stats.stat(g, h, "monthly_income"), inc), "бонус монетного двора тот же при посаде I")
	# одна в мире: великий торг у Гарольда — Вильгельму уже не построить
	var w: Dictionary = g.ch("william")
	p.buildings.append("great_market")
	check(Decisions.unique_taken(g, "great_market", "world", w) == pid, "великий торг один на весь мир")

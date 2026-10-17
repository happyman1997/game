extends TestCase
## Законы державы: группы видны по рангу; подати меняют налог с домена и
## мнение графств; щитовые деньги меняют войска вассалов на золото;
## королевская десятина злит главу веры; рельеф с наследника вассала идёт
## сюзерену статьёй «Рельеф»; выморочный лен бездетного графа возвращается
## сюзерену; ИИ на войне объявляет всеобщий сбор.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _shown(g: Game, c: Dictionary) -> Array:
	return Laws.groups(g).filter(func(gd): return Laws.is_group_shown(g, c, gd)).map(func(gd): return gd.id)


## Сбросить кэши характеристик, налогов и мнений после смены закона.
func _fresh(g: Game) -> void:
	g.stat_cache.clear()
	g.month_cache.clear()
	g.day_cache.clear()


## Мнение графства без месячного кэша.
func _county_op(g: Game, pid: String) -> float:
	var s := 0.0
	for part in Populace.opinion_parts(g, pid, false):
		s += Data.num(part.value)
	return s


func _count_vassal(g: Game, liege: Dictionary) -> Dictionary:
	for v in g.vassals_of(liege.id):
		if Titles.primary_tier(g, v) == 1 and Chars.is_adult(g, v) and v.get("prison") == null:
			return v
	return {}


func _vassal_with_child(g: Game, liege: Dictionary) -> Dictionary:
	for v in g.vassals_of(liege.id):
		if Succession.alive_children(g, v).any(func(x): return Succession.can_inherit(x)):
			return v
	return {}


func test_groups_by_tier() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var shown := _shown(g, h)
	for gid in ["crown_authority", "tax_law", "military_service", "church_law", "fief_law"]:
		check(shown.has(gid), "королю видна группа %s" % gid)
	var v := _count_vassal(g, h)
	var vs := _shown(g, v)
	check(vs.has("tax_law") and vs.has("church_law") and not vs.has("fief_law") and not vs.has("crown_authority"), "графу — подати, повинность, Храм; без ленов и власти короны: %s" % [vs])
	check_eq(Laws.current(g, h, "tax_law").id, "tax_law_1", "по умолчанию — обычные подати")


func test_heavy_taxes() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var pid: String = Titles.domain_counties(g, h)[0]
	var tax0 := Economy.domain_tax(g, h)
	var op0 := _county_op(g, pid)
	check(Laws.change(g, h, "tax_law_2", true), "тяжкие подати")
	_fresh(g)
	check(Economy.domain_tax(g, h) > tax0 * 1.1, "налог с домена вырос (%.2f → %.2f)" % [tax0, Economy.domain_tax(g, h)])
	check(_county_op(g, pid) <= op0 - 10.0, "графство злее (%.0f → %.0f)" % [op0, _county_op(g, pid)])
	# блокировка: недовольные графства не дают ввести тяжкие подати
	check(Laws.change(g, h, "tax_law_1", true), "назад к обычным")
	var law: Dictionary = g.content.get_def("realm_laws", "tax_law_2")
	h.flags.erase("law_cd:tax_law")
	for p in Titles.domain_counties(g, h).slice(0, 3):
		Populace.add_county_opinion(g, p, "generic", -200)
	_fresh(g)
	check(not Laws.change_blockers(g, h, law).is_empty(), "при недовольных графствах — нельзя")


func test_scutage_trades_levies_for_gold() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var lev0 := Economy.realm_levy(g, h)
	var vt0 := 0.0
	for v in g.vassals_of(h.id):
		vt0 += Economy.vassal_tax_to(g, h, v)
	check(Laws.change(g, h, "military_service_0", true), "щитовые деньги")
	_fresh(g)
	var vt1 := 0.0
	for v in g.vassals_of(h.id):
		vt1 += Economy.vassal_tax_to(g, h, v)
	check(Economy.realm_levy(g, h) < lev0, "войск меньше (%d → %d)" % [lev0, Economy.realm_levy(g, h)])
	check(vt1 > vt0, "налогов с вассалов больше (%.2f → %.2f)" % [vt0, vt1])


func test_royal_tithe_angers_faith_head() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Variant = Temple.head_of(g, h)
	if head == null:
		check(true, "у веры Гарольда нет главы — пропуск")
		return
	var op0 := Opinion.opinion(g, head, h)
	var piety0 := Economy.monthly_income(g, h)
	check(Laws.change(g, h, "church_law_2", true), "королевская десятина")
	_fresh(g)
	check_eq(Opinion.opinion(g, head, h), op0 - 25, "глава веры недоволен")
	check(Economy.monthly_income(g, h) > piety0, "казна богаче")


func test_relief_from_heir() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v := _vassal_with_child(g, h)
	check(not v.is_empty(), "у Гарольда есть вассал с детьми")
	var heir: Variant = Succession.primary_heir(g, v)
	check(heir != null, "у вассала есть наследник")
	v.gold = 300.0
	var hg := float(h.gold)
	Succession.kill_character(g, v)
	var nh: Dictionary = g.ch(heir.id)
	check(nh.liege == h.id, "наследник — вассал Гарольда")
	var got := float(Treasury.totals(g, h).get("relief", 0.0))
	check(got >= 5.0, "рельеф уплачен (%.1f)" % got)
	check(float(h.gold) - hg >= got - 0.01, "золото у сюзерена")


func test_escheat_childless_count() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	check(Laws.change(g, h, "crown_authority_2", true), "высокая власть")
	check(Laws.change(g, h, "fief_law_2", true), "выморочное право")
	var v := _count_vassal(g, h)
	for cid in v.children:
		var ch: Variant = g.ch(cid)
		if ch != null:
			ch.death = g.date
	var titles: Array = v.titles.duplicate()
	# у игрока лен не отбирают
	g.state.player = v.id
	check(not Laws.escheats(g, v, h), "игрок своих земель не теряет")
	g.state.player = "harold"
	check(not titles.is_empty() and Laws.escheats(g, v, h), "бездетный граф — лен выморочен")
	Succession.kill_character(g, v)
	for t in titles:
		check_eq(g.state.titles[t].holder, "harold", "%s вернулся к сюзерену" % t)


func test_ai_general_levy_at_war() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	if not Wars.is_at_war(g, h.id):
		var ts := Wars.available_war_targets(g, g.ch("william"), h.id)
		check(not ts.is_empty(), "у Вильгельма есть повод против Гарольда")
		Wars.declare_war(g, g.ch("william"), ts[0])
	check(Wars.is_at_war(g, h.id), "Гарольд воюет")
	var law := ""
	for k in 30:
		h.flags.erase("law_cd:military_service")
		Laws.yearly_ai(g)
		law = Laws.current(g, h, "military_service").id
		if law != "military_service_1":
			break
	check_eq(law, "military_service_2", "на войне — всеобщий сбор")

extends TestCase
## Стези: перки меняют правила и характер, вершины открывают действия,
## правила связывают механики (казни и страх, темница, поединки и вещи,
## наследия рода, воспитание, деяния и опыт, пути, заказ вещей, слава).


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _perks(g: Game, c: Dictionary, ids: Array) -> void:
	for pid in ids:
		Lifestyles.unlock_perk(g, c, pid, true)
	g.stat_cache.erase(c.id)


func test_every_tree_is_a_path() -> void:
	var g := _game()
	var trees := {}
	for p in g.content.all("perks"):
		if str(p.get("lifestyle")) in ["diplomacy_lifestyle", "martial_lifestyle", "stewardship_lifestyle", "intrigue_lifestyle", "learning_lifestyle"]:
			trees[str(p.tree)] = int(trees.get(str(p.tree), 0)) + 1
	check_eq(trees.size(), 11, "одиннадцать стезей")
	for t in trees:
		check(g.loc.raw("perk_tree_desc." + t) != null, "описание стези %s" % t)
	# у каждой вершины — черта и своё действие
	for p in g.content.all("perks"):
		if p.get("trait") != null and str(p.get("lifestyle")) != "sorcery_lifestyle":
			check(not Data.as_array(p.get("unlocks")).is_empty(), "вершина %s открывает действие" % p.id)
		check(g.loc.raw("perk_desc." + str(p.id)) != null or str(p.get("lifestyle")) == "sorcery_lifestyle", "описание перка %s" % p.id)


func test_tyrant_fear_and_reactions() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	check(Personality.stress_for(g, h, "execute_prisoner") >= 0.0, "без стези казнь не в радость")
	_perks(g, h, ["stern_gaze", "bloody_justice", "dungeon_dread", "iron_fist"])
	check(Personality.stress_for(g, h, "execute_prisoner") < 0.0, "Тирану казнь по душе")
	check(h.traits.has("tyrant"), "черта Тирана")
	# темница внушает страх
	var victims := g.living().filter(func(c): return c.id != "harold" and c.titles.is_empty() and Chars.is_adult(g, c) and not Chars.is_close_family(g, h, c)).slice(0, 2)
	for v in victims:
		Prison.imprison(g, h, v)
	h.vars.erase("dread")
	Politics.monthly_char(g, h)
	check(Politics.dread(h) >= 1.5, "пленники в темнице внушают страх (%.1f)" % Politics.dread(h))
	# показательная казнь
	var def: Dictionary = g.content.get_def("decisions", "public_execution")
	check(Decisions.can_take(g, def, h), "показательная казнь доступна: %s" % [Decisions.blockers(g, def, h)])
	var before := Politics.tier_level(g, h)
	check(Decisions.take(g, def, h), "казнь состоялась")
	check(Politics.tier_level(g, h) >= before + 1, "грозная слава — ступенью выше")
	check(victims.any(func(v): return v.death != null), "пленник казнён")


func test_intimidate_vassal() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_perks(g, h, ["stern_gaze", "bloody_justice", "dungeon_dread", "iron_fist"])
	var vs: Array = g.vassals_of("harold").filter(func(v): return float(v.gold) >= 20.0 and Politics.stance(g, v, h) != "defiant")
	check(not vs.is_empty(), "есть покорный вассал с золотом")
	var v: Dictionary = vs[0]
	v.gold = 200.0
	Politics.add_dread(g, h, 100)
	var def: Dictionary = g.content.get_def("interactions", "intimidate")
	check(Interactions.is_shown(g, def, h, v), "можно запугать")
	var gold0 := float(h.gold)
	var res := Interactions.execute(g, def, h, v)
	check(res in ["accepted", "declined"], "запугивание: %s" % res)
	if res == "accepted":
		check(float(h.gold) > gold0, "дань получена")
	else:
		var ctx := ScriptContext.make(g, {"type": "character", "id": h.id})
		check(Interp.eval_trigger(ctx, ctx.root, {"has_imprisonment_reason": {"type": "character", "id": v.id}}), "отказ — повод к темнице")


func test_knight_trophy_from_duel() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	_perks(g, h, ["knightly_vow", "trophy_taker"])
	for it in Artifacts.equipped(g, w).filter(func(x): return Artifacts.slot_of(g, x) == "weapon"):
		Artifacts.unequip(g, w, it)
	var sword := Artifacts.create(g, "sword", "famed", w, {"how": "found"})
	check(Artifacts.slot_of(g, sword) == "weapon" or Artifacts.equip(g, w, sword), "у Вильгельма меч в руке")
	g.on_action("on_duel_won", {"type": "character", "id": "harold"}, {"loser": {"type": "character", "id": "william"}})
	check_eq(str(Artifacts.item(g, sword.id).owner), "harold", "меч побеждённого — трофей")
	check(Data.as_array(Artifacts.item(g, sword.id).get("claims")).has("william"), "побеждённый притязает на свой меч")


func test_dynast_mentor_and_legacies() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Variant = Dynasties.head_of(g, h.dynasty)
	check(head != null, "у рода есть глава")
	var cost0 := Dynasties.legacy_cost(g, h.dynasty)
	_perks(g, head, ["fecund_line", "blood_ties"])
	check(Dynasties.legacy_cost(g, h.dynasty) < cost0, "наследия дешевле у Династа")


func test_scholar_deeds_and_paths() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	Lifestyles.set_focus(g, h, "focus_scholarship", true)
	_perks(g, h, ["avid_reader"])
	var xp0 := Lifestyles.xp_of(h, "learning_lifestyle")
	Deeds.record(g, h, "buildings")
	check(Lifestyles.xp_of(h, "learning_lifestyle") >= xp0 + 25.0 - 0.01, "деяние — опыт образа жизни")
	var min0 := Trials.skill_min(g, h, "warlord")
	_perks(g, h, ["natural_philosophy", "polymath"])
	check_eq(Trials.skill_min(g, h, "warlord"), min0 - 2.0, "пути открываются раньше")


func test_architect_commission_and_sovereign_glory() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var c0 := Artifacts.commission_cost(g, h, "fine")
	_perks(g, h, ["master_builder", "thriving_lands", "court_splendor"])
	check(Artifacts.commission_cost(g, h, "fine") < c0, "заказ дешевле")
	# слава Государя весит больше
	h.prestige = 3000.0
	var base := Renown.opinion_for(g, "prestige", Renown.level_of(g, h, "prestige"))
	_perks(g, h, ["regal_bearing"])
	check(Renown.boosted(g, h, "prestige", base) > base, "слава поднимает мнение сильнее")


func test_treasurer_loan_and_bribe() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_perks(g, h, ["efficient_rule", "tax_collectors", "lombard_loan", "great_administrator"])
	var loan: Dictionary = g.content.get_def("decisions", "take_loan")
	var gold0 := float(h.gold)
	check(Decisions.take(g, loan, h), "заём взят")
	check_eq(float(h.gold), gold0 + 300.0, "золото сразу")
	check(not Decisions.can_take(g, loan, h), "второй заём — после первого")
	var v: Dictionary = g.vassals_of("harold").filter(func(x): return not x.traits.has("honest") and not x.traits.has("just"))[0]
	h.gold = 500.0
	var bribe: Dictionary = g.content.get_def("interactions", "bribe")
	var op0 := Opinion.opinion(g, v, h)
	check_eq(Interactions.execute(g, bribe, h, v), "accepted", "подкуп принят")
	check(Opinion.opinion(g, v, h) > op0 + 20, "вассал расположен")
	check(float(h.gold) < 500.0, "подкуп стоит золота")


func test_seducer_hooks() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_perks(g, h, ["alluring", "pillow_talk", "heartbreaker"])
	var target: Dictionary = g.ch("william")
	var ctx := ScriptContext.make(g, {"type": "character", "id": "harold"}, {"owner": {"type": "character", "id": "harold"}, "target": {"type": "character", "id": "william"}})
	Interp.run_effect(ctx, ctx.root, g.content.get_def("schemes", "seduce").on_success)
	check(h.hooks.any(func(k): return k.target == "william"), "любовник на крючке")
	check(Leverage.hook_on(g, h, target.id) != null, "крюк записан")


func test_saint_relic_and_merge_fix() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_perks(g, h, ["devout_prayer", "inner_peace", "relic_keeper"])
	var rel := Artifacts.create(g, "reliquary", "masterwork", h, {"how": "found"})
	check(rel.get("slot") != null or Artifacts.equip(g, h, rel), "реликварий при дворе")
	var p0 := float(h.piety)
	g.on_action("on_yearly_pulse", {"type": "character", "id": "harold"})
	check(float(h.piety) >= p0 + 60.0 - 0.01, "мощи дают благочестие")
	# список-директива в новой записи становится списком
	check_eq(Data.deep_merge(null, {"x": {"$append": [1, 2]}}), {"x": [1, 2]}, "$append без основы")


func test_spider_sells_secret() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_perks(g, h, ["subtle_hand", "prying_eyes", "secret_trade"])
	var buyer: Dictionary = g.ch("philip")
	var victim: Dictionary = g.ch("william")
	var s: Variant = Secrets.add_secret(g, victim, "secret_embezzler", null, ["harold"])
	check(s != null, "у Вильгельма есть тайна, Гарольд её знает")
	buyer.gold = 300.0
	var def: Dictionary = g.content.get_def("interactions", "sell_secret")
	check(Interactions.is_shown(g, def, h, buyer), "можно продать тайну")
	check(Interactions.blockers(g, def, h, buyer).is_empty(), "есть что продать: %s" % [Interactions.blockers(g, def, h, buyer)])
	var gold0 := float(h.gold)
	var res := Interactions.execute(g, def, h, buyer)
	if res == "accepted":
		check(float(h.gold) > gold0, "серебро за тайну")
		var ctx := ScriptContext.make(g, {"type": "character", "id": "philip"})
		check(Interp.eval_trigger(ctx, ctx.root, {"num_known_secrets": ">= 1"}), "покупатель узнал тайну")
	else:
		check(res == "declined", "сделка: %s" % res)

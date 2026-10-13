extends TestCase
## «Свет и Пепел»: карма от деяний, ступени, совесть, исповедь и Пепелище,
## ревнители веры, Книга деяний, миниатюра вкладки.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	# начальный нрав души — от черт; тесты начинают с равновесия
	Karma.set_value(g, g.ch("harold"), 0.0)
	return g


func _ctx(g: Game, id: String, scopes: Dictionary = {}) -> ScriptContext:
	return ScriptContext.make(g, {"type": "character", "id": id}, scopes)


func test_deeds_and_tiers() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	check_eq(Karma.value(h), 0.0, "в начале весы в равновесии")
	check_eq(str(Karma.tier_of(g, h).id), "common", "как все")
	var ctx := _ctx(g, "harold")
	Interp.run_effect(ctx, ctx.root, {"add_karma": {"value": -25, "deed": "murder"}})
	check_eq(Karma.value(h), -25.0, "пепел лёг")
	check(Interp.eval_trigger(ctx, ctx.root, {"karma_tier": "tainted"}), "запятнанный пеплом")
	check(Interp.eval_trigger(ctx, ctx.root, {"karma_tier": "<= tainted"}), "сравнение ступеней")
	var log: Array = h.vars.karma_log
	check_eq(str(log[-1][2]), "murder", "запись в Книге деяний")
	g.stat_cache.erase(h.id)
	check(Stats.char_stats(g, h).has("monthly_piety"), "ступень даёт модификаторы")
	# Пепел сам не тает
	for i in 12:
		g.on_action("on_monthly_pulse", {"type": "character", "id": "harold"})
	check(Karma.value(h) <= -25.0, "пепел не тает сам")
	# исповедь и Пепелище снимают пепел, но не дают света
	Interp.run_effect(ctx, ctx.root, {"cleanse_ash": 15})
	check_eq(Karma.value(h), -10.0, "исповедь сняла пепел")
	Interp.run_effect(ctx, ctx.root, {"cleanse_ash": 40})
	check_eq(Karma.value(h), 0.0, "не выше нуля")
	Interp.run_effect(ctx, ctx.root, {"add_karma": 70})
	check_eq(str(Karma.tier_of(g, h).id), "solar", "солнечный")
	Interp.run_effect(ctx, ctx.root, {"add_karma": 500})
	check_eq(Karma.value(h), 100.0, "предел — сто")


func test_conscience_and_zealots() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	for t in ["callous", "sadistic"]:
		Chars.remove_trait(g, h, t)
	Chars.add_trait(g, h, "just")
	var s0 := float(h.stress)
	Karma.add(g, h, -20.0, "murder")
	check(float(h.stress) >= s0 + 15.0, "совестливого мучает грех (%.0f → %.0f)" % [s0, h.stress])
	Karma.add(g, h, -45.0, "murder")
	check_eq(str(Karma.tier_of(g, h).id), "ashen", "пепельный")
	var z: Dictionary = g.vassals_of("harold")[0]
	var op0 := Opinion.opinion(g, z, h)
	Chars.add_trait(g, z, "zealous")
	g.stat_cache.erase("op:%s>%s" % [z.id, h.id])
	check(Opinion.opinion(g, z, h) < op0, "ревнитель веры холоден к пепельному")
	check(Karma.knows_exact(g, h, h), "свою душу знаешь точно")
	check(not Karma.knows_exact(g, h, z), "чужую — лишь по ступени")


func test_deeds_in_data() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var victim: Dictionary = g.living().filter(func(c): return c.id != "harold" and c.titles.is_empty() and Chars.is_adult(g, c) and not Chars.is_close_family(g, h, c))[0]
	Prison.imprison(g, h, victim)
	var def: Dictionary = g.content.get_def("interactions", "execute_prisoner")
	Interactions.execute(g, def, h, victim)
	check(Karma.value(h) <= -15.0, "казнь без вины — пепел (%.0f)" % Karma.value(h))
	var alms: Dictionary = g.content.get_def("decisions", "give_alms")
	h.gold = 500.0
	var k0 := Karma.value(h)
	check(Decisions.take(g, alms, h), "милостыня")
	check(Karma.value(h) > k0, "милостыня — шаг к Свету")
	# паломничество к Пепелищу видно лишь с пеплом на душе
	var pil: Dictionary = g.content.get_def("decisions", "ash_pilgrimage")
	check(Decisions.is_shown(g, pil, h), "паломничество к Пепелищу доступно грешнику")
	var k1 := Karma.value(h)
	h.gold = 500.0
	check(Decisions.take(g, pil, h), "паломничество совершено")
	check(Karma.value(h) > k1, "у Пепелища пепел сходит")


func test_nature_of_soul() -> void:
	var g := TestEnv.engine().new_game("b1066", 5)
	var kind := g.living().filter(func(c): return Chars.is_adult(g, c) and c.traits.has("compassionate") and not c.traits.has("sadistic") and not c.traits.has("callous"))
	var cruel := g.living().filter(func(c): return Chars.is_adult(g, c) and c.traits.has("callous") and not c.traits.has("compassionate"))
	check(not kind.is_empty() and not cruel.is_empty(), "есть добрые и чёрствые")
	check(kind.all(func(c): return Karma.value(c) > -10.0), "добрые начинают светлее")
	check(cruel.all(func(c): return Karma.value(c) < 10.0), "чёрствые — темнее")
	var drift: Variant = g.def_val("karma.trait_drift", {})
	var c0: Dictionary = kind.filter(func(c): return Karma._by_traits(c, drift) > 0.0)[0]
	var k0 := Karma.value(c0)
	for m in 13:
		Karma.monthly_char(g, c0)
		g.state.date += 30
	check(Karma.value(c0) > k0, "за год сострадательный светлеет")


func test_miniature() -> void:
	var g := _game()
	for k in [-100.0, -30.0, 0.0, 45.0, 100.0]:
		var img := Image.new()
		check_eq(img.load_svg_from_string(SoulPanel.svg(g, k), 1.0), OK, "миниатюра рисуется (%d)" % roundi(k))
	check(SoulPanel._angle(g, 100.0) < 0.0 and SoulPanel._angle(g, -100.0) > 0.0, "Свет клонит весы влево, Пепел — вправо")

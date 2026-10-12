extends TestCase
## Мод «Киберимпланты»: вживление и извлечение, человечность и черты,
## киберпсихоз, кибер-конечность вместо потерянной, скрипт, мнение набожных.

var M: Script = load("res://mods/cyberware/scripts/main.gd")


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func test_install_and_remove() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	h.gold = 1000.0
	var h0: float = M.humanity(g, h)
	var pr0 := Stats.stat(g, h, "prowess")
	check(M.blockers(g, h, "reflex_tuner").is_empty(), "можно вживить")
	check(M.install(g, h, "reflex_tuner") != "", "вживлён")
	check(M.has_implant(g, h, "reflex_tuner"), "имплант на месте")
	check_eq(float(h.gold), 880.0, "оплачен")
	check_eq(M.humanity(g, h), h0 - 6.0, "съел человечность")
	check(Stats.stat(g, h, "prowess") >= pr0 + 3.0 - 0.001, "модификаторы действуют")
	check(not M.blockers(g, h, "reflex_tuner").is_empty(), "дважды не вживить")
	# система вмещает ограниченное число
	M.install(g, h, "neofiber")
	check(not M.blockers(g, h, "calm_regulator").is_empty(), "в нервной системе два слота")
	check(M.remove(g, h, "reflex_tuner", true), "извлечён")
	check(not M.has_implant(g, h, "reflex_tuner"), "больше нет")
	check_eq(float(h.gold), 880.0 - 220.0 - M.removal_cost(g), "операция извлечения оплачена")


func test_humanity_traits_and_psychosis() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var base: float = M.humanity_max(g, h)
	Chars.add_trait(g, h, "calm")
	g.stat_cache.erase(h.id)
	check(M.humanity_max(g, h) > base, "спокойный выдерживает больше хрома")
	for iid in ["overmind", "chrono_booster", "neural_crown", "sickle_blades", "synth_heart", "optical_camo", "oracle_eye"]:
		M.install(g, h, iid, true)
	check(M.humanity(g, h) < 40.0, "много хрома — мало человечности")
	check(M.status(g, h) != "stable", "нестабилен")
	var got := false
	for _i in 400:
		M._condition(g, h)
		if h.traits.has("cyberpsychosis"):
			got = true
			break
	if M.humanity(g, h) < 20.0:
		check(got, "на грани — киберпсихоз")
	# вернул человечность — со временем отпускает
	for iid in ["overmind", "chrono_booster", "neural_crown", "sickle_blades", "synth_heart", "optical_camo", "oracle_eye"]:
		M.remove(g, h, iid)
	if got:
		var healed := false
		for _i in 400:
			M._condition(g, h)
			if not h.traits.has("cyberpsychosis"):
				healed = true
				break
		check(healed, "киберпсихоз отступает")


func test_cyber_limb_cures_maimed() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	Chars.add_trait(g, h, "maimed")
	check(h.traits.has("maimed"), "искалечен")
	M.install(g, h, "power_fists", true)
	check(not h.traits.has("maimed"), "кибер-рука вместо потерянной")


func test_script_and_opinion() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var ctx := ScriptContext.make(g, {"type": "character", "id": "harold"})
	Interp.run_effect(ctx, ctx.root, {"install_implant": "hawk_optics"})
	check(Interp.eval_trigger(ctx, ctx.root, {"has_implant": "hawk_optics", "num_implants": ">= 1", "humanity": "< 100"}), "условия и значения")
	Interp.run_effect(ctx, ctx.root, {"install_implant": "biomonitor"})
	# набожные не терпят хрома
	var zealot: Variant = null
	for c in g.living():
		if c.id != "harold" and c.traits.has("zealous"):
			zealot = c
			break
	if zealot != null:
		var labels := Opinion.breakdown(g, zealot, h).map(func(x): return str(x.get("label", "")))
		check(labels.has(g.loc.t("cyber.opinion_chrome")), "«богомерзкое железо» в мнении набожного")
	Interp.run_effect(ctx, ctx.root, {"remove_implant": "random"})
	check_eq(M.implants_of(g, h).size(), 1, "случайный имплант извлечён")


func test_save_and_ai() -> void:
	var e := TestEnv.engine()
	var g := e.new_game("b1066", 7)
	var w: Dictionary = g.ch("william")
	M.install(g, w, "berserk", true)
	var res := e.load_game(SaveGame.serialize(g))
	check(res.error == "", res.error)
	var g2: Game = res.game
	check(M.has_implant(g2, g2.ch("william"), "berserk"), "импланты сохраняются")
	# ИИ с деньгами иногда решается на хром
	var bought := [0]
	e.hooks.on("cyberware.installed", func(_p): bought[0] += 1)
	for r in g.rulers():
		r.gold = 2000.0
		for _i in 20:
			M._ai_buy(g, r)
		if bought[0] > 0:
			break
	check(bought[0] > 0, "ИИ покупает импланты")

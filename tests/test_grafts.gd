extends TestCase
## Мод «Железо и плоть»: вживление и извлечение, стойкость и черты, одержимость
## и экзорцизм, железная рука вместо потерянной, скрипт, мнение набожных.

var M: Script = load("res://mods/grafts/scripts/main.gd")

const HEAVY := ["wisdom_stone", "star_iron_heart", "blade_arm", "dragon_scales", "giant_bones", "dragon_blood", "raven_eye", "rune_of_tyr", "quicksilver", "skull_runes", "wire_sinews", "iron_jaw", "silver_ribs"]


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func test_install_and_remove() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	h.gold = 1000.0
	var s0: float = M.fortitude(g, h)
	var pr0 := Stats.stat(g, h, "prowess")
	check(M.blockers(g, h, "wire_sinews").is_empty(), "можно вживить")
	check(M.install(g, h, "wire_sinews") != "", "вживлено")
	check(M.has_graft(g, h, "wire_sinews"), "вживление на месте")
	check_eq(float(h.gold), 870.0, "оплачено")
	check_eq(M.fortitude(g, h), s0 - 6.0, "подтачивает стойкость")
	check(Stats.stat(g, h, "prowess") >= pr0 + 3.0 - 0.001, "модификаторы действуют")
	check(not M.blockers(g, h, "wire_sinews").is_empty(), "дважды не вживить")
	# часть тела вмещает ограниченное число
	M.install(g, h, "gut_tendons")
	check(not M.blockers(g, h, "stag_sinews").is_empty(), "в жилах два места")
	check(M.remove(g, h, "wire_sinews", true), "извлечено")
	check(not M.has_graft(g, h, "wire_sinews"), "больше нет")
	check_eq(float(h.gold), 870.0 - 60.0 - M.removal_cost(g), "операция извлечения оплачена")


func test_fortitude_traits_possession_and_exorcism() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var base: float = M.fortitude_max(g, h)
	Chars.add_trait(g, h, "calm")
	g.stat_cache.erase(h.id)
	check(M.fortitude_max(g, h) > base, "спокойный выдерживает больше железа")
	for gid in HEAVY:
		M.install(g, h, gid, true)
	check(M.fortitude(g, h) < 40.0, "много железа — мало стойкости")
	check(M.status(g, h) != "whole", "стойкость в смятении")
	var got := false
	for _i in 400:
		M._condition(g, h)
		if h.traits.has("iron_possession"):
			got = true
			break
	check(M.fortitude(g, h) < 20.0, "стойкость на грани")
	check(got, "на грани — одержимость")
	if got:
		check_eq(M.status(g, h), "possessed", "статус — одержимость")
		h.gold = 500.0
		check(M.exorcise(g, h), "экзорцизм")
		check(not h.traits.has("iron_possession"), "бесы изгнаны")
		check_eq(float(h.gold), 500.0 - M.exorcism_cost(g), "экзорцист оплачен")
		Chars.add_trait(g, h, "iron_possession")
	# вернул стойкость — со временем отпускает
	for gid in HEAVY:
		M.remove(g, h, gid)
	if got:
		var healed := false
		for _i in 400:
			M._condition(g, h)
			if not h.traits.has("iron_possession"):
				healed = true
				break
		check(healed, "одержимость отступает")


func test_iron_limb_cures_maimed() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	Chars.add_trait(g, h, "maimed")
	check(h.traits.has("maimed"), "искалечен")
	M.install(g, h, "iron_hand", true)
	check(not h.traits.has("maimed"), "железная рука вместо потерянной")


func test_script_and_opinion() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var ctx := ScriptContext.make(g, {"type": "character", "id": "harold"})
	Interp.run_effect(ctx, ctx.root, {"install_graft": "glass_eye"})
	check(Interp.eval_trigger(ctx, ctx.root, {"has_graft": "glass_eye", "num_grafts": ">= 1", "fortitude": "< 100"}), "условия и значения")
	Interp.run_effect(ctx, ctx.root, {"install_graft": "galen_humors"})
	# набожные косятся на железных людей
	var zealot: Variant = null
	for c in g.living():
		if c.id != "harold" and c.traits.has("zealous"):
			zealot = c
			break
	if zealot != null:
		var labels := Opinion.breakdown(g, zealot, h).map(func(x): return str(x.get("label", "")))
		check(labels.has(g.loc.t("grafts.opinion_iron")), "«железо в плоти» в мнении набожного")
	Interp.run_effect(ctx, ctx.root, {"remove_graft": "random"})
	check_eq(M.grafts_of(g, h).size(), 1, "случайное вживление извлечено")


func test_content_is_complete() -> void:
	var g := _game()
	for d in g.content.all("grafts"):
		check(g.content.has("body_parts", str(d.get("part"))), "часть тела вживления %s" % d.id)
		check(g.loc.raw("graft." + str(d.id)) != null, "название вживления %s" % d.id)
		check(g.loc.raw("graft_desc." + str(d.id)) != null, "описание вживления %s" % d.id)
	for p in g.content.all("body_parts"):
		check(g.loc.raw("body_part." + str(p.id)) != null, "название части тела %s" % p.id)
	for st in ["whole", "troubled", "brink", "possessed"]:
		check(g.loc.raw("grafts.status_" + st) != null, "статус стойкости %s" % st)


func test_save_and_ai() -> void:
	var e := TestEnv.engine()
	var g := e.new_game("b1066", 7)
	var w: Dictionary = g.ch("william")
	M.install(g, w, "lion_heart", true)
	var res := e.load_game(SaveGame.serialize(g))
	check(res.error == "", res.error)
	var g2: Game = res.game
	check(M.has_graft(g2, g2.ch("william"), "lion_heart"), "вживления сохраняются")
	# ИИ с деньгами иногда решается на вживление
	var bought := [0]
	e.hooks.on("grafts.installed", func(_p): bought[0] += 1)
	for r in g.rulers():
		r.gold = 2000.0
		for _i in 20:
			M._ai_buy(g, r)
		if bought[0] > 0:
			break
	check(bought[0] > 0, "ИИ решается на вживления")

extends TestCase
## Сражение в ядре: перестрелка, сеча по дням, слом и погоня. Большее войско
## побеждает; пикинёры держат тяжёлую конницу; втрое меньшее войско сечи не
## принимает; трус ломается раньше; бой в войне оставляет отчёт с потерями по
## видам войск и поле битвы на карте, а рыцари, сошедшиеся в поединке,
## получают свои судьбы.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _params(g: Game) -> Dictionary:
	var params: Dictionary = g.defines.battle.duplicate()
	for k in ["chase_min", "chase_max", "loser_commander_death", "winner_commander_death", "personal_example_safe", "personal_example_wound"]:
		params[k] = g.def_num("military." + k, 0.0)
	return params


func _levy(g: Game, n: int) -> Dictionary:
	var u: Dictionary = g.defines.battle.levy.duplicate()
	u.merge({"key": "levy", "type": "levy", "category": "levy", "men": n, "levy": true, "quality": 1.0})
	return u


func _reg(g: Game, t: String, n: int) -> Dictionary:
	var d: Dictionary = g.content.get_def("regiment_types", t)
	var u := Battle.profile(g, t).duplicate()
	u.merge({"key": t, "type": t, "category": d.category, "men": n, "quality": 1.0, "counters": d.get("counters", {})}, true)
	return u


## Доля побед первой стороны за n боёв.
func _wins(g: Game, a: Array, b: Array, n: int, ca := {}, cb := {}) -> float:
	var won := 0
	for i in n:
		var s0 := {"units": a, "knights": []}
		var s1 := {"units": b, "knights": []}
		if not ca.is_empty():
			s0["commander"] = ca
		if not cb.is_empty():
			s1["commander"] = cb
		var r: Dictionary = Battle.core().fight({"seed": i + 1, "params": _params(g), "sides": [s0, s1]})
		if int(r.winner) == 0:
			won += 1
	return float(won) / n


func test_bigger_wins_and_report() -> void:
	var g := _game()
	check(Battle.core() != null, "ядро сражений собрано")
	check(_wins(g, [_levy(g, 8000)], [_levy(g, 5000)], 40) > 0.9, "большее войско побеждает")
	var r: Dictionary = Battle.core().fight({"seed": 7, "params": _params(g), "sides": [{"units": [_levy(g, 5000)]}, {"units": [_levy(g, 5000)]}]})
	check(int(r.days) >= 2, "равные бьются не меньше двух дней (%d)" % int(r.days))
	check(r.log.size() >= 3 and r.log[0].phase == "skirmish" and r.log[1].phase == "melee", "ход боя: перестрелка, сеча")
	check(r.events.any(func(e): return e.kind in ["broke", "withdrew"]), "одна сторона ломается или отходит")
	var u: Dictionary = r.units[int(r.winner)][0]
	check(int(u.left) < int(u.men), "у победителя тоже потери")


func test_pikes_hold_cavalry() -> void:
	var g := _game()
	var cav := [_levy(g, 4000), _reg(g, "heavy_cavalry", 500)]
	var plain := _wins(g, cav, [_levy(g, 5000)], 60)
	var pikes := _wins(g, cav, [_levy(g, 4500), _reg(g, "pikemen", 500)], 60)
	check(pikes < plain, "пикинёры держат тяжёлую конницу (без пик %.0f%%, с пиками %.0f%%)" % [plain * 100, pikes * 100])


func test_outnumbered_refuses() -> void:
	var g := _game()
	var r: Dictionary = Battle.core().fight({"seed": 3, "params": _params(g), "sides": [{"units": [_levy(g, 9000)]}, {"units": [_levy(g, 2000)]}]})
	check_eq(int(r.winner), 0, "огромное войско берёт верх")
	check(r.events.any(func(e): return e.kind == "refused" and int(e.side) == 1), "малое войско сечи не принимает")
	check(float(r.lost[1]) / 2000.0 <= 0.45, "и отходит с умеренными потерями (%d из 2000)" % int(r.lost[1]))


func test_craven_breaks_first() -> void:
	var g := _game()
	var brave := {"id": "a", "martial": 6, "craven": false}
	var craven := {"id": "b", "martial": 6, "craven": true}
	var even := _wins(g, [_levy(g, 5000)], [_levy(g, 5000)], 80, brave, brave)
	var vs_craven := _wins(g, [_levy(g, 5000)], [_levy(g, 5000)], 80, brave, craven)
	check(vs_craven > even + 0.15, "трус ломается первым (%.0f%% → %.0f%%)" % [even * 100, vs_craven * 100])


func test_battle_in_war() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var ts := Wars.available_war_targets(g, w, h.id)
	check(not ts.is_empty(), "у Вильгельма есть повод против Гарольда")
	var war: Variant = Wars.declare_war(g, w, ts[0])
	check(war != null, "война объявлена")
	var aw: Variant = Military.raise_army(g, w)
	var ah: Variant = Military.raise_army(g, h)
	check(aw != null and ah != null, "обе армии подняты")
	ah.location = aw.location
	var men := [int(aw.size), int(ah.size)]
	var seen := [null]
	g.engine.hooks.on("battle", func(p): seen[0] = p.get("report"), 0, "test")
	Military._resolve_battles(g)
	var r: Variant = seen[0]
	check(r != null, "бой посчитало ядро")
	check(not war.battles.is_empty() and war.battles[-1].get("report") != null, "отчёт сохранён в войне")
	var after := [int(aw.size) if g.state.armies.has(aw.id) else 0, int(ah.size) if g.state.armies.has(ah.id) else 0]
	check(after[0] < men[0] or after[1] < men[1], "армии понесли потери")
	check(r.units[0].size() + r.units[1].size() >= 2, "потери по видам войск")
	# судьбы рыцарей из поединков применены
	for f in r.knights:
		var k: Variant = g.ch(f.id)
		if k == null:
			continue
		if f.fate == "killed":
			check(k.death != null, "рыцарь, павший в поединке, мёртв")
		elif f.fate == "captured":
			check(k.get("prison") != null or k.death != null, "взятый в плен рыцарь в темнице")
	# поле битвы на карте — с отчётом; через field_years лет его не будет
	var fields: Array = g.state.get("battlefields", [])
	check(not fields.is_empty() and fields[-1].get("report") != null and Battle.field(g, fields[-1].id) != null, "поле битвы на карте")
	var res := g.engine.load_game(SaveGame.serialize(g))
	check(res.error == "", res.error)
	var w2: Variant = res.game.state.wars.get(war.id)
	check(w2 == null or w2.battles[-1].get("report") != null, "отчёт битвы переживает сохранение")
	g.state.date += int(Data.num(g.defines.battle.field_years) * GameDate.DAYS_PER_YEAR) + 1
	Battle.prune_fields(g)
	check(g.state.battlefields.is_empty(), "старое поле битвы зарастает")

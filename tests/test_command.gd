extends TestCase
## Полководцы: перевес из военного дела, прибавок и навыков; навыки местности
## и роли; навыки в ядре (залпы, отход); перевес решает равный бой; навык
## обретается в бою; назначение полководца армии и выбор ИИ; сильные воители
## приходят в мир с навыками.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _sum(parts: Array) -> float:
	var v := 0.0
	for p in parts:
		v += float(p.value)
	return v


func _set_martial(g: Game, c: Dictionary, v: int) -> void:
	c.skills["martial"] = v
	g.touch(c)
	g.stat_cache.erase(c.id)


func _clear_skills(g: Game, c: Dictionary) -> void:
	for d in Command.traits_of(g, c):
		Chars.remove_trait(g, c, d.id)


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


func _cmd(id: String, adv: float, extra := {}) -> Dictionary:
	var c := {"id": id, "adv": adv, "craven": false}
	c.merge(extra, true)
	return c


func _fight(g: Game, seed: int, a: Array, b: Array, ca: Dictionary, cb: Dictionary) -> Dictionary:
	return Battle.core().fight({"seed": seed, "params": _params(g),
		"sides": [{"units": a, "knights": [], "commander": ca}, {"units": b, "knights": [], "commander": cb}]})


func test_advantage_parts_and_skills() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_clear_skills(g, h)
	_set_martial(g, h, 10)
	var base := _sum(Command.advantage_parts(g, h))
	check(base >= 10.0, "военное дело даёт перевес (%.1f)" % base)
	check(Command.advantage_parts(g, h).any(func(p): return p.key == "martial"), "в разборе есть военное дело")
	check(Chars.add_trait(g, h, "unstoppable"), "навык «неудержимый» получен")
	check_eq(_sum(Command.advantage_parts(g, h, null, false, false)), base, "в обороне «неудержимый» не помогает")
	check_eq(_sum(Command.advantage_parts(g, h, null, true, false)), base + 8.0, "нападая — +8")
	var p: Array = Command.advantage_parts(g, h, null, true, false).filter(func(x): return x.key == "trait")
	check(p.size() == 1 and p[0].trait == "unstoppable", "разбор называет навык")
	Chars.add_trait(g, h, "shock_master")
	Chars.add_trait(g, h, "volley_master")
	var sk := Command.skills(g, h)
	check_eq(float(sk.get("charge")), 0.6, "натиск складывается из черт")
	check_eq(float(sk.get("volleys")), 1.0, "лишний залп")
	check_eq(Command.traits_of(g, h).size(), 3, "три навыка полководца")
	var tip := Command.describe(g, Chars.trait_def(g, "shock_master"))
	check(tip != "" and tip.contains("60"), "подсказка навыка называет силу (%s)" % tip)
	var ctx := ScriptContext.make(g, {"type": "character", "id": h.id})
	check(absf(Interp.eval_value(ctx, ctx.root, "command_advantage") - _sum(Command.advantage_parts(g, h))) < 0.001, "значение command_advantage для условий")
	check_eq(Interp.eval_value(ctx, ctx.root, "num_command_skills"), 3.0, "значение num_command_skills")


func test_terrain_skill() -> void:
	var g := _game()
	if not g.land().ready():
		check(true, "карта местности не готова — пропуск")
		return
	var best := "c_sussex"
	var best_s := g.land().share(best, "forest")
	check(best_s > 0.5, "Суссекс лесист (%.2f)" % best_s)
	var h: Dictionary = g.ch("harold")
	_clear_skills(g, h)
	var plain := _sum(Command.advantage_parts(g, h, best))
	Chars.add_trait(g, h, "forest_leader")
	var forest := _sum(Command.advantage_parts(g, h, best))
	check(absf(forest - plain - 9.0 * best_s) < 0.01, "лесной навык — по доле леса (%.2f → %.2f)" % [plain, forest])
	check_eq(_sum(Command.advantage_parts(g, h)), plain, "вне поля навык местности молчит")


func test_advantage_decides_even_battle() -> void:
	var g := _game()
	var won := [0, 0]
	for i in 60:
		var r := _fight(g, i + 1, [_levy(g, 5000)], [_levy(g, 5000)], _cmd("a", 0), _cmd("b", 0))
		if int(r.winner) == 0:
			won[0] += 1
		r = _fight(g, i + 1, [_levy(g, 5000)], [_levy(g, 5000)], _cmd("a", 15), _cmd("b", 0))
		if int(r.winner) == 0:
			won[1] += 1
	check(won[1] > won[0] + 12, "перевес в 15 очков решает равный бой (%d → %d из 60)" % won)
	# перевес не всесилен: вдвое большее войско против лучшего полководца
	var big := 0
	for i in 40:
		var r := _fight(g, i + 1, [_levy(g, 5000)], [_levy(g, 9000)], _cmd("a", 10), _cmd("b", 0))
		if int(r.winner) == 1:
			big += 1
	check(big > 30, "почти вдвое большее войско всё равно берёт верх (%d из 40)" % big)


func test_core_skills() -> void:
	var g := _game()
	var archers := [_levy(g, 3000), _reg(g, "archers", 800)]
	var r0 := _fight(g, 5, archers, [_levy(g, 4000)], _cmd("a", 0), _cmd("b", 0))
	var r1 := _fight(g, 5, archers, [_levy(g, 4000)], _cmd("a", 0, {"ranged": 0.5, "volleys": 1}), _cmd("b", 0))
	var volleys: Array = Data.as_array(r1.events).filter(func(e): return e.kind == "volley" and int(e.side) == 0)
	check(not volleys.is_empty(), "мастер залпов даёт лишний залп")
	var hit := func(r: Dictionary) -> float: return float(r.log[0].lost[1])
	check(hit.call(r1) > hit.call(r0), "перестрелка мастера залпов злее (%d → %d)" % [int(hit.call(r0)), int(hit.call(r1))])
	# отход: проигравший с арьергардом теряет в погоне меньше
	var chase := [0.0, 0.0]
	for i in 30:
		for k in 2:
			var cb := _cmd("b", 0, {"rearguard": 0.5}) if k == 1 else _cmd("b", 0)
			var r := _fight(g, i + 1, [_levy(g, 6000)], [_levy(g, 4000)], _cmd("a", 0), cb)
			for e in r.events:
				if e.kind == "pursuit" and int(e.side) == 0:
					chase[k] += Data.num(e.get("n"))
	check(chase[1] < chase[0], "арьергард бережёт отходящих (%d → %d)" % [int(chase[0]), int(chase[1])])


func test_learn_in_battle() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	_clear_skills(g, h)
	g.defines.command["learn_chance_win"] = 1.0
	# защитник выстоял — урок стены щитов
	var report := {"winner": 1, "days": 3, "start": [6000, 5000], "lost": [2500, 900], "morale": [10, 30],
		"events": [], "sides": [{"owners": ["william"], "commander": null, "defending": false},
			{"owners": [h.id], "commander": h.id, "defending": true}]}
	check(Command.lessons(g, report, "c_kent", 1).has("shield_wall"), "оборона учит стене щитов")
	check(not Command.lessons(g, report, "c_kent", 1).has("unstoppable"), "а не натиску нападающего")
	Command.learn(g, report, "c_kent")
	check_eq(Command.traits_of(g, h).size(), 1, "полководец обрёл навык")
	check(report.events.any(func(e): return e.kind == "learned" and e.a == h.id), "в отчёте отмечено")
	# навыков не больше max_traits
	for t in ["hound_of_war", "inspirer", "volley_master", "rearguard"]:
		Chars.add_trait(g, h, t)
	var n := Command.traits_of(g, h).size()
	Command.learn(g, report, "c_kent")
	check_eq(Command.traits_of(g, h).size(), n, "сверх предела навыки не прибывают")


func test_appoint_and_ai() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var a: Variant = Military.raise_army(g, h)
	check(a != null, "армия поднята")
	var cands := Command.candidates(g, h, a.id)
	check(cands.any(func(x): return x.id == h.id), "хозяин среди возможных полководцев")
	var other: Variant = null
	for x in cands:
		if x.id != h.id:
			other = x
			break
	check(other != null, "есть кому отдать армию")
	check(Command.appoint(g, a, other.id), "назначение")
	check_eq(Military.commander_of(g, a).id, other.id, "армию ведёт назначенный")
	check(not Command.appoint(g, a, "william"), "чужого не назначить")
	var b: Variant = Military.raise_army(g, h)
	if b != null:
		check(not Command.candidates(g, h, b.id).any(func(x): return x.id == other.id), "кто ведёт одну армию, не ведёт другую")
	check(Command.appoint(g, a, null), "снять назначение")
	check_eq(Military.commander_of(g, a).id, h.id, "армию ведёт хозяин")
	# ИИ: отдаёт армию заметно лучшему полководцу
	_set_martial(g, h, 2)
	_clear_skills(g, h)
	_set_martial(g, other, 20)
	for t in ["shock_master", "inspirer"]:
		Chars.add_trait(g, other, t)
	check_eq(Command.best_for(g, h, a.id).id, other.id, "лучший полководец — сильный воитель")
	_set_martial(g, other, 3)
	_clear_skills(g, other)
	check_eq(Command.best_for(g, h, a.id).id, h.id, "без заметной разницы ведёт сам хозяин")


func test_side_commander_and_report() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var ts := Wars.available_war_targets(g, w, h.id)
	var war: Variant = Wars.declare_war(g, w, ts[0])
	check(war != null, "война объявлена")
	var aw: Variant = Military.raise_army(g, w)
	var ah: Variant = Military.raise_army(g, h)
	ah.location = aw.location
	var seen := [null]
	g.engine.hooks.on("battle", func(p): seen[0] = p.get("report"), 0, "test")
	Military._resolve_battles(g)
	var r: Variant = seen[0]
	check(r != null, "бой состоялся")
	for i in 2:
		var s: Dictionary = r.sides[i]
		if s.get("commander") != null:
			check(s.get("adv_parts") is Array and absf(_sum(s.adv_parts) - float(s.adv)) < 0.01, "перевес стороны %d с разбором" % i)
	var res := g.engine.load_game(SaveGame.serialize(g))
	check(res.error == "", res.error)


func test_start_skills() -> void:
	var g := _game()
	var mx := int(g.def_num("command.max_traits", 3))
	var with := 0
	for c in g.living():
		var n := Command.traits_of(g, c).size()
		check(n <= mx, "%s: навыков не больше предела" % c.id)
		if n > 0:
			with += 1
	check(with > 0, "сильные воители приходят с навыками (%d)" % with)
	check(with < g.living().size() / 3, "но навыки — у немногих (%d из %d)" % [with, g.living().size()])

extends TestCase
## Воинства: кому по пути и что нужно, чтобы собрать; стойкость от условий
## и событий, распад; умения в ядре сражений (ополчение не бежит, страх,
## охрана вождя, засада, уход без погони, заклинания); воинство вождя
## стороны в бою (сила против еретиков, перевес вожака стаи); особые отряды;
## павшие встают; ИИ собирает воинство.


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


func _fight(g: Game, seed: int, a: Dictionary, b: Dictionary, params: Variant = null) -> Dictionary:
	return Battle.core().fight({"seed": seed, "params": params if params != null else _params(g), "sides": [a, b]})


func _count(r: Dictionary, kind: String, side: int) -> int:
	return Data.as_array(r.events).filter(func(e): return e.kind == kind and int(e.side) == side).size()


func test_adopt_and_replace() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var ids := Hosts.available(g, h).map(func(d): return d.id)
	check(ids.has("kin_host"), "родовая дружина — роду Годвинов по пути (%s)" % str(ids))
	var kin: Dictionary = Hosts.def_of(g, "kin_host")
	h.prestige = 0.0
	g.touch(h)
	check(not Hosts.adopt_blockers(g, h, kin).is_empty(), "без славы не собрать")
	check(not Hosts.adopt(g, h, "kin_host"), "и не собирается")
	h.prestige = 1000.0
	g.touch(h)
	check(Hosts.adopt(g, h, "kin_host"), "собрана")
	check_eq(float(h.prestige), 800.0, "слава уплачена")
	check_eq(Hosts.active(g, h).id, "kin_host", "воинство действует")
	var ctx := ScriptContext.make(g, {"type": "character", "id": h.id})
	check(Interp.eval_trigger(ctx, ctx.root, {"has_host": "kin_host"}), "условие has_host")
	check(Interp.eval_value(ctx, ctx.root, "host_devotion") > 0.0, "значение host_devotion")
	check(not Hosts.adopt_blockers(g, h, kin).is_empty(), "второй раз то же не собрать")
	# особые отряды — только своему воинству
	var sworn: Dictionary = g.content.get_def("regiment_types", "kin_sworn")
	var sun: Dictionary = g.content.get_def("regiment_types", "sun_guard")
	check(Regiments.is_type_shown(g, h, sworn), "родовые побратимы идут в родовую дружину")
	check(not Regiments.is_type_shown(g, h, sun), "а солнечная стража — нет")
	# новое воинство вместо прежнего
	check(Hosts.adopt(g, h, "forest_host", true), "собрано другое")
	check_eq(Hosts.host_of(h).id, "forest_host", "прежнее распалось")
	Interp.run_effect(ctx, ctx.root, {"set_host": "none"})
	check(Hosts.host_of(h) == null, "эффект set_host: none распускает")


func test_devotion_rules_and_dissolve() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	Hosts.adopt(g, h, "ash_host", true)
	var d0 := float(Hosts.host_of(h).devotion)
	Hosts.monthly_char(g, h)
	check_eq(float(Hosts.host_of(h).devotion), d0 - 6.0, "пепельному воинству нужна кровь: тает без побед")
	Hosts.on_event(g, h, "battle_won")
	check_eq(float(Hosts.host_of(h).devotion), d0 - 6.0 + 20.0, "победа его питает")
	Hosts.host_of(h).devotion = 3.0
	Hosts.monthly_char(g, h)
	check(Hosts.host_of(h) == null, "стойкость кончилась — воинство распалось")
	# лес не рубить
	Hosts.adopt(g, h, "forest_host", true)
	var f0 := float(Hosts.host_of(h).devotion)
	g.emit("land.work_done", {"province": "c_sussex", "work": "clear_forest", "by": h.id, "cells": 3})
	check_eq(float(Hosts.host_of(h).devotion), f0 - 25.0, "сведённый лес бьёт по лесному войску")
	g.emit("land.work_done", {"province": "c_sussex", "work": "drain_marsh", "by": h.id, "cells": 3})
	check_eq(float(Hosts.host_of(h).devotion), f0 - 25.0, "иные работы ему не мешают")


func test_core_abilities() -> void:
	var g := _game()
	# ополчение не бежит
	var fled := [0, 0]
	for i in 30:
		var r := _fight(g, i + 1, {"units": [_levy(g, 5000)]}, {"units": [_levy(g, 5000)]})
		fled[0] += _count(r, "levy_fled", 0) + _count(r, "levy_fled", 1)
		r = _fight(g, i + 1, {"units": [_levy(g, 5000)], "host": {"levy_hold": true}}, {"units": [_levy(g, 5000)], "host": {"levy_hold": true}})
		fled[1] += _count(r, "levy_fled", 0) + _count(r, "levy_fled", 1)
	check(fled[0] > 0 and fled[1] == 0, "стойкое воинство не бежит (%d → %d)" % fled)
	# страх: ополчение врага бежит раньше
	var won := [0, 0]
	for i in 40:
		if int(_fight(g, i + 1, {"units": [_levy(g, 5000)]}, {"units": [_levy(g, 5000)]}).winner) == 0:
			won[0] += 1
		var r := _fight(g, i + 1, {"units": [_levy(g, 5000)], "host": {"terror": 18}}, {"units": [_levy(g, 5000)]})
		if int(r.winner) == 0:
			won[1] += 1
		if i == 0:
			check(_count(r, "terror", 0) == 1, "страх отмечен в отчёте")
	check(won[1] > won[0], "перед страшным воинством враг ломается (%d → %d из 40)" % won)
	# засада: перестрелка злее; заклинания — до залпов
	var a := _fight(g, 3, {"units": [_levy(g, 4000)]}, {"units": [_levy(g, 4000)]})
	var b := _fight(g, 3, {"units": [_levy(g, 4000)], "host": {"ambush": 0.35}}, {"units": [_levy(g, 4000)]})
	check(float(b.log[0].lost[1]) > float(a.log[0].lost[1]), "из засады бьют сильнее")
	var m := _fight(g, 3, {"units": [_levy(g, 4000)], "host": {"spells": 400}}, {"units": [_levy(g, 4000)]})
	check(_count(m, "spells", 0) == 1 and float(m.log[0].lost[1]) > float(a.log[0].lost[1]), "заклинания разят до залпов")
	# уход без погони
	var chase := 0.0
	var slipped := 0
	for i in 20:
		var r := _fight(g, i + 1, {"units": [_levy(g, 7000)]}, {"units": [_levy(g, 3000)], "host": {"slip": true}})
		chase += float(Data.as_array(r.events).filter(func(e): return e.kind == "pursuit").size())
		slipped += _count(r, "slipped", 1)
	check(chase == 0.0 and slipped > 0, "лесное войско уходит без погони")
	# охрана вождя: гибель — только если войско бежало
	var p := _params(g)
	p["winner_commander_death"] = 1.0
	var guard := _fight(g, 5, {"units": [_levy(g, 8000)], "commander": {"id": "x", "adv": 0}, "host": {"guard": true}}, {"units": [_levy(g, 3000)]}, p)
	check(int(guard.winner) == 0 and _count(guard, "commander_fell", 0) == 0 and _count(guard, "guarded", 0) == 1, "родовая дружина заслоняет вождя")


func test_side_input() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	h.faith = "sun_rite"
	h.piety = 500.0
	g.touch(h)
	check(Hosts.adopt(g, h, "sun_host"), "Воинство Солнца собрано")
	var ah: Variant = Military.raise_army(g, h)
	var aw: Variant = Military.raise_army(g, w)
	# против еретика — сильнее
	w.faith = "sun_rite"
	g.touch(w)
	var s0 := Battle._side(g, [ah], [aw], "c_kent", false, true)
	w.faith = "east_rite"
	g.touch(w)
	var s1 := Battle._side(g, [ah], [aw], "c_kent", false, true)
	check(absf(float(s1.mult) / float(s0.mult) - 1.2) < 0.001, "против еретиков бьют злее")
	check(not s0.host.has("levy_hold"), "без жреца ополчение может бежать")
	# жрец при войске
	var pool := g.courtiers_of(h.id).filter(func(x): return Chars.is_adult(g, x) and x.faith == h.faith)
	if pool.is_empty():
		pool = g.courtiers_of(h.id).filter(func(x): return Chars.is_adult(g, x))
		for x in pool:
			x.faith = h.faith
			g.touch(x)
	check(not pool.is_empty(), "есть кого посадить капелланом")
	Council.appoint(g, h, "court_chaplain", pool[0].id)
	var s2 := Battle._side(g, [ah], [aw], "c_kent", false, true)
	check(bool(s2.host.get("levy_hold", false)), "при жреце ополчение не бежит")
	check(s2.get("host_id") == "sun_host" and s2.get("host_owner") == h.id, "воинство стороны в отчёте")
	# вожак стаи ведёт доблестью
	h.skills.prowess = 25
	h.skills.martial = 5
	g.touch(h)
	g.stat_cache.erase(h.id)
	var ci := Battle._commander_input(g, h, [ah], "c_kent", true, false, {"pack_leader": 1.0})
	check(ci.parts.any(func(x): return x.key == "pack" and float(x.value) >= 19.0), "вожак стаи берёт перевес доблестью")


func test_rise_and_report() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var a: Variant = Military.raise_army(g, h)
	var n0 := int(a.size)
	var rep := {"winner": 0, "days": 3, "lost": [500, 1500], "events": [],
		"sides": [{"owners": [h.id], "armies": [a.id], "host_owner": h.id, "rise": 0.12}, {"owners": [], "armies": []}]}
	Hosts.after_battle(g, rep, "c_kent")
	check_eq(int(a.size), n0 + 240, "павшие встали в строй")
	check(rep.events.any(func(e): return e.kind == "risen" and int(e.n) == 240), "в отчёте — вставшие")
	check(not Battle.guarded({"winner": 1, "broke": true, "sides": [{"guard": true}, {}]}, 0), "бежавших дружина не спасает")
	check(Battle.guarded({"winner": 1, "broke": false, "sides": [{"guard": true}, {}]}, 0), "отошедших — спасает")


func test_ai_adopts() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	h.prestige = 2000.0
	h.piety = 2000.0
	g.touch(h)
	g.defines.hosts["ai_adopt_chance"] = 1.0
	Hosts.monthly_char(g, h)
	check(Hosts.host_of(h) != null, "ИИ собрал воинство")

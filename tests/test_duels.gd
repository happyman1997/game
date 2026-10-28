extends TestCase
## Схватка: профиль бойца из доблести, черт и вещей; правила обмена (натиск
## сминает хитрость, хитрость обходит защиту, защита ловит натиск); оценка
## шанса сходится с прогоном боёв; ИИ читает привычки противника; бой ИИ
## решается сразу и оставляет следы; бой игрока ждёт его ходов, подсказки
## вернее у хитрого; победитель решает судьбу павшего; бой с врагом из
## данных; бой насмерть; автопилот доигрывает бой.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _fighter(g: Game, prowess: float, traits: Array = []) -> Dictionary:
	var c := Chars.create_character(g, {"culture": "saxon", "faith": g.ch("harold").faith, "age": 30, "female": false})
	c.traits = traits.duplicate()
	c.skills["prowess"] = prowess
	c.skills["intrigue"] = 5
	g.stat_cache.erase(c.id)
	g.stat_cache.erase("ai:" + c.id)
	return c


func test_profile_from_prowess_traits_and_gear() -> void:
	var g := _game()
	var a := _fighter(g, 10)
	var p := Duels.profile(g, a)
	check(p.attack > 0 and p.guard > 0 and p.feint > 0 and p.vigor > 0, "у бойца три стойки и стойкость")
	var b := _fighter(g, 10, ["deceitful"])
	check(Duels.profile(g, b).feint > p.feint, "лживый хитрее в бою")
	var s := _fighter(g, 10, ["strong"])
	check(Duels.profile(g, s).vigor > p.vigor, "силач стойче")
	var it := Artifacts.create(g, "sword", "famed", a)
	Artifacts.equip(g, a, it)
	g.stat_cache.erase(a.id)
	var p2 := Duels.profile(g, a)
	check(p2.attack > p.attack and p2.guard > p.guard, "меч прибавляет к натиску и защите")
	var parts := Duels.stance_parts(g, a, "attack")
	check(parts.size() >= 2, "разбор силы натиска: доблесть и меч")


func test_exchange_rules() -> void:
	var g := _game()
	var k := Duels.cfg(g)
	var pa := Duels.profile(g, _fighter(g, 10))
	var pb := Duels.profile(g, _fighter(g, 10))
	var rng := Rng.from_seed(1)
	var f := Duels._new_fight(pa, pb, "duel")
	var e := Duels.exchange(k, f, "attack", "feint", rng)
	check(e.w == 0 and e.d[1] > 0 and e.d[0] == 0, "натиск сминает хитрость")
	e = Duels.exchange(k, f, "attack", "guard", rng)
	check(e.w == 1 and e.d[0] > 0 and e.d[1] == 0, "защита ловит натиск")
	e = Duels.exchange(k, f, "feint", "guard", rng)
	check(e.w == 0 and e.d[1] > 0, "хитрость обходит защиту")
	e = Duels.exchange(k, f, "attack", "attack", rng)
	check(e.d[0] > 0 and e.d[1] > 0, "два натиска — бьют оба")
	var before: Array = f.vig.duplicate()
	e = Duels.exchange(k, f, "guard", "guard", rng)
	check(e.d[0] == 0 and e.d[1] == 0 and f.vig[0] >= before[0], "две защиты — кружат и переводят дух")
	check_eq(int(f.round), 5, "пять обменов в журнале")


func test_odds_match_simulation() -> void:
	var g := _game()
	var base := Duels.profile(g, _fighter(g, 10))
	var prev := 0
	for pr in [4.0, 8.0, 12.0, 16.0]:
		var p := Duels.profile(g, _fighter(g, pr))
		var est := Duels.profile_odds(g, p, base, "duel")
		var sim := Duels.simulated_odds(g, p, base, "duel", 400, str(pr))
		check(absi(est - sim) <= 10, "оценка шанса (%d%%) близка к прогону (%d%%) при доблести %d" % [est, sim, pr])
		check(est > prev, "чем доблестнее, тем выше шанс")
		prev = est


func test_ai_reads_habits() -> void:
	var g := _game()
	var k := Duels.cfg(g)
	var f := Duels._new_fight(Duels.profile(g, _fighter(g, 10)), Duels.profile(g, _fighter(g, 10)), "duel")
	f.max = [1000.0, 1000.0]
	f.vig = [1000.0, 1000.0]
	for i in 3:
		f.hist.append(["attack", "guard"])
	var rng := Rng.from_seed(3)
	var guards := 0
	for i in 300:
		if Duels.ai_stance(k, f, 1, rng) == "guard":
			guards += 1
	check(guards > 130, "кто всё время рвётся в натиск, того встречают защитой (%d из 300)" % guards)


func test_ai_duel_resolves_with_consequences() -> void:
	var g := _game()
	var a := _fighter(g, 14)
	var b := _fighter(g, 8)
	var got := []
	g.engine.hooks.on("duel", func(p): got.append(p), 0, "test")
	var pa := float(a.prestige)
	var w := Duels.duel(g, a, b)
	check(not w.is_empty(), "бой ИИ решается сразу")
	check(got.size() == 1 and got[0].mercy in ["spare", "wound", "kill", "none"], "сигнал duel с исходом: %s" % [got[0].mercy if not got.is_empty() else "—"])
	var win: Dictionary = got[0].winner
	var lose: Dictionary = got[0].loser
	check(win.id == w.id, "победитель тот же, что в сигнале")
	check(win.id != a.id or a.prestige > pa, "победителю — слава")
	check(Opinion.has_opinion_modifier(lose, win, "bested_in_duel") or lose.death != null, "побеждённый запомнил")
	check(Duels.pending(g).is_empty(), "бой ИИ не ждёт игрока")


func test_player_fight_waits_and_mercy() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var foe := _fighter(g, 10)
	foe.children = []
	var son := Chars.create_character(g, {"culture": "saxon", "faith": h.faith, "age": 20, "female": false, "father": foe.id})
	foe.children.append(son.id)
	Duels.duel(g, h, foe, {"champions": false})
	check_eq(Duels.pending(g).size(), 1, "игрок бьётся сам — бой ждёт его ходов")
	var f: Dictionary = Duels.pending(g)[0]
	check(f.tell in Duels.STANCES and f.tell_acc > 0, "противник чем-то себя выдаёт")
	# противник почти без сил, но не сдастся — храбрец
	f.vig[1] = 1.0
	f.prof[1].yields = false
	var guard := 0
	while f.phase == "fight" and guard < 20:
		Duels.player_move(g, f.uid, Duels.COUNTER[f.next[1]])
		guard += 1
	check_eq(str(f.phase), "mercy", "противник пал — игрок решает его судьбу")
	Duels.player_mercy(g, f.uid, "kill")
	check(foe.death != null, "убит по слову победителя")
	check(Opinion.has_opinion_modifier(son, h, "slew_my_kin"), "сын убитого не простит")
	check_eq(str(f.phase), "over", "бой окончен")
	Duels.dismiss(g, f.uid)
	check(Duels.pending(g).is_empty(), "окно закрыто")


func test_player_yields() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var foe := _fighter(g, 10)
	Duels.duel(g, h, foe, {"champions": false})
	var f: Dictionary = Duels.pending(g)[0]
	var pr := float(h.prestige)
	Duels.player_yield(g, f.uid)
	check_eq(str(f.phase), "over", "сдался — бой окончен, судьбу решил победитель")
	check(f.winner == 1 and str(f.how) == "yield", "верх за противником")
	check(h.prestige < pr, "сдаться — позор")


func test_tells_truer_for_the_cunning() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var foe := _fighter(g, 10)
	Duels.duel(g, h, foe, {"champions": false})
	var f: Dictionary = Duels.pending(g)[0]
	f.prof[0].feint = float(f.prof[1].feint) - 3.0
	Duels._prepare(g, f)
	var low := int(f.tell_acc)
	f.prof[0].feint = float(f.prof[1].feint) + 8.0
	Duels._prepare(g, f)
	check(int(f.tell_acc) > low, "хитрый читает противника вернее (%d%% против %d%%)" % [f.tell_acc, low])
	var hits := 0
	for i in 200:
		Duels._prepare(g, f)
		if f.tell == f.next[1]:
			hits += 1
	check(hits > 200 * (f.tell_acc - 15) / 100.0, "подсказка верна примерно с обещанным шансом (%d из 200)" % hits)


func test_fight_foe_and_outcome_effects() -> void:
	var g := _game()
	var c := _fighter(g, 30, ["strong", "brave"])
	var got := []
	g.engine.hooks.on("fight", func(p): got.append(p), 0, "test")
	var ctx := ScriptContext.make(g, {"type": "character", "id": c.id})
	Interp.run_effect(ctx, ctx.root, {"fight": {"foe": "wolf", "on_win": {"add_gold": 77}}})
	check(got.size() == 1 and got[0].foe == "wolf", "бой с волком состоялся")
	if not got.is_empty() and got[0].won:
		check(c.gold >= 77.0, "победа — исход on_win")
	check(Duels.foe_odds(g, c, "wolf") > Duels.foe_odds(g, _fighter(g, 4), "wolf"), "сильному волк не страшен")
	var lines := Interp.describe_effect(ctx, ctx.root, {"fight": {"foe": "man_eater"}})
	check(not lines.is_empty() and "%" in str(lines[0]), "подсказка показывает шанс: %s" % [lines])


func test_mortal_fight_kills() -> void:
	var g := _game()
	var a := _fighter(g, 20)
	var b := _fighter(g, 4)
	var w := Duels.duel(g, a, b, {"kind": "mortal"})
	var loser: Dictionary = b if w.id == a.id else a
	check(loser.death != null, "бой насмерть: проигравший гибнет")


func test_autopilot_finishes_fight() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	Duels.duel(g, h, _fighter(g, 10), {"champions": false})
	check(not Duels.pending(g).is_empty(), "бой ждёт игрока")
	g.autopilot = true
	g.tick()
	check(Duels.pending(g).is_empty(), "на автопилоте бой доигрывает ИИ")


func test_challenge_event() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var v: Dictionary = g.vassals_of(h.id)[0]
	v.skills["prowess"] = 14
	if not v.traits.has("arrogant"):
		v.traits.append("arrogant")
	g.stat_cache.clear()
	var dueled := [0]
	g.engine.hooks.on("duel", func(_p): dueled[0] += 1, 0, "test")
	check(g.events.fire("duel.0001", {"type": "character", "id": h.id}), "вассал бросает перчатку")
	check(dueled[0] <= 1, "поединок — не больше одного")

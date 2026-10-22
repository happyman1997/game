extends TestCase
## Общая проверка: шанс из основы и факторов (с разбором), стресс мешает,
## три исхода — удача, отчасти, провал; подсказка показывает шанс и исходы;
## учёный чаще находит право на землю в архивах, чем невежда.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _ctx(g: Game, c: Dictionary) -> ScriptContext:
	return ScriptContext.make(g, {"type": "character", "id": c.id})


const SPEC := {
	"skill": "learning",
	"base": 10,
	"add": [{"desc": "skill.learning", "value": {"value": "learning", "multiply": 4}}],
	"success": {"add_gold": 10},
	"partial": {"add_gold": 5},
	"failure": {"add_gold": -1},
}


func test_odds_and_breakdown() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	h.skills["learning"] = 10
	h.stress = 0.0
	g.stat_cache.clear()
	var ctx := _ctx(g, h)
	var o := Checks.odds(ctx, ctx.root, SPEC)
	check_eq(o.success, 10.0 + 4.0 * Stats.skill(g, h, "learning"), "шанс — основа плюс учёность")
	check(o.partial > 0.0 and is_equal_approx(o.success + o.partial + o.failure, 100.0), "три исхода в сумме дают 100")
	check(o.parts.size() >= 2, "разбор: основа и навык")
	h.stress = 200.0
	var o2 := Checks.odds(ctx, ctx.root, SPEC)
	check(o2.success < o.success, "стресс мешает")
	var no_partial: Dictionary = SPEC.duplicate()
	no_partial.erase("partial")
	check_eq(Checks.odds(ctx, ctx.root, no_partial).partial, 0.0, "без блока partial — только удача и провал")


func test_outcomes_follow_odds() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var ctx := _ctx(g, h)
	var seen := {}
	for i in 300:
		seen[Checks.run(ctx, ctx.root, SPEC)] = true
	check(seen.has("success") and seen.has("partial") and seen.has("failure"), "выпадают все три исхода")
	var sure := {"base": 200, "success": {"add_gold": 1}, "failure": {"add_gold": -1}}
	var hits := 0
	for i in 100:
		if Checks.run(ctx, ctx.root, sure) == "success":
			hits += 1
	check(hits >= 85 and hits < 100, "шанс не выше предела: даже верное дело иногда срывается (%d из 100)" % hits)


func test_describe_shows_chance_and_outcomes() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var ctx := _ctx(g, h)
	var lines := Interp.describe_effect(ctx, ctx.root, {"check": SPEC}).map(func(x): return str(x.text))
	check(lines.size() >= 6, "в подсказке шанс, разбор и три исхода")
	check(lines.any(func(t): return t.contains("%")), "шанс в процентах")


func test_learned_find_archives_more_often() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var dec: Dictionary = g.content.get_def("decisions", "search_archives")
	var ctx := _ctx(g, h)
	var spec: Dictionary = dec.effect.check
	h.skills["learning"] = 2
	g.stat_cache.clear()
	var low: float = Checks.odds(ctx, ctx.root, spec).success
	h.skills["learning"] = 18
	g.stat_cache.clear()
	var high: float = Checks.odds(ctx, ctx.root, spec).success
	check(high > low + 30.0, "учёный находит чаще (%.0f%% против %.0f%%)" % [high, low])
	# средний учёный: Архивариусу находка почти верна
	h.skills["learning"] = 8
	g.stat_cache.clear()
	var mid: float = Checks.odds(ctx, ctx.root, spec).success
	Lifestyles.unlock_perk(g, h, "archivist", true)
	g.stat_cache.clear()
	g.month_cache.clear()
	check(Checks.odds(ctx, ctx.root, spec).success >= mid + 30.0, "Архивариус находит куда чаще")

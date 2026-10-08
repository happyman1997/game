extends TestCase
## Симуляция, сохранения, скриптовый язык и механики на реальном контенте.


func _ctx(game: Game, root: String, scopes: Dictionary = {}) -> ScriptContext:
	return ScriptContext.make(game, {"type": "character", "id": root}, scopes)


func test_mods_load_without_issues() -> void:
	var e := TestEnv.engine()
	var ids := e.mods.map(func(m): return m.id)
	for m in ["core", "plague", "tournaments", "elective_monarchy"]:
		check(ids.has(m), "загружен мод " + m)
	for i in e.issues:
		failures.append("проблема контента: %s" % i.message)


func test_world_stays_consistent() -> void:
	var game := TestEnv.engine().new_game("b1066", 7)
	check_eq(TestEnv.invariants(game), [], "инварианты на старте")
	for y in 3:
		TestEnv.ticks(game, 365)
		var probs := TestEnv.invariants(game)
		check(probs.is_empty(), "год %d: %s" % [GameDate.year_of(game.date), probs.slice(0, 5)])
	check(game.living().size() > 200, "живых персонажей: %d" % game.living().size())
	for i in TestEnv.engine().issues:
		check(not str(i.message).begins_with("Скрипт"), "ошибка скрипта: %s" % i.message)


func test_save_load_is_deterministic() -> void:
	var e := TestEnv.engine()
	var game := e.new_game("b1066", 11)
	TestEnv.ticks(game, 60)
	var json := SaveGame.serialize(game)
	var res := e.load_game(json)
	check(res.error == "", res.error)
	var game2: Game = res.game
	TestEnv.ticks(game, 45)
	TestEnv.ticks(game2, 45)
	check_eq(game2.date, game.date, "дата")
	var diff := TestEnv.first_diff(game.state, game2.state, "state")
	check(diff == "", "после загрузки партия идёт так же: " + diff)


func test_triggers_values_effects() -> void:
	var game := TestEnv.engine().new_game("b1066", 3)
	var ctx := _ctx(game, "harold", {"other": {"type": "character", "id": "william"}})
	var root := {"type": "character", "id": "harold"}
	check(Interp.eval_trigger(ctx, root, {"is_adult": "yes", "tier": ">= kingdom"}), "Гарольд — взрослый король")
	check(Interp.eval_trigger(ctx, root, {"has_trait": Data.as_array(game.ch("harold").traits)}), "есть свои черты")
	check(not Interp.eval_trigger(ctx, root, {"NOT": {"is_alive": "yes"}}), "NOT")
	check(Interp.eval_trigger(ctx, root, {"any_vassal": {"count": ">= 2"}}), "есть вассалы")
	check(Interp.eval_trigger(ctx, root, {"scope:other": {"is_ruler": "yes"}}), "сохранённый скоуп")
	check_eq(Interp.eval_value(ctx, root, {"value": 10, "add": [5, 5], "max": 12}), 12.0, "значение")
	var parts := []
	Interp.eval_value(ctx, root, {"value": 0, "add": [{"desc": "Тест", "value": 7}]}, parts)
	check_eq(parts, [{"label": "Тест", "value": 7.0}], "слагаемые с подписями")
	var gold0: float = game.ch("harold").gold
	Interp.run_effect(ctx, root, [{"add_gold": 5}, {"if": {"limit": {"gold": "> 100000"}, "add_gold": 1000}, "else": {"add_gold": 1}}])
	check_eq(game.ch("harold").gold, gold0 + 6, "эффекты и if/else")
	var before := JSON.stringify(game.state)
	var lines := Interp.describe_effect(ctx, root, [{"add_gold": 50}, {"scope:other": {"add_prestige": 10}}])
	check(lines.size() >= 2, "описание эффекта")
	check(JSON.stringify(game.state) == before, "описание не меняет мир")


func test_features_installed_and_work() -> void:
	var e := TestEnv.engine()
	for f in ["lifestyles", "council", "prison", "factions", "regiments", "secrets", "laws", "knights"]:
		check(e.has_feature(f), "механика " + f)
	var game := e.new_game("b1066", 5)
	TestEnv.ticks(game, 40)
	var harold: Dictionary = game.ch("harold")
	check(harold.get("lifestyle") != null and harold.lifestyle.focus != null, "ИИ выбрал фокус")
	check(harold.get("council") != null and harold.council.size() >= 3, "совет заполнен")
	check(not Regiments.regs_of(harold).is_empty(), "у короля есть отряды")
	check(Laws.current(game, harold, "crown_authority") != null, "действует закон о власти короны")
	# темница
	var victim: Dictionary = game.courtiers_of(harold.id).filter(func(c): return Chars.is_adult(game, c))[0]
	check(Prison.imprison(game, harold, victim, "test"), "заключение")
	check(Prison.prisoners_of(game, harold.id).has(victim), "пленник в списке")
	Prison.release(game, victim)
	check(victim.get("prison") == null, "освобождение")
	# секреты и крюки
	var spy: Dictionary = game.courtiers_of(harold.id).filter(func(c): return c.id != victim.id and Chars.is_adult(game, c))[0]
	Secrets.add_secret(game, victim, "secret_murder", null, [spy.id])
	check(Secrets.blackmail(game, spy, victim), "шантаж")
	check(Leverage.hook_on(game, spy, victim.id) != null, "крюк получен")

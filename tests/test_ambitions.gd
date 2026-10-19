extends TestCase
## Желания: исполнение и благодарность сюзерену, обида за долгое ожидание,
## брошенное желание, исполнение сюзереном, выбор желания игроком, пожалование
## не тому.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _run_months(g: Game, months: int) -> void:
	for _i in months * 30:
		g.state.pending_events.clear()
		g.state.pending_requests.clear()
		g.tick()


## Вассал игрока без желания (не в темнице, взрослый).
func _vassal(g: Game) -> Dictionary:
	for v in g.vassals_of("harold"):
		if Ambitions.eligible(g, v):
			v.vars.erase("ambition")
			return v
	return {}


func test_progress_fulfil_gratitude() -> void:
	var g := _game()
	var v := _vassal(g)
	check(not v.is_empty(), "есть вассал")
	var harold: Dictionary = g.ch("harold")
	check(Ambitions.start(g, v, "wealth"), "желание заведено")
	var pr: Variant = Ambitions.progress_of(g, v)
	check(pr != null and float(pr.done) == 0.0 and float(pr.need) >= 50.0, "ход желания считается от начала")
	Ambitions.check(g, v)
	check(Ambitions.current(v) != null, "пока не исполнено")
	v.gold = float(v.gold) + float(pr.need) + 1.0
	Ambitions.check(g, v)
	check(Ambitions.current(v) == null, "исполнено — снято")
	check(Opinion.has_opinion_modifier(v, harold, "ambition_fulfilled"), "благодарность сюзерену")
	check(int(v.vars.get("ambition_cd", 0)) > g.date, "перерыв до нового желания")
	# в перерыве новое не заводится
	for _i in 50:
		Ambitions.monthly_char(g, v)
	check(Ambitions.current(v) == null, "в перерыве нового нет")


func test_frustration_and_expire() -> void:
	var g := _game()
	var v := _vassal(g)
	var harold: Dictionary = g.ch("harold")
	var op0 := Opinion.opinion(g, v, harold)
	Ambitions.start(g, v, "glory")
	check_eq(Ambitions.frustration(g, v), 0.0, "пока терпит")
	var d: Dictionary = Ambitions.def_of(g, "glory")
	v.vars.ambition.since = g.date - roundi((float(d.patience) + 1.5) * GameDate.DAYS_PER_YEAR)
	var fr := Ambitions.frustration(g, v)
	check(fr > 0.0, "терпение кончилось — обида")
	check_eq(Opinion.opinion(g, v, harold), op0 - roundi(fr), "обида в мнении о сюзерене")
	var ctx := ScriptContext.make(g, {"type": "character", "id": v.id})
	check(Interp.eval_trigger(ctx, ctx.root, {"ambition_frustrated": true, "has_ambition": "glory"}), "триггеры желания")
	check(Ambitions.frustrated_of(g, harold).has(v), "в списке обиженных двора")
	# брошено — долгая обида
	v.vars.ambition.since = g.date - roundi((float(d.expire) + 0.1) * GameDate.DAYS_PER_YEAR)
	Ambitions.check(g, v)
	check(Ambitions.current(v) == null, "брошено")
	check(Opinion.has_opinion_modifier(v, harold, "ambition_ignored"), "долгая обида")


func test_liege_grants_ambition() -> void:
	var g := _game()
	var v := _vassal(g)
	var harold: Dictionary = g.ch("harold")
	harold.gold = 2000.0
	Ambitions.start(g, v, "wealth")
	# игрок — сюзерен — может исполнить сам
	check(Ambitions.grantable_by(g, v, harold), "можно исполнить своими силами")
	var cost := Ambitions.grant_cost(g, v, "gold")
	check(cost > 0.0, "цена в золоте")
	var def: Dictionary = g.content.get_def("interactions", "fulfill_ambition")
	check(Interactions.is_shown(g, def, harold, v), "взаимодействие видно")
	var gold0 := float(v.gold)
	var hg0 := float(harold.gold)
	Interactions.execute(g, def, harold, v)
	check(Ambitions.current(v) == null, "желание исполнено")
	check(float(v.gold) >= gold0 + cost - 1.0, "вассал получил золото")
	check(float(harold.gold) <= hg0 - cost + 1.0, "сюзерен заплатил")
	check(Opinion.has_opinion_modifier(v, harold, "ambition_fulfilled"), "благодарность")
	# желание без grant так не исполнить
	var w := _vassal(g)
	if not w.is_empty() and w.id != v.id:
		Ambitions.start(g, w, "glory")
		check(not Interactions.is_shown(g, def, harold, w), "слава в битвах — не за золото")


func test_player_offers() -> void:
	var g := _game()
	var harold: Dictionary = g.ch("harold")
	harold.vars.erase("ambition")
	harold.vars.erase("ambition_cd")
	Ambitions.monthly_char(g, harold)
	var offs := Ambitions.offers(harold)
	check(offs.size() > 0 and offs.size() <= 3, "игроку предложены желания")
	var ids := {}
	for o in offs:
		ids[o.id] = true
	check_eq(ids.size(), offs.size(), "без повторов")
	Ambitions.choose_offer(g, harold, 0)
	check(Ambitions.current(harold) != null and str(Ambitions.current(harold).id) == str(offs[0].id), "выбрано первое")
	check(Ambitions.offers(harold).is_empty(), "предложения сняты")
	check_eq(Ambitions.frustration(g, harold), 0.0, "у игрока нет обиды на себя")
	var st := float(harold.stress)
	Ambitions.abandon(g, harold)
	check(Ambitions.current(harold) == null, "оставлено")
	check(float(harold.stress) > st, "стресс за отказ")
	check(int(harold.vars.get("ambition_cd", 0)) > g.date, "перерыв")
	# отказ от выбора — тоже перерыв
	harold.vars.erase("ambition_cd")
	Ambitions.monthly_char(g, harold)
	Ambitions.choose_offer(g, harold, -1)
	check(Ambitions.current(harold) == null and int(harold.vars.get("ambition_cd", 0)) > g.date, "отложено на год")


func test_land_passed_over() -> void:
	var g := _game()
	var harold: Dictionary = g.ch("harold")
	var grantable: Array = g.engine.scripting.lists.get_item("grantable_title").list.call(
		ScriptContext.make(g, {"type": "character", "id": "harold"}), {"type": "character", "id": "harold"})
	check(grantable.size() >= 2, "у короля есть что пожаловать")
	var cs: Array = g.courtiers_of("harold").filter(func(x): return Ambitions.eligible(g, x) and x.titles.is_empty())
	if cs.size() < 2:
		cs = g.vassals_of("harold").filter(func(x): return Ambitions.eligible(g, x) and Titles.primary_tier(g, x) <= Titles.tier_rank("county"))
	check(cs.size() >= 2, "есть кому желать земли")
	var a: Dictionary = cs[0]
	var b: Dictionary = cs[1]
	a.vars.erase("ambition")
	b.vars.erase("ambition")
	# пожаловали другому — обида
	Ambitions.start(g, a, "land", grantable[0])
	Titles.transfer_title(g, grantable[0].id, b.id)
	Ambitions.check(g, a)
	check(Ambitions.current(a) == null, "желание стало невозможным")
	check(Opinion.has_opinion_modifier(a, harold, "passed_over"), "обойдён пожалованием")
	# пожаловали ему — благодарность
	b.vars.erase("ambition")
	Ambitions.start(g, b, "land", grantable[1])
	var ctx := ScriptContext.make(g, {"type": "character", "id": b.id}, {"target": grantable[1]})
	check(Interp.eval_trigger(ctx, ctx.root, {"ambition_target_is": "scope:target"}), "цель желания")
	Titles.transfer_title(g, grantable[1].id, b.id)
	Ambitions.check(g, b)
	check(Ambitions.current(b) == null, "земля получена")
	check(Opinion.has_opinion_modifier(b, harold, "ambition_fulfilled"), "благодарность за землю")


func test_ai_takes_up_ambitions() -> void:
	var g := _game()
	var started := [0]
	g.engine.hooks.on("ambition.started", func(_p): started[0] += 1)
	_run_months(g, 18)
	var with_amb := 0
	for c in g.state.characters.values():
		if Ambitions.current(c) != null:
			with_amb += 1
			check(Ambitions.def_of(g, Ambitions.current(c).id) != null, "известное желание")
	check(started[0] > 10, "ИИ заводит желания (%d)" % started[0])
	check(with_amb > 5, "у многих есть желания (%d)" % with_amb)


## Мечта о независимости: и у графа, и тем сильнее, чем чужее он сюзерену;
## с ней вассал охотнее идёт во фракцию за независимость.
func test_independence_ambition() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v: Variant = null
	for x in g.vassals_of(h.id):
		if Chars.is_adult(g, x) and x.get("prison") == null and not x.traits.has("content"):
			v = x
			break
	Opinion.add_opinion(g, v, h, "generic", -200)
	var opt: Array = Ambitions.options(g, v).filter(func(o): return o.id == "independence")
	check(not opt.is_empty(), "недовольный вассал может мечтать о независимости")
	var w0: float = opt[0].weight if not opt.is_empty() else 0.0
	for f in g.content.all("faiths"):
		if str(f.id) != str(h.faith):
			v.faith = f.id
			break
	var opt2: Array = Ambitions.options(g, v).filter(func(o): return o.id == "independence")
	check(not opt2.is_empty() and float(opt2[0].weight) > w0, "иноверец мечтает сильнее (%.1f → %.1f)" % [w0, opt2[0].weight if not opt2.is_empty() else 0.0])
	var def: Dictionary = g.content.get_def("factions", "independence_faction")
	var s0 := Factions.ai_join_score(g, v, def, h)
	check(Ambitions.start(g, v, "independence"), "желание начато")
	check(Factions.ai_join_score(g, v, def, h) > s0, "с мечтой — охотнее во фракцию")

extends TestCase
## Инвентарь: стартовые реликвии, слоты и модификаторы надетого, износ и
## ремонт, наследство, трофеи и притязания, заказ мастеру, подарок,
## скрипт, старые сохранения.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func test_start_and_equipped_modifiers() -> void:
	var g := _game()
	var harold: Dictionary = g.ch("harold")
	var crown: Variant = Artifacts.item(g, "edward_crown")
	check(crown != null and crown.owner == "harold", "венец Эдуарда у Гарольда")
	check(crown.slot == "regalia", "венец надет")
	check(Artifacts.holder_of(g, "joyeuse") != null and Artifacts.holder_of(g, "joyeuse").id == "philip", "Жуайёз у Филиппа")
	check(Artifacts.items_of(g, harold).size() >= 3, "у короля есть снаряжение и убранство двора")
	var with_crown := Stats.stat(g, harold, "vassal_opinion")
	Artifacts.unequip(g, harold, crown)
	check(crown.slot == null, "снят")
	check(with_crown - Stats.stat(g, harold, "vassal_opinion") >= 8.0, "модификаторы даёт только надетое")
	check(Artifacts.equip(g, harold, crown), "надет обратно")
	check_eq(Stats.stat(g, harold, "vassal_opinion"), with_crown, "модификатор вернулся")


func test_slots_and_auto_equip() -> void:
	var g := _game()
	var harold: Dictionary = g.ch("harold")
	for it in Artifacts.in_slot(g, harold, "trinket"):
		Artifacts.unequip(g, harold, it)
	var made := []
	for i in 4:
		made.append(Artifacts.create(g, "ring", "common", harold))
	check_eq(Artifacts.in_slot(g, harold, "trinket").size(), 3, "три безделушки — больше не наденешь")
	check(made[3].slot == null, "четвёртая — в хранилище")
	# ИИ меняет худшее на лучшее
	var w: Dictionary = g.ch("william")
	for it in Artifacts.in_slot(g, w, "weapon"):
		Artifacts.unequip(g, w, it)
	var bad := Artifacts.create(g, "sword", "common", w)
	check(bad.slot == "weapon", "пустой слот занят")
	var good := Artifacts.create(g, "sword", "famed", w)
	check(good.slot == "weapon" and bad.slot == null, "ИИ надел лучший меч")
	# у безземельного нет убранства двора
	var courtier: Variant = null
	for x in g.courtiers_of("harold"):
		if x.titles.is_empty() and Chars.is_adult(g, x):
			courtier = x
			break
	if courtier != null:
		check_eq(Artifacts.slot_capacity(g, courtier, "throne"), 0, "трон — только правителю")
		var t := Artifacts.create(g, "throne", "common", courtier)
		check(t.slot == null, "трон придворного — в хранилище")


func test_durability_repair_melt() -> void:
	var g := _game()
	var harold: Dictionary = g.ch("harold")
	var it := Artifacts.create(g, "mail", "masterwork", harold)
	it.durability = 10.0
	harold.gold = 500.0
	var cost := Artifacts.repair_cost(g, it)
	check(cost > 0.0, "ремонт стоит золота")
	check(Artifacts.repair(g, harold, it), "починено")
	check_eq(float(it.durability), float(it.max_durability), "прочность восстановлена")
	check_eq(float(harold.gold), 500.0 - cost, "золото списано")
	it.durability = 0.1
	Artifacts.monthly(g)
	check(Artifacts.item(g, it.id) == null, "рассыпалась от ветхости")
	var crown: Dictionary = Artifacts.item(g, "edward_crown")
	var d0 := float(crown.durability)
	for _i in 24:
		Artifacts.monthly(g)
	check_eq(float(crown.durability), d0, "уникальная реликвия не ветшает")
	var ring := Artifacts.create(g, "ring", "famed", harold)
	var gold0 := float(harold.gold)
	check(Artifacts.melt(g, harold, ring), "переплавлено")
	check(float(harold.gold) > gold0 and Artifacts.item(g, ring.id) == null, "золото за переплавку")
	check(not Artifacts.melt(g, harold, crown), "реликвию не переплавить")


func test_inheritance() -> void:
	var g := _game()
	var harold: Dictionary = g.ch("harold")
	var heir: Variant = Succession.primary_heir(g, harold)
	check(heir != null, "есть наследник")
	var n := Artifacts.items_of(g, harold).size()
	Succession.kill_character(g, harold, "natural")
	check(Artifacts.items_of(g, harold).is_empty(), "у покойного вещей нет")
	check(Artifacts.items_of(g, heir).size() >= n, "всё — наследнику")
	check(Artifacts.holder_of(g, "edward_crown").id == heir.id, "венец Эдуарда унаследован")


func test_loot_claims_and_demand() -> void:
	var g := _game()
	var harold: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var helm := Artifacts.create(g, "helm", "famed", harold)
	var op0 := Opinion.opinion(g, harold, w)
	Artifacts.give(g, helm.id, w, "looted")
	check(helm.owner == "william", "трофей у победителя")
	check(Artifacts.has_claim(g, harold, helm), "у прежнего владельца — притязание")
	check(Artifacts.claimed_from(g, harold, w).has(helm), "видно, что именно у кого")
	check(Opinion.opinion(g, harold, w) < op0, "«держит мою вещь» — мнение хуже")
	var def: Dictionary = g.content.get_def("interactions", "demand_artifact")
	check(Interactions.is_shown(g, def, harold, w), "можно потребовать")
	# вернули — притязание снято
	var ctx := ScriptContext.make(g, {"type": "character", "id": "william"}, {"target": {"type": "artifact", "id": helm.id}, "to": {"type": "character", "id": "harold"}})
	Interp.run_effect(ctx, ctx.root, {"transfer_artifact": {"artifact": "scope:target", "to": "scope:to", "how": "returned"}})
	check(helm.owner == "harold" and not Artifacts.has_claim(g, harold, helm), "вернули — притязание снято")
	check(not Interactions.is_shown(g, def, harold, w), "требовать больше нечего")
	# трофей в битве
	var sw := Artifacts.create(g, "sword", "masterwork", w)
	var looted := false
	for _i in 200:
		Artifacts.on_battle(g, harold, w)
		if sw.owner == "harold":
			looted = true
			break
	check(looted, "победитель снимает оружие с побеждённого")


func test_commission() -> void:
	var g := _game()
	var harold: Dictionary = g.ch("harold")
	harold.gold = 1000.0
	var n0 := Artifacts.items_of(g, harold).size()
	check(Artifacts.commission_blockers(g, harold, "fine").is_empty(), "можно заказать")
	check(Artifacts.commission(g, harold, "goblet", "fine"), "заказ принят")
	check_eq(float(harold.gold), 880.0, "оплачен")
	check(not Artifacts.commission_blockers(g, harold, "fine").is_empty(), "мастер занят")
	Artifacts.commission_of(harold).done = g.date
	Artifacts.monthly_char(g, harold)
	check(Artifacts.commission_of(harold) == null, "заказ выполнен")
	check_eq(Artifacts.items_of(g, harold).size(), n0 + 1, "вещь готова")
	check(Artifacts.items_of(g, harold).any(func(it): return it.type == "goblet"), "тот самый кубок")
	var ch := Artifacts.commission_chances(g, harold, "lavish")
	check(not ch.is_empty() and ch.all(func(x): return x.rarity != "common"), "шедевр не бывает обычным")


func test_gift_interaction() -> void:
	var g := _game()
	var harold: Dictionary = g.ch("harold")
	var gyrth: Dictionary = g.ch("gyrth")
	var ring := Artifacts.create(g, "ring", "famed", harold)
	var def: Dictionary = g.content.get_def("interactions", "gift_artifact")
	check(Interactions.is_shown(g, def, harold, gyrth), "можно подарить")
	var opts := Interactions.target_options(g, def, harold, gyrth)
	check(opts.any(func(o): return o.ref.id == ring.id), "перстень среди вещей на выбор")
	Interactions.execute(g, def, harold, gyrth, {"target": {"type": "artifact", "id": ring.id}})
	check(ring.owner == "gyrth", "подарено")
	check(Opinion.has_opinion_modifier(gyrth, harold, "artifact_gift"), "благодарность за подарок")
	check(not Artifacts.has_claim(g, harold, ring), "подарок — без притязаний")


func test_script_and_migration() -> void:
	var g := _game()
	var ctx := ScriptContext.make(g, {"type": "character", "id": "harold"})
	Interp.run_effect(ctx, ctx.root, {"create_artifact": {"type": "book", "rarity": "famed", "save_scope_as": "made"}})
	var made: Variant = ctx.scopes.get("made")
	check(made is Dictionary and made.type == "artifact", "вещь сохранена в скоуп")
	check(Interp.eval_trigger(ctx, ctx.root, {"has_artifact_type": "book", "any_artifact": {"artifact_rarity": "famed", "artifact_type": "book"}}), "условия и перебор вещей")
	check(g.scope_name(made) != "?", "имя вещи в тексте")
	check(Interp.eval_value(ctx, made, "artifact_durability") == 100.0, "прочность новой вещи")
	# старое сохранение: {реликвия: владелец}
	g.state.artifacts = {"sun_crown": "harold", "otgar_sword": null}
	g.month_cache.clear()
	Artifacts.migrate(g)
	var sc: Variant = Artifacts.item(g, "sun_crown")
	check(sc is Dictionary and sc.owner == "harold", "венец перенесён в новый инвентарь")
	check(Artifacts.item(g, "otgar_sword") is Dictionary and Artifacts.item(g, "otgar_sword").owner == null, "утерянная реликвия — без хозяина")

extends TestCase
## Вера: добродетели и грехи культов, Великий Светоч (Престол в Реймсе),
## отлучение и коронация через его мнение, дар Храму и покаяние, развод,
## Восточный обряд как ересь, захват и освобождение Храма.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _labels(g: Game, a: Dictionary, b: Dictionary) -> Array:
	return Opinion.breakdown(g, a, b).map(func(x): return str(x.get("label", "")))


func _fresh(g: Game, a: Dictionary, b: Dictionary) -> void:
	g.stat_cache.erase(a.id)
	g.stat_cache.erase(b.id)
	g.stat_cache.erase("op:%s>%s" % [a.id, b.id])


func test_virtues_and_sins() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v: Dictionary = g.vassals_of("harold").filter(func(x): return x.faith == h.faith)[0]
	for t in ["just", "greedy"]:
		Chars.remove_trait(g, h, t)
	var part := func(word: String) -> float:
		_fresh(g, v, h)
		var s := 0.0
		for x in Opinion.breakdown(g, v, h):
			if str(x.label).contains(word):
				s += Data.num(x.value)
		return s
	Chars.add_trait(g, h, "just")
	check_eq(part.call("Чтит культ: " + g.name_of("traits", "just")), 5.0, "единоверец чтит добродетель культа")
	Chars.remove_trait(g, h, "just")
	Chars.add_trait(g, h, "greedy")
	check_eq(part.call("Осуждает культ: " + g.name_of("traits", "greedy")), -5.0, "и осуждает грех")
	# иноверец о культе не судит
	var other: Dictionary = g.ch("gero_eisenwart")
	_fresh(g, other, h)
	check(not _labels(g, other, h).any(func(l): return l.contains("Чтит культ") or l.contains("Осуждает культ")), "иноверец не судит по чужому культу")


func test_great_lightbearer() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Variant = Temple.head_of(g, h)
	check(head != null and head.id == "gervais_reims", "глава веры — Великий Светоч Жерве")
	check(Temple.is_head(g, head), "он держит Престол Светоча")
	check_eq(Governments.of(g, head), "temple", "храмовый престол")
	check(head.liege == null, "Храм независим")
	# культ-ересь главы не признаёт
	check(Temple.head_of(g, g.ch("gero_eisenwart")) == null, "у ереси нет Великого Светоча")
	# мнение Храма — по лицу: благочестию
	h.piety = -200.0
	_fresh(g, head, h)
	var low := Opinion.opinion(g, head, h)
	h.piety = 2500.0
	_fresh(g, head, h)
	check(Opinion.opinion(g, head, h) > low, "благочестивому Храм благоволит больше (%d → %d)" % [low, Opinion.opinion(g, head, h)])
	# преемника избирают жрецы-светочи
	var ctx := ScriptContext.make(g, {"type": "character", "id": head.id})
	Interp.run_effect(ctx, ctx.root, {"death": {"reason": "natural"}})
	var nh: Variant = Temple.head_of(g, h)
	check(nh != null and nh.traits.has("sun_priest"), "новый Великий Светоч — из жрецов (%s)" % (nh.id if nh != null else "—"))


func test_excommunication_and_coronation_follow_the_head() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Dictionary = Temple.head_of(g, h)
	Karma.set_value(g, h, -80.0)
	var def: Dictionary = g.content.get_def("events", "soul.0005")
	var tgt := {"type": "character", "id": h.id}
	h.piety = 3000.0
	_fresh(g, head, h)
	check(not g.events.can_fire(def, tgt, ScriptContext.make(g, tgt)), "лицо спасает: благочестивого лицемера не отлучают")
	h.piety = -200.0
	_fresh(g, head, h)
	check(g.events.can_fire(def, tgt, ScriptContext.make(g, tgt)), "нечестивого с пеплом на душе — отлучают")
	# коронация — лишь с благословения Великого Светоча
	var cor: Dictionary = g.content.get_def("decisions", "coronation")
	h.gold = 1000.0
	h.piety = 3000.0
	_fresh(g, head, h)
	check(Decisions.can_take(g, cor, h), "благочестивого помажут")
	var gold0 := float(head.gold)
	check(Decisions.take(g, cor, h), "коронация")
	check(float(head.gold) > gold0, "часть платы — Храму")


func test_gift_and_absolution() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Dictionary = Temple.head_of(g, h)
	h.gold = 1000.0
	h.piety = 500.0
	_fresh(g, head, h)
	var op0 := Opinion.opinion(g, head, h)
	check_eq(Interactions.execute(g, g.content.get_def("interactions", "temple_gift"), h, head), "accepted", "дар Храму принят")
	_fresh(g, head, h)
	check(Opinion.opinion(g, head, h) > op0, "Великий Светоч благосклоннее к дарителю")
	# отлучённый кается — тому, кому верят, отлучение снимают
	var ctx := ScriptContext.make(g, {"type": "character", "id": h.id})
	Interp.run_effect(ctx, ctx.root, {"add_modifier": {"id": "cast_out_of_light", "years": 10}})
	h.piety = 3000.0
	_fresh(g, head, h)
	check_eq(Interactions.execute(g, g.content.get_def("interactions", "beg_absolution"), h, head), "accepted", "покаяние принято")
	check(not h.modifiers.any(func(m): return m.id == "cast_out_of_light"), "отлучение снято")


func test_divorce_by_leave_of_the_temple() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Dictionary = Temple.head_of(g, h)
	var dv: Dictionary = g.content.get_def("decisions", "request_divorce")
	if h.spouses.is_empty():
		var w: Dictionary = g.living().filter(func(c): return c.female and Chars.is_adult(g, c) and c.spouses.is_empty() and c.faith == h.faith)[0]
		Chars.marry(g, h, w)
	check(Decisions.is_shown(g, dv, h), "солнечный обряд — развод с дозволения Храма")
	h.piety = -200.0
	h.gold = 500.0
	_fresh(g, head, h)
	check(not Decisions.can_take(g, dv, h), "без благосклонности Великого Светоча — нельзя")
	h.piety = 3000.0
	Opinion.add_opinion(g, head, h, "temple_gift")
	_fresh(g, head, h)
	var n0: int = h.spouses.size()
	check(Decisions.take(g, dv, h), "Храм дозволил развод")
	check(h.spouses.size() < n0, "брак расторгнут")


func test_east_rite_is_heresy() -> void:
	var g := _game()
	var gero: Dictionary = g.ch("gero_eisenwart")
	check(Wars.is_heretic(g, gero), "Восточный обряд — ересь")
	var found := false
	for r in g.rulers():
		if r.liege != null or r.id == gero.id or Wars.is_heretic(g, r):
			continue
		if Wars.available_war_targets(g, r).any(func(t): return t.cb == "holy_war" and t.defender == gero.id):
			found = true
			break
	check(found, "на Восточную марку есть повод к священной войне")


func test_temple_taken_and_freed() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Dictionary = Temple.head_of(g, h)
	var philip: Dictionary = g.ch("philip")
	# захват Реймса — святотатство, престол пустеет
	Titles.transfer_title(g, "c_reims", philip.id)
	check(philip.modifiers.any(func(m): return m.id == "cast_out_of_light"), "захватчика Храма отлучают")
	Titles.enforce_landed_titles(g)
	check(Temple.head_of(g, h) == null, "престол Светоча пуст")
	check(not head.titles.has("d_sun_throne"), "Жерве в изгнании")
	var cor: Dictionary = g.content.get_def("decisions", "coronation")
	h.gold = 1000.0
	h.piety = 3000.0
	check(not Decisions.can_take(g, cor, h), "помазать некому")
	# освобождение Храма
	var t: Variant = null
	for x in Wars.available_war_targets(g, h):
		if x.cb == "liberate_temple":
			t = x
	check(t != null and t.defender == philip.id, "повод освободить Храм — против Филиппа")
	var cb: Dictionary = g.content.get_def("casus_belli", "liberate_temple")
	var ctx := Wars.cb_context(g, h.id, t)
	Interp.run_effect(ctx, ctx.root, cb.on_victory)
	var nh: Variant = Temple.head_of(g, h)
	check(nh != null and nh.titles.has("c_reims") and nh.liege == null, "на Престоле новый Великий Светоч, Храм снова независим")

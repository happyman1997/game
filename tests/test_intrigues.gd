extends TestCase
## Новые интриги: похищение (пленник — в вашей темнице, родня злится),
## кража реликвии (сначала своя утраченная, у жертвы — притязание), смута
## (три графства врага злее к нему), поджог (подати столицы падают, стройка
## откатывается, но не дальше начала); раскрытая интрига — повод к темнице;
## ИИ похищает родню врагов.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


## Успех интриги без броска.
func _succeed(g: Game, type: String, owner: Dictionary, target: Dictionary) -> Dictionary:
	var s: Variant = Schemes.start_scheme(g, type, owner, target)
	check(s != null, "интрига %s начата" % type)
	if s == null:
		return {}
	var ctx := Schemes.scheme_context(g, s)
	Interp.run_effect(ctx, ctx.root, g.content.get_def("schemes", type).on_success)
	Schemes.end_scheme(g, s.id)
	return s


func _child_of(g: Game, c: Dictionary) -> Dictionary:
	for id in c.children:
		var x: Variant = g.ch(id)
		if x != null and Chars.is_alive(x) and x.titles.is_empty():
			return x
	return {}


func test_abduct() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var kid := _child_of(g, w)
	check(not kid.is_empty(), "у Вильгельма есть дети без земель")
	var op0 := Opinion.opinion(g, w, h)
	_succeed(g, "abduct", h, kid)
	check(kid.get("prison") != null and kid.prison.by == h.id, "похищенный — в темнице Гарольда")
	g.stat_cache.clear()
	check(Opinion.opinion(g, w, h) < op0, "отец похищенного злится")
	check(Prison.has_imprisonment_reason(g, w, h), "и у него законный повод к темнице")


func test_steal_prefers_own_claim() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var cheap := Artifacts.create(g, "ring", "common", w)
	Artifacts.create(g, "sword", "famed", w)
	var items := Artifacts.items_of(g, w)
	items.sort_custom(func(a, b): return Artifacts.value_of(g, a) > Artifacts.value_of(g, b))
	var rich: Dictionary = items[0]
	_succeed(g, "steal_artifact", h, w)
	check_eq(str(Artifacts.item(g, rich.id).owner), h.id, "украдена самая ценная вещь")
	check(Data.as_array(Artifacts.item(g, rich.id).get("claims")).has(w.id), "у Вильгельма — притязание")
	# своя утраченная вещь — прежде ценной
	var it: Dictionary = Artifacts.item(g, cheap.id)
	it["claims"] = [h.id]
	var left := Artifacts.items_of(g, w).size()
	_succeed(g, "steal_artifact", g.ch("harold"), w)
	check_eq(str(Artifacts.item(g, cheap.id).owner), h.id, "сначала — то, на что притязает вор")
	check_eq(Artifacts.items_of(g, w).size(), left - 1, "украдена одна вещь")


func test_incite_unrest() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	_succeed(g, "incite_unrest", h, w)
	var hit := 0
	for pid in Titles.domain_counties(g, w):
		if Data.as_array(g.state.provinces[pid].vars.get("copinions")).any(func(e): return e.mod == "incited_unrest"):
			hit += 1
	check_eq(hit, mini(3, Titles.domain_counties(g, w).size()), "подстрекатели — в трёх графствах")


func test_sabotage() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var cap: String = str(w.capital)
	var p: Dictionary = g.state.provinces[cap]
	p.construction = {"building": "walls", "done": g.date + 100, "days": 300, "by": w.id}
	var tax0 := Economy.county_tax(g, cap)
	_succeed(g, "sabotage", h, w)
	g.stat_cache.clear()
	check(p.modifiers.any(func(m): return m.id == "burned_stores"), "склады сгорели")
	check(Economy.county_tax(g, cap) < tax0, "подати столицы упали")
	check_eq(int(p.construction.done), g.date + 280, "стройка откатилась на полгода (100 + 180)")
	_succeed(g, "sabotage", h, w)
	check(int(p.construction.done) <= g.date + 300, "но не дальше начала")


func test_ai_abducts_enemy_kin() -> void:
	var g := _game()
	g.state.player = null
	var h: Dictionary = g.ch("harold")
	var w: Dictionary = g.ch("william")
	var ts := Wars.available_war_targets(g, w, h.id)
	check(not ts.is_empty(), "у Вильгельма есть повод против Гарольда")
	Wars.declare_war(g, w, ts[0])
	var def: Dictionary = g.content.get_def("interactions", "abduct")
	var kin := Ai._ai_targets(g, h, def, {}).map(func(x): return x.id)
	var kid := _child_of(g, w)
	check(kin.has(kid.id), "дети врага — в целях похищения")
	var ctx := Interactions.context(g, def, h, kid)
	var will := Interp.eval_value(ctx, ctx.root, def.ai_will_do)
	check(will > 0.0 or h.traits.any(func(t): return t in ["compassionate", "honest", "just"]), "на войне ИИ хочет похитить (%.0f)" % will)

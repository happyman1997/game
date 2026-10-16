class_name SettlementPanel
extends RefCounted
## Поселение графства в окне провинции (механика districts): районы с уровнем
## и силой, их постройки по местам, стройка, «Заложить район» и «Поднять».


static func build(app: App, id: String) -> Array:
	var g := app.game
	var st: Variant = g.prov(id)
	var t: Variant = g.title(id)
	var holder: Variant = g.ch(t.holder) if t != null else null
	var p: Variant = g.player
	var mine: bool = p != null and holder != null and holder.id == p.id
	var out := []
	var body := K.vbox([], 6)
	# участки и содержание
	var head := K.hbox([], 10)
	var plots := K.label(app.t("ui.plots", {"used": Districts.used_plots(g, id), "total": Districts.plots(g, id)}), "MutedLabel")
	K.tip(plots, BB.esc(app.t("ui.plots_tip")))
	head.add_child(plots)
	body.add_child(head)
	# стройка
	var cons: Variant = st.get("construction")
	if cons is Dictionary:
		var total := maxi(1, int(Data.num(cons.get("days"), 365)))
		var left := maxi(0, int(cons.done) - g.date)
		body.add_child(K.vbox([K.hbox([K.icon("scaffold", 18, "silver"), K.label("%s — %s" % [Decisions.construction_name(g, cons), app.t("ui.days_left", {"n": left})])], 6),
			K.bar(total - left, total, Color("#d8a84a"))], 2))
	# районы
	var cands_b: Array = Decisions.building_candidates(g, p, id) if mine else []
	var cands_d: Array = Districts.candidates(g, p, id) if mine else []
	for d in Districts.all_defs(g):
		var lvl := Districts.level(g, id, d.id)
		if lvl <= 0:
			continue
		body.add_child(_district_card(app, id, d, lvl, cands_b, cands_d, mine))
	out.append(K.section(app.t("ui.districts"), [body], "castle"))
	# заложить новый район
	if mine:
		var fresh := cands_d.filter(func(x): return x.level == 1)
		if not fresh.is_empty():
			var fl := K.flow([], 6)
			for x in fresh:
				fl.add_child(_district_button(app, id, x, true))
			out.append(K.section(app.t("ui.found_district"), [fl], "plus"))
	# достопримечательности и постройки без района
	var special := []
	var other := []
	for b in st.buildings:
		if Decisions.is_special_building(g, b):
			special.append(b)
		elif Districts.building_district(g, b) == null:
			other.append(b)
	if not special.is_empty():
		var fl := K.flow([], 6)
		for b in special:
			fl.add_child(_building_chip(app, id, b, 1.0))
		out.append(K.section(app.t("ui.special_buildings"), [fl], "star"))
	if not other.is_empty() or (mine and cands_b.any(func(x): return Districts.building_district(g, x.def.id) == null)):
		var fl := K.flow([], 6)
		for b in other:
			fl.add_child(_building_chip(app, id, b, 1.0))
		for x in cands_b:
			if Districts.building_district(g, x.def.id) == null:
				fl.add_child(_build_button(app, id, x, 1.0))
		out.append(K.section("%s (%d/%d)" % [app.t("ui.other_buildings"), other.size(), Decisions.building_slots(g, id)], [fl], "castle"))
	return out


## Карточка района: герб, уровень, сила; постройки по местам; что можно
## построить в нём и поднять ли сам район.
static func _district_card(app: App, id: String, d: Dictionary, lvl: int, cands_b: Array, cands_d: Array, mine: bool) -> Control:
	var g := app.game
	var col := Color(str(d.get("color", "#cccccc")))
	var pw := Districts.power(g, id, d.id)
	var name := K.label("%s %s" % [g.name_of("districts", d.id), Districts.roman(lvl)], "SubheaderLabel")
	name.add_theme_color_override("font_color", col.lightened(0.35))
	var lvl_name := K.label(app.t("district.level_name." + str(lvl)), "MutedLabel")
	var power := K.label(app.t("ui.district_power", {"value": K.fmt(pw, 2)}), "GoldLabel")
	var badge := K.panel(K.icon(d.get("icon", "castle"), 22, "ink"))
	badge.add_theme_stylebox_override("panel", UiArt.flat(col.darkened(0.1), Color("#e6c47a"), 1, 4, 3))
	var top := K.hbox([badge, name, lvl_name, K.expand(), power], 8)
	K.tip(top, district_tip(app, id, d, lvl))
	var card := K.vbox([top], 4)
	# постройки района по местам
	var slots := Districts.slots(g, id, d.id)
	var have := Districts.buildings_in(g, id, d.id)
	var fl := K.flow([], 6)
	for b in have:
		fl.add_child(_building_chip(app, id, b, pw))
	for k in maxi(0, slots - have.size()):
		var empty := K.panel(K.hbox([K.icon("plus", 14, "silver"), K.label(app.t("ui.district_empty_slot"), "MutedLabel")], 4), "InsetPanel")
		fl.add_child(empty)
	card.add_child(fl)
	if mine:
		var acts := K.flow([], 6)
		# в полном районе строить нечего — только поднять его
		if have.size() < slots:
			for x in cands_b:
				if Districts.building_district(g, x.def.id) == d.id:
					acts.add_child(_build_button(app, id, x, pw))
		for x in cands_d:
			if x.def.id == d.id and x.level == lvl + 1:
				acts.add_child(_district_button(app, id, x, false))
		if acts.get_child_count() > 0:
			card.add_child(acts)
	var panel := K.panel(card, "RowPanel")
	return panel


static func _building_chip(app: App, id: String, b: String, pw: float) -> Control:
	var g := app.game
	var bd: Variant = g.content.get_def("buildings", b)
	var chip := K.panel(K.hbox([K.icon(bd.get("icon", "castle") if bd != null else "castle", 18), K.label(g.name_of("buildings", b))], 5), "InsetPanel")
	K.tip(chip, building_tip(app, id, b, Districts.building_scale(g, id, b)))
	return chip


static func _build_button(app: App, id: String, x: Dictionary, pw: float) -> Control:
	var g := app.game
	var p: Dictionary = g.player
	var bd: Dictionary = x.def
	var bid: String = bd.id
	var blockers: Array = x.blockers
	var cost := Decisions.building_cost(g, bd, p, id)
	var k := pw if Districts.building_district(g, bid) != null else 1.0
	return K.button("%s · %s" % [g.name_of("buildings", bid), K.fmt(cost.gold)], func():
		if Decisions.start_building(g, p, id, bid):
			app.toast(app.t("ui.construction_started"), "good")
		app.mark_dirty(true), {"icon": bd.get("icon", "castle"), "disabled": not blockers.is_empty(), "align": HORIZONTAL_ALIGNMENT_LEFT,
		"tip": func(): return building_tip(app, id, bid, k, cost, blockers)})


static func _district_button(app: App, id: String, x: Dictionary, fresh: bool) -> Control:
	var g := app.game
	var p: Dictionary = g.player
	var d: Dictionary = x.def
	var did: String = d.id
	var blockers: Array = x.blockers
	var text := g.name_of("districts", did) if fresh else app.t("ui.upgrade_district", {"level": Districts.roman(int(x.level))})
	return K.button("%s · %s" % [text, K.fmt(x.cost.gold)], func():
		if Districts.start(g, p, id, did):
			app.toast(app.t("ui.construction_started"), "good")
		app.mark_dirty(true), {"icon": d.get("icon", "castle") if fresh else "plus", "disabled": not blockers.is_empty(), "align": HORIZONTAL_ALIGNMENT_LEFT,
		"tip": func():
			var bb := district_tip(app, id, d, int(x.level))
			bb += "\n" + BB.cost(g, x.cost) + "  ·  " + BB.esc(app.t("ui.days_n", {"n": x.days}))
			if not blockers.is_empty():
				bb += "\n" + BB.reasons(blockers)
			return bb})


## Подсказка района на уровне lvl: описание, из чего сила, что даёт сам район,
## места и содержание.
static func district_tip(app: App, id: String, d: Dictionary, lvl: int) -> String:
	var g := app.game
	var parts := Districts.power_parts(g, id, d.id, lvl)
	var pw := Districts.projected_power(g, id, d.id, lvl)
	var bb := BB.title("%s %s" % [g.name_of("districts", d.id), Districts.roman(lvl)])
	var desc := g.desc_of("districts", d.id)
	if desc != "":
		bb += "\n" + BB.i(desc)
	var rows := []
	for x in parts:
		rows.append([BB.esc(x.label), BB.gold("×" + K.fmt(x.value, 2))])
	rows.append([BB.b(app.t("ui.district_power", {"value": ""}).strip_edges()), BB.gold("×" + K.fmt(pw, 2))])
	bb += "\n" + BB.rows(rows)
	bb += "\n" + BB.muted(app.t("ui.district_power_tip"))
	var base := BB.modifiers(g, Districts.scaled(d.get("modifiers"), pw)) + BB.modifiers(g, Districts.scaled(d.get("owner_modifiers"), pw))
	if base != "":
		bb += "\n" + BB.b(app.t("ui.district_base")) + "\n" + base
	var slots := int(Districts._arr(g.def_val("districts.slots_by_level", [1, 2, 3]), lvl, 1))
	bb += "\n" + BB.esc(app.t("ui.district_slots", {"used": Districts.buildings_in(g, id, d.id).size(), "total": slots}))
	var up := Districts._arr(d.get("upkeep"), lvl)
	if up > 0.0:
		bb += "\n" + BB.esc(app.t("ui.district_upkeep")) + ": " + BB.bad("−" + K.fmt(up, 2))
	return bb


## Подсказка постройки: цена, описание, бонусы с силой района, ежегодное.
static func building_tip(app: App, id: String, b: String, k: float, cost: Variant = null, blockers: Array = []) -> String:
	var g := app.game
	var bd: Variant = g.content.get_def("buildings", b)
	var bb := BB.title(g.name_of("buildings", b))
	if bd == null:
		return bb
	if cost != null:
		bb += "\n" + BB.cost(g, cost) + "  ·  " + BB.esc(app.t("ui.days_n", {"n": bd.get("days", 0)}))
	var desc := g.desc_of("buildings", b)
	if desc != "":
		bb += "\n" + BB.i(desc)
	var did: Variant = Districts.building_district(g, b)
	if did != null:
		bb += "\n" + BB.muted(app.t("ui.district_scaled", {"value": K.fmt(k, 2)}))
	bb += "\n" + BB.modifiers(g, Districts.scaled(bd.get("modifiers"), k)) + BB.modifiers(g, Districts.scaled(bd.get("owner_modifiers"), k))
	if bd.get("yearly") != null:
		var h: Variant = g.player if g.player != null else null
		var root := {"type": "character", "id": h.id} if h != null else {"type": "province", "id": id}
		var ctx := ScriptContext.make(g, root, {"province": {"type": "province", "id": id}})
		ctx.values["power"] = k
		bb += "\n" + BB.b(app.t("ui.district_yearly")) + "\n" + BB.desc_lines(Interp.describe_effect(ctx, root, bd.yearly))
	if not blockers.is_empty():
		bb += "\n" + BB.reasons(blockers)
	return bb

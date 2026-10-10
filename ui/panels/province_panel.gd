class_name ProvincePanel
extends RefCounted
## Окна провинции (графства) и титула: владелец, доходы, владения,
## постройки, армии, создание и узурпация вышестоящих титулов.


static func de_jure_chain(app: App, id: String) -> Array:
	var g := app.game
	var out := []
	var d: Variant = g.title_def(id)
	var t: Variant = d.get("liege") if d != null else null
	while t != null:
		out.append(t)
		var td: Variant = g.title_def(t)
		t = td.get("liege") if td != null else null
	return out


static func _chain_row(app: App, id: String) -> Control:
	var row := K.flow([], 2)
	var chain := de_jure_chain(app, id)
	for i in chain.size():
		if i > 0:
			row.add_child(K.label("›", "MutedLabel"))
		row.add_child(W.title_link(app, chain[i]))
	return row


static func _kv(pairs: Array) -> Control:
	var grid := K.grid(2, [], 16, 3)
	for p in pairs:
		if p == null:
			continue
		var l := K.label(p[0], "MutedLabel")
		grid.add_child(l)
		var v: Variant = p[1]
		if v is Control:
			grid.add_child(v)
		else:
			grid.add_child(K.label(str(v)))
	return K.panel(grid, "InsetPanel")


static func title_actions(app: App, title_id: String) -> Variant:
	var g := app.game
	var p: Variant = g.player
	var def: Variant = g.title_def(title_id)
	if p == null or def == null or def.tier == "county" or g.state.game_over != null:
		return null
	var st: Dictionary = g.state.titles[title_id]
	var share := Titles.controlled_share(g, p, title_id)
	if share.have == 0 or float(share.have) / maxf(1, share.total) < 0.25:
		return null
	var tip_head := BB.esc(app.t("ui.counties_controlled", {"have": share.have, "total": share.total}))
	if st.holder == null and not def.get("no_create", false):
		var r := Titles.can_create_title(g, p, title_id)
		var cost := Titles.title_action_cost(g, title_id, "create")
		return K.button("%s %s" % [app.t("ui.create_title"), Titles.full_name(g, title_id)], func():
			if Titles.create_title(g, p, title_id):
				app.toast(app.t("ui.title_created"), "good")
			app.mark_dirty(true), {"icon": "crown", "variation": "GoldButton", "disabled": not r.ok,
			"tip": tip_head + "\n" + BB.cost(g, cost) + ("\n" + BB.reasons(r.reasons) if not r.reasons.is_empty() else "")})
	elif st.holder != null and st.holder != p.id:
		var r := Titles.can_usurp_title(g, p, title_id)
		var cost := Titles.title_action_cost(g, title_id, "usurp")
		return K.button("%s %s" % [app.t("ui.usurp_title"), Titles.full_name(g, title_id)], func():
			if Titles.usurp_title(g, p, title_id):
				app.toast(app.t("ui.title_usurped"), "good")
			app.mark_dirty(true), {"icon": "swords", "disabled": not r.ok,
			"tip": tip_head + "\n" + BB.cost(g, cost) + ("\n" + BB.reasons(r.reasons) if not r.reasons.is_empty() else "")})
	return null


static func build(app: App, id: String) -> Control:
	var g := app.game
	var def: Variant = g.prov_def(id)
	var st: Variant = g.prov(id)
	if def == null:
		return K.vbox()
	var root := K.vbox([], 10)
	if def.get("impassable", false) or st == null:
		root.add_child(K.header(g.name_of("provinces", id)))
		root.add_child(K.label(app.t("ui.impassable"), "MutedLabel"))
		return root
	var t: Variant = g.title(id)
	var holder: Variant = g.ch(t.holder) if t != null else null
	var ctrl: Variant = Titles.province_controller(g, id)
	var name := K.label(Titles.full_name(g, id), "HeaderLabel")
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var head_info := K.vbox([name, _chain_row(app, id)], 2)
	head_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := K.hbox([W.coa(app, id, 56, false), head_info], 12)
	if holder != null:
		head.add_child(W.portrait(app, holder, 64, {"coa": true}))
	root.add_child(head)
	root.add_child(_kv([
		[app.t("ui.holder"), W.char_link(app, holder.id, true) if holder != null else app.t("ui.none")],
		[app.t("ui.occupant"), W.char_link(app, ctrl.id, true)] if ctrl != null and holder != null and ctrl.id != holder.id else null,
		[app.t("ui.terrain"), g.name_of("terrain", def.get("terrain"))],
		[app.t("ui.culture"), g.name_of("cultures", st.culture)],
		[app.t("ui.faith"), g.name_of("faiths", st.faith)],
		[app.t("ui.development"), K.fmt(st.development)],
		[app.t("ui.tax"), W.stat("gold", "%s / %s" % [K.fmt(Economy.county_tax(g, id), 2), app.t("ui.month_short")], null, UiArt.C_TEXT, 16)],
		[app.t("ui.levy"), W.stat("levies", K.fmt(Economy.county_levy(g, id)), null, UiArt.C_TEXT, 16)],
		[app.t("ui.fort"), W.stat("tower", K.fmt(Military.province_fort(g, id)), null, UiArt.C_TEXT, 16)],
	]))
	var holds := K.flow([], 6)
	for hd in Data.as_array(def.get("holdings")):
		var hdef: Variant = g.content.get_def("holdings", hd)
		var chip := K.panel(K.hbox([K.icon(hdef.get("icon", "castle") if hdef != null else "castle", 18), K.label(g.name_of("holdings", hd))], 4), "InsetPanel")
		K.tip(chip, BB.title(g.name_of("holdings", hd)) + "\n" + BB.modifiers(g, {"tax": hdef.get("tax", 0), "levy": hdef.get("levy", 0), "fort": hdef.get("fort", 0)} if hdef != null else {}))
		holds.add_child(chip)
	root.add_child(holds)
	if st.get("siege") != null:
		root.add_child(K.vbox([W.stat("tower", "%s: %d%%" % [app.t("ui.siege"), int(st.siege.progress)]), K.bar(st.siege.progress, 100, Color("#c9a040"))], 2))
	# чужая вера или культура графства (механика lands)
	if g.engine.has_feature("lands"):
		var strange := K.flow([], 4)
		for part in Lands.strangeness(g, id):
			var chip := K.panel(K.hbox([K.icon("piety" if part.kind == "faith" else "speech", 16), K.label(app.t("ui.foreign_" + part.kind), "SmallLabel")], 3))
			chip.add_theme_stylebox_override("panel", UiArt.flat(Color("#4a2a2a"), Color(UiArt.BRONZE, 0.6), 1, 3, 3))
			K.tip(chip, BB.title(app.t("ui.foreign_" + part.kind)) + "\n" + BB.esc(app.t("ui.foreign_%s_tip" % part.kind)) + "\n" + BB.modifiers(g, part.modifiers))
			strange.add_child(chip)
		if strange.get_child_count() > 0:
			root.add_child(strange)
	if not st.modifiers.is_empty():
		var mods := K.flow([], 4)
		for m in st.modifiers:
			var md: Variant = g.content.get_def("modifiers", m.id)
			var chip := K.panel(K.hbox([K.icon(md.get("icon", "star") if md != null else "star", 16), K.label(g.name_of("modifiers", m.id), "SmallLabel")], 3))
			chip.add_theme_stylebox_override("panel", UiArt.flat(Color("#2e4230") if md != null and md.get("good", false) else Color("#4a2a2a"), Color(UiArt.BRONZE, 0.6), 1, 3, 3))
			K.tip(chip, BB.title(g.name_of("modifiers", m.id)) + "\n" + BB.modifiers(g, md.get("modifiers") if md != null else null))
			mods.add_child(chip)
		root.add_child(mods)

	# постройки
	var builds := K.vbox([], 4)
	for b in st.buildings:
		var bd: Variant = g.content.get_def("buildings", b)
		var row := K.panel(K.hbox([K.icon(bd.get("icon", "castle") if bd != null else "castle", 20), K.label(g.name_of("buildings", b))], 6), "RowPanel")
		K.tip(row, BB.title(g.name_of("buildings", b)) + "\n" + BB.modifiers(g, bd.get("modifiers") if bd != null else null) + "\n" + BB.modifiers(g, bd.get("owner_modifiers") if bd != null else null))
		builds.add_child(row)
	if st.get("construction") != null:
		var bd: Variant = g.content.get_def("buildings", st.construction.building)
		var total := int(Data.num(bd.get("days"), 1)) if bd != null else 1
		var left: int = st.construction.done - g.date
		builds.add_child(K.vbox([K.label("%s — %s" % [g.name_of("buildings", st.construction.building), app.t("ui.days_left", {"n": left})]), K.bar(total - left, total)], 2))
	root.add_child(K.section("%s (%d/%d)" % [app.t("ui.buildings"), st.buildings.size(), Decisions.building_slots(g, id)], [builds], "castle"))
	var p: Variant = g.player
	if p != null and holder != null and holder.id == p.id:
		var cands := Decisions.building_candidates(g, p, id)
		if not cands.is_empty():
			var list := K.vbox([], 4)
			for item in cands:
				var bd: Dictionary = item.def
				var blockers: Array = item.blockers
				var cost := Decisions.building_cost(g, bd, p, id)
				var bid: String = bd.id
				var b := K.button("%s  ·  %s" % [g.name_of("buildings", bid), app.t("ui.days_n", {"n": bd.get("days", 0)})], func():
					if Decisions.start_building(g, p, id, bid):
						app.toast(app.t("ui.construction_started"), "good")
					app.mark_dirty(true), {"icon": bd.get("icon", "castle"), "disabled": not blockers.is_empty(), "align": HORIZONTAL_ALIGNMENT_LEFT,
					"tip": func():
						var bb := BB.title(g.name_of("buildings", bid)) + "\n" + BB.cost(g, cost)
						var desc := g.desc_of("buildings", bid)
						if desc != "":
							bb += "\n" + BB.i(desc)
						bb += "\n" + BB.modifiers(g, bd.get("modifiers")) + BB.modifiers(g, bd.get("owner_modifiers"))
						if not blockers.is_empty():
							bb += "\n" + BB.reasons(blockers)
						return bb})
				list.add_child(b)
			root.add_child(K.section(app.t("ui.build"), [list], "plus"))
	var armies := Military.armies_at(g, id)
	if not armies.is_empty():
		var al := K.vbox([], 3)
		for a in armies:
			var aid: String = a.id
			al.add_child(K.hbox([K.button(K.fmt(a.size), func(): app.select_army(aid), {"icon": "swords", "variation": "FlatButton"}), W.char_link(app, a.owner, true)], 6))
		root.add_child(K.section(app.t("ui.armies_here"), [al], "swords"))
	var actions := []
	for tt in de_jure_chain(app, id):
		var a: Variant = title_actions(app, tt)
		if a != null:
			actions.append(a)
	if not actions.is_empty():
		root.add_child(K.section(app.t("ui.title_actions"), actions, "crown"))
	var secs: Array = g.engine.ui.province_sections.values()
	Data.sort_by(secs, func(s): return Data.num(s.get("order")))
	for s in secs:
		var r: Variant = s.render.call(g, id, app)
		if r is String and r != "":
			root.add_child(K.section(g.loc.resolve(s.get("title", s.id)), [K.rich(r)]))
		elif r is Control:
			root.add_child(K.section(g.loc.resolve(s.get("title", s.id)), [r]))
	return root


static func build_title(app: App, id: String) -> Control:
	var g := app.game
	var def: Variant = g.title_def(id)
	var st: Variant = g.title(id)
	if def == null or st == null:
		return K.vbox()
	if def.tier == "county" and g.prov(id) != null:
		return build(app, id)
	var root := K.vbox([], 10)
	var name := K.label(Titles.full_name(g, id), "HeaderLabel")
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var info := K.vbox([name, _chain_row(app, id)], 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := K.hbox([W.coa(app, id, 72, false), info], 12)
	var holder: Variant = g.ch(st.holder)
	if holder != null:
		head.add_child(W.portrait(app, holder, 72, {"coa": false}))
	root.add_child(head)
	root.add_child(_kv([
		[app.t("ui.holder"), W.char_link(app, st.holder, true) if st.holder != null else app.t("ui.none")],
		[app.t("ui.counties"), K.fmt(Titles.de_jure_counties(g, id).size())],
	]))
	var act: Variant = title_actions(app, id)
	if act != null:
		root.add_child(act)
	var vassals := K.vbox([], 2)
	for tt in Titles.de_jure_vassal_titles(g, id):
		var row := K.hbox([W.coa(app, tt, 20), W.title_link(app, tt)], 6)
		var th: Variant = g.state.titles.get(tt)
		row.add_child(K.label(Chars.full_name(g, g.ch(th.holder), false) if th != null and th.holder != null else app.t("ui.none"), "SmallLabel"))
		vassals.add_child(row)
	root.add_child(K.section(app.t("ui.de_jure_vassals"), [vassals], "shield"))
	if not st.history.is_empty():
		var hist := K.vbox([], 1)
		var items: Array = st.history.duplicate()
		items.reverse()
		for e in items.slice(0, 12):
			hist.add_child(K.hbox([K.label("%d:" % int(e.from / 365), "MutedLabel"), W.char_link(app, e.holder)], 6))
		root.add_child(K.section(app.t("ui.history"), [hist], "book"))
	return root

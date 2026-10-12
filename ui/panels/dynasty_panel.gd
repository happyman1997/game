class_name DynastyPanel
extends RefCounted
## Окно рода (как в CK3): герб, слава и известность, глава рода; вкладки
## «Наследия» (ветви наследий, открывает глава) и «Род и дома».


static func build(app: App, dyn_id: Variant) -> Control:
	var g := app.game
	if dyn_id == null or not g.state.dynasties.has(dyn_id):
		return K.label(app.t("ui.lowborn_no_dynasty"), "MutedLabel")
	var root_id: Variant = Chars.dynasty_root(g, dyn_id)
	var root := K.vbox([], 10)
	root.add_child(_header(app, dyn_id, root_id))
	var tabs := [
		{"id": "legacies", "name": app.t("ui.dtab.legacies"), "icon": "star", "badge": Dynasties.owned(g, root_id).size()},
		{"id": "members", "name": app.t("ui.dtab.members"), "icon": "dynasty", "badge": Dynasties.members(g, root_id).size()},
	]
	root.add_child(W.tabs(app, "dynasty", tabs, func(tab_id: String) -> Control:
		if tab_id == "members":
			return _members_tab(app, root_id)
		return _legacies_tab(app, root_id)))
	return root


static func _header(app: App, dyn_id: Variant, root_id: Variant) -> Control:
	var g := app.game
	var info := K.vbox([], 3)
	var house := Dynasties.is_house(g, dyn_id)
	info.add_child(K.label(app.t("ui.house_n", {"name": g.name_of("dynasties", dyn_id)}) if house else app.t("ui.dynasty_n", {"name": g.name_of("dynasties", dyn_id)}), "HeaderLabel"))
	if house:
		info.add_child(K.rich(BB.muted(app.t("ui.cadet_of", {"name": ""})) + BB.link("dyn", root_id, g.name_of("dynasties", root_id)), false))
	var lv := Dynasties.level(g, root_id)
	var lvl := K.label(Dynasties.level_name(g, lv), "GoldLabel")
	K.tip(lvl, func() -> String:
		var bb := BB.title(app.t("ui.dynasty_level")) + "\n" + BB.esc(Dynasties.level_name(g, lv))
		var nxt := Dynasties.next_level_at(g, root_id)
		if nxt > 0:
			bb += "\n" + BB.muted(app.t("ui.dynasty_next_level", {"name": Dynasties.level_name(g, lv + 1), "n": K.fmt(nxt - Dynasties.renown_total(g, root_id))}))
		var lp: Array = Data.as_array(g.def_val("dynasty.level_prestige", []))
		if lv < lp.size() and Data.num(lp[lv]) != 0.0:
			bb += "\n" + BB.modifiers(g, {"monthly_prestige": Data.num(lp[lv])})
		return bb)
	info.add_child(lvl)
	info.add_child(K.hbox([
		W.stat("renown", K.fmt(Dynasties.renown(g, root_id)), func(): return renown_tip(app, root_id)),
		K.label(app.t("ui.dynasty_total_n", {"n": K.fmt(Dynasties.renown_total(g, root_id))}), "MutedLabel"),
	], 12))
	var head: Variant = Dynasties.head_of(g, root_id)
	if head != null:
		info.add_child(K.rich(BB.muted(app.t("ui.dynasty_head") + ": ") + BB.char_link(g, head.id, true), false))
	if house:
		var hh: Variant = Dynasties.head_of(g, dyn_id)
		if hh != null:
			info.add_child(K.rich(BB.muted(app.t("ui.house_head") + ": ") + BB.char_link(g, hh.id, true), false))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := K.hbox([W.dynasty_coa(app, dyn_id, 72), info], 12)
	if head != null:
		row.add_child(W.portrait(app, head, 80, {"coa": not head.titles.is_empty()}))
	return K.panel(row, "InsetPanel")


static func renown_tip(app: App, root_id: Variant) -> String:
	var g := app.game
	var bb := BB.title(app.t("ui.dynasty_renown")) + "\n" + BB.i(app.t("ui.dynasty_renown_tip"))
	bb += "\n" + BB.esc(app.t("ui.dynasty_total_n", {"n": K.fmt(Dynasties.renown_total(g, root_id))}))
	bb += "\n" + BB.esc(app.t("ui.legacy_cost", {"n": K.fmt(Dynasties.legacy_cost(g, root_id))}))
	return bb


## Описание наследия: модификаторы членам и главе, мнения.
static func legacy_desc(app: App, l: Dictionary) -> String:
	var g := app.game
	var parts := []
	var d := g.loc.t_or("dynasty_legacy_desc." + str(l.id), "")
	if d != "":
		parts.append(BB.i(d))
	var mods := BB.modifiers(g, l.get("modifiers"))
	if mods != "":
		parts.append(mods)
	var hm := BB.modifiers(g, l.get("head_modifiers"))
	if hm != "":
		parts.append(BB.muted(app.t("ui.dynasty_head") + ":") + "\n" + hm)
	var rows := []
	if Data.num(l.get("kin_opinion")) != 0.0:
		rows.append([BB.esc(app.t("opinion.dynasty_kin")), BB.good(K.signed(Data.num(l.kin_opinion)))])
	if Data.num(l.get("head_opinion")) != 0.0:
		rows.append([BB.esc(app.t("opinion.dynasty_head")), BB.good(K.signed(Data.num(l.head_opinion)))])
	if not rows.is_empty():
		parts.append(BB.rows(rows))
	return "\n".join(parts)


static func _legacies_tab(app: App, root_id: Variant) -> Control:
	var g := app.game
	var p: Variant = g.player
	var root := K.vbox([], 10)
	var cost := Dynasties.legacy_cost(g, root_id)
	var can_buy: bool = p != null and p.dynasty != null and Chars.dynasty_root(g, p.dynasty) == root_id and Dynasties.is_head(g, p)
	var line := K.hbox([
		W.stat("renown", K.fmt(Dynasties.renown(g, root_id)), func(): return renown_tip(app, root_id)),
		K.label(app.t("ui.legacy_cost", {"n": K.fmt(cost)}), "MutedLabel"),
	], 14)
	root.add_child(line)
	if p != null and Chars.dynasty_root(g, p.dynasty) == root_id and not can_buy:
		root.add_child(K.label(app.t("ui.legacy_only_head"), "MutedLabel"))
	for tr in Dynasties.tracks(g):
		var cards := K.hbox([], 6)
		for l in Dynasties.legacies_of_track(g, tr.id):
			cards.add_child(_legacy_card(app, l, root_id, can_buy))
		root.add_child(K.section(g.name_of("legacy_tracks", tr.id), [cards], tr.get("icon", "star")))
	return root


static func _legacy_card(app: App, l: Dictionary, root_id: Variant, can_buy: bool) -> Control:
	var g := app.game
	var owned := Dynasties.has_legacy(g, root_id, l.id)
	var box := K.vbox([], 4)
	var title := K.label(g.name_of("dynasty_legacies", l.id), "GoodLabel" if owned else "")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var desc := K.rich(legacy_desc(app, l))
	desc.custom_minimum_size.x = 170
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		desc.add_theme_font_size_override(k, 14)
	box.add_child(desc)
	if owned:
		box.add_child(K.label("✓ " + app.t("ui.legacy_owned"), "GoodLabel"))
	elif can_buy:
		var blockers := Dynasties.legacy_blockers(g, g.player, l.id)
		var lid: String = l.id
		var b := K.button(app.t("ui.legacy_unlock"), func():
			if Dynasties.unlock(app.game, app.game.player, lid):
				UiSound.play("click_gold")
				app.mark_dirty(true), {"variation": "GoldButton", "disabled": not blockers.is_empty(), "tip": BB.reasons(blockers) if not blockers.is_empty() else null})
		box.add_child(b)
	else:
		var blockers := []
		var lv := int(Data.num(l.get("level"), 1))
		for prev in Dynasties.legacies_of_track(g, str(l.track)):
			if int(Data.num(prev.get("level"), 1)) < lv and not Dynasties.has_legacy(g, root_id, prev.id):
				blockers.append(app.t("ui.legacy_needs", {"name": g.name_of("dynasty_legacies", prev.id)}))
				break
		if not blockers.is_empty():
			box.add_child(K.label(str(blockers[0]), "MutedLabel"))
	var panel := K.panel(K.margin(box, 4), "InsetPanel")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if owned:
		panel.modulate = Color(1.05, 1.05, 0.95)
	elif not can_buy:
		panel.modulate = Color(0.85, 0.85, 0.85)
	return panel


static func _members_tab(app: App, root_id: Variant) -> Control:
	var g := app.game
	var root := K.vbox([], 10)
	var members := Dynasties.members(g, root_id)
	# дома: старшая линия и младшие ветви
	var houses := [g.state.dynasties[root_id]] + Dynasties.houses_of(g, root_id)
	var hl := K.vbox([], 3)
	for d in houses:
		var did: String = d.id
		var n := members.filter(func(x): return x.dynasty == did).size()
		var hh: Variant = Dynasties.head_of(g, did)
		var name := BB.link("dyn", did, g.name_of("dynasties", did))
		var row := K.hbox([W.dynasty_coa(app, did, 28), K.rich(name + "  " + BB.muted("(%d)" % n), false)], 8)
		row.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if hh != null:
			row.add_child(K.rich(BB.char_link(g, hh.id, true), false))
		hl.add_child(K.panel(row, "RowPanel"))
	root.add_child(K.section(app.t("ui.dynasty_houses"), [hl], "castle"))
	# правители рода — от высших
	var rulers := members.filter(func(x): return not x.titles.is_empty())
	Data.sort_by(rulers, func(x): return Titles.primary_tier(g, x) * 10000 + float(x.prestige), true)
	if not rulers.is_empty():
		var rl := K.vbox([], 3)
		for r in rulers.slice(0, 15):
			var tier_t: String = Titles.full_name(g, r.titles[0])
			rl.add_child(W.char_row(app, r, [tier_t], [], 40))
		if rulers.size() > 15:
			rl.add_child(K.label("+%d" % (rulers.size() - 15), "MutedLabel"))
		root.add_child(K.section("%s (%d)" % [app.t("ui.dynasty_rulers"), rulers.size()], [rl], "crown"))
	# прочие члены рода — портретами
	var others := members.filter(func(x): return x.titles.is_empty())
	Data.sort_by(others, func(x): return float(x.birth))
	var flow := K.flow([], 6)
	for x in others.slice(0, 40):
		flow.add_child(W.portrait(app, x, 48))
	if others.size() > 40:
		flow.add_child(K.label("+%d" % (others.size() - 40), "MutedLabel"))
	root.add_child(K.section("%s (%d)" % [app.t("ui.dynasty_members_title"), members.size()], [flow], "person"))
	return root


## Короткий блок рода для окна персонажа: герб, имя дома, слава, известность, глава.
static func summary(app: App, c: Dictionary) -> Control:
	var g := app.game
	var root_id: Variant = Chars.dynasty_root(g, c.dynasty)
	var house := Dynasties.is_house(g, c.dynasty)
	var name := app.t("ui.house_n", {"name": g.name_of("dynasties", c.dynasty)}) if house else app.t("ui.dynasty_n", {"name": g.name_of("dynasties", c.dynasty)})
	var info := K.vbox([K.rich(BB.link("dyn", c.dynasty, name, BB.GOLD), false)], 2)
	if house:
		info.add_child(K.rich(BB.muted(app.t("ui.cadet_of", {"name": ""})) + BB.link("dyn", root_id, g.name_of("dynasties", root_id)), false))
	var head: Variant = Dynasties.head_of(g, root_id)
	info.add_child(K.hbox([
		K.label(Dynasties.level_name(g, Dynasties.level(g, root_id)), "GoldLabel"),
		W.stat("renown", K.fmt(Dynasties.renown(g, root_id)), func(): return renown_tip(app, root_id)),
		K.label(app.t("ui.dynasty_members_n", {"n": Dynasties.members(g, root_id).size()}), "MutedLabel"),
	], 12))
	if head != null:
		var tags := ""
		if head.id == c.id:
			tags = BB.gold(app.t("ui.dynasty_head"))
		else:
			tags = BB.muted(app.t("ui.dynasty_head") + ": ") + BB.char_link(g, head.id, true)
		info.add_child(K.rich(tags, false))
	if c.flags.has("disinherited"):
		info.add_child(K.label(app.t("ui.disinherited"), "BadLabel"))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var did: Variant = c.dynasty
	var open := K.button(app.t("ui.open_dynasty"), func(): app.open_panel({"kind": "dynasty", "id": did}), {"icon": "dynasty", "variation": "FlatButton"})
	var box := K.vbox([K.hbox([W.dynasty_coa(app, c.dynasty, 44), info], 10), open], 6)
	# правители рода — портретами
	var rulers := Dynasties.members(g, root_id).filter(func(x): return not x.titles.is_empty())
	Data.sort_by(rulers, func(x): return Titles.primary_tier(g, x), true)
	var rf := K.flow([], 6)
	for r in rulers.slice(0, 10):
		rf.add_child(W.portrait(app, r, 48, {"coa": true}))
	if rf.get_child_count() > 0:
		box.add_child(rf)
	return box

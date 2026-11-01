class_name RetinueSections
extends RefCounted
## Дружина в интерфейсе: строка отряда (имя, ранг, опыт, капитан, летопись),
## выбор капитана, наёмные роты.

const RANK_COLORS := ["#7d8a92", "#5f9a6a", "#b98c3e", "#c8503c"]


static func rank_chip(app: App, r: Dictionary) -> Control:
	var g := app.game
	var i := Retinue.rank_index(g, float(r.get("xp", 0.0)))
	var rk: Dictionary = Retinue.ranks(g)[i]
	var chip := K.panel(K.label(g.name_of("regiment_ranks", rk.id), "SmallLabel"))
	chip.add_theme_stylebox_override("panel", UiArt.flat(Color(RANK_COLORS[mini(i, RANK_COLORS.size() - 1)]).darkened(0.45), Color(RANK_COLORS[mini(i, RANK_COLORS.size() - 1)]), 1, 3, 2))
	return chip


## Подсказка отряда: вид войск, ранг и опыт, капитан, счёт и летопись.
static func tip(app: App, owner: Variant, r: Dictionary) -> String:
	var g := app.game
	var def: Variant = g.content.get_def("regiment_types", r.type)
	var bb := BB.title(Retinue.name_of(g, r)) + "\n" + BB.muted(g.name_of("regiment_types", r.type))
	var rs := Retinue.ranks(g)
	var i := Retinue.rank_index(g, float(r.get("xp", 0.0)))
	var xp := roundi(float(r.get("xp", 0.0)))
	if i < rs.size() - 1:
		bb += "\n" + app.t("retinue.xp", {"xp": xp, "next": g.name_of("regiment_ranks", rs[i + 1].id), "need": roundi(Data.num(rs[i + 1].xp) - xp)})
	else:
		bb += "\n" + app.t("retinue.xp_max", {"xp": xp})
	var rm := Retinue.unit_mods(g, owner, r)
	bb += "\n" + BB.good(app.t("retinue.rank_fx", {"q": snappedf(Data.num(rs[i].get("quality"), 1.0), 0.01), "m": roundi(Data.num(rs[i].get("morale")))}))
	var cap: Variant = Retinue.captain_of(g, owner, r)
	if cap != null:
		var q := roundi((float(rm.quality) / Data.num(rs[i].get("quality"), 1.0) - 1.0) * 100.0)
		bb += "\n" + app.t("retinue.captain") + ": " + BB.char_link(g, cap.id) + " — " + BB.good(app.t("retinue.captain_fx", {"q": q, "m": roundi(float(rm.morale) - Data.num(rs[i].get("morale")))}))
	bb += "\n" + app.t("retinue.record", {"b": int(r.get("battles", 0)), "w": int(r.get("wins", 0)), "k": K.fmt(float(r.get("kills", 0)))})
	if r.get("since") != null:
		bb += "\n" + BB.muted(app.t("retinue.since", {"y": GameDate.parts(int(r.since)).y}))
	var ch: Array = Data.as_array(r.get("chronicle"))
	if not ch.is_empty():
		bb += "\n\n" + BB.gold(app.t("retinue.chronicle"))
		for k in range(ch.size() - 1, maxi(-1, ch.size() - 7), -1):
			var e: Dictionary = ch[k]
			var d := GameDate.parts(int(e.date))
			var row := app.t("retinue.chronicle_row", {"date": "%d.%d.%d" % [d.d, d.m, d.y], "place": g.name_of("provinces", e.location),
				"result": app.t("retinue.won" if e.won else "retinue.lost"), "k": K.fmt(float(e.kills)), "l": K.fmt(float(e.lost))})
			if e.get("rank") != null:
				row += " — " + app.t("retinue.rank_up", {"rank": g.name_of("regiment_ranks", e.rank)})
			bb += "\n" + (BB.good(BB.esc(row)) if e.won else BB.esc(row))
	if def != null:
		bb += "\n\n" + FeatureSections.regiment_tip(app, def)
	return bb


## Строка отряда в разделе «Отряды».
static func regiment_row(app: App, p: Dictionary, r: Dictionary, raised: bool) -> Control:
	var g := app.game
	var def: Variant = g.content.get_def("regiment_types", r.type)
	var mx := Data.num(def.get("size"), 1) if def != null else 1.0
	var status := ""
	if r.get("merc") != null:
		var m: Variant = Mercenaries.get_company(g, r.merc)
		status = app.t("retinue.merc_tag") + (" · " + Mercenaries.name_of(g, m) if m != null else "")
	elif raised:
		status = app.t("ui.regiment_in_army")
	elif float(r.size) < mx:
		status = app.t("ui.regiment_reinforcing")
	var head := K.hbox([K.label(Retinue.name_of(g, r), "GoldLabel"), rank_chip(app, r)], 6)
	if status != "":
		head.add_child(K.label(status, "MutedLabel"))
	var cap: Variant = Retinue.captain_of(g, p, r)
	var cap_row: Control
	if cap != null:
		cap_row = K.hbox([K.label(app.t("retinue.captain") + ":", "SmallLabel"), W.char_link(app, cap.id)], 4)
	else:
		cap_row = K.label(app.t("retinue.no_captain"), "MutedLabel")
	var info := K.label("%s · %s / %s · %s" % [g.name_of("regiment_types", r.type), K.fmt(r.size), K.fmt(mx),
		app.t("ui.regiment_power", {"n": K.fmt(float(r.size) * Data.num(def.get("power") if def != null else 1.0))})], "SmallLabel")
	var main := K.vbox([head, info, K.bar(r.size, mx), K.bar(Retinue.rank_progress(g, r), 1.0, Color("#6f8fb0"), 4), cap_row], 2)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := K.hbox([K.icon(def.get("icon", "spear") if def != null else "spear", 26), main], 8)
	var rid: String = r.id
	if r.get("merc") == null and g.is_player(p.id):
		var btns := K.vbox([
			K.button(app.t("retinue.set_captain"), func(): open_captain(app, p, rid), {"variation": "FlatButton"}),
			K.center(K.button("", func():
				Regiments.disband(g, p, rid)
				app.mark_dirty(true), {"icon": "close", "tip": app.t("ui.dismiss_regiment")})),
		], 4)
		btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(btns)
	var pan := K.panel(row, "RowPanel")
	K.tip(pan, func():
		var rec: Variant = Retinue.record(p, rid)
		return tip(app, p, rec) if rec != null else "")
	return pan


## Окно выбора капитана: кандидаты с доблестью и военным делом.
static func open_captain(app: App, p: Dictionary, rid: String) -> void:
	var g := app.game
	var r: Variant = Retinue.record(p, rid)
	if r == null:
		return
	var close := [Callable()]
	var list := K.vbox([], 6)
	var cands := Retinue.captain_candidates(g, p, rid)
	cands.sort_custom(func(x, y): return Retinue.captain_score(g, x) > Retinue.captain_score(g, y))
	var cur: Variant = Retinue.captain_of(g, p, r)
	for c in cands.slice(0, 30):
		var cid: String = c.id
		var q := minf(g.def_num("regiments.captain_quality_max", 0.25), Stats.skill(g, c, "prowess") * g.def_num("regiments.captain_prowess", 0.012))
		var m := Stats.skill(g, c, "martial") * g.def_num("regiments.captain_martial", 0.6)
		var fx := K.label(app.t("retinue.captain_fx", {"q": roundi(q * 100.0), "m": roundi(m)}), "GoodLabel")
		var skills := K.label("⚔ %d · ♜ %d" % [Stats.skill(g, c, "prowess"), Stats.skill(g, c, "martial")], "SmallLabel")
		var info := K.vbox([W.char_link(app, cid), skills, fx], 2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_cur: bool = cur != null and cur.id == cid
		var btn := K.button(app.t("retinue.current") if is_cur else app.t("retinue.appoint"), func():
			Retinue.set_captain(g, p, rid, cid)
			close[0].call()
			app.mark_dirty(true), {"variation": "GoldButton", "disabled": is_cur})
		list.add_child(K.panel(K.hbox([W.portrait(app, c, 48), info, btn], 8), "RowPanel"))
	if cands.is_empty():
		list.add_child(K.label(app.t("retinue.no_captain"), "MutedLabel"))
	var head := K.label(app.t("retinue.captain_title", {"name": Retinue.name_of(g, r)}), "SubheaderLabel")
	var scroll := K.scroll(list)
	scroll.custom_minimum_size = Vector2(520, 400)
	var buttons := K.hbox([], 8, BoxContainer.ALIGNMENT_CENTER)
	if cur != null:
		buttons.add_child(K.button(app.t("retinue.remove"), func():
			Retinue.set_captain(g, p, rid, null)
			close[0].call()
			app.mark_dirty(true)))
	buttons.add_child(K.button(app.t("battle.close"), func(): close[0].call()))
	var body := K.vbox([head, K.para(app.t("retinue.captain_hint"), "SmallLabel"), scroll, buttons], 8)
	close[0] = app.modal(K.panel(K.margin(body, 10)), {"closable": true})


## Раздел «Наёмные роты»: свободные и свои — найм и отпуск.
static func mercenaries(app: App, p: Dictionary) -> Variant:
	var g := app.game
	if not g.engine.has_feature("mercenaries") or p.titles.is_empty():
		return null
	var comps: Array = Mercenaries.all(g).values()
	if comps.is_empty():
		return null
	# свои — первыми, потом свободные, потом чужие
	var key := func(m): return 0 if m.get("employer") == p.id else (1 if m.get("employer") == null else 2)
	comps.sort_custom(func(a, b): return key.call(a) < key.call(b) or (key.call(a) == key.call(b) and Mercenaries.men_of(g, a) > Mercenaries.men_of(g, b)))
	var list := K.vbox([], 4)
	for m in comps:
		list.add_child(_company_row(app, p, m))
	return K.section(app.t("merc.title"), [K.para(app.t("merc.hint"), "SmallLabel"), list], "coins")


static func _company_row(app: App, p: Dictionary, m: Dictionary) -> Control:
	var g := app.game
	var mid: String = m.id
	var regs := Mercenaries.regiments_of(g, m)
	var by := {}
	var order := []
	for r in regs:
		if not by.has(r.type):
			by[r.type] = 0
			order.append(r.type)
		by[r.type] += 1
	var comp := K.hbox([], 6)
	for t in order:
		var def: Variant = g.content.get_def("regiment_types", t)
		var cell := K.hbox([K.icon(def.get("icon", "spear") if def != null else "spear", 16), K.label("×%d" % by[t], "SmallLabel")], 2)
		K.tip(cell, g.name_of("regiment_types", t))
		comp.add_child(cell)
	var fake := {"xp": Mercenaries.avg_xp(g, m)}
	var head := K.hbox([K.label(Mercenaries.name_of(g, m), "GoldLabel"), rank_chip(app, fake), K.label(app.t("merc.men", {"men": K.fmt(Mercenaries.men_of(g, m))}), "SmallLabel")], 6)
	var cap: Variant = g.ch(m.get("captain"))
	var lines: Array = [head, comp]
	if cap != null:
		lines.append(K.hbox([K.label(app.t("retinue.captain") + ":", "SmallLabel"), W.char_link(app, cap.id)], 4))
	var emp: Variant = g.ch(m.get("employer"))
	var btn: Control = null
	if emp != null and emp.id == p.id:
		var d := GameDate.parts(int(m.until)) if m.get("until") != null else {"d": 0, "m": 0, "y": 0}
		lines.append(K.label(app.t("merc.yours_until", {"date": "%d.%d.%d" % [d.d, d.m, d.y]}) + " · " + app.t("merc.cost", {"hire": "—", "fee": K.fmt(Mercenaries.fee(g, m), 1)}), "GoodLabel"))
		if g.is_player(p.id):
			btn = K.button(app.t("merc.dismiss"), func():
				Mercenaries.release(g, mid, "contract")
				app.mark_dirty(true), {"variation": "FlatButton"})
	elif emp != null:
		lines.append(K.label(app.t("merc.serves", {"who": Chars.full_name(g, emp, false)}), "MutedLabel"))
	else:
		lines.append(K.label(app.t("merc.cost", {"hire": K.fmt(Mercenaries.hire_cost(g, m)), "fee": K.fmt(Mercenaries.fee(g, m), 1)}), "SmallLabel"))
		if g.is_player(p.id):
			var blockers := Mercenaries.hire_blockers(g, p, m)
			btn = K.button(app.t("merc.hire"), func():
				Mercenaries.hire(g, p, mid)
				app.mark_dirty(true), {"variation": "GoldButton", "disabled": not blockers.is_empty(),
				"tip": (BB.reasons(blockers) if not blockers.is_empty() else "")})
	var main := K.vbox(lines, 2)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := K.hbox([K.icon(m.get("icon", "⚔"), 26), main], 8)
	if btn != null:
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(btn)
	var pan := K.panel(row, "RowPanel")
	K.tip(pan, func():
		var bb := BB.title(Mercenaries.name_of(g, m))
		var desc: String = g.loc.t_or("mercenary_company_desc." + str(m.get("def")), "") if m.get("def") != null else ""
		if desc != "":
			bb += "\n" + BB.i(desc)
		for r in Mercenaries.regiments_of(g, m):
			bb += "\n• %s — %s, %s (%s)" % [BB.esc(Retinue.name_of(g, r)), BB.esc(g.name_of("regiment_types", r.type)), K.fmt(r.size), BB.esc(g.name_of("regiment_ranks", Retinue.rank_of(g, r).id))]
		return bb)
	return pan

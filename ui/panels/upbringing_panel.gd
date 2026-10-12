class_name UpbringingPanel
extends RefCounted
## Воспитание и регентство в окне персонажа: детская черта, направление
## воспитания, опекун и ожидаемое образование; воспитанники; регент
## правителя-ребёнка.


## Раздел «Воспитание» для ребёнка.
static func section(app: App, c: Dictionary) -> Control:
	var g := app.game
	var p: Variant = g.player
	var manage: bool = p != null and Upbringing.can_manage(g, p, c)
	var box := K.vbox([], 8)
	# детская черта
	var ct: Variant = Upbringing.childhood_trait(g, c)
	if ct != null:
		var d: Variant = g.content.get_def("traits", ct)
		var apt: Variant = d.childhood.get("aptitude") if (d != null and d.get("childhood") is Dictionary) else null
		var line := K.hbox([K.icon(d.get("icon", "star") if d != null else "star", 18), K.label(g.name_of("traits", ct), "GoldLabel")], 6)
		if apt != null:
			line.add_child(K.label("· %s: %s" % [app.t("ui.aptitude"), g.name_of("skills", str(apt))], "MutedLabel"))
		K.tip(line, BB.title(g.name_of("traits", ct)) + "\n" + BB.i(g.loc.t_or("trait_desc." + str(ct), "")))
		box.add_child(line)
	else:
		box.add_child(K.label(app.t("ui.childhood_none", {"n": int(g.def_num("upbringing.childhood_age", 3))}), "MutedLabel"))
	if not Upbringing.in_education(g, c):
		box.add_child(K.label(app.t("ui.too_young_for_education", {"n": int(g.def_num("upbringing.education_age", 6))}), "MutedLabel"))
		return K.section(app.t("ui.upbringing"), [box], "baby")
	# направление воспитания
	var focus: Variant = Upbringing.focus_of(g, c)
	var fl := K.hbox([], 4)
	for s in Upbringing.focuses(g):
		var sd: Variant = g.content.get_def("skills", s)
		var sid: String = s
		var cid: String = c.id
		var tipbb := BB.title(g.name_of("skills", s))
		if Upbringing.aptitude_matches(g, c, s):
			tipbb += "\n" + BB.good(app.t("ui.aptitude"))
		var b := K.button(g.name_of("skills", s), func():
			var ch: Variant = app.game.ch(cid)
			if ch != null and Upbringing.can_manage(app.game, app.game.player, ch):
				Upbringing.set_focus(app.game, ch, sid)
				app.mark_dirty(true), {"variation": "WindowTab", "icon": sd.get("icon", "star") if sd != null else "star", "icon_size": 16,
			"toggled": str(focus) == s, "disabled": not manage, "tip": tipbb})
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fl.add_child(b)
	box.add_child(K.vbox([K.label(app.t("ui.education_focus"), "SmallLabel", app.t("ui.education_focus_tip")), fl], 2))
	# опекун
	var gdn: Variant = Upbringing.guardian_of(g, c)
	if gdn != null:
		var right: Array = []
		if focus != null:
			right.append(W.stat(g.content.get_def("skills", str(focus)).get("icon", "star"), str(Stats.skill(g, gdn, str(focus))),
				BB.title(g.name_of("skills", str(focus)))))
		box.add_child(K.vbox([K.label(app.t("ui.guardian"), "SmallLabel"), W.char_row(app, gdn, [], right, 40)], 2))
	else:
		box.add_child(K.label(app.t("ui.no_guardian"), "BadLabel"))
	if manage:
		var def: Variant = g.content.get_def("interactions", "choose_guardian")
		if def != null:
			var cid: String = c.id
			box.add_child(K.button(app.t("ui.change_guardian" if gdn != null else "ui.pick_guardian"), func():
				InteractionWindow.open(app, def, app.game.player.id, cid), {"icon": "baby", "variation": "GoldButton" if gdn == null else ""}))
	# ход воспитания и ожидаемое образование
	var pts := Upbringing.points_of(g, c)
	var pred := Upbringing.predicted_points(g, c)
	var lv := Upbringing.level_for(g, pred)
	var edu: Variant = Upbringing.education_trait(g, str(focus), lv) if focus != null else null
	var ths: Array = Data.as_array(g.def_val("upbringing.level_thresholds", [70, 140, 195]))
	var top := Data.num(ths[ths.size() - 1], 195) * 1.15 if not ths.is_empty() else 200.0
	var gain := Upbringing.monthly_gain(g, c)
	var bar := K.bar(minf(pts, top), top, Color("#4a7ab8"), 14, app.t("ui.education_progress", {"n": K.fmt(pts), "gain": K.fmt(gain, 2)}))
	var cid2: String = c.id
	K.tip(bar, func() -> String:
		var ch: Variant = app.game.ch(cid2)
		if ch == null:
			return ""
		var parts := []
		Upbringing.monthly_gain(app.game, ch, parts)
		var bb := BB.title(app.t("ui.upbringing")) + "\n" + BB.breakdown(parts, 2)
		bb += "\n" + BB.muted(app.t("ui.education_levels", {"list": " / ".join(ths.map(func(x): return K.fmt(Data.num(x))))}))
		return bb)
	box.add_child(bar)
	if edu != null:
		var ed: Variant = g.content.get_def("traits", edu)
		var el := K.hbox([K.label(app.t("ui.expected_education") + ":", "SmallLabel"), K.icon(ed.get("icon", "book") if ed != null else "book", 16),
			K.label(g.name_of("traits", str(edu)), "GoodLabel" if lv >= 3 else "")], 6)
		K.tip(el, BB.title(g.name_of("traits", str(edu))) + "\n" + BB.modifiers(g, ed.get("modifiers") if ed != null else null))
		box.add_child(el)
	return K.section(app.t("ui.upbringing"), [box], "baby")


## Раздел «Воспитанники» для опекуна.
static func wards_section(app: App, c: Dictionary) -> Variant:
	var g := app.game
	var wards := Upbringing.wards_of(g, c)
	if wards.is_empty():
		return null
	var list := K.vbox([], 3)
	for w in wards:
		var f: Variant = Upbringing.focus_of(g, w)
		var lines := [app.t("ui.age_n", {"n": Chars.age_of(g, w)})]
		if f != null:
			lines.append(g.name_of("skills", str(f)))
		list.add_child(W.char_row(app, w, lines, [], 40))
	return K.section("%s (%d)" % [app.t("ui.wards"), wards.size()], [list], "baby")


## Регентство правителя-ребёнка: регент, его честолюбие, смена регента.
static func regency_section(app: App, c: Dictionary) -> Variant:
	var g := app.game
	if not Upbringing.needs_regent(g, c):
		return null
	var box := K.vbox([], 6)
	var r: Variant = Upbringing.regent_of(g, c)
	if r != null:
		var amb := Upbringing.regent_ambition(g, r, c)
		var al := K.label(app.t("ui.regent_ambitious") if amb > 0.0 else app.t("ui.regent_loyal"), "BadLabel" if amb > 0.0 else "GoodLabel")
		box.add_child(W.char_row(app, r, [al], [], 44))
	else:
		box.add_child(K.label(app.t("ui.no_regent"), "BadLabel"))
	var mods := Upbringing.regency_modifiers(g, c)
	var ml := K.rich(BB.modifiers(g, mods))
	box.add_child(ml)
	if g.is_player(c.id):
		box.add_child(K.button(app.t("ui.appoint_regent"), func(): _pick_regent(app), {"icon": "scales"}))
	var sec := K.section(app.t("ui.regency"), [box], "scales")
	K.tip(sec.get_child(0), BB.title(app.t("ui.regency")) + "\n" + BB.i(app.t("ui.regent_tip")))
	return sec


static func _pick_regent(app: App) -> void:
	var g := app.game
	var p: Dictionary = g.player
	var list := K.vbox([], 3)
	var close_ref := [Callable()]
	for x in Upbringing.regent_candidates(g, p).slice(0, 12):
		var xid: String = x.id
		var right := [W.stat("scales", str(roundi(Upbringing._regent_score(g, x)))),
			K.button(app.t("ui.appoint_regent"), func():
				var cand: Variant = app.game.ch(xid)
				if cand != null and Upbringing.can_be_regent(app.game, cand, app.game.player):
					Upbringing.set_regent(app.game, app.game.player, cand)
				close_ref[0].call()
				app.mark_dirty(true), {"variation": "GoldButton"})]
		var lines := []
		var amb := Upbringing.regent_ambition(g, x, p)
		lines.append(K.label(app.t("ui.regent_ambitious") if amb > 0.0 else app.t("ui.regent_loyal"), "BadLabel" if amb > 0.0 else "GoodLabel"))
		list.add_child(W.char_row(app, x, lines, right, 40))
	var sc := K.scroll(list)
	sc.custom_minimum_size = Vector2(540, 420)
	var body := K.vbox([K.label(app.t("ui.appoint_regent"), "HeaderLabel"), K.para(app.t("ui.regent_tip"), "MutedLabel"), sc,
		K.hbox([K.expand(), K.button(app.t("ui.cancel"), func(): close_ref[0].call(), {"min_w": 120}), K.expand()])], 8)
	close_ref[0] = app.modal(K.panel(K.margin(body, 8)))

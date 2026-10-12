class_name WarsPanel
extends RefCounted
## Вкладка «Войны»: идущие войны со счётом, мир, возможные войны;
## окно объявления войны.


static func build(app: App) -> Control:
	var g := app.game
	var p: Dictionary = g.player
	var root := K.vbox([], 10)
	var wars := Wars.wars_of(g, p.id)
	if wars.is_empty():
		root.add_child(K.label(app.t("ui.no_wars"), "MutedLabel"))
	for w in wars:
		var side: String = Wars.participant_side(w, p.id)
		var ws := Wars.warscore(g, w)
		var sign := 1.0 if side == "att" else -1.0
		var mine: float = ws.total * sign
		var leader: bool = (w.attacker if side == "att" else w.defender) == p.id
		var enemy_side := "def" if side == "att" else "att"
		var cb: Variant = g.content.get_def("casus_belli", w.cb)
		var box := K.vbox([], 8)
		var months := int((g.date - int(w.get("start", g.date))) / 30)
		box.add_child(K.hbox([K.icon(cb.get("icon", "swords") if cb != null else "swords", 26), K.label(str(w.get("name", "")), "SubheaderLabel"),
			K.expand(), K.label(app.t("ui.war_months", {"n": months}), "SmallLabel")], 6))
		var sub := g.name_of("casus_belli", w.cb)
		if w.get("target") != null:
			sub += " · " + Titles.full_name(g, w.target)
		box.add_child(K.label(sub, "MutedLabel"))

		# стороны: вождь крупно, союзники мелко, сила стороны
		var sides := K.hbox([], 10)
		for pair in [["att", "ui.attackers", w.attackers, w.attacker], ["def", "ui.defenders", w.defenders, w.defender]]:
			var strength := 0.0
			for x in pair[2]:
				var cx: Variant = g.ch(x)
				if cx != null and cx.death == null:
					strength += Economy.military_strength(g, cx)
			var ours: bool = pair[0] == side
			var head := K.hbox([K.label(app.t(pair[1]), "GoodLabel" if ours else "BadLabel"), K.expand(),
				W.stat("levies", K.fmt(strength), BB.title(app.t("ui.side_strength")), UiArt.C_TEXT, 14)], 4)
			var col := K.vbox([head], 4)
			var lead: Variant = g.ch(pair[3])
			var faces := K.flow([], 3)
			if lead != null:
				faces.add_child(W.portrait(app, lead, 56, {"coa": true}))
			for x in pair[2]:
				var c: Variant = g.ch(x)
				if c != null and x != pair[3]:
					faces.add_child(W.portrait(app, c, 36, {"coa": true}))
			col.add_child(faces)
			var side_panel := K.panel(col, "RowPanel")
			side_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			side_panel.size_flags_stretch_ratio = 1.0
			sides.add_child(side_panel)
		box.add_child(sides)

		var track := WarScoreBar.new()
		track.value = mine
		track.custom_minimum_size = Vector2(0, 20)
		var score_l := K.label("%s: %s%%" % [app.t("ui.warscore"), K.signed(mine)], "GoodLabel" if mine >= 0 else "BadLabel")
		score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var score := K.vbox([track, score_l], 2)
		K.tip(score, func():
			var rows := [
				[BB.esc(app.t("ui.ws_battles")), BB.signed(ws.battle * sign)],
				[BB.esc(app.t("ui.ws_occupation")), BB.signed(ws.occupation * sign)],
				[BB.esc(app.t("ui.ws_ticking")), BB.signed(ws.ticking * sign)],
			]
			for x in ws.extra:
				rows.append([BB.esc(x.label), BB.signed(Data.num(x.value) * sign)])
			return BB.title(app.t("ui.warscore")) + "\n" + BB.rows(rows))
		box.add_child(score)

		# цель войны: графства и кто их держит сейчас
		var goal: Array = Data.as_array(w.get("target_counties")).filter(func(c): return g.state.provinces.has(c))
		if not goal.is_empty():
			var chips := K.flow([], 4)
			for cid in goal.slice(0, 12):
				var pr: Dictionary = g.state.provinces[cid]
				var occ: bool = pr.occupant != null and pr.get("occupant_war") == w.id
				var occ_side: Variant = Wars.participant_side(w, pr.occupant) if occ else null
				var col := UiArt.C_TEXT
				if occ:
					col = UiArt.C_GOOD if occ_side == side else UiArt.C_BAD
				var chip := K.panel(K.hbox([K.icon("banner" if occ else "castle", 14, "green" if occ and occ_side == side else ("red" if occ else "gold")), K.label(g.name_of("provinces", cid), "SmallLabel")], 3))
				chip.add_theme_stylebox_override("panel", UiArt.flat(Color(0, 0, 0, 0.25), Color(col, 0.6), 1, 3, 3))
				K.on_click(chip, func(): app.open_province(cid, true))
				K.tip(chip, func(): return app.province_tooltip(cid))
				chips.add_child(chip)
			box.add_child(K.vbox([K.label(app.t("ui.war_goal"), "GoldLabel"), chips], 3))

		# битвы — последние сверху
		var battles: Array = Data.as_array(w.get("battles")).duplicate()
		battles.reverse()
		var bl := K.vbox([], 1)
		for b in battles.slice(0, 5):
			var won: bool = (b.att_won and side == "att") or (not b.att_won and side == "def")
			var d := GameDate.parts(int(b.date))
			bl.add_child(K.rich("%s  %s %s — %s %s (%s / %s)" % [
				BB.muted("%d.%d.%d" % [d.d, d.m, d.y]),
				BB.icon("swords"),
				BB.c(app.t("ui.battle_won" if won else "ui.battle_lost"), BB.GOOD if won else BB.BAD),
				BB.esc(g.name_of("provinces", b.location)),
				BB.char_link(g, b.winner),
				BB.good("−" + K.fmt(b.win_loss)) if won else BB.bad("−" + K.fmt(b.lose_loss)),
				BB.bad("−" + K.fmt(b.lose_loss)) if won else BB.good("−" + K.fmt(b.win_loss)),
			], false))
		if battles.is_empty():
			bl.add_child(K.label(app.t("ui.no_battles"), "MutedLabel"))
		box.add_child(K.vbox([K.label(app.t("ui.battles"), "GoldLabel"), bl], 3))
		if leader:
			var enemy_accepts := Wars.ai_will_accept_surrender(g, w, enemy_side)
			var win := "victory" if side == "att" else "defeat"
			var lose := "defeat" if side == "att" else "victory"
			box.add_child(K.flow([
				K.button(app.t("ui.enforce_peace"), func():
					Wars.end_war(g, w, win)
					app.mark_dirty(true), {"variation": "GoldButton", "disabled": not (mine >= 100 or enemy_accepts), "tip": app.t("ui.enforce_peace_tip")}),
				K.button(app.t("ui.white_peace"), func():
					if Wars.ai_will_accept_white_peace(g, w, enemy_side):
						Wars.end_war(g, w, "white_peace")
						app.toast(app.t("ui.white_peace_accepted"), "good")
					else:
						app.toast(app.t("ui.white_peace_refused"), "bad")
					app.mark_dirty(true)),
				K.button(app.t("ui.surrender"), func():
					Wars.end_war(g, w, lose)
					app.mark_dirty(true)),
			], 6))
		root.add_child(K.panel(box, "InsetPanel"))
	var targets := Wars.available_war_targets(g, p).slice(0, 12)
	if not targets.is_empty():
		var rows := []
		for t in targets:
			var cb: Variant = g.content.get_def("casus_belli", t.cb)
			var did: String = t.defender
			var info := K.vbox([
				K.label("%s: %s" % [g.name_of("casus_belli", t.cb), Titles.full_name(g, t.title) if t.get("title") != null else ""]),
				W.char_link(app, t.defender, true),
			], 0)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rows.append([W.category_of(g, "casus_belli", cb) if cb != null else "other", K.panel(K.hbox([K.icon(cb.get("icon", "swords") if cb != null else "swords", 22), info,
				K.button(app.t("ui.declare"), func(): open_declare_war(app, did))], 8), "RowPanel")])
		root.add_child(K.section(app.t("ui.possible_wars"), [W.grouped(app, "casus_belli", rows)], "banner"))
	return root


## Окно объявления войны персонажу (его верховному сюзерену).
static func open_declare_war(app: App, defender_id: String) -> void:
	var g := app.game
	var p: Dictionary = g.player
	var def: Dictionary = g.ch(defender_id)
	var top := Titles.top_liege(g, def)
	var targets := Wars.available_war_targets(g, p).filter(func(t): return t.defender == defender_id or t.defender == top.id)
	var close_ref := [Callable()]
	var body := K.vbox([], 10)
	body.custom_minimum_size.x = 600
	body.add_child(K.hbox([K.icon("swords", 28), K.label(app.t("ui.declare_war"), "HeaderLabel")], 8, BoxContainer.ALIGNMENT_CENTER))
	body.add_child(K.hbox([
		W.portrait(app, p, 72, {"clickable": false, "coa": true}),
		K.center(K.vbox([
			K.label("%s: %s" % [app.t("ui.your_strength"), K.fmt(Economy.military_strength(g, p))], "GoodLabel"),
			K.label("%s: %s" % [app.t("ui.enemy_strength"), K.fmt(Economy.military_strength(g, def))], "BadLabel"),
		], 2)),
		W.portrait(app, def, 72, {"clickable": false, "coa": true}),
	], 12, BoxContainer.ALIGNMENT_CENTER))
	var cards := []
	for t in targets:
		var cb: Variant = g.content.get_def("casus_belli", t.cb)
		var cost := Wars.war_cost(g, p, t)
		var afford := Wars.can_afford_war(g, p, t)
		var tt: Dictionary = t
		var card := K.vbox([
			K.hbox([K.icon(cb.get("icon", "swords") if cb != null else "swords", 22), K.label(g.name_of("casus_belli", t.cb), "SubheaderLabel")], 6),
			K.para(g.desc_of("casus_belli", t.cb), "MutedLabel"),
			K.label("%s: %s (%s)" % [app.t("ui.target"), Titles.full_name(g, t.title) if t.get("title") != null else "—", app.t("ui.counties_n", {"n": Data.as_array(t.get("counties")).size()})]),
			K.hbox([K.label(app.t("ui.enemy") + ":"), W.char_link(app, t.defender, true)], 4),
			K.rich("%s: %s" % [BB.esc(app.t("ui.cost")), BB.cost(g, cost)]),
			K.button(app.t("ui.declare"), func():
				var w: Variant = Wars.declare_war(g, p, tt)
				close_ref[0].call()
				if w != null:
					app.toast(app.t("ui.war_declared"), "bad")
				app.open_tab("wars"), {"variation": "GoldButton", "disabled": not afford}),
		], 4)
		cards.append([W.category_of(g, "casus_belli", cb) if cb != null else "other", K.panel(card, "InsetPanel")])
	var list := K.vbox([], 6)
	if not cards.is_empty():
		list.add_child(W.grouped(app, "casus_belli", cards))
	if targets.is_empty():
		list.add_child(K.label(app.t("ui.no_cb"), "MutedLabel"))
	var sc := K.scroll(list)
	sc.custom_minimum_size.y = mini(460, 200 * maxi(1, targets.size()))
	body.add_child(sc)
	body.add_child(K.hbox([K.expand(), K.button(app.t("ui.cancel"), func(): close_ref[0].call(), {"min_w": 120})]))
	close_ref[0] = app.modal(K.panel(body))


## Полоса счёта войны: от −100 (красное) до +100 (зелёное).
class WarScoreBar:
	extends Control
	var value := 0.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("#0d1113"))
		var half := size.x / 2
		var w := clampf(absf(value) / 100.0, 0.0, 1.0) * half
		if value >= 0:
			draw_rect(Rect2(half, 2, w, size.y - 4), Color("#5f9a3a"))
		else:
			draw_rect(Rect2(half - w, 2, w, size.y - 4), Color("#a83a2e"))
		draw_line(Vector2(half, 0), Vector2(half, size.y), Color(UiArt.GOLD), 2.0)
		draw_rect(r, Color(UiArt.BRONZE), false, 1.0)

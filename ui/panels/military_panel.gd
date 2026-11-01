class_name MilitaryPanel
extends RefCounted
## Вкладка «Армия» и окно армии.


static func _kv(pairs: Array) -> Control:
	return ProvincePanel._kv(pairs)


static func build(app: App) -> Control:
	var g := app.game
	var p: Dictionary = g.player
	var root := K.vbox([], 10)
	root.add_child(_kv([
		[app.t("ui.levies"), W.stat("levies", K.fmt(Economy.realm_levy(g, p)))],
		[app.t("ui.levy_ratio"), "%d%%" % roundi(float(p.levy_ratio) * 100)],
		[app.t("ui.military_strength"), K.fmt(Economy.military_strength(g, p))],
	]))
	root.add_child(K.button(app.t("ui.raise_army"), func():
		var a: Variant = Military.raise_army(g, p)
		if a != null:
			app.select_army(a.id)
			app.map_view.focus(a.location)
		app.mark_dirty(true), {"icon": "swords", "variation": "GoldButton", "disabled": not Military.can_raise_army(g, p), "tip": app.t("ui.raise_army_tip"), "min_h": 42}))
	root.add_child(K.para(app.t("ui.move_hint"), "SmallLabel"))
	var regs: Variant = FeatureSections.regiments(app, p)
	if regs != null:
		root.add_child(regs)
	var mercs: Variant = RetinueSections.mercenaries(app, p)
	if mercs != null:
		root.add_child(mercs)
	var kn: Variant = FeatureSections.knights(app, p)
	if kn != null:
		root.add_child(kn)
	var armies := Military.armies_of(g, p.id)
	if not armies.is_empty():
		var list := K.vbox([], 4)
		for a in armies:
			var aid: String = a.id
			var loc: String = a.location
			var dest := (" → " + g.name_of("provinces", a.path[a.path.size() - 1])) if not a.path.is_empty() else ""
			var card := K.panel(K.vbox([
				W.stat("swords", "%s / %s" % [K.fmt(a.size), K.fmt(a.max_size)]),
				K.bar(a.size, a.max_size, Color("#a83a2e")),
				K.label(g.name_of("provinces", a.location) + dest, "SmallLabel"),
			], 3), "RowPanel")
			K.on_click(card, func():
				app.select_army(aid)
				app.map_view.focus(loc))
			list.add_child(card)
		root.add_child(K.section(app.t("ui.armies"), [list], "swords"))
	var allies := Wars.allies_of(g, p.id)
	var al := []
	for x in allies:
		al.append(W.char_link(app, x, true))
	if al.is_empty():
		al.append(K.label(app.t("ui.no_allies"), "MutedLabel"))
	root.add_child(K.section(app.t("ui.allies"), al, "handshake"))
	var truces: Array = g.state.truces.filter(func(t): return t.until > g.date and (t.a == p.id or t.b == p.id))
	if not truces.is_empty():
		var tl := []
		for t in truces:
			tl.append(K.hbox([W.char_link(app, t.b if t.a == p.id else t.a), K.label("— " + app.t("ui.until_year", {"y": int(t.until / 365)}), "MutedLabel")], 4))
		root.add_child(K.section(app.t("ui.truces"), tl, "scroll"))
	return root


## Полководец армии: перевес с разбором, навыки; хозяину — «Сменить».
static func command_block(app: App, a: Dictionary, cmd: Dictionary) -> Control:
	var g := app.game
	var box := K.vbox([], 4)
	var adv := K.label(app.t("command.advantage", {"n": roundi(_adv_total(g, cmd))}), "GoldLabel")
	K.tip(adv, func(): return advantage_tip(app, Command.advantage_parts(g, cmd)))
	var row := K.hbox([W.portrait(app, cmd, 44), K.vbox([W.char_link(app, cmd.id), adv], 2)], 8)
	if g.is_player(a.owner):
		row.add_child(K.expand())
		row.add_child(K.button(app.t("command.change"), func(): open_appoint(app, a), {"variation": "FlatButton"}))
	box.add_child(row)
	var sk: Variant = skill_chips(app, cmd)
	if sk != null:
		box.add_child(sk)
	return K.section(app.t("command.title"), [box], "swords")


static func _adv_total(g: Game, c: Dictionary) -> float:
	var v := 0.0
	for p in Command.advantage_parts(g, c):
		v += float(p.value)
	return v


## Разбор очков перевеса (для подсказки).
static func advantage_tip(app: App, parts: Array) -> String:
	var g := app.game
	var rows := []
	var total := 0.0
	for p in parts:
		total += float(p.value)
		var name: String = g.name_of("traits", p.trait) if p.get("trait") != null else app.t("command.part." + str(p.key))
		rows.append([BB.esc(name), BB.signed(float(p.value))])
	return BB.title(app.t("command.advantage", {"n": roundi(total)})) + "\n" + BB.rows(rows) + "\n" + BB.small(BB.muted(app.t("command.advantage_tip")))


## Навыки полководца — значки с подсказками.
static func skill_chips(app: App, c: Dictionary) -> Variant:
	var g := app.game
	var ts := Command.traits_of(g, c)
	if ts.is_empty():
		return null
	var f := K.flow([], 4)
	for d in ts:
		var chip := K.panel(K.hbox([K.icon(d.get("icon"), 14), K.label(g.name_of("traits", d.id), "SmallLabel")], 3))
		chip.add_theme_stylebox_override("panel", UiArt.flat(Color("#3a2a1a"), Color(UiArt.BRONZE, 0.7), 1, 3, 3))
		var tid: String = d.id
		K.tip(chip, func(): return BB.title(g.name_of("traits", tid)) + "\n" + BB.i(g.loc.t_or("trait_desc." + tid, "")) + "\n" + Command.describe(g, Chars.trait_def(g, tid)))
		f.add_child(chip)
	return f


## Окно выбора полководца: кандидаты с перевесом и навыками.
static func open_appoint(app: App, a: Dictionary) -> void:
	var g := app.game
	var owner: Variant = g.ch(a.owner)
	if owner == null:
		return
	var close := [Callable()]
	var list := K.vbox([], 6)
	var cands := Command.candidates(g, owner, a.id)
	cands.sort_custom(func(x, y): return Command.score(g, x) > Command.score(g, y))
	var cur: Variant = Military.commander_of(g, a)
	for c in cands.slice(0, 24):
		var cid: String = c.id
		var adv := K.label(app.t("command.advantage", {"n": roundi(_adv_total(g, c))}), "GoldLabel")
		K.tip(adv, func(): return advantage_tip(app, Command.advantage_parts(g, g.ch(cid))))
		var info := K.vbox([W.char_link(app, cid), adv], 2)
		var sk: Variant = skill_chips(app, c)
		if sk != null:
			info.add_child(sk)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_cur: bool = cur != null and cur.id == cid
		var btn := K.button(app.t("command.current") if is_cur else app.t("command.appoint"), func():
			Command.appoint(g, a, cid)
			close[0].call()
			app.mark_dirty(true), {"variation": "GoldButton", "disabled": is_cur})
		list.add_child(K.panel(K.hbox([W.portrait(app, c, 48), info, btn], 8), "RowPanel"))
	var head := K.label(app.t("command.appoint_title"), "SubheaderLabel")
	var scroll := K.scroll(list)
	scroll.custom_minimum_size = Vector2(520, 420)
	var body := K.vbox([head, K.para(app.t("command.appoint_hint"), "SmallLabel"), scroll,
		K.center(K.button(app.t("battle.close"), func(): close[0].call()))], 8)
	close[0] = app.modal(K.panel(K.margin(body, 10)), {"closable": true})


static func build_army(app: App, id: String) -> Control:
	var g := app.game
	if not g.state.armies.has(id):
		return K.label(app.t("ui.army_gone"), "MutedLabel")
	var a: Dictionary = g.state.armies[id]
	var root := K.vbox([], 10)
	var cmd: Variant = Military.commander_of(g, a)
	var owner: Variant = g.ch(a.owner)
	var head := K.hbox([], 10)
	if owner != null:
		head.add_child(W.portrait(app, owner, 64, {"coa": true}))
	head.add_child(K.vbox([K.label(K.fmt(a.size), "TitleLabel"), K.bar(a.size, a.max_size, Color("#a83a2e"), 10)], 2))
	head.get_child(head.get_child_count() - 1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(head)
	var war: Variant = Military.hostile_war_at(g, a, a.location)
	var pst: Variant = g.prov(a.location)
	var status := app.t("ui.idle")
	if a.get("retreating", false):
		status = app.t("ui.retreating")
	elif not a.path.is_empty():
		status = app.t("ui.marching", {"place": g.name_of("provinces", a.path[a.path.size() - 1]), "days": Military.days_to_next(g, a)})
	elif pst != null and pst.get("siege") != null and pst.siege.get("army") == a.id:
		status = app.t("ui.sieging", {"n": int(pst.siege.progress)})
	elif war != null:
		status = app.t("ui.in_enemy_land")
	root.add_child(_kv([
		[app.t("ui.owner"), W.char_link(app, a.owner, true)],
		[app.t("ui.commander"), W.char_link(app, cmd.id) if cmd != null else app.t("ui.none")],
		[app.t("ui.location"), W.prov_link(app, a.location)],
		[app.t("ui.status"), status],
	]))
	if cmd != null and g.engine.has_feature("command"):
		root.add_child(command_block(app, a, cmd))
	var regs: Variant = FeatureSections.army_regiments(app, a)
	if regs != null:
		root.add_child(regs)
	if g.is_player(a.owner):
		root.add_child(K.para(app.t("ui.move_hint"), "SmallLabel"))
		root.add_child(K.button(app.t("ui.disband"), func():
			Military.disband_army(g, a.id)
			app.map_view.selected_army = null
			app.close_panel(), {"icon": "close"}))
	return root

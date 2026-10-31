class_name AffairsPanel
extends RefCounted
## Окно «Дела» (механика affairs): свои дела — поручения, работы на земле и
## дорогах, стройка, интриги — с ходом и сроком; чужие дела рядом — с
## кнопками вмешательства (помочь открыто или тайно помешать: шанс и риск
## раскрытия — в подсказке); угрозы в державе — шайки.


static func build(app: App) -> Control:
	var g := app.game
	var p: Dictionary = g.player
	var root := K.vbox([], 10)
	root.add_child(K.para(app.t("affairs.hint"), "SmallLabel"))
	var vis := Affairs.visible_to(g, p)
	# свои дела
	var mine := []
	for a in vis.mine:
		mine.append(_row(app, p, a, false))
	if mine.is_empty():
		mine.append(K.label(app.t("affairs.none_mine"), "MutedLabel"))
	root.add_child(K.section(app.t("affairs.mine"), mine, "scroll"))
	# чужие дела рядом
	var others := []
	var list: Array = vis.others
	list.sort_custom(func(a, b): return (1 if a.get("to_me", false) else 0) > (1 if b.get("to_me", false) else 0))
	for a in list:
		others.append(_row(app, p, a, true))
	if others.is_empty():
		others.append(K.label(app.t("affairs.none_others"), "MutedLabel"))
	root.add_child(K.section(app.t("affairs.others"), others, "eye"))
	# шайки в державе
	if g.engine.has_feature("travel"):
		var realm := Titles.realm_counties(g, p)
		var bl := []
		for b in Travel.bands(g).values():
			if realm.has(b.province):
				var bid: String = b.id
				var lbl := K.label("⚠ %s — %s" % [g.name_of("bands", str(b.kind)), g.name_of("provinces", b.province)])
				lbl.add_theme_color_override("font_color", Color("#e08a6a"))
				K.tip(lbl, func(): return app.thing_tooltip("band", bid))
				var pid: String = b.province
				K.on_click(lbl, func(): app.open_province(pid, true))
				bl.append(lbl)
		if not bl.is_empty():
			root.add_child(K.section(app.t("affairs.bands"), bl, "warning"))
	return root


static func _icon(a: Dictionary) -> String:
	match str(a.kind):
		"land_work":
			return "wheat"
		"road_work":
			return "horse"
		"construction":
			return "scaffold"
		"mission":
			return "map"
		"scheme":
			return "dagger"
	return "scroll"


## Строка дела: значок, название, хозяин (у чужих), ход, срок; у чужих —
## кнопки вмешательства.
static func _row(app: App, p: Dictionary, a: Dictionary, foreign: bool) -> Control:
	var g := app.game
	var title := K.label(Affairs.title_of(g, a), "SubheaderLabel")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 160
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := K.hbox([title], 6)
	if foreign and a.get("actor") != null and g.ch(a.actor) != null:
		head.add_child(W.char_link(app, a.actor, true))
	if a.get("to_me", false):
		head.add_child(K.label("· " + app.t("affairs.to_me"), "GoodLabel"))
	var info := K.vbox([head], 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sub := app.t("affairs.kind." + str(a.kind))
	if int(a.get("days", -1)) >= 0:
		sub += " · " + app.t("affairs.days", {"n": int(a.days)})
	info.add_child(K.label(sub, "SmallLabel"))
	info.add_child(K.bar(float(a.progress), 1.0, Color("#8fae5a") if not foreign else Color("#b0905a"), 6))
	var row := K.hbox([K.icon(_icon(a), 26), info], 8)
	if foreign:
		var btns := K.hbox([], 4)
		for d in Affairs.for_affair(g, a):
			btns.add_child(_meddle_button(app, p, a, d))
		row.add_child(btns)
	var place: Variant = a.get("place")
	if place != null:
		K.on_click(info, func(): app.open_province(str(place), true))
	return K.panel(row, "InsetPanel")


static func _meddle_button(app: App, p: Dictionary, a: Dictionary, d: Dictionary) -> Control:
	var g := app.game
	var iid: String = d.id
	var key: String = a.key
	var why := Affairs.blockers(g, p, a, d)
	var b := K.button(str(d.get("icon", "")), func():
		var res := Affairs.meddle(g, p, key, iid)
		if res != "":
			app.toast(g.name_of("interventions", iid), "good" if res in ["help", "success"] else ("info" if res == "partial" else "bad"))
		app.mark_dirty(true), {"min_w": 36, "variation": "GoldButton" if str(d.get("side")) == "help" else ""})
	b.disabled = not why.is_empty()
	K.tip(b, func() -> String:
		var bb := BB.title(g.name_of("interventions", iid)) + "\n" + BB.esc(g.loc.t("intervention_desc." + iid))
		var cost := Affairs.cost_for(g, p, d)
		if cost > 0.0:
			bb += "\n" + BB.cost(g, {"gold": cost})
		var ctx := Affairs._ctx(g, p, a, iid)
		if str(d.get("side", "help")) == "help":
			bb += "\n" + BB.desc_lines(Interp.describe_effect(ctx, ctx.root, d.get("effect")))
			bb += "\n" + BB.good(app.t("affairs.help_note"))
		else:
			var spec: Dictionary = (d.get("check") if d.get("check") is Dictionary else {}).duplicate()
			for k in ["success", "partial", "failure"]:
				if d.get(k) != null:
					spec[k] = d[k]
			var o := Checks.odds(ctx, ctx.root, spec)
			bb += "\n" + app.t("affairs.chance", {"s": roundi(o.success), "p": roundi(o.partial), "f": roundi(o.failure)})
			bb += "\n" + BB.breakdown(o.parts, 0)
			var disc: Variant = d.get("discovery")
			if disc is Dictionary:
				bb += "\n" + BB.bad(app.t("affairs.discovery", {"s": int(Data.num(disc.get("success"))), "p": int(Data.num(disc.get("partial"))), "f": int(Data.num(disc.get("failure")))}))
			var lines: Array = Interp.describe_effect(ctx, ctx.root, d.get("success"))
			if not lines.is_empty():
				bb += "\n" + BB.muted(app.t("affairs.on_success")) + "\n" + BB.desc_lines(lines)
		if not why.is_empty():
			bb += "\n" + BB.bad("\n".join(why.map(func(k): return app.t(k))))
		return bb)
	return b

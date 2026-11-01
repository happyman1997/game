class_name BattleWindow
extends RefCounted
## Окно битвы: стороны с полководцами, итог, ход боя по дням (дух и потери
## обеих сторон), войска по видам, рыцари в гуще и переломы. rec — запись
## битвы войны (war.battles[]) или поля битвы: {date, location, winner,
## loser, report} (отчёт — engine/world/battle.gd).

const THEME := Color("#6b2a1c")
const C_ATT := Color("#c8503c")
const C_DEF := Color("#4f7fb8")


static func build(app: App, rec: Dictionary, on_close: Callable) -> Control:
	var g := app.game
	var r: Dictionary = rec.report
	var wi := int(r.winner)
	var d := GameDate.parts(int(rec.date))
	var head := K.label(app.t("battle.title", {"place": g.name_of("provinces", rec.location)}), "TitleLabel")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 28)
	var span := app.t("battle.days", {"n": int(r.days)}) if int(r.days) > 0 else app.t("battle.no_melee")
	var date_l := K.label("%d.%d.%d · %s" % [d.d, d.m, d.y, span], "MutedLabel")
	date_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# стороны: полководец, хозяин, войско до и после
	var scene := EventWindow.EventScene.new()
	scene.color = THEME
	scene.icon_name = Icons.resolve("swords")
	scene.custom_minimum_size = Vector2(0, 268)
	var row := K.hbox([_side(app, r, 0), _center(app, r), _side(app, r, 1)], 24, BoxContainer.ALIGNMENT_CENTER)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(row)

	var refused: bool = Data.as_array(r.events).any(func(e): return e.kind == "refused")
	var wname := _owner_name(app, r, wi)
	var lname := _owner_name(app, r, 1 - wi)
	var result := K.rich("[center]%s[/center]" % BB.gold(app.t("battle.result_refused" if refused else "battle.result", {"winner": wname, "loser": lname})))

	var parts: Array = [result, K.section(app.t("battle.course"), [_course(app, r)], "swords")]
	parts.append(K.section(app.t("battle.units"), [K.hbox([_units(app, r, 0), _units(app, r, 1)], 16)], "banner"))
	var kn: Variant = _knights(app, r)
	if kn != null:
		parts.append(K.section(app.t("battle.knights"), [kn], "sword"))
	parts.append(K.section(app.t("battle.turns"), [_turns(app, r)], "scroll"))
	var body_box := K.vbox(parts, 8)
	var scroll := K.scroll(K.margin(body_box, 6))
	scroll.custom_minimum_size = Vector2(0, 330)
	var parchment := K.panel(scroll, "ParchmentPanel")
	var close := K.button(app.t("battle.close"), on_close, {"variation": "GoldButton"})
	var body := K.vbox([K.panel(K.vbox([head, date_l], 2), "HeaderPanel"), scene, parchment, K.center(close)], 8)
	body.custom_minimum_size = Vector2(760, 0)
	return K.panel(body)


static func _owner_name(app: App, r: Dictionary, i: int) -> String:
	var owners: Array = r.sides[i].owners if i < r.sides.size() else []
	var o: Variant = app.game.ch(owners[0]) if not owners.is_empty() else null
	return Chars.full_name(app.game, o, false) if o != null else app.t("battle.side_att" if i == 0 else "battle.side_def")


static func _side_word(app: App, i: int) -> String:
	return app.t("battle.side_att" if i == 0 else "battle.side_def")


static func _side(app: App, r: Dictionary, i: int) -> Control:
	var g := app.game
	var s: Dictionary = r.sides[i]
	var col := C_ATT if i == 0 else C_DEF
	var items: Array = []
	var won := int(r.winner) == i
	var lbl := K.label(_side_word(app, i), "GoodLabel" if won else "BadLabel")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	items.append(lbl)
	var cmd: Variant = g.ch(s.get("commander"))
	if cmd != null:
		items.append(K.center(W.portrait(app, cmd, 76, {"coa": true})))
		var cn := K.label(Chars.full_name(g, cmd, false), "SmallLabel")
		cn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		items.append(cn)
		# перевес полководца (разбор — в подсказке) и значки его навыков
		var adv := K.label(app.t("battle.advantage", {"n": roundi(float(s.get("adv", 0.0)))}), "GoldLabel")
		var parts: Array = Data.as_array(s.get("adv_parts"))
		K.tip(adv, func(): return MilitaryPanel.advantage_tip(app, parts))
		var adv_row := K.hbox([adv], 4, BoxContainer.ALIGNMENT_CENTER)
		for d in Command.traits_of(g, cmd):
			var ic := K.icon(d.get("icon"), 16)
			var tid: String = d.id
			K.tip(ic, func(): return BB.title(g.name_of("traits", tid)) + "\n" + Command.describe(g, Chars.trait_def(g, tid)))
			adv_row.add_child(ic)
		items.append(adv_row)
		var fate := str(r.commander[i]) if i < r.commander.size() else ""
		if fate != "":
			var fl := K.label(app.t("battle.cmd_fate_short." + fate), "BadLabel")
			fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			items.append(fl)
	else:
		var owners: Array = s.owners
		var o: Variant = g.ch(owners[0]) if not owners.is_empty() else null
		if o != null:
			items.append(K.center(W.portrait(app, o, 76, {"coa": true})))
		items.append(K.label(app.t("battle.no_commander"), "MutedLabel"))
	var men := int(r.start[i])
	var left := men - int(r.lost[i])
	var bar := _meter(left, maxi(1, men), col, "%s → %s" % [K.fmt(men), K.fmt(left)], 180)
	items.append(K.center(bar))
	var box := K.vbox(items, 3)
	box.custom_minimum_size = Vector2(220, 0)
	return box


static func _center(app: App, r: Dictionary) -> Control:
	var m: Array = r.get("morale", [0, 0])
	var l := K.label("%s\n%d : %d" % [app.t("battle.morale"), int(m[0]), int(m[1])], "SubheaderLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return K.center(l)


## Плотная полоса с подписью: фон, заливка по доле, текст посередине.
static func _meter(value: float, max_value: float, color: Color, text: String, width: float) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(width, 18)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.28)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color(color, 0.85)
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(value / maxf(1e-9, max_value), 0.0, 1.0)
	box.add_child(fill)
	var l := K.label(text, "SmallLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_color_override("font_color", Color("#f4ead2"))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	box.add_child(l)
	return box


## Ход боя: фаза, дух обеих сторон полосами, потери за день.
static func _course(app: App, r: Dictionary) -> Control:
	var grid := K.grid(4, [], 10, 4)
	for e in r.log:
		var ph := str(e.phase)
		var name := app.t("battle.phase." + ph, {"n": int(e.day)})
		grid.add_child(K.label(name, "GoldLabel" if ph != "melee" else ""))
		for i in 2:
			var mo := float(e.morale[i])
			grid.add_child(_meter(mo, 100.0, C_ATT if i == 0 else C_DEF, str(int(mo)), 150))
		grid.add_child(K.rich("%s  %s" % [BB.c("−" + K.fmt(float(e.lost[0])), "#" + C_ATT.to_html(false)), BB.c("−" + K.fmt(float(e.lost[1])), "#" + C_DEF.to_html(false))], false))
	return grid


## Войска стороны по видам: сколько было, сколько осталось, сколько бежало.
static func _units(app: App, r: Dictionary, i: int) -> Control:
	var g := app.game
	var by := {}
	var order := []
	for u in r.units[i]:
		var t := str(u.type)
		if not by.has(t):
			by[t] = {"men": 0, "left": 0, "fled": 0}
			order.append(t)
		by[t].men += int(u.men)
		by[t].left += int(u.left)
		by[t].fled += int(u.get("fled", 0))
	var rows := K.vbox([K.label(_side_word(app, i), "GoodLabel" if int(r.winner) == i else "BadLabel")], 3)
	for t in order:
		var x: Dictionary = by[t]
		var def: Variant = g.content.get_def("regiment_types", t)
		var icon: String = str(def.get("icon", "👥")) if def != null else "👥"
		var nm := app.t("battle.levy") if t == "levy" else g.name_of("regiment_types", t)
		var lost := int(x.men) - int(x.left)
		var txt := "%s %s  %s → %s  %s" % [icon, BB.esc(nm), K.fmt(x.men), K.fmt(x.left), BB.bad("−" + K.fmt(lost)) if lost > 0 else ""]
		if int(x.fled) > 0:
			txt += " " + BB.muted("(%s %s)" % [K.fmt(x.fled), app.t("battle.fled")])
		rows.add_child(K.rich(txt, false))
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rows


static func _knights(app: App, r: Dictionary) -> Variant:
	var list: Array = Data.as_array(r.get("knights"))
	if list.is_empty():
		return null
	var g := app.game
	var box := K.vbox([], 2)
	for f in list:
		var by := BB.char_link(g, f.get("by")) if f.get("by") != null and g.ch(f.get("by")) != null else "?"
		var col := BB.BAD if str(f.fate) in ["killed", "captured"] else BB.MUTED
		box.add_child(K.rich("%s · %s — %s" % [BB.muted(_side_word(app, int(f.side))), BB.char_link(g, f.id) if g.ch(f.id) != null else "?",
			BB.c(app.t("battle.fate." + str(f.fate), {"by": by}), col)], false))
	return box


## Переломы: что решило бой.
static func _turns(app: App, r: Dictionary) -> Control:
	var g := app.game
	var box := K.vbox([], 2)
	for e in r.events:
		var kind := str(e.kind)
		var side := _side_word(app, int(e.side))
		var b_name := ""
		if kind == "learned":
			b_name = g.name_of("traits", str(e.get("b", "")))
		elif e.get("b") != null and g.ch(e.b) != null:
			b_name = Chars.full_name(g, g.ch(e.b), false)
		var params := {"side": side, "n": K.fmt(Data.num(e.get("n"))),
			"a": Chars.full_name(g, g.ch(e.a), false) if e.get("a") != null and g.ch(e.a) != null else "",
			"b": b_name}
		var day := app.t("battle.phase.skirmish") if int(e.day) == 0 else app.t("battle.phase.melee", {"n": int(e.day)})
		box.add_child(K.rich("%s  %s" % [BB.muted(day), BB.esc(app.t("battle.ev." + kind, params))], false))
	return box

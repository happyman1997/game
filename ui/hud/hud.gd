class_name Hud
extends Control
## Игровой экран поверх карты (по образцу CK3):
##   слева вверху — оповещения; справа вверху — ресурсы и меню;
##   слева внизу — медальон игрока с гербом и кнопками разделов по дуге;
##   справа внизу — дата и скорость, над ними — режимы карты;
##   справа — список армий, войн и интриг и журнал событий;
##   слева — окно (персонаж, провинция, раздел).

var app: App

var resources: HBoxContainer
var alerts_box: HBoxContainer
var cluster: Control
var tabs_box: Control
var date_label: Label
var pause_btn: Button
var speed_pips: Array = []
var modes_box: HBoxContainer
var outliner: VBoxContainer
var messages: VBoxContainer
var window: PanelContainer
var window_title: Label
var window_back: Button
var window_body: ScrollContainer
var pick_banner: Control

var _alerts_sig := ""
var _cluster_sig := ""
var _tabs_sig := ""
var _modes_sig := ""
var _window_key := ""
var _window_at := 0
var _seen_messages := 0
var _res_sig := ""
var _date_sig := ""
var _outliner_sig := ""
var _messages_sig := ""

## Пока игра идёт, открытое окно обновляется не чаще (мс): его перестройка дорогая.
const LIVE_WINDOW_MS := 1500


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func t(key: String, params: Dictionary = {}) -> String:
	return app.t(key, params)


func build() -> void:
	_seen_messages = app.game.state.messages.size()
	# ---- справа вверху: ресурсы
	var top_right := K.panel(null, "BarPanel")
	top_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.offset_right = 0
	top_right.offset_top = 0
	resources = K.hbox([], 18)
	var menu_btn := K.round_button("menu", func(): GameMenu.open(app), t("ui.menu"), 34)
	top_right.add_child(K.hbox([resources, K.spacer(6), menu_btn], 8))
	add_child(top_right)

	# ---- слева вверху: оповещения
	alerts_box = K.hbox([], 6)
	alerts_box.position = Vector2(12, 10)
	add_child(alerts_box)

	# ---- баннер выбора персонажа
	pick_banner = K.panel(K.label(t("ui.pick_character_hint"), "SubheaderLabel"), "DarkPanel")
	pick_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pick_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pick_banner.offset_top = 56
	add_child(pick_banner)

	# ---- справа внизу: дата и скорость
	var date_panel := K.panel(null, "PanelContainer")
	date_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	date_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	date_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	date_panel.offset_right = -10
	date_panel.offset_bottom = -10
	pause_btn = K.round_button("pause", func(): app.toggle_pause(), t("ui.pause_hint"), 46)
	date_label = K.label("", "HeaderLabel")
	date_label.custom_minimum_size.x = 210
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K.tip(date_label, t("ui.speed_hint"))
	var pips := K.hbox([], 3)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	for s in range(1, 6):
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(26, 16)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var speed := s
		b.pressed.connect(func():
			app.set_speed(speed)
			if app.paused:
				app.toggle_pause())
		K.tip(b, t("ui.speed_n", {"n": s}))
		pips.add_child(b)
		speed_pips.append(b)
	var minus := K.button("−", func(): app.set_speed(app.speed - 1), {"min_w": 26, "tip": t("ui.speed_down")})
	var plus := K.button("+", func(): app.set_speed(app.speed + 1), {"min_w": 26, "tip": t("ui.speed_up")})
	date_panel.add_child(K.hbox([pause_btn, K.vbox([date_label, K.hbox([minus, pips, plus], 4, BoxContainer.ALIGNMENT_CENTER)], 2)], 10))
	add_child(date_panel)

	# ---- над датой: режимы карты
	modes_box = K.hbox([], 4)
	var modes_panel := K.panel(modes_box, "DarkPanel")
	modes_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	modes_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	modes_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	modes_panel.offset_right = -14
	modes_panel.offset_bottom = -112
	add_child(modes_panel)

	# ---- справа: обзор (армии, войны, интриги) и журнал
	var right := K.vbox([], 8)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.offset_top = 64
	right.offset_right = -10
	right.custom_minimum_size.x = 300
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outliner = K.vbox([], 2)
	var ol_panel := K.panel(outliner, "DarkPanel")
	ol_panel.name = "Outliner"
	right.add_child(ol_panel)
	messages = K.vbox([], 2)
	var msg_panel := K.panel(messages, "DarkPanel")
	msg_panel.name = "Messages"
	right.add_child(msg_panel)
	add_child(right)

	# ---- слева внизу: медальон игрока, герб и полоса разделов
	cluster = Control.new()
	cluster.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cluster.offset_left = 0
	cluster.offset_top = -158
	cluster.offset_right = 760
	cluster.offset_bottom = 0
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cluster)
	tabs_box = Control.new()
	tabs_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	cluster.add_child(tabs_box)

	# ---- окно слева
	window = PanelContainer.new()
	window.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	window.offset_left = 8
	window.offset_top = 52
	window.offset_right = 8 + 500
	window.offset_bottom = -166
	window.visible = false
	var head := K.hbox([], 6)
	window_back = K.button("", func(): app.back(), {"icon": "back", "variation": "CloseButton", "min_w": 32, "min_h": 32, "tip": t("ui.back")})
	window_title = K.label("", "HeaderLabel")
	window_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	window_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	window_title.clip_text = true
	var close := K.button("", func(): app.close_panel(), {"icon": "close", "variation": "CloseButton", "min_w": 32, "min_h": 32, "tip": t("ui.close")})
	head.add_child(window_back)
	head.add_child(window_title)
	head.add_child(close)
	var head_panel := K.panel(head, "HeaderPanel")
	window_body = ScrollContainer.new()
	window_body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	window_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	window.add_child(K.vbox([head_panel, window_body], 6))
	add_child(window)


# ------------------------------------------------------------ обновление

## full — полная перерисовка (действие игрока, пауза); иначе — «живое»
## обновление во время хода игры: перестраивается только изменившееся.
func refresh(full: bool = true) -> void:
	var g := app.game
	var p: Variant = g.player
	pick_banner.visible = app.pick_mode
	_refresh_resources(p)
	_refresh_alerts(p)
	_refresh_cluster(p)
	_refresh_date()
	_refresh_modes()
	_refresh_outliner(p)
	_refresh_messages()
	_refresh_window(full)


func _refresh_resources(p: Variant) -> void:
	var g := app.game
	var items: Array = []
	if p != null:
		var income := Economy.monthly_income(g, p)
		items.append(["gold", K.fmt(p.gold), K.signed(income, 1), income >= 0, func():
			var pl: Variant = app.game.player
			return BB.title(t("ui.gold")) + ("\n" + BB.breakdown(Economy.income_breakdown(app.game, pl), 1) if pl != null else "")])
		var mp := Economy.monthly_prestige(g, p)
		items.append(["prestige", K.fmt(p.prestige), K.signed(mp, 1), mp >= 0, BB.title(t("ui.prestige"))])
		var pi := Economy.monthly_piety(g, p)
		items.append(["piety", K.fmt(p.piety), K.signed(pi, 1), pi >= 0, BB.title(t("ui.piety"))])
		items.append(["levies", K.fmt(Economy.realm_levy(g, p)), "", true, BB.title(t("ui.levies"))])
		if float(p.stress) > 0:
			items.append(["stress", K.fmt(p.stress), "", float(p.stress) < 100, BB.title(t("ui.stress"))])
		var widgets: Array = g.engine.ui.top_bar.values()
		Data.sort_by(widgets, func(w): return Data.num(w.get("order")))
		for w in widgets:
			var r: Variant = w.render.call(g)
			if r is Dictionary:
				items.append([r.get("icon", "star"), str(r.get("text", "")), "", true, r.get("tooltip")])
	# Перестраиваем, только если изменились значения (подсказки — по тексту).
	var sig := ""
	for it in items:
		sig += "%s|%s|%s|%s|%s;" % [it[0], it[1], it[2], it[3], it[4] if it[4] is String else ""]
	if sig == _res_sig:
		return
	_res_sig = sig
	K.clear(resources)
	for it in items:
		resources.add_child(_res(it[0], it[1], it[2], it[3], it[4]))


func _res(icon_name: Variant, value: String, delta: String, positive: bool, tip_content: Variant) -> Control:
	var v := K.label(value)
	v.add_theme_font_override("font", Fonts.bold())
	var row := K.hbox([K.icon(icon_name, 22), v], 4)
	if delta != "":
		var d := K.label("(" + delta + ")", "SmallLabel")
		d.add_theme_color_override("font_color", UiArt.C_GOOD if positive else UiArt.C_BAD)
		row.add_child(d)
	elif not positive:
		v.add_theme_color_override("font_color", UiArt.C_BAD)
	if tip_content != null:
		K.tip(row, tip_content)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


func _refresh_alerts(p: Variant) -> void:
	var list: Array = Alerts.collect(app.game) if p != null else []
	var sig := ""
	for a in list:
		sig += str(a.get("icon")) + str(a.get("text")) + "|"
	if sig == _alerts_sig:
		return
	_alerts_sig = sig
	K.clear(alerts_box)
	for a in list:
		var kind: String = a.get("kind", "info")
		var b := K.round_button(a.get("icon", "warning"), func(): Alerts.run_action(app, a.get("action")), null, 44)
		var ring: Color = {"good": Color("#7fcf5a"), "bad": Color("#e0503e")}.get(kind, UiArt.C_GOLD)
		b.self_modulate = Color.WHITE.lerp(ring, 0.35)
		K.tip(b, BB.c(a.get("text", ""), BB.GOOD if kind == "good" else (BB.BAD if kind == "bad" else BB.GOLD)))
		alerts_box.add_child(b)


func _tabs() -> Array:
	var g := app.game
	var list := [
		{"id": "me", "icon": "person", "name": t("ui.tab.character")},
	]
	if g.engine.has_feature("lifestyles") and not g.content.all("lifestyles").is_empty():
		list.append({"id": "lifestyle", "icon": "leaf", "name": t("ui.tab.lifestyle")})
	list.append_array([
		{"id": "realm", "icon": "castle", "name": t("ui.tab.realm")},
		{"id": "military", "icon": "swords", "name": t("ui.tab.military")},
		{"id": "wars", "icon": "fire", "name": t("ui.tab.wars")},
		{"id": "intrigue", "icon": "dagger", "name": t("ui.tab.intrigue")},
		{"id": "decisions", "icon": "scroll", "name": t("ui.tab.decisions")},
		{"id": "log", "icon": "book", "name": t("ui.tab.log")},
	])
	var mods: Array = g.engine.ui.panels.values()
	Data.sort_by(mods, func(x): return Data.num(x.get("order")))
	for m in mods:
		list.append({"id": "mod:" + m.id, "icon": m.get("icon", "star"), "name": g.loc.resolve(m.get("name", m.id))})
	return list


func tab_name(id: String) -> String:
	for tb in _tabs():
		if tb.id == id:
			return tb.name
	return ""


func _refresh_cluster(p: Variant) -> void:
	var active := ""
	if app.panel_ref != null:
		active = app.panel_ref.kind + ":" + str(app.panel_ref.id)
	var sig := ""
	if p != null:
		sig = "%s|%s|%s|%s|%s" % [p.id, ",".join(p.titles), active, _tabs().size(), Chars.age_of(app.game, p)]
	if sig == _cluster_sig:
		return
	_cluster_sig = sig
	K.clear(tabs_box)
	if p == null:
		return
	# полоса разделов справа от медальона
	var strip := K.hbox([], 4)
	var strip_panel := K.panel(strip, "BarPanel")
	strip_panel.position = Vector2(118, 96)
	tabs_box.add_child(strip_panel)
	for tb in _tabs():
		var is_active := false
		if app.panel_ref != null:
			if tb.id == "me":
				is_active = app.panel_ref.kind == "character" and app.panel_ref.id == p.id
			else:
				is_active = app.panel_ref.kind == "tab" and app.panel_ref.id == tb.id
		var id: String = tb.id
		strip.add_child(K.round_button(tb.icon, func():
			if id == "me":
				app.open_character(app.game.player.id)
			else:
				app.open_tab(id), tb.name, 44, is_active))
	# медальон и герб
	var med := W.portrait(app, p, 140, {"round": true})
	med.position = Vector2(8, 10)
	tabs_box.add_child(med)
	if not p.titles.is_empty():
		var coa := W.coa(app, p.titles[0], 44)
		coa.position = Vector2(120, 4)
		tabs_box.add_child(coa)
	var name := K.label(Chars.full_name(app.game, p, true), "SubheaderLabel")
	name.position = Vector2(170, 64)
	name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name.add_theme_constant_override("outline_size", 5)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs_box.add_child(name)


func _refresh_date() -> void:
	var g := app.game
	var d := GameDate.parts(g.date)
	date_label.text = "%d %s %d" % [d.d, t("month_gen.%d" % d.m) if g.loc.has("month_gen.%d" % d.m) else t("month.%d" % d.m), d.y]
	var sig := "%s|%d" % [app.paused, app.speed]
	if sig == _date_sig:
		return
	_date_sig = sig
	pause_btn.icon = Icons.texture("play" if app.paused else "pause", 22)
	pause_btn.self_modulate = Color(1.0, 0.75, 0.6) if app.paused else Color.WHITE
	for i in speed_pips.size():
		var on: bool = i < app.speed
		var b: Button = speed_pips[i]
		var sb := UiArt.flat(Color("#e3b44a") if on else Color("#1b2226"), Color(UiArt.BRONZE), 1, 2)
		var sbh := UiArt.flat(Color("#f3cf70") if on else Color("#2e383e"), Color(UiArt.GOLD), 1, 2)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sbh)
		b.add_theme_stylebox_override("pressed", sbh)


func _refresh_modes() -> void:
	var g := app.game
	var specs: Array = g.engine.ui.map_modes.values()
	Data.sort_by(specs, func(m): return Data.num(m.get("order")))
	var sig := app.map_view.mode + str(specs.size())
	if sig == _modes_sig:
		return
	_modes_sig = sig
	K.clear(modes_box)
	for m in specs:
		var id: String = m.id
		var b := K.round_button(m.get("icon", "map"), func():
			app.map_view.set_mode(id)
			app.mark_dirty(true), g.loc.resolve(m.get("name", id)), 38, app.map_view.mode == id)
		modes_box.add_child(b)


func _refresh_outliner(p: Variant) -> void:
	var g := app.game
	var panel := outliner.get_parent() as Control
	if p == null:
		K.clear(outliner)
		_outliner_sig = ""
		panel.visible = false
		return
	var wars := Wars.wars_of(g, p.id)
	var armies := Military.armies_of(g, p.id)
	var schemes := []
	for s in g.state.schemes.values():
		if s.owner == p.id:
			schemes.append(s)
	var sig := "%s|%s|" % [g.loc.lang, app.map_view.selected_army]
	for w in wars:
		sig += "w%s:%d;" % [w.id, int(Wars.warscore(g, w).total)]
	for a in armies:
		sig += "a%s:%d:%s:%d;" % [a.id, int(a.size), a.location, a.path.size()]
	for s in schemes:
		sig += "s%s:%d;" % [s.id, int(s.progress)]
	if sig == _outliner_sig:
		return
	_outliner_sig = sig
	K.clear(outliner)
	panel.visible = not (wars.is_empty() and armies.is_empty() and schemes.is_empty())
	if not wars.is_empty():
		outliner.add_child(K.label(t("ui.tab.wars"), "SubheaderLabel"))
		for w in wars:
			var ws := Wars.warscore(g, w)
			var side: Variant = Wars.participant_side(w, p.id)
			var score := int(ws.total) if side == "att" else -int(ws.total)
			var row := K.button("%s  %s%%" % [w.get("name", ""), K.signed(score)], func(): app.open_tab("wars"), {"variation": "FlatButton", "icon": "fire", "align": HORIZONTAL_ALIGNMENT_LEFT})
			outliner.add_child(row)
	if not armies.is_empty():
		outliner.add_child(K.label(t("ui.armies"), "SubheaderLabel"))
		for a in armies:
			var aid: String = a.id
			var loc = a.location
			var txt := "%s — %s%s" % [K.fmt(a.size), g.name_of("provinces", a.location), " →" if not a.path.is_empty() else ""]
			var b := K.button(txt, func():
				app.select_army(aid)
				app.map_view.focus(loc), {"variation": "FlatButton", "icon": "swords", "align": HORIZONTAL_ALIGNMENT_LEFT, "toggled": app.map_view.selected_army == aid})
			outliner.add_child(b)
	if not schemes.is_empty():
		outliner.add_child(K.label(t("ui.tab.intrigue"), "SubheaderLabel"))
		for s in schemes:
			var def: Variant = g.content.get_def("schemes", s.type)
			outliner.add_child(K.button("%s: %d%%" % [g.name_of("schemes", s.type), int(s.progress)], func(): app.open_tab("intrigue"),
				{"variation": "FlatButton", "icon": def.get("icon", "dagger") if def != null else "dagger", "align": HORIZONTAL_ALIGNMENT_LEFT}))


func _refresh_messages() -> void:
	var g := app.game
	var all: Array = g.state.messages
	var last: Variant = all[all.size() - 1] if not all.is_empty() else null
	var sig := "%s|%d|%s" % [g.loc.lang, all.size(), str(last.date) + str(last.text) if last != null else ""]
	if sig == _messages_sig:
		return
	_messages_sig = sig
	var fresh := all.size() - _seen_messages
	_seen_messages = all.size()
	K.clear(messages)
	var panel := messages.get_parent() as Control
	var n := mini(6, all.size())
	panel.visible = n > 0
	for i in n:
		var m: Dictionary = all[all.size() - 1 - i]
		var d := GameDate.parts(m.date)
		var color := BB.MUTED
		match m.get("kind"):
			"good": color = BB.GOOD
			"bad": color = BB.BAD
			"war": color = BB.WARN
		var text := "[color=%s]%d.%d.%d[/color]  %s" % [BB.MUTED, d.d, d.m, d.y, BB.c(m.text, "#e9dfc6" if i >= fresh else "#fff3cf")]
		var r := K.rich(text)
		r.custom_minimum_size.x = 280
		r.add_theme_font_size_override("normal_font_size", 13)
		var ref: Variant = m.get("ref")
		if ref is Dictionary:
			K.on_click(r, func(): app.open_ref(ref))
		var row := K.hbox([ColorRect.new(), r], 6)
		var bar: ColorRect = row.get_child(0)
		bar.color = Color(color)
		bar.custom_minimum_size = Vector2(3, 0)
		messages.add_child(row)


func _refresh_window(full: bool = true) -> void:
	var ref: Variant = app.panel_ref
	if ref == null:
		window.visible = false
		_window_key = ""
		return
	window.visible = true
	var key: String = ref.kind + ":" + str(ref.id)
	if not full and key == _window_key and Time.get_ticks_msec() - _window_at < LIVE_WINDOW_MS:
		return
	_window_at = Time.get_ticks_msec()
	var scroll := window_body.scroll_vertical if key == _window_key else 0
	var built := Panels.build(app, ref)
	window_title.text = built.title
	window_back.visible = not app.history.is_empty()
	K.clear(window_body)
	var body: Control = built.body
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := K.margin(body, 4, 2, 10, 8)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	window_body.add_child(m)
	_window_key = key
	if scroll > 0:
		_restore_scroll.call_deferred(scroll)


func _restore_scroll(v: int) -> void:
	window_body.scroll_vertical = v

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
var _window_closing := false
var _window_at := 0
var _window_due := false
var _seen_messages := 0
var _res_sig := ""
var _date_sig := ""
var _outliner_sig := ""
var _messages_sig := ""
var _ol_scroll: ScrollContainer
var _msg_panel: Control
var _right: Control
var _modes_panel: Control

## Пока игра идёт, открытое окно обновляется не чаще (мс).
const LIVE_WINDOW_MS := 1000
## Ширина окна слева.
const WINDOW_W := 700


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
	pause_btn.set_meta("silent", true)
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
	# обзор прокручивается, если не помещается над режимами карты
	_ol_scroll = ScrollContainer.new()
	_ol_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ol_scroll.add_child(ol_panel)
	ol_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_ol_scroll)
	messages = K.vbox([], 2)
	_msg_panel = K.panel(messages, "DarkPanel")
	_msg_panel.name = "Messages"
	right.add_child(_msg_panel)
	add_child(right)
	_right = right
	_modes_panel = modes_panel
	get_viewport().size_changed.connect(func(): _fit_right.call_deferred())

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
	window.offset_right = 8 + WINDOW_W
	# как в CK3: окно во всю высоту, поверх медальона и полосы разделов
	window.offset_bottom = -10
	window.visible = false
	var head := K.hbox([], 6)
	window_back = K.button("", func(): app.back(), {"icon": "back", "variation": "CloseButton", "min_w": 34, "min_h": 34, "tip": t("ui.back")})
	window_title = K.label("", "HeaderLabel")
	window_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var close := K.button("", func(): app.close_panel(), {"icon": "close", "variation": "CloseButton", "min_w": 34, "min_h": 34, "tip": t("ui.close")})
	head.add_child(window_back)
	# заголовок между завитками
	head.add_child(K.expand())
	head.add_child(K.flourish(false))
	head.add_child(window_title)
	head.add_child(K.flourish(true))
	head.add_child(K.expand())
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
	_fit_right.call_deferred()
	if full:
		_refresh_window(true)
	else:
		# Во время хода игры окно обновляется в отдельном кадре (live_window),
		# чтобы его сборка не складывалась с остальным HUD.
		_window_due = true


func window_due() -> bool:
	return _window_due


## Отложенное «живое» обновление окна (вызывается в кадре без перерисовки HUD).
func live_window() -> void:
	_window_due = false
	_refresh_window(false)


## Подсказка престижа или благочестия: уровень славы (механика renown).
func _renown_tip(p: Variant, kind: String) -> String:
	var bb := BB.title(t("ui." + kind))
	if p != null and app.game.engine.has_feature("renown"):
		bb += "\n" + BB.esc(Renown.describe(app.game, p, kind))
	return bb


func _refresh_resources(p: Variant) -> void:
	var g := app.game
	var items: Array = []
	if p != null:
		var income := Economy.monthly_income(g, p)
		items.append(["gold", K.fmt(p.gold), K.signed(income, 1), income >= 0, func():
			var pl: Variant = app.game.player
			return BB.title(t("ui.gold")) + ("\n" + BB.breakdown(Economy.income_breakdown(app.game, pl), 1) if pl != null else "")])
		var mp := Economy.monthly_prestige(g, p)
		items.append(["prestige", K.fmt(p.prestige), K.signed(mp, 1), mp >= 0, func(): return _renown_tip(app.game.player, "prestige")])
		var pi := Economy.monthly_piety(g, p)
		items.append(["piety", K.fmt(p.piety), K.signed(pi, 1), pi >= 0, func(): return _renown_tip(app.game.player, "piety")])
		items.append(["levies", K.fmt(Economy.realm_levy(g, p)), "", true, BB.title(t("ui.levies"))])
		if not p.titles.is_empty():
			var dom := Titles.domain_counties(g, p).size()
			var lim := Economy.domain_limit(g, p)
			items.append(["castle", "%d/%d" % [dom, lim], "", dom <= lim, BB.title(t("ui.domain")) + "\n" + BB.esc(t("ui.domain_tip"))])
		if float(p.stress) > 0:
			items.append(["stress", K.fmt(p.stress), "", float(p.stress) < 100, func(): return W.stress_tip(app, app.game.player) if app.game.player != null else ""])
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
	list.append({"id": "realm", "icon": "castle", "name": t("ui.tab.realm")})
	if g.engine.has_feature("dynasties") and g.player != null and g.player.dynasty != null:
		list.append({"id": "dynasty", "icon": "dynasty", "name": t("ui.tab.dynasty")})
	list.append_array([
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


func _tab_tip(tb: Dictionary) -> String:
	var key := "C" if tb.id == "me" else ""
	for k in App.TAB_KEYS:
		if App.TAB_KEYS[k] == tb.id:
			key = OS.get_keycode_string(k)
	return tb.name + (" " + BB.muted("(%s)" % key) if key != "" else "")


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
				app.open_tab(id), _tab_tip(tb), 44, is_active))
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


## Обзор справа (как outliner в CK3): сворачиваемые разделы — закреплённые
## персонажи, войны, армии, интриги, фракции против вас, недовольные
## вассалы, стройки.
func _refresh_outliner(p: Variant) -> void:
	var g := app.game
	var panel := outliner.get_parent() as Control
	if p == null:
		K.clear(outliner)
		_outliner_sig = ""
		panel.visible = false
		return
	var sections := _outliner_sections(p)
	var sig := "%s|%s|%s|" % [g.loc.lang, app.map_view.selected_army, str(app.outliner_collapsed)]
	for sec in sections:
		sig += sec.id + ":" + sec.sig + ";"
	if sig == _outliner_sig:
		return
	_outliner_sig = sig
	K.clear(outliner)
	panel.visible = not sections.is_empty()
	for sec in sections:
		var collapsed: bool = app.outliner_collapsed.get(sec.id, false)
		var sid: String = sec.id
		var head := K.button("%s  %d" % [sec.name, sec.rows.size()], func():
			app.outliner_collapsed[sid] = not app.outliner_collapsed.get(sid, false)
			app.mark_dirty(true), {"variation": "FlatButton", "icon": sec.icon, "align": HORIZONTAL_ALIGNMENT_LEFT})
		head.add_theme_color_override("font_color", UiArt.C_GOLD)
		head.add_child(_chevron(collapsed))
		outliner.add_child(head)
		if collapsed:
			continue
		for r in sec.rows:
			outliner.add_child(r)


func _chevron(collapsed: bool) -> Control:
	var l := K.label("▸" if collapsed else "▾", "SmallLabel")
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	l.offset_left = -18
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _outliner_sections(p: Dictionary) -> Array:
	var g := app.game
	var out := []
	var row := func(text: String, icon: Variant, cb: Callable, opts: Dictionary = {}) -> Control:
		var o := {"variation": "FlatButton", "icon": icon, "align": HORIZONTAL_ALIGNMENT_LEFT}
		o.merge(opts)
		var b := K.button(text, cb, o)
		b.clip_text = true
		b.custom_minimum_size.x = 280
		return b
	# закреплённые персонажи
	var pins: Array = Data.as_array(g.state.get("pinned")).filter(func(id): return g.ch(id) != null)
	if not pins.is_empty():
		var rows := []
		var sig := ""
		for id in pins:
			var c: Dictionary = g.ch(id)
			var cid: String = id
			var r: Control = row.call(Chars.full_name(g, c, true) + (" ✝" if c.death != null else ""), "person", func(): app.open_character(cid),
				{"tip": func(): return app.character_tooltip(cid)})
			rows.append(r)
			sig += id + str(c.death) + c.name
		out.append({"id": "pins", "name": t("ui.ol.pinned"), "icon": "star", "rows": rows, "sig": sig})
	# войны
	var wars := Wars.wars_of(g, p.id)
	if not wars.is_empty():
		var rows := []
		var sig := ""
		for w in wars:
			var ws := Wars.warscore(g, w)
			var side: Variant = Wars.participant_side(w, p.id)
			var score := int(ws.total) if side == "att" else -int(ws.total)
			rows.append(row.call("%s  %s%%" % [w.get("name", ""), K.signed(score)], "fire", func(): app.open_tab("wars")))
			sig += "%s:%d," % [w.id, score]
		out.append({"id": "wars", "name": t("ui.tab.wars"), "icon": "fire", "rows": rows, "sig": sig})
	# армии
	var armies := Military.armies_of(g, p.id)
	if not armies.is_empty():
		var rows := []
		var sig := ""
		for a in armies:
			var aid: String = a.id
			var loc = a.location
			var txt := "%s — %s%s" % [K.fmt(a.size), g.name_of("provinces", a.location), " →" if not a.path.is_empty() else ""]
			rows.append(row.call(txt, "swords", func():
				app.select_army(aid)
				app.map_view.focus(loc), {"toggled": app.map_view.selected_army == aid}))
			sig += "%s:%d:%s:%d," % [a.id, int(a.size), a.location, a.path.size()]
		out.append({"id": "armies", "name": t("ui.armies"), "icon": "swords", "rows": rows, "sig": sig})
	# интриги
	var schemes: Array = g.state.schemes.values().filter(func(s): return s.owner == p.id)
	if not schemes.is_empty():
		var rows := []
		var sig := ""
		for s in schemes:
			var def: Variant = g.content.get_def("schemes", s.type)
			var target: Variant = g.ch(s.target)
			rows.append(row.call("%s → %s: %d%%" % [g.name_of("schemes", s.type), target.name if target != null else "?", int(s.progress)],
				def.get("icon", "dagger") if def != null else "dagger", func(): app.open_tab("intrigue")))
			sig += "%s:%d," % [s.id, int(s.progress)]
		out.append({"id": "schemes", "name": t("ui.tab.intrigue"), "icon": "dagger", "rows": rows, "sig": sig})
	# фракции против вас
	if g.engine.has_feature("factions"):
		var facs: Array = g.state.factions.values().filter(func(f): return f.get("target") == p.id)
		if not facs.is_empty():
			var rows := []
			var sig := ""
			for f in facs:
				var disc := int(Data.num(f.get("discontent")))
				rows.append(row.call("%s: %d%%" % [g.name_of("factions", f.type), disc], "fist", func():
					app.subtabs["realm"] = "politics"
					app.open_tab("realm"), {}))
				sig += "%s:%d," % [f.id, disc]
			out.append({"id": "factions", "name": t("ui.ol.factions"), "icon": "fist", "rows": rows, "sig": sig})
	# недовольные вассалы
	var unhappy := []
	for v in g.vassals_of(p.id):
		var op := Opinion.opinion(g, v, p)
		if op < 0:
			unhappy.append([op, v])
	if not unhappy.is_empty():
		unhappy.sort_custom(func(a, b): return a[0] < b[0])
		var rows := []
		var sig := ""
		for item in unhappy.slice(0, 6):
			var v: Dictionary = item[1]
			var vid: String = v.id
			rows.append(row.call("%s  %s" % [Chars.full_name(g, v, true), K.signed(item[0])], "person", func(): app.open_character(vid),
				{"tip": func(): return app.character_tooltip(vid)}))
			sig += "%s:%d," % [v.id, item[0]]
		out.append({"id": "unhappy", "name": t("ui.ol.unhappy_vassals"), "icon": "warning", "rows": rows, "sig": sig})
	# желания: своё и двора (обиженные — первыми)
	if g.engine.has_feature("ambitions"):
		var amb_rows := []
		var amb_sig := ""
		var own: Variant = Ambitions.current(p)
		if own != null or not Ambitions.offers(p).is_empty():
			var od: Variant = Ambitions.def_of(g, own.id) if own != null else null
			var txt: String = Ambitions.describe_name(g, p, own) if own != null else t("ui.ambition_choose")
			var pr: Variant = Ambitions.progress_of(g, p) if own != null else null
			if pr != null:
				txt += "  %s/%s" % [K.fmt(minf(float(pr.done), float(pr.need))), K.fmt(float(pr.need))]
			var pid: String = p.id
			amb_rows.append(row.call(txt, od.get("icon", "star") if od != null else "star", func(): app.open_character(pid),
				{"variation": "FlatButton" if own != null else "GoldButton"}))
			amb_sig += "own:%s:%s," % [str(own.id) if own != null else "?", txt]
		var court := []
		for x in g.vassals_of(p.id) + g.courtiers_of(p.id):
			var xa: Variant = Ambitions.current(x)
			var xd: Variant = Ambitions.def_of(g, xa.id) if xa != null else null
			if xd != null and xd.get("credit") == "liege":
				court.append([-Ambitions.frustration(g, x), -Ambitions.years_of(g, x), x, xa, xd])
		court.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
		for item in court.slice(0, 6):
			var x: Dictionary = item[2]
			var xid: String = x.id
			var fr: float = -item[0]
			var txt := "%s — %s" % [Chars.char_name(g, x), g.loc.t_or("ambition_short." + str(item[3].id), str(item[3].id))]
			if fr > 0.0:
				txt += "  " + K.signed(-fr)
			var r: Control = row.call(txt, item[4].get("icon", "star"), func(): app.open_character(xid),
				{"tip": func(): return app.character_tooltip(xid)})
			if fr > 0.0:
				r.add_theme_color_override("font_color", Color("#e08070"))
			amb_rows.append(r)
			amb_sig += "%s:%s:%d," % [xid, item[3].id, int(fr)]
		if not amb_rows.is_empty():
			out.append({"id": "ambitions", "name": t("ui.ol.ambitions"), "icon": "star", "rows": amb_rows, "sig": amb_sig})
	# стройки в домене
	var builds := []
	for cid in Titles.domain_counties(g, p):
		var pr: Variant = g.state.provinces.get(cid)
		if pr != null and pr.construction != null:
			builds.append([cid, pr.construction])
	if not builds.is_empty():
		var rows := []
		var sig := ""
		for item in builds:
			var cid: String = item[0]
			var left := maxi(0, int(item[1].done) - g.date)
			rows.append(row.call("%s: %s (%s)" % [g.name_of("provinces", cid), g.name_of("buildings", item[1].building), t("ui.days_left", {"n": left})],
				"castle", func(): app.open_province(cid, true)))
			sig += "%s:%d," % [cid, left / 30]
		out.append({"id": "builds", "name": t("ui.ol.construction"), "icon": "castle", "rows": rows, "sig": sig})
	return out


## Обзор справа — не ниже режимов карты: высота по содержимому, а что не
## поместилось — прокручивается.
func _fit_right() -> void:
	if _ol_scroll == null or not is_inside_tree():
		return
	var inner := _ol_scroll.get_child(0) as Control
	var want := inner.get_combined_minimum_size().y if inner.visible else 0.0
	var bottom := _modes_panel.get_global_rect().position.y - 10.0 if _modes_panel.visible else get_viewport_rect().size.y - 180.0
	var msg_h := _msg_panel.get_combined_minimum_size().y + 8.0 if _msg_panel.visible else 0.0
	var avail := maxf(80.0, bottom - _right.get_global_rect().position.y - msg_h)
	var h := minf(want, avail)
	if not is_equal_approx(_ol_scroll.custom_minimum_size.y, h):
		_ol_scroll.custom_minimum_size.y = h
	_ol_scroll.visible = inner.visible


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
	var n := mini(5, all.size())
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
		r.add_theme_font_size_override("normal_font_size", 14)
		var ref: Variant = m.get("ref")
		if ref is Dictionary:
			K.on_click(r, func(): app.open_ref(ref))
		var row := K.hbox([ColorRect.new(), r], 6)
		var bar: ColorRect = row.get_child(0)
		bar.color = Color(color)
		bar.custom_minimum_size = Vector2(3, 0)
		messages.add_child(row)
		# свежие записи проявляются; война и битвы — с барабаном
		if i < fresh and fresh < 6:
			UiFx.fade_in(row, 0.0, 0.35)
			if m.get("kind") == "war":
				UiSound.play("war", 1.0, -4.0)


## Медальон и полоса разделов внизу слева прячутся под открытым окном и
## проявляются, когда окно закрыто.
func _show_cluster(on: bool) -> void:
	if on:
		cluster.visible = true
		UiFx.fade_in(cluster, 0.0, 0.18)
	else:
		cluster.visible = false


func _refresh_window(full: bool = true) -> void:
	var ref: Variant = app.panel_ref
	if ref == null:
		# окно уезжает влево и гаснет
		if window.visible and not _window_closing:
			_window_closing = true
			UiSound.follow("close")
			UiFx.slide_out(window, func():
				window.visible = false
				_window_closing = false
				_show_cluster(true))
		_window_key = ""
		return
	# вкладки окна — часть ключа: другая вкладка прокручивается с начала
	var key: String = ref.kind + ":" + str(ref.id) + "|" + str(app.subtabs)
	if not window.visible or _window_closing:
		_window_closing = false
		window.visible = true
		_show_cluster(false)
		UiSound.follow("open")
		UiFx.slide_in(window)
	elif key != _window_key and _window_key != "":
		# другое окно или вкладка — шелест страницы (если щелчок не прозвучал
		# только что) и мягкое проявление
		if UiSound.quiet_for(150):
			UiSound.play("tab")
		UiFx.fade_in(window_body, 0.2)
	if not full and key == _window_key and Time.get_ticks_msec() - _window_at < LIVE_WINDOW_MS:
		return
	_window_at = Time.get_ticks_msec()
	var built := Panels.build(app, ref)
	window_title.text = built.title
	window_back.visible = not app.history.is_empty()
	var body: Control = built.body
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := K.margin(body, 4, 2, 10, 8)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# То же окно: переносим новое содержимое в показанное, если структура
	# совпала (без вставки в сцену — нет рывка, прокрутка сохраняется).
	if key == _window_key and window_body.get_child_count() == 1 and Morph.apply(window_body.get_child(0), m):
		m.free()
		return
	var scroll := window_body.scroll_vertical if key == _window_key else 0
	K.clear(window_body)
	window_body.add_child(m)
	_window_key = key
	if scroll > 0:
		_restore_scroll.call_deferred(scroll)


func _restore_scroll(v: int) -> void:
	window_body.scroll_vertical = v

class_name App
extends Control
## Приложение: загрузка модов, главное меню, игровой цикл, окна и модальные
## окна. Состояние игры живёт в Game (движок); интерфейс только читает его
## и вызывает функции мира в ответ на действия игрока.

## Секунд реального времени на игровой день для скоростей 1–5
## (на пятой — так быстро, как успевает поток симуляции).
const SPEED_SEC := [INF, 0.7, 0.3, 0.12, 0.045, 0.004]

static var instance: App

var engine: GameEngine
var game: Game
var packages: Array = []
var enabled: Variant = null
var lang := "ru"
var speed := 2
var paused := true
var pick_mode := false
## Какой образ жизни открыт во вкладке «Образ жизни».
var lifestyle_view := ""
## Открытое окно: {kind: character|province|title|army|tab, id}.
var panel_ref: Variant = null
var history: Array = []
var ui_theme: Theme

var map_view: MapView
var screen_layer: Control
var hud: Hud
var window_layer: Control
var modal_layer: Control
var toast_box: VBoxContainer
var tooltip: TooltipLayer

## Поток симуляции: мир считается в фоне, интерфейс читает его в «окне доступа».
var sim := SimRunner.new()

var _modals: Array = []
var _shown_event: Variant = null
var _dirty := true
var _dirty_now := false
var _render_timer := 0.0
var _acc := 0.0
var _seen_days := 0
var _last_autosave := -1
var _seen_messages := 0


func _ready() -> void:
	instance = self
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_theme = GameTheme.build()
	theme = ui_theme
	get_tree().root.theme = ui_theme
	lang = str(Platform.setting("lang", _default_lang()))
	var en: Variant = Platform.setting("enabled_mods", null)
	if en is Array:
		enabled = en
	_apply_window_settings()
	get_tree().set_auto_accept_quit(false)

	map_view = MapView.new()
	map_view.visible = false
	add_child(map_view)
	screen_layer = _layer("Screen")
	window_layer = _layer("Windows")
	modal_layer = _layer("Modals")
	toast_box = VBoxContainer.new()
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	toast_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	toast_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast_box.offset_right = -24
	toast_box.offset_bottom = -150
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	add_child(toast_box)
	tooltip = TooltipLayer.new()
	tooltip.scope = func(): return _modals.back().node if not _modals.is_empty() else null
	add_child(tooltip)

	map_view.province_clicked.connect(func(id): locked(_on_province_clicked.bind(id)))
	map_view.province_right_clicked.connect(func(id): locked(_on_province_right_clicked.bind(id)))
	sim.snapshot_fn = MapOverlay.build_snapshot
	map_view.sim = sim
	map_view.army_clicked.connect(func(id): locked(select_army.bind(id)))
	map_view.tooltip_provider = province_tooltip
	map_view.overlay.army_tooltip = army_tooltip
	boot.call_deferred()


func _layer(name: String) -> Control:
	var c := Control.new()
	c.name = name
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _default_lang() -> String:
	return "ru" if OS.get_locale_language() == "ru" else "en"


func _apply_window_settings() -> void:
	var scale := float(Platform.setting("ui_scale", 1.0))
	get_tree().root.content_scale_factor = scale
	if Platform.setting("fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func t(key: String, params: Dictionary = {}) -> String:
	return engine.loc.t(key, params) if engine != null else key


# ------------------------------------------------------------ запуск

func boot() -> void:
	show_loading("…")
	await get_tree().process_frame
	await build_engine()
	show_main_menu()


func build_engine() -> void:
	var issues := []
	packages = Platform.load_mod_packages(issues)
	show_loading(tr_fallback("Загрузка модов…", "Loading mods…"))
	await get_tree().process_frame
	engine = GameEngine.create(packages, {
		"enabled": enabled, "lang": lang, "default_localization": Platform.default_localization(),
		"on_progress": func(m): pass,
	})
	engine.issues.append_array(issues)
	MapModes.register_builtin(engine)
	Alerts.register_builtin(engine)
	show_loading(t("ui.generating_world"))
	await get_tree().process_frame
	# Карта строится (или читается из кэша) заранее, чтобы меню открылось сразу.
	var _m := engine.map


func tr_fallback(ru: String, en: String) -> String:
	return ru if lang == "ru" else en


func set_enabled_mods(ids: Variant) -> void:
	enabled = ids
	Platform.set_setting("enabled_mods", ids)


func set_language(l: String) -> void:
	locked(_set_language.bind(l))


func _set_language(l: String) -> void:
	lang = l
	Platform.set_setting("lang", l)
	if engine != null:
		engine.loc.lang = l
	map_view.invalidate()
	mark_dirty(true)


# ------------------------------------------------------------ экраны

func _set_screen(c: Control) -> void:
	K.clear(screen_layer)
	K.clear(window_layer)
	screen_layer.add_child(c)


func show_loading(msg: String) -> void:
	var existing := screen_layer.get_node_or_null("Loading")
	if existing != null:
		existing.get_node("Box/Msg").text = msg
		return
	var bg := ColorRect.new()
	bg.name = "Loading"
	bg.color = Color("#120e0a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var crown := K.tex(Icons.texture("crown", 72), Vector2(72, 72))
	box.add_child(crown)
	var title := K.label(tr_fallback("Корона и Династия", "Crown and Dynasty"), "TitleLabel")
	title.add_theme_font_size_override("font_size", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var m := K.label(msg, "MutedLabel")
	m.name = "Msg"
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(m)
	bg.add_child(box)
	map_view.visible = false
	_set_screen(bg)


## Выполнить fn с доступом к миру (блокирующе): для действий игрока.
## Без запущенного потока — просто вызывает fn.
static func locked(fn: Callable, args: Array = []) -> Variant:
	var app := instance
	if app == null:
		return fn.callv(args)
	app.sim.enter()
	var r: Variant = fn.callv(args)
	app.sim.leave()
	return r


func show_main_menu() -> void:
	sim.stop()
	game = null
	paused = true
	_close_all_modals()
	hud = null
	panel_ref = null
	history = []
	# Фон меню — карта мира в «бумажном» виде, медленно плывущая.
	var preview := engine.new_game(engine.bookmarks()[0].id, 1) if not engine.bookmarks().is_empty() else null
	if preview != null:
		map_view.set_game(preview)
		map_view.interactive = false
		map_view.paper_bias = 0.6
		map_view.visible = true
		map_view.fit.call_deferred()
		map_view.drift = Vector2(9, 4)
		map_view.selected_province = null
		map_view.selected_army = null
	_set_screen(MainMenu.build(self))


func start_new_game(bookmark: String, player_id: Variant = null) -> void:
	sim.stop()
	show_loading(t("ui.generating_world"))
	await get_tree().process_frame
	var g := engine.new_game(bookmark)
	enter_game(g)
	if player_id != null:
		set_player(player_id)
	else:
		pick_mode = true
		open_tab("pick")


func set_player(id: String) -> void:
	var g := game
	g.state.player = id
	g.state.player_dynasty = g.ch(id).dynasty
	pick_mode = false
	map_view.overlay.highlighted = {}
	g.emit("player.selected", {"character": id})
	g.on_action("on_player_start", {"type": "character", "id": id})
	var cap: Variant = g.ch(id).capital
	if cap != null:
		map_view.focus(cap, maxf(map_view.zoom, 1.6))
	history = []
	panel_ref = null
	open_character(id)
	map_view.invalidate()
	mark_dirty(true)


func enter_game(g: Game) -> void:
	sim.stop()
	game = g
	paused = true
	panel_ref = null
	history = []
	_shown_event = null
	_close_all_modals()
	_seen_messages = g.state.messages.size()
	_last_autosave = -1
	map_view.drift = Vector2.ZERO
	map_view.paper_bias = 0.0
	map_view.interactive = true
	map_view.visible = true
	map_view.selected_army = null
	map_view.selected_province = null
	map_view.set_game(g)
	map_view.fit()
	hud = Hud.new()
	hud.app = self
	_set_screen(hud)
	hud.build()
	# Сигнал приходит из потока симуляции — обрабатываем в главном потоке.
	g.changed.connect(func(kind):
		if kind == "event":
			mark_dirty(true), CONNECT_DEFERRED)
	sim.set_snapshot(MapOverlay.build_snapshot(g))
	sim.start(g)
	mark_dirty(true)


# ------------------------------------------------------------ цикл

func mark_dirty(now: bool = false) -> void:
	_dirty = true
	if now:
		_dirty_now = true


func _process(delta: float) -> void:
	sim.begin_frame()
	var g := game
	if g == null or hud == null:
		return
	# Время идёт: поток симуляции получает «бюджет» дней по скорости игры.
	var running := not paused and not pick_mode and _modals.is_empty()
	sim.allowed = running
	if running:
		_acc += delta
		var step: float = SPEED_SEC[speed]
		var n := floori(_acc / step)
		_acc -= n * step
		if n > 0:
			sim.add_days(n, 2 if speed < 4 else 12)
	else:
		_acc = 0.0
		sim.clear_days()
	if sim.days_done != _seen_days:
		_seen_days = sim.days_done
		_dirty = true
	_render_timer -= delta
	if _dirty and (_dirty_now or _render_timer <= 0.0):
		# Окно доступа к миру: если поток сейчас считает день, ждём следующего кадра.
		if sim.try_enter():
			# Полная перерисовка — после действий игрока и на паузе;
			# во время хода игры — только изменившееся.
			var full := _dirty_now or paused or not running
			_dirty = false
			_dirty_now = false
			_render_timer = 0.03 if paused else 0.25
			sim.set_snapshot(MapOverlay.build_snapshot(g))
			render(full)
			_autosave()
			sim.leave()


## Автосохранение: при переходе через 1 января (или 1 июля).
func _autosave() -> void:
	var g := game
	var mode := str(Platform.setting("autosave", "yearly"))
	var p := GameDate.parts(g.date)
	var key: int = p.y * 12 + (p.m - 1 if mode != "half_year" else (6 if p.m >= 7 else 0))
	if mode != "half_year":
		key = p.y * 12
	if _last_autosave < 0:
		_last_autosave = key
		return
	if key <= _last_autosave:
		return
	_last_autosave = key
	if mode == "off" or g.state.player == null:
		return
	SaveScreens.write_save(self, "autosave", SaveGame.serialize(g))


func toggle_pause() -> void:
	paused = not paused
	mark_dirty(true)


func set_speed(s: int) -> void:
	speed = clampi(s, 1, 5)
	mark_dirty(true)


func _unhandled_key_input(event: InputEvent) -> void:
	locked(_handle_key.bind(event))


func _handle_key(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_F11:
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		Platform.set_setting("fullscreen", not fs)
		get_viewport().set_input_as_handled()
		return
	if game == null or hud == null:
		if k.keycode == KEY_ESCAPE and not _modals.is_empty():
			close_modal()
		return
	match k.keycode:
		KEY_SPACE:
			toggle_pause()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			set_speed(k.keycode - KEY_0)
		KEY_EQUAL, KEY_KP_ADD:
			set_speed(speed + 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			set_speed(speed - 1)
		KEY_ESCAPE:
			if not _modals.is_empty():
				if _modals.back().closable:
					close_modal()
			elif panel_ref != null:
				close_panel()
			else:
				GameMenu.open(self)
		KEY_F5:
			quick_save()
		KEY_C:
			if game.player != null:
				open_character(game.player.id)
		_:
			return
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if game != null and locked(func(): return game.state.player != null):
			SettingsScreen.open_quit_dialog(self)
		else:
			quit_game()
	elif what == NOTIFICATION_PREDELETE:
		sim.stop()


func quit_game() -> void:
	sim.stop()
	get_tree().quit()


func quick_save() -> void:
	if game == null or game.state.player == null:
		return
	var err := SaveScreens.write_save(self, "quicksave", SaveGame.serialize(game))
	if err == OK:
		toast(t("ui.saved"), "good")
	else:
		toast("%s: %s" % [t("ui.save_failed"), error_string(err)], "bad")


# ------------------------------------------------------------ окна

func _push_history() -> void:
	if panel_ref != null:
		history.append(panel_ref)
		if history.size() > 30:
			history.pop_front()


func open_panel(p: Dictionary) -> void:
	if panel_ref != null and panel_ref.kind == p.kind and panel_ref.id == p.id:
		mark_dirty(true)
		return
	_push_history()
	panel_ref = p
	if p.kind == "province":
		map_view.selected_province = p.id
	mark_dirty(true)


func open_character(id: String) -> void:
	open_panel({"kind": "character", "id": id})


func open_province(id: String, focus: bool = false) -> void:
	if focus:
		map_view.focus(id)
	open_panel({"kind": "province", "id": id})


func open_title(id: String) -> void:
	open_panel({"kind": "title", "id": id})


## Открыть окно по ссылке на скоуп {type, id} (из сообщений и событий).
func open_ref(ref: Variant) -> void:
	if not (ref is Dictionary):
		return
	match ref.get("type"):
		"character":
			open_character(ref.id)
		"province":
			open_province(ref.id, true)
		"title":
			open_title(ref.id)
		"war":
			open_tab("wars")


func open_tab(id: String) -> void:
	if panel_ref != null and panel_ref.kind == "tab" and panel_ref.id == id and id != "pick":
		close_panel()
		return
	open_panel({"kind": "tab", "id": id})


func close_panel() -> void:
	panel_ref = null
	history = []
	map_view.selected_province = null
	mark_dirty(true)


func back() -> void:
	panel_ref = history.pop_back() if not history.is_empty() else null
	map_view.selected_province = panel_ref.id if panel_ref != null and panel_ref.kind == "province" else null
	mark_dirty(true)


func select_army(id: String) -> void:
	map_view.selected_army = id
	open_panel({"kind": "army", "id": id})


func selected_army() -> Variant:
	var id: Variant = map_view.selected_army
	if game == null or id == null or not game.state.armies.has(id):
		return null
	return id


func _on_province_clicked(id: String) -> void:
	if game == null:
		return
	map_view.selected_army = null
	if pick_mode:
		var t: Variant = game.title(id)
		var h: Variant = game.ch(t.holder) if t != null else null
		if h != null:
			open_character(Titles.top_liege(game, h).id)
		return
	open_province(id)


func _on_province_right_clicked(id: String) -> void:
	var aid: Variant = selected_army()
	if aid == null:
		return
	var a: Dictionary = game.state.armies[aid]
	if not game.is_player(a.owner):
		return
	if not Military.move_army(game, aid, id):
		toast(t("ui.no_path"), "bad")
	mark_dirty(true)


# ------------------------------------------------------------ подсказки

func province_tooltip(id: String) -> String:
	var g := game
	if g == null:
		return ""
	var def: Variant = g.prov_def(id)
	if def == null:
		return ""
	if def.get("impassable", false):
		return BB.title(g.name_of("provinces", id)) + "\n" + BB.muted(t("ui.impassable"))
	var parts := PackedStringArray([BB.title(Titles.full_name(g, id))])
	var tt: Variant = g.title(id)
	var holder: Variant = g.ch(tt.holder) if tt != null else null
	if holder != null:
		parts.append(BB.esc(Chars.full_name(g, holder, true)))
		var top := Titles.top_liege(g, holder)
		if top.id != holder.id and not top.titles.is_empty():
			parts.append(BB.muted(t("ui.realm_of", {"name": Titles.full_name(g, top.titles[0])})))
	var ctrl: Variant = Titles.province_controller(g, id)
	if ctrl != null and holder != null and ctrl.id != holder.id:
		parts.append(BB.bad(t("ui.occupied_by", {"who": Chars.full_name(g, ctrl, true)})))
	var st: Variant = g.prov(id)
	if st != null:
		var info := PackedStringArray()
		if st.culture != null:
			info.append(g.name_of("cultures", st.culture))
		if st.faith != null:
			info.append(g.name_of("faiths", st.faith))
		if def.get("terrain") != null:
			info.append(g.name_of("terrain", def.terrain))
		parts.append(BB.muted(" · ".join(info)))
	var reg := g.engine.ui.map_modes
	if reg.has(map_view.mode):
		var spec: Dictionary = reg.get_item(map_view.mode)
		if spec.get("tooltip") is Callable:
			var extra: Variant = spec.tooltip.call(g, id)
			if extra != null and str(extra) != "":
				parts.append(BB.gold(str(extra)))
	if pick_mode:
		parts.append(BB.small(BB.muted(t("ui.pick_click_hint"))))
	elif selected_army() != null and game.is_player(game.state.armies[selected_army()].owner):
		parts.append(BB.small(BB.muted(t("ui.move_army_hint"))))
	return "\n".join(parts)


func character_tooltip(id: Variant) -> String:
	var g := game
	var c: Variant = g.ch(id) if g != null else null
	if c == null:
		return ""
	var parts := PackedStringArray([BB.title(Chars.full_name(g, c, true))])
	if not c.titles.is_empty():
		parts.append(BB.esc(Titles.full_name(g, c.titles[0])))
	parts.append(BB.muted(t("ui.age_n", {"n": Chars.age_of(g, c)}) + (" ✝" if c.death != null else "")))
	var p: Variant = g.player
	if p != null and p.id != c.id and c.death == null:
		parts.append("%s: %s" % [t("ui.opinion_of_you"), BB.signed(Opinion.opinion(g, c, p))])
	return "\n".join(parts)


func army_tooltip(id: Variant) -> String:
	var g := game
	if g == null or not g.state.armies.has(id):
		return ""
	var a: Dictionary = g.state.armies[id]
	var parts := PackedStringArray([BB.title(t("ui.army") + ": " + K.fmt(a.size))])
	parts.append(BB.esc(Chars.full_name(g, g.ch(a.owner), true)))
	var cmd: Variant = Military.commander_of(g, a)
	if cmd != null:
		parts.append(BB.muted(t("ui.commander") + ": " + Chars.full_name(g, cmd, false)))
	parts.append(BB.muted(g.name_of("provinces", a.location)))
	return "\n".join(parts)


# ------------------------------------------------------------ модальные окна

## Модальное окно поверх всего. Возвращает функцию закрытия.
## opts: closable (клик мимо и Esc закрывают), dim (затемнение), on_close.
func modal(content: Control, opts: Dictionary = {}) -> Callable:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, float(opts.get("dim", 0.45)))
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	center.add_child(content)
	modal_layer.add_child(root)
	var entry := {"node": root, "closable": opts.get("closable", true), "on_close": opts.get("on_close", Callable())}
	_modals.append(entry)
	if entry.closable:
		dim.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_close_entry(entry))
	tooltip.block()
	return func(): _close_entry(entry)


func _close_entry(entry: Dictionary) -> void:
	if not _modals.has(entry):
		return
	_modals.erase(entry)
	entry.node.queue_free()
	if entry.on_close is Callable and entry.on_close.is_valid():
		entry.on_close.call()
	mark_dirty(true)


func close_modal() -> void:
	if not _modals.is_empty():
		_close_entry(_modals.back())


func _close_all_modals() -> void:
	for e in _modals.duplicate():
		e.node.queue_free()
	_modals.clear()
	if modal_layer != null:
		K.clear(modal_layer)


func has_modal() -> bool:
	return not _modals.is_empty()


## Короткое уведомление в правом нижнем углу. kind: info | good | bad.
func toast(text: String, kind: String = "info") -> void:
	var p := K.panel(null, "DarkPanel")
	var color: Color = {"good": UiArt.C_GOOD, "bad": UiArt.C_BAD}.get(kind, UiArt.C_TEXT)
	var l := K.label(text)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 320
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(p)
	var tw := p.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.7)
	tw.tween_callback(p.queue_free)


# ------------------------------------------------------------ отрисовка

func render(full: bool = true) -> void:
	if game == null or hud == null:
		return
	hud.refresh(full)
	_render_pending()


func _render_pending() -> void:
	var g := game
	if g.state.game_over != null and _modals.is_empty():
		var body := K.vbox([
			K.header(t("ui.game_over")),
			K.para(t("ui.game_over_" + str(g.state.game_over.reason))),
			K.center(K.button(t("ui.main_menu"), show_main_menu, {"variation": "GoldButton", "min_w": 220})),
		], 12)
		modal(K.panel(K.min_size(body, 420)), {"closable": false})
		return
	if not _modals.is_empty():
		return
	if not g.state.pending_events.is_empty():
		var ev: Dictionary = g.state.pending_events[0]
		if _shown_event != ev.uid:
			_shown_event = ev.uid
			var close_ref := [Callable()]
			var close := modal(EventWindow.build(self, ev, func():
				close_ref[0].call()
				_shown_event = null), {"closable": false, "dim": 0.35})
			close_ref[0] = close
		return
	if not g.state.pending_requests.is_empty():
		var rq: Dictionary = g.state.pending_requests[0]
		var close_ref := [Callable()]
		close_ref[0] = modal(EventWindow.build_request(self, rq, func(): close_ref[0].call()), {"closable": false, "dim": 0.35})


## Короткий ранг + имя для списков.
func ranked_name(id: Variant) -> String:
	var c: Variant = game.ch(id)
	if c == null:
		return "?"
	if c.titles.is_empty():
		return Chars.full_name(game, c, false)
	return "%s %s" % [Titles.rank_name(game, c), Chars.full_name(game, c, false)]


func context(root_id: String) -> ScriptContext:
	return ScriptContext.make(game, {"type": "character", "id": root_id})

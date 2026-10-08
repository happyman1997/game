class_name SaveScreens
extends RefCounted
## Сохранения: запись, окно сохранения, список для загрузки.
## Файлы лежат в «Документы/Crown and Dynasty/save games».


static func write_save(app: App, slot: String, json: String, name: Variant = null) -> Error:
	var g := app.game
	var p: Variant = g.player
	var d := GameDate.parts(g.date)
	var label: String = name if name != null else (app.t("ui.autosave") if slot == "autosave" else (app.t("ui.quicksave") if slot == "quicksave" else slot))
	var meta := {
		"slot": slot, "name": label, "date": "%d.%d.%d" % [d.d, d.m, d.y],
		"player": Chars.full_name(g, p, true) if p != null else "",
		"saved_at": Time.get_datetime_string_from_system(false, true),
	}
	return Platform.write_save(meta, json)


static func show_message(app: App, text: String) -> void:
	if app.game != null and app.hud != null:
		app.toast(text, "bad")
		return
	var close_ref := [Callable()]
	var body := K.vbox([K.para(text), K.center(K.button(app.t("ui.close"), func(): close_ref[0].call(), {"min_w": 140}))], 12)
	body.custom_minimum_size.x = 420
	close_ref[0] = app.modal(K.panel(body))


static func load_json(app: App, json: String) -> void:
	app.show_loading(app.t("ui.loading_save"))
	await app.get_tree().process_frame
	var res: Dictionary = app.engine.load_game(json)
	if res.get("game") == null:
		app.show_main_menu()
		show_message(app, "%s: %s" % [app.t("ui.load_failed"), res.get("error", "?")])
		return
	app.enter_game(res.game)
	var pid: Variant = res.game.state.player
	if pid != null:
		app.open_character(pid)
		var cap: Variant = res.game.ch(pid).capital
		if cap != null:
			app.map_view.focus.call_deferred(cap, 1.6)
	for w in res.get("warnings", []):
		app.toast(str(w), "bad")


static func load_slot(app: App, slot: String) -> void:
	var json: Variant = Platform.read_save(slot)
	if json == null:
		show_message(app, app.t("ui.load_failed"))
		return
	load_json(app, json)


static func open_save_dialog(app: App) -> void:
	var input := LineEdit.new()
	var d := GameDate.parts(app.game.date)
	input.text = "%s_%d" % [Chars.char_name(app.game, app.game.player).to_lower().replace(" ", "_") if app.game.player != null else "save", d.y]
	input.custom_minimum_size = Vector2(360, 36)
	var close_ref := [Callable()]
	var do_save := func(_t = null):
		var slot := input.text.strip_edges()
		if slot == "":
			slot = "save"
		close_ref[0].call()
		var err := write_save(app, slot, SaveGame.serialize(app.game), slot)
		if err == OK:
			app.toast(app.t("ui.saved"), "good")
		else:
			app.toast("%s: %s" % [app.t("ui.save_failed"), error_string(err)], "bad")
	input.text_submitted.connect(func(t): App.locked(do_save, [t]))
	var existing := K.vbox([], 2)
	for s in Platform.list_saves().slice(0, 8):
		var slot: String = s.slot
		existing.add_child(K.button("%s  ·  %s" % [s.name, s.get("date", "")], func(): input.text = slot, {"variation": "FlatButton", "align": HORIZONTAL_ALIGNMENT_LEFT}))
	var body := K.vbox([
		K.header(app.t("ui.save_game")),
		input,
		K.label(app.t("ui.existing_saves"), "SmallLabel") if existing.get_child_count() > 0 else null,
		existing,
		K.hbox([K.expand(), K.button(app.t("ui.save"), do_save, {"variation": "GoldButton", "min_w": 150}), K.button(app.t("ui.cancel"), func(): close_ref[0].call(), {"min_w": 120})], 10),
	], 10)
	body.custom_minimum_size.x = 460
	close_ref[0] = app.modal(K.panel(body))
	input.grab_focus.call_deferred()
	input.select_all.call_deferred()


static func open_load_dialog(app: App) -> void:
	var body := K.vbox([], 10)
	body.custom_minimum_size = Vector2(620, 0)
	var close_ref := [Callable()]
	var render_ref := [Callable()]
	var render := func() -> void:
		K.clear(body)
		body.add_child(K.header(app.t("ui.load_game")))
		var list := K.vbox([], 4)
		var saves := Platform.list_saves()
		if saves.is_empty():
			list.add_child(K.label(app.t("ui.no_saves"), "MutedLabel"))
		for s in saves:
			var slot: String = s.slot
			var info := K.vbox([K.label(s.name, "SubheaderLabel"), K.label(" · ".join([s.get("player", ""), s.get("date", ""), s.get("saved_at", "")].filter(func(x): return x != "")), "SmallLabel")], 0)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list.add_child(K.panel(K.hbox([
				info,
				K.button(app.t("ui.load"), func():
					close_ref[0].call()
					load_slot(app, slot), {"variation": "GoldButton", "min_w": 110}),
				K.button("", func():
					Platform.delete_save(slot)
					render_ref[0].call(), {"icon": "close", "tip": app.t("ui.delete_save"), "min_w": 36}),
			], 8), "RowPanel"))
		var sc := K.scroll(list)
		sc.custom_minimum_size.y = 380
		body.add_child(sc)
		body.add_child(K.hbox([
			K.button(app.t("ui.open_saves_folder"), func(): Platform.open_folder("saves"), {"tip": Platform.folder("saves")}),
			K.expand(),
			K.button(app.t("ui.cancel"), func(): close_ref[0].call(), {"min_w": 120}),
		], 10))
	render_ref[0] = render
	render.call()
	close_ref[0] = app.modal(K.panel(body))

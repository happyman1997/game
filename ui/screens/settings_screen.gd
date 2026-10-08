class_name SettingsScreen
extends RefCounted
## Настройки (язык, автосохранение, полный экран, масштаб интерфейса,
## папки) и выход из игры.

const SCALES := [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]


static func _row(label: String, control: Control, hint: String = "") -> Control:
	var l := K.vbox([K.label(label)], 0)
	if hint != "":
		l.add_child(K.label(hint, "SmallLabel"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 220)
	return K.hbox([l, control], 12)


static func _select(options: Array, value: Variant, on_change: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for i in options.size():
		o.add_item(str(options[i][1]), i)
		if str(options[i][0]) == str(value):
			o.select(i)
	o.item_selected.connect(func(i): on_change.call(options[i][0]))
	return o


static func open(app: App, on_close: Callable = Callable()) -> void:
	var close_ref := [Callable()]
	var body := K.vbox([K.header(app.t("ui.settings"))], 12)
	body.custom_minimum_size.x = 560
	body.add_child(_row(app.t("ui.setting_language"), _select([["ru", "Русский"], ["en", "English"]], app.lang, func(v):
		app.set_language(v)
		close_ref[0].call()
		if app.game == null:
			app.show_main_menu()
		open(app, on_close))))
	body.add_child(_row(app.t("ui.setting_autosave"), _select([
		["yearly", app.t("ui.autosave_yearly")], ["half_year", app.t("ui.autosave_half_year")], ["off", app.t("ui.autosave_off")],
	], Platform.setting("autosave", "yearly"), func(v): Platform.set_setting("autosave", v))))
	var fs := CheckBox.new()
	fs.focus_mode = Control.FOCUS_NONE
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(func(on):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
		Platform.set_setting("fullscreen", on))
	body.add_child(_row(app.t("ui.setting_fullscreen"), fs, "F11"))
	var cur := float(Platform.setting("ui_scale", 1.0))
	var opts := []
	for z in SCALES:
		opts.append([z, "%d%%" % roundi(z * 100)])
	body.add_child(_row(app.t("ui.setting_zoom"), _select(opts, cur, func(v):
		Platform.set_setting("ui_scale", v)
		app.get_tree().root.content_scale_factor = float(v))))
	var vsync := CheckBox.new()
	vsync.focus_mode = Control.FOCUS_NONE
	vsync.button_pressed = Platform.setting("vsync", true)
	vsync.toggled.connect(func(on):
		Platform.set_setting("vsync", on)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED))
	body.add_child(_row(app.t("ui.setting_vsync"), vsync))
	body.add_child(K.sep())
	body.add_child(K.flow([
		K.button(app.t("ui.open_saves_folder"), func(): Platform.open_folder("saves"), {"tip": Platform.folder("saves")}),
		K.button(app.t("ui.open_mods_folder"), func(): Platform.open_folder("mods"), {"tip": Platform.folder("mods")}),
	], 8))
	body.add_child(K.label("%s v%s" % [app.t("ui.game_title"), ProjectSettings.get_setting("application/config/version", "")], "SmallLabel"))
	body.add_child(K.hbox([K.expand(), K.button(app.t("ui.close"), func(): close_ref[0].call(), {"variation": "GoldButton", "min_w": 160}), K.expand()]))
	close_ref[0] = app.modal(K.panel(body), {"on_close": on_close})


## Выход из игры. Посреди партии предлагает сохраниться.
static func open_quit_dialog(app: App) -> void:
	if app.game == null or app.game.state.player == null:
		app.quit_game()
		return
	var close_ref := [Callable()]
	var body := K.vbox([
		K.header(app.t("ui.quit_game")),
		K.para(app.t("ui.quit_confirm")),
		K.hbox([
			K.button(app.t("ui.save_and_quit"), func():
				close_ref[0].call()
				var err := SaveScreens.write_save(app, "autosave", SaveGame.serialize(app.game))
				if err == OK:
					app.quit_game()
				else:
					app.toast("%s: %s" % [app.t("ui.save_failed"), error_string(err)], "bad"), {"variation": "GoldButton"}),
			K.button(app.t("ui.quit_without_saving"), func(): app.quit_game()),
			K.button(app.t("ui.cancel"), func(): close_ref[0].call()),
		], 8),
	], 12)
	body.custom_minimum_size.x = 480
	close_ref[0] = app.modal(K.panel(body))

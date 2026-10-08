class_name GameMenu
extends RefCounted
## Меню паузы (Esc): продолжить, сохранить, загрузить, настройки, выход.


static func open(app: App) -> void:
	var g := app.game
	var was_paused := app.paused
	app.paused = true
	var close_ref := [Callable()]
	var big := func(text: String, cb: Callable, opts: Dictionary = {}) -> Button:
		opts["min_h"] = 44
		opts["min_w"] = 300
		var b := K.button(text, func():
			close_ref[0].call()
			cb.call(), opts)
		b.add_theme_font_override("font", Fonts.heading(700))
		b.add_theme_font_size_override("font_size", 20)
		return b
	var head := K.label(app.t("ui.menu"), "TitleLabel")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var body := K.vbox([
		head,
		big.call(app.t("ui.resume"), func(): app.paused = was_paused, {"variation": "GoldButton"}),
		big.call(app.t("ui.save_game"), func(): SaveScreens.open_save_dialog(app), {"disabled": g.state.player == null}),
		big.call(app.t("ui.load_game"), func(): SaveScreens.open_load_dialog(app)),
		big.call(app.t("ui.settings"), func(): SettingsScreen.open(app)),
		big.call(app.t("ui.mod_issues"), func(): ModsScreen.open_issues(app)),
		big.call(app.t("ui.main_menu"), func(): app.show_main_menu()),
		big.call(app.t("ui.quit_game"), func(): SettingsScreen.open_quit_dialog(app)),
	], 8)
	close_ref[0] = app.modal(K.panel(K.margin(body, 14, 8, 14, 8)))

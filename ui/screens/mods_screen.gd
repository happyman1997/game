class_name ModsScreen
extends RefCounted
## Менеджер модов (включение, зависимости, проблемы) и список проблем.


static func open_manager(app: App) -> void:
	var all := app.packages
	var enabled := {}
	if app.enabled is Array:
		for id in app.enabled:
			enabled[id] = true
	else:
		for p in all:
			if p.manifest.get("default_enabled", true) != false:
				enabled[p.id] = true
	var body := K.vbox([], 10)
	body.custom_minimum_size = Vector2(720, 0)
	var close_ref := [Callable()]
	var render_ref := [Callable()]
	var render := func() -> void:
		K.clear(body)
		body.add_child(K.header(app.t("ui.mods")))
		body.add_child(K.para(app.t("ui.mods_hint"), "MutedLabel"))
		var list := K.vbox([], 4)
		for p in app.packages:
			var m: Dictionary = p.manifest
			var id: String = p.id
			var deps := Data.as_array(m.get("dependencies")).filter(func(d): return not enabled.has(d))
			var errs := 0
			var warns := 0
			for i in app.engine.issues:
				if i.get("mod") == id:
					if i.get("level") == "error":
						errs += 1
					else:
						warns += 1
			var cb := CheckBox.new()
			cb.focus_mode = Control.FOCUS_NONE
			cb.button_pressed = enabled.has(id)
			cb.disabled = id == "core"
			cb.toggled.connect(func(on):
				if on:
					enabled[id] = true
				else:
					enabled.erase(id)
				render_ref[0].call())
			var info := K.vbox([
				K.rich("%s  %s" % [BB.b(p.display_name(app.lang)), BB.muted("%s · v%s · %s" % [id, m.get("version", "?"), p.origin])], false),
				K.para(p.description(app.lang), "MutedLabel"),
			], 2)
			if not Data.as_array(m.get("dependencies")).is_empty():
				info.add_child(K.label("%s: %s" % [app.t("ui.depends_on"), ", ".join(Data.as_array(m.dependencies))], "BadLabel" if not deps.is_empty() else "SmallLabel"))
			if errs + warns > 0:
				info.add_child(K.label(app.t("ui.issues_n", {"e": errs, "w": warns}), "BadLabel" if errs > 0 else "GoldLabel"))
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list.add_child(K.panel(K.hbox([cb, info], 8), "RowPanel"))
		var sc := K.scroll(list)
		sc.custom_minimum_size.y = 380
		body.add_child(sc)
		body.add_child(K.para(app.t("ui.mods_folder_hint", {"path": Platform.folder("mods")}), "SmallLabel"))
		body.add_child(K.hbox([
			K.button(app.t("ui.open_mods_folder"), func(): Platform.open_folder("mods"), {"tip": Platform.folder("mods")}),
			K.button(app.t("ui.rescan_mods"), func():
				var issues := []
				app.packages = Platform.load_mod_packages(issues)
				render_ref[0].call(), {"tip": app.t("ui.rescan_mods_tip")}),
			K.expand(),
			K.button(app.t("ui.apply_mods"), func():
				close_ref[0].call()
				app.set_enabled_mods(enabled.keys())
				app.show_loading(app.t("ui.loading_mods"))
				await app.build_engine()
				app.show_main_menu(), {"variation": "GoldButton"}),
			K.button(app.t("ui.cancel"), func(): close_ref[0].call()),
		], 8))
	render_ref[0] = render
	render.call()
	close_ref[0] = app.modal(K.panel(body))


static func open_issues(app: App) -> void:
	var issues: Array = app.engine.issues
	var list := K.vbox([], 3)
	if issues.is_empty():
		list.add_child(K.label(app.t("ui.no_issues"), "MutedLabel"))
	for i in issues:
		var lvl: String = i.get("level", "warning")
		var text := "[%s] %s%s%s" % [lvl, (str(i.mod) + ": ") if i.get("mod") != null else "", (str(i.file) + ": ") if i.get("file") != null else "", i.get("message", "")]
		var l := K.para(text, "BadLabel" if lvl == "error" else "GoldLabel")
		list.add_child(l)
	var sc := K.scroll(list)
	sc.custom_minimum_size = Vector2(720, 420)
	var close_ref := [Callable()]
	var body := K.vbox([
		K.header(app.t("ui.mod_issues")), sc,
		K.hbox([K.expand(), K.button(app.t("ui.close"), func(): close_ref[0].call(), {"min_w": 140})]),
	], 10)
	close_ref[0] = app.modal(K.panel(body))

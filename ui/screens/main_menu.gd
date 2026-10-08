class_name MainMenu
extends RefCounted
## Главное меню: слева — колонка с названием и кнопками на тёмной ткани,
## справа — живая карта мира в «бумажном» виде.


static func build(app: App) -> Control:
	var e := app.engine
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# затемнение слева
	var shade := MenuShade.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var col := K.vbox([], 10)
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 90
	col.offset_right = 90 + 420
	col.offset_top = 0
	col.offset_bottom = 0
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(col)

	var crown := K.tex(Icons.texture("crown", 84), Vector2(84, 84))
	col.add_child(K.center(crown))
	var title := K.label(app.t("ui.game_title"), "TitleLabel")
	title.add_theme_font_size_override("font_size", 58)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var sub := K.label(app.t("ui.game_subtitle"), "MutedLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var div := TextureRect.new()
	div.texture = UiArt.texture("divider", UiArt.divider_svg())
	div.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	div.custom_minimum_size = Vector2(0, 20)
	col.add_child(div)

	var buttons := K.vbox([], 8)
	var big := func(text: String, cb: Callable, gold: bool = false) -> Button:
		var b := K.button(text, cb, {"variation": "GoldButton" if gold else "Button", "min_h": 48})
		b.add_theme_font_override("font", Fonts.heading(700))
		b.add_theme_font_size_override("font_size", 22)
		return b
	var saves := Platform.list_saves()
	if not saves.is_empty():
		var last: Dictionary = saves[0]
		var cont: Button = big.call(app.t("ui.continue"), func(): SaveScreens.load_slot(app, last.slot), true)
		K.tip(cont, BB.title(last.name) + "\n" + BB.muted(" · ".join([last.get("player", ""), last.get("date", "")])))
		buttons.add_child(cont)
	buttons.add_child(big.call(app.t("ui.new_game"), func(): NewGameScreen.open(app), saves.is_empty()))
	buttons.add_child(big.call(app.t("ui.load_game"), func(): SaveScreens.open_load_dialog(app)))
	buttons.add_child(big.call("%s (%d)" % [app.t("ui.mods"), e.mods.size()], func(): ModsScreen.open_manager(app)))
	buttons.add_child(big.call(app.t("ui.settings"), func(): SettingsScreen.open(app)))
	buttons.add_child(big.call(app.t("ui.quit_game"), func(): app.get_tree().quit()))
	col.add_child(K.margin(buttons, 30, 6, 30, 6))

	# низ: версия, моды, проблемы
	var errors := 0
	for i in e.issues:
		if i.get("level") == "error":
			errors += 1
	var warnings := e.issues.size() - errors
	var names := []
	for m in e.mods:
		names.append(m.display_name(app.lang))
	var foot := K.vbox([], 2)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_left = 24
	foot.offset_bottom = -16
	foot.add_child(K.label("v" + str(ProjectSettings.get_setting("application/config/version", "")), "SmallLabel"))
	var mods_line := K.para("%s: %s" % [app.t("ui.active_mods"), ", ".join(names)], "SmallLabel")
	mods_line.custom_minimum_size.x = 520
	foot.add_child(mods_line)
	if errors > 0 or warnings > 0:
		var link := K.button(app.t("ui.issues_n", {"e": errors, "w": warnings}), func(): ModsScreen.open_issues(app), {"variation": "LinkText"})
		link.add_theme_color_override("font_color", UiArt.C_BAD if errors > 0 else UiArt.C_WARN)
		foot.add_child(link)
	root.add_child(foot)

	var lang_btn := K.button("English" if app.lang == "ru" else "Русский", func():
		app.set_language("en" if app.lang == "ru" else "ru")
		app.show_main_menu(), {"icon": "speech", "min_w": 140})
	lang_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	lang_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lang_btn.offset_right = -20
	lang_btn.offset_top = 16
	root.add_child(lang_btn)
	return root


## Тёмная «ткань» под колонкой меню с мягким краем.
class MenuShade:
	extends Control
	var _tex: GradientTexture2D

	func _ready() -> void:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 0.75, 1.0])
		g.colors = PackedColorArray([Color(0.05, 0.045, 0.04, 0.94), Color(0.05, 0.045, 0.04, 0.88), Color(0.05, 0.045, 0.04, 0.45), Color(0.05, 0.045, 0.04, 0.0)])
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.width = 256
		_tex.height = 4
		_tex.fill_from = Vector2(0, 0)
		_tex.fill_to = Vector2(1, 0)

	func _draw() -> void:
		draw_texture_rect(_tex, Rect2(0, 0, 680, size.y), false)

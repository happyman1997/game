class_name GameTheme
extends RefCounted
## Тема интерфейса (Godot Theme): шрифты, цвета и стили всех виджетов.
## Варианты типов (theme_type_variation) задают особые виды:
##   панели — InsetPanel, HeaderPanel, ParchmentPanel, DarkPanel, BarPanel, RowPanel;
##   кнопки — GoldButton, RoundButton, FlatButton, EventOption, TabButton, CloseButton;
##   надписи — TitleLabel, HeaderLabel, SubheaderLabel, MutedLabel, SmallLabel,
##             InkLabel, InkTitle, GoodLabel, BadLabel, GoldLabel.

const BODY := 15
const SMALL := 13


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = Fonts.regular()
	t.default_font_size = BODY

	_labels(t)
	_panels(t)
	_buttons(t)
	_inputs(t)
	_scroll(t)
	_misc(t)
	return t


static func _label_variation(t: Theme, name: String, color: Color, size: int = 0, font: Font = null, shadow := true) -> void:
	t.set_type_variation(name, "Label")
	t.set_color("font_color", name, color)
	if size > 0:
		t.set_font_size("font_size", name, size)
	if font != null:
		t.set_font("font", name, font)
	if not shadow:
		t.set_color("font_shadow_color", name, Color(0, 0, 0, 0))


static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", UiArt.C_TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("line_spacing", "Label", 1)
	_label_variation(t, "TitleLabel", Color("#f3e2b0"), 34, Fonts.heading(700))
	_label_variation(t, "HeaderLabel", UiArt.C_GOLD, 22, Fonts.heading(700))
	_label_variation(t, "SubheaderLabel", UiArt.C_GOLD, 17, Fonts.heading(700))
	_label_variation(t, "MutedLabel", UiArt.C_MUTED)
	_label_variation(t, "SmallLabel", UiArt.C_MUTED, SMALL)
	_label_variation(t, "GoodLabel", UiArt.C_GOOD)
	_label_variation(t, "BadLabel", UiArt.C_BAD)
	_label_variation(t, "GoldLabel", UiArt.C_GOLD)
	_label_variation(t, "InkLabel", UiArt.C_INK, 0, null, false)
	_label_variation(t, "InkTitle", Color("#3a2410"), 30, Fonts.heading(700), false)

	t.set_color("default_color", "RichTextLabel", UiArt.C_TEXT)
	t.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0.5))
	t.set_constant("shadow_offset_x", "RichTextLabel", 1)
	t.set_constant("shadow_offset_y", "RichTextLabel", 1)
	t.set_font("normal_font", "RichTextLabel", Fonts.regular())
	t.set_font("bold_font", "RichTextLabel", Fonts.bold())
	t.set_font("italics_font", "RichTextLabel", Fonts.italic())
	t.set_font("bold_italics_font", "RichTextLabel", Fonts.bold())
	t.set_font_size("normal_font_size", "RichTextLabel", BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", BODY)
	t.set_font_size("italics_font_size", "RichTextLabel", BODY)
	t.set_constant("line_separation", "RichTextLabel", 1)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())
	# Текст на пергаменте (события).
	t.set_type_variation("InkText", "RichTextLabel")
	t.set_color("default_color", "InkText", Color("#2b1d0c"))
	t.set_color("font_shadow_color", "InkText", Color(0, 0, 0, 0))
	t.set_font_size("normal_font_size", "InkText", 16)
	t.set_font_size("bold_font_size", "InkText", 16)
	t.set_font_size("italics_font_size", "InkText", 16)


static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", UiArt.panel_box())
	t.set_stylebox("panel", "Panel", UiArt.panel_box())
	for pair in [
		["InsetPanel", UiArt.inset_box()],
		["HeaderPanel", UiArt.header_box()],
		["ParchmentPanel", UiArt.parchment_box()],
		["DarkPanel", UiArt.flat(Color("#0d1114", 0.86), Color(UiArt.BRONZE, 0.55), 1, 2, 8)],
		["BarPanel", UiArt.bar_strip_box()],
		["RowPanel", UiArt.flat(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 2, 4)],
		["ClearPanel", StyleBoxEmpty.new()],
	]:
		t.set_type_variation(pair[0], "PanelContainer")
		t.set_stylebox("panel", pair[0], pair[1])
	t.set_stylebox("panel", "TooltipPanel", UiArt.tooltip_box())
	t.set_color("font_color", "TooltipLabel", UiArt.C_TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)


static func _button_states(t: Theme, type: String, boxes: Dictionary, colors: Dictionary, size: int = 0, font: Font = null) -> void:
	for k in boxes:
		t.set_stylebox(k, type, boxes[k])
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	for k in colors:
		t.set_color(k, type, colors[k])
	if size > 0:
		t.set_font_size("font_size", type, size)
	if font != null:
		t.set_font("font", type, font)


static func _buttons(t: Theme) -> void:
	var light := {
		"font_color": UiArt.C_TEXT, "font_hover_color": Color("#fff4d6"), "font_pressed_color": UiArt.C_GOLD,
		"font_focus_color": UiArt.C_TEXT, "font_hover_pressed_color": UiArt.C_GOLD, "font_disabled_color": Color("#7c7466"),
		"icon_normal_color": UiArt.C_TEXT, "icon_hover_color": Color.WHITE, "icon_pressed_color": UiArt.C_GOLD,
		"icon_disabled_color": Color(1, 1, 1, 0.35), "font_outline_color": Color(0, 0, 0, 0.6),
	}
	_button_states(t, "Button", {
		"normal": UiArt.button_box("normal"), "hover": UiArt.button_box("hover"), "pressed": UiArt.button_box("pressed"),
		"hover_pressed": UiArt.button_box("pressed"), "disabled": UiArt.button_box("disabled"),
	}, light)
	t.set_constant("h_separation", "Button", 6)
	t.set_constant("outline_size", "Button", 0)

	t.set_type_variation("GoldButton", "Button")
	var gold := light.duplicate()
	gold.font_color = Color("#fff3d0")
	gold.font_hover_color = Color.WHITE
	gold.font_pressed_color = Color("#fff3d0")
	_button_states(t, "GoldButton", {
		"normal": UiArt.button_box("gold"), "hover": UiArt.button_box("gold_hover"), "pressed": UiArt.button_box("pressed"),
		"hover_pressed": UiArt.button_box("pressed"), "disabled": UiArt.button_box("disabled"),
	}, gold, 16, Fonts.bold())

	t.set_type_variation("RoundButton", "Button")
	_button_states(t, "RoundButton", {
		"normal": UiArt.round_box("normal"), "hover": UiArt.round_box("hover"), "pressed": UiArt.round_box("active"),
		"hover_pressed": UiArt.round_box("active"), "disabled": UiArt.round_box("normal"),
	}, light, 20, Fonts.emoji())

	t.set_type_variation("TabButton", "Button")
	_button_states(t, "TabButton", {
		"normal": UiArt.round_box("normal"), "hover": UiArt.round_box("hover"), "pressed": UiArt.round_box("active"),
		"hover_pressed": UiArt.round_box("active"), "disabled": UiArt.round_box("normal"),
	}, light, 22, Fonts.emoji())

	t.set_type_variation("FlatButton", "Button")
	var row_hover := UiArt.flat(Color(UiArt.GOLD, 0.12), Color(UiArt.GOLD, 0.35), 1, 2, 4)
	var row_norm := UiArt.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 1, 2, 4)
	_button_states(t, "FlatButton", {
		"normal": row_norm, "hover": row_hover, "pressed": UiArt.flat(Color(UiArt.GOLD, 0.2), Color(UiArt.GOLD, 0.5), 1, 2, 4),
		"hover_pressed": row_hover, "disabled": row_norm,
	}, light)

	t.set_type_variation("LinkText", "Button")
	var link := light.duplicate()
	link.font_color = UiArt.C_GOLD
	link.font_hover_color = Color("#fff0b8")
	var empty := StyleBoxEmpty.new()
	_button_states(t, "LinkText", {"normal": empty, "hover": empty, "pressed": empty, "hover_pressed": empty, "disabled": empty}, link)

	t.set_type_variation("EventOption", "Button")
	var ink := {
		"font_color": Color("#2b1d0c"), "font_hover_color": Color("#120a02"), "font_pressed_color": Color("#120a02"),
		"font_focus_color": Color("#2b1d0c"), "font_hover_pressed_color": Color("#120a02"), "font_disabled_color": Color("#7d705a"),
	}
	_button_states(t, "EventOption", {
		"normal": UiArt.option_box("normal"), "hover": UiArt.option_box("hover"), "pressed": UiArt.option_box("hover"),
		"hover_pressed": UiArt.option_box("hover"), "disabled": UiArt.option_box("disabled"),
	}, ink, 16)
	t.set_color("font_shadow_color", "EventOption", Color(0, 0, 0, 0))

	t.set_type_variation("CloseButton", "Button")
	_button_states(t, "CloseButton", {
		"normal": UiArt.round_box("normal"), "hover": UiArt.round_box("hover"), "pressed": UiArt.round_box("active"),
		"hover_pressed": UiArt.round_box("active"), "disabled": UiArt.round_box("normal"),
	}, light, 14, Fonts.bold())

	# Флажки
	for type in ["CheckBox", "CheckButton"]:
		_button_states(t, type, {
			"normal": StyleBoxEmpty.new(), "hover": UiArt.flat(Color(1, 1, 1, 0.04)), "pressed": StyleBoxEmpty.new(),
			"hover_pressed": UiArt.flat(Color(1, 1, 1, 0.04)), "disabled": StyleBoxEmpty.new(),
		}, light)
	t.set_icon("checked", "CheckBox", UiArt.texture("check_on", UiArt.check_svg(true)))
	t.set_icon("unchecked", "CheckBox", UiArt.texture("check_off", UiArt.check_svg(false)))
	t.set_icon("checked_disabled", "CheckBox", UiArt.texture("check_on", UiArt.check_svg(true)))
	t.set_icon("unchecked_disabled", "CheckBox", UiArt.texture("check_off", UiArt.check_svg(false)))
	t.set_icon("radio_checked", "CheckBox", UiArt.texture("radio_on", UiArt.radio_svg(true)))
	t.set_icon("radio_unchecked", "CheckBox", UiArt.texture("radio_off", UiArt.radio_svg(false)))

	# Выпадающий список
	_button_states(t, "OptionButton", {
		"normal": UiArt.button_box("normal"), "hover": UiArt.button_box("hover"), "pressed": UiArt.button_box("pressed"),
		"hover_pressed": UiArt.button_box("pressed"), "disabled": UiArt.button_box("disabled"),
	}, light)
	t.set_icon("arrow", "OptionButton", UiArt.texture("arrow_down", UiArt.arrow_svg()))
	t.set_constant("arrow_margin", "OptionButton", 8)


static func _inputs(t: Theme) -> void:
	var field := UiArt.flat(Color("#0b0f11", 0.9), Color(UiArt.BRONZE, 0.8), 1, 2, 6)
	var field_focus := UiArt.flat(Color("#0b0f11", 0.95), Color(UiArt.GOLD), 1, 2, 6)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", UiArt.C_TEXT)
	t.set_color("caret_color", "LineEdit", UiArt.C_GOLD)
	t.set_color("selection_color", "LineEdit", Color(UiArt.GOLD, 0.35))
	t.set_color("font_placeholder_color", "LineEdit", Color(UiArt.C_MUTED, 0.7))

	t.set_stylebox("normal", "TextEdit", field)
	t.set_stylebox("focus", "TextEdit", field_focus)
	t.set_color("font_color", "TextEdit", UiArt.C_TEXT)

	var popup := UiArt.flat(Color("#141a1d", 0.98), Color(UiArt.BRONZE), 1, 2, 4)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", UiArt.flat(Color(UiArt.GOLD, 0.2), Color(0, 0, 0, 0), 0, 2))
	t.set_color("font_color", "PopupMenu", UiArt.C_TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_stylebox("panel", "PopupPanel", popup)

	# Ползунок
	t.set_stylebox("slider", "HSlider", UiArt.flat(Color("#0b0f11"), Color(UiArt.BRONZE), 1, 2, 2))
	t.set_stylebox("grabber_area", "HSlider", UiArt.flat(Color(UiArt.GOLD, 0.6), Color(0, 0, 0, 0), 0, 2, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", UiArt.flat(Color(UiArt.GOLD, 0.8), Color(0, 0, 0, 0), 0, 2, 2))
	t.set_icon("grabber", "HSlider", UiArt.texture("grabber", UiArt.grabber_svg()))
	t.set_icon("grabber_highlight", "HSlider", UiArt.texture("grabber", UiArt.grabber_svg()))

	t.set_stylebox("background", "ProgressBar", UiArt.bar_bg())
	t.set_stylebox("fill", "ProgressBar", UiArt.bar_fill(Color("#b8913f")))
	t.set_color("font_color", "ProgressBar", UiArt.C_TEXT)
	t.set_font_size("font_size", "ProgressBar", 12)


static func _scroll(t: Theme) -> void:
	var track := UiArt.flat(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 3)
	track.content_margin_left = 3
	track.content_margin_right = 3
	var grab := UiArt.flat(Color(UiArt.BRONZE, 0.75), Color(0, 0, 0, 0), 0, 3)
	var grab_hi := UiArt.flat(Color(UiArt.GOLD, 0.9), Color(0, 0, 0, 0), 0, 3)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("scroll_focus", type, track)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hi)
		t.set_stylebox("grabber_pressed", type, grab_hi)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())


static func _misc(t: Theme) -> void:
	var sep := StyleBoxTexture.new()
	sep.texture = UiArt.texture("divider", UiArt.divider_svg())
	sep.texture_margin_left = 110
	sep.texture_margin_right = 110
	sep.content_margin_top = 6
	sep.content_margin_bottom = 6
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 14)
	var vsep := StyleBoxLine.new()
	vsep.color = Color(UiArt.BRONZE, 0.5)
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)

	t.set_constant("separation", "HBoxContainer", 6)
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("h_separation", "GridContainer", 8)
	t.set_constant("v_separation", "GridContainer", 4)
	t.set_constant("h_separation", "HFlowContainer", 6)
	t.set_constant("v_separation", "HFlowContainer", 6)

	# Вкладки
	var tab_sel := UiArt.flat(Color("#2f3a40"), Color(UiArt.GOLD), 1, 2, 6)
	tab_sel.border_width_bottom = 0
	var tab_un := UiArt.flat(Color("#151b1e"), Color(UiArt.BRONZE, 0.6), 1, 2, 6)
	tab_un.border_width_bottom = 0
	var tab_hover := UiArt.flat(Color("#232c31"), Color(UiArt.GOLD, 0.7), 1, 2, 6)
	tab_hover.border_width_bottom = 0
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_un)
	t.set_stylebox("tab_hovered", "TabBar", tab_hover)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hover)
	t.set_stylebox("panel", "TabContainer", UiArt.inset_box())
	for type in ["TabBar", "TabContainer"]:
		t.set_color("font_selected_color", type, UiArt.C_GOLD)
		t.set_color("font_unselected_color", type, UiArt.C_MUTED)
		t.set_color("font_hovered_color", type, UiArt.C_TEXT)

	t.set_stylebox("panel", "ItemList", UiArt.inset_box())
	t.set_stylebox("selected", "ItemList", UiArt.flat(Color(UiArt.GOLD, 0.2)))
	t.set_stylebox("selected_focus", "ItemList", UiArt.flat(Color(UiArt.GOLD, 0.25)))
	t.set_stylebox("hovered", "ItemList", UiArt.flat(Color(1, 1, 1, 0.05)))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())

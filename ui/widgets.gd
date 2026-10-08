class_name W
extends RefCounted
## Игровые элементы интерфейса: портреты, гербы, ссылки на персонажей,
## титулы и провинции, строки списков.


## Портрет в рамке. opts: clickable (true), coa (герб в углу), round (медальон),
## tip (своя подсказка), dim (затемнить — недоступный выбор).
static func portrait(app: App, c: Variant, width: int = 72, opts: Dictionary = {}) -> Control:
	var v := PortraitView.new()
	v.app = app
	v.game = app.game
	v.character = c
	v.round = opts.get("round", false)
	v.show_coa = opts.get("coa", false)
	v.custom_minimum_size = Vector2(width, width if v.round else roundi(width * 1.2))
	v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if c == null:
		return v
	if opts.get("clickable", true):
		K.on_click(v, func(): app.open_character(c.id))
	K.tip(v, opts.get("tip", func(): return app.character_tooltip(c.id)))
	if opts.get("dim", false):
		v.modulate = Color(0.6, 0.6, 0.6)
	return v


static func coa(app: App, title_id: Variant, width: int = 32, clickable: bool = true) -> Control:
	if title_id == null:
		return K.spacer(width, width * 1.12)
	var r := K.tex(Coa.of_title(app.game, title_id, width), Vector2(width, roundi(width * 1.12)))
	r.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if clickable:
		K.on_click(r, func(): app.open_title(title_id))
	K.tip(r, BB.title(Titles.full_name(app.game, title_id)))
	return r


static func dynasty_coa(app: App, dyn_id: Variant, width: int = 32) -> Control:
	var r := K.tex(Coa.of_dynasty(app.game, dyn_id, width), Vector2(width, roundi(width * 1.12)))
	if dyn_id != null:
		K.tip(r, BB.title(app.game.name_of("dynasties", dyn_id)))
	return r


static func _link(text: String, color: Color, cb: Callable, tip_content: Variant = null) -> Button:
	var b := Button.new()
	b.theme_type_variation = "LinkText"
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", color)
	b.add_theme_constant_override("h_separation", 0)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(cb)
	if tip_content != null:
		K.tip(b, tip_content)
	return b


static func char_link(app: App, id: Variant, with_rank: bool = false) -> Control:
	var g := app.game
	var c: Variant = g.ch(id)
	if c == null:
		return K.label("—", "MutedLabel")
	var dead: bool = c.death != null
	var color := Color("#b0a38a") if dead else (Color("#ffe08a") if g.is_player(c.id) else Color("#f0d48a"))
	var name := Chars.full_name(g, c, with_rank) + (" ✝" if dead else "")
	return _link(name, color, func(): app.open_character(c.id), func(): return app.character_tooltip(c.id))


static func title_link(app: App, id: Variant) -> Control:
	if id == null:
		return K.label("—", "MutedLabel")
	return _link(Titles.full_name(app.game, id), Color("#f0d48a"), func(): app.open_title(id))


static func prov_link(app: App, id: Variant) -> Control:
	if id == null:
		return K.label("—", "MutedLabel")
	return _link(app.game.name_of("provinces", id), Color("#f0d48a"), func(): app.open_province(id, true),
		func(): return app.province_tooltip(id))


static func scope_link(app: App, ref: Variant) -> Control:
	if not (ref is Dictionary):
		return null
	match ref.get("type"):
		"character": return char_link(app, ref.id)
		"title": return title_link(app, ref.id)
		"province": return prov_link(app, ref.id)
	return K.label(app.game.scope_name(ref))


## Строка списка персонажей: портрет, имя и строки под ним.
static func char_row(app: App, c: Dictionary, lines: Array = [], right: Array = [], width: int = 44) -> Control:
	var info := K.vbox([char_link(app, c.id, true)], 0)
	for l in lines:
		if l is String:
			info.add_child(K.label(l, "SmallLabel"))
		elif l is Control:
			info.add_child(l)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := K.hbox([portrait(app, c, width, {"coa": not c.titles.is_empty()}), info], 8)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	for r in right:
		if r != null:
			row.add_child(r)
	return K.panel(row, "RowPanel")


## Значок со значением (иконка + число) с подсказкой.
static func stat(icon_name: Variant, text: String, tip_content: Variant = null, color: Color = UiArt.C_TEXT, size: int = 18) -> Control:
	var l := K.label(text)
	l.add_theme_color_override("font_color", color)
	var box := K.hbox([K.icon(icon_name, size), l], 4)
	if tip_content != null:
		K.tip(box, tip_content)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	return box


## Навыки персонажа: значки с числами.
static func skills(app: App, c: Dictionary) -> Control:
	var g := app.game
	var row := K.hbox([], 10)
	for s in Chars.skill_ids(g):
		var d: Variant = g.content.get_def("skills", s)
		var v := int(Stats.skill(g, c, s))
		var ic: Variant = d.get("icon", "star") if d != null else "star"
		row.add_child(stat(ic, str(v), BB.title(g.name_of("skills", s)) + "\n" + BB.breakdown(Stats.stat_breakdown(g, c, s)), UiArt.C_TEXT, 18))
	return row


## Черты персонажа: значки-плашки.
static func traits(app: App, c: Dictionary) -> Control:
	var g := app.game
	var f := K.flow([], 4)
	for t in c.traits:
		var d: Variant = Chars.trait_def(g, t)
		if d == null:
			continue
		var name := g.name_of("traits", t)
		var col: Color = {
			"personality": Color("#2e3a40"), "education": Color("#24384e"), "congenital": Color("#3e2e48"),
			"health": Color("#4a2a2a"), "lifestyle": Color("#2e4230"), "fame": Color("#4a3c20"),
		}.get(d.get("category", ""), Color("#2e3a40"))
		var chip := K.panel(K.hbox([K.icon(d.get("icon"), 16), K.label(name, "SmallLabel")], 3))
		chip.add_theme_stylebox_override("panel", UiArt.flat(col, Color(UiArt.BRONZE, 0.7), 1, 3, 3))
		var tipbb := BB.title(name)
		var desc := g.loc.t_or("trait_desc." + t, "")
		if desc != "":
			tipbb += "\n" + BB.i(desc)
		var mods := BB.modifiers(g, d.get("modifiers"))
		if mods != "":
			tipbb += "\n" + mods
		K.tip(chip, tipbb)
		f.add_child(chip)
	return f


## Портрет с рамкой (прямоугольный или круглый медальон).
class PortraitView:
	extends Control
	var app: App
	var game: Game
	var character: Variant
	var round := false
	var show_coa := false
	static var _frame: StyleBoxTexture

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	static func frame_box() -> StyleBoxTexture:
		if _frame == null:
			var svg := """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
<defs><linearGradient id="br" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="%s"/><stop offset="0.4" stop-color="%s"/><stop offset="0.6" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>
<linearGradient id="sh" x1="0" y1="0" x2="0" y2="1"><stop offset="0.6" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.45"/></linearGradient></defs>
<rect x="0" y="0" width="48" height="48" fill="url(#sh)"/>
<rect x="0.5" y="0.5" width="47" height="47" fill="none" stroke="%s" stroke-width="1"/>
<rect x="2" y="2" width="44" height="44" fill="none" stroke="url(#br)" stroke-width="2.4"/>
<rect x="3.7" y="3.7" width="40.6" height="40.6" fill="none" stroke="%s" stroke-opacity="0.8" stroke-width="0.8"/>
</svg>""" % [UiArt.BRONZE_DARK, UiArt.GOLD_LIGHT, UiArt.GOLD, UiArt.BRONZE_DARK, UiArt.INK, UiArt.INK]
			var sb := StyleBoxTexture.new()
			sb.texture = UiArt.texture("portrait_frame", svg)
			sb.texture_margin_left = 6
			sb.texture_margin_right = 6
			sb.texture_margin_top = 6
			sb.texture_margin_bottom = 6
			_frame = sb
		return _frame

	func _draw() -> void:
		if character == null or game == null:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.4))
			return
		var w := int(size.x)
		var tex := Portraits.texture(game, character, maxi(48, w * 2 if w < 64 else w))
		if round:
			var c := size / 2
			var r := minf(size.x, size.y) / 2 - 1
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i in 48:
				var a := TAU * i / 48.0
				var p := Vector2(cos(a), sin(a))
				pts.append(c + p * r)
				# лицо в круге: верхние 5/6 портрета
				uvs.append(Vector2(0.5 + p.x * 0.5, 0.42 + p.y * 0.42))
			draw_colored_polygon(pts, Color.WHITE, uvs, tex)
			var ring := UiArt.texture("medallion_%d" % int(size.x), UiArt.medallion_svg(int(size.x)))
			draw_texture_rect(ring, Rect2(Vector2.ZERO, size), false)
		else:
			draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
			draw_style_box(frame_box(), Rect2(Vector2.ZERO, size))
		if show_coa and not character.titles.is_empty():
			var cw := int(size.x * 0.36)
			var ct := Coa.of_title(game, character.titles[0], cw)
			draw_texture_rect(ct, Rect2(Vector2(size.x - cw - 1, size.y - cw * 1.12 - 1), Vector2(cw, cw * 1.12)), false)
		if character.death != null and not round:
			var f := Fonts.bold()
			draw_string(f, Vector2(4, size.y - 6), "✝", HORIZONTAL_ALIGNMENT_LEFT, -1, int(size.x * 0.22), Color(1, 1, 1, 0.8))

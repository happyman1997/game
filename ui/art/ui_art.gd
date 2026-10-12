class_name UiArt
extends RefCounted
## Графика интерфейса: рамки, кнопки, пергамент, медальоны. Всё рисуется
## из SVG (растеризация ThorVG) и кэшируется — своих растровых ассетов нет,
## поэтому стиль легко менять прямо здесь (или модом через UiArt.override).
##
## Палитра в духе CK3: тёмная сине-серая ткань панелей, бронза и золото
## окантовки, пергамент событий.

const INK := "#0b0d0f"
const SLATE_TOP := "#2a343a"
const SLATE_BOTTOM := "#141a1e"
const BRONZE_DARK := "#5a4422"
const BRONZE := "#9a7a3e"
const GOLD := "#d8b25e"
const GOLD_LIGHT := "#f3d98f"

## Цвета текста и состояний — для темы и виджетов.
const C_TEXT := Color("#e9dfc6")
const C_MUTED := Color("#a49577")
const C_GOLD := Color("#e3c06a")
const C_GOOD := Color("#8fd16a")
const C_BAD := Color("#e8685a")
const C_WARN := Color("#e8b84a")
const C_INK := Color("#2a1d0e")

static var _cache := {}
## Подмена SVG по имени (для модов и тем): name → Callable() -> String.
static var overrides := {}


static func texture(name: String, svg: String, scale: float = 1.0) -> Texture2D:
	var key := "%s@%s" % [name, scale]
	if _cache.has(key):
		return _cache[key]
	var src := svg
	if overrides.has(name):
		src = overrides[name].call()
	var img := Image.new()
	if img.load_svg_from_string(src, scale) != OK:
		push_error("UiArt: не удалось нарисовать " + name)
		img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func svg_texture(svg: String, scale: float = 1.0) -> Texture2D:
	return texture("raw:" + str(svg.hash()), svg, scale)


## Растр SVG (для смешивания на CPU).
static func svg_image(svg: String, scale: float = 1.0) -> Image:
	var img := Image.new()
	img.load_svg_from_string(svg, scale)
	return img


static func _box(tex: Texture2D, margin: float, content: Vector4, scale: float = 1.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	var m := margin * scale
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = content.x
	sb.content_margin_top = content.y
	sb.content_margin_right = content.z
	sb.content_margin_bottom = content.w
	return sb


# ------------------------------------------------------------ панели

## Окно: ткань с виньеткой, бронзово-золотая окантовка с фаской, тонкая
## внутренняя кайма и узорные уголки (всё — в пределах полей 9-patch,
## чтобы орнамент не растягивался).
const PANEL_MARGIN := 22


static func panel_svg(top: String = SLATE_TOP, bottom: String = SLATE_BOTTOM) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<defs>
 <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>
 <radialGradient id="vg" cx="50%%" cy="35%%" r="75%%"><stop offset="0" stop-color="#ffffff" stop-opacity="0.05"/><stop offset="0.7" stop-color="#000000" stop-opacity="0"/><stop offset="1" stop-color="#000000" stop-opacity="0.35"/></radialGradient>
 <linearGradient id="br" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="%s"/><stop offset="0.3" stop-color="%s"/><stop offset="0.5" stop-color="%s"/><stop offset="0.7" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>
</defs>
<rect x="0" y="0" width="128" height="128" rx="4" fill="%s"/>
<rect x="2" y="2" width="124" height="124" rx="3" fill="url(#bg)"/>
<rect x="2" y="2" width="124" height="124" rx="3" fill="url(#vg)"/>
<rect x="2.5" y="2.5" width="123" height="123" rx="3" fill="none" stroke="url(#br)" stroke-width="3.5"/>
<rect x="4.6" y="4.6" width="118.8" height="118.8" rx="2" fill="none" stroke="%s" stroke-opacity="0.45" stroke-width="0.8"/>
<rect x="7" y="7" width="114" height="114" fill="none" stroke="%s" stroke-width="1.2"/>
<rect x="8.6" y="8.6" width="110.8" height="110.8" fill="none" stroke="%s" stroke-opacity="0.4" stroke-width="0.8"/>
%s
</svg>""" % [top, bottom, BRONZE_DARK, GOLD, GOLD_LIGHT, GOLD, BRONZE_DARK, INK, GOLD_LIGHT, INK, GOLD, ornate_corners(128)]


## Узорный уголок (для верхнего левого; остальные — отражения).
static func _corner_ornament() -> String:
	return """<path d="M7 19 V10.5 Q7 7 10.5 7 H19" fill="none" stroke="%s" stroke-width="2.2" stroke-linecap="round"/>
<path d="M7 19 V10.5 Q7 7 10.5 7 H19" fill="none" stroke="%s" stroke-width="0.9" stroke-linecap="round"/>
<path d="M11.5 7.6 L14.5 10.6 L11.5 13.6 L8.5 10.6 Z" fill="%s" stroke="%s" stroke-width="0.7"/>
<circle cx="19.5" cy="7" r="1.3" fill="%s" stroke="%s" stroke-width="0.5"/>
<circle cx="7" cy="19.5" r="1.3" fill="%s" stroke="%s" stroke-width="0.5"/>""" % [INK, GOLD_LIGHT, GOLD, INK, GOLD, INK, GOLD, INK]


static func ornate_corners(size: float) -> String:
	var o := _corner_ornament()
	return "<g>%s</g><g transform=\"translate(%s 0) scale(-1 1)\">%s</g><g transform=\"translate(0 %s) scale(1 -1)\">%s</g><g transform=\"translate(%s %s) scale(-1 -1)\">%s</g>" % [o, size, o, size, o, size, size, o]


static func _corners(size: float) -> String:
	var out := ""
	for c in [[6, 6], [size - 6, 6], [6, size - 6], [size - 6, size - 6]]:
		out += '<path d="M%s %s l3.5 -3.5 l3.5 3.5 l-3.5 3.5 Z" fill="%s" stroke="%s" stroke-width="0.6"/>' % [c[0] - 3.5, c[1], GOLD, INK]
	return out


static func panel_box(scale: float = 1.0) -> StyleBoxTexture:
	return _box(texture("panel", panel_svg(), scale), PANEL_MARGIN, Vector4(20, 18, 20, 18), scale)


## Внутренняя «врезка» (секция внутри окна): темнее, тень сверху, тонкая
## бронзовая рамка с золотыми точками в углах.
static func inset_svg() -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0b0f12" stop-opacity="0.92"/><stop offset="0.25" stop-color="#121a1e" stop-opacity="0.88"/><stop offset="1" stop-color="#1b252a" stop-opacity="0.85"/></linearGradient></defs>
<rect x="0.5" y="0.5" width="47" height="47" rx="2.5" fill="url(#bg)" stroke="%s" stroke-opacity="0.75" stroke-width="1"/>
<rect x="1.5" y="1.5" width="45" height="45" rx="2" fill="none" stroke="#000" stroke-opacity="0.6" stroke-width="1"/>
<circle cx="3.5" cy="3.5" r="1" fill="%s"/><circle cx="44.5" cy="3.5" r="1" fill="%s"/><circle cx="3.5" cy="44.5" r="1" fill="%s"/><circle cx="44.5" cy="44.5" r="1" fill="%s"/>
</svg>""" % [BRONZE, GOLD, GOLD, GOLD, GOLD]


static func inset_box() -> StyleBoxTexture:
	return _box(texture("inset", inset_svg()), 6, Vector4(12, 9, 12, 9))


## Тёмная плашка (обзор справа, журнал, режимы карты): полупрозрачная ткань,
## бронзовая кайма и золотые уголки.
static func dark_svg() -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#161d21" stop-opacity="0.9"/><stop offset="1" stop-color="#0a0e10" stop-opacity="0.9"/></linearGradient></defs>
<rect x="0.5" y="0.5" width="39" height="39" rx="3" fill="url(#bg)" stroke="%s" stroke-opacity="0.7" stroke-width="1"/>
<rect x="2.5" y="2.5" width="35" height="35" rx="2" fill="none" stroke="%s" stroke-opacity="0.18" stroke-width="0.8"/>
<path d="M1.5 7 V3 Q1.5 1.5 3 1.5 H7" fill="none" stroke="%s" stroke-width="1.2"/>
<path d="M33 1.5 H37 Q38.5 1.5 38.5 3 V7" fill="none" stroke="%s" stroke-width="1.2"/>
<path d="M1.5 33 V37 Q1.5 38.5 3 38.5 H7" fill="none" stroke="%s" stroke-width="1.2"/>
<path d="M33 38.5 H37 Q38.5 38.5 38.5 37 V33" fill="none" stroke="%s" stroke-width="1.2"/>
</svg>""" % [BRONZE, GOLD_LIGHT, GOLD, GOLD, GOLD, GOLD]


static func dark_box() -> StyleBoxTexture:
	return _box(texture("dark", dark_svg()), 8, Vector4(10, 8, 10, 8))


## Строка списка: лёгкий свет слева, тонкая золотая черта снизу.
static func row_svg() -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="24" viewBox="0 0 64 24">
<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#ffffff" stop-opacity="0.07"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.015"/></linearGradient>
<linearGradient id="ln" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="%s" stop-opacity="0.55"/><stop offset="1" stop-color="%s" stop-opacity="0.05"/></linearGradient></defs>
<rect x="0" y="0" width="64" height="23" rx="2" fill="url(#bg)"/>
<rect x="0" y="0" width="2" height="23" fill="%s" fill-opacity="0.45"/>
<rect x="0" y="23" width="64" height="1" fill="url(#ln)"/>
</svg>""" % [GOLD, GOLD, GOLD]


static func row_box() -> StyleBoxTexture:
	var sb := _box(texture("row", row_svg()), 3, Vector4(8, 4, 6, 5))
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return sb


## Вкладка окна: тёмная плашка; у наведённой — светлее, у активной — тёплый
## золотой свет снизу и яркая черта.
static func tab_svg(kind: String) -> String:
	var glow := 0.0
	var line := BRONZE
	var line_w := 1.0
	var top := "#1c2428"
	var bottom := "#141a1d"
	match kind:
		"hover":
			glow = 0.12
			line = GOLD
			top = "#232d32"
		"active":
			glow = 0.32
			line = GOLD_LIGHT
			line_w = 3.0
			top = "#2a2a22"
			bottom = "#241f14"
	return """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="36" viewBox="0 0 48 36">
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>
<linearGradient id="gl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s" stop-opacity="0"/><stop offset="1" stop-color="%s" stop-opacity="%s"/></linearGradient></defs>
<path d="M0 36 V4 Q0 0 4 0 H44 Q48 0 48 4 V36 Z" fill="url(#bg)"/>
<path d="M0 36 V4 Q0 0 4 0 H44 Q48 0 48 4 V36 Z" fill="url(#gl)"/>
<path d="M0.5 36 V4 Q0.5 0.5 4 0.5 H44 Q47.5 0.5 47.5 4 V36" fill="none" stroke="%s" stroke-opacity="0.35" stroke-width="1"/>
<rect x="0" y="%s" width="48" height="%s" fill="%s"/>
</svg>""" % [top, bottom, GOLD, GOLD, glow, BRONZE, 36 - line_w, line_w, line]


static func tab_box(kind: String) -> StyleBoxTexture:
	var sb := _box(texture("tab_" + kind, tab_svg(kind)), 5, Vector4(12, 6, 12, 7))
	sb.texture_margin_bottom = 4
	return sb


## Завиток по сторонам заголовка (right — зеркально, для правой стороны).
static func flourish_svg(right: bool) -> String:
	var g := """<defs><linearGradient id="ln" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="%s" stop-opacity="0"/><stop offset="0.6" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>
<path d="M2 9 H62" stroke="url(#ln)" stroke-width="1.4"/>
<path d="M44 9 Q52 2 60 6 Q64 8 62 11 Q60 13 57 11" fill="none" stroke="%s" stroke-width="1.3" stroke-linecap="round"/>
<path d="M44 9 Q52 16 60 12" fill="none" stroke="%s" stroke-opacity="0.6" stroke-width="1"/>
<path d="M68 9 L72 5 L76 9 L72 13 Z" fill="%s" stroke="%s" stroke-width="0.7"/>
<circle cx="66" cy="9" r="1.2" fill="%s"/>""" % [GOLD, GOLD, GOLD_LIGHT, GOLD, GOLD, GOLD, INK, GOLD_LIGHT]
	var body := ("<g transform=\"translate(80 0) scale(-1 1)\">%s</g>" % g) if right else g
	return '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="18" viewBox="0 0 80 18">%s</svg>' % body


## Линия под заголовком раздела: ромб у начала и золото, гаснущее вправо.
static func section_line_svg() -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="256" height="10" viewBox="0 0 256 10">
<defs><linearGradient id="ln" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="%s"/><stop offset="0.5" stop-color="%s" stop-opacity="0.45"/><stop offset="1" stop-color="%s" stop-opacity="0"/></linearGradient></defs>
<path d="M1 5 L5 1 L9 5 L5 9 Z" fill="%s" stroke="%s" stroke-width="0.6"/>
<rect x="11" y="4.4" width="245" height="1.3" fill="url(#ln)"/>
</svg>""" % [GOLD, GOLD, GOLD, GOLD, INK]


## Заголовок окна: тёмная полоса с отблеском сверху и двойной золотой
## линией снизу.
static func header_svg() -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="48" viewBox="0 0 64 48">
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#43352a"/><stop offset="0.45" stop-color="#271f18"/><stop offset="1" stop-color="#15110d"/></linearGradient>
<linearGradient id="ln" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="%s" stop-opacity="0"/><stop offset="0.15" stop-color="%s"/><stop offset="0.85" stop-color="%s"/><stop offset="1" stop-color="%s" stop-opacity="0"/></linearGradient></defs>
<rect width="64" height="48" rx="2" fill="url(#bg)"/>
<rect y="1" width="64" height="1" fill="#fff3c8" fill-opacity="0.12"/>
<rect y="41" width="64" height="2" fill="url(#ln)"/>
<rect y="44" width="64" height="1" fill="url(#ln)" fill-opacity="0.5"/>
<rect y="46" width="64" height="2" fill="#000" fill-opacity="0.5"/>
</svg>""" % [GOLD, GOLD_LIGHT, GOLD_LIGHT, GOLD]


static func header_box() -> StyleBoxTexture:
	var sb := _box(texture("header", header_svg()), 8, Vector4(14, 7, 14, 12))
	sb.texture_margin_bottom = 9
	return sb


## Пергамент окна событий.
static func parchment_svg() -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<defs>
 <radialGradient id="p" cx="50%%" cy="45%%" r="75%%"><stop offset="0" stop-color="#f3e6c4"/><stop offset="0.65" stop-color="#e2cf9f"/><stop offset="1" stop-color="#b8996a"/></radialGradient>
 <linearGradient id="br" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="%s"/><stop offset="0.5" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>
</defs>
<rect width="128" height="128" rx="3" fill="%s"/>
<rect x="2" y="2" width="124" height="124" rx="2" fill="url(#p)" stroke="url(#br)" stroke-width="4"/>
<rect x="7" y="7" width="114" height="114" fill="none" stroke="#5a3e1c" stroke-opacity="0.55" stroke-width="1"/>
%s
</svg>""" % [BRONZE_DARK, GOLD, BRONZE_DARK, INK, _corners(128)]


static func parchment_box() -> StyleBoxTexture:
	return _box(texture("parchment", parchment_svg()), 14, Vector4(22, 18, 22, 18))


## Тень под окном.
static func shadow_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


# ------------------------------------------------------------ кнопки

## kind: normal | hover | pressed | disabled | gold | gold_hover
static func button_svg(kind: String) -> String:
	var top := "#3c4950"
	var bottom := "#1f272c"
	var border := BRONZE
	var hi := "#ffffff"
	var hi_op := 0.12
	match kind:
		"hover":
			top = "#4b5b63"
			bottom = "#27333a"
			border = GOLD
			hi_op = 0.2
		"pressed":
			top = "#1a2125"
			bottom = "#2f3a40"
			border = GOLD
			hi_op = 0.04
		"disabled":
			top = "#2b2e30"
			bottom = "#1d1f21"
			border = "#5a5348"
			hi_op = 0.04
		"gold":
			top = "#8a6a2c"
			bottom = "#4c3714"
			border = GOLD_LIGHT
			hi = "#fff3c8"
			hi_op = 0.25
		"gold_hover":
			top = "#a5813a"
			bottom = "#5e4519"
			border = "#fff0b8"
			hi = "#fff3c8"
			hi_op = 0.35
	return """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="32" viewBox="0 0 48 32">
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>
<linearGradient id="sh" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="%s"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/><stop offset="1" stop-color="#000000" stop-opacity="0.25"/></linearGradient></defs>
<rect x="0.5" y="0.5" width="47" height="31" rx="3.5" fill="%s"/>
<rect x="1.5" y="1.5" width="45" height="29" rx="3" fill="url(#bg)"/>
<rect x="1.5" y="1.5" width="45" height="29" rx="3" fill="url(#sh)"/>
<rect x="1.5" y="1.5" width="45" height="29" rx="3" fill="none" stroke="%s" stroke-width="1.4"/>
<path d="M5 3.6 H43" stroke="%s" stroke-opacity="%s" stroke-width="1"/>
<rect x="3.2" y="3.2" width="41.6" height="25.6" rx="2" fill="none" stroke="#000" stroke-opacity="0.25" stroke-width="0.8"/>
</svg>""" % [top, bottom, hi_op * 0.8, INK, border, hi, hi_op]


static func button_box(kind: String) -> StyleBoxTexture:
	return _box(texture("button_" + kind, button_svg(kind)), 6, Vector4(14, 6, 14, 7))


## Круглый медальон (кнопки вкладок, режимов карты, скорости).
static func round_svg(kind: String) -> String:
	var ring := GOLD if kind != "normal" else BRONZE
	var inner_top := "#33414a" if kind != "active" else "#6e5420"
	var inner_bottom := "#11171b" if kind != "active" else "#2c2009"
	var glow := '<circle cx="32" cy="32" r="31" fill="none" stroke="%s" stroke-opacity="0.45" stroke-width="2"/>' % GOLD_LIGHT if kind == "hover" or kind == "active" else ""
	return """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<defs>
 <radialGradient id="in" cx="40%%" cy="30%%" r="80%%"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></radialGradient>
 <linearGradient id="ring" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="%s"/><stop offset="0.5" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>
</defs>
<circle cx="32" cy="32" r="30" fill="%s"/>
<circle cx="32" cy="32" r="28" fill="url(#in)" stroke="url(#ring)" stroke-width="3.5"/>
<circle cx="32" cy="32" r="24.5" fill="none" stroke="%s" stroke-width="1"/>
%s
</svg>""" % [inner_top, inner_bottom, BRONZE_DARK, ring, BRONZE_DARK, INK, INK, glow]


static func round_box(kind: String) -> StyleBoxTexture:
	var sb := _box(texture("round_" + kind, round_svg(kind)), 0, Vector4(6, 6, 6, 6))
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return sb


## Вариант события (полоса на пергаменте).
static func option_svg(kind: String) -> String:
	var top := "#d9c294" if kind != "hover" else "#ead7a8"
	var bottom := "#c4a872" if kind != "hover" else "#d6bd86"
	var border := "#6b4c22" if kind != "hover" else "#3c2a10"
	if kind == "disabled":
		top = "#c9bfa8"
		bottom = "#b5aa90"
		border = "#8a7b5e"
	return """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="32" viewBox="0 0 48 32">
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>
<rect x="0.75" y="0.75" width="46.5" height="30.5" rx="2.5" fill="url(#bg)" stroke="%s" stroke-width="1.5"/>
<path d="M4 3 H44" stroke="#fff8e0" stroke-opacity="0.5" stroke-width="1"/>
</svg>""" % [top, bottom, border]


static func option_box(kind: String) -> StyleBoxTexture:
	return _box(texture("option_" + kind, option_svg(kind)), 6, Vector4(14, 7, 14, 8))


# ------------------------------------------------------------ мелочи

## Орнаментальный разделитель.
static func divider_svg() -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="240" height="12" viewBox="0 0 240 12">
<defs><linearGradient id="ln" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="%s" stop-opacity="0"/><stop offset="0.3" stop-color="%s"/><stop offset="0.7" stop-color="%s"/><stop offset="1" stop-color="%s" stop-opacity="0"/></linearGradient></defs>
<rect x="0" y="5.5" width="240" height="1.2" fill="url(#ln)"/>
<path d="M120 1.5 L124.5 6 L120 10.5 L115.5 6 Z" fill="%s" stroke="%s" stroke-width="0.6"/>
<circle cx="108" cy="6" r="1.4" fill="%s"/><circle cx="132" cy="6" r="1.4" fill="%s"/>
</svg>""" % [GOLD, GOLD, GOLD, GOLD, GOLD, INK, GOLD, GOLD]


## Кольцо-рамка медальона портрета.
static func medallion_svg(size: int) -> String:
	var c := size / 2.0
	return """<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">
<defs><linearGradient id="ring" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="%s"/><stop offset="0.35" stop-color="%s"/><stop offset="0.5" stop-color="%s"/><stop offset="0.7" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>
<circle cx="%s" cy="%s" r="%s" fill="none" stroke="%s" stroke-width="%s"/>
<circle cx="%s" cy="%s" r="%s" fill="none" stroke="url(#ring)" stroke-width="%s"/>
<circle cx="%s" cy="%s" r="%s" fill="none" stroke="%s" stroke-width="1.2"/>
</svg>""" % [size, size, size, size, BRONZE_DARK, GOLD_LIGHT, GOLD, BRONZE, BRONZE_DARK,
		c, c, c - 1.5, INK, 3, c, c, c - 4.5, size * 0.06, c, c, c - 4.5 - size * 0.03, INK]


## Рамка портрета (прямоугольная).
static func frame_svg(w: int, h: int, thick: float = 4.0) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">
<defs><linearGradient id="br" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="%s"/><stop offset="0.4" stop-color="%s"/><stop offset="0.6" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>
<rect x="0.5" y="0.5" width="%s" height="%s" fill="none" stroke="%s" stroke-width="1"/>
<rect x="%s" y="%s" width="%s" height="%s" fill="none" stroke="url(#br)" stroke-width="%s"/>
<rect x="%s" y="%s" width="%s" height="%s" fill="none" stroke="%s" stroke-width="1"/>
</svg>""" % [w, h, w, h, BRONZE_DARK, GOLD_LIGHT, GOLD, BRONZE_DARK,
		w - 1, h - 1, INK, thick / 2 + 1, thick / 2 + 1, w - thick - 2, h - thick - 2, thick, thick + 1.5, thick + 1.5, w - 2 * thick - 3, h - 2 * thick - 3, INK]


## Полоса прогресса: фон и заполнение.
static func bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0d1113")
	sb.border_color = Color(BRONZE)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	return sb


static func bar_fill(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(2)
	sb.border_color = color.lightened(0.3)
	sb.border_width_top = 1
	return sb


## Подсказка: тёмная ткань, бронзовая кайма с золотыми уголками и тень.
static func tooltip_svg() -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1a2226"/><stop offset="1" stop-color="#0d1214"/></linearGradient></defs>
<rect x="0" y="0" width="48" height="48" rx="3" fill="%s" fill-opacity="0.9"/>
<rect x="1" y="1" width="46" height="46" rx="2.5" fill="url(#bg)" stroke="%s" stroke-width="1.2"/>
<rect x="3" y="3" width="42" height="42" rx="1.5" fill="none" stroke="%s" stroke-opacity="0.2" stroke-width="0.8"/>
<path d="M1.5 8 V3.5 Q1.5 1.5 3.5 1.5 H8" fill="none" stroke="%s" stroke-width="1.4"/>
<path d="M40 1.5 H44.5 Q46.5 1.5 46.5 3.5 V8" fill="none" stroke="%s" stroke-width="1.4"/>
<path d="M1.5 40 V44.5 Q1.5 46.5 3.5 46.5 H8" fill="none" stroke="%s" stroke-width="1.4"/>
<path d="M40 46.5 H44.5 Q46.5 46.5 46.5 44.5 V40" fill="none" stroke="%s" stroke-width="1.4"/>
</svg>""" % [INK, BRONZE, GOLD_LIGHT, GOLD, GOLD, GOLD, GOLD]


static func tooltip_box() -> StyleBoxTexture:
	return _box(texture("tooltip", tooltip_svg()), 9, Vector4(14, 10, 14, 11))


static func flat(color: Color, border: Color = Color(0, 0, 0, 0), width: int = 0, radius: int = 0, margin: float = -1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	if margin >= 0:
		sb.set_content_margin_all(margin)
	return sb


## Полоса верхней/нижней панели: тёмная ткань с золотой кромкой снизу.
static func bar_strip_svg() -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="48" viewBox="0 0 64 48">
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1d2529" stop-opacity="0.97"/><stop offset="1" stop-color="#0e1316" stop-opacity="0.97"/></linearGradient>
<linearGradient id="ln" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>
<rect width="64" height="48" fill="url(#bg)"/>
<rect y="0" width="64" height="1" fill="%s" fill-opacity="0.35"/>
<rect y="43" width="64" height="3" fill="url(#ln)"/>
<rect y="46" width="64" height="2" fill="#000" fill-opacity="0.6"/>
</svg>""" % [GOLD_LIGHT, BRONZE_DARK, GOLD]


static func bar_strip_box() -> StyleBoxTexture:
	var sb := _box(texture("bar_strip", bar_strip_svg()), 0, Vector4(10, 4, 10, 8))
	sb.texture_margin_top = 2
	sb.texture_margin_bottom = 6
	return sb


static func check_svg(on: bool) -> String:
	var mark := '<path d="M5 10.5 L8.5 14 L15.5 6" fill="none" stroke="%s" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>' % GOLD_LIGHT if on else ""
	return """<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
<rect x="1.5" y="1.5" width="17" height="17" rx="2" fill="#0b0f11" stroke="%s" stroke-width="1.4"/>%s
</svg>""" % [GOLD if on else BRONZE, mark]


static func radio_svg(on: bool) -> String:
	var dot := '<circle cx="10" cy="10" r="4.2" fill="%s"/>' % GOLD_LIGHT if on else ""
	return """<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
<circle cx="10" cy="10" r="8.3" fill="#0b0f11" stroke="%s" stroke-width="1.4"/>%s
</svg>""" % [GOLD if on else BRONZE, dot]


static func arrow_svg() -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="14" height="10" viewBox="0 0 14 10">
<path d="M1.5 2 L7 8 L12.5 2 Z" fill="%s" stroke="%s" stroke-width="0.8"/></svg>""" % [GOLD, INK]


static func grabber_svg() -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
<path d="M9 1.5 L16.5 9 L9 16.5 L1.5 9 Z" fill="%s" stroke="%s" stroke-width="1.2"/></svg>""" % [GOLD, INK]

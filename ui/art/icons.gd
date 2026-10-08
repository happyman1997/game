class_name Icons
extends RefCounted
## Иконки интерфейса (SVG, золото с тёмным контуром). Встроенные эмодзи
## из данных модов (👑, ⚔, 🗡…) автоматически заменяются нарисованными
## иконками; неизвестные эмодзи показываются шрифтом Noto Emoji.
## Мод может добавить или заменить иконку: Icons.register(name, svg_body).

const STROKE := "#1c140a"

## Тела иконок в системе координат 24×24. Заливка по умолчанию — золото.
static var BODIES := {
	"gold": '<ellipse cx="12" cy="17.5" rx="8" ry="3.2"/><path d="M4 17.5 V14.5 A8 3.2 0 0 0 20 14.5 V17.5"/><ellipse cx="12" cy="14.5" rx="8" ry="3.2"/><path d="M4 14.5 V11.5 A8 3.2 0 0 0 20 11.5 V14.5"/><ellipse cx="12" cy="11.5" rx="8" ry="3.2"/><ellipse cx="12" cy="11.5" rx="4.5" ry="1.6" fill="none"/>',
	"prestige": '<path d="M12 2 L14.6 8.2 L21.3 8.6 L16.2 12.9 L17.8 19.4 L12 15.9 L6.2 19.4 L7.8 12.9 L2.7 8.6 L9.4 8.2 Z"/><circle cx="12" cy="11.2" r="2.2" fill="#fff3c8"/>',
	"piety": '<circle cx="12" cy="9" r="7.2" fill="none" stroke-width="1.2" opacity="0.8"/><path d="M10.4 3 H13.6 V7.2 H17.8 V10.4 H13.6 V21 H10.4 V10.4 H6.2 V7.2 H10.4 Z"/>',
	"levies": '<path d="M4 3 L6.5 3 L15 12.5 L13 14.5 L4 5.5 Z"/><path d="M20 3 L17.5 3 L9 12.5 L11 14.5 L20 5.5 Z"/><path d="M11.5 14 L14 16.5 L10.5 20 L9.5 21 L8 19.5 L9 18.5 L7.5 17 L9 15.5 L10.5 16.5 Z"/><path d="M12.5 14 L10 16.5 L13.5 20 L14.5 21 L16 19.5 L15 18.5 L16.5 17 L15 15.5 L13.5 16.5 Z"/>',
	"stress": '<path d="M12 3 C7 3 3.5 6.5 3.5 11 C3.5 16 7.5 21 12 21 C16.5 21 20.5 16 20.5 11 C20.5 6.5 17 3 12 3 Z"/><path d="M13 4 L10.5 10 L13.5 11.5 L10.5 20" fill="none" stroke-width="1.6"/>',
	"dread": '<path d="M12 2.5 C6.5 2.5 3.5 6.5 3.5 11 C3.5 14 5 15.5 6.5 16.5 V20.5 H17.5 V16.5 C19 15.5 20.5 14 20.5 11 C20.5 6.5 17.5 2.5 12 2.5 Z"/><circle cx="8.7" cy="11" r="2.3" fill="#1c140a"/><circle cx="15.3" cy="11" r="2.3" fill="#1c140a"/><path d="M12 13.5 L13.2 16 H10.8 Z" fill="#1c140a"/>',
	"renown": '<path d="M12 21 V11 M12 11 C8 11 5.5 8.5 5.5 5.5 C8.5 5.5 11 7.5 12 11 C13 7.5 15.5 5.5 18.5 5.5 C18.5 8.5 16 11 12 11 Z M12 15 C9 15 6.5 13.5 5.5 11 C8.5 11 11 12.5 12 15 C13 12.5 15.5 11 18.5 11 C17.5 13.5 15 15 12 15 Z"/>',
	"crown": '<path d="M3.5 18 L3 7.5 L8 11.5 L12 4.5 L16 11.5 L21 7.5 L20.5 18 Z"/><rect x="3.5" y="18" width="17" height="2.8" rx="0.6"/><circle cx="12" cy="14.5" r="1.5" fill="#b02020"/><circle cx="7.2" cy="15" r="1.1" fill="#2050b0"/><circle cx="16.8" cy="15" r="1.1" fill="#2050b0"/>',
	"castle": '<path d="M3 21 V9 H5.5 V11 H7.5 V9 H10 V11 H11 V6 H9.8 V3 H11.6 V4.5 H12.4 V3 H14.2 V6 H13 V11 H14 V9 H16.5 V11 H18.5 V9 H21 V21 Z"/><path d="M10 21 V16.5 A2 2 0 0 1 14 16.5 V21 Z" fill="#1c140a"/>',
	"swords": '<path d="M4 3 L6.5 3 L15 12.5 L13 14.5 L4 5.5 Z"/><path d="M20 3 L17.5 3 L9 12.5 L11 14.5 L20 5.5 Z"/><path d="M11.5 14 L14 16.5 L10.5 20 L9.5 21 L8 19.5 L9 18.5 L7.5 17 L9 15.5 L10.5 16.5 Z"/><path d="M12.5 14 L10 16.5 L13.5 20 L14.5 21 L16 19.5 L15 18.5 L16.5 17 L15 15.5 L13.5 16.5 Z"/>',
	"shield": '<path d="M12 2.5 L20 5.5 V11 C20 16 16.5 19.5 12 21.5 C7.5 19.5 4 16 4 11 V5.5 Z"/><path d="M12 2.5 V21.5 M4.5 10.5 H19.5" fill="none" stroke-width="1.3"/>',
	"banner": '<path d="M5 2 V22" fill="none" stroke-width="2"/><path d="M6 3 H19 L16 8 L19 13 H6 Z"/><circle cx="5" cy="2.2" r="1.4"/>',
	"fire": '<path d="M12 2.5 C13 6 17.5 8.5 17.5 14 C17.5 18 15 21 12 21 C9 21 6.5 18 6.5 14.5 C6.5 11.5 8.5 10 9 7.5 C10.5 9 10.5 11 11 12 C12.5 9.5 12.5 6 12 2.5 Z"/><path d="M12 13 C13.5 15 14.5 16 14.5 17.8 C14.5 19.3 13.4 20.2 12 20.2 C10.6 20.2 9.5 19.3 9.5 17.8 C9.5 16.2 11 15.5 12 13 Z" fill="#fff0b0"/>',
	"dagger": '<path d="M17.5 2.5 L21.5 2.5 L21.5 6.5 L11.5 16.5 L7.5 12.5 Z"/><path d="M5 11 L13 19 L11.8 20.2 L3.8 12.2 Z"/><path d="M7.5 16.5 L4 20 L5 21 L8.5 17.5 Z" stroke-width="1.6"/>',
	"scroll": '<path d="M6 4 H18 C19.5 4 20.5 5 20.5 6.5 C20.5 8 19.5 9 18 9 H17 V18 C17 19.8 15.8 21 14 21 H5 C3.5 21 2.5 20 2.5 18.5 C2.5 17 3.5 16 5 16 H6 Z"/><path d="M8.5 8 H14.5 M8.5 11 H14.5 M8.5 14 H13" fill="none" stroke-width="1.1"/>',
	"book": '<path d="M3 5 C6 3.5 9.5 3.5 12 5.5 C14.5 3.5 18 3.5 21 5 V19.5 C18 18 14.5 18 12 20 C9.5 18 6 18 3 19.5 Z"/><path d="M12 5.5 V20" fill="none" stroke-width="1.2"/>',
	"person": '<circle cx="12" cy="7.5" r="4.3"/><path d="M3.5 21.5 C3.5 15.5 7 12.8 12 12.8 C17 12.8 20.5 15.5 20.5 21.5 Z"/>',
	"leaf": '<path d="M4 20 C4 10 9 4 20 3.5 C20 14 14 20 4 20 Z"/><path d="M4 20 L15 9" fill="none" stroke-width="1.2"/>',
	"council": '<circle cx="12" cy="12" r="5.2"/><circle cx="12" cy="3.6" r="2"/><circle cx="12" cy="20.4" r="2"/><circle cx="3.6" cy="12" r="2"/><circle cx="20.4" cy="12" r="2"/><circle cx="6.1" cy="6.1" r="1.8"/><circle cx="17.9" cy="6.1" r="1.8"/><circle cx="6.1" cy="17.9" r="1.8"/><circle cx="17.9" cy="17.9" r="1.8"/>',
	"scales": '<path d="M12 3 V20 M7 20.5 H17 M4 6 H20" fill="none" stroke-width="1.8"/><path d="M1.5 13 L4.5 6.5 L7.5 13 Z M16.5 13 L19.5 6.5 L22.5 13 Z"/><path d="M1.5 13 A3 2 0 0 0 7.5 13 Z M16.5 13 A3 2 0 0 0 22.5 13 Z"/>',
	"fist": '<path d="M7 21 V14 L5.5 11 V7.5 A1.5 1.5 0 0 1 8.5 7.5 V6 A1.5 1.5 0 0 1 11.5 6 V5.5 A1.5 1.5 0 0 1 14.5 5.5 V6.5 A1.5 1.5 0 0 1 17.5 6.5 V13 L16 15 V21 Z"/>',
	"spear": '<path d="M12 1.5 L15 7 L13 8 V22 H11 V8 L9 7 Z"/><path d="M8.5 9 H15.5" fill="none" stroke-width="1.6"/>',
	"eye": '<path d="M1.5 12 Q12 1.5 22.5 12 Q12 22.5 1.5 12 Z"/><circle cx="12" cy="12" r="3.6" fill="#1c140a"/><circle cx="13.2" cy="10.8" r="1.1" fill="#fff3c8"/>',
	"helm": '<path d="M5 20 V11 C5 6.5 8 3.5 12 3.5 C16 3.5 19 6.5 19 11 V20 Z"/><path d="M7.5 11 H16.5 M12 11 V18" fill="none" stroke-width="1.8"/>',
	"menu": '<rect x="4" y="5.5" width="16" height="2.4" rx="1"/><rect x="4" y="10.8" width="16" height="2.4" rx="1"/><rect x="4" y="16.1" width="16" height="2.4" rx="1"/>',
	"play": '<path d="M7.5 4.5 L19.5 12 L7.5 19.5 Z"/>',
	"pause": '<rect x="6" y="4.5" width="4.2" height="15" rx="0.8"/><rect x="13.8" y="4.5" width="4.2" height="15" rx="0.8"/>',
	"close": '<path d="M5.5 7.5 L7.5 5.5 L12 10 L16.5 5.5 L18.5 7.5 L14 12 L18.5 16.5 L16.5 18.5 L12 14 L7.5 18.5 L5.5 16.5 L10 12 Z"/>',
	"back": '<path d="M10.5 4.5 L3 12 L10.5 19.5 V14.5 H21 V9.5 H10.5 Z"/>',
	"plus": '<path d="M10.2 4 H13.8 V10.2 H20 V13.8 H13.8 V20 H10.2 V13.8 H4 V10.2 H10.2 Z"/>',
	"minus": '<rect x="4" y="10.2" width="16" height="3.6" rx="0.6"/>',
	"handshake": '<circle cx="8.5" cy="12" r="5.8" fill="none" stroke-width="2.6"/><circle cx="15.5" cy="12" r="5.8" fill="none" stroke-width="2.6"/>',
	"mountain": '<path d="M1.5 20 L8.5 7 L12 12.5 L15 8 L22.5 20 Z"/><path d="M8.5 7 L10.5 10.6 L9.3 10 L8.2 11.2 L6.9 10 Z M15 8 L16.8 11 L15.6 10.6 L14.5 11.4 L13.6 10.2 Z" fill="#fff8e6"/>',
	"speech": '<path d="M3 5 H21 V16 H11 L6 20.5 V16 H3 Z"/><path d="M6.5 8.5 H17.5 M6.5 12 H14" fill="none" stroke-width="1.2"/>',
	"cross": '<path d="M10.2 2.5 H13.8 V7.5 H18.8 V11.1 H13.8 V21.5 H10.2 V11.1 H5.2 V7.5 H10.2 Z"/>',
	"skull": '<path d="M12 2.5 C6.5 2.5 3.5 6.5 3.5 11 C3.5 14 5 15.5 6.5 16.5 V20.5 H17.5 V16.5 C19 15.5 20.5 14 20.5 11 C20.5 6.5 17.5 2.5 12 2.5 Z"/><circle cx="8.7" cy="11" r="2.3" fill="#1c140a"/><circle cx="15.3" cy="11" r="2.3" fill="#1c140a"/><path d="M12 13.5 L13.2 16 H10.8 Z" fill="#1c140a"/>',
	"ring": '<circle cx="12" cy="14" r="6.5" fill="none" stroke-width="3"/><path d="M9.5 7.5 L12 3 L14.5 7.5 Z"/>',
	"heart": '<path d="M12 21 C5 15.5 2.5 12 2.5 8.5 C2.5 5.5 4.8 3.5 7.5 3.5 C9.5 3.5 11 4.8 12 6.5 C13 4.8 14.5 3.5 16.5 3.5 C19.2 3.5 21.5 5.5 21.5 8.5 C21.5 12 19 15.5 12 21 Z"/>',
	"chain": '<rect x="2.5" y="8.5" width="10" height="7" rx="3.5" fill="none" stroke-width="2.4"/><rect x="11.5" y="8.5" width="10" height="7" rx="3.5" fill="none" stroke-width="2.4"/>',
	"tower": '<path d="M7 21 V9 H5.5 V3.5 H8.5 V5.5 H10.5 V3.5 H13.5 V5.5 H15.5 V3.5 H18.5 V9 H17 V21 Z"/><path d="M10 21 V16 A2 2 0 0 1 14 16 V21 Z" fill="#1c140a"/>',
	"hourglass": '<path d="M5 2.5 H19 V4.5 H18 C18 9 14 10.5 14 12 C14 13.5 18 15 18 19.5 H19 V21.5 H5 V19.5 H6 C6 15 10 13.5 10 12 C10 10.5 6 9 6 4.5 H5 Z"/>',
	"star": '<path d="M12 2 L14.6 8.2 L21.3 8.6 L16.2 12.9 L17.8 19.4 L12 15.9 L6.2 19.4 L7.8 12.9 L2.7 8.6 L9.4 8.2 Z"/>',
	"warning": '<path d="M12 2.5 L22.5 20.5 H1.5 Z"/><path d="M12 8.5 V14.5" fill="none" stroke-width="2.4"/><circle cx="12" cy="17.3" r="1.3" fill="#1c140a"/>',
	"save": '<path d="M3.5 3.5 H17.5 L20.5 6.5 V20.5 H3.5 Z"/><rect x="7" y="3.5" width="9" height="5.5" fill="#1c140a"/><rect x="6.5" y="12.5" width="11" height="8" rx="0.5" fill="#fff3c8"/>',
	"gear": '<path d="M10.5 2.5 H13.5 L14 5.2 L16.3 6.2 L18.6 4.6 L20.7 6.7 L19.1 9 L20.1 11.3 L22.5 11.8 V14.2 L20 14.8 L19 17.1 L20.5 19.4 L18.4 21.5 L16.1 19.9 L13.8 20.9 L13.3 23 H10.7 L10.2 20.9 L7.9 19.9 L5.6 21.5 L3.5 19.4 L5 17.1 L4 14.8 L1.5 14.2 V11.8 L3.9 11.3 L4.9 9 L3.3 6.7 L5.4 4.6 L7.7 6.2 L10 5.2 Z"/><circle cx="12" cy="12.8" r="3.6" fill="#1c140a"/>',
	"map": '<path d="M2.5 5.5 L8.5 3.5 L15.5 6 L21.5 4 V18.5 L15.5 20.5 L8.5 18 L2.5 20 Z"/><path d="M8.5 3.5 V18 M15.5 6 V20.5" fill="none" stroke-width="1.1"/>',
	"dynasty": '<path d="M12 21 V12 M12 12 L6 7 M12 12 L18 7 M12 16 L8 13 M12 16 L16 13" fill="none" stroke-width="2"/><circle cx="12" cy="5" r="2.6"/><circle cx="5.5" cy="6.5" r="2.2"/><circle cx="18.5" cy="6.5" r="2.2"/>',
	"baby": '<circle cx="12" cy="9" r="5"/><path d="M6 21 C6 16.5 8.5 14.5 12 14.5 C15.5 14.5 18 16.5 18 21 Z"/><circle cx="12" cy="3.5" r="1.4"/>',
	"tournament": '<path d="M3 21 L17 3.5 L19 5 L5.5 22 Z"/><path d="M14 3 H21 V10 L18 7.5 Z"/>',
}

## Эмодзи из данных → имя нарисованной иконки.
static var EMOJI := {
	"💰": "gold", "🪙": "gold", "⭐": "prestige", "🌟": "prestige", "✝": "piety", "✝️": "piety", "🙏": "piety",
	"⚔": "swords", "⚔️": "swords", "🗡": "dagger", "🗡️": "dagger", "🔪": "dagger", "👑": "crown", "🏰": "castle",
	"🛡": "shield", "🛡️": "shield", "🔥": "fire", "📜": "scroll", "📖": "book", "👤": "person", "🌿": "leaf",
	"🏛": "council", "🏛️": "council", "⚖": "scales", "⚖️": "scales", "✊": "fist", "🔱": "spear", "👁": "eye",
	"👁️": "eye", "🪖": "helm", "☰": "menu", "🤝": "handshake", "⛰": "mountain", "⛰️": "mountain", "🗣": "speech",
	"🗣️": "speech", "☠": "skull", "☠️": "skull", "💀": "skull", "💍": "ring", "❤": "heart", "❤️": "heart",
	"⛓": "chain", "⛓️": "chain", "🗼": "tower", "⏳": "hourglass", "⌛": "hourglass", "⚠": "warning", "⚠️": "warning",
	"😣": "stress", "😰": "stress", "🚩": "banner", "🏳": "banner", "🏴": "banner", "🗺": "map", "🗺️": "map",
	"🌳": "dynasty", "👶": "baby", "🏇": "tournament", "🐎": "tournament", "💾": "save", "⚙": "gear", "⚙️": "gear",
}

static var _tex := {}


static func register(name: String, body: String) -> void:
	BODIES[name] = body
	var drop := []
	for k in _tex:
		if k.begins_with(name + "@"):
			drop.append(k)
	for k in drop:
		_tex.erase(k)


static func has_icon(name: String) -> bool:
	return BODIES.has(name)


## Имя нарисованной иконки для текста иконки из данных (эмодзи или имя).
static func resolve(icon: Variant) -> String:
	var s := str(icon) if icon != null else ""
	if s.begins_with("icon:"):
		s = s.substr(5)
	if BODIES.has(s):
		return s
	return EMOJI.get(s, EMOJI.get(s.replace("️", ""), ""))


static func svg(name: String, size: int = 24, fill_top: String = "#f6dea0", fill_bottom: String = "#b0843a") -> String:
	var body: String = BODIES.get(name, BODIES.star)
	return """<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>
<g fill="url(#g)" stroke="%s" stroke-width="1" stroke-linejoin="round">%s</g></svg>""" % [size, size, fill_top, fill_bottom, STROKE, body]


## Текстура иконки (с кэшем). tint: gold | silver | red | green | blue.
static func texture(name: String, size: int = 24, tint: String = "gold") -> Texture2D:
	var key := "%s@%d@%s" % [name, size, tint]
	if _tex.has(key):
		return _tex[key]
	var cols: Array = {
		"gold": ["#f6dea0", "#b0843a"], "silver": ["#f2f2ee", "#9a9a94"], "red": ["#f08a7a", "#9a2a20"],
		"green": ["#bfe8a0", "#4a8a30"], "blue": ["#a8c8f0", "#3a5a9a"], "ink": ["#5a4020", "#2a1a08"],
	}.get(tint, ["#f6dea0", "#b0843a"])
	var img := Image.new()
	# Рисуем вдвое крупнее и уменьшаем — так мелкие иконки чётче.
	img.load_svg_from_string(svg(name, size * 2, cols[0], cols[1]), 1.0)
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex


## Иконка для текста из данных: TextureRect с нарисованной иконкой или
## надпись с эмодзи-шрифтом.
static func node(icon: Variant, size: int = 20, tint: String = "gold") -> Control:
	var name := resolve(icon)
	if name != "":
		var r := TextureRect.new()
		r.texture = texture(name, size, tint)
		r.custom_minimum_size = Vector2(size, size)
		r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		r.mouse_filter = Control.MOUSE_FILTER_PASS
		return r
	var l := Label.new()
	l.text = str(icon) if icon != null else ""
	l.add_theme_font_override("font", Fonts.emoji())
	l.add_theme_font_size_override("font_size", int(size * 0.85))
	l.add_theme_color_override("font_color", UiArt.C_GOLD)
	l.custom_minimum_size = Vector2(size, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l

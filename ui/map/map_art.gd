class_name MapArt
extends RefCounted
## Рисунки поселений на карте: цветные SVG-миниатюры построек (вид
## спереди-сверху, с тёмным контуром, как на рисованной карте). Постройка
## выбирает рисунок полем map_sprite в данных; без него — по району и роду.
## Мод может добавить или заменить рисунок: MapArt.register(name, w, h, size, body).
##
## Рисунок: viewBox w×h, основание — середина нижнего края; size — высота на
## карте (в пикселях карты). Метки: smoke — трубы (дым), lamp — огонь или
## свет [точка, цвет], flag — верх древка (флаг цвета державы), hub — ось
## мельничных крыльев.

const INK := "#2b1d10"

const PAL := {
	"stone": "#d6cbb0", "stone2": "#b3a68a", "stone3": "#958a76", "plaster": "#efe4c6",
	"timber": "#6b4a2b", "roof": "#b4503a", "roof2": "#8e3c2b", "slate": "#5f6874",
	"slate2": "#474e58", "thatch": "#cfa65a", "thatch2": "#a8843e", "wood": "#8a5a32",
	"dark": "#33241a", "door": "#5a3a20", "gold": "#e8b84a", "gold2": "#ffe08a",
	"green": "#5f8a3a", "green2": "#3f6428", "red": "#c0483a", "blue": "#3a6aa8",
	"white": "#f2ede0", "glass": "#f2d27a", "copper": "#5a9a8a", "ink": INK,
}

## name → {w, h, size, body, smoke, lamp, flag, hub}
static var SPRITES := {}
static var _tex := {}
static var _shadow: Texture2D
static var _glow: Texture2D
static var _ready := false

const BUCKETS := [12, 16, 24, 32, 48, 64, 96, 128, 192]


## Зубцы стены по верху: от x0 до x1 на высоте y, зубец w×h.
static func _teeth(x0: float, x1: float, y: float, w: float, h: float, fill: String) -> String:
	var d := "M%.1f %.1f" % [x0, y]
	var x := x0
	var up := true
	while x < x1 - 0.01:
		var nx := minf(x + w, x1)
		if up:
			d += " V%.1f H%.1f V%.1f" % [y - h, nx, y]
		else:
			d += " H%.1f" % nx
		x = nx
		up = not up
	return '<path d="%s Z" fill="%s"/>' % [d, fill]


static func _win(x: float, y: float, w: float = 2.2, h: float = 3.0, fill: String = "{dark}") -> String:
	return '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % [x, y, w, h, fill]


static func _arch(x: float, y: float, w: float, h: float, fill: String = "{dark}") -> String:
	var r := w / 2.0
	return '<path d="M%.1f %.1f V%.1f A%.1f %.1f 0 0 1 %.1f %.1f V%.1f Z" fill="%s"/>' % [x, y + h, y + r, r, r, x + w, y + r, y + h, fill]


static func _stall(x: float, col: String) -> String:
	return ('<path d="M%.1f 21 V15 M%.1f 21 V15" fill="none" stroke-width="0.8"/><rect x="%.1f" y="15" width="10" height="5" fill="{wood}"/>' % [x + 1.5, x + 10.5, x + 1]
		+ '<path d="M%.1f 15 L%.1f 9 H%.1f L%.1f 15 Z" fill="%s"/>' % [x - 0.5, x + 2, x + 10, x + 12.5, col]
		+ '<path d="M%.1f 9 L%.1f 15 M%.1f 9 V15 M%.1f 9 L%.1f 15" fill="none" stroke="#f2e6c8" stroke-width="1.1"/>' % [x + 4, x + 3.3, x + 6, x + 8, x + 8.7]
		+ '<circle cx="%.1f" cy="14" r="1" fill="{gold}"/><circle cx="%.1f" cy="14" r="1" fill="{red}"/>' % [x + 4, x + 7])


static func register(name: String, w: float, h: float, size: float, body: String, meta: Dictionary = {}) -> void:
	_init_all()
	var spec := {"w": w, "h": h, "size": size, "body": body.format(PAL)}
	spec.merge(meta, true)
	SPRITES[name] = spec
	for k in _tex.keys():
		if str(k).begins_with(name + "@"):
			_tex.erase(k)


static func _add(name: String, w: float, h: float, size: float, body: String, meta: Dictionary = {}) -> void:
	var spec := {"w": w, "h": h, "size": size, "body": body.format(PAL)}
	spec.merge(meta, true)
	SPRITES[name] = spec


static func has(name: String) -> bool:
	_init_all()
	return SPRITES.has(name)


static func spec(name: String) -> Dictionary:
	_init_all()
	return SPRITES.get(name, SPRITES.house)


## Размер из BUCKETS, ближайший сверху к px.
static func bucket(px: float) -> int:
	if px <= 16.0:
		return 12 if px <= 12.0 else 16
	if px <= 32.0:
		return 24 if px <= 24.0 else 32
	if px <= 64.0:
		return 48 if px <= 48.0 else 64
	if px <= 128.0:
		return 96 if px <= 96.0 else 128
	return 192


## Текстура рисунка высотой не меньше px (берётся ближайший размер из BUCKETS).
static func texture(name: String, px: float) -> Texture2D:
	_init_all()
	var b := bucket(px)
	var key := "%s@%d" % [name, b]
	if _tex.has(key):
		return _tex[key]
	var sp: Dictionary = SPRITES.get(name, SPRITES.house)
	var hh: float = sp.h
	var ww: float = sp.w
	var k := b * 2.0 / hh
	var sw := maxf(0.8, hh / 34.0)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %s %s"><g stroke="%s" stroke-width="%.2f" stroke-linejoin="round" stroke-linecap="round">%s</g></svg>' % [
		ceili(ww * k), ceili(hh * k), str(ww), str(hh), INK, sw, sp.body]
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	img.resize(maxi(1, ceili(ww * k / 2.0)), b, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex


## Мягкая тень под постройкой.
static func shadow() -> Texture2D:
	if _shadow == null:
		var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 64:
				var d := Vector2((x - 31.5) / 32.0, (y - 15.5) / 16.0).length()
				img.set_pixel(x, y, Color(0.05, 0.03, 0.01, clampf(1.0 - d, 0.0, 1.0) * 0.55))
		_shadow = ImageTexture.create_from_image(img)
	return _shadow


## Золотое сияние под великой стройкой.
static func glow() -> Texture2D:
	if _glow == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1.0, 0.86, 0.45, a * a * 0.8))
		_glow = ImageTexture.create_from_image(img)
	return _glow


## Рисунок постройки: map_sprite из данных, иначе по району и роду.
static func for_building(bd: Variant) -> String:
	_init_all()
	if bd == null:
		return "house"
	var s: Variant = bd.get("map_sprite")
	if s is String and (s == "none" or SPRITES.has(s)):
		return s
	var cat := str(bd.get("category", ""))
	match str(bd.get("district", "")):
		"market":
			return "stalls" if cat == "economy" else "inn"
		"temple_quarter":
			return "chapel"
		"fields":
			return "barn"
		"crafts":
			return "smithy"
		"harbor":
			return "warehouse"
	match cat:
		"fortification":
			return "tower"
		"military":
			return "hall"
		"faith":
			return "chapel"
		"arcane":
			return "mage_tower"
	return "hall"


static func _init_all() -> void:
	if _ready:
		return
	_ready = true
	# ------------------------------------------------ жильё
	_add("house", 32, 28, 3.2,
		'<path d="M7 27 V16 H25 V27 Z" fill="{plaster}"/><path d="M7 21 H25" fill="none" stroke-width="0.6"/>'
		+ '<path d="M4.5 17 L9.5 8.5 H22.5 L27.5 17 Z" fill="{roof}"/><path d="M10 9.4 H22 L23 11 H9 Z" fill="#d06e52" stroke="none"/>'
		+ _win(11, 21, 3.6, 6, "{door}") + _win(18, 18.2, 3.4, 2.6))
	_add("cottage", 28, 28, 3.0,
		'<rect x="18" y="7" width="2.6" height="7" fill="{stone3}"/><path d="M7 27 V17 H21 V27 Z" fill="#e2d2a6"/>'
		+ '<path d="M4 18 L14 7.5 L24 18 Z" fill="{thatch}"/><path d="M14 8.5 L22.5 17.5 H19 Z" fill="{thatch2}" stroke="none"/>'
		+ _win(12.2, 21, 3.6, 6, "{door}"))
	_add("townhouse", 24, 34, 3.9,
		'<path d="M5 33 V16 H19 V33 Z" fill="{plaster}"/><path d="M5 24.5 H19" fill="none" stroke="{timber}" stroke-width="1"/>'
		+ '<path d="M3 17 L12 5 L21 17 Z" fill="{roof2}"/>' + _win(7.5, 19, 2.6, 3) + _win(13.9, 19, 2.6, 3)
		+ _win(7.5, 27, 2.6, 3) + _win(13.5, 27, 3.6, 6, "{door}"))
	_add("hall", 44, 26, 3.6,
		'<path d="M5 25 V14 H39 V25 Z" fill="#e6d6b0"/><path d="M3 15 L8 6 H36 L41 15 Z" fill="#7a5a3a"/>'
		+ _win(19.5, 18, 5, 7, "{door}") + _win(9, 17, 3, 3) + _win(32, 17, 3, 3))
	# ------------------------------------------------ детинец
	_add("keep", 30, 42, 7.0,
		'<path d="M15 10 V1.5" fill="none" stroke-width="1"/>'
		+ '<rect x="6" y="13" width="18" height="28" fill="{stone}"/><rect x="18" y="13" width="6" height="28" fill="{stone2}" stroke="none"/>'
		+ _teeth(6, 24, 13, 2.6, 3, "{stone}") + '<path d="M6 16.5 H24" fill="none" stroke-width="0.7"/>'
		+ _arch(12.5, 34, 5, 7) + _win(10, 20, 1.8, 4) + _win(18.2, 20, 1.8, 4) + _win(14.1, 26, 1.8, 4),
		{"flag": Vector2(15, 1.5)})
	_add("castle", 56, 46, 9.0,
		'<path d="M28 8 V0.5" fill="none" stroke-width="1"/>'
		+ '<rect x="19" y="10" width="18" height="26" fill="{stone}"/><rect x="31" y="10" width="6" height="26" fill="{stone2}" stroke="none"/>'
		+ _teeth(19, 37, 10, 2.6, 3, "{stone}") + _win(23, 16, 1.8, 4) + _win(32, 16, 1.8, 4)
		+ '<rect x="11" y="29" width="34" height="16" fill="#cdc0a2"/>' + _teeth(11, 45, 29, 2.8, 2.6, "#cdc0a2")
		+ _arch(24.5, 35, 7, 10)
		+ '<rect x="3" y="20" width="10" height="25" fill="{stone}"/><path d="M1.5 21 L8 9 L14.5 21 Z" fill="{slate}"/>' + _win(7, 27, 2, 4)
		+ '<rect x="43" y="20" width="10" height="25" fill="{stone2}"/><path d="M41.5 21 L48 9 L54.5 21 Z" fill="{slate2}"/>' + _win(47, 27, 2, 4),
		{"flag": Vector2(28, 0.5)})
	_add("tower", 20, 40, 5.0,
		'<rect x="4" y="14" width="12" height="25" fill="{stone}"/><rect x="12" y="14" width="4" height="25" fill="{stone2}" stroke="none"/>'
		+ '<path d="M2.5 15 L10 2 L17.5 15 Z" fill="{slate}"/>' + _win(9, 20, 2, 4) + _win(9, 29, 2, 4))
	_add("tower_small", 14, 22, 3.0,
		'<rect x="2" y="7" width="10" height="14" fill="{stone2}"/>' + _teeth(2, 12, 7, 2, 2.2, "{stone2}") + _win(6, 11, 2, 3))
	_add("gatehouse", 30, 28, 3.8,
		'<rect x="9" y="11" width="12" height="16" fill="{stone2}"/>' + _teeth(9, 21, 11, 2, 2, "{stone2}")
		+ '<rect x="2" y="8" width="9" height="19" fill="{stone}"/>' + _teeth(2, 11, 8, 1.8, 2.2, "{stone}")
		+ '<rect x="19" y="8" width="9" height="19" fill="{stone}"/>' + _teeth(19, 28, 8, 1.8, 2.2, "{stone}")
		+ _arch(11.5, 17, 7, 10) + '<path d="M13 19 V27 M15 18 V27 M17 19 V27" fill="none" stroke="#8a8a80" stroke-width="0.6"/>')
	_add("armory", 32, 28, 3.8,
		'<path d="M5 27 V14 H27 V27 Z" fill="#cfc3a6"/><path d="M3 15 L8 6 H24 L29 15 Z" fill="{slate}"/>'
		+ _win(13.5, 19, 5, 8, "{door}") + '<circle cx="16" cy="11" r="2" fill="{red}"/><path d="M8 18 L11 21 M11 18 L8 21 M21 18 L24 21 M24 18 L21 21" fill="none" stroke="#c8c8c0" stroke-width="0.9"/>')
	_add("great_hall", 48, 34, 5.0,
		'<path d="M4 33 V18 H44 V33 Z" fill="#d8cbab"/><path d="M2 19 L10 6 H38 L46 19 Z" fill="{roof2}"/>'
		+ _arch(21, 23, 6, 10) + _win(8, 23, 2.6, 4.5) + _win(14, 23, 2.6, 4.5) + _win(31.4, 23, 2.6, 4.5) + _win(37.4, 23, 2.6, 4.5)
		+ '<path d="M18 19 V28 L19.5 26.5 L21 28 V19 Z" fill="{red}"/><path d="M27 19 V28 L28.5 26.5 L30 28 V19 Z" fill="{blue}"/>')
	_add("longhouse", 46, 24, 3.4,
		'<path d="M6 23 V14 H40 V23 Z" fill="#8a6a44"/><path d="M2 15 Q23 1 44 15 Z" fill="#5a4630"/>'
		+ '<path d="M2 15 L0.8 9.5 M44 15 L45.2 9.5" fill="none" stroke-width="1.4"/>' + _win(20.5, 17, 5, 6, "#2e2014")
		+ '<circle cx="12" cy="18" r="1.6" fill="{red}"/><circle cx="34" cy="18" r="1.6" fill="{gold}"/>')
	_add("yard", 48, 22, 3.0,
		'<ellipse cx="24" cy="14" rx="22" ry="7" fill="#cdb27a" stroke="{timber}" stroke-width="1.2"/>'
		+ '<path d="M6 14 H42" fill="none" stroke="{wood}" stroke-width="1.2"/>'
		+ '<path d="M6 14 V3 M42 14 V3" fill="none" stroke-width="1"/><path d="M6 3 H11 L9.5 5 L11 7 H6 Z" fill="{red}"/><path d="M42 3 H37 L38.5 5 L37 7 H42 Z" fill="{blue}"/>')
	_add("gallows", 22, 26, 3.2,
		'<rect x="2" y="22.5" width="18" height="3" fill="{wood}"/><path d="M5 23 V4 H16 M5 9 L9 4 M14.5 4 V8.5" fill="none" stroke="#5a3a20" stroke-width="2"/>'
		+ '<ellipse cx="14.5" cy="10.5" rx="1.4" ry="1.8" fill="none" stroke="{thatch}" stroke-width="0.8"/>')
	_add("jail", 26, 24, 3.0,
		'<rect x="3" y="10" width="20" height="13" fill="{stone3}"/>' + _teeth(3, 23, 10, 2.5, 2.4, "{stone3}")
		+ '<rect x="10" y="14" width="6" height="5" fill="{ink}"/><path d="M12 14 V19 M14 14 V19" fill="none" stroke="#9a9a92" stroke-width="0.7"/>')
	_add("lodge", 32, 28, 3.6,
		'<path d="M6 27 V16 H26 V27 Z" fill="#7a5a3a"/><path d="M3 17 L16 5 L29 17 Z" fill="#4f6a3a"/>'
		+ _win(13.5, 20, 5, 7, "#2e2014") + '<ellipse cx="16" cy="12.5" rx="2.6" ry="1.6" fill="{plaster}"/><circle cx="16" cy="12.5" r="0.9" fill="{ink}"/>')
	_add("mage_tower", 20, 50, 8.0,
		'<path d="M5 49 L6.5 16 H13.5 L15 49 Z" fill="#9a90a8"/><path d="M3.5 17 L10 2 L16.5 17 Z" fill="#5a3f8a"/>'
		+ '<circle cx="10" cy="2.5" r="1.4" fill="#d6c2ff"/>' + _win(9, 23, 2, 4, "#d6c2ff") + _win(9, 33, 2, 4),
		{"lamp": [Vector2(10, 2.5), Color("#b48cff")]})
	_add("beacon", 20, 40, 5.5,
		'<rect x="4" y="12" width="12" height="27" fill="{stone3}"/><path d="M3 12 H17 V9 H3 Z" fill="#6f6a64"/>'
		+ '<path d="M6 9 C6 5 9 5 10 1.5 C11 5 14 5 14 9 Z" fill="#f0a030"/>' + _win(9, 18, 2, 4),
		{"lamp": [Vector2(10, 5.5), Color("#ff9a30")]})
	# ------------------------------------------------ торг
	_add("stalls", 44, 22, 3.0, _stall(2.0, "{red}") + _stall(16.0, "{blue}") + _stall(30.0, "{green}"))
	_add("town_hall", 36, 48, 7.0,
		'<path d="M4 47 V24 H32 V47 Z" fill="#e2d4b2"/><path d="M14 27 V8 H22 V27 Z" fill="#d4c6a6"/>'
		+ '<path d="M12.5 9 L18 1 L23.5 9 Z" fill="{slate}"/><circle cx="18" cy="13" r="2" fill="{white}"/>'
		+ '<path d="M2 25 L8 16 H28 L34 25 Z" fill="{roof2}"/>'
		+ _win(7, 30, 2.6, 5) + _win(12, 30, 2.6, 5) + _win(21.4, 30, 2.6, 5) + _win(26.4, 30, 2.6, 5) + _arch(15, 38, 6, 9),
		{"flag": Vector2(18, 1)})
	_add("guild", 30, 44, 5.5,
		'<path d="M4 43 V18 H6 V14 H9 V10 H12 V6 H18 V10 H21 V14 H24 V18 H26 V43 Z" fill="#c07a52"/>'
		+ _win(13.5, 10, 3, 4) + _win(8.5, 20, 3, 4) + _win(13.5, 20, 3, 4) + _win(18.5, 20, 3, 4)
		+ _win(8.5, 28, 3, 4) + _win(18.5, 28, 3, 4) + _win(13, 35, 4, 8, "{door}") + '<circle cx="23" cy="32" r="2.2" fill="{gold}"/>')
	_add("tents", 46, 28, 3.8,
		'<path d="M14 27 L23 5 L32 27 Z" fill="#efe4c6"/><path d="M23 5 L19 27 M23 5 L27 27" fill="none" stroke="{blue}" stroke-width="1.6"/>'
		+ '<path d="M23 5 V1 L26.5 2.5 L23 4" fill="{blue}"/>'
		+ '<path d="M2 27 L9 10 L16 27 Z" fill="#efe4c6"/><path d="M9 10 L6 27 M9 10 L12 27" fill="none" stroke="{red}" stroke-width="1.5"/>'
		+ '<path d="M30 27 L37 11 L44 27 Z" fill="#efe4c6"/><path d="M37 11 L34 27 M37 11 L40 27" fill="none" stroke="{green}" stroke-width="1.5"/>'
		+ '<path d="M37 11 V7 L40 8.5 L37 10" fill="{gold}"/>')
	_add("counting_house", 28, 30, 4.0,
		'<path d="M4 29 V14 H24 V29 Z" fill="#dacdb0"/><path d="M2 15 L14 6 L26 15 Z" fill="{slate}"/>'
		+ '<circle cx="14" cy="11.5" r="2.1" fill="{gold}"/>' + _win(11.5, 21, 5, 8, "{door}") + _win(6, 18, 3, 3) + _win(19, 18, 3, 3))
	_add("inn", 40, 30, 4.2,
		'<path d="M4 29 V12 H36 V29 Z" fill="#e8dbb8"/><path d="M4 20 H36" fill="none" stroke="{timber}" stroke-width="0.9"/>'
		+ '<path d="M2 13 L7 4 H33 L38 13 Z" fill="{roof2}"/>' + _arch(16, 21, 8, 8)
		+ _win(7, 14.5, 3, 3) + _win(13, 14.5, 3, 3) + _win(24, 14.5, 3, 3) + _win(30, 14.5, 3, 3)
		+ '<path d="M36 15 H39.5" fill="none" stroke-width="0.8"/><rect x="37" y="15.5" width="2.6" height="3.2" fill="{gold}"/>')
	_add("bath", 32, 28, 3.8,
		'<path d="M12 9 C10.5 7 13.5 6 12 3.5 M16 8.5 C14.5 6.5 17.5 5.5 16 3 M20 9 C18.5 7 21.5 6 20 3.5" fill="none" stroke="{white}" stroke-opacity="0.8" stroke-width="1"/>'
		+ '<path d="M4 27 V16 H28 V27 Z" fill="#e2d6b8"/><path d="M8 16.5 A8 6 0 0 1 24 16.5 Z" fill="#b8704a"/>' + _arch(13.5, 20, 5, 7))
	_add("mint", 34, 32, 4.6,
		'<path d="M3 31 V27 H31 V31 Z" fill="#cfc3a6"/><path d="M5 27 V14 H29 V27 Z" fill="#a89c84"/>'
		+ '<rect x="6" y="14" width="3" height="13" fill="#f2ead6"/><rect x="12" y="14" width="3" height="13" fill="#f2ead6"/>'
		+ '<rect x="19" y="14" width="3" height="13" fill="#f2ead6"/><rect x="25" y="14" width="3" height="13" fill="#f2ead6"/>'
		+ '<path d="M3 14.5 L17 6 L31 14.5 Z" fill="{gold}"/><circle cx="17" cy="11.2" r="1.8" fill="{gold2}"/>')
	# ------------------------------------------------ храмы
	_add("church", 30, 44, 6.5,
		'<rect x="18" y="16" width="8" height="27" fill="{stone}"/><path d="M16.5 17 L22 3 L27.5 17 Z" fill="{slate}"/>'
		+ '<circle cx="22" cy="3" r="1.6" fill="{gold}"/>'
		+ '<path d="M2 43 V27 H18 V43 Z" fill="#e2d6b8"/><path d="M0.5 28 L9.5 19 L18.5 28 Z" fill="{roof2}"/>'
		+ '<circle cx="10" cy="31" r="2" fill="{glass}"/>' + _arch(19.5, 34, 5, 9) + _win(21, 21, 2, 4) + _win(5, 34, 2, 5) + _win(13, 34, 2, 5))
	_add("chapel", 22, 32, 4.5,
		'<path d="M9.5 9 V4 H12.5 V9" fill="{stone}"/><circle cx="11" cy="2.6" r="1.3" fill="{gold}"/>'
		+ '<path d="M4 31 V17 H18 V31 Z" fill="#e2d6b8"/><path d="M2 18 L11 8 L20 18 Z" fill="{roof2}"/>' + _arch(9, 24, 4, 7))
	_add("cathedral", 48, 56, 9.0,
		'<rect x="17" y="24" width="14" height="31" fill="#e6dcc4"/><path d="M15.5 25 L24 13 L32.5 25 Z" fill="{stone}"/>'
		+ '<circle cx="24" cy="31" r="3.6" fill="{gold}"/><circle cx="24" cy="31" r="1.4" fill="{blue}"/>' + _arch(20, 41, 8, 14)
		+ '<rect x="6" y="18" width="11" height="37" fill="{stone}"/><path d="M4.5 19 L11.5 2 L18.5 19 Z" fill="{slate}"/>'
		+ '<rect x="31" y="18" width="11" height="37" fill="{stone2}"/><path d="M29.5 19 L36.5 2 L43.5 19 Z" fill="{slate2}"/>'
		+ '<circle cx="11.5" cy="2" r="1.4" fill="{gold}"/><circle cx="36.5" cy="2" r="1.4" fill="{gold}"/>'
		+ _win(10.5, 24, 2, 6) + _win(10.5, 36, 2, 6) + _win(35.5, 24, 2, 6) + _win(35.5, 36, 2, 6))
	_add("monastery", 50, 34, 5.0,
		'<rect x="31" y="8" width="7" height="18" fill="{stone}"/><path d="M29.5 9 L34.5 1 L39.5 9 Z" fill="{slate}"/>'
		+ '<path d="M14 26 V15 H31 V26 Z" fill="#e2d6b8"/><path d="M12 16 L22.5 8 L33 16 Z" fill="{roof2}"/>'
		+ '<path d="M3 26 V17 H14 V26 Z" fill="{plaster}"/><path d="M1.5 18 L8.5 11 L15.5 18 Z" fill="{thatch}"/>'
		+ '<rect x="1" y="25" width="48" height="8" fill="#cfc3a6"/>' + _arch(22, 26, 5, 7) + _win(35, 14, 2, 4))
	_add("infirmary", 36, 26, 3.6,
		'<path d="M4 25 V14 H32 V25 Z" fill="{plaster}"/><path d="M2 15 L7 7 H29 L34 15 Z" fill="{thatch}"/>'
		+ _win(15.5, 18, 5, 7, "{door}") + _win(7, 17.5, 3, 3) + _win(26, 17.5, 3, 3) + '<circle cx="18" cy="11" r="1.7" fill="{red}"/>')
	_add("library", 28, 36, 5.0,
		'<path d="M19 35 V12 H26 V35 Z" fill="#cfc3a6"/><path d="M18 13 L22.5 4 L27 13 Z" fill="{roof2}"/>'
		+ '<path d="M3 35 V16 H20 V35 Z" fill="#dacdb0"/><path d="M1.5 17 L11.5 7 L21.5 17 Z" fill="{slate}"/>'
		+ _arch(8.5, 21, 6, 9, "{glass}") + _win(21.5, 18, 2, 4))
	_add("reliquary", 24, 30, 4.2,
		'<path d="M12 10 V5" fill="none" stroke-width="1"/><circle cx="12" cy="4" r="1.5" fill="{gold2}"/>'
		+ '<path d="M5 29 V17 H19 V29 Z" fill="#e6dcc4"/><path d="M4 17.5 A8 8 0 0 1 20 17.5 Z" fill="{gold}"/>' + _arch(9.5, 22, 5, 7))
	_add("belfry", 18, 46, 6.2,
		'<rect x="4" y="14" width="10" height="31" fill="{stone}"/><path d="M3 15 L9 3 L15 15 Z" fill="{roof2}"/>'
		+ _arch(6, 18, 6, 7, "{ink}") + '<path d="M7.2 24 A1.8 2.4 0 0 1 10.8 24 Z" fill="{gold}"/>' + _win(8, 32, 2, 4))
	_add("sun_school", 36, 30, 4.2,
		'<path d="M4 29 V14 H32 V29 Z" fill="{plaster}"/><path d="M2 15 L18 5 L34 15 Z" fill="{slate}"/>'
		+ '<circle cx="18" cy="11" r="2.3" fill="{gold}"/>' + _win(7, 18, 3, 3) + _win(12, 18, 3, 3) + _win(21, 18, 3, 3) + _win(26, 18, 3, 3)
		+ _win(15.5, 22, 5, 7, "{door}"))
	_add("onion", 26, 44, 6.0,
		'<path d="M13 3 V0.5" fill="none" stroke-width="1"/><path d="M8 22 V16 H18 V22 Z" fill="#e6dcc4"/>'
		+ '<path d="M13 3 C16 6 20 9 18.5 16.5 H7.5 C6 9 10 6 13 3 Z" fill="{copper}"/>'
		+ '<path d="M5 43 V22 H21 V43 Z" fill="#e6dcc4"/>' + _arch(10.5, 33, 5, 10) + _win(8, 25, 2, 4) + _win(16, 25, 2, 4))
	_add("stones", 32, 24, 3.0,
		'<path d="M2 23 L3 13 L6.5 12 L7.5 23 Z" fill="#9a948a"/><path d="M24.5 23 L25.5 12.5 L29 13 L30 23 Z" fill="#8f8a80"/>'
		+ '<rect x="15" y="4" width="2.6" height="19" fill="{timber}"/><circle cx="16.3" cy="5" r="2.4" fill="{plaster}"/>'
		+ '<circle cx="15.5" cy="4.7" r="0.6" fill="{ink}"/><circle cx="17.1" cy="4.7" r="0.6" fill="{ink}"/>'
		+ '<path d="M8.5 23 L9.5 15 L12.5 14.5 L13 23 Z" fill="#a8a296"/><path d="M19 23 L19.5 14.5 L22.5 15 L23.5 23 Z" fill="#a8a296"/>')
	_add("pillared", 34, 30, 4.2,
		'<path d="M3 29 V26 H31 V29 Z" fill="#cfc3a6"/><path d="M5 26 V14 H29 V26 Z" fill="{stone3}"/>'
		+ '<rect x="6" y="14" width="3" height="12" fill="#e6dcc4"/><rect x="12" y="14" width="3" height="12" fill="#e6dcc4"/>'
		+ '<rect x="19" y="14" width="3" height="12" fill="#e6dcc4"/><rect x="25" y="14" width="3" height="12" fill="#e6dcc4"/>'
		+ '<path d="M3 14.5 L17 6 L31 14.5 Z" fill="#cfc3a6"/>')
	_add("mausoleum", 26, 26, 3.6,
		'<path d="M4 25 V12 H22 V25 Z" fill="#8f8a84"/><path d="M2.5 12.5 L13 5 L23.5 12.5 Z" fill="#6f6a64"/>'
		+ _arch(10, 15, 6, 10, "#1a120a") + '<circle cx="13" cy="9.6" r="1.5" fill="{plaster}"/>')
	# ------------------------------------------------ угодья
	_add("windmill", 24, 40, 5.5,
		'<path d="M6 39 L8 14 H16 L18 39 Z" fill="#e2d4b2"/><path d="M6.5 15 L12 7 L17.5 15 Z" fill="{wood}"/>' + _win(10, 31, 4, 8, "{door}"),
		{"hub": Vector2(12, 12)})
	_add("barn", 36, 30, 4.2,
		'<path d="M5 29 V15 H31 V29 Z" fill="#a8452f"/><path d="M3 16 L8 8 L18 4 L28 8 L33 16 Z" fill="{timber}"/>'
		+ '<path d="M13 29 V19 H23 V29 Z" fill="{door}"/><path d="M13 19 L23 29 M23 19 L13 29" fill="none" stroke="#e6d6b0" stroke-width="0.8"/>')
	_add("stable", 40, 24, 3.4,
		'<path d="M4 23 V13 H36 V23 Z" fill="#9a6a40"/><path d="M2 14 L6 7 H34 L38 14 Z" fill="{thatch}"/>'
		+ _win(7, 16, 4, 7, "{dark}") + _win(14, 16, 4, 7, "{dark}") + _win(22, 16, 4, 7, "{dark}") + _win(29, 16, 4, 7, "{dark}"))
	_add("depot", 38, 22, 3.0,
		'<rect x="6" y="7" width="6" height="5" fill="#b48a5a"/><rect x="3" y="12" width="8" height="9" fill="#a8784a"/><rect x="11" y="15" width="6" height="6" fill="#b48a5a"/>'
		+ '<path d="M20 14 C20 7 34 7 34 14 Z" fill="#e8dcc0"/><rect x="19" y="14" width="16" height="4" fill="{wood}"/>'
		+ '<circle cx="23" cy="19.5" r="2.3" fill="{door}"/><circle cx="31" cy="19.5" r="2.3" fill="{door}"/>')
	_add("apple", 14, 18, 2.2,
		'<rect x="6.2" y="10" width="1.8" height="7.5" fill="{timber}"/><circle cx="7" cy="7.5" r="5.8" fill="{green}"/>'
		+ '<circle cx="5" cy="6.2" r="0.9" fill="{red}" stroke="none"/><circle cx="8.8" cy="8.4" r="0.9" fill="{red}" stroke="none"/><circle cx="6.5" cy="9.8" r="0.9" fill="{red}" stroke="none"/>')
	_add("pine", 12, 22, 2.8,
		'<rect x="5.2" y="17" width="1.6" height="4.5" fill="{timber}"/><path d="M6 1 L11 10 H8.5 L11.5 17.5 H0.5 L3.5 10 H1 Z" fill="{green2}"/>')
	_add("oak", 16, 18, 2.4,
		'<rect x="7.1" y="10" width="1.8" height="7.5" fill="{timber}"/><circle cx="5.5" cy="8" r="4.5" fill="#6a9440"/><circle cx="10.5" cy="8" r="4.5" fill="#5a843a"/><circle cx="8" cy="5" r="4.5" fill="#6f9a44"/>')
	_add("sheep", 10, 8, 0.9,
		'<ellipse cx="5" cy="4.5" rx="4" ry="2.6" fill="{white}"/><circle cx="8.6" cy="3.6" r="1.3" fill="{dark}"/><path d="M3 7 V7.8 M6.5 7 V7.8" fill="none" stroke-width="0.8"/>')
	_add("horse", 14, 10, 1.2,
		'<path d="M2 5 C2 3 4 3 9 3 L11 1 L13 2.5 L11.5 4.5 L10.5 6 V9 H9.5 V6.5 H4 V9 H3 V6.5 C2.2 6.5 2 6 2 5 Z" fill="{wood}"/>')
	# ------------------------------------------------ слобода
	_add("smithy", 34, 28, 3.8,
		'<rect x="22" y="3" width="5" height="14" fill="#8f8a84"/><path d="M4 27 V14 H30 V27 Z" fill="#a8845a"/>'
		+ '<path d="M2 15 L7 8 H29 L32 15 Z" fill="#5a4630"/><rect x="8" y="18" width="10" height="9" fill="{ink}"/><rect x="10" y="22" width="6" height="5" fill="#f08a30"/>',
		{"smoke": [Vector2(24.5, 3)]})
	_add("stoneyard", 38, 24, 3.2,
		'<rect x="6" y="10" width="7" height="5" fill="#cfc3a6"/><rect x="3" y="15" width="9" height="8" fill="{stone}"/><rect x="12" y="17" width="7" height="6" fill="{stone2}"/>'
		+ '<circle cx="28" cy="16" r="6" fill="none" stroke="{wood}" stroke-width="1.4"/><path d="M28 22 V3 L36 6 M36 6 V12" fill="none" stroke="{wood}" stroke-width="1.3"/>')
	_add("jeweler", 26, 32, 4.2,
		'<path d="M5 31 V14 H21 V31 Z" fill="#e2c9a0"/><path d="M3 15 L13 5 L23 15 Z" fill="{roof2}"/>'
		+ '<rect x="7" y="18" width="12" height="5" fill="{gold}"/>' + _win(11, 24.5, 4, 6.5, "{door}"))
	_add("weavers", 34, 28, 3.8,
		'<path d="M3 27 V14 H19 V27 Z" fill="{plaster}"/><path d="M1.5 15 L11 6 L20.5 15 Z" fill="{thatch}"/>' + _win(8.5, 20, 4, 7, "{door}")
		+ '<path d="M19.5 27 V11 M33 27 V11 M19.5 12 H33" fill="none" stroke="{timber}" stroke-width="0.9"/>'
		+ '<rect x="21" y="12" width="3.5" height="8" fill="{blue}"/><rect x="25.5" y="12" width="3.5" height="9" fill="{red}"/><rect x="30" y="12" width="2.6" height="7" fill="#d8b040"/>')
	_add("tannery", 36, 24, 3.2,
		'<path d="M3 23 V13 H17 V23 Z" fill="#a8845a"/><path d="M1.5 14 L10 6 L18.5 14 Z" fill="#7a5a3a"/>' + _win(8, 17, 4, 6, "{dark}")
		+ '<ellipse cx="23" cy="19.5" rx="3.6" ry="2.2" fill="#7a3a24"/><ellipse cx="31" cy="19.5" rx="3.6" ry="2.2" fill="#a88a3a"/><ellipse cx="27" cy="15" rx="3.2" ry="1.9" fill="#6a2a20"/>')
	_add("trebuchet", 36, 36, 4.6,
		'<path d="M4 34 H32" fill="none" stroke="{timber}" stroke-width="2.2"/><path d="M10 34 L18 14 L26 34" fill="none" stroke="{wood}" stroke-width="2"/>'
		+ '<path d="M4 5 L31 22" fill="none" stroke="{wood}" stroke-width="1.8"/><rect x="27.5" y="21" width="6" height="6" fill="#6f6a64"/>')
	_add("mine", 36, 28, 3.8,
		'<path d="M1 27 L8 12 L15 8 L23 10 L30 15 L35 27 Z" fill="#9a8f80"/><path d="M15 8 L23 10 L26 16 L17 13 Z" fill="#b0a696" stroke="none"/>'
		+ _arch(13, 18, 10, 9, "#1e150c") + '<path d="M13 27 V18.5 H23 V27" fill="none" stroke="{wood}" stroke-width="1.5"/>'
		+ '<rect x="25" y="22" width="7" height="3.5" fill="{timber}"/><circle cx="27" cy="26.3" r="1"/><circle cx="30" cy="26.3" r="1"/>'
		+ '<circle cx="27" cy="21.6" r="0.9" fill="{gold}" stroke="none"/><circle cx="29.5" cy="21.4" r="0.9" fill="{gold}" stroke="none"/>')
	# ------------------------------------------------ пристань
	_add("boat", 20, 20, 3.0,
		'<path d="M10 15 V2" fill="none" stroke-width="1"/><path d="M5 4 Q10 6 15 4 L15.5 11.5 Q10 13.5 4.5 11.5 Z" fill="#efe6d0"/>'
		+ '<path d="M5 7.8 Q10 9.8 15.2 7.8" fill="none" stroke="{red}" stroke-width="1.3"/><path d="M2 14 H18 L15.5 18.5 H4.5 Z" fill="#7a5030"/>')
	_add("skiff", 14, 8, 1.4,
		'<path d="M1 3 H13 L11 7 H3 Z" fill="#8a6038"/><path d="M4 3 L2 0.5 M10 3 L12 0.5" fill="none" stroke-width="0.7"/>')
	_add("warehouse", 38, 26, 3.6,
		'<path d="M4 25 V12 H30 V25 Z" fill="#b08a5a"/><path d="M2 13 L7 5 H27 L32 13 Z" fill="{timber}"/><rect x="13" y="17" width="8" height="8" fill="#4a3220"/>'
		+ '<path d="M31 25 V8 H37 V14" fill="none" stroke="{wood}" stroke-width="1.3"/><circle cx="34" cy="23" r="2" fill="{wood}"/>')
	_add("fish_rack", 30, 18, 2.4,
		'<path d="M3 17 V6 M15 17 V6 M27 17 V6 M2 6.5 H28" fill="none" stroke="{timber}" stroke-width="1.2"/>'
		+ '<ellipse cx="6.5" cy="10" rx="1" ry="2.6" fill="#c8d0d4"/><ellipse cx="10" cy="10" rx="1" ry="2.6" fill="#c8d0d4"/>'
		+ '<ellipse cx="19" cy="10" rx="1" ry="2.6" fill="#c8d0d4"/><ellipse cx="22.5" cy="10" rx="1" ry="2.6" fill="#c8d0d4"/>')
	_add("salt_hut", 26, 20, 2.6,
		'<path d="M2 19 V12 H11 V19 Z" fill="#c8b08a"/><path d="M1 12.5 L6.5 7 L12 12.5 Z" fill="{thatch}"/>'
		+ '<path d="M13 19 L17 11 L21 19 Z" fill="{white}"/><path d="M18 19 L21.5 13 L25 19 Z" fill="#e8e6dc"/>')
	_add("customs", 30, 32, 4.5,
		'<path d="M23.5 10 V2" fill="none" stroke-width="1"/><path d="M4 31 V14 H22 V31 Z" fill="#d8ccae"/><path d="M2 15 L13 6 L24 15 Z" fill="{slate}"/>'
		+ '<rect x="20" y="10" width="7" height="21" fill="#cfc3a6"/>' + _teeth(20, 27, 10, 1.75, 1.8, "#cfc3a6") + _win(10.5, 22, 5, 9, "{door}") + _win(22.5, 15, 2, 3),
		{"flag": Vector2(23.5, 2)})
	_add("ship_frame", 44, 24, 3.4,
		'<path d="M2 23 H42" fill="none" stroke="{timber}" stroke-width="1.6"/>'
		+ '<path d="M10 18.5 V8 M16 20.5 V6 M22 21 V5 M28 20.5 V6 M34 18.5 V8" fill="none" stroke="{wood}" stroke-width="1.3"/>'
		+ '<path d="M4 15 Q22 27 40 15" fill="none" stroke="{wood}" stroke-width="2.2"/><path d="M41 23 V4 H33" fill="none" stroke="{timber}" stroke-width="1.1"/>')
	_add("lighthouse", 16, 46, 6.5,
		'<path d="M3.5 45 L5 14 H11 L12.5 45 Z" fill="#efe6d4"/><path d="M4.3 37 H11.7 L11.4 31 H4.6 Z M4.9 25 H11.1 L10.8 19 H5.2 Z" fill="{red}" stroke="none"/>'
		+ '<rect x="4.5" y="8" width="7" height="6" fill="{gold2}"/><path d="M3.5 8.5 L8 3 L12.5 8.5 Z" fill="{slate}"/>',
		{"lamp": [Vector2(8, 11), Color("#ffe08a")]})
	_add("scaffold", 28, 32, 4.2,
		'<path d="M5 31 V24 H19 V31 Z" fill="{stone}"/>'
		+ '<path d="M4 31 V8 M14 31 V8 M24 31 V12" fill="none" stroke="{wood}" stroke-width="1.4"/>'
		+ '<path d="M3 13 H25 M3 21 H25 M3 29 H25" fill="none" stroke="{wood}" stroke-width="1.2"/>'
		+ '<path d="M4 21 L14 13 M14 29 L24 21" fill="none" stroke="#a87a4a" stroke-width="0.9"/><path d="M14 8 L26 3 V9" fill="none" stroke-width="1"/>')
	# ------------------------------------------------ великие стройки
	var rays := ""
	for k in 8:
		var a := k * PI / 4.0
		rays += "M%.1f %.1f L%.1f %.1f " % [36 + cos(a) * 5.5, 8 + sin(a) * 5.5, 36 + cos(a) * 8, 8 + sin(a) * 8]
	_add("sun_cathedral", 72, 72, 13.0,
		'<path d="' + rays + '" fill="none" stroke="{gold}" stroke-width="1.6"/><circle cx="36" cy="8" r="4.2" fill="{gold2}"/>'
		+ '<path d="M36 12 V16" fill="none" stroke-width="1.3"/>'
		+ '<rect x="25" y="26" width="22" height="14" fill="#e6dcc4"/><path d="M21.5 27.5 A14.5 13 0 0 1 50.5 27.5 Z" fill="{gold}"/>'
		+ '<path d="M27 25 A10 9 0 0 1 36 15.5 L36 27 Z" fill="#f6d27a" stroke="none"/>'
		+ '<rect x="14" y="38" width="44" height="33" fill="#efe6d0"/><path d="M12 39 L36 30 L60 39 Z" fill="{stone}"/>'
		+ '<circle cx="36" cy="46" r="4.6" fill="{gold}"/><circle cx="36" cy="46" r="2" fill="{red}"/>' + _arch(30, 54, 12, 17)
		+ _win(19, 46, 2.6, 8) + _win(50.4, 46, 2.6, 8)
		+ '<rect x="3" y="24" width="12" height="47" fill="{stone}"/><path d="M1.5 25 L9 6 L16.5 25 Z" fill="{gold}"/>'
		+ '<rect x="57" y="24" width="12" height="47" fill="{stone2}"/><path d="M55.5 25 L63 6 L70.5 25 Z" fill="#c8982e"/>'
		+ _win(8, 32, 2.2, 7) + _win(8, 48, 2.2, 7) + _win(62, 32, 2.2, 7) + _win(62, 48, 2.2, 7),
		{"glow": true})
	var domes := ""
	for d in [[18.0, 6.5], [38.0, 9.0], [58.0, 6.5]]:
		domes += '<path d="M%.1f 22.5 A%.1f %.1f 0 0 1 %.1f 22.5 Z" fill="{copper}"/><circle cx="%.1f" cy="%.1f" r="1.3" fill="{gold}"/>' % [
			d[0] - d[1], d[1], d[1] * 0.9, d[0] + d[1], d[0], 22.5 - d[1] * 0.9 - 1.2]
	var arches := ""
	for k in 7:
		arches += _arch(8.0 + k * 9.0, 34, 5, 13)
	_add("great_bazaar", 76, 48, 8.0,
		'<path d="M6 22 V4 M70 22 V4" fill="none" stroke-width="1"/><path d="M6 4 H13 L11 6.5 L13 9 H6 Z" fill="{red}"/><path d="M70 4 H63 L65 6.5 L63 9 H70 Z" fill="{blue}"/>'
		+ domes + '<rect x="3" y="22" width="70" height="25" fill="#e6d6b0"/>' + _teeth(3, 73, 22, 3.5, 2, "#e6d6b0") + arches
		+ '<path d="M2 47 L5 40 H17 L20 47 Z" fill="{red}"/><path d="M56 47 L59 40 H71 L74 47 Z" fill="{green}"/>'
		+ '<circle cx="27" cy="30" r="1.8" fill="{gold}"/><circle cx="49" cy="30" r="1.8" fill="{gold}"/>',
		{"glow": true})
	_add("great_lighthouse", 36, 90, 15.0,
		'<path d="M4 89 L7 50 H29 L32 89 Z" fill="#e6dcc4"/><path d="M22 50 H29 L32 89 H24 Z" fill="#cfc3a6" stroke="none"/>'
		+ _teeth(7, 29, 50, 2.75, 2.5, "#e6dcc4") + _arch(15, 76, 6, 13) + _win(11, 58, 2.4, 5) + _win(22.6, 58, 2.4, 5)
		+ '<path d="M9.5 50 L11.5 28 H24.5 L26.5 50 Z" fill="#ddd2b8"/>' + _win(16.8, 36, 2.4, 6)
		+ '<path d="M12.5 28 L13.5 16 H22.5 L23.5 28 Z" fill="{stone}"/><rect x="13" y="14" width="10" height="3" fill="{stone2}"/>'
		+ '<path d="M14 15 C14 9 17 9 18 3 C19 9 22 9 22 15 Z" fill="#f0a030"/><path d="M16 15 C16 11.5 17.5 11.5 18 8 C18.5 11.5 20 11.5 20 15 Z" fill="{gold2}" stroke="none"/>',
		{"glow": true, "lamp": [Vector2(18, 10), Color("#ffd060")]})
	_add("university", 70, 52, 9.0,
		'<path d="M35 10 V2" fill="none" stroke-width="1"/>'
		+ '<rect x="27" y="12" width="16" height="39" fill="{stone}"/>' + _teeth(27, 43, 12, 2.7, 2.6, "{stone}")
		+ '<circle cx="35" cy="20" r="3" fill="{white}"/><path d="M35 18.2 V20 H36.4" fill="none" stroke-width="0.7"/>' + _arch(31, 38, 8, 13)
		+ '<path d="M2 51 V27 H28 V51 Z" fill="#e2d6b8"/><path d="M0.5 28 L6 18 H28 V28 Z" fill="{slate}"/>'
		+ '<path d="M42 51 V27 H68 V51 Z" fill="#d8ccae"/><path d="M42 28 V18 H64 L69.5 28 Z" fill="{slate2}"/>'
		+ _win(6, 32, 2.4, 5) + _win(12, 32, 2.4, 5) + _win(18, 32, 2.4, 5) + _win(6, 42, 2.4, 5) + _win(12, 42, 2.4, 5) + _win(18, 42, 2.4, 5)
		+ _win(49.6, 32, 2.4, 5) + _win(55.6, 32, 2.4, 5) + _win(61.6, 32, 2.4, 5) + _win(49.6, 42, 2.4, 5) + _win(55.6, 42, 2.4, 5) + _win(61.6, 42, 2.4, 5),
		{"glow": true, "flag": Vector2(35, 2)})
	_add("great_foundry", 70, 50, 8.5,
		'<rect x="14" y="3" width="6" height="22" fill="#8f8a84"/><rect x="32" y="1" width="6" height="24" fill="#8f8a84"/><rect x="50" y="3" width="6" height="22" fill="#8f8a84"/>'
		+ '<path d="M3 49 V22 H67 V49 Z" fill="#9a8a74"/><path d="M1 23 L8 13 H62 L69 23 Z" fill="#4f4a44"/>'
		+ _arch(10, 32, 10, 17, "#f08a30") + _arch(30, 30, 10, 19, "#f6a040") + _arch(50, 32, 10, 17, "#f08a30")
		+ '<rect x="27" y="17" width="16" height="4" fill="{gold}"/>',
		{"glow": true, "smoke": [Vector2(17, 3), Vector2(35, 1), Vector2(53, 3)]})
	_add("justice_hall", 68, 50, 9.0,
		'<path d="M26 18 A8 8 0 0 1 42 18 Z" fill="{gold}"/><circle cx="34" cy="9" r="1.5" fill="{gold2}"/>'
		+ '<path d="M2 49 V44 H66 V49 Z" fill="#cfc3a6"/><path d="M5 44 V24 H63 V44 Z" fill="{stone3}"/>'
		+ '<rect x="7" y="24" width="4" height="20" fill="#efe6d0"/><rect x="17" y="24" width="4" height="20" fill="#efe6d0"/><rect x="27" y="24" width="4" height="20" fill="#efe6d0"/>'
		+ '<rect x="37" y="24" width="4" height="20" fill="#efe6d0"/><rect x="47" y="24" width="4" height="20" fill="#efe6d0"/><rect x="57" y="24" width="4" height="20" fill="#efe6d0"/>'
		+ '<path d="M2 24.5 L34 14 L66 24.5 Z" fill="#e6dcc4"/><path d="M34 16 V22.5 M29 18 H39" fill="none" stroke="{gold}" stroke-width="1.2"/>'
		+ '<path d="M27.5 22 L29 18.5 L30.5 22 Z M37.5 22 L39 18.5 L40.5 22 Z" fill="{gold}"/>',
		{"glow": true})
	_add("royal_stables", 72, 40, 7.0,
		'<path d="M36 9 V1" fill="none" stroke-width="1"/>'
		+ '<rect x="30" y="9" width="12" height="20" fill="{stone}"/><path d="M28.5 10 L36 2.5 L43.5 10 Z" fill="{roof2}"/>'
		+ '<path d="M3 30 V18 H69 V30 Z" fill="#9a6a40"/><path d="M1 19 L5 12 H67 L71 19 Z" fill="{roof}"/>'
		+ _win(7, 22, 4, 8) + _win(14, 22, 4, 8) + _win(21, 22, 4, 8) + _arch(32, 20, 8, 10) + _win(47, 22, 4, 8) + _win(54, 22, 4, 8) + _win(61, 22, 4, 8)
		+ '<path d="M2 38 H70 M2 34.5 H70 M4 33 V39 M14 33 V39 M24 33 V39 M34 33 V39 M44 33 V39 M54 33 V39 M64 33 V39" fill="none" stroke="#e6d6b0" stroke-width="0.9"/>',
		{"glow": true, "flag": Vector2(36, 1)})
	_add("wall_gate", 76, 40, 7.0,
		'<rect x="2" y="20" width="72" height="19" fill="{stone2}"/>' + _teeth(2, 74, 20, 3, 2.5, "{stone2}")
		+ '<rect x="12" y="8" width="14" height="31" fill="{stone}"/>' + _teeth(12, 26, 8, 2.8, 2.6, "{stone}")
		+ '<rect x="50" y="8" width="14" height="31" fill="{stone}"/>' + _teeth(50, 64, 8, 2.8, 2.6, "{stone}")
		+ _arch(32, 25, 12, 14) + '<path d="M34 28 V39 M36.5 26.5 V39 M39 26 V39 M41.5 26.5 V39 M32.5 31 H43.5 M32 35 H44" fill="none" stroke="#8a8a80" stroke-width="0.8"/>'
		+ _win(18, 14, 2.2, 5) + _win(56, 14, 2.2, 5)
		+ '<path d="M19 8 V1 M57 8 V1" fill="none" stroke-width="1"/><path d="M19 1 H25 L23.5 3 L25 5 H19 Z" fill="{red}"/><path d="M57 1 H63 L61.5 3 L63 5 H57 Z" fill="{red}"/>',
		{"glow": true})
	_add("palace", 60, 50, 10.0,
		'<rect x="22" y="14" width="16" height="22" fill="#efe6d0"/><path d="M21 15 A9 9 0 0 1 39 15 Z" fill="{gold}"/><circle cx="30" cy="4.6" r="1.6" fill="{gold2}"/>'
		+ '<path d="M2 49 V26 H58 V49 Z" fill="#efe6d0"/><path d="M0.5 27 L6 19 H54 L59.5 27 Z" fill="{gold}"/>'
		+ _arch(25.5, 35, 9, 14) + _win(7, 31, 2.6, 6) + _win(13, 31, 2.6, 6) + _win(44.4, 31, 2.6, 6) + _win(50.4, 31, 2.6, 6),
		{"glow": true})
	_add("ruin", 48, 34, 5.5,
		'<path d="M4 33 V14 L7 12 L9 17 L11 13 V33 Z" fill="#6f6a64"/><path d="M11 33 V22 L16 20 L20 24 L24 19 V33 Z" fill="#7d776e"/>'
		+ '<path d="M24 33 V9 L28 6 L30 11 L33 8 V33 Z" fill="#6f6a64"/><path d="M33 33 V21 L38 24 L42 18 L44 22 V33 Z" fill="#7d776e"/>'
		+ _win(27, 15, 2.4, 5, "#1a120a") + _win(6, 20, 2.4, 5, "#1a120a")
		+ '<path d="M2 33 H46" fill="none" stroke="#3a3a36" stroke-width="1.5"/>')
	_add("dike", 64, 20, 3.5,
		'<path d="M1 19 L8 8 H56 L63 19 Z" fill="#8a9a5a"/><path d="M8 8 H56" fill="none" stroke="#5f7a3a" stroke-width="1.2"/>'
		+ '<rect x="28" y="9" width="8" height="10" fill="{stone2}"/><rect x="30" y="12" width="4" height="7" fill="#3a5a6a"/>'
		+ '<path d="M14 8 V2 M50 8 V2" fill="none" stroke-width="0.9"/><path d="M14 2 L17 4 L14 6 Z M50 2 L53 4 L50 6 Z" fill="{blue}"/>')

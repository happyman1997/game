class_name Fonts
extends RefCounted
## Шрифты интерфейса. Основной текст — PT Serif, заголовки и подписи
## на карте — Cormorant Garamond. Символы и эмодзи (иконки модов) берутся
## из Noto Sans Symbols 2 и Noto Emoji.

const DIR := "res://assets/fonts/"

static var _cache := {}


static func _file(name: String) -> FontFile:
	if not _cache.has(name):
		_cache[name] = load(DIR + name)
	return _cache[name]


static func _fallbacks() -> Array[Font]:
	return [_file("NotoSansSymbols2.ttf"), _file("NotoEmoji.ttf")]


static func _with_fallbacks(base: Font, key: String) -> Font:
	if _cache.has(key):
		return _cache[key]
	var v := FontVariation.new()
	v.base_font = base
	v.fallbacks = _fallbacks()
	_cache[key] = v
	return v


static func regular() -> Font:
	return _with_fallbacks(_file("PTSerif-Regular.ttf"), "regular")


static func bold() -> Font:
	return _with_fallbacks(_file("PTSerif-Bold.ttf"), "bold")


static func italic() -> Font:
	return _with_fallbacks(_file("PTSerif-Italic.ttf"), "italic")


## Cormorant Garamond заданной насыщенности (300–700).
static func heading(weight: int = 650) -> Font:
	var key := "heading%d" % weight
	if _cache.has(key):
		return _cache[key]
	var v := FontVariation.new()
	v.base_font = _file("CormorantGaramond.ttf")
	var ts := TextServerManager.get_primary_interface()
	v.variation_opentype = {ts.name_to_tag("wght"): weight}
	v.fallbacks = _fallbacks()
	_cache[key] = v
	return v


## Шрифт для эмодзи-иконок модов.
static func emoji() -> Font:
	return _with_fallbacks(_file("NotoEmoji.ttf"), "emoji")

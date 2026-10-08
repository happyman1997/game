class_name Coa
extends RefCounted
## Процедурные гербы (SVG → текстура). Герб можно задать в данных титула
## или династии:
##   coa: { field: azure, division: per_pale, field2: gules,
##          ordinary: cross, ordinary_tincture: or,
##          charge: fleur, charge_tincture: or, count: 3 }
## Если не задан — генерируется детерминированно из id. Мод может добавить
## фигуры (Coa.CHARGES) и цвета (Coa.TINCTURES).

static var TINCTURES := {
	"or": "#e2b43c", "argent": "#efeee6", "gules": "#b4262a", "azure": "#2a4f9e",
	"vert": "#2e7a3c", "sable": "#262422", "purpure": "#6a3a86",
}
const METALS := ["or", "argent"]
const COLOURS := ["gules", "azure", "vert", "sable", "purpure"]

static var CHARGES := {
	"roundel": '<circle cx="0" cy="0" r="7"/>',
	"mullet": '<path d="M0 -9 L2.6 -2.8 L9 -2.8 L3.8 1.2 L5.6 8 L0 4 L-5.6 8 L-3.8 1.2 L-9 -2.8 L-2.6 -2.8 Z"/>',
	"lozenge": '<path d="M0 -9 L6 0 L0 9 L-6 0 Z"/>',
	"cross": '<path d="M-2.5 -9 H2.5 V-2.5 H9 V2.5 H2.5 V9 H-2.5 V2.5 H-9 V-2.5 H-2.5 Z"/>',
	"crescent": '<path d="M-7 -2 A7.5 7.5 0 1 0 7 -2 A6 6 0 1 1 -7 -2 Z"/>',
	"crown": '<path d="M-9 5 L-9 -4 L-4.5 0 L0 -7 L4.5 0 L9 -4 L9 5 Z"/>',
	"fleur": '<path d="M0 -10 C4 -6 4 -2 0 2 C-4 -2 -4 -6 0 -10 Z M-1.5 2 C-6 -4 -11 -1 -7 4 C-5 6 -2 4 -1.5 2 Z M1.5 2 C6 -4 11 -1 7 4 C5 6 2 4 1.5 2 Z M-5 4 H5 V6 H-5 Z M-1 6 H1 L0 10 Z"/>',
	"tower": '<path d="M-6 9 V-3 H-7 V-8 H-4 V-6 H-1.5 V-8 H1.5 V-6 H4 V-8 H7 V-3 H6 V9 Z M-2 9 V4 A2 2 0 0 1 2 4 V9 Z" fill-rule="evenodd"/>',
	"lion": '<path d="M-8 8 L-6 1 C-8 -1 -8 -5 -5 -6 C-4 -9 0 -10 2 -8 C4 -9 7 -7 6 -4 C8 -3 8 0 6 1 L7 8 L4 8 L3 3 L-2 3 L-3 8 Z M5 -4 L9 -7 L8 -2 Z"/>',
	"eagle": '<path d="M0 -9 C2 -9 3 -7 2 -5 L9 -8 L7 -2 L10 -1 L5 2 L4 6 L2 4 L1 9 L-1 9 L-2 4 L-4 6 L-5 2 L-10 -1 L-7 -2 L-9 -8 L-2 -5 C-3 -7 -2 -9 0 -9 Z"/>',
}

const SHIELD := "M6 6 H94 V52 Q94 88 50 106 Q6 88 6 52 Z"

static var _tex := {}


static func _contrast(base: String, rng: Rng) -> String:
	return rng.pick(COLOURS) if METALS.has(base) else rng.pick(METALS)


static func random_spec(seed: String) -> Dictionary:
	var rng := Rng.new({"s": Rng.hash_string(seed) & 0xFFFFFFFF})
	var field: String = rng.pick(METALS) if rng.chance(0.4) else rng.pick(COLOURS)
	var spec := {"field": field}
	var r := rng.next()
	if r < 0.25:
		spec.division = rng.pick(["per_pale", "per_fess", "quarterly", "per_bend"])
		spec.field2 = _contrast(field, rng)
	if not spec.has("division") and rng.chance(0.55):
		spec.ordinary = rng.pick(["cross", "saltire", "fess", "pale", "bend", "chevron", "chief", "bordure"])
		spec.ordinary_tincture = _contrast(field, rng)
	if rng.chance(0.6):
		var charges := CHARGES.keys()
		charges.sort()
		spec.charge = rng.pick(charges)
		spec.charge_tincture = _contrast(field, rng)
		spec.count = rng.pick([1, 1, 2, 3, 3])
	return spec


static func _t(n: Variant) -> String:
	if n == null:
		return "#888888"
	return TINCTURES.get(str(n), str(n))


static func svg(spec: Variant, seed: String) -> String:
	var s := random_spec(seed)
	if spec is Dictionary:
		for k in spec:
			s[k] = spec[k]
		for k in ["division", "ordinary", "charge"]:
			if not spec.has(k) or spec[k] == null:
				s.erase(k)
	var p := PackedStringArray()
	p.append('<defs><clipPath id="cl"><path d="%s"/></clipPath>' % SHIELD)
	p.append('<linearGradient id="gl" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.38"/><stop offset="0.45" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.4"/></linearGradient>')
	p.append('<linearGradient id="rim" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f6dc90"/><stop offset="0.5" stop-color="#b68a3a"/><stop offset="1" stop-color="#6a4a18"/></linearGradient></defs>')
	p.append('<g clip-path="url(#cl)"><rect width="100" height="110" fill="%s"/>' % _t(s.field))
	var f2 := _t(s.get("field2"))
	match s.get("division"):
		"per_pale": p.append('<rect x="50" width="50" height="110" fill="%s"/>' % f2)
		"per_fess": p.append('<rect y="52" width="100" height="60" fill="%s"/>' % f2)
		"quarterly": p.append('<rect x="50" width="50" height="52" fill="%s"/><rect y="52" width="50" height="60" fill="%s"/>' % [f2, f2])
		"per_bend": p.append('<path d="M0 0 L100 110 L0 110 Z" fill="%s"/>' % f2)
	var o := _t(s.get("ordinary_tincture"))
	match s.get("ordinary"):
		"cross": p.append('<rect x="41" width="18" height="110" fill="%s"/><rect y="38" width="100" height="18" fill="%s"/>' % [o, o])
		"saltire": p.append('<path d="M0 0 L100 110 M100 0 L0 110" stroke="%s" stroke-width="16"/>' % o)
		"fess": p.append('<rect y="40" width="100" height="22" fill="%s"/>' % o)
		"pale": p.append('<rect x="38" width="24" height="110" fill="%s"/>' % o)
		"bend": p.append('<path d="M0 0 L100 110" stroke="%s" stroke-width="18"/>' % o)
		"chevron": p.append('<path d="M0 90 L50 40 L100 90" stroke="%s" stroke-width="16" fill="none"/>' % o)
		"chief": p.append('<rect width="100" height="32" fill="%s"/>' % o)
		"bordure": p.append('<path d="%s" fill="none" stroke="%s" stroke-width="16"/>' % [SHIELD, o])
	var charge: Variant = s.get("charge")
	if charge != null and CHARGES.has(charge):
		var n := clampi(int(s.get("count", 1)), 1, 3)
		var pos: Array
		if n == 1:
			pos = [[50, 64 if s.get("ordinary") == "chief" else 52, 2.2]]
		elif n == 2:
			pos = [[32, 46, 1.4], [68, 46, 1.4]]
		else:
			pos = [[30, 32, 1.3], [70, 32, 1.3], [50, 72, 1.3]]
		for q in pos:
			p.append('<g transform="translate(%s %s) scale(%s)" fill="%s" stroke="#000" stroke-opacity="0.4" stroke-width="0.5">%s</g>' % [q[0], q[1], q[2], _t(s.get("charge_tincture")), CHARGES[charge]])
	p.append('<rect width="100" height="110" fill="url(#gl)"/></g>')
	p.append('<path d="%s" fill="none" stroke="url(#rim)" stroke-width="4.5"/>' % SHIELD)
	p.append('<path d="%s" fill="none" stroke="#1c140a" stroke-width="1.2"/>' % SHIELD)
	return '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="112" viewBox="0 0 100 112">' + "".join(p) + '</svg>'


static func texture(spec: Variant, seed: String, width: int = 40) -> Texture2D:
	var key := "%s:%d:%s" % [seed, width, JSON.stringify(spec)]
	if _tex.has(key):
		return _tex[key]
	var img := Image.new()
	# Рисуем вдвое крупнее и уменьшаем: тонкие линии без «лесенки».
	if img.load_svg_from_string(svg(spec, seed), width * 2 / 100.0) != OK:
		img = Image.create(width * 2, int(width * 2.24), false, Image.FORMAT_RGBA8)
	img.resize(width, int(round(width * 1.12)), Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	if _tex.size() > 3000:
		_tex.clear()
	_tex[key] = tex
	return tex


static func of_title(game: Game, title_id: Variant, width: int = 40) -> Texture2D:
	if title_id == null:
		return texture(null, "none", width)
	var d: Variant = game.title_def(title_id)
	return texture(d.get("coa") if d != null else null, str(title_id), width)


static func of_dynasty(game: Game, dynasty_id: Variant, width: int = 40) -> Texture2D:
	if dynasty_id == null:
		return texture(null, "lowborn", width)
	var d: Variant = game.state.dynasties.get(dynasty_id)
	var spec: Variant = null
	if d is Dictionary:
		spec = d.get("coa")
	if spec == null:
		var def: Variant = game.content.get_def("dynasties", dynasty_id)
		if def != null:
			spec = def.get("coa")
	return texture(spec, "dyn:" + str(dynasty_id), width)


## Герб персонажа: его главного титула, иначе — династии.
static func of_character(game: Game, c: Dictionary, width: int = 40) -> Texture2D:
	if not c.titles.is_empty():
		return of_title(game, c.titles[0], width)
	return of_dynasty(game, c.dynasty, width)

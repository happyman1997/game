class_name ContentNormalize
extends RefCounted
## Приводит контент к каноническому виду: значения по умолчанию,
## графства из провинций, цвета и т.п. Вызывается после загрузки модов,
## до инициализации их скриптов.

const DEFAULT_DEFINES := {
	"character": {
		"adult_age": 16,
		"marriage_age": 16,
		"base_health": 5,
		"personality_traits": 3,
		"base_stats": {"fertility": 0.5},
	},
	"economy": {},
	"military": {},
	"war": {},
	"ai": {},
	"opinion": {},
	"titles": {"create_fraction": 0.51},
	"succession": {"default_law": "partition"},
	"script_stat_values": ["general_opinion", "vassal_opinion", "monthly_prestige", "monthly_piety", "prowess"],
}


## Цвет "#rrggbb" из строки, списка [r, g, b] (0..1 или 0..255) или по хешу id.
static func parse_color(c: Variant, fallback_seed: String) -> String:
	if c is String:
		var h: String = c.trim_prefix("#")
		if h.length() == 6 and h.is_valid_hex_number():
			return "#" + h.to_lower()
	if c is Array and c.size() >= 3:
		var unit := true
		for i in 3:
			if Data.num(c[i]) > 1.0:
				unit = false
		var out := "#"
		for i in 3:
			var v = Data.num(c[i])
			out += "%02x" % clampi(roundi(v * 255.0 if unit else v), 0, 255)
		return out
	var hue := (Rng.hash_string(fallback_seed) & 0xFFFFFFFF) % 360
	return hsl_to_hex(hue, 45, 45)


static func hsl_to_hex(h: float, s: float, l: float) -> String:
	return _hsl(h, s / 100.0, l / 100.0)


static func _hsl(h: float, s: float, l: float) -> String:
	var a := s * minf(l, 1.0 - l)
	var f := func(n: float) -> float:
		var k := fmod(n + h / 30.0, 12.0)
		return l - a * maxf(-1.0, minf(k - 3.0, minf(9.0 - k, 1.0)))
	return "#%02x%02x%02x" % [roundi(f.call(0.0) * 255.0), roundi(f.call(8.0) * 255.0), roundi(f.call(4.0) * 255.0)]


static func _vary(hex: String, seed: String, amount: float = 18.0) -> String:
	var c := Color.html(hex)
	var hh := Rng.hash_string(seed)
	var d := ((hh & 0xff) / 255.0 - 0.5) * 2.0 * amount
	var cl := func(x: float) -> int: return clampi(roundi(x * 255.0 + d), 0, 255)
	return "#%02x%02x%02x" % [cl.call(c.r), cl.call(c.g), cl.call(c.b)]


static func normalize(content: ContentStore) -> void:
	content.set_singleton("defines", Data.deep_merge(DEFAULT_DEFINES, content.singleton("defines")))
	for t in content.all("titles"):
		if not (t.get("tier") in Titles.TIERS):
			t["tier"] = "duchy"
	for t in content.all("titles"):
		t["color"] = parse_color(t.get("color"), t.id)
	for p in content.all("provinces"):
		if p.get("holdings") == null:
			p["holdings"] = ["castle"]
		if p.get("development") == null:
			p["development"] = 5
		if p.get("impassable", false):
			continue
		var existing: Variant = content.get_def("titles", p.id)
		var duchy: Variant = p.get("duchy")
		if duchy == null and existing != null:
			duchy = existing.get("liege")
		var duchy_def: Variant = content.get_def("titles", duchy) if duchy != null else null
		var duchy_color: Variant = duchy_def.get("color") if duchy_def != null else null
		var color: String
		if existing != null and existing.get("color") != null and existing.color != parse_color(null, p.id):
			color = existing.color
		elif p.get("color") != null:
			color = parse_color(p.color, p.id)
		elif duchy_color != null:
			color = _vary(duchy_color, p.id)
		else:
			color = parse_color(null, p.id)
		var def: Dictionary = existing.duplicate() if existing != null else {}
		def["tier"] = "county"
		def["liege"] = duchy
		def["color"] = color
		def["capital"] = p.id
		def["province"] = p.id
		content.set_def("titles", p.id, def)
	for c in content.all("cultures"):
		c["color"] = parse_color(c.get("color"), c.id)
		if c.get("male_names") == null:
			c["male_names"] = ["John"]
		if c.get("female_names") == null:
			c["female_names"] = ["Mary"]
	for f in content.all("faiths"):
		f["color"] = parse_color(f.get("color"), f.id)
	for t in content.all("terrain"):
		t["color"] = parse_color(t.get("color"), t.id)
		if t.get("defense") == null:
			t["defense"] = 0
		if t.get("movement") == null:
			t["movement"] = 1
		if t.get("height") == null:
			t["height"] = 0.2
	for e in content.all("events"):
		if e.get("options") is Dictionary:
			e["options"] = e.options.values()
	for oa in content.all("on_actions"):
		if oa.get("events") is Dictionary:
			oa["events"] = oa.events.keys()
	for s in content.all("skills"):
		s["color"] = parse_color(s.get("color"), s.id)
	for t in content.all("traits"):
		if t.get("modifiers") != null and not (t.modifiers is Dictionary):
			t["modifiers"] = {}

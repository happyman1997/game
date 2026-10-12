extends RefCounted
## Анатомический лист из лекарского трактата: пергамент, фигура тушью с
## вживлениями прямо на теле (железная рука, деревянная нога, пластина в
## черепе, стеклянный глаз, руны, драконья чешуя…), части тела по полям —
## медальоны с вживлениями и пунктир к месту на теле, красные пометки,
## «Душа» рядом ромбов-лазуритов. Окно вживления и мастерская
## цирюльника-хирурга — в обычном оформлении игры.

const Main := preload("main.gd")

const INK := Color("#3a2614")
const INK_SOFT := Color("#6b4e2e")
const RUBRIC := Color("#9a1c1c")
const LAPIS := Color("#2a4a8a")
const OCHRE := Color("#b8801c")
const PARCH := Color("#eadcb4")
const PARCH_LIGHT := Color("#f4ead0")

const AREA := Vector2(580, 470)
const FIG_W := 220
const FIG_H := 400
const FIG_SCALE := 1.1
const FIG_POS := Vector2(169, 12)
const CELL := 50
const GROUP_W := 200

static var _tex := {}


static func register_icons() -> void:
	var D := "#1c140a"
	Icons.register("rune", '<path d="M10.6 2 H13.4 V9 L18.5 5 L20 7.2 L13.4 12.4 V22 H10.6 V12.4 L4 7.2 L5.5 5 L10.6 9 Z"/>')
	Icons.register("tooth", '<path d="M5 4 C7.5 2 10 3.5 12 3.5 C14 3.5 16.5 2 19 4 C21 6 20 10.5 18.5 13 C17.5 15 17.5 20.5 15.5 21 C13.5 21.5 13.5 16 12 16 C10.5 16 10.5 21.5 8.5 21 C6.5 20.5 6.5 15 5.5 13 C4 10.5 3 6 5 4 Z"/>')
	Icons.register("drop", '<path d="M12 2.5 C14 7 19 11 19 15.5 C19 19.5 15.8 22 12 22 C8.2 22 5 19.5 5 15.5 C5 11 10 7 12 2.5 Z"/><path d="M9 15 Q9 18.5 12 19" fill="none" stroke-width="1.4"/>')
	Icons.register("vial", '<rect x="9.5" y="2" width="5" height="2.2" rx="0.6"/><path d="M10 4.2 H14 V8.5 L19 17.5 C20 19.8 18.6 22 16 22 H8 C5.4 22 4 19.8 5 17.5 L10 8.5 Z"/><path d="M7 16 H17 L18.2 18.5 C18.6 19.6 17.8 20.6 16.6 20.6 H7.4 C6.2 20.6 5.4 19.6 5.8 18.5 Z" fill="%s"/>' % D)
	Icons.register("hook", '<rect x="9" y="2" width="6" height="7" rx="1.5"/><path d="M11 9 H13 V15 C13 17.5 15 18.5 16.5 17.5 C17.5 16.8 17.6 15.5 17 14.5 L18.8 13.6 C20 15.6 19.4 18.4 17.4 19.6 C14.6 21.2 11 19.6 11 15.5 Z"/>')
	Icons.register("gauntlet", '<path d="M6 22 V13 L4.5 9.5 V7.5 A1.4 1.4 0 0 1 7.3 7.5 V10 V4.5 A1.4 1.4 0 0 1 10.1 4.5 V10 V3.5 A1.4 1.4 0 0 1 12.9 3.5 V10 V4.5 A1.4 1.4 0 0 1 15.7 4.5 V12 L18 9.5 A1.4 1.4 0 0 1 20 11.2 L15.5 17 V22 Z"/><rect x="5.6" y="18" width="10.3" height="1.4" fill="%s"/><circle cx="8.5" cy="14.5" r="1" fill="%s"/><circle cx="13" cy="14.5" r="1" fill="%s"/>' % [D, D, D])
	Icons.register("pegleg", '<path d="M8 2 H16 V9 C16 10.5 15 11.5 14 12 L13.6 21 H15 V22.5 H9 V21 H10.4 L10 12 C9 11.5 8 10.5 8 9 Z"/><rect x="7.6" y="8.2" width="8.8" height="1.4" fill="%s"/>' % D)
	Icons.register("gem", '<path d="M7 3.5 H17 L21.5 9 L12 21.5 L2.5 9 Z"/><path d="M2.5 9 H21.5 M7 3.5 L9.5 9 L12 21.5 L14.5 9 L17 3.5" fill="none" stroke-width="0.9"/>')
	Icons.register("bone", '<path d="M6.5 3 A2.5 2.5 0 0 0 3 6.5 A2.5 2.5 0 0 0 6 9.5 L14.5 18 A2.5 2.5 0 0 0 17.5 21 A2.5 2.5 0 0 0 21 17.5 A2.5 2.5 0 0 0 18 14.5 L9.5 6 A2.5 2.5 0 0 0 6.5 3 Z"/>')
	Icons.register("spine", '<rect x="8.5" y="2" width="7" height="3.6" rx="1.2"/><rect x="8" y="6.6" width="8" height="3.6" rx="1.2"/><rect x="7.5" y="11.2" width="9" height="3.6" rx="1.2"/><rect x="8" y="15.8" width="8" height="3.6" rx="1.2"/><path d="M10.5 20.4 H13.5 L12 22.5 Z"/>')
	Icons.register("scales_hide", '<path d="M12 2 L20.5 7 V17 L12 22 L3.5 17 V7 Z"/><path d="M7 9 Q12 6 17 9 M7 13 Q12 10 17 13 M7 17 Q12 14 17 17" fill="none" stroke-width="1.2"/>')


static func tier_color(game: Game, tier: Variant) -> Color:
	var d: Variant = game.content.get_def("graft_tiers", str(int(Data.num(tier, 1))))
	return Color(str(d.get("color", "#5a5650"))) if d != null else Color("#5a5650")


static func _box(bg: Color, border: Color, width: int = 1, radius: int = 2, margin: float = -1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	if margin >= 0:
		sb.set_content_margin_all(margin)
	return sb


static func _label(text: String, color: Color, size: int = 15) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


static func _rich(bb: String) -> RichTextLabel:
	var r := K.rich(bb)
	r.add_theme_color_override("default_color", INK)
	return r


## Свойства тушью: подпись — чернила, польза — зелёная, вред — красная киноварь.
static func ink_modifiers(game: Game, mods: Variant) -> String:
	if not (mods is Dictionary) or mods.is_empty():
		return ""
	var out := "[table=2]"
	for k in mods:
		var v := float(mods[k])
		var is_bad := v > 0 if k == "stress_gain_mult" else v < 0
		out += "[cell expand=1][color=#3a2614]%s[/color][/cell][cell]   [color=%s]%s[/color][/cell]" % [
			BB.esc(game.loc.t_or("stat." + k, k)), "#9a1c1c" if is_bad else "#2e5a1c", BB.stat_value(k, v)]
	return out + "[/table]"


## Подсказка вживления (на тёмной подложке подсказок); head — с названием.
static func graft_tip(game: Game, gid: String, head: bool = true) -> String:
	var d: Variant = Main.def_of(game, gid)
	if d == null:
		return gid
	var parts := []
	if head:
		var col := tier_color(game, d.get("tier")).lightened(0.35).to_html(false)
		parts.append("[b][color=#%s]%s[/color][/b]" % [col, BB.esc(game.name_of("grafts", gid))])
		parts.append(BB.muted(game.loc.t("grafts.ui_work", {"part": game.name_of("body_parts", d.get("part")), "work": game.loc.t("grafts.tier_" + str(int(Data.num(d.get("tier"), 1))))})))
	var desc := game.desc_of("grafts", gid)
	if desc != "":
		parts.append(BB.i(desc))
	var bb := "\n".join(parts)
	bb += "\n" + BB.modifiers(game, d.get("modifiers"))
	if not Data.as_array(d.get("cures")).is_empty():
		bb += "\n" + BB.good(game.loc.t("grafts.ui_cures"))
	bb += "\n" + BB.bad(game.loc.t("grafts.ui_soul_cost", {"n": roundi(Data.num(d.get("soul")))}))
	return bb


# ------------------------------------------------------------ пергамент и рисунок

## Пергамент: тёплая середина, потемневшие края, пятна, двойная рамка.
static func parchment_texture() -> Texture2D:
	if _tex.has("parch"):
		return _tex.parch
	var w := 256
	var h := 256
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 256 256">' % [w, h]
	svg += '<defs><radialGradient id="p" cx="50%" cy="45%" r="75%"><stop offset="0" stop-color="#f3e8c8"/><stop offset="0.7" stop-color="#e6d3a2"/><stop offset="1" stop-color="#c9ad74"/></radialGradient></defs>'
	svg += '<rect width="256" height="256" fill="url(#p)"/>'
	svg += '<rect x="6" y="6" width="244" height="244" fill="none" stroke="#6b4e2e" stroke-width="2"/>'
	svg += '<rect x="11" y="11" width="234" height="234" fill="none" stroke="#9a1c1c" stroke-opacity="0.6" stroke-width="1"/>'
	for q in [[11, 11], [245, 11], [11, 245], [245, 245]]:
		svg += '<circle cx="%d" cy="%d" r="3.2" fill="#9a1c1c" fill-opacity="0.7"/>' % [q[0], q[1]]
	svg += '</svg>'
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	var tex := ImageTexture.create_from_image(img)
	_tex["parch"] = tex
	return tex


static func _f(x: float) -> String:
	return str(snappedf(x, 0.1))


## Фигура тушью (SVG 220×400): контур, черты лица, рёбра, сердце, жилы;
## вживления — прямо на теле; одержимость — тёмный дым и красные глаза.
static func figure_svg(game: Game, c: Dictionary) -> String:
	var have := {}
	for x in Main.grafts_of(game, c):
		var d: Variant = Main.def_of(game, x.id)
		if d != null:
			have[str(x.id)] = "#" + tier_color(game, d.get("tier")).to_html(false)
	var possessed: bool = c.traits.has("iron_possession")
	var ink := "#3a2614"
	var p := PackedStringArray()
	p.append('<defs><linearGradient id="steel" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#4a4e54"/><stop offset="0.5" stop-color="#b8bec6"/><stop offset="1" stop-color="#3e4248"/></linearGradient>')
	p.append('<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6dc8a"/><stop offset="1" stop-color="#9a6a14"/></linearGradient>')
	p.append('<linearGradient id="wood" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#5a3a1c"/><stop offset="0.5" stop-color="#9a6a3a"/><stop offset="1" stop-color="#4a2e14"/></linearGradient></defs>')
	var body := "M100 74 L100 84 Q72 86 62 96 L44 170 L36 240 Q38 256 47 250 L56 182 L70 122 L74 230 L82 388 L104 388 L108 252 L112 252 L116 388 L138 388 L146 230 L150 122 L164 182 L173 250 Q182 256 184 240 L176 170 L158 96 Q148 86 120 84 L120 74 Z"
	if possessed:
		# тёмное марево по контуру и струйки дыма, поднимающиеся от тела
		p.append('<path d="%s" fill="none" stroke="#1e1018" stroke-opacity="0.16" stroke-width="16" stroke-linejoin="round"/>' % body)
		for w in ["M62 100 C46 84 64 70 48 54 C38 44 50 30 40 18", "M158 100 C174 84 156 68 172 52 C182 42 170 28 180 16",
				"M44 176 C26 164 40 146 24 132", "M176 176 C194 162 180 146 196 130", "M100 70 C92 56 104 46 96 32 C92 24 98 14 94 6",
				"M120 70 C128 56 116 46 124 32 C128 24 122 14 126 6", "M78 300 C60 290 70 272 56 260", "M142 300 C160 288 150 272 164 258"]:
			p.append('<path d="%s" fill="none" stroke="#2a1426" stroke-opacity="0.38" stroke-width="2.6" stroke-linecap="round"/>' % w)
			p.append('<path d="%s" fill="none" stroke="#2a1426" stroke-opacity="0.14" stroke-width="7" stroke-linecap="round"/>' % w)
	p.append('<path d="%s" fill="#e3c299" fill-opacity="0.55" stroke="%s" stroke-width="1.6" stroke-linejoin="round"/>' % [body, ink])
	# штриховка тени справа
	for i in 14:
		var y := 104 + i * 9
		p.append('<path d="M%d %d l6 -5" stroke="%s" stroke-opacity="0.35" stroke-width="0.8"/>' % [140 + (2 if i % 2 == 0 else 0), y, ink])
	# голова
	p.append('<ellipse cx="110" cy="48" rx="20" ry="25" fill="#e3c299" fill-opacity="0.6" stroke="%s" stroke-width="1.6"/>' % ink)
	p.append('<path d="M90 48 q-4 4 0 8 M130 48 q4 4 0 8" fill="none" stroke="%s" stroke-width="1.2"/>' % ink)
	p.append('<path d="M92 30 Q110 14 128 30" fill="none" stroke="%s" stroke-width="2.2" stroke-opacity="0.7"/>' % ink)
	# лицо
	var eye_l: String = ink
	var eye_r: String = ink
	for gid in ["glass_eye", "crystal_eye", "ruby_eye", "raven_eye"]:
		if have.has(gid):
			eye_l = {"glass_eye": "#6a9ac8", "crystal_eye": "#e8f0f4", "ruby_eye": "#b01c2a", "raven_eye": "#141014"}[gid]
	if possessed:
		eye_l = "#d01c1c"
		eye_r = "#d01c1c"
	p.append('<circle cx="102" cy="46" r="2.6" fill="%s" stroke="%s" stroke-width="0.8"/><circle cx="118" cy="46" r="2" fill="%s"/>' % [eye_l, ink, eye_r])
	if eye_l != ink and not possessed:
		p.append('<circle cx="102" cy="46" r="4.2" fill="none" stroke="#b8901c" stroke-width="1"/>')
	p.append('<path d="M110 48 v8 h-3 M104 62 q6 3 12 0" fill="none" stroke="%s" stroke-width="1.2"/>' % ink)
	# уста
	if have.has("gold_teeth"):
		p.append('<path d="M105 62 h10" stroke="url(#gold)" stroke-width="2.4"/>')
	if have.has("silver_tongue"):
		p.append('<circle cx="110" cy="63" r="1.6" fill="#d0d6dc"/>')
	if have.has("iron_jaw"):
		p.append('<path d="M94 58 Q110 80 126 58 L124 66 Q110 82 96 66 Z" fill="url(#steel)" stroke="%s" stroke-width="0.8"/>' % ink)
	# голова: пластина, печать, руны, камень
	if have.has("trepan_plate"):
		p.append('<path d="M96 27 Q110 18 124 27 L121 31 Q110 24 99 31 Z" fill="url(#steel)" stroke="%s" stroke-width="0.8"/>' % ink)
		for x in [101, 110, 119]:
			p.append('<circle cx="%d" cy="%d" r="0.9" fill="%s"/>' % [x, 26 if x == 110 else 28, ink])
	if have.has("lead_seal"):
		p.append('<circle cx="92" cy="40" r="3.6" fill="#5a5e64" stroke="%s" stroke-width="0.8"/>' % ink)
	if have.has("skull_runes") or have.has("rune_of_tyr"):
		p.append('<path d="M110 30 v8 M106 33 l4 -3 l4 3" fill="none" stroke="#9a1c1c" stroke-width="1.5"/>')
	if have.has("wisdom_stone"):
		p.append('<path d="M110 33 l3 3 l-3 4 l-3 -4 Z" fill="#3a6ab8" stroke="#b8901c" stroke-width="0.8"/>')
	# рёбра, сердце, пупок, колени
	var ribs := "#c0c6cc" if have.has("silver_ribs") else ink
	var ro := "0.9" if have.has("silver_ribs") else "0.3"
	for i in 4:
		var y := 112 + i * 11
		p.append('<path d="M110 %d Q90 %d 82 %d M110 %d Q130 %d 138 %d" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="1.1"/>' % [y, y - 2, y + 8, y, y - 2, y + 8, ribs, ro])
	var heart_fill := "#8a2420"
	if have.has("lion_heart"):
		heart_fill = "url(#gold)"
	if have.has("star_iron_heart"):
		heart_fill = "url(#steel)"
	p.append('<path d="M122 136 C114 130 112 124 116 120 C119 117 122 119 122 122 C122 119 125 117 128 120 C132 124 130 130 122 136 Z" fill="%s" stroke="%s" stroke-width="0.8"/>' % [heart_fill, ink])
	if have.has("relic_heart"):
		p.append('<path d="M127 112 h7 v7 h-7 Z M127 112 l3.5 -3 l3.5 3" fill="url(#gold)" stroke="%s" stroke-width="0.6"/>' % ink)
	p.append('<circle cx="110" cy="190" r="1.4" fill="%s" fill-opacity="0.6"/>' % ink)
	p.append('<path d="M86 312 q6 -5 12 0 M118 312 q6 -5 12 0" fill="none" stroke="%s" stroke-opacity="0.5" stroke-width="1"/>' % ink)
	# кровь — жилы на руках
	var vein := "#a8302a"
	var vo := "0.35"
	for gid in ["galen_humors", "theriac", "quicksilver", "dragon_blood"]:
		if have.has(gid):
			vein = {"galen_humors": "#b8302a", "theriac": "#c08a1c", "quicksilver": "#a8b0b8", "dragon_blood": "#2a7a3a"}[gid]
			vo = "0.95"
	p.append('<path d="M158 112 L166 170 L172 236 M62 112 L54 170" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="1.4"/>' % [vein, vo])
	# жилы — струны вдоль рук и ног
	for gid in ["gut_tendons", "wire_sinews", "stag_sinews"]:
		if have.has(gid):
			var sc: String = {"gut_tendons": "#b89a6a", "wire_sinews": "#9aa2aa", "stag_sinews": "#7a4a2a"}[gid]
			p.append('<path d="M150 130 L160 182 L168 240 M78 236 L86 380 M134 236 L128 380" fill="none" stroke="%s" stroke-width="1.6" stroke-dasharray="6 3"/>' % sc)
	# кожа: руны, мощи, тушь теней, чешуя
	if have.has("rune_tattoos"):
		p.append('<path d="M78 104 l6 8 l6 -8 M80 118 h8 M72 140 l4 6 l4 -6 l4 6" fill="none" stroke="#2a3e7a" stroke-width="1.4"/>')
	if have.has("saint_relic"):
		p.append('<path d="M96 150 v14 M90 156 h12" stroke="%s" stroke-width="1.6"/><path d="M92 148 l1 2 M100 148 l1 2 M92 165 l1 2 M100 165 l1 2" stroke="%s" stroke-width="0.9"/>' % [ink, ink])
	if have.has("shadow_ink"):
		p.append('<ellipse cx="132" cy="160" rx="9" ry="14" fill="#1a1418" fill-opacity="0.35"/>')
	if have.has("dragon_scales"):
		for i in 3:
			for j in 3:
				p.append('<path d="M%s %s q4 -4 8 0" fill="none" stroke="#3a6a3a" stroke-width="1.4"/>' % [_f(64.0 + j * 7.0 + (3.5 if i % 2 == 1 else 0.0)), _f(104.0 + i * 7.0)])
	# кости: железные скобы
	if have.has("iron_splints"):
		p.append('<path d="M120 300 h20 M120 340 h20 M44 196 h14" stroke="url(#steel)" stroke-width="3.2"/>')
	if have.has("giant_bones"):
		p.append('<path d="M84 240 L90 380 M136 240 L128 380" fill="none" stroke="#e8e0cc" stroke-width="2.4" stroke-opacity="0.9"/>')
	# руки (правая рука персонажа — слева от зрителя)
	if have.has("hook_hand"):
		p.append('<path d="M38 236 h14 v8 h-14 Z" fill="url(#steel)" stroke="%s"/><path d="M44 244 v8 q0 8 -6 8 q-6 0 -6 -6" fill="none" stroke="url(#steel)" stroke-width="3.2"/>' % ink)
	elif have.has("iron_hand"):
		p.append('<path d="M37 234 h16 l2 10 l-3 16 h-3 l-1 -10 l-2 11 h-3 l-1 -11 l-2 9 h-3 l-1 -14 Z" fill="url(#steel)" stroke="%s" stroke-width="0.9"/>' % ink)
		p.append('<circle cx="41" cy="239" r="1" fill="%s"/><circle cx="49" cy="239" r="1" fill="%s"/>' % [ink, ink])
	elif have.has("blade_arm"):
		p.append('<path d="M38 234 h14 v8 h-14 Z" fill="url(#steel)" stroke="%s"/><path d="M42 242 L46 242 L45 300 L44 306 L43 300 Z" fill="url(#steel)" stroke="%s" stroke-width="0.8"/>' % [ink, ink])
	elif have.has("clockwork_arm"):
		p.append('<path d="M36 200 L54 200 L52 244 L38 244 Z" fill="url(#gold)" stroke="%s" stroke-width="0.9"/>' % ink)
		p.append('<circle cx="45" cy="214" r="5" fill="none" stroke="%s" stroke-width="1.4" stroke-dasharray="2 1.5"/><circle cx="45" cy="214" r="1.6" fill="%s"/>' % [ink, ink])
		p.append('<path d="M38 244 h14 l1 12 h-16 Z" fill="url(#gold)" stroke="%s" stroke-width="0.9"/>' % ink)
	# ноги (левая нога персонажа — справа от зрителя): ниже колена
	if have.has("peg_leg"):
		p.append('<path d="M114 320 h26 l-4 8 h-18 Z" fill="url(#wood)" stroke="%s"/><path d="M123 328 h8 l-1 60 h-6 Z" fill="url(#wood)" stroke="%s"/>' % [ink, ink])
	elif have.has("iron_leg"):
		p.append('<path d="M115 318 h24 l-2 70 h-20 Z" fill="url(#steel)" stroke="%s" stroke-width="0.9"/><circle cx="127" cy="320" r="3.4" fill="url(#steel)" stroke="%s"/>' % [ink, ink])
		p.append('<path d="M116 350 h22 M117 370 h20" stroke="%s" stroke-width="0.8"/>' % ink)
	elif have.has("stag_legs"):
		p.append('<path d="M120 320 L118 386 M134 320 L136 386" fill="none" stroke="#7a4a2a" stroke-width="2"/>')
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [FIG_W, FIG_H, FIG_W, FIG_H] + "".join(p) + '</svg>'


static func figure_texture(game: Game, c: Dictionary) -> Texture2D:
	var key := "%s|%s|%s" % [c.id, str(Main.grafts_of(game, c).map(func(x): return x.id)), c.traits.has("iron_possession")]
	if _tex.has(key):
		return _tex[key]
	var img := Image.new()
	if img.load_svg_from_string(figure_svg(game, c), FIG_SCALE) != OK:
		img = Image.create(int(FIG_W * FIG_SCALE), int(FIG_H * FIG_SCALE), false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	if _tex.size() > 64:
		_tex.clear()
	_tex[key] = tex
	return tex


## Пунктир тушью от медальонов к месту на теле; на конце — красная пометка.
class InkLines extends Control:
	var segs: Array = []

	func _draw() -> void:
		var ink := Color("#3a2614")
		for sg in segs:
			var a: Vector2 = sg[0]
			var b: Vector2 = sg[1]
			var filled: bool = sg[2]
			var col := Color(ink, 0.75 if filled else 0.3)
			var mid := Vector2(lerpf(a.x, b.x, 0.35), a.y)
			draw_dashed_line(a, mid, col, 1.3, 5.0)
			draw_dashed_line(mid, b, col, 1.3, 5.0)
			if filled:
				draw_circle(b, 3.4, Color("#9a1c1c"))
				draw_circle(b, 1.3, Color("#f4ead0"))


## «Душа»: ромбы-лазуриты, пороги смятения и одержимости — крестиками.
class SoulBar extends Control:
	var value := 100.0
	var max_value := 100.0
	var troubled := 40.0
	var possession := 20.0

	func _draw() -> void:
		var n := 25
		var w := size.x / n
		var filled := roundi(clampf(value / maxf(1.0, max_value), 0.0, 1.0) * n)
		for i in n:
			var cx := w * (i + 0.5)
			var cy := size.y / 2.0
			var r := minf(w * 0.42, size.y * 0.5)
			var frac := float(i + 1) / n * max_value
			var col := Color("#2a4a8a")
			if frac <= possession:
				col = Color("#9a1c1c")
			elif frac <= troubled:
				col = Color("#b8801c")
			var pts := PackedVector2Array([Vector2(cx, cy - r), Vector2(cx + r * 0.7, cy), Vector2(cx, cy + r), Vector2(cx - r * 0.7, cy)])
			if i < filled:
				draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, Color("#3a2614", 0.7), 1.0, true)
		for th in [troubled, possession]:
			var x: float = th / maxf(1.0, max_value) * size.x
			draw_line(Vector2(x, -6), Vector2(x, -1), Color("#9a1c1c"), 1.5)
			draw_line(Vector2(x - 2.5, -3.5), Vector2(x + 2.5, -3.5), Color("#9a1c1c"), 1.5)


# ------------------------------------------------------------ лист

static func build(game: Game, cid: String, app: Object) -> Control:
	var c: Variant = game.ch(cid)
	var outer := PanelContainer.new()
	var sb := StyleBoxTexture.new()
	sb.texture = parchment_texture()
	sb.set_texture_margin_all(24)
	sb.set_content_margin_all(22)
	outer.add_theme_stylebox_override("panel", sb)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	outer.add_child(root)
	if c == null:
		root.add_child(_label("—", INK))
		return outer
	var is_me: bool = game.is_player(cid)
	# заглавие с красной буквицей
	var title := game.loc.t("grafts.ui_title")
	var head := _rich("[font_size=34][color=#9a1c1c]%s[/color][/font_size][font_size=24][color=#3a2614]%s[/color][/font_size]" % [BB.esc(title.substr(0, 1)), BB.esc(title.substr(1))])
	head.fit_content = true
	root.add_child(head)
	root.add_child(_rich("[i][color=#6b4e2e]%s[/color][/i]" % BB.esc(game.loc.t("grafts.ui_subtitle", {"name": Chars.full_name(game, c, true)}))))
	# фигура и части тела
	var cc := CenterContainer.new()
	cc.add_child(_body(game, c, app, is_me))
	root.add_child(cc)
	# душа
	root.add_child(_soul_block(game, c))
	# свойства
	var mods := Main.total_modifiers(game, c)
	var box := VBoxContainer.new()
	box.add_child(_label(game.loc.t("grafts.ui_effects", {"n": Main.grafts_of(game, c).size()}), RUBRIC, 15))
	if mods.is_empty():
		box.add_child(_label(game.loc.t("grafts.ui_no_grafts"), INK_SOFT, 14))
	else:
		box.add_child(_rich(ink_modifiers(game, mods)))
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(Color(PARCH_LIGHT, 0.6), Color(INK_SOFT, 0.6), 1, 2, 10))
	pc.add_child(box)
	root.add_child(pc)
	if is_me:
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 10)
		hb.add_child(K.button(game.loc.t("grafts.ui_workshop"), func(): open_shop(game, app, ""), {"icon": "hammer", "variation": "GoldButton", "min_w": 260}))
		if c.traits.has("iron_possession"):
			var cost := Main.exorcism_cost(game)
			var xb := K.button(game.loc.t("grafts.ui_exorcism", {"n": roundi(cost)}), func():
				var ch: Variant = game.ch(cid)
				if ch != null and Main.exorcise(game, ch):
					app.mark_dirty(true), {"icon": "cross", "disabled": float(c.gold) < cost, "min_w": 220})
			K.tip(xb, BB.title(game.loc.t("grafts.ui_exorcism", {"n": roundi(cost)})) + "\n" + BB.i(game.loc.t("grafts.ui_exorcism_tip")))
			hb.add_child(xb)
		root.add_child(hb)
	return outer


static func _body(game: Game, c: Dictionary, app: Object, is_me: bool) -> Control:
	var root := Control.new()
	root.custom_minimum_size = AREA
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	var fig := TextureRect.new()
	fig.texture = figure_texture(game, c)
	fig.position = FIG_POS
	fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fig)
	var lines := InkLines.new()
	lines.size = AREA
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lines)
	var left := []
	var right := []
	for s in Main.parts(game):
		if str(s.get("side", "left")) == "right":
			right.append(s)
		else:
			left.append(s)
	for col in [[left, 0.0], [right, AREA.x - GROUP_W]]:
		var arr: Array = col[0]
		var gx: float = col[1]
		var step := AREA.y / maxf(1.0, arr.size())
		for i in arr.size():
			var s: Dictionary = arr[i]
			var gy := 4.0 + i * step
			var grp := _group(game, c, s, app, is_me, gx > 0.0)
			grp.position = Vector2(gx, gy)
			root.add_child(grp)
			var zone: Array = Data.as_array(s.get("zone"))
			if zone.size() < 2:
				continue
			var to := FIG_POS + Vector2(float(zone[0]), float(zone[1])) * FIG_SCALE
			var n := Main.in_part(game, c, s.id).size()
			var cap := Main.capacity(game, s.id)
			var cells_w := float(cap * CELL + (cap - 1) * 6)
			var from := Vector2(gx + cells_w + 4.0, gy + 22.0 + CELL / 2.0) if gx == 0.0 else Vector2(gx + GROUP_W - cells_w - 4.0, gy + 22.0 + CELL / 2.0)
			lines.segs.append([from, to, n > 0])
	lines.queue_redraw()
	return root


## Часть тела: подпись тушью и медальоны вживлений.
static func _group(game: Game, c: Dictionary, s: Dictionary, app: Object, is_me: bool, right: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size.x = GROUP_W
	var items := Main.in_part(game, c, s.id)
	var name := _rich("[color=#3a2614]%s[/color] [color=#9a1c1c]%d/%d[/color]" % [BB.esc(game.name_of("body_parts", s.id)), items.size(), Main.capacity(game, s.id)])
	name.fit_content = true
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.custom_minimum_size = Vector2(GROUP_W, 20)
	if right:
		name.text = "[right]" + name.text + "[/right]"
	box.add_child(name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	for i in Main.capacity(game, s.id):
		var x: Variant = items[i] if i < items.size() else null
		row.add_child(_medallion(game, c, s, x, app, is_me))
	box.add_child(row)
	return box


static func _medallion(game: Game, c: Dictionary, s: Dictionary, x: Variant, app: Object, is_me: bool) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL, CELL)
	b.focus_mode = Control.FOCUS_NONE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(center)
	var r := CELL / 2
	if x != null:
		var d: Dictionary = Main.def_of(game, x.id)
		var col := tier_color(game, d.get("tier"))
		b.add_theme_stylebox_override("normal", _box(PARCH_LIGHT, col, 3, r))
		b.add_theme_stylebox_override("hover", _box(Color("#fff6dc"), col.lightened(0.2), 3, r))
		b.add_theme_stylebox_override("pressed", _box(PARCH, col, 3, r))
		var ic := Icons.node(d.get("icon", s.get("icon", "star")), 30, "ink")
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(ic)
		var gid: String = x.id
		var cid: String = c.id
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		K.tip(b, func(): return graft_tip(game, gid))
		b.pressed.connect(func(): open_detail(game, app, cid, gid))
	else:
		b.add_theme_stylebox_override("normal", _box(Color(PARCH_LIGHT, 0.35), Color(INK_SOFT, 0.35), 1, r))
		b.add_theme_stylebox_override("hover", _box(Color(PARCH_LIGHT, 0.7), Color(INK_SOFT, 0.8), 1, r))
		b.add_theme_stylebox_override("pressed", _box(PARCH, INK_SOFT, 1, r))
		var ic := Icons.node(s.get("icon", "star"), 24, "ink")
		ic.modulate = Color(1, 1, 1, 0.3)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(ic)
		K.tip(b, BB.muted(game.loc.t("grafts.ui_empty", {"part": game.name_of("body_parts", s.id)})) + ("\n" + BB.gold(game.loc.t("grafts.ui_click_install")) if is_me else ""))
		if is_me:
			var sid: String = s.id
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			b.pressed.connect(func(): open_shop(game, app, sid))
	return b


static func _soul_block(game: Game, c: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var h := Main.soul(game, c)
	var mx := Main.soul_max(game, c)
	var st := Main.status(game, c)
	var row := HBoxContainer.new()
	row.add_child(_label(game.loc.t("grafts.ui_soul"), INK, 17))
	row.add_child(_label("  %d / %d" % [roundi(h), roundi(mx)], INK_SOFT, 16))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(_label(game.loc.t("grafts.status_" + st), LAPIS if st == "whole" else (OCHRE if st == "troubled" else RUBRIC), 17))
	box.add_child(row)
	var bar := SoulBar.new()
	bar.custom_minimum_size = Vector2(0, 18)
	bar.value = h
	bar.max_value = mx
	bar.troubled = Main._n(game, "troubled_below", 40)
	bar.possession = Main._n(game, "possession_below", 20)
	K.tip(bar, BB.title(game.loc.t("grafts.ui_soul")) + "\n" + BB.i(game.loc.t("grafts.ui_soul_tip", {"t": roundi(bar.troubled), "p": roundi(bar.possession)})) +
		"\n" + BB.muted(game.loc.t("grafts.ui_soul_parts", {"base": roundi(Main._n(game, "soul_base", 100)), "traits": K.signed(roundi(mx - Main._n(game, "soul_base", 100))), "used": roundi(Main.soul_used(game, c))})))
	box.add_child(bar)
	return box


# ------------------------------------------------------------ окна (обычное оформление игры)

## Окно вживления: свойства, когда вживлено, извлечь (своё).
static func open_detail(game: Game, app: Object, cid: String, gid: String) -> void:
	var c: Variant = game.ch(cid)
	var d: Variant = Main.def_of(game, gid)
	if c == null or d == null:
		return
	var close_ref := [Callable()]
	var head := K.hbox([Icons.node(d.get("icon", "star"), 44), K.vbox([K.label(game.name_of("grafts", gid), "HeaderLabel"),
		K.label(game.loc.t("grafts.ui_work", {"part": game.name_of("body_parts", d.get("part")), "work": game.loc.t("grafts.tier_" + str(int(Data.num(d.get("tier"), 1))))}), "MutedLabel")], 0)], 12)
	var body := K.vbox([head, K.rich(graft_tip(game, gid, false))], 10)
	var x: Variant = null
	for it in Main.grafts_of(game, c):
		if it.id == gid:
			x = it
	if x != null:
		body.add_child(K.label(game.loc.t("grafts.ui_installed_on", {"date": CharacterPanel.fmt_date(app, int(x.date))}), "MutedLabel"))
	var row := K.hbox([K.expand()], 10)
	if game.is_player(cid) and x != null:
		var cost := Main.removal_cost(game)
		row.add_child(K.button(game.loc.t("grafts.ui_remove", {"n": roundi(cost)}), func():
			var ch: Variant = game.ch(cid)
			if ch != null and Main.remove(game, ch, gid, true):
				close_ref[0].call()
				app.mark_dirty(true), {"icon": "hammer", "disabled": float(c.gold) < cost, "min_w": 200}))
	row.add_child(K.button(game.loc.t("ui.close"), func(): close_ref[0].call(), {"min_w": 140}))
	row.add_child(K.expand())
	body.add_child(row)
	body.custom_minimum_size.x = 480
	close_ref[0] = app.modal(K.panel(K.margin(body, 14)))


## Мастерская цирюльника-хирурга: вживления по частям тела.
static func open_shop(game: Game, app: Object, part: String) -> void:
	var st := {"part": part}
	var close_ref := [Callable()]
	var box := K.vbox([], 10)
	box.custom_minimum_size.x = 680
	var render := [Callable()]
	render[0] = func():
		K.clear(box)
		var p: Variant = game.player
		if p == null:
			return
		box.add_child(K.label(game.loc.t("grafts.ui_workshop"), "HeaderLabel"))
		box.add_child(K.para(game.loc.t("grafts.ui_workshop_info", {"risk": roundi(Main.surgery_risk(game, p) * 100.0), "soul": roundi(Main.soul(game, p)), "gold": roundi(float(p.gold))}), "MutedLabel"))
		var fl := K.flow([], 4)
		fl.add_child(K.button(game.loc.t("grafts.ui_all"), func():
			st.part = ""
			render[0].call(), {"variation": "WindowTab", "toggled": st.part == ""}))
		for s in Main.parts(game):
			var sid: String = s.id
			fl.add_child(K.button(game.name_of("body_parts", sid), func():
				st.part = sid
				render[0].call(), {"variation": "WindowTab", "toggled": st.part == sid, "icon": s.get("icon", "star"), "icon_size": 16}))
		box.add_child(fl)
		var list := K.vbox([], 6)
		var defs: Array = game.content.all("grafts").filter(func(d): return st.part == "" or str(d.get("part")) == st.part)
		Data.sort_by(defs, func(d):
			var sd: Variant = game.content.get_def("body_parts", str(d.get("part")))
			return Data.num(sd.get("order") if sd != null else 99) * 100 + Data.num(d.get("tier")))
		for d in defs:
			list.add_child(_shop_card(game, d, func():
				render[0].call()
				app.mark_dirty(true)))
		var sc := K.scroll(list)
		sc.custom_minimum_size.y = 430
		box.add_child(sc)
		box.add_child(K.hbox([K.expand(), K.button(game.loc.t("ui.close"), func(): close_ref[0].call(), {"min_w": 140}), K.expand()]))
	render[0].call()
	close_ref[0] = app.modal(K.panel(K.margin(box, 14)))


static func _shop_card(game: Game, d: Dictionary, on_change: Callable) -> Control:
	var p: Dictionary = game.player
	var gid: String = d.id
	var col := tier_color(game, d.get("tier")).lightened(0.3)
	var name := K.label(game.name_of("grafts", gid), "SubheaderLabel")
	name.add_theme_color_override("font_color", col)
	var info := K.vbox([name, K.label(game.loc.t("grafts.ui_work", {"part": game.name_of("body_parts", d.get("part")), "work": game.loc.t("grafts.tier_" + str(int(Data.num(d.get("tier"), 1))))}), "SmallLabel"),
		K.rich(BB.modifiers(game, d.get("modifiers")))], 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not Data.as_array(d.get("cures")).is_empty():
		info.add_child(K.label(game.loc.t("grafts.ui_cures"), "GoodLabel"))
	var blk := Main.blockers(game, p, gid)
	var b := K.button(game.loc.t("grafts.ui_install"), func():
		var ch: Variant = game.player
		if ch != null and Main.install(game, ch, gid) != "":
			on_change.call(), {"variation": "GoldButton", "icon": "hammer", "disabled": not blk.is_empty(), "min_w": 140})
	if not blk.is_empty():
		K.tip(b, BB.reasons(blk))
	var right := K.vbox([K.rich(BB.cost(game, {"gold": Data.num(d.get("price"))})), K.label(game.loc.t("grafts.ui_soul_cost", {"n": roundi(Data.num(d.get("soul")))}), "BadLabel"), b], 4)
	var row := K.hbox([Icons.node(d.get("icon", "star"), 40), info, right], 10)
	var pc := K.panel(K.margin(row, 10, 6), "RowPanel")
	K.tip(info, func(): return graft_tip(game, gid))
	return pc

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

const AREA := Vector2(580, 500)
const FIG_W := 220
const FIG_H := 400
const FIG_SCALE := 1.2
const FIG_POS := Vector2(158, 8)
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
static func ink_modifiers(game: Game, mods: Variant, cols: int = 2) -> String:
	if not (mods is Dictionary) or mods.is_empty():
		return ""
	var out := "[table=%d]" % (cols * 2)
	var n := 0
	for k in mods:
		var v := float(mods[k])
		var is_bad := v > 0 if k == "stress_gain_mult" else v < 0
		out += "[cell expand=1][color=#3a2614]%s[/color][/cell][cell]   [color=%s]%s[/color]      [/cell]" % [
			BB.esc(game.loc.t_or("stat." + k, k)), "#9a1c1c" if is_bad else "#2e5a1c", BB.stat_value(k, v)]
		n += 1
	while n % cols != 0:
		out += "[cell][/cell][cell][/cell]"
		n += 1
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


## Буквица: лазурь в золотой рамке, белая вязь по углам.
static func initial_texture() -> Texture2D:
	if _tex.has("initial"):
		return _tex.initial
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="56" height="56" viewBox="0 0 56 56">'
	svg += '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f6dc8a"/><stop offset="1" stop-color="#a87418"/></linearGradient></defs>'
	svg += '<rect x="1" y="1" width="54" height="54" fill="url(#g)"/><rect x="4" y="4" width="48" height="48" fill="#2a4a8a"/>'
	svg += '<rect x="6" y="6" width="44" height="44" fill="none" stroke="#f4ead0" stroke-opacity="0.55" stroke-width="0.8"/>'
	for q in [[9, 9, 1, 1], [47, 9, -1, 1], [9, 47, 1, -1], [47, 47, -1, -1]]:
		svg += '<path d="M%d %d q%d 0 %d %d q0 %d %d %d" fill="none" stroke="#f4ead0" stroke-opacity="0.8" stroke-width="0.9"/>' % [q[0], q[1], 6 * q[2], 6 * q[2], 6 * q[3], 4 * q[3], -3 * q[2], 2 * q[3]]
		svg += '<circle cx="%d" cy="%d" r="1.1" fill="#f4ead0" fill-opacity="0.8"/>' % [q[0] + 2 * q[2], q[1] + 2 * q[3]]
	svg += '</svg>'
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	_tex["initial"] = ImageTexture.create_from_image(img)
	return _tex.initial


## Весы души: в левой чаше — душа, в правой — железо; коромысло клонится
## к железу, когда вживления тяжелее оставшейся души.
static func scales_texture(tilt: int) -> Texture2D:
	var key := "scales%d" % tilt
	if _tex.has(key):
		return _tex[key]
	var a := deg_to_rad(float(tilt))
	var pv := Vector2(42, 16)
	var r := pv + Vector2(cos(a), sin(a)) * 30.0
	var l := pv - Vector2(cos(a), sin(a)) * 30.0
	var ink := "#3a2614"
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="84" height="66" viewBox="0 0 84 66">'
	svg += '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6dc8a"/><stop offset="1" stop-color="#9a6a14"/></linearGradient></defs>'
	svg += '<path d="M42 16 V60 M31 61 H53" stroke="%s" stroke-width="2" stroke-linecap="round"/>' % ink
	svg += '<path d="M%s %s L%s %s" stroke="%s" stroke-width="2.2" stroke-linecap="round"/><circle cx="42" cy="16" r="2.4" fill="url(#g)" stroke="%s" stroke-width="0.8"/>' % [_f(l.x), _f(l.y), _f(r.x), _f(r.y), ink, ink]
	for e in [[l, true], [r, false]]:
		var pt: Vector2 = e[0]
		var py := pt.y + 24.0
		svg += '<path d="M%s %s L%s %s M%s %s L%s %s" stroke="%s" stroke-width="0.7"/>' % [_f(pt.x), _f(pt.y), _f(pt.x - 9), _f(py), _f(pt.x), _f(pt.y), _f(pt.x + 9), _f(py), ink]
		if e[1]:
			# душа — маленькая белая фигурка
			svg += '<circle cx="%s" cy="%s" r="2.2" fill="#fbf6ea" stroke="%s" stroke-width="0.6"/><path d="M%s %s q3 0 3 6 h-6 q0 -6 3 -6 Z" fill="#fbf6ea" stroke="%s" stroke-width="0.6"/>' % [_f(pt.x), _f(py - 9), ink, _f(pt.x), _f(py - 6.5), ink]
		else:
			# железо — гиря
			svg += '<path d="M%s %s h6 l2 7 h-10 Z" fill="#4a4e54" stroke="%s" stroke-width="0.6"/><circle cx="%s" cy="%s" r="1.4" fill="none" stroke="#4a4e54" stroke-width="1"/>' % [_f(pt.x - 3), _f(py - 7), ink, _f(pt.x), _f(py - 8.4)]
		svg += '<path d="M%s %s Q%s %s %s %s Z" fill="url(#g)" stroke="%s" stroke-width="0.8"/>' % [_f(pt.x - 11), _f(py), _f(pt.x), _f(py + 9), _f(pt.x + 11), _f(py), ink]
	svg += '</svg>'
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex


static func _f(x: float) -> String:
	return str(snappedf(x, 0.1))


## Фигура в духе лекарских трактатов (SVG 220×400): контур тушью,
## телесная заливка, штриховка тени, мышцы, волосы и борода. Вживления —
## прямо на теле; протез заменяет кисть, предплечье или голень (контур
## закрывается культёй). Одержимость — тёмный венец и бес, выходящий из уст.
const INK_HEX := "#3a2614"

# Левая половина силуэта (правая сторона персонажа) по частям: шея → плечо →
# рука → бок → нога → промежность. Правая половина — зеркальное отражение.
const HALF := [
	["neck", [["L", 100, 76]]],
	["shoulder", [["C", 92, 80, 74, 80, 64, 88], ["C", 54, 94, 50, 104, 50, 118]]],
	["upperarm_out", [["C", 48, 136, 44, 152, 42, 170]]],
	["forearm_out", [["C", 40, 196, 38, 218, 37, 238]]],
	["hand", [["C", 32, 243, 28, 249, 27, 255], ["C", 26, 259, 30, 261, 33, 257], ["C", 33, 265, 34, 273, 37, 279],
		["C", 40, 284, 47, 283, 48, 275], ["C", 50, 265, 51, 250, 50, 240]]],
	["forearm_in", [["C", 52, 222, 56, 196, 58, 176]]],
	["upperarm_in", [["C", 60, 158, 64, 140, 68, 122]]],
	["torso", [["C", 72, 140, 75, 160, 76, 178], ["C", 77, 192, 73, 204, 72, 214]]],
	["thigh_out", [["C", 71, 240, 76, 270, 78, 300]]],
	["calf_out", [["C", 78, 316, 76, 334, 80, 356], ["C", 82, 366, 84, 372, 84, 378]]],
	["foot", [["C", 80, 383, 72, 387, 70, 391], ["C", 70, 394, 74, 395, 78, 395], ["L", 98, 395], ["C", 101, 393, 101, 386, 100, 378]]],
	["calf_in", [["C", 100, 350, 102, 326, 100, 304]]],
	["thigh_in", [["C", 100, 280, 104, 256, 108, 238], ["L", 110, 235]]],
]
const HALF_START := [100, 62]
# культи: вместо кисти, предплечья с кистью, голени со стопой
const STUMPS := {
	"wrist": {"skip": ["hand"], "after": "forearm_out", "seg": ["C", 38, 246, 49, 248, 50, 240]},
	"elbow": {"skip": ["forearm_out", "hand", "forearm_in"], "after": "upperarm_out", "seg": ["C", 42, 182, 56, 186, 58, 176]},
	"knee": {"skip": ["calf_out", "foot", "calf_in"], "after": "thigh_out", "seg": ["C", 80, 314, 98, 316, 100, 304]},
}


## Сегменты левой половины с культями: [[start, seg], ...].
static func _half(stumps: Array) -> Array:
	var out := []
	var cur := Vector2(HALF_START[0], HALF_START[1])
	var skip := {}
	var extra := {}
	for s in stumps:
		var st: Dictionary = STUMPS[s]
		for k in st.skip:
			skip[k] = true
		extra[st.after] = st.seg
	for part in HALF:
		if not skip.has(part[0]):
			for seg in part[1]:
				out.append([cur, seg])
				cur = Vector2(seg[seg.size() - 2], seg[seg.size() - 1])
		if extra.has(part[0]):
			var seg: Array = extra[part[0]]
			out.append([cur, seg])
			cur = Vector2(seg[seg.size() - 2], seg[seg.size() - 1])
	return out


static func _seg_str(seg: Array, mirror: bool, start: Vector2) -> String:
	# зеркальная половина идёт в обратном порядке: конец сегмента — его начало
	var m := func(x: float) -> float: return 220.0 - x if mirror else x
	match str(seg[0]):
		"L":
			return "L%s %s " % [_f(m.call(start.x if mirror else float(seg[1]))), _f(start.y if mirror else float(seg[2]))]
		"C":
			if mirror:
				return "C%s %s %s %s %s %s " % [_f(m.call(float(seg[3]))), _f(seg[4]), _f(m.call(float(seg[1]))), _f(seg[2]), _f(m.call(start.x)), _f(start.y)]
			return "C%s %s %s %s %s %s " % [_f(seg[1]), _f(seg[2]), _f(seg[3]), _f(seg[4]), _f(seg[5]), _f(seg[6])]
	return ""


## Силуэт: левая половина (рука может быть культёй) и зеркальная правая
## (нога может быть культёй).
static func body_path(arm_stump: String, leg_stump: String) -> String:
	var left := _half([arm_stump] if arm_stump != "" else [])
	var right := _half([leg_stump] if leg_stump != "" else [])
	var d := "M%s %s " % [_f(HALF_START[0]), _f(HALF_START[1])]
	for it in left:
		d += _seg_str(it[1], false, it[0])
	for i in range(right.size() - 1, -1, -1):
		d += _seg_str(right[i][1], true, right[i][0])
	return d + "Z"


## Штриховка тени: короткие косые штрихи вдоль ломаной края, внутрь на dx.
static func _hatch(p: PackedStringArray, pts: Array, step: float, dx: float, op: float = 0.4) -> void:
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var n := maxi(1, int(a.distance_to(b) / step))
		for k in n:
			var q := a.lerp(b, (k + 0.5) / n)
			p.append('<path d="M%s %s l%s -5" stroke="%s" stroke-opacity="%s" stroke-width="0.7"/>' % [_f(q.x + dx), _f(q.y + 2.5), _f(-dx * 0.6), INK_HEX, op])


static func figure_svg(game: Game, c: Dictionary) -> String:
	var have := {}
	for x in Main.grafts_of(game, c):
		if Main.def_of(game, x.id) != null:
			have[str(x.id)] = true
	var possessed: bool = c.traits.has("iron_possession")
	var female: bool = bool(c.get("female", false))
	var adult := Chars.is_adult(game, c)
	var ink := INK_HEX
	var arm_stump := ""
	if have.has("blade_arm") or have.has("clockwork_arm"):
		arm_stump = "elbow"
	elif have.has("hook_hand") or have.has("iron_hand"):
		arm_stump = "wrist"
	var leg_stump := "knee" if have.has("peg_leg") or have.has("iron_leg") or have.has("stag_legs") else ""
	var p := PackedStringArray()
	p.append('<defs><linearGradient id="flesh" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#f0d8b4"/><stop offset="0.55" stop-color="#e6c49a"/><stop offset="1" stop-color="#cfa274"/></linearGradient>')
	p.append('<linearGradient id="steel" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#4a4e54"/><stop offset="0.5" stop-color="#c4cad2"/><stop offset="1" stop-color="#3e4248"/></linearGradient>')
	p.append('<linearGradient id="gold" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f6dc8a"/><stop offset="1" stop-color="#9a6a14"/></linearGradient>')
	p.append('<linearGradient id="wood" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#5a3a1c"/><stop offset="0.5" stop-color="#a8743e"/><stop offset="1" stop-color="#4a2e14"/></linearGradient></defs>')
	# одержимость: тёмный венец лучей вокруг головы
	if possessed:
		for i in 17:
			var a := deg_to_rad(-200.0 + i * 13.0)
			var r1 := 31.0 + (3.0 if i % 2 == 0 else 0.0)
			var r2 := r1 + (12.0 if i % 2 == 0 else 7.0)
			p.append('<path d="M%s %s L%s %s" stroke="#1e1018" stroke-opacity="0.75" stroke-width="%s" stroke-linecap="round"/>' % [_f(110 + cos(a) * r1), _f(38 + sin(a) * r1), _f(110 + cos(a) * r2), _f(38 + sin(a) * r2), "2.2" if i % 2 == 0 else "1.3"])
	# тело
	var body := body_path(arm_stump, leg_stump)
	p.append('<path d="%s" fill="url(#flesh)" stroke="%s" stroke-width="1.7" stroke-linejoin="round"/>' % [body, ink])
	# штриховка тени: правый бок, внутренняя сторона руки, внешняя сторона ноги
	_hatch(p, [[152, 124], [146, 160], [144, 178], [147, 210]], 5.5, -3.0)
	_hatch(p, [[170, 120], [176, 160], [178, 170]], 6.0, -2.5)
	if leg_stump == "":
		_hatch(p, [[148, 216], [146, 260], [142, 300], [143, 340], [136, 376]], 6.0, -3.0)
	else:
		_hatch(p, [[148, 216], [146, 260], [142, 298]], 6.0, -3.0)
	_hatch(p, [[106, 100], [106, 200]], 9.0, -2.0, 0.18)
	# мышцы и кости — тонкой тушью
	var lines := ["M100 84 Q86 84 70 90", "M120 84 Q134 84 150 90", "M110 100 L110 200", "M97 148 Q110 151 123 148", "M98 166 Q110 169 122 166",
		"M80 192 Q88 202 96 208", "M140 192 Q132 202 124 208", "M56 118 Q62 110 66 102", "M164 118 Q158 110 154 102",
		"M82 292 Q89 300 96 292", "M102 68 Q106 76 108 82", "M118 68 Q114 76 112 82"]
	if arm_stump == "":
		lines.append("M44 172 Q48 178 54 176")
	lines.append("M176 172 Q172 178 166 176")
	if leg_stump == "":
		lines.append_array(["M138 292 Q131 300 124 292", "M128 316 Q126 340 128 366"])
	lines.append("M92 316 Q94 340 92 366")
	if not female:
		lines.append_array(["M72 118 Q90 130 108 120", "M148 118 Q130 130 112 120"])
	for ln in lines:
		p.append('<path d="%s" fill="none" stroke="%s" stroke-opacity="0.5" stroke-width="0.9" stroke-linecap="round"/>' % [ln, ink])
	p.append('<ellipse cx="110" cy="186" rx="1.6" ry="2.3" fill="none" stroke="%s" stroke-opacity="0.7" stroke-width="0.9"/>' % ink)
	if not female:
		p.append('<circle cx="90" cy="123" r="1.2" fill="%s" fill-opacity="0.55"/><circle cx="130" cy="123" r="1.2" fill="%s" fill-opacity="0.55"/>' % [ink, ink])
	# пальцы и стопы
	if arm_stump == "":
		p.append('<path d="M38 266 L40 279 M42 266 L44 282 M46 265 L47 278" fill="none" stroke="%s" stroke-opacity="0.6" stroke-width="0.8"/>' % ink)
	p.append('<path d="M182 266 L180 279 M178 266 L176 282 M174 265 L173 278" fill="none" stroke="%s" stroke-opacity="0.6" stroke-width="0.8"/>' % ink)
	p.append('<path d="M76 391 v4 M81 392 v3 M86 392 v3 M91 392 v3" stroke="%s" stroke-opacity="0.6" stroke-width="0.8"/>' % ink)
	if leg_stump == "":
		p.append('<path d="M144 391 v4 M139 392 v3 M134 392 v3 M129 392 v3" stroke="%s" stroke-opacity="0.6" stroke-width="0.8"/>' % ink)
	# повязка на бёдрах (и на груди у женщин)
	p.append('<path d="M72 206 C92 212 128 212 148 206 L147 218 C136 230 124 240 116 252 C113 248 111 246 110 246 C109 246 107 248 104 252 C96 240 84 230 73 218 Z" fill="#f2ead6" stroke="%s" stroke-width="1"/>' % ink)
	p.append('<path d="M84 216 Q92 228 100 240 M136 216 Q128 228 120 240 M110 213 L110 244" fill="none" stroke="%s" stroke-opacity="0.4" stroke-width="0.7"/>' % ink)
	p.append('<path d="M72 206 C92 212 128 212 148 206" fill="none" stroke="%s" stroke-width="1.8"/><path d="M78 209 q-5 6 -2 12 M80 209 q2 7 -1 13" fill="none" stroke="%s" stroke-width="1"/>' % [ink, ink])
	if female:
		p.append('<path d="M74 110 C92 116 128 116 146 110 L147 128 C128 134 92 134 73 128 Z" fill="#f2ead6" stroke="%s" stroke-width="1"/>' % ink)
		p.append('<path d="M86 116 Q90 122 88 130 M134 116 Q130 122 132 130" fill="none" stroke="%s" stroke-opacity="0.4" stroke-width="0.7"/>' % ink)
	# голова
	if female:
		p.append('<path d="M89 40 C86 20 97 8 110 8 C123 8 134 20 131 40 C133 56 134 72 138 88 C130 90 126 84 126 74 C126 60 128 44 126 34 C121 26 116 24 110 24 C104 24 99 26 94 34 C92 44 94 60 94 74 C94 84 90 90 82 88 C86 72 87 56 89 40 Z" fill="#6a3e1c" stroke="%s" stroke-width="1"/>' % ink)
	p.append('<path d="M91 38 C91 22 99 13 110 13 C121 13 129 22 129 38 C129 51 125 59 119 64 C116 67 113 68 110 68 C107 68 104 67 101 64 C95 59 91 51 91 38 Z" fill="url(#flesh)" stroke="%s" stroke-width="1.6"/>' % ink)
	p.append('<path d="M91 36 C87 35 86 41 87 45 C88 49 91 49 92 47 M129 36 C133 35 134 41 133 45 C132 49 129 49 128 47" fill="url(#flesh)" stroke="%s" stroke-width="1.1"/>' % ink)
	var hair := "#6a3e1c" if female else "#4a2e18"
	p.append('<path d="M89 40 C86 22 97 9 110 9 C123 9 134 22 131 40 C129 32 126 26 121 23 C116 22 104 22 99 23 C94 26 91 32 89 40 Z" fill="%s" stroke="%s" stroke-width="1"/>' % [hair, ink])
	p.append('<path d="M93 32 q2 -4 5 -4 M100 24 q3 -3 6 -2 M114 23 q3 -1 6 1 M123 27 q3 0 5 4" fill="none" stroke="#8a5a30" stroke-width="0.9"/>')
	if female:
		p.append('<path d="M92 22 Q110 14 128 22" fill="none" stroke="#b8901c" stroke-width="1.4"/>')
	elif adult:
		p.append('<path d="M92 50 C93 60 99 71 110 73 C121 71 127 60 128 50 C125 56 120 60 117 60 C114 57 106 57 103 60 C100 60 95 56 92 50 Z" fill="%s" fill-opacity="0.92" stroke="%s" stroke-width="0.8"/>' % [hair, ink])
		p.append('<path d="M100 64 q2 4 1 7 M110 66 v6 M120 64 q-2 4 -1 7" fill="none" stroke="#8a5a30" stroke-width="0.7"/>')
	# лицо
	p.append('<path d="M97 34 Q102 31 107 33 M113 33 Q118 31 123 34" fill="none" stroke="%s" stroke-width="1.1"/>' % ink)
	var iris_l := ink
	var iris_r := ink
	var eye_graft := ""
	for gid in ["glass_eye", "crystal_eye", "ruby_eye", "raven_eye"]:
		if have.has(gid):
			eye_graft = gid
	if eye_graft != "":
		iris_l = {"glass_eye": "#5a8ac0", "crystal_eye": "#dce8f0", "ruby_eye": "#b01c2a", "raven_eye": "#141014"}[eye_graft]
	if possessed:
		iris_l = "#d01c1c"
		iris_r = "#d01c1c"
	for e in [[102, iris_l], [118, iris_r]]:
		p.append('<path d="M%d 40 Q%d 36.6 %d 40 Q%d 42.6 %d 40 Z" fill="#f6eede" stroke="%s" stroke-width="0.8"/>' % [e[0] - 5, e[0], e[0] + 5, e[0], e[0] - 5, ink])
		p.append('<circle cx="%d" cy="40" r="1.7" fill="%s"/>' % [e[0], e[1]])
	if eye_graft != "" and not possessed:
		p.append('<circle cx="102" cy="40" r="4.4" fill="none" stroke="#b8901c" stroke-width="1"/><circle cx="102.8" cy="39.3" r="0.5" fill="#ffffff"/>')
	p.append('<path d="M110 38 C109 44 107 48 107 50 Q110 52 113 50" fill="none" stroke="%s" stroke-width="0.9"/>' % ink)
	p.append('<path d="M105 59 Q110 61 115 59" fill="none" stroke="#5a1a14" stroke-width="1.1"/>')
	# уста
	if have.has("gold_teeth"):
		p.append('<path d="M106 59.6 h8" stroke="url(#gold)" stroke-width="2.2"/>')
	if have.has("silver_tongue"):
		p.append('<ellipse cx="110" cy="60" rx="2.6" ry="1" fill="#d8dee4" stroke="%s" stroke-width="0.4"/>' % ink)
	if have.has("iron_jaw"):
		p.append('<path d="M97 56 Q110 74 123 56 L122 63 Q110 80 98 63 Z" fill="url(#steel)" stroke="%s" stroke-width="0.8"/>' % ink)
		p.append('<circle cx="100" cy="61" r="0.8" fill="%s"/><circle cx="120" cy="61" r="0.8" fill="%s"/>' % [ink, ink])
	# голова: пластина, печать, руны, камень
	if have.has("trepan_plate"):
		p.append('<path d="M99 14 Q110 8 121 14 L119 19 Q110 14 101 19 Z" fill="url(#steel)" stroke="%s" stroke-width="0.8"/>' % ink)
		for q in [[102.5, 15.6], [110, 12.5], [117.5, 15.6]]:
			p.append('<circle cx="%s" cy="%s" r="0.8" fill="%s"/>' % [q[0], q[1], ink])
	if have.has("lead_seal"):
		p.append('<circle cx="93.5" cy="31" r="3.4" fill="#5a5e64" stroke="%s" stroke-width="0.8"/><path d="M92 31 h3 M93.5 29.5 v3" stroke="#c8ccd0" stroke-width="0.7"/>' % ink)
	if have.has("rune_of_tyr"):
		p.append('<path d="M100 31 V24 M97.2 26.8 L100 24 L102.8 26.8" fill="none" stroke="#9a1c1c" stroke-width="1.3"/>')
	if have.has("skull_runes"):
		p.append('<path d="M119 24 V31 M119 24 L122.5 26 L119 28 L122.5 31" fill="none" stroke="#2a3e7a" stroke-width="1.2"/>')
	if have.has("wisdom_stone"):
		p.append('<path d="M110 23.5 l3.4 4 l-3.4 4.6 l-3.4 -4.6 Z" fill="#3a6ab8" stroke="#b8901c" stroke-width="0.9"/>')
	# сердце, мощевик, швы
	var heart_fill := "#9a2a22"
	if have.has("lion_heart"):
		heart_fill = "url(#gold)"
	if have.has("star_iron_heart"):
		heart_fill = "url(#steel)"
	p.append('<path d="M120 117 Q118 112 116 109 M124 117 Q126 112 130 110" fill="none" stroke="#8a2420" stroke-width="0.9"/>')
	p.append('<path d="M122 134 C114 128 112 122 116 118 C119 115 122 117 122 120 C122 117 125 115 128 118 C132 122 130 128 122 134 Z" fill="%s" stroke="%s" stroke-width="0.8"/>' % [heart_fill, ink])
	if have.has("star_iron_heart"):
		p.append('<circle cx="119" cy="122" r="0.7" fill="%s"/><circle cx="125" cy="122" r="0.7" fill="%s"/>' % [ink, ink])
	if have.has("relic_heart"):
		p.append('<path d="M131 103 h7 v7 h-7 Z M131 103 l3.5 -3 l3.5 3" fill="url(#gold)" stroke="%s" stroke-width="0.6"/><path d="M134.5 104.5 v4 M133 106 h3" stroke="%s" stroke-width="0.6"/>' % [ink, ink])
	if have.has("lion_heart") or have.has("star_iron_heart") or have.has("relic_heart"):
		p.append('<path d="M113 140 h18 M115 138 v4 M119 138 v4 M123 138 v4 M127 138 v4" fill="none" stroke="#5a1a14" stroke-width="0.8"/>')
	# рёбра
	if have.has("silver_ribs"):
		for i in 4:
			var y := 132 + i * 8
			p.append('<path d="M78 %d Q88 %d 98 %d M142 %d Q132 %d 122 %d" fill="none" stroke="#c4cad2" stroke-width="1.4"/>' % [y, y + 5, y + 3, y, y + 5, y + 3])
	else:
		for i in 2:
			var y := 136 + i * 10
			p.append('<path d="M79 %d Q87 %d 93 %d M141 %d Q133 %d 127 %d" fill="none" stroke="%s" stroke-opacity="0.3" stroke-width="0.8"/>' % [y, y + 4, y + 2, y, y + 4, y + 2, ink])
	# кровь — жила на левой руке
	var vein := "#a8302a"
	var vo := "0.3"
	for gid in ["galen_humors", "theriac", "quicksilver", "dragon_blood"]:
		if have.has(gid):
			vein = {"galen_humors": "#b8302a", "theriac": "#c08a1c", "quicksilver": "#a8b0b8", "dragon_blood": "#2a7a3a"}[gid]
			vo = "0.95"
	p.append('<path d="M160 116 C164 140 168 156 170 174 C172 196 174 216 176 238" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="1.5"/>' % [vein, vo])
	if vo != "0.3":
		p.append('<path d="M170 174 l5 4 M172 200 l-4 5 M163 140 l5 -2" fill="none" stroke="%s" stroke-width="1"/>' % vein)
	# жилы — струны вдоль левого предплечья и бёдер
	for gid in ["gut_tendons", "wire_sinews", "stag_sinews"]:
		if have.has(gid):
			var sc: String = {"gut_tendons": "#b89a6a", "wire_sinews": "#8a929a", "stag_sinews": "#7a4a2a"}[gid]
			p.append('<path d="M166 178 C170 200 172 220 173 236 M172 174 C176 196 178 216 180 236 M83 238 C84 258 86 278 88 294 M137 238 C136 258 134 278 132 294" fill="none" stroke="%s" stroke-width="1.5" stroke-dasharray="5 2.5"/>' % sc)
	# кожа (правая сторона персонажа): руны, мощи, тушь теней, чешуя
	if have.has("rune_tattoos"):
		# футарк: альгиз, тейваз, отал и узорная лента
		p.append('<path d="M50 118 Q57 122 65 118 M50 121 Q57 125 65 121 M57 128 v10 M53 130 l4 4 l4 -4 M57 144 v10 M54 147 l3 -3 l3 3 M57 160 l-4 4.5 l4 4.5 l4 -4.5 Z M53 172 l4 -3.5 M61 172 l-4 -3.5" fill="none" stroke="#2a3e7a" stroke-width="1.3"/>')
	if have.has("saint_relic"):
		p.append('<path d="M92 140 v14 M86 146 h12" stroke="#b8901c" stroke-width="2"/><path d="M84 139 l2 2 M84 153 l2 2 M100 139 l-2 2 M100 153 l-2 2" stroke="%s" stroke-width="0.8"/>' % ink)
	if have.has("shadow_ink"):
		# тушь теней: полумесяц и звёзды на боку
		p.append('<path d="M90 156 C78 158 76 178 90 182 C82 176 82 162 90 156 Z" fill="#1a1418" fill-opacity="0.85"/>')
		p.append('<path d="M94 160 l1 2 l2 0.4 l-2 0.6 l-1 2 l-1 -2 l-2 -0.6 l2 -0.4 Z M93 180 l0.8 1.6 l1.6 0.3 l-1.6 0.5 l-0.8 1.6 l-0.8 -1.6 l-1.6 -0.5 l1.6 -0.3 Z" fill="#1a1418"/>')
	if have.has("dragon_scales"):
		for i in 3:
			for j in 3:
				p.append('<path d="M%s %s q3.5 -4 7 0" fill="none" stroke="#2e6a3a" stroke-width="1.4"/>' % [_f(57.0 + j * 6.5 + (3.2 if i % 2 == 1 else 0.0)), _f(98.0 + i * 6.5)])
	# кости: скобы на бедре, кости великана
	if have.has("giant_bones"):
		for q in [[89, 240, 92, 290], [131, 240, 128, 290]]:
			p.append('<path d="M%d %d L%d %d" stroke="#f4ecd8" stroke-width="3" stroke-linecap="round"/><circle cx="%d" cy="%d" r="2.6" fill="#f4ecd8"/><circle cx="%d" cy="%d" r="2.6" fill="#f4ecd8"/>' % [q[0], q[1], q[2], q[3], q[0], q[1], q[2], q[3]])
	if have.has("iron_splints"):
		p.append('<path d="M117 258 L146 256 M118 282 L144 280" stroke="url(#steel)" stroke-width="3.4"/>')
		for q in [[120, 258], [143, 256], [121, 282], [141, 280]]:
			p.append('<circle cx="%d" cy="%d" r="0.9" fill="%s"/>' % [q[0], q[1], ink])
	# правая рука персонажа (слева от зрителя)
	if have.has("hook_hand") or have.has("iron_hand"):
		p.append('<path d="M35 232 L52 234 L51 249 L37 248 Z" fill="url(#steel)" stroke="%s" stroke-width="0.9"/><path d="M36 238 L52 240 M36 244 L51 246" stroke="#5a3a1c" stroke-width="1.2"/>' % ink)
		if have.has("hook_hand"):
			p.append('<path d="M44 248 V262 C44 273 33 275 31 266" fill="none" stroke="url(#steel)" stroke-width="3.4" stroke-linecap="round"/><path d="M44 248 V262 C44 273 33 275 31 266" fill="none" stroke="%s" stroke-width="0.6"/>' % ink)
		else:
			p.append('<path d="M38 249 C33 252 28 255 27 259 C26 263 30 264 33 261 C33 268 34 275 37 280 C40 285 47 284 48 276 C50 267 51 257 50 249 Z" fill="url(#steel)" stroke="%s" stroke-width="0.9"/>' % ink)
			p.append('<path d="M38 266 L40 280 M42 266 L44 283 M46 265 L47 278 M36 258 h13" fill="none" stroke="%s" stroke-width="0.7"/>' % ink)
	elif have.has("blade_arm"):
		p.append('<path d="M40 166 L60 172 L56 210 L42 208 Z" fill="url(#steel)" stroke="%s" stroke-width="0.9"/><path d="M41 180 L59 185 M42 196 L57 199" stroke="#5a3a1c" stroke-width="1.4"/>' % ink)
		p.append('<path d="M38 208 L60 211" stroke="%s" stroke-width="2.4" stroke-linecap="round"/><path d="M46 211 L52 212 L50 296 L48 304 L46 296 Z" fill="url(#steel)" stroke="%s" stroke-width="0.8"/><path d="M49 214 L48.6 294" stroke="%s" stroke-opacity="0.5" stroke-width="0.6"/>' % [ink, ink, ink])
	elif have.has("clockwork_arm"):
		p.append('<path d="M41 168 L59 175 L51 240 L37 238 Z" fill="url(#gold)" stroke="%s" stroke-width="0.9"/>' % ink)
		p.append('<circle cx="49" cy="194" r="6" fill="none" stroke="%s" stroke-width="1.6" stroke-dasharray="2 1.4"/><circle cx="49" cy="194" r="1.8" fill="%s"/><circle cx="45" cy="220" r="4" fill="none" stroke="%s" stroke-width="1.3" stroke-dasharray="1.6 1.2"/>' % [ink, ink, ink])
		p.append('<path d="M38 240 C33 244 28 249 27 255 C26 259 30 261 33 257 C33 265 34 273 37 279 C40 284 47 283 48 275 C50 265 51 250 50 241 Z" fill="url(#gold)" stroke="%s" stroke-width="0.9"/><path d="M38 266 L40 279 M42 266 L44 282 M46 265 L47 278" fill="none" stroke="%s" stroke-width="0.7"/>' % [ink, ink])
	# левая нога персонажа (справа от зрителя): ниже колена
	if have.has("peg_leg"):
		p.append('<path d="M126 318 L134 318 L132 390 L128 390 Z" fill="url(#wood)" stroke="%s" stroke-width="0.9"/><path d="M126.5 389 h7 v5 h-7 Z" fill="#4a4e54" stroke="%s" stroke-width="0.7"/>' % [ink, ink])
		p.append('<path d="M117 292 L145 290 L141 316 C134 324 126 324 120 316 Z" fill="#7a4e28" stroke="%s" stroke-width="0.9"/><path d="M118 299 L144 297 M119 308 L142 306" stroke="#3a2210" stroke-width="1.3"/>' % ink)
	elif have.has("iron_leg"):
		p.append('<path d="M121 310 L141 308 L137 376 L123 376 Z" fill="url(#steel)" stroke="%s" stroke-width="0.9"/><path d="M122 330 L140 329 M123 352 L138 351" stroke="%s" stroke-width="0.7"/>' % [ink, ink])
		p.append('<path d="M122 376 L138 376 C142 382 148 388 150 393 L121 394 Z" fill="url(#steel)" stroke="%s" stroke-width="0.9"/><circle cx="131" cy="306" r="4.6" fill="url(#steel)" stroke="%s" stroke-width="0.9"/>' % [ink, ink])
	elif have.has("stag_legs"):
		p.append('<path d="M124 310 L137 310 L143 344 L133 386 L127 386 L134 346 Z" fill="#8a5a32" stroke="%s" stroke-width="0.9"/><path d="M130 312 L138 344 L130 384" fill="none" stroke="#c8a070" stroke-width="0.8" stroke-dasharray="3 2"/>' % ink)
		p.append('<path d="M126 386 L134 386 L137 394 L123 394 Z" fill="#2a1a0a"/><path d="M130 387 V394" stroke="#8a5a32" stroke-width="0.8"/><circle cx="131" cy="306" r="4.6" fill="url(#steel)" stroke="%s" stroke-width="0.9"/>' % ink)
	# одержимость: бес выходит из уст
	if possessed:
		p.append('<path d="M115 60 C126 64 132 54 140 56 C148 58 152 50 158 52" fill="none" stroke="#2a1426" stroke-opacity="0.55" stroke-width="2" stroke-linecap="round"/>')
		var imp := "#1a1012"
		p.append('<path d="M161 44 C154 36 150 40 145 35 C147 44 151 47 154 49 C156 47 158 49 161 49 Z M171 44 C178 36 182 40 187 35 C185 44 181 47 178 49 C176 47 174 49 171 49 Z" fill="%s"/>' % imp)
		p.append('<ellipse cx="166" cy="47" rx="5" ry="7" fill="%s"/><circle cx="166" cy="37" r="4.6" fill="%s"/>' % [imp, imp])
		p.append('<path d="M163 34 L160.5 28 L164.8 32.4 Z M169 34 L171.5 28 L167.2 32.4 Z" fill="%s"/>' % imp)
		p.append('<path d="M166 53 C168 60 174 60 172 66 M162 53 L160 58 M170 53 L172 58" fill="none" stroke="%s" stroke-width="1.3" stroke-linecap="round"/><path d="M170.5 64.5 L175 66 L171.5 69 Z" fill="%s"/>' % [imp, imp])
		p.append('<circle cx="164.4" cy="36.6" r="0.9" fill="#e02020"/><circle cx="167.6" cy="36.6" r="0.9" fill="#e02020"/>')
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [FIG_W, FIG_H, FIG_W, FIG_H] + "".join(p) + '</svg>'


static func figure_texture(game: Game, c: Dictionary) -> Texture2D:
	var key := "%s|%s|%s|%s" % [c.id, str(Main.grafts_of(game, c).map(func(x): return x.id)), c.traits.has("iron_possession"), Chars.is_adult(game, c)]
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
				# киноварное колечко — не закрывает само вживление
				draw_arc(b, 4.2, 0.0, TAU, 20, Color("#9a1c1c"), 1.6, true)


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
	# заглавие с буквицей: золото по лазури
	var title := game.loc.t("grafts.ui_title")
	var ini := TextureRect.new()
	ini.texture = initial_texture()
	ini.custom_minimum_size = Vector2(56, 56)
	var il := _label(title.substr(0, 1), Color("#f6dc8a"), 34)
	il.add_theme_color_override("font_outline_color", Color("#1a2a4a"))
	il.add_theme_constant_override("outline_size", 4)
	il.set_anchors_preset(Control.PRESET_FULL_RECT)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ini.add_child(il)
	var tb := VBoxContainer.new()
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_theme_constant_override("separation", 2)
	tb.add_child(_label(title.substr(1), INK, 26))
	tb.add_child(_rich("[i][color=#6b4e2e]%s[/color][/i]" % BB.esc(game.loc.t("grafts.ui_subtitle", {"name": Chars.full_name(game, c, true)}))))
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 4)
	th.add_child(ini)
	th.add_child(tb)
	root.add_child(th)
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
	var used := Main.soul_used(game, c)
	var scales := TextureRect.new()
	scales.texture = scales_texture(roundi(clampf((used - h) / maxf(1.0, mx) * 25.0, -25.0, 25.0)))
	scales.custom_minimum_size = Vector2(84, 66)
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
	var tip := BB.title(game.loc.t("grafts.ui_soul")) + "\n" + BB.i(game.loc.t("grafts.ui_soul_tip", {"t": roundi(bar.troubled), "p": roundi(bar.possession)})) + \
		"\n" + BB.muted(game.loc.t("grafts.ui_soul_parts", {"base": roundi(Main._n(game, "soul_base", 100)), "traits": K.signed(roundi(mx - Main._n(game, "soul_base", 100))), "used": roundi(used)}))
	K.tip(bar, tip)
	K.tip(scales, tip)
	box.add_child(bar)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.add_child(scales)
	hb.add_child(box)
	return hb


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

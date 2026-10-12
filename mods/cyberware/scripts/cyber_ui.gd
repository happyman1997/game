extends RefCounted
## Экран имплантов в неоновом стиле: голограмма тела, системы со слотами по
## бокам и линии к точкам вживления, шкала человечности, сводка эффектов;
## окно импланта (извлечь) и клиника потрошителя (вживить).

const Main := preload("main.gd")

const CYAN := Color("#39f3ff")
const MAGENTA := Color("#ff3c78")
const YELLOW := Color("#f3e600")
const BG := Color("#05080e")
const PANEL := Color("#0a131d")

const AREA := Vector2(580, 470)
const HOLO_W := 220
const HOLO_H := 400
const HOLO_SCALE := 1.1
const HOLO_POS := Vector2(169, 12)
const CELL := 50
const GROUP_W := 200

static var _tex := {}


static func register_icons() -> void:
	var D := "#1c140a"
	Icons.register("chip", '<rect x="6" y="6" width="12" height="12" rx="1.5"/><rect x="8.2" y="2.4" width="1.6" height="3.6"/><rect x="11.2" y="2.4" width="1.6" height="3.6"/><rect x="14.2" y="2.4" width="1.6" height="3.6"/><rect x="8.2" y="18" width="1.6" height="3.6"/><rect x="11.2" y="18" width="1.6" height="3.6"/><rect x="14.2" y="18" width="1.6" height="3.6"/><rect x="2.4" y="8.2" width="3.6" height="1.6"/><rect x="2.4" y="11.2" width="3.6" height="1.6"/><rect x="2.4" y="14.2" width="3.6" height="1.6"/><rect x="18" y="8.2" width="3.6" height="1.6"/><rect x="18" y="11.2" width="3.6" height="1.6"/><rect x="18" y="14.2" width="3.6" height="1.6"/><rect x="9.4" y="9.4" width="5.2" height="5.2" fill="%s"/>' % D)
	Icons.register("deck", '<rect x="2.5" y="5" width="19" height="14" rx="2"/><rect x="5" y="7.5" width="14" height="6" fill="%s"/><rect x="5" y="15" width="3" height="2" fill="%s"/><rect x="9.5" y="15" width="3" height="2" fill="%s"/><rect x="14" y="15" width="5" height="2" fill="%s"/>' % [D, D, D, D])
	Icons.register("optic", '<ellipse cx="12" cy="12" rx="10.8" ry="7.2"/><circle cx="12" cy="12" r="4.6" fill="%s"/><circle cx="12" cy="12" r="2.4"/><rect x="11.3" y="3.5" width="1.4" height="3"/><rect x="11.3" y="17.5" width="1.4" height="3"/>' % D)
	Icons.register("brain", '<path d="M12 4 C9 2.5 5.5 3.5 5 6.5 C2.5 7.5 2.5 11 4 12.5 C3 15 5 18 8 17.5 C9 19.5 11 20 12 19 C13 20 15 19.5 16 17.5 C19 18 21 15 20 12.5 C21.5 11 21.5 7.5 19 6.5 C18.5 3.5 15 2.5 12 4 Z"/><path d="M11.4 5 H12.6 V18.5 H11.4 Z M7.5 8 H10 V9.2 H7.5 Z M14 11 H16.5 V12.2 H14 Z M7.5 13.5 H10 V14.7 H7.5 Z" fill="%s"/>' % D)
	Icons.register("spine", '<rect x="8.5" y="2" width="7" height="3.6" rx="1.2"/><rect x="8" y="6.6" width="8" height="3.6" rx="1.2"/><rect x="7.5" y="11.2" width="9" height="3.6" rx="1.2"/><rect x="8" y="15.8" width="8" height="3.6" rx="1.2"/><path d="M10.5 20.4 H13.5 L12 22.5 Z"/>')
	Icons.register("hexskin", '<path d="M12 2 L20.5 7 V17 L12 22 L3.5 17 V7 Z"/><path d="M12 7.5 L16 9.8 V14.2 L12 16.5 L8 14.2 V9.8 Z" fill="%s"/>' % D)
	Icons.register("bone", '<path d="M6.5 3 A2.5 2.5 0 0 0 3 6.5 A2.5 2.5 0 0 0 6 9.5 L14.5 18 A2.5 2.5 0 0 0 17.5 21 A2.5 2.5 0 0 0 21 17.5 A2.5 2.5 0 0 0 18 14.5 L9.5 6 A2.5 2.5 0 0 0 6.5 3 Z"/>')
	Icons.register("cyberarm", '<path d="M2.5 20.5 L9 14 L11.5 11.5 L14 12.5 L16.5 10 L13.5 7 L11 9.5 L9 8.5 L2.5 15 Z"/><path d="M14.5 8 L21.8 1.8 L19.2 9.4 L16.8 10.8 Z"/><circle cx="10.5" cy="12.5" r="1.3" fill="%s"/>' % D)
	Icons.register("cyberhand", '<path d="M7 21 V13 L5 9.5 V7.5 A1.4 1.4 0 0 1 7.8 7.5 V10 V4.5 A1.4 1.4 0 0 1 10.6 4.5 V10 V3.5 A1.4 1.4 0 0 1 13.4 3.5 V10 V4.5 A1.4 1.4 0 0 1 16.2 4.5 V12 L18.5 9.5 A1.4 1.4 0 0 1 20.5 11.2 L16 17 V21 Z"/><circle cx="11.5" cy="15" r="1.6" fill="%s"/>' % D)
	Icons.register("cyberleg", '<path d="M9 2 H15 L14.5 11 L16 12.5 L15 20 H19 V22 H9 L10 12.5 L9.5 11 Z"/><circle cx="12.2" cy="11.8" r="1.6" fill="%s"/>' % D)
	Icons.register("glitch", '<path d="M3 4 H14 V7 H21 V10 H9 V13 H18 V16 H5 V19 H15 V21 H3 V17 H8 V14 H3 V11 H12 V8 H3 Z"/>')


static func tier_color(game: Game, tier: Variant) -> Color:
	var d: Variant = game.content.get_def("cyber_tiers", str(int(Data.num(tier, 1))))
	return Color(str(d.get("color", "#b8c2cc"))) if d != null else Color("#b8c2cc")


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


static func _neon_button(text: String, cb: Callable, color: Color = CYAN, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = disabled
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", _box(Color(color, 0.08), color, 1, 2, 8))
	b.add_theme_stylebox_override("hover", _box(Color(color, 0.2), color.lightened(0.2), 1, 2, 8))
	b.add_theme_stylebox_override("pressed", _box(Color(color, 0.3), color, 2, 2, 8))
	b.add_theme_stylebox_override("disabled", _box(Color(0.2, 0.25, 0.3, 0.2), Color(color, 0.25), 1, 2, 8))
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color.lightened(0.3))
	b.add_theme_color_override("font_disabled_color", Color(color, 0.35))
	b.pressed.connect(cb)
	return b


## Подсказка импланта: название цветом класса, система, человечность, эффекты.
static func implant_tip(game: Game, iid: String) -> String:
	var d: Variant = Main.def_of(game, iid)
	if d == null:
		return iid
	var col := tier_color(game, d.get("tier")).to_html(false)
	var bb := "[b][color=#%s]%s[/color][/b]" % [col, BB.esc(game.name_of("implants", iid))]
	bb += "\n" + BB.muted(game.loc.t("cyber.ui_class", {"system": game.name_of("cyber_systems", d.get("system")), "n": int(Data.num(d.get("tier"), 1))}))
	var desc := game.desc_of("implants", iid)
	if desc != "":
		bb += "\n" + BB.i(desc)
	bb += "\n" + BB.modifiers(game, d.get("modifiers"))
	if not Data.as_array(d.get("cures")).is_empty():
		bb += "\n" + BB.good(game.loc.t("cyber.ui_cures"))
	bb += "\n[color=#ff3c78]%s[/color]" % BB.esc(game.loc.t("cyber.ui_humanity_cost", {"n": roundi(Data.num(d.get("humanity")))}))
	return bb


# ------------------------------------------------------------ голограмма

## Голограмма тела (SVG 220×400): контур, мозг, позвоночник, рёбра, сердце;
## системы с имплантами подсвечены цветом лучшего импланта, киберпсихоз —
## красный сбой.
static func holo_svg(lit: Dictionary, psycho: bool) -> String:
	var c := "#39f3ff"
	var p := PackedStringArray()
	for x in range(0, HOLO_W + 1, 20):
		p.append('<path d="M%d 0 V%d" stroke="%s" stroke-opacity="0.05"/>' % [x, HOLO_H, c])
	for y in range(0, HOLO_H + 1, 20):
		p.append('<path d="M0 %d H%d" stroke="%s" stroke-opacity="0.05"/>' % [y, HOLO_W, c])
	var body := "M100 72 L100 84 Q72 86 62 96 L44 170 L36 240 Q38 256 47 250 L56 182 L70 122 L74 230 L82 388 L104 388 L108 252 L112 252 L116 388 L138 388 L146 230 L150 122 L164 182 L173 250 Q182 256 184 240 L176 170 L158 96 Q148 86 120 84 L120 72 Z"
	var head := "M110 22 A24 24 0 1 1 109.9 22 Z"
	if psycho:
		p.append('<g transform="translate(4,1)"><path d="%s" fill="none" stroke="#ff3c78" stroke-opacity="0.55" stroke-width="1.6"/><path d="%s" fill="none" stroke="#ff3c78" stroke-opacity="0.55" stroke-width="1.6"/></g>' % [body, head])
	for d in [body, head]:
		p.append('<path d="%s" fill="%s" fill-opacity="0.06" stroke="%s" stroke-opacity="0.18" stroke-width="6"/>' % [d, c, c])
		p.append('<path d="%s" fill="none" stroke="%s" stroke-opacity="0.9" stroke-width="1.5"/>' % [d, c])
	# мозг — дорожки схемы
	var bc: String = lit.get("frontal_cortex", lit.get("os", c))
	var bo := "0.95" if lit.has("frontal_cortex") or lit.has("os") else "0.45"
	p.append('<path d="M96 34 H104 V28 H112 M118 30 V38 H126 M100 42 H110 V48 M114 44 H122 M106 22 V30" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="1.2"/>' % [bc, bo])
	for q in [[104, 28], [126, 38], [110, 48], [122, 44], [96, 34]]:
		p.append('<circle cx="%d" cy="%d" r="1.6" fill="%s" fill-opacity="%s"/>' % [q[0], q[1], bc, bo])
	# глаза
	var ec: String = lit.get("ocular", c)
	var eo := "1" if lit.has("ocular") else "0.5"
	p.append('<circle cx="101" cy="50" r="2.6" fill="%s" fill-opacity="%s"/><circle cx="119" cy="50" r="2.6" fill="%s" fill-opacity="%s"/>' % [ec, eo, ec, eo])
	# позвоночник
	var nc: String = lit.get("nervous", c)
	p.append('<path d="M110 86 V236" stroke="%s" stroke-opacity="%s" stroke-width="2.4" stroke-dasharray="5 3"/>' % [nc, "0.95" if lit.has("nervous") else "0.4"])
	# рёбра и таз
	var sc: String = lit.get("skeleton", c)
	var so := "0.85" if lit.has("skeleton") else "0.3"
	for i in 5:
		var y := 108 + i * 12
		p.append('<path d="M110 %d Q%d %d %d %d M110 %d Q%d %d %d %d" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="1.3"/>' % [y, 86, y - 2, 80, y + 8, y, 134, y - 2, 140, y + 8, sc, so])
	p.append('<path d="M84 214 Q110 236 136 214 M90 206 Q110 224 130 206" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="1.4"/>' % [sc, so])
	# сердце
	var hc: String = lit.get("circulatory", "#ff3c78")
	var hs := "1" if lit.has("circulatory") else "0.45"
	p.append('<path d="M122 136 C114 130 112 124 116 120 C119 117 122 119 122 122 C122 119 125 117 128 120 C132 124 130 130 122 136 Z" fill="%s" fill-opacity="%s"/>' % [hc, hs])
	p.append('<path d="M122 136 C110 150 100 156 92 170 M122 120 C130 112 140 108 148 104" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="1"/>' % [hc, str(float(hs) * 0.6)])
	# кожа — соты на груди
	if lit.has("integumentary"):
		for i in 4:
			for j in 3:
				var x := 82.0 + i * 16.0 + (8.0 if j % 2 == 1 else 0.0)
				var y := 140.0 + j * 14.0
				p.append('<path d="M%s %s l6 -3.5 l6 3.5 v7 l-6 3.5 l-6 -3.5 Z" fill="none" stroke="%s" stroke-opacity="0.75" stroke-width="0.9"/>' % [_f(x), _f(y), lit.integumentary])
	# руки, кисти, ноги
	if lit.has("arms"):
		p.append('<path d="M62 96 L44 170 L56 182 L70 122" fill="none" stroke="%s" stroke-width="3" stroke-opacity="0.9"/><path d="M46 176 L30 150" stroke="%s" stroke-width="2.4"/>' % [lit.arms, lit.arms])
	if lit.has("hands"):
		p.append('<circle cx="178" cy="246" r="7" fill="none" stroke="%s" stroke-width="2.4"/>' % lit.hands)
	if lit.has("legs"):
		p.append('<path d="M116 252 L116 388 L138 388 L146 230" fill="none" stroke="%s" stroke-width="3" stroke-opacity="0.9"/><circle cx="128" cy="318" r="5" fill="none" stroke="%s" stroke-width="2"/>' % [lit.legs, lit.legs])
	# развёртка сканера
	for y in range(0, HOLO_H, 3):
		p.append('<path d="M0 %d H%d" stroke="#000" stroke-opacity="0.12"/>' % [y, HOLO_W])
	if psycho:
		for y in [64, 150, 232, 301]:
			p.append('<rect x="20" y="%d" width="180" height="3" fill="#ff3c78" fill-opacity="0.35"/>' % y)
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [HOLO_W, HOLO_H, HOLO_W, HOLO_H] + "".join(p) + '</svg>'


static func _f(x: float) -> String:
	return str(snappedf(x, 0.1))


static func holo_texture(game: Game, c: Dictionary) -> Texture2D:
	var lit := {}
	for s in Main.systems(game):
		var best := 0
		for x in Main.in_system(game, c, s.id):
			best = maxi(best, int(Data.num(Main.def_of(game, x.id).get("tier"), 1)))
		if best > 0:
			lit[s.id] = "#" + tier_color(game, best).to_html(false)
	var psycho: bool = c.traits.has("cyberpsychosis")
	var key := "%s|%s" % [str(lit), psycho]
	if _tex.has(key):
		return _tex[key]
	var img := Image.new()
	if img.load_svg_from_string(holo_svg(lit, psycho), HOLO_SCALE) != OK:
		img = Image.create(int(HOLO_W * HOLO_SCALE), int(HOLO_H * HOLO_SCALE), false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	if _tex.size() > 64:
		_tex.clear()
	_tex[key] = tex
	return tex


## Неоновые линии от систем к точкам на голограмме.
class Wires extends Control:
	var segs: Array = []

	func _draw() -> void:
		for sg in segs:
			var a: Vector2 = sg[0]
			var b: Vector2 = sg[1]
			var col: Color = sg[2]
			var mid := Vector2(lerpf(a.x, b.x, 0.35), a.y)
			draw_polyline(PackedVector2Array([a, mid, b]), Color(col, col.a * 0.35), 4.0, true)
			draw_polyline(PackedVector2Array([a, mid, b]), col, 1.4, true)
			draw_circle(b, 4.5, Color(col, col.a * 0.35))
			draw_circle(b, 2.4, col)


## Шкала человечности: сегменты, пороги нестабильности и киберпсихоза.
class HumanityBar extends Control:
	var value := 100.0
	var max_value := 100.0
	var unstable := 40.0
	var psycho := 20.0

	func _draw() -> void:
		var n := 50
		var gap := 2.0
		var w := (size.x - gap * (n - 1)) / n
		var filled := roundi(clampf(value / maxf(1.0, max_value), 0.0, 1.0) * n)
		for i in n:
			var frac := float(i + 1) / n * max_value
			var col := Color("#39f3ff")
			if frac <= psycho:
				col = Color("#ff3c78")
			elif frac <= unstable:
				col = Color("#f3e600")
			if i >= filled:
				col = Color(col, 0.12)
			draw_rect(Rect2(i * (w + gap), 0, w, size.y), col)
		for th in [unstable, psycho]:
			var x: float = th / maxf(1.0, max_value) * size.x
			draw_line(Vector2(x, -4), Vector2(x, size.y + 4), Color(1, 1, 1, 0.8), 1.5)


# ------------------------------------------------------------ экран

static func build(game: Game, cid: String, app: Object) -> Control:
	var c: Variant = game.ch(cid)
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", _box(BG, Color(CYAN, 0.55), 1, 3, 12))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	outer.add_child(root)
	if c == null:
		root.add_child(_label("—", CYAN))
		return outer
	var is_me: bool = game.is_player(cid)
	# шапка
	var title := _label("◢ " + game.loc.t("cyber.ui_title").to_upper(), CYAN, 24)
	var who := _label(Chars.full_name(game, c, true), Color(CYAN, 0.6), 15)
	var head := HBoxContainer.new()
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(who)
	root.add_child(head)
	var line := ColorRect.new()
	line.color = MAGENTA
	line.custom_minimum_size = Vector2(0, 2)
	root.add_child(line)
	# тело и системы
	var cc := CenterContainer.new()
	cc.add_child(_body(game, c, app, is_me))
	root.add_child(cc)
	# человечность
	root.add_child(_humanity_block(game, c))
	# сводка эффектов
	var mods := Main.total_modifiers(game, c)
	var sum := VBoxContainer.new()
	sum.add_child(_label(game.loc.t("cyber.ui_effects", {"n": Main.implants_of(game, c).size()}).to_upper(), Color(CYAN, 0.8), 14))
	if mods.is_empty():
		sum.add_child(_label(game.loc.t("cyber.ui_no_implants"), Color(CYAN, 0.45), 14))
	else:
		var rt := K.rich(BB.modifiers(game, mods))
		sum.add_child(rt)
	var sp2 := PanelContainer.new()
	sp2.add_theme_stylebox_override("panel", _box(PANEL, Color(CYAN, 0.25), 1, 2, 10))
	sp2.add_child(sum)
	root.add_child(sp2)
	if is_me:
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_child(_neon_button("⚕  " + game.loc.t("cyber.ui_clinic").to_upper(), func(): open_shop(game, app, ""), CYAN))
		root.add_child(hb)
	return outer


static func _body(game: Game, c: Dictionary, app: Object, is_me: bool) -> Control:
	var root := Control.new()
	root.custom_minimum_size = AREA
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	var holo := TextureRect.new()
	holo.texture = holo_texture(game, c)
	holo.position = HOLO_POS
	holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holo)
	var wires := Wires.new()
	wires.size = AREA
	wires.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wires)
	var left := []
	var right := []
	for s in Main.systems(game):
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
			var to := HOLO_POS + Vector2(float(zone[0]), float(zone[1])) * HOLO_SCALE
			var n := Main.in_system(game, c, s.id).size()
			var cells_w := float(Main.capacity(game, s.id) * CELL + (Main.capacity(game, s.id) - 1) * 6)
			var from := Vector2(gx + cells_w + 4.0, gy + 22.0 + CELL / 2.0) if gx == 0.0 else Vector2(gx + GROUP_W - cells_w - 4.0, gy + 22.0 + CELL / 2.0)
			var colr := CYAN
			var best := 0
			for x in Main.in_system(game, c, s.id):
				best = maxi(best, int(Data.num(Main.def_of(game, x.id).get("tier"), 1)))
			if best > 0:
				colr = tier_color(game, best)
			wires.segs.append([from, to, Color(colr, 0.85 if n > 0 else 0.3)])
	wires.queue_redraw()
	return root


## Группа системы: подпись и ячейки (вживлённые и свободные).
static func _group(game: Game, c: Dictionary, s: Dictionary, app: Object, is_me: bool, right: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size.x = GROUP_W
	var items := Main.in_system(game, c, s.id)
	var name := _label("%s  %d/%d" % [game.name_of("cyber_systems", s.id).to_upper(), items.size(), Main.capacity(game, s.id)], Color(CYAN, 0.85), 12)
	name.clip_text = true
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	name.custom_minimum_size.x = GROUP_W
	box.add_child(name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	for i in Main.capacity(game, s.id):
		var x: Variant = items[i] if i < items.size() else null
		row.add_child(_cell(game, c, s, x, app, is_me))
	box.add_child(row)
	return box


static func _cell(game: Game, c: Dictionary, s: Dictionary, x: Variant, app: Object, is_me: bool) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL, CELL)
	b.focus_mode = Control.FOCUS_NONE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(center)
	if x != null:
		var d: Dictionary = Main.def_of(game, x.id)
		var col := tier_color(game, d.get("tier"))
		b.add_theme_stylebox_override("normal", _box(Color(col, 0.12), col, 2, 2))
		b.add_theme_stylebox_override("hover", _box(Color(col, 0.25), col.lightened(0.3), 2, 2))
		b.add_theme_stylebox_override("pressed", _box(Color(col, 0.3), col, 2, 2))
		var ic := Icons.node(d.get("icon", s.get("icon", "chip")), 32, "neon")
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(ic)
		var iid: String = x.id
		var cid: String = c.id
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		K.tip(b, func(): return implant_tip(game, iid))
		b.pressed.connect(func(): open_detail(game, app, cid, iid))
	else:
		b.add_theme_stylebox_override("normal", _box(Color(PANEL, 0.8), Color(CYAN, 0.25), 1, 2))
		b.add_theme_stylebox_override("hover", _box(Color(CYAN, 0.08), Color(CYAN, 0.6), 1, 2))
		b.add_theme_stylebox_override("pressed", _box(Color(CYAN, 0.12), CYAN, 1, 2))
		var ic := Icons.node(s.get("icon", "chip"), 26, "neon_dim")
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(ic)
		K.tip(b, BB.muted(game.loc.t("cyber.ui_empty_slot", {"system": game.name_of("cyber_systems", s.id)})) + ("\n" + BB.gold(game.loc.t("cyber.ui_click_install")) if is_me else ""))
		if is_me:
			var sid: String = s.id
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			b.pressed.connect(func(): open_shop(game, app, sid))
	return b


static func _humanity_block(game: Game, c: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var h := Main.humanity(game, c)
	var mx := Main.humanity_max(game, c)
	var st := Main.status(game, c)
	var st_col: Color = {"stable": CYAN, "unstable": YELLOW, "critical": MAGENTA, "psycho": MAGENTA}.get(st, CYAN)
	var row := HBoxContainer.new()
	row.add_child(_label(game.loc.t("cyber.ui_humanity").to_upper(), CYAN, 15))
	row.add_child(_label("  %d / %d" % [roundi(h), roundi(mx)], Color.WHITE, 15))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(_label(game.loc.t("cyber.status_" + st).to_upper(), st_col, 15))
	box.add_child(row)
	var bar := HumanityBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.value = h
	bar.max_value = mx
	bar.unstable = Main._n(game, "unstable_below", 40)
	bar.psycho = Main._n(game, "psychosis_below", 20)
	K.tip(bar, BB.title(game.loc.t("cyber.ui_humanity")) + "\n" + BB.i(game.loc.t("cyber.ui_humanity_tip", {"u": roundi(bar.unstable), "p": roundi(bar.psycho)})) +
		"\n" + BB.muted(game.loc.t("cyber.ui_humanity_parts", {"base": roundi(Main._n(game, "humanity_base", 100)), "traits": K.signed(roundi(mx - Main._n(game, "humanity_base", 100))), "used": roundi(Main.humanity_used(game, c))})))
	box.add_child(bar)
	return box


# ------------------------------------------------------------ окна

static func _modal_panel(content: Control, width: int) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(BG, CYAN, 1, 3, 14))
	content.custom_minimum_size.x = width
	pc.add_child(content)
	return pc


## Окно импланта: эффекты, когда вживлён, извлечь (своё).
static func open_detail(game: Game, app: Object, cid: String, iid: String) -> void:
	var c: Variant = game.ch(cid)
	var d: Variant = Main.def_of(game, iid)
	if c == null or d == null:
		return
	var close_ref := [Callable()]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var col := tier_color(game, d.get("tier"))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(Icons.node(d.get("icon", "chip"), 48, "neon"))
	var nm := VBoxContainer.new()
	nm.add_child(_label(game.name_of("implants", iid), col, 22))
	nm.add_child(_label(game.loc.t("cyber.ui_class", {"system": game.name_of("cyber_systems", d.get("system")), "n": int(Data.num(d.get("tier"), 1))}), Color(CYAN, 0.6), 14))
	head.add_child(nm)
	box.add_child(head)
	box.add_child(K.rich(implant_tip(game, iid)))
	var x: Variant = null
	for it in Main.implants_of(game, c):
		if it.id == iid:
			x = it
	if x != null:
		var dp := GameDate.parts(int(x.date))
		box.add_child(_label(game.loc.t("cyber.ui_installed_on", {"date": "%d.%d.%d" % [dp.d, dp.m, dp.y]}), Color(CYAN, 0.55), 13))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	if game.is_player(cid) and x != null:
		var cost := Main.removal_cost(game)
		row.add_child(_neon_button(game.loc.t("cyber.ui_remove", {"n": roundi(cost)}).to_upper(), func():
			var ch: Variant = game.ch(cid)
			if ch != null and Main.remove(game, ch, iid, true):
				close_ref[0].call()
				app.mark_dirty(true), MAGENTA, float(c.gold) < cost))
	row.add_child(_neon_button(game.loc.t("ui.close").to_upper(), func(): close_ref[0].call(), CYAN))
	box.add_child(row)
	close_ref[0] = app.modal(_modal_panel(box, 480))


## Клиника потрошителя: импланты по системам — цена, человечность, эффекты.
static func open_shop(game: Game, app: Object, system: String) -> void:
	var st := {"system": system}
	var close_ref := [Callable()]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var render := [Callable()]
	render[0] = func():
		for ch in box.get_children():
			ch.queue_free()
		var p: Variant = game.player
		if p == null:
			return
		box.add_child(_label("⚕ " + game.loc.t("cyber.ui_clinic").to_upper(), CYAN, 22))
		box.add_child(_label(game.loc.t("cyber.ui_clinic_info", {"risk": roundi(Main.surgery_risk(game, p) * 100.0), "h": roundi(Main.humanity(game, p)), "gold": roundi(float(p.gold))}), Color(CYAN, 0.65), 14))
		# фильтр по системам
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 4)
		fl.add_theme_constant_override("v_separation", 4)
		var all_b := _neon_button(game.loc.t("cyber.ui_all"), func():
			st.system = ""
			render[0].call(), YELLOW if st.system == "" else CYAN)
		fl.add_child(all_b)
		for s in Main.systems(game):
			var sid: String = s.id
			fl.add_child(_neon_button(game.name_of("cyber_systems", sid), func():
				st.system = sid
				render[0].call(), YELLOW if st.system == sid else CYAN))
		box.add_child(fl)
		# список
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 6)
		var defs: Array = game.content.all("implants").filter(func(d): return st.system == "" or str(d.get("system")) == st.system)
		Data.sort_by(defs, func(d):
			var sd: Variant = game.content.get_def("cyber_systems", str(d.get("system")))
			return Data.num(sd.get("order") if sd != null else 99) * 100 + Data.num(d.get("tier")))
		for d in defs:
			list.add_child(_shop_card(game, app, d, func():
				render[0].call()
				app.mark_dirty(true)))
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size = Vector2(0, 430)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(list)
		box.add_child(sc)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(_neon_button(game.loc.t("ui.close").to_upper(), func(): close_ref[0].call(), CYAN))
		box.add_child(row)
	render[0].call()
	close_ref[0] = app.modal(_modal_panel(box, 700))


static func _shop_card(game: Game, app: Object, d: Dictionary, on_change: Callable) -> Control:
	var p: Dictionary = game.player
	var iid: String = d.id
	var col := tier_color(game, d.get("tier"))
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(PANEL, Color(col, 0.6), 1, 2, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pc.add_child(row)
	var ic := Icons.node(d.get("icon", "chip"), 40, "neon")
	row.add_child(ic)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	info.add_child(_label(game.name_of("implants", iid), col, 17))
	info.add_child(_label(game.loc.t("cyber.ui_class", {"system": game.name_of("cyber_systems", d.get("system")), "n": int(Data.num(d.get("tier"), 1))}), Color(CYAN, 0.55), 13))
	var rt := K.rich(BB.modifiers(game, d.get("modifiers")))
	info.add_child(rt)
	if not Data.as_array(d.get("cures")).is_empty():
		info.add_child(_label(game.loc.t("cyber.ui_cures"), Color("#6ee08a"), 13))
	row.add_child(info)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(_label("%d ⛁" % roundi(Data.num(d.get("price"))), YELLOW, 16))
	right.add_child(_label(game.loc.t("cyber.ui_humanity_cost", {"n": roundi(Data.num(d.get("humanity")))}), MAGENTA, 13))
	var blk := Main.blockers(game, p, iid)
	var b := _neon_button(game.loc.t("cyber.ui_install").to_upper(), func():
		var ch: Variant = game.player
		if ch != null and Main.install(game, ch, iid) != "":
			on_change.call(), CYAN, not blk.is_empty())
	if not blk.is_empty():
		K.tip(b, BB.reasons(blk))
	right.add_child(b)
	row.add_child(right)
	K.tip(info, func(): return implant_tip(game, iid))
	return pc

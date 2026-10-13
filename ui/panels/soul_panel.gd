class_name SoulPanel
extends RefCounted
## Вкладка «Свет и Пепел»: миниатюра в духе рукописи — слева Император-Солнце
## в золоте, справа разлом в пепле с ликом Князя Пепла, внизу весы, чей
## язычок клонится к Свету или к Пеплу. Ниже — ступень души и «Книга деяний».
## Свою карму персонаж знает точно, чужую — лишь по ступени.

const W_ := 600
const H_ := 320
const TILT := 12.0          # наибольший наклон коромысла, градусы
const DIAL := 64.0          # наибольший наклон язычка на шкале, градусы
const PIVOT := Vector2(300, 250)

static var _tex := {}


static func build(app: App, c: Dictionary) -> Control:
	var g := app.game
	var root := K.vbox([], 10)
	if not g.engine.has_feature("karma"):
		return root
	var p: Variant = g.player
	var exact := Karma.knows_exact(g, c, p)
	var k := Karma.value(c)
	var lvl := Karma.tier_level(g, c)
	var t: Variant = Karma.tier_at(g, lvl)
	var shown := k if exact else _tier_mid(g, lvl)
	# миниатюра
	var pic := TextureRect.new()
	pic.texture = texture(g, shown)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(W_, H_) * 0.95
	K.tip(pic, BB.title(app.t("ui.soul")) + "\n" + BB.i(app.t("ui.soul_tip")))
	var caps := K.hbox([], 0)
	for pair in [["ui.soul_light", "GoldLabel"], ["ui.soul_ash", "MutedLabel"]]:
		var cc := _centered(K.label(app.t(pair[0]), pair[1]))
		cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caps.add_child(cc)
	caps.custom_minimum_size.x = W_ * 0.95
	root.add_child(K.panel(K.vbox([_centered(pic), _centered(caps)], 2), "InsetPanel"))
	# ступень
	if t != null:
		var head := K.hbox([K.icon(t.get("icon", "piety"), 22), K.label(g.name_of("karma_tiers", t.id), "SubheaderLabel")], 6)
		if exact:
			var val := K.rich(BB.good(app.t("ui.soul_value_light", {"n": roundi(k)})) if k > 0.0 else (BB.bad(app.t("ui.soul_value_ash", {"n": roundi(-k)})) if k < 0.0 else BB.muted(app.t("ui.soul_value_none"))), false)
			head.add_child(K.expand())
			head.add_child(val)
		var box := K.vbox([head], 4)
		var d := g.desc_of("karma_tiers", t.id)
		if d != "":
			box.add_child(K.para(d, "MutedLabel"))
		if t.get("modifiers") is Dictionary and not t.modifiers.is_empty():
			box.add_child(K.rich(BB.modifiers(g, t.modifiers), false))
		if not exact:
			box.add_child(K.para(app.t("ui.soul_hidden"), "MutedLabel"))
		root.add_child(K.panel(box, "InsetPanel"))
	# Книга деяний
	if exact:
		var lines := K.vbox([], 3)
		var log: Array = Data.as_array(c.vars.get("karma_log")).duplicate()
		log.reverse()
		for e in log:
			var dv: float = float(e[1])
			var name := app.t("karma_deed." + str(e[2])) if str(e[2]) != "" else app.t("karma_deed.other")
			var amount := ("+%d" % roundi(dv)) if dv > 0.0 else ("−%d" % roundi(-dv))
			var row := K.hbox([K.label(CharacterPanel.fmt_date(app, int(e[0])), "SmallLabel"), K.label(name), K.expand(),
				K.rich(BB.good(amount) if dv > 0.0 else BB.bad(amount), false)], 8)
			lines.add_child(row)
		if log.is_empty():
			lines.add_child(K.label(app.t("ui.soul_book_empty"), "MutedLabel"))
		lines.add_child(K.para(app.t("ui.soul_cleanse_hint"), "MutedLabel"))
		root.add_child(K.section(app.t("ui.soul_book"), [lines], "book"))
	return root


## Середина ступени — куда клонятся весы для того, кто видит лишь ступень.
static func _tier_mid(g: Game, lvl: int) -> float:
	var ts := Karma.tiers(g)
	var mx := Karma.max_value(g)
	if lvl < 0 or lvl >= ts.size():
		return 0.0
	var lo: float = Data.num(ts[lvl].get("min"), -mx)
	var hi: float = Data.num(ts[lvl + 1].get("min"), mx) - 1.0 if lvl + 1 < ts.size() else mx
	return (lo + hi) / 2.0


static func _centered(child: Control) -> Control:
	var cc := CenterContainer.new()
	cc.add_child(child)
	return cc


static func texture(g: Game, k: float) -> Texture2D:
	var key := "%d|%d" % [roundi(k), Karma.tiers(g).size()]
	if _tex.has(key):
		return _tex[key]
	var img := Image.new()
	if img.load_svg_from_string(svg(g, k), 1.0) != OK:
		img = Image.create(W_, H_, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	if _tex.size() > 32:
		_tex.clear()
	_tex[key] = tex
	return tex


# ------------------------------------------------------------ миниатюра

static func _pt(v: Vector2) -> String:
	return "%.1f %.1f" % [v.x, v.y]


## Наклон коромысла для кармы k (Свет перевешивает — левая чаша ниже).
static func _angle(g: Game, k: float) -> float:
	return deg_to_rad(-clampf(k / Karma.max_value(g), -1.0, 1.0) * TILT)


## Угол язычка на шкале (влево — к Свету).
static func _dial(g: Game, k: float) -> float:
	return deg_to_rad(-clampf(k / Karma.max_value(g), -1.0, 1.0) * DIAL)


static func _rot(v: Vector2, a: float) -> Vector2:
	return Vector2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a))


static func svg(g: Game, k: float) -> String:
	var s := PackedStringArray()
	s.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [W_, H_, W_, H_])
	s.append('''<defs>
<linearGradient id="parch" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#efe3c2"/><stop offset="1" stop-color="#d9c596"/></linearGradient>
<radialGradient id="glow" cx="0.5" cy="0.4" r="0.6"><stop offset="0" stop-color="#fff4b8" stop-opacity="0.95"/><stop offset="0.6" stop-color="#f3d77a" stop-opacity="0.35"/><stop offset="1" stop-color="#f3d77a" stop-opacity="0"/></radialGradient>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbe9a0"/><stop offset="0.55" stop-color="#e2b54a"/><stop offset="1" stop-color="#a8742a"/></linearGradient>
<linearGradient id="ash" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5a524c"/><stop offset="1" stop-color="#2b2420"/></linearGradient>
<linearGradient id="rift" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#120d0b"/><stop offset="0.5" stop-color="#2c1a12"/><stop offset="1" stop-color="#0e0a08"/></linearGradient>
<radialGradient id="ember" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#ffb04a"/><stop offset="0.5" stop-color="#ff5a12" stop-opacity="0.6"/><stop offset="1" stop-color="#ff3a00" stop-opacity="0"/></radialGradient>
</defs>''')
	# пергамент и рамка
	s.append('<rect x="2" y="2" width="596" height="316" rx="10" fill="url(#parch)" stroke="#6b4a1c" stroke-width="3"/>')
	s.append('<rect x="11" y="11" width="578" height="298" rx="6" fill="none" stroke="#b8862e" stroke-width="1.4"/>')
	for cpt in [Vector2(11, 11), Vector2(589, 11), Vector2(11, 309), Vector2(589, 309)]:
		s.append('<path d="M%s l6 6 l-6 6 l-6 -6 Z" fill="#c8962e" stroke="#6b4a1c" stroke-width="0.8"/>' % _pt(cpt + Vector2(0, -6)))
	# левая половина: свет
	s.append('<rect x="16" y="16" width="284" height="214" fill="#f6e7b0" opacity="0.55"/>')
	s.append('<ellipse cx="156" cy="96" rx="140" ry="112" fill="url(#glow)"/>')
	_emperor(s, Vector2(156, 0))
	# правая половина: пепел и разлом
	s.append('<rect x="300" y="16" width="284" height="214" fill="url(#ash)" opacity="0.85"/>')
	_rift(s)
	# граница миров — тонкая золотая черта
	s.append('<path d="M300 16 V230" stroke="#b8862e" stroke-width="1.2" stroke-dasharray="4 3"/>')
	s.append('<path d="M16 230 H584" stroke="#6b4a1c" stroke-width="1.2"/>')
	_scales(s, g, k)
	s.append('</svg>')
	return "".join(s)


## Император-Солнце: солнечный диск-нимб, лучи, лик и одеяние, руки воздеты.
static func _emperor(s: PackedStringArray, o: Vector2) -> void:
	var c := Vector2(156, 74)
	for i in 24:
		var a := TAU * i / 24.0
		var r1 := 44.0 if i % 2 == 0 else 40.0
		var r2 := 92.0 if i % 2 == 0 else 70.0
		var w := 0.07
		var p1 := c + Vector2(cos(a - w), sin(a - w)) * r1
		var p2 := c + Vector2(cos(a), sin(a)) * r2
		var p3 := c + Vector2(cos(a + w), sin(a + w)) * r1
		s.append('<path d="M%s L%s L%s Z" fill="url(#gold)" stroke="#8a5e1c" stroke-width="0.6" opacity="0.9"/>' % [_pt(p1), _pt(p2), _pt(p3)])
	s.append('<circle cx="156" cy="74" r="40" fill="url(#gold)" stroke="#7a5520" stroke-width="1.5"/>')
	s.append('<circle cx="156" cy="74" r="33" fill="none" stroke="#fff1b0" stroke-width="1" opacity="0.8"/>')
	# одеяние
	s.append('<path d="M156 96 C140 98 128 108 124 124 L106 226 H206 L188 124 C184 108 172 98 156 96 Z" fill="url(#gold)" stroke="#7a5520" stroke-width="1.4"/>')
	s.append('<path d="M156 110 V226 M142 130 L132 226 M170 130 L180 226" stroke="#9a6a24" stroke-width="1" fill="none" opacity="0.7"/>')
	s.append('<path d="M128 150 H184" stroke="#fff1b0" stroke-width="2" opacity="0.6"/>')
	# руки воздеты к солнцу
	s.append('<path d="M130 116 C118 100 112 84 108 64 L116 62 C120 80 128 94 140 108 Z" fill="url(#gold)" stroke="#7a5520" stroke-width="1.2"/>')
	s.append('<path d="M182 116 C194 100 200 84 204 64 L196 62 C192 80 184 94 172 108 Z" fill="url(#gold)" stroke="#7a5520" stroke-width="1.2"/>')
	# лик
	s.append('<circle cx="156" cy="80" r="15" fill="#f8dc84" stroke="#7a5520" stroke-width="1.3"/>')
	s.append('<path d="M149.5 78.5 q2 -1.4 4 0 M158.5 78.5 q2 -1.4 4 0 M156 80 v4 M153.5 88 h5" stroke="#7a5520" stroke-width="1.1" fill="none" stroke-linecap="round"/>')
	s.append('<path d="M144 86 C146 98 166 98 168 86 C164 92 148 92 144 86 Z" fill="#f0c860" stroke="#7a5520" stroke-width="0.9"/>')
	# венец из пламени
	s.append('<path d="M142 68 L146 56 L150 64 L156 50 L162 64 L166 56 L170 68 Z" fill="#ffd34a" stroke="#7a5520" stroke-width="1.1"/>')


## Разлом с ликом Князя Пепла и пепел вокруг.
static func _rift(s: PackedStringArray) -> void:
	var pts := [Vector2(432, 18), Vector2(458, 18), Vector2(474, 58), Vector2(464, 92), Vector2(492, 132), Vector2(470, 172), Vector2(480, 228),
		Vector2(408, 228), Vector2(420, 182), Vector2(396, 140), Vector2(424, 100), Vector2(410, 58)]
	var d := "M" + " L".join(pts.map(func(v): return _pt(v))) + " Z"
	s.append('<path d="%s" fill="#ff5a12" opacity="0.25" transform="translate(-3 0) scale(1.012 1)"/>' % d)
	s.append('<path d="%s" fill="url(#rift)" stroke="#a8461a" stroke-width="1.6" stroke-opacity="0.8"/>' % d)
	# лик: рога, глаза-угли, рот
	s.append('<path d="M424 104 C410 92 408 74 418 62 C418 78 424 88 434 96 Z" fill="#3a2a22" stroke="#7a3a1a" stroke-width="0.9"/>')
	s.append('<path d="M464 104 C478 92 480 74 470 62 C470 78 464 88 454 96 Z" fill="#3a2a22" stroke="#7a3a1a" stroke-width="0.9"/>')
	s.append('<path d="M424 112 C430 104 458 104 464 112 C462 140 452 152 444 154 C436 152 426 140 424 112 Z" fill="#1e1410" stroke="#5a2a14" stroke-width="1"/>')
	for e in [Vector2(434, 120), Vector2(454, 120)]:
		s.append('<circle cx="%.1f" cy="%.1f" r="10" fill="url(#ember)"/>' % [e.x, e.y])
		s.append('<ellipse cx="%.1f" cy="%.1f" rx="5.5" ry="2.2" fill="#ffcf6a"/>' % [e.x, e.y])
	s.append('<path d="M434 138 Q444 144 454 138" stroke="#c0501a" stroke-width="1.4" fill="none" opacity="0.8"/>')
	# хлопья пепла
	var rng := RandomNumberGenerator.new()
	rng.seed = 1066
	for i in 40:
		var x := rng.randf_range(306, 580)
		var y := rng.randf_range(20, 226)
		if absf(x - 444) < 34 and y > 30:
			continue
		s.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#c8c0b8" opacity="%.2f"/>' % [x, y, rng.randf_range(0.8, 2.2), rng.randf_range(0.25, 0.7)])
	for i in 8:
		var x2 := rng.randf_range(400, 490)
		var y2 := rng.randf_range(30, 220)
		s.append('<circle cx="%.1f" cy="%.1f" r="1.3" fill="#ff7a2a" opacity="%.2f"/>' % [x2, y2, rng.randf_range(0.4, 0.9)])


## Весы: шкала ступеней, коромысло с чашами, язычок с отметкой персонажа.
static func _scales(s: PackedStringArray, g: Game, k: float) -> void:
	var mx := Karma.max_value(g)
	var ts := Karma.tiers(g)
	var cols := {"ashen": "#2e2622", "tainted": "#7d7670", "common": "#d9c69a", "pious": "#ecc95e", "solar": "#ffd23a"}
	var rad := 62.0
	var top := PIVOT + Vector2(0, -8)
	# шкала-полукруг над осью: слева — Свет, справа — Пепел
	s.append('<path d="M%s A%.1f %.1f 0 0 1 %s" stroke="#6b4a1c" stroke-width="13" fill="none" stroke-linecap="round"/>' % [_pt(top + _rot(Vector2(0, -rad), _dial(g, mx))), rad, rad, _pt(top + _rot(Vector2(0, -rad), _dial(g, -mx)))])
	for i in ts.size():
		var lo: float = Data.num(ts[i].get("min"), -mx)
		var hi: float = Data.num(ts[i + 1].get("min"), mx) if i + 1 < ts.size() else mx
		var p1 := top + _rot(Vector2(0, -rad), _dial(g, hi))
		var p2 := top + _rot(Vector2(0, -rad), _dial(g, lo))
		var col: String = cols.get(str(ts[i].id), "#c8b48a")
		s.append('<path d="M%s A%.1f %.1f 0 0 1 %s" stroke="%s" stroke-width="9" fill="none"/>' % [_pt(p1), rad, rad, _pt(p2), col])
		if i > 0:
			var q1 := top + _rot(Vector2(0, -rad + 6), _dial(g, lo))
			var q2 := top + _rot(Vector2(0, -rad - 6), _dial(g, lo))
			s.append('<path d="M%s L%s" stroke="#4a3010" stroke-width="1.2"/>' % [_pt(q1), _pt(q2)])
	# стойка
	s.append('<path d="M300 %d V312 M276 312 H324" stroke="#6b4a1c" stroke-width="4" stroke-linecap="round"/>' % int(PIVOT.y))
	var a := _angle(g, k)
	var L := 128.0
	var left := PIVOT + _rot(Vector2(-L, 0), a)
	var right := PIVOT + _rot(Vector2(L, 0), a)
	# чаши: слева солнце, справа пепел
	for side in [[left, true], [right, false]]:
		var end: Vector2 = side[0]
		var pan := end + Vector2(0, 34)
		s.append('<path d="M%s L%s M%s L%s" stroke="#6b4a1c" stroke-width="1"/>' % [_pt(end), _pt(pan + Vector2(-20, 0)), _pt(end), _pt(pan + Vector2(20, 0))])
		s.append('<path d="M%s Q%s %s Z" fill="%s" stroke="#6b4a1c" stroke-width="1.4"/>' % [_pt(pan + Vector2(-22, 0)), _pt(pan + Vector2(0, 18)), _pt(pan + Vector2(22, 0)), "url(#gold)" if side[1] else "#5a524c"])
		if side[1]:
			s.append('<circle cx="%.1f" cy="%.1f" r="6" fill="#ffd34a" stroke="#7a5520" stroke-width="0.8"/>' % [pan.x, pan.y - 4])
		else:
			s.append('<path d="M%s Q%s %s Z" fill="#8a837c" stroke="#3a302a" stroke-width="0.8"/>' % [_pt(pan + Vector2(-12, 0)), _pt(pan + Vector2(0, -14)), _pt(pan + Vector2(12, 0))])
	# коромысло
	s.append('<path d="M%s L%s" stroke="#7a5520" stroke-width="5" stroke-linecap="round"/>' % [_pt(left), _pt(right)])
	s.append('<path d="M%s L%s" stroke="#e2b54a" stroke-width="2" stroke-linecap="round"/>' % [_pt(left), _pt(right)])
	# язычок и отметка души
	var tip := top + _rot(Vector2(0, -rad), _dial(g, k))
	s.append('<path d="M%s L%s" stroke="#4a3010" stroke-width="2.5" stroke-linecap="round"/>' % [_pt(PIVOT), _pt(tip)])
	var mark := "#ffe27a" if k > 5.0 else ("#ff7a2a" if k < -5.0 else "#efe3c2")
	s.append('<circle cx="%.1f" cy="%.1f" r="8" fill="%s" stroke="#3a2410" stroke-width="2"/>' % [tip.x, tip.y, mark])
	s.append('<circle cx="300" cy="%.1f" r="6" fill="#c8962e" stroke="#4a3010" stroke-width="1.5"/>' % PIVOT.y)

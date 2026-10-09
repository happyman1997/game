class_name Portraits
extends RefCounted
## Процедурные портреты персонажей (SVG → текстура). Внешность берётся из
## «генов» (dna), возраста, пола и ранга: цвет кожи и волос, форма лица,
## борода, причёска, одежда цветов державы, корона по рангу.
## Мод может заменить генератор: Portraits.generator = func(game, c) -> String (SVG 100×120).
## Черты меняют облик полем portrait (только если черта видна игроку):
##   skin, skin_amount (0..1), eyes, glow (свечение глаз), pale, undead
##   (запавшие глазницы), fangs, aura (сияние за головой), hood (капюшон),
##   marks (светящиеся руны), hair, no_hair, ageless (видимый возраст не старше).

const HAIR := ["#1b1410", "#33221a", "#52341f", "#7a4d29", "#9c4a24", "#b88a4e", "#d9bb7c"]

static var generator: Callable
static var _cache := {}


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func mix(a: String, b: String, t: float) -> String:
	return _hex(Color(a).lerp(Color(b), clampf(t, 0.0, 1.0)))


static func _f(x: float) -> String:
	return str(snappedf(x, 0.1))


static func clothes_color(game: Game, c: Dictionary) -> String:
	if not c.titles.is_empty():
		var d: Variant = game.title_def(c.titles[0])
		if d != null and d.get("color") is String:
			return d.color
	return "#6a5a48" if c.dynasty != null else "#5a5048"


## Текстура портрета шириной width (высота = 1.2 × width).
static func texture(game: Game, c: Dictionary, width: int = 96) -> Texture2D:
	var age := Chars.age_of(game, c)
	var tier := Titles.primary_tier(game, c)
	var dead: bool = c.death != null
	var clothes := clothes_color(game, c)
	var lk := looks(game, c)
	var key := "%s:%d:%d:%s:%s:%d:%d" % [c.id, age, tier, dead, clothes, width, lk.hash() if not lk.is_empty() else 0]
	if _cache.has(key):
		return _cache[key]
	var src: String = generator.call(game, c) if generator.is_valid() else svg(game, c)
	var img := Image.new()
	if img.load_svg_from_string(src, width / 100.0) != OK:
		img = Image.create(width, int(width * 1.2), false, Image.FORMAT_RGBA8)
	if dead:
		img.adjust_bcs(0.82, 1.0, 0.0)
	var tex := ImageTexture.create_from_image(img)
	if _cache.size() > 1500:
		_cache.clear()
	_cache[key] = tex
	return tex


## Облик от черт с полем portrait, видимых игроку (скрытые черты — только посвящённым).
static func looks(game: Game, c: Dictionary) -> Dictionary:
	var out := {}
	var viewer: Variant = game.state.get("player")
	for t in c.traits:
		var d: Variant = Chars.trait_def(game, t)
		if d == null or not (d.get("portrait") is Dictionary):
			continue
		if not Chars.trait_visible(game, c, t, viewer):
			continue
		out.merge(d.portrait, true)
	return out


static func svg(game: Game, c: Dictionary) -> String:
	var lk := looks(game, c)
	var age := Chars.age_of(game, c)
	if lk.get("ageless") != null:
		age = mini(age, int(Data.num(lk.ageless)))
	var tier := Titles.primary_tier(game, c)
	var clothes := clothes_color(game, c)
	var dna: Dictionary = c.get("dna", {}) if c.get("dna") is Dictionary else {}
	var h := Rng.hash_string(c.id) & 0x7FFFFFFF
	var female: bool = c.female
	var skin := mix("#f3d6bf", "#a87a58", float(dna.get("skin", 0.3)))
	if lk.get("skin") is String:
		skin = mix(skin, lk.skin, Data.num(lk.get("skin_amount"), 0.75))
	var hair: String = HAIR[mini(HAIR.size() - 1, int(float(dna.get("hair", 0.4)) * HAIR.size()))]
	if lk.get("hair") is String:
		hair = lk.hair
	var no_hair: bool = lk.get("no_hair", false)
	var pale: bool = lk.get("pale", false) or lk.get("undead", false)
	if age > 45:
		hair = mix(hair, "#c8c8c4", minf(1.0, (age - 45) / 30.0))
	var child := age < 14
	var s := 0.86 if child else 1.0
	var head_y := 56.0 if child else 52.0
	var face_w := 18.5 + float(dna.get("face", 0.5)) * 4.0
	var fw := face_w * s
	var eye_y := head_y - 2.0
	var beard := not female and age >= 18
	var beard_style := h % 4
	var hair_style := (h >> 3) % 3
	var top := head_y - 26.0 * s - 2.0
	var dy := 6.0 if child else 0.0
	var p := PackedStringArray()

	# фон: ткань цвета державы с виньеткой
	p.append('<defs>')
	p.append('<radialGradient id="bg" cx="50%%" cy="38%%" r="78%%"><stop offset="0" stop-color="%s"/><stop offset="0.6" stop-color="%s"/><stop offset="1" stop-color="%s"/></radialGradient>' % [mix(clothes, "#ffffff", 0.18), mix(clothes, "#000000", 0.45), mix(clothes, "#000000", 0.78)])
	p.append('<radialGradient id="skin" cx="45%%" cy="40%%" r="65%%"><stop offset="0" stop-color="%s"/><stop offset="0.75" stop-color="%s"/><stop offset="1" stop-color="%s"/></radialGradient>' % [mix(skin, "#ffffff", 0.12), skin, mix(skin, "#3a2010", 0.28)])
	p.append('<linearGradient id="hair" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>' % [mix(hair, "#ffffff", 0.18), mix(hair, "#000000", 0.25)])
	p.append('<linearGradient id="cloth" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>' % [mix(clothes, "#ffffff", 0.12), mix(clothes, "#000000", 0.45)])
	p.append('<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbe7a0"/><stop offset="0.5" stop-color="#d9a842"/><stop offset="1" stop-color="#8a6014"/></linearGradient>')
	if lk.get("aura") is String:
		p.append('<radialGradient id="aura" cx="50%%" cy="50%%" r="50%%"><stop offset="0.45" stop-color="%s" stop-opacity="0.85"/><stop offset="0.75" stop-color="%s" stop-opacity="0.35"/><stop offset="1" stop-color="%s" stop-opacity="0"/></radialGradient>' % [lk.aura, lk.aura, lk.aura])
	p.append('</defs>')
	p.append('<rect width="100" height="120" fill="url(#bg)"/>')
	# сияние за головой (чары, проклятие)
	if lk.get("aura") is String:
		p.append('<ellipse cx="50" cy="%s" rx="44" ry="46" fill="url(#aura)"/>' % _f(head_y - 4))

	# волосы сзади (длинные у женщин)
	if female and not no_hair:
		p.append('<path d="M%s %s Q%s %s %s %s L%s %s Q%s %s %s %s Z" fill="url(#hair)"/>' % [
			_f(50 - fw - 4), _f(head_y - 8), _f(50 - fw - 9), _f(head_y + 36), _f(50 - fw + 3), _f(head_y + 44),
			_f(50 + fw - 3), _f(head_y + 44), _f(50 + fw + 9), _f(head_y + 36), _f(50 + fw + 4), _f(head_y - 8)])

	# плечи и одежда
	var sh := 90.0 + dy
	p.append('<path d="M6 120 Q10 %s 50 %s Q90 %s 94 120 Z" fill="url(#cloth)" stroke="#000" stroke-opacity="0.35"/>' % [_f(sh + 4), _f(sh), _f(sh + 4)])
	if tier >= 3:
		# горностаевый воротник
		p.append('<path d="M22 %s Q50 %s 78 %s L82 %s Q50 %s 18 %s Z" fill="#f1ede2" stroke="#00000044"/>' % [_f(sh + 6), _f(sh + 16), _f(sh + 6), _f(sh + 14), _f(sh + 26), _f(sh + 14)])
		for i in 7:
			var x := 26.0 + i * 8.0
			var y := sh + 12.0 + 4.0 * (1.0 - absf(i - 3) / 3.0)
			p.append('<path d="M%s %s l1.2 2.6 l-1.2 -0.6 l-1.2 0.6 Z" fill="#1a1a1a"/>' % [_f(x), _f(y)])
	elif tier >= 1:
		p.append('<path d="M30 %s Q50 %s 70 %s" fill="none" stroke="url(#gold)" stroke-width="3"/>' % [_f(sh + 3), _f(sh + 16), _f(sh + 3)])
	else:
		p.append('<path d="M38 %s L50 %s L62 %s" fill="none" stroke="%s" stroke-width="2"/>' % [_f(sh + 1), _f(sh + 14), _f(sh + 1), mix(clothes, "#fff", 0.35)])
	if tier >= 2:
		p.append('<circle cx="50" cy="%s" r="3" fill="url(#gold)" stroke="#5a3a08" stroke-width="0.6"/>' % _f(sh + 16 if tier >= 3 else sh + 14))

	# шея и голова
	p.append('<path d="M%s %s h%s v%s q%s 4 %s 0 Z" fill="%s"/>' % [_f(50 - 7 * s), _f(head_y + 12 * s), _f(14 * s), _f(16 * s), _f(-7 * s), _f(-14 * s), mix(skin, "#000", 0.18)])
	p.append('<ellipse cx="%s" cy="%s" rx="3.2" ry="5" fill="%s"/><ellipse cx="%s" cy="%s" rx="3.2" ry="5" fill="%s"/>' % [
		_f(50 - fw + 0.5), _f(eye_y + 3), mix(skin, "#000", 0.12), _f(50 + fw - 0.5), _f(eye_y + 3), mix(skin, "#000", 0.12)])
	p.append('<ellipse cx="50" cy="%s" rx="%s" ry="%s" fill="url(#skin)"/>' % [_f(head_y), _f(fw), _f(25 * s)])
	# румянец
	if not pale:
		p.append('<ellipse cx="%s" cy="%s" rx="4" ry="2.5" fill="#d0605a" fill-opacity="%s"/><ellipse cx="%s" cy="%s" rx="4" ry="2.5" fill="#d0605a" fill-opacity="%s"/>' % [
		_f(50 - 10 * s), _f(eye_y + 8), "0.22" if female else "0.12", _f(50 + 10 * s), _f(eye_y + 8), "0.22" if female else "0.12"])

	# глаза и брови
	var eyes := float(dna.get("eyes", 0.5))
	var eye_c := "#3a5a8a" if eyes > 0.6 else ("#4a6a3a" if eyes > 0.3 else "#3a2a1a")
	if lk.get("eyes") is String:
		eye_c = lk.eyes
	if lk.get("undead", false):
		# запавшие глазницы и впалые щёки
		for side in [-1, 1]:
			p.append('<ellipse cx="%s" cy="%s" rx="4.4" ry="3.4" fill="#140c10" fill-opacity="0.68"/>' % [_f(50.0 + side * 7.0 * s), _f(eye_y + 0.4)])
		p.append('<path d="M%s %s q3 6 1 11 M%s %s q-3 6 -1 11" stroke="#000" stroke-opacity="0.38" stroke-width="1.8" fill="none"/>' % [
			_f(50 - fw + 3), _f(eye_y + 4), _f(50 + fw - 3), _f(eye_y + 4)])
	for side in [-1, 1]:
		var ex: float = 50.0 + side * 7.0 * s
		if lk.get("glow") is String:
			p.append('<circle cx="%s" cy="%s" r="3.4" fill="%s" fill-opacity="0.45"/>' % [_f(ex), _f(eye_y), lk.glow])
		if lk.get("undead", false):
			# вместо глаз — огоньки в пустых глазницах
			p.append('<circle cx="%s" cy="%s" r="1.5" fill="%s"/><circle cx="%s" cy="%s" r="0.6" fill="#ffffff" fill-opacity="0.8"/>' % [_f(ex), _f(eye_y + 0.3), eye_c, _f(ex), _f(eye_y + 0.3)])
			continue
		p.append('<ellipse cx="%s" cy="%s" rx="2.8" ry="1.7" fill="#f6f1e6"/>' % [_f(ex), _f(eye_y)])
		p.append('<circle cx="%s" cy="%s" r="1.35" fill="%s"/><circle cx="%s" cy="%s" r="0.55" fill="#0a0806"/>' % [_f(ex), _f(eye_y), eye_c, _f(ex), _f(eye_y)])
		p.append('<path d="M%s %s q2.8 -2 5.6 0" fill="none" stroke="%s" stroke-width="0.8"/>' % [_f(ex - 2.8), _f(eye_y - 0.9), mix(skin, "#000", 0.45)])
		if no_hair:
			continue
		var bx: float = ex - 4.0
		p.append('<path d="M%s %s q4 %s 8 %s" stroke="%s" stroke-width="%s" fill="none" stroke-linecap="round"/>' % [
			_f(bx), _f(eye_y - 4.5), _f(-2.4 if side < 0 else -1.6), _f(0.6 if side < 0 else -0.6), mix(hair, "#000", 0.3), "1.2" if female else "1.7"])
	# нос и рот
	p.append('<path d="M50.5 %s q-0.5 5 -2.5 7.5 q2 1.4 4.6 0" stroke="%s" fill="none" stroke-width="1"/>' % [_f(eye_y + 1), mix(skin, "#000", 0.35)])
	var mouth_y := head_y + 13.0 * s
	if female:
		p.append('<path d="M%s %s q5 -1.5 10 0 q-5 4 -10 0 Z" fill="#b0505a"/>' % [_f(45), _f(mouth_y)])
	else:
		p.append('<path d="M%s %s q4.5 1.6 9 0" stroke="%s" stroke-width="1.3" fill="none" stroke-linecap="round"/>' % [_f(45.5), _f(mouth_y), mix(skin, "#000", 0.45)])
	if lk.get("undead", false):
		# оскал без губ
		p.append('<path d="M%s %s h8" stroke="#2a1a14" stroke-opacity="0.5" stroke-width="2.4" stroke-dasharray="1.1 0.6"/>' % [_f(46), _f(mouth_y)])
	if lk.get("fangs", false):
		var fy := mouth_y + (1.2 if female else 0.8)
		p.append('<path d="M%s %s l0.9 2.6 l0.9 -2.6 Z M%s %s l0.9 2.6 l0.9 -2.6 Z" fill="#fbf8f0" stroke="#00000055" stroke-width="0.25"/>' % [
			_f(46.6), _f(fy), _f(51.6), _f(fy)])
	if lk.get("marks") is String:
		# светящиеся руны на лбу и скулах
		p.append('<path d="M48.2 %s l1.8 2.2 l1.8 -2.2 M%s %s v2.6 M%s %s v2.6" stroke="%s" stroke-width="0.6" fill="none" stroke-linecap="round" stroke-opacity="0.75"/>' % [
			_f(eye_y - 9.5), _f(50 - 12 * s), _f(eye_y + 5), _f(50 + 12 * s), _f(eye_y + 5), lk.marks])
	if age > 40:
		var a := clampf((age - 40) / 30.0, 0.15, 0.5)
		p.append('<path d="M%s %s q3 2 5 0 M%s %s q3 2 5 0 M%s %s q-2 4 -1 7 M%s %s q2 4 1 7" stroke="#000" stroke-opacity="%s" fill="none" stroke-width="0.7"/>' % [
			_f(50 - 13 * s), _f(eye_y + 4), _f(50 + 8 * s), _f(eye_y + 4), _f(50 - 8 * s), _f(eye_y + 8), _f(50 + 8 * s), _f(eye_y + 8), _f(a)])

	# борода
	if beard and not no_hair:
		var bw := fw
		match beard_style:
			0:
				p.append('<path d="M%s %s Q50 %s %s %s Q%s %s 50 %s Q%s %s %s %s Z" fill="url(#hair)"/>' % [
					_f(50 - bw + 1.5), _f(head_y + 1), _f(head_y + 42), _f(50 + bw - 1.5), _f(head_y + 1), _f(50 + 6), _f(head_y + 16), _f(head_y + 18), _f(50 - 6), _f(head_y + 16), _f(50 - bw + 1.5), _f(head_y + 1)])
			1:
				p.append('<path d="M%s %s Q50 %s %s %s Q50 %s %s %s Z" fill="url(#hair)"/>' % [
					_f(50 - 9), _f(head_y + 10), _f(head_y + 31), _f(50 + 9), _f(head_y + 10), _f(head_y + 17), _f(50 - 9), _f(head_y + 10)])
			2:
				p.append('<path d="M%s %s Q50 %s %s %s Q%s %s 50 %s Q%s %s %s %s Z" fill="url(#hair)"/>' % [
					_f(50 - bw + 1), _f(head_y - 2), _f(head_y + 32), _f(50 + bw - 1), _f(head_y - 2), _f(50 + 7), _f(head_y + 14), _f(head_y + 17), _f(50 - 7), _f(head_y + 14), _f(50 - bw + 1), _f(head_y - 2)])
		p.append('<path d="M%s %s q8 -4 16 0" stroke="url(#hair)" stroke-width="3.2" fill="none" stroke-linecap="round"/>' % [_f(50 - 8), _f(mouth_y - 3)])

	# волосы сверху
	if no_hair:
		pass
	elif female:
		p.append('<path d="M%s %s Q%s %s 50 %s Q%s %s %s %s Q%s %s 50 %s Q%s %s %s %s Z" fill="url(#hair)"/>' % [
			_f(50 - fw - 3), _f(head_y + 2), _f(50 - fw), _f(top - 7), _f(top - 5), _f(50 + fw), _f(top - 7), _f(50 + fw + 3), _f(head_y + 2),
			_f(50 + 9), _f(top + 7), _f(top + 9), _f(50 - 9), _f(top + 7), _f(50 - fw - 3), _f(head_y + 2)])
	elif hair_style == 0 or age > 60:
		p.append('<path d="M%s %s Q%s %s 50 %s Q%s %s %s %s Q50 %s %s %s Z" fill="url(#hair)"/>' % [
			_f(50 - fw - 1), _f(head_y - 4), _f(50 - fw), _f(top - 4), _f(top - 3), _f(50 + fw), _f(top - 4), _f(50 + fw + 1), _f(head_y - 4), _f(top + 6), _f(50 - fw - 1), _f(head_y - 4)])
	elif hair_style == 1:
		p.append('<path d="M%s %s Q%s %s 50 %s Q%s %s %s %s L%s %s Q50 %s %s %s Z" fill="url(#hair)"/>' % [
			_f(50 - fw - 2), _f(head_y + 6), _f(50 - fw - 3), _f(top - 6), _f(top - 4), _f(50 + fw + 3), _f(top - 6), _f(50 + fw + 2), _f(head_y + 6),
			_f(50 + fw - 2), _f(head_y - 6), _f(top + 4), _f(50 - fw + 2), _f(head_y - 6)])
	else:
		p.append('<path d="M%s %s Q%s %s 50 %s Q%s %s %s %s L%s %s Q50 %s %s %s Z" fill="url(#hair)"/>' % [
			_f(50 - fw - 2.5), _f(head_y + 12), _f(50 - fw - 4), _f(top - 6), _f(top - 4), _f(50 + fw + 4), _f(top - 6), _f(50 + fw + 2.5), _f(head_y + 12),
			_f(50 + fw - 1.5), _f(head_y - 4), _f(top + 6), _f(50 - fw + 1.5), _f(head_y - 4)])

	# капюшон чародея
	if lk.get("hood") is String:
		var hc: String = lk.hood
		p.append('<path d="M%s %s Q%s %s 50 %s Q%s %s %s %s L%s %s Q%s %s 50 %s Q%s %s %s %s Z" fill="%s" stroke="#000" stroke-opacity="0.4" stroke-width="0.8"/>' % [
			_f(50 - fw - 10), _f(head_y + 34), _f(50 - fw - 13), _f(top - 12), _f(top - 14), _f(50 + fw + 13), _f(top - 12), _f(50 + fw + 10), _f(head_y + 34),
			_f(50 + fw + 1), _f(head_y + 30), _f(50 + fw + 3), _f(top + 1), _f(top - 2), _f(50 - fw - 3), _f(top + 1), _f(50 - fw - 1), _f(head_y + 30), hc])
		# светлая кромка по краю капюшона
		p.append('<path d="M%s %s Q%s %s 50 %s Q%s %s %s %s" stroke="%s" stroke-width="1.2" fill="none" stroke-opacity="0.8"/>' % [
			_f(50 - fw - 1), _f(head_y + 30), _f(50 - fw - 3), _f(top + 1), _f(top - 2), _f(50 + fw + 3), _f(top + 1), _f(50 + fw + 1), _f(head_y + 30), mix(hc, "#ffffff", 0.3)])
	# корона по рангу
	var ct := top - 6.0
	var gem := '<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="#00000066" stroke-width="0.4"/>'
	match tier:
		1:
			p.append('<rect x="35" y="%s" width="30" height="4.2" rx="1.2" fill="url(#gold)" stroke="#5a3a08" stroke-width="0.6"/>' % _f(ct + 4))
		2:
			p.append('<path d="M34.5 %s L34.5 %s L40.5 %s L50 %s L59.5 %s L65.5 %s L65.5 %s Z" fill="url(#gold)" stroke="#5a3a08" stroke-width="0.6"/>' % [_f(ct + 9.5), _f(ct + 1.5), _f(ct + 5.5), _f(ct - 1.5), _f(ct + 5.5), _f(ct + 1.5), _f(ct + 9.5)])
			p.append(gem % ["50", _f(ct + 6.2), "1.4", "#2a7a3a"])
		3:
			p.append('<path d="M33 %s L33 %s L40 %s L45 %s L50 %s L55 %s L60 %s L67 %s L67 %s Z" fill="url(#gold)" stroke="#5a3a08" stroke-width="0.7"/>' % [
				_f(ct + 10.5), _f(ct - 1.5), _f(ct + 5), _f(ct - 4.5), _f(ct + 2.5), _f(ct - 4.5), _f(ct + 5), _f(ct - 1.5), _f(ct + 10.5)])
			for q in [[33, -1.5], [45, -4.5], [55, -4.5], [67, -1.5]]:
				p.append('<circle cx="%s" cy="%s" r="1.3" fill="url(#gold)" stroke="#5a3a08" stroke-width="0.4"/>' % [_f(q[0]), _f(ct + q[1])])
			p.append(gem % ["50", _f(ct + 7), "1.8", "#b02020"])
			p.append(gem % ["41", _f(ct + 7.5), "1.2", "#2050b0"])
			p.append(gem % ["59", _f(ct + 7.5), "1.2", "#2050b0"])
		_:
			if tier >= 4:
				p.append('<path d="M32 %s L32 %s Q50 %s 68 %s L68 %s Z" fill="url(#gold)" stroke="#5a3a08" stroke-width="0.7"/>' % [_f(ct + 10.5), _f(ct - 2), _f(ct - 17), _f(ct - 2), _f(ct + 10.5)])
				p.append('<path d="M50 %s v-7 M46.5 %s h7" stroke="url(#gold)" stroke-width="2.2"/>' % [_f(ct - 11), _f(ct - 15)])
				p.append('<path d="M32 %s H68" stroke="#5a3a08" stroke-width="0.6"/>' % _f(ct + 4))
				p.append(gem % ["42", _f(ct + 7.2), "1.6", "#2050b0"])
				p.append(gem % ["50", _f(ct + 7.2), "1.9", "#b02020"])
				p.append(gem % ["58", _f(ct + 7.2), "1.6", "#2a7a3a"])
	# мягкая виньетка поверх
	p.append('<rect width="100" height="120" fill="none" stroke="#000" stroke-opacity="0.35" stroke-width="3"/>')
	return '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="120" viewBox="0 0 100 120">' + "".join(p) + '</svg>'

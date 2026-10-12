class_name PaperDoll
extends RefCounted
## Инвентарь «на человеке» (как в CK3): фигура персонажа в полный рост —
## голова как на портрете, одежда цветов державы, плащ по рангу — и
## надетые вещи прямо на ней: шлем, корона или венец, кольчуга, оружие в
## руке, скипетр, оберег, перстень, кинжал и рог на поясе. И тронный зал:
## трон, гобелены и знамёна на стенах, постаменты.
##
## Фигура — SVG 200×320; точки, к которым ведут линии от ячеек слотов, —
## ANCHORS (в тех же координатах).

const W := 200
const H := 320
const HALL_W := 520
const HALL_H := 250

const ANCHORS := {
	"helmet": Vector2(100, 26), "regalia": Vector2(100, 34), "armor": Vector2(100, 140),
	"weapon": Vector2(45, 196), "trinket": Vector2(100, 170), "scepter": Vector2(156, 128),
	"amulet": Vector2(100, 127), "ring": Vector2(151, 193), "dagger": Vector2(129, 186),
	"horn": Vector2(70, 194), "seal": Vector2(112, 189), "book": Vector2(87, 185),
}

const RARITY_GLOW := {"famed": "#c58bf0", "illustrious": "#f0b44a"}

static var _cache := {}


static func _f(x: float) -> String:
	return str(snappedf(x, 0.1))


## Что надето: {slot: [{type, rarity}]}.
static func gear_of(game: Game, c: Dictionary) -> Dictionary:
	var out := {}
	if not game.engine.has_feature("artifacts"):
		return out
	for it in Artifacts.equipped(game, c):
		var s := Artifacts.slot_of(game, it)
		if not out.has(s):
			out[s] = []
		out[s].append({"type": str(it.get("type", "")), "rarity": str(it.get("rarity", "common"))})
	return out


static func _first(gear: Dictionary, slot: String) -> Variant:
	var a: Variant = gear.get(slot)
	return a[0] if a is Array and not a.is_empty() else null


static func _has_type(gear: Dictionary, slot: String, types: Array) -> Variant:
	for x in gear.get(slot, []):
		if types.has(x.type):
			return x
	return null


static func _steel(id: String) -> String:
	return '<linearGradient id="%s" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#5a6068"/><stop offset="0.45" stop-color="#c8ced4"/><stop offset="0.6" stop-color="#9aa2aa"/><stop offset="1" stop-color="#4a5058"/></linearGradient>' % id


static func _glow(rarity: String, path: String, width: float) -> String:
	if not RARITY_GLOW.has(rarity):
		return ""
	return '<path d="%s" fill="none" stroke="%s" stroke-opacity="0.35" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>' % [path, RARITY_GLOW[rarity], _f(width)]


# ------------------------------------------------------------ фигура

static func figure_texture(game: Game, c: Dictionary, width: int = 240) -> Texture2D:
	var gear := gear_of(game, c)
	var key := "%s:%d:%d:%s:%s:%d:%d" % [c.id, Chars.age_of(game, c), Titles.primary_tier(game, c), c.death != null,
		Portraits.clothes_color(game, c), width, str(gear).hash() ^ Portraits.looks(game, c).hash()]
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	if img.load_svg_from_string(figure_svg(game, c, gear), width / float(W)) != OK:
		img = Image.create(width, int(width * H / float(W)), false, Image.FORMAT_RGBA8)
	if c.death != null:
		img.adjust_bcs(0.82, 1.0, 0.0)
	var tex := ImageTexture.create_from_image(img)
	if _cache.size() > 200:
		_cache.clear()
	_cache[key] = tex
	return tex


static func figure_svg(game: Game, c: Dictionary, gear: Dictionary) -> String:
	var tier := Titles.primary_tier(game, c)
	var clothes := Portraits.clothes_color(game, c)
	var age := Chars.age_of(game, c)
	var female: bool = c.female
	var dna: Dictionary = c.get("dna", {}) if c.get("dna") is Dictionary else {}
	var skin := Portraits.mix("#f3d6bf", "#a87a58", float(dna.get("skin", 0.3)))
	var lk := Portraits.looks(game, c)
	if lk.get("skin") is String:
		skin = Portraits.mix(skin, lk.skin, Data.num(lk.get("skin_amount"), 0.75))
	var dark := Portraits.mix(clothes, "#000000", 0.45)
	var p := PackedStringArray()
	p.append('<defs>')
	p.append('<radialGradient id="fbg" cx="50%%" cy="40%%" r="75%%"><stop offset="0" stop-color="%s"/><stop offset="0.7" stop-color="#16110b"/><stop offset="1" stop-color="#0c0906"/></radialGradient>' % Portraits.mix(clothes, "#1a140d", 0.7))
	p.append('<linearGradient id="fcloth" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>' % [Portraits.mix(clothes, "#ffffff", 0.12), dark])
	p.append('<linearGradient id="fcloak" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>' % [Portraits.mix(clothes, "#000000", 0.3), Portraits.mix(clothes, "#000000", 0.65)])
	p.append('<linearGradient id="fgold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbe7a0"/><stop offset="0.5" stop-color="#d9a842"/><stop offset="1" stop-color="#8a6014"/></linearGradient>')
	p.append(_steel("fsteel"))
	p.append('<linearGradient id="fmail" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#4c535a"/><stop offset="0.5" stop-color="#9aa2a9"/><stop offset="1" stop-color="#454c53"/></linearGradient>')
	p.append('</defs>')
	p.append('<rect width="%d" height="%d" fill="url(#fbg)"/>' % [W, H])
	p.append('<ellipse cx="100" cy="306" rx="62" ry="9" fill="#000" fill-opacity="0.45"/>')
	# ребёнок — меньше ростом
	var child := age < 14
	if child:
		p.append('<g transform="translate(20,64) scale(0.8)">')
	# плащ по рангу
	if tier >= 2:
		p.append('<path d="M60 92 Q34 190 40 300 L160 300 Q166 190 140 92 Z" fill="url(#fcloak)" stroke="#000" stroke-opacity="0.4"/>')
	# ноги и обувь (у женщин — подол до пят)
	var boots := "#2a1d12"
	if female:
		p.append('<path d="M62 160 L48 298 Q100 306 152 298 L138 160 Z" fill="url(#fcloth)" stroke="#000" stroke-opacity="0.35"/>')
		p.append('<path d="M76 296 h16 v6 h-18 Z M108 296 h16 l2 6 h-18 Z" fill="%s"/>' % boots)
	else:
		var hose := Portraits.mix(clothes, "#2a2018", 0.6)
		p.append('<path d="M74 222 L72 292 L94 292 L97 222 Z M103 222 L106 292 L128 292 L126 222 Z" fill="%s" stroke="#000" stroke-opacity="0.35"/>' % hose)
		p.append('<path d="M70 286 h25 v14 h-29 q-2 -6 4 -14 Z M105 286 h25 q6 8 4 14 h-29 Z" fill="%s"/>' % boots)
	# туника
	if not female:
		p.append('<path d="M60 94 Q100 86 140 94 L150 232 Q100 242 50 232 Z" fill="url(#fcloth)" stroke="#000" stroke-opacity="0.35"/>')
	else:
		p.append('<path d="M62 94 Q100 86 138 94 L140 170 Q100 176 60 170 Z" fill="url(#fcloth)" stroke="#000" stroke-opacity="0.35"/>')
	# доспех поверх туники
	var armor: Variant = _first(gear, "armor")
	if armor != null:
		p.append(_armor_svg(armor, female))
	# руки
	var sleeve := "url(#fmail)" if armor != null else "url(#fcloth)"
	p.append('<path d="M60 96 Q46 100 42 132 L38 184 L53 186 L57 136 Z" fill="%s" stroke="#000" stroke-opacity="0.4"/>' % sleeve)
	p.append('<path d="M140 96 Q154 100 158 132 L162 184 L147 186 L143 136 Z" fill="%s" stroke="#000" stroke-opacity="0.4"/>' % sleeve)
	# пояс
	p.append('<rect x="62" y="166" width="76" height="9" rx="2" fill="#3a2614" stroke="#000" stroke-opacity="0.5"/>')
	p.append('<rect x="95" y="165" width="10" height="11" rx="1.5" fill="url(#fgold)" stroke="#5a3a08" stroke-width="0.6"/>')
	# знаки ранга на груди
	if tier >= 3:
		p.append('<path d="M66 98 Q100 112 134 98 L136 106 Q100 122 64 106 Z" fill="#f1ede2" stroke="#00000044"/>')
		for i in 7:
			p.append('<path d="M%s %s l1.3 2.8 l-1.3 -0.6 l-1.3 0.6 Z" fill="#1a1a1a"/>' % [_f(72.0 + i * 9.4), _f(104.0 + 5.0 * (1.0 - absf(i - 3) / 3.0))])
	elif tier >= 1:
		p.append('<path d="M76 98 Q100 122 124 98" fill="none" stroke="url(#fgold)" stroke-width="2.6"/>')
	# безделушки: оберег на груди, кинжал и рог на поясе
	var amulet: Variant = _has_type(gear, "trinket", ["amulet"])
	if amulet != null:
		p.append('<path d="M86 96 Q100 122 114 96" fill="none" stroke="#c8a040" stroke-width="1"/>')
		p.append(_glow(amulet.rarity, "M100 118 L106 126 L100 136 L94 126 Z", 5))
		p.append('<path d="M100 118 L106 126 L100 136 L94 126 Z" fill="url(#fgold)" stroke="#5a3a08" stroke-width="0.6"/><circle cx="100" cy="126.5" r="2.2" fill="#b02020"/>')
	var dagger: Variant = _has_type(gear, "trinket", ["dagger"])
	if dagger != null:
		p.append(_glow(dagger.rarity, "M124 172 L136 204", 6))
		p.append('<path d="M126 176 L137 204 L134 205 L123 177 Z" fill="url(#fsteel)" stroke="#222" stroke-width="0.5"/><rect x="119" y="170" width="11" height="3" rx="1" transform="rotate(22 124 172)" fill="url(#fgold)"/><rect x="121" y="163" width="4" height="9" rx="1" transform="rotate(22 123 168)" fill="#3a2614"/>')
	var horn: Variant = _has_type(gear, "trinket", ["horn"])
	if horn != null:
		p.append('<path d="M70 176 Q60 196 72 210 L76 207 Q68 196 76 178 Z" fill="#e8dcc0" stroke="#5a4a30" stroke-width="0.8"/><path d="M70 208 h8" stroke="url(#fgold)" stroke-width="2.4"/>')
	var seal: Variant = _has_type(gear, "trinket", ["seal"])
	if seal != null:
		p.append('<path d="M112 175 v10" stroke="#8a2a20" stroke-width="1.2"/><circle cx="112" cy="189" r="4.5" fill="#a02a20" stroke="#5a1008" stroke-width="0.8"/>')
	var book: Variant = _has_type(gear, "trinket", ["book"])
	if book != null:
		p.append('<path d="M80 176 h14 v18 h-14 Z" fill="#6a2a1a" stroke="#2a1008" stroke-width="0.8"/><path d="M82 178 h10 v14 h-10 Z" fill="none" stroke="url(#fgold)" stroke-width="0.8"/>')
	# кисти рук
	p.append('<circle cx="45" cy="190" r="7" fill="%s" stroke="#000" stroke-opacity="0.35"/><circle cx="155" cy="190" r="7" fill="%s" stroke="#000" stroke-opacity="0.35"/>' % [skin, skin])
	var ring: Variant = _has_type(gear, "trinket", ["ring"])
	if ring != null:
		p.append('<circle cx="151" cy="193" r="2.3" fill="none" stroke="#e8c050" stroke-width="1.6"/>')
	# голова — как на портрете (без фона, плеч и короны ранга)
	var head_y := 56.0 if age < 14 else 52.0
	p.append('<g transform="translate(%s,%s)">' % [_f(50.0), _f(60.0 - head_y)])
	p.append(Portraits.svg(game, c, {"inner": true}))
	p.append('</g>')
	# головной убор: шлем, поверх — корона; без шлема — корона или венец
	var helm: Variant = _first(gear, "helmet")
	var crown: Variant = _has_type(gear, "regalia", ["crown"])
	var circlet: Variant = _has_type(gear, "regalia", ["circlet"])
	if helm != null:
		p.append(_glow(helm.rarity, "M75 52 Q75 20 100 11 Q125 20 125 52", 6))
		p.append('<path d="M74 54 Q73 20 100 10 Q127 20 126 54 L120 55 Q100 47 80 55 Z" fill="url(#fsteel)" stroke="#1a1d20" stroke-width="1"/>')
		p.append('<rect x="73" y="45" width="54" height="7" rx="1.5" fill="%s" stroke="#1a1d20" stroke-width="0.7"/>' % ("url(#fgold)" if crown != null or helm.rarity != "common" else "url(#fsteel)"))
		p.append('<rect x="97.6" y="45" width="4.8" height="21" rx="1.5" fill="url(#fsteel)" stroke="#1a1d20" stroke-width="0.7"/>')
		p.append('<path d="M100 11 V45" stroke="#ffffff" stroke-opacity="0.25" stroke-width="1.2"/>')
	elif crown != null:
		p.append(_glow(crown.rarity, "M78 40 L78 26 L88 33 L94 21 L100 30 L106 21 L112 33 L122 26 L122 40 Z", 5))
		p.append('<path d="M78 41 L78 26 L88 33 L94 21 L100 30 L106 21 L112 33 L122 26 L122 41 Z" fill="url(#fgold)" stroke="#5a3a08" stroke-width="0.8"/>')
		p.append('<circle cx="100" cy="36" r="2.4" fill="#b02020" stroke="#00000066" stroke-width="0.4"/><circle cx="88" cy="37" r="1.6" fill="#2050b0"/><circle cx="112" cy="37" r="1.6" fill="#2050b0"/>')
	elif circlet != null:
		p.append('<path d="M79 40 Q100 46 121 40" fill="none" stroke="url(#fgold)" stroke-width="3"/><circle cx="100" cy="43.5" r="2.2" fill="#2a7a3a"/>')
	# скипетр — в левой руке
	var scepter: Variant = _has_type(gear, "regalia", ["scepter"])
	if scepter != null:
		p.append(_glow(scepter.rarity, "M156 132 V220", 7))
		p.append('<rect x="153.5" y="132" width="5" height="88" rx="2" fill="url(#fgold)" stroke="#5a3a08" stroke-width="0.6"/><circle cx="156" cy="128" r="7" fill="url(#fgold)" stroke="#5a3a08" stroke-width="0.7"/><path d="M156 115 v8 M152 118 h8" stroke="url(#fgold)" stroke-width="2"/>')
		p.append('<circle cx="155" cy="190" r="7" fill="%s" stroke="#000" stroke-opacity="0.35"/>' % skin)
	# оружие — в правой руке
	var weapon: Variant = _first(gear, "weapon")
	if weapon != null:
		p.append(_weapon_svg(weapon))
		p.append('<circle cx="45" cy="190" r="6.5" fill="%s" stroke="#000" stroke-opacity="0.35"/>' % skin)
	if child:
		p.append('</g>')
	p.append('<rect width="%d" height="%d" fill="none" stroke="#000" stroke-opacity="0.5" stroke-width="4"/>' % [W, H])
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [W, H, W, H] + "".join(p) + '</svg>'


## Кольчуга или чешуйчатый доспех на теле: основа и узор колец/пластин.
static func _armor_svg(a: Dictionary, female: bool) -> String:
	var p := PackedStringArray()
	var hem := 206.0 if not female else 172.0
	var body := 'M58 94 Q100 85 142 94 L147 %s Q100 %s 53 %s Z' % [_f(hem), _f(hem + 9), _f(hem)]
	p.append(_glow(a.rarity, body, 5))
	p.append('<path d="%s" fill="url(#fmail)" stroke="#1a1d20" stroke-width="1"/>' % body)
	if a.type == "lamellar":
		var y := 100.0
		while y < hem - 4:
			var x := 60.0 + fmod(y, 2.0) * 3.0
			while x < 140:
				p.append('<rect x="%s" y="%s" width="7" height="9" rx="1.5" fill="none" stroke="#2a2f34" stroke-opacity="0.7" stroke-width="0.7"/>' % [_f(x), _f(y)])
				x += 8.0
			y += 8.5
	else:
		var y := 100.0
		var row := 0
		while y < hem - 2:
			var x := 58.0 + (2.5 if row % 2 == 1 else 0.0)
			var d := PackedStringArray()
			while x < 142:
				d.append('M%s %s q2.5 3 5 0' % [_f(x), _f(y)])
				x += 5.0
			p.append('<path d="%s" fill="none" stroke="#2a2f34" stroke-opacity="0.65" stroke-width="0.7"/>' % " ".join(d))
			y += 4.0
			row += 1
	var trim: String = RARITY_GLOW.get(a.rarity, "#8a9096" if a.rarity == "common" else "#7fb4e6")
	p.append('<path d="M53 %s Q100 %s 147 %s" fill="none" stroke="%s" stroke-width="2.2"/>' % [_f(hem), _f(hem + 9), _f(hem), trim])
	return "".join(p)


## Оружие в правой руке (у зрителя слева): меч остриём вниз, топор, копьё, булава.
static func _weapon_svg(w: Dictionary) -> String:
	var p := PackedStringArray()
	match w.type:
		"axe":
			p.append(_glow(w.rarity, "M45 130 V282 M45 140 Q24 136 22 160 Q34 158 45 166", 7))
			p.append('<rect x="42.5" y="128" width="5" height="156" rx="2" fill="#5a3a1c" stroke="#2a1a0c" stroke-width="0.6"/>')
			p.append('<path d="M46 138 Q20 132 17 162 Q30 156 46 168 Z" fill="url(#fsteel)" stroke="#1a1d20" stroke-width="0.9"/>')
		"spear":
			p.append(_glow(w.rarity, "M45 30 V300", 7))
			p.append('<rect x="43" y="40" width="4" height="262" rx="1.5" fill="#6a4a24" stroke="#2a1a0c" stroke-width="0.5"/>')
			p.append('<path d="M45 12 L52 40 L45 46 L38 40 Z" fill="url(#fsteel)" stroke="#1a1d20" stroke-width="0.8"/><path d="M39 46 h12" stroke="url(#fgold)" stroke-width="2.4"/>')
		"mace":
			p.append(_glow(w.rarity, "M45 182 V246", 8))
			p.append('<rect x="42.5" y="182" width="5" height="56" rx="2" fill="#5a3a1c" stroke="#2a1a0c" stroke-width="0.6"/>')
			p.append('<circle cx="45" cy="249" r="10" fill="url(#fsteel)" stroke="#1a1d20" stroke-width="0.9"/>')
			p.append('<path d="M45 235 l2 -5 l2 5 Z M45 263 l2 5 l2 -5 Z M31 249 l-5 2 l5 2 Z M59 249 l5 2 l-5 2 Z" fill="url(#fsteel)" stroke="#1a1d20" stroke-width="0.5"/>')
		_:
			# меч остриём к земле, рука на навершии
			p.append(_glow(w.rarity, "M45 196 V290", 9))
			p.append('<path d="M41.5 198 L48.5 198 L48 284 L45 293 L42 284 Z" fill="url(#fsteel)" stroke="#1a1d20" stroke-width="0.8"/>')
			p.append('<path d="M45 200 V280" stroke="#3a4046" stroke-width="0.8"/>')
			p.append('<rect x="32" y="194" width="26" height="5" rx="2" fill="url(#fgold)" stroke="#5a3a08" stroke-width="0.6"/>')
			p.append('<rect x="42.5" y="178" width="5" height="16" rx="1.5" fill="#3a2614"/><circle cx="45" cy="177" r="4" fill="url(#fgold)" stroke="#5a3a08" stroke-width="0.6"/>')
	return "".join(p)


# ------------------------------------------------------------ тронный зал

## Тронный зал (SVG 520×250): стена, пол, ковёр, помост; трон и висящие на
## стенах вещи — какие надеты. Ячейки слотов кладутся поверх по HALL_SPOTS.
const HALL_SPOTS := {
	"throne": [Vector2(260, 108)],
	"wall": [Vector2(92, 74), Vector2(428, 74)],
	"pedestal": [Vector2(172, 168), Vector2(348, 168)],
}


static func hall_texture(game: Game, c: Dictionary, width: int = 520) -> Texture2D:
	var gear := gear_of(game, c)
	var court := {"throne": gear.get("throne", []), "wall": gear.get("wall", []), "pedestal": gear.get("pedestal", [])}
	var key := "hall:%s:%d:%d" % [Portraits.clothes_color(game, c), str(court).hash(), width]
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	if img.load_svg_from_string(hall_svg(Portraits.clothes_color(game, c), court), width / float(HALL_W)) != OK:
		img = Image.create(width, int(width * HALL_H / float(HALL_W)), false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func hall_svg(clothes: String, court: Dictionary) -> String:
	var p := PackedStringArray()
	p.append('<defs>')
	p.append('<linearGradient id="hwall" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a231b"/><stop offset="1" stop-color="#4a3e30"/></linearGradient>')
	p.append('<linearGradient id="hfloor" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a2c1e"/><stop offset="1" stop-color="#1a130c"/></linearGradient>')
	p.append('<linearGradient id="hgold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbe7a0"/><stop offset="0.5" stop-color="#d9a842"/><stop offset="1" stop-color="#8a6014"/></linearGradient>')
	p.append('<linearGradient id="hwood" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#4a2e16"/><stop offset="0.5" stop-color="#7a4e26"/><stop offset="1" stop-color="#3a2410"/></linearGradient>')
	p.append('<radialGradient id="hlight" cx="50%" cy="30%" r="60%"><stop offset="0" stop-color="#e8b060" stop-opacity="0.22"/><stop offset="1" stop-color="#e8b060" stop-opacity="0"/></radialGradient>')
	p.append('</defs>')
	# стена с кладкой
	p.append('<rect width="%d" height="160" fill="url(#hwall)"/>' % HALL_W)
	var y := 14
	var row := 0
	while y < 160:
		p.append('<path d="M0 %d H%d" stroke="#1a140e" stroke-opacity="0.6" stroke-width="1"/>' % [y, HALL_W])
		var x := 0 if row % 2 == 0 else 26
		while x < HALL_W:
			p.append('<path d="M%d %d v-14" stroke="#1a140e" stroke-opacity="0.45" stroke-width="1"/>' % [x, y])
			x += 52
		y += 14
		row += 1
	# пол и ковёр
	p.append('<path d="M0 160 H%d V%d H0 Z" fill="url(#hfloor)"/>' % [HALL_W, HALL_H])
	for i in 9:
		var x0 := 260.0 + (i - 4) * 40.0
		p.append('<path d="M%s 160 L%s %d" stroke="#000" stroke-opacity="0.35"/>' % [_f(x0), _f(260.0 + (i - 4) * 90.0), HALL_H])
	p.append('<path d="M232 160 L288 160 L320 %d L200 %d Z" fill="%s" stroke="#e0c070" stroke-opacity="0.6"/>' % [HALL_H, HALL_H, Portraits.mix(clothes, "#8a1a14", 0.5)])
	# окна-бойницы и свет
	for wx in [180, 340]:
		p.append('<path d="M%d 66 v-30 q8 -12 16 0 v30 Z" fill="#0c0a08" stroke="#5a4a38" stroke-width="2"/>' % wx)
	p.append('<rect width="%d" height="%d" fill="url(#hlight)"/>' % [HALL_W, HALL_H])
	# помост
	p.append('<path d="M200 160 H320 L328 172 H192 Z" fill="#5a4a38" stroke="#000" stroke-opacity="0.5"/>')
	p.append('<path d="M214 150 H306 L312 160 H208 Z" fill="#6a5844" stroke="#000" stroke-opacity="0.5"/>')
	# трон
	var throne: Array = court.get("throne", [])
	if not throne.is_empty():
		var t: Dictionary = throne[0]
		var acc: String = RARITY_GLOW.get(t.rarity, "#d9a842")
		p.append('<path d="M226 150 V62 Q260 34 294 62 V150 Z" fill="url(#hwood)" stroke="#1a0e06" stroke-width="1.5"/>')
		p.append('<path d="M234 140 V70 Q260 50 286 70 V140 Z" fill="%s" stroke="%s" stroke-width="2"/>' % [Portraits.mix(clothes, "#000", 0.25), acc])
		p.append('<path d="M218 118 H302 V132 H218 Z" fill="url(#hwood)" stroke="#1a0e06"/><path d="M218 150 V118 M302 150 V118" stroke="#3a2410" stroke-width="6"/>')
		p.append('<circle cx="260" cy="52" r="5" fill="url(#hgold)" stroke="#5a3a08"/>')
	else:
		p.append('<path d="M236 150 V96 H284 V150 Z" fill="#3a2a1a" fill-opacity="0.6" stroke="#000" stroke-opacity="0.4" stroke-dasharray="4 3"/>')
	# на стенах: гобелены, знамёна, щиты
	var walls: Array = court.get("wall", [])
	var wxs := [92.0, 428.0]
	for i in 2:
		var cx: float = wxs[i]
		p.append('<path d="M%s 22 H%s" stroke="#6a4a24" stroke-width="4" stroke-linecap="round"/>' % [_f(cx - 46), _f(cx + 46)])
		if i >= walls.size():
			continue
		var wi: Dictionary = walls[i]
		var acc2: String = RARITY_GLOW.get(wi.rarity, "#d9a842")
		match wi.type:
			"banner":
				p.append('<path d="M%s 24 H%s V108 L%s 96 L%s 108 Z" fill="%s" stroke="%s" stroke-width="2"/>' % [_f(cx - 30), _f(cx + 30), _f(cx), _f(cx - 30), Portraits.mix(clothes, "#000", 0.1), acc2])
			"trophy_shield":
				p.append('<path d="M%s 34 H%s V70 Q%s 104 %s 116 Q%s 104 %s 70 Z" fill="%s" stroke="%s" stroke-width="2.5"/>' % [_f(cx - 30), _f(cx + 30), _f(cx + 30), _f(cx), _f(cx - 30), _f(cx - 30), Portraits.mix(clothes, "#000", 0.2), acc2])
				p.append('<path d="M%s 40 V110 M%s 66 H%s" stroke="#e8dcc0" stroke-opacity="0.7" stroke-width="3"/>' % [_f(cx), _f(cx - 28), _f(cx + 28)])
			_:
				p.append('<path d="M%s 24 H%s V118 L%s 124 L%s 118 L%s 124 L%s 118 L%s 124 L%s 118 Z" fill="%s" stroke="%s" stroke-width="2"/>' % [
					_f(cx - 42), _f(cx + 42), _f(cx + 30), _f(cx + 18), _f(cx), _f(cx - 18), _f(cx - 30), _f(cx - 42), Portraits.mix(clothes, "#5a3a20", 0.55), acc2])
				p.append('<path d="M%s 34 H%s V110 H%s Z" fill="none" stroke="#e8c070" stroke-opacity="0.45" stroke-width="1.2"/>' % [_f(cx - 34), _f(cx + 34), _f(cx - 34)])
	# постаменты
	var peds: Array = court.get("pedestal", [])
	var pxs := [172.0, 348.0]
	for i in 2:
		var cx: float = pxs[i]
		p.append('<path d="M%s 236 H%s L%s 226 H%s Z" fill="#4a3e30" stroke="#000" stroke-opacity="0.5"/>' % [_f(cx - 26), _f(cx + 26), _f(cx + 20), _f(cx - 20)])
		p.append('<rect x="%s" y="198" width="28" height="28" fill="#5a4c3c" stroke="#000" stroke-opacity="0.5"/>' % _f(cx - 14))
		p.append('<path d="M%s 198 H%s L%s 190 H%s Z" fill="#6a5a48" stroke="#000" stroke-opacity="0.5"/>' % [_f(cx - 18), _f(cx + 18), _f(cx + 22), _f(cx - 22)])
		if i < peds.size():
			p.append('<ellipse cx="%s" cy="190" rx="22" ry="4" fill="%s" fill-opacity="0.5"/>' % [_f(cx), RARITY_GLOW.get(peds[i].rarity, "#d9a842")])
	p.append('<rect width="%d" height="%d" fill="none" stroke="#000" stroke-opacity="0.55" stroke-width="4"/>' % [HALL_W, HALL_H])
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [HALL_W, HALL_H, HALL_W, HALL_H] + "".join(p) + '</svg>'

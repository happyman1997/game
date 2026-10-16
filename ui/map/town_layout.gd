class_name TownLayout
extends RefCounted
## Раскладка поселения графства на карте: где стоят замок, ратуша и храм,
## постройки районов, дома, стены, поля, сады и пристань с лодками. Всё — в
## координатах карты и внутри пикселей графства: районы расходятся от
## середины в свои стороны (детинец — вверх, посад — вправо, соборная
## сторона — влево, слобода — вниз), угодья — туда, где графство шире,
## пристань — к ближайшему морю. Считается заново, только когда меняется
## застройка графства.

const GA := 2.39996323

## Сторона района от середины поселения: [угол, доля радиуса города].
const SIDES := {
	"citadel": [-PI / 2, 0.2],
	"market": [0.2, 0.85],
	"temple_quarter": [PI - 0.2, 0.85],
	"crafts": [PI * 0.32, 1.0],
}

## Главный рисунок района, если владения нет.
const DISTRICT_MAIN := {"citadel": "tower", "market": "stalls", "temple_quarter": "chapel", "crafts": "smithy"}

const FIELD_COLORS := ["#d9b65a", "#c9a24a", "#8fae55", "#a3b860", "#9a7448", "#b9a26a"]


## Сборщик: занятые места, рисунки и земля.
class Town:
	var m: MapData
	var i: int
	var k := 1.0
	var occ: Array = []
	var items: Array = []
	var ground: Array = []

	func _init(map: MapData, idx: int) -> void:
		m = map
		i = idx

	func free_at(p: Vector2, r: float) -> bool:
		for o in occ:
			var d: Vector2 = p - o[0]
			d.y *= 1.5
			if d.length() < (r + float(o[1])) * 0.9:
				return false
		return true

	## Ближайшее к anchor свободное место (по спирали) на суше графства или на воде.
	func find(anchor: Vector2, r: float, margin: float, water := false, tries := 260) -> Variant:
		var step := maxf(0.45, r * 0.5)
		for n in tries:
			var p := anchor + Vector2.from_angle(n * 2.39996323) * sqrt(float(n)) * step
			if water:
				if not TownLayout.is_water(m, p, margin):
					continue
			elif not TownLayout.inside(m, i, p, margin):
				continue
			if free_at(p, r):
				occ.append([p, r])
				return p
		return null

	## Поставить рисунок как можно ближе к anchor. extra — b, d, great, flag…
	func sprite(name: String, anchor: Vector2, prio: int, extra: Dictionary = {}, water := false) -> Variant:
		var sp := MapArt.spec(name)
		var h: float = float(sp.size) * k * float(extra.get("scale", 1.0))
		var w: float = h * float(sp.w) / float(sp.h)
		var p: Variant = find(anchor, w * 0.42, 0.6 * k if water else 1.0 * k, water)
		if p == null:
			return null
		var it := {"kind": "sprite", "sprite": name, "pos": p, "h": h, "prio": prio, "b": "", "d": ""}
		it.merge(extra, true)
		items.append(it)
		return it


static func inside(m: MapData, i: int, p: Vector2, r: float) -> bool:
	if m.province_at(floori(p.x), floori(p.y)) != i:
		return false
	if r <= 0.0:
		return true
	return m.province_at(floori(p.x + r), floori(p.y)) == i and m.province_at(floori(p.x - r), floori(p.y)) == i \
		and m.province_at(floori(p.x), floori(p.y + r)) == i and m.province_at(floori(p.x), floori(p.y - r)) == i


static func is_water(m: MapData, p: Vector2, r: float) -> bool:
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var q: Vector2 = p + o
		if q.x < 0 or q.y < 0 or q.x >= m.width or q.y >= m.height:
			return false
		if m.province_at(floori(q.x), floori(q.y)) != -1:
			return false
	return true


## Сколько пройдёт луч от p по графству (до границы), не дальше maxlen.
static func _ray(m: MapData, i: int, p: Vector2, dir: Vector2, maxlen: float) -> float:
	var d := 0.0
	while d < maxlen:
		var q := p + dir * (d + 1.0)
		if m.province_at(floori(q.x), floori(q.y)) != i:
			return d
		d += 1.0
	return maxlen


## Ближайшее море от p: {dir, coast (последняя суша), water (первая вода)} или null.
static func _sea(m: MapData, i: int, p: Vector2, maxlen: float) -> Variant:
	var best: Variant = null
	for n in 32:
		var dir := Vector2.from_angle(n * TAU / 32.0)
		var d := 0.0
		while d < maxlen:
			var q := p + dir * (d + 1.0)
			var at := m.province_at(floori(q.x), floori(q.y))
			if at == i:
				d += 1.0
				continue
			if at == -1 and q.x >= 0 and q.y >= 0 and q.x < m.width and q.y < m.height and (best == null or d < best.len):
				best = {"dir": dir, "len": d, "coast": p + dir * maxf(0.0, d - 1.5), "water": p + dir * (d + 2.5)}
			break
	return best


## Прямоугольник поля: середина, длина, ширина, угол → 4 угла и борозды.
static func _patch(c: Vector2, a: float, b: float, ang: float, lines: int) -> Dictionary:
	var u := Vector2.from_angle(ang)
	var v := Vector2(-u.y, u.x)
	var pts := PackedVector2Array([c - u * a - v * b, c + u * a - v * b, c + u * a + v * b, c - u * a + v * b])
	var ls := []
	for j in lines:
		var t := (j + 1.0) / (lines + 1.0) * 2.0 - 1.0
		ls.append([c - u * a * 0.92 + v * b * t, c + u * a * 0.92 + v * b * t])
	return {"pts": pts, "lines": ls, "c": c}


## Поле целиком внутри графства и не поверх построек; null — не нашлось.
static func _place_patch(t: Town, anchor: Vector2, a: float, b: float, ang: float, lines: int) -> Variant:
	for attempt in 4:
		var p: Variant = t.find(anchor, a * 0.85, 1.0 * t.k)
		if p == null:
			return null
		var pt := _patch(p, a, b, ang, lines)
		var ok := true
		for q in pt.pts:
			if not inside(t.m, t.i, q, 0.4):
				ok = false
				break
		if ok:
			return pt
		# место занято зря — пусть там встанет что-то поменьше
		t.occ.pop_back()
		t.occ.append([p, 0.5])
		anchor = anchor.lerp(Vector2(t.m.centers[t.i * 2], t.m.centers[t.i * 2 + 1]), 0.3)
	return null


## Раскладка. s — поселение из MapOverlay.settlements_of, cons — стройка
## (district, building, level) или null.
static func build(g: Game, m: MapData, i: int, s: Dictionary, cons: Variant) -> Dictionary:
	var pid: String = m.provinces[i]
	var R := sqrt(float(m.areas[i]) / PI)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pid)
	var t := Town.new(m, i)
	t.k = clampf(R / 20.0, 0.6, 1.0)
	var k := t.k
	# середина поселения: центр графства (он дальше всего от границ)
	var core := Vector2(m.centers[i * 2], m.centers[i * 2 + 1])
	if not inside(m, i, core, 2.0 * k):
		for n in 200:
			var p := core + Vector2.from_angle(n * GA) * sqrt(float(n)) * 0.8
			if inside(m, i, p, 2.0 * k):
				core = p
				break
	var lv := {}
	for x in s.districts:
		lv[x[0]] = int(x[1])
	var holdings: Array = s.get("holdings", [])
	var levels: int = s.levels
	var rc := minf(clampf(3.0 + levels * 0.5, 4.0, 9.5) * k, R * 0.5)
	var rot := rng.randf_range(-0.45, 0.45)
	var anchors := {}
	for did in SIDES:
		anchors[did] = core + Vector2.from_angle(SIDES[did][0] + rot) * rc * float(SIDES[did][1])
	# море — для пристани; угодья — туда, где графство шире и нет моря
	var sea: Variant = _sea(m, i, core, R * 1.7) if lv.has("harbor") or s.bmap.has("harbor") else null
	var best_dir := Vector2.DOWN
	var best_len := -1.0
	for n in 12:
		var dir := Vector2.from_angle(n * TAU / 12.0 + rot)
		if sea != null and dir.dot(sea.dir) > 0.6:
			continue
		# вверху — главное здание, внизу — название графства
		if absf(dir.y) > 0.8:
			continue
		var l := _ray(m, i, core, dir, R * 1.4)
		if l > best_len:
			best_len = l
			best_dir = dir
	var fields_at := core + best_dir * clampf(best_len * 0.5, rc + 2.5 * k, rc + 7.0 * k)
	anchors["fields"] = fields_at
	anchors["harbor"] = sea.coast if sea != null else core + Vector2.from_angle(rot + PI / 2) * rc
	var town_ds := ["citadel", "market", "temple_quarter", "crafts"]
	var features := {}
	# 1. главное: замок, ратуша, храм — или знак района, заложенного без владения
	var has_d: bool = not s.districts.is_empty()
	var mains := {"castle": "citadel", "city": "market", "temple": "temple_quarter"}
	for h in holdings:
		if not mains.has(h):
			continue
		var did: String = mains[h]
		var name: String = "castle" if h == "castle" and int(lv.get("citadel", 1)) >= 2 else {"castle": "keep", "city": "town_hall", "temple": "church"}[h]
		t.sprite(name, anchors[did], 1, {"d": did if has_d else "", "flag": h != "temple", "main": true})
	for did in DISTRICT_MAIN:
		if lv.has(did) and not holdings.has({"citadel": "castle", "market": "city", "temple_quarter": "temple"}.get(did, "")) \
				and s.bmap.get(did, []).is_empty():
			t.sprite(DISTRICT_MAIN[did], anchors[did], 2, {"d": did})
	# 2. достопримечательности и великие стройки
	for b in s.special:
		var nm := MapArt.for_building(g.content.get_def("buildings", b))
		if nm != "none":
			t.sprite(nm, core + Vector2(rc * 0.6, -rc * 0.4).rotated(rot), 1, {"b": b, "great": true})
	# 3. стройка — леса там, где встанет постройка
	if cons != null:
		var bd: Variant = g.content.get_def("buildings", str(cons.get("building", ""))) if cons.get("building") != null else null
		var did: Variant = cons.get("district") if cons.get("district") != null else (bd.get("district") if bd != null else null)
		var at: Vector2 = anchors.get(str(did), core + Vector2(rc, 0))
		t.sprite("scaffold", at, 1, {"scaffold": true, "b": str(cons.get("building", "")) if bd != null else "", "d": str(did) if did != null and bd == null else ""},
			false)
	# 4. постройки районов
	var all_b := []
	for did in s.bmap:
		for b in s.bmap[did]:
			all_b.append([did, b])
	for b in s.other:
		all_b.append(["", b])
	for x in all_b:
		var bd: Variant = g.content.get_def("buildings", x[1])
		var feat: Variant = bd.get("map_feature") if bd != null else null
		if feat is String:
			features[feat] = int(features.get(feat, 0)) + 1
	# великие и крупные — первыми, чтобы встали ближе к своему месту; стены —
	# после великих, остальное обходит их
	all_b.sort_custom(func(x, y): return _rank(g, x[1]) > _rank(g, y[1]))
	var walled := not features.has("walls")
	for x in all_b:
		var bd: Variant = g.content.get_def("buildings", x[1])
		if bd == null:
			continue
		var great := bd.get("unique") != null
		if not walled and not great:
			_walls(t, core, rc, R, rng)
			walled = true
		var nm := MapArt.for_building(bd)
		if nm == "none":
			continue
		var did: String = x[0]
		var at: Vector2 = anchors.get(did, core + Vector2(0, rc * 0.5))
		if did == "harbor" and sea != null:
			at = sea.coast
		t.sprite(nm, at, 1 if great else 2, {"b": x[1], "d": did, "great": great})
	if not walled:
		_walls(t, core, rc, R, rng)
	# 6. дома
	var dev := int(s.get("dev", 5))
	var houses := {"citadel": int(lv.get("citadel", 0)), "market": 1 + int(lv.get("market", 0)) * 3,
		"temple_quarter": int(lv.get("temple_quarter", 0)), "crafts": int(lv.get("crafts", 0)) * 2}
	if not lv.has("market") and holdings.has("city"):
		houses["market"] = 3
	var extra := clampi(dev / 5, 0, 6)
	var total := 0
	for did in town_ds:
		var n: int = houses.get(did, 0) + (extra if did == "market" else 0)
		for j in mini(n, 14 - total):
			var kind: String = ["house", "townhouse", "house", "cottage"][rng.randi() % 4] if did == "market" else ("cottage" if did != "citadel" else "house")
			var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 0.7) * rc
			if t.sprite(kind, anchors[did] + off, 3) != null:
				total += 1
	var town_bottom := core.y + 2.0
	for it in t.items:
		if it.kind == "sprite" and town_ds.has(it.d) or it.get("main", false):
			town_bottom = maxf(town_bottom, it.pos.y)
	# 7. угодья: поля, сады, пастбища, лес
	var fl := int(lv.get("fields", 0))
	var patches := (2 + fl * 2 if fl > 0 else (2 if holdings.size() > 0 else 0)) + int(features.get("fields", 0)) * 2
	var fang := rng.randf() * PI
	for j in patches:
		var a := rng.randf_range(2.4, 3.2) * k
		var b := rng.randf_range(1.4, 1.9) * k
		var pt: Variant = _place_patch(t, fields_at + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * 2.0 * k, a, b, fang + rng.randf_range(-0.25, 0.25), 3)
		if pt != null:
			pt.merge({"kind": "field", "prio": 2, "col": Color(FIELD_COLORS[rng.randi() % FIELD_COLORS.size()]), "line": Color(0.3, 0.22, 0.1, 0.35)})
			t.ground.append(pt)
	for j in int(features.get("vineyard", 0)) * 2:
		var pt: Variant = _place_patch(t, fields_at, 2.8 * k, 1.7 * k, fang + 0.1, 4)
		if pt != null:
			pt.merge({"kind": "vine", "prio": 2, "col": Color("#b5a06a"), "line": Color("#3f6428")})
			t.ground.append(pt)
	for j in int(features.get("polders", 0)) * 3:
		var pt: Variant = _place_patch(t, fields_at, 3.0 * k, 1.8 * k, fang, 2)
		if pt != null:
			pt.merge({"kind": "field", "prio": 2, "col": Color("#7fa65a"), "line": Color(0.25, 0.45, 0.6, 0.8)})
			t.ground.append(pt)
	for feat in ["flock", "paddock"]:
		for j in int(features.get(feat, 0)):
			var pt: Variant = _place_patch(t, fields_at, 2.6 * k, 1.7 * k, fang, 0)
			if pt == null:
				continue
			var p: Vector2 = pt.c
			pt.merge({"kind": "pen", "prio": 2, "col": Color("#9ab865"), "line": Color("#6b4a2b")})
			t.ground.append(pt)
			for n in (5 if feat == "flock" else 3):
				var q: Vector2 = p + Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.8, 1.0)) * k
				t.items.append({"kind": "sprite", "sprite": "sheep" if feat == "flock" else "horse", "pos": q, "h": float(MapArt.spec("sheep" if feat == "flock" else "horse").size) * k, "prio": 3, "b": "", "d": ""})
	for j in int(features.get("orchard", 0)) * 6:
		t.sprite("apple", fields_at + Vector2.from_angle(rng.randf() * TAU) * 2.0 * k, 3)
	var forest := int(features.get("forest", 0)) * 8
	var terr := str(s.get("terrain", ""))
	forest += 3 if terr == "forest" else 0
	var wild_at := core - best_dir * clampf(R * 0.55, rc + 3.0 * k, rc + 10.0 * k)
	for j in forest:
		t.sprite("pine", wild_at + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * 3.0 * k, 3)
	for j in (2 if ["plains", "farmlands", "hills"].has(terr) else 1):
		t.sprite("oak", core + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rc + 1.0, rc + 6.0 * k), 3)
	# 8. пристань: мостки в воду, лодки, солеварни
	if sea != null and lv.has("harbor"):
		var hl := int(lv.harbor)
		var a: Vector2 = sea.coast
		var len := (2.5 + hl) * k
		var d: Vector2 = sea.dir
		var u := Vector2(-d.y, d.x) * 0.55 * k
		t.ground.append({"kind": "pier", "prio": 2, "pts": PackedVector2Array([a - u, a + d * len - u, a + d * len + u, a + u]),
			"lines": [], "col": Color("#9a6a3a"), "line": Color("#5a3a20")})
		var boats := hl + int(features.get("boats", 0)) * 2
		for j in boats:
			t.sprite("boat", a + d * (len + 1.5 * k) + u * rng.randf_range(-3.0, 3.0), 2, {"bob": rng.randf() * TAU}, true)
		for j in int(features.get("skiffs", 0)) * 3:
			t.sprite("skiff", a + d * (len + 4.0 * k) + u * rng.randf_range(-6.0, 6.0), 3, {"bob": rng.randf() * TAU}, true)
		for j in int(features.get("saltpans", 0)) * 4:
			var pt: Variant = _place_patch(t, a - d * 2.0 * k, 0.9 * k, 0.7 * k, atan2(d.y, d.x), 0)
			if pt != null:
				pt.merge({"kind": "field", "prio": 3, "col": Color("#f4f2ea"), "line": Color(0.4, 0.4, 0.4, 0.5)})
				t.ground.append(pt)
	t.items.sort_custom(func(x, y): return x.pos.y < y.pos.y)
	return {"items": t.items, "items1": t.items.filter(func(x): return int(x.prio) <= 1),
		"items2": t.items.filter(func(x): return int(x.prio) <= 2), "ground": _ground_mesh(t.ground, k),
		"core": core, "bottom": town_bottom, "radius": R}


## Земля одной сеткой: треугольники полей, загонов и мостков и тонкие линии
## (края, борозды, доски) — рисуется за два вызова.
static func _ground_mesh(ground: Array, k: float) -> Dictionary:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var lp := PackedVector2Array()
	var lc := PackedColorArray()
	var ink := Color(0.17, 0.11, 0.06, 0.55)
	for gr in ground:
		var q: PackedVector2Array = gr.pts
		var col: Color = gr.col
		var line: Color = gr.line
		var fill := Color(col, 0.88)
		var edge := ink
		if gr.kind == "pen":
			fill = Color(col, 0.5)
			edge = line
		elif gr.kind == "pier":
			fill = col
			edge = line
		var b := pts.size()
		for p in q:
			pts.append(p)
			cols.append(fill)
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
		for j in 4:
			lp.append(q[j])
			lp.append(q[(j + 1) % 4])
			lc.append(edge)
		if gr.kind == "pier":
			for j in range(1, 6):
				lp.append(q[0].lerp(q[1], j / 6.0))
				lp.append(q[3].lerp(q[2], j / 6.0))
				lc.append(Color(line, 0.6))
		for l in gr.lines:
			if gr.kind != "vine":
				lp.append(l[0])
				lp.append(l[1])
				lc.append(line)
				continue
			# лоза — тёмные кусты вдоль ряда
			for j in 7:
				var c: Vector2 = l[0].lerp(l[1], (j + 0.5) / 7.0)
				var r := 0.3 * k
				var b2 := pts.size()
				pts.append_array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)])
				for n in 4:
					cols.append(line)
				idx.append_array([b2, b2 + 1, b2 + 2, b2, b2 + 2, b2 + 3])
	return {"pts": pts, "cols": cols, "idx": idx, "lp": lp, "lc": lc}


## Порядок постановки: великие, потом по величине рисунка.
static func _rank(g: Game, b: String) -> float:
	var bd: Variant = g.content.get_def("buildings", b)
	if bd == null:
		return 0.0
	return float(MapArt.spec(MapArt.for_building(bd)).size) + (100.0 if bd.get("unique") != null else 0.0)


## Стены: кольцо вокруг середины поселения с башнями и воротами. Крупные
## постройки на линии стены становятся её частью; прочие её обходят.
static func _walls(t: Town, core: Vector2, rc: float, R: float, rng: RandomNumberGenerator) -> void:
	var k := t.k
	var rw := minf(rc * 1.15, R * 0.8)
	var n := 20
	var pts := []
	for j in n:
		var dir := Vector2.from_angle(j * TAU / n)
		var r := rw * rng.randf_range(0.96, 1.04)
		while r > rw * 0.5 and not inside(t.m, t.i, core + Vector2(dir.x, dir.y / 1.3) * r, 0.8 * k):
			r -= 0.5
		pts.append(core + Vector2(dir.x, dir.y / 1.3) * r)
	# крупные постройки на линии стены сами становятся её частью
	var big := func(q: Vector2) -> bool:
		for o in t.occ:
			if float(o[1]) >= 2.0 * k and q.distance_to(o[0]) < float(o[1]) * 1.1:
				return true
		return false
	# ворота — внизу (ближе к зрителю), но не в стене здания
	var gate := -1
	for j in n:
		if not big.call(pts[j]) and (gate < 0 or pts[j].y > pts[gate].y):
			gate = j
	if gate < 0:
		return
	for j in n:
		var a: Vector2 = pts[j]
		var b: Vector2 = pts[(j + 1) % n]
		if big.call(a.lerp(b, 0.5)) or (big.call(a) and big.call(b)):
			continue
		if (j + 1) % n == gate:
			b = a.lerp(b, 0.6)
		elif j == gate:
			a = a.lerp(b, 0.4)
		t.items.append({"kind": "wall", "a": a, "b": b, "pos": Vector2((a.x + b.x) / 2.0, maxf(a.y, b.y) - 0.01), "prio": 2, "w": 0.9 * k})
		var steps := maxi(1, ceili(a.distance_to(b) / (1.0 * k)))
		for n2 in steps:
			t.occ.append([a.lerp(b, n2 / float(steps)), 0.6 * k])
	var gp: Vector2 = pts[gate]
	t.items.append({"kind": "sprite", "sprite": "gatehouse", "pos": gp, "h": float(MapArt.spec("gatehouse").size) * k, "prio": 2, "b": "walls", "d": "citadel"})
	t.occ.append([gp, 1.8 * k])
	for j in range(2, n, 4):
		if absi(j - gate) < 2 or big.call(pts[j]):
			continue
		t.items.append({"kind": "sprite", "sprite": "tower_small", "pos": pts[j] + Vector2(0, 0.01), "h": float(MapArt.spec("tower_small").size) * k, "prio": 2, "b": "walls", "d": "citadel"})

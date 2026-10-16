class_name MapOverlay
extends Control
## Слой поверх карты: подписи держав (по дуге), поселения графств с их
## районами и постройками, названия графств при приближении, армии, осады,
## путь выбранной армии.

var view: MapView
var labels: Array = []
## Провинции с подсветкой (выбор персонажа, цели войны) — id → true.
var highlighted := {}
## Подсказка для армии: Callable(army_id) -> String.
var army_tooltip: Callable
var _army_pos: Array = []
## Нижний край рисунка поселения (экранный y) — название графства идёт под ним.
var _name_below := {}


func _process(_delta: float) -> void:
	if view != null and view.game != null:
		queue_redraw()


func _draw() -> void:
	if view == null or view.game == null or view.map == null:
		return
	_draw_labels()
	var snap := _snapshot()
	_name_below.clear()
	_draw_settlements(snap)
	_draw_county_names()
	_draw_sieges(snap)
	_draw_path(snap)
	_draw_armies(snap)


# ------------------------------------------------------------ подписи

func _draw_labels() -> void:
	var z := view.zoom
	if z > 3.2:
		return
	var font := Fonts.heading(700)
	var fade := 1.0 - smoothstep(2.2, 3.2, z)
	var placed: Array[Rect2] = []
	for l in labels:
		var px: float = l.size * z
		if px < 9.0:
			continue
		px = minf(px, 120.0)
		var fs := int(px)
		var spacing := px * 0.18
		var chars: PackedStringArray = []
		var widths: PackedFloat32Array = []
		var total := 0.0
		for ch in l.text:
			chars.append(ch)
			var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			widths.append(w)
			total += w + spacing
		total -= spacing
		var center := view.map_to_screen(l.pos)
		var ang: float = l.angle
		var dir := Vector2(cos(ang), sin(ang))
		var nrm := Vector2(dir.y, -dir.x)
		var sag := total * 0.07
		var half := total * 0.5
		var bb := Rect2(center - Vector2(half, px * 0.6), Vector2(total, px * 1.2))
		if absf(ang) > 0.15:
			var hw := absf(dir.x) * half + absf(nrm.x) * px * 0.6
			var hh := absf(dir.y) * half + absf(nrm.y) * px * 0.6
			bb = Rect2(center - Vector2(hw, hh), Vector2(hw, hh) * 2)
		if not bb.intersects(Rect2(Vector2.ZERO, size)):
			continue
		var clash := false
		for r in placed:
			if r.intersects(bb):
				clash = true
				break
		if clash:
			continue
		placed.append(bb)
		var ascent := font.get_ascent(fs)
		var descent := font.get_descent(fs)
		var fill := Color(0.97, 0.92, 0.80, 0.93 * fade)
		var outline := Color(0.08, 0.05, 0.02, 0.55 * fade)
		var s := -half
		for i in chars.size():
			var mid_s := s + widths[i] * 0.5
			var t := mid_s / half
			var p := center + dir * mid_s + nrm * (sag * (1.0 - t * t))
			var slope := -2.0 * sag * t / half
			var rot := ang + atan(-slope)
			draw_set_transform(p, rot, Vector2.ONE)
			var o := Vector2(-widths[i] * 0.5, (ascent - descent) * 0.5)
			draw_char_outline(font, o, chars[i], fs, maxi(2, int(px / 7)), outline)
			draw_char(font, o, chars[i], fs, fill)
			s += widths[i] + spacing
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_county_names() -> void:
	var z := view.zoom
	if z < 2.0:
		return
	var m := view.map
	var g := view.game
	var font := Fonts.heading(650)
	var fs := int(minf(17.0, 5.0 * z))
	var alpha := smoothstep(2.0, 2.6, z)
	for p in m.provinces.size():
		if m.areas[p] * z * z < 2200:
			continue
		var pos := view.map_to_screen(Vector2(m.centers[p * 2], m.centers[p * 2 + 1] + 8.0))
		if _name_below.has(p):
			pos.y = maxf(pos.y, float(_name_below[p]) + fs * 0.6)
		if pos.x < -80 or pos.y < -20 or pos.x > size.x + 80 or pos.y > size.y + 20:
			continue
		var name := g.name_of("provinces", m.provinces[p])
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var o := pos - Vector2(w / 2, -fs * 0.35)
		draw_string_outline(font, o, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6 * alpha))
		draw_string(font, o, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.92, 0.82, alpha))


# ------------------------------------------------------------ армии и осады
# Армии и осады рисуются по снимку мира (build_snapshot): его готовит поток
# симуляции после каждого дня, так что отрисовка не трогает живое состояние.

## Снимок для карты: армии (позиция, цвет, рамка, подпись, путь) и осады.
## Вызывается под замком мира (в потоке симуляции или в окне доступа).
static func build_snapshot(g: Game) -> Dictionary:
	var m := g.engine.map
	var player: Variant = g.state.player
	var player_wars: Array = Wars.wars_of(g, player) if player != null else []
	var armies: Array = []
	var ids: Array = g.state.armies.keys()
	ids.sort()
	var colors := {}
	for id in ids:
		var a: Dictionary = g.state.armies[id]
		var owner: Variant = g.ch(a.owner)
		if owner == null or not m.index.has(a.location):
			continue
		var top := Titles.top_liege(g, owner)
		var col: Variant = colors.get(top.id)
		if col == null:
			col = Color("#888888")
			if not top.titles.is_empty():
				var d: Variant = g.title_def(top.titles[0])
				if d != null and d.get("color") is String:
					col = Color(d.color)
			colors[top.id] = col
		var kind := "neutral"
		if a.owner == player:
			kind = "player"
		else:
			for w in player_wars:
				var ps: Variant = Wars.participant_side(w, player)
				var os: Variant = Wars.participant_side(w, a.owner)
				if ps != null and os != null and ps != os:
					kind = "enemy"
					break
		var pos := m.center_of(a.location)
		if not a.path.is_empty() and m.index.has(a.path[0]):
			pos = pos.lerp(m.center_of(a.path[0]), clampf(float(a.progress), 0.0, 1.0))
		var n := int(a.size)
		armies.append({
			"id": id, "location": a.location, "pos": pos, "color": col, "kind": kind,
			"label": ("%.1fk" % (n / 1000.0)) if n >= 1000 else str(n),
			"retreating": a.get("retreating", false),
			"path": a.path.duplicate(), "days": Military.days_to_next(g, a) if not a.path.is_empty() else 0,
		})
	var sieges: Array = []
	var builds := {}
	for p in g.state.provinces.values():
		if p.get("siege") != null and m.index.has(p.id):
			sieges.append({"prov": p.id, "progress": clampf(float(p.siege.progress) / 100.0, 0.0, 1.0)})
		var cons: Variant = p.get("construction")
		if cons is Dictionary and m.index.has(p.id):
			var days := maxf(1.0, Data.num(cons.get("days"), 365))
			builds[p.id] = {"district": cons.get("district"), "building": cons.get("building"), "level": int(cons.get("level", 0)),
				"progress": clampf(1.0 - (float(cons.done) - g.date) / days, 0.0, 1.0)}
	return {"armies": armies, "sieges": sieges, "settlements": settlements_of(g), "builds": builds}


# ------------------------------------------------------------ поселения
# Застройка графств меняется редко: снимок поселений пересобирается, только
# когда меняется game.state.build_ver (районы и постройки).

static var _settle_key := ""
static var _settle_data := {}


static func settlements_of(g: Game) -> Dictionary:
	var key := "%d:%d" % [g.get_instance_id(), int(g.state.get("build_ver", 0))]
	if key == _settle_key:
		return _settle_data
	var out := {}
	var m := g.engine.map
	for p in g.state.provinces.values():
		if not m.index.has(p.id):
			continue
		var pd: Variant = g.content.get_def("provinces", p.id)
		var hs := Data.as_array(pd.get("holdings")) if pd != null else []
		var ds: Dictionary = p.get("districts") if p.get("districts") is Dictionary else {}
		if hs.is_empty() and ds.is_empty() and p.buildings.is_empty():
			continue
		var dl := []
		for d in Districts.all_defs(g) if g.engine.has_feature("districts") else []:
			if ds.has(d.id):
				dl.append([d.id, int(ds[d.id])])
		var bmap := {}
		var special := []
		var other := []
		var great := []
		for b in p.buildings:
			var bd: Variant = g.content.get_def("buildings", b)
			if bd == null:
				continue
			if bd.get("special", false):
				special.append(b)
				continue
			if bd.get("unique") != null:
				great.append(b)
			var did: Variant = Districts.building_district(g, b) if g.engine.has_feature("districts") else null
			if did != null and ds.has(did):
				if not bmap.has(did):
					bmap[did] = []
				bmap[did].append(b)
			else:
				other.append(b)
		var main := ""
		for h in ["castle", "city", "temple"]:
			if hs.has(h):
				main = h
				break
		var levels := 0
		for x in dl:
			levels += int(x[1])
		out[p.id] = {"main": main, "districts": dl, "bmap": bmap, "special": special, "great": great, "other": other, "levels": levels, "count": p.buildings.size()}
	_settle_key = key
	_settle_data = out
	return out


const HOLDING_ICON := {"castle": "castle", "city": "city", "temple": "church"}
static var _plate: StyleBoxFlat


static func _plate_box() -> StyleBoxFlat:
	if _plate == null:
		_plate = StyleBoxFlat.new()
		_plate.bg_color = Color(0.09, 0.07, 0.05, 0.82)
		_plate.border_color = Color(0.83, 0.68, 0.38, 0.85)
		_plate.set_border_width_all(1)
		_plate.set_corner_radius_all(4)
		_plate.shadow_color = Color(0, 0, 0, 0.45)
		_plate.shadow_size = 2
		_plate.shadow_offset = Vector2(1, 2)
	return _plate


func _hex(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := PI / 6.0 + i * PI / 3.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Поселения: вдали — достопримечательности; ближе — печати застроенных
## графств (герб владения и точки районов); вблизи — главный силуэт, районы-
## шестиугольники с уровнем и постройки под ними. В режиме «Застройка» всё это
## видно с большей высоты и у всех графств.
func _draw_settlements(snap: Dictionary) -> void:
	var data: Dictionary = snap.get("settlements", {})
	if data.is_empty():
		return
	var m := view.map
	var g := view.game
	var dmode := view.mode == "districts"
	var z := view.zoom * (1.6 if dmode else 1.0)
	var builds: Dictionary = snap.get("builds", {})
	if z < 1.25:
		_draw_landmarks(data)
		return
	var sc := clampf(view.zoom / 3.2, 0.9, 1.7)
	for i in m.provinces.size():
		var pid: String = m.provinces[i]
		var s: Variant = data.get(pid)
		if s == null:
			continue
		var c := view.map_to_screen(Vector2(m.centers[i * 2], m.centers[i * 2 + 1]))
		if c.x < -120 or c.y < -140 or c.x > size.x + 120 or c.y > size.y + 120:
			continue
		var span := sqrt(float(m.areas[i])) * view.zoom
		if z >= 3.0 and span >= 70.0:
			_name_below[i] = _draw_vignette(g, s, c, builds.get(pid), z >= 3.6 and span >= 100.0, sc)
		elif span >= 26.0 and (dmode or _developed(s) or builds.has(pid)):
			_draw_seal(g, s, c + Vector2(0, -12), builds.get(pid))


## Застроено ли графство сверх того, что дали владения.
static func _developed(s: Dictionary) -> bool:
	if s.count > 0:
		return true
	for x in s.districts:
		if int(x[1]) > 1:
			return true
	return s.districts.size() > 3


## Издалека — только достопримечательности (особые постройки).
func _draw_landmarks(data: Dictionary) -> void:
	if view.zoom < 0.75:
		return
	var m := view.map
	for pid in data:
		var s: Dictionary = data[pid]
		var marks: Array = s.special + s.get("great", [])
		if marks.is_empty():
			continue
		var c := view.map_to_screen(m.center_of(pid)) + Vector2(0, -6)
		if c.x < -20 or c.y < -20 or c.x > size.x + 20 or c.y > size.y + 20:
			continue
		for k in marks.size():
			var mc := c + Vector2((k - (marks.size() - 1) / 2.0) * 19.0, 0)
			var great: bool = k >= s.special.size()
			draw_circle(mc + Vector2(1, 2), 8.5, Color(0, 0, 0, 0.45))
			draw_circle(mc, 8.5, Color(0.12, 0.08, 0.04, 0.92))
			if great:
				draw_arc(mc, 10.5, 0, TAU, 28, Color(1.0, 0.85, 0.4, 0.35), 3.0, true)
			draw_arc(mc, 8.5, 0, TAU, 24, Color("#ffd36a") if great else Color("#e8c060"), 1.6, true)
			var icon := Icons.resolve(view.game.content.get_def("buildings", marks[k]).get("icon", "star"))
			draw_texture(Icons.texture(icon if icon != "" else "star", 12), mc - Vector2(6, 6))


## Печать поселения: герб владения в круге, по нижней дуге — точки районов
## (цвет района, размер — уровень); кольцо с молоточком — идёт стройка.
func _draw_seal(g: Game, s: Dictionary, c: Vector2, build: Variant) -> void:
	var r := 10.0
	draw_circle(c + Vector2(1, 2), r + 1, Color(0, 0, 0, 0.42))
	draw_circle(c, r, Color(0.11, 0.08, 0.05, 0.9))
	var rim := Color("#f0c860") if not (s.special.is_empty() and s.get("great", []).is_empty()) else Color(0.8, 0.67, 0.42, 0.95)
	draw_arc(c, r, 0, TAU, 28, rim, 1.5, true)
	var icon: String = HOLDING_ICON.get(s.main, "castle")
	draw_texture(Icons.texture(icon, 14), c - Vector2(7, 7.5))
	var n: int = s.districts.size()
	for k in n:
		# точки — по нижней дуге печати
		var a := PI / 2 + ((n - 1) / 2.0 - k) * 0.6
		var d: Variant = g.content.get_def("districts", s.districts[k][0])
		var col := Color(str(d.get("color", "#cccccc"))) if d != null else Color.GRAY
		var p := c + Vector2(cos(a), sin(a)) * (r + 2.5)
		var pr := 1.8 + 0.6 * float(s.districts[k][1])
		draw_circle(p + Vector2(0.6, 0.9), pr + 0.6, Color(0, 0, 0, 0.5))
		draw_circle(p, pr + 0.6, Color(0.1, 0.07, 0.04, 0.95))
		draw_circle(p, pr, col)
	if build != null:
		var bp := c + Vector2(r + 5, -r + 2)
		draw_circle(bp, 6.5, Color(0.1, 0.07, 0.04, 0.92))
		draw_arc(bp, 6.5, -PI / 2, -PI / 2 + TAU * float(build.progress), 16, Color("#ffcc55"), 1.8, true)
		draw_texture(Icons.texture("hammer", 9, "silver"), bp - Vector2(4.5, 4.5))


## Поселение вблизи: силуэт главного владения (чем застроеннее графство, тем
## крупнее), под ним районы — шестиугольники цвета района с гербом и точками
## уровня, под каждым — его постройки в круглых печатках.
func _draw_vignette(g: Game, s: Dictionary, c: Vector2, build: Variant, with_buildings: bool, sc: float) -> float:
	var n: int = s.districts.size()
	var hr := 11.0 * sc
	var gap := 4.0 * sc
	var row_w := n * hr * 2.0 + maxi(0, n - 1) * gap
	var main_sz := roundi(clampf(18.0 + 2.5 * maxf(0.0, float(s.levels) - 2.0), 18.0, 34.0) * sc)
	var isz := roundi(14 * sc)
	var bsz := roundi(13 * sc)
	var br := bsz * 0.5 + 3.0 * sc
	# рисунок — вокруг середины графства, название — под ним
	var kmax := 0
	if with_buildings:
		for x in s.districts:
			kmax = maxi(kmax, s.bmap.get(x[0], []).size())
	var col_h := (9.0 * sc + kmax * (br * 2.0 + 2.0 * sc)) if kmax > 0 else 0.0
	var height := main_sz + 4.0 * sc + hr * 2.0 + 5.0 * sc + col_h
	var top := Vector2(c.x, c.y - height * 0.5 + main_sz * 0.5)
	# главный силуэт — тень и золото
	if s.main != "":
		var tex := Icons.texture(HOLDING_ICON.get(s.main, "castle"), main_sz)
		draw_texture(tex, top - Vector2(main_sz, main_sz) * 0.5 + Vector2(1.5, 2.0) * sc, Color(0, 0, 0, 0.55))
		draw_texture(tex, top - Vector2(main_sz, main_sz) * 0.5)
	# достопримечательности — рядом с силуэтом, в золотом круге
	for k in s.special.size():
		var sp := top + Vector2(main_sz * 0.5 + (10.0 + k * 19.0) * sc, -2.0)
		var rr := 8.5 * sc
		draw_circle(sp + Vector2(1, 1.5), rr, Color(0, 0, 0, 0.45))
		draw_circle(sp, rr, Color(0.13, 0.09, 0.04, 0.94))
		draw_arc(sp, rr, 0, TAU, 20, Color("#f0c860"), 1.6, true)
		var si := Icons.resolve(g.content.get_def("buildings", s.special[k]).get("icon", "star"))
		var ssz := roundi(12 * sc)
		draw_texture(Icons.texture(si if si != "" else "star", ssz), sp - Vector2(ssz, ssz) * 0.5)
	var y := top.y + main_sz * 0.5 + hr + 4.0 * sc
	var x0 := c.x - row_w / 2.0 + hr
	for k in n:
		var did: String = s.districts[k][0]
		var lvl: int = s.districts[k][1]
		var d: Variant = g.content.get_def("districts", did)
		var col := Color(str(d.get("color", "#cccccc"))) if d != null else Color.GRAY
		var hc := Vector2(x0 + k * (hr * 2.0 + gap), y)
		draw_colored_polygon(_hex(hc + Vector2(1.2, 2.2) * sc, hr + 1.0), Color(0, 0, 0, 0.5))
		draw_colored_polygon(_hex(hc, hr + 1.2), Color(0.09, 0.06, 0.03, 0.95))
		var hex := _hex(hc, hr)
		draw_colored_polygon(hex, col.darkened(0.3))
		draw_colored_polygon(_hex(hc + Vector2(0, -0.8 * sc), hr - 2.6 * sc), col.darkened(0.05))
		hex.append(hex[0])
		draw_polyline(hex, Color("#ecc97e"), 1.3, true)
		var di := Icons.resolve(d.get("icon", "star")) if d != null else "star"
		draw_texture(Icons.texture(di if di != "" else "star", isz, "ink"), hc - Vector2(isz, isz) * 0.5 + Vector2(0, -0.5))
		# уровень — точки под шестиугольником
		for j in lvl:
			var pp := hc + Vector2((j - (lvl - 1) / 2.0) * 5.5 * sc, hr + 3.0 * sc)
			draw_circle(pp, 2.4 * sc, Color(0.1, 0.07, 0.04, 0.95))
			draw_circle(pp, 1.6 * sc, Color("#f2d27a"))
		if with_buildings:
			var bl: Array = s.bmap.get(did, [])
			for j in bl.size():
				var bp := Vector2(hc.x, hc.y + hr + 9.0 * sc + br + j * (br * 2.0 + 2.0 * sc))
				var is_great: bool = s.get("great", []).has(bl[j])
				draw_circle(bp + Vector2(1, 1.5), br, Color(0, 0, 0, 0.45))
				if is_great:
					draw_circle(bp, br + 2.5 * sc, Color(1.0, 0.82, 0.35, 0.3))
				draw_circle(bp, br, Color(0.12, 0.09, 0.05, 0.93))
				draw_arc(bp, br, 0, TAU, 20, Color("#ffd36a") if is_great else col.lightened(0.15), 2.0 if is_great else 1.3, true)
				var bi := Icons.resolve(g.content.get_def("buildings", bl[j]).get("icon", "castle"))
				draw_texture(Icons.texture(bi if bi != "" else "castle", bsz), bp - Vector2(bsz, bsz) * 0.5)
	# стройка — леса с кольцом готовности справа от ряда
	if build != null:
		var rr := 9.5 * sc
		var bp := Vector2(c.x + row_w / 2.0 + rr + 6.0 * sc, y)
		draw_circle(bp + Vector2(1, 1.5), rr, Color(0, 0, 0, 0.45))
		draw_circle(bp, rr, Color(0.1, 0.07, 0.04, 0.92))
		draw_arc(bp, rr, -PI / 2, -PI / 2 + TAU * float(build.progress), 24, Color("#ffcc55"), 2.0, true)
		var ssz := roundi(13 * sc)
		draw_texture(Icons.texture("scaffold", ssz, "silver"), bp - Vector2(ssz, ssz) * 0.5)
	return c.y + height * 0.5


func _snapshot() -> Dictionary:
	if view.sim != null and view.sim.is_running():
		return view.sim.get_snapshot()
	return build_snapshot(view.game)


func _draw_sieges(snap: Dictionary) -> void:
	var m := view.map
	var tower := Icons.texture("tower", 16)
	for s in snap.get("sieges", []):
		var c := view.map_to_screen(m.center_of(s.prov)) + Vector2(0, 12)
		draw_circle(c, 12, Color(0, 0, 0, 0.6))
		draw_arc(c, 10, 0, TAU, 32, Color(0.2, 0.15, 0.1, 0.9), 3.0, true)
		draw_arc(c, 10, -PI / 2, -PI / 2 + TAU * float(s.progress), 32, Color("#ffcc33"), 3.0, true)
		draw_texture(tower, c - Vector2(8, 8))


func _draw_path(snap: Dictionary) -> void:
	var id: Variant = view.selected_army
	if id == null:
		return
	var a: Variant = null
	for x in snap.get("armies", []):
		if x.id == id:
			a = x
			break
	if a == null or a.path.is_empty():
		return
	var m := view.map
	var pts := PackedVector2Array([view.map_to_screen(a.pos)])
	for p in a.path:
		if m.index.has(p):
			pts.append(view.map_to_screen(m.center_of(p)))
	for i in pts.size() - 1:
		draw_dashed_line(pts[i], pts[i + 1], Color(0, 0, 0, 0.5), 4.5, 9.0, true)
		draw_dashed_line(pts[i], pts[i + 1], Color("#ffe9a8"), 2.5, 9.0, true)
	var last := pts[pts.size() - 1]
	draw_circle(last, 6, Color(0, 0, 0, 0.6))
	draw_circle(last, 4, Color("#ffe9a8"))
	var font := Fonts.bold()
	var txt := "%d" % int(a.days)
	draw_string_outline(font, last + Vector2(8, -6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.7))
	draw_string(font, last + Vector2(8, -6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffe9a8"))


func _draw_armies(snap: Dictionary) -> void:
	var by_loc := {}
	var font := Fonts.bold()
	var swords := Icons.texture("swords", 14)
	var flag := Icons.texture("banner", 14, "silver")
	_army_pos = []
	for a in snap.get("armies", []):
		var k: int = by_loc.get(a.location, 0)
		by_loc[a.location] = k + 1
		var pos := view.map_to_screen(a.pos) + Vector2(k * 12, -16 - k * 8)
		if pos.x < -60 or pos.y < -30 or pos.x > size.x + 60 or pos.y > size.y + 30:
			continue
		_army_pos.append({"id": a.id, "pos": pos})
		var col: Color = a.color
		var label: String = a.label
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var w := tw + 26.0
		var r := Rect2(pos - Vector2(w / 2, 10), Vector2(w, 20))
		var selected: bool = a.id == view.selected_army
		draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.5))
		draw_rect(r, col.darkened(0.35))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 7)), Color(1, 1, 1, 0.12))
		var border := Color("#1a1208")
		if selected:
			border = Color("#fff6c8")
		elif a.kind == "player":
			border = Color("#e8c050")
		elif a.kind == "enemy":
			border = Color("#ff4a3a")
		draw_rect(r, border, false, 3.0 if selected else 1.6)
		draw_texture(flag if a.retreating else swords, r.position + Vector2(4, 3))
		draw_string_outline(font, r.position + Vector2(20, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.6))
		draw_string(font, r.position + Vector2(20, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func army_at(pos: Vector2) -> Variant:
	var best: Variant = null
	var bd := 18.0
	for p in _army_pos:
		var d: float = p.pos.distance_to(pos)
		if d < bd:
			bd = d
			best = p.id
	return best

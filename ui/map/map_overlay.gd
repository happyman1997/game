class_name MapOverlay
extends Control
## Слой поверх карты: подписи держав (по дуге), названия графств при
## приближении, армии, осады, путь выбранной армии.

var view: MapView
var labels: Array = []
## Провинции с подсветкой (выбор персонажа, цели войны) — id → true.
var highlighted := {}
## Подсказка для армии: Callable(army_id) -> String.
var army_tooltip: Callable
var _army_pos: Array = []


func _process(_delta: float) -> void:
	if view != null and view.game != null:
		queue_redraw()


func _draw() -> void:
	if view == null or view.game == null or view.map == null:
		return
	_draw_labels()
	_draw_county_names()
	_draw_sieges()
	_draw_path()
	_draw_armies()


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
		if pos.x < -80 or pos.y < -20 or pos.x > size.x + 80 or pos.y > size.y + 20:
			continue
		var name := g.name_of("provinces", m.provinces[p])
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var o := pos - Vector2(w / 2, -fs * 0.35)
		draw_string_outline(font, o, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6 * alpha))
		draw_string(font, o, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.92, 0.82, alpha))


# ------------------------------------------------------------ армии и осады

func _army_map_pos(a: Dictionary) -> Vector2:
	var m := view.map
	var p := m.center_of(a.location)
	if not a.path.is_empty():
		var q := m.center_of(a.path[0])
		p = p.lerp(q, clampf(float(a.progress), 0.0, 1.0))
	return p


func _draw_sieges() -> void:
	var g := view.game
	var m := view.map
	var tower := Icons.texture("tower", 16)
	for p in g.state.provinces.values():
		if p.get("siege") == null:
			continue
		if not m.index.has(p.id):
			continue
		var c := view.map_to_screen(m.center_of(p.id)) + Vector2(0, 12)
		draw_circle(c, 12, Color(0, 0, 0, 0.6))
		draw_arc(c, 10, 0, TAU, 32, Color(0.2, 0.15, 0.1, 0.9), 3.0, true)
		var prog := clampf(float(p.siege.progress) / 100.0, 0.0, 1.0)
		draw_arc(c, 10, -PI / 2, -PI / 2 + TAU * prog, 32, Color("#ffcc33"), 3.0, true)
		draw_texture(tower, c - Vector2(8, 8))


func _draw_path() -> void:
	var g := view.game
	var id: Variant = view.selected_army
	if id == null or not g.state.armies.has(id):
		return
	var a: Dictionary = g.state.armies[id]
	if a.path.is_empty():
		return
	var m := view.map
	var pts := PackedVector2Array([view.map_to_screen(_army_map_pos(a))])
	for p in a.path:
		pts.append(view.map_to_screen(m.center_of(p)))
	for i in pts.size() - 1:
		draw_dashed_line(pts[i], pts[i + 1], Color(0, 0, 0, 0.5), 4.5, 9.0, true)
		draw_dashed_line(pts[i], pts[i + 1], Color("#ffe9a8"), 2.5, 9.0, true)
	var last := pts[pts.size() - 1]
	draw_circle(last, 6, Color(0, 0, 0, 0.6))
	draw_circle(last, 4, Color("#ffe9a8"))
	var font := Fonts.bold()
	var txt := "%d" % Military.days_to_next(g, a)
	draw_string_outline(font, last + Vector2(8, -6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.7))
	draw_string(font, last + Vector2(8, -6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffe9a8"))


func _draw_armies() -> void:
	var g := view.game
	var player: Variant = g.state.player
	var player_wars: Array = Wars.wars_of(g, player) if player != null else []
	var by_loc := {}
	var font := Fonts.bold()
	var swords := Icons.texture("swords", 14)
	var flag := Icons.texture("banner", 14, "silver")
	_army_pos = []
	var ids: Array = g.state.armies.keys()
	ids.sort()
	for id in ids:
		var a: Dictionary = g.state.armies[id]
		var owner: Variant = g.ch(a.owner)
		if owner == null:
			continue
		var k: int = by_loc.get(a.location, 0)
		by_loc[a.location] = k + 1
		var pos := view.map_to_screen(_army_map_pos(a)) + Vector2(k * 12, -16 - k * 8)
		if pos.x < -60 or pos.y < -30 or pos.x > size.x + 60 or pos.y > size.y + 30:
			continue
		_army_pos.append({"id": id, "pos": pos})
		var top := Titles.top_liege(g, owner)
		var col := Color("#888888")
		if not top.titles.is_empty():
			var d: Variant = g.title_def(top.titles[0])
			if d != null and d.get("color") is String:
				col = Color(d.color)
		var enemy := false
		for w in player_wars:
			var ps: Variant = Wars.participant_side(w, player)
			var os: Variant = Wars.participant_side(w, a.owner)
			if ps != null and os != null and ps != os:
				enemy = true
		var n := int(a.size)
		var label := ("%.1fk" % (n / 1000.0)) if n >= 1000 else str(n)
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var w := tw + 26.0
		var r := Rect2(pos - Vector2(w / 2, 10), Vector2(w, 20))
		var selected: bool = id == view.selected_army
		draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.5))
		draw_rect(r, col.darkened(0.35))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 7)), Color(1, 1, 1, 0.12))
		var border := Color("#1a1208")
		if selected:
			border = Color("#fff6c8")
		elif a.owner == player:
			border = Color("#e8c050")
		elif enemy:
			border = Color("#ff4a3a")
		draw_rect(r, border, false, 3.0 if selected else 1.6)
		draw_texture(flag if a.get("retreating", false) else swords, r.position + Vector2(4, 3))
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

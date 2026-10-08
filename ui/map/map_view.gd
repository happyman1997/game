class_name MapView
extends Control
## Карта мира: шейдерная отрисовка (map.gdshader), камера с плавным зумом,
## подписи держав, армии и осады (MapOverlay), выбор провинций и армий.
## Хост (App) получает сигналы и даёт подсказку для провинции.

signal province_clicked(id: String)
signal province_right_clicked(id: String)
signal army_clicked(id: String)

const MIN_ZOOM := 0.3
const MAX_ZOOM := 9.0
const TW := 256

var game: Game
var map: MapData
var mode := "realms"
## Экранных пикселей на пиксель карты и точка карты в левом верхнем углу.
var zoom := 1.0
var origin := Vector2.ZERO
var hover := -1
var selected_province: Variant = null
var selected_army: Variant = null
## Подсказка для провинции: Callable(id) -> String (BBCode).
var tooltip_provider: Callable
## Интерактивность (в главном меню карта — только фон).
var interactive := true
## Медленное «парение» камеры (фон главного меню).
var drift := Vector2.ZERO
var paper_bias := 0.0

var surface: ColorRect
var overlay: MapOverlay
var material_map: ShaderMaterial

var _target_zoom := 1.0
var _zoom_anchor := Vector2.ZERO
var _target_origin: Variant = null
var _drag_from: Variant = null
var _drag_origin := Vector2.ZERO
var _dragging := false
var _signature := ""
var _dirty := true
var _time := 0.0
var _color_img: Image
var _realm_img: Image
var _flags_img: Image
var _color_tex: ImageTexture
var _realm_tex: ImageTexture
var _flags_tex: ImageTexture
var _sig_timer := 0.0

## Державы: индекс → {owner, area, cx, cy, ...}; провинция → индекс державы.
var realm_of := PackedInt32Array()
var realms: Array = []

static var _static_cache := {}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	surface = ColorRect.new()
	surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material_map = ShaderMaterial.new()
	material_map.shader = load("res://ui/map/map.gdshader")
	surface.material = material_map
	add_child(surface)
	overlay = MapOverlay.new()
	overlay.view = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	set_meta("tip", func(): return _tooltip())


func set_game(g: Game) -> void:
	var first := map == null
	game = g
	if map != g.engine.map:
		map = g.engine.map
		_build_static()
		first = true
	_dirty = true
	if first:
		fit.call_deferred()


func set_mode(id: String) -> void:
	mode = id
	_dirty = true


func invalidate() -> void:
	_dirty = true


# ------------------------------------------------------------ статические текстуры

func _build_static() -> void:
	var key := map.get_instance_id()
	var st: Dictionary
	if _static_cache.has(key):
		st = _static_cache[key]
	else:
		st = _make_static()
		_static_cache.clear()
		_static_cache[key] = st
	var P := map.provinces.size()
	var th := maxi(1, ceili(P / float(TW)))
	_color_img = Image.create(TW, th, false, Image.FORMAT_RGBA8)
	_realm_img = Image.create(TW, th, false, Image.FORMAT_RGBA8)
	_flags_img = Image.create(TW, th, false, Image.FORMAT_RGBA8)
	_color_tex = ImageTexture.create_from_image(_color_img)
	_realm_tex = ImageTexture.create_from_image(_realm_img)
	_flags_tex = ImageTexture.create_from_image(_flags_img)
	var m := material_map
	m.set_shader_parameter("id_tex", st.id)
	m.set_shader_parameter("land_tex", st.land)
	m.set_shader_parameter("noise_tex", st.noise)
	m.set_shader_parameter("terrain_tex", st.terrain)
	m.set_shader_parameter("color_tex", _color_tex)
	m.set_shader_parameter("realm_tex", _realm_tex)
	m.set_shader_parameter("flags_tex", _flags_tex)
	m.set_shader_parameter("TW", TW)
	m.set_shader_parameter("map_size", Vector2(map.width, map.height))


func _make_static() -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var W := map.width
	var H := map.height
	var id_img := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, map.pixels.to_byte_array())
	# Маска воды: у воды все байты 255 (индекс -1), у суши альфа 0.
	var water := Image.create(W, H, false, Image.FORMAT_RGBA8)
	water.fill(Color.BLACK)
	water.blend_rect(id_img, Rect2i(0, 0, W, H), Vector2i.ZERO)
	water.convert(Image.FORMAT_L8)
	water.generate_mipmaps()
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	noise.seed = 1066
	var nimg := noise.get_seamless_image(256, 256, false, false, 0.1, true)
	nimg.generate_mipmaps()
	# Местность по провинциям: цвет и высота.
	var P := map.provinces.size()
	var th := maxi(1, ceili(P / float(TW)))
	var terr := Image.create(TW, th, false, Image.FORMAT_RGBA8)
	var c := game.content
	for i in P:
		var pid: String = map.provinces[i]
		var pd: Variant = c.get_def("provinces", pid)
		var col := Color("#9a9a7a")
		var hgt := 0.1
		if map.impassable[i] == 1:
			col = Color("#7d746a")
			hgt = 1.0
		elif pd != null:
			var td: Variant = c.get_def("terrain", str(pd.get("terrain", "")))
			if td != null:
				if td.get("color") is String:
					col = Color(td.color)
				hgt = Data.num(td.get("height"), 0.1)
		col.a = clampf(hgt, 0.0, 1.0)
		terr.set_pixel(i % TW, i / TW, col)
	print("Карта: текстуры подготовлены за %d мс" % (Time.get_ticks_msec() - t0))
	return {
		"id": ImageTexture.create_from_image(id_img),
		"land": ImageTexture.create_from_image(water),
		"noise": ImageTexture.create_from_image(nimg),
		"terrain": ImageTexture.create_from_image(terr),
	}


# ------------------------------------------------------------ раскраска

func _compute_signature() -> String:
	var g := game
	var parts := PackedStringArray([mode, g.loc.lang, str(g.state.player)])
	for p in map.provinces:
		var t: Variant = g.state.titles.get(p)
		var st: Variant = g.state.provinces.get(p)
		parts.append("%s:%s" % [t.holder if t != null else "", st.occupant if st != null else ""])
	if mode != "realms" and mode != "culture" and mode != "faith" and mode != "terrain":
		parts.append(str(g.date / 30))
	parts.append(str(g.state.wars.size()))
	return "|".join(parts)


func _to_color(v: Variant) -> Variant:
	if v is Color:
		return v
	if v is String and v.begins_with("#"):
		return Color(v)
	if v is Array and v.size() >= 3:
		return Color8(int(v[0]), int(v[1]), int(v[2]))
	return null


func recolor() -> void:
	var g := game
	var reg := g.engine.ui.map_modes
	var spec: Variant = reg.get_item(mode) if reg.has(mode) else reg.get_item("realms")
	var transparent: bool = spec != null and spec.get("transparent", false)
	var P := map.provinces.size()
	realm_of = PackedInt32Array()
	realm_of.resize(P)
	realm_of.fill(-1)
	realms = []
	var realm_ids := {}
	var sub_ids := {}
	var mode_name := mode
	for i in P:
		var id: String = map.provinces[i]
		var x := i % TW
		var y := i / TW
		var col: Variant = null
		var realm := 65535
		var sub := 65535
		var flag := Color(0, 0, 0, 0)
		if map.impassable[i] == 1:
			realm = 65534
			sub = 65534
		else:
			var t: Variant = g.state.titles.get(id)
			var holder: Variant = g.ch(t.holder) if t != null else null
			if holder != null:
				var top := Titles.top_liege(g, holder)
				if not realm_ids.has(top.id):
					realm_ids[top.id] = realm_ids.size()
					realms.append({"owner": top.id, "area": 0.0, "provs": []})
				realm = realm_ids[top.id]
				realm_of[i] = realm
				realms[realm].area += map.areas[i]
				realms[realm].provs.append(i)
				var s: Dictionary = holder
				for k in 20:
					if s.liege == null or s.liege == top.id:
						break
					var l: Variant = g.ch(s.liege)
					if l == null:
						break
					s = l
				if not sub_ids.has(s.id):
					sub_ids[s.id] = sub_ids.size()
				sub = sub_ids[s.id]
			if spec != null and not transparent:
				var r: Variant = spec.color.call(g, id)
				col = _to_color(r)
			var st: Variant = g.state.provinces.get(id)
			if st != null and st.occupant != null and mode_name == "realms":
				var o: Variant = g.ch(st.occupant)
				if o != null:
					var ot := Titles.top_liege(g, o)
					var od: Variant = g.title_def(ot.titles[0]) if not ot.titles.is_empty() else null
					if od != null and od.get("color") is String:
						flag = Color(od.color)
						flag.a = 1.0
			if overlay.highlighted.has(id) and flag.a == 0.0:
				flag = Color(1, 1, 1, 0.5)
		_color_img.set_pixel(x, y, col if col != null else Color(0, 0, 0, 0))
		_realm_img.set_pixel(x, y, Color8(realm & 255, realm >> 8, sub & 255, sub >> 8))
		_flags_img.set_pixel(x, y, flag)
	_color_tex.update(_color_img)
	_realm_tex.update(_realm_img)
	_flags_tex.update(_flags_img)
	material_map.set_shader_parameter("overlay_strength", 0.0 if transparent else 1.0)
	_compute_labels()
	overlay.queue_redraw()


## Самая большая связная (по суше) часть державы — без островов и анклавов.
func _main_component(provs: Array) -> Array:
	var inset := {}
	for i in provs:
		inset[i] = true
	var seen := {}
	var best: Array = []
	var best_area := -1.0
	for start in provs:
		if seen.has(start):
			continue
		var comp := [start]
		seen[start] = true
		var area := 0.0
		var k := 0
		while k < comp.size():
			var i: int = comp[k]
			k += 1
			area += map.areas[i]
			for nid in map.land_neighbors.get(map.provinces[i], []):
				var j: int = map.index.get(nid, -1)
				if j >= 0 and inset.has(j) and not seen.has(j):
					seen[j] = true
					comp.append(j)
		if area > best_area:
			best_area = area
			best = comp
	return best


## Подписи держав: центр, главная ось (по провинциям) и размер шрифта.
func _compute_labels() -> void:
	var g := game
	var labels := []
	for r in realms:
		if r.area < 1200:
			continue
		var c: Variant = g.ch(r.owner)
		if c == null or c.titles.is_empty():
			continue
		var provs := _main_component(r.provs)
		var sx := 0.0
		var sy := 0.0
		var sa := 0.0
		for i in provs:
			var a := float(map.areas[i])
			sx += map.centers[i * 2] * a
			sy += map.centers[i * 2 + 1] * a
			sa += a
		var cx := sx / sa
		var cy := sy / sa
		var cxx := 0.0
		var cyy := 0.0
		var cxy := 0.0
		for i in provs:
			var a := float(map.areas[i])
			var dx: float = map.centers[i * 2] - cx
			var dy: float = map.centers[i * 2 + 1] - cy
			cxx += dx * dx * a
			cyy += dy * dy * a
			cxy += dx * dy * a
		var angle := 0.5 * atan2(2.0 * cxy, cxx - cyy)
		if angle > PI / 2:
			angle -= PI
		if angle < -PI / 2:
			angle += PI
		angle = clampf(angle, -0.6, 0.6)
		var dir := Vector2(cos(angle), sin(angle))
		# протяжённость вдоль оси
		var lo := 0.0
		var hi := 0.0
		for i in provs:
			var rad := sqrt(float(map.areas[i])) * 0.5
			var d := (Vector2(map.centers[i * 2], map.centers[i * 2 + 1]) - Vector2(cx, cy)).dot(dir)
			lo = minf(lo, d - rad)
			hi = maxf(hi, d + rad)
		var extent := (hi - lo) * 0.78
		var mid := Vector2(cx, cy) + dir * ((lo + hi) * 0.5)
		# центр должен быть внутри державы — иначе берём ближайший центр провинции
		var mp := Vector2i(mid.round())
		var pi_at := map.province_at(mp.x, mp.y)
		if pi_at < 0 or realm_of[pi_at] != realm_of[r.provs[0]]:
			var best := INF
			for i in provs:
				var pc := Vector2(map.centers[i * 2], map.centers[i * 2 + 1])
				var dd := pc.distance_squared_to(mid)
				if dd < best:
					best = dd
					mid = pc
		var text := Titles.short_name(g, c.titles[0]).to_upper()
		var size := clampf(extent / maxf(4.0, text.length() * 0.95), 6.0, 46.0)
		size = minf(size, sqrt(sa) * 0.32)
		labels.append({"text": text, "pos": mid, "angle": angle, "size": size, "extent": extent, "owner": r.owner})
	labels.sort_custom(func(a, b): return a.size > b.size)
	overlay.labels = labels


# ------------------------------------------------------------ камера

func fit() -> void:
	if map == null:
		return
	var s := size if size.x > 0 else Vector2(1600, 900)
	zoom = maxf(MIN_ZOOM, maxf(s.x / map.width, s.y / map.height) * 1.02)
	_target_zoom = zoom
	origin = Vector2(map.width, map.height) / 2 - s / 2 / zoom
	_target_origin = null


## Центрировать карту на провинции (плавно).
func focus(prov_id: String, z: float = 0.0) -> void:
	if map == null or not map.index.has(prov_id):
		return
	if z > 0:
		zoom = z
		_target_zoom = z
	var c := map.center_of(prov_id)
	_target_origin = c - size / 2 / zoom


func screen_to_map(p: Vector2) -> Vector2:
	return origin + p / zoom


func map_to_screen(p: Vector2) -> Vector2:
	return (p - origin) * zoom


func province_at_screen(p: Vector2) -> int:
	var m := screen_to_map(p)
	return map.province_at(floori(m.x), floori(m.y))


func _clamp_view() -> void:
	var w := size.x / zoom
	var h := size.y / zoom
	var mx := float(map.width)
	var my := float(map.height)
	var margin_x := maxf(0.0, w * 0.4)
	var margin_y := maxf(0.0, h * 0.4)
	origin.x = clampf(origin.x, -margin_x, maxf(-margin_x, mx - w + margin_x))
	origin.y = clampf(origin.y, -margin_y, maxf(-margin_y, my - h + margin_y))
	if w > mx + 2 * margin_x:
		origin.x = (mx - w) / 2
	if h > my + 2 * margin_y:
		origin.y = (my - h) / 2


func _process(delta: float) -> void:
	if map == null or game == null:
		return
	_time += delta
	# плавный зум вокруг точки под курсором
	if absf(_target_zoom - zoom) > 0.0005:
		var anchor_map := screen_to_map(_zoom_anchor)
		zoom = lerpf(zoom, _target_zoom, 1.0 - exp(-delta * 14.0))
		origin = anchor_map - _zoom_anchor / zoom
		overlay.queue_redraw()
	if _target_origin != null:
		origin = origin.lerp(_target_origin, 1.0 - exp(-delta * 8.0))
		if origin.distance_to(_target_origin) < 0.5:
			_target_origin = null
		overlay.queue_redraw()
	if drift != Vector2.ZERO:
		origin += drift * delta
		# парим только в пределах карты (без тёмных краёв)
		var max_x := maxf(0.0, map.width - size.x / zoom)
		var max_y := maxf(0.0, map.height - size.y / zoom)
		if (origin.x > max_x and drift.x > 0) or (origin.x < 0.0 and drift.x < 0):
			drift.x = -drift.x
		if (origin.y > max_y and drift.y > 0) or (origin.y < 0.0 and drift.y < 0):
			drift.y = -drift.y
		origin = origin.clamp(Vector2(-2, -2), Vector2(max_x + 2, max_y + 2))
		overlay.queue_redraw()
	elif interactive:
		_keyboard_pan(delta)
	if drift == Vector2.ZERO:
		_clamp_view()
	# перекраска при изменении мира (проверяем не чаще 5 раз в секунду)
	_sig_timer -= delta
	if _dirty or _sig_timer <= 0.0:
		_sig_timer = 0.2
		var sig := _compute_signature()
		if _dirty or sig != _signature:
			_signature = sig
			_dirty = false
			recolor()
	var m := material_map
	m.set_shader_parameter("rect_size", size)
	m.set_shader_parameter("origin", origin)
	m.set_shader_parameter("zoom", zoom)
	m.set_shader_parameter("hover_idx", hover if interactive else -1)
	var sel := -1
	if selected_province != null:
		sel = map.index.get(selected_province, -1)
	m.set_shader_parameter("sel_idx", sel)
	m.set_shader_parameter("time", _time)
	m.set_shader_parameter("paper_bias", paper_bias)


func _keyboard_pan(delta: float) -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1
	if v != Vector2.ZERO:
		origin += v.normalized() * 700.0 * delta / zoom
		_target_origin = null
		overlay.queue_redraw()


func zoom_by(factor: float, anchor: Vector2) -> void:
	_target_zoom = clampf(_target_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_zoom_anchor = anchor


# ------------------------------------------------------------ ввод

func _gui_input(event: InputEvent) -> void:
	if not interactive or map == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.18, mb.position)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.18, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_drag_from = mb.position
				_drag_origin = origin
				_dragging = false
			else:
				var was := _dragging
				_drag_from = null
				_dragging = false
				if not was and mb.button_index == MOUSE_BUTTON_LEFT:
					_click(mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var p := province_at_screen(mb.position)
			if p >= 0:
				province_right_clicked.emit(map.provinces[p])
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_from != null:
			var d: Vector2 = mm.position - _drag_from
			if absf(d.x) + absf(d.y) > 4:
				_dragging = true
			if _dragging:
				origin = _drag_origin - d / zoom
				_target_origin = null
				overlay.queue_redraw()
		var h := province_at_screen(mm.position)
		if h != hover:
			hover = h
	elif event is InputEventMagnifyGesture:
		zoom_by((event as InputEventMagnifyGesture).factor, (event as InputEventMagnifyGesture).position)
	elif event is InputEventPanGesture:
		origin += (event as InputEventPanGesture).delta * 12.0 / zoom
		overlay.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover = -1


func _click(pos: Vector2) -> void:
	var army: Variant = overlay.army_at(pos)
	if army != null:
		army_clicked.emit(army)
		return
	var p := province_at_screen(pos)
	if p >= 0:
		province_clicked.emit(map.provinces[p])


func _tooltip() -> Variant:
	if not interactive or _dragging or hover < 0 or not tooltip_provider.is_valid():
		return null
	var army: Variant = overlay.army_at(get_local_mouse_position())
	if army != null and overlay.army_tooltip.is_valid():
		return overlay.army_tooltip.call(army)
	return tooltip_provider.call(map.provinces[hover])

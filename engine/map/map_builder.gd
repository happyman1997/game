class_name MapBuilder
extends RefCounted
## Построение растровой карты из данных модов.
##
## Моддер описывает:
##  - map: размеры и проекцию (границы в градусах широты/долготы);
##  - landmasses: контуры суши (списки точек [широта, долгота] или pos в пикселях);
##  - provinces: «зерно» каждой провинции (lat/lon или pos);
##  - map_links: морские переправы между провинциями.
##
## Движок сам «заливает» сушу от зёрен с шумом (получаются естественные
## границы), считает соседство, центры и прибрежность. Поэтому добавить
## провинцию — это одна строка в YAML.
##
## Построение занимает несколько секунд, поэтому результат кэшируется
## (user://cache/map_<хеш>.bin); готовый кэш для базовой игры лежит в res://cache/.

const CACHE_VERSION := 1


## Ключ кэша: хеш всех данных, влияющих на карту.
static func cache_key(content: ContentStore) -> String:
	var parts := [CACHE_VERSION, content.singleton("map")]
	for lm in content.all("landmasses"):
		parts.append(lm)
	for p in content.all("provinces"):
		parts.append([p.id, p.get("lat"), p.get("lon"), p.get("pos"), p.get("impassable", false)])
	for l in content.all("map_links"):
		parts.append([l.get("a"), l.get("b")])
	return JSON.stringify(parts).md5_text()


## Карта из кэша или построенная заново (с записью в кэш).
static func load_or_build(content: ContentStore) -> MapData:
	if content.all("provinces").is_empty():
		return MapData.new()
	var key := cache_key(content)
	for path in ["user://cache/map_%s.bin" % key, "res://cache/map_%s.bin" % key]:
		if FileAccess.file_exists(path):
			var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
			if f != null:
				var d: Variant = f.get_var()
				if d is Dictionary and d.has("pixels"):
					return MapData.from_dict(d)
	var m := build(content)
	DirAccess.make_dir_recursive_absolute("user://cache")
	var f = FileAccess.open_compressed("user://cache/map_%s.bin" % key, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f != null:
		f.store_var(m.to_dict())
	return m


static func _fractalize(points: Array, roughness: float, min_len: float, rng: Rng) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := points.size()
	for i in n:
		_fract_rec(points[i], points[(i + 1) % n], 0, roughness, min_len, rng, out)
	return out


static func _fract_rec(a: Vector2, b: Vector2, depth: int, roughness: float, min_len: float, rng: Rng, out: PackedVector2Array) -> void:
	var d := b - a
	var len := d.length()
	if len < min_len or depth > 12:
		out.append(b)
		return
	var off := (rng.next() - 0.5) * len * roughness
	var mid = Vector2((a.x + b.x) / 2.0 - (d.y / len) * off, (a.y + b.y) / 2.0 + (d.x / len) * off)
	_fract_rec(a, mid, depth + 1, roughness, min_len, rng, out)
	_fract_rec(mid, b, depth + 1, roughness, min_len, rng, out)


## Заливка многоугольника по правилу чёт-нечёт в маску (FORMAT_LA8).
static func _rasterize(mask: Image, w: int, h: int, poly: PackedVector2Array) -> void:
	var n := poly.size()
	var rows := {}
	for i in n:
		var p1 = poly[i]
		var p2 = poly[(i + 1) % n]
		if p1.y == p2.y:
			continue
		var y0 = maxi(0, ceili(minf(p1.y, p2.y) - 0.5))
		var y1 = mini(h - 1, floori(maxf(p1.y, p2.y) - 0.5))
		for y in range(y0, y1 + 1):
			var cy := y + 0.5
			if (p1.y <= cy and p2.y > cy) or (p2.y <= cy and p1.y > cy):
				var x = p1.x + (cy - p1.y) / (p2.y - p1.y) * (p2.x - p1.x)
				if rows.has(y):
					rows[y].append(x)
				else:
					rows[y] = PackedFloat32Array([x])
	var white := Color(1, 1, 1, 1)
	for y in rows:
		var xs: PackedFloat32Array = rows[y]
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			var from = maxi(0, ceili(xs[k] - 0.5))
			var to = mini(w - 1, floori(xs[k + 1] - 0.5))
			if to >= from:
				mask.fill_rect(Rect2i(from, y, to - from + 1, 1), white)
			k += 2


static func build(content: ContentStore) -> MapData:
	var t0 := Time.get_ticks_msec()
	var s := content.singleton("map")
	var m := MapData.new()
	var width := int(Data.num(s.get("width"), 1000))
	var bounds: Dictionary = s.get("bounds", {}) if s.get("bounds") is Dictionary else {}
	var lon: Array = bounds.get("lon", [-10, 10])
	var lat: Array = bounds.get("lat", [40, 60])
	var ref_lat = Data.num(s.get("ref_lat"), (Data.num(lat[0]) + Data.num(lat[1])) / 2.0)
	m.k = cos(deg_to_rad(ref_lat))
	m.scale = width / ((Data.num(lon[1]) - Data.num(lon[0])) * m.k)
	m.lon0 = Data.num(lon[0])
	m.lat1 = Data.num(lat[1])
	var height = roundi((Data.num(lat[1]) - Data.num(lat[0])) * m.scale)
	m.width = width
	m.height = height
	var seed := int(Data.num(s.get("seed"), 1))
	var N = width * height

	# 1. Суша
	var land_img := Image.create(width, height, false, Image.FORMAT_LA8)
	var on := Image.create(width, height, false, Image.FORMAT_LA8)
	on.fill(Color(1, 1, 1, 1))
	var off := Image.create(width, height, false, Image.FORMAT_LA8)
	off.fill(Color(0, 0, 0, 0))
	var full := Rect2i(0, 0, width, height)
	for lm in content.all("landmasses"):
		var pts := []
		for p in Data.as_array(lm.get("points")):
			if lm.get("pixel", false):
				pts.append(Vector2(Data.num(p[0]), Data.num(p[1])))
			else:
				pts.append(m.project(Data.num(p[0]), Data.num(p[1])))
		if pts.size() < 3:
			continue
		var rough := Data.num(lm.get("roughness"), Data.num(s.get("coast_roughness"), 0.3))
		var poly: PackedVector2Array
		if rough > 0.0:
			poly = _fractalize(pts, rough, 1.5, Rng.new({"s": (Rng.hash_string(str(lm.id)) ^ seed) & 0xFFFFFFFF}))
		else:
			poly = PackedVector2Array(pts)
		var mask := Image.create(width, height, false, Image.FORMAT_LA8)
		_rasterize(mask, width, height, poly)
		land_img.blit_rect_mask(off if lm.get("water", false) else on, mask, full, Vector2i.ZERO)
	# LA8: байты [яркость, альфа] на пиксель
	var la := land_img.get_data()
	var land := PackedByteArray()
	land.resize(N)
	for i in N:
		land[i] = 1 if la[i * 2 + 1] > 127 else 0
	la = PackedByteArray()

	# 2. Провинции и зёрна
	var defs := content.all("provinces")
	var P := defs.size()
	m.impassable.resize(P)
	var seeds := PackedInt32Array()
	seeds.resize(P)
	for i in P:
		var d: Dictionary = defs[i]
		m.provinces.append(d.id)
		m.index[d.id] = i
		m.impassable[i] = 1 if d.get("impassable", false) else 0
		var pos: Vector2
		if d.get("pos") is Array:
			pos = Vector2(Data.num(d.pos[0]), Data.num(d.pos[1]))
		else:
			pos = m.project(Data.num(d.get("lat")), Data.num(d.get("lon")))
		var x = clampi(roundi(pos.x), 0, width - 1)
		var y = clampi(roundi(pos.y), 0, height - 1)
		var found = y * width + x
		if land[found] == 0:
			# ищем ближайшую сушу по спирали
			found = -1
			for r in range(1, 40):
				for dy in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if maxi(absi(dx), absi(dy)) != r:
							continue
						var nx = x + dx
						var ny = y + dy
						if nx < 0 or ny < 0 or nx >= width or ny >= height:
							continue
						if land[ny * width + nx] == 1:
							found = ny * width + nx
							break
					if found >= 0:
						break
				if found >= 0:
					break
		seeds[i] = found

	# 3. Заливка от зёрен с шумовой стоимостью (алгоритм Дейкстры с корзинами)
	var noise_amp := Data.num(s.get("border_noise"), 0.8)
	var fbm := FastNoiseLite.new()
	fbm.seed = seed
	fbm.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	fbm.frequency = 1.0 / 18.0
	fbm.fractal_type = FastNoiseLite.FRACTAL_FBM
	fbm.fractal_octaves = 3
	var fbm_data := fbm.get_image(width, height, false, false, true).get_data()
	var white := FastNoiseLite.new()
	white.seed = seed + 7
	white.noise_type = FastNoiseLite.TYPE_VALUE
	white.frequency = 0.9
	white.fractal_type = FastNoiseLite.FRACTAL_NONE
	var white_data := white.get_image(width, height, false, false, true).get_data()
	var cost := PackedByteArray()
	cost.resize(N)
	for i in N:
		if land[i] == 0:
			continue
		var nv = fbm_data[i] / 255.0
		cost[i] = 1 + mini(4, floori(nv * nv * 6.0 * noise_amp + white_data[i] / 255.0 * 0.8))
	fbm_data = PackedByteArray()
	white_data = PackedByteArray()

	var pixels := PackedInt32Array()
	pixels.resize(N)
	pixels.fill(-1)
	var dist := PackedInt32Array()
	dist.resize(N)
	dist.fill(0x7fffffff)
	const C := 8
	var buckets: Array[PackedInt32Array] = []
	for b in C:
		buckets.append(PackedInt32Array())
	var pending := 0
	for i in P:
		var p = seeds[i]
		if p < 0:
			continue
		dist[p] = 0
		pixels[p] = i
		buckets[0].append(p)
		pending += 1
	var d := 0
	while pending > 0:
		var bi := d % C
		var b: PackedInt32Array = buckets[bi]
		buckets[bi] = PackedInt32Array()
		pending -= b.size()
		var j := 0
		while j < b.size():
			var p = b[j]
			j += 1
			if dist[p] != d:
				continue
			var x = p % width
			var owner = pixels[p]
			var q := 0
			var nd := 0
			# 4 соседа (развёрнуто ради скорости)
			if x > 0:
				q = p - 1
				if land[q] == 1:
					nd = d + cost[q]
					if nd < dist[q]:
						dist[q] = nd
						pixels[q] = owner
						if nd % C == bi:
							b.append(q)
						else:
							buckets[nd % C].append(q)
							pending += 1
			if x < width - 1:
				q = p + 1
				if land[q] == 1:
					nd = d + cost[q]
					if nd < dist[q]:
						dist[q] = nd
						pixels[q] = owner
						if nd % C == bi:
							b.append(q)
						else:
							buckets[nd % C].append(q)
							pending += 1
			if p >= width:
				q = p - width
				if land[q] == 1:
					nd = d + cost[q]
					if nd < dist[q]:
						dist[q] = nd
						pixels[q] = owner
						if nd % C == bi:
							b.append(q)
						else:
							buckets[nd % C].append(q)
							pending += 1
			if p < N - width:
				q = p + width
				if land[q] == 1:
					nd = d + cost[q]
					if nd < dist[q]:
						dist[q] = nd
						pixels[q] = owner
						if nd % C == bi:
							b.append(q)
						else:
							buckets[nd % C].append(q)
							pending += 1
		d += 1
	dist = PackedInt32Array()

	# 4. Острова без зёрен — к ближайшей провинции (через воду)
	var unassigned := 0
	for i in N:
		if land[i] == 1 and pixels[i] < 0:
			unassigned += 1
	if unassigned > 0:
		var owner_px := pixels.duplicate()
		var seen := PackedByteArray()
		seen.resize(N)
		var frontier := PackedInt32Array()
		for i in N:
			if pixels[i] >= 0:
				frontier.append(i)
				seen[i] = 1
		while not frontier.is_empty() and unassigned > 0:
			var next := PackedInt32Array()
			for p in frontier:
				var x := p % width
				for q in [p - 1 if x > 0 else -1, p + 1 if x < width - 1 else -1, p - width, p + width]:
					if q < 0 or q >= N or seen[q] == 1:
						continue
					seen[q] = 1
					owner_px[q] = owner_px[p]
					if land[q] == 1 and pixels[q] < 0:
						pixels[q] = owner_px[p]
						unassigned -= 1
					next.append(q)
			frontier = next

	# 5. Площади, прибрежность, соседство
	var areas := PackedInt32Array()
	areas.resize(P)
	var coastal := PackedByteArray()
	coastal.resize(P)
	var pair_count := {}
	for y in height:
		var row = y * width
		for x in width:
			var i = row + x
			var a = pixels[i]
			if a < 0:
				continue
			areas[a] += 1
			if x < width - 1:
				var bb = pixels[i + 1]
				if bb < 0:
					coastal[a] = 1
				elif bb != a:
					var key = a * P + bb if a < bb else bb * P + a
					pair_count[key] = pair_count.get(key, 0) + 1
			if y < height - 1:
				var bb = pixels[i + width]
				if bb < 0:
					coastal[a] = 1
				elif bb != a:
					var key = a * P + bb if a < bb else bb * P + a
					pair_count[key] = pair_count.get(key, 0) + 1
			if x > 0 and pixels[i - 1] < 0:
				coastal[a] = 1
			if y > 0 and pixels[i - width] < 0:
				coastal[a] = 1
	for id in m.provinces:
		m.land_neighbors[id] = []
	for key in pair_count:
		if pair_count[key] < 2:
			continue
		var a: int = key / P
		var bb: int = key % P
		m.land_neighbors[m.provinces[a]].append(m.provinces[bb])
		m.land_neighbors[m.provinces[bb]].append(m.provinces[a])

	# 6. Центры: точка, максимально удалённая от границы провинции
	# (считается на уменьшенной сетке — для подписей и расстояний этого достаточно).
	m.centers = _centers(pixels, width, height, P, seeds)

	# 7. Переправы и итоговое соседство (без непроходимых провинций)
	for l in content.all("map_links"):
		if m.index.has(l.get("a")) and m.index.has(l.get("b")):
			m.links.append([l.a, l.b])
	for id in m.provinces:
		var i: int = m.index[id]
		if m.impassable[i] == 1:
			m.neighbors[id] = []
			continue
		var set := {}
		for q in m.land_neighbors[id]:
			if m.impassable[m.index[q]] == 0:
				set[q] = true
		for lk in m.links:
			if lk[0] == id and m.impassable[m.index[lk[1]]] == 0:
				set[lk[1]] = true
			if lk[1] == id and m.impassable[m.index[lk[0]]] == 0:
				set[lk[0]] = true
		m.neighbors[id] = set.keys()
	m.pixels = pixels
	m.areas = areas
	m.coastal = coastal
	print("Карта построена: %dx%d, %d провинций, %d мс" % [width, height, P, Time.get_ticks_msec() - t0])
	return m


static func _centers(pixels: PackedInt32Array, width: int, height: int, P: int, seeds: PackedInt32Array) -> PackedFloat32Array:
	const S := 3
	var gw := ceili(width / float(S))
	var gh := ceili(height / float(S))
	var G := gw * gh
	var grid := PackedInt32Array()
	grid.resize(G)
	for gy in gh:
		for gx in gw:
			var x := mini(width - 1, gx * S + 1)
			var y := mini(height - 1, gy * S + 1)
			grid[gy * gw + gx] = pixels[y * width + x]
	var dd := PackedInt32Array()
	dd.resize(G)
	dd.fill(-1)
	var frontier := PackedInt32Array()
	for i in G:
		var a = grid[i]
		if a < 0:
			continue
		var x := i % gw
		var edge := x == 0 or x == gw - 1 or i < gw or i >= G - gw \
			or grid[i - 1] != a or grid[i + 1] != a or grid[i - gw] != a or grid[i + gw] != a
		if edge:
			dd[i] = 0
			frontier.append(i)
	var d := 0
	while not frontier.is_empty():
		d += 1
		var next := PackedInt32Array()
		for p in frontier:
			var x := p % gw
			for q in [p - 1 if x > 0 else -1, p + 1 if x < gw - 1 else -1, p - gw, p + gw]:
				if q < 0 or q >= G or dd[q] >= 0 or grid[q] != grid[p]:
					continue
				dd[q] = d
				next.append(q)
		frontier = next
	var best := PackedInt32Array()
	best.resize(P)
	best.fill(-1)
	var best_idx := PackedInt32Array()
	best_idx.resize(P)
	best_idx.fill(-1)
	for i in G:
		var a = grid[i]
		if a >= 0 and dd[i] > best[a]:
			best[a] = dd[i]
			best_idx[a] = i
	var centers := PackedFloat32Array()
	centers.resize(P * 2)
	for a in P:
		if best_idx[a] >= 0:
			var i = best_idx[a]
			centers[a * 2] = (i % gw) * S + 1.5
			centers[a * 2 + 1] = floori(i / float(gw)) * S + 1.5
		elif seeds[a] >= 0:
			centers[a * 2] = (seeds[a] % width) + 0.5
			centers[a * 2 + 1] = floori(seeds[a] / float(width)) + 0.5
	return centers

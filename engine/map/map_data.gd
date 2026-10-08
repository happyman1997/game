class_name MapData
extends RefCounted
## Растровая карта: индекс провинции для каждого пикселя, соседство,
## центры, прибрежность. Строится MapBuilder из данных модов.

var width := 1
var height := 1
## Индекс провинции для каждого пикселя, -1 — вода.
var pixels := PackedInt32Array([-1])
var provinces: Array = []
var index := {}
var impassable := PackedByteArray()
var centers := PackedFloat32Array()
var areas := PackedInt32Array()
var coastal := PackedByteArray()
## id → Array[id] — соседство с учётом морских переправ (без непроходимых).
var neighbors := {}
## Только сухопутное соседство (для отрисовки).
var land_neighbors := {}
var links: Array = []
## Проекция: x = (lon - lon0) * k * scale, y = (lat1 - lat) * scale.
var lon0 := 0.0
var lat1 := 0.0
var k := 1.0
var scale := 1.0


func project(lat: float, lon: float) -> Vector2:
	return Vector2((lon - lon0) * k * scale, (lat1 - lat) * scale)


func center_of(id: String) -> Vector2:
	var i: int = index.get(id, -1)
	if i < 0:
		return Vector2.ZERO
	return Vector2(centers[i * 2], centers[i * 2 + 1])


func province_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return pixels[y * width + x]


func to_dict() -> Dictionary:
	return {
		"width": width, "height": height, "pixels": pixels, "provinces": provinces, "impassable": impassable,
		"centers": centers, "areas": areas, "coastal": coastal, "neighbors": neighbors, "land_neighbors": land_neighbors,
		"links": links, "lon0": lon0, "lat1": lat1, "k": k, "scale": scale,
	}


static func from_dict(d: Dictionary) -> MapData:
	var m := MapData.new()
	m.width = d.width
	m.height = d.height
	m.pixels = d.pixels
	m.provinces = d.provinces
	for i in m.provinces.size():
		m.index[m.provinces[i]] = i
	m.impassable = d.impassable
	m.centers = d.centers
	m.areas = d.areas
	m.coastal = d.coastal
	m.neighbors = d.neighbors
	m.land_neighbors = d.land_neighbors
	m.links = d.links
	m.lon0 = d.lon0
	m.lat1 = d.lat1
	m.k = d.k
	m.scale = d.scale
	return m

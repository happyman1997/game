extends TestCase
## Поселения на карте (TownLayout): постройки стоят на земле своего графства,
## лодки — на воде, поля целиком внутри графства, у каждой постройки есть
## рисунок, великие стройки отмечены, стены появляются со стенами, стройка —
## лесами, раскладка не меняется от раза к разу.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = "harold"
	return g


func _grow(g: Game) -> void:
	var pid := "c_winchester"
	var p: Dictionary = g.state.provinces[pid]
	for d in [["temple_quarter", 3], ["market", 3], ["citadel", 2], ["fields", 2], ["harbor", 2]]:
		Districts.set_level(g, pid, d[0], d[1])
	for b in ["cathedral", "sun_cathedral", "fairground", "great_market", "walls", "farms", "orchards", "sheepfold", "vineyard", "docks", "lighthouse"]:
		if not p.buildings.has(b):
			p.buildings.append(b)
	g.state.build_ver = int(g.state.get("build_ver", 0)) + 1


func test_every_building_has_art() -> void:
	var g := _game()
	for b in g.content.all("buildings"):
		var s: Variant = b.get("map_sprite")
		check(s == null or s == "none" or MapArt.has(str(s)), "рисунок постройки %s: %s" % [b.id, s])
		check(MapArt.has(MapArt.for_building(b)) or MapArt.for_building(b) == "none", "у %s есть рисунок" % b.id)


func test_town_stays_in_county() -> void:
	var g := _game()
	_grow(g)
	var m: MapData = g.engine.map
	var data := MapOverlay.settlements_of(g)
	var bad := []
	for pid in data:
		var i: int = m.index[pid]
		var lay := TownLayout.build(g, m, i, data[pid], null)
		for it in lay.items:
			if it.kind != "sprite":
				continue
			var at := m.province_at(floori(it.pos.x), floori(it.pos.y))
			var ok := at == -1 if it.has("bob") else at == i
			if not ok:
				bad.append("%s:%s" % [pid, it.sprite])
		var gm: Dictionary = lay.ground
		for j in range(0, gm.pts.size(), 1):
			var q: Vector2 = gm.pts[j]
			var at2 := m.province_at(floori(q.x), floori(q.y))
			if at2 != i and at2 != -1:
				bad.append("%s:поле" % pid)
				break
	check(bad.is_empty(), "всё стоит в своём графстве: %s" % [bad.slice(0, 8)])


func test_great_town() -> void:
	var g := _game()
	_grow(g)
	var m: MapData = g.engine.map
	var pid := "c_winchester"
	var s: Dictionary = MapOverlay.settlements_of(g)[pid]
	var lay := TownLayout.build(g, m, m.index[pid], s, null)
	var sprites := {}
	var great := []
	var walls := 0
	var boats := 0
	for it in lay.items:
		if it.kind == "wall":
			walls += 1
			continue
		sprites[it.sprite] = true
		if it.get("great", false):
			great.append(it.b)
		if it.sprite == "boat":
			boats += 1
	check(sprites.has("castle"), "детинец II — замок с башнями")
	check(sprites.has("town_hall") and sprites.has("church"), "ратуша и храм")
	check(great.has("sun_cathedral") and great.has("great_market"), "великие стройки отмечены: %s" % [great])
	check(walls >= 6 and sprites.has("gatehouse"), "стены (%d отрезков) и ворота" % walls)
	check(sprites.has("windmill") and sprites.has("sheep"), "мельница и овцы в угодьях")
	check(boats >= 2 and sprites.has("lighthouse"), "лодки у пристани (%d) и маяк" % boats)
	check(lay.ground.idx.size() >= 6 * 6, "поля, виноградник и загон на земле")
	# стройка — леса
	var lay2 := TownLayout.build(g, m, m.index[pid], s, {"building": "guild_hall", "district": null, "level": 0, "progress": 0.5})
	check(lay2.items.any(func(x): return x.get("scaffold", false) and x.b == "guild_hall"), "стройка видна лесами")
	# та же застройка — та же раскладка
	var lay3 := TownLayout.build(g, m, m.index[pid], s, null)
	check_eq(lay3.items.size(), lay.items.size(), "раскладка повторяется")
	check(lay3.items[0].pos == lay.items[0].pos, "и стоит на тех же местах")

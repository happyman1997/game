class_name Land
extends RefCounted
## Земля по клеткам. Карта нарезана на шестиугольные клетки (ядро на Rust —
## CellMap, native/src/cells.rs и land.rs), у каждой клетки суши — своя
## местность. Провинция — смесь местностей: доли её клеток. От долей зависят
## доход и набор (modifiers местностей), рост, оборона, путь войск, полки и
## районы; господствующая местность (Game.terrain_of) — самая большая группа
## (дремучий лес — тоже лес), а в ней — самая частая местность.
##
## Начальная раскладка — из данных: terrain.<id>.start — доли местностей
## провинции с такой местностью на карте, по порядку от селения к краям
## (поля у селения, лес — по краям и языками внутрь). Раскладка не зависит от
## зерна партии: начало у всех одинаковое.
##
## Состояние живёт в ядре; в сохранение (state.land_cells: {ids, cells, data})
## оно попадает перед записью (SaveGame) и читается при загрузке. Старые
## сохранения (местность целиком у графства, state.provinces.<id>.terrain)
## раскладываются заново от той местности.

const CELL_SIZE := 7.5

var game: Game
var core: Object
## Индекс местности → id, id → индекс, индекс → группа.
var ids := PackedStringArray()
var index := {}
var groups := PackedStringArray()
var _cells := {}
var _mix := {}
var _dom := {}
var _agg := {}


func _init(g: Game) -> void:
	game = g
	if not ClassDB.class_exists("CellMap"):
		push_error("Ядро не загружено (bin/): соберите его — native/build.sh")
		return
	var map: MapData = g.engine.map
	core = ClassDB.instantiate("CellMap")
	var passable := PackedByteArray()
	passable.resize(map.provinces.size())
	for i in map.provinces.size():
		passable[i] = 0 if map.impassable[i] == 1 else 1
	core.build(map.width, map.height, map.pixels, passable, map.centers, g.def_num("land.cell_size", CELL_SIZE))
	var defs: Array = g.content.all("terrain").duplicate()
	defs.sort_custom(func(a, b): return str(a.id) < str(b.id))
	var moves := PackedFloat32Array()
	for d in defs:
		index[str(d.id)] = ids.size()
		ids.append(str(d.id))
		groups.append(str(d.get("group", d.id)))
		moves.append(Data.num(d.get("movement"), 1.0))
	core.set_moves(moves)
	if not _load(g.state.get("land_cells")):
		_seed()
	g.state.erase("land_cells")


func ready() -> bool:
	return core != null


# ------------------------------------------------------------ начало и сохранение

## Раскладка всех провинций от их местности (из данных карты или старого
## сохранения).
func _seed() -> void:
	var map: MapData = game.engine.map
	var seed := Rng.hash_string(str(game.engine.content.singleton("map").get("seed", 1066)))
	for i in map.provinces.size():
		var pid: String = map.provinces[i]
		var base := ""
		var st: Variant = game.state.provinces.get(pid)
		if st != null and st.get("terrain") != null:
			base = str(st.terrain)
			st.erase("terrain")
		else:
			var pd: Variant = game.content.get_def("provinces", pid)
			base = str(pd.get("terrain", "")) if pd != null else ""
		if not index.has(base):
			base = "plains" if index.has("plains") else (ids[0] if not ids.is_empty() else "")
		if base == "":
			continue
		var td: Variant = game.content.get_def("terrain", base)
		var start: Variant = td.get("start") if td != null else null
		var ts := PackedInt32Array()
		var sh := PackedFloat32Array()
		if start is Dictionary and not start.is_empty():
			for t in start:
				if index.has(str(t)):
					ts.append(index[str(t)])
					sh.append(Data.num(start[t]))
		if ts.is_empty():
			ts.append(index[base])
			sh.append(1.0)
		core.seed_province(i, ts, sh, seed + i * 7919)


func _load(saved: Variant) -> bool:
	if not (saved is Dictionary) or int(Data.num(saved.get("cells"))) != core.cell_count():
		return false
	var raw := Marshalls.base64_to_raw(str(saved.get("data", "")))
	var bytes := raw.decompress(core.cell_count(), FileAccess.COMPRESSION_DEFLATE)
	if bytes.size() != core.cell_count():
		return false
	# индексы местностей в сохранении → нынешние (моды могли добавить местности)
	var old_ids: Array = Data.as_array(saved.get("ids"))
	var remap := PackedByteArray()
	remap.resize(256)
	remap.fill(255)
	for k in old_ids.size():
		var t := str(old_ids[k])
		remap[k] = index[t] if index.has(t) else (index.get("plains", 0))
	for i in bytes.size():
		bytes[i] = remap[bytes[i]]
	return core.load_terrain(bytes)


## Записать землю в состояние (перед сохранением).
func save_into(state: Dictionary) -> void:
	if core == null:
		return
	var bytes: PackedByteArray = core.terrain_bytes()
	state["land_cells"] = {"ids": Array(ids), "cells": core.cell_count(),
		"data": Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_DEFLATE))}


# ------------------------------------------------------------ состав провинции

func _pi(pid: Variant) -> int:
	return game.engine.map.index.get(pid, -1)


## Клетки провинции.
func cells(pid: Variant) -> PackedInt32Array:
	var c: Variant = _cells.get(pid)
	if c == null:
		var i := _pi(pid)
		c = core.province_cells(i) if core != null and i >= 0 else PackedInt32Array()
		_cells[pid] = c
	return c


func count(pid: Variant) -> int:
	return cells(pid).size()


## Доли местностей провинции: {местность: доля}, по убыванию доли.
func mix(pid: Variant) -> Dictionary:
	var m: Variant = _mix.get(pid)
	if m != null:
		return m
	var out := {}
	var i := _pi(pid)
	var n := count(pid)
	if core != null and i >= 0 and n > 0:
		var counts: PackedInt32Array = core.province_counts(i, ids.size())
		var pairs := []
		for k in counts.size():
			if counts[k] > 0:
				pairs.append([ids[k], float(counts[k]) / n])
		pairs.sort_custom(func(a, b): return a[1] > b[1] or (a[1] == b[1] and a[0] < b[0]))
		for p in pairs:
			out[p[0]] = p[1]
	_mix[pid] = out
	return out


## Господствующая местность: самая большая группа, в ней — самая частая.
func dominant(pid: Variant) -> String:
	var d: Variant = _dom.get(pid)
	if d != null:
		return d
	var m := mix(pid)
	var by_group := {}
	for t in m:
		var g := group_of(t)
		by_group[g] = float(by_group.get(g, 0.0)) + float(m[t])
	var best_g := ""
	var best := -1.0
	for g in by_group:
		if by_group[g] > best + 1e-6:
			best = by_group[g]
			best_g = g
	var out := ""
	for t in m:
		if group_of(t) == best_g:
			out = t
			break
	_dom[pid] = out
	return out


func group_of(t: String) -> String:
	var k: int = index.get(t, -1)
	return groups[k] if k >= 0 else t


## Подходит ли местность t под what (id, группа или их список).
func matches(t: String, what: Variant) -> bool:
	var g := group_of(t)
	for x in Data.as_array(what):
		if str(x) == t or str(x) == g:
			return true
	return false


## Доля клеток провинции, подходящих под what (id, группа или список).
func share(pid: Variant, what: Variant) -> float:
	var s := 0.0
	var m := mix(pid)
	for t in m:
		if matches(t, what):
			s += float(m[t])
	return s


## Взвешенное по долям числовое свойство местностей (movement, defense,
## development_growth, attrition…).
func num(pid: Variant, key: String, fallback: float = 0.0) -> float:
	var a := _aggregate(pid)
	return float(a.nums.get(key, fallback)) if a.nums.has(key) else fallback


## Взвешенные по долям модификаторы местностей: field — modifiers или
## capital_modifiers. Для modifiers сюда же — рост (development_growth).
func mods(pid: Variant, field: String = "modifiers") -> Dictionary:
	return _aggregate(pid).get(field, {})


func _aggregate(pid: Variant) -> Dictionary:
	var a: Variant = _agg.get(pid)
	if a != null:
		return a
	var nums := {}
	var out := {"nums": nums, "modifiers": {}, "capital_modifiers": {}}
	var m := mix(pid)
	for key in ["movement", "defense", "attrition", "height"]:
		var any := false
		var v := 0.0
		for t in m:
			var td: Variant = game.content.get_def("terrain", t)
			var x: Variant = td.get(key) if td != null else null
			if x != null:
				any = true
			v += float(m[t]) * Data.num(x, 1.0 if key == "movement" else 0.0)
		if any:
			nums[key] = v
	for t in m:
		var td: Variant = game.content.get_def("terrain", t)
		if td == null:
			continue
		var w := float(m[t])
		if Data.num(td.get("development_growth")) != 0.0:
			out.modifiers["development_growth"] = float(out.modifiers.get("development_growth", 0.0)) + w * Data.num(td.development_growth)
		for field in ["modifiers", "capital_modifiers"]:
			var md: Variant = td.get(field)
			if md is Dictionary:
				for k in md:
					if md[k] is int or md[k] is float:
						out[field][k] = float(out[field].get(k, 0.0)) + w * float(md[k])
	_agg[pid] = out
	return out


## Значение из словаря { местность: значение } по долям: у каждой местности
## — её значение (точное или группы, иначе fallback). null — ни одна
## местность провинции в словаре не названа.
func pick(d: Variant, pid: Variant, fallback: Variant = null) -> Variant:
	if not (d is Dictionary) or d.is_empty():
		return null
	var m := mix(pid)
	var any := false
	var v := 0.0
	for t in m:
		var x: Variant = d.get(t)
		if x == null:
			x = d.get(group_of(t))
		if x != null:
			any = true
		else:
			x = fallback
		v += float(m[t]) * Data.num(x)
	return v if any else null


# ------------------------------------------------------------ клетки

func terrain_at(cell: int) -> String:
	var k: int = core.terrain_at(cell) if core != null else -1
	return ids[k] if k >= 0 and k < ids.size() else ""


## Провинция клетки (id) или "".
func province_at_cell(cell: int) -> String:
	var i: int = core.province_of(cell) if core != null else -1
	return game.engine.map.provinces[i] if i >= 0 else ""


## Битовая маска местностей: по id или группам из списка.
func mask(what: Variant, with_groups: bool = true) -> int:
	var m := 0
	var list := Data.as_array(what)
	for k in ids.size():
		for x in list:
			if str(x) == ids[k] or (with_groups and str(x) == groups[k]):
				m |= 1 << k
				break
	return m


## Участок: до n клеток провинции с местностью из from (точные id), растёт
## от клеток toward (id или группы). Только выбирает.
func patch(pid: Variant, from: Variant, toward: Variant, n: int, seed: int) -> PackedInt32Array:
	var i := _pi(pid)
	if core == null or i < 0 or n <= 0:
		return PackedInt32Array()
	return core.pick_patch(i, mask(from, false), mask(toward), n, seed)


## Природа: клетки местности t провинции, которые перейдут за год (шанс
## chance; near — от каких местностей идёт: у таких соседей шанс выше).
func drift_pick(pid: Variant, t: String, chance: float, near: Variant, seed: int) -> PackedInt32Array:
	var i := _pi(pid)
	if core == null or i < 0 or not index.has(t):
		return PackedInt32Array()
	var nm := mask(near) if near != null else 0
	return core.drift_pick(i, index[t], chance, nm, 0.4 if nm != 0 else 1.0, 0.3 if nm != 0 else 0.0, seed)


## Сменить местность клеток провинции. {n — сколько изменилось, from —
## какая местность была у большинства из них}.
func change(pid: Variant, list: PackedInt32Array, to: String) -> Dictionary:
	if core == null or not index.has(to) or list.is_empty():
		return {"n": 0, "from": ""}
	var was := {}
	for c in list:
		var t := terrain_at(c)
		if t != "" and t != to:
			was[t] = int(was.get(t, 0)) + 1
	var from := ""
	for t in was:
		if from == "" or was[t] > was[from]:
			from = t
	var n: int = core.set_cells(list, index[to])
	if n > 0:
		forget(pid)
	return {"n": n, "from": from}


## Сбросить кэш долей провинции (после смены клеток).
func forget(pid: Variant) -> void:
	_mix.erase(pid)
	_dom.erase(pid)
	_agg.erase(pid)

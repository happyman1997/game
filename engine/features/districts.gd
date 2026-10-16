class_name Districts
extends EngineFeature
## Районы: поселение графства растёт кварталами — детинец, торговый посад,
## соборная сторона, угодья, ремесленная слобода, пристань. Район — это
## участок с уровнем (I–III); у него есть сила, и сила масштабирует всё, что
## в нём стоит: постройки района дают свои бонусы, умноженные на силу.
##
## Данные (districts):
##   free_with: castle       — даётся с владением (уровень I, участок не занимает)
##   trigger: {...}          — где можно заложить (графство; scope:builder)
##   cost: [100, 260, 640]   — цена уровней I, II, III (золото; build_cost_mult)
##   days: [300, 540, 900]   — сроки (build_time_mult)
##   development: [0, 10, 18] — нужное развитие графства для уровня
##   upkeep: [0, 0.2, 0.5]   — содержание в месяц (строка «Содержание районов»)
##   modifiers / owner_modifiers — графству / владельцу, × сила района
##   power: [ множители силы ]:
##     { kind: terrain, mult: { farmlands: 1.5 } }   — по местности
##     { kind: coastal, mult: 1.2 }                   — прибрежное графство
##     { kind: border, mult: 1.4 }                    — граница с чужой державой
##     { kind: neighbors, district: market, per: 0.12, max: 0.6 }
##         — +per за соседнее графство с таким районом (если их владельцы не воюют)
##     { kind: domain, district: harbor, per: 0.15, max: 0.6 }
##         — +per за другое графство домена с таким районом
##     { kind: trigger, limit: {...}, mult: 1.25, desc: ключ } — условие
##         (графство; scope:owner — владелец)
##   yearly: эффект раз в год (root — владелец, scope:province, scope:power)
##   ai_will_do: значение (root — строитель, scope:province)
## Сила = defines.districts.level_power[уровень] × множители (не выше max_power).
## Постройки (buildings) с полем district стоят в районе: нужно, чтобы район
## был заложен (level: N — не ниже уровня N), и мест в районе —
## defines.districts.slots_by_level[уровень]. Их modifiers и owner_modifiers
## умножаются на силу района; yearly — эффект раз в год со scope:power.
## Великие стройки: unique: world (одна в мире) или realm (одна на державу
## верховного сюзерена); scale: no — бонусы постройки не зависят от силы.
## Участков под районы сверх данных владениями: plots_base +
## развитие × plots_per_development (не больше max_plots).
## Состояние: province.districts = { район: уровень }; стройка района —
## province.construction = { district, level, done, days, by }.

const OWNER := "core/districts"
const ROMAN := ["", "I", "II", "III", "IV", "V"]


func _init() -> void:
	id = "districts"
	doc = "Районы графства: кварталы с уровнями, сила района масштабирует постройки"


static func on(game: Game) -> bool:
	return game.engine.has_feature("districts")


# ------------------------------------------------------------ состояние

static func of(p: Dictionary) -> Dictionary:
	if not (p.get("districts") is Dictionary):
		p["districts"] = {}
	return p.districts


static func level(game: Game, prov_id: String, did: String) -> int:
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null or not (p.get("districts") is Dictionary):
		return 0
	return int(p.districts.get(did, 0))


static func def_of(game: Game, did: String) -> Variant:
	return game.content.get_def("districts", did)


## Все районы по порядку (кэш на движке).
static func all_defs(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("districts:defs")
	if hit == null:
		hit = game.content.all("districts").duplicate()
		Data.sort_by(hit, func(d): return Data.num(d.get("order"), 100))
		game.engine.cache["districts:defs"] = hit
	return hit


static func roman(n: int) -> String:
	return ROMAN[clampi(n, 0, ROMAN.size() - 1)]


static func _arr(v: Variant, lvl: int, fallback: float = 0.0) -> float:
	var a := Data.as_array(v)
	if a.is_empty():
		return Data.num(v, fallback) if not (v is Array) else fallback
	return Data.num(a[clampi(lvl - 1, 0, a.size() - 1)], fallback)


static func max_level(game: Game) -> int:
	return int(game.def_num("districts.max_level", 3))


static func holder_of(game: Game, prov_id: String) -> Variant:
	var t: Variant = game.state.titles.get(prov_id)
	return game.ch(t.holder) if t != null and t.holder != null else null


## Отметка «застройка изменилась» — для карты (снимок поселений) и кэша силы.
static func touch(game: Game) -> void:
	mark(game)
	game.month_cache.erase("dpow")
	game.stat_cache.clear()


## Только для карты: началась стройка (бонусы ещё не изменились).
static func mark(game: Game) -> void:
	game.state["build_ver"] = int(game.state.get("build_ver", 0)) + 1


# ------------------------------------------------------------ участки и места

## Районы, данные владениями графства (уровень I бесплатно, участок не занимают).
static func holding_districts(game: Game, prov_id: String) -> Array:
	var pdef: Variant = game.content.get_def("provinces", prov_id)
	var hs := Data.as_array(pdef.get("holdings")) if pdef != null else []
	var out := []
	for d in all_defs(game):
		if d.get("free_with") != null and hs.has(str(d.free_with)):
			out.append(d.id)
	return out


## Участков под районы сверх данных владениями.
static func plots(game: Game, prov_id: String) -> int:
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null:
		return 0
	var n := game.def_num("districts.plots_base", 1) + floorf(Data.num(p.development) * game.def_num("districts.plots_per_development", 0.1))
	return clampi(int(n), 0, int(game.def_num("districts.max_plots", 4)))


static func used_plots(game: Game, prov_id: String) -> int:
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null or not (p.get("districts") is Dictionary):
		return 0
	var free := holding_districts(game, prov_id)
	var n := 0
	for did in p.districts:
		if not free.has(did):
			n += 1
	# стройка нового района тоже занимает участок
	var cons: Variant = p.get("construction")
	if cons is Dictionary and cons.get("district") != null and not p.districts.has(cons.district) and not free.has(cons.district):
		n += 1
	return n


static func free_plots(game: Game, prov_id: String) -> int:
	return plots(game, prov_id) - used_plots(game, prov_id)


## Мест под постройки в районе.
static func slots(game: Game, prov_id: String, did: String) -> int:
	var lvl := level(game, prov_id, did)
	if lvl <= 0:
		return 0
	return int(_arr(game.def_val("districts.slots_by_level", [1, 2, 3]), lvl, 1))


## Район постройки (null — без района). Таблица на движке.
static func building_district(game: Game, bid: String) -> Variant:
	var map: Variant = game.engine.cache.get("districts:bmap")
	if map == null:
		map = {}
		for bd in game.content.all("buildings"):
			if bd.get("district") != null and not bd.get("special", false) and game.content.has("districts", str(bd.district)):
				map[bd.id] = str(bd.district)
		game.engine.cache["districts:bmap"] = map
	return map.get(bid)


## Постройки, бонусы которых сила района не меняет (scale: no — великие стройки).
static func _unscaled(game: Game) -> Dictionary:
	var hit: Variant = game.engine.cache.get("districts:unscaled")
	if hit == null:
		hit = {}
		for bd in game.content.all("buildings"):
			if bd.get("scale") != null and not ScriptContext.is_yes(bd.scale):
				hit[bd.id] = true
		game.engine.cache["districts:unscaled"] = hit
	return hit


## Постройки графства в районе (и стройка в нём, если with_construction).
static func buildings_in(game: Game, prov_id: String, did: String, with_construction: bool = false) -> Array:
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null:
		return []
	var out := []
	for b in p.buildings:
		if building_district(game, b) == did:
			out.append(b)
	var cons: Variant = p.get("construction")
	if with_construction and cons is Dictionary and cons.get("building") != null and building_district(game, str(cons.building)) == did:
		out.append(str(cons.building))
	return out


# ------------------------------------------------------------ сила

## Сила района графства (0 — района нет). Кэш на месяц: соседи, войны и
## владельцы меняются не каждый день, а стройка сбрасывает его (touch).
static func power(game: Game, prov_id: String, did: String) -> float:
	var cache: Variant = game.month_cache.get("dpow")
	if cache == null:
		cache = {}
		game.month_cache["dpow"] = cache
	var key := prov_id + ":" + did
	var hit: Variant = cache.get(key)
	if hit != null:
		return hit
	var v := 0.0
	var lvl := level(game, prov_id, did)
	var d: Variant = def_of(game, did)
	if lvl > 0 and d != null:
		v = _arr(game.def_val("districts.level_power", [1.0, 1.75, 2.5]), lvl, 1.0)
		var holder: Variant = holder_of(game, prov_id)
		for f in Data.as_array(d.get("power")):
			if f is Dictionary:
				v *= _factor_value(game, prov_id, f, holder)
		v = minf(v, game.def_num("districts.max_power", 5.0))
	cache[key] = v
	return v


## Множитель силы без подписей (быстрый путь для power).
static func _factor_value(game: Game, prov_id: String, f: Dictionary, holder: Variant) -> float:
	match str(f.get("kind", "")):
		"terrain":
			var pdef: Variant = game.content.get_def("provinces", prov_id)
			var m: Variant = f.get("mult", {}).get(str(pdef.get("terrain", ""))) if pdef != null and f.get("mult") is Dictionary else null
			return Data.num(m, 1.0) if m != null else 1.0
		"coastal":
			return Data.num(f.get("mult"), 1.0) if game.engine.is_coastal(prov_id) else 1.0
		"border":
			return Data.num(f.get("mult"), 1.0) if holder != null and _is_border(game, prov_id, holder) else 1.0
		"neighbors", "domain":
			var did := str(f.get("district", ""))
			var n := _count_neighbors(game, prov_id, did, holder) if f.kind == "neighbors" else _count_domain(game, prov_id, did, holder)
			return 1.0 + minf(Data.num(f.get("max"), 1.0), Data.num(f.get("per"), 0.1) * n)
		"trigger":
			var ctx := ScriptContext.make(game, {"type": "province", "id": prov_id}, {"owner": {"type": "character", "id": holder.id}} if holder != null else {})
			return Data.num(f.get("mult"), 1.0) if Interp.eval_trigger(ctx, ctx.root, f.get("limit")) else 1.0
	return 1.0


## Из чего сложилась сила: [{label, value}] — первая строка — уровень.
## lvl — для прикидки на другом уровне (по умолчанию — нынешний).
static func power_parts(game: Game, prov_id: String, did: String, lvl: int = -1) -> Array:
	if lvl < 0:
		lvl = level(game, prov_id, did)
	var d: Variant = def_of(game, did)
	if lvl <= 0 or d == null:
		return []
	var out := [{"label": game.loc.t("district.part.level", {"n": roman(lvl)}), "value": _arr(game.def_val("districts.level_power", [1.0, 1.75, 2.5]), lvl, 1.0)}]
	var holder: Variant = holder_of(game, prov_id)
	for f in Data.as_array(d.get("power")):
		if not (f is Dictionary):
			continue
		var part: Variant = _factor(game, prov_id, f, holder)
		if part != null and not is_equal_approx(float(part.value), 1.0):
			out.append(part)
	return out


## Сила района на уровне lvl (прикидка для стройки и подсказок).
static func projected_power(game: Game, prov_id: String, did: String, lvl: int) -> float:
	var v := 1.0
	for part in power_parts(game, prov_id, did, lvl):
		v *= float(part.value)
	return minf(v, game.def_num("districts.max_power", 5.0)) if lvl > 0 else 0.0


static func _factor(game: Game, prov_id: String, f: Dictionary, holder: Variant) -> Variant:
	var label_key := str(f.get("desc", ""))
	match str(f.get("kind", "")):
		"terrain":
			var pdef: Variant = game.content.get_def("provinces", prov_id)
			var t := str(pdef.get("terrain", "")) if pdef != null else ""
			var m: Variant = f.get("mult", {}).get(t) if f.get("mult") is Dictionary else null
			if m == null:
				return null
			return {"label": game.loc.t(label_key if label_key != "" else "district.factor.terrain", {"terrain": game.name_of("terrain", t)}), "value": Data.num(m, 1.0)}
		"coastal":
			if not game.engine.is_coastal(prov_id):
				return null
			return {"label": game.loc.t(label_key if label_key != "" else "district.factor.coastal"), "value": Data.num(f.get("mult"), 1.0)}
		"border":
			if holder == null or not _is_border(game, prov_id, holder):
				return null
			return {"label": game.loc.t(label_key if label_key != "" else "district.factor.border"), "value": Data.num(f.get("mult"), 1.0)}
		"neighbors", "domain":
			var did := str(f.get("district", ""))
			var n := _count_neighbors(game, prov_id, did, holder) if f.kind == "neighbors" else _count_domain(game, prov_id, did, holder)
			if n <= 0:
				return null
			var add := minf(Data.num(f.get("max"), 1.0), Data.num(f.get("per"), 0.1) * n)
			var key := label_key if label_key != "" else "district.factor." + str(f.kind)
			return {"label": game.loc.t(key, {"n": n, "district": game.name_of("districts", did)}), "value": 1.0 + add}
		"trigger":
			var ctx := ScriptContext.make(game, {"type": "province", "id": prov_id}, {"owner": {"type": "character", "id": holder.id}} if holder != null else {})
			if not Interp.eval_trigger(ctx, ctx.root, f.get("limit")):
				return null
			return {"label": game.loc.t(label_key), "value": Data.num(f.get("mult"), 1.0)}
	return null


## Граничит ли графство с землёй чужой державы (или ничейной).
static func _is_border(game: Game, prov_id: String, holder: Dictionary) -> bool:
	var top := Titles.top_liege(game, holder)
	for nid in game.engine.map.land_neighbors.get(prov_id, []):
		var t: Variant = game.state.titles.get(nid)
		if t == null:
			continue
		var h: Variant = game.ch(t.holder) if t.holder != null else null
		if h == null or Titles.top_liege(game, h).id != top.id:
			return true
	return false


static func _count_neighbors(game: Game, prov_id: String, did: String, holder: Variant) -> int:
	var n := 0
	for nid in game.engine.neighbors(prov_id):
		if level(game, nid, did) <= 0:
			continue
		var h: Variant = holder_of(game, nid)
		if holder != null and h != null and h.id != holder.id and Wars.is_at_war_with(game, holder.id, h.id):
			continue
		n += 1
	return n


static func _count_domain(game: Game, prov_id: String, did: String, holder: Variant) -> int:
	if holder == null:
		return 0
	var n := 0
	for cid in Titles.domain_counties(game, holder):
		if cid != prov_id and level(game, cid, did) > 0:
			n += 1
	return n


## Числовые модификаторы × k (флаги — как есть).
static func scaled(mods: Variant, k: float) -> Dictionary:
	var out := {}
	if not (mods is Dictionary):
		return out
	for key in mods:
		var v: Variant = mods[key]
		out[key] = v * k if (v is float or v is int) else v
	return out


## Множитель построек: сила их района (1 — у построек без района или без механики).
static func building_scale(game: Game, prov_id: String, bid: String) -> float:
	var did: Variant = building_district(game, bid) if on(game) else null
	if did == null or _unscaled(game).has(bid):
		return 1.0
	var pw := power(game, prov_id, did)
	return pw if pw > 0.0 else 1.0


## Модификаторы постройки графства (поле modifiers или owner_modifiers) с силой района.
static func building_mods(game: Game, prov_id: String, bid: String, field: String) -> Dictionary:
	var bd: Variant = game.content.get_def("buildings", bid)
	if bd == null or not (bd.get(field) is Dictionary):
		return {}
	var k := building_scale(game, prov_id, bid)
	return bd.get(field) if is_equal_approx(k, 1.0) else scaled(bd.get(field), k)


## Модификаторы районов графства (modifiers или owner_modifiers) с их силой.
## Кэш на месяц, как и сила; словарь из кэша не менять.
static func district_mods(game: Game, prov_id: String, field: String) -> Dictionary:
	var cache: Variant = game.month_cache.get("dpow")
	if cache == null:
		cache = {}
		game.month_cache["dpow"] = cache
	var key := field + "@" + prov_id
	var hit: Variant = cache.get(key)
	if hit != null:
		return hit
	var out := {}
	var p: Variant = game.state.provinces.get(prov_id)
	if p != null and p.get("districts") is Dictionary and on(game):
		for did in p.districts:
			var d: Variant = def_of(game, did)
			if d != null and d.get(field) is Dictionary:
				Stats.add_into_scaled(out, d.get(field), power(game, prov_id, did))
	cache[key] = out
	return out


## Одна характеристика графства от районов и построек с силой (крепость,
## мнение графства). Кэш до сброса характеристик.
static func prov_bonus(game: Game, p: Dictionary, key: String) -> float:
	var ck := "pb:%s:%s" % [p.id, key]
	var hit: Variant = game.stat_cache.get(ck)
	if hit != null:
		return hit
	var v := _prov_bonus(game, p, key)
	game.stat_cache[ck] = v
	return v


static func _prov_bonus(game: Game, p: Dictionary, key: String) -> float:
	var v := 0.0
	for b in p.buildings:
		var bd: Variant = game.content.get_def("buildings", b)
		if bd != null and bd.get("modifiers") is Dictionary and bd.modifiers.has(key):
			v += Data.num(bd.modifiers[key]) * building_scale(game, p.id, b)
	if p.get("districts") is Dictionary and on(game):
		for did in p.districts:
			var d: Variant = def_of(game, did)
			if d != null and d.get("modifiers") is Dictionary and d.modifiers.has(key):
				v += Data.num(d.modifiers[key]) * power(game, p.id, did)
	return v


## Содержание районов домена в месяц (кэш до сброса характеристик).
static func upkeep(game: Game, c: Dictionary) -> float:
	var ck := "dupk:" + str(c.id)
	var hit: Variant = game.stat_cache.get(ck)
	if hit != null:
		return hit
	var s := 0.0
	for cid in Titles.domain_counties(game, c):
		var p: Variant = game.state.provinces.get(cid)
		if p == null or not (p.get("districts") is Dictionary):
			continue
		for did in p.districts:
			var d: Variant = def_of(game, did)
			if d != null and d.get("upkeep") != null:
				s += _arr(d.upkeep, int(p.districts[did]))
	game.stat_cache[ck] = s
	return s


# ------------------------------------------------------------ стройка

static func cost_of(game: Game, d: Dictionary, c: Dictionary, lvl: int) -> Dictionary:
	var mult := maxf(0.1, 1.0 + Stats.stat(game, c, "build_cost_mult"))
	return {"gold": roundf(_arr(d.get("cost"), lvl) * mult), "prestige": roundf(_arr(d.get("prestige_cost"), lvl))}


static func days_of(game: Game, d: Dictionary, c: Dictionary, lvl: int) -> int:
	return int(_arr(d.get("days"), lvl, 365) * maxf(0.3, 1.0 + Stats.stat(game, c, "build_time_mult")))


## Что можно заложить или поднять: [{def, level, cost, days, blockers}].
## Районы, которым графство не подходит (trigger), не показываются.
static func candidates(game: Game, c: Dictionary, prov_id: String) -> Array:
	var out := []
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null or not on(game):
		return out
	var t: Variant = game.state.titles.get(prov_id)
	var free := free_plots(game, prov_id)
	for d in all_defs(game):
		var cur := level(game, prov_id, d.id)
		var target := cur + 1
		if target > max_level(game):
			continue
		var ctx := ScriptContext.make(game, {"type": "province", "id": prov_id}, {"builder": {"type": "character", "id": c.id}})
		if cur == 0 and d.get("trigger") != null and not Interp.eval_trigger(ctx, ctx.root, d.trigger):
			continue
		var bl := []
		if t == null or t.holder != c.id:
			bl.append(game.loc.t("ui.not_your_domain"))
		if p.construction != null:
			bl.append(game.loc.t("ui.already_building"))
		if p.occupant != null:
			bl.append(game.loc.t("ui.occupied"))
		if cur == 0 and free <= 0:
			bl.append(game.loc.t("ui.no_plots"))
		var need := _arr(d.get("development"), target)
		if Data.num(p.development) < need:
			bl.append(game.loc.t("ui.district_needs_dev", {"n": int(need)}))
		var cost := cost_of(game, d, c, target)
		bl.append_array(Economy.cost_blockers(game, c, cost))
		out.append({"def": d, "level": target, "cost": cost, "days": days_of(game, d, c, target), "blockers": bl})
	return out


static func start(game: Game, c: Dictionary, prov_id: String, did: String) -> bool:
	var cand: Variant = null
	for x in candidates(game, c, prov_id):
		if x.def.id == did:
			cand = x
	if cand == null or not cand.blockers.is_empty():
		return false
	c.gold -= cand.cost.gold
	c.prestige -= cand.cost.prestige
	game.state.provinces[prov_id].construction = {"district": did, "level": cand.level, "done": game.date + int(cand.days), "days": int(cand.days), "by": c.id}
	mark(game)
	game.emit("district.started", {"province": prov_id, "district": did, "level": cand.level, "by": c.id})
	return true


## Стройка района завершена (из Decisions.daily_construction).
static func complete(game: Game, p: Dictionary) -> void:
	var cons: Dictionary = p.construction
	var did := str(cons.district)
	var lvl := int(cons.get("level", 1))
	var by: Variant = cons.get("by")
	of(p)[did] = maxi(lvl, int(p.districts.get(did, 0)))
	p.construction = null
	touch(game)
	var t: Variant = game.state.titles.get(p.id)
	game.message(game.loc.t("msg.district_done", {"district": game.name_of("districts", did), "level": roman(lvl), "place": game.name_of("provinces", p.id)}),
		"good", {"type": "province", "id": p.id}, [t.holder if t != null else null])
	game.emit("district.completed", {"province": p.id, "district": did, "level": lvl, "by": by})
	if by != null and game.ch(str(by)) != null:
		game.on_action("on_district_completed", {"type": "character", "id": str(by)}, {"province": {"type": "province", "id": p.id}})


## Поднять район сразу (эффект, события, перенос старых построек).
static func set_level(game: Game, prov_id: String, did: String, lvl: int) -> void:
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null or not game.content.has("districts", did):
		return
	if lvl <= 0:
		of(p).erase(did)
		# постройки снесённого района исчезают вместе с ним
		p.buildings = p.buildings.filter(func(b): return building_district(game, b) != did)
	else:
		of(p)[did] = mini(lvl, max_level(game))
	touch(game)


## Районы от владений и под постройки, что уже стоят (новая партия, старое
## сохранение). Возвращает true, если что-то добавилось.
static func ensure(game: Game, prov_id: String) -> bool:
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null:
		return false
	var changed := not (p.get("districts") is Dictionary)
	var ds := of(p)
	for did in holding_districts(game, prov_id):
		if not ds.has(did):
			ds[did] = 1
			changed = true
	for b in p.buildings:
		var did: Variant = building_district(game, b)
		if did == null:
			continue
		var bd: Dictionary = game.content.get_def("buildings", b)
		var need := maxi(1, int(Data.num(bd.get("level"), 1)))
		if int(ds.get(did, 0)) < need:
			ds[did] = need
			changed = true
	var cons: Variant = p.get("construction")
	if cons is Dictionary and cons.get("building") != null:
		var cdid: Variant = building_district(game, str(cons.building))
		if cdid != null and not ds.has(cdid):
			ds[cdid] = 1
			changed = true
	return changed


static func ensure_all(game: Game) -> void:
	if not on(game):
		return
	var changed := false
	for pid in game.state.provinces:
		changed = ensure(game, pid) or changed
	if changed:
		touch(game)


# ------------------------------------------------------------ год

## Ежегодные эффекты построек и районов (yearly) — владельцу графства.
static func yearly(game: Game) -> void:
	var ids: Variant = game.engine.cache.get("districts:yearly")
	if ids == null:
		ids = {}
		for b in game.content.all("buildings"):
			if b.get("yearly") != null:
				ids[b.id] = true
		game.engine.cache["districts:yearly"] = ids
	var dyearly := all_defs(game).filter(func(d): return d.get("yearly") != null)
	if ids.is_empty() and dyearly.is_empty():
		return
	for p in game.state.provinces.values():
		if p.occupant != null:
			continue
		var h: Variant = holder_of(game, p.id)
		if h == null or not Chars.is_alive(h):
			continue
		for b in p.buildings:
			if ids.has(b):
				_run_yearly(game, h, p.id, game.content.get_def("buildings", b).yearly, building_scale(game, p.id, b), "building:" + str(b))
		for d in dyearly:
			if level(game, p.id, d.id) > 0:
				_run_yearly(game, h, p.id, d.yearly, power(game, p.id, d.id), "district:" + str(d.id))


static func _run_yearly(game: Game, h: Dictionary, prov_id: String, block: Variant, pw: float, src: String) -> void:
	var ctx := ScriptContext.make(game, {"type": "character", "id": h.id}, {"province": {"type": "province", "id": prov_id}})
	ctx.values["power"] = pw
	ctx.values["__src"] = src
	Interp.run_effect(ctx, ctx.root, block)


# ------------------------------------------------------------ ИИ

## Варианты стройки районов в домене для ИИ: [{province, def, level, cost, weight}].
## Быстрый путь: без строк причин, только то, что можно начать сейчас.
static func domain_options(game: Game, c: Dictionary) -> Array:
	var out := []
	if not on(game):
		return out
	var mult := maxf(0.1, 1.0 + Stats.stat(game, c, "build_cost_mult"))
	var top := max_level(game)
	for cid in Titles.domain_counties(game, c):
		var p: Variant = game.state.provinces.get(cid)
		if p == null or p.construction != null or p.occupant != null:
			continue
		var free := -1
		for d in all_defs(game):
			var cur := level(game, cid, d.id)
			var target := cur + 1
			if target > top or Data.num(p.development) < _arr(d.get("development"), target):
				continue
			var gold := roundf(_arr(d.get("cost"), target) * mult)
			if gold > float(c.gold):
				continue
			if cur == 0:
				if free < 0:
					free = free_plots(game, cid)
				if free <= 0:
					continue
				if d.get("trigger") != null:
					var tctx := ScriptContext.make(game, {"type": "province", "id": cid}, {"builder": {"type": "character", "id": c.id}})
					if not Interp.eval_trigger(tctx, tctx.root, d.trigger):
						continue
			var ctx := ScriptContext.make(game, {"type": "character", "id": c.id}, {"province": {"type": "province", "id": cid}})
			var w := Interp.eval_value(ctx, ctx.root, d.get("ai_will_do", 8))
			if cur > 0:
				# поднимать район стоит, когда в нём тесно
				w *= 1.0 if buildings_in(game, cid, d.id).size() >= slots(game, cid, d.id) else 0.35
			if w > 0.0:
				out.append({"province": cid, "def": d, "level": target, "cost": {"gold": gold, "prestige": 0.0}, "weight": w})
	return out


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.hooks.on("game.setup", func(p): Districts.ensure_all(p.game), 0, OWNER)
	engine.hooks.on("game.loaded", func(p): Districts.ensure_all(p.game), 0, OWNER)
	engine.systems.register("districts", {"id": "districts", "order": 61, "on_year": Districts.yearly}, OWNER)
	# районы графства: modifiers × сила
	engine.province_modifier_providers.register("districts", {"fn": func(game: Game, prov_id: String) -> Variant:
		var m := Districts.district_mods(game, prov_id, "modifiers")
		return m if not m.is_empty() else null
	}, OWNER)
	# владельцу: owner_modifiers районов домена × сила
	engine.modifier_providers.register("districts", {"label": "modsrc.districts", "fn": func(game: Game, c: Dictionary) -> Variant:
		if c.titles.is_empty():
			return null
		var out := {}
		for cid in Titles.domain_counties(game, c):
			Stats.add_into(out, Districts.district_mods(game, cid, "owner_modifiers"))
		return out if not out.is_empty() else null
	}, OWNER)
	# содержание районов — строка в доходах
	engine.hooks.on("economy.income", func(p):
		var v := Districts.upkeep(p.game, p.character)
		return {"label": p.game.loc.t("ui.district_upkeep"), "value": -v} if v > 0.0 else null
	, 0, OWNER)
	engine.content_validators.register("districts", func(e: GameEngine, v: ScriptValidator) -> void:
		for d in e.content.all("districts"):
			var where := "districts/" + str(d.id)
			v.trigger(d.get("trigger"), where)
			v.effect(d.get("yearly"), where)
			v.value(d.get("ai_will_do"), where)
			for f in Data.as_array(d.get("power")):
				if not (f is Dictionary) or not ["terrain", "coastal", "border", "neighbors", "domain", "trigger"].has(str(f.get("kind"))):
					v.issue("%s: неизвестный множитель силы %s" % [where, str(f)])
				elif f.kind == "trigger":
					v.trigger(f.get("limit"), where)
				elif (f.kind == "neighbors" or f.kind == "domain") and not e.content.has("districts", str(f.get("district"))):
					v.issue("%s: нет района \"%s\"" % [where, str(f.get("district"))])
		for b in e.content.all("buildings"):
			if b.get("district") != null and not e.content.has("districts", str(b.district)):
				v.issue("buildings/%s: нет района \"%s\"" % [b.id, str(b.district)])
			if b.get("unique") != null and not ["world", "realm"].has(str(b.unique)):
				v.issue("buildings/%s: unique — world или realm, а не \"%s\"" % [b.id, str(b.unique)])
			v.effect(b.get("yearly"), "buildings/" + str(b.id))
			v.value(b.get("ai_will_do"), "buildings/" + str(b.id))
	, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	const PR := ["province"]
	r.triggers.register("has_district", {"scopes": PR, "doc": "В графстве есть район (не ниже уровня): has_district: market или { district: market, level: 2 }", "eval": func(ctx, s, arg):
		var did := str(arg.get("district", "")) if arg is Dictionary else str(arg)
		var need := int(Data.num(arg.get("level"), 1)) if arg is Dictionary else 1
		return Districts.level(ctx.game, s.id, did) >= need,
		"describe": func(ctx, _s, arg):
			var did := str(arg.get("district", "")) if arg is Dictionary else str(arg)
			var need := int(Data.num(arg.get("level"), 1)) if arg is Dictionary else 1
			return ctx.game.loc.t("tr.has_district", {"value": ctx.game.name_of("districts", did), "level": Districts.roman(need)}),
	}, OWNER)
	r.values.register("district_level", {"scopes": PR, "doc": "Уровень района графства: district_level(market)", "get": func(ctx, s, a):
		return float(Districts.level(ctx.game, s.id, str(a))) if s != null else 0.0
	}, OWNER)
	r.values.register("district_power", {"scopes": PR, "doc": "Сила района графства: district_power(market)", "get": func(ctx, s, a):
		return Districts.power(ctx.game, s.id, str(a)) if s != null else 0.0
	}, OWNER)
	r.values.register("num_districts", {"scopes": PR, "doc": "Сумма уровней районов графства", "get": func(ctx, s, _a):
		var p: Variant = ctx.game.state.provinces.get(s.id) if s != null else null
		var n := 0
		if p != null and p.get("districts") is Dictionary:
			for did in p.districts:
				n += int(p.districts[did])
		return float(n)
	}, OWNER)
	r.effects.register("set_district_level", {"scopes": PR, "doc": "Поднять (или снести) район графства: set_district_level: { district: market, level: 2 } (0 — снести вместе с постройками)",
		"apply": func(ctx, s, arg):
			if arg is Dictionary:
				Districts.set_level(ctx.game, s.id, str(arg.get("district", "")), int(Data.num(arg.get("level"), 1))),
		"describe": func(ctx, s, arg):
			if not (arg is Dictionary):
				return null
			var lvl := int(Data.num(arg.get("level"), 1))
			return ctx.game.loc.t("fx.set_district_level" if lvl > 0 else "fx.raze_district", {"place": ctx.game.scope_name(s),
				"value": ctx.game.name_of("districts", str(arg.get("district", ""))), "level": Districts.roman(lvl)}),
	}, OWNER)

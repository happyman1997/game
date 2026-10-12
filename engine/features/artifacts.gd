class_name Artifacts
extends EngineFeature
## Инвентарь и реликвии (как в CK3). Каждая вещь — отдельный предмет мира:
## тип (меч, венец, гобелен…), редкость, свои модификаторы, прочность,
## история владельцев и притязания. Модификаторы даёт только надетое —
## личное снаряжение (шлем, регалия, доспех, оружие, безделушки) и убранство
## двора правителя (трон, стены, постаменты); остальное лежит в хранилище.
## Вещи ветшают и разрушаются, их чинят за золото, заказывают у мастеров,
## дарят, берут трофеями в битвах, переплавляют; после смерти владельца всё
## переходит основному наследнику. Отнятая вещь оставляет притязание:
## прежний владелец (а реликвия, ушедшая из рода, — глава рода) помнит,
## у кого она, и может потребовать её назад.
##
##   artifact_slots:    { <id>: { group: personal | court, count, order, icon } }
##                      court — только у правителя;
##   artifact_rarities: { <id>: { order, mult, durability, value, color,
##                        gift_opinion, bonuses } } — mult умножает
##                      модификаторы типа, bonuses — сколько добавок из bonus;
##   artifact_types:    { <id>: { slot, icon, modifiers, bonus: [ {…}, … ],
##                        names (число имён artifact_name.<id>.<n>),
##                        weight, commission: no } }
##   commission_tiers:  { <id>: { order, cost, months, chances: {редкость: вес} } }
##   artifacts:         уникальные реликвии { <id>: { type?, slot?, rarity?,
##                        icon, modifiers, holder (персонаж при старте),
##                        contested, inherit: no, house } }
##   defines.artifacts: decay_per_year, storage_decay_mult, battle_wear,
##                      loot_chance, trophy_chance, repair_mult, melt_mult,
##                      storage_max, claim_opinion, start (по рангам) …
## Состояние: state.artifacts = { <id>: предмет } — {id, def, type, rarity,
## name, owner, slot, durability, max_durability, modifiers, created,
## creator, house, claims: [персонажи], history: [[дата, как, от, кому]]};
## заказ мастеру — c.vars.commission = {type, tier, start, done}.
## Хуки: artifact.gained {artifact, character, from, how}, artifact.lost,
## artifact.destroyed {artifact, character, reason}, artifact.created.

const OWNER := "core/artifacts"
const HISTORY_MAX := 10


func _init() -> void:
	id = "artifacts"
	doc = "Инвентарь и реликвии: снаряжение, убранство двора, прочность, притязания"


static func _n(game: Game, key: String, def: float) -> float:
	return game.def_num("artifacts." + key, def)


static func _state(game: Game) -> Dictionary:
	if not (game.state.get("artifacts") is Dictionary):
		game.state["artifacts"] = {}
	return game.state.artifacts


## Старые сохранения: {реликвия: владелец} → предметы.
static func migrate(game: Game) -> void:
	var st := _state(game)
	var old := {}
	for k in st:
		if not (st[k] is Dictionary):
			old[k] = st[k]
	for k in old:
		st.erase(k)
		var it := ensure_unique(game, str(k))
		if it.is_empty():
			continue
		if old[k] != null and game.is_alive(old[k]):
			_place(game, it, game.ch(old[k]), "inherited", null)
	_dirty(game, [])


# ------------------------------------------------------------ чтение

static func item(game: Game, iid: Variant) -> Variant:
	return _state(game).get(str(iid)) if iid != null else null


static func type_def(game: Game, it: Dictionary) -> Variant:
	return game.content.get_def("artifact_types", str(it.get("type"))) if it.get("type") != null else null


static func unique_def(game: Game, it: Dictionary) -> Variant:
	return game.content.get_def("artifacts", str(it.def)) if it.get("def") != null else null


static func rarity_def(game: Game, r: Variant) -> Dictionary:
	var d: Variant = game.content.get_def("artifact_rarities", str(r))
	return d if d != null else {"order": 1, "mult": 1.0, "durability": 60, "value": 30, "color": "#c8c8c8"}


static func rarity_order(game: Game, r: Variant) -> int:
	return int(Data.num(rarity_def(game, r).get("order"), 1))


static func slot_of(game: Game, it: Dictionary) -> String:
	var u: Variant = unique_def(game, it)
	if u != null and u.get("slot") != null:
		return str(u.slot)
	var t: Variant = type_def(game, it)
	return str(t.get("slot", "trinket")) if t != null else "trinket"


static func icon_of(game: Game, it: Dictionary) -> Variant:
	var u: Variant = unique_def(game, it)
	if u != null and u.get("icon") != null:
		return u.icon
	var t: Variant = type_def(game, it)
	return t.get("icon", "star") if t != null else "star"


static func name_of(game: Game, it: Dictionary) -> String:
	if it.get("def") != null:
		return game.name_of("artifacts", it.def)
	if it.get("name") != null:
		return game.loc.t_or(str(it.name), str(it.name))
	return game.name_of("artifact_types", it.get("type"))


static func is_unique(it: Dictionary) -> bool:
	return it.get("def") != null


static func indestructible(game: Game, it: Dictionary) -> bool:
	var u: Variant = unique_def(game, it)
	return u != null and u.get("indestructible", true) != false


static func modifiers_of(game: Game, it: Dictionary) -> Dictionary:
	var u: Variant = unique_def(game, it)
	if u != null and u.get("modifiers") is Dictionary:
		return u.modifiers
	return it.get("modifiers", {}) if it.get("modifiers") is Dictionary else {}


static func value_of(game: Game, it: Dictionary) -> float:
	return Data.num(rarity_def(game, it.get("rarity")).get("value"), 30)


static func durability_frac(it: Dictionary) -> float:
	return clampf(float(it.get("durability", 1)) / maxf(1.0, float(it.get("max_durability", 1))), 0.0, 1.0)


## Индекс владельцев (кэш на месяц, сбрасывается при каждом переходе вещи).
static func _index(game: Game) -> Dictionary:
	var idx: Variant = game.month_cache.get("art_idx")
	if idx is Dictionary:
		return idx
	var out := {}
	var st := _state(game)
	for iid in st:
		var o: Variant = st[iid].get("owner") if st[iid] is Dictionary else null
		if o != null:
			if not out.has(o):
				out[o] = []
			out[o].append(iid)
	game.month_cache["art_idx"] = out
	return out


static func _dirty(game: Game, ids: Array) -> void:
	game.month_cache.erase("art_idx")
	game.month_cache.erase("art_claims")
	for id in ids:
		if id != null:
			game.stat_cache.erase(id)
	game.mark_chars_dirty(ids)


## Вещи персонажа (предметы).
static func items_of(game: Game, c: Dictionary) -> Array:
	var st := _state(game)
	var out := []
	for iid in _index(game).get(c.id, []):
		if st.has(iid):
			out.append(st[iid])
	return out


static func equipped(game: Game, c: Dictionary) -> Array:
	return items_of(game, c).filter(func(it): return it.get("slot") != null)


static func storage(game: Game, c: Dictionary) -> Array:
	return items_of(game, c).filter(func(it): return it.get("slot") == null)


## Совместимость: id вещей персонажа.
static func held_by(game: Game, c: Dictionary) -> Array:
	return items_of(game, c).map(func(it): return it.id)


## Владелец вещи (по id предмета или уникальной реликвии) или null.
static func holder_of(game: Game, aid: String) -> Variant:
	var it: Variant = item(game, aid)
	return game.ch(it.owner) if it != null and it.get("owner") != null else null


## Вещь у кого-то в державе персонажа (у него, вассалов или двора).
static func in_realm_of(game: Game, c: Dictionary, aid: String) -> bool:
	var h: Variant = holder_of(game, aid)
	return h != null and Titles.top_liege(game, h).id == c.id


# ------------------------------------------------------------ слоты

static func slot_def(game: Game, slot: String) -> Variant:
	return game.content.get_def("artifact_slots", slot)


static func slots(game: Game, group: String = "") -> Array:
	var out: Array = game.content.all("artifact_slots").filter(func(s): return group == "" or s.get("group", "personal") == group)
	Data.sort_by(out, func(s): return Data.num(s.get("order")))
	return out


static func slot_capacity(game: Game, c: Dictionary, slot: String) -> int:
	var sd: Variant = slot_def(game, slot)
	if sd == null:
		return 0
	if sd.get("group", "personal") == "court" and c.titles.is_empty():
		return 0
	return int(Data.num(sd.get("count"), 1))


static func in_slot(game: Game, c: Dictionary, slot: String) -> Array:
	return items_of(game, c).filter(func(it): return it.get("slot") == slot)


## Оценка вещи для ИИ: дороже и целее — лучше.
static func score(game: Game, it: Dictionary) -> float:
	return value_of(game, it) * (0.5 + 0.5 * durability_frac(it))


static func can_equip(game: Game, c: Dictionary, it: Dictionary) -> bool:
	return it.get("owner") == c.id and slot_capacity(game, c, slot_of(game, it)) > 0


## Надеть (поставить) вещь; если слот занят — снимается replace или худшая.
static func equip(game: Game, c: Dictionary, it: Dictionary, replace: Variant = null) -> bool:
	if not can_equip(game, c, it):
		return false
	var slot := slot_of(game, it)
	var cur := in_slot(game, c, slot)
	if it.get("slot") == slot:
		return true
	if cur.size() >= slot_capacity(game, c, slot):
		var out: Variant = replace if replace is Dictionary and cur.has(replace) else null
		if out == null:
			cur.sort_custom(func(a, b): return score(game, a) < score(game, b))
			out = cur[0]
		out.slot = null
	it.slot = slot
	_dirty(game, [c.id])
	return true


static func unequip(game: Game, c: Dictionary, it: Dictionary) -> void:
	if it.get("owner") == c.id and it.get("slot") != null:
		it.slot = null
		_dirty(game, [c.id])


## Новая вещь: в свободный слот; ИИ меняет худшее на лучшее.
static func _auto_equip(game: Game, c: Dictionary, it: Dictionary) -> bool:
	var slot := slot_of(game, it)
	var cap := slot_capacity(game, c, slot)
	if cap <= 0:
		return false
	var cur := in_slot(game, c, slot)
	if cur.size() < cap:
		it.slot = slot
		return true
	if game.is_player(c.id):
		return false
	cur.sort_custom(func(a, b): return score(game, a) < score(game, b))
	if score(game, it) > score(game, cur[0]) * 1.1:
		cur[0].slot = null
		it.slot = slot
		return true
	return false


## Убрать в хранилище то, что больше не помещается (стал безземельным и т.п.).
static func _fit_slots(game: Game, c: Dictionary) -> bool:
	var changed := false
	var by := {}
	for it in equipped(game, c):
		var s: String = it.slot
		if not by.has(s):
			by[s] = []
		by[s].append(it)
	for s in by:
		var cap := slot_capacity(game, c, s)
		if by[s].size() > cap:
			by[s].sort_custom(func(a, b): return score(game, a) > score(game, b))
			for i in range(cap, by[s].size()):
				by[s][i].slot = null
				changed = true
	return changed


# ------------------------------------------------------------ создание

static func _scale(v: Variant, mult: float) -> float:
	var f := float(v)
	if absf(f - roundf(f)) < 0.0001 and absf(f) >= 1.0:
		var r := roundf(f * mult)
		return r if r != 0.0 else signf(f)
	return roundf(f * mult * 100.0) / 100.0


static func _add_mods(out: Dictionary, mods: Variant, mult: float) -> void:
	if not (mods is Dictionary):
		return
	for k in mods:
		out[k] = float(out.get(k, 0.0)) + _scale(mods[k], mult)


static func _history(it: Dictionary, game: Game, how: String, from: Variant, to: Variant) -> void:
	if not (it.get("history") is Array):
		it["history"] = []
	it.history.append([game.date, how, from, to])
	if it.history.size() > HISTORY_MAX:
		it.history = it.history.slice(it.history.size() - HISTORY_MAX)


## Создать вещь типа type и редкости rarity (у owner, если задан).
## opts: name (ключ или текст), creator, house, how.
static func create(game: Game, type: String, rarity: String, owner: Variant = null, opts: Dictionary = {}) -> Dictionary:
	var td: Variant = game.content.get_def("artifact_types", type)
	if td == null:
		game.script_error("Нет типа вещи \"%s\"" % type)
		return {}
	var rd := rarity_def(game, rarity)
	var mult := Data.num(rd.get("mult"), 1.0)
	var mods := {}
	_add_mods(mods, td.get("modifiers"), mult)
	var pool: Array = Data.as_array(td.get("bonus")).duplicate()
	for _i in int(Data.num(rd.get("bonuses"), 0)):
		if pool.is_empty():
			break
		var b: Variant = game.rng.pick(pool)
		pool.erase(b)
		_add_mods(mods, b, mult)
	var name: Variant = opts.get("name")
	var names := int(Data.num(td.get("names"), 0))
	if name == null and names > 0 and rarity_order(game, rarity) >= 2:
		name = "artifact_name.%s.%d" % [type, game.rng.range_int(1, names)]
	var dur := Data.num(rd.get("durability"), 60)
	var it := {
		"id": game.new_id("art"), "def": null, "type": type, "rarity": rarity, "name": name,
		"owner": null, "slot": null, "durability": dur, "max_durability": dur, "modifiers": mods,
		"created": game.date, "creator": opts.get("creator"), "house": opts.get("house"), "claims": [], "history": [],
	}
	_state(game)[it.id] = it
	_history(it, game, str(opts.get("how", "created")), opts.get("creator"), owner.id if owner is Dictionary else null)
	if owner is Dictionary:
		_place(game, it, owner, "", null)
		_dirty(game, [owner.id])
	game.emit("artifact.created", {"artifact": it.id, "character": owner})
	return it


## Уникальная реликвия из данных (artifacts) — создаётся при первом обращении.
static func ensure_unique(game: Game, aid: String) -> Dictionary:
	var st := _state(game)
	if st.get(aid) is Dictionary:
		return st[aid]
	var d: Variant = game.content.get_def("artifacts", aid)
	if d == null:
		return {}
	var rarity := str(d.get("rarity", "illustrious"))
	var dur := Data.num(rarity_def(game, rarity).get("durability"), 100)
	var it := {
		"id": aid, "def": aid, "type": d.get("type"), "rarity": rarity, "name": null,
		"owner": null, "slot": null, "durability": dur, "max_durability": dur, "modifiers": {},
		"created": game.date, "creator": null, "house": d.get("house"), "claims": [], "history": [],
	}
	st[aid] = it
	return it


## Положить вещь владельцу (без сообщений): история, притязания, слот.
static func _place(game: Game, it: Dictionary, c: Dictionary, how: String, prev: Variant) -> void:
	it.slot = null
	it.owner = c.id
	if how != "":
		_history(it, game, how, prev, c.id)
	var claims: Array = it.get("claims", [])
	claims.erase(c.id)
	if prev != null and how in ["looted", "seized", "stolen", "confiscated"] and not claims.has(prev):
		claims.append(prev)
	it["claims"] = claims
	_dirty(game, [c.id, prev])
	_auto_equip(game, c, it)


## Передать вещь персонажу. how: gift, inherited, looted, seized, returned,
## bought, found, gained… (взятое силой оставляет притязание прежнему).
static func give(game: Game, aid: String, c: Dictionary, how: String = "gained") -> void:
	if c.death != null:
		return
	var it: Variant = item(game, aid)
	if it == null:
		it = ensure_unique(game, aid)
		if it.is_empty():
			return
	var prev: Variant = it.get("owner")
	if prev == c.id:
		return
	_place(game, it, c, how, prev)
	var name := name_of(game, it)
	# наследство приходит пачкой — о нём и так сообщает наследование
	if game.is_player(c.id) and how != "inherited":
		game.message(game.loc.t("msg.artifact_gained", {"value": name}), "good", {"type": "artifact", "id": it.id}, [c.id])
	elif prev != null and game.is_player(prev):
		game.message(game.loc.t("msg.artifact_taken", {"who": game.scope_name({"type": "character", "id": c.id}), "value": name}), "bad",
			{"type": "character", "id": c.id}, [c.id, prev])
	game.emit("artifact.gained", {"artifact": it.id, "character": c, "from": prev, "how": how})


## Утратить вещь: уникальная пропадает (её можно найти снова), прочие гибнут.
static func lose(game: Game, aid: String) -> void:
	var it: Variant = item(game, aid)
	if it == null or it.get("owner") == null:
		return
	if not is_unique(it):
		destroy(game, aid, "lost")
		return
	var prev: Variant = it.owner
	it.owner = null
	it.slot = null
	_history(it, game, "lost", prev, null)
	_dirty(game, [prev])
	if game.is_player(prev):
		game.message(game.loc.t("msg.artifact_lost", {"value": name_of(game, it)}), "bad", null, [prev])
	game.emit("artifact.lost", {"artifact": aid, "character": game.ch(prev)})


static func destroy(game: Game, aid: String, reason: String = "") -> void:
	var it: Variant = item(game, aid)
	if it == null:
		return
	var prev: Variant = it.get("owner")
	if is_unique(it):
		lose(game, aid)
		return
	_state(game).erase(aid)
	_dirty(game, [prev])
	if prev != null and game.is_player(prev) and reason != "melted":
		game.message(game.loc.t("msg.artifact_destroyed", {"value": name_of(game, it)}), "bad", null, [prev])
	game.emit("artifact.destroyed", {"artifact": aid, "character": game.ch(prev) if prev != null else null, "reason": reason})


# ------------------------------------------------------------ притязания

## Притязает ли персонаж на вещь (личное притязание или реликвия его рода —
## у главы рода).
static func has_claim(game: Game, c: Dictionary, it: Dictionary) -> bool:
	if it.get("owner") == c.id:
		return false
	if Data.as_array(it.get("claims")).has(c.id):
		return true
	var house: Variant = it.get("house")
	if house == null or c.dynasty == null or not game.engine.has_feature("dynasties"):
		return false
	var root: Variant = Chars.dynasty_root(game, c.dynasty)
	if root != house:
		return false
	var holder: Variant = game.ch(it.owner) if it.get("owner") != null else null
	if holder != null and holder.dynasty != null and Chars.dynasty_root(game, holder.dynasty) == house:
		return false
	var head: Variant = Dynasties.head_of(game, house)
	return head != null and head.id == c.id


## Вещи holder, на которые притязает c.
static func claimed_from(game: Game, c: Dictionary, holder: Dictionary) -> Array:
	var by: Variant = _claim_index(game).get(holder.id)
	if by == null or not by.has(c.id):
		return []
	var out := []
	for iid in by[c.id]:
		var it: Variant = item(game, iid)
		if it != null:
			out.append(it)
	return out


## Индекс притязаний (кэш на месяц): {владелец: {притязающий: [вещи]}}.
static func _claim_index(game: Game) -> Dictionary:
	var idx: Variant = game.month_cache.get("art_claims")
	if idx is Dictionary:
		return idx
	var out := {}
	var heads := {}
	var dyn := game.engine.has_feature("dynasties")
	for it in _state(game).values():
		var o: Variant = it.get("owner")
		if o == null:
			continue
		var who := []
		for pid in Data.as_array(it.get("claims")):
			if pid != o and game.is_alive(pid):
				who.append(pid)
		var house: Variant = it.get("house")
		if dyn and house != null:
			if not heads.has(house):
				var h: Variant = Dynasties.head_of(game, house)
				heads[house] = h.id if h != null else null
			var hid: Variant = heads[house]
			var holder: Variant = game.ch(o)
			if hid != null and hid != o and not who.has(hid) and holder != null and (holder.dynasty == null or Chars.dynasty_root(game, holder.dynasty) != house):
				who.append(hid)
		for pid in who:
			if not out.has(o):
				out[o] = {}
			if not out[o].has(pid):
				out[o][pid] = []
			out[o][pid].append(it.id)
	game.month_cache["art_claims"] = out
	return out


## Все вещи, на которые притязает c (у кого бы ни были).
static func claims_of(game: Game, c: Dictionary) -> Array:
	var out := []
	var idx := _claim_index(game)
	for o in idx:
		for iid in idx[o].get(c.id, []):
			var it: Variant = item(game, iid)
			if it != null:
				out.append(it)
	return out


# ------------------------------------------------------------ ремонт, переплавка

static func repair_cost(game: Game, it: Dictionary) -> float:
	return roundf(value_of(game, it) * (1.0 - durability_frac(it)) * _n(game, "repair_mult", 0.6))


static func repair(game: Game, c: Dictionary, it: Dictionary) -> bool:
	var cost := repair_cost(game, it)
	if it.get("owner") != c.id or cost <= 0.0 or float(c.gold) < cost:
		return false
	c.gold = float(c.gold) - cost
	it.durability = float(it.max_durability)
	_history(it, game, "repaired", null, c.id)
	game.mark_chars_dirty([c.id])
	return true


static func melt_value(game: Game, it: Dictionary) -> float:
	return roundf(value_of(game, it) * _n(game, "melt_mult", 0.3) * (0.5 + 0.5 * durability_frac(it)))


static func melt(game: Game, c: Dictionary, it: Dictionary) -> bool:
	if it.get("owner") != c.id or is_unique(it):
		return false
	c.gold = float(c.gold) + melt_value(game, it)
	destroy(game, it.id, "melted")
	return true


# ------------------------------------------------------------ заказ мастеру

static func commission_of(c: Dictionary) -> Variant:
	var o: Variant = c.vars.get("commission")
	return o if o is Dictionary else null


static func commission_types(game: Game) -> Array:
	var out: Array = game.content.all("artifact_types").filter(func(t): return t.get("commission", true) != false)
	Data.sort_by(out, func(t):
		var sd: Variant = slot_def(game, str(t.get("slot", "trinket")))
		return Data.num(sd.get("order") if sd != null else 99) * 100 + Data.num(t.get("order")))
	return out


static func commission_tiers(game: Game) -> Array:
	var out: Array = game.content.all("commission_tiers")
	Data.sort_by(out, func(t): return Data.num(t.get("order")))
	return out


## Шансы редкости заказа [{rarity, weight}] с поправкой на управление заказчика.
static func commission_chances(game: Game, c: Dictionary, tier: String) -> Array:
	var td: Variant = game.content.get_def("commission_tiers", tier)
	if td == null:
		return []
	var skill := Stats.skill(game, c, str(game.def_val("artifacts.commission_skill", "stewardship")))
	var bump := maxf(0.0, (skill - _n(game, "commission_skill_base", 8)) * _n(game, "commission_skill_step", 0.04))
	# стезя Зодчего: лучшие мастера ищут его заказов
	bump += maxf(0.0, Stats.stat(game, c, "commission_quality"))
	var out := []
	for r in td.get("chances", {}):
		var w := Data.num(td.chances[r])
		# умелый заказчик сдвигает шансы к редкому
		w *= 1.0 + bump * float(rarity_order(game, r) - 1)
		if w > 0.0:
			out.append({"rarity": r, "weight": w})
	out.sort_custom(func(a, b): return rarity_order(game, a.rarity) < rarity_order(game, b.rarity))
	return out


## Цена заказа для персонажа (commission_cost_mult — стезя Зодчего).
static func commission_cost(game: Game, c: Dictionary, tier: String) -> float:
	var td: Variant = game.content.get_def("commission_tiers", tier)
	if td == null:
		return 0.0
	return roundf(Data.num(td.get("cost")) * maxf(0.1, 1.0 + Stats.stat(game, c, "commission_cost_mult")))


static func commission_blockers(game: Game, c: Dictionary, tier: String) -> Array:
	var out := []
	var td: Variant = game.content.get_def("commission_tiers", tier)
	if td == null:
		return [game.loc.t("ui.inv_no_tier")]
	if commission_of(c) != null:
		out.append(game.loc.t("ui.inv_commission_busy"))
	if float(c.gold) < commission_cost(game, c, tier):
		out.append(game.loc.t("ui.inv_need_gold", {"n": roundi(commission_cost(game, c, tier))}))
	if not Chars.is_adult(game, c):
		out.append(game.loc.t("ui.inv_too_young"))
	return out


static func commission(game: Game, c: Dictionary, type: String, tier: String) -> bool:
	var td: Variant = game.content.get_def("commission_tiers", tier)
	if td == null or not game.content.has("artifact_types", type) or not commission_blockers(game, c, tier).is_empty():
		return false
	c.gold = float(c.gold) - commission_cost(game, c, tier)
	var months := Data.num(td.get("months"), 6)
	c.vars["commission"] = {"type": type, "tier": tier, "start": game.date, "done": game.date + roundi(months * 30.4)}
	game.mark_chars_dirty([c.id])
	return true


static func _finish_commission(game: Game, c: Dictionary) -> void:
	var o: Dictionary = c.vars.commission
	c.vars.erase("commission")
	var pick: Variant = game.rng.weighted(commission_chances(game, c, str(o.tier)), func(x): return x.weight)
	var rarity: String = pick.rarity if pick != null else "common"
	var house: Variant = Chars.dynasty_root(game, c.dynasty) if c.dynasty != null else null
	var it := create(game, str(o.type), rarity, c, {"house": house, "how": "commissioned"})
	if it.is_empty():
		return
	if game.is_player(c.id):
		game.message(game.loc.t("msg.artifact_commissioned", {"value": name_of(game, it), "rarity": game.name_of("artifact_rarities", rarity)}), "good",
			{"type": "artifact", "id": it.id}, [c.id])


# ------------------------------------------------------------ ход времени

## Помесячно для персонажа: заказ, а у ИИ — снаряжение, ремонт, заказы.
static func monthly_char(game: Game, c: Dictionary) -> void:
	var o: Variant = commission_of(c)
	if o != null and int(o.done) <= game.date:
		_finish_commission(game, c)
	if game.is_player(c.id):
		return
	var items := items_of(game, c)
	if not items.is_empty():
		_ai_manage(game, c, items)
	if not c.titles.is_empty() and o == null and game.rng.chance(_n(game, "ai_commission_chance", 0.03)):
		_ai_commission(game, c)


static func _ai_manage(game: Game, c: Dictionary, items: Array) -> void:
	var changed := _fit_slots(game, c)
	for it in items:
		if it.get("slot") == null and _auto_equip(game, c, it):
			changed = true
	if changed:
		_dirty(game, [c.id])
	var below := _n(game, "ai_repair_below", 0.3)
	for it in items:
		if it.get("slot") != null and durability_frac(it) < below and not indestructible(game, it):
			var cost := repair_cost(game, it)
			if float(c.gold) > cost + _n(game, "ai_repair_reserve", 20):
				repair(game, c, it)
	# хранилище не бездонно: худшее — в переплавку
	var cap := int(_n(game, "storage_max", 10))
	if items.size() > cap:
		var store := items.filter(func(it): return it.get("slot") == null and not is_unique(it))
		if store.size() > cap:
			store.sort_custom(func(a, b): return score(game, a) < score(game, b))
			for i in store.size() - cap:
				melt(game, c, store[i])


static func _ai_commission(game: Game, c: Dictionary) -> void:
	var tiers := commission_tiers(game)
	var best: Variant = null
	for t in tiers:
		if float(c.gold) >= commission_cost(game, c, str(t.id)) * 2.0 + _n(game, "ai_commission_reserve", 60):
			best = t
	if best == null:
		return
	# что заказать: в пустой слот, иначе — что угодно
	var empty := []
	for t in commission_types(game):
		var slot := str(t.get("slot", "trinket"))
		if in_slot(game, c, slot).size() < slot_capacity(game, c, slot):
			empty.append(t)
	var pool: Array = empty if not empty.is_empty() else ([] if storage(game, c).size() >= 3 else commission_types(game))
	var pick: Variant = game.rng.weighted(pool, func(t): return Data.num(t.get("weight"), 10))
	if pick != null:
		commission(game, c, pick.id, best.id)


## Помесячно: вещи ветшают; рассыпавшиеся гибнут.
static func monthly(game: Game) -> void:
	var decay := _n(game, "decay_per_year", 4) / 12.0
	var store_mult := _n(game, "storage_decay_mult", 0.5)
	var dead := []
	for it in _state(game).values():
		if it.get("owner") == null or indestructible(game, it):
			continue
		it.durability = float(it.durability) - decay * (1.0 if it.get("slot") != null else store_mult)
		if float(it.durability) <= 0.0:
			dead.append(it.id)
	for iid in dead:
		destroy(game, iid, "decay")


## Битва: снаряжение полководцев изнашивается, победитель может взять
## трофей — вещь побеждённого (тот запомнит) или чужое оружие с поля.
static func on_battle(game: Game, wc: Variant, lc: Variant) -> void:
	var wear := _n(game, "battle_wear", 2)
	for cm in [wc, lc]:
		if cm == null:
			continue
		for it in equipped(game, cm):
			if slot_of(game, it) in ["weapon", "armor", "helmet"] and not indestructible(game, it):
				it.durability = maxf(1.0, float(it.durability) - wear)
	if wc == null or wc.death != null:
		return
	if lc != null and game.rng.chance(_n(game, "loot_chance", 0.12)):
		var spoils: Array = equipped(game, lc).filter(func(it): return slot_of(game, it) in ["weapon", "armor", "helmet"])
		if not spoils.is_empty():
			var it: Dictionary = game.rng.pick(spoils)
			give(game, it.id, wc, "looted")
			return
	if game.rng.chance(_n(game, "trophy_chance", 0.06)):
		var types: Array = game.content.all("artifact_types").filter(func(t): return str(t.get("slot")) in ["weapon", "armor", "helmet"])
		var t: Variant = game.rng.pick(types)
		if t != null:
			var it := create(game, t.id, "masterwork" if game.rng.chance(0.25) else "common", null, {"how": "trophy"})
			if not it.is_empty():
				give(game, it.id, wc, "trophy")


## Наследство: всё — основному наследнику, без него — сюзерену; уникальное
## без хозяина теряется. Реликвия, ушедшая из рода, — притязание главы рода.
static func on_death(game: Game, c: Dictionary, heir_id: Variant) -> void:
	var items := items_of(game, c)
	if items.is_empty():
		return
	var heir: Variant = game.ch(heir_id) if heir_id != null else null
	if heir == null or heir.death != null:
		heir = Succession.primary_heir(game, c)
	if heir == null or heir.death != null:
		heir = game.ch(c.liege) if c.liege != null else null
	var root: Variant = Chars.dynasty_root(game, c.dynasty) if c.dynasty != null else null
	for it in items:
		var u: Variant = unique_def(game, it)
		if heir == null or heir.death != null or (u != null and u.get("inherit", true) == false):
			lose(game, it.id)
			continue
		var heir_root: Variant = Chars.dynasty_root(game, heir.dynasty) if heir.dynasty != null else null
		if root != null and heir_root != root and it.get("house") == null and rarity_order(game, it.rarity) >= 2:
			it["house"] = root
		give(game, it.id, heir, "inherited")


## Стартовые вещи: сначала исторические реликвии (holder), затем — по рангу
## правителя в свободные слоты (defines.artifacts.start).
static func on_setup(game: Game) -> void:
	for d in game.content.all("artifacts"):
		var h: Variant = d.get("holder")
		if h != null and game.is_alive(h):
			var it := ensure_unique(game, d.id)
			if not it.is_empty() and it.get("owner") == null:
				_place(game, it, game.ch(h), "heirloom", null)
	var start: Variant = game.def_val("artifacts.start", {})
	if not (start is Dictionary):
		return
	var by_order := {}
	for rd in game.content.all("artifact_rarities"):
		by_order[int(Data.num(rd.get("order")))] = rd.id
	for r in game.rulers():
		var key: String = ["", "county", "duchy", "kingdom", "empire"][clampi(Titles.primary_tier(game, r), 0, 4)]
		var house: Variant = Chars.dynasty_root(game, r.dynasty) if r.dynasty != null else null
		for spec in Data.as_array(start.get(key)):
			if not (spec is Dictionary) or not game.rng.chance(Data.num(spec.get("chance"), 1.0)):
				continue
			var types: Array = game.content.all("artifact_types").filter(func(t):
				return (spec.get("slot") == null or t.get("slot") == spec.slot) and (spec.get("types") == null or Data.as_array(spec.types).has(t.id)))
			var t: Variant = game.rng.weighted(types, func(x): return Data.num(x.get("weight"), 10))
			if t == null:
				continue
			var slot := str(t.get("slot", "trinket"))
			if in_slot(game, r, slot).size() >= slot_capacity(game, r, slot):
				continue
			var rarity := str(spec.get("rarity", "common"))
			if spec.get("upgrade") != null and game.rng.chance(Data.num(spec.upgrade)):
				rarity = str(by_order.get(rarity_order(game, rarity) + 1, rarity))
			create(game, t.id, rarity, r, {"house": house if rarity_order(game, rarity) >= 3 else null, "how": "heirloom"})
	_dirty(game, [])


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("artifacts", {"id": "artifacts", "order": 17, "on_character_month": Artifacts.monthly_char, "on_month": Artifacts.monthly}, OWNER)
	engine.modifier_providers.register("artifacts", {"fn": func(game: Game, c: Dictionary) -> Variant:
		var st: Variant = game.state.get("artifacts")
		if not (st is Dictionary) or st.is_empty():
			return null
		var out := []
		for it in Artifacts.equipped(game, c):
			var mods := Artifacts.modifiers_of(game, it)
			if not mods.is_empty():
				var iid: String = it.id
				out.append({"label": func():
					var x: Variant = Artifacts.item(game, iid)
					return Artifacts.name_of(game, x) if x != null else iid, "modifiers": mods})
		return out if not out.is_empty() else null
	}, OWNER)
	# притязания: «держит мою вещь»
	engine.opinion_providers.register("artifacts", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		var by: Variant = Artifacts._claim_index(game).get(b.id)
		if by == null or not by.has(a.id):
			return null
		var iids: Array = by[a.id]
		var it: Variant = Artifacts.item(game, iids[0])
		var name := Artifacts.name_of(game, it) if it != null else "?"
		return {"label": game.loc.t("opinion.holds_my_artifact", {"name": name}), "value": Artifacts._n(game, "claim_opinion", -10) * mini(iids.size(), 2)}
	}, OWNER)
	engine.hooks.on("character.death", func(p):
		Artifacts.on_death(p.game, p.character, p.get("heir"))
	, 0, OWNER)
	engine.hooks.on("battle", func(p):
		var game: Game = p.game
		Artifacts.on_battle(game, game.ch(p.get("win_commander")) if p.get("win_commander") != null else null,
			game.ch(p.get("lose_commander")) if p.get("lose_commander") != null else null)
	, 0, OWNER)
	engine.hooks.on("game.setup", func(p): Artifacts.on_setup(p.game), 0, OWNER)
	engine.hooks.on("game.loaded", func(p): Artifacts.migrate(p.game), 0, OWNER)
	# цель войны: держава, где хранится спорная реликвия
	engine.cb_targets.register("artifact_holder", {"targets": func(game: Game, attacker: Dictionary) -> Array:
		var out := []
		var seen := {}
		for it in Artifacts._state(game).values():
			var d: Variant = Artifacts.unique_def(game, it)
			if d == null or not d.get("contested", false) or it.get("owner") == null:
				continue
			var h: Variant = game.ch(it.owner)
			if h == null:
				continue
			var top: Dictionary = Titles.top_liege(game, h)
			if top.id == attacker.id or top.titles.is_empty() or seen.has(top.id):
				continue
			seen[top.id] = true
			out.append({"defender": top.id, "title": top.titles[0], "counties": Titles.domain_counties(game, top)})
		return out
	}, OWNER)
	# цели взаимодействий: свои вещи (подарить) и чужие, на которые есть притязание
	var opt := func(game: Game, it: Dictionary) -> Dictionary:
		return {"id": it.id, "label": "%s (%s)" % [Artifacts.name_of(game, it), game.name_of("artifact_rarities", it.rarity)], "ref": {"type": "artifact", "id": it.id}}
	engine.interaction_targets.register("own_artifacts", {"options": func(game: Game, actor: Dictionary, _r: Dictionary) -> Array:
		var items := Artifacts.items_of(game, actor)
		items.sort_custom(func(a, b): return Artifacts.score(game, a) > Artifacts.score(game, b))
		return items.map(func(it): return opt.call(game, it))
	}, OWNER)
	engine.interaction_targets.register("claimed_artifacts", {"options": func(game: Game, actor: Dictionary, recipient: Dictionary) -> Array:
		return Artifacts.claimed_from(game, actor, recipient).map(func(it): return opt.call(game, it))
	}, OWNER)
	engine.content_validators.register("artifacts", func(e: GameEngine, v: ScriptValidator):
		for t in e.content.all("artifact_types"):
			if not e.content.has("artifact_slots", str(t.get("slot", "trinket"))):
				v.issue("artifact_types/%s: нет слота \"%s\"" % [t.id, t.get("slot")])
		for d in e.content.all("artifacts"):
			if d.get("type") != null:
				v.ref("artifact_types", d.type, "artifacts/" + d.id)
			if d.get("slot") != null:
				v.ref("artifact_slots", d.slot, "artifacts/" + d.id)
			if d.get("rarity") != null:
				v.ref("artifact_rarities", d.rarity, "artifacts/" + d.id)
		for t in e.content.all("commission_tiers"):
			for r in t.get("chances", {}):
				v.ref("artifact_rarities", r, "commission_tiers/" + t.id)
	, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	const CH := ["character"]
	const AR := ["artifact"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s is Dictionary and s.get("type") == "character") else null
	var art := func(ctx: ScriptContext, s: Variant) -> Variant:
		return Artifacts.item(ctx.game, s.id) if (s is Dictionary and s.get("type") == "artifact") else null
	var art_arg := func(ctx: ScriptContext, s: Variant, arg: Variant) -> Variant:
		var ref: Variant = Interp.resolve_scope(ctx, s, arg) if not (arg is String and Artifacts.item(ctx.game, arg) != null) else {"type": "artifact", "id": arg}
		return Artifacts.item(ctx.game, ref.id) if (ref is Dictionary and ref.get("type") == "artifact") else null
	var aname := func(ctx: ScriptContext, arg: Variant) -> String:
		var it: Variant = Artifacts.item(ctx.game, str(arg))
		return Artifacts.name_of(ctx.game, it) if it != null else ctx.game.name_of("artifacts", str(arg))

	# --- персонаж
	r.triggers.register("has_artifact", {"scopes": CH, "doc": "Персонаж держит вещь (реликвию по id или предмет): has_artifact: <id>", "eval": func(ctx, s, arg):
		var it: Variant = Artifacts.item(ctx.game, str(arg))
		return it != null and it.get("owner") == s.id,
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_artifact", {"value": aname.call(ctx, arg)}),
	}, OWNER)
	r.triggers.register("realm_has_artifact", {"scopes": CH, "doc": "Реликвия хранится в державе персонажа (у него, вассалов или двора)", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		return c != null and Artifacts.in_realm_of(ctx.game, c, str(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.realm_has_artifact", {"value": aname.call(ctx, arg)}),
	}, OWNER)
	r.triggers.register("artifact_is_held", {"doc": "Реликвия у кого-то есть (не утеряна): artifact_is_held: <id>", "eval": func(ctx, _s, arg):
		var it: Variant = Artifacts.item(ctx.game, str(arg))
		return it != null and it.get("owner") != null,
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.artifact_is_held", {"value": aname.call(ctx, arg)}),
	}, OWNER)
	r.triggers.register("has_artifact_type", {"scopes": CH, "doc": "Есть вещь этого типа: has_artifact_type: sword", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return c != null and Artifacts.items_of(ctx.game, c).any(func(it): return it.get("type") == str(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_artifact_type", {"value": ctx.game.name_of("artifact_types", str(arg))}),
	}, OWNER)
	r.triggers.register("has_artifact_claim", {"scopes": CH, "doc": "Притязает на чью-то вещь (yes) или на вещь этого персонажа: has_artifact_claim: scope:recipient", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c == null:
			return false
		if arg is bool or str(arg) in ["yes", "no"]:
			return (not Artifacts.claims_of(ctx.game, c).is_empty()) == ScriptContext.is_yes(arg)
		var o: Variant = Interp.resolve_scope(ctx, s, arg)
		var oc: Variant = ctx.game.ch(o.id) if (o is Dictionary and o.get("type") == "character") else null
		return oc != null and not Artifacts.claimed_from(ctx.game, c, oc).is_empty(),
		"describe": func(ctx, s, arg):
			if arg is bool or str(arg) in ["yes", "no"]:
				return ctx.game.loc.t("tr.has_artifact_claim_any")
			return ctx.game.loc.t("tr.has_artifact_claim", {"who": ctx.game.scope_name(Interp.resolve_scope(ctx, s, arg))}),
	}, OWNER)
	r.values.register("num_artifacts", {"scopes": CH, "doc": "Число вещей у персонажа", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(Artifacts.items_of(ctx.game, c).size()) if c != null else 0.0
	}, OWNER)
	r.values.register("num_equipped_artifacts", {"scopes": CH, "doc": "Число надетых вещей и убранства двора", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(Artifacts.equipped(ctx.game, c).size()) if c != null else 0.0
	}, OWNER)
	r.values.register("num_spare_artifacts", {"scopes": CH, "doc": "Число вещей в хранилище (не надетых)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(Artifacts.storage(ctx.game, c).size()) if c != null else 0.0
	}, OWNER)
	r.effects.register("gain_artifact", {"scopes": CH, "doc": "Получить реликвию или вещь (у прежнего владельца она пропадает): gain_artifact: <id>", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			Artifacts.give(ctx.game, str(arg), c),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.gain_artifact", {"who": ctx.game.scope_name(s), "value": aname.call(ctx, arg)}),
	}, OWNER)
	r.effects.register("lose_artifact", {"scopes": CH, "doc": "Утратить реликвию — она пропадает, и её можно найти снова: lose_artifact: <id>", "apply": func(ctx, s, arg):
		var it: Variant = Artifacts.item(ctx.game, str(arg))
		if it != null and it.get("owner") == s.id:
			Artifacts.lose(ctx.game, str(arg)),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.lose_artifact", {"who": ctx.game.scope_name(s), "value": aname.call(ctx, arg)}),
	}, OWNER)
	r.effects.register("seize_realm_artifacts", {"scopes": CH, "doc": "Забрать спорные реликвии из державы персонажа from: seize_realm_artifacts: scope:defender", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var from: Variant = Interp.resolve_scope(ctx, s, arg)
		var fc: Variant = ctx.game.ch(from.id) if from != null else null
		if c == null or fc == null:
			return
		for it in Artifacts._state(ctx.game).values().duplicate():
			var d: Variant = Artifacts.unique_def(ctx.game, it)
			if d != null and d.get("contested", false) and Artifacts.in_realm_of(ctx.game, fc, it.id):
				Artifacts.give(ctx.game, it.id, c, "seized"),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.seize_realm_artifacts", {"who": ctx.game.scope_name(s), "from": ctx.game.scope_name(Interp.resolve_scope(ctx, s, arg))}),
	}, OWNER)
	r.effects.register("create_artifact", {"scopes": CH, "doc": "Создать вещь персонажу: create_artifact: { type: sword | [ring, amulet] | slot: trinket, rarity: masterwork | [common, masterwork], save_scope_as }", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var a: Dictionary = arg if arg is Dictionary else {"type": arg}
		if c == null:
			return
		var g: Game = ctx.game
		var types: Array = g.content.all("artifact_types").filter(func(t):
			return (a.get("type") == null or Data.as_array(a.type).has(t.id)) and (a.get("slot") == null or t.get("slot") == a.slot))
		var t: Variant = g.rng.weighted(types, func(x): return Data.num(x.get("weight"), 10))
		if t == null:
			return
		var rarities: Array = Data.as_array(a.get("rarity", "common"))
		var it := Artifacts.create(g, t.id, str(g.rng.pick(rarities)), null, {"how": str(a.get("how", "found"))})
		if it.is_empty():
			return
		Artifacts.give(g, it.id, c, str(a.get("how", "found")))
		if a.get("save_scope_as") != null:
			ctx.scopes[str(a.save_scope_as)] = {"type": "artifact", "id": it.id},
		"describe": func(ctx, s, arg):
			var a: Dictionary = arg if arg is Dictionary else {"type": arg}
			var what: String = ctx.game.loc.t("ui.inv_some_artifact")
			if a.get("type") is String:
				what = ctx.game.name_of("artifact_types", a.type)
			var rr: Variant = a.get("rarity")
			if rr is String:
				what += " (%s)" % ctx.game.name_of("artifact_rarities", rr)
			return ctx.game.loc.t("fx.create_artifact", {"who": ctx.game.scope_name(s), "value": what}),
	}, OWNER)
	r.effects.register("transfer_artifact", {"scopes": CH, "doc": "Отдать вещь персонажу: transfer_artifact: { artifact: scope:target, to: scope:recipient, how: gift }", "apply": func(ctx, s, arg):
		if not (arg is Dictionary):
			return
		var it: Variant = art_arg.call(ctx, s, arg.get("artifact"))
		var to: Variant = Interp.resolve_scope(ctx, s, arg.get("to", "this"))
		var tc: Variant = ctx.game.ch(to.id) if (to is Dictionary and to.get("type") == "character") else null
		if it != null and tc != null:
			Artifacts.give(ctx.game, it.id, tc, str(arg.get("how", "gift"))),
		"describe": func(ctx, s, arg):
			if not (arg is Dictionary):
				return null
			var it: Variant = art_arg.call(ctx, s, arg.get("artifact"))
			var to: Variant = Interp.resolve_scope(ctx, s, arg.get("to", "this"))
			return ctx.game.loc.t("fx.transfer_artifact", {"value": Artifacts.name_of(ctx.game, it) if it != null else "?", "who": ctx.game.scope_name(to) if to is Dictionary else "?"}),
	}, OWNER)
	r.lists.register("artifact", {"from": CH, "doc": "Вещи персонажа (any_artifact, random_artifact, every_artifact)", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		return Artifacts.items_of(ctx.game, c).map(func(it): return {"type": "artifact", "id": it.id}) if c != null else []
	}, OWNER)
	r.lists.register("artifact_claim_holders", {"from": CH, "doc": "Те, у кого вещи, на которые притязает персонаж", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		if c == null:
			return []
		var seen := {}
		var out := []
		for it in Artifacts.claims_of(ctx.game, c):
			if not seen.has(it.owner):
				seen[it.owner] = true
				out.append({"type": "character", "id": it.owner})
		return out
	}, OWNER)
	# --- вещь
	r.triggers.register("artifact_type", {"scopes": AR, "doc": "Тип вещи: artifact_type: sword", "eval": func(ctx, s, arg):
		var it: Variant = art.call(ctx, s)
		return it != null and Data.as_array(arg).has(it.get("type")),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.artifact_type", {"value": ctx.game.name_of("artifact_types", str(arg))}),
	}, OWNER)
	r.triggers.register("artifact_rarity", {"scopes": AR, "doc": "Редкость вещи не ниже: artifact_rarity: masterwork", "eval": func(ctx, s, arg):
		var it: Variant = art.call(ctx, s)
		return it != null and Artifacts.rarity_order(ctx.game, it.rarity) >= Artifacts.rarity_order(ctx.game, str(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.artifact_rarity", {"value": ctx.game.name_of("artifact_rarities", str(arg))}),
	}, OWNER)
	r.triggers.register("artifact_is_equipped", {"scopes": AR, "doc": "Вещь надета или стоит при дворе", "eval": func(ctx, s, arg):
		var it: Variant = art.call(ctx, s)
		return (it != null and it.get("slot") != null) == (arg == null or ScriptContext.is_yes(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.artifact_is_equipped" + ("" if arg == null or ScriptContext.is_yes(arg) else ".not")),
	}, OWNER)
	r.values.register("artifact_value", {"scopes": AR, "doc": "Ценность вещи (по редкости)", "get": func(ctx, s, _a):
		var it: Variant = art.call(ctx, s)
		return Artifacts.value_of(ctx.game, it) if it != null else 0.0
	}, OWNER)
	r.values.register("artifact_durability", {"scopes": AR, "doc": "Прочность вещи, % от наибольшей", "get": func(ctx, s, _a):
		var it: Variant = art.call(ctx, s)
		return Artifacts.durability_frac(it) * 100.0 if it != null else 0.0
	}, OWNER)
	r.values.register("artifact_gift_opinion", {"scopes": AR, "doc": "Насколько радует такой подарок (мнение, по редкости)", "get": func(ctx, s, _a):
		var it: Variant = art.call(ctx, s)
		return Data.num(Artifacts.rarity_def(ctx.game, it.rarity).get("gift_opinion"), 10) if it != null else 0.0
	}, OWNER)
	r.effects.register("add_artifact_durability", {"scopes": AR, "doc": "Изменить прочность вещи: add_artifact_durability: -20", "apply": func(ctx, s, arg):
		var it: Variant = art.call(ctx, s)
		if it == null or Artifacts.indestructible(ctx.game, it):
			return
		it.durability = clampf(float(it.durability) + Interp.eval_value(ctx, s, arg), 0.0, float(it.max_durability))
		if float(it.durability) <= 0.0:
			Artifacts.destroy(ctx.game, it.id, "decay"),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.add_artifact_durability", {"value": "%+d" % roundi(Interp.eval_value(ctx, s, arg))}),
	}, OWNER)
	r.effects.register("destroy_artifact", {"scopes": AR, "doc": "Уничтожить вещь (уникальная — теряется): destroy_artifact: yes", "apply": func(ctx, s, _arg):
		var it: Variant = art.call(ctx, s)
		if it != null:
			Artifacts.destroy(ctx.game, it.id, "script"),
		"describe": func(ctx, s, _arg): return ctx.game.loc.t("fx.destroy_artifact", {"value": ctx.game.scope_name(s)}),
	}, OWNER)
	r.links.register("artifact_owner", {"from": AR, "doc": "Владелец вещи", "resolve": func(ctx, s):
		var it: Variant = Artifacts.item(ctx.game, s.id)
		return {"type": "character", "id": it.owner} if it != null and it.get("owner") != null else null
	}, OWNER)

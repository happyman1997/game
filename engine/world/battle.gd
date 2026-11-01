class_name Battle
extends RefCounted
## Сражение: собирает стороны для ядра (CoreBattle, native/src/battle.rs) и
## применяет итог — потери армий и отрядов, судьбы рыцарей и полководцев.
## Сам бой — перестрелка, сеча по дням, слом и погоня — считает ядро; здесь
## только перевод армий в войска по видам и обратно.
##
## Отчёт битвы (сохраняется в войне, w.battles[].report, и в поле битвы на
## карте): {winner (0 — нападающие, 1 — защитники), days, broke, log: [{day,
## phase, morale, lost, men}], units: [[{key, type, men, left, fled}], …],
## knights: [{id, side, fate, by}], events: [{day, kind, side, n?, a?, b?}],
## commander: [судьба, судьба], lost, start, morale, sides: [{owners,
## commander, armies}]}.


static func core() -> Variant:
	if not ClassDB.class_exists("CoreBattle"):
		return null
	return ClassDB.instantiate("CoreBattle")


static func _d(game: Game, key: String, fallback: Variant) -> Variant:
	var b: Variant = game.defines.get("battle")
	return b.get(key, fallback) if b is Dictionary else fallback


## Боевые свойства вида войск: regiment_types.<id>.battle или по силе (power).
static func profile(game: Game, type: String) -> Dictionary:
	var d: Variant = game.content.get_def("regiment_types", type)
	if d == null:
		return {}
	var b: Variant = d.get("battle")
	if b is Dictionary:
		return b
	var pw := Data.num(d.get("power"), 1.0)
	return {"melee": pw, "toughness": 1.0 + (pw - 1.0) * 0.4, "morale": 70, "pursuit": 0.5, "screen": 0.7}


## Полководец стороны: из полководцев её армий — с наибольшим перевесом на
## этом поле (военное дело, навыки, местность).
static func _commander(game: Game, armies: Array, loc: String, attacking: bool, defending: bool) -> Variant:
	var best: Variant = null
	var best_v := -INF
	for a in armies:
		var c: Variant = Military.commander_of(game, a)
		if c == null:
			continue
		var v := 0.0
		for p in Command.advantage_parts(game, c, loc, attacking, defending):
			v += float(p.value)
		if v > best_v:
			best = c
			best_v = v
	return best


## Полководец для ядра: очки перевеса с разбором (parts — для окна битвы),
## нрав и навыки (черты command, Command.skills).
static func _commander_input(game: Game, c: Dictionary, armies: Array, loc: String, attacking: bool, defending: bool) -> Dictionary:
	var parts := Command.advantage_parts(game, c, loc, attacking, defending)
	# home_advantage (мастер засад): бой на земле своей державы
	var ha := Stats.stat(game, c, "home_advantage")
	if ha != 0.0 and not armies.is_empty():
		var owner: Variant = game.ch(armies[0].owner)
		var holder: Variant = Titles.province_controller(game, loc)
		if owner != null and holder != null and (holder.id == owner.id or Titles.top_liege(game, holder).id == Titles.top_liege(game, owner).id):
			parts.append({"key": "home", "value": ha * Command.stat_mult(game)})
	var adv := 0.0
	for p in parts:
		adv += float(p.value)
	var sk := Command.skills(game, c)
	var has := func(key: String) -> bool:
		for t in Data.as_array(_d(game, key, [])):
			if c.traits.has(t):
				return true
		return false
	return {
		"id": c.id, "adv": adv, "parts": parts,
		"aggression": 1.0 if has.call("aggressive") else 0.0,
		"caution": 1.0 if has.call("cautious") else 0.0,
		"craven": has.call("craven"),
		"pursuit": Stats.stat(game, c, "pursuit") + float(sk.get("pursuit", 0.0)),
		"orderly": Stats.stat(game, c, "orderly_retreat"),
		"death_mult": Military._death_mult(game, c) * (1.0 + float(sk.get("risk", 0.0))),
		"front": Stats.stat(game, c, "personal_example"),
		"charge": sk.get("charge", 0.0), "charge_day": sk.get("charge_day", 0.0),
		"ranged": sk.get("ranged", 0.0), "volleys": sk.get("volleys", 0.0),
		"rearguard": sk.get("rearguard", 0.0), "steady": sk.get("steady", 0.0),
		"levy_steady": sk.get("levy_steady", 0.0), "losses": sk.get("losses", 0.0), "luck": sk.get("luck", 0.0),
		"morale": sk.get("morale", 0.0),
	}


## Войска стороны: ополчение и отряды каждой армии (ключ — армия:отряд).
static func _units(game: Game, armies: Array, loc: String) -> Array:
	var out := []
	var levy: Dictionary = _d(game, "levy", {})
	for a in armies:
		var regs := Data.as_array(a.get("regiments"))
		var in_regs := 0
		for r in regs:
			in_regs += int(r.size)
		var owner: Variant = game.ch(a.owner)
		var drill := maxf(0.0, 1.0 + Stats.stat(game, owner, "regiment_power")) if owner != null else 1.0
		var lv := maxi(0, int(a.size) - in_regs)
		if lv > 0:
			var u := levy.duplicate()
			u.merge({"key": a.id + ":levy", "type": "levy", "category": "levy", "men": lv, "levy": true, "quality": 1.0})
			out.append(u)
		for r in regs:
			if int(r.size) <= 0:
				continue
			var def: Variant = game.content.get_def("regiment_types", r.type)
			var u := profile(game, str(r.type)).duplicate()
			var terr := 1.0 + Data.num(game.terrain_pick(def.get("terrain"), loc, 0.0)) if def != null else 1.0
			u.merge({"key": a.id + ":" + str(r.id), "type": str(r.type), "category": str(def.get("category", "special")) if def != null else "special",
				"men": int(r.size), "quality": maxf(0.1, terr) * drill, "counters": def.get("counters", {}) if def != null else {}}, true)
			out.append(u)
	return out


## Рыцари владельцев, чья главная армия в бою.
static func _knights(game: Game, armies: Array) -> Array:
	if not game.engine.has_feature("knights"):
		return []
	var out := []
	var seen := {}
	for a in armies:
		var owner: Variant = game.ch(a.owner)
		if owner == null or seen.has(owner.id):
			continue
		var main: Variant = Knights.main_army_of(game, owner.id)
		if main == null or main.id != a.id:
			continue
		seen[owner.id] = true
		var eff := maxf(0.0, 1.0 + Stats.stat(game, owner, "knight_effectiveness"))
		for k in Knights.knights_of(game, owner):
			if k.death == null:
				out.append({"id": k.id, "prowess": Stats.skill(game, k, "prowess") * eff, "death_mult": Military._death_mult(game, k)})
	return out


## Прочие прибавки к силе (механики и моды — хук army.power_bonus): множитель стороны.
static func _mult(game: Game, armies: Array, enemies: Array, loc: String) -> float:
	var men := 0.0
	var extra := 0.0
	for a in armies:
		men += float(a.size)
		for b in game.engine.hooks.collect("army.power_bonus", {"game": game, "army": a, "enemies": enemies, "location": loc, "native_battle": true}):
			extra += Data.num(b)
	if men <= 0.0:
		return 1.0
	return clampf((men + extra) / men, 0.1, 5.0)


static func _side(game: Game, armies: Array, enemies: Array, loc: String, defending: bool, attacking: bool) -> Dictionary:
	var c: Variant = _commander(game, armies, loc, attacking, defending)
	var s := {
		"units": _units(game, armies, loc),
		"knights": _knights(game, armies),
		"mult": _mult(game, armies, enemies, loc),
		"defense": game.terrain_num(loc, "defense") if defending else 0.0,
		"morale_bonus": 0.0,
	}
	if c != null:
		var ci := _commander_input(game, c, armies, loc, attacking, defending)
		s["commander"] = ci
		s.morale_bonus = Stats.skill(game, c, "martial") * Data.num(_d(game, "morale_per_martial", 1)) + float(ci.morale)
	return s


## Бой: отчёт ядра (или null — ядро не собрано). att/def — армии сторон.
static func fight(game: Game, loc: String, att: Array, def: Array, defender_side: Variant) -> Variant:
	if not ScriptContext.is_yes(_d(game, "core", true)):
		return null
	var cb: Variant = core()
	if cb == null:
		return null
	var params: Dictionary = game.defines.get("battle", {}).duplicate()
	for k in ["chase_min", "chase_max", "loser_commander_death", "winner_commander_death", "personal_example_safe", "personal_example_wound"]:
		params[k] = game.def_num("military." + k, Data.num(params.get(k)))
	var input := {
		"seed": game.rng.range_int(1, 2000000000),
		"params": params,
		"sides": [_side(game, att, def, loc, defender_side == "att", true), _side(game, def, att, loc, defender_side == "def", false)],
	}
	var r: Dictionary = cb.fight(input)
	r["sides"] = []
	for i in 2:
		var armies: Array = att if i == 0 else def
		var cm: Variant = input.sides[i].get("commander")
		r.sides.append({"owners": Data.uniq(armies.map(func(a): return a.owner)), "armies": armies.map(func(a): return a.id),
			"commander": cm.id if cm != null else null, "adv": cm.adv if cm != null else 0.0, "adv_parts": cm.parts if cm != null else [],
			"defending": defender_side == ("att" if i == 0 else "def")})
	return r


## Поле битвы на карте (state.battlefields): остаётся defines.battle.field_years
## лет, не больше field_max последних.
static func add_field(game: Game, rec: Dictionary) -> void:
	var fields: Array = Data.as_array(game.state.get("battlefields")).duplicate()
	var f := rec.duplicate()
	f["id"] = game.new_id("bf")
	fields.append(f)
	game.state["battlefields"] = fields
	prune_fields(game)


static func prune_fields(game: Game) -> void:
	var keep := int(Data.num(_d(game, "field_years", 2)) * GameDate.DAYS_PER_YEAR)
	var mx := int(Data.num(_d(game, "field_max", 30)))
	var fields: Array = Data.as_array(game.state.get("battlefields")).filter(func(f): return game.date - int(f.date) <= keep)
	if fields.size() > mx:
		fields = fields.slice(fields.size() - mx)
	game.state["battlefields"] = fields


static func field(game: Game, id: Variant) -> Variant:
	for f in Data.as_array(game.state.get("battlefields")):
		if f.id == id:
			return f
	return null


## Потери из отчёта — в армии и их отряды.
static func apply_losses(game: Game, r: Dictionary, armies: Array) -> void:
	var by_key := {}
	for side in r.units:
		for u in side:
			by_key[str(u.key)] = u
	for a in armies:
		var lost := 0
		var lv: Variant = by_key.get(a.id + ":levy")
		if lv != null:
			lost += int(lv.men) - int(lv.left)
		for reg in Data.as_array(a.get("regiments")):
			var u: Variant = by_key.get(a.id + ":" + str(reg.id))
			if u != null:
				lost += int(u.men) - int(u.left)
				reg.size = int(u.left)
		a.size = maxi(0, int(a.size) - lost)

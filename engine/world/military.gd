class_name Military
extends RefCounted
## Армии: сбор ополчения, передвижение по графу соседства провинций,
## сражения и осады. Числа — в defines.military.


static func armies_of(game: Game, id: String) -> Array:
	return game.state.armies.values().filter(func(a): return a.owner == id)


static func armies_at(game: Game, prov_id: String) -> Array:
	return game.state.armies.values().filter(func(a): return a.location == prov_id)


static func can_raise_army(game: Game, c: Dictionary) -> bool:
	return not c.titles.is_empty() and armies_of(game, c.id).is_empty() and Economy.realm_levy(game, c) >= game.def_num("military.min_army", 50)


static func new_army_record() -> Dictionary:
	return {"id": "", "owner": "", "war": null, "size": 0, "max_size": 0, "location": "", "path": [], "progress": 0.0,
		"commander": null, "retreating": false, "regiments": null, "ai_target": null, "ai_replan": null}


static func raise_army(game: Game, c: Dictionary) -> Variant:
	if not can_raise_army(game, c):
		return null
	var size := Economy.realm_levy(game, c)
	var loc: Variant = Titles.capital_of(game, c)
	if loc == null:
		var dom := Titles.domain_counties(game, c)
		loc = dom[0] if not dom.is_empty() else null
	if loc == null:
		return null
	var a := new_army_record()
	a.id = game.new_id("army")
	a.owner = c.id
	a.size = size
	a.max_size = size
	a.location = loc
	game.state.armies[a.id] = a
	game.day_cache.clear()
	game.emit("army.raised", {"army": a})
	game.notify("army")
	return a


static func disband_army(game: Game, id: String) -> void:
	var a: Variant = game.state.armies.get(id)
	if a == null:
		return
	var owner: Variant = game.ch(a.owner)
	if owner != null and Chars.is_alive(owner):
		var ratio = clampf(float(a.size) / float(a.max_size), 0.0, 1.0) if a.max_size > 0 else 1.0
		var min_r = game.def_num("military.min_levy_ratio", 0.1)
		for m in Titles.realm_members(game, owner):
			m.levy_ratio = maxf(min_r, float(m.levy_ratio) * ratio)
	for p in game.state.provinces.values():
		if p.siege != null and p.siege.army == id:
			p.siege = null
	game.state.armies.erase(id)
	game.day_cache.clear()
	game.emit("army.disbanded", {"army": a})
	game.notify("army")


static func commander_of(game: Game, a: Dictionary) -> Variant:
	var c: Variant = game.ch(a.commander)
	if c == null:
		c = game.ch(a.owner)
	if c != null and Chars.is_alive(c) and Chars.is_adult(game, c) and c.get("prison") == null:
		return c
	return null


# ------------------------------------------------------------ путь

static func edge_cost(game: Game, from: String, to: String) -> float:
	var pd: Variant = game.content.get_def("provinces", to)
	var terrain: Variant = game.content.get_def("terrain", pd.get("terrain")) if pd != null else null
	return game.engine.distance(from, to) * (Data.num(terrain.get("movement"), 1.0) if terrain != null else 1.0)


## Кратчайший путь. Возвращает путь без стартовой провинции или null.
static func find_path(game: Game, from: String, to: String) -> Variant:
	if from == to:
		return []
	return game.engine.find_path(from, to)


## Число переходов по кратчайшему пути (для оценок ИИ).
static func path_steps(game: Game, from: String, to: String) -> float:
	if from == to:
		return 0.0
	var p: Variant = find_path(game, from, to)
	return float(p.size()) if p != null else INF


static func move_army(game: Game, id: String, dest: String) -> bool:
	var a: Variant = game.state.armies.get(id)
	if a == null or a.get("retreating", false):
		return false
	var path: Variant = find_path(game, a.location, dest)
	if path == null:
		return false
	a.path = path
	a.progress = 0.0
	game.notify("army")
	return true


## Сколько дней до следующей провинции на пути.
static func days_to_next(game: Game, a: Dictionary) -> int:
	if a.path.is_empty():
		return 0
	return ceili((1.0 - float(a.progress)) * edge_cost(game, a.location, a.path[0]) / game.def_num("military.speed", 12))


# ------------------------------------------------------------ враждебность

## Война, в которой армия враждебна контролёру провинции.
static func hostile_war_at(game: Game, a: Dictionary, prov_id: String) -> Variant:
	var ctrl: Variant = Titles.province_controller(game, prov_id)
	if ctrl == null:
		return null
	for w in Wars.wars_of(game, a.owner):
		var mine: Variant = Wars.participant_side(w, a.owner)
		var p: Dictionary = game.state.provinces[prov_id]
		var theirs: Variant = Wars.participant_side(w, p.occupant) if (p.occupant != null and p.occupant_war == w.id) else Wars.side_of(game, w, ctrl.id)
		if mine != null and theirs != null and mine != theirs:
			return w
	return null


## Своя провинция, захваченная врагом в войне, где армия участвует.
static func _liberation_war_at(game: Game, a: Dictionary, prov_id: String) -> Variant:
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null or p.occupant == null or p.occupant_war == null:
		return null
	var w: Variant = game.state.wars.get(p.occupant_war)
	if w == null:
		return null
	var mine: Variant = Wars.participant_side(w, a.owner)
	var holder_side: Variant = Wars.side_of(game, w, game.state.titles[prov_id].holder if game.state.titles.has(prov_id) else null)
	var occ_side: Variant = Wars.participant_side(w, p.occupant)
	return w if (mine != null and holder_side == mine and occ_side != mine) else null


static func _enemy_armies_in_war(game: Game, w: Dictionary, side: String, loc: String) -> Array:
	return armies_at(game, loc).filter(func(x):
		var s: Variant = Wars.participant_side(w, x.owner)
		return s != null and s != side and not x.get("retreating", false))


# ------------------------------------------------------------ ежедневный цикл

static func daily_military(game: Game) -> void:
	var speed = game.def_num("military.speed", 12)
	for a in game.state.armies.values():
		if not game.is_alive(a.owner):
			game.state.armies.erase(a.id)
			continue
		if a.path.is_empty():
			continue
		var cost = maxf(1.0, edge_cost(game, a.location, a.path[0]))
		a.progress = float(a.progress) + speed / cost
		if a.progress >= 1.0:
			a.location = a.path.pop_front()
			a.progress = 0.0
			if a.path.is_empty():
				a.retreating = false
			var p: Variant = game.state.provinces.get(a.location)
			if p != null and p.siege != null and p.siege.army != a.id and not game.state.armies.has(p.siege.army):
				p.siege = null
	_resolve_battles(game)
	_progress_sieges(game)


static func _resolve_battles(game: Game) -> void:
	var by_loc := {}
	for a in game.state.armies.values():
		if a.get("retreating", false):
			continue
		if not by_loc.has(a.location):
			by_loc[a.location] = []
		by_loc[a.location].append(a)
	for loc in by_loc:
		var armies: Array = by_loc[loc]
		if armies.size() < 2:
			continue
		for w in game.state.wars.values():
			var att = armies.filter(func(a): return game.state.armies.has(a.id) and Wars.participant_side(w, a.owner) == "att" and not a.get("retreating", false))
			var def = armies.filter(func(a): return game.state.armies.has(a.id) and Wars.participant_side(w, a.owner) == "def" and not a.get("retreating", false))
			if not att.is_empty() and not def.is_empty():
				_battle(game, w, loc, att, def)


## Сила армии с учётом бонусов механик (отряды и т.п.); enemies — армии противника в бою.
static func army_strength(game: Game, a: Dictionary, enemies: Array = [], location: Variant = null) -> float:
	var v = float(a.size)
	for b in game.engine.hooks.collect("army.power_bonus", {"game": game, "army": a, "enemies": enemies, "location": location if location != null else a.location}):
		v += Data.num(b)
	return maxf(0.0, v)


## {power, men, commander}
static func _side_power(game: Game, armies: Array, defending: bool, loc: String, enemies: Array) -> Dictionary:
	var men := 0.0
	var eff := 0.0
	var best: Variant = null
	for a in armies:
		men += float(a.size)
		eff += army_strength(game, a, enemies, loc)
		var c: Variant = commander_of(game, a)
		if c != null and (best == null or Stats.skill(game, c, "martial") > Stats.skill(game, best, "martial")):
			best = c
	var martial = Stats.skill(game, best, "martial") if best != null else 0
	var adv = Stats.stat(game, best, "commander_advantage") if best != null else 0.0
	var pd: Variant = game.content.get_def("provinces", loc)
	var terrain: Variant = game.content.get_def("terrain", pd.get("terrain")) if pd != null else null
	var power = eff * (1.0 + martial * game.def_num("military.martial_bonus", 0.04) + adv / 100.0) * game.rng.range_float(game.def_num("military.battle_luck_min", 0.85), game.def_num("military.battle_luck_max", 1.15))
	if defending:
		power *= 1.0 + (Data.num(terrain.get("defense")) if terrain != null else 0.0)
	return {"power": power, "men": men, "commander": best}


static func _battle(game: Game, w: Dictionary, loc: String, att: Array, def: Array) -> void:
	var ctrl: Variant = Titles.province_controller(game, loc)
	var ctrl_side: Variant = Wars.side_of(game, w, ctrl.id if ctrl != null else null)
	var A := _side_power(game, att, ctrl_side == "att", loc, def)
	var D := _side_power(game, def, ctrl_side == "def", loc, att)
	var att_wins: bool = A.power >= D.power
	var win: Dictionary = A if att_wins else D
	var lose: Dictionary = D if att_wins else A
	var win_armies: Array = att if att_wins else def
	var lose_armies: Array = def if att_wins else att
	var ratio = minf(1.0, lose.power / maxf(1.0, win.power))
	var lose_loss = roundi(lose.men * (game.def_num("military.loser_loss_base", 0.25) + game.def_num("military.loser_loss_scale", 0.4) * (1.0 - ratio)))
	var win_loss = roundi(win.men * (game.def_num("military.winner_loss_base", 0.05) + game.def_num("military.winner_loss_scale", 0.2) * ratio))
	_distribute(win_armies, win_loss, win.men)
	_distribute(lose_armies, lose_loss, lose.men)

	var loser_max := 0.0
	for a in lose_armies:
		loser_max += float(a.max_size)
	var delta = maxf(game.def_num("military.battle_score_min", 5), minf(game.def_num("military.battle_score_max", 25), roundf(5.0 + 30.0 * lose_loss / maxf(1.0, loser_max))))
	w.battle_score = float(w.battle_score) + (delta if att_wins else -delta)

	var win_owner: Dictionary = game.ch(win_armies[0].owner)
	var lose_owner: Dictionary = game.ch(lose_armies[0].owner)
	var bp = game.def_num("military.battle_prestige", 20)
	win_owner.prestige += bp
	lose_owner.prestige -= bp / 2.0

	game.message(game.loc.t("msg.battle", {
		"place": game.name_of("provinces", loc),
		"winner": game.scope_name({"type": "character", "id": win_owner.id}),
		"loser": game.scope_name({"type": "character", "id": lose_owner.id}),
		"wl": win_loss, "ll": lose_loss,
	}), "war", {"type": "province", "id": loc}, w.attackers + w.defenders)
	game.emit("battle", {"war": w, "location": loc, "winner": win_owner.id, "loser": lose_owner.id, "win_loss": win_loss, "lose_loss": lose_loss})
	game.on_action("on_battle_won", {"type": "character", "id": win_owner.id}, {"enemy": {"type": "character", "id": lose_owner.id}})
	game.on_action("on_battle_lost", {"type": "character", "id": lose_owner.id}, {"enemy": {"type": "character", "id": win_owner.id}})

	# Гибель полководцев
	var lc: Variant = lose.commander
	var wc: Variant = win.commander
	if lc != null and game.rng.chance(game.def_num("military.loser_commander_death", 0.04)):
		Succession.kill_character(game, lc, "battle", wc.id if wc != null else null)
	else:
		if wc != null and game.rng.chance(game.def_num("military.winner_commander_death", 0.01)):
			Succession.kill_character(game, wc, "battle", lc.id if lc != null else null)
		if lc != null and lc.death == null:
			game.emit("battle.commander_survived", {"war": w, "commander": lc.id, "captor": win_owner.id})

	# Отступление проигравших
	var min_army = game.def_num("military.min_army", 50)
	var loser_side = "def" if att_wins else "att"
	for a in lose_armies:
		if not game.state.armies.has(a.id):
			continue
		if a.size < min_army:
			game.state.armies.erase(a.id)
			continue
		var dest: Variant = _retreat_target(game, w, loser_side, a.location)
		if dest == null:
			game.state.armies.erase(a.id)
			continue
		var path: Variant = find_path(game, a.location, dest)
		a.path = path if path != null else []
		a.progress = 0.0
		a.retreating = not a.path.is_empty()
		if not a.retreating:
			game.state.armies.erase(a.id)
	for a in win_armies:
		if game.state.armies.has(a.id) and a.size < min_army:
			game.state.armies.erase(a.id)
	game.notify("army")


static func _distribute(armies: Array, total: int, men: float) -> void:
	for a in armies:
		var before = int(a.size)
		a.size = maxi(0, int(a.size) - roundi(float(total) * a.size / maxf(1.0, men)))
		# профессиональные отряды несут потери в той же доле
		if a.get("regiments") != null and not a.regiments.is_empty() and before > 0:
			for r in a.regiments:
				r.size = roundi(float(r.size) * a.size / before)


static func _retreat_target(game: Game, w: Dictionary, side: String, from: String) -> Variant:
	var seen := {from: true}
	var frontier := [from]
	for depth in 8:
		var next := []
		for p in frontier:
			for n in game.engine.neighbors(p):
				if seen.has(n):
					continue
				seen[n] = true
				var ctrl: Variant = Titles.province_controller(game, n)
				var ctrl_side: Variant = Wars.side_of(game, w, ctrl.id if ctrl != null else null)
				if ctrl_side == side and _enemy_armies_in_war(game, w, side, n).is_empty():
					return n
				next.append(n)
		frontier = next
	return null


static func _progress_sieges(game: Game) -> void:
	for a in game.state.armies.values():
		if not a.path.is_empty() or a.get("retreating", false):
			continue
		var p: Variant = game.state.provinces.get(a.location)
		if p == null:
			continue
		var war: Variant = hostile_war_at(game, a, a.location)
		if war == null:
			war = _liberation_war_at(game, a, a.location)
		if war == null:
			if p.siege != null and p.siege.army == a.id:
				p.siege = null
			continue
		var side: String = Wars.participant_side(war, a.owner)
		if not _enemy_armies_in_war(game, war, side, a.location).is_empty():
			continue
		if p.siege != null and p.siege.army != a.id and game.state.armies.has(p.siege.army):
			continue
		if p.siege == null:
			p.siege = {"army": a.id, "progress": 0.0}
		var fort = maxf(1.0, province_fort(game, a.location))
		var liberation: bool = p.occupant != null and Wars.participant_side(war, p.occupant) != side
		var daily = float(a.size) / (fort * game.def_num("military.siege_per_fort", 800) + game.def_num("military.siege_base", 400)) * game.def_num("military.siege_speed", 3) * (2.0 if liberation else 1.0)
		p.siege.progress = float(p.siege.progress) + minf(game.def_num("military.siege_max_daily", 12), daily)
		if p.siege.progress >= 100.0:
			p.siege = null
			var holder: Variant = game.state.titles[a.location].holder if game.state.titles.has(a.location) else null
			if liberation and Wars.side_of(game, war, holder) == side:
				p.occupant = null
				p.occupant_war = null
			else:
				p.occupant = a.owner
				p.occupant_war = war.id
				# добыча и разорение — в данных (on_actions.on_siege_won)
				var scopes := {"province": {"type": "province", "id": a.location}, "war": {"type": "war", "id": war.id}}
				if holder != null:
					scopes["defender"] = {"type": "character", "id": holder}
				game.on_action("on_siege_won", {"type": "character", "id": a.owner}, scopes)
			game.message(game.loc.t("msg.siege_won", {"place": game.name_of("provinces", a.location), "who": game.scope_name({"type": "character", "id": a.owner})}), "war", {"type": "province", "id": a.location}, war.attackers + war.defenders)
			game.emit("siege.won", {"war": war, "army": a, "province": a.location})
			game.notify("map")


static func province_fort(game: Game, prov_id: String) -> float:
	var def: Variant = game.content.get_def("provinces", prov_id)
	var fort := 0.0
	if def != null:
		for h in Data.as_array(def.get("holdings")):
			var hd: Variant = game.content.get_def("holdings", h)
			if hd != null:
				fort = maxf(fort, Data.num(hd.get("fort")))
	var st: Variant = game.state.provinces.get(prov_id)
	if st != null:
		for b in st.buildings:
			var bd: Variant = game.content.get_def("buildings", b)
			if bd != null and bd.get("modifiers") is Dictionary:
				fort += Data.num(bd.modifiers.get("fort"))
	return fort


## Ежемесячно: восстановление ополчений.
static func regen_levies(game: Game) -> void:
	var r = game.def_num("military.levy_regen", 0.05)
	var raised := {}
	for a in game.state.armies.values():
		raised[a.owner] = true
	for c in game.rulers():
		if not raised.has(c.id) and c.levy_ratio < 1.0:
			c.levy_ratio = minf(1.0, float(c.levy_ratio) + r)

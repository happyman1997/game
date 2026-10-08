class_name Ai
extends RefCounted
## ИИ правителей. Каждый правитель «думает» раз в месяц в свой день
## (нагрузка размазана по месяцу). Поведение задаётся весами ai_will_do
## в данных и личностью из черт (traits.ai). Мод может добавить своё
## поведение через хук "ai.think" или заменить систему "ai" целиком.


static func personality(game: Game, c: Dictionary) -> Dictionary:
	var key = "ai:" + c.id
	var cached: Variant = game.stat_cache.get(key)
	if cached != null:
		return cached
	var out := {}
	for t in c.traits:
		var d: Variant = game.content.get_def("traits", t)
		if d != null and d.get("ai") is Dictionary:
			for k in d.ai:
				out[k] = float(out.get(k, 0.0)) + Data.num(d.ai[k])
	game.stat_cache[key] = out
	return out


static func _think_day(c: Dictionary) -> int:
	var h := 0
	var id: String = c.id
	for i in id.length():
		h = (h * 31 + id.unicode_at(i)) & 0xFFFFFFFF
	if h >= 0x80000000:
		h -= 0x100000000
	return absi(h) % 28


static func daily_ai(game: Game) -> void:
	var day := (game.date % 365) % 28
	for c in game.rulers():
		if game.is_player(c.id) or c.death != null:
			continue
		if _think_day(c) != day:
			continue
		think_ruler(game, c)
	for a in game.state.armies.values():
		if game.is_player(a.owner) or not game.state.armies.has(a.id):
			continue
		army_ai(game, a)


static func think_ruler(game: Game, c: Dictionary) -> void:
	if not game.engine.hooks.veto("ai.think", {"game": game, "character": c}):
		return
	_manage_peace(game, c)
	if c.death != null:
		return
	_manage_armies(game, c)
	if Wars.wars_of(game, c.id).is_empty() and game.rng.chance(game.def_num("ai.war_check_chance", 0.35)):
		_consider_war(game, c)
	_consider_interactions(game, c)
	_consider_decisions(game, c)
	_consider_titles(game, c)
	_consider_building(game, c)


# ------------------------------------------------------------ война

static func _consider_war(game: Game, c: Dictionary) -> void:
	var p := personality(game, c)
	var targets := Wars.available_war_targets(game, c).filter(func(t): return Wars.can_afford_war(game, c, t))
	if targets.is_empty():
		return
	var my_str := Economy.military_strength(game, c)
	var best: Variant = null
	var best_score := 0.0
	for t in targets:
		var def: Dictionary = game.ch(t.defender)
		if game.is_player(def.id) and game.rng.chance(game.def_num("ai.spare_player_chance", 0)):
			continue
		var enemy_str := Economy.military_strength(game, def)
		var ratio := my_str / maxf(1.0, enemy_str)
		var need = game.def_num("ai.war_strength_ratio", 1.3) - Data.num(p.get("boldness")) * 0.02 - Data.num(p.get("aggression")) * 0.02
		if ratio < need:
			continue
		var cb: Variant = game.content.get_def("casus_belli", t.cb)
		var ctx := Decisions.context(game, c)
		ctx.scopes["defender"] = {"type": "character", "id": t.defender}
		if t.get("title") != null:
			ctx.scopes["target"] = {"type": "title", "id": t.title}
		var will = Interp.eval_value(ctx, ctx.root, cb.ai_will_do) if (cb != null and cb.get("ai_will_do") != null) else 50.0
		var score = will * minf(3.0, ratio) * (1.0 + t.counties.size() * 0.1)
		if score > 0.0 and (best == null or score > best_score):
			best = t
			best_score = score
	if best == null:
		return
	var chance = minf(0.9, game.def_num("ai.base_war_chance", 0.25) + (Data.num(p.get("aggression")) + Data.num(p.get("greed"))) * 0.03)
	if game.rng.chance(chance):
		Wars.declare_war(game, c, best)


static func _manage_peace(game: Game, c: Dictionary) -> void:
	for w in Wars.wars_of(game, c.id):
		if not game.state.wars.has(w.id):
			continue
		var side: Variant = Wars.participant_side(w, c.id)
		var leader: String = w.attacker if side == "att" else w.defender
		if leader != c.id:
			continue
		var ws: float = Wars.warscore(game, w).total
		var mine = ws if side == "att" else -ws
		var enemy_leader: String = w.defender if side == "att" else w.attacker
		var other = "def" if side == "att" else "att"
		if mine >= 100.0:
			Wars.end_war(game, w, "victory" if side == "att" else "defeat")
			return
		if game.is_player(enemy_leader):
			if mine <= -game.def_num("ai.surrender_to_player_at", 90):
				Wars.end_war(game, w, "defeat" if side == "att" else "victory")
			continue
		if mine >= game.def_num("ai.enforce_at", 50) and Wars.ai_will_accept_surrender(game, w, other):
			Wars.end_war(game, w, "victory" if side == "att" else "defeat")
			return
		if Wars.ai_will_accept_white_peace(game, w, side) and Wars.ai_will_accept_white_peace(game, w, other):
			Wars.end_war(game, w, "white_peace")
			return


static func _manage_armies(game: Game, c: Dictionary) -> void:
	var at_war = not Wars.wars_of(game, c.id).is_empty()
	var armies = Military.armies_of(game, c.id)
	if at_war and armies.is_empty():
		Military.raise_army(game, c)
	if not at_war:
		for a in armies:
			Military.disband_army(game, a.id)


## Сила армии для оценок ИИ (без учёта контр), кэшируется на день.
static func _cached_strength(game: Game, a: Dictionary) -> float:
	return game.cached_daily("army:" + a.id, func(): return Military.army_strength(game, a))


## Ежедневно: армии ИИ выбирают цель — вражескую армию послабее или осаду.
static func army_ai(game: Game, a: Dictionary) -> void:
	if a.get("retreating", false):
		return
	if not a.path.is_empty() and a.get("ai_replan") != null and a.ai_replan > game.date:
		return
	var wars = Wars.wars_of(game, a.owner)
	if wars.is_empty():
		return
	var p: Variant = game.state.provinces.get(a.location)
	if a.path.is_empty() and p != null and p.siege != null and p.siege.army == a.id:
		return # продолжаем осаду
	a.ai_replan = game.date + 10

	var best_dest: Variant = null
	var best_score := -INF
	var my_leader: Dictionary = game.ch(a.owner)
	var my_top := Titles.top_liege(game, my_leader)
	var my_str := _cached_strength(game, a)
	for w in wars:
		var side: String = Wars.participant_side(w, a.owner)
		# Вражеские армии
		for e in game.state.armies.values():
			var es: Variant = Wars.participant_side(w, e.owner)
			if es == null or es == side or e.get("retreating", false):
				continue
			var len = game.engine.path_length(a.location, e.location)
			if is_inf(len) or len > 6 * 80:
				continue
			var ratio := my_str / maxf(1.0, _cached_strength(game, e))
			if ratio > 1.15:
				var sc = 120.0 * minf(2.0, ratio) - (len / 80.0) * 8.0
				if sc > best_score:
					best_score = sc
					best_dest = e.location
		# Осады: цели войны в приоритете, затем любые вражеские графства
		var enemy_leaders: Array = w.defenders if side == "att" else w.attackers
		var tset := {}
		for x in w.target_counties:
			tset[x] = true
		var cand := {}
		for id in enemy_leaders:
			var chd: Variant = game.ch(id)
			if chd != null:
				for cty in Titles.realm_counties(game, chd):
					cand[cty] = true
		# Освобождение своих земель
		for cty in Titles.realm_counties(game, my_top):
			var pp: Variant = game.state.provinces.get(cty)
			if pp != null and pp.occupant_war == w.id:
				cand[cty] = true
		for cty in cand:
			var ctrl: Variant = Titles.province_controller(game, cty)
			if ctrl == null:
				continue
			var theirs: Variant = Wars.side_of(game, w, ctrl.id)
			var pst: Variant = game.state.provinces.get(cty)
			var occupied_by_us: bool = pst != null and pst.occupant_war == w.id and Wars.participant_side(w, pst.occupant) == side
			if theirs == side and (pst == null or pst.occupant == null):
				continue
			if occupied_by_us:
				continue
			var len = game.engine.path_length(a.location, cty)
			if is_inf(len):
				continue
			var liberation: bool = theirs == side
			var is_my_capital: bool = cty == my_leader.capital or cty == my_top.capital
			var score = (70.0 if is_my_capital else 20.0) if liberation else (80.0 if tset.has(cty) else 40.0)
			score -= (len / 80.0) * 6.0
			# не лезем в провинцию, где стоит вражеская армия сильнее нас
			for e in game.state.armies.values():
				if e.location != cty:
					continue
				var es2: Variant = Wars.participant_side(w, e.owner)
				if es2 != null and es2 != side and _cached_strength(game, e) > my_str * 0.9:
					score -= 200.0
					break
			if score > best_score:
				best_score = score
				best_dest = cty
	if best_dest == null:
		return
	if best_dest == a.location:
		a.path = []
		return
	if a.get("ai_target") != best_dest or a.path.is_empty():
		Military.move_army(game, a.id, best_dest)
		a.ai_target = best_dest


# ------------------------------------------------------------ взаимодействия

static func _ai_targets(game: Game, c: Dictionary, def: Dictionary, cache: Dictionary) -> Array:
	var out := {}
	var ctx := Interactions.context(game, def, c, c)
	for lname in Data.as_array(def.get("ai_targets")):
		var lst: Variant = game.engine.scripting.lists.get_item(str(lname))
		if lst == null:
			continue
		# Один и тот же список (соседи, вассалы…) за ход правителя считаем один раз.
		if not cache.has(lname):
			cache[lname] = lst.list.call(ctx, ctx.root)
		for r in cache[lname]:
			if r.type != "character":
				continue
			var x: Variant = game.ch(r.id)
			if x != null and Chars.is_alive(x) and x.id != c.id:
				out[x.id] = x
	if def.get("self", false):
		out[c.id] = c
	var arr := out.values()
	game.rng.shuffle(arr)
	return arr.slice(0, int(game.def_num("ai.max_targets_per_interaction", 12)))


static func _consider_interactions(game: Game, c: Dictionary) -> void:
	var defs := Interactions.defs(game).filter(func(d): return d.get("ai_will_do") != null and (d.get("ai_targets") != null or d.get("self", false)))
	var list_cache := {}
	for def in defs:
		var freq := Data.num(def.get("ai_frequency_months"), 6)
		if not game.rng.chance(1.0 / freq):
			continue
		var best: Variant = null
		for r in _ai_targets(game, c, def, list_cache):
			if not Interactions.is_shown(game, def, c, r):
				continue
			var secs: Array = [null]
			if def.get("secondary_actor") != null:
				secs = Interactions.secondary_candidates(game, def, c, r).slice(0, 4).map(func(x): return x.id)
			var targs: Array = [null]
			if def.get("target") != null:
				targs = Interactions.target_options(game, def, c, r).slice(0, 4)
			for sec in secs:
				for t in targs:
					var args = {"secondary": sec, "target": t.get("ref") if t != null else null}
					if not Interactions.blockers(game, def, c, r, args).is_empty():
						continue
					var ctx := Interactions.context(game, def, c, r, args)
					var will = Interp.eval_value(ctx, ctx.root, def.ai_will_do)
					if will <= 0.0:
						continue
					# Не предлагаем то, на что заведомо откажут (кроме игрока — тот решает сам),
					# если только нет крюка, которым можно заставить согласиться.
					var decider := Interactions.decider_of(game, def, r)
					if not game.is_player(decider.id):
						var acc := Interactions.acceptance(game, def, c, r, args)
						if not acc.auto and acc.total <= 0.0:
							if not Interactions.hook_available(game, def, c, r) or will < game.def_num("ai.use_hook_min_will", 30):
								continue
							args["use_hook"] = true
					elif Interactions.hook_available(game, def, c, r) and will >= game.def_num("ai.use_hook_on_player_min_will", 60):
						args["use_hook"] = true
					if best == null or will > best.score:
						best = {"r": r, "args": args, "score": will}
		if best != null and game.rng.next() * 100.0 < minf(game.def_num("ai.max_interaction_chance", 90), best.score):
			Interactions.execute(game, def, c, best.r, best.args)
	_arrange_marriages(game, c)


## Отдельная эвристика для браков членов семьи и двора — самая частая задача ИИ.
static func _arrange_marriages(game: Game, c: Dictionary) -> void:
	var def: Variant = game.content.get_def("interactions", "arrange_marriage")
	if def == null or not game.rng.chance(game.def_num("ai.marriage_chance", 0.5)):
		return
	var family = (game.courtiers_of(c.id) + [c]).filter(func(x):
		return Chars.is_alive(x) and Chars.is_adult(game, x) and x.spouses.is_empty() and (x.id == c.id or x.dynasty == c.dynasty or x.father == c.id))
	if family.is_empty():
		return
	var single: Dictionary = game.rng.pick(family)
	var candidates := []
	for r in game.rulers():
		if r.id == c.id:
			continue
		for x in [r] + game.courtiers_of(r.id):
			if Chars.is_alive(x) and not game.is_player(x.id) and Chars.can_marry(game, single, x):
				candidates.append(x)
	game.rng.shuffle(candidates)
	for recipient in candidates.slice(0, 15):
		if not Interactions.is_shown(game, def, c, recipient):
			continue
		var args = {"secondary": single.id}
		if not Interactions.blockers(game, def, c, recipient, args).is_empty():
			continue
		var acc := Interactions.acceptance(game, def, c, recipient, args)
		if acc.auto or acc.total > 0.0:
			Interactions.execute(game, def, c, recipient, args)
			return


static func _consider_decisions(game: Game, c: Dictionary) -> void:
	for def in game.content.all("decisions"):
		if def.get("ai_will_do") == null:
			continue
		if not game.rng.chance(1.0 / Data.num(def.get("ai_check_months"), 6)):
			continue
		if not Decisions.is_shown(game, def, c) or not Decisions.blockers(game, def, c).is_empty():
			continue
		var ctx := Decisions.context(game, c)
		if game.rng.next() * 100.0 < Interp.eval_value(ctx, ctx.root, def.ai_will_do):
			Decisions.take(game, def, c)


static func _consider_titles(game: Game, c: Dictionary) -> void:
	if not game.rng.chance(0.25):
		return
	var candidates := {}
	for cty in Titles.realm_counties(game, c).slice(0, 40):
		var td: Variant = game.content.get_def("titles", cty)
		var t: Variant = td.get("liege") if td != null else null
		while t != null:
			var st: Variant = game.state.titles.get(t)
			if st != null and st.holder == null:
				candidates[t] = true
			var d: Variant = game.content.get_def("titles", t)
			t = d.get("liege") if d != null else null
	for t in candidates:
		if Titles.can_create_title(game, c, t).ok:
			Titles.create_title(game, c, t)


static func _consider_building(game: Game, c: Dictionary) -> void:
	var reserve = game.def_num("ai.gold_reserve", 60)
	if c.gold < reserve:
		return
	if not game.rng.chance(game.def_num("ai.build_chance", 0.3)):
		return
	var opts := Decisions.domain_build_options(game, c).filter(func(o):
		var cost: Variant = o.def.get("cost")
		return (Data.num(cost.get("gold")) if cost is Dictionary else 0.0) + reserve <= c.gold)
	var pick: Variant = game.rng.pick(opts)
	if pick != null:
		Decisions.start_building(game, c, pick.province, pick.def.id)


## ИИ игрока-вассала: держит ли он сторону сюзерена (используется модами).
static func is_loyal(game: Game, c: Dictionary) -> bool:
	var l: Variant = game.ch(c.liege)
	return l != null and Titles.is_in_realm_of(game, c, l)


static func war_for_ai(game: Game, id: String) -> Variant:
	var ws := Wars.wars_of(game, id)
	return ws[0] if not ws.is_empty() else null

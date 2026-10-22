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


static func _think_hash(c: Dictionary) -> int:
	var h := 0
	var id: String = c.id
	for i in id.length():
		h = (h * 31 + id.unicode_at(i)) & 0xFFFFFFFF
	if h >= 0x80000000:
		h -= 0x100000000
	return absi(h)


static func _think_day(c: Dictionary) -> int:
	var h := 0
	var id: String = c.id
	for i in id.length():
		h = (h * 31 + id.unicode_at(i)) & 0xFFFFFFFF
	if h >= 0x80000000:
		h -= 0x100000000
	return absi(h) % 28


static func daily_ai(game: Game) -> void:
	# Независимые правители думают раз в 4 недели, вассалы — раз в 8 (их решения
	# реже влияют на мир, а нагрузка на ИИ так снижается почти вдвое).
	var period := int(game.def_num("ai.think_days", 28))
	var vassal_period := int(game.def_num("ai.vassal_think_days", 56))
	var day := game.date % 365
	for c in game.rulers():
		if not game.ai_controls(c.id) or c.death != null:
			continue
		var per := period if c.liege == null else vassal_period
		if _think_hash(c) % per != day % per:
			continue
		think_ruler(game, c)
	for a in game.state.armies.values():
		if not game.ai_controls(a.owner) or not game.state.armies.has(a.id):
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
	var targets := Wars.available_war_targets(game, c)
	if targets.is_empty():
		return
	var my_str := Economy.military_strength(game, c)
	var need = game.def_num("ai.war_strength_ratio", 1.3) - Data.num(p.get("boldness")) * 0.02 - Data.num(p.get("aggression")) * 0.02
	var best: Variant = null
	var best_score := 0.0
	for t in targets:
		var def: Dictionary = game.ch(t.defender)
		# Сначала дешёвое (соотношение сил), потом цена войны и желание.
		var ratio := my_str / maxf(1.0, Economy.military_strength(game, def))
		if ratio < need or not Wars.can_afford_war(game, c, t):
			continue
		if game.is_player(def.id) and game.rng.chance(game.def_num("ai.spare_player_chance", 0)):
			continue
		var cb: Variant = game.content.get_def("casus_belli", t.cb)
		var ctx := Decisions.context(game, c)
		ctx.scopes["defender"] = {"type": "character", "id": t.defender}
		if t.get("title") != null:
			ctx.scopes["target"] = {"type": "title", "id": t.title}
		var will = Interp.eval_value(ctx, ctx.root, cb.ai_will_do) if (cb != null and cb.get("ai_will_do") != null) else 50.0
		# правление цели может отпугивать единоверцев (Храм: ai_attacked_mult) —
		# еретику и иноверцу святыня не указ
		if game.engine.has_feature("governments"):
			var am := Data.num(Governments.rule(game, def, "ai_attacked_mult", 1.0), 1.0)
			if am != 1.0 and not Wars.is_heretic(game, c) and Wars._religion(game, c.faith) == Wars._religion(game, def.faith):
				will *= am
		# механики и моды сдвигают желание войны (ai.war_will — множители; Божий мир Собора)
		for m in game.engine.hooks.collect("ai.war_will", {"game": game, "attacker": c, "defender": def, "cb": t.cb}):
			will *= Data.num(m, 1.0)
		var score = will * minf(3.0, ratio) * (1.0 + t.counties.size() * 0.1)
		if score > 0.0 and (best == null or score > best_score):
			best = t
			best_score = score
	if best == null:
		return
	var chance = minf(0.9, game.def_num("ai.base_war_chance", 0.25) + (Data.num(p.get("aggression")) + Data.num(p.get("greed"))) * 0.03)
	if game.engine.has_feature("personality"):
		# робким и довольным война в тягость (стресс → меньше шанс)
		chance += Personality.ai_will_shift(game, c, "declare_war") * 0.01
	# правление: республика воюет неохотно
	if game.engine.has_feature("governments"):
		chance *= Data.num(Governments.rule(game, c, "ai_war_mult", 1.0), 1.0)
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
		if not game.ai_controls(enemy_leader):
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


## Армии по провинциям (на день; набор армий меняется — кэш сбрасывается).
static func _armies_by_location(game: Game) -> Dictionary:
	return game.cached_daily("ai:armies_by_loc", func():
		var m := {}
		for e in game.state.armies.values():
			if not m.has(e.location):
				m[e.location] = []
			m[e.location].append(e)
		return m)


## Графства для осады в войне w для стороны side (и освобождение земель
## державы top): [{id, liberation, war_target}]. Не зависит от конкретной
## армии, поэтому считается раз в день на войну, сторону и сюзерена.
static func _siege_targets(game: Game, w: Dictionary, side: String, top: Dictionary) -> Array:
	return game.cached_daily("ai:sieges:%s:%s:%s" % [w.id, side, top.id], func():
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
		for cty in Titles.realm_counties(game, top):
			var pp: Variant = game.state.provinces.get(cty)
			if pp != null and pp.occupant_war == w.id:
				cand[cty] = true
		var out := []
		for cty in cand:
			var ctrl: Variant = Titles.province_controller(game, cty)
			if ctrl == null:
				continue
			var theirs: Variant = Wars.side_of(game, w, ctrl.id)
			var pst: Variant = game.state.provinces.get(cty)
			if theirs == side and (pst == null or pst.occupant == null):
				continue
			if pst != null and pst.occupant_war == w.id and Wars.participant_side(w, pst.occupant) == side:
				continue
			out.append({"id": cty, "liberation": theirs == side, "war_target": tset.has(cty)})
		return out)


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
	var by_loc := _armies_by_location(game)
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
		for t in _siege_targets(game, w, side, my_top):
			var cty: String = t.id
			var len = game.engine.path_length(a.location, cty)
			if is_inf(len):
				continue
			var is_my_capital: bool = cty == my_leader.capital or cty == my_top.capital
			var score = (70.0 if is_my_capital else 20.0) if t.liberation else (80.0 if t.war_target else 40.0)
			score -= (len / 80.0) * 6.0
			if score <= best_score:
				continue
			# не лезем в провинцию, где стоит вражеская армия сильнее нас
			for e in by_loc.get(cty, []):
				var es2: Variant = Wars.participant_side(w, e.owner)
				if es2 != null and es2 != side and game.state.armies.has(e.id) and _cached_strength(game, e) > my_str * 0.9:
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


static func _ai_interaction_defs(game: Game) -> Array:
	var cached: Variant = game.engine.cache.get("ai_interaction_defs")
	if cached == null:
		cached = Interactions.defs(game).filter(func(d): return d.get("ai_will_do") != null and (d.get("ai_targets") != null or d.get("self", false)))
		game.engine.cache["ai_interaction_defs"] = cached
	return cached


static func _consider_interactions(game: Game, c: Dictionary) -> void:
	var list_cache := {}
	var has_personality := game.engine.has_feature("personality")
	for def in _ai_interaction_defs(game):
		var freq := Data.num(def.get("ai_frequency_months"), 6)
		if not game.rng.chance(1.0 / freq):
			continue
		# условия самого действующего лица — один раз, а не на каждую цель
		if not Interactions.actor_passes(game, def, c):
			continue
		# ai_potential: стоит ли ИИ вообще об этом думать (только действующее лицо)
		var pot: Variant = def.get("ai_potential")
		if pot != null:
			var pctx := Interactions.context(game, def, c, c)
			if not Interp.eval_trigger(pctx, pctx.root, pot):
				continue
		# характер: претящее делается реже, то, что по душе, — охотнее
		var shift := Personality.ai_will_shift(game, c, str(def.get("scheme", def.id))) if has_personality else 0.0
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
			# Желание, не зависящее от цели и второго участника, считаем раз на получателя.
			var per_recipient := not _will_uses_args(game, def)
			var cached_will: Variant = null
			for sec in secs:
				for t in targs:
					var args = {"secondary": sec, "target": t.get("ref") if t != null else null}
					# Сначала желание (обычно дешевле и чаще всего отсекает), затем условия.
					var ctx := Interactions.context(game, def, c, r, args)
					var will = cached_will if cached_will != null else Interp.eval_value(ctx, ctx.root, def.ai_will_do)
					if per_recipient:
						cached_will = will
					will += shift
					if will <= 0.0 or (best != null and will <= best.score):
						continue
					if not Interactions.blockers(game, def, c, r, args).is_empty():
						continue
					# Не предлагаем то, на что заведомо откажут (кроме игрока — тот решает сам),
					# если только нет крюка, которым можно заставить согласиться. Исключение —
					# ai_send_if_declined: сам отказ чего-то стоит (вызов на поединок).
					var decider := Interactions.decider_of(game, def, r)
					if game.ai_controls(decider.id) and not ScriptContext.is_yes(def.get("ai_send_if_declined", false)):
						var acc := Interactions.acceptance(game, def, c, r, args)
						if not acc.auto and acc.total <= 0.0:
							if not Interactions.hook_available(game, def, c, r) or will < game.def_num("ai.use_hook_min_will", 30):
								continue
							args["use_hook"] = true
					elif Interactions.hook_available(game, def, c, r) and will >= game.def_num("ai.use_hook_on_player_min_will", 60):
						args["use_hook"] = true
					best = {"r": r, "args": args, "score": will}
		if best != null and game.rng.next() * 100.0 < minf(game.def_num("ai.max_interaction_chance", 90), best.score) \
				and can_spend(game, c, Interactions.cost(game, def, Interactions.context(game, def, c, best.r, best.args)).gold):
			Interactions.execute(game, def, c, best.r, best.args)
	_arrange_marriages(game, c)


## Ссылается ли ai_will_do взаимодействия на цель или второго участника
## (иначе его можно считать один раз на получателя).
static func _will_uses_args(game: Game, def: Dictionary) -> bool:
	var key := "ai:will_args:" + str(def.id)
	var hit: Variant = game.engine.cache.get(key)
	if hit == null:
		var src := var_to_str(def.get("ai_will_do"))
		hit = src.contains("target") or src.contains("secondary")
		# скриптовые значения и условия могут ссылаться на цель внутри — не рискуем
		for kind in ["scripted_values", "scripted_triggers"]:
			for d in game.content.all(kind):
				if src.contains(str(d.id)):
					hit = true
		game.engine.cache[key] = hit
	return hit


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
	# Кандидаты: случайные свободные взрослые другого пола (кроме своего двора),
	# пока не наберётся 15 подходящих. Список свободных — на месяц.
	var pool: Dictionary = game.cached_monthly("ai:marriage_pool", func():
		var m := {true: [], false: []}
		for x in game.living():
			if x.get("prison") == null and not game.is_player(x.id) and Chars.is_adult(game, x) \
					and (x.spouses.is_empty() or Chars._polygamy(game, x)):
				m[x.female].append(x)
		return m)
	var opp: Array = pool[not single.female]
	var candidates := []
	for i in mini(opp.size(), 80):
		var x: Dictionary = opp[game.rng.range_int(0, opp.size() - 1)]
		if x.id == c.id or (x.titles.is_empty() and x.liege == c.id) or candidates.has(x):
			continue
		if Chars.can_marry(game, single, x):
			candidates.append(x)
			if candidates.size() >= 15:
				break
	game.rng.shuffle(candidates)
	for recipient in candidates.slice(0, 15):
		if not Interactions.is_shown(game, def, c, recipient):
			continue
		var args = {"secondary": single.id}
		var acc := Interactions.acceptance(game, def, c, recipient, args)
		if not acc.auto and acc.total <= 0.0:
			continue
		if not Interactions.blockers(game, def, c, recipient, args).is_empty():
			continue
		Interactions.execute(game, def, c, recipient, args)
		return


## Решения для ИИ: [одиночные, {группа: [решения]}] — решения с ai_group ИИ
## обдумывает вместе, одной проверкой (например, пути архетипов).
static func _ai_decision_defs(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("ai:decisions")
	if hit == null:
		var single := []
		var groups := {}
		for def in game.content.all("decisions"):
			if def.get("ai_will_do") == null:
				continue
			var grp: Variant = def.get("ai_group")
			if grp == null:
				single.append(def)
			else:
				if not groups.has(grp):
					groups[grp] = []
				groups[grp].append(def)
		hit = [single, groups]
		game.engine.cache["ai:decisions"] = hit
	return hit


static func _consider_decisions(game: Game, c: Dictionary) -> void:
	var has_personality := game.engine.has_feature("personality")
	# один контекст на все проверки; сохранённые условиями скоупы сбрасываются
	var ctx := Decisions.context(game, c)
	var base_scopes := ctx.scopes.duplicate()
	var split := _ai_decision_defs(game)
	# группа: раз в ai_check_months первого решения — выбор по весу из доступных
	for grp in split[1]:
		var defs: Array = split[1][grp]
		if not game.rng.chance(1.0 / Data.num(defs[0].get("ai_check_months"), 6)):
			continue
		# ai_potential первого решения — общее условие группы, один раз
		if defs[0].get("ai_potential") != null and not Interp.eval_trigger(ctx, ctx.root, defs[0].ai_potential):
			continue
		var cands := []
		for def in defs:
			if ctx.scopes.size() != base_scopes.size() or not ctx.values.is_empty():
				ctx = Decisions.context(game, c)
			if not Decisions.is_shown(game, def, c, ctx) or not Decisions.can_take(game, def, c, ctx):
				continue
			var w := Interp.eval_value(ctx, ctx.root, def.ai_will_do)
			if has_personality:
				w += Personality.ai_will_shift(game, c, str(def.id))
			if w > 0.0:
				cands.append([def, w])
		var pick: Variant = game.rng.weighted(cands, func(x): return x[1])
		if pick != null and game.rng.next() * 100.0 < pick[1] and can_spend(game, c, Decisions.cost(game, pick[0], c).gold):
			Decisions.take(game, pick[0], c)
	for def in split[0]:
		var months := Data.num(def.get("ai_check_months"), 6)
		if not game.rng.chance(1.0 / months):
			continue
		if ctx.scopes.size() != base_scopes.size() or not ctx.values.is_empty():
			ctx = Decisions.context(game, c)
		if def.get("ai_potential") != null and not Interp.eval_trigger(ctx, ctx.root, def.ai_potential):
			continue
		if not Decisions.is_shown(game, def, c, ctx) or not Decisions.can_take(game, def, c, ctx):
			continue
		var will := Interp.eval_value(ctx, ctx.root, def.ai_will_do)
		if has_personality:
			will += Personality.ai_will_shift(game, c, str(def.id))
		if game.rng.next() * 100.0 < will and can_spend(game, c, Decisions.cost(game, def, c).gold):
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
	# копилка: есть цель — копим на неё, а набрав — строим
	var gl: Variant = goal_of(game, c)
	if gl != null:
		var stale: bool = game.date - int(gl.get("since", game.date)) > roundi(game.def_num("ai.goal_months", 48) * 30.4)
		if stale or not _goal_ok(game, c, gl):
			c.vars.erase("ai_goal")
		else:
			if float(c.gold) >= float(gl.cost) + reserve and _start_goal(game, c, gl):
				c.vars.erase("ai_goal")
			return
	var income := Economy.monthly_income(game, c)
	if c.gold < reserve and income <= 0.0:
		return
	# богатый строит охотнее: золото не должно лежать мёртвым грузом
	var rich := game.def_num("ai.rich_gold", 400)
	var chance := game.def_num("ai.build_chance", 0.3) * (1.0 + maxf(0.0, float(c.gold) - rich) / rich)
	if not game.rng.chance(minf(1.0, chance)):
		return
	# выбор — из досягаемого: что по карману сейчас или за ai.save_months дохода
	var reach := float(c.gold) + maxf(0.0, income) * game.def_num("ai.save_months", 24)
	var opts := Decisions.domain_build_options(game, c, true).filter(func(o): return float(o.cost.gold) + reserve <= reach)
	# вес постройки — её ai_will_do (root — строитель, scope:province), по умолчанию 10
	for o in opts:
		var ai: Variant = o.def.get("ai_will_do")
		if ai == null:
			o["weight"] = 10.0
		else:
			var actx := ScriptContext.make(game, {"type": "character", "id": c.id}, {"province": {"type": "province", "id": o.province}})
			o["weight"] = Interp.eval_value(actx, actx.root, ai)
	# районы: заложить новый или поднять тесный (Districts.domain_options)
	for o in Districts.domain_options(game, c, reach - reserve):
		opts.append(o)
	# долгое ожидание немного отбивает охоту: лучше то, что ближе
	for o in opts:
		var wait := maxf(0.0, float(o.cost.gold) + reserve - float(c.gold)) / maxf(0.5, income)
		o.weight = float(o.weight) / (1.0 + wait / 24.0)
	var pick: Variant = game.rng.weighted(opts, func(o): return o.weight)
	if pick == null:
		return
	var goal := {"kind": "district" if pick.has("level") else "building", "id": str(pick.def.id), "province": str(pick.province),
		"level": int(pick.get("level", 0)), "cost": float(pick.cost.gold), "since": game.date}
	if float(pick.cost.gold) + reserve <= float(c.gold):
		_start_goal(game, c, goal)
	else:
		c.vars["ai_goal"] = goal


# ------------------------------------------------------------ копилка
# ИИ копит на стройку, которая ему нужна, а не берёт самое дешёвое из того,
# что по карману. Пока копит, прочие крупные траты (решения, предложения,
# найм отрядов, заказ вещей) не трогают отложенное — мелочь можно.

## Цель копилки: {kind: building|district, id, province, level, cost, since} или null.
static func goal_of(_game: Game, c: Dictionary) -> Variant:
	var gl: Variant = c.vars.get("ai_goal")
	return gl if gl is Dictionary else null


static func goal_name(game: Game, gl: Dictionary) -> String:
	var what := game.name_of("buildings", str(gl.id)) if gl.kind == "building" \
		else "%s %s" % [game.name_of("districts", str(gl.id)), Districts.roman(int(gl.level))]
	return "%s (%s)" % [what, game.name_of("provinces", str(gl.province))]


## Может ли ИИ потратить amount, не трогая отложенного на цель. Мелочь — до
## ai.petty_spend или двух месячных доходов — можно всегда.
static func can_spend(game: Game, c: Dictionary, amount: float) -> bool:
	if amount <= 0.0:
		return true
	var gl: Variant = goal_of(game, c)
	if gl == null or float(c.gold) - amount >= float(gl.cost):
		return true
	return amount <= maxf(game.def_num("ai.petty_spend", 10), Economy.monthly_income(game, c) * 2.0)


## Цель ещё достижима (графство в домене, не захвачено, постройка не стоит,
## мешает только цена). Пока в графстве идёт другая стройка — ждём.
static func _goal_ok(game: Game, c: Dictionary, gl: Dictionary) -> bool:
	var pid := str(gl.province)
	var p: Variant = game.state.provinces.get(pid)
	if p == null or p.occupant != null or not Titles.domain_counties(game, c).has(pid):
		return false
	if gl.kind == "district":
		return Districts.on(game) and Districts.level(game, pid, str(gl.id)) == int(gl.level) - 1
	if p.buildings.has(gl.id):
		return false
	if p.construction != null:
		return true
	for x in Decisions.building_candidates(game, c, pid):
		if x.def.id == gl.id:
			if x.blockers.is_empty() or x.cost_only:
				gl.cost = float(x.cost.gold)
				return true
			return false
	return false


static func _start_goal(game: Game, c: Dictionary, gl: Dictionary) -> bool:
	if gl.kind == "district":
		return Districts.start(game, c, str(gl.province), str(gl.id))
	return Decisions.start_building(game, c, str(gl.province), str(gl.id))


## ИИ игрока-вассала: держит ли он сторону сюзерена (используется модами).
static func is_loyal(game: Game, c: Dictionary) -> bool:
	var l: Variant = game.ch(c.liege)
	return l != null and Titles.is_in_realm_of(game, c, l)


static func war_for_ai(game: Game, id: String) -> Variant:
	var ws := Wars.wars_of(game, id)
	return ws[0] if not ws.is_empty() else null

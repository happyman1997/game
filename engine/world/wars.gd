class_name Wars
extends RefCounted
## Войны. Поводы к войне (casus_belli) описываются в данных; список
## возможных целей для каждого повода даёт «поставщик целей» из
## engine.cb_targets — мод может добавить новый тип войны.
##
## Цель войны: {cb, defender, title?, counties: Array}.
## Поставщик целей: {label?, targets: Callable(game, attacker) -> Array[{defender, title?, counties}]}.


static func wars_of(game: Game, id: String) -> Array:
	return game.state.wars.values().filter(func(w): return w.attackers.has(id) or w.defenders.has(id))


static func is_at_war(game: Game, id: String) -> bool:
	for w in game.state.wars.values():
		if w.attackers.has(id) or w.defenders.has(id):
			return true
	return false


## "att", "def" или null.
static func participant_side(w: Dictionary, id: Variant) -> Variant:
	if id == null:
		return null
	if w.attackers.has(id):
		return "att"
	if w.defenders.has(id):
		return "def"
	return null


## Сторона персонажа в войне — как участника или как вассала участника.
static func side_of(game: Game, w: Dictionary, id: Variant) -> Variant:
	var cur: Variant = game.ch(id)
	for i in 30:
		if cur == null:
			return null
		var s: Variant = participant_side(w, cur.id)
		if s != null:
			return s
		cur = game.ch(cur.liege)
	return null


static func county_side(game: Game, w: Dictionary, county_id: String) -> Variant:
	var p: Variant = game.state.provinces.get(county_id)
	if p != null and p.occupant != null and p.occupant_war == w.id:
		var s: Variant = participant_side(w, p.occupant)
		return s if s != null else side_of(game, w, p.occupant)
	return side_of(game, w, game.state.titles[county_id].holder if game.state.titles.has(county_id) else null)


static func is_at_war_with(game: Game, a: String, b: String) -> bool:
	for w in wars_of(game, a):
		var sa: Variant = participant_side(w, a)
		var sb: Variant = participant_side(w, b)
		if sa != null and sb != null and sa != sb:
			return true
	return false


static func enemies_of(game: Game, id: String) -> Array:
	var out := {}
	for w in wars_of(game, id):
		var s: Variant = participant_side(w, id)
		for e in (w.defenders if s == "att" else w.attackers):
			out[e] = true
	return out.keys()


static func has_truce(game: Game, a: String, b: String) -> bool:
	for t in game.state.truces:
		if t.until > game.date and ((t.a == a and t.b == b) or (t.a == b and t.b == a)):
			return true
	return false


static func allies_of(game: Game, id: String) -> Array:
	var out := []
	for al in game.state.alliances:
		var other: Variant = al.b if al.a == id else (al.a if al.b == id else null)
		if other != null and game.is_alive(other):
			out.append(other)
	return out


static func is_allied(game: Game, a: String, b: String) -> bool:
	for al in game.state.alliances:
		if (al.a == a and al.b == b) or (al.a == b and al.b == a):
			return true
	return false


# ------------------------------------------------------------ цели войны

static func _holder(game: Game, title_id: String) -> Variant:
	var t: Variant = game.state.titles.get(title_id)
	return game.ch(t.holder) if t != null else null


static func builtin_cb_targets() -> Dictionary:
	return {
		"claim": {"targets": func(game: Game, attacker: Dictionary) -> Array:
			var out := []
			var my_top := Titles.top_liege(game, attacker)
			for t in attacker.claims:
				var h: Variant = _holder(game, t)
				if h == null or not Chars.is_alive(h) or h.id == attacker.id:
					continue
				if Titles.top_liege(game, h).id == my_top.id:
					continue
				var realm := {}
				for x in Titles.realm_counties(game, h):
					realm[x] = true
				var counties := Titles.de_jure_counties(game, t).filter(func(c): return realm.has(c))
				out.append({"defender": h.id, "title": t, "counties": counties if not counties.is_empty() else Titles.domain_counties(game, h)})
			return out},
		"de_jure": {"targets": func(game: Game, attacker: Dictionary) -> Array:
			var out := []
			var mine := {}
			for x in Titles.realm_counties(game, attacker):
				mine[x] = true
			var my_top := Titles.top_liege(game, attacker)
			var duchies := {}
			for t in attacker.titles:
				var tr := Titles.tier_of(game, t)
				if tr == 2:
					duchies[t] = true
				if tr >= 3:
					var stack := [t]
					while not stack.is_empty():
						var x: String = stack.pop_back()
						for chd in Titles.de_jure_vassal_titles(game, x):
							var r := Titles.tier_of(game, chd)
							if r == 2:
								duchies[chd] = true
							elif r > 2:
								stack.append(chd)
			for d in duchies:
				var by_defender := {}
				for c in Titles.de_jure_counties(game, d):
					if mine.has(c):
						continue
					var h: Variant = _holder(game, c)
					if h == null:
						continue
					var def := Titles.top_liege(game, h)
					if def.id == my_top.id or def.id == attacker.id:
						continue
					if not by_defender.has(def.id):
						by_defender[def.id] = []
					by_defender[def.id].append(c)
				for defender in by_defender:
					out.append({"defender": defender, "title": d, "counties": by_defender[defender]})
			return out},
		"independence": {"targets": func(game: Game, attacker: Dictionary) -> Array:
			if attacker.liege == null or attacker.titles.is_empty():
				return []
			var l: Variant = game.ch(attacker.liege)
			if l == null or not Chars.is_alive(l):
				return []
			return [{"defender": l.id, "title": attacker.titles[0], "counties": Titles.realm_counties(game, attacker)}]},
		"adjacent_county": {"targets": func(game: Game, attacker: Dictionary) -> Array:
			if attacker.liege != null:
				return []
			var mine := {}
			for x in Titles.realm_counties(game, attacker):
				mine[x] = true
			var out := []
			var seen := {}
			for c in mine:
				for n in game.engine.neighbors(c):
					if mine.has(n) or seen.has(n):
						continue
					seen[n] = true
					var h: Variant = _holder(game, n)
					if h == null:
						continue
					var def := Titles.top_liege(game, h)
					if def.id == attacker.id:
						continue
					out.append({"defender": def.id, "title": n, "counties": [n]})
			return out},
		"holy_war": {"targets": func(game: Game, attacker: Dictionary) -> Array:
			if attacker.liege != null:
				return []
			var out := []
			var mine := Titles.realm_counties(game, attacker)
			var mine_set := {}
			for x in mine:
				mine_set[x] = true
			var border := {}
			for c in mine:
				for n in game.engine.neighbors(c):
					if not mine_set.has(n):
						border[n] = true
			var seen := {}
			for c in border:
				var h: Variant = _holder(game, c)
				if h == null:
					continue
				var def := Titles.top_liege(game, h)
				if def.faith == attacker.faith or def.id == attacker.id:
					continue
				var td: Variant = game.content.get_def("titles", c)
				var duchy: Variant = td.get("liege") if td != null else null
				var key = "%s:%s" % [def.id, duchy if duchy != null else c]
				if seen.has(key):
					continue
				seen[key] = true
				var realm := {}
				for x in Titles.realm_counties(game, def):
					realm[x] = true
				var counties = (Titles.de_jure_counties(game, duchy) if duchy != null else [c]).filter(func(x): return realm.has(x))
				out.append({"defender": def.id, "title": duchy if duchy != null else c, "counties": counties})
			return out},
	}


static func cb_context(game: Game, attacker: String, t: Dictionary, war_id: Variant = null, extra: Variant = null) -> ScriptContext:
	var scopes: Dictionary = extra.duplicate() if extra is Dictionary else {}
	scopes["attacker"] = {"type": "character", "id": attacker}
	scopes["defender"] = {"type": "character", "id": t.defender}
	if t.get("title") != null:
		scopes["target"] = {"type": "title", "id": t.title}
	if war_id != null:
		scopes["war"] = {"type": "war", "id": war_id}
	return ScriptContext.make(game, {"type": "character", "id": attacker}, scopes)


## Все доступные персонажу поводы к войне (опционально — только против defender).
static func available_war_targets(game: Game, attacker: Dictionary, defender: Variant = null) -> Array:
	if attacker.titles.is_empty():
		return []
	var out := []
	for cb in game.content.all("casus_belli"):
		if cb.get("manual", false):
			continue # только из скриптов/механик (мятежи фракций)
		var prov: Variant = game.engine.cb_targets.get_item(str(cb.get("targets")))
		if prov == null:
			game.script_error("Нет поставщика целей войны \"%s\"" % cb.get("targets"))
			continue
		for t in prov.targets.call(game, attacker):
			if defender != null and t.defender != defender:
				continue
			if t.defender == attacker.id:
				continue
			if has_truce(game, attacker.id, t.defender) or is_at_war_with(game, attacker.id, t.defender):
				continue
			if game.state.wars.values().any(func(w): return w.attacker == attacker.id and w.defender == t.defender):
				continue
			var ctx = cb_context(game, attacker.id, t)
			if not Interp.eval_trigger(ctx, ctx.root, cb.get("is_valid")):
				continue
			var wt: Dictionary = t.duplicate()
			wt["cb"] = cb.id
			out.append(wt)
	return out


## {gold, prestige, piety}
static func war_cost(game: Game, attacker: Dictionary, t: Dictionary) -> Dictionary:
	var cb: Dictionary = game.content.get_def("casus_belli", t.cb)
	var ctx = cb_context(game, attacker.id, t)
	var cost: Dictionary = cb.get("cost", {}) if cb.get("cost") is Dictionary else {}
	return {
		"gold": roundf(Interp.eval_value(ctx, ctx.root, cost.get("gold", 0))),
		"prestige": roundf(Interp.eval_value(ctx, ctx.root, cost.get("prestige", 0))),
		"piety": roundf(Interp.eval_value(ctx, ctx.root, cost.get("piety", 0))),
	}


static func can_afford_war(game: Game, attacker: Dictionary, t: Dictionary) -> bool:
	return Economy.cost_blockers(game, attacker, war_cost(game, attacker, t)).is_empty()


## ИИ-союзник решает, вступать ли в войну: мнение о зовущем не ниже
## war.ally_min_opinion минус его ally_persuasion (дипломатия).
static func ally_will_join(game: Game, ally: Dictionary, leader: Dictionary, enemy: String) -> bool:
	if not Chars.is_alive(ally) or ally.titles.is_empty():
		return false
	if is_at_war_with(game, ally.id, leader.id) or ally.id == enemy:
		return false
	if game.is_player(ally.id):
		return true
	if is_allied(game, ally.id, enemy):
		return false
	return Opinion.opinion(game, ally, leader) >= game.def_num("war.ally_min_opinion", 0) - Stats.stat(game, leader, "ally_persuasion")


static func new_war_record() -> Dictionary:
	return {"id": "", "cb": "", "attacker": "", "defender": "", "attackers": [], "defenders": [], "target": null,
		"target_counties": [], "start": 0, "battle_score": 0.0, "ticking": 0.0, "name": null, "scopes": null, "faction": null}


## opts: free — без цены повода (мятежи, скрипты); attackers — дополнительные
## участники нападения; scopes — именованные скоупы войны (scope:claimant);
## faction — фракция, поднявшая мятеж.
static func declare_war(game: Game, attacker: Dictionary, t: Dictionary, opts: Dictionary = {}) -> Variant:
	var cb: Variant = game.content.get_def("casus_belli", t.cb)
	var defender: Variant = game.ch(t.defender)
	if cb == null or defender == null or not Chars.is_alive(defender):
		return null
	if not game.engine.hooks.veto("war.before_declare", {"game": game, "attacker": attacker, "target": t, "options": opts}):
		return null
	if not opts.get("free", false):
		var cost := war_cost(game, attacker, t)
		attacker.gold -= cost.gold
		attacker.prestige -= cost.prestige
		attacker.piety -= cost.piety
	var w := new_war_record()
	w.id = game.new_id("war")
	w.cb = t.cb
	w.attacker = attacker.id
	w.defender = defender.id
	w.attackers = [attacker.id]
	w.defenders = [defender.id]
	w.target = t.get("title")
	w.target_counties = t.counties.duplicate()
	w.start = game.date
	if opts.get("scopes") is Dictionary:
		w.scopes = opts.scopes.duplicate()
	if opts.get("faction") != null:
		w.faction = opts.faction
	for id in Data.as_array(opts.get("attackers")):
		if not w.attackers.has(id) and id != defender.id and game.is_alive(id):
			w.attackers.append(id)
	game.state.wars[w.id] = w
	var ctx = cb_context(game, attacker.id, t, w.id, w.scopes)
	w.name = game.text(cb.get("war_name", "ui.war_name_default"), ctx, {
		"attacker": game.scope_name({"type": "character", "id": attacker.id}),
		"defender": game.scope_name({"type": "character", "id": defender.id}),
		"target": game.scope_name({"type": "title", "id": t.title}) if t.get("title") != null else "",
	})
	for al in allies_of(game, attacker.id):
		if ally_will_join(game, game.ch(al), attacker, defender.id) and not w.defenders.has(al) and not w.attackers.has(al):
			w.attackers.append(al)
	for al in allies_of(game, defender.id):
		if ally_will_join(game, game.ch(al), defender, attacker.id) and not w.attackers.has(al) and not w.defenders.has(al):
			w.defenders.append(al)
	Interp.run_effect(ctx, ctx.root, cb.get("on_declare"))
	game.mark_chars_dirty(w.attackers + w.defenders)
	game.message(game.loc.t("msg.war_declared", {"name": w.name}), "war", {"type": "war", "id": w.id}, w.attackers + w.defenders)
	game.on_action("on_war_started", {"type": "character", "id": attacker.id}, ctx.scopes)
	game.emit("war.declared", {"war": w})
	return w


# ------------------------------------------------------------ счёт войны

## {total, battle, occupation, ticking, extra: [{label, value}]}
static func warscore(game: Game, w: Dictionary) -> Dictionary:
	# Земли сторон. Державы могут вкладываться друг в друга (мятеж вассалов),
	# поэтому сторона графства определяется ближайшим участником вверх по цепочке сюзеренов.
	var att_side := {}
	var def_side := {}
	for id in w.attackers + w.defenders:
		var c: Variant = game.ch(id)
		if c == null:
			continue
		for county in Titles.realm_counties(game, c):
			if att_side.has(county) or def_side.has(county):
				continue
			var side: Variant = side_of(game, w, game.state.titles[county].holder if game.state.titles.has(county) else null)
			if side == "att":
				att_side[county] = true
			elif side == "def":
				def_side[county] = true
	var targets: Array = w.target_counties.filter(func(c): return game.state.provinces.has(c))
	var on_att := Data.count(targets, func(c): return att_side.has(c))
	var on_def := Data.count(targets, func(c): return def_side.has(c))
	var targets_on_att := targets.size() > 0 and on_att > on_def
	var tw = game.def_num("war.target_weight", 70)
	var cap_bonus = game.def_num("war.capital_bonus", 15)
	var occ_att = minf(100.0, _occ_score(game, w, def_side, "att", [] if targets_on_att else targets, tw) + _cap_occ(game, w, w.defender, "att", cap_bonus))
	var occ_def = minf(100.0, _occ_score(game, w, att_side, "def", targets if targets_on_att else [], tw) + _cap_occ(game, w, w.attacker, "def", cap_bonus))
	var mbs = game.def_num("war.max_battle_score", 40)
	var mt = game.def_num("war.max_ticking", 25)
	var battle = clampf(float(w.battle_score), -mbs, mbs)
	var ticking = clampf(float(w.ticking), -mt, mt)
	var occupation = occ_att - occ_def
	var extra := []
	for x in game.engine.hooks.collect("war.score", {"game": game, "war": w}):
		extra.append_array(Data.as_array(x))
	var extra_sum := 0.0
	for x in extra:
		extra_sum += Data.num(x.get("value"))
	var total := clampf(roundf(occupation + battle + ticking + extra_sum), -100.0, 100.0)
	return {"total": total, "battle": roundf(battle), "occupation": roundf(occupation), "ticking": roundf(ticking), "extra": extra}


static func _occ_by(game: Game, w: Dictionary, c: String, side: String) -> bool:
	var p: Variant = game.state.provinces.get(c)
	return p != null and p.occupant != null and p.occupant_war == w.id and participant_side(w, p.occupant) == side


static func _occ_score(game: Game, w: Dictionary, enemy_counties: Dictionary, side: String, tgts: Array, tw: float) -> float:
	var tset := {}
	for c in tgts:
		if enemy_counties.has(c):
			tset[c] = true
	var others := enemy_counties.keys().filter(func(c): return not tset.has(c))
	var tf = float(Data.count(tset.keys(), func(c): return _occ_by(game, w, c, side))) / tset.size() if tset.size() > 0 else 0.0
	var of = float(Data.count(others, func(c): return _occ_by(game, w, c, side))) / others.size() if others.size() > 0 else tf
	if tset.is_empty():
		return 100.0 * of
	return tw * tf + (100.0 - tw) * of


static func _cap_occ(game: Game, w: Dictionary, leader: String, side: String, bonus: float) -> float:
	var c: Variant = game.ch(leader)
	var cap: Variant = c.capital if c != null else null
	return bonus if (cap != null and _occ_by(game, w, cap, side)) else 0.0


## Ежемесячно: «тикающий» счёт за удержание целей войны.
static func update_ticking(game: Game, w: Dictionary) -> void:
	var targets: Array = w.target_counties.filter(func(c): return game.state.provinces.has(c))
	if targets.is_empty():
		return
	var months = (game.date - int(w.start)) / 30.0
	var gain = game.def_num("war.ticking_gain", 2)
	var loss = game.def_num("war.ticking_loss", 1)
	var after = game.def_num("war.defender_ticking_after_months", 12)
	var t0: Variant = game.state.titles.get(targets[0])
	var att_holds: bool = side_of(game, w, t0.holder if t0 != null else null) == "att"
	if not att_holds:
		var o := Data.count(targets, func(c): return _occ_by(game, w, c, "att"))
		if o == targets.size():
			w.ticking += gain
		elif o == 0 and months > after:
			w.ticking -= loss
	else:
		var o := Data.count(targets, func(c): return _occ_by(game, w, c, "def"))
		if o == targets.size():
			w.ticking -= gain
		elif o == 0 and months > after:
			w.ticking += loss
	var mt = game.def_num("war.max_ticking", 25)
	w.ticking = clampf(float(w.ticking), -mt, mt)


# ------------------------------------------------------------ мир

## outcome: "victory", "white_peace" или "defeat".
static func end_war(game: Game, w: Dictionary, outcome: String) -> void:
	if not game.state.wars.has(w.id):
		return
	var cb: Variant = game.content.get_def("casus_belli", w.cb)
	var scopes: Dictionary = w.scopes.duplicate() if w.get("scopes") is Dictionary else {}
	scopes["attacker"] = {"type": "character", "id": w.attacker}
	scopes["defender"] = {"type": "character", "id": w.defender}
	scopes["war"] = {"type": "war", "id": w.id}
	if w.target != null:
		scopes["target"] = {"type": "title", "id": w.target}
	var ctx = ScriptContext.make(game, {"type": "character", "id": w.attacker}, scopes)
	if game.is_alive(w.attacker) and game.is_alive(w.defender) and cb != null:
		var key = "on_victory" if outcome == "victory" else ("on_defeat" if outcome == "defeat" else "on_white_peace")
		Interp.run_effect(ctx, ctx.root, cb.get(key))
	var years: float = Data.num(cb.get("truce_years"), game.def_num("war.truce_years", 5)) if cb != null else game.def_num("war.truce_years", 5)
	game.state.truces.append({"a": w.attacker, "b": w.defender, "until": game.date + roundi(years * GameDate.DAYS_PER_YEAR)})
	game.state.truces = game.state.truces.filter(func(t): return t.until > game.date)
	for p in game.state.provinces.values():
		if p.occupant_war == w.id:
			p.occupant = null
			p.occupant_war = null
		if p.siege != null:
			var sa: Variant = game.state.armies.get(p.siege.army)
			if sa != null and sa.get("war") == w.id:
				p.siege = null
	game.state.wars.erase(w.id)
	game.mark_chars_dirty(w.attackers + w.defenders)
	# ИИ распускает войска, если больше ни с кем не воюет.
	for id in w.attackers + w.defenders:
		if game.is_player(id) or is_at_war(game, id):
			continue
		for a in game.state.armies.values():
			if a.owner == id:
				Military.disband_army(game, a.id)
	var mkey = "msg.war_won_att" if outcome == "victory" else ("msg.war_won_def" if outcome == "defeat" else "msg.war_white_peace")
	game.message(game.loc.t(mkey, {"name": w.name if w.name != null else ""}), "war", null, w.attackers + w.defenders)
	var end_scopes := scopes.duplicate()
	end_scopes.erase("war")
	if game.is_alive(w.attacker):
		game.on_action("on_war_ended", {"type": "character", "id": w.attacker}, end_scopes)
	# победитель (root) и побеждённый (scope:enemy)
	if outcome == "victory" or outcome == "defeat":
		var winner: String = w.attacker if outcome == "victory" else w.defender
		var loser: String = w.defender if outcome == "victory" else w.attacker
		if game.is_alive(winner) and game.is_alive(loser):
			game.on_action("on_war_won", {"type": "character", "id": winner}, {"enemy": {"type": "character", "id": loser}})
	game.emit("war.ended", {"war": w, "outcome": outcome})


## Ежемесячная проверка: война теряет смысл, если лидеры умерли или цель утрачена.
static func validate_wars(game: Game) -> void:
	for w in game.state.wars.values():
		w.attackers = w.attackers.filter(func(id): return game.is_alive(id) and not game.ch(id).titles.is_empty())
		w.defenders = w.defenders.filter(func(id): return game.is_alive(id) and not game.ch(id).titles.is_empty())
		if not game.is_alive(w.attacker) or not game.is_alive(w.defender) or not w.attackers.has(w.attacker) or not w.defenders.has(w.defender):
			end_war(game, w, "white_peace")
			continue
		if w.get("faction") != null:
			if game.ch(w.attacker).liege != w.defender:
				end_war(game, w, "white_peace")
			continue
		var cbd: Variant = game.content.get_def("casus_belli", w.cb)
		if w.cb == "independence" or (cbd != null and cbd.get("targets") == "independence"):
			if game.ch(w.attacker).liege != w.defender:
				end_war(game, w, "white_peace")
			continue
		# Цели больше не во владении стороны защитника
		var def: Dictionary = game.ch(w.defender)
		var still_held: bool = w.target_counties.any(func(c):
			var h: Variant = _holder(game, c)
			return h != null and Titles.is_in_realm_of(game, h, def))
		if not w.target_counties.is_empty() and not still_held:
			end_war(game, w, "white_peace")


## Насколько сторона готова сдаться (для ИИ).
## Дар убеждения того, кто предлагает мир стороне side (вождь другой стороны):
## на столько очков счёта войны раньше она соглашается.
static func peace_persuasion(game: Game, w: Dictionary, side: String) -> float:
	var other: Variant = game.ch(w.attacker if side == "def" else w.defender)
	return Stats.stat(game, other, "peace_persuasion") if other != null else 0.0


static func ai_will_accept_surrender(game: Game, w: Dictionary, loser_side: String) -> bool:
	var ws: float = warscore(game, w).total
	var score = ws if loser_side == "def" else -ws
	if score >= 100.0:
		return true
	# «Военная усталость»: чем дольше война, тем охотнее проигрывающий сдаётся.
	var years = (game.date - int(w.start)) / float(GameDate.DAYS_PER_YEAR)
	var fatigue = maxf(0.0, years - game.def_num("war.fatigue_after_years", 2)) * game.def_num("war.fatigue_per_year", 6)
	var need := maxf(game.def_num("war.min_surrender_threshold", 50), game.def_num("war.ai_surrender_threshold", 85) - fatigue)
	return score >= need - peace_persuasion(game, w, loser_side)


static func ai_will_accept_white_peace(game: Game, w: Dictionary, side: String) -> bool:
	var ws: float = warscore(game, w).total
	var mine = ws if side == "att" else -ws
	var years = (game.date - int(w.start)) / float(GameDate.DAYS_PER_YEAR)
	if mine <= -game.def_num("war.white_peace_losing", 35) + peace_persuasion(game, w, side):
		return true
	return years >= game.def_num("war.white_peace_years", 3) and absf(ws) <= game.def_num("war.white_peace_max_score", 30)


static func primary_war_tier(game: Game, id: String) -> int:
	var c: Variant = game.ch(id)
	return Titles.primary_tier(game, c) if c != null else 0

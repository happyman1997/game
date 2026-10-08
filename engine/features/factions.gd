class_name Factions
extends EngineFeature
## Фракции вассалов. Недовольные вассалы объединяются против сюзерена
## (за независимость, за претендента на трон). Когда сила фракции
## превышает порог, растёт недовольство; на 100% фракция предъявляет
## ультиматум: сюзерен либо выполняет требования, либо получает мятеж —
## войну, в которой все члены фракции выступают вместе.
##
## Данные:
##   factions: { icon, cb, claimant, can_join, ai_join, ai_accept_demands,
##               on_demands_accepted, ultimatum_event }
##   defines.factions: { power_threshold, discontent_gain, discontent_decay,
##                       ai_join_chance, ai_create_threshold, ai_create_chance,
##                       ai_leave_below, cooldown_years }
## Скоупы: root — вассал (для can_join/ai_join) или лидер фракции (для
## on_demands_accepted), scope:liege, scope:faction, scope:faction_leader,
## scope:claimant.

const OWNER := "core/factions"


func _init() -> void:
	id = "factions"
	doc = "Фракции вассалов: независимость, претендент; ультиматумы и мятежи"


static func fref(f: Dictionary) -> Dictionary:
	return {"type": "faction", "id": f.id}


static func against(game: Game, liege_id: String) -> Array:
	return game.state.factions.values().filter(func(f): return f.target == liege_id)


static func faction_of(game: Game, c: Dictionary) -> Variant:
	for f in game.state.factions.values():
		if f.members.has(c.id):
			return f
	return null


static func context(game: Game, root: Dictionary, liege: Dictionary, f: Variant = null, claimant: Variant = null) -> ScriptContext:
	var scopes := {
		"liege": {"type": "character", "id": liege.id},
		"vassal": {"type": "character", "id": root.id},
	}
	if f != null:
		scopes["faction"] = fref(f)
		scopes["faction_leader"] = {"type": "character", "id": f.leader}
	var cl: Variant = claimant if claimant != null else (f.get("claimant") if f != null else null)
	if cl != null:
		scopes["claimant"] = {"type": "character", "id": cl}
	return ScriptContext.make(game, {"type": "character", "id": root.id}, scopes)


## Кандидаты в претенденты: у кого есть претензия на основной титул сюзерена.
static func claimant_candidates(game: Game, liege: Dictionary) -> Array:
	if liege.titles.is_empty():
		return []
	var t: String = liege.titles[0]
	return game.living().filter(func(c): return c.id != liege.id and c.claims.has(t) and Chars.is_adult(game, c) and c.get("prison") == null and not game.is_player(c.id))


static func _best_claimant(game: Game, liege: Dictionary, vassal: Dictionary) -> Variant:
	var cands := claimant_candidates(game, liege)
	if cands.any(func(c): return c.id == vassal.id):
		return vassal.id
	Data.stable_sort(cands, func(a, b):
		if b.titles.size() != a.titles.size():
			return b.titles.size() - a.titles.size()
		return signf(float(b.prestige) - float(a.prestige)))
	return cands[0].id if not cands.is_empty() else null


static func can_join(game: Game, c: Dictionary, def: Dictionary, liege: Dictionary, claimant: Variant = null) -> bool:
	if not Chars.is_alive(c) or c.liege != liege.id or c.titles.is_empty() or c.get("prison") != null:
		return false
	var cd: Variant = c.flags.get("faction_cooldown")
	if cd != null and cd > game.date:
		return false
	if def.get("claimant", false) and claimant == null:
		return false
	var ctx := context(game, c, liege, null, claimant)
	return Interp.eval_trigger(ctx, ctx.root, def.get("can_join"))


static func ai_join_score(game: Game, c: Dictionary, def: Dictionary, liege: Dictionary, f: Variant = null, claimant: Variant = null) -> float:
	var ctx := context(game, c, liege, f, claimant)
	return Interp.eval_value(ctx, ctx.root, def.ai_join) if def.get("ai_join") != null else 0.0


## Сила фракции в процентах от силы сюзерена (без её членов).
static func power(game: Game, f: Dictionary) -> int:
	var liege: Variant = game.ch(f.target)
	if liege == null:
		return 0
	var share := game.def_num("economy.vassal_levy_share", 0.35) * maxf(0.0, 1.0 + Stats.stat(game, liege, "vassal_levy_mult"))
	var members := 0.0
	for id in f.members:
		var m: Variant = game.ch(id)
		if m != null:
			members += Economy.realm_levy(game, m)
	var liege_str := maxf(1.0, Economy.realm_levy(game, liege) - members * share)
	return roundi(members / liege_str * 100.0)


static func create(game: Game, type: String, founder: Dictionary, claimant: Variant = null) -> Variant:
	var def: Variant = game.content.get_def("factions", type)
	var liege: Variant = game.ch(founder.liege)
	if def == null or liege == null or faction_of(game, founder) != null:
		return null
	if def.get("claimant", false) and claimant == null:
		claimant = _best_claimant(game, liege, founder)
	if not can_join(game, founder, def, liege, claimant):
		return null
	if against(game, liege.id).any(func(f): return f.type == type):
		return null
	var f := {"id": game.new_id("fac"), "type": type, "target": liege.id, "leader": founder.id, "members": [founder.id], "claimant": claimant, "discontent": 0.0, "created": game.date, "ultimatum": false}
	game.state.factions[f.id] = f
	game.emit("faction.created", {"faction": f})
	game.message(game.loc.t("msg.faction_created", {"faction": game.name_of("factions", type), "who": game.scope_name({"type": "character", "id": founder.id}), "liege": game.scope_name({"type": "character", "id": liege.id})}),
		"bad", {"type": "character", "id": founder.id}, [liege.id, founder.id])
	return f


static func join(game: Game, c: Dictionary, f: Dictionary) -> bool:
	var def: Variant = game.content.get_def("factions", f.type)
	var liege: Variant = game.ch(f.target)
	if def == null or liege == null or faction_of(game, c) != null or not can_join(game, c, def, liege, f.get("claimant")):
		return false
	f.members.append(c.id)
	_update_leader(game, f)
	game.emit("faction.joined", {"faction": f, "character": c})
	return true


static func leave(game: Game, c: Dictionary) -> void:
	var f: Variant = faction_of(game, c)
	if f == null:
		return
	f.members = f.members.filter(func(x): return x != c.id)
	if f.members.is_empty():
		game.state.factions.erase(f.id)
	else:
		_update_leader(game, f)
	game.emit("faction.left", {"faction": f, "character": c})


static func _update_leader(game: Game, f: Dictionary) -> void:
	# Лидер — претендент, если он член фракции, иначе самый сильный член.
	if f.get("claimant") != null and f.members.has(f.claimant):
		f.leader = f.claimant
		return
	var best: Variant = null
	var bv := -INF
	for id in f.members:
		var m: Variant = game.ch(id)
		if m == null:
			continue
		var v := float(Economy.realm_levy(game, m))
		if best == null or v > bv:
			best = id
			bv = v
	if best != null:
		f.leader = best


static func dissolve(game: Game, f: Dictionary, cooldown: bool = true) -> void:
	if not game.state.factions.has(f.id):
		return
	game.state.factions.erase(f.id)
	if cooldown:
		var until := game.date + roundi(game.def_num("factions.cooldown_years", 5) * 365)
		for id in f.members:
			var m: Variant = game.ch(id)
			if m != null:
				m.flags["faction_cooldown"] = until
	game.emit("faction.dissolved", {"faction": f})


## Требования выполнены без войны.
static func enforce_demands(game: Game, f: Dictionary) -> void:
	var def: Variant = game.content.get_def("factions", f.type)
	var leader: Variant = game.ch(f.leader)
	var liege: Variant = game.ch(f.target)
	if def == null or leader == null or liege == null:
		return
	var ctx := context(game, leader, liege, f)
	game.emit("faction.ultimatum", {"faction": f, "accepted": true})
	game.message(game.loc.t("msg.faction_demands_accepted", {"faction": game.name_of("factions", f.type), "liege": game.scope_name({"type": "character", "id": liege.id})}), "war", null, [liege.id] + f.members)
	Interp.run_effect(ctx, ctx.root, def.get("on_demands_accepted"))
	dissolve(game, f)
	game.mark_dirty()


## Ультиматум отвергнут — мятеж.
static func revolt(game: Game, f: Dictionary) -> bool:
	var def: Variant = game.content.get_def("factions", f.type)
	var leader: Variant = game.ch(f.leader)
	var liege: Variant = game.ch(f.target)
	if def == null or leader == null or liege == null:
		return false
	game.emit("faction.ultimatum", {"faction": f, "accepted": false})
	var members: Array = f.members.filter(func(id): return game.is_alive(id) and game.ch(id).liege == liege.id and game.ch(id).get("prison") == null)
	if not members.has(leader.id):
		return false
	var counties := []
	if def.get("claimant", false):
		counties = Titles.domain_counties(game, liege)
	else:
		for id in members:
			counties.append_array(Titles.realm_counties(game, game.ch(id)))
	var scopes := {"faction_leader": {"type": "character", "id": leader.id}}
	if f.get("claimant") != null and game.is_alive(f.claimant):
		scopes["claimant"] = {"type": "character", "id": f.claimant}
	var w: Variant = Wars.declare_war(game, leader, {"cb": def.cb, "defender": liege.id, "title": liege.titles[0] if not liege.titles.is_empty() else null, "counties": counties},
		{"free": true, "attackers": members, "scopes": scopes, "faction": f.id})
	if w == null:
		return false
	f.ultimatum = false
	return true


static func _issue_ultimatum(game: Game, f: Dictionary) -> void:
	var def: Dictionary = game.content.get_def("factions", f.type)
	var liege: Dictionary = game.ch(f.target)
	var leader: Dictionary = game.ch(f.leader)
	if game.is_player(liege.id):
		if f.get("ultimatum", false):
			return
		f.ultimatum = true
		var ev: String = str(def.get("ultimatum_event", game.def_val("factions.ultimatum_event", "faction.0001")))
		if game.content.has("events", ev):
			var scopes := {"faction": fref(f), "faction_leader": {"type": "character", "id": leader.id}}
			if f.get("claimant") != null:
				scopes["claimant"] = {"type": "character", "id": f.claimant}
			game.events.fire(ev, {"type": "character", "id": liege.id}, scopes)
		else:
			revolt(game, f)
		return
	var ctx := context(game, liege, liege, f)
	var accept := Interp.eval_value(ctx, ctx.root, def.ai_accept_demands) if def.get("ai_accept_demands") != null else -1.0
	if accept > 0:
		enforce_demands(game, f)
	else:
		revolt(game, f)


static func _faction_at_war(game: Game, f: Dictionary) -> bool:
	return game.state.wars.values().any(func(w): return w.get("faction") == f.id)


static func monthly(game: Game) -> void:
	# 1. чистка
	for f in game.state.factions.values():
		var liege: Variant = game.ch(f.target)
		if not Chars.is_alive(liege) or liege.titles.is_empty():
			dissolve(game, f, false)
			continue
		if _faction_at_war(game, f):
			continue
		f.members = f.members.filter(func(id):
			var m: Variant = game.ch(id)
			return Chars.is_alive(m) and m.liege == f.target and not m.titles.is_empty())
		if f.get("claimant") != null and (not game.is_alive(f.claimant) or liege.titles.is_empty() or not game.ch(f.claimant).claims.has(liege.titles[0])):
			dissolve(game, f, false)
			continue
		if f.members.is_empty():
			dissolve(game, f, false)
			continue
		if not f.members.has(f.leader):
			_update_leader(game, f)

	# 2. ИИ-вассалы вступают, создают и покидают фракции
	var types := game.content.all("factions")
	if not types.is_empty():
		for v in game.rulers().duplicate():
			if v.liege == null or game.is_player(v.id) or v.get("prison") != null or v.death != null:
				continue
			var liege: Variant = game.ch(v.liege)
			if liege == null or not Chars.is_alive(liege):
				continue
			if Wars.is_at_war_with(game, v.id, liege.id):
				continue
			var cur: Variant = faction_of(game, v)
			if cur != null:
				if cur.leader != v.id or cur.members.size() > 1:
					var cdef: Variant = game.content.get_def("factions", cur.type)
					if cdef != null and ai_join_score(game, v, cdef, liege, cur) < game.def_num("factions.ai_leave_below", -10) and game.rng.chance(0.3):
						leave(game, v)
				continue
			if not game.rng.chance(game.def_num("factions.ai_consider_chance", 0.35)):
				continue
			var existing := against(game, liege.id)
			for def in types:
				var f: Variant = null
				for x in existing:
					if x.type == def.id:
						f = x
						break
				var claimant: Variant = f.get("claimant") if f != null else (_best_claimant(game, liege, v) if def.get("claimant", false) else null)
				if not can_join(game, v, def, liege, claimant):
					continue
				var score := ai_join_score(game, v, def, liege, f, claimant)
				if f != null:
					if score > 0 and game.rng.chance(game.def_num("factions.ai_join_chance", 0.5)):
						join(game, v, f)
						break
				elif score > game.def_num("factions.ai_create_threshold", 20) and game.rng.chance(game.def_num("factions.ai_create_chance", 0.25)):
					create(game, def.id, v, claimant)
					break

	# 3. недовольство и ультиматумы
	for f in game.state.factions.values():
		if not game.state.factions.has(f.id) or _faction_at_war(game, f):
			continue
		var liege: Variant = game.ch(f.target)
		if liege == null:
			continue
		if game.state.wars.values().any(func(w): return w.defenders.has(liege.id) and w.get("faction") != null):
			continue
		var pw := power(game, f)
		if pw >= game.def_num("factions.power_threshold", 80):
			f.discontent = minf(100.0, float(f.discontent) + game.def_num("factions.discontent_gain", 6))
		else:
			f.discontent = maxf(0.0, float(f.discontent) - game.def_num("factions.discontent_decay", 4))
		if f.discontent >= 100.0:
			if game.is_player(f.leader):
				if not f.get("ultimatum", false):
					f.ultimatum = true
					game.message(game.loc.t("msg.faction_ready"), "war")
				continue
			if game.is_alive(f.leader) and game.ch(f.leader).get("prison") == null:
				_issue_ultimatum(game, f)


## Претендент забирает основной титул проигравшего: получает его (и столичное
## графство, если своих земель нет), прежний владелец становится вассалом,
## вассалы его ранга и выше переходят к победителю.
static func seize_primary_title(game: Game, winner: Dictionary, loser: Dictionary) -> void:
	if loser.titles.is_empty() or winner.id == loser.id:
		return
	var t: String = loser.titles[0]
	var vassals := game.vassals_of(loser.id)
	var loser_liege: Variant = loser.liege
	Titles.transfer_title(game, t, winner.id, winner.id)
	if Titles.domain_counties(game, winner).is_empty():
		var cap: Variant = loser.capital if (loser.capital != null and loser.titles.has(loser.capital)) else null
		if cap == null:
			var dom := Titles.domain_counties(game, loser)
			cap = dom[0] if not dom.is_empty() else null
		if cap != null:
			Titles.transfer_title(game, cap, winner.id, winner.id)
	if winner.liege == loser.id or winner.liege == winner.id:
		Chars.set_liege(game, winner, loser_liege if loser_liege != winner.id else null)
	if loser.death == null and not loser.titles.is_empty():
		Chars.set_liege(game, loser, winner.id)
	for v in vassals:
		if not Chars.is_alive(v) or v.id == winner.id or v.liege != loser.id:
			continue
		if Titles.primary_tier(game, v) >= Titles.primary_tier(game, loser):
			Chars.set_liege(game, v, winner.id)
	game.mark_dirty()


## Игрок-лидер предъявляет ультиматум.
static func player_ultimatum(game: Game, f: Dictionary) -> void:
	if f.discontent < 100.0:
		return
	f.ultimatum = false
	_issue_ultimatum(game, f)


func install(engine: GameEngine) -> void:
	engine.systems.register("factions", {"id": "factions", "order": 58, "on_month": Factions.monthly}, OWNER)
	# Поставщик целей для мятежей: в обычных объявлениях войны не участвует.
	engine.cb_targets.register("faction", {"targets": func(_g, _a): return []}, OWNER)
	# Конец войны фракции — фракция распадается.
	engine.hooks.on("war.ended", func(p):
		var w: Dictionary = p.war
		if w.get("faction") == null:
			return
		var f: Variant = p.game.state.factions.get(w.faction)
		if f != null:
			Factions.dissolve(p.game, f)
	, 0, OWNER)
	# Дети, не унаследовавшие основной титул родителя, получают на него претензию — будущие претенденты.
	engine.hooks.on("succession", func(p):
		var game: Game = p.game
		var prim: Variant = game.ch(p.primary)
		if prim == null or prim.titles.is_empty():
			return
		var t: String = prim.titles[0]
		if game.state.titles[t].holder != p.primary:
			return
		var deceased: Dictionary = p.deceased
		if not deceased.children.has(p.primary) and not deceased.spouses.has(p.primary):
			return
		for id in deceased.children:
			var chd: Variant = game.ch(id)
			if chd == null or chd.id == p.primary or not Chars.is_alive(chd) or chd.claims.has(t):
				continue
			if game.rng.chance(game.def_num("factions.sibling_claim_chance", 0.5)):
				chd.claims.append(t)
	, 0, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var FA := ["faction"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	var fac := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.state.factions.get(s.id) if (s != null and s.type == "faction") else null
	var is_no := func(arg: Variant) -> bool: return (arg is String and arg == "no") or (arg is bool and not arg)
	r.triggers.register("is_in_faction", {"scopes": CH, "doc": "Состоит во фракции (yes/no или тип)",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var f: Variant = Factions.faction_of(ctx.game, c) if c != null else null
			if is_no.call(arg):
				return f == null
			return f != null and (arg == null or ScriptContext.is_yes(arg) or f.type == arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_in_faction.not" if is_no.call(arg) else "tr.is_in_faction"),
	}, OWNER)
	r.triggers.register("is_faction_leader", {"scopes": CH, "doc": "Возглавляет фракцию",
		"eval": func(ctx, s, arg): return ctx.game.state.factions.values().any(func(f): return f.leader == s.id) == (arg == null or ScriptContext.is_yes(arg)),
	}, OWNER)
	r.triggers.register("faction_type", {"scopes": FA, "doc": "Тип фракции", "eval": func(ctx, s, arg):
		var f: Variant = fac.call(ctx, s)
		return f != null and f.type == arg
	}, OWNER)
	r.values.register("faction_power", {"scopes": FA, "doc": "Сила фракции в % от силы сюзерена", "get": func(ctx, s, _a):
		var f: Variant = fac.call(ctx, s)
		return float(Factions.power(ctx.game, f)) if f != null else 0.0
	}, OWNER)
	r.values.register("faction_discontent", {"scopes": FA, "doc": "Недовольство фракции (0–100)", "get": func(ctx, s, _a):
		var f: Variant = fac.call(ctx, s)
		return float(f.discontent) if f != null else 0.0
	}, OWNER)
	r.values.register("num_faction_members", {"scopes": FA, "doc": "Число членов фракции", "get": func(ctx, s, _a):
		var f: Variant = fac.call(ctx, s)
		return float(f.members.size()) if f != null else 0.0
	}, OWNER)
	r.links.register("faction_leader", {"from": FA, "doc": "Лидер фракции", "resolve": func(ctx, s):
		var f: Variant = fac.call(ctx, s)
		return {"type": "character", "id": f.leader} if f != null else null
	}, OWNER)
	r.links.register("faction_target", {"from": FA, "doc": "Сюзерен, против которого фракция", "resolve": func(ctx, s):
		var f: Variant = fac.call(ctx, s)
		return {"type": "character", "id": f.target} if f != null else null
	}, OWNER)
	r.links.register("faction_claimant", {"from": FA, "doc": "Претендент фракции", "resolve": func(ctx, s):
		var f: Variant = fac.call(ctx, s)
		return {"type": "character", "id": f.claimant} if (f != null and f.get("claimant") != null) else null
	}, OWNER)
	r.links.register("joined_faction", {"from": CH, "doc": "Фракция, в которой состоит персонаж", "resolve": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		var f: Variant = Factions.faction_of(ctx.game, c) if c != null else null
		return Factions.fref(f) if f != null else null
	}, OWNER)
	r.lists.register("faction_member", {"from": FA, "doc": "Члены фракции", "list": func(ctx, s):
		var f: Variant = fac.call(ctx, s)
		return f.members.map(func(id): return {"type": "character", "id": id}) if f != null else []
	}, OWNER)
	r.lists.register("faction_against", {"from": CH, "doc": "Фракции против персонажа", "list": func(ctx, s):
		return Factions.against(ctx.game, s.id).map(func(f): return Factions.fref(f))
	}, OWNER)
	r.lists.register("war_attacker", {"from": ["war"], "doc": "Участники войны на стороне нападения", "list": func(ctx, s):
		var w: Variant = ctx.game.state.wars.get(s.id)
		return w.attackers.filter(func(id): return ctx.game.is_alive(id)).map(func(id): return {"type": "character", "id": id}) if w != null else []
	}, OWNER)
	r.lists.register("war_defender", {"from": ["war"], "doc": "Участники войны на стороне защиты", "list": func(ctx, s):
		var w: Variant = ctx.game.state.wars.get(s.id)
		return w.defenders.filter(func(id): return ctx.game.is_alive(id)).map(func(id): return {"type": "character", "id": id}) if w != null else []
	}, OWNER)
	r.effects.register("faction_enforce_demands", {"scopes": FA, "doc": "Сюзерен выполняет требования фракции",
		"apply": func(ctx, s, _arg):
			var f: Variant = fac.call(ctx, s)
			if f != null:
				Factions.enforce_demands(ctx.game, f),
		"describe": func(ctx, s, _arg):
			var f: Variant = fac.call(ctx, s)
			return ctx.game.loc.t("fx.faction_enforce_demands", {"faction": ctx.game.name_of("factions", f.type)}) if f != null else null,
	}, OWNER)
	r.effects.register("faction_start_war", {"scopes": FA, "doc": "Фракция поднимает мятеж",
		"apply": func(ctx, s, _arg):
			var f: Variant = fac.call(ctx, s)
			if f != null:
				Factions.revolt(ctx.game, f),
		"describe": func(ctx, s, _arg):
			var f: Variant = fac.call(ctx, s)
			return ctx.game.loc.t("fx.faction_start_war", {"faction": ctx.game.name_of("factions", f.type)}) if f != null else null,
	}, OWNER)
	r.effects.register("join_faction", {"scopes": CH, "doc": "Вступить во фракцию против сюзерена (или создать): join_faction: <тип>",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c == null or c.liege == null:
				return
			for f in Factions.against(ctx.game, c.liege):
				if f.type == arg:
					Factions.join(ctx.game, c, f)
					return
			Factions.create(ctx.game, str(arg), c),
	}, OWNER)
	r.effects.register("seize_primary_title", {"scopes": CH, "doc": "Забрать основной титул персонажа (претендент): прежний владелец становится вассалом",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var o: Variant = ch.call(ctx, Interp.resolve_scope(ctx, s, arg))
			if c != null and o != null:
				Factions.seize_primary_title(ctx.game, c, o),
		"describe": func(ctx, s, arg):
			var o: Variant = ch.call(ctx, Interp.resolve_scope(ctx, s, arg))
			if o == null or o.titles.is_empty():
				return null
			return ctx.game.loc.t("fx.gain_title", {"who": ctx.game.scope_name(s), "value": ctx.game.scope_name({"type": "title", "id": o.titles[0]})}),
	}, OWNER)
	r.effects.register("leave_faction", {"scopes": CH, "doc": "Выйти из фракции", "apply": func(ctx, s, _arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			Factions.leave(ctx.game, c)
	}, OWNER)
	r.effects.register("add_faction_discontent", {"scopes": FA, "doc": "Изменить недовольство фракции", "apply": func(ctx, s, arg):
		var f: Variant = fac.call(ctx, s)
		if f != null:
			f.discontent = clampf(float(f.discontent) + Interp.eval_value(ctx, s, arg), 0.0, 100.0)
	}, OWNER)
	engine.content_validators.register("factions", func(e: GameEngine, v: ScriptValidator):
		for f in e.content.all("factions"):
			var w: String = "factions/" + f.id
			v.ref("casus_belli", f.get("cb"), w)
			v.ref("events", f.get("ultimatum_event"), w)
			v.trigger(f.get("can_join"), w + " can_join")
			v.effect(f.get("on_demands_accepted"), w + " on_demands_accepted")
	, OWNER)

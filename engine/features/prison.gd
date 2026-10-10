class_name Prison
extends EngineFeature
## Темница. Персонажа можно заключить (взаимодействием из данных или эффектом
## imprison), держать, выкупать, отпускать и казнить. Правителей берут в плен
## при взятии столицы и после проигранных сражений; плен вражеского лидера
## приносит счёт войны.
##
## Заключённый не правит (ИИ не думает), не командует войсками, его интриги
## стоят. Все действия с пленниками — обычные взаимодействия в данных
## (imprison, release_prisoner, execute_prisoner, demand_ransom).
##
##   defines.prison: { escape_chance, escape_per_passage, siege_capture_chance,
##                     battle_capture_chance, leader_captured_warscore,
##                     ransom_base, ransom_per_tier, ransom_income_months,
##                     crime_opinion_modifiers, monthly_stress, dungeon_health }
## Тайные ходы (secret_passages — от интриги): шанс бежать из темницы
## (× escape_per_passage в месяц) и уйти из павшей столицы, не попав в плен.
## Состояние: c.prison = {by, since, home, war}.

const OWNER := "core/prison"
const INDEX_KEY := "prison:index"


func _init() -> void:
	id = "prison"
	doc = "Темница: заключение, выкуп, казнь, плен на войне"


static func is_imprisoned(c: Variant) -> bool:
	return c != null and c.get("prison") != null


static func prisoners_of(game: Game, id: String) -> Array:
	# Индекс «тюремщик → пленники» на месяц; новые пленники сбрасывают его
	# (imprison, смена тюремщика), освобождённые отсеиваются проверкой.
	var idx: Dictionary = game.cached_monthly(INDEX_KEY, func():
		var m := {}
		for c in game.living():
			if c.get("prison") != null:
				if not m.has(c.prison.by):
					m[c.prison.by] = []
				m[c.prison.by].append(c)
		return m)
	return idx.get(id, []).filter(func(c): return c.death == null and c.get("prison") != null and c.prison.by == id)


static func imprison(game: Game, jailer: Dictionary, prisoner: Dictionary, reason: Variant = null, war: Variant = null) -> bool:
	if not Chars.is_alive(jailer) or not Chars.is_alive(prisoner) or prisoner.id == jailer.id or prisoner.get("prison") != null:
		return false
	if not game.engine.hooks.veto("prison.before_imprison", {"game": game, "jailer": jailer, "prisoner": prisoner, "reason": reason}):
		return false
	prisoner["prison"] = {"by": jailer.id, "since": game.date, "home": prisoner.liege, "war": war}
	game.month_cache.erase(INDEX_KEY)
	# армии остаются без него
	for a in game.state.armies.values():
		if a.commander == prisoner.id:
			a.commander = null
	game.mark_chars_dirty([prisoner.id, jailer.id])
	game.message(game.loc.t("msg.imprisoned", {"who": game.scope_name({"type": "character", "id": prisoner.id}), "jailer": game.scope_name({"type": "character", "id": jailer.id})}),
		"bad", {"type": "character", "id": prisoner.id}, [prisoner.id, jailer.id, prisoner.liege])
	game.emit("prison.imprisoned", {"jailer": jailer, "prisoner": prisoner, "reason": reason})
	game.on_action("on_imprisoned", {"type": "character", "id": prisoner.id}, {"jailer": {"type": "character", "id": jailer.id}})
	return true


static func release(game: Game, prisoner: Dictionary, reason: String = "released") -> void:
	if prisoner.get("prison") == null:
		return
	var jailer: String = prisoner.prison.by
	prisoner.prison = null
	game.mark_chars_dirty([prisoner.id, jailer])
	if Chars.is_alive(prisoner):
		game.message(game.loc.t("msg.prison_" + reason, {"who": game.scope_name({"type": "character", "id": prisoner.id})}),
			"info", {"type": "character", "id": prisoner.id}, [prisoner.id, jailer, prisoner.liege])
	game.emit("prison.released", {"prisoner": prisoner, "jailer": jailer, "reason": reason})
	game.on_action("on_released_from_prison", {"type": "character", "id": prisoner.id}, {"jailer": {"type": "character", "id": jailer}})


## Кто платит выкуп: сам правитель-пленник или двор, к которому он принадлежал, или родня-правитель.
static func ransom_payer(game: Game, prisoner: Dictionary) -> Dictionary:
	if not prisoner.titles.is_empty():
		return prisoner
	var by: Variant = prisoner.prison.by if prisoner.get("prison") != null else null
	var home_id: Variant = prisoner.prison.get("home") if prisoner.get("prison") != null else null
	var home: Variant = game.ch(home_id if home_id != null else prisoner.liege)
	if home != null and Chars.is_alive(home) and not home.titles.is_empty() and home.id != by:
		return home
	for id in [prisoner.father, prisoner.mother] + prisoner.spouses:
		var r: Variant = game.ch(id)
		if r != null and Chars.is_alive(r) and not r.titles.is_empty() and r.id != by:
			return r
	return prisoner


static func ransom_cost(game: Game, prisoner: Dictionary) -> int:
	var payer := ransom_payer(game, prisoner)
	var income := maxf(0.0, Economy.monthly_income(game, payer)) if not payer.titles.is_empty() else 0.0
	return roundi(game.def_num("prison.ransom_base", 40) + game.def_num("prison.ransom_per_tier", 60) * Titles.primary_tier(game, prisoner) + income * game.def_num("prison.ransom_income_months", 6))


## Есть ли у jailer законный повод заключить target (без тирании).
static func has_imprisonment_reason(game: Game, jailer: Dictionary, target: Dictionary) -> bool:
	var crimes: Array = game.def_val("prison.crime_opinion_modifiers", ["attempted_murder", "murdered_relative", "rebel"])
	for e in jailer.opinions.get(target.id, []):
		if crimes.has(e.mod):
			return true
	var flag: Variant = target.flags.get("criminal:" + jailer.id)
	if flag != null and (flag == 0 or flag > game.date):
		return true
	# раскрытая враждебная интрига против jailer или его близких
	var protected_ids := {jailer.id: true}
	for x in jailer.spouses + jailer.children:
		protected_ids[x] = true
	for s in game.state.schemes.values():
		var d: Variant = game.content.get_def("schemes", s.type)
		if s.owner == target.id and s.discovered and protected_ids.has(s.target) and d != null and d.get("category") == "hostile":
			return true
	return false


static func _leader_captured(game: Game, w: Dictionary, leader: String, captor_side: String) -> bool:
	var c: Variant = game.ch(leader)
	if c == null or c.get("prison") == null:
		return false
	return Wars.participant_side(w, c.prison.by) == captor_side


static func monthly(game: Game) -> void:
	for c in game.living():
		if c.get("prison") == null:
			continue
		var jailer: Variant = game.ch(c.prison.by)
		if not Chars.is_alive(jailer):
			release(game, c, "jailer_died")
			continue
		Chars.change_stress(game, c, game.def_num("prison.monthly_stress", 2), "prison")
		# тайные ходы (интрига): знает, где в стене плохо держится камень
		var escape := game.def_num("prison.escape_chance", 0.004) + Stats.stat(game, c, "secret_passages") * game.def_num("prison.escape_per_passage", 0.02)
		if game.rng.chance(escape):
			release(game, c, "escaped")


## Пленение правителей при взятии их столицы.
static func _on_siege_won(game: Game, war: Dictionary, army: Dictionary, province: String) -> void:
	var captor: Variant = game.ch(army.owner)
	if captor == null:
		return
	var side: Variant = Wars.participant_side(war, captor.id)
	if side == null:
		return
	for r in game.rulers().duplicate():
		if r.capital != province or r.get("prison") != null or not Chars.is_alive(r):
			continue
		var rs: Variant = Wars.participant_side(war, r.id)
		if rs == null or rs == side:
			continue
		# правитель с поднятой армией находится при войске, а не в замке
		if game.state.armies.values().any(func(a): return a.owner == r.id):
			continue
		if game.rng.chance(game.def_num("prison.siege_capture_chance", 0.5)):
			# тайные ходы: правитель уходит из павшей столицы подземным ходом
			if game.rng.chance(clampf(Stats.stat(game, r, "secret_passages"), 0.0, 0.9)):
				if game.is_player(r.id):
					game.message(game.loc.t("msg.escaped_by_passage", {"place": game.name_of("provinces", province)}), "good", {"type": "province", "id": province})
				game.emit("prison.passage_escape", {"character": r, "province": province})
			else:
				imprison(game, captor, r, "siege", war.id)
		for id in r.spouses + r.children:
			var f: Variant = game.ch(id)
			if f != null and Chars.is_alive(f) and f.get("prison") == null and f.titles.is_empty() and f.liege == r.id and Chars.is_adult(game, f) and game.rng.chance(game.def_num("prison.family_capture_chance", 0.3)):
				imprison(game, captor, f, "siege", war.id)


func install(engine: GameEngine) -> void:
	engine.systems.register("prison", {"id": "prison", "order": 22, "on_month": Prison.monthly}, OWNER)
	engine.modifier_providers.register("prison", {"fn": func(game: Game, c: Dictionary) -> Variant:
		return {"health": game.def_num("prison.dungeon_health", -1), "fertility": -0.5} if c.get("prison") != null else null
	}, OWNER)
	engine.hooks.on("siege.won", func(p): Prison._on_siege_won(p.game, p.war, p.army, p.province), 0, OWNER)
	engine.hooks.on("battle.commander_survived", func(p):
		var game: Game = p.game
		var c: Variant = game.ch(p.commander)
		var cap: Variant = game.ch(p.captor)
		if c != null and cap != null and c.get("prison") == null and game.rng.chance(game.def_num("prison.battle_capture_chance", 0.08)):
			Prison.imprison(game, cap, c, "battle", p.war.id)
	, 0, OWNER)
	# Пленники умершего тюремщика переходят к его основному наследнику.
	engine.hooks.on("succession", func(p):
		for c in p.game.living():
			if c.get("prison") != null and c.prison.by == p.deceased.id:
				c.prison.by = p.primary
				p.game.month_cache.erase(INDEX_KEY)
	, 0, OWNER)
	engine.hooks.on("character.death", func(p):
		if p.character.get("prison") != null:
			p.character.prison = null
	, 0, OWNER)
	# Плен лидера вражеской стороны даёт счёт войны.
	engine.hooks.on("war.score", func(p):
		var game: Game = p.game
		var v := game.def_num("prison.leader_captured_warscore", 75)
		var out := []
		if Prison._leader_captured(game, p.war, p.war.defender, "att"):
			out.append({"label": game.loc.t("ui.ws_captured_leader"), "value": v})
		if Prison._leader_captured(game, p.war, p.war.attacker, "def"):
			out.append({"label": game.loc.t("ui.ws_captured_leader"), "value": -v})
		return out
	, 0, OWNER)
	# Пленники не правят: ИИ не думает за них.
	engine.hooks.on("ai.think", func(p): return false if p.character.get("prison") != null else null, 100, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	var target := func(ctx: ScriptContext, s: Variant, arg: Variant) -> Variant:
		return ch.call(ctx, Interp.resolve_scope(ctx, s, arg))
	var yes := func(arg: Variant) -> bool: return arg == null or ScriptContext.is_yes(arg)
	r.triggers.register("is_imprisoned", {"scopes": CH, "doc": "В темнице",
		"eval": func(ctx, s, arg): return Prison.is_imprisoned(ch.call(ctx, s)) == yes.call(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_imprisoned" if yes.call(arg) else "tr.is_imprisoned.not"),
	}, OWNER)
	r.triggers.register("is_imprisoned_by", {"scopes": CH, "doc": "В темнице у персонажа",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var j: Variant = target.call(ctx, s, arg)
			return c != null and c.get("prison") != null and j != null and c.prison.by == j.id,
		"describe": func(ctx, _s, _arg): return ctx.game.loc.t("tr.is_imprisoned_by"),
	}, OWNER)
	r.triggers.register("has_imprisonment_reason", {"scopes": CH, "doc": "Есть законный повод заключить персонажа (преступление против этого персонажа)",
		"eval": func(ctx, s, arg):
			var j: Variant = ch.call(ctx, s)
			var t: Variant = target.call(ctx, s, arg)
			return j != null and t != null and Prison.has_imprisonment_reason(ctx.game, j, t),
		"describe": func(ctx, _s, _arg): return ctx.game.loc.t("tr.has_imprisonment_reason"),
	}, OWNER)
	r.values.register("prison_months", {"scopes": CH, "doc": "Сколько месяцев персонаж в темнице", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return floorf((ctx.game.date - int(c.prison.since)) / 30.0) if (c != null and c.get("prison") != null) else 0.0
	}, OWNER)
	r.values.register("ransom_cost", {"scopes": CH, "doc": "Размер выкупа за пленника", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(Prison.ransom_cost(ctx.game, c)) if c != null else 0.0
	}, OWNER)
	r.values.register("num_prisoners", {"scopes": CH, "doc": "Число пленников", "get": func(ctx, s, _a): return float(Prison.prisoners_of(ctx.game, s.id).size())}, OWNER)
	r.lists.register("prisoner", {"from": CH, "doc": "Пленники персонажа", "list": func(ctx, s):
		return Prison.prisoners_of(ctx.game, s.id).map(func(c): return {"type": "character", "id": c.id})
	}, OWNER)
	r.effects.register("imprison", {"scopes": CH, "doc": "Заключить персонажа в свою темницу: imprison: scope:x или { target, reason }",
		"apply": func(ctx, s, arg):
			var j: Variant = ch.call(ctx, s)
			var t: Variant = target.call(ctx, s, arg.get("target") if arg is Dictionary else arg)
			if j != null and t != null:
				Prison.imprison(ctx.game, j, t, arg.get("reason") if arg is Dictionary else null),
		"describe": func(ctx, s, arg):
			var t: Variant = target.call(ctx, s, arg.get("target") if arg is Dictionary else arg)
			return ctx.game.loc.t("fx.imprison", {"who": ctx.game.scope_name({"type": "character", "id": t.id})}) if t != null else null,
	}, OWNER)
	r.effects.register("release_from_prison", {"scopes": CH, "doc": "Освободить этого персонажа из темницы",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				Prison.release(ctx.game, c, arg if (arg is String and arg != "yes") else "released"),
		"describe": func(ctx, s, _arg): return ctx.game.loc.t("fx.release_from_prison", {"who": ctx.game.scope_name(s)}),
	}, OWNER)
	r.effects.register("mark_criminal", {"scopes": CH, "doc": "Даёт target законный повод заключить этого персонажа: { target, years }",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var t: Variant = target.call(ctx, s, arg.get("target") if arg is Dictionary else arg)
			if c == null or t == null:
				return
			var years := Data.num(arg.get("years")) if arg is Dictionary else 0.0
			c.flags["criminal:" + t.id] = ctx.game.date + roundi(years * 365) if years > 0 else 0,
		"describe": func(_ctx, _s, _arg): return null,
	}, OWNER)
	engine.interaction_deciders.register("payer", {"decider": func(game: Game, recipient: Dictionary, _actor: Variant) -> Dictionary: return Prison.ransom_payer(game, recipient)}, OWNER)

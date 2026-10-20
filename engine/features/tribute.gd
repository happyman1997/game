class_name Tribute
extends EngineFeature
## Дань: независимый правитель, проигравший войну за дань (или купивший ею
## мир), платит победителю долю своих податей — с домена и с вассалов —
## столько-то лет. Дань видна строками казны («Дань уплачена» и «Дань
## получена»), данник не любит господина, а данником или господином
## становится и наследник. Данник, ставший чьим-то вассалом, перестаёт
## платить; отказаться платить можно решением — но господин этого не простит.
##
## Данные:
##   defines.tribute: { share — доля податей, years — срок по умолчанию,
##     opinion — мнение данника о господине }
## Состояние: данник — c.vars.tribute = { to, until, share }.
## Скрипт: условия is_tributary, is_tributary_of; значение num_tributaries,
## tribute_amount; ссылка tribute_suzerain; список tributary; эффекты
## make_tributary: { to, years, share }, end_tribute. Повод к войне — цели
## cb_targets.tribute (независимые соседи, ещё не данники).

const OWNER := "core/tribute"
const INDEX := "tribute:index"


func _init() -> void:
	id = "tribute"
	doc = "Дань: доля податей данника — победителю войны за дань"


## Господин данника (или null).
static func suzerain_of(game: Game, c: Dictionary) -> Variant:
	var t: Variant = c.vars.get("tribute")
	if not (t is Dictionary):
		return null
	if t.get("until") != null and int(t.until) <= game.date:
		return null
	var s: Variant = game.ch(str(t.to))
	return s if s != null and Chars.is_alive(s) else null


## Данники правителя (индекс на месяц).
static func tributaries_of(game: Game, c: Dictionary) -> Array:
	var idx: Dictionary = game.cached_monthly(INDEX, func():
		var m := {}
		for r in game.rulers():
			var s: Variant = Tribute.suzerain_of(game, r)
			if s != null:
				if not m.has(s.id):
					m[s.id] = []
				m[s.id].append(r.id)
		return m)
	return Data.as_array(idx.get(c.id, [])).map(func(id): return game.ch(id)).filter(func(x): return x != null and Chars.is_alive(x))


## Сколько данник платит в месяц: доля податей с домена и вассалов.
static func amount(game: Game, c: Dictionary) -> float:
	var t: Variant = c.vars.get("tribute")
	if suzerain_of(game, c) == null:
		return 0.0
	var base := Economy.domain_tax(game, c)
	for v in game.vassals_of(c.id):
		base += Economy.vassal_tax_to(game, c, v)
	return maxf(0.0, base) * Data.num(t.get("share"), game.def_num("tribute.share", 0.2))


static func make(game: Game, payer: Dictionary, to: Dictionary, years: float = -1.0, share: float = -1.0) -> void:
	if payer.id == to.id or payer.titles.is_empty():
		return
	var y := years if years > 0.0 else game.def_num("tribute.years", 10)
	payer.vars["tribute"] = {"to": to.id, "until": game.date + roundi(y * 365.0), "share": share if share > 0.0 else game.def_num("tribute.share", 0.2)}
	game.month_cache.erase(INDEX)
	game.stat_cache.erase("op:%s>%s" % [payer.id, to.id])
	game.emit("tribute.started", {"payer": payer, "suzerain": to})
	game.message(game.loc.t("msg.tribute_started", {"payer": game.scope_name({"type": "character", "id": payer.id}), "to": game.scope_name({"type": "character", "id": to.id})}),
		"info", {"type": "character", "id": payer.id}, [payer.id, to.id])


static func end(game: Game, payer: Dictionary, reason: String = "ended") -> void:
	var t: Variant = payer.vars.get("tribute")
	if not (t is Dictionary):
		return
	payer.vars.erase("tribute")
	game.month_cache.erase(INDEX)
	game.stat_cache.erase("op:%s>%s" % [payer.id, str(t.to)])
	game.emit("tribute.ended", {"payer": payer, "suzerain": str(t.to), "reason": reason})
	if game.is_player(payer.id) or game.is_player(str(t.to)):
		game.message(game.loc.t("msg.tribute_" + reason, {"payer": game.scope_name({"type": "character", "id": payer.id}), "to": game.scope_name({"type": "character", "id": str(t.to)})}),
			"info", {"type": "character", "id": payer.id})


## Раз в месяц: дань истекает, кончается у тех, кто стал вассалом.
static func monthly(game: Game) -> void:
	for c in game.rulers():
		var t: Variant = c.vars.get("tribute")
		if not (t is Dictionary):
			continue
		if c.liege != null:
			end(game, c, "vassalized")
		elif t.get("until") != null and int(t.until) <= game.date:
			end(game, c, "expired")
		elif suzerain_of(game, c) == null:
			end(game, c, "ended")


func install(engine: GameEngine) -> void:
	engine.systems.register("tribute", {"id": "tribute", "order": 56, "on_month": Tribute.monthly}, OWNER)
	# строки казны: данник платит, господин получает
	engine.hooks.on("economy.income", func(p):
		var v := Tribute.amount(p.game, p.character)
		return {"label": p.game.loc.t("ui.tribute_paid"), "value": -v, "key": "tribute_paid"} if v > 0.0 else null
	, 0, OWNER)
	engine.hooks.on("economy.income", func(p):
		var sum := 0.0
		for t in Tribute.tributaries_of(p.game, p.character):
			sum += Tribute.amount(p.game, t)
		return {"label": p.game.loc.t("ui.tribute_received"), "value": sum, "key": "tribute_received"} if sum > 0.0 else null
	, 0, OWNER)
	# данник не любит господина
	engine.opinion_providers.register("tribute", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		var s: Variant = Tribute.suzerain_of(game, a)
		if s == null or s.id != b.id:
			return null
		return [{"label": game.loc.t("opinion.pays_tribute"), "value": game.def_num("tribute.opinion", -15)}]
	}, OWNER)
	# наследник данника продолжает платить, наследник господина — получать
	engine.hooks.on("succession", func(p):
		var game: Game = p.game
		var dead: Dictionary = p.deceased
		var heir: Variant = game.ch(p.primary)
		if heir == null or heir.titles.is_empty() or heir.liege != null:
			return
		var t: Variant = dead.vars.get("tribute")
		if t is Dictionary and heir.id != str(t.to):
			heir.vars["tribute"] = t.duplicate()
		for r in game.rulers():
			var rt: Variant = r.vars.get("tribute")
			if rt is Dictionary and str(rt.to) == dead.id and r.id != heir.id:
				rt.to = heir.id
		game.month_cache.erase(INDEX)
	, 0, OWNER)
	# повод: независимые соседи, ещё не данники
	engine.cb_targets.register("tribute", {"targets": func(game: Game, attacker: Dictionary) -> Array:
		if attacker.liege != null:
			return []
		var mine := {}
		for x in Titles.realm_counties(game, attacker):
			mine[x] = true
		var seen := {}
		var out := []
		for cid in mine:
			for n in game.engine.neighbors(cid):
				if mine.has(n):
					continue
				var h: Variant = game.ch(game.state.titles[n].holder) if game.state.titles.has(n) and game.state.titles[n].holder != null else null
				if h == null:
					continue
				var top := Titles.top_liege(game, h)
				if top.id == attacker.id or seen.has(top.id) or Tribute.suzerain_of(game, top) != null or top.titles.is_empty():
					continue
				seen[top.id] = true
				out.append({"defender": top.id, "title": top.titles[0], "counties": Titles.domain_counties(game, top)})
		return out}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	r.triggers.register("is_tributary", {"scopes": CH, "doc": "Платит кому-то дань: is_tributary: yes", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return c != null and (Tribute.suzerain_of(ctx.game, c) != null) == ScriptContext.is_yes(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_tributary" if ScriptContext.is_yes(arg) else "tr.is_tributary.not"),
	}, OWNER)
	r.triggers.register("is_tributary_of", {"scopes": CH, "doc": "Платит дань этому персонажу: is_tributary_of: scope:x", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var o: Variant = Interp.resolve_scope(ctx, s, arg)
		var su: Variant = Tribute.suzerain_of(ctx.game, c) if c != null else null
		return su != null and o is Dictionary and su.id == o.get("id"),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("tr.is_tributary_of", {"who": ctx.game.scope_name(Interp.resolve_scope(ctx, s, arg))}),
	}, OWNER)
	r.values.register("num_tributaries", {"scopes": CH, "doc": "Число данников", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(Tribute.tributaries_of(ctx.game, c).size()) if c != null else 0.0
	}, OWNER)
	r.values.register("tribute_amount", {"scopes": CH, "doc": "Сколько данник платит в месяц", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Tribute.amount(ctx.game, c) if c != null else 0.0
	}, OWNER)
	r.links.register("tribute_suzerain", {"from": CH, "doc": "Кому персонаж платит дань", "resolve": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		var su: Variant = Tribute.suzerain_of(ctx.game, c) if c != null else null
		return {"type": "character", "id": su.id} if su != null else null
	}, OWNER)
	r.lists.register("tributary", {"from": CH, "doc": "Данники персонажа", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		return Tribute.tributaries_of(ctx.game, c).map(func(x): return {"type": "character", "id": x.id}) if c != null else []
	}, OWNER)
	r.effects.register("make_tributary", {"scopes": CH, "doc": "Сделать персонажа данником: make_tributary: { to: scope:attacker, years: 10, share: 0.2 } (или make_tributary: scope:x)", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var to_ref: Variant = Interp.resolve_scope(ctx, s, arg.get("to") if arg is Dictionary else arg)
		var to: Variant = ctx.game.ch(to_ref.id) if to_ref is Dictionary and to_ref.get("type") == "character" else null
		if c != null and to != null:
			var years := Interp.eval_value(ctx, s, arg.get("years")) if arg is Dictionary and arg.get("years") != null else -1.0
			var share := Interp.eval_value(ctx, s, arg.get("share")) if arg is Dictionary and arg.get("share") != null else -1.0
			Tribute.make(ctx.game, c, to, years, share),
		"describe": func(ctx, s, arg):
			var to_ref: Variant = Interp.resolve_scope(ctx, s, arg.get("to") if arg is Dictionary else arg)
			return ctx.game.loc.t("fx.make_tributary", {"who": ctx.game.scope_name(s), "to": ctx.game.scope_name(to_ref) if to_ref is Dictionary else "?"}),
	}, OWNER)
	r.effects.register("end_tribute", {"scopes": CH, "doc": "Перестать платить дань: end_tribute: yes", "apply": func(ctx, s, _arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			Tribute.end(ctx.game, c, "refused"),
		"describe": func(ctx, s, _arg): return ctx.game.loc.t("fx.end_tribute", {"who": ctx.game.scope_name(s)}),
	}, OWNER)

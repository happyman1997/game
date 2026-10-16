class_name Ambitions
extends EngineFeature
## Желания: у каждого заметного персонажа (правителя, вассала, знатного
## придворного) одно видимое желание, выведенное из его характера и
## положения, — получить земли, место в совете, брак, отомстить сопернику,
## разбогатеть… Исполненное желание приносит благодарность тому, кто помог
## (обычно сюзерену), неисполненное — копит обиду, а брошенное — оставляет
## её надолго. У игрока своё желание: он выбирает его из трёх предложенных,
## и исполнение даёт награду.
##
##   ambitions: { <id>: {
##     icon, order,
##     is_valid:  условие — может ли персонаж этого хотеть (root — персонаж);
##     weight:    значение — насколько хочет (вес случайного выбора);
##     target:    { from?: ссылка (liege), list: список, trigger?, weight? } —
##                цель желания (scope:target; в trigger и weight — скоуп цели,
##                scope:owner — сам персонаж);
##     progress:  { value: значение, need: значение } — исполнено, когда value
##                выросло на need с начала желания;
##     fulfilled: условие — исполнено (вместо или вместе с progress);
##     failed:    условие — стало невозможным (scope:target, scope:patron —
##                сюзерен);
##     min_years, patience, expire — не раньше; терпение (после него —
##                обида на сюзерена); через сколько лет желание бросают;
##     credit: liege   — благодарность и обида достаются сюзерену;
##     credit_if:      условие — благодарность только если оно выполнено;
##     grant: { gold?, prestige?, effect } — сюзерен может исполнить желание
##                сам (взаимодействие fulfill_ambition): цена и эффект;
##     council_bonus — насколько охотнее ИИ даёт место в совете;
##     player: no     — не предлагать игроку;
##     on_fulfilled, on_failed, on_expired — эффекты (scope:target,
##                scope:patron) } }
##   defines.ambitions: { monthly_chance, cooldown_years, offers,
##     frustration_per_year, frustration_max }
## Состояние: c.vars.ambition = {id, target, since, base, need, patron};
## c.vars.ambition_cd — не раньше этой даты новое; c.vars.ambition_offers —
## варианты для игрока.
## Хуки: ambition.started, ambition.fulfilled, ambition.failed,
## ambition.expired — {character, ambition, target, patron}.

const OWNER := "core/ambitions"


func _init() -> void:
	id = "ambitions"
	doc = "Желания персонажей: цели из характера, благодарность и обида сюзерену"


static func _n(game: Game, key: String, def: float) -> float:
	return game.def_num("ambitions." + key, def)


static func def_of(game: Game, aid: Variant) -> Variant:
	return game.content.get_def("ambitions", str(aid)) if aid != null else null


static func current(c: Dictionary) -> Variant:
	var a: Variant = c.vars.get("ambition")
	return a if a is Dictionary else null


## Заметный персонаж: правитель или знатный взрослый при дворе.
static func eligible(game: Game, c: Dictionary) -> bool:
	if not Chars.is_alive(c) or not Chars.is_adult(game, c) or c.get("prison") != null:
		return false
	return not c.titles.is_empty() or (c.liege != null and c.dynasty != null)


static func _ctx(game: Game, c: Dictionary, target: Variant, patron: Variant = null) -> ScriptContext:
	var scopes := {"owner": {"type": "character", "id": c.id}}
	if target is Dictionary:
		scopes["target"] = target
	var p: Variant = patron if patron != null else c.liege
	if p != null:
		scopes["patron"] = {"type": "character", "id": str(p)}
	return ScriptContext.make(game, {"type": "character", "id": c.id}, scopes)


## Цели желания: [{scope, weight}].
static func _targets(game: Game, c: Dictionary, d: Dictionary) -> Array:
	var spec: Variant = d.get("target")
	if not (spec is Dictionary):
		return []
	var ctx := _ctx(game, c, null)
	var from: Variant = ctx.root
	if spec.get("from") != null:
		from = Interp.resolve_scope(ctx, ctx.root, str(spec.from))
		if from == null:
			return []
	var lst: Variant = game.engine.scripting.lists.get_item(str(spec.get("list")))
	if lst == null:
		return []
	var out := []
	for ref in lst.list.call(ctx, from):
		if ref is Dictionary and ref.get("type") == "character" and ref.id == c.id:
			continue
		if spec.get("trigger") != null and not Interp.eval_trigger(ctx, ref, spec.trigger):
			continue
		var w := Interp.eval_value(ctx, ref, spec.weight) if spec.get("weight") != null else 1.0
		if w > 0.0:
			out.append({"scope": ref, "weight": w})
	return out


## Варианты желаний для персонажа: [{id, target, weight}].
static func options(game: Game, c: Dictionary, for_player: bool = false) -> Array:
	var out := []
	var ctx := _ctx(game, c, null)
	for d in game.content.all("ambitions"):
		if for_player and d.get("player", true) == false:
			continue
		if not Interp.eval_trigger(ctx, ctx.root, d.get("is_valid")):
			continue
		var w := Interp.eval_value(ctx, ctx.root, d.get("weight", 10))
		if w <= 0.0:
			continue
		var target: Variant = null
		if d.get("target") != null:
			var ts := _targets(game, c, d)
			if ts.is_empty():
				continue
			var pick: Variant = game.rng.weighted(ts, func(t): return t.weight)
			target = pick.scope if pick != null else null
			if target == null:
				continue
		out.append({"id": d.id, "target": target, "weight": w})
	return out


static func start(game: Game, c: Dictionary, aid: String, target: Variant = null) -> bool:
	var d: Variant = def_of(game, aid)
	if d == null:
		return false
	var a := {"id": aid, "target": target, "since": game.date, "patron": c.liege}
	var pr: Variant = d.get("progress")
	if pr is Dictionary:
		var ctx := _ctx(game, c, target)
		a["base"] = Interp.eval_value(ctx, ctx.root, pr.get("value"))
		a["need"] = maxf(1.0, Interp.eval_value(ctx, ctx.root, pr.get("need", 1)))
	c.vars["ambition"] = a
	c.vars.erase("ambition_offers")
	game.mark_chars_dirty([c.id])
	game.emit("ambition.started", {"character": c, "ambition": aid, "target": target})
	return true


## Ход желания: {done, need} для progress (или null).
static func progress_of(game: Game, c: Dictionary) -> Variant:
	var a: Variant = current(c)
	var d: Variant = def_of(game, a.id) if a != null else null
	if d == null or not (d.get("progress") is Dictionary) or a.get("base") == null:
		return null
	var ctx := _ctx(game, c, a.get("target"), a.get("patron"))
	var now := Interp.eval_value(ctx, ctx.root, d.progress.get("value"))
	return {"done": maxf(0.0, now - float(a.base)), "need": float(a.need)}


static func years_of(game: Game, c: Dictionary) -> float:
	var a: Variant = current(c)
	return (game.date - int(a.since)) / float(GameDate.DAYS_PER_YEAR) if a != null else 0.0


## Насколько обижен на сюзерена (0 — пока терпит).
static func frustration(game: Game, c: Dictionary) -> float:
	var a: Variant = current(c)
	var d: Variant = def_of(game, a.id) if a != null else null
	if d == null or d.get("credit") != "liege" or not game.ai_controls(c.id):
		return 0.0
	var over := years_of(game, c) - Data.num(d.get("patience"), 3)
	if over <= 0.0:
		return 0.0
	return minf(_n(game, "frustration_max", 30), (1.0 + floorf(over)) * _n(game, "frustration_per_year", 6))


## Проверка желания: исполнено, невозможно или брошено.
static func check(game: Game, c: Dictionary) -> void:
	var a: Variant = current(c)
	var d: Variant = def_of(game, a.id) if a != null else null
	if d == null:
		c.vars.erase("ambition")
		return
	var target: Variant = a.get("target")
	# цель-персонаж умерла — проверка fulfilled ниже решит (месть), иначе невозможно
	var ctx := _ctx(game, c, target, a.get("patron"))
	var years := years_of(game, c)
	var done := false
	if years >= Data.num(d.get("min_years"), 0):
		var pr: Variant = progress_of(game, c)
		if pr != null and float(pr.done) >= float(pr.need):
			done = true
		if not done and d.get("fulfilled") != null and Interp.eval_trigger(ctx, ctx.root, d.fulfilled):
			done = true
	if done:
		finish(game, c, "fulfilled")
		return
	if target is Dictionary and target.get("type") == "character" and not game.is_alive(target.id):
		finish(game, c, "failed")
		return
	if d.get("failed") != null and Interp.eval_trigger(ctx, ctx.root, d.failed):
		finish(game, c, "failed")
		return
	if years >= Data.num(d.get("expire"), 8):
		finish(game, c, "expired")


## Завершить желание: result — fulfilled | failed | expired.
static func finish(game: Game, c: Dictionary, result: String, patron_override: Variant = null) -> void:
	var a: Variant = current(c)
	if a == null:
		return
	var d: Variant = def_of(game, a.id)
	var patron_id: Variant = patron_override if patron_override != null else c.liege
	var patron: Variant = game.ch(patron_id) if patron_id != null else null
	var ctx := _ctx(game, c, a.get("target"), patron_id)
	c.vars.erase("ambition")
	c.vars["ambition_cd"] = game.date + roundi(_n(game, "cooldown_years", 2) * GameDate.DAYS_PER_YEAR)
	if d != null:
		Interp.run_effect(ctx, ctx.root, d.get("on_" + result))
		# благодарность и обида — сюзерену (или тому, кто исполнил)
		var credit: bool = d.get("credit") == "liege" or patron_override != null
		if credit and patron != null and Chars.is_alive(patron) and patron.id != c.id and game.ai_controls(c.id):
			if result == "fulfilled":
				if d.get("credit_if") == null or patron_override != null or Interp.eval_trigger(ctx, ctx.root, d.credit_if):
					Opinion.add_opinion(game, c, patron, "ambition_fulfilled")
			elif result == "expired":
				Opinion.add_opinion(game, c, patron, "ambition_ignored")
	game.mark_chars_dirty([c.id, patron_id])
	game.emit("ambition." + result, {"character": c, "ambition": a.id, "target": a.get("target"), "patron": patron_id})
	# сообщения игроку: своё желание и желания его двора
	var p: Variant = game.state.player
	if p != null and (c.id == p or patron_id == p):
		var name := describe_name(game, c, a)
		var key := "msg.ambition_%s%s" % [result, "_own" if c.id == p else ""]
		var kind := "good" if result == "fulfilled" else "bad"
		game.message(game.loc.t(key, {"who": game.scope_name({"type": "character", "id": c.id}), "name": name}), kind,
			{"type": "character", "id": c.id}, [c.id, patron_id])


## Название желания с целью: «Получить графство Руан».
static func describe_name(game: Game, c: Dictionary, a: Dictionary) -> String:
	var t: Variant = a.get("target")
	var tname := game.scope_name(t) if t is Dictionary else ""
	return game.loc.t("ambition." + str(a.id), {"target": tname})


## Помесячно: проверить желание или (с перерывом) завести новое.
static func monthly_char(game: Game, c: Dictionary) -> void:
	if current(c) != null:
		if c.get("prison") == null:
			check(game, c)
		return
	if not eligible(game, c):
		return
	var cd: Variant = c.vars.get("ambition_cd")
	if cd != null and int(cd) > game.date:
		return
	if not game.ai_controls(c.id):
		if not (c.vars.get("ambition_offers") is Array):
			_make_offers(game, c)
		return
	if not game.rng.chance(_n(game, "monthly_chance", 0.08)):
		return
	var opts := options(game, c)
	var pick: Variant = game.rng.weighted(opts, func(o): return o.weight)
	if pick != null:
		start(game, c, pick.id, pick.target)


## Игроку — несколько желаний на выбор.
static func _make_offers(game: Game, c: Dictionary) -> void:
	var opts := options(game, c, true)
	var out := []
	var n := int(_n(game, "offers", 3))
	while not opts.is_empty() and out.size() < n:
		var pick: Variant = game.rng.weighted(opts, func(o): return o.weight)
		if pick == null:
			break
		opts.erase(pick)
		out.append({"id": pick.id, "target": pick.target})
	if not out.is_empty():
		c.vars["ambition_offers"] = out


static func offers(c: Dictionary) -> Array:
	var o: Variant = c.vars.get("ambition_offers")
	return o if o is Array else []


## Игрок выбрал желание из предложенных (index) или отказался (-1).
static func choose_offer(game: Game, c: Dictionary, index: int) -> void:
	var o := offers(c)
	c.vars.erase("ambition_offers")
	if index >= 0 and index < o.size():
		start(game, c, str(o[index].id), o[index].get("target"))
	else:
		c.vars["ambition_cd"] = game.date + GameDate.DAYS_PER_YEAR


## Отказаться от своего желания (игрок): немного стресса и перерыв.
static func abandon(game: Game, c: Dictionary) -> void:
	if current(c) == null:
		return
	c.vars.erase("ambition")
	c.vars["ambition_cd"] = game.date + GameDate.DAYS_PER_YEAR
	Chars.change_stress(game, c, _n(game, "abandon_stress", 10), "ambition")
	game.mark_chars_dirty([c.id])


## Может ли patron исполнить желание сам (grant).
static func grantable_by(game: Game, c: Dictionary, patron: Dictionary) -> bool:
	var a: Variant = current(c)
	var d: Variant = def_of(game, a.id) if a != null else null
	return d != null and d.get("grant") is Dictionary and c.liege == patron.id and game.ai_controls(c.id)


static func grant_cost(game: Game, c: Dictionary, kind: String) -> float:
	var a: Variant = current(c)
	var d: Variant = def_of(game, a.id) if a != null else null
	if d == null or not (d.get("grant") is Dictionary) or d.grant.get(kind) == null:
		return 0.0
	var ctx := _ctx(game, c, a.get("target"), a.get("patron"))
	return maxf(0.0, roundf(Interp.eval_value(ctx, ctx.root, d.grant.get(kind))))


## Исполнить желание персонажа силами patron: эффект grant и благодарность ему.
static func grant(game: Game, c: Dictionary, patron: Dictionary) -> void:
	var a: Variant = current(c)
	var d: Variant = def_of(game, a.id) if a != null else null
	if d == null or not (d.get("grant") is Dictionary):
		return
	var ctx := _ctx(game, c, a.get("target"), patron.id)
	Interp.run_effect(ctx, ctx.root, d.grant.get("effect"))
	finish(game, c, "fulfilled", patron.id)


## Недовольные среди двора и вассалов персонажа (кэш на месяц).
static func frustrated_of(game: Game, liege: Dictionary) -> Array:
	return game.cached_monthly("amb_fr:" + liege.id, func():
		var out := []
		for x in game.vassals_of(liege.id) + game.courtiers_of(liege.id):
			if Ambitions.frustration(game, x) > 0.0:
				out.append(x)
		return out)


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("ambitions", {"id": "ambitions", "order": 16, "on_character_month": Ambitions.monthly_char}, OWNER)
	# обида на сюзерена за неисполненное желание
	engine.opinion_providers.register("ambitions", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		if a.liege != b.id or not (a.vars.get("ambition") is Dictionary):
			return null
		var f := Ambitions.frustration(game, a)
		if f <= 0.0:
			return null
		var am: Dictionary = a.vars.ambition
		return {"label": game.loc.t("opinion.ambition_frustrated", {"name": Ambitions.describe_name(game, a, am)}), "value": -f}
	}, OWNER)
	# ИИ охотнее сажает в совет тех, кто об этом мечтает
	engine.hooks.on("council.candidate_score", func(p):
		var a: Variant = Ambitions.current(p.candidate)
		var d: Variant = Ambitions.def_of(p.game, a.id) if a != null else null
		return Data.num(d.get("council_bonus")) if d != null else null
	, 0, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	const CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s is Dictionary and s.get("type") == "character") else null
	var other := func(ctx: ScriptContext, s: Variant, arg: Variant) -> Variant:
		var o: Variant = Interp.resolve_scope(ctx, s, arg)
		return ctx.game.ch(o.id) if (o is Dictionary and o.get("type") == "character") else null

	r.triggers.register("has_ambition", {"scopes": CH, "doc": "Есть желание (yes/no) или именно это: has_ambition: land", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var a: Variant = Ambitions.current(c) if c != null else null
		if arg is bool or arg == null or str(arg) in ["yes", "no"]:
			return (a != null) == (arg == null or ScriptContext.is_yes(arg))
		return a != null and str(a.id) == str(arg),
		"describe": func(ctx, _s, arg):
			if arg is bool or arg == null or str(arg) in ["yes", "no"]:
				return ctx.game.loc.t("tr.has_any_ambition" + ("" if arg == null or ScriptContext.is_yes(arg) else ".not"))
			return ctx.game.loc.t("tr.has_ambition", {"value": ctx.game.loc.t_or("ambition_short." + str(arg), str(arg))}),
	}, OWNER)
	r.triggers.register("ambition_target_is", {"scopes": CH, "doc": "Цель желания — этот скоуп: ambition_target_is: scope:target", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var a: Variant = Ambitions.current(c) if c != null else null
		var t: Variant = Interp.resolve_scope(ctx, s, arg)
		return a != null and a.get("target") is Dictionary and t is Dictionary and a.target.get("id") == t.get("id"),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("tr.ambition_target_is", {"value": ctx.game.scope_name(Interp.resolve_scope(ctx, s, arg))}),
	}, OWNER)
	r.triggers.register("ambition_frustrated", {"scopes": CH, "doc": "Желание давно не исполняется — копится обида", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return (c != null and Ambitions.frustration(ctx.game, c) > 0.0) == (arg == null or ScriptContext.is_yes(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.ambition_frustrated" + ("" if arg == null or ScriptContext.is_yes(arg) else ".not")),
	}, OWNER)
	r.triggers.register("ambition_grantable_by", {"scopes": CH, "doc": "Сюзерен может исполнить желание сам: ambition_grantable_by: scope:actor", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var o: Variant = other.call(ctx, s, arg)
		return c != null and o != null and Ambitions.grantable_by(ctx.game, c, o),
		"describe": func(ctx, _s, _arg): return ctx.game.loc.t("tr.ambition_grantable_by"),
	}, OWNER)
	r.values.register("ambition_frustration", {"scopes": CH, "doc": "Обида за неисполненное желание (0 — терпит)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Ambitions.frustration(ctx.game, c) if c != null else 0.0
	}, OWNER)
	r.values.register("ambition_remaining", {"scopes": CH, "doc": "Сколько осталось до исполнения желания (по progress)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		var pr: Variant = Ambitions.progress_of(ctx.game, c) if c != null else null
		return maxf(0.0, float(pr.need) - float(pr.done)) if pr != null else 0.0
	}, OWNER)
	r.values.register("ambition_grant_gold", {"scopes": CH, "doc": "Цена исполнения желания сюзереном: золото", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Ambitions.grant_cost(ctx.game, c, "gold") if c != null else 0.0
	}, OWNER)
	r.values.register("ambition_grant_prestige", {"scopes": CH, "doc": "Цена исполнения желания сюзереном: престиж", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Ambitions.grant_cost(ctx.game, c, "prestige") if c != null else 0.0
	}, OWNER)
	r.values.register("num_well_educated_children", {"scopes": CH, "doc": "Детей с образованием не ниже 3-го уровня", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		if c == null:
			return 0.0
		var n := 0
		for cid in c.children:
			var x: Variant = ctx.game.ch(cid)
			if x == null:
				continue
			for t in x.traits:
				var d: Variant = ctx.game.content.get_def("traits", t)
				if d != null and d.get("education") is Dictionary and int(d.education.get("level", 1)) >= 3:
					n += 1
					break
		return float(n)
	}, OWNER)
	r.effects.register("start_ambition", {"scopes": CH, "doc": "Завести желание: start_ambition: land (цель — случайная подходящая)", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c == null or Ambitions.current(c) != null:
			return
		for o in Ambitions.options(ctx.game, c):
			if o.id == str(arg):
				Ambitions.start(ctx.game, c, o.id, o.target)
				return,
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.start_ambition", {"value": ctx.game.loc.t_or("ambition_short." + str(arg), str(arg))}),
	}, OWNER)
	r.effects.register("fulfill_ambition", {"scopes": CH, "doc": "Исполнить желание персонажа (благодарность — patron): fulfill_ambition: scope:actor", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var o: Variant = other.call(ctx, s, arg)
		if c != null and o != null and Ambitions.current(c) != null:
			Ambitions.grant(ctx.game, c, o),
		"describe": func(ctx, s, _arg): return ctx.game.loc.t("fx.fulfill_ambition", {"who": ctx.game.scope_name(s)}),
	}, OWNER)
	r.effects.register("clear_ambition", {"scopes": CH, "doc": "Снять желание без последствий: clear_ambition: yes", "apply": func(ctx, s, _arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			c.vars.erase("ambition"),
		"describe": func(ctx, s, _arg): return ctx.game.loc.t("fx.clear_ambition", {"who": ctx.game.scope_name(s)}),
	}, OWNER)
	# списки для целей желаний
	r.lists.register("rival", {"from": CH, "doc": "Соперники и кровные враги персонажа", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		if c == null:
			return []
		var out := []
		for tid in c.opinions:
			if not ctx.game.is_alive(tid):
				continue
			for e in c.opinions[tid]:
				var od: Variant = ctx.game.content.get_def("opinion_modifiers", e.mod)
				if e.mod == "rival" or (od != null and od.get("feud", false)):
					out.append({"type": "character", "id": tid})
					break
		return out
	}, OWNER)
	r.lists.register("grantable_title", {"from": CH, "doc": "Титулы, которые персонаж может пожаловать (графства домена кроме столицы, лишние герцогства)", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		if c == null or c.titles.is_empty():
			return []
		var g: Game = ctx.game
		var out := []
		for t in Titles.domain_counties(g, c):
			if t != c.capital:
				out.append({"type": "title", "id": t})
		for t in c.titles:
			var d: Variant = g.content.get_def("titles", t)
			if d != null and d.tier == "duchy" and t != c.titles[0]:
				out.append({"type": "title", "id": t})
		return out
	}, OWNER)

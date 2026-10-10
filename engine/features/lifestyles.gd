class_name Lifestyles
extends EngineFeature
## Образ жизни (lifestyles). Взрослый персонаж выбирает фокус одного из
## образов жизни, каждый месяц копит опыт этого образа жизни и тратит его на
## перки — узлы деревьев. Последний перк дерева обычно даёт черту.
##
## Данные:
##   lifestyles:   { skill, secondary_skill, secondary_share, xp_mult, icon, color, order, is_shown }
##   focuses:      { lifestyle, icon, modifiers, is_shown, ai_will_do }
##   perks:        { lifestyle, tree, requires, icon, modifiers, trait, effect, ai_will_do }
##   defines.lifestyle: { base_xp, xp_per_skill, perk_cost, perk_cost_growth, focus_change_cooldown_months }

const OWNER := "core/lifestyles"


func _init() -> void:
	id = "lifestyles"
	doc = "Образ жизни: фокусы, опыт и деревья перков"


static func state_of(c: Dictionary) -> Dictionary:
	if c.get("lifestyle") == null:
		c["lifestyle"] = {"focus": null, "focus_since": null, "xp": {}, "perks": []}
	return c.lifestyle


## Списки из контента кэшируются в engine.cache (контент после загрузки не меняется).
static func all(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("lifestyles:all")
	if hit != null:
		return hit
	var l := game.content.all("lifestyles").duplicate()
	Data.sort_by(l, func(x): return Data.num(x.get("order")))
	game.engine.cache["lifestyles:all"] = l
	return l


static func focuses_of(game: Game, lifestyle: String) -> Array:
	var key := "lifestyles:focuses:" + lifestyle
	var hit: Variant = game.engine.cache.get(key)
	if hit == null:
		hit = game.content.all("focuses").filter(func(f): return f.get("lifestyle") == lifestyle)
		game.engine.cache[key] = hit
	return hit


static func perks_of(game: Game, lifestyle: String) -> Array:
	var key := "lifestyles:perks:" + lifestyle
	var hit: Variant = game.engine.cache.get(key)
	if hit == null:
		hit = game.content.all("perks").filter(func(p): return p.get("lifestyle") == lifestyle)
		game.engine.cache[key] = hit
	return hit


static func _depth(game: Game, p: Dictionary, seen: Dictionary) -> int:
	if seen.has(p.id):
		return 0
	seen[p.id] = true
	var best := -1
	for r in Data.as_array(p.get("requires")):
		var rd: Variant = game.content.get_def("perks", r)
		if rd != null:
			best = maxi(best, _depth(game, rd, seen))
	return 0 if best < 0 else best + 1


## Деревья образа жизни: [{tree, perks}] — перки в порядке глубины (корни первыми).
static func trees_of(game: Game, lifestyle: String) -> Array:
	var by_tree := {}
	for p in perks_of(game, lifestyle):
		var t: String = str(p.get("tree", "main"))
		if not by_tree.has(t):
			by_tree[t] = []
		by_tree[t].append(p)
	var out := []
	for t in by_tree:
		var perks: Array = by_tree[t].duplicate()
		Data.sort_by(perks, func(p): return _depth(game, p, {}))
		out.append({"tree": t, "perks": perks})
	return out


static func current(game: Game, c: Dictionary) -> Variant:
	var st: Variant = c.get("lifestyle")
	if st == null or st.focus == null:
		return null
	var f: Variant = game.content.get_def("focuses", st.focus)
	return game.content.get_def("lifestyles", f.get("lifestyle")) if f != null else null


static func has_perk(c: Dictionary, perk: String) -> bool:
	return c.get("lifestyle") != null and c.lifestyle.perks.has(perk)


static func perk_cost(game: Game, c: Dictionary, lifestyle: String) -> int:
	var owned := 0
	if c.get("lifestyle") != null:
		for p in c.lifestyle.perks:
			var pd: Variant = game.content.get_def("perks", p)
			if pd != null and pd.get("lifestyle") == lifestyle:
				owned += 1
	return roundi(game.def_num("lifestyle.perk_cost", 300) + game.def_num("lifestyle.perk_cost_growth", 100) * owned)


static func requirements_met(_game: Game, c: Dictionary, perk: Dictionary) -> bool:
	for r in Data.as_array(perk.get("requires")):
		if not has_perk(c, r):
			return false
	return true


static func available_perks(game: Game, c: Dictionary, lifestyle: String) -> Array:
	return perks_of(game, lifestyle).filter(func(p): return not has_perk(c, p.id) and requirements_met(game, c, p))


static func xp_of(c: Dictionary, lifestyle: String) -> float:
	return Data.num(c.lifestyle.xp.get(lifestyle)) if c.get("lifestyle") != null else 0.0


static func can_unlock(game: Game, c: Dictionary, perk_id: String) -> bool:
	var p: Variant = game.content.get_def("perks", perk_id)
	if p == null or has_perk(c, perk_id) or not requirements_met(game, c, p):
		return false
	return xp_of(c, p.lifestyle) >= perk_cost(game, c, p.lifestyle)


## Открывает перк. free — без траты опыта (из скрипта).
static func unlock_perk(game: Game, c: Dictionary, perk_id: String, free: bool = false) -> bool:
	var p: Variant = game.content.get_def("perks", perk_id)
	if p == null or has_perk(c, perk_id):
		return false
	if not free and not can_unlock(game, c, perk_id):
		return false
	var st := state_of(c)
	if not free:
		st.xp[p.lifestyle] = xp_of(c, p.lifestyle) - perk_cost(game, c, p.lifestyle)
	st.perks.append(p.id)
	if p.get("trait") != null:
		Chars.add_trait(game, c, p.trait)
	if p.get("effect") != null:
		var ctx := ScriptContext.make(game, {"type": "character", "id": c.id}, {"perk_owner": {"type": "character", "id": c.id}})
		Interp.run_effect(ctx, ctx.root, p.effect)
	c.flags.erase("tmp:perk_notified")
	game.month_cache.erase("lifestyle:" + c.id)
	game.stat_cache.erase(c.id)
	game.emit("perk.gained", {"character": c, "perk": p.id})
	if game.is_player(c.id):
		game.message(game.loc.t("msg.perk_gained", {"perk": game.name_of("perks", p.id)}), "good")
	game.notify("character")
	return true


static func focus_change_blocked_until(game: Game, c: Dictionary) -> int:
	var st: Variant = c.get("lifestyle")
	if st == null or st.focus == null or st.get("focus_since") == null:
		return 0
	var until: int = int(st.focus_since) + roundi(game.def_num("lifestyle.focus_change_cooldown_months", 12) * 30)
	return until if until > game.date else 0


static func is_focus_shown(game: Game, c: Dictionary, focus_id: String) -> bool:
	var f: Variant = game.content.get_def("focuses", focus_id)
	if f == null:
		return false
	var l: Variant = game.content.get_def("lifestyles", f.get("lifestyle"))
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
	return Interp.eval_trigger(ctx, ctx.root, l.get("is_shown") if l != null else null) and Interp.eval_trigger(ctx, ctx.root, f.get("is_shown"))


static func set_focus(game: Game, c: Dictionary, focus_id: Variant, force: bool = false) -> bool:
	if focus_id != null and not game.content.has("focuses", focus_id):
		return false
	if not force and focus_change_blocked_until(game, c) > 0:
		return false
	var st := state_of(c)
	if st.focus == focus_id:
		return false
	st.focus = focus_id
	st.focus_since = game.date
	game.month_cache.erase("lifestyle:" + c.id)
	game.stat_cache.erase(c.id)
	game.emit("lifestyle.focus_changed", {"character": c, "focus": focus_id})
	return true


static func _modifiers(game: Game, c: Dictionary, st: Dictionary) -> Array:
	var out := []
	var f: Variant = game.content.get_def("focuses", st.focus) if st.focus != null else null
	if f != null and f.get("modifiers") is Dictionary and Chars.is_adult(game, c):
		var fid: String = f.id
		out.append({"label": func(): return game.loc.t("ui.focus_n", {"name": game.name_of("focuses", fid)}), "modifiers": f.modifiers})
	for pid in st.perks:
		var p: Variant = game.content.get_def("perks", pid)
		if p != null and p.get("modifiers") is Dictionary:
			var perk_id: String = pid
			out.append({"label": func(): return game.name_of("perks", perk_id), "modifiers": p.modifiers})
	return out


static func monthly_xp(game: Game, c: Dictionary) -> float:
	var l: Variant = current(game, c)
	if l == null:
		return 0.0
	var base := game.def_num("lifestyle.base_xp", 20) + Stats.skill(game, c, str(l.get("skill"))) * game.def_num("lifestyle.xp_per_skill", 2)
	# secondary_skill — второй навык пути (учёность для колдовства) даёт долю опыта
	if l.get("secondary_skill") != null:
		base += Stats.skill(game, c, str(l.secondary_skill)) * game.def_num("lifestyle.xp_per_skill", 2) * Data.num(l.get("secondary_share"), 0.5)
	# xp_mult образа жизни: трудные пути (колдовство) постигаются дольше
	return maxf(0.0, base * (1.0 + Stats.stat(game, c, "lifestyle_xp_mult")) * Data.num(l.get("xp_mult"), 1.0))


## ИИ (и стартовый выбор для всех): фокус по навыкам и образованию.
static func ai_choose_focus(game: Game, c: Dictionary) -> Variant:
	var edu: Variant = null
	for t in c.traits:
		var td: Variant = Chars.trait_def(game, t)
		if td != null and td.get("education") is Dictionary:
			edu = td.education.get("skill")
			break
	var opts := []
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
	for l in all(game):
		if not Interp.eval_trigger(ctx, ctx.root, l.get("is_shown")):
			continue
		var base := maxf(1.0, Stats.skill(game, c, str(l.get("skill")))) + (10.0 if edu == l.get("skill") else 0.0)
		for f in focuses_of(game, l.id):
			if not Interp.eval_trigger(ctx, ctx.root, f.get("is_shown")):
				continue
			var w := base * maxf(0.0, Interp.eval_value(ctx, ctx.root, f.ai_will_do) if f.get("ai_will_do") != null else 1.0)
			if w > 0.0:
				opts.append({"id": f.id, "w": w})
	var pick: Variant = game.rng.weighted(opts, func(o): return o.w)
	return pick.id if pick != null else null


static func ai_choose_perk(game: Game, c: Dictionary, lifestyle: String) -> Variant:
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
	var opts := []
	for p in available_perks(game, c, lifestyle):
		var w := maxf(0.0, Interp.eval_value(ctx, ctx.root, p.ai_will_do) if p.get("ai_will_do") != null else 10.0)
		if w > 0.0:
			opts.append({"id": p.id, "w": w})
	var pick: Variant = game.rng.weighted(opts, func(o): return o.w)
	return pick.id if pick != null else null


## Помесячно для персонажа (в его день): выбор фокуса, опыт, перки ИИ.
static func monthly_char(game: Game, c: Dictionary) -> void:
	if not Chars.is_adult(game, c) or c.get("prison") != null:
		return
	var st := state_of(c)
	if st.focus == null or not game.content.has("focuses", st.focus):
		set_focus(game, c, ai_choose_focus(game, c), true)
		if st.focus == null:
			return
	var l: Variant = current(game, c)
	if l == null:
		return
	if available_perks(game, c, l.id).is_empty():
		return # всё изучено
	st.xp[l.id] = xp_of(c, l.id) + monthly_xp(game, c)
	if st.xp[l.id] < perk_cost(game, c, l.id):
		return
	if game.is_player(c.id):
		if not c.flags.has("tmp:perk_notified"):
			c.flags["tmp:perk_notified"] = game.date + 3650
			game.message(game.loc.t("msg.perk_available", {"lifestyle": game.name_of("lifestyles", l.id)}), "good")
	else:
		var pick: Variant = ai_choose_perk(game, c, l.id)
		if pick != null:
			unlock_perk(game, c, pick)


## Все персонажи сразу (для скриптов и тестов).
static func monthly(game: Game) -> void:
	for c in game.living().duplicate():
		if c.death == null:
			monthly_char(game, c)


func install(engine: GameEngine) -> void:
	engine.systems.register("lifestyles", {"id": "lifestyles", "order": 25, "on_character_month": Lifestyles.monthly_char}, OWNER)
	engine.modifier_providers.register("lifestyle", {"fn": func(game: Game, c: Dictionary) -> Variant:
		var st: Variant = c.get("lifestyle")
		if st == null:
			return null
		return game.cached_monthly("lifestyle:" + c.id, func(): return Lifestyles._modifiers(game, c, st))
	}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	var names := func(ctx: ScriptContext, type: String, arg: Variant) -> String:
		return " / ".join(Data.as_array(arg).map(func(p): return ctx.game.name_of(type, str(p))))
	r.triggers.register("has_perk", {"scopes": CH, "doc": "Открыт перк",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			return c != null and Data.as_array(arg).any(func(p): return Lifestyles.has_perk(c, str(p))),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_perk", {"value": names.call(ctx, "perks", arg)}),
	}, OWNER)
	r.triggers.register("has_focus", {"scopes": CH, "doc": "Выбран фокус образа жизни",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			return c != null and c.get("lifestyle") != null and Data.as_array(arg).has(c.lifestyle.focus),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_focus", {"value": names.call(ctx, "focuses", arg)}),
	}, OWNER)
	r.triggers.register("has_lifestyle", {"scopes": CH, "doc": "Текущий фокус принадлежит образу жизни",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c == null:
				return false
			var l: Variant = Lifestyles.current(ctx.game, c)
			return l != null and Data.as_array(arg).has(l.id),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_lifestyle", {"value": names.call(ctx, "lifestyles", arg)}),
	}, OWNER)
	r.values.register("num_perks", {"scopes": CH, "doc": "Число открытых перков", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(c.lifestyle.perks.size()) if (c != null and c.get("lifestyle") != null) else 0.0
	}, OWNER)
	r.values.register("lifestyle_xp", {"scopes": CH, "doc": "Опыт текущего образа жизни", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		var l: Variant = Lifestyles.current(ctx.game, c) if c != null else null
		return Lifestyles.xp_of(c, l.id) if l != null else 0.0
	}, OWNER)
	r.effects.register("add_perk", {"scopes": CH, "doc": "Открыть перк бесплатно",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				Lifestyles.unlock_perk(ctx.game, c, str(arg), true),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.add_perk", {"value": ctx.game.name_of("perks", str(arg))}),
	}, OWNER)
	r.effects.register("remove_perk", {"scopes": CH, "doc": "Убрать перк",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c == null:
				return
			if c.get("lifestyle") != null:
				c.lifestyle.perks = c.lifestyle.perks.filter(func(p): return p != str(arg))
			ctx.game.month_cache.erase("lifestyle:" + c.id)
			ctx.game.stat_cache.erase(c.id),
	}, OWNER)
	r.effects.register("set_focus", {"scopes": CH, "doc": "Сменить фокус образа жизни (без перерыва)",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				Lifestyles.set_focus(ctx.game, c, str(arg), true),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.set_focus", {"value": ctx.game.name_of("focuses", str(arg))}),
	}, OWNER)
	var xp_args := func(ctx: ScriptContext, c: Variant, arg: Variant) -> Array:
		if arg is Dictionary and arg.has("lifestyle"):
			return [str(arg.lifestyle), arg.get("value")]
		var l: Variant = Lifestyles.current(ctx.game, c) if c != null else null
		return [l.id if l != null else null, arg]
	r.effects.register("add_lifestyle_xp", {"scopes": CH, "doc": "Опыт образа жизни: число (текущий образ жизни) или { lifestyle, value }",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c == null:
				return
			var a: Array = xp_args.call(ctx, c, arg)
			if a[0] == null:
				return
			var st := Lifestyles.state_of(c)
			st.xp[a[0]] = maxf(0.0, Lifestyles.xp_of(c, a[0]) + Interp.eval_value(ctx, s, a[1])),
		"describe": func(ctx, s, arg):
			var a: Array = xp_args.call(ctx, ch.call(ctx, s), arg)
			var v := roundi(Interp.eval_value(ctx, s, a[1]))
			return ctx.game.loc.t("fx.add_lifestyle_xp", {"value": ("+%d" % v) if v > 0 else str(v), "lifestyle": ctx.game.name_of("lifestyles", a[0]) if a[0] != null else ""}),
	}, OWNER)

	engine.content_validators.register("lifestyles", func(e: GameEngine, v: ScriptValidator):
		for l in e.content.all("lifestyles"):
			if not e.content.has("skills", l.get("skill")):
				v.issue("lifestyles/%s: нет навыка \"%s\"" % [l.id, l.get("skill")])
			v.trigger(l.get("is_shown"), "lifestyles/%s is_shown" % l.id)
		for f in e.content.all("focuses"):
			v.ref("lifestyles", f.get("lifestyle"), "focuses/" + f.id)
			v.trigger(f.get("is_shown"), "focuses/%s is_shown" % f.id)
		for p in e.content.all("perks"):
			v.ref("lifestyles", p.get("lifestyle"), "perks/" + p.id)
			for req in Data.as_array(p.get("requires")):
				v.ref("perks", req, "perks/%s requires" % p.id)
			if p.get("trait") != null:
				v.ref("traits", p.trait, "perks/" + p.id)
			v.effect(p.get("effect"), "perks/%s effect" % p.id)
	, OWNER)

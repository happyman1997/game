class_name Laws
extends EngineFeature
## Законы державы (realm laws) — например, власть короны. Закон состоит в
## группе (law_groups), в группе законы упорядочены по level. Закон даёт
## правителю модификаторы (налоги и войска с вассалов, мнение вассалов) и
## открывает права, которые данные проверяют триггерами (has_realm_law,
## <группа>_level). Смена закона стоит престижа и возможна раз в несколько лет.
##
## Данные:
##   law_groups: { icon, default, is_shown, cooldown_years, order }
##   realm_laws: { group, level, icon, modifiers, can_change, change_cost, on_change, ai_will_do }
## Состояние: c.laws = { группа: закон }.

const OWNER := "core/laws"


func _init() -> void:
	id = "laws"
	doc = "Законы державы: власть короны и другие группы законов"


static func groups(game: Game) -> Array:
	return game.engine.sorted_content("law_groups")


static func laws_of_group(game: Game, group: String) -> Array:
	var key := "laws:group:" + group
	var hit: Variant = game.engine.cache.get(key)
	if hit == null:
		hit = game.content.all("realm_laws").filter(func(x): return x.get("group") == group)
		Data.sort_by(hit, func(x): return Data.num(x.get("level")))
		game.engine.cache[key] = hit
	return hit


static func is_group_shown(game: Game, c: Dictionary, g: Dictionary) -> bool:
	if c.titles.is_empty():
		return false
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
	return Interp.eval_trigger(ctx, ctx.root, g.get("is_shown"))


## Действующий закон группы (у безземельных — нет).
static func current(game: Game, c: Dictionary, group: String) -> Variant:
	var gd: Variant = game.content.get_def("law_groups", group)
	if gd == null or c.titles.is_empty():
		return null
	var lid: Variant = c.laws.get(group) if c.get("laws") != null else null
	var law: Variant = game.content.get_def("realm_laws", lid if lid != null else gd.get("default"))
	return law if law != null else game.content.get_def("realm_laws", gd.get("default"))


static func change_cost(game: Game, c: Dictionary, law: Dictionary) -> Dictionary:
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id}, {"law_owner": {"type": "character", "id": c.id}})
	var cd: Dictionary = law.get("change_cost") if law.get("change_cost") is Dictionary else {}
	# law_cost_mult — например, у архетипа «Реформатор»
	var k := maxf(0.1, 1.0 + Stats.stat(game, c, "law_cost_mult"))
	return {
		"gold": roundf(Interp.eval_value(ctx, ctx.root, cd.get("gold", 0)) * k),
		"prestige": roundf(Interp.eval_value(ctx, ctx.root, cd.get("prestige", 0)) * k),
		"piety": roundf(Interp.eval_value(ctx, ctx.root, cd.get("piety", 0)) * k),
	}


static func change_blockers(game: Game, c: Dictionary, law: Dictionary) -> Array:
	var gd: Variant = game.content.get_def("law_groups", law.get("group"))
	if gd == null:
		return ["?"]
	var out := []
	var cur: Variant = current(game, c, law.group)
	if cur != null and cur.id == law.id:
		out.append(game.loc.t("ui.law_current"))
	# законы меняются на одну ступень за раз
	if cur != null and absf(Data.num(cur.get("level")) - Data.num(law.get("level"))) > 1:
		out.append(game.loc.t("ui.law_one_step"))
	var cdv: Variant = c.flags.get("law_cd:" + str(law.group))
	if cdv != null and cdv > game.date:
		out.append(game.loc.t("ui.on_cooldown", {"days": int(cdv) - game.date}))
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
	out.append_array(Interp.failed_triggers(ctx, ctx.root, law.get("can_change")))
	out.append_array(Economy.cost_blockers(game, c, change_cost(game, c, law)))
	return out


static func change(game: Game, c: Dictionary, law_id: String, free: bool = false) -> bool:
	var law: Variant = game.content.get_def("realm_laws", law_id)
	if law == null:
		return false
	if not free and not change_blockers(game, c, law).is_empty():
		return false
	var gd: Dictionary = game.content.get_def("law_groups", law.group)
	if not free:
		var cst := change_cost(game, c, law)
		c.gold -= cst.gold
		c.prestige -= cst.prestige
		c.piety -= cst.piety
		c.flags["law_cd:" + str(law.group)] = game.date + roundi(Data.num(gd.get("cooldown_years"), 5) * 365)
	var prev: Variant = current(game, c, law.group)
	if c.get("laws") == null:
		c["laws"] = {}
	c.laws[law.group] = law.id
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
	Interp.run_effect(ctx, ctx.root, law.get("on_change"))
	game.stat_cache.clear()
	game.emit("law.changed", {"character": c, "law": law.id, "previous": prev.id if prev != null else null})
	if game.is_player(c.id) or game.vassals_of(c.id).any(func(v): return game.is_player(v.id)):
		game.message(game.loc.t("msg.law_changed", {"who": game.scope_name({"type": "character", "id": c.id}), "law": game.name_of("realm_laws", law.id)}), "info", {"type": "character", "id": c.id})
	return true


static func yearly_ai(game: Game) -> void:
	for c in game.rulers().duplicate():
		if game.is_player(c.id) or c.get("prison") != null or c.death != null:
			continue
		for gd in groups(game):
			if not is_group_shown(game, c, gd):
				continue
			var cur: Variant = current(game, c, gd.id)
			var opts := laws_of_group(game, gd.id).filter(func(l): return (cur == null or l.id != cur.id) and change_blockers(game, c, l).is_empty())
			if opts.is_empty():
				continue
			var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
			var best: Variant = null
			var bv := 0.0
			for l in opts:
				var v := Interp.eval_value(ctx, ctx.root, l.ai_will_do) if l.get("ai_will_do") != null else 0.0
				if v > 0 and (best == null or v > bv):
					best = l
					bv = v
			if best != null and game.rng.next() * 100.0 < bv:
				change(game, c, best.id)


func install(engine: GameEngine) -> void:
	engine.systems.register("laws", {"id": "laws", "order": 85, "on_year": Laws.yearly_ai}, OWNER)
	engine.modifier_providers.register("realm_laws", {"fn": func(game: Game, c: Dictionary) -> Variant:
		if c.titles.is_empty():
			return null
		var out := []
		for gd in Laws.groups(game):
			if not Laws.is_group_shown(game, c, gd):
				continue
			var l: Variant = Laws.current(game, c, gd.id)
			if l != null and l.get("modifiers") is Dictionary:
				var lid: String = l.id
				out.append({"label": func(): return game.name_of("realm_laws", lid), "modifiers": l.modifiers})
		return out
	}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	r.triggers.register("has_realm_law", {"scopes": CH, "doc": "Действует закон державы",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var law: Variant = ctx.game.content.get_def("realm_laws", str(arg))
			if c == null or law == null:
				return false
			var cur: Variant = Laws.current(ctx.game, c, law.group)
			return cur != null and cur.id == law.id,
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_realm_law", {"value": ctx.game.name_of("realm_laws", str(arg))}),
	}, OWNER)
	for gd in engine.content.all("law_groups"):
		var gid: String = gd.id
		r.values.register(gid + "_level", {"scopes": CH, "doc": "Уровень закона группы %s (−1, если не действует)" % gid, "get": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			var l: Variant = Laws.current(ctx.game, c, gid) if c != null else null
			return Data.num(l.get("level")) if l != null else -1.0
		}, OWNER)
	r.effects.register("set_realm_law", {"scopes": CH, "doc": "Установить закон державы (без цены и перерыва)",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				Laws.change(ctx.game, c, str(arg), true),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.set_realm_law", {"value": ctx.game.name_of("realm_laws", str(arg))}),
	}, OWNER)
	r.effects.register("shift_realm_law", {"scopes": CH, "doc": "Сдвинуть закон группы на ступени: shift_realm_law: { group: crown_authority, by: -1 } (без цены)",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c == null or not (arg is Dictionary):
				return
			var gid := str(arg.get("group"))
			var cur: Variant = Laws.current(ctx.game, c, gid)
			if cur == null:
				return
			var list := Laws.laws_of_group(ctx.game, gid)
			var i := list.find(cur)
			var j := clampi(i + int(Interp.eval_value(ctx, s, arg.get("by", -1))), 0, list.size() - 1)
			if j != i:
				Laws.change(ctx.game, c, list[j].id, true),
		"describe": func(ctx, s, arg):
			if not (arg is Dictionary):
				return null
			var by := int(Interp.eval_value(ctx, s, arg.get("by", -1)))
			return ctx.game.loc.t("fx.shift_realm_law_down" if by < 0 else "fx.shift_realm_law_up", {"value": ctx.game.name_of("law_groups", str(arg.get("group")))}),
	}, OWNER)
	engine.content_validators.register("laws", func(e: GameEngine, v: ScriptValidator):
		for gd in e.content.all("law_groups"):
			v.ref("realm_laws", gd.get("default"), "law_groups/%s default" % gd.id)
			v.trigger(gd.get("is_shown"), "law_groups/%s is_shown" % gd.id)
		for l in e.content.all("realm_laws"):
			v.ref("law_groups", l.get("group"), "realm_laws/" + l.id)
			v.trigger(l.get("can_change"), "realm_laws/%s can_change" % l.id)
			v.effect(l.get("on_change"), "realm_laws/%s on_change" % l.id)
	, OWNER)

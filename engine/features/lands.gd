class_name Lands
extends EngineFeature
## Вера и культура земель. Графство чужой веры или культуры (по сравнению с
## его владельцем) платит меньше и даёт меньше войск, пока его не обратят:
##   defines.lands: { foreign_faith: {модификаторы графства},
##                    foreign_culture: {модификаторы графства} }
## Обращают задачи совета и решения из данных (эффекты convert_to_holder_faith,
## convert_to_holder_culture); после обращения графство — как родное.

const OWNER := "core/lands"


func _init() -> void:
	id = "lands"
	doc = "Вера и культура земель: чужие графства дают меньше, их можно обратить"


static func holder_of(game: Game, prov_id: String) -> Variant:
	var t: Variant = game.state.titles.get(prov_id)
	return game.ch(t.holder) if t != null and t.holder != null else null


static func foreign_faith(game: Game, prov_id: String) -> bool:
	var p: Variant = game.state.provinces.get(prov_id)
	var h: Variant = holder_of(game, prov_id)
	return p != null and h != null and p.faith != h.faith


static func foreign_culture(game: Game, prov_id: String) -> bool:
	var p: Variant = game.state.provinces.get(prov_id)
	var h: Variant = holder_of(game, prov_id)
	return p != null and h != null and p.culture != h.culture


## Чем графство чуждо владельцу: [{kind: "faith"|"culture", modifiers}].
static func strangeness(game: Game, prov_id: String) -> Array:
	var out := []
	if foreign_faith(game, prov_id):
		out.append({"kind": "faith", "modifiers": game.def_val("lands.foreign_faith", {})})
	if foreign_culture(game, prov_id):
		out.append({"kind": "culture", "modifiers": game.def_val("lands.foreign_culture", {})})
	return out


static func count_foreign(game: Game, c: Dictionary, kind: String) -> int:
	var n := 0
	for cty in Titles.domain_counties(game, c):
		var p: Variant = game.state.provinces.get(cty)
		if p != null and str(p.get(kind)) != str(c.get(kind)):
			n += 1
	return n


## Обратить графство в веру (или культуру) владельца.
static func convert(game: Game, prov_id: String, kind: String) -> bool:
	var p: Variant = game.state.provinces.get(prov_id)
	var h: Variant = holder_of(game, prov_id)
	if p == null or h == null or p.get(kind) == h.get(kind):
		return false
	var before: String = str(p.get(kind))
	p[kind] = h.get(kind)
	game.stat_cache.erase("prov:" + prov_id)
	game.emit("lands.converted", {"province": prov_id, "kind": kind, "from": before, "to": p[kind], "holder": h})
	if game.is_player(h.id):
		game.message(game.loc.t("msg.converted_" + kind, {"place": game.name_of("provinces", prov_id),
			"value": game.name_of("faiths" if kind == "faith" else "cultures", p[kind])}), "good", {"type": "province", "id": prov_id})
	game.notify("map")
	return true


func install(engine: GameEngine) -> void:
	engine.province_modifier_providers.register("lands", {"fn": func(game: Game, prov_id: String) -> Variant:
		var out := {}
		for part in Lands.strangeness(game, prov_id):
			Stats.add_into(out, part.modifiers)
		return out if not out.is_empty() else null
	}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	const PR := ["province"]
	const CH := ["character"]
	r.triggers.register("has_holder_faith", {"scopes": PR, "doc": "Графство одной веры с владельцем", "eval": func(ctx, s, arg):
		return (not Lands.foreign_faith(ctx.game, s.id)) == ScriptContext.is_yes(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_holder_faith" if ScriptContext.is_yes(arg) else "tr.not_holder_faith"),
	}, OWNER)
	r.triggers.register("has_holder_culture", {"scopes": PR, "doc": "Графство одной культуры с владельцем", "eval": func(ctx, s, arg):
		return (not Lands.foreign_culture(ctx.game, s.id)) == ScriptContext.is_yes(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_holder_culture" if ScriptContext.is_yes(arg) else "tr.not_holder_culture"),
	}, OWNER)
	r.values.register("num_foreign_faith_counties", {"scopes": CH, "doc": "Графств домена чужой веры", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return float(Lands.count_foreign(ctx.game, c, "faith")) if c != null else 0.0
	}, OWNER)
	r.values.register("num_foreign_culture_counties", {"scopes": CH, "doc": "Графств домена чужой культуры", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return float(Lands.count_foreign(ctx.game, c, "culture")) if c != null else 0.0
	}, OWNER)
	r.effects.register("convert_to_holder_faith", {"scopes": PR, "doc": "Обратить графство в веру владельца", "apply": func(ctx, s, _arg):
		Lands.convert(ctx.game, s.id, "faith"),
		"describe": func(ctx, s, _arg): return ctx.game.loc.t("fx.convert_to_holder_faith", {"place": ctx.game.scope_name(s)}),
	}, OWNER)
	r.effects.register("convert_to_holder_culture", {"scopes": PR, "doc": "Привить графству культуру владельца", "apply": func(ctx, s, _arg):
		Lands.convert(ctx.game, s.id, "culture"),
		"describe": func(ctx, s, _arg): return ctx.game.loc.t("fx.convert_to_holder_culture", {"place": ctx.game.scope_name(s)}),
	}, OWNER)

class_name Artifacts
extends EngineFeature
## Реликвии: единственные в мире предметы (венец, меч, печать). Реликвию
## держит один персонаж; её модификаторы действуют на владельца. После смерти
## владельца реликвия переходит к основному наследнику, а без наследника —
## теряется (её можно найти снова).
##   artifacts: { <id>: {
##     icon, modifiers: {...},
##     inherit: no         — не переходит по наследству, а теряется;
##     contested: yes      — за неё воюют: владелец — цель повода с
##                           targets: artifact_holder (условие повода —
##                           realm_has_artifact) } }
## Состояние: state.artifacts = { <id>: id владельца | null (утеряна) }.
## Хуки: artifact.gained — {artifact, character, from}; artifact.lost —
## {artifact, character}.

const OWNER := "core/artifacts"


func _init() -> void:
	id = "artifacts"
	doc = "Реликвии: уникальные предметы, переходят по наследству и добываются войной"


static func _state(game: Game) -> Dictionary:
	if not (game.state.get("artifacts") is Dictionary):
		game.state["artifacts"] = {}
	return game.state.artifacts


## Владелец реликвии (персонаж) или null.
static func holder_of(game: Game, aid: String) -> Variant:
	var h: Variant = _state(game).get(aid)
	return game.ch(h) if h != null else null


## Реликвии персонажа (id).
static func held_by(game: Game, c: Dictionary) -> Array:
	var out := []
	var st := _state(game)
	for aid in st:
		if st[aid] == c.id:
			out.append(aid)
	return out


## Реликвия у кого-то в державе персонажа (у него, его вассалов или двора).
static func in_realm_of(game: Game, c: Dictionary, aid: String) -> bool:
	var h: Variant = holder_of(game, aid)
	return h != null and Titles.top_liege(game, h).id == c.id


static func give(game: Game, aid: String, c: Dictionary) -> void:
	if not game.content.has("artifacts", aid) or c.death != null:
		return
	var st := _state(game)
	var prev: Variant = st.get(aid)
	if prev == c.id:
		return
	st[aid] = c.id
	game.stat_cache.erase(c.id)
	if prev != null:
		game.stat_cache.erase(prev)
	game.mark_chars_dirty([c.id, prev])
	var name := game.name_of("artifacts", aid)
	if game.is_player(c.id):
		game.message(game.loc.t("msg.artifact_gained", {"value": name}), "good", {"type": "character", "id": c.id}, [c.id])
	elif prev != null and game.is_player(prev):
		game.message(game.loc.t("msg.artifact_taken", {"who": game.scope_name({"type": "character", "id": c.id}), "value": name}), "bad",
			{"type": "character", "id": c.id}, [c.id, prev])
	game.emit("artifact.gained", {"artifact": aid, "character": c, "from": prev})


static func lose(game: Game, aid: String) -> void:
	var st := _state(game)
	var prev: Variant = st.get(aid)
	if prev == null:
		return
	st[aid] = null
	game.stat_cache.erase(prev)
	game.mark_chars_dirty([prev])
	if game.is_player(prev):
		game.message(game.loc.t("msg.artifact_lost", {"value": game.name_of("artifacts", aid)}), "bad", null, [prev])
	game.emit("artifact.lost", {"artifact": aid, "character": game.ch(prev)})


func install(engine: GameEngine) -> void:
	engine.modifier_providers.register("artifacts", {"fn": func(game: Game, c: Dictionary) -> Variant:
		var st: Variant = game.state.get("artifacts")
		if not (st is Dictionary) or st.is_empty():
			return null
		var out := []
		for aid in st:
			if st[aid] != c.id:
				continue
			var d: Variant = game.content.get_def("artifacts", aid)
			if d != null and d.get("modifiers") is Dictionary:
				var a: String = aid
				out.append({"label": func(): return game.name_of("artifacts", a), "modifiers": d.modifiers})
		return out if not out.is_empty() else null
	}, OWNER)
	# по наследству — основному наследнику; без него реликвия теряется
	engine.hooks.on("character.death", func(p):
		var game: Game = p.game
		var c: Dictionary = p.character
		for aid in Artifacts.held_by(game, c):
			var d: Variant = game.content.get_def("artifacts", aid)
			var heir: Variant = game.ch(p.get("heir")) if p.get("heir") != null else null
			if heir == null or heir.death != null:
				heir = Succession.primary_heir(game, c)
			if d != null and d.get("inherit", true) != false and heir != null and heir.death == null:
				Artifacts.give(game, aid, heir)
			else:
				Artifacts.lose(game, aid)
	, 0, OWNER)
	# цель войны: держава, где хранится спорная реликвия
	engine.cb_targets.register("artifact_holder", {"targets": func(game: Game, attacker: Dictionary) -> Array:
		var out := []
		var seen := {}
		var st: Variant = game.state.get("artifacts")
		if not (st is Dictionary):
			return out
		for aid in st:
			var d: Variant = game.content.get_def("artifacts", aid)
			if d == null or not d.get("contested", false):
				continue
			var h: Variant = Artifacts.holder_of(game, aid)
			if h == null:
				continue
			var top: Dictionary = Titles.top_liege(game, h)
			if top.id == attacker.id or top.titles.is_empty() or seen.has(top.id):
				continue
			seen[top.id] = true
			out.append({"defender": top.id, "title": top.titles[0], "counties": Titles.domain_counties(game, top)})
		return out
	}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	const CH := ["character"]
	r.triggers.register("has_artifact", {"scopes": CH, "doc": "Персонаж держит реликвию: has_artifact: <id>", "eval": func(ctx, s, arg):
		var h: Variant = Artifacts._state(ctx.game).get(str(arg))
		return h != null and h == s.id,
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_artifact", {"value": ctx.game.name_of("artifacts", str(arg))}),
	}, OWNER)
	r.triggers.register("realm_has_artifact", {"scopes": CH, "doc": "Реликвия хранится в державе персонажа (у него, вассалов или двора)", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		return c != null and Artifacts.in_realm_of(ctx.game, c, str(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.realm_has_artifact", {"value": ctx.game.name_of("artifacts", str(arg))}),
	}, OWNER)
	r.triggers.register("artifact_is_held", {"doc": "Реликвия у кого-то есть (не утеряна): artifact_is_held: <id>", "eval": func(ctx, _s, arg):
		return Artifacts._state(ctx.game).get(str(arg)) != null,
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.artifact_is_held", {"value": ctx.game.name_of("artifacts", str(arg))}),
	}, OWNER)
	r.values.register("num_artifacts", {"scopes": CH, "doc": "Число реликвий у персонажа", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return float(Artifacts.held_by(ctx.game, c).size()) if c != null else 0.0
	}, OWNER)
	r.effects.register("gain_artifact", {"scopes": CH, "doc": "Получить реликвию (у прежнего владельца она пропадает): gain_artifact: <id>", "apply": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c != null:
			Artifacts.give(ctx.game, str(arg), c),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.gain_artifact", {"who": ctx.game.scope_name(s), "value": ctx.game.name_of("artifacts", str(arg))}),
	}, OWNER)
	r.effects.register("lose_artifact", {"scopes": CH, "doc": "Утратить реликвию — она пропадает, и её можно найти снова: lose_artifact: <id>", "apply": func(ctx, s, arg):
		var h: Variant = Artifacts._state(ctx.game).get(str(arg))
		if h != null and h == s.id:
			Artifacts.lose(ctx.game, str(arg)),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.lose_artifact", {"who": ctx.game.scope_name(s), "value": ctx.game.name_of("artifacts", str(arg))}),
	}, OWNER)
	r.effects.register("seize_realm_artifacts", {"scopes": CH, "doc": "Забрать спорные реликвии из державы персонажа from: seize_realm_artifacts: scope:defender", "apply": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		var from: Variant = Interp.resolve_scope(ctx, s, arg)
		var fc: Variant = ctx.game.ch(from.id) if from != null else null
		if c == null or fc == null:
			return
		for aid in Artifacts._state(ctx.game).keys():
			var d: Variant = ctx.game.content.get_def("artifacts", aid)
			if d != null and d.get("contested", false) and Artifacts.in_realm_of(ctx.game, fc, aid):
				Artifacts.give(ctx.game, aid, c),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.seize_realm_artifacts", {"who": ctx.game.scope_name(s), "from": ctx.game.scope_name(Interp.resolve_scope(ctx, s, arg))}),
	}, OWNER)

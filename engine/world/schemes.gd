class_name Schemes
extends RefCounted
## Интриги (схемы): длительные действия против цели — убийство,
## соблазнение, дружба. Прогресс, шанс успеха и раскрытия задаются
## значениями в данных.


static func scheme_context(game: Game, s: Dictionary) -> ScriptContext:
	return ScriptContext.make(game, {"type": "character", "id": s.owner}, {
		"owner": {"type": "character", "id": s.owner},
		"actor": {"type": "character", "id": s.owner},
		"target": {"type": "character", "id": s.target},
		"recipient": {"type": "character", "id": s.target},
		"scheme": {"type": "scheme", "id": s.id},
	})


static func start_scheme(game: Game, type: String, owner: Dictionary, target: Dictionary) -> Variant:
	var def: Variant = game.content.get_def("schemes", type)
	if def == null:
		game.script_error("Нет интриги \"%s\"" % type)
		return null
	for s in game.state.schemes.values():
		if s.owner == owner.id and s.type == type and s.target == target.id:
			return null
	var s = {"id": game.new_id("sch"), "type": type, "owner": owner.id, "target": target.id, "progress": 0.0, "start": game.date, "discovered": false}
	var ctx := scheme_context(game, s)
	if not Interp.eval_trigger(ctx, ctx.root, def.get("is_valid")):
		return null
	game.state.schemes[s.id] = s
	game.emit("scheme.started", {"scheme": s})
	return s


static func success_chance(game: Game, s: Dictionary) -> int:
	var def: Variant = game.content.get_def("schemes", s.type)
	if def == null:
		return 0
	var ctx := scheme_context(game, s)
	return clampi(roundi(Interp.eval_value(ctx, ctx.root, def.get("success_chance"))), 0, int(game.def_num("schemes.max_success", 95)))


static func monthly_progress(game: Game, s: Dictionary) -> float:
	var def: Variant = game.content.get_def("schemes", s.type)
	if def == null:
		return 0.0
	var ctx := scheme_context(game, s)
	return maxf(1.0, Interp.eval_value(ctx, ctx.root, def.get("progress")))


static func end_scheme(game: Game, id: String) -> void:
	game.state.schemes.erase(id)


static func monthly_schemes(game: Game) -> void:
	for s in game.state.schemes.values():
		if not game.state.schemes.has(s.id):
			continue
		var def: Variant = game.content.get_def("schemes", s.type)
		var owner: Variant = game.ch(s.owner)
		var target: Variant = game.ch(s.target)
		if def == null or not Chars.is_alive(owner) or not Chars.is_alive(target):
			end_scheme(game, s.id)
			continue
		var ctx := scheme_context(game, s)
		if not Interp.eval_trigger(ctx, ctx.root, def.get("is_valid")):
			end_scheme(game, s.id)
			continue
		if owner.get("prison") != null:
			continue # в темнице интриги стоят
		s.progress = float(s.progress) + monthly_progress(game, s)
		if not s.discovered and def.get("discovery_chance") != null and game.rng.next() * 100.0 < Interp.eval_value(ctx, ctx.root, def.discovery_chance):
			s.discovered = true
			Interp.run_effect(ctx, ctx.root, def.get("on_discovered"))
			game.emit("scheme.discovered", {"scheme": s})
		if s.progress >= 100.0:
			var chance := success_chance(game, s)
			var success := game.rng.next() * 100.0 < chance
			end_scheme(game, s.id)
			Interp.run_effect(ctx, ctx.root, def.get("on_success") if success else def.get("on_failure"))
			game.emit("scheme.ended", {"scheme": s, "success": success})

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


## Интрига раскрыта: её on_discovered, сигнал scheme.discovered и для враждебной
## (category: hostile) — on_action on_scheme_discovered у цели (root — цель,
## scope:plotter — заговорщик, scope:scheme).
## scapegoat у заговорщика (архетип «Серый кардинал») — «чужими руками»:
## подозрение падает на случайного придворного, последствия — на него.
static func mark_discovered(game: Game, s: Dictionary) -> void:
	s.discovered = true
	var def: Variant = game.content.get_def("schemes", s.type)
	var blamed := s
	var owner: Variant = game.ch(s.owner)
	if owner != null and Stats.stat(game, owner, "scapegoat") > 0.0:
		var pool := game.courtiers_of(owner.id).filter(func(x): return Chars.is_alive(x) and Chars.is_adult(game, x) and x.id != s.target and not owner.spouses.has(x.id) and not owner.children.has(x.id))
		var goat: Variant = game.rng.pick(pool)
		if goat != null:
			blamed = s.duplicate()
			blamed.owner = goat.id
			if game.is_player(owner.id):
				game.message(game.loc.t("msg.scapegoat", {"who": game.scope_name({"type": "character", "id": goat.id})}), "good", {"type": "character", "id": goat.id})
	var ctx := scheme_context(game, blamed)
	Interp.run_effect(ctx, ctx.root, def.get("on_discovered") if def != null else null)
	game.emit("scheme.discovered", {"scheme": s, "blamed": blamed.owner})
	if def != null and def.get("category") == "hostile" and game.is_alive(s.target) and game.is_alive(blamed.owner):
		game.on_action("on_scheme_discovered", {"type": "character", "id": s.target},
			{"plotter": {"type": "character", "id": blamed.owner}, "scheme": {"type": "scheme", "id": s.id}})


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
			mark_discovered(game, s)
		if s.progress >= 100.0:
			var chance := success_chance(game, s)
			var success := game.rng.next() * 100.0 < chance
			end_scheme(game, s.id)
			Interp.run_effect(ctx, ctx.root, def.get("on_success") if success else def.get("on_failure"))
			game.emit("scheme.ended", {"scheme": s, "success": success})

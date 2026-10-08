class_name GameEvents
extends RefCounted
## Исполнение событий из данных. Событие адресовано персонажу (root).
## Для игрока событие ставится в очередь и показывается окном; ИИ выбирает
## вариант по весам ai_chance.

var game: Game


func _init(g: Game) -> void:
	game = g


func def(id: String) -> Variant:
	return game.content.get_def("events", id)


## Запустить событие сейчас или через delay_days.
func trigger(id: String, target: Dictionary, scopes: Dictionary = {}, delay_days: int = 0) -> void:
	if delay_days > 0:
		game.state.scheduled.append({"date": game.date + delay_days, "event": id, "target": target, "scopes": scopes.duplicate()})
		return
	fire(id, target, scopes)


func can_fire(d: Dictionary, target: Dictionary, ctx: ScriptContext) -> bool:
	if target.type == "character":
		var c: Variant = game.ch(target.id)
		if c == null or c.death != null:
			return false
		var until: Variant = c.flags.get("ev:" + str(d.id))
		if until != null and (until == 0 or until > game.date):
			return false
	return Interp.eval_trigger(ctx, target, d.get("trigger"))


## Возвращает true, если событие сработало.
func fire(id: String, target: Dictionary, scopes: Dictionary = {}, force: bool = false) -> bool:
	var d: Variant = def(id)
	if d == null:
		game.script_error("Нет события \"%s\"" % id)
		return false
	var ctx := ScriptContext.make(game, target, scopes)
	if not force and not can_fire(d, target, ctx):
		return false
	if not game.engine.hooks.veto("event.before_fire", {"game": game, "event": id, "target": target, "scopes": scopes}):
		return false
	if target.type == "character":
		var c: Dictionary = game.ch(target.id)
		if d.get("once", false):
			c.flags["ev:" + id] = 0
		elif d.get("cooldown") != null:
			c.flags["ev:" + id] = game.date + GameDate.duration_days(d.cooldown)
	Interp.run_effect(ctx, target, d.get("immediate"))
	var opts := visible_options(d, ctx, target)
	if d.get("hidden", false) or Data.as_array(d.get("options")).is_empty():
		Interp.run_effect(ctx, target, d.get("after"))
		game.emit("event.fired", {"event": id, "target": target})
		return true
	if target.type == "character" and game.is_player(target.id):
		var pe := {"uid": game.new_id("ev"), "event": id, "target": target, "scopes": ctx.scopes.duplicate()}
		game.state.pending_events.append(pe)
		game.emit("event.player", {"pending": pe})
		game.notify("event")
		return true
	# ИИ
	var pick: Variant = game.rng.weighted(opts, func(o): return maxf(0.0, Interp.eval_value(ctx, target, o.opt.get("ai_chance", 1))))
	var chosen: Variant = pick if pick != null else (opts[0] if not opts.is_empty() else null)
	if chosen != null:
		Interp.run_effect(ctx, target, chosen.opt.get("effect"))
	Interp.run_effect(ctx, target, d.get("after"))
	game.emit("event.fired", {"event": id, "target": target, "option": chosen.index if chosen != null else null})
	return true


## [{opt, index}]
func visible_options(d: Dictionary, ctx: ScriptContext, target: Dictionary) -> Array:
	var out := []
	var options := Data.as_array(d.get("options"))
	for i in options.size():
		if Interp.eval_trigger(ctx, target, options[i].get("trigger")):
			out.append({"opt": options[i], "index": i})
	return out


func context_for(pe: Dictionary) -> ScriptContext:
	return ScriptContext.make(game, pe.target, pe.scopes)


## Игрок выбрал вариант события.
func choose(uid: String, option_index: int) -> void:
	var i := -1
	for k in game.state.pending_events.size():
		if game.state.pending_events[k].uid == uid:
			i = k
			break
	if i < 0:
		return
	var pe: Dictionary = game.state.pending_events[i]
	game.state.pending_events.remove_at(i)
	var d: Variant = def(pe.event)
	if d == null:
		return
	var ctx := context_for(pe)
	if not game.exists(pe.target):
		return
	var options := Data.as_array(d.get("options"))
	if option_index >= 0 and option_index < options.size():
		Interp.run_effect(ctx, pe.target, options[option_index].get("effect"))
	Interp.run_effect(ctx, pe.target, d.get("after"))
	game.emit("event.fired", {"event": pe.event, "target": pe.target, "option": option_index})
	game.notify("event")


## Ежедневно: отложенные события.
func process_scheduled() -> void:
	var due := []
	var rest := []
	for s in game.state.scheduled:
		if s.date <= game.date:
			due.append(s)
		else:
			rest.append(s)
	if due.is_empty():
		return
	game.state.scheduled = rest
	for s in due:
		fire(s.event, s.target, s.scopes)


## Выполнить on_action из данных: эффект, обязательные события и случайное событие.
func run_on_action(id: String, root: Dictionary, scopes: Dictionary) -> void:
	var d: Variant = game.content.get_def("on_actions", id)
	if d == null:
		return
	if root.type == "character" and id != "on_death":
		var c: Variant = game.ch(root.id)
		if c != null and c.death != null:
			return
	var ctx := ScriptContext.make(game, root, scopes)
	Interp.run_effect(ctx, root, d.get("effect"))
	for ev in Data.as_array(d.get("events")):
		fire(str(ev), root, ctx.scopes)
	var re: Variant = d.get("random_events")
	if not (re is Dictionary):
		return
	var chance = 100.0 if re.get("chance") == null else Interp.eval_value(ctx, root, re.chance)
	if game.rng.next() * 100.0 >= chance:
		return
	var entries := []
	var evs: Variant = re.get("events")
	if evs is Array:
		for e in evs:
			entries.append({"event": str(e.get("event")), "weight": e.get("weight", 1)})
	elif evs is Dictionary:
		for ev in evs:
			entries.append({"event": str(ev), "weight": evs[ev]})
	var candidates := []
	for e in entries:
		var ed: Variant = def(e.event)
		if ed == null:
			game.script_error("on_action %s: нет события \"%s\"" % [id, e.event])
			continue
		var ev_ctx := ScriptContext.make(game, root, ctx.scopes)
		if not can_fire(ed, root, ev_ctx):
			continue
		var w = Interp.eval_value(ev_ctx, root, e.weight) * (Interp.eval_value(ev_ctx, root, ed.weight) if ed.get("weight") != null else 1.0)
		if w > 0.0:
			candidates.append({"event": e.event, "w": w})
	var pick: Variant = game.rng.weighted(candidates, func(c): return c.w)
	if pick != null:
		fire(pick.event, root, ctx.scopes)

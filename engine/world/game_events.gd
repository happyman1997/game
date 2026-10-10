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
		run_option(ctx, target, chosen.opt, id)
	Interp.run_effect(ctx, target, d.get("after"))
	game.emit("event.fired", {"event": id, "target": target, "option": chosen.index if chosen != null else null})
	return true


## [{opt, index, locked?}]. with_locked — показать и варианты-«голоса навыка»,
## до которых персонаж не дорос (окно игрока показывает их серыми).
func visible_options(d: Dictionary, ctx: ScriptContext, target: Dictionary, with_locked: bool = false) -> Array:
	var out := []
	var options := Data.as_array(d.get("options"))
	for i in options.size():
		if not Interp.eval_trigger(ctx, target, options[i].get("trigger")):
			continue
		var ok := skill_gate_ok(options[i], target)
		if ok or with_locked:
			out.append({"opt": options[i], "index": i, "locked": not ok})
	return out


# ------------------------------------------------------------ голоса навыков
# Вариант события может говорить голосом навыка:
#   skill: { skill: learning, min: 14 }       — доступен при навыке не ниже min;
#   skill: { archetype: arbiter }             — доступен архетипу (связке навыков);
#   skill: { skill: intrigue, check: 12 }     — проверка: шанс виден заранее,
#       после effect выполняется success или failure.
# Шанс проверки: events.check_base + (навык − сложность) × events.check_per_point,
# в пределах events.check_min…check_max.

static func skill_spec(opt: Dictionary) -> Variant:
	var s: Variant = opt.get("skill")
	return s if s is Dictionary else null


func skill_gate_ok(opt: Dictionary, target: Dictionary) -> bool:
	var sp: Variant = skill_spec(opt)
	if sp == null or target.type != "character":
		return true
	var c: Variant = game.ch(target.id)
	if c == null:
		return false
	if sp.get("archetype") != null and Stats.stat(game, c, "archetype:" + str(sp.archetype)) <= 0.0:
		return false
	if sp.get("min") != null and Stats.skill(game, c, str(sp.get("skill"))) < int(Data.num(sp.min)):
		return false
	return true


## Шанс проверки навыка в процентах (или -1, если вариант без проверки).
func check_chance(opt: Dictionary, target: Dictionary) -> int:
	var sp: Variant = skill_spec(opt)
	if sp == null or sp.get("check") == null or target.type != "character":
		return -1
	var c: Variant = game.ch(target.id)
	var sk := float(Stats.skill(game, c, str(sp.get("skill")))) if c != null else 0.0
	var v := game.def_num("events.check_base", 50) + (sk - Data.num(sp.check)) * game.def_num("events.check_per_point", 5)
	# стресс мешает: каждая сотня стресса — минус к шансу
	if c != null:
		v -= floorf(float(c.stress) / 100.0) * game.def_num("events.check_stress_penalty", 10)
	return clampi(roundi(v), int(game.def_num("events.check_min", 5)), int(game.def_num("events.check_max", 95)))


## Выполнить выбранный вариант: эффект и, если это проверка, успех или неудачу.
func run_option(ctx: ScriptContext, target: Dictionary, opt: Dictionary, event_id: String) -> void:
	ctx.values["__src"] = "event:" + event_id
	Interp.run_effect(ctx, target, opt.get("effect"))
	var chance := check_chance(opt, target)
	if chance < 0:
		return
	var success := game.rng.next() * 100.0 < chance
	ctx.values["check_success"] = 1.0 if success else 0.0
	Interp.run_effect(ctx, target, opt.get("success") if success else opt.get("failure"))
	game.emit("event.check", {"event": event_id, "character": target.id, "skill": str(skill_spec(opt).get("skill")), "chance": chance, "success": success})
	if game.is_player(target.id):
		game.message(game.loc.t("msg.check_success" if success else "msg.check_failure", {
			"skill": game.name_of("skills", str(skill_spec(opt).get("skill"))), "chance": chance}), "good" if success else "bad", target)


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
		run_option(ctx, pe.target, options[option_index], str(pe.event))
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

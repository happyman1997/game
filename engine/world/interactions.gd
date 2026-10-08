class_name Interactions
extends RefCounted
## Взаимодействия персонажей (брак, подарок, вассалитет, интриги...).
## Полностью описываются в данных: условия показа/доступности, цена,
## согласие ИИ (ai_accept со слагаемыми desc для подсказки), эффекты.
##
## Поставщик целей: {label?, options: Callable(game, actor, recipient) -> Array[{id, label, ref?}]}.
## Решающий: {decider: Callable(game, recipient, actor) -> Dictionary|null}.
## Аргументы (args): {secondary?: id, target?: скоуп, use_hook?: bool}.


static func context(game: Game, def: Dictionary, actor: Dictionary, recipient: Dictionary, args: Dictionary = {}) -> ScriptContext:
	var scopes := {
		"actor": {"type": "character", "id": actor.id},
		"recipient": {"type": "character", "id": recipient.id},
		"decider": {"type": "character", "id": decider_of(game, def, recipient).id},
	}
	if args.get("secondary") != null:
		scopes["secondary_actor"] = {"type": "character", "id": args.secondary}
	if args.get("target") != null:
		scopes["target"] = args.target
	return ScriptContext.make(game, scopes.actor, scopes)


## Кто принимает решение: сам получатель или (decider: guardian) его опекун-сюзерен.
static func decider_of(game: Game, def: Dictionary, recipient: Dictionary) -> Dictionary:
	var dec: Variant = def.get("decider")
	if dec == null or dec == "recipient":
		return recipient
	if dec == "guardian":
		if recipient.titles.is_empty() and recipient.liege != null:
			var g: Variant = game.ch(recipient.liege)
			if g != null and Chars.is_alive(g):
				return g
		return recipient
	var reg: Variant = game.engine.interaction_deciders.get_item(str(dec))
	var d: Variant = reg.decider.call(game, recipient, null) if reg != null else null
	return d if (d != null and Chars.is_alive(d)) else recipient


static func defs(game: Game) -> Array:
	return game.content.all("interactions")


static func is_shown(game: Game, def: Dictionary, actor: Dictionary, recipient: Dictionary) -> bool:
	if not Chars.is_alive(actor) or not Chars.is_alive(recipient):
		return false
	if def.get("self", false):
		if actor.id != recipient.id:
			return false
	elif actor.id == recipient.id:
		return false
	# Пленники ничего не предпринимают; с пленником доступны только взаимодействия с prisoner: only/allowed.
	if actor.get("prison") != null:
		return false
	var mode: String = str(def.get("prisoner", "never"))
	if (mode == "never") if recipient.get("prison") != null else (mode == "only"):
		return false
	var ctx := context(game, def, actor, recipient)
	return Interp.eval_trigger(ctx, ctx.root, def.get("is_shown"))


static func _cooldown_key(def: Dictionary, recipient: Dictionary) -> String:
	return "ia:%s:%s" % [def.id, recipient.id]


static func cost(game: Game, def: Dictionary, ctx: ScriptContext) -> Dictionary:
	var cd: Dictionary = def.get("cost") if def.get("cost") is Dictionary else {}
	return {
		"gold": roundf(Interp.eval_value(ctx, ctx.root, cd.get("gold", 0))),
		"prestige": roundf(Interp.eval_value(ctx, ctx.root, cd.get("prestige", 0))),
		"piety": roundf(Interp.eval_value(ctx, ctx.root, cd.get("piety", 0))),
	}


static func secondary_candidates(game: Game, def: Dictionary, actor: Dictionary, recipient: Dictionary) -> Array:
	var sa: Variant = def.get("secondary_actor")
	if not (sa is Dictionary):
		return []
	var ctx := context(game, def, actor, recipient)
	var seen := {}
	var out := []
	for lname in Data.as_array(sa.get("list")):
		var lst: Variant = game.engine.scripting.lists.get_item(str(lname))
		if lst == null:
			game.script_error("Взаимодействие %s: нет списка \"%s\"" % [def.id, lname])
			continue
		for ref in lst.list.call(ctx, ctx.root):
			if ref.type != "character" or seen.has(ref.id):
				continue
			seen[ref.id] = true
			var c: Variant = game.ch(ref.id)
			if c == null or not Chars.is_alive(c):
				continue
			var sctx = context(game, def, actor, recipient, {"secondary": c.id})
			if Interp.eval_trigger(sctx, {"type": "character", "id": c.id}, sa.get("trigger")):
				out.append(c)
	return out


static func target_options(game: Game, def: Dictionary, actor: Dictionary, recipient: Dictionary) -> Array:
	var t: Variant = def.get("target")
	if not (t is Dictionary):
		return []
	var p: Variant = game.engine.interaction_targets.get_item(str(t.get("provider")))
	if p == null:
		game.script_error("Взаимодействие %s: нет поставщика целей \"%s\"" % [def.id, t.get("provider")])
		return []
	return p.options.call(game, actor, recipient)


## Причины, по которым взаимодействие сейчас недоступно (пусто — доступно).
static func blockers(game: Game, def: Dictionary, actor: Dictionary, recipient: Dictionary, args: Dictionary = {}) -> Array:
	var ctx := context(game, def, actor, recipient, args)
	var out := Interp.failed_triggers(ctx, ctx.root, def.get("is_valid"))
	out.append_array(Economy.cost_blockers(game, actor, cost(game, def, ctx)))
	var cd: Variant = actor.flags.get(_cooldown_key(def, recipient))
	if cd != null and cd > game.date:
		out.append(game.loc.t("ui.on_cooldown", {"days": int(cd) - game.date}))
	if def.get("secondary_actor") != null and args.get("secondary") == null and secondary_candidates(game, def, actor, recipient).is_empty():
		out.append(game.loc.t("ui.no_candidates"))
	if def.get("target") != null and args.get("target") == null and target_options(game, def, actor, recipient).is_empty():
		out.append(game.loc.t("ui.no_targets"))
	if def.get("scheme") != null:
		for s in game.state.schemes.values():
			if s.owner == actor.id and s.type == def.scheme and s.target == recipient.id:
				out.append(game.loc.t("ui.scheme_exists"))
				break
	return out


## Можно ли в этом взаимодействии надавить крюком на решающего.
static func hook_available(game: Game, def: Dictionary, actor: Dictionary, recipient: Dictionary) -> bool:
	if def.get("scheme") != null or def.get("hookable") == false or def.get("ai_accept") == null:
		return false
	var decider := decider_of(game, def, recipient)
	return decider.id != actor.id and Leverage.can_use_hook(game, actor, decider.id)


static func is_auto_accept(game: Game, def: Dictionary, ctx: ScriptContext, actor: Dictionary, recipient: Dictionary, args: Dictionary = {}) -> bool:
	if def.get("scheme") != null:
		return true
	if args.get("use_hook", false) and hook_available(game, def, actor, recipient):
		return true
	if actor.id == recipient.id or (ctx.scopes.has("decider") and ctx.scopes.decider.id == actor.id):
		return true
	var aa: Variant = def.get("auto_accept")
	if (aa is bool and aa) or (aa is String and aa == "yes"):
		return true
	if aa is Dictionary or aa is Array:
		return Interp.eval_trigger(ctx, ctx.root, aa)
	return def.get("ai_accept") == null


## {auto, total, parts: [{label, value}]}
static func acceptance(game: Game, def: Dictionary, actor: Dictionary, recipient: Dictionary, args: Dictionary = {}) -> Dictionary:
	var ctx := context(game, def, actor, recipient, args)
	if is_auto_accept(game, def, ctx, actor, recipient, args):
		return {"auto": true, "total": 1.0, "parts": []}
	var parts := []
	var total := Interp.eval_value(ctx, ctx.scopes.decider, def.get("ai_accept"), parts)
	return {"auto": false, "total": total, "parts": parts}


## Возвращает "accepted", "declined", "pending", "invalid" или "scheme".
static func execute(game: Game, def: Dictionary, actor: Dictionary, recipient: Dictionary, args: Dictionary = {}) -> String:
	if not is_shown(game, def, actor, recipient):
		return "invalid"
	if not blockers(game, def, actor, recipient, args).is_empty():
		return "invalid"
	if not game.engine.hooks.veto("interaction.before", {"game": game, "interaction": def.id, "actor": actor, "recipient": recipient, "args": args}):
		return "invalid"
	var ctx := context(game, def, actor, recipient, args)
	var cst := cost(game, def, ctx)
	actor.gold -= cst.gold
	actor.prestige -= cst.prestige
	actor.piety -= cst.piety
	if def.get("cooldown") != null:
		actor.flags[_cooldown_key(def, recipient)] = game.date + GameDate.duration_days(def.cooldown)

	if def.get("scheme") != null:
		var s: Variant = Schemes.start_scheme(game, def.scheme, actor, recipient)
		if s != null:
			Interp.run_effect(ctx, ctx.root, def.get("on_accept"))
		return "scheme" if s != null else "invalid"
	if is_auto_accept(game, def, ctx, actor, recipient, args):
		if args.get("use_hook", false) and hook_available(game, def, actor, recipient):
			var decider := decider_of(game, def, recipient)
			Leverage.use_hook(game, actor, decider.id)
			if game.is_player(decider.id):
				game.message(game.loc.t("msg.hook_used_on_you", {"who": game.scope_name({"type": "character", "id": actor.id}), "what": game.name_of("interactions", def.id)}), "bad", {"type": "character", "id": actor.id})
		Interp.run_effect(ctx, ctx.root, def.get("on_accept"))
		game.emit("interaction", {"interaction": def.id, "actor": actor.id, "recipient": recipient.id, "accepted": true})
		return "accepted"
	if game.is_player(decider_of(game, def, recipient).id):
		game.state.pending_requests.append({
			"uid": game.new_id("rq"), "interaction": def.id, "actor": actor.id, "recipient": recipient.id,
			"secondary": args.get("secondary"), "target": args.get("target"),
		})
		game.notify("event")
		return "pending"
	var acc := acceptance(game, def, actor, recipient, args)
	var ok: bool = acc.total > 0
	Interp.run_effect(ctx, ctx.root, def.get("on_accept") if ok else def.get("on_decline"))
	if game.is_player(actor.id):
		var txt: Variant = def.get("accept_text", "msg.interaction_accepted") if ok else def.get("decline_text", "msg.interaction_declined")
		game.message(game.text(txt, ctx, {"who": game.scope_name({"type": "character", "id": recipient.id}), "what": game.name_of("interactions", def.id)}), "good" if ok else "bad", {"type": "character", "id": recipient.id})
	game.emit("interaction", {"interaction": def.id, "actor": actor.id, "recipient": recipient.id, "accepted": ok})
	return "accepted" if ok else "declined"


## Игрок ответил на предложение ИИ.
static func resolve_request(game: Game, uid: String, accept: bool) -> void:
	var i := -1
	for k in game.state.pending_requests.size():
		if game.state.pending_requests[k].uid == uid:
			i = k
			break
	if i < 0:
		return
	var r: Dictionary = game.state.pending_requests[i]
	game.state.pending_requests.remove_at(i)
	var def: Variant = game.content.get_def("interactions", r.interaction)
	var actor: Variant = game.ch(r.actor)
	var recipient: Variant = game.ch(r.recipient)
	if def == null or not Chars.is_alive(actor) or not Chars.is_alive(recipient):
		return
	if r.get("secondary") != null and not game.is_alive(r.secondary):
		return
	var ctx := context(game, def, actor, recipient, {"secondary": r.get("secondary"), "target": r.get("target")})
	if accept and not Interp.failed_triggers(ctx, ctx.root, def.get("is_valid")).is_empty():
		return
	Interp.run_effect(ctx, ctx.root, def.get("on_accept") if accept else def.get("on_decline"))
	game.emit("interaction", {"interaction": def.id, "actor": actor.id, "recipient": recipient.id, "accepted": accept})
	game.notify("event")

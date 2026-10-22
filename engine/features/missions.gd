class_name Missions
extends EngineFeature
## Поручения: человек из круга правителя — сын, дочь, придворный, рыцарь —
## уходит в мир с делом: посольство, служба при чужом дворе, странствие за
## славой, паломничество, проповедь. Пока он в пути, с ним случается
## всякое (события приходят покровителю), а по возвращении исход решает
## проверка его навыков: удача, «отчасти» или провал. Может и не вернуться.
## ИИ отправляет своих людей так же.
##
## Данные (missions):
##   icon
##   agent: { ... }           — кто может идти (root — агент, scope:patron)
##   target: ruler | county   — куда (без поля — без цели: странствие)
##   target_trigger: { ... }  — какие цели годятся (root — цель, scope:patron, scope:agent)
##   months: 8                — срок (значение; root — агент)
##   cost: { gold, prestige, piety }
##   accept: { ... }          — согласится ли агент (как ai_accept; нет — идёт без спроса)
##   events: { <событие>: вес } — события в пути (root — покровитель, scope:agent, scope:target)
##   event_chance: 20         — шанс события в месяц, % (defines.missions.event_chance)
##   check: { skill, base, add } — проверка по возвращении (root — агент, scope:patron, scope:target)
##   success / partial / failure — исходы (как у эффекта check)
##   ai_will_do, ai_frequency_months — ИИ-покровитель (root — он, scope:recipient — агент, scope:target)
## Для каждого поручения движок сам создаёт взаимодействие mission_<id>
## (категория missions; своё с таким id в данных его заменяет) и отзыв
## mission_recall. Агент — тот, кто живёт при дворе покровителя (или его
## ребёнок без земли), не моложе defines.missions.min_age, не в темнице, не в
## совете и не в другом поручении. В отъезде он не служит рыцарем и не
## садится в совет.
## Состояние: агент — c.vars.mission = { id, patron, target, start, until }.
## Хук mission.ended — {agent, patron, mission, result: success|partial|failure|dead|recalled}.

const OWNER := "core/missions"


func _init() -> void:
	id = "missions"
	doc = "Поручения: люди правителя уходят в мир с делом"


static func of(c: Variant) -> Variant:
	return c.vars.get("mission") if c is Dictionary else null


static func is_away(c: Variant) -> bool:
	return c is Dictionary and c.vars.has("mission")


## Может ли agent уйти с поручением mid от patron.
static func can_go(game: Game, mid: String, agent: Dictionary, patron: Dictionary) -> bool:
	var d: Variant = game.content.get_def("missions", mid)
	if d == null or agent.id == patron.id or not Chars.is_alive(agent) or not agent.titles.is_empty():
		return false
	if agent.get("prison") != null or is_away(agent) or Chars.age_of(game, agent) < game.def_num("missions.min_age", 15):
		return false
	var at_court: bool = agent.liege == patron.id or (agent.liege == null and (agent.father == patron.id or agent.mother == patron.id))
	if not at_court or Council.position_of(game, agent) != null:
		return false
	var ctx := ScriptContext.make(game, {"type": "character", "id": agent.id}, {"patron": {"type": "character", "id": patron.id}, "agent": {"type": "character", "id": agent.id}})
	return Interp.eval_trigger(ctx, ctx.root, d.get("agent"))


## Куда можно отправить: [{id, label, ref}] (для окна взаимодействия).
static func targets(game: Game, mid: String, patron: Dictionary, agent: Dictionary) -> Array:
	var d: Variant = game.content.get_def("missions", mid)
	if d == null or d.get("target") == null:
		return []
	var refs := []
	match str(d.target):
		"ruler":
			for r in game.rulers():
				if r.id != patron.id and r.id != agent.id:
					refs.append({"type": "character", "id": r.id})
		"county":
			for cid in Titles.realm_counties(game, patron):
				refs.append({"type": "province", "id": cid})
	var scopes := {"patron": {"type": "character", "id": patron.id}, "agent": {"type": "character", "id": agent.id}}
	var out := []
	for ref in refs:
		var ctx := ScriptContext.make(game, ref, scopes)
		if Interp.eval_trigger(ctx, ref, d.get("target_trigger")):
			out.append({"id": ref.id, "label": game.scope_name(ref), "ref": ref})
	# правители — сначала крупные и славные; не больше defines.missions.max_targets
	if str(d.target) == "ruler":
		Data.sort_by(out, func(o):
			var r: Dictionary = game.ch(o.id)
			return Titles.primary_tier(game, r) * 100000.0 + float(r.prestige), true)
	return out.slice(0, int(game.def_num("missions.max_targets", 12)))


static func start(game: Game, mid: String, agent: Dictionary, patron: Dictionary, target: Variant = null) -> void:
	var d: Variant = game.content.get_def("missions", mid)
	if d == null:
		return
	var scopes := _scopes(patron.id, agent.id, target)
	var ctx := ScriptContext.make(game, {"type": "character", "id": agent.id}, scopes)
	var months := maxf(1.0, Interp.eval_value(ctx, ctx.root, d.get("months", 6)))
	agent.vars["mission"] = {"id": mid, "patron": patron.id, "target": target, "start": game.date, "until": game.date + roundi(months * 30.4)}
	game.month_cache.erase("knights:" + patron.id)
	game.emit("mission.started", {"agent": agent, "patron": patron.id, "mission": mid})
	if game.is_player(patron.id):
		game.message(game.loc.t("msg.mission_started", _msg_args(game, mid, agent, target, roundi(months))), "info", {"type": "character", "id": agent.id})
	game.notify("character")


static func _scopes(patron_id: Variant, agent_id: String, target: Variant) -> Dictionary:
	var s := {"agent": {"type": "character", "id": agent_id}}
	if patron_id != null:
		s["patron"] = {"type": "character", "id": patron_id}
	if target is Dictionary:
		s["target"] = target
	return s


static func _msg_args(game: Game, mid: String, agent: Dictionary, target: Variant, months: int = 0) -> Dictionary:
	return {"agent": game.scope_name({"type": "character", "id": agent.id}), "mission": game.name_of("missions", mid),
		"target": (" — " + game.scope_name(target)) if target is Dictionary else "", "months": months}


## Конец поручения без исхода (отозван, погиб, схвачен).
static func finish(game: Game, agent: Dictionary, result: String) -> void:
	var m: Variant = of(agent)
	if m == null:
		return
	agent.vars.erase("mission")
	var patron: Variant = game.ch(str(m.patron)) if m.get("patron") != null else null
	if patron != null:
		game.month_cache.erase("knights:" + patron.id)
	game.emit("mission.ended", {"agent": agent, "patron": m.get("patron"), "mission": m.id, "result": result})
	if patron != null and game.is_player(patron.id) and result in ["dead", "recalled", "captured"]:
		game.message(game.loc.t("msg.mission_" + result, _msg_args(game, str(m.id), agent, m.get("target"))),
			"info" if result == "recalled" else "bad", {"type": "character", "id": agent.id})
	game.notify("character")


## Возвращение: проверка и её исход, весть покровителю.
static func resolve(game: Game, agent: Dictionary) -> void:
	var m: Variant = of(agent)
	var d: Variant = game.content.get_def("missions", str(m.id)) if m != null else null
	if d == null:
		agent.vars.erase("mission")
		return
	var patron: Variant = game.ch(str(m.patron)) if m.get("patron") != null else null
	var ctx := ScriptContext.make(game, {"type": "character", "id": agent.id}, _scopes(patron.id if patron != null and Chars.is_alive(patron) else null, agent.id, m.get("target")))
	ctx.values["__src"] = "mission:" + str(m.id)
	agent.vars.erase("mission")
	var spec: Dictionary = (d.get("check") if d.get("check") is Dictionary else {}).duplicate()
	for k in ["success", "partial", "failure"]:
		if d.get(k) != null:
			spec[k] = d[k]
	spec["name"] = "mission." + str(m.id)
	var result := Checks.run(ctx, ctx.root, spec)
	if patron != null:
		game.month_cache.erase("knights:" + patron.id)
		if game.is_player(patron.id):
			game.message(game.loc.t("msg.mission_" + result, _msg_args(game, str(m.id), agent, m.get("target"))),
				{"success": "good", "partial": "info", "failure": "bad"}[result], {"type": "character", "id": agent.id})
	game.emit("mission.ended", {"agent": agent, "patron": m.get("patron"), "mission": m.id, "result": result})
	game.notify("character")


## Раз в месяц (в день агента): событие в пути или возвращение.
static func monthly_char(game: Game, c: Dictionary) -> void:
	var m: Variant = of(c)
	if m == null:
		return
	if c.get("prison") != null:
		finish(game, c, "captured")
		return
	if game.date >= int(m.until):
		resolve(game, c)
		return
	var d: Variant = game.content.get_def("missions", str(m.id))
	var patron: Variant = game.ch(str(m.patron)) if m.get("patron") != null else null
	if d == null or patron == null or not Chars.is_alive(patron) or not (d.get("events") is Dictionary):
		return
	if not game.rng.chance(Data.num(d.get("event_chance"), game.def_num("missions.event_chance", 20)) / 100.0):
		return
	var root := {"type": "character", "id": patron.id}
	var scopes := _scopes(patron.id, c.id, m.get("target"))
	var cands := []
	for ev in d.events:
		var ed: Variant = game.events.def(str(ev))
		if ed == null:
			continue
		var ectx := ScriptContext.make(game, root, scopes)
		if game.events.can_fire(ed, root, ectx):
			cands.append({"event": str(ev), "w": Interp.eval_value(ectx, root, d.events[ev])})
	var pick: Variant = game.rng.weighted(cands.filter(func(x): return x.w > 0.0), func(x): return x.w)
	if pick != null:
		game.events.fire(pick.event, root, scopes)


func install(engine: GameEngine) -> void:
	engine.systems.register("missions", {"id": "missions", "order": 16, "on_character_month": Missions.monthly_char}, OWNER)
	# погиб в пути — весть покровителю; умер покровитель — служат наследнику
	engine.hooks.on("character.death", func(p):
		var game: Game = p.game
		var dead: Dictionary = p.character
		if Missions.is_away(dead):
			Missions.finish(game, dead, "dead")
		var heir: Variant = p.get("heir")
		for c in game.living():
			var m: Variant = Missions.of(c)
			if m != null and str(m.get("patron")) == dead.id:
				m.patron = heir
	, 0, OWNER)
	# цели поручений и взаимодействия «Отправить…» (своё с тем же id в данных — важнее)
	for d in engine.content.all("missions"):
		var mid: String = d.id
		engine.interaction_targets.register("mission:" + mid, {"options": func(game: Game, actor: Dictionary, recipient: Dictionary) -> Array:
			return Missions.targets(game, mid, actor, recipient)
		}, OWNER)
		var iid := "mission_" + mid
		if engine.content.has("interactions", iid):
			continue
		var def := {
			"icon": d.get("icon", "scroll"),
			"category": "missions",
			"name": "mission." + mid,
			"desc": "mission_desc." + mid,
			"is_shown": {"scope:recipient": {"can_go_on_mission": mid}},
			"cost": d.get("cost", {}),
			"on_accept": {"start_mission": mid},
			"ai_targets": ["child", "courtier"],
			"ai_frequency_months": d.get("ai_frequency_months", engine.content.singleton("defines").get("missions", {}).get("ai_frequency_months", 12)),
			"hookable": false,
		}
		if d.get("target") != null:
			def["target"] = {"provider": "mission:" + mid}
		if d.get("accept") != null:
			def["ai_accept"] = d.accept
		else:
			def["auto_accept"] = true
		if d.get("ai_will_do") != null:
			def["ai_will_do"] = d.ai_will_do
		engine.content.set_def("interactions", iid, def)
	if not engine.content.has("interactions", "mission_recall"):
		engine.content.set_def("interactions", "mission_recall", {
			"icon": "↩", "category": "missions", "name": "mission.recall", "desc": "mission_desc.recall",
			"is_shown": {"scope:recipient": {"is_on_mission_of": "scope:actor"}},
			"auto_accept": true, "hookable": false,
			"on_accept": {"scope:recipient": {"end_mission": "recalled"}},
		})
	engine.content_validators.register("missions", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("missions"):
			var w := "missions/" + str(d.id)
			v.trigger(d.get("agent"), w + " agent")
			v.trigger(d.get("target_trigger"), w + " target_trigger")
			if d.get("target") != null and not (str(d.target) in ["ruler", "county"]):
				v.issue("%s: target — ruler или county" % w)
			for ev in (d.events if d.get("events") is Dictionary else {}):
				v.ref("events", ev, w + " events")
			v.check(d.get("check") if d.get("check") is Dictionary else {}, w)
			for k in ["success", "partial", "failure"]:
				v.effect(d.get(k), "%s %s" % [w, k])
	, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	r.triggers.register("can_go_on_mission", {"scopes": CH, "doc": "Может уйти с поручением от scope:actor (или scope:patron): can_go_on_mission: <поручение>", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var pref: Variant = ctx.scopes.get("actor", ctx.scopes.get("patron"))
		var p: Variant = ctx.game.ch(pref.id) if pref is Dictionary else null
		return c != null and p != null and Missions.can_go(ctx.game, str(arg), c, p),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.can_go_on_mission", {"name": ctx.game.name_of("missions", str(arg))}),
	}, OWNER)
	r.triggers.register("on_mission", {"scopes": CH, "doc": "В отъезде с поручением: on_mission: yes | <поручение> | [список]", "eval": func(ctx, s, arg):
		var m: Variant = Missions.of(ch.call(ctx, s))
		if arg is bool or (arg is String and (arg == "yes" or arg == "no")):
			return (m != null) == ScriptContext.is_yes(arg)
		return m != null and Data.as_array(arg).has(str(m.id)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.on_mission" if ScriptContext.is_yes(arg) or not (arg is bool or arg in ["yes", "no"]) else "tr.on_mission.not"),
	}, OWNER)
	r.triggers.register("is_on_mission_of", {"scopes": CH, "doc": "В отъезде с поручением этого покровителя: is_on_mission_of: scope:actor", "eval": func(ctx, s, arg):
		var m: Variant = Missions.of(ch.call(ctx, s))
		var o: Variant = Interp.resolve_scope(ctx, s, arg)
		return m != null and o is Dictionary and str(m.get("patron")) == str(o.get("id")),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("tr.is_on_mission_of", {"who": ctx.game.scope_name(Interp.resolve_scope(ctx, s, arg))}),
	}, OWNER)
	r.values.register("mission_months_left", {"scopes": CH, "doc": "Сколько месяцев до возвращения", "get": func(ctx, s, _a):
		var m: Variant = Missions.of(ch.call(ctx, s))
		return maxf(0.0, ceilf((float(m.until) - ctx.game.date) / 30.4)) if m != null else 0.0
	}, OWNER)
	r.lists.register("mission_agent", {"from": CH, "doc": "Люди персонажа, ушедшие с его поручениями", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		if c == null:
			return []
		return ctx.game.living().filter(func(x): return Missions.of(x) != null and str(Missions.of(x).get("patron")) == c.id).map(func(x): return {"type": "character", "id": x.id})
	}, OWNER)
	r.effects.register("start_mission", {"scopes": CH, "doc": "Отправить с поручением (в скоупе покровителя): start_mission: <поручение> (агент — scope:recipient, цель — scope:target) или { id, agent, target }",
		"apply": func(ctx, s, arg):
			var p: Variant = ch.call(ctx, s)
			var mid := str(arg.get("id")) if arg is Dictionary else str(arg)
			var aref: Variant = Interp.resolve_scope(ctx, s, arg.get("agent")) if arg is Dictionary and arg.get("agent") != null else ctx.scopes.get("recipient")
			var tref: Variant = Interp.resolve_scope(ctx, s, arg.get("target")) if arg is Dictionary and arg.get("target") != null else ctx.scopes.get("target")
			var a: Variant = ctx.game.ch(aref.id) if aref is Dictionary and aref.get("type") == "character" else null
			if p != null and a != null:
				Missions.start(ctx.game, mid, a, p, tref),
		"describe": func(ctx, _s, arg):
			var mid := str(arg.get("id")) if arg is Dictionary else str(arg)
			return ctx.game.loc.t("fx.start_mission", {"name": ctx.game.name_of("missions", mid)}),
	}, OWNER)
	r.effects.register("end_mission", {"scopes": CH, "doc": "Прервать поручение (агент возвращается без исхода): end_mission: recalled",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				Missions.finish(ctx.game, c, str(arg) if arg is String and arg != "yes" else "recalled"),
		"describe": func(ctx, s, _arg): return ctx.game.loc.t("fx.end_mission", {"who": ctx.game.scope_name(s)}),
	}, OWNER)

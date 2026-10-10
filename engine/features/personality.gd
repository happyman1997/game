class_name Personality
extends EngineFeature
## Характер. Черты отзываются стрессом на поступки и положение:
##   traits:
##     compassionate:
##       stress_reactions: { execute_prisoner: 40, give_alms: -15 }   # поступок → стресс
##       stress_monthly: { trigger: { is_at_war: yes }, value: 4 }     # каждый месяц, пока верно
## Поступок — id взаимодействия (принятого; если оно запускает интригу —
## считается сама интрига), решения, интриги (при её начале) или declare_war.
## Отрицательное значение — поступок по душе и снимает стресс. ИИ избегает
## того, что ему претит, и охотнее делает то, что по душе
## (defines.personality.ai_weight — сколько воли за очко стресса).

const OWNER := "core/personality"


func _init() -> void:
	id = "personality"
	doc = "Характер: черты отзываются стрессом на поступки, ИИ поступает по характеру"


## Источники характера: черты и тени мастерства навыков (skills.<id>.mastery,
## источник "mastery:<навык>"). [[источник, определение с stress_*], ...]
static func _sources(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("personality:src")
	if hit == null:
		hit = []
		for t in game.content.all("traits"):
			if t.get("stress_reactions") is Dictionary or t.get("stress_monthly") is Dictionary:
				hit.append([str(t.id), t])
		for sk in game.content.all("skills"):
			if sk.get("mastery") is Dictionary:
				hit.append(["mastery:" + str(sk.id), sk.mastery])
		game.engine.cache["personality:src"] = hit
	return hit


## {действие: [[источник, стресс], ...]} — на движок.
static func _index(game: Game) -> Dictionary:
	var hit: Variant = game.engine.cache.get("personality:idx")
	if hit == null:
		hit = {}
		for item in _sources(game):
			var r: Variant = item[1].get("stress_reactions")
			if not (r is Dictionary):
				continue
			for action in r:
				if not hit.has(action):
					hit[action] = []
				hit[action].append([item[0], Data.num(r[action])])
		game.engine.cache["personality:idx"] = hit
	return hit


## Источники со stress_monthly: [[источник, условие, стресс], ...].
static func _monthly(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("personality:monthly")
	if hit == null:
		hit = []
		for item in _sources(game):
			var m: Variant = item[1].get("stress_monthly")
			if m is Dictionary:
				hit.append([item[0], m.get("trigger"), Data.num(m.get("value"))])
		game.engine.cache["personality:monthly"] = hit
	return hit


## Есть ли у персонажа источник: черта или тень мастерства.
static func has_source(game: Game, c: Dictionary, src: String) -> bool:
	if src.begins_with("mastery:"):
		return Stats.stat(game, c, src) > 0.0
	return c.traits.has(src)


static func source_name(game: Game, src: String) -> String:
	if src.begins_with("mastery:"):
		return game.loc.t("mastery." + src.substr(8))
	return game.name_of("traits", src)


## Сколько стресса принесёт персонажу поступок (сумма по его чертам).
static func stress_for(game: Game, c: Dictionary, action: String) -> float:
	var list: Variant = _index(game).get(action)
	if list == null:
		return 0.0
	var total := 0.0
	for pair in list:
		if has_source(game, c, pair[0]):
			total += pair[1]
	return total


## Черты, которые отзываются на поступок: [[источник, стресс], ...].
static func reacting_traits(game: Game, c: Dictionary, action: String) -> Array:
	return Data.as_array(_index(game).get(action)).filter(func(pair): return Personality.has_source(game, c, pair[0]))


## Поправка к желанию ИИ: претит — меньше, по душе — больше.
static func ai_will_shift(game: Game, c: Dictionary, action: String) -> float:
	var s := stress_for(game, c, action)
	return -s * game.def_num("personality.ai_weight", 0.5) if s != 0.0 else 0.0


## Название поступка для текстов.
static func action_name(game: Game, action: String) -> String:
	if action == "declare_war":
		return game.loc.t("ui.declare_war_action")
	for kind in ["interactions", "decisions", "schemes"]:
		if game.content.has(kind, action):
			return game.name_of(kind, action)
	return action


## Строки для подсказки черты: что претит, что по душе, что тяготит каждый месяц.
static func trait_summary(game: Game, tdef: Dictionary) -> Dictionary:
	var bad := []
	var good := []
	var r: Variant = tdef.get("stress_reactions")
	if r is Dictionary:
		for action in r:
			var v := Data.num(r[action])
			if v == 0.0 or not (action == "declare_war" or game.content.has("interactions", action) or game.content.has("decisions", action) or game.content.has("schemes", action)):
				continue
			(bad if v > 0 else good).append("%s (%+d)" % [action_name(game, action), roundi(v)])
	var monthly := ""
	var m: Variant = tdef.get("stress_monthly")
	if m is Dictionary and m.get("desc") != null:
		monthly = game.loc.t("ui.stress_monthly", {"when": game.loc.t(str(m.desc)), "value": "%+d" % roundi(Data.num(m.get("value")))})
	return {"bad": ", ".join(bad), "good": ", ".join(good), "monthly": monthly}


## Изменить стресс (рост умножается на stress_gain_mult, как у эффекта add_stress).
static func add_stress(game: Game, c: Dictionary, v: float) -> void:
	if v > 0.0:
		v *= maxf(0.0, 1.0 + Stats.stat(game, c, "stress_gain_mult"))
	c.stress = maxf(0.0, float(c.stress) + v)


## Отклик характера на поступок: стресс и, для игрока, запись в журнал.
static func react(game: Game, c: Variant, action: String, action_name: String = "") -> void:
	if c == null or c.death != null:
		return
	var parts := reacting_traits(game, c, action)
	if parts.is_empty():
		return
	var total := 0.0
	for pair in parts:
		total += pair[1]
	if total == 0.0:
		return
	var before := float(c.stress)
	add_stress(game, c, total)
	game.emit("personality.reacted", {"character": c, "action": action, "stress": float(c.stress) - before})
	if game.is_player(c.id):
		var names := ", ".join(parts.map(func(pair): return Personality.source_name(game, pair[0])))
		game.message(game.loc.t("msg.stress_reaction_bad" if total > 0 else "msg.stress_reaction_good", {
			"action": action_name if action_name != "" else action, "traits": names,
			"value": "%+d" % roundi(float(c.stress) - before)}), "bad" if total > 0 else "good", {"type": "character", "id": c.id})


static func monthly_char(game: Game, c: Dictionary) -> void:
	var list := _monthly(game)
	if list.is_empty() or c.death != null:
		return
	var ctx: ScriptContext = null
	for item in list:
		if not Personality.has_source(game, c, item[0]):
			continue
		if ctx == null:
			ctx = ScriptContext.make(game, {"type": "character", "id": c.id})
		if Interp.eval_trigger(ctx, ctx.root, item[1]):
			add_stress(game, c, item[2])


func install(engine: GameEngine) -> void:
	engine.systems.register("personality", {"id": "personality", "order": 12, "on_character_month": Personality.monthly_char}, OWNER)
	engine.hooks.on("interaction", func(p):
		if not p.accepted:
			return
		var g: Game = p.game
		var def: Variant = g.content.get_def("interactions", p.interaction)
		if def != null and def.get("scheme") == null:
			Personality.react(g, g.ch(p.actor), p.interaction, g.name_of("interactions", p.interaction))
	, 0, OWNER)
	engine.hooks.on("decision.taken", func(p):
		var g: Game = p.game
		Personality.react(g, g.ch(p.character), p.decision, g.name_of("decisions", p.decision))
	, 0, OWNER)
	engine.hooks.on("scheme.started", func(p):
		var g: Game = p.game
		Personality.react(g, g.ch(p.scheme.owner), p.scheme.type, g.name_of("schemes", p.scheme.type))
	, 0, OWNER)
	engine.hooks.on("war.declared", func(p):
		var g: Game = p.game
		Personality.react(g, g.ch(p.war.attacker), "declare_war", g.loc.t("ui.declare_war_action"))
	, 0, OWNER)


func register_script(engine: GameEngine) -> void:
	engine.content_validators.register("personality", func(e: GameEngine, v: ScriptValidator):
		var known := {"declare_war": true}
		for kind in ["interactions", "decisions", "schemes"]:
			for d in e.content.all(kind):
				known[str(d.id)] = true
		var defs := []
		for t in e.content.all("traits"):
			defs.append(["traits/" + str(t.id), t])
		for sk in e.content.all("skills"):
			if sk.get("mastery") != null:
				defs.append(["skills/%s mastery" % sk.id, sk.mastery])
		for item in defs:
			var where: String = item[0]
			var t: Variant = item[1]
			if not (t is Dictionary):
				v.issue("%s: ожидается словарь" % where)
				continue
			var r: Variant = t.get("stress_reactions")
			if r != null and not (r is Dictionary):
				v.issue("%s: stress_reactions должен быть словарём" % where)
				continue
			for action in (r if r is Dictionary else {}):
				if not known.has(str(action)):
					v.issue("%s: stress_reactions — неизвестный поступок \"%s\"" % [where, action])
			var m: Variant = t.get("stress_monthly")
			if m is Dictionary:
				v.trigger(m.get("trigger"), "%s stress_monthly" % where)
	, OWNER)

class_name Momentum
extends EngineFeature
## Кураж и хандра. Успехи в одной сфере (навыке) подряд дают кураж: навык
## растёт на skill_per_level за ступень, каждый успех снимает стресс. Провалы
## подряд — хандра: навык падает, провал добавляет стресс. Без новых успехов
## и провалов ступень за decay_days уходит к нулю. Кураж от uplift_level —
## «душевный подъём»: стресс копится медленнее.
## Успехи и провалы: проверки навыков в событиях, интриги (по навыку
## интриги), битвы (военное дело), дипломатические и интриганские
## взаимодействия игрока, которые решает другая сторона.
##   defines.momentum: { max_level, skill_per_level, decay_days, success_stress,
##                       failure_stress, uplift_level, uplift_stress_gain }
## Состояние — c.vars.momentum: {навык: [ступень, дата последнего изменения]}.

const OWNER := "core/momentum"


func _init() -> void:
	id = "momentum"
	doc = "Кураж и хандра: полосы удач и неудач в одной сфере меняют навык и стресс"


static func level(c: Dictionary, skill: String) -> int:
	var m: Variant = c.vars.get("momentum")
	if not (m is Dictionary) or not m.has(skill):
		return 0
	return int(m[skill][0])


## Успех (true) или провал в сфере навыка.
static func record(game: Game, c: Variant, skill: String, success: bool) -> void:
	if not (c is Dictionary) or c.death != null or skill == "" or not game.content.has("skills", skill):
		return
	if not Chars.is_adult(game, c):
		return
	var mx := int(game.def_num("momentum.max_level", 3))
	var cur := level(c, skill)
	var nxt := mini(mx, maxi(cur, 0) + 1) if success else maxi(-mx, mini(cur, 0) - 1)
	var m: Dictionary = c.vars.get("momentum", {})
	if nxt == 0:
		m.erase(skill)
	else:
		m[skill] = [nxt, game.date]
	if m.is_empty():
		c.vars.erase("momentum")
	else:
		c.vars["momentum"] = m
	if nxt != cur:
		game.stat_cache.erase(c.id)
	# успех снимает стресс, провал добавляет — сильнее на полосе
	var base := game.def_num("momentum.success_stress", -4) if success else game.def_num("momentum.failure_stress", 4)
	var delta := base * (1.0 + absf(nxt) * 0.5)
	Chars.change_stress(game, c, delta, "momentum:" + skill)
	if game.is_player(c.id) and absi(nxt) >= 2 and absi(nxt) > absi(cur):
		game.message(game.loc.t("msg.momentum_up" if nxt > 0 else "msg.momentum_down", {"skill": game.name_of("skills", skill), "n": absi(nxt)}), "good" if nxt > 0 else "bad", {"type": "character", "id": c.id})
	game.emit("momentum.changed", {"character": c, "skill": skill, "level": nxt, "success": success})


static func monthly_char(game: Game, c: Dictionary) -> void:
	var m: Variant = c.vars.get("momentum")
	if not (m is Dictionary):
		return
	var decay := int(game.def_num("momentum.decay_days", 365))
	var changed := false
	for skill in m.keys():
		var e: Array = m[skill]
		if game.date - int(e[1]) >= decay:
			var lv := int(e[0])
			lv -= signi(lv)
			changed = true
			if lv == 0:
				m.erase(skill)
			else:
				m[skill] = [lv, game.date]
	if m.is_empty():
		c.vars.erase("momentum")
	if changed:
		game.stat_cache.erase(c.id)


func install(engine: GameEngine) -> void:
	engine.systems.register("momentum", {"id": "momentum", "order": 13, "on_character_month": Momentum.monthly_char}, OWNER)
	engine.modifier_providers.register("momentum", {"fn": func(game: Game, c: Dictionary) -> Variant:
		var m: Variant = c.vars.get("momentum")
		if not (m is Dictionary):
			return null
		var out := []
		var per := game.def_num("momentum.skill_per_level", 1)
		var uplift := false
		for skill in m:
			var lv := int(m[skill][0])
			if lv == 0:
				continue
			var sk: String = skill
			out.append({"label": func(): return game.loc.t("modsrc.momentum_up" if lv > 0 else "modsrc.momentum_down", {"skill": game.name_of("skills", sk), "n": absi(lv)}),
				"modifiers": {sk: lv * per}})
			if lv >= int(game.def_num("momentum.uplift_level", 2)):
				uplift = true
		if uplift:
			out.append({"label": func(): return game.loc.t("modsrc.uplift"), "modifiers": {"stress_gain_mult": game.def_num("momentum.uplift_stress_gain", -0.2)}})
		return out
	}, OWNER)
	engine.hooks.on("event.check", func(p):
		Momentum.record(p.game, p.game.ch(p.character), str(p.skill), p.success)
	, 0, OWNER)
	engine.hooks.on("scheme.ended", func(p):
		var g: Game = p.game
		var d: Variant = g.content.get_def("schemes", p.scheme.type)
		if d != null and d.get("skill") != null:
			Momentum.record(g, g.ch(p.scheme.owner), str(d.skill), p.success)
	, 0, OWNER)
	engine.hooks.on("scheme.discovered", func(p):
		var g: Game = p.game
		var d: Variant = g.content.get_def("schemes", p.scheme.type)
		if d != null and d.get("skill") != null:
			Momentum.record(g, g.ch(p.scheme.owner), str(d.skill), false)
	, 0, OWNER)
	engine.hooks.on("battle", func(p):
		var g: Game = p.game
		Momentum.record(g, g.ch(p.winner), "martial", true)
		Momentum.record(g, g.ch(p.loser), "martial", false)
	, 0, OWNER)
	# дипломатия и интриги: согласие или отказ другой стороны
	engine.hooks.on("interaction", func(p):
		var g: Game = p.game
		# ИИ предлагает только то, на что согласятся, — его «успехи» не в счёт
		if not g.is_player(p.actor):
			return
		var d: Variant = g.content.get_def("interactions", p.interaction)
		if d == null or d.get("scheme") != null or ScriptContext.is_yes(d.get("auto_accept", false)) or d.get("ai_accept") == null:
			return
		var cat := str(d.get("category", ""))
		if cat == "diplomacy" or cat == "intrigue":
			Momentum.record(g, g.ch(p.actor), cat, p.accepted)
	, 0, OWNER)

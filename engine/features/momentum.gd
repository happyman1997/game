class_name Momentum
extends EngineFeature
## Удачи и неудачи: успех в своём деле снимает стресс, провал — добавляет.
## Успехи и провалы: проверки навыков в событиях, интриги (по навыку
## интриги), битвы, поединки, дипломатические и интриганские
## взаимодействия игрока, которые решает другая сторона.
##   defines.momentum: { success_stress, failure_stress }
## Хук momentum.changed — {character, skill, success}.

const OWNER := "core/momentum"


func _init() -> void:
	id = "momentum"
	doc = "Удачи и неудачи: успех снимает стресс, провал добавляет"


## Успех (true) или провал в сфере навыка.
static func record(game: Game, c: Variant, skill: String, success: bool) -> void:
	if not (c is Dictionary) or c.death != null or skill == "" or not game.content.has("skills", skill):
		return
	if not Chars.is_adult(game, c):
		return
	var delta := game.def_num("momentum.success_stress", -5) if success else game.def_num("momentum.failure_stress", 5)
	Chars.change_stress(game, c, delta, "momentum:" + skill)
	game.emit("momentum.changed", {"character": c, "skill": skill, "success": success})


func install(engine: GameEngine) -> void:
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

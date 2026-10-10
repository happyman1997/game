class_name Reputation
extends EngineFeature
## Молва: что о персонаже думают. У навыков с полем reputation молва живёт
## отдельно от настоящего навыка: победы и поражения, раскрытые интриги
## сдвигают её, а со временем она тянется к правде.
##   skills.<id>.reputation: { drift: 0.2, max_gap: 10 }
## ИИ судит по молве: полководца, чья слава обгоняет правду, боятся больше
## (сила армии в глазах врага),
## вассалы реже идут против него (в данных фракций), к известному интригану
## относятся настороженно (мнение).
##   defines.reputation: { war_weight, infamy_from, infamy_per_point }

const OWNER := "core/reputation"


func _init() -> void:
	id = "reputation"
	doc = "Молва: слава полководца и дурная слава интригана живут своей жизнью"


static func _def(game: Game, skill: String) -> Variant:
	var d: Variant = game.content.get_def("skills", skill)
	return d.get("reputation") if d != null and d.get("reputation") is Dictionary else null


## Молва о навыке персонажа (без отдельной молвы — сам навык).
static func value(game: Game, c: Dictionary, skill: String) -> float:
	var v: Variant = c.vars.get("rep:" + skill)
	return float(v) if v != null else float(Stats.skill(game, c, skill))


static func add(game: Game, c: Dictionary, skill: String, v: float) -> void:
	var d: Variant = _def(game, skill)
	if d == null or c.death != null:
		return
	var actual := float(Stats.skill(game, c, skill))
	var gap := Data.num(d.get("max_gap"), 10)
	c.vars["rep:" + skill] = clampf(value(game, c, skill) + v, maxf(0.0, actual - gap), actual + gap)
	game.stat_cache.erase(c.id)


## Множитель силы армии в глазах врага: насколько слава полководца
## расходится с правдой (раздутая пугает, подмоченная ободряет).
static func war_fear(game: Game, c: Dictionary) -> float:
	var v: Variant = c.vars.get("rep:martial")
	if v == null:
		return 1.0
	return maxf(0.5, 1.0 + (float(v) - float(Stats.skill(game, c, "martial"))) * game.def_num("reputation.war_weight", 0.03))


static func yearly(game: Game) -> void:
	for c in game.living():
		for key in c.vars.keys():
			if not str(key).begins_with("rep:"):
				continue
			var skill := str(key).substr(4)
			var d: Variant = _def(game, skill)
			if d == null:
				c.vars.erase(key)
				continue
			var actual := float(Stats.skill(game, c, skill))
			var cur := float(c.vars[key])
			cur += (actual - cur) * Data.num(d.get("drift"), 0.2)
			if absf(cur - actual) < 0.5:
				c.vars.erase(key)
			else:
				c.vars[key] = cur


func install(engine: GameEngine) -> void:
	engine.systems.register("reputation", {"id": "reputation", "order": 85, "on_year": Reputation.yearly}, OWNER)
	# раскрытая интрига и разоблачённый секрет — дурная слава
	engine.hooks.on("scheme.discovered", func(p):
		var g: Game = p.game
		var o: Variant = g.ch(p.scheme.owner)
		if o != null:
			Reputation.add(g, o, "intrigue", g.def_num("reputation.discovered_scheme", 2))
	, 0, OWNER)
	engine.hooks.on("secret.exposed", func(p):
		var g: Game = p.game
		var o: Variant = p.get("owner")
		if o is Dictionary:
			Reputation.add(g, o, "intrigue", g.def_num("reputation.exposed_secret", 3))
	, 0, OWNER)
	# дурная слава: к известному интригану все относятся настороженно
	engine.opinion_providers.register("reputation", {"fn": func(game: Game, _a: Dictionary, b: Dictionary) -> Variant:
		var v: Variant = b.vars.get("rep:intrigue")
		if v == null:
			return null
		var over := float(v) - game.def_num("reputation.infamy_from", 12)
		if over <= 0.0:
			return null
		return {"label": game.loc.t("opinion.infamy"), "value": roundf(over * game.def_num("reputation.infamy_per_point", -1.0))}
	}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	for skill in ["diplomacy", "martial", "stewardship", "intrigue", "learning", "prowess"]:
		var sk: String = skill
		r.values.register(sk + "_reputation", {"scopes": ["character"], "doc": "Молва о навыке «%s» (без молвы — сам навык)" % sk, "get": func(ctx, s, _a):
			var c: Variant = ctx.game.ch(s.id)
			return Reputation.value(ctx.game, c, sk) if c != null else 0.0
		}, OWNER)
	r.effects.register("add_reputation", {"scopes": ["character"], "doc": "Сдвинуть молву о навыке: add_reputation: { skill: martial, value: 2 }", "apply": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c != null and arg is Dictionary:
			Reputation.add(ctx.game, c, str(arg.get("skill")), Interp.eval_value(ctx, s, arg.get("value", 0))),
		"describe": func(ctx, s, arg):
			if not (arg is Dictionary):
				return null
			return ctx.game.loc.t("fx.add_reputation", {"skill": ctx.game.name_of("skills", str(arg.get("skill"))), "value": "%+d" % roundi(Interp.eval_value(ctx, s, arg.get("value", 0)))}),
	}, OWNER)

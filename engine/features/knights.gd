class_name Knights
extends EngineFeature
## Рыцари. Самые доблестные придворные и вассалы правителя (проходящие
## scripted_trigger knight_candidate) сопровождают его главную армию: каждое
## очко доблести стоит power_per_prowess ополченцев. В сражениях рыцари
## получают раны и гибнут.
##
##   defines.knights: { cap_by_tier, power_per_prowess, loser_death_chance,
##                      loser_wound_chance, winner_death_chance, winner_wound_chance,
##                      wound_trait, prestige_per_battle }

const OWNER := "core/knights"


func _init() -> void:
	id = "knights"
	doc = "Рыцари: доблестные придворные и вассалы усиливают армию правителя"


static func cap(game: Game, c: Dictionary) -> int:
	var by_tier: Array = game.def_val("knights.cap_by_tier", [0, 3, 5, 8, 12])
	var pt := Titles.primary_tier(game, c)
	return maxi(0, floori((Data.num(by_tier[pt]) if pt < by_tier.size() else 0.0) + Stats.stat(game, c, "knight_cap")))


static func is_candidate(game: Game, liege: Dictionary, c: Dictionary) -> bool:
	if not Chars.is_alive(c) or c.get("prison") != null or c.id == liege.id:
		return false
	if game.content.has("scripted_triggers", "knight_candidate"):
		var ctx := ScriptContext.make(game, {"type": "character", "id": c.id}, {"liege": {"type": "character", "id": liege.id}})
		return Interp.eval_trigger(ctx, ctx.root, "knight_candidate")
	return Stats.skill(game, c, "prowess") >= 6


## Рыцари правителя: лучшие по доблести кандидаты из двора и вассалов (кэш на месяц).
static func knights_of(game: Game, c: Dictionary) -> Array:
	return game.cached_monthly("knights:" + c.id, func():
		var pool := (game.courtiers_of(c.id) + game.vassals_of(c.id)).filter(func(x): return Knights.is_candidate(game, c, x))
		Data.sort_by(pool, func(x): return Stats.skill(game, x, "prowess"), true)
		return pool.slice(0, Knights.cap(game, c)))


static func power(game: Game, c: Dictionary) -> float:
	return game.cached_monthly("kpow:" + c.id, func():
		var k := game.def_num("knights.power_per_prowess", 8)
		var total := 0.0
		for x in Knights.knights_of(game, c):
			total += Stats.skill(game, x, "prowess") * k
		return total * maxf(0.0, 1.0 + Stats.stat(game, c, "knight_effectiveness")))


## Главная (самая большая) армия правителя — с ней идут рыцари.
static func main_army_of(game: Game, owner_id: String) -> Variant:
	var best: Variant = null
	for a in game.state.armies.values():
		if a.owner == owner_id and (best == null or a.size > best.size):
			best = a
	return best


static func _battle_casualties(game: Game, owner_id: String, won: bool) -> void:
	var owner: Variant = game.ch(owner_id)
	if owner == null:
		return
	var death := game.def_num("knights.winner_death_chance", 0.01) if won else game.def_num("knights.loser_death_chance", 0.04)
	var wound := game.def_num("knights.winner_wound_chance", 0.05) if won else game.def_num("knights.loser_wound_chance", 0.12)
	for k in knights_of(game, owner):
		if k.death != null:
			continue
		if game.rng.chance(death):
			Succession.kill_character(game, k, "battle")
			continue
		if game.rng.chance(wound):
			Chars.add_trait(game, k, str(game.def_val("knights.wound_trait", "wounded")))
		elif won:
			k.prestige += game.def_num("knights.prestige_per_battle", 10)
	game.month_cache.erase("knights:" + owner.id)
	game.month_cache.erase("kpow:" + owner.id)


func install(engine: GameEngine) -> void:
	engine.hooks.on("army.power_bonus", func(p):
		var main: Variant = Knights.main_army_of(p.game, p.army.owner)
		if main == null or main.id != p.army.id:
			return null
		var owner: Variant = p.game.ch(p.army.owner)
		return Knights.power(p.game, owner) if owner != null else null
	, 0, OWNER)
	engine.hooks.on("military.strength_bonus", func(p):
		return null if Knights.main_army_of(p.game, p.character.id) != null else Knights.power(p.game, p.character)
	, 0, OWNER)
	engine.hooks.on("battle", func(p):
		Knights._battle_casualties(p.game, p.winner, true)
		Knights._battle_casualties(p.game, p.loser, false)
	, -20, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	r.triggers.register("is_knight", {"scopes": CH, "doc": "Служит рыцарем у своего сюзерена", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var l: Variant = ctx.game.ch(c.liege) if c != null else null
		var yes: bool = c != null and l != null and ctx.game.engine.has_feature("knights") and Knights.knights_of(ctx.game, l).any(func(k): return k.id == c.id)
		return yes == (arg == null or ScriptContext.is_yes(arg))
	}, OWNER)
	r.values.register("num_knights", {"scopes": CH, "doc": "Число рыцарей", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(Knights.knights_of(ctx.game, c).size()) if (c != null and ctx.game.engine.has_feature("knights")) else 0.0
	}, OWNER)
	r.values.register("knights_power", {"scopes": CH, "doc": "Сила рыцарей (в ополченцах)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Knights.power(ctx.game, c) if (c != null and ctx.game.engine.has_feature("knights")) else 0.0
	}, OWNER)
	r.lists.register("knight", {"from": CH, "doc": "Рыцари правителя", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		if c == null or not ctx.game.engine.has_feature("knights"):
			return []
		return Knights.knights_of(ctx.game, c).map(func(k): return {"type": "character", "id": k.id})
	}, OWNER)

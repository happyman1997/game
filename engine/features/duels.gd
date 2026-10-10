class_name Duels
extends EngineFeature
## Поединки. Эффект duel: <скоуп> — бой один на один между персонажем и
## целью. За каждую сторону бьётся она сама или её поборник: лучший рыцарь
## правителя, если он доблестнее хозяина хотя бы на champion_margin.
## Шанс — от разницы доблести бойцов. Победитель получает престиж (и страх,
## если правит), проигравший боец рискует жизнью (death_chance с учётом
## battle_survival) и раной, проигравшая сторона — престижем.
##   defines.duels: { per_point, min_chance, max_chance, champion_margin,
##                    win_prestige, lose_prestige, champion_share, win_dread,
##                    death_chance, wound_chance, loser_opinion }
## Сигнал duel: {winner, loser, winner_fighter, loser_fighter, death}.

const OWNER := "core/duels"


func _init() -> void:
	id = "duels"
	doc = "Поединки: вызов на бой один на один, поборники из рыцарей"


## Кто бьётся за персонажа: он сам или лучший из рыцарей, если тот сильнее.
static func champion_of(game: Game, c: Dictionary) -> Dictionary:
	if c.titles.is_empty() or not game.engine.has_feature("knights"):
		return c
	var own := Stats.skill(game, c, "prowess")
	var margin := int(game.def_num("duels.champion_margin", 2))
	var wound := str(game.def_val("military.wound_trait", "wounded"))
	for k in Knights.knights_of(game, c):
		if k.id == c.id or not Chars.is_alive(k) or k.get("prison") != null or k.traits.has(wound):
			continue
		# рыцари отсортированы по доблести: первый подходящий — лучший
		return k if Stats.skill(game, k, "prowess") >= own + margin else c
	return c


## Шанс стороны a победить сторону b, в процентах.
static func odds(game: Game, a: Dictionary, b: Dictionary) -> int:
	var fa := champion_of(game, a)
	var fb := champion_of(game, b)
	var d := Stats.skill(game, fa, "prowess") - Stats.skill(game, fb, "prowess")
	return clampi(roundi(50.0 + d * game.def_num("duels.per_point", 4)), int(game.def_num("duels.min_chance", 10)), int(game.def_num("duels.max_chance", 90)))


## Поединок; возвращает победившую сторону.
static func duel(game: Game, a: Dictionary, b: Dictionary) -> Dictionary:
	var fa := champion_of(game, a)
	var fb := champion_of(game, b)
	var a_wins := game.rng.next() * 100.0 < odds(game, a, b)
	var win: Dictionary = a if a_wins else b
	var lose: Dictionary = b if a_wins else a
	var fw: Dictionary = fa if a_wins else fb
	var fl: Dictionary = fb if a_wins else fa
	var share := game.def_num("duels.champion_share", 0.5)
	# слава — тому, за кого бились; поборнику — его доля
	win.prestige += game.def_num("duels.win_prestige", 60) * (share if fw.id != win.id else 1.0)
	if fw.id != win.id:
		fw.prestige += game.def_num("duels.win_prestige", 60) * share
	lose.prestige -= game.def_num("duels.lose_prestige", 40) * (share if fl.id != lose.id else 1.0)
	if not win.titles.is_empty() and game.engine.has_feature("politics"):
		Politics.add_dread(game, win, game.def_num("duels.win_dread", 5))
	if game.content.has("opinion_modifiers", str(game.def_val("duels.loser_opinion", "bested_in_duel"))):
		Opinion.add_opinion(game, lose, win, str(game.def_val("duels.loser_opinion", "bested_in_duel")))
	# проигравший боец: смерть (доблестным реже — battle_survival) или рана
	var died := false
	if game.rng.chance(game.def_num("duels.death_chance", 0.1) * Military._death_mult(game, fl)):
		died = true
	elif game.rng.chance(game.def_num("duels.wound_chance", 0.5)):
		Military._wound(game, fl)
	var params := {
		"winner": game.scope_name({"type": "character", "id": fw.id}),
		"loser": game.scope_name({"type": "character", "id": fl.id}),
	}
	for side in [a, b, fa, fb]:
		if game.is_player(side.id):
			var mine: bool = side.id == win.id or side.id == fw.id
			game.message(game.loc.t("msg.duel_died" if died else "msg.duel_result", params), "good" if mine else "bad", {"type": "character", "id": fl.id})
			break
	game.emit("duel", {"winner": win, "loser": lose, "winner_fighter": fw, "loser_fighter": fl, "death": died})
	if died:
		Succession.kill_character(game, fl, "duel", fw.id)
	game.stat_cache.erase(win.id)
	game.stat_cache.erase(lose.id)
	return win


func install(engine: GameEngine) -> void:
	# поединок — сфера доблести: кураж и хандра бойцов
	engine.hooks.on("duel", func(p):
		var g: Game = p.game
		if g.engine.has_feature("momentum"):
			Momentum.record(g, p.winner_fighter, "prowess", true)
			Momentum.record(g, p.loser_fighter, "prowess", false)
	, 0, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	r.effects.register("duel", {"scopes": CH, "doc": "Поединок с персонажем: duel: scope:x (за правителей могут биться поборники)",
		"apply": func(ctx, s, arg):
			var a: Variant = ctx.game.ch(s.id)
			var t: Variant = Interp.resolve_scope(ctx, s, arg)
			var b: Variant = ctx.game.ch(t.id) if t != null and t.type == "character" else null
			if a != null and b != null and a.id != b.id and Chars.is_alive(a) and Chars.is_alive(b):
				Duels.duel(ctx.game, a, b),
		"describe": func(ctx, s, arg):
			var a: Variant = ctx.game.ch(s.id)
			var t: Variant = Interp.resolve_scope(ctx, s, arg)
			var b: Variant = ctx.game.ch(t.id) if t != null and t.type == "character" else null
			if a == null or b == null:
				return null
			var fa := Duels.champion_of(ctx.game, a)
			var fb := Duels.champion_of(ctx.game, b)
			return ctx.game.loc.t("fx.duel", {
				"a": ctx.game.scope_name({"type": "character", "id": fa.id}),
				"b": ctx.game.scope_name({"type": "character", "id": fb.id}),
				"chance": Duels.odds(ctx.game, a, b),
			}),
	}, OWNER)
	r.values.register("duel_odds", {"scopes": CH, "doc": "Шанс победить персонажа в поединке, %: duel_odds(scope:x)", "get": func(ctx, s, arg):
		var a: Variant = ctx.game.ch(s.id)
		var b: Variant = ctx.game.ch(arg.id) if arg is Dictionary and arg.get("type") == "character" else null
		return float(Duels.odds(ctx.game, a, b)) if a != null and b != null else 0.0
	}, OWNER)
	r.triggers.register("has_champion", {"scopes": CH, "doc": "За персонажа в поединке бьётся поборник", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		var has: bool = c != null and Duels.champion_of(ctx.game, c).id != c.id
		return has == ScriptContext.is_yes(arg)
	}, OWNER)

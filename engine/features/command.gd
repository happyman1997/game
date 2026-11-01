class_name Command
extends EngineFeature
## Полководцы: перевес и навыки командования.
##
## Сила полководца в сражении — очки перевеса: военное дело, прибавки
## (commander_advantage, личный пример), навыки и местность. В бою важна
## разница: каждое очко перевеса над вражеским полководцем — сила стороны
## (defines.battle.advantage_effect). Навыки — черты категории commander
## (common/command.yaml, поле command): перевес на своей местности, нападая
## или защищаясь, натиск конницы, залпы, стойкость, погоня, отход, осторожность
## и безрассудство. Полководец обретает навыки в боях (learn — при каком бое) и
## приходит с ними в мир (сильные воители на старте). Армию ведёт назначенный
## полководец (army.commander) или сам хозяин; ИИ отдаёт армию тому, кто
## заметно лучше (defines.command.ai_min_gain).

const OWNER := "core/command"
const SKILL_KEYS := ["charge", "charge_day", "ranged", "volleys", "pursuit", "rearguard", "morale", "steady", "levy_steady", "losses", "luck", "risk"]


func _init() -> void:
	id = "command"
	doc = "Полководцы: перевес в сражении и навыки командования"


static func _n(game: Game, key: String, fallback: float) -> float:
	return game.def_num("command." + key, fallback)


static func stat_mult(game: Game) -> float:
	return _n(game, "stat_mult", 0.5)


## Черты-навыки полководца (у которых есть command).
static func skill_traits(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("command:traits")
	if hit == null:
		hit = game.content.all("traits").filter(func(d): return d.get("category") == "commander")
		game.engine.cache["command:traits"] = hit
	return hit


static func traits_of(game: Game, c: Dictionary) -> Array:
	var out := []
	for t in c.traits:
		var d: Variant = Chars.trait_def(game, t)
		if d != null and d.get("category") == "commander":
			out.append(d)
	return out


## Навыки полководца, сложенные по всем его чертам: {charge, ranged, …}.
static func skills(game: Game, c: Dictionary) -> Dictionary:
	var out := {}
	for d in traits_of(game, c):
		var cmd: Variant = d.get("command")
		if not (cmd is Dictionary):
			continue
		for k in SKILL_KEYS:
			if cmd.has(k):
				out[k] = float(out.get(k, 0.0)) + Data.num(cmd[k])
	return out


## Очки перевеса с разбором: [{key, value, trait?}]. loc — место боя (для
## навыков местности), attacking/defending — роль стороны.
static func advantage_parts(game: Game, c: Dictionary, loc: Variant = null, attacking := false, defending := false) -> Array:
	var parts := []
	var m := Stats.skill(game, c, "martial") * _n(game, "per_martial", 1.0)
	if m != 0.0:
		parts.append({"key": "martial", "value": m})
	var ca := Stats.stat(game, c, "commander_advantage") * stat_mult(game)
	if ca != 0.0:
		parts.append({"key": "commander_advantage", "value": ca})
	var pe := Stats.stat(game, c, "personal_example") * _n(game, "example_mult", 50.0)
	if pe != 0.0:
		parts.append({"key": "personal_example", "value": pe})
	for d in traits_of(game, c):
		var cmd: Variant = d.get("command")
		if not (cmd is Dictionary):
			continue
		var v := Data.num(cmd.get("advantage"))
		if attacking:
			v += Data.num(cmd.get("attacking"))
		if defending:
			v += Data.num(cmd.get("defending"))
		if loc != null and cmd.get("terrain") is Dictionary and game.land().ready():
			for t in cmd.terrain:
				v += game.land().share(str(loc), str(t)) * Data.num(cmd.terrain[t])
		if v != 0.0:
			parts.append({"key": "trait", "trait": str(d.id), "value": v})
	return parts


## Сила полководца вне боя (для выбора, кому вести армию): перевес без
## местности и роли плюс по очку за каждый навык.
static func score(game: Game, c: Dictionary) -> float:
	var s := 0.0
	for p in advantage_parts(game, c):
		s += float(p.value)
	return s + traits_of(game, c).size() * 2.0


## Кому можно отдать армию: хозяин, его рыцари, взрослые придворные и
## прямые вассалы (не в темнице и не во главе другой армии).
static func candidates(game: Game, owner: Dictionary, army_id: Variant = null) -> Array:
	var busy := {}
	for a in game.state.armies.values():
		if a.id != army_id and a.get("commander") != null:
			busy[a.commander] = true
	var out := []
	var seen := {}
	var pool: Array = [owner] + game.courtiers_of(owner.id) + game.vassals_of(owner.id)
	if game.engine.has_feature("knights"):
		pool = Knights.knights_of(game, owner) + pool
	for x in pool:
		if x == null or seen.has(x.id) or busy.has(x.id):
			continue
		seen[x.id] = true
		if Chars.is_alive(x) and Chars.is_adult(game, x) and x.get("prison") == null:
			out.append(x)
	return out


## Лучший полководец для армии хозяина (ИИ).
static func best_for(game: Game, owner: Dictionary, army_id: Variant = null) -> Dictionary:
	var best: Dictionary = owner
	var own := score(game, owner)
	var top := own + _n(game, "ai_min_gain", 3.0)
	for x in candidates(game, owner, army_id):
		var s := score(game, x)
		if s > top:
			top = s
			best = x
	return best


## Назначить полководца армии (null — ведёт сам хозяин).
static func appoint(game: Game, army: Dictionary, cid: Variant) -> bool:
	if cid == null or cid == army.owner:
		army.commander = null
		game.notify("army")
		return true
	var owner: Variant = game.ch(army.owner)
	if owner == null or not candidates(game, owner, army.id).any(func(x): return x.id == cid):
		return false
	army.commander = cid
	game.emit("army.commander", {"army": army, "commander": cid})
	game.notify("army")
	return true


## Что делает навык в бою — строки для подсказки (BBCode).
static func describe(game: Game, d: Variant) -> String:
	if not (d is Dictionary) or not (d.get("command") is Dictionary):
		return BB.modifiers(game, d.get("modifiers")) if d is Dictionary else ""
	var cmd: Dictionary = d.command
	var out := PackedStringArray()
	for k in cmd:
		var v: Variant = cmd[k]
		if k == "terrain" and v is Dictionary:
			for t in v:
				out.append(game.loc.t("command.fx.terrain", {"terrain": game.name_of("terrains", t), "n": K.signed(Data.num(v[t]))}))
		else:
			var n := Data.num(v)
			var pct := roundi(absf(n) * 100.0)
			out.append(game.loc.t("command.fx." + str(k), {"n": K.signed(n), "pct": pct, "abs": roundi(absf(n))}))
	var mods := BB.modifiers(game, d.get("modifiers"))
	if mods != "":
		out.append(mods)
	return "\n".join(out)


## Навыки, которые бой мог бы дать стороне side (по полю learn черт).
static func lessons(game: Game, report: Dictionary, loc: String, side: int) -> Array:
	var won := int(report.winner) == side
	var start := maxf(1.0, float(report.start[side]))
	var lost_frac := float(report.lost[side]) / start
	var ev_of := func(kind: String) -> Array: return Data.as_array(report.events).filter(func(e): return e.kind == kind and int(e.side) == side)
	var defending: bool = report.sides[side].get("defending", false) if side < report.sides.size() else false
	var share_min := _n(game, "learn_terrain_share", 0.4)
	var out := []
	for d in skill_traits(game):
		var l: Variant = d.get("learn")
		if not (l is Dictionary):
			continue
		var ok := true
		if l.get("terrain") != null:
			ok = ok and won and game.land().ready() and game.land().share(loc, str(l.terrain)) >= share_min
		if l.get("charge", false):
			ok = ok and won and not ev_of.call("charge").is_empty()
		if l.get("volley", false):
			ok = ok and not ev_of.call("skirmish").is_empty()
		if l.get("defending", false):
			ok = ok and won and defending
		if l.get("attacking", false):
			ok = ok and won and not defending and int(report.days) >= 2
		if l.get("pursuit", false):
			var pur: Array = ev_of.call("pursuit")
			ok = ok and won and not pur.is_empty() and Data.num(pur[0].get("n")) >= 0.1 * float(report.start[1 - side])
		if l.get("rearguard", false):
			ok = ok and not won and lost_frac < 0.35
		if l.get("morale", false):
			ok = ok and won and float(report.morale[side]) >= 40.0
		if l.get("cautious", false):
			ok = ok and won and lost_frac < 0.1
		if l.get("reckless", false):
			ok = ok and won and lost_frac > 0.25
		if ok:
			out.append(str(d.id))
	return out


## После боя полководцы могут обрести навык — по тому, как шёл бой.
static func learn(game: Game, report: Dictionary, loc: String) -> void:
	var mx := int(_n(game, "max_traits", 3))
	for side in 2:
		var c: Variant = game.ch(report.sides[side].get("commander")) if side < report.sides.size() else null
		if c == null or c.death != null:
			continue
		var have := traits_of(game, c)
		if have.size() >= mx:
			continue
		var opts := lessons(game, report, loc, side).filter(func(t): return not c.traits.has(t))
		if opts.is_empty():
			continue
		var won := int(report.winner) == side
		var chance := (_n(game, "learn_chance_win", 0.18) if won else _n(game, "learn_chance_lose", 0.06)) \
			* (1.0 + Stats.skill(game, c, "martial") * _n(game, "learn_per_martial", 0.05))
		if not game.rng.chance(minf(0.9, chance)):
			continue
		var t: String = game.rng.pick(opts)
		if Chars.add_trait(game, c, t):
			report.events.append({"day": int(report.days), "kind": "learned", "side": side, "a": c.id, "b": t})
			var owner: Variant = report.sides[side].owners[0] if not report.sides[side].owners.is_empty() else null
			if game.is_player(c.id) or game.is_player(owner):
				game.message(game.loc.t("msg.command_learned", {"who": game.scope_name({"type": "character", "id": c.id}), "skill": game.name_of("traits", t)}),
					"good", {"type": "character", "id": c.id}, [c.id])
			game.emit("command.learned", {"character": c, "trait": t})


## На старте сильные воители уже бывали в боях: по одному-два навыка.
## Свой генератор (от состояния общего, не сдвигая его): навыки не меняют
## остальной ход мира от того же зерна.
static func seed_start(game: Game) -> void:
	var th: Array = game.def_val("command.start_martial", [12, 17])
	var pool := skill_traits(game).filter(func(d): return d.get("learn") is Dictionary)
	if pool.is_empty() or th.is_empty():
		return
	var rng := Rng.from_seed("command:%d" % int(game.rng.state.get("s", 0)))
	for c in game.living():
		if not Chars.is_adult(game, c):
			continue
		var m := Stats.skill(game, c, "martial")
		var n := 0
		for x in th:
			if m >= Data.num(x):
				n += 1
		for i in n:
			var opts := pool.filter(func(d): return not c.traits.has(d.id))
			if opts.is_empty():
				break
			Chars.add_trait(game, c, str(rng.pick(opts).id))


func install(engine: GameEngine) -> void:
	engine.hooks.on("game.setup", func(p): Command.seed_start(p.game), 0, OWNER)
	# ИИ отдаёт армию тому, кто ведёт её заметно лучше
	engine.hooks.on("army.raised", func(p):
		var game: Game = p.game
		var a: Dictionary = p.army
		if not game.ai_controls(a.owner):
			return
		var owner: Variant = game.ch(a.owner)
		if owner == null:
			return
		var best := Command.best_for(game, owner, a.id)
		if best.id != owner.id:
			a.commander = best.id
	, 0, OWNER)
	engine.hooks.on("battle", func(p):
		if p.get("report") is Dictionary:
			Command.learn(p.game, p.report, str(p.location))
	, 10, OWNER)
	engine.content_validators.register("command_traits", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("traits"):
			if d.get("category") != "commander":
				continue
			var cmd: Variant = d.get("command")
			if cmd != null and not (cmd is Dictionary):
				v.issue("traits/%s: command — словарь" % d.id)
			elif cmd is Dictionary:
				for k in cmd:
					if not (str(k) in SKILL_KEYS or str(k) in ["advantage", "attacking", "defending", "terrain"]):
						v.issue("traits/%s: command.%s — нет такого навыка" % [d.id, k])
	, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	r.values.register("command_advantage", {"scopes": ["character"], "doc": "Очки перевеса полководца (без местности): военное дело, прибавки, навыки",
		"get": func(ctx, s, _a):
			var c: Variant = ctx.game.ch(s.id)
			if c == null:
				return 0.0
			var v := 0.0
			for p in Command.advantage_parts(ctx.game, c):
				v += float(p.value)
			return v,
	}, OWNER)
	r.values.register("num_command_skills", {"scopes": ["character"], "doc": "Сколько у персонажа навыков полководца",
		"get": func(ctx, s, _a):
			var c: Variant = ctx.game.ch(s.id)
			return float(Command.traits_of(ctx.game, c).size()) if c != null else 0.0,
	}, OWNER)

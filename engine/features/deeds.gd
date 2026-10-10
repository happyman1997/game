class_name Deeds
extends EngineFeature
## Деяния: летопись того, что персонаж совершил за жизнь — выигранные битвы,
## постройки, казни, пиры, поединки. Из неё растут прозвища (nicknames) и
## цели испытаний архетипов. Сами по себе деяния ничего не дают.
##
## Данные:
##   deeds: { <id>: { icon, order, signal | decisions | interactions | schemes | events } }
##     signal — встроенный источник: battle_won, battle_lost, siege_won,
##       war_won, war_lost, duel_won, duel_lost, building, conversion,
##       scheme_success, discord, secret_exposed, revolt_led, law_changed,
##       trial_completed;
##     decisions — принятые решения, interactions — принятые взаимодействия
##       (у действующего лица), schemes — удачные интриги (у заговорщика),
##       events — события, через которые прошёл персонаж.
##     ai_hint: { decisions, interactions } — что помогает добиться деяния
##       (ИИ на испытании охотнее это делает), если сам источник — сигнал.
##   nicknames: { <id>: { deed, count, priority } } — прозвище (ключ
##     локализации nick.<id>, женское — nick.<id>_f, если есть) приходит,
##     когда счётчик деяния дорос до count; новое заменяет старое, только если
##     priority выше. Прозвища из истории (поле nickname персонажа) не
##     заменяются. Прозвище — только имя: никаких эффектов.
## Состояние: c.vars.deeds = {деяние: число}, c.vars.nick_priority.
## Скрипт: эффект add_deed, значения deeds_<id>, условие has_nickname.
## Хуки: deed — {character, deed, count}; nickname.gained — {character, nickname}.

const OWNER := "core/deeds"
const SIGNALS := ["battle_won", "battle_lost", "siege_won", "war_won", "war_lost", "duel_won", "duel_lost",
	"building", "conversion", "scheme_success", "discord", "secret_exposed", "revolt_led", "law_changed", "trial_completed"]


func _init() -> void:
	id = "deeds"
	doc = "Деяния: летопись поступков персонажа и прозвища, которые из неё растут"


static func count(c: Variant, deed: String) -> int:
	if not (c is Dictionary):
		return 0
	var d: Variant = c.vars.get("deeds")
	return int(d.get(deed, 0)) if d is Dictionary else 0


## Индекс источников: {"signal:<s>" | "decision:<id>" | "interaction:<id>" | "scheme:<id>": [деяния]}.
static func _index(game: Game) -> Dictionary:
	var hit: Variant = game.engine.cache.get("deeds:index")
	if hit != null:
		return hit
	var m := {}
	var put := func(key: String, deed: String) -> void:
		if not m.has(key):
			m[key] = []
		m[key].append(deed)
	for d in game.content.all("deeds"):
		if d.get("signal") != null:
			put.call("signal:" + str(d.signal), d.id)
		for k in ["decisions", "interactions", "schemes", "events"]:
			for x in Data.as_array(d.get(k)):
				put.call(k.trim_suffix("s") + ":" + str(x), d.id)
		var hint: Variant = d.get("ai_hint")
		if hint is Dictionary:
			for k in ["decisions", "interactions"]:
				for x in Data.as_array(hint.get(k)):
					put.call("hint:" + k.trim_suffix("s") + ":" + str(x), d.id)
	game.engine.cache["deeds:index"] = m
	return m


## Записать деяние персонажу.
static func record(game: Game, c: Variant, deed: String, n: int = 1) -> void:
	if not (c is Dictionary) or c.death != null or n == 0 or not game.content.has("deeds", deed):
		return
	var d: Dictionary = c.vars.get("deeds", {})
	d[deed] = int(d.get(deed, 0)) + n
	c.vars["deeds"] = d
	game.emit("deed", {"character": c, "deed": deed, "count": d[deed]})
	_check_nicknames(game, c, deed)


## Все деяния, у которых этот источник.
static func on_source(game: Game, key: String, c: Variant) -> void:
	for deed in _index(game).get(key, []):
		record(game, c, deed)


# ------------------------------------------------------------ прозвища

static func _nick_defs(game: Game, deed: String) -> Array:
	var key := "deeds:nicks:" + deed
	var hit: Variant = game.engine.cache.get(key)
	if hit == null:
		hit = game.content.all("nicknames").filter(func(n): return str(n.get("deed")) == deed)
		game.engine.cache[key] = hit
	return hit


static func _check_nicknames(game: Game, c: Dictionary, deed: String) -> void:
	var have := count(c, deed)
	var cur := Data.num(c.vars.get("nick_priority"), -1.0)
	# прозвище из истории — навсегда
	if c.get("nickname") != null and c.vars.get("nick_priority") == null:
		return
	var best: Variant = null
	for n in _nick_defs(game, deed):
		if have >= int(Data.num(n.get("count"), 1)) and Data.num(n.get("priority"), 0) > cur:
			if best == null or Data.num(n.get("priority"), 0) > Data.num(best.get("priority"), 0):
				best = n
	if best != null:
		give_nickname(game, c, best.id)


static func give_nickname(game: Game, c: Dictionary, nick: String) -> void:
	var n: Variant = game.content.get_def("nicknames", nick)
	if n == null:
		return
	var key := "nick." + nick
	if c.female and game.loc.raw("nick." + nick + "_f") != null:
		key += "_f"
	c.nickname = key
	c.vars["nick_priority"] = Data.num(n.get("priority"), 0)
	c.vars["nick_id"] = nick
	if game.is_player(c.id) or game.is_player(str(c.get("liege"))):
		game.message(game.loc.t("msg.nickname_gained", {"who": game.scope_name({"type": "character", "id": c.id}, "first_name"), "nick": game.loc.resolve(key)}), "good" if game.is_player(c.id) else "info", {"type": "character", "id": c.id})
	game.emit("nickname.gained", {"character": c, "nickname": nick})
	game.notify("character")


## Ближайшее прозвище для подсказки: [{nickname, deed, have, need}], по одному на деяние.
static func next_nicknames(game: Game, c: Dictionary) -> Array:
	var out := []
	var cur := Data.num(c.vars.get("nick_priority"), -1.0)
	var historic: bool = c.get("nickname") != null and c.vars.get("nick_priority") == null
	if historic:
		return out
	var by_deed := {}
	for n in game.content.all("nicknames"):
		var deed := str(n.get("deed"))
		var need := int(Data.num(n.get("count"), 1))
		if Data.num(n.get("priority"), 0) <= cur or count(c, deed) >= need:
			continue
		if not by_deed.has(deed) or need < by_deed[deed].need:
			by_deed[deed] = {"nickname": n.id, "deed": deed, "have": count(c, deed), "need": need}
	for k in by_deed:
		out.append(by_deed[k])
	out.sort_custom(func(a, b): return float(a.have) / a.need > float(b.have) / b.need)
	return out


func install(engine: GameEngine) -> void:
	var H := engine.hooks
	var sig := func(g: Game, name: String, c: Variant) -> void:
		if c is String:
			c = g.ch(c)
		Deeds.on_source(g, "signal:" + name, c)
	H.on("battle", func(p):
		sig.call(p.game, "battle_won", p.winner)
		sig.call(p.game, "battle_lost", p.loser)
	, 0, OWNER)
	H.on("siege.won", func(p): sig.call(p.game, "siege_won", p.army.owner), 0, OWNER)
	H.on("war.ended", func(p):
		var w: Dictionary = p.war
		if p.outcome == "victory":
			sig.call(p.game, "war_won", w.attacker)
			sig.call(p.game, "war_lost", w.defender)
		elif p.outcome == "defeat":
			sig.call(p.game, "war_won", w.defender)
			sig.call(p.game, "war_lost", w.attacker)
	, 0, OWNER)
	H.on("duel", func(p):
		sig.call(p.game, "duel_won", p.winner)
		sig.call(p.game, "duel_lost", p.loser)
	, 0, OWNER)
	H.on("building.completed", func(p):
		if p.get("by") != null:
			sig.call(p.game, "building", str(p.by))
	, 0, OWNER)
	H.on("lands.converted", func(p): sig.call(p.game, "conversion", p.holder), 0, OWNER)
	H.on("scheme.ended", func(p):
		if p.success:
			sig.call(p.game, "scheme_success", p.scheme.owner)
			Deeds.on_source(p.game, "scheme:" + str(p.scheme.type), p.game.ch(p.scheme.owner))
	, 0, OWNER)
	H.on("politics.discord", func(p): sig.call(p.game, "discord", p.actor), 0, OWNER)
	H.on("secret.exposed", func(p):
		if p.get("exposer") is Dictionary:
			sig.call(p.game, "secret_exposed", p.exposer)
	, 0, OWNER)
	H.on("faction.ultimatum", func(p):
		if not p.accepted and not p.get("negotiated", false):
			sig.call(p.game, "revolt_led", p.faction.leader)
	, 0, OWNER)
	H.on("trial.completed", func(p): sig.call(p.game, "trial_completed", p.character), 0, OWNER)
	H.on("law.changed", func(p): sig.call(p.game, "law_changed", p.character), 0, OWNER)
	H.on("event.fired", func(p):
		if p.target.type == "character":
			Deeds.on_source(p.game, "event:" + str(p.event), p.game.ch(p.target.id))
	, 0, OWNER)
	H.on("decision.taken", func(p): Deeds.on_source(p.game, "decision:" + str(p.decision), p.game.ch(p.character)), 0, OWNER)
	H.on("interaction", func(p):
		if p.accepted:
			Deeds.on_source(p.game, "interaction:" + str(p.interaction), p.game.ch(p.actor))
	, 0, OWNER)
	engine.content_validators.register("deeds", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("deeds"):
			if d.get("signal") != null and not SIGNALS.has(str(d.signal)):
				v.issue("deeds/%s: неизвестный signal \"%s\" (есть: %s)" % [d.id, d.signal, ", ".join(SIGNALS)])
			for x in Data.as_array(d.get("decisions")):
				v.ref("decisions", x, "deeds/" + d.id)
			for x in Data.as_array(d.get("interactions")):
				v.ref("interactions", x, "deeds/" + d.id)
			for x in Data.as_array(d.get("schemes")):
				v.ref("schemes", x, "deeds/" + d.id)
			for x in Data.as_array(d.get("events")):
				v.ref("events", x, "deeds/" + d.id)
			var hint: Variant = d.get("ai_hint")
			if hint is Dictionary:
				for x in Data.as_array(hint.get("decisions")):
					v.ref("decisions", x, "deeds/%s ai_hint" % d.id)
				for x in Data.as_array(hint.get("interactions")):
					v.ref("interactions", x, "deeds/%s ai_hint" % d.id)
		for n in e.content.all("nicknames"):
			v.ref("deeds", n.get("deed"), "nicknames/" + n.id)
	)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	for d in engine.content.all("deeds"):
		var did: String = d.id
		r.values.register("deeds_" + did, {"scopes": CH, "doc": "Деяния: " + did, "get": func(ctx, s, _a):
			return float(Deeds.count(ctx.game.ch(s.id), did))
		}, OWNER)
	r.effects.register("add_deed", {"scopes": CH, "doc": "Записать деяние: add_deed: <id> или { id, value }",
		"apply": func(ctx, s, arg):
			var c: Variant = ctx.game.ch(s.id)
			var did := str(arg.get("id")) if arg is Dictionary else str(arg)
			var n := roundi(Interp.eval_value(ctx, s, arg.get("value", 1))) if arg is Dictionary else 1
			Deeds.record(ctx.game, c, did, n),
		"describe": func(_ctx, _s, _arg): return null,
	}, OWNER)
	r.triggers.register("has_nickname", {"scopes": CH, "doc": "Есть прозвище (yes/no или id прозвища из nicknames)", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c == null:
			return false
		if arg is String and arg != "yes" and arg != "no":
			return str(c.vars.get("nick_id")) == arg
		return (c.get("nickname") != null) == ScriptContext.is_yes(arg)
	}, OWNER)

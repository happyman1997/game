class_name Secrets
extends EngineFeature
## Секреты. Персонажи совершают постыдное (убийство, измена, казнокрадство),
## и это становится секретом. Секрет могут узнать другие — тайный советник,
## родня, случайные свидетели. Знающий может шантажировать владельца секрета
## (получить крюк) или разоблачить его (эффект on_expose, секрет исчезает).
##
## Данные:
##   secret_types: { icon, hook: strong|weak, severity, discovered_by, discovery_chance, on_expose }
##     discovered_by — список (spouse, close_family, liege…), чьи члены могут
##     случайно узнать секрет; discovery_chance — шанс в месяц (в %).
##     on_expose: root — владелец, scope:exposer, scope:secret_target.
##   defines.secrets: { max_known_per_secret }
## Состояние: c.secrets = [{id, type, target, known: [id], since}].

const OWNER := "core/secrets"
const INDEX_KEY := "secrets:index"


func _init() -> void:
	id = "secrets"
	doc = "Секреты: раскрытие, шантаж (крюки) и разоблачение"


static func secrets_of(c: Variant) -> Array:
	return c.secrets if (c != null and c.get("secrets") != null) else []


static func known_secrets_of(_game: Game, owner: Dictionary, knower: String) -> Array:
	return secrets_of(owner).filter(func(s): return s.known.has(knower))


## Персонажи, чьи секреты известны knower. Индекс «знающий → владельцы» на
## месяц; новое знание (add_secret, learn) сбрасывает его, забытое и
## раскрытое отсеивается проверкой.
static func owners_known_by(game: Game, knower: String) -> Array:
	var idx: Dictionary = game.cached_monthly(INDEX_KEY, func():
		var m := {}
		for o in game.living():
			for s in secrets_of(o):
				for k in s.known:
					if not m.has(k):
						m[k] = {}
					m[k][o.id] = o
		return m)
	var out := []
	for o in idx.get(knower, {}).values():
		if o.death == null and not known_secrets_of(game, o, knower).is_empty():
			out.append(o)
	return out


static func add_secret(game: Game, owner: Dictionary, type: String, target: Variant = null, known_by: Array = []) -> Variant:
	if not game.content.has("secret_types", type):
		game.script_error("Нет типа секрета \"%s\"" % type)
		return null
	for dup in secrets_of(owner):
		if dup.type == type and dup.get("target") == target:
			for k in known_by:
				if not dup.known.has(k) and k != owner.id:
					dup.known.append(k)
			game.month_cache.erase(INDEX_KEY)
			return dup
	var s := {"id": game.new_id("sec"), "type": type, "target": target, "known": known_by.filter(func(k): return k != owner.id), "since": game.date}
	if owner.get("secrets") == null:
		owner["secrets"] = []
	owner.secrets.append(s)
	game.month_cache.erase(INDEX_KEY)
	game.emit("secret.added", {"owner": owner, "secret": s})
	return s


## Персонаж узнаёт секрет.
static func learn(game: Game, knower: Dictionary, owner: Dictionary, s: Dictionary) -> bool:
	if knower.id == owner.id or s.known.has(knower.id):
		return false
	s.known.append(knower.id)
	game.month_cache.erase(INDEX_KEY)
	# знание тайны меняет отношение (скрытые черты влияют на мнение)
	game.stat_cache.erase("op:%s>%s" % [knower.id, owner.id])
	var mx := int(game.def_num("secrets.max_known_per_secret", 12))
	if s.known.size() > mx:
		var alive: Array = s.known.filter(func(id): return game.is_alive(id))
		s.known = alive.slice(maxi(0, alive.size() - mx))
	game.emit("secret.learned", {"knower": knower, "owner": owner, "secret": s})
	if game.is_player(knower.id):
		game.message(game.loc.t("msg.secret_learned", {"who": game.scope_name({"type": "character", "id": owner.id}), "secret": game.name_of("secret_types", s.type)}), "good", {"type": "character", "id": owner.id})
	if game.is_player(owner.id):
		game.message(game.loc.t("msg.secret_known_by", {"who": game.scope_name({"type": "character", "id": knower.id}), "secret": game.name_of("secret_types", s.type)}), "bad", {"type": "character", "id": knower.id})
	return true


static func _def(game: Game, s: Dictionary) -> Variant:
	return game.content.get_def("secret_types", s.type)


static func _severity(game: Game, s: Dictionary) -> float:
	var d: Variant = _def(game, s)
	return Data.num(d.get("severity")) if d != null else 0.0


## Самый тяжёлый секрет owner, известный knower.
static func worst_known(game: Game, owner: Dictionary, knower: String) -> Variant:
	var known := known_secrets_of(game, owner, knower)
	return Data.max_by(known, func(s): return _severity(game, s))


static func blackmail(game: Game, knower: Dictionary, owner: Dictionary, s: Variant = null) -> bool:
	var sec: Variant = s if s != null else worst_known(game, owner, knower.id)
	if sec == null:
		return false
	var d: Variant = _def(game, sec)
	Leverage.add_hook(game, knower, owner, d != null and d.get("hook") == "strong")
	game.emit("secret.blackmailed", {"knower": knower, "owner": owner, "secret": sec})
	return true


static func expose(game: Game, exposer: Variant, owner: Dictionary, s: Variant = null) -> bool:
	var sec: Variant = s
	if sec == null:
		if exposer != null:
			sec = worst_known(game, owner, exposer.id)
		elif not secrets_of(owner).is_empty():
			sec = secrets_of(owner)[0]
	if sec == null:
		return false
	owner.secrets = secrets_of(owner).filter(func(x): return x.id != sec.id)
	var def: Variant = _def(game, sec)
	var scopes := {"secret_owner": {"type": "character", "id": owner.id}}
	if exposer != null:
		scopes["exposer"] = {"type": "character", "id": exposer.id}
	if sec.get("target") != null and game.ch(sec.target) != null:
		scopes["secret_target"] = {"type": "character", "id": sec.target}
	var ctx := ScriptContext.make(game, {"type": "character", "id": owner.id}, scopes)
	Interp.run_effect(ctx, ctx.root, def.get("on_expose") if def != null else null)
	game.message(game.loc.t("msg.secret_exposed", {"who": game.scope_name({"type": "character", "id": owner.id}), "secret": game.name_of("secret_types", sec.type), "by": game.scope_name({"type": "character", "id": exposer.id}) if exposer != null else "—"}),
		"event", {"type": "character", "id": owner.id}, [owner.id, exposer.id if exposer != null else null, owner.liege, sec.get("target")])
	game.emit("secret.exposed", {"exposer": exposer, "owner": owner, "secret": sec})
	return true


## Узнать случайный секрет кого-то из державы (или двора) персонажа.
static func discover(game: Game, c: Dictionary) -> bool:
	var top := Titles.top_liege(game, c)
	var pool := {}
	for x in Titles.realm_members(game, top) + game.courtiers_of(c.id) + game.vassals_of(c.id):
		pool[x.id] = x
	var cands := []
	for oid in pool:
		var o: Dictionary = pool[oid]
		if o.id == c.id or not Chars.is_alive(o):
			continue
		for s in secrets_of(o):
			if not s.known.has(c.id):
				cands.append([o, s])
	# и секреты придворных вассалов
	for o in game.living():
		if not o.titles.is_empty() or secrets_of(o).is_empty() or o.id == c.id or pool.has(o.id):
			continue
		if o.liege != null and pool.has(o.liege):
			for s in o.secrets:
				if not s.known.has(c.id):
					cands.append([o, s])
	var pick: Variant = game.rng.pick(cands)
	if pick == null:
		return false
	return learn(game, c, pick[0], pick[1])


static func monthly(game: Game) -> void:
	for owner in game.living():
		if secrets_of(owner).is_empty():
			continue
		for s in owner.secrets.duplicate():
			# секреты об умерших сообщниках не исчезают, а знающие умирают
			s.known = s.known.filter(func(id): return game.is_alive(id))
			var def: Variant = _def(game, s)
			if def == null or def.get("discovered_by") == null:
				continue
			var scopes := {"secret_target": {"type": "character", "id": s.target}} if s.get("target") != null else {}
			var ctx := ScriptContext.make(game, {"type": "character", "id": owner.id}, scopes)
			var chance := Interp.eval_value(ctx, ctx.root, def.get("discovery_chance", 1))
			if game.rng.next() * 100.0 >= chance:
				continue
			var lname: Variant = game.rng.pick(Data.as_array(def.discovered_by))
			var lst: Variant = game.engine.scripting.lists.get_item(str(lname)) if lname != null else null
			if lst == null:
				continue
			var refs: Array = lst.list.call(ctx, ctx.root).filter(func(r): return r.type == "character" and r.id != owner.id and not s.known.has(r.id))
			var who: Variant = game.rng.pick(refs)
			var knower: Variant = game.ch(who.id) if who != null else null
			if knower != null and Chars.is_alive(knower):
				learn(game, knower, owner, s)


func install(engine: GameEngine) -> void:
	engine.systems.register("secrets", {"id": "secrets", "order": 42, "on_month": Secrets.monthly}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	var target := func(ctx: ScriptContext, s: Variant, arg: Variant) -> Variant:
		return ch.call(ctx, Interp.resolve_scope(ctx, s, arg))
	r.triggers.register("has_secret", {"scopes": CH, "doc": "Есть секрет (yes или тип)", "eval": func(ctx, s, arg):
		var secs := Secrets.secrets_of(ch.call(ctx, s))
		if (arg is String and arg == "no") or (arg is bool and not arg):
			return secs.is_empty()
		if arg == null or ScriptContext.is_yes(arg):
			return not secs.is_empty()
		var types := Data.as_array(arg)
		return secs.any(func(x): return types.has(x.type))
	}, OWNER)
	r.triggers.register("knows_secret_of", {"scopes": CH, "doc": "Знает какой-то секрет персонажа",
		"eval": func(ctx, s, arg):
			var o: Variant = target.call(ctx, s, arg)
			return o != null and not Secrets.known_secrets_of(ctx.game, o, s.id).is_empty(),
		"describe": func(ctx, _s, _arg): return ctx.game.loc.t("tr.knows_secret_of"),
	}, OWNER)
	r.values.register("num_secrets", {"scopes": CH, "doc": "Число секретов персонажа", "get": func(ctx, s, _a): return float(Secrets.secrets_of(ch.call(ctx, s)).size())}, OWNER)
	r.values.register("num_known_secrets", {"scopes": CH, "doc": "Сколько чужих секретов знает персонаж", "get": func(ctx, s, _a):
		var n := 0
		for o in Secrets.owners_known_by(ctx.game, s.id):
			n += Secrets.known_secrets_of(ctx.game, o, s.id).size()
		return float(n)
	}, OWNER)
	r.lists.register("known_secret_owner", {"from": CH, "doc": "Персонажи, чьи секреты известны этому персонажу", "list": func(ctx, s):
		return Secrets.owners_known_by(ctx.game, s.id).map(func(o): return {"type": "character", "id": o.id})
	}, OWNER)
	r.effects.register("add_secret", {"scopes": CH, "doc": "Персонаж получает секрет: add_secret: тип или { type, target, known_by }",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c == null:
				return
			var type: Variant = arg if not (arg is Dictionary) else arg.get("type")
			var t: Variant = target.call(ctx, s, arg.target) if (arg is Dictionary and arg.get("target") != null) else null
			var known := []
			if arg is Dictionary:
				for p in Data.as_array(arg.get("known_by")):
					var k: Variant = target.call(ctx, s, p)
					if k != null:
						known.append(k.id)
			Secrets.add_secret(ctx.game, c, str(type), t.id if t != null else null, known),
		"describe": func(_ctx, _s, _arg): return null,
	}, OWNER)
	r.effects.register("discover_secret", {"scopes": CH, "doc": "Узнать случайный секрет кого-то из своей державы",
		"apply": func(ctx, s, _arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				Secrets.discover(ctx.game, c),
		"describe": func(ctx, _s, _arg): return ctx.game.loc.t("fx.discover_secret"),
	}, OWNER)
	r.effects.register("blackmail", {"scopes": CH, "doc": "Шантажировать персонажа его самым тяжёлым известным секретом (получить крюк)",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var o: Variant = target.call(ctx, s, arg)
			if c != null and o != null:
				Secrets.blackmail(ctx.game, c, o),
		"describe": func(ctx, s, arg):
			var o: Variant = target.call(ctx, s, arg)
			var sec: Variant = Secrets.worst_known(ctx.game, o, s.id) if o != null else null
			if sec == null:
				return null
			var d: Variant = ctx.game.content.get_def("secret_types", sec.type)
			var strong: bool = d != null and d.get("hook") == "strong"
			return ctx.game.loc.t("fx.add_strong_hook" if strong else "fx.add_hook", {"value": ctx.game.scope_name({"type": "character", "id": o.id})}),
	}, OWNER)
	r.effects.register("expose_secret", {"scopes": CH, "doc": "Разоблачить самый тяжёлый известный секрет персонажа",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var o: Variant = target.call(ctx, s, arg)
			if c != null and o != null:
				Secrets.expose(ctx.game, c, o),
		"describe": func(ctx, s, arg):
			var o: Variant = target.call(ctx, s, arg)
			var sec: Variant = Secrets.worst_known(ctx.game, o, s.id) if o != null else null
			if sec == null:
				return null
			return ctx.game.loc.t("fx.expose_secret", {"who": ctx.game.scope_name({"type": "character", "id": o.id}), "secret": ctx.game.name_of("secret_types", sec.type)}),
	}, OWNER)
	engine.content_validators.register("secrets", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("secret_types"):
			for l in Data.as_array(d.get("discovered_by")):
				if not e.scripting.lists.has(str(l)):
					v.issue("secret_types/%s: нет списка \"%s\"" % [d.id, l])
			v.effect(d.get("on_expose"), "secret_types/%s on_expose" % d.id)
	, OWNER)

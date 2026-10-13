class_name Karma
extends EngineFeature
## «Свет и Пепел» — карма персонажа (−max…max). Она копится от деяний
## (эффект add_karma в данных: казнь без вины, убийство, шантаж, ложь —
## пепел; милостыня, справедливый суд, милость к пленнику, паломничество —
## свет) и сама не тает: пепел снимают только исповедь и паломничество к
## Пепелищу (эффект cleanse_ash). Совестливые (conscience_traits, кроме
## носителей conscience_immune) мучаются от греха — стресс за очко пепла.
##
## Данные:
##   karma_tiers: { <id>: { min, icon, modifiers, zealot_opinion } } —
##     ступени по порогу min (нижняя — с самым малым): modifiers — носителю,
##     zealot_opinion — мнение ревнителей веры (zealot_traits) о нём.
##   defines.karma: { max, conscience_traits, conscience_immune,
##     conscience_stress, zealot_traits, log_size, known_by,
##     trait_seed, trait_drift, drift_max }
##   Нрав души: в начале игры карма взрослых складывается из trait_seed
##   их черт (с небольшим разбросом), а каждый год черты понемногу двигают
##   её (trait_drift — повседневные мелкие дела; не больше drift_max за год,
##   без записи в Книге деяний).
##   Название деяния в «Книге деяний» — karma_deed.<deed>.
##   on_actions: on_karma_tier_up / on_karma_tier_down (root — персонаж).
## Видимость: сам персонаж знает свою карму точно, другие видят лишь
## ступень; точное число видят и носители черт defines.karma.known_by.
## Состояние: c.vars.karma, c.vars.karma_tier (id ступени, кроме нейтральной
## по умолчанию), c.vars.karma_log = [[дата, изменение, деяние], ...].

const OWNER := "core/karma"


func _init() -> void:
	id = "karma"
	doc = "Свет и Пепел: карма от деяний, ступени, Книга деяний"


static func value(c: Variant) -> float:
	return Data.num(c.vars.get("karma")) if c is Dictionary else 0.0


static func max_value(game: Game) -> float:
	return game.def_num("karma.max", 100)


# ------------------------------------------------------------ ступени

static func tiers(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("karma:tiers")
	if hit == null:
		hit = game.content.all("karma_tiers").duplicate()
		Data.sort_by(hit, func(x): return Data.num(x.get("min"), -INF))
		game.engine.cache["karma:tiers"] = hit
	return hit


static func level_for(game: Game, v: float) -> int:
	var lvl := 0
	var ts := tiers(game)
	for i in ts.size():
		if ts[i].get("min") == null or v >= Data.num(ts[i].min):
			lvl = i
	return lvl if not ts.is_empty() else -1


static func tier_level(game: Game, c: Dictionary) -> int:
	return level_for(game, value(c))


static func tier_at(game: Game, lvl: int) -> Variant:
	var ts := tiers(game)
	return ts[lvl] if lvl >= 0 and lvl < ts.size() else null


static func tier_of(game: Game, c: Dictionary) -> Variant:
	return tier_at(game, tier_level(game, c))


static func level_of_id(game: Game, tid: String) -> int:
	var ts := tiers(game)
	for i in ts.size():
		if ts[i].id == tid:
			return i
	return -1


## Ступень, на которой стоит «как все» (ей принадлежит ноль).
static func neutral_level(game: Game) -> int:
	return level_for(game, 0.0)


## Видит ли viewer точную карму c (а не только ступень).
static func knows_exact(game: Game, c: Dictionary, viewer: Variant) -> bool:
	if viewer == null:
		return false
	if viewer.id == c.id:
		return true
	for t in game.def_val("karma.known_by", []):
		if viewer.traits.has(t):
			return true
	return false


# ------------------------------------------------------------ изменение

## Изменить карму. deed — ключ деяния для «Книги деяний» (karma_deed.<deed>);
## quiet — без записи в книгу и без мук совести (повседневный нрав души).
static func add(game: Game, c: Dictionary, v: float, deed: String = "", quiet: bool = false) -> void:
	if v == 0.0 or c.death != null:
		return
	var mx := max_value(game)
	var before := value(c)
	var after := clampf(before + v, -mx, mx)
	_store(game, c, after)
	var d := after - before
	if d == 0.0:
		return
	if not quiet:
		var log: Array = Data.as_array(c.vars.get("karma_log")).duplicate()
		log.append([game.date, d, deed])
		var n := int(game.def_num("karma.log_size", 12))
		c.vars["karma_log"] = log.slice(maxi(0, log.size() - n))
	# совесть: грех мучает совестливых
	if d < 0.0 and not quiet and _has_conscience(game, c):
		Chars.change_stress(game, c, -d * game.def_num("karma.conscience_stress", 1.0), "karma")
	game.emit("karma.changed", {"character": c, "value": d, "deed": deed})
	_check_tier(game, c)


## Снять пепел: поднять отрицательную карму к нулю не больше чем на v.
static func cleanse(game: Game, c: Dictionary, v: float, deed: String = "") -> void:
	var k := value(c)
	if k >= 0.0 or v <= 0.0:
		return
	add(game, c, minf(v, -k), deed)


static func _store(_game: Game, c: Dictionary, v: float) -> void:
	if absf(v) < 0.001:
		c.vars.erase("karma")
	else:
		c.vars["karma"] = v


static func _has_conscience(game: Game, c: Dictionary) -> bool:
	for t in game.def_val("karma.conscience_immune", []):
		if c.traits.has(t):
			return false
	for t in game.def_val("karma.conscience_traits", []):
		if c.traits.has(t):
			return true
	return false


static func _check_tier(game: Game, c: Dictionary) -> void:
	var lvl := tier_level(game, c)
	var t: Variant = tier_at(game, lvl)
	if t == null:
		return
	var neutral := neutral_level(game)
	var was_id: Variant = c.vars.get("karma_tier")
	var was := level_of_id(game, str(was_id)) if was_id != null else neutral
	if was == lvl:
		return
	if lvl == neutral:
		c.vars.erase("karma_tier")
	else:
		c.vars["karma_tier"] = t.id
	game.stat_cache.erase(c.id)
	game.emit("karma.tier", {"character": c, "from": was, "to": lvl})
	if game.is_player(c.id):
		game.message(game.loc.t("msg.karma_tier_up" if lvl > was else "msg.karma_tier_down", {"tier": game.name_of("karma_tiers", t.id)}),
			"good" if lvl > was else "bad", {"type": "character", "id": c.id})
	game.on_action("on_karma_tier_up" if lvl > was else "on_karma_tier_down", {"type": "character", "id": c.id})


## Перенести карму (например, «пепел на роду» наследнику): вызывает хуки.
static func set_value(game: Game, c: Dictionary, v: float) -> void:
	var mx := max_value(game)
	_store(game, c, clampf(v, -mx, mx))
	_check_tier(game, c)


# ------------------------------------------------------------ нрав души

## Сумма значений из словаря черта → число по чертам персонажа.
static func _by_traits(c: Dictionary, table: Variant) -> float:
	var v := 0.0
	if table is Dictionary:
		for t in c.traits:
			v += Data.num(table.get(t))
	return v


## Начальная карма по чертам (в начале игры).
static func seed_world(game: Game) -> void:
	var table: Variant = game.def_val("karma.trait_seed", {})
	for c in game.living():
		if not Chars.is_adult(game, c):
			continue
		var v := _by_traits(c, table)
		if v != 0.0:
			v += game.rng.range_float(-5.0, 5.0)
			set_value(game, c, roundf(v))


## Раз в год (в «свой» месяц): черты понемногу двигают карму.
static func monthly_char(game: Game, c: Dictionary) -> void:
	if c.death != null or (Rng.hash_string(c.id + ":soul") & 0x7FFFFFFF) % 12 != GameDate.parts(game.date).m - 1:
		return
	if not Chars.is_adult(game, c):
		return
	var v := _by_traits(c, game.def_val("karma.trait_drift", {}))
	if v == 0.0:
		return
	var cap := game.def_num("karma.drift_max", 3)
	add(game, c, clampf(v, -cap, cap), "", true)


# ------------------------------------------------------------ сравнение ступеней

static func compare_tier(game: Game, lvl: int, arg: Variant) -> bool:
	var p := Politics._tier_arg(str(arg))
	var want := level_of_id(game, p[1])
	if want < 0:
		game.script_error("Неизвестная ступень кармы \"%s\"" % p[1])
		return false
	match p[0]:
		">=":
			return lvl >= want
		">":
			return lvl > want
		"<=":
			return lvl <= want
		"<":
			return lvl < want
		"!=":
			return lvl != want
	return lvl == want


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("karma", {"id": "karma", "order": 58, "on_character_month": Karma.monthly_char}, OWNER)
	engine.hooks.on("game.setup", func(p): Karma.seed_world(p.game), 0, OWNER)
	# ступень кармы — модификаторы носителю (кроме нейтральной)
	engine.modifier_providers.register("karma_tier", {"fn": func(game: Game, c: Dictionary) -> Variant:
		if not c.vars.has("karma_tier"):
			return null
		var t: Variant = game.content.get_def("karma_tiers", str(c.vars.karma_tier))
		if t == null or not (t.get("modifiers") is Dictionary) or t.modifiers.is_empty():
			return null
		var tid: String = t.id
		return [{"label": func(): return game.loc.t("ui.karma_tier_mod", {"tier": game.name_of("karma_tiers", tid)}), "modifiers": t.modifiers}]
	}, OWNER)
	# ревнители веры холодны к запятнанным пеплом и чтут праведников
	engine.opinion_providers.register("karma", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		if not b.vars.has("karma_tier") or a.id == b.id:
			return null
		var zealot := false
		for t in game.def_val("karma.zealot_traits", ["zealous"]):
			if a.traits.has(t):
				zealot = true
				break
		if not zealot:
			return null
		var t: Variant = game.content.get_def("karma_tiers", str(b.vars.karma_tier))
		var v := Data.num(t.get("zealot_opinion")) if t != null else 0.0
		if v == 0.0:
			return null
		return {"label": game.loc.t("opinion.karma_zealot", {"tier": game.name_of("karma_tiers", t.id)}), "value": v}
	}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	r.values.register("karma", {"scopes": CH, "doc": "Карма «Свет и Пепел» (−100…100)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Karma.value(c) if c != null else 0.0
	}, OWNER)
	r.values.register("karma_tier_level", {"scopes": CH, "doc": "Номер ступени кармы (0 — самая пепельная)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(maxi(0, Karma.tier_level(ctx.game, c))) if c != null else 0.0
	}, OWNER)
	r.triggers.register("karma_tier", {"scopes": CH, "doc": "Ступень кармы: karma_tier: ashen или karma_tier: \">= pious\"", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return c != null and Karma.compare_tier(ctx.game, Karma.tier_level(ctx.game, c), arg),
		"describe": func(ctx, _s, arg):
			var p := Politics._tier_arg(str(arg))
			var op: String = {">=": "ge", ">": "gt", "<=": "le", "<": "lt", "!=": "ne", "==": "eq"}[p[0]]
			return ctx.game.loc.t("tr.karma_tier", {"cond": ctx.game.loc.t("tr.tier_cmp." + op, {"tier": ctx.game.name_of("karma_tiers", p[1])})}),
	}, OWNER)
	r.effects.register("add_karma", {"scopes": CH, "doc": "Изменить карму: add_karma: -15 или { value: -15, deed: unjust_execution } (deed — запись в Книге деяний)",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c == null:
				return
			var v := Interp.eval_value(ctx, s, arg.get("value", 0)) if arg is Dictionary else Interp.eval_value(ctx, s, arg)
			Karma.add(ctx.game, c, v, str(arg.get("deed", "")) if arg is Dictionary else ""),
		"describe": func(ctx, s, arg):
			var v := Interp.eval_value(ctx, s, arg.get("value", 0)) if arg is Dictionary else Interp.eval_value(ctx, s, arg)
			return ctx.game.loc.t("fx.add_karma_light" if v > 0 else "fx.add_karma_ash"),
	}, OWNER)
	r.effects.register("cleanse_ash", {"scopes": CH, "doc": "Снять пепел: поднять отрицательную карму к нулю (не выше) на N: cleanse_ash: 40 или { value, deed }",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c == null:
				return
			var v := Interp.eval_value(ctx, s, arg.get("value", 0)) if arg is Dictionary else Interp.eval_value(ctx, s, arg)
			Karma.cleanse(ctx.game, c, v, str(arg.get("deed", "")) if arg is Dictionary else ""),
		"describe": func(ctx, _s, _arg): return ctx.game.loc.t("fx.cleanse_ash"),
	}, OWNER)
	engine.content_validators.register("karma", func(e: GameEngine, v: ScriptValidator):
		var lows := e.content.all("karma_tiers").filter(func(t): return t.get("min") == null)
		if lows.size() > 1:
			v.issue("karma_tiers: без порога min может быть только нижняя ступень")
	, OWNER)

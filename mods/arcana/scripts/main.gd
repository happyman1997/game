extends RefCounted
## «Тайные искусства» — механики, которые не выразить данными:
##   • колдовская сила одарённых (переменная arcane_power) и её восполнение;
##   • жажда вампиров (blood_thirst), кормление, безумие крови, бессмертие;
##   • полнолуние для оборотней;
##   • восставшие мертвецы на карте: курганы, распространение, битвы армий
##     с нежитью, очищение, освящение, власть некроманта над мёртвыми;
##   • драконы в горах и охота на них;
##   • проклятия, охота на ведьм, «Священная охота» на разоблачённых чудовищ;
##   • пути развития: сила крови вампира (птенец → древний), зверь внутри
##     оборотня (укрощение или одичание), слава охотника на нечисть, упадок
##     мертвецов без колдовской силы некроманта;
##   • взгляды вер: христиане видят в чудовищах нечисть, язычники Севера
##     чтят сейд и ульфхеднаров;
##   • стартовая расстановка мира, иконки и интерфейс (режим карты, вкладка,
##     виджеты, оповещения, раздел провинции).
## Состояние мода — game.mod_data("arcana"), попадает в сохранения.

const MOD := "arcana"
const ARCANE_TRAITS := ["gifted", "changeling", "necromancer", "lich", "white_mage", "battlemage"]
## Не умирают от старости и болезней.
const UNDYING := ["vampire", "lich"]
const MORTAL_REASONS := {"natural": true, "illness": true, "childhood": true, "plague": true}
## Чудовища, на которых охотится Церковь (когда о них известно).
const MONSTERS := ["vampire", "lich", "necromancer", "lycanthrope"]
const MONSTER_SECRETS := ["secret_necromancy", "secret_vampire", "secret_werewolf"]
const CELTIC := ["irish", "welsh", "scottish", "breton"]
const NORSE := ["norse", "danish", "swedish"]
## Черты, о которых у вер есть мнение (быстрый отсев в поставщике мнения).
const FAITH_VIEWED := ["gifted", "white_mage", "vampire", "lich", "necromancer", "lycanthrope"]
## Модификаторы уровней пути: снимаются, когда персонаж теряет черту.
const VAMPIRE_TIER_MODS := ["", "", "vampire_tier_2", "vampire_tier_3", "vampire_tier_4"]
const WOLF_MODS := ["wolf_feral", "wolf_tamed", "wolf_alpha"]


# ============================================================ состояние

## { risen: {провинция: {strength, months}}, barrows: [...], fey: [...],
##   dragons: {провинция: {hoard, months}}, outbreaks, dragons_slain }
static func state_of(game: Game) -> Dictionary:
	return game.mod_data(MOD, func(): return {"risen": {}, "barrows": [], "fey": [], "dragons": {}, "outbreaks": 0, "dragons_slain": 0})


static func t(game: Game, key: String, params: Dictionary = {}) -> String:
	return game.loc.t("arcana." + key, params)


static func pname(game: Game, prov: String) -> String:
	return game.name_of("provinces", prov)


static func cname(game: Game, id: Variant) -> String:
	return game.scope_name({"type": "character", "id": id})


## Где живёт персонаж: своя столица или столица сюзерена.
static func home_of(game: Game, c: Dictionary) -> Variant:
	if not c.titles.is_empty():
		return c.capital
	var l: Variant = game.ch(c.liege)
	return l.capital if l != null else null


## Затрагивает ли провинция державу игрока (для сообщений и событий).
static func player_realm_has(game: Game, prov: String) -> bool:
	var p: Variant = game.player
	if p == null:
		return false
	var t: Variant = game.state.titles.get(prov)
	var h: Variant = game.ch(t.holder) if t != null else null
	return h != null and (h.id == p.id or Titles.is_in_realm_of(game, h, p))


static func notify_player(game: Game, prov: String, text: String, kind: String) -> void:
	if player_realm_has(game, prov):
		game.message(text, kind, {"type": "province", "id": prov})


# ============================================================ колдовская сила

static func is_arcanist(game: Game, c: Dictionary) -> bool:
	for tr in ARCANE_TRAITS:
		if c.traits.has(tr):
			return true
	# Без дара колдовство 6+ бывает только при заметном врождённом навыке —
	# остальным не нужно считать характеристики (проверка идёт каждый месяц).
	return Data.num(c.skills.get("sorcery")) >= 2.0 and Stats.skill(game, c, "sorcery") >= 6


static func power(c: Dictionary) -> float:
	return Data.num(c.vars.get("arcane_power"))


static func power_max(game: Game, c: Dictionary) -> float:
	return game.def_num("arcana.power_base_max", 40) + Stats.skill(game, c, "sorcery") * game.def_num("arcana.power_max_per_sorcery", 3) \
		+ Stats.stat(game, c, "arcane_capacity")


static func add_power(game: Game, c: Dictionary, v: float) -> void:
	c.vars["arcane_power"] = clampf(power(c) + v, 0.0, maxf(power(c), power_max(game, c)) if v < 0 else power_max(game, c))


static func thirst(c: Dictionary) -> float:
	return Data.num(c.vars.get("blood_thirst"))


static func potency(c: Dictionary) -> float:
	return Data.num(c.vars.get("blood_potency"))


## Уровень вампира: 1 — птенец, 2 — вампир, 3 — старейшина, 4 — древний; 0 — не вампир.
static func vampire_tier(game: Game, c: Dictionary) -> int:
	if not c.traits.has("vampire"):
		return 0
	var p := potency(c)
	var tier := 1
	for s in game.def_val("arcana.vampire_tiers", [20, 50, 90]):
		if p >= Data.num(s):
			tier += 1
	return tier


## Зверь внутри оборотня: от −100 (зверь взял верх) до 100 (зверь укрощён).
static func beast(c: Dictionary) -> float:
	return Data.num(c.vars.get("beast_control"))


static func monsters_slain(c: Dictionary) -> int:
	return int(Data.num(c.vars.get("monsters_slain")))


# ============================================================ инициализация

func init(api: ModApi) -> void:
	_register_icons()
	_register_script(api)
	_register_hooks(api)
	_register_ui(api)
	api.add_system({"id": "arcana", "order": 66, "on_month": _monthly, "on_character_month": _char_month})
	api.log("тайные искусства пробудились: черт — %d, событий — %d" % [
		api.content.all("traits").filter(func(x): return x.get("category") == "supernatural").size(),
		api.content.all("events").filter(func(e): return str(e.id).begins_with("arcana.")).size()])


# ------------------------------------------------------------ скриптовый язык

func _register_script(api: ModApi) -> void:
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null

	api.value("arcane_power", {"scopes": CH, "doc": "Колдовская сила персонажа",
		"get": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			return power(c) if c != null else 0.0})
	api.value("blood_thirst", {"scopes": CH, "doc": "Жажда крови вампира (0–100)",
		"get": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			return thirst(c) if c != null else 0.0})
	api.value("blood_potency", {"scopes": CH, "doc": "Сила крови вампира (растёт с годами и кормлением)",
		"get": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			return potency(c) if c != null else 0.0})
	api.value("vampire_tier", {"scopes": CH, "doc": "Уровень вампира: 1 птенец, 2 вампир, 3 старейшина, 4 древний (0 — не вампир)",
		"get": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			return float(vampire_tier(ctx.game, c)) if c != null else 0.0})
	api.value("beast_control", {"scopes": CH, "doc": "Власть оборотня над зверем: −100 (одичал) … 100 (вожак стаи)",
		"get": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			return beast(c) if c != null else 0.0})
	api.value("monsters_slain", {"scopes": CH, "doc": "Сколько чудовищ уничтожил персонаж (слава охотника)",
		"get": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			return float(monsters_slain(c)) if c != null else 0.0})
	api.value("world_vampires", {"doc": "Сколько вампиров живёт в мире (считается раз в месяц)",
		"get": func(ctx, _s, _a):
			var g: Game = ctx.game
			var hit: Variant = g.month_cache.get("arcana:vampires")
			if hit == null:
				hit = float(g.living().filter(func(c): return c.traits.has("vampire")).size())
				g.month_cache["arcana:vampires"] = hit
			return hit})

	api.effect("add_arcane_power", {"scopes": CH, "doc": "Изменить колдовскую силу: add_arcane_power: -30",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				add_power(ctx.game, c, Interp.eval_value(ctx, s, arg)),
		"describe": func(ctx, s, arg):
			var v := Interp.eval_value(ctx, s, arg)
			return t(ctx.game, "fx_power", {"value": ("+" if v > 0 else "") + str(roundi(v))})})
	api.effect("add_blood_thirst", {"scopes": CH, "doc": "Изменить жажду крови",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				c.vars["blood_thirst"] = clampf(thirst(c) + Interp.eval_value(ctx, s, arg), 0.0, 100.0),
		"describe": func(_ctx, _s, _a): return null})
	api.effect("add_blood_potency", {"scopes": CH, "doc": "Изменить силу крови вампира",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null and c.traits.has("vampire"):
				add_potency(ctx.game, c, Interp.eval_value(ctx, s, arg)),
		"describe": func(ctx, s, arg): return t(ctx.game, "fx_potency", {"value": "%+d" % roundi(Interp.eval_value(ctx, s, arg))})})
	api.effect("add_beast_control", {"scopes": CH, "doc": "Сдвинуть власть оборотня над зверем (+ укрощение, − одичание)",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null and c.traits.has("lycanthrope"):
				add_beast(ctx.game, c, Interp.eval_value(ctx, s, arg)),
		"describe": func(ctx, s, arg):
			var v := Interp.eval_value(ctx, s, arg)
			return t(ctx.game, "fx_beast_up" if v > 0 else "fx_beast_down", {"value": "%+d" % roundi(v)})})
	api.effect("add_monster_kill", {"scopes": CH, "doc": "Засчитать уничтоженное чудовище: add_monster_kill: 2 (слава охотника)",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				add_monster_kill(ctx.game, c, int(Interp.eval_value(ctx, s, arg))),
		"describe": func(ctx, _s, _a): return t(ctx.game, "fx_hunter")})
	api.effect("bless_domain", {"scopes": CH, "doc": "Светлый чародей благословляет земли домена",
		"apply": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				bless_domain(ctx.game, c),
		"describe": func(ctx, _s, _a): return t(ctx.game, "fx_bless")})
	api.effect("firestorm", {"scopes": CH, "doc": "Огненная буря на крупнейшее вражеское войско у границ",
		"apply": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				firestorm(ctx.game, c),
		"describe": func(ctx, _s, _a): return t(ctx.game, "fx_firestorm")})
	api.effect("plague_of_the_dead", {"scopes": CH, "doc": "Лич поднимает мёртвых в столице главного врага",
		"apply": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				plague_of_dead(ctx.game, c),
		"describe": func(ctx, _s, _a): return t(ctx.game, "fx_plague_dead")})
	api.effect("hunt_monsters", {"scopes": CH, "doc": "Выследить чудовище в державе: найденная тайна раскрывается",
		"apply": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				hunt_monsters(ctx.game, c),
		"describe": func(ctx, _s, _a): return t(ctx.game, "fx_hunt_monsters")})
	api.effect("cure_ailments", {"scopes": CH, "doc": "Снять болезни, раны и порчу",
		"apply": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				cure_ailments(ctx.game, c),
		"describe": func(ctx, _s, _a): return t(ctx.game, "fx_cure")})
	api.effect("arcane_witness", {"scopes": CH, "doc": "Риск свидетелей: { secret, chance } — кто-то при дворе узнаёт тайну",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null and arg is Dictionary:
				witness(ctx.game, c, str(arg.get("secret")), Data.num(arg.get("chance"), 20)),
		"describe": func(ctx, _s, arg): return t(ctx.game, "fx_witness", {"n": int(Data.num(arg.get("chance"), 20)) if arg is Dictionary else 20})})
	api.effect("learn_secret", {"scopes": CH, "doc": "Узнать тайну персонажа: { owner, type }",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var o: Variant = Interp.resolve_scope(ctx, s, arg.get("owner")) if arg is Dictionary else null
			var oc: Variant = ctx.game.ch(o.id) if (o != null and o.type == "character") else null
			if c != null and oc != null:
				for sec in Secrets.secrets_of(oc):
					if sec.type == arg.get("type"):
						Secrets.learn(ctx.game, c, oc, sec),
		"describe": func(_ctx, _s, _a): return null})
	api.effect("cast_curse_on", {"scopes": CH, "doc": "Проклясть персонажа (со стоимостью и риском разоблачения)",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var o: Variant = Interp.resolve_scope(ctx, s, arg)
			var oc: Variant = ctx.game.ch(o.id) if (o != null and o.type == "character") else null
			if c != null and oc != null:
				cast_curse(ctx.game, c, oc),
		"describe": func(ctx, s, arg):
			var o: Variant = Interp.resolve_scope(ctx, s, arg)
			return t(ctx.game, "fx_curse", {"who": ctx.game.scope_name(o) if o != null else "?"})})
	api.effect("feed_on_blood", {"scopes": CH, "doc": "Вампир утоляет жажду (жертва — пленник или придворный)",
		"apply": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				feed(ctx.game, c),
		"describe": func(ctx, _s, _a): return t(ctx.game, "fx_feed")})
	api.effect("witch_hunt", {"scopes": CH, "doc": "Охота на ведьм в державе",
		"apply": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				witch_hunt(ctx.game, c),
		"describe": func(_ctx, _s, _a): return null})
	api.effect("awaken_dead", {"scopes": ["province"], "doc": "Мёртвые восстают в провинции: awaken_dead: 30 (сила)",
		"apply": func(ctx, s, arg): awaken(ctx.game, s.id, Data.num(arg, 30) if not (arg is bool) else 30.0),
		"describe": func(ctx, s, _a): return t(ctx.game, "fx_awaken", {"place": pname(ctx.game, s.id)})})
	api.effect("purge_restless_dead", {"scopes": CH, "doc": "Выжечь нежить в самой поражённой провинции державы (purge_restless_dead: { magic: yes } — светом чар, а не ополчением)",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				purge(ctx.game, c, arg is Dictionary and ScriptContext.is_yes(arg.get("magic"))),
		"describe": func(_ctx, _s, _a): return null})
	api.effect("consecrate_against_dead", {"scopes": CH, "doc": "Освятить земли державы против нежити",
		"apply": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				consecrate(ctx.game, c),
		"describe": func(_ctx, _s, _a): return null})
	api.effect("command_restless_dead", {"scopes": CH, "doc": "Некромант подчиняет восставших мёртвых своей державы",
		"apply": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				command_dead(ctx.game, c),
		"describe": func(_ctx, _s, _a): return null})
	api.effect("hunt_dragon", {"scopes": CH, "doc": "Выйти на бой с ближайшим драконом",
		"apply": func(ctx, s, _a):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				hunt_dragon(ctx.game, c),
		"describe": func(_ctx, _s, _a): return null})

	api.trigger("realm_has_restless_dead", {"scopes": CH, "doc": "В державе персонажа восстали мертвецы",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var yes: bool = c != null and not realm_risen(ctx.game, c).is_empty()
			return yes == ScriptContext.is_yes(arg)})
	api.trigger("near_dragon_lair", {"scopes": CH, "doc": "Логово дракона в державе персонажа или по соседству",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var yes: bool = c != null and nearest_lair(ctx.game, c) != null
			return yes == ScriptContext.is_yes(arg)})
	api.trigger("realm_has_fey_hills", {"scopes": CH, "doc": "В державе персонажа есть холмы фей",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var yes: bool = c != null and not realm_places(ctx.game, c, "fey").is_empty()
			return yes == ScriptContext.is_yes(arg)})
	api.trigger("realm_has_barrow", {"scopes": CH, "doc": "В державе персонажа есть древний курган",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var yes: bool = c != null and not realm_places(ctx.game, c, "barrows").is_empty()
			return yes == ScriptContext.is_yes(arg)})
	api.trigger("dragon_wary", {"scopes": CH, "doc": "Ближайший дракон настороже после недавней охоты",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			var lair: Variant = nearest_lair(ctx.game, c) if c != null else null
			var yes: bool = lair != null and int(state_of(ctx.game).dragons[lair].get("wary_until", 0)) > ctx.game.date
			return yes == ScriptContext.is_yes(arg)})
	api.trigger("province_restless", {"scopes": ["province"], "doc": "В провинции бродят мертвецы",
		"eval": func(ctx, s, arg): return state_of(ctx.game).risen.has(s.id) == ScriptContext.is_yes(arg)})
	api.trigger("is_arcanist", {"scopes": CH, "doc": "Владеет колдовством (дар или навык ≥ 6)",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			return (c != null and is_arcanist(ctx.game, c)) == ScriptContext.is_yes(arg)})
	api.trigger("is_known_monster", {"scopes": CH, "doc": "Разоблачённое чудовище (вампир, лич, некромант, оборотень)",
		"eval": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			return (c != null and is_known_monster(ctx.game, c)) == ScriptContext.is_yes(arg)})

	# «Священная охота»: цели — разоблачённые чудовища по соседству и в своей державе
	api.registries.cb_targets.register("monster_hunt", {"targets": func(game: Game, attacker: Dictionary) -> Array:
		var out := []
		# чаще всего разоблачённых чудовищ-правителей нет вовсе — соседей не перебираем
		var known := known_monster_rulers(game)
		if known.is_empty():
			return out
		for id in nearby_rulers(game, attacker):
			if not known.has(id):
				continue
			var d: Variant = game.ch(id)
			if d == null or d.titles.is_empty():
				continue
			var cap: Variant = d.capital if d.capital != null else Titles.capital_of(game, d)
			out.append({"defender": d.id, "title": d.titles[0], "counties": [cap] if cap != null else []})
		return out}, api.owner)

	# Взгляды вер: христиане видят в разоблачённых чудовищах нечисть, а
	# ревнители — грех и в самом даре, но чтут светлых целителей; язычники
	# Севера уважают сейд и ульфхеднаров.
	api.registries.opinion_providers.register("arcana_faith", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		var bt: Array = b.traits
		var any := false
		for tr in FAITH_VIEWED:
			if bt.has(tr):
				any = true
				break
		if not any or a.traits.has("vampire") or a.traits.has("lich"):
			return null
		var faith: Variant = game.content.get_def("faiths", a.faith)
		var rel: Variant = faith.get("religion") if faith != null else null
		if rel == "christianity":
			for tr in MONSTERS:
				if bt.has(tr) and Chars.trait_visible(game, b, tr, a.id):
					return {"label": t(game, "opinion_abomination"), "value": game.def_num("arcana.abomination_opinion", -40)}
			if bt.has("white_mage"):
				return {"label": t(game, "opinion_saint_healer"), "value": 10.0}
			if bt.has("gifted") and a.traits.has("zealous"):
				return {"label": t(game, "opinion_sinful_gift"), "value": -10.0}
		elif rel == "germanic":
			if bt.has("lycanthrope") and Chars.trait_visible(game, b, "lycanthrope", a.id):
				return {"label": t(game, "opinion_ulfhednar"), "value": 15.0}
			if bt.has("gifted") or bt.has("white_mage"):
				return {"label": t(game, "opinion_seidr"), "value": 10.0}
		return null}, api.owner)


# ------------------------------------------------------------ хуки

func _register_hooks(api: ModApi) -> void:
	# Вампиры и личи не умирают от старости и болезней.
	api.hooks.on("character.before_death", func(p):
		var c: Dictionary = p.character
		if MORTAL_REASONS.has(str(p.get("reason"))):
			for tr in UNDYING:
				if c.traits.has(tr):
					return false
		return null, 0, api.owner)
	api.hooks.on("game.setup", func(p): _setup_world(p.game), 0, api.owner)
	# Разоблачивший чудовище — на шаг ближе к славе охотника.
	api.hooks.on("secret.exposed", func(p):
		var ex: Variant = p.get("exposer")
		if ex != null and MONSTER_SECRETS.has(str(p.secret.type)):
			add_monster_kill(p.game, ex, 1)
		return null, 0, api.owner)
	# Поле кровавой битвы может пробудить мёртвых.
	api.hooks.on("battle", func(p):
		var game: Game = p.game
		var losses := int(p.get("win_loss", 0)) + int(p.get("lose_loss", 0))
		if losses >= int(game.def_num("arcana.battlefield_min_losses", 1500)) and game.rng.chance(game.def_num("arcana.battlefield_rise_chance", 0.08)):
			awaken(game, str(p.location), 15.0 + losses / 200.0)
		return null, 0, api.owner)


# ============================================================ стартовая расстановка

static func _setup_world(game: Game) -> void:
	var st := state_of(game)
	var rng := game.rng
	var provs: Array = game.state.provinces.keys()
	provs.sort()
	# Древние курганы — места, где мёртвые спят неглубоко.
	var barrow_terrain := {"hills": true, "plains": true, "wetlands": true, "farmlands": true}
	var cands := provs.filter(func(p):
		var d: Variant = game.content.get_def("provinces", p)
		return d != null and barrow_terrain.has(str(d.get("terrain"))))
	rng.shuffle(cands)
	for p in cands.slice(0, int(game.def_num("arcana.barrows", 7))):
		st.barrows.append(p)
		game.state.provinces[p].modifiers.append({"id": "ancient_barrow"})
	# Холмы фей — в кельтских землях.
	var fey := provs.filter(func(p):
		var d: Variant = game.content.get_def("provinces", p)
		return d != null and CELTIC.has(str(d.get("culture"))))
	rng.shuffle(fey)
	for p in fey.slice(0, int(game.def_num("arcana.fey_hills", 5))):
		st.fey.append(p)
		game.state.provinces[p].modifiers.append({"id": "fey_hills"})
	# Одарённые.
	var chance := game.def_num("arcana.gifted_start_chance", 0.03)
	for c in game.living():
		if rng.chance(chance) and not c.traits.has("gifted"):
			Chars.add_trait(game, c, "gifted")
			c.vars["arcane_power"] = float(rng.range_int(10, 30))
	# Древний вампир — тихий граф на краю христианского мира.
	var counts := game.rulers().filter(func(c): return Titles.primary_tier(game, c) == 1 and c.liege != null and Chars.age_of(game, c) >= 25)
	if not counts.is_empty():
		var v: Dictionary = rng.pick(counts)
		_make_vampire(game, v, true)
	# Тёмный чародей при чужом дворе.
	var courtiers := game.living().filter(func(c): return c.titles.is_empty() and c.liege != null and Chars.age_of(game, c) >= 30)
	if not courtiers.is_empty():
		var n: Dictionary = rng.pick(courtiers)
		if not n.traits.has("gifted"):
			Chars.add_trait(game, n, "gifted")
		# весь путь некроманта: шёпот могил (тайна), подъём мёртвых, жатва, черта
		for perk in ["grave_whispers", "raise_dead", "soul_harvest", "deathless_will"]:
			Lifestyles.unlock_perk(game, n, perk, true)
		n.vars["arcane_power"] = 60.0
	# Оборотень где-то в лесах.
	var woods := game.living().filter(func(c):
		var h: Variant = home_of(game, c)
		var d: Variant = game.content.get_def("provinces", h) if h != null else null
		return d != null and d.get("terrain") == "forest" and Chars.age_of(game, c) >= 18 and c.titles.is_empty())
	if not woods.is_empty():
		var w: Dictionary = rng.pick(woods)
		Chars.add_trait(game, w, "lycanthrope")
		Secrets.add_secret(game, w, "secret_werewolf")
	# Дракон спит в горах.
	_wake_dragon(game, false)


static func _make_vampire(game: Game, c: Dictionary, ancient: bool = false) -> void:
	Chars.add_trait(game, c, "vampire")
	if Secrets.secrets_of(c).all(func(s): return s.type != "secret_vampire"):
		Secrets.add_secret(game, c, "secret_vampire")
	c.vars["blood_thirst"] = 20.0
	if ancient:
		# древняя кровь: этот вампир старше самой державы
		add_potency(game, c, 160.0)


# ============================================================ месяц персонажа

static func _char_month(game: Game, c: Dictionary) -> void:
	if c.death != null:
		return
	# колдовская сила
	if is_arcanist(game, c):
		var regen := game.def_num("arcana.power_base_regen", 2) + Stats.skill(game, c, "sorcery") * game.def_num("arcana.power_per_sorcery", 0.35) \
			+ Stats.stat(game, c, "arcane_regen")
		add_power(game, c, regen)
	if c.traits.has("vampire"):
		_vampire_month(game, c)
	elif c.vars.has("blood_potency"):
		_drop_path(game, c, VAMPIRE_TIER_MODS + ["bloodthirst"], ["blood_potency", "blood_thirst"])
	if c.traits.has("lycanthrope"):
		_wolf_month(game, c)
	elif c.vars.has("beast_control"):
		_drop_path(game, c, WOLF_MODS, ["beast_control"])
	if c.traits.has("changeling"):
		_fey_sight(game, c)
	if c.titles.is_empty():
		return
	if c.get("regiments") != null and not c.regiments.is_empty():
		_risen_upkeep(game, c)
	# Тайные события двора: игрок — каждый месяц, остальные правители — раз в
	# год, в «свой» месяц (шансы в on_arcane_pulse рассчитаны на это).
	if game.is_player(c.id) or (Rng.hash_string(c.id) & 0x7FFFFFFF) % 12 == GameDate.parts(game.date).m - 1:
		game.on_action("on_arcane_pulse", {"type": "character", "id": c.id})


## Черта пути снята (исцеление, обряд): убрать её уровни и счётчики.
static func _drop_path(game: Game, c: Dictionary, mods: Array, vars: Array) -> void:
	c.modifiers = c.modifiers.filter(func(m): return not mods.has(m.id))
	for v in vars:
		c.vars.erase(v)
	game.stat_cache.erase(c.id)


# ------------------------------------------------------------ вампиры: жажда и сила крови

static func _vampire_month(game: Game, c: Dictionary) -> void:
	add_potency(game, c, game.def_num("arcana.potency_per_month", 0.25))
	var tier := vampire_tier(game, c)
	# молодая кровь голоднее
	var per: Array = game.def_val("arcana.thirst_by_tier", [12, 10, 8, 6])
	var th := minf(100.0, thirst(c) + Data.num(per[clampi(tier - 1, 0, per.size() - 1)], 10.0))
	c.vars["blood_thirst"] = th
	var has_mod: bool = c.modifiers.any(func(m): return m.id == "bloodthirst")
	if th >= game.def_num("arcana.thirst_stress_from", 60):
		c.stress = float(c.stress) + 6.0
		if not has_mod:
			c.modifiers.append({"id": "bloodthirst"})
			game.stat_cache.erase(c.id)
		if game.is_player(c.id) and th >= 70 and th < 80:
			game.events.trigger("arcana.0012", {"type": "character", "id": c.id})
	elif has_mod:
		c.modifiers = c.modifiers.filter(func(m): return m.id != "bloodthirst")
		game.stat_cache.erase(c.id)
	# ИИ-вампир (в том числе придворный, у которого нет решений) кормится сам
	if not game.is_player(c.id) and th >= 50.0 and game.rng.chance(0.7):
		feed(game, c)
	elif th >= 100.0:
		if tier >= 4:
			# древний не теряет себя — лишь мучается
			c.stress = float(c.stress) + 10.0
		else:
			frenzy(game, c)


static func add_potency(game: Game, c: Dictionary, v: float) -> void:
	var before := vampire_tier(game, c)
	c.vars["blood_potency"] = maxf(0.0, potency(c) + v)
	var tier := vampire_tier(game, c)
	var want: String = VAMPIRE_TIER_MODS[tier]
	if tier == before and (want == "" or c.modifiers.any(func(m): return m.id == want)):
		return
	# уровень — скрытый модификатор (виден лишь знающим тайну)
	c.modifiers = c.modifiers.filter(func(m): return not VAMPIRE_TIER_MODS.has(m.id))
	if want != "":
		c.modifiers.append({"id": want})
	game.stat_cache.erase(c.id)
	if tier > before and game.is_player(c.id):
		game.message(t(game, "msg_tier_vampire", {"tier": t(game, "vampire_tier_%d" % tier), "powers": t(game, "vampire_powers_%d" % tier)}), "good")


# ------------------------------------------------------------ оборотни: зверь внутри

static func _wolf_month(game: Game, c: Dictionary) -> void:
	var b := beast(c)
	var chance := game.def_num("arcana.full_moon_chance", 30)
	if b >= 90.0:
		return  # вожак стаи оборачивается, когда сам захочет
	if b >= 50.0:
		chance *= 0.5
	elif b <= -50.0:
		chance *= 1.5
	if game.rng.next() * 100.0 < chance:
		game.events.trigger("arcana.0041", {"type": "character", "id": c.id})


static func add_beast(game: Game, c: Dictionary, v: float) -> void:
	var before := _wolf_stage(beast(c))
	var b := clampf(beast(c) + v, -100.0, 100.0)
	c.vars["beast_control"] = b
	var stage := _wolf_stage(b)
	if stage != before:
		c.modifiers = c.modifiers.filter(func(m): return not WOLF_MODS.has(m.id))
		if stage != "":
			c.modifiers.append({"id": stage})
		game.stat_cache.erase(c.id)
		if game.is_player(c.id) and stage != "":
			game.message(t(game, "msg_" + stage), "good" if stage != "wolf_feral" else "bad")
	if b <= -100.0:
		_beast_wins(game, c)


static func _wolf_stage(b: float) -> String:
	if b >= 90.0:
		return "wolf_alpha"
	if b >= 50.0:
		return "wolf_tamed"
	if b <= -50.0:
		return "wolf_feral"
	return ""


## Зверь победил: правитель разоблачён и правит зверем, безземельный уходит в лес.
static func _beast_wins(game: Game, c: Dictionary) -> void:
	if game.is_player(c.id):
		game.events.trigger("arcana.0042", {"type": "character", "id": c.id})
	for s in Secrets.secrets_of(c).duplicate():
		if s.type == "secret_werewolf":
			Secrets.expose(game, null, c, s)
	if c.titles.is_empty():
		Succession.kill_character(game, c, "beast_within")
	else:
		c.vars["beast_control"] = -60.0
		c.stress = float(c.stress) + 40.0


# ------------------------------------------------------------ подменыши, мертвецы на службе

## Подменыш видит сквозь чары: порой узнаёт тайну чудовища при своём дворе.
static func _fey_sight(game: Game, c: Dictionary) -> void:
	if not game.rng.chance(game.def_num("arcana.fey_sight_chance", 0.03)):
		return
	var court_of: String = c.id if not c.titles.is_empty() else str(c.liege)
	var pool: Array = game.courtiers_of(court_of)
	var l: Variant = game.ch(court_of)
	if l != null:
		pool.append(l)
	for x in pool:
		if x.id == c.id:
			continue
		for s in Secrets.secrets_of(x):
			if MONSTER_SECRETS.has(s.type) and not s.known.has(c.id):
				Secrets.learn(game, c, x, s)
				if game.is_player(c.id):
					game.message(t(game, "msg_fey_sight", {"who": cname(game, x.id)}), "event", {"type": "character", "id": x.id})
				return


## Мертвецов держит воля некроманта: каждый отряд в месяц стоит колдовской
## силы; без неё (или без некроманта) нежить истлевает.
static func _risen_upkeep(game: Game, c: Dictionary) -> void:
	var risen: Array = c.regiments.filter(func(r): return r.type == "risen_dead")
	if risen.is_empty():
		return
	var cost := risen.size() * game.def_num("arcana.risen_upkeep_power", 0.75)
	var master: bool = c.traits.has("necromancer") or c.traits.has("lich")
	if master and power(c) >= cost:
		add_power(game, c, -cost)
		return
	var raised := Regiments._raised_ids(game, c.id)
	var rot := game.def_num("arcana.risen_rot", 0.12)
	for r in risen:
		if raised.has(r.id):
			continue  # в походе мертвецы держатся строя
		r.size = int(float(r.size) * (1.0 - rot))
		if int(r.size) < 20:
			Regiments.disband(game, c, r.id)


# ============================================================ месяц мира

static func _monthly(game: Game) -> void:
	var st := state_of(game)
	_restless_month(game, st)
	_dragon_month(game, st)


# ------------------------------------------------------------ восставшие мёртвые

static func awaken(game: Game, prov: String, strength: float) -> void:
	var st := state_of(game)
	if not game.state.provinces.has(prov):
		return
	var p: Dictionary = game.state.provinces[prov]
	# освящённая земля, чудотворная икона — мёртвые здесь не встают
	for m in p.modifiers:
		var md: Variant = game.content.get_def("modifiers", m.id)
		if md != null and md.get("wards_off_dead", false):
			return
	if st.risen.has(prov):
		st.risen[prov].strength = float(st.risen[prov].strength) + strength
		return
	st.risen[prov] = {"strength": strength, "months": 0}
	st.outbreaks = int(st.outbreaks) + 1
	if not p.modifiers.any(func(m): return m.id == "restless_dead"):
		p.modifiers.append({"id": "restless_dead"})
	game.stat_cache.erase("prov:" + prov)
	notify_player(game, prov, t(game, "msg_dead_rise", {"place": pname(game, prov)}), "bad")
	var pl: Variant = game.player
	if pl != null and player_realm_has(game, prov) and not pl.flags.has("arcana_seen_dead"):
		pl.flags["arcana_seen_dead"] = 0
		game.events.trigger("arcana.0020", {"type": "character", "id": pl.id}, {"place": {"type": "province", "id": prov}})
	game.emit("arcana.dead_risen", {"province": prov, "strength": strength})


static func _cleanse(game: Game, prov: String, by: Variant = null) -> void:
	var st := state_of(game)
	st.risen.erase(prov)
	var p: Variant = game.state.provinces.get(prov)
	if p == null:
		return
	var hero: Variant = game.ch(by) if by != null else null
	if hero != null:
		add_monster_kill(game, hero, 1)
		# драугры Севера стерегут курганное золото
		var d: Variant = game.content.get_def("provinces", prov)
		if d != null and NORSE.has(str(d.get("culture"))) and st.barrows.has(prov):
			var gold := game.rng.range_int(60, 160)
			hero.gold = float(hero.gold) + gold
			if game.is_player(hero.id):
				game.message(t(game, "msg_draugr_gold", {"place": pname(game, prov), "gold": gold}), "good", {"type": "province", "id": prov})
	p.modifiers = p.modifiers.filter(func(m): return m.id != "restless_dead")
	p.modifiers.append({"id": "haunted_ground", "expires": game.date + 365 * 3})
	game.stat_cache.erase("prov:" + prov)
	notify_player(game, prov, t(game, "msg_dead_cleansed", {"place": pname(game, prov), "who": cname(game, by) if by != null else "—"}), "good")
	game.emit("arcana.dead_cleansed", {"province": prov, "by": by})


static func _restless_month(game: Game, st: Dictionary) -> void:
	var rng := game.rng
	# курганы просыпаются
	for b in st.barrows:
		if not st.risen.has(b) and rng.next() < game.def_num("arcana.restless_outbreak_chance", 0.0025):
			awaken(game, b, 25.0)
	if st.risen.is_empty():
		return
	# где кто живёт — один проход по живым
	var homes := {}
	for c in game.living():
		var h: Variant = home_of(game, c)
		if h != null and st.risen.has(h):
			if not homes.has(h):
				homes[h] = []
			homes[h].append(c)
	var growth := game.def_num("arcana.restless_growth", 5)
	var spread_at := game.def_num("arcana.restless_spread_at", 60)
	var spread_chance := game.def_num("arcana.restless_spread_chance", 0.08)
	var lifespan := int(game.def_num("arcana.restless_lifespan", 12))
	var decay := game.def_num("arcana.restless_decay", 6)
	var cap := int(game.def_num("arcana.restless_max_provinces", 6))
	for prov in st.risen.keys():
		var e: Dictionary = st.risen[prov]
		# армии на месте сражаются с мёртвыми
		_armies_fight_dead(game, prov, e)
		if float(e.strength) <= 0.0:
			_cleanse(game, prov, e.get("last_fighter"))
			continue
		var ruled_by_necro := false
		var tt: Variant = game.state.titles.get(prov)
		var holder: Variant = game.ch(tt.holder) if tt != null else null
		if holder != null and (holder.traits.has("necromancer") or holder.traits.has("lich")):
			ruled_by_necro = true
		e.months = int(e.months) + 1
		# молодая вспышка растёт; старая без некроманта истлевает сама
		if ruled_by_necro or int(e.months) <= lifespan:
			e.strength = float(e.strength) + growth * (1.5 if ruled_by_necro else 1.0)
		else:
			e.strength = float(e.strength) - decay
			if float(e.strength) <= 0.0:
				_cleanse(game, prov)
				continue
		# мертвецы забирают живых
		var kill := game.def_num("arcana.restless_kill_chance", 0.02)
		for c in homes.get(prov, []):
			if c.death == null and not c.traits.has("lich") and not c.traits.has("vampire") and rng.next() < kill:
				Succession.kill_character(game, c, "undead")
		# разорение
		if e.months % 6 == 0:
			var p: Dictionary = game.state.provinces[prov]
			p.development = maxi(0, int(p.development) - 1)
		# расползаются по соседям
		if float(e.strength) >= spread_at and st.risen.size() < cap and rng.chance(spread_chance):
			var ns: Array = game.engine.neighbors(prov).filter(func(n): return game.state.provinces.has(n) and not st.risen.has(n))
			if not ns.is_empty():
				var n: String = rng.pick(ns)
				awaken(game, n, float(e.strength) / 4.0)
				e.strength = float(e.strength) * 0.75


static func _armies_fight_dead(game: Game, prov: String, e: Dictionary) -> void:
	var armies: Array = game.state.armies.values().filter(func(a): return a.location == prov and a.path.is_empty() and not a.get("retreating", false))
	if armies.is_empty():
		return
	var per_man := game.def_num("arcana.army_vs_dead", 0.02)
	var dmg := 0.0
	var men := 0.0
	for a in armies:
		var holy := 1.0
		for r in Data.as_array(a.get("regiments")):
			if r.type == "silver_flame":
				holy += 0.5 * float(r.size) / maxf(1.0, float(a.size))
			elif r.type == "risen_dead":
				holy -= 0.3 * float(r.size) / maxf(1.0, float(a.size))
		dmg += float(a.size) * per_man * maxf(0.3, holy)
		men += float(a.size)
	var before := float(e.strength)
	e.strength = maxf(0.0, before - dmg * game.rng.range_float(0.7, 1.3))
	var loss := roundi(minf(men * 0.25, before * game.def_num("arcana.dead_vs_army", 2.5)))
	Military._distribute(armies, loss, men)
	e["last_fighter"] = armies[0].owner
	for a in armies:
		if game.is_player(a.owner):
			game.message(t(game, "msg_army_vs_dead", {"place": pname(game, prov), "loss": loss, "left": roundi(e.strength)}), "war", {"type": "province", "id": prov})
			break
	for a in armies:
		if int(a.size) < 30 and game.state.armies.has(a.id):
			Military.disband_army(game, a.id)


## Тайные места (barrows / fey) в державе персонажа.
static func realm_places(game: Game, c: Dictionary, kind: String) -> Array:
	var places: Array = state_of(game)[kind]
	if places.is_empty() or c.titles.is_empty():
		return []
	var realm := {}
	for p in Titles.realm_counties(game, c):
		realm[p] = true
	return places.filter(func(p): return realm.has(p))


## Провинции державы персонажа, где бродят мёртвые (сильнейшие первыми).
static func realm_risen(game: Game, c: Dictionary) -> Array:
	var st := state_of(game)
	if st.risen.is_empty() or c.titles.is_empty():
		return []
	var out := []
	for prov in Titles.realm_counties(game, c):
		if st.risen.has(prov):
			out.append(prov)
	out.sort_custom(func(a, b): return float(st.risen[a].strength) > float(st.risen[b].strength))
	return out


static func purge(game: Game, c: Dictionary, magic: bool = false) -> void:
	var list := realm_risen(game, c)
	if list.is_empty():
		return
	var prov: String = list[0]
	var e: Dictionary = state_of(game).risen[prov]
	var force := 0.0
	if magic:
		# очищающий свет: сила — в колдовстве, а не в ополчении
		force = 20.0 + Stats.skill(game, c, "sorcery") * 6.0
	else:
		var holy := 0.0
		for r in Regiments.regs_of(c):
			if r.type == "silver_flame":
				holy += float(r.size) * 0.6
		force = float(Economy.realm_levy(game, c)) * 0.03 + Stats.skill(game, c, "martial") * 3.0 + Knights.power(game, c) * 0.05 + holy
		if c.traits.has("monster_bane"):
			force *= 1.5
	force *= game.rng.range_float(0.7, 1.3)
	e.strength = float(e.strength) - force
	var who: String = c.id
	if float(e.strength) <= 0.0:
		_cleanse(game, prov, who)
		c.prestige = float(c.prestige) + 50.0
	elif game.is_player(c.id):
		game.message(t(game, "msg_purge_partial", {"place": pname(game, prov), "left": roundi(e.strength)}), "info", {"type": "province", "id": prov})


static func consecrate(game: Game, c: Dictionary) -> void:
	var st := state_of(game)
	var power_v := 35.0 + Stats.skill(game, c, "learning") * 2.0 + float(c.piety) / 40.0
	for prov in realm_risen(game, c):
		var e: Dictionary = st.risen[prov]
		e.strength = float(e.strength) - power_v
		if float(e.strength) <= 0.0:
			_cleanse(game, prov, c.id)
			game.state.provinces[prov].modifiers.append({"id": "consecrated_ground", "expires": game.date + 365 * 10})


static func command_dead(game: Game, c: Dictionary) -> void:
	var list := realm_risen(game, c)
	if list.is_empty():
		return
	var prov: String = list[0]
	var e: Dictionary = state_of(game).risen[prov]
	var n := clampi(int(float(e.strength) / 35.0), 1, 4)
	var got := 0
	for i in n:
		if Regiments.recruit(game, c, "risen_dead", true) != null:
			got += 1
	state_of(game).risen.erase(prov)
	var p: Dictionary = game.state.provinces[prov]
	p.modifiers = p.modifiers.filter(func(m): return m.id != "restless_dead")
	game.stat_cache.erase("prov:" + prov)
	if game.is_player(c.id):
		game.message(t(game, "msg_command_dead", {"place": pname(game, prov), "n": got}), "good", {"type": "province", "id": prov})


# ------------------------------------------------------------ драконы

static func _dragon_month(game: Game, st: Dictionary) -> void:
	var rng := game.rng
	if st.dragons.size() < int(game.def_num("arcana.max_dragons", 2)) and rng.next() < game.def_num("arcana.dragon_wake_chance", 0.0015):
		_wake_dragon(game, true)
	for prov in st.dragons.keys():
		var d: Dictionary = st.dragons[prov]
		d.months = int(d.months) + 1
		d.hoard = float(d.hoard) + 4.0
		if rng.next() < game.def_num("arcana.dragon_burn_chance", 0.15):
			var ns: Array = game.engine.neighbors(prov).filter(func(n): return game.state.provinces.has(n))
			ns.append(prov)
			var target: String = rng.pick(ns)
			var p: Dictionary = game.state.provinces[target]
			p.development = maxi(0, int(p.development) - 1)
			p.modifiers = p.modifiers.filter(func(m): return m.id != "dragon_scorched")
			p.modifiers.append({"id": "dragon_scorched", "expires": game.date + 365 * 2})
			game.stat_cache.erase("prov:" + target)
			d.hoard = float(d.hoard) + 25.0
			notify_player(game, target, t(game, "msg_dragon_burns", {"place": pname(game, target)}), "bad")


static func _wake_dragon(game: Game, announce: bool) -> void:
	var st := state_of(game)
	var provs: Array = game.state.provinces.keys().filter(func(p):
		var d: Variant = game.content.get_def("provinces", p)
		return d != null and d.get("terrain") == "mountains" and not st.dragons.has(p))
	if provs.is_empty():
		provs = game.state.provinces.keys().filter(func(p):
			var d: Variant = game.content.get_def("provinces", p)
			return d != null and d.get("terrain") == "hills" and not st.dragons.has(p))
	if provs.is_empty():
		return
	provs.sort()
	var prov: String = game.rng.pick(provs)
	st.dragons[prov] = {"months": 0, "hoard": float(game.rng.range_int(300, 700))}
	st["lair_ver"] = int(st.get("lair_ver", 0)) + 1
	game.state.provinces[prov].modifiers.append({"id": "dragon_lair"})
	game.stat_cache.erase("prov:" + prov)
	if announce:
		var pl: Variant = game.player
		if pl != null:
			game.message(t(game, "msg_dragon_wakes", {"place": pname(game, prov)}), "war", {"type": "province", "id": prov})
			if nearest_lair(game, pl) == prov:
				game.events.trigger("arcana.0030", {"type": "character", "id": pl.id}, {"place": {"type": "province", "id": prov}})


## Логово дракона в державе персонажа или в соседней провинции. Ответ живёт
## месяц; пробуждение и гибель дракона меняют «версию» логовищ (lair_ver).
static func nearest_lair(game: Game, c: Dictionary) -> Variant:
	var st := state_of(game)
	if st.dragons.is_empty() or c.titles.is_empty():
		return null
	var key: String = "arcana:lair:%d:%s" % [int(st.get("lair_ver", 0)), c.id]
	if game.month_cache.has(key):
		return game.month_cache[key]
	var found: Variant = _find_lair(game, c, st)
	game.month_cache[key] = found
	return found


static func _find_lair(game: Game, c: Dictionary, st: Dictionary) -> Variant:
	var mine := {}
	for p in Titles.realm_counties(game, c):
		mine[p] = true
	for lair in st.dragons:
		if mine.has(lair):
			return lair
	for lair in st.dragons:
		for n in game.engine.neighbors(lair):
			if mine.has(n):
				return lair
	return null


static func hunt_dragon(game: Game, c: Dictionary) -> void:
	var lair: Variant = nearest_lair(game, c)
	if lair == null:
		return
	var st := state_of(game)
	var d: Dictionary = st.dragons[lair]
	# после любой охоты дракон два года не подпускает к логову
	d.wary_until = game.date + 365 * 2
	var chance := 2.0 + Stats.skill(game, c, "prowess") * 1.6 + Knights.power(game, c) / 60.0
	if c.traits.has("dragonslayer"):
		chance += 15.0
	if c.modifiers.any(func(m): return m.id == "dragon_preparations"):
		chance += 15.0
	if c.traits.has("battlemage"):
		chance += 12.0
	chance = clampf(chance, 3.0, 75.0)
	var scopes := {"place": {"type": "province", "id": lair}}
	if game.rng.next() * 100.0 < chance:
		var hoard := roundi(float(d.hoard))
		c.gold = float(c.gold) + hoard
		c.prestige = float(c.prestige) + 500.0
		Chars.add_trait(game, c, "dragonslayer")
		add_monster_kill(game, c, 3)
		st.dragons.erase(lair)
		st["lair_ver"] = int(st.get("lair_ver", 0)) + 1
		st.dragons_slain = int(st.dragons_slain) + 1
		var p: Dictionary = game.state.provinces[lair]
		p.modifiers = p.modifiers.filter(func(m): return m.id != "dragon_lair")
		game.stat_cache.erase("prov:" + lair)
		var pl: Variant = game.player
		if pl != null:
			game.message(t(game, "msg_dragon_slain", {"who": cname(game, c.id), "place": pname(game, lair), "gold": hoard}), "good", {"type": "character", "id": c.id})
		if game.is_player(c.id):
			game.events.trigger("arcana.0031", {"type": "character", "id": c.id}, scopes)
		game.emit("arcana.dragon_slain", {"character": c, "province": lair})
	else:
		if game.rng.chance(0.4):
			if game.is_player(c.id):
				game.events.trigger("arcana.0032", {"type": "character", "id": c.id}, scopes)
			Succession.kill_character(game, c, "dragon")
		else:
			if game.content.has("traits", "wounded"):
				Chars.add_trait(game, c, "wounded")
			c.stress = float(c.stress) + 30.0
			d.hoard = float(d.hoard) + 50.0
			if game.is_player(c.id):
				game.message(t(game, "msg_dragon_escape", {"place": pname(game, lair)}), "bad", {"type": "province", "id": lair})


# ------------------------------------------------------------ вампиры

## Жертва для кормления: пленник, иначе придворный (не родня и не вампир).
static func _victim_for(game: Game, c: Dictionary) -> Variant:
	var prisoners: Array = Prison.prisoners_of(game, c.id).filter(func(x): return not x.traits.has("vampire") and not x.traits.has("lich"))
	if not prisoners.is_empty():
		return game.rng.pick(prisoners)
	var court: Array = game.courtiers_of(c.id if not c.titles.is_empty() else str(c.liege)).filter(func(x):
		return x.id != c.id and Chars.is_adult(game, x) and not x.traits.has("vampire") and not x.traits.has("lich") \
			and not Chars.is_close_family(game, x, c) and not c.spouses.has(x.id))
	return game.rng.pick(court) if not court.is_empty() else null


static func feed(game: Game, c: Dictionary) -> void:
	var v: Variant = _victim_for(game, c)
	c.vars["blood_thirst"] = 0.0 if v != null else maxf(0.0, thirst(c) - 30.0)
	c.modifiers = c.modifiers.filter(func(m): return m.id != "bloodthirst")
	game.stat_cache.erase(c.id)
	if v == null:
		if game.is_player(c.id):
			game.message(t(game, "msg_feed_beasts"), "info")
		return
	add_potency(game, c, game.def_num("arcana.potency_per_feeding", 2))
	if game.rng.next() * 100.0 < game.def_num("arcana.feed_death_chance", 5):
		if game.is_player(c.id):
			game.message(t(game, "msg_feed_killed", {"who": cname(game, v.id)}), "bad", {"type": "character", "id": v.id})
		Succession.kill_character(game, v, "exsanguinated")
		add_potency(game, c, 2.0)
	else:
		v.modifiers.append({"id": "drained", "expires": game.date + 365})
		game.stat_cache.erase(v.id)
		if game.is_player(c.id):
			game.message(t(game, "msg_feed_ok", {"who": cname(game, v.id)}), "info", {"type": "character", "id": v.id})
	# старшие вампиры осторожнее
	witness(game, c, "secret_vampire", maxf(3.0, game.def_num("arcana.feed_witness_chance", 12) - 2.5 * (vampire_tier(game, c) - 1)))


static func frenzy(game: Game, c: Dictionary) -> void:
	if game.is_player(c.id):
		game.events.trigger("arcana.0013", {"type": "character", "id": c.id})
	var v: Variant = _victim_for(game, c)
	if v != null:
		Succession.kill_character(game, v, "exsanguinated")
		add_potency(game, c, 1.0)
	c.vars["blood_thirst"] = 20.0
	witness(game, c, "secret_vampire", 60.0)
	witness(game, c, "secret_vampire", 40.0)


## Кто-то при дворе с шансом chance% узнаёт тайну secret_type персонажа.
static func witness(game: Game, c: Dictionary, secret_type: String, chance: float) -> void:
	if game.rng.next() * 100.0 >= chance:
		return
	var sec: Variant = null
	for s in Secrets.secrets_of(c):
		if s.type == secret_type:
			sec = s
	if sec == null:
		return
	var court_of: String = c.id if not c.titles.is_empty() else str(c.liege)
	var pool: Array = game.courtiers_of(court_of).filter(func(x): return x.id != c.id and Chars.is_adult(game, x) and not sec.known.has(x.id))
	if c.liege != null:
		var l: Variant = game.ch(c.liege)
		if l != null and not sec.known.has(l.id):
			pool.append(l)
	if pool.is_empty():
		return
	var w: Dictionary = game.rng.pick(pool)
	Secrets.learn(game, w, c, sec)


# ------------------------------------------------------------ проклятия, болезни, охота на ведьм

static func cure_ailments(game: Game, c: Dictionary) -> void:
	for tr in c.traits.duplicate():
		var d: Variant = Chars.trait_def(game, tr)
		if d != null and d.get("category") == "health" and tr != "fey_touched":
			Chars.remove_trait(game, c, tr)


static func cast_curse(game: Game, c: Dictionary, target: Dictionary) -> void:
	add_power(game, c, -35.0)
	var resist := Stats.stat(game, target, "curse_resistance")
	var chance := clampf(70.0 + Stats.skill(game, c, "sorcery") * 2.0 - resist - Stats.skill(game, target, "sorcery") * 2.0, 5.0, 95.0)
	var ok := game.rng.next() * 100.0 < chance
	if ok:
		Chars.add_trait(game, target, "hexed")
	if game.is_player(c.id):
		game.message(t(game, "msg_curse_ok" if ok else "msg_curse_failed", {"who": cname(game, target.id)}), "good" if ok else "bad", {"type": "character", "id": target.id})
	if game.is_player(target.id) and ok:
		game.message(t(game, "msg_cursed_me"), "bad")
	# колдовство оставляет следы
	if game.rng.chance(0.5) and Secrets.secrets_of(c).all(func(s): return s.type != "secret_witchcraft"):
		Secrets.add_secret(game, c, "secret_witchcraft", target.id)
	if game.rng.chance(0.25):
		Opinion.add_opinion(game, target, c, "cursed_me")


static func witch_hunt(game: Game, c: Dictionary) -> void:
	var found := 0
	var burned := 0
	var pool: Array = game.courtiers_of(c.id) + game.vassals_of(c.id)
	for x in pool:
		if x.id == c.id or x.death != null:
			continue
		# тайные чудовища и колдуны — разоблачение
		for s in Secrets.secrets_of(x).duplicate():
			if ["secret_witchcraft", "secret_necromancy", "secret_vampire", "secret_werewolf"].has(s.type) and game.rng.chance(0.5):
				if Secrets.expose(game, c, x, s):
					found += 1
		# одарённых придворных хватают по подозрению (светлых целителей щадят)
		if x.titles.is_empty() and not x.traits.has("white_mage") and is_arcanist(game, x) and game.rng.chance(0.35):
			Prison.imprison(game, c, x, "witchcraft")
			burned += 1
	for v in game.vassals_of(c.id):
		if v.traits.has("zealous"):
			continue
		if game.rng.chance(0.4):
			Opinion.add_opinion(game, v, c, "witch_hunt_terror")
	if c.traits.has("compassionate"):
		c.stress = float(c.stress) + 25.0
	if game.is_player(c.id):
		game.events.trigger("arcana.0071", {"type": "character", "id": c.id})
		game.message(t(game, "msg_witch_hunt", {"found": found, "seized": burned}), "info")


# ------------------------------------------------------------ слава охотника и вершины путей

## Засчитать уничтоженных чудовищ: первая победа — «Охотник на нечисть»,
## шестая — «Гроза нечисти» (черты одной группы, старшая заменяет младшую).
static func add_monster_kill(game: Game, c: Dictionary, n: int) -> void:
	if n <= 0 or c.death != null or c.traits.has("vampire") or c.traits.has("lich"):
		return
	c.vars["monsters_slain"] = monsters_slain(c) + n
	var k := monsters_slain(c)
	var want := "monster_bane" if k >= int(game.def_num("arcana.monster_bane_at", 6)) else "monster_hunter"
	if c.traits.has(want) or c.traits.has("monster_bane"):
		return
	Chars.add_trait(game, c, want)
	if game.is_player(c.id):
		game.message(t(game, "msg_" + want), "good")


## Охота на нечисть: ловчие обыскивают двор и земли вассалов. Шанс найти
## чудовище растёт с доблестью, интригой и славой охотника; найденная тайна
## раскрывается (и засчитывается охотнику через хук secret.exposed). Если
## чудовищ нет, на охоте попадается лишь крупный зверь — немного славы.
static func hunt_monsters(game: Game, c: Dictionary) -> void:
	var chance := 0.25 + (Stats.skill(game, c, "prowess") + Stats.skill(game, c, "intrigue")) * 0.012 + monsters_slain(c) * 0.03
	var pool: Array = game.courtiers_of(c.id) + game.vassals_of(c.id)
	game.rng.shuffle(pool)
	for x in pool:
		if x.death != null or x.id == c.id:
			continue
		for s in Secrets.secrets_of(x):
			if MONSTER_SECRETS.has(s.type) and game.rng.chance(minf(0.85, chance)):
				Secrets.expose(game, c, x, s)
				return
	c.prestige = float(c.prestige) + 25.0
	if game.is_player(c.id):
		game.message(t(game, "msg_hunt_nothing"), "info")


## Светлый чародей благословляет домен: земли богатеют, нежить отступает.
static func bless_domain(game: Game, c: Dictionary) -> void:
	for prov in Titles.domain_counties(game, c):
		var p: Variant = game.state.provinces.get(prov)
		if p == null:
			continue
		p.modifiers = p.modifiers.filter(func(m): return m.id != "blessed_land")
		p.modifiers.append({"id": "blessed_land", "expires": game.date + 365 * 5})
		game.stat_cache.erase("prov:" + prov)
		var e: Variant = state_of(game).risen.get(prov)
		if e != null:
			_cleanse(game, prov, c.id)


## Огненная буря боевого мага: крупнейшее вражеское войско в державе или у её
## границ теряет часть людей.
static func firestorm(game: Game, c: Dictionary) -> void:
	var enemies := {}
	for id in Wars.enemies_of(game, c.id):
		enemies[id] = true
	if enemies.is_empty():
		return
	var near := {}
	for p in Titles.realm_counties(game, c):
		near[p] = true
		for n in game.engine.neighbors(p):
			near[n] = true
	var target: Variant = null
	for a in game.state.armies.values():
		if enemies.has(a.owner) and near.has(a.location) and (target == null or int(a.size) > int(target.size)):
			target = a
	if target == null:
		if game.is_player(c.id):
			game.message(t(game, "msg_firestorm_none"), "info")
		return
	var frac := clampf(0.15 + Stats.skill(game, c, "sorcery") * 0.008, 0.15, 0.35)
	var loss := roundi(float(target.size) * frac)
	Military._distribute([target], loss, float(target.size))
	var place: String = pname(game, target.location)
	if game.is_player(c.id) or game.is_player(target.owner):
		game.message(t(game, "msg_firestorm", {"place": place, "loss": loss}), "war", {"type": "province", "id": target.location})
	if int(target.size) < 30 and game.state.armies.has(target.id):
		Military.disband_army(game, target.id)


## Мор мёртвых: лич поднимает погосты в столице главного врага.
static func plague_of_dead(game: Game, c: Dictionary) -> void:
	var best: Variant = null
	for id in Wars.enemies_of(game, c.id):
		var e: Variant = game.ch(id)
		if e != null and not e.titles.is_empty() and (best == null or Titles.primary_tier(game, e) > Titles.primary_tier(game, best)):
			best = e
	if best == null:
		return
	var cap: Variant = best.capital if best.capital != null else Titles.capital_of(game, best)
	if cap == null:
		return
	awaken(game, str(cap), 40.0 + Stats.skill(game, c, "sorcery") * 2.0)
	if game.is_player(c.id):
		game.message(t(game, "msg_plague_dead", {"place": pname(game, str(cap))}), "good", {"type": "province", "id": str(cap)})


# ------------------------------------------------------------ чудовища и соседи

## Разоблачённые чудовища среди правителей (список на месяц).
static func known_monster_rulers(game: Game) -> Dictionary:
	return game.cached_monthly("arcana:known_monsters", func():
		var out := {}
		for c in game.rulers():
			if is_known_monster(game, c):
				out[c.id] = true
		return out)


static func is_known_monster(game: Game, c: Dictionary) -> bool:
	for tr in MONSTERS:
		if c.traits.has(tr) and Chars.trait_visible(game, c, tr, null):
			return true
	return false


## Правители по соседству с державой персонажа и внутри неё.
static func nearby_rulers(game: Game, c: Dictionary) -> Array:
	var top := Titles.top_liege(game, c)
	var key: String = "arcana:nearby:" + str(top.id)
	var hit: Variant = game.realm_cache.get(key)
	if hit != null:
		return hit
	var mine := {}
	for p in Titles.realm_counties(game, top):
		mine[p] = true
	var out := {}
	for p in mine:
		var tt: Variant = game.state.titles.get(p)
		if tt != null and tt.holder != null:
			out[tt.holder] = true
		for n in game.engine.neighbors(p):
			if mine.has(n):
				continue
			var nt: Variant = game.state.titles.get(n)
			if nt != null and nt.holder != null:
				out[nt.holder] = true
	out.erase(c.id)
	var ids := out.keys()
	game.realm_cache[key] = ids
	return ids


# ============================================================ иконки

static func _register_icons() -> void:
	var icons := {
		"moon": '<path d="M15.5 2.5 A9.5 9.5 0 1 0 21.5 16 A7.5 7.5 0 1 1 15.5 2.5 Z"/>',
		"bat": '<path d="M12 9 C11.2 7.4 10.4 7 9.6 7.8 C8 6 5 5.2 1.5 7.5 C3.8 8.4 4.8 10 4.8 11.8 C6.3 10.8 8 11.2 9 12.6 C9.6 11.5 10.6 11.2 12 14 C13.4 11.2 14.4 11.5 15 12.6 C16 11.2 17.7 10.8 19.2 11.8 C19.2 10 20.2 8.4 22.5 7.5 C19 5.2 16 6 14.4 7.8 C13.6 7 12.8 7.4 12 9 Z"/><path d="M10.8 8.6 L10.6 6.2 L11.6 7.6 Z M13.2 8.6 L13.4 6.2 L12.4 7.6 Z"/>',
		"crystal": '<circle cx="12" cy="10" r="7"/><path d="M6.5 17.5 H17.5 L16 21.5 H8 Z"/><circle cx="9.4" cy="7.4" r="1.9" fill="#fff8e0"/><path d="M8.5 12 C9.5 14 12 14.8 14.5 13.8" fill="none" stroke="#fff8e0" stroke-width="0.9"/>',
		"wand": '<path d="M3.5 21.5 L14 11 L16 13 L5.5 23.5 Z"/><path d="M17 1.5 L18.3 5.2 L22 6.5 L18.3 7.8 L17 11.5 L15.7 7.8 L12 6.5 L15.7 5.2 Z"/>',
		"dragon": '<path d="M2.5 15 C4.5 10 8.5 7 13.5 6 L12.5 2.5 L16 5.2 L17.8 2 L18.8 6.4 C20.8 7.8 22 10 21.5 12.2 L18 12.5 L19.6 14.2 L16 14.6 C14 16.2 12.2 18.6 11.2 21.8 L8 21.8 C8.4 19.2 9 17.6 9.5 16.6 C7 17.1 4.8 16.6 2.5 15 Z"/><circle cx="16.4" cy="9" r="1.15" fill="#b01010"/>',
		"wolf": '<path d="M3.5 2.5 L8.8 8 H15.2 L20.5 2.5 L19.4 11 C19.4 15 16.4 18.2 13.6 21.5 H10.4 C7.6 18.2 4.6 15 4.6 11 Z"/><path d="M8.2 12 L10.6 13.1 M15.8 12 L13.4 13.1" stroke-width="1.5" fill="none"/><path d="M10.9 17 H13.1 L12 18.6 Z" fill="#1c140a"/>',
		"blood": '<path d="M12 2.5 C14.6 7 18.6 11 18.6 15 C18.6 18.8 15.6 21.6 12 21.6 C8.4 21.6 5.4 18.8 5.4 15 C5.4 11 9.4 7 12 2.5 Z"/><path d="M8.8 15 C8.8 17 10.2 18.6 12 18.9" fill="none" stroke="#fff3c8" stroke-width="1.2"/>',
		"grave": '<path d="M6 20.5 V9 C6 5.5 8.7 3 12 3 C15.3 3 18 5.5 18 9 V20.5 Z"/><path d="M12 6.8 V15 M9 9.8 H15" fill="none" stroke-width="1.7"/><rect x="3" y="20" width="18" height="2.2" rx="0.6"/>',
		"rune": '<path d="M8 2.5 V21.5 M8 4 L16 9 L8 14 L16 21" fill="none" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>',
		"sparkle": '<path d="M10 1.5 L11.9 8.1 L18.5 10 L11.9 11.9 L10 18.5 L8.1 11.9 L1.5 10 L8.1 8.1 Z"/><path d="M18 13.5 L18.9 16.6 L22 17.5 L18.9 18.4 L18 21.5 L17.1 18.4 L14 17.5 L17.1 16.6 Z"/>',
		"ghost": '<path d="M5 21.5 V10 C5 5.5 8 2.5 12 2.5 C16 2.5 19 5.5 19 10 V21.5 L16.7 19.4 L14.3 21.5 L12 19.4 L9.7 21.5 L7.3 19.4 Z"/><circle cx="9.5" cy="10" r="1.7" fill="#1c140a"/><circle cx="14.5" cy="10" r="1.7" fill="#1c140a"/>',
		"fey": '<path d="M12 7 C10 3 3 2 3 7 C3 10.5 7 11.5 10.5 11.6 C6.5 12.5 4.5 15 6 18 C7.5 21 11 18 12 14 C13 18 16.5 21 18 18 C19.5 15 17.5 12.5 13.5 11.6 C17 11.5 21 10.5 21 7 C21 2 14 3 12 7 Z"/><path d="M12 6 V16" fill="none" stroke-width="1.4"/>',
		"potion": '<path d="M9.5 2.5 H14.5 V4 H13.5 V8.5 C17 10 19 12.5 19 15.5 C19 19 16 21.5 12 21.5 C8 21.5 5 19 5 15.5 C5 12.5 7 10 10.5 8.5 V4 H9.5 Z"/><path d="M6.5 15 C9 13.5 15 16.5 17.5 15" fill="none" stroke="#fff3c8" stroke-width="1.1"/>',
		"bolt": '<path d="M14.5 1.5 L5 13.5 H11 L9.5 22.5 L19.5 10 H13.2 Z"/>',
		"spiral": '<path d="M12 12 C13 11 14 12 13.5 13 C12.8 14.6 10.5 14.2 10 12.6 C9.3 10.3 11.5 8.5 13.6 9 C16.6 9.7 17 13.5 15.5 15.6 C13.4 18.4 8.8 17.8 7.4 14.8 C5.6 11 8.2 6.6 12.3 6.3 C17 6 20 10 19.4 14" fill="none" stroke-width="2.2" stroke-linecap="round"/>',
		"candle": '<rect x="9" y="9" width="6" height="11.5" rx="0.8"/><path d="M12 2.5 C13.5 4.5 14 5.6 14 6.5 C14 7.6 13.1 8.3 12 8.3 C10.9 8.3 10 7.6 10 6.5 C10 5.6 10.5 4.5 12 2.5 Z" fill="#fff0b0"/><rect x="6.5" y="20" width="11" height="2.2" rx="0.6"/>',
		"dove": '<path d="M2.5 13 C5.5 13 7.8 11.5 9.4 9 C10.4 6 13 4.4 15.5 5 L18.2 3.4 L17.6 6 C19.1 7.5 19.6 10 18.6 12.5 C17 16.5 12.5 19 7 18.5 L4.5 21.2 L5 17.5 C3.4 16.5 2.5 15 2.5 13 Z"/><circle cx="16" cy="7.5" r="0.9" fill="#1c140a"/>',
		"fountain": '<path d="M11 3.5 C11 2.6 13 2.6 13 3.5 V8 H11 Z"/><path d="M6 8.2 H18 C17.4 10.4 15 11.6 12 11.6 C9 11.6 6.6 10.4 6 8.2 Z"/><path d="M11 11.5 H13 V16 H11 Z"/><path d="M3 16 H21 C20.6 19.6 16.8 21.6 12 21.6 C7.2 21.6 3.4 19.6 3 16 Z"/><path d="M7 7.5 C6.4 6 5.2 5.4 4 5.6 M17 7.5 C17.6 6 18.8 5.4 20 5.6" fill="none" stroke-width="1.3" stroke-linecap="round"/>',
		"serpent": '<path d="M17.5 3 C20.5 3 21.6 6.2 19.6 8 C17.6 9.8 13 9.4 9.4 10.6 C5.6 11.9 5.4 15 8.6 15.6 C11.4 16.1 15.2 14.6 17.4 15.6 C19.8 16.7 19 20.6 15.6 21.3 C12.6 21.9 7.2 21.4 3.5 20.2 C7.4 20.1 12 20.2 14.4 19.4 C16.4 18.7 16 17.2 14 17.4 C11.4 17.6 8.2 18.6 5.8 17.4 C2.6 15.8 3 11 7.4 9 C11 7.4 15.6 7.6 17.3 6.6 C18.3 6 18 5 16.8 4.9 Z"/><circle cx="18.2" cy="4.8" r="0.7" fill="#1c140a"/>',
		"tomb_hand": '<path d="M3 21.5 H21 V19 H3 Z"/><path d="M9 19 V10 C9 9 10.5 9 10.5 10 V14 V6.5 C10.5 5.5 12 5.5 12 6.5 V13 V5.5 C12 4.5 13.5 4.5 13.5 5.5 V13 V7 C13.5 6 15 6 15 7 V15 C15 17 14 19 14 19 Z"/>',
	}
	for k in icons:
		Icons.register(k, icons[k])
	var emoji := {
		"🌙": "moon", "🌑": "moon", "🦇": "bat", "🔮": "crystal", "🪄": "wand", "🐉": "dragon", "🐲": "dragon",
		"🐺": "wolf", "🩸": "blood", "🪦": "grave", "✨": "sparkle", "🌠": "sparkle", "👻": "ghost", "🧚": "fey",
		"🌸": "fey", "🧪": "potion", "⚡": "bolt", "🌩": "bolt", "🌩️": "bolt", "🌦": "bolt", "🌀": "spiral",
		"🕯": "candle", "🕯️": "candle", "🕊": "dove", "🕊️": "dove", "🤲": "heart", "🧟": "tomb_hand",
		"ᚱ": "rune", "🧶": "rune", "⛲": "fountain", "🐍": "serpent", "⚗": "potion", "⚗️": "potion", "💎": "sparkle", "🌾": "leaf", "🌕": "moon",
	}
	for k in emoji:
		Icons.EMOJI[k] = emoji[k]


# ============================================================ интерфейс

func _register_ui(api: ModApi) -> void:
	api.ui.map_modes.register("arcana", {
		"id": "arcana",
		"name": {"ru": "Тьма", "en": "Darkness"},
		"icon": "🌑",
		"order": 95,
		"color": func(game: Game, p: String) -> Variant:
			var st := state_of(game)
			var e: Variant = st.risen.get(p)
			if e != null:
				return Portraits.mix("#6a7a4a", "#16200e", clampf(float(e.strength) / 120.0, 0.0, 1.0))
			if st.dragons.has(p):
				return "#c0501a"
			var pm: Variant = game.state.provinces.get(p)
			if pm != null:
				for m in pm.modifiers:
					match m.id:
						"dragon_scorched": return "#8a4a24"
						"haunted_ground": return "#7a8a6e"
						"consecrated_ground": return "#e0d6a8"
						"ancient_barrow": return "#6e5e82"
						"fey_hills": return "#3a8a7a"
			return "#b8b0a0",
		"tooltip": func(game: Game, p: String) -> Variant: return _place_text(game, p, false),
	}, api.owner)

	api.ui.province_sections.register("arcana", {
		"id": "arcana",
		"title": {"ru": "Тайное", "en": "The Unseen"},
		"render": func(game: Game, prov: String, _ui: Object) -> Variant: return _place_text(game, prov, true),
	}, api.owner)

	api.ui.top_bar.register("arcana_power", {
		"id": "arcana_power",
		"order": 20,
		"render": func(game: Game) -> Variant:
			var p: Variant = game.player
			if p == null or not is_arcanist(game, p):
				return null
			return {"icon": "🔮", "text": "%d/%d" % [roundi(power(p)), roundi(power_max(game, p))],
				"tooltip": BB.title(t(game, "power_title")) + "\n" + t(game, "power_tip")},
	}, api.owner)
	api.ui.top_bar.register("arcana_thirst", {
		"id": "arcana_thirst",
		"order": 21,
		"render": func(game: Game) -> Variant:
			var p: Variant = game.player
			if p == null or not p.traits.has("vampire"):
				return null
			return {"icon": "🩸", "text": "%d%%" % roundi(thirst(p)), "tooltip": BB.title(t(game, "thirst_title")) + "\n" + t(game, "thirst_tip")
				+ "\n\n" + BB.b(t(game, "potency_title") + ": " + t(game, "vampire_tier_%d" % vampire_tier(game, p)))},
	}, api.owner)

	api.ui.alerts.register("arcana_dead", {
		"id": "arcana_dead",
		"check": func(game: Game) -> Variant:
			var p: Variant = game.player
			if p == null:
				return null
			var list := realm_risen(game, p)
			if list.is_empty():
				return null
			return {"icon": "💀", "kind": "bad", "text": t(game, "alert_dead", {"place": pname(game, list[0]), "n": list.size()}),
				"action": {"province": list[0]}},
	}, api.owner)
	api.ui.alerts.register("arcana_thirst", {
		"id": "arcana_thirst",
		"check": func(game: Game) -> Variant:
			var p: Variant = game.player
			if p == null or not p.traits.has("vampire") or thirst(p) < 60.0:
				return null
			return {"icon": "🩸", "kind": "bad", "text": t(game, "alert_thirst"), "action": {"tab": "decisions"}},
	}, api.owner)
	api.ui.alerts.register("arcana_dragon", {
		"id": "arcana_dragon",
		"check": func(game: Game) -> Variant:
			var p: Variant = game.player
			if p == null:
				return null
			var lair: Variant = nearest_lair(game, p)
			if lair == null:
				return null
			return {"icon": "🐉", "kind": "info", "text": t(game, "alert_dragon", {"place": pname(game, lair)}), "action": {"province": lair}},
	}, api.owner)
	api.ui.alerts.register("arcana_power_full", {
		"id": "arcana_power_full",
		"check": func(game: Game) -> Variant:
			var p: Variant = game.player
			if p == null or not is_arcanist(game, p) or power(p) < power_max(game, p) - 0.5:
				return null
			return {"icon": "✨", "kind": "good", "text": t(game, "alert_power_full"), "action": {"tab": "mod:arcana"}},
	}, api.owner)

	api.ui.panels.register("arcana", {
		"id": "arcana",
		"name": {"ru": "Тайное", "en": "The Unseen"},
		"icon": "🔮",
		"order": 60,
		"render": func(game: Game, ui: Object) -> Control: return _panel(game, ui),
	}, api.owner)


## Что тайного в провинции: мертвецы, дракон, курган, холмы фей.
static func _place_text(game: Game, prov: String, icons: bool) -> Variant:
	var st := state_of(game)
	var lines := PackedStringArray()
	var e: Variant = st.risen.get(prov)
	if e != null:
		lines.append(("💀 " if icons else "") + t(game, "tip_risen", {"n": roundi(e.strength)}))
	if st.dragons.has(prov):
		lines.append(("🐉 " if icons else "") + t(game, "tip_dragon", {"gold": roundi(st.dragons[prov].hoard)}))
	if st.barrows.has(prov):
		lines.append(("🪦 " if icons else "") + t(game, "tip_barrow"))
	if st.fey.has(prov):
		lines.append(("🧚 " if icons else "") + t(game, "tip_fey"))
	return "\n".join(lines) if not lines.is_empty() else null


static func _panel(game: Game, ui: Object) -> Control:
	var root := K.vbox([], 10)
	var p: Variant = game.player
	var st := state_of(game)
	# ---- сам игрок
	if p != null:
		var me := K.vbox([], 4)
		if is_arcanist(game, p):
			me.add_child(K.rich("%s %s" % [BB.icon("🔮"), BB.b(t(game, "power_title"))]))
			me.add_child(K.bar(power(p), power_max(game, p), Color("#7a6ad0"), 10, "%d / %d" % [roundi(power(p)), roundi(power_max(game, p))]))
			me.add_child(K.para(t(game, "power_tip"), "MutedLabel"))
		else:
			me.add_child(K.para(t(game, "no_gift"), "MutedLabel"))
		if p.traits.has("vampire"):
			me.add_child(K.rich("%s %s" % [BB.icon("🩸"), BB.b(t(game, "thirst_title"))]))
			me.add_child(K.bar(thirst(p), 100.0, Color("#a01828"), 10, "%d%%" % roundi(thirst(p))))
			me.add_child(K.para(t(game, "thirst_tip"), "MutedLabel"))
			# путь крови: уровень, сила до следующего, открытые силы
			var tier := vampire_tier(game, p)
			var steps: Array = game.def_val("arcana.vampire_tiers", [20, 50, 90])
			me.add_child(K.rich("%s %s — %s" % [BB.icon("🦇"), BB.b(t(game, "potency_title")), t(game, "vampire_tier_%d" % tier)]))
			if tier <= steps.size():
				var lo := 0.0 if tier == 1 else Data.num(steps[tier - 2])
				var hi := Data.num(steps[tier - 1])
				me.add_child(K.bar(potency(p) - lo, hi - lo, Color("#6a1830"), 8, t(game, "potency_next", {"n": roundi(hi - potency(p)), "tier": t(game, "vampire_tier_%d" % (tier + 1))})))
			me.add_child(K.para(t(game, "vampire_powers_%d" % tier), "MutedLabel"))
		if p.traits.has("lycanthrope"):
			var b := beast(p)
			var stage := _wolf_stage(b)
			me.add_child(K.rich("%s %s — %s" % [BB.icon("🐺"), BB.b(t(game, "beast_title")), t(game, "stage_" + (stage if stage != "" else "wolf_torn"))]))
			me.add_child(K.bar(b + 100.0, 200.0, Color("#a07a3a") if b >= 0 else Color("#7a2a1a"), 8, "%+d" % roundi(b)))
			me.add_child(K.para(t(game, "wolf_tip"), "MutedLabel"))
		if monsters_slain(p) > 0 or p.traits.has("monster_hunter") or p.traits.has("monster_bane"):
			var need := int(game.def_num("arcana.monster_bane_at", 6))
			var k := monsters_slain(p)
			me.add_child(K.rich("%s %s: %d" % [BB.icon("🗡"), BB.b(t(game, "hunter_title")), k]))
			if k < need:
				me.add_child(K.para(t(game, "hunter_next", {"n": need - k}), "MutedLabel"))
		me.add_child(K.button(t(game, "open_decisions"), func(): ui.open_tab("decisions"), {"icon": "scroll"}))
		root.add_child(K.section(t(game, "section_you"), [me], "🔮"))
	# ---- тёмные места
	var places := K.vbox([], 3)
	var risen_ids: Array = st.risen.keys()
	risen_ids.sort_custom(func(a, b): return float(st.risen[a].strength) > float(st.risen[b].strength))
	for prov in risen_ids:
		var pid: String = prov
		places.add_child(K.button("%s — %s" % [pname(game, prov), t(game, "tip_risen", {"n": roundi(st.risen[prov].strength)})],
			func(): ui.open_province(pid, true), {"variation": "FlatButton", "icon": "💀", "align": HORIZONTAL_ALIGNMENT_LEFT}))
	for prov in st.dragons:
		var pid: String = prov
		places.add_child(K.button("%s — %s" % [pname(game, prov), t(game, "tip_dragon", {"gold": roundi(st.dragons[prov].hoard)})],
			func(): ui.open_province(pid, true), {"variation": "FlatButton", "icon": "🐉", "align": HORIZONTAL_ALIGNMENT_LEFT}))
	if places.get_child_count() == 0:
		places.add_child(K.label(t(game, "world_quiet"), "MutedLabel"))
	root.add_child(K.section(t(game, "section_places"), [places], "🌑"))
	# ---- разоблачённые чудовища
	var monsters := K.vbox([], 3)
	for c in game.living():
		if is_known_monster(game, c):
			monsters.add_child(W.char_row(ui, c, [", ".join(MONSTERS.filter(func(x): return c.traits.has(x) and Chars.trait_visible(game, c, x, null)).map(func(x): return game.name_of("traits", x)))], [], 40))
			if monsters.get_child_count() >= 12:
				break
	if monsters.get_child_count() == 0:
		monsters.add_child(K.label(t(game, "no_monsters"), "MutedLabel"))
	root.add_child(K.section(t(game, "section_monsters"), [monsters], "🦇"))
	# ---- летопись
	root.add_child(K.para(t(game, "chronicle", {"risen": st.outbreaks, "dragons": st.dragons_slain}), "SmallLabel"))
	return root

extends RefCounted
## Мод «Киберимпланты». Импланты вживляются в системы тела (лобная кора,
## глаза, кровеносная и нервная системы, кожа, скелет, руки, кисти, ноги,
## операционная система); каждая система вмещает несколько имплантов.
## Модификаторы имплантов действуют на носителя, но каждый съедает
## человечность: ниже unstable_below — стресс, ниже psychosis_below —
## риск киберпсихоза. Операцию делает потрошитель — за золото и с риском
## осложнений; кибер-рука или нога заменяет потерянную (лечит maimed).
## Набожные не любят тех, в ком много хрома.
##
## Состояние: game.mod_data("cyberware") = {implants: {персонаж: [{id, date}]}}.
## Хуки: cyberware.installed / cyberware.removed — {character, implant}.

const MOD := "cyberware"
const CyberUI := preload("cyber_ui.gd")


static func _n(game: Game, key: String, def: float) -> float:
	return game.def_num("cyberware." + key, def)


static func state_of(game: Game) -> Dictionary:
	return game.mod_data(MOD, func(): return {"implants": {}})


static func def_of(game: Game, iid: Variant) -> Variant:
	return game.content.get_def("implants", str(iid)) if iid != null else null


## Импланты персонажа: [{id, date}].
static func implants_of(game: Game, c: Dictionary) -> Array:
	var st: Dictionary = state_of(game).implants
	return st.get(c.id, [])


static func has_implant(game: Game, c: Dictionary, iid: String) -> bool:
	return implants_of(game, c).any(func(x): return x.id == iid)


static func in_system(game: Game, c: Dictionary, sys: String) -> Array:
	return implants_of(game, c).filter(func(x):
		var d: Variant = def_of(game, x.id)
		return d != null and str(d.get("system")) == sys)


static func systems(game: Game) -> Array:
	var out: Array = game.content.all("cyber_systems")
	Data.sort_by(out, func(s): return Data.num(s.get("order")))
	return out


static func capacity(game: Game, sys: String) -> int:
	var d: Variant = game.content.get_def("cyber_systems", sys)
	return int(Data.num(d.get("slots"), 1)) if d != null else 0


## Наибольшая человечность (с поправкой черт) и сколько съели импланты.
static func humanity_max(game: Game, c: Dictionary) -> float:
	return _n(game, "humanity_base", 100) + Stats.stat(game, c, "humanity")


static func humanity_used(game: Game, c: Dictionary) -> float:
	var s := 0.0
	for x in implants_of(game, c):
		var d: Variant = def_of(game, x.id)
		if d != null:
			s += Data.num(d.get("humanity"))
	return s


static func humanity(game: Game, c: Dictionary) -> float:
	return humanity_max(game, c) - humanity_used(game, c)


## Состояние: stable | unstable | critical | psycho.
static func status(game: Game, c: Dictionary) -> String:
	if c.traits.has("cyberpsychosis"):
		return "psycho"
	var h := humanity(game, c)
	if h < _n(game, "psychosis_below", 20):
		return "critical"
	if h < _n(game, "unstable_below", 40):
		return "unstable"
	return "stable"


static func surgery_risk(game: Game, c: Dictionary) -> float:
	return maxf(_n(game, "surgery_risk_min", 0.03), _n(game, "surgery_risk", 0.12) - Stats.skill(game, c, "learning") * 0.005)


## Почему нельзя вживить (пусто — можно).
static func blockers(game: Game, c: Dictionary, iid: String, free: bool = false) -> Array:
	var g := game
	var d: Variant = def_of(g, iid)
	if d == null:
		return [g.loc.t("cyber.err_unknown")]
	var out := []
	if has_implant(g, c, iid):
		out.append(g.loc.t("cyber.err_have"))
	var sys := str(d.get("system"))
	if in_system(g, c, sys).size() >= capacity(g, sys):
		out.append(g.loc.t("cyber.err_full", {"system": g.name_of("cyber_systems", sys)}))
	if not free and float(c.gold) < Data.num(d.get("price")):
		out.append(g.loc.t("cyber.err_gold", {"n": roundi(Data.num(d.get("price")))}))
	if humanity(g, c) - Data.num(d.get("humanity")) < 0.0:
		out.append(g.loc.t("cyber.err_humanity"))
	if not Chars.is_adult(g, c):
		out.append(g.loc.t("cyber.err_child"))
	return out


## Вживить имплант. free — без оплаты (событие, скрипт). Возвращает
## "ok", "complication" или "" (нельзя).
static func install(game: Game, c: Dictionary, iid: String, free: bool = false) -> String:
	if not blockers(game, c, iid, free).is_empty():
		return ""
	var d: Dictionary = def_of(game, iid)
	if not free:
		c.gold = float(c.gold) - Data.num(d.get("price"))
	var st: Dictionary = state_of(game).implants
	if not st.has(c.id):
		st[c.id] = []
	st[c.id].append({"id": iid, "date": game.date})
	# кибер-рука или нога вместо потерянной
	for t in Data.as_array(d.get("cures")):
		if c.traits.has(t):
			Chars.remove_trait(game, c, str(t))
	var result := "ok"
	if game.rng.chance(surgery_risk(game, c)):
		result = "complication"
		Chars.add_trait(game, c, "wounded")
		Chars.change_stress(game, c, 10, "cyberware")
	game.stat_cache.erase(c.id)
	game.mark_chars_dirty([c.id])
	if game.is_player(c.id):
		game.message(game.loc.t("cyber.msg_installed" + ("_bad" if result == "complication" else ""), {"name": game.name_of("implants", iid)}),
			"bad" if result == "complication" else "good", {"type": "character", "id": c.id}, [c.id])
	game.emit("cyberware.installed", {"character": c, "implant": iid})
	return result


static func removal_cost(game: Game) -> float:
	return _n(game, "removal_cost", 30)


## Извлечь имплант (paid — игрок платит за операцию).
static func remove(game: Game, c: Dictionary, iid: String, paid: bool = false) -> bool:
	var list: Array = state_of(game).implants.get(c.id, [])
	for i in list.size():
		if list[i].id == iid:
			if paid:
				if float(c.gold) < removal_cost(game):
					return false
				c.gold = float(c.gold) - removal_cost(game)
			list.remove_at(i)
			if list.is_empty():
				state_of(game).implants.erase(c.id)
			Chars.change_stress(game, c, _n(game, "removal_stress", 8), "cyberware")
			game.stat_cache.erase(c.id)
			game.mark_chars_dirty([c.id])
			game.emit("cyberware.removed", {"character": c, "implant": iid})
			return true
	return false


## Суммарные модификаторы имплантов.
static func total_modifiers(game: Game, c: Dictionary) -> Dictionary:
	var out := {}
	for x in implants_of(game, c):
		var d: Variant = def_of(game, x.id)
		if d == null or not (d.get("modifiers") is Dictionary):
			continue
		for k in d.modifiers:
			out[k] = float(out.get(k, 0.0)) + float(d.modifiers[k])
	return out


# ------------------------------------------------------------ ход времени

static func _monthly_char(game: Game, c: Dictionary) -> void:
	var st: Dictionary = state_of(game).implants
	if st.has(c.id):
		_condition(game, c)
	elif not c.titles.is_empty() and not game.is_player(c.id) and float(c.gold) > 110.0 and game.rng.chance(_n(game, "ai_chance", 0.03)):
		_ai_buy(game, c)
	if st.has(c.id) and not game.is_player(c.id) and not c.titles.is_empty() and float(c.gold) > 250.0 and game.rng.chance(_n(game, "ai_chance", 0.03)):
		_ai_buy(game, c)


## Человечность на исходе: стресс, киберпсихоз; вернувшему человечность — исцеление.
static func _condition(game: Game, c: Dictionary) -> void:
	var h := humanity(game, c)
	if c.traits.has("cyberpsychosis"):
		if h >= _n(game, "unstable_below", 40) and game.rng.chance(_n(game, "recovery_chance", 0.12)):
			Chars.remove_trait(game, c, "cyberpsychosis")
			if game.is_player(c.id):
				game.message(game.loc.t("cyber.msg_recovered"), "good", {"type": "character", "id": c.id}, [c.id])
		return
	if h < _n(game, "unstable_below", 40):
		Chars.change_stress(game, c, _n(game, "unstable_stress", 4), "cyberware")
	if h < _n(game, "psychosis_below", 20) and game.rng.chance(_n(game, "psychosis_chance", 0.06)):
		Chars.add_trait(game, c, "cyberpsychosis")
		game.stat_cache.erase(c.id)
		var p: Variant = game.player
		if p != null and (c.id == p.id or c.liege == p.id):
			game.message(game.loc.t("cyber.msg_psycho" + ("_own" if c.id == p.id else ""), {"who": game.scope_name({"type": "character", "id": c.id})}), "bad",
				{"type": "character", "id": c.id}, [c.id])
		game.emit("cyberware.psychosis", {"character": c})


## Склонность ИИ по чертам (ai.<k> в определениях черт).
static func _ai_trait(game: Game, c: Dictionary, k: String) -> float:
	var v := 0.0
	for tr in c.traits:
		var d: Variant = game.content.get_def("traits", tr)
		if d != null and d.get("ai") is Dictionary:
			v += Data.num(d.ai.get(k))
	return v


## ИИ: имплант по характеру — смелым боевой, интриганам кибердеку, учёным чипы.
static func _ai_buy(game: Game, c: Dictionary) -> void:
	# смелые и гневливые не боятся потерять себя
	var minh := _n(game, "ai_min_humanity", 55) - 25.0 * clampf(_ai_trait(game, c, "boldness"), 0.0, 1.0)
	var opts := []
	for d in game.content.all("implants"):
		var price := Data.num(d.get("price"))
		if float(c.gold) < price * 1.5 + 30.0 or humanity(game, c) - Data.num(d.get("humanity")) < minh:
			continue
		if not blockers(game, c, d.id).is_empty():
			continue
		var w := 1.0
		var mods: Dictionary = d.get("modifiers", {})
		for k in mods:
			var v := float(mods[k])
			if k in ["prowess", "martial", "commander_advantage", "battle_survival"]:
				w += v * (1.0 + maxf(0.0, _ai_trait(game, c, "boldness"))) * 0.2
			elif k in ["intrigue", "scheme_power", "scheme_defense"]:
				w += v * 0.15 * (1.0 + Stats.skill(game, c, "intrigue") / 10.0)
			elif k in ["health", "stress_gain_mult"]:
				w += absf(v) * 2.0
			else:
				w += absf(v) * 0.1
		# увечному — в первую очередь кибер-конечность
		for t in Data.as_array(d.get("cures")):
			if c.traits.has(t):
				w *= 6.0
		opts.append({"id": d.id, "w": w})
	var pick: Variant = game.rng.weighted(opts, func(o): return o.w)
	if pick != null:
		install(game, c, pick.id)


# ------------------------------------------------------------ установка

func init(api: ModApi) -> void:
	CyberUI.register_icons()
	api.add_system({"id": "cyberware", "order": 66, "on_character_month": _monthly_char})
	# модификаторы имплантов
	api.registries.modifier_providers.register("cyberware", {"fn": func(game: Game, c: Dictionary) -> Variant:
		var st: Dictionary = state_of(game).implants
		if not st.has(c.id):
			return null
		var out := []
		for x in st[c.id]:
			var d: Variant = def_of(game, x.id)
			if d != null and d.get("modifiers") is Dictionary:
				var iid: String = x.id
				out.append({"label": func(): return game.name_of("implants", iid), "modifiers": d.modifiers})
		return out if not out.is_empty() else null
	}, api.owner)
	# набожные не терпят хрома
	api.registries.opinion_providers.register("cyberware", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		var st: Dictionary = state_of(game).implants
		if not st.has(b.id) or not a.traits.has("zealous"):
			return null
		if st[b.id].size() < int(_n(game, "zealot_threshold", 2)):
			return null
		return {"label": game.loc.t("cyber.opinion_chrome"), "value": _n(game, "zealot_opinion", -15)}
	}, api.owner)
	api.on("character.death", func(p):
		state_of(p.game).implants.erase(p.character.id))

	# --- скрипт
	api.trigger("has_implant", {"scopes": ["character"], "doc": "Есть имплант (yes/no или id): has_implant: cyberdeck", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c == null:
			return false
		if arg is bool or str(arg) in ["yes", "no"]:
			return (not implants_of(ctx.game, c).is_empty()) == ScriptContext.is_yes(arg)
		return has_implant(ctx.game, c, str(arg)),
		"describe": func(ctx, _s, arg):
			if arg is bool or str(arg) in ["yes", "no"]:
				return ctx.game.loc.t("cyber.tr_has_any" + ("" if ScriptContext.is_yes(arg) else ".not"))
			return ctx.game.loc.t("cyber.tr_has", {"value": ctx.game.name_of("implants", str(arg))}),
	})
	api.value("num_implants", {"scopes": ["character"], "doc": "Число имплантов", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return float(implants_of(ctx.game, c).size()) if c != null else 0.0
	})
	api.value("humanity", {"scopes": ["character"], "doc": "Оставшаяся человечность", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return humanity(ctx.game, c) if c != null else 0.0
	})
	api.effect("install_implant", {"scopes": ["character"], "doc": "Вживить имплант бесплатно: install_implant: hawk_optics", "apply": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c != null:
			install(ctx.game, c, str(arg), true),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("cyber.fx_install", {"who": ctx.game.scope_name(s), "value": ctx.game.name_of("implants", str(arg))}),
	})
	api.effect("remove_implant", {"scopes": ["character"], "doc": "Извлечь имплант: remove_implant: <id> | random", "apply": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c == null:
			return
		var list := implants_of(ctx.game, c)
		if list.is_empty():
			return
		var iid := str(arg)
		if iid == "random":
			iid = str(ctx.game.rng.pick(list).id)
		remove(ctx.game, c, iid),
		"describe": func(ctx, s, arg):
			if str(arg) == "random":
				return ctx.game.loc.t("cyber.fx_remove_random", {"who": ctx.game.scope_name(s)})
			return ctx.game.loc.t("cyber.fx_remove", {"who": ctx.game.scope_name(s), "value": ctx.game.name_of("implants", str(arg))}),
	})

	# --- интерфейс: экран имплантов — отдельный раздел и вкладка персонажа
	api.ui.panels.register("cyberware", {
		"id": "cyberware", "name": {"ru": "Импланты", "en": "Cyberware"}, "icon": "chip", "order": 20,
		"render": func(game: Game, ui: Object) -> Control:
			return CyberUI.build(game, str(game.state.player), ui),
	}, api.owner)
	api.ui.character_tabs.register("cyberware", {
		"id": "cyberware", "name": {"ru": "Импланты", "en": "Cyberware"}, "icon": "chip", "order": 10,
		"shown": func(game: Game, c: Dictionary) -> bool:
			return c.death == null and (game.is_player(c.id) or not implants_of(game, c).is_empty()),
		"badge": func(game: Game, c: Dictionary) -> int: return implants_of(game, c).size(),
		"render": func(game: Game, cid: String, ui: Object) -> Control: return CyberUI.build(game, cid, ui),
	}, api.owner)
	api.ui.alerts.register("cyber_humanity", {"id": "cyber_humanity", "order": 18, "check": func(game: Game) -> Variant:
		var p: Variant = game.player
		if p == null or not state_of(game).implants.has(p.id):
			return null
		var stt := status(game, p)
		if stt == "stable":
			return null
		return {"icon": "glitch", "kind": "bad", "text": game.loc.t("cyber.alert_" + stt, {"n": roundi(humanity(game, p))}), "action": {"tab": "mod:cyberware"}},
	}, api.owner)
	api.log("импланты подключены: %d в %d системах тела" % [api.content.all("implants").size(), api.content.all("cyber_systems").size()])

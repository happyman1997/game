extends RefCounted
## Мод «Железо и плоть». Цирюльники-хирурги и мастера вживляют в людей
## звёздное железо, серебро, руны и эликсиры: в голову, очи, уста, сердце,
## кровь, жилы, кожу, кости, руки и ноги; каждая часть тела вмещает
## несколько вживлений. Их модификаторы действуют на носителя, но каждое
## подтачивает стойкость: ниже troubled_below — смятение и стресс, ниже
## possession_below — риск одержимости. Операция стоит золота и грозит
## осложнениями; железная рука или нога заменяет потерянную (лечит maimed).
## Набожные косятся на тех, в ком много железа; одержимого отчитывает
## экзорцист.
##
## Состояние: game.mod_data("grafts") = {grafts: {персонаж: [{id, date}]}}.
## Хуки: grafts.installed / grafts.removed — {character, graft};
## grafts.possession — {character}.

const MOD := "grafts"
const AnatomyUI := preload("anatomy_ui.gd")


static func _n(game: Game, key: String, def: float) -> float:
	return game.def_num("grafts." + key, def)


static func state_of(game: Game) -> Dictionary:
	return game.mod_data(MOD, func(): return {"grafts": {}})


static func def_of(game: Game, gid: Variant) -> Variant:
	return game.content.get_def("grafts", str(gid)) if gid != null else null


## Вживления персонажа: [{id, date}].
static func grafts_of(game: Game, c: Dictionary) -> Array:
	return state_of(game).grafts.get(c.id, [])


static func has_graft(game: Game, c: Dictionary, gid: String) -> bool:
	return grafts_of(game, c).any(func(x): return x.id == gid)


static func in_part(game: Game, c: Dictionary, part: String) -> Array:
	return grafts_of(game, c).filter(func(x):
		var d: Variant = def_of(game, x.id)
		return d != null and str(d.get("part")) == part)


static func parts(game: Game) -> Array:
	var out: Array = game.content.all("body_parts")
	Data.sort_by(out, func(s): return Data.num(s.get("order")))
	return out


static func capacity(game: Game, part: String) -> int:
	var d: Variant = game.content.get_def("body_parts", part)
	return int(Data.num(d.get("slots"), 1)) if d != null else 0


## Стойкость (с поправкой черт) и сколько её подтачивают вживления.
static func fortitude_max(game: Game, c: Dictionary) -> float:
	return _n(game, "fortitude_base", 100) + Stats.stat(game, c, "fortitude")


static func fortitude_used(game: Game, c: Dictionary) -> float:
	var s := 0.0
	for x in grafts_of(game, c):
		var d: Variant = def_of(game, x.id)
		if d != null:
			s += Data.num(d.get("fortitude"))
	return s


static func fortitude(game: Game, c: Dictionary) -> float:
	return fortitude_max(game, c) - fortitude_used(game, c)


## Состояние стойкости: whole | troubled | brink | possessed.
static func status(game: Game, c: Dictionary) -> String:
	if c.traits.has("iron_possession"):
		return "possessed"
	var h := fortitude(game, c)
	if h < _n(game, "possession_below", 20):
		return "brink"
	if h < _n(game, "troubled_below", 40):
		return "troubled"
	return "whole"


static func surgery_risk(game: Game, c: Dictionary) -> float:
	return maxf(_n(game, "surgery_risk_min", 0.03), _n(game, "surgery_risk", 0.12) - Stats.skill(game, c, "learning") * 0.005)


## Почему нельзя вживить (пусто — можно).
static func blockers(game: Game, c: Dictionary, gid: String, free: bool = false) -> Array:
	var g := game
	var d: Variant = def_of(g, gid)
	if d == null:
		return [g.loc.t("grafts.err_unknown")]
	var out := []
	if has_graft(g, c, gid):
		out.append(g.loc.t("grafts.err_have"))
	var part := str(d.get("part"))
	if in_part(g, c, part).size() >= capacity(g, part):
		out.append(g.loc.t("grafts.err_full", {"part": g.name_of("body_parts", part)}))
	if not free and float(c.gold) < Data.num(d.get("price")):
		out.append(g.loc.t("grafts.err_gold", {"n": roundi(Data.num(d.get("price")))}))
	if fortitude(g, c) - Data.num(d.get("fortitude")) < 0.0:
		out.append(g.loc.t("grafts.err_fortitude"))
	if not Chars.is_adult(g, c):
		out.append(g.loc.t("grafts.err_child"))
	return out


## Вживить. free — без оплаты (событие, скрипт). Возвращает "ok",
## "complication" или "" (нельзя).
static func install(game: Game, c: Dictionary, gid: String, free: bool = false) -> String:
	if not blockers(game, c, gid, free).is_empty():
		return ""
	var d: Dictionary = def_of(game, gid)
	if not free:
		c.gold = float(c.gold) - Data.num(d.get("price"))
	var st: Dictionary = state_of(game).grafts
	if not st.has(c.id):
		st[c.id] = []
	st[c.id].append({"id": gid, "date": game.date})
	# железная рука или нога вместо потерянной
	for t in Data.as_array(d.get("cures")):
		if c.traits.has(t):
			Chars.remove_trait(game, c, str(t))
	var result := "ok"
	if game.rng.chance(surgery_risk(game, c)):
		result = "complication"
		Chars.add_trait(game, c, "wounded")
		Chars.change_stress(game, c, 10, "grafts")
	game.stat_cache.erase(c.id)
	game.mark_chars_dirty([c.id])
	if game.is_player(c.id):
		game.message(game.loc.t("grafts.msg_installed" + ("_bad" if result == "complication" else ""), {"name": game.name_of("grafts", gid)}),
			"bad" if result == "complication" else "good", {"type": "character", "id": c.id}, [c.id])
	game.emit("grafts.installed", {"character": c, "graft": gid})
	return result


static func removal_cost(game: Game) -> float:
	return _n(game, "removal_cost", 30)


## Извлечь (paid — игрок платит за операцию).
static func remove(game: Game, c: Dictionary, gid: String, paid: bool = false) -> bool:
	var list: Array = state_of(game).grafts.get(c.id, [])
	for i in list.size():
		if list[i].id == gid:
			if paid:
				if float(c.gold) < removal_cost(game):
					return false
				c.gold = float(c.gold) - removal_cost(game)
			list.remove_at(i)
			if list.is_empty():
				state_of(game).grafts.erase(c.id)
			Chars.change_stress(game, c, _n(game, "removal_stress", 8), "grafts")
			game.stat_cache.erase(c.id)
			game.mark_chars_dirty([c.id])
			game.emit("grafts.removed", {"character": c, "graft": gid})
			return true
	return false


## Экзорцизм: снять одержимость за золото (благочестие растёт).
static func exorcism_cost(game: Game) -> float:
	return _n(game, "exorcism_cost", 100)


static func exorcise(game: Game, c: Dictionary) -> bool:
	if not c.traits.has("iron_possession") or float(c.gold) < exorcism_cost(game):
		return false
	c.gold = float(c.gold) - exorcism_cost(game)
	Chars.remove_trait(game, c, "iron_possession")
	c.piety = float(c.piety) + 20.0
	Chars.change_stress(game, c, 10, "grafts")
	game.stat_cache.erase(c.id)
	game.mark_chars_dirty([c.id])
	return true


## Суммарные модификаторы вживлений.
static func total_modifiers(game: Game, c: Dictionary) -> Dictionary:
	var out := {}
	for x in grafts_of(game, c):
		var d: Variant = def_of(game, x.id)
		if d == null or not (d.get("modifiers") is Dictionary):
			continue
		for k in d.modifiers:
			out[k] = float(out.get(k, 0.0)) + float(d.modifiers[k])
	return out


# ------------------------------------------------------------ ход времени

static func _monthly_char(game: Game, c: Dictionary) -> void:
	var st: Dictionary = state_of(game).grafts
	if st.has(c.id):
		_condition(game, c)
	if c.titles.is_empty() or game.is_player(c.id):
		return
	var need := 250.0 if st.has(c.id) else 110.0
	if float(c.gold) > need and game.rng.chance(_n(game, "ai_chance", 0.03)):
		_ai_buy(game, c)


## Стойкость на исходе: смятение, одержимость; вернувшему стойкость — облегчение.
static func _condition(game: Game, c: Dictionary) -> void:
	var h := fortitude(game, c)
	if c.traits.has("iron_possession"):
		if h >= _n(game, "troubled_below", 40) and game.rng.chance(_n(game, "recovery_chance", 0.12)):
			Chars.remove_trait(game, c, "iron_possession")
			if game.is_player(c.id):
				game.message(game.loc.t("grafts.msg_recovered"), "good", {"type": "character", "id": c.id}, [c.id])
		return
	if h < _n(game, "troubled_below", 40):
		Chars.change_stress(game, c, _n(game, "troubled_stress", 4), "grafts")
	if h < _n(game, "possession_below", 20) and game.rng.chance(_n(game, "possession_chance", 0.06)):
		Chars.add_trait(game, c, "iron_possession")
		game.stat_cache.erase(c.id)
		# шёпот из железа — голос Князя Пепла: пепел ложится на душу
		if game.engine.has_feature("karma"):
			Karma.add(game, c, -10.0, "iron_whisper")
		var p: Variant = game.player
		if p != null and (c.id == p.id or c.liege == p.id):
			game.message(game.loc.t("grafts.msg_possessed" + ("_own" if c.id == p.id else ""), {"who": game.scope_name({"type": "character", "id": c.id})}), "bad",
				{"type": "character", "id": c.id}, [c.id])
		game.emit("grafts.possession", {"character": c})


## Склонность ИИ по чертам (ai.<k> в определениях черт).
static func _ai_trait(game: Game, c: Dictionary, k: String) -> float:
	var v := 0.0
	for tr in c.traits:
		var d: Variant = game.content.get_def("traits", tr)
		if d != null and d.get("ai") is Dictionary:
			v += Data.num(d.ai.get(k))
	return v


## ИИ: вживление по характеру — смелым боевое, интриганам руны и тушь,
## увечным — железную руку или ногу.
static func _ai_buy(game: Game, c: Dictionary) -> void:
	# смелые и гневливые меньше боятся железа
	var minh := _n(game, "ai_min_fortitude", 55) - 25.0 * clampf(_ai_trait(game, c, "boldness"), 0.0, 1.0)
	var opts := []
	for d in game.content.all("grafts"):
		var price := Data.num(d.get("price"))
		if float(c.gold) < price * 1.5 + 30.0 or fortitude(game, c) - Data.num(d.get("fortitude")) < minh:
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
			elif k in ["monthly_piety"]:
				w += v * (1.0 + maxf(0.0, _ai_trait(game, c, "zeal"))) * 3.0
			elif k in ["health", "stress_gain_mult"]:
				w += absf(v) * 2.0
			else:
				w += absf(v) * 0.1
		for t in Data.as_array(d.get("cures")):
			if c.traits.has(t):
				w *= 6.0
		opts.append({"id": d.id, "w": w})
	var pick: Variant = game.rng.weighted(opts, func(o): return o.w)
	if pick != null:
		install(game, c, pick.id)


# ------------------------------------------------------------ установка

func init(api: ModApi) -> void:
	AnatomyUI.register_icons()
	api.add_system({"id": "grafts", "order": 66, "on_character_month": _monthly_char})
	api.registries.modifier_providers.register("grafts", {"fn": func(game: Game, c: Dictionary) -> Variant:
		var st: Dictionary = state_of(game).grafts
		if not st.has(c.id):
			return null
		var out := []
		for x in st[c.id]:
			var d: Variant = def_of(game, x.id)
			if d != null and d.get("modifiers") is Dictionary:
				var gid: String = x.id
				out.append({"label": func(): return game.name_of("grafts", gid), "modifiers": d.modifiers})
		return out if not out.is_empty() else null
	}, api.owner)
	# набожные косятся на железных людей
	api.registries.opinion_providers.register("grafts", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		var st: Dictionary = state_of(game).grafts
		if not st.has(b.id) or not a.traits.has("zealous"):
			return null
		if st[b.id].size() < int(_n(game, "zealot_threshold", 2)):
			return null
		return {"label": game.loc.t("grafts.opinion_iron"), "value": _n(game, "zealot_opinion", -15)}
	}, api.owner)
	api.on("character.death", func(p):
		state_of(p.game).grafts.erase(p.character.id))

	# --- скрипт
	api.trigger("has_graft", {"scopes": ["character"], "doc": "Есть вживление (yes/no или id): has_graft: iron_hand", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c == null:
			return false
		if arg is bool or str(arg) in ["yes", "no"]:
			return (not grafts_of(ctx.game, c).is_empty()) == ScriptContext.is_yes(arg)
		return has_graft(ctx.game, c, str(arg)),
		"describe": func(ctx, _s, arg):
			if arg is bool or str(arg) in ["yes", "no"]:
				return ctx.game.loc.t("grafts.tr_has_any" + ("" if ScriptContext.is_yes(arg) else ".not"))
			return ctx.game.loc.t("grafts.tr_has", {"value": ctx.game.name_of("grafts", str(arg))}),
	})
	api.value("num_grafts", {"scopes": ["character"], "doc": "Число вживлений", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return float(grafts_of(ctx.game, c).size()) if c != null else 0.0
	})
	api.value("fortitude", {"scopes": ["character"], "doc": "Сколько стойкости осталось (вживления её подтачивают)", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return fortitude(ctx.game, c) if c != null else 0.0
	})
	api.effect("install_graft", {"scopes": ["character"], "doc": "Вживить бесплатно: install_graft: glass_eye", "apply": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c != null:
			install(ctx.game, c, str(arg), true),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("grafts.fx_install", {"who": ctx.game.scope_name(s), "value": ctx.game.name_of("grafts", str(arg))}),
	})
	api.effect("remove_graft", {"scopes": ["character"], "doc": "Извлечь вживление: remove_graft: <id> | random", "apply": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c == null:
			return
		var list := grafts_of(ctx.game, c)
		if list.is_empty():
			return
		var gid := str(arg)
		if gid == "random":
			gid = str(ctx.game.rng.pick(list).id)
		remove(ctx.game, c, gid),
		"describe": func(ctx, s, arg):
			if str(arg) == "random":
				return ctx.game.loc.t("grafts.fx_remove_random", {"who": ctx.game.scope_name(s)})
			return ctx.game.loc.t("grafts.fx_remove", {"who": ctx.game.scope_name(s), "value": ctx.game.name_of("grafts", str(arg))}),
	})

	# --- интерфейс: анатомический лист — раздел внизу и вкладка персонажа
	api.ui.panels.register("grafts", {
		"id": "grafts", "name": {"ru": "Вживления", "en": "Grafts"}, "icon": "gauntlet", "order": 20,
		"render": func(game: Game, ui: Object) -> Control:
			return AnatomyUI.build(game, str(game.state.player), ui),
	}, api.owner)
	api.ui.character_tabs.register("grafts", {
		"id": "grafts", "name": {"ru": "Вживления", "en": "Grafts"}, "icon": "gauntlet", "order": 10,
		"shown": func(game: Game, c: Dictionary) -> bool:
			return c.death == null and (game.is_player(c.id) or not grafts_of(game, c).is_empty()),
		"badge": func(game: Game, c: Dictionary) -> int: return grafts_of(game, c).size(),
		"render": func(game: Game, cid: String, ui: Object) -> Control: return AnatomyUI.build(game, cid, ui),
	}, api.owner)
	api.ui.alerts.register("grafts_fortitude", {"id": "grafts_fortitude", "order": 18, "check": func(game: Game) -> Variant:
		var p: Variant = game.player
		if p == null or not state_of(game).grafts.has(p.id):
			return null
		var stt := status(game, p)
		if stt == "whole":
			return null
		return {"icon": "skull", "kind": "bad", "text": game.loc.t("grafts.alert_" + stt, {"n": roundi(fortitude(game, p))}), "action": {"tab": "mod:grafts"}},
	}, api.owner)
	api.log("вживления: %d в %d частях тела" % [api.content.all("grafts").size(), api.content.all("body_parts").size()])

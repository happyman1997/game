class_name Dynasties
extends EngineFeature
## Династия (как в CK3): известность рода, наследия, глава рода и младшие
## ветви — дома.
##
## Известность — престиж династии (state.dynasties[id].prestige; копится у
## корня рода — младшие ветви делят её с родом). Источники: доля престижа
## членов рода (economy.dynasty_prestige_share), каждый месяц — правители
## рода по рангу (dynasty.renown_by_tier), деяния (dynasty.renown_from_deeds:
## { <деяние>: известность }) и эффект add_dynasty_prestige. renown_total —
## сколько накоплено за всё время: от него уровень славы рода
## (dynasty.levels — пороги, названия dynasty_level.<n>, dynasty.level_prestige —
## ежемесячный престиж правителей рода по уровню).
##
## Наследия: legacy_tracks: { <ветвь>: { icon, order } } и
##   dynasty_legacies: { <id>: { track, level, icon?, modifiers?, head_modifiers?,
##     kin_opinion?, head_opinion?, ai_weight? } }
## modifiers действуют на всех живых членов рода, head_modifiers — на главу;
## kin_opinion — мнение членов рода друг о друге, head_opinion — о главе.
## Наследие покупает глава рода за известность: dynasty.legacy_cost_base +
## legacy_cost_step × открытых; уровень ветви — только после предыдущего.
##
## Глава рода — основной наследник прежнего главы, если он из рода, иначе
## самый высокородный (потом самый прославленный) член рода. Глава может
## лишить наследства, взыскать с родича золото и воздать почести
## (взаимодействия в данных, эффекты spend_dynasty_renown, disinherit…).
##
## Младшая ветвь (дом): эффект found_cadet_house — новая запись в
## state.dynasties с полем parent; основатель и его живые потомки из прежнего
## дома переходят в неё. Глава дома — его основатель и наследники.
## Хуки: dynasty.legacy_unlocked — {dynasty, legacy, character};
## dynasty.head_changed — {dynasty, head, old}; dynasty.house_founded —
## {house, parent, character}.

const OWNER := "core/dynasties"


func _init() -> void:
	id = "dynasties"
	doc = "Династия: известность рода, наследия, глава рода и младшие ветви"


static func rec(game: Game, dyn_id: Variant) -> Variant:
	return game.state.dynasties.get(dyn_id) if dyn_id != null else null


static func root_of(game: Game, c: Dictionary) -> Variant:
	return Chars.dynasty_root(game, c.dynasty) if c.dynasty != null else null


static func is_house(game: Game, dyn_id: Variant) -> bool:
	var d: Variant = rec(game, dyn_id)
	return d != null and d.get("parent") != null


## Живые члены рода (со всеми ветвями), кэш на месяц.
static func members(game: Game, root_id: Variant) -> Array:
	if root_id == null:
		return []
	return game.cached_monthly("dynmem:" + str(root_id), func():
		return game.living().filter(func(x): return x.dynasty != null and Chars.dynasty_root(game, x.dynasty) == root_id))


## Живые члены одного дома (без ветвей).
static func house_members(game: Game, dyn_id: Variant) -> Array:
	if dyn_id == null:
		return []
	return game.living().filter(func(x): return x.dynasty == dyn_id)


## Младшие ветви рода.
static func houses_of(game: Game, root_id: Variant) -> Array:
	var out := []
	for d in game.state.dynasties.values():
		if d.get("parent") != null and Chars.dynasty_root(game, d.id) == root_id:
			out.append(d)
	return out


static func renown(game: Game, dyn_id: Variant) -> float:
	var d: Variant = rec(game, Chars.dynasty_root(game, dyn_id))
	return float(d.prestige) if d != null else 0.0


static func renown_total(game: Game, dyn_id: Variant) -> float:
	var d: Variant = rec(game, Chars.dynasty_root(game, dyn_id))
	return Data.num(d.get("renown_total"), maxf(0.0, float(d.prestige))) if d != null else 0.0


static func level(game: Game, dyn_id: Variant) -> int:
	if dyn_id == null:
		return 0
	var total := renown_total(game, dyn_id)
	var lv := 0
	for th in Data.as_array(game.def_val("dynasty.levels", [])):
		if total >= Data.num(th):
			lv += 1
	return lv


static func level_name(game: Game, lv: int) -> String:
	return game.loc.t("dynasty_level.%d" % lv)


## Сколько известности до следующего уровня (или -1 — высший).
static func next_level_at(game: Game, dyn_id: Variant) -> float:
	var ths := Data.as_array(game.def_val("dynasty.levels", []))
	var lv := level(game, dyn_id)
	return Data.num(ths[lv]) if lv < ths.size() else -1.0


# ------------------------------------------------------------ глава рода

## Глава рода или дома dyn_id (запись проверяется и при надобности обновляется).
static func head_of(game: Game, dyn_id: Variant) -> Variant:
	var d: Variant = rec(game, dyn_id)
	if d == null:
		return null
	var h: Variant = game.ch(d.get("head")) if d.get("head") != null else null
	if h != null and Chars.is_alive(h) and _belongs(game, h, dyn_id):
		return h
	var nh: Variant = _pick_head(game, dyn_id, h)
	_set_head(game, d, nh, h)
	return nh


static func _belongs(game: Game, c: Dictionary, dyn_id: Variant) -> bool:
	if c.dynasty == null:
		return false
	if c.dynasty == dyn_id:
		return true
	return not is_house(game, dyn_id) and Chars.dynasty_root(game, c.dynasty) == dyn_id


static func _pick_head(game: Game, dyn_id: Variant, old: Variant) -> Variant:
	if old != null:
		for hid in Succession.heirs_of(game, old):
			var x: Variant = game.ch(hid)
			if x != null and Chars.is_alive(x) and _belongs(game, x, dyn_id):
				return x
	var pool: Array = members(game, dyn_id) if not is_house(game, dyn_id) else house_members(game, dyn_id)
	var best: Variant = null
	var key := -1.0
	for x in pool:
		var k := Titles.primary_tier(game, x) * 100000.0 + (50000.0 if Chars.is_adult(game, x) else 0.0) + float(x.prestige)
		if k > key:
			key = k
			best = x
	return best


static func _set_head(game: Game, d: Dictionary, nh: Variant, old: Variant) -> void:
	d["head"] = nh.id if nh != null else null
	game.emit("dynasty.head_changed", {"dynasty": d.id, "head": d.head, "old": old.id if old != null else null})
	if nh != null and game.is_player(nh.id) and d.get("parent") == null and (old == null or old.id != nh.id):
		game.message(game.loc.t("msg.became_dynasty_head", {"name": game.name_of("dynasties", d.id)}), "good", {"type": "character", "id": nh.id}, [nh.id])


static func is_head(game: Game, c: Dictionary) -> bool:
	if c.dynasty == null:
		return false
	var h: Variant = head_of(game, Chars.dynasty_root(game, c.dynasty))
	return h != null and h.id == c.id


static func is_house_head(game: Game, c: Dictionary) -> bool:
	if c.dynasty == null:
		return false
	var h: Variant = head_of(game, c.dynasty)
	return h != null and h.id == c.id


# ------------------------------------------------------------ наследия

static func tracks(game: Game) -> Array:
	return game.engine.sorted_content("legacy_tracks")


static func legacies_of_track(game: Game, track: String) -> Array:
	var out: Array = game.content.all("dynasty_legacies").filter(func(l): return str(l.get("track")) == track)
	Data.sort_by(out, func(l): return Data.num(l.get("level"), 1))
	return out


static func owned(game: Game, dyn_id: Variant) -> Array:
	var d: Variant = rec(game, Chars.dynasty_root(game, dyn_id))
	return d.get("legacies", []) if d != null else []


static func has_legacy(game: Game, dyn_id: Variant, lid: String) -> bool:
	return owned(game, dyn_id).has(lid)


static func legacy_cost(game: Game, dyn_id: Variant) -> float:
	var cost := game.def_num("dynasty.legacy_cost_base", 300) + game.def_num("dynasty.legacy_cost_step", 250) * owned(game, dyn_id).size()
	# Династ во главе рода: legacy_cost_mult
	var h: Variant = head_of(game, dyn_id)
	if h != null:
		cost *= maxf(0.1, 1.0 + Stats.stat(game, h, "legacy_cost_mult"))
	return roundf(cost)


## Причины, по которым персонаж не может открыть наследие (пусто — может).
static func legacy_blockers(game: Game, c: Dictionary, lid: String) -> Array:
	var out := []
	var l: Variant = game.content.get_def("dynasty_legacies", lid)
	if l == null or c.dynasty == null:
		return [game.loc.t("ui.legacy_unknown")]
	var root: Variant = Chars.dynasty_root(game, c.dynasty)
	if has_legacy(game, root, lid):
		return [game.loc.t("ui.legacy_owned")]
	if not is_head(game, c):
		out.append(game.loc.t("ui.legacy_only_head"))
	var lv := int(Data.num(l.get("level"), 1))
	for prev in legacies_of_track(game, str(l.track)):
		if int(Data.num(prev.get("level"), 1)) < lv and not has_legacy(game, root, prev.id):
			out.append(game.loc.t("ui.legacy_needs", {"name": game.name_of("dynasty_legacies", prev.id)}))
			break
	var cost := legacy_cost(game, root)
	if renown(game, root) < cost:
		out.append(game.loc.t("ui.legacy_need_renown", {"n": roundi(cost)}))
	return out


static func unlock(game: Game, c: Dictionary, lid: String) -> bool:
	if not legacy_blockers(game, c, lid).is_empty():
		return false
	var root: Variant = Chars.dynasty_root(game, c.dynasty)
	var d: Dictionary = rec(game, root)
	var cost := legacy_cost(game, root)
	d.prestige = float(d.prestige) - cost
	if not (d.get("legacies") is Array):
		d["legacies"] = []
	d.legacies.append(lid)
	game.month_cache.erase("dynleg:" + str(root))
	game.stat_cache.clear()
	game.emit("dynasty.legacy_unlocked", {"dynasty": root, "legacy": lid, "character": c})
	for m in members(game, root):
		if game.is_player(m.id):
			game.message(game.loc.t("msg.legacy_unlocked", {"name": game.name_of("dynasty_legacies", lid)}), "good", null, [m.id])
			break
	return true


## Сводка рода (кэш на месяц): уровень славы и его престиж, модификаторы
## наследий для членов и главы, мнения.
static func legacy_summary(game: Game, root: Variant) -> Dictionary:
	return game.cached_monthly("dynleg:" + str(root), func():
		var lv := Dynasties.level(game, root)
		var lp: Array = Data.as_array(game.def_val("dynasty.level_prestige", []))
		var out := {"modifiers": {}, "head_modifiers": {}, "kin_opinion": 0.0, "head_opinion": 0.0,
			"level": lv, "level_prestige": Data.num(lp[clampi(lv, 0, lp.size() - 1)]) if not lp.is_empty() else 0.0}
		for lid in Dynasties.owned(game, root):
			var l: Variant = game.content.get_def("dynasty_legacies", lid)
			if l == null:
				continue
			Stats.add_into(out.modifiers, l.get("modifiers"))
			Stats.add_into(out.head_modifiers, l.get("head_modifiers"))
			out.kin_opinion += Data.num(l.get("kin_opinion"))
			out.head_opinion += Data.num(l.get("head_opinion"))
		return out)


## ИИ главы рода: открыть наследие, если хватает известности.
static func ai_legacies(game: Game, c: Dictionary) -> void:
	var root: Variant = Chars.dynasty_root(game, c.dynasty)
	if renown(game, root) < legacy_cost(game, root):
		return
	var opts := []
	for l in game.content.all("dynasty_legacies"):
		if legacy_blockers(game, c, l.id).is_empty():
			opts.append(l)
	if opts.is_empty():
		return
	var pick: Variant = game.rng.weighted(opts, func(l):
		var w := Data.num(l.get("ai_weight"), 10.0)
		var sk: Variant = l.get("ai_skill")
		if sk != null:
			w += Stats.skill(game, c, str(sk))
		return maxf(1.0, w))
	if pick != null:
		unlock(game, c, pick.id)


# ------------------------------------------------------------ ветви и власть главы

## Основать младшую ветвь: новый дом, куда переходят основатель и его живые
## потомки из прежнего дома.
static func found_house(game: Game, c: Dictionary) -> Variant:
	if c.dynasty == null:
		return null
	var parent: Variant = c.dynasty
	var cul: Variant = game.content.get_def("cultures", c.culture)
	var key: Variant = null
	if cul != null and cul.get("dynasty_pattern") == "place":
		key = Titles.capital_of(game, c)
	if key == null:
		key = c.name
	var d := Chars.create_dynasty(game, c.culture, c.id, "gen:%s:%s" % [c.culture, key])
	d["parent"] = parent
	d["head"] = c.id
	d["founded"] = game.date
	var moved := [c]
	var queue: Array = c.children.duplicate()
	while not queue.is_empty():
		var x: Variant = game.ch(queue.pop_front())
		if x == null or x.dynasty != parent:
			continue
		moved.append(x)
		queue.append_array(x.children)
	for x in moved:
		if Chars.is_alive(x):
			x.dynasty = d.id
	game.month_cache.clear()
	game.mark_chars_dirty(moved.map(func(x): return x.id))
	game.emit("dynasty.house_founded", {"house": d.id, "parent": parent, "character": c})
	return d


static func disinherit(game: Game, c: Dictionary, on: bool) -> void:
	if on:
		c.flags["disinherited"] = 0
	else:
		c.flags.erase("disinherited")
	game.mark_chars_dirty([c.id])


static func monthly_char(game: Game, c: Dictionary) -> void:
	if c.dynasty == null or c.titles.is_empty():
		return
	# правители рода приносят ему известность по рангу
	var by_tier: Array = Data.as_array(game.def_val("dynasty.renown_by_tier", []))
	var pt := Titles.primary_tier(game, c)
	if pt < by_tier.size():
		Chars.add_dynasty_renown(game, c.dynasty, Data.num(by_tier[pt]))
	if not game.is_player(c.id) and is_head(game, c):
		ai_legacies(game, c)


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("dynasties", {"id": "dynasties", "order": 11, "on_character_month": Dynasties.monthly_char}, OWNER)
	engine.hooks.on("deed", func(p):
		var c: Dictionary = p.character
		if c.dynasty == null:
			return
		var by_deed: Variant = p.game.def_val("dynasty.renown_from_deeds", {})
		if by_deed is Dictionary and by_deed.has(p.deed):
			Chars.add_dynasty_renown(p.game, c.dynasty, Data.num(by_deed[p.deed]))
	, 0, OWNER)
	# смерть главы — сразу передаём главенство (наследнику из рода)
	engine.hooks.on("character.death", func(p):
		var game: Game = p.game
		var c: Dictionary = p.character
		if c.dynasty == null:
			return
		for did in [c.dynasty, Chars.dynasty_root(game, c.dynasty)]:
			var d: Variant = Dynasties.rec(game, did)
			if d != null and d.get("head") == c.id:
				Dynasties._set_head(game, d, Dynasties._pick_head(game, did, c), c)
		game.month_cache.erase("dynmem:" + str(Chars.dynasty_root(game, c.dynasty)))
	, 0, OWNER)
	engine.modifier_providers.register("dynasty", {"fn": func(game: Game, c: Dictionary) -> Variant:
		if c.dynasty == null:
			return null
		var root: Variant = Chars.dynasty_root(game, c.dynasty)
		var d: Variant = Dynasties.rec(game, root)
		if d == null:
			return null
		var out := []
		var sm := Dynasties.legacy_summary(game, root)
		if not c.titles.is_empty() and float(sm.level_prestige) != 0.0:
			var lv: int = sm.level
			out.append({"label": func(): return game.loc.t("modsrc.dynasty_level", {"name": Dynasties.level_name(game, lv)}), "modifiers": {"monthly_prestige": sm.level_prestige}})
		var legs: Variant = d.get("legacies")
		if legs is Array and not legs.is_empty():
			if not sm.modifiers.is_empty():
				out.append({"label": func(): return game.loc.t("modsrc.dynasty_legacies"), "modifiers": sm.modifiers})
			if not sm.head_modifiers.is_empty() and d.get("head") == c.id:
				out.append({"label": func(): return game.loc.t("modsrc.dynasty_head"), "modifiers": sm.head_modifiers})
		return out if not out.is_empty() else null
	}, OWNER)
	engine.opinion_providers.register("dynasty", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		if a.dynasty == null or b.dynasty == null:
			return null
		var root: Variant = Chars.dynasty_root(game, a.dynasty)
		if Chars.dynasty_root(game, b.dynasty) != root:
			return null
		var d: Variant = Dynasties.rec(game, root)
		if d == null:
			return null
		var out := []
		var legs: Variant = d.get("legacies")
		var sm: Variant = Dynasties.legacy_summary(game, root) if (legs is Array and not legs.is_empty()) else null
		if d.get("head") == b.id:
			var hv := game.def_num("dynasty.head_opinion", 5) + (float(sm.head_opinion) if sm != null else 0.0)
			if hv != 0.0:
				out.append({"label": game.loc.t("opinion.dynasty_head"), "value": hv})
		if sm != null and float(sm.kin_opinion) != 0.0:
			out.append({"label": game.loc.t("opinion.dynasty_kin"), "value": float(sm.kin_opinion)})
		return out if not out.is_empty() else null
	}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	const CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s is Dictionary and s.get("type") == "character") else null
	var other := func(ctx: ScriptContext, s: Variant, arg: Variant) -> Variant:
		var o: Variant = Interp.resolve_scope(ctx, s, arg)
		return ctx.game.ch(o.id) if (o is Dictionary and o.get("type") == "character") else null
	var yes := func(arg: Variant) -> bool: return arg == null or ScriptContext.is_yes(arg)

	r.triggers.register("is_dynasty_head", {"scopes": CH, "doc": "Глава своего рода", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return (c != null and Dynasties.is_head(ctx.game, c)) == yes.call(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_dynasty_head" + ("" if yes.call(arg) else ".not")),
	}, OWNER)
	r.triggers.register("is_house_head", {"scopes": CH, "doc": "Глава своего дома (ветви или рода)", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return (c != null and Dynasties.is_house_head(ctx.game, c)) == yes.call(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_house_head" + ("" if yes.call(arg) else ".not")),
	}, OWNER)
	r.triggers.register("is_dynasty_head_of", {"scopes": CH, "doc": "Глава рода этого персонажа: is_dynasty_head_of: scope:recipient", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var o: Variant = other.call(ctx, s, arg)
		return c != null and o != null and o.id != c.id and Chars.same_dynasty(ctx.game, c, o) and Dynasties.is_head(ctx.game, c),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("tr.is_dynasty_head_of", {"who": ctx.game.scope_name(Interp.resolve_scope(ctx, s, arg))}),
	}, OWNER)
	r.triggers.register("is_disinherited", {"scopes": CH, "doc": "Лишён наследства главой рода", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return (c != null and c.flags.has("disinherited")) == yes.call(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_disinherited" + ("" if yes.call(arg) else ".not")),
	}, OWNER)
	r.triggers.register("has_dynasty_legacy", {"scopes": CH, "doc": "Род персонажа открыл наследие: has_dynasty_legacy: <id>", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return c != null and c.dynasty != null and Dynasties.has_legacy(ctx.game, c.dynasty, str(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_dynasty_legacy", {"value": ctx.game.name_of("dynasty_legacies", str(arg))}),
	}, OWNER)
	r.triggers.register("is_cadet_house", {"scopes": CH, "doc": "Персонаж из младшей ветви рода", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return (c != null and Dynasties.is_house(ctx.game, c.dynasty)) == yes.call(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_cadet_house" + ("" if yes.call(arg) else ".not")),
	}, OWNER)
	r.values.register("dynasty_renown", {"scopes": CH, "doc": "Известность рода (можно тратить)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Dynasties.renown(ctx.game, c.dynasty) if (c != null and c.dynasty != null) else 0.0
	}, OWNER)
	r.values.register("dynasty_level", {"scopes": CH, "doc": "Уровень славы рода (0 — безвестный)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(Dynasties.level(ctx.game, c.dynasty)) if (c != null and c.dynasty != null) else 0.0
	}, OWNER)
	r.values.register("num_dynasty_legacies", {"scopes": CH, "doc": "Открыто наследий у рода", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(Dynasties.owned(ctx.game, c.dynasty).size()) if (c != null and c.dynasty != null) else 0.0
	}, OWNER)
	r.effects.register("spend_dynasty_renown", {"scopes": CH, "doc": "Потратить известность рода: spend_dynasty_renown: 100", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c != null and c.dynasty != null:
			var d: Variant = Dynasties.rec(ctx.game, Chars.dynasty_root(ctx.game, c.dynasty))
			d.prestige = float(d.prestige) - Interp.eval_value(ctx, s, arg),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.spend_dynasty_renown", {"value": roundi(Interp.eval_value(ctx, s, arg))}),
	}, OWNER)
	r.effects.register("disinherit", {"scopes": CH, "doc": "Лишить наследства (yes) или восстановить в правах (no)", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			Dynasties.disinherit(ctx.game, c, yes.call(arg)),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.disinherit" + ("" if yes.call(arg) else ".not"), {"who": ctx.game.scope_name(s)}),
	}, OWNER)
	r.effects.register("found_cadet_house", {"scopes": CH, "doc": "Основать младшую ветвь рода: found_cadet_house: yes", "apply": func(ctx, s, _arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			Dynasties.found_house(ctx.game, c),
		"describe": func(ctx, s, _arg): return ctx.game.loc.t("fx.found_cadet_house", {"who": ctx.game.scope_name(s)}),
	}, OWNER)
	r.effects.register("unlock_dynasty_legacy", {"scopes": CH, "doc": "Открыть наследие рода (если можно): unlock_dynasty_legacy: <id>", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			Dynasties.unlock(ctx.game, c, str(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.unlock_dynasty_legacy", {"value": ctx.game.name_of("dynasty_legacies", str(arg))}),
	}, OWNER)
	r.links.register("dynasty_head", {"from": CH, "doc": "Глава рода персонажа", "resolve": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		if c == null or c.dynasty == null:
			return null
		var h: Variant = Dynasties.head_of(ctx.game, Chars.dynasty_root(ctx.game, c.dynasty))
		return {"type": "character", "id": h.id} if h != null else null
	}, OWNER)
	r.links.register("house_head", {"from": CH, "doc": "Глава дома персонажа", "resolve": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		if c == null or c.dynasty == null:
			return null
		var h: Variant = Dynasties.head_of(ctx.game, c.dynasty)
		return {"type": "character", "id": h.id} if h != null else null
	}, OWNER)

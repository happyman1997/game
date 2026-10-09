class_name Opinion
extends RefCounted
## Мнение персонажа a о персонаже b — сумма «частей» от поставщиков мнения.
## Встроенные поставщики (черты, культура, вера, семья, сюзерен, сохранённые
## модификаторы) зарегистрированы в engine.opinion_providers наравне с
## моддерскими: {label?, fn: Callable(game, a, b) -> Array[{label, value}] | {label, value} | null}.


## [{label, value}]
static func breakdown(game: Game, a: Dictionary, b: Dictionary) -> Array:
	var out := []
	if a.id == b.id:
		return out
	var reg := game.engine.opinion_providers
	for id in reg.ids():
		var r: Variant = reg.get_item(id).fn.call(game, a, b)
		if r == null:
			continue
		for part in Data.as_array(r):
			if part is Dictionary and Data.num(part.get("value")) != 0.0:
				out.append(part)
	return out


static func opinion(game: Game, a: Dictionary, b: Dictionary) -> int:
	if a.id == b.id:
		return 100
	var key = "op:%s>%s" % [a.id, b.id]
	var cached: Variant = game.stat_cache.get(key)
	if cached != null:
		return cached.v
	var total := 0.0
	for p in breakdown(game, a, b):
		total += Data.num(p.value)
	var v := clampi(roundi(total), -100, 100)
	game.stat_cache[key] = {"v": v}
	return v


## Добавляет модификатор мнения: a станет иначе относиться к b.
static func add_opinion(game: Game, a: Dictionary, b: Dictionary, mod_id: String, value: Variant = null) -> void:
	var def: Variant = game.content.get_def("opinion_modifiers", mod_id)
	var v: float = Data.num(value) if value != null else (Data.num(def.get("value")) if def != null else 0.0)
	if not a.opinions.has(b.id):
		a.opinions[b.id] = []
	var list: Array = a.opinions[b.id]
	var months: Variant = null
	if def != null:
		if def.get("months") != null:
			months = Data.num(def.months)
		elif def.get("years") != null:
			months = Data.num(def.years) * 12.0
	var expires: Variant = game.date + roundi(months * 30.0) if months != null else null
	if def == null or not def.get("stacking", false):
		for e in list:
			if e.mod == mod_id:
				e.value = v
				e.expires = expires
				game.stat_cache.erase("op:%s>%s" % [a.id, b.id])
				return
	list.append({"mod": mod_id, "value": v, "expires": expires})
	game.stat_cache.erase("op:%s>%s" % [a.id, b.id])


static func remove_opinion(game: Game, a: Dictionary, b: Dictionary, mod_id: String) -> void:
	if not a.opinions.has(b.id):
		return
	a.opinions[b.id] = a.opinions[b.id].filter(func(e): return e.mod != mod_id)
	if a.opinions[b.id].is_empty():
		a.opinions.erase(b.id)
	game.stat_cache.erase("op:%s>%s" % [a.id, b.id])


static func has_opinion_modifier(a: Dictionary, b: Dictionary, mod_id: String) -> bool:
	return a.opinions.has(b.id) and a.opinions[b.id].any(func(e): return e.mod == mod_id)


## Ежемесячно: истечение и затухание модификаторов мнения.
static func decay_opinions(game: Game) -> void:
	for c in game.living():
		for target in c.opinions.keys():
			var kept := []
			for e in c.opinions[target]:
				if e.expires != null and e.expires <= game.date:
					continue
				var def: Variant = game.content.get_def("opinion_modifiers", e.mod)
				if def != null and def.get("decay") != null:
					var s := signf(e.value)
					e.value -= s * Data.num(def.decay)
					if signf(e.value) != s or e.value == 0.0:
						continue
				kept.append(e)
			var t: Variant = game.ch(target)
			if not kept.is_empty() and t != null and t.death == null:
				c.opinions[target] = kept
			else:
				c.opinions.erase(target)


# ------------------------------------------------------------ встроенные поставщики

static func _part(label: String, value: float) -> Variant:
	return {"label": label, "value": value} if value != 0.0 else null


static func builtin_providers() -> Dictionary:
	return {
		"stored": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
			return a.opinions.get(b.id, []).map(func(e): return {"label": game.name_of("opinion_modifiers", e.mod), "value": float(roundi(e.value))}),
		"traits": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
			var v := 0.0
			for t in a.traits:
				var d: Variant = game.content.get_def("traits", t)
				var comp: Variant = d.get("compatibility") if d != null else null
				if not (comp is Dictionary):
					continue
				for t2 in b.traits:
					# скрытые черты b влияют, только если a о них знает
					if comp.has(t2) and Chars.trait_visible(game, b, t2, a.id):
						v += Data.num(comp.get(t2))
			return _part(game.loc.t("opinion.traits"), v),
		"general": func(game: Game, _a: Dictionary, b: Dictionary) -> Variant:
			return _part(game.loc.t("opinion.general"), roundi(Stats.stat(game, b, "general_opinion"))),
		"attraction": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
			if a.female == b.female or not Chars.is_adult(game, a) or not Chars.is_adult(game, b):
				return null
			return _part(game.loc.t("opinion.attraction"), roundi(Stats.stat(game, b, "attraction_opinion"))),
		"culture": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
			var same: bool = a.culture == b.culture
			var v = game.def_num("opinion.same_culture" if same else "opinion.different_culture", 0)
			return _part(game.loc.t("opinion.same_culture" if same else "opinion.different_culture"), v),
		"faith": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
			var same: bool = a.faith == b.faith
			var v = game.def_num("opinion.same_faith" if same else "opinion.different_faith", 0)
			return _part(game.loc.t("opinion.same_faith" if same else "opinion.different_faith"), v),
		"family": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
			var parts := []
			if a.spouses.has(b.id):
				parts.append({"label": game.loc.t("opinion.spouse"), "value": game.def_num("opinion.spouse", 20)})
			if Chars.is_parent_of(b, a):
				parts.append({"label": game.loc.t("opinion.parent"), "value": game.def_num("opinion.parent", 20)})
			if Chars.is_parent_of(a, b):
				parts.append({"label": game.loc.t("opinion.child"), "value": game.def_num("opinion.child", 20)})
			if Chars.is_sibling(a, b):
				parts.append({"label": game.loc.t("opinion.sibling"), "value": game.def_num("opinion.sibling", 10)})
			elif a.dynasty != null and a.dynasty == b.dynasty and not Chars.is_parent_of(a, b) and not Chars.is_parent_of(b, a):
				parts.append({"label": game.loc.t("opinion.same_dynasty"), "value": game.def_num("opinion.same_dynasty", 5)})
			if not parts.is_empty():
				var fam := roundi(Stats.stat(game, b, "family_opinion"))
				if fam != 0:
					parts.append({"label": game.loc.t("opinion.family_bonus"), "value": float(fam)})
			return parts,
		"liege": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
			if a.liege != b.id or a.titles.is_empty():
				return null
			var parts := []
			var v = roundi(game.def_num("opinion.liege_base", 0) + Stats.stat(game, b, "vassal_opinion"))
			if v != 0:
				parts.append({"label": game.loc.t("opinion.liege"), "value": float(v)})
			# «Недолгое правление»: вассалы присматриваются к новому сюзерену.
			var hist: Variant = null
			if not b.titles.is_empty() and game.state.titles.has(b.titles[0]):
				hist = game.state.titles[b.titles[0]].history
			var years := INF
			if hist != null and hist.size() > 1:
				years = (game.date - int(hist[hist.size() - 1].from)) / 365.0
			var mx = game.def_num("opinion.short_reign", 0)
			var span = game.def_num("opinion.short_reign_years", 8)
			if mx != 0.0 and years < span:
				parts.append({"label": game.loc.t("opinion.short_reign"), "value": float(roundi(mx * (1.0 - years / span)))})
			return parts,
		"claim": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
			# Претенденты недолюбливают тех, кто держит их титулы.
			var holds: bool = b.titles.any(func(t): return a.claims.has(t))
			return _part(game.loc.t("opinion.holds_claim"), game.def_num("opinion.holds_my_claim", -15) if holds else 0.0),
	}

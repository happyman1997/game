class_name Stats
extends RefCounted
## Характеристики персонажа = база + сумма модификаторов из всех источников:
## черты, временные модификаторы, культура, вера, возраст и «поставщики»
## модификаторов, которые регистрируют моды (engine.modifier_providers).
##
## Поставщик: {label?, fn: Callable(game, c) -> Dictionary | Array[{label, modifiers}] | null}.
## label в элементах массива может быть Callable() -> String: подпись нужна
## только для подсказок, а характеристики считаются часто.
## Поставщик провинции: {label?, fn: Callable(game, prov_id) -> Dictionary | null}.

## Персонажи, чьи характеристики считаются прямо сейчас (защита от циклов: совет супругов и т.п.).
static var _computing := {}


static func add_into(out: Dictionary, mods: Variant) -> void:
	if not (mods is Dictionary):
		return
	for k in mods:
		var v: Variant = mods[k]
		if v is int or v is float:
			out[k] = float(out.get(k, 0.0)) + float(v)


## Источники: [{label, mods}]. labels = false — без подписей (быстрее).
static func _sources(game: Game, c: Dictionary, with_providers: bool = true, labels: bool = true) -> Array:
	var out := []
	var base = {"health": float(c.health)}
	for s in Chars.skill_ids(game):
		base[s] = Data.num(c.skills.get(s))
	add_into(base, game.def_val("character.base_stats"))
	out.append({"label": game.loc.t("ui.base_value") if labels else "", "mods": base})
	# В подписях (разбивка для игрока) скрытые черты и модификаторы не называются:
	# их вклад растворяется в базовом значении, иначе подсказка выдаст тайну.
	var viewer: Variant = game.state.player if labels else null
	for t in c.traits:
		var d: Variant = game.content.get_def("traits", t)
		if d != null and d.get("modifiers") is Dictionary:
			if labels and d.get("concealed") != null and not Chars.trait_visible(game, c, t, viewer):
				add_into(base, d.modifiers)
			else:
				out.append({"label": game.name_of("traits", t) if labels else "", "mods": d.modifiers})
	for m in c.modifiers:
		var d: Variant = game.content.get_def("modifiers", m.id)
		if d != null and d.get("modifiers") is Dictionary:
			if labels and d.get("concealed") != null and not Chars.modifier_visible(game, c, m.id, viewer):
				add_into(base, d.modifiers)
			else:
				out.append({"label": game.name_of("modifiers", m.id) if labels else "", "mods": d.modifiers})
	var cul: Variant = game.content.get_def("cultures", c.culture)
	if cul != null and cul.get("modifiers") is Dictionary:
		out.append({"label": game.name_of("cultures", c.culture) if labels else "", "mods": cul.modifiers})
	var faith: Variant = game.content.get_def("faiths", c.faith)
	if faith != null and faith.get("modifiers") is Dictionary:
		out.append({"label": game.name_of("faiths", c.faith) if labels else "", "mods": faith.modifiers})
	if not with_providers:
		return out
	var reg := game.engine.modifier_providers
	for id in reg.ids():
		var p: Dictionary = reg.get_item(id)
		var mods: Variant = p.fn.call(game, c)
		if mods is Array:
			for m in mods:
				if m is Dictionary and m.get("modifiers") is Dictionary and not m.modifiers.is_empty():
					# подпись может быть ленивой: Callable() -> String
					var lbl: Variant = m.get("label", "")
					if labels and lbl is Callable:
						lbl = (lbl as Callable).call()
					out.append({"label": str(lbl) if not (lbl is Callable) else "", "mods": m.modifiers})
		elif mods is Dictionary and not mods.is_empty():
			var label := ""
			if labels:
				label = game.loc.resolve(p.label) if p.get("label") != null else game.loc.t_or("modsrc." + id, id)
			out.append({"label": label, "mods": mods})
	return out


static func _age_adjust(game: Game, c: Dictionary, totals: Dictionary) -> Dictionary:
	var age := Chars.age_of(game, c)
	var adj := {}
	var adult = game.def_num("character.adult_age", 16)
	if age < adult:
		var f := maxf(0.15, age / adult)
		for s in Chars.skill_ids(game):
			var v := Data.num(totals.get(s))
			adj[s] = v * f - v
	var old_start = game.def_num("character.old_age_start", 50)
	if age > old_start:
		var y = age - old_start
		adj["health"] = -y * game.def_num("character.old_age_health_per_year", 0.08)
		adj["prowess"] = -y * game.def_num("character.old_age_prowess_per_year", 0.2)
		adj["fertility"] = -y * game.def_num("character.old_age_fertility_per_year", 0.02)
	return adj


## То же, что сумма _sources(), но без промежуточных массивов (горячий путь).
static func _accumulate(game: Game, c: Dictionary, out: Dictionary) -> void:
	out["health"] = float(c.health)
	var skills: Dictionary = c.skills
	for s in Chars.skill_ids(game):
		out[s] = Data.num(skills.get(s))
	add_into(out, game.def_val("character.base_stats"))
	var content := game.content
	for t in c.traits:
		var d: Variant = content.get_def("traits", t)
		if d != null:
			var m: Variant = d.get("modifiers")
			if m is Dictionary:
				add_into(out, m)
	for md in c.modifiers:
		var d: Variant = content.get_def("modifiers", md.id)
		if d != null:
			var m: Variant = d.get("modifiers")
			if m is Dictionary:
				add_into(out, m)
	var cul: Variant = content.get_def("cultures", c.culture)
	if cul != null and cul.get("modifiers") is Dictionary:
		add_into(out, cul.modifiers)
	var faith: Variant = content.get_def("faiths", c.faith)
	if faith != null and faith.get("modifiers") is Dictionary:
		add_into(out, faith.modifiers)
	for p in game.engine.modifier_providers._map.values():
		var mods: Variant = p.fn.call(game, c)
		if mods is Array:
			for m in mods:
				if m is Dictionary and m.get("modifiers") is Dictionary:
					add_into(out, m.modifiers)
		elif mods is Dictionary:
			add_into(out, mods)


static func char_stats(game: Game, c: Dictionary) -> Dictionary:
	var cached: Variant = game.stat_cache.get(c.id)
	if cached != null:
		return cached
	var out := {}
	if _computing.has(c.id):
		# Циклическая зависимость (A считает навык B, а B — навык A): берём характеристики без поставщиков.
		for s in _sources(game, c, false, false):
			add_into(out, s.mods)
		return out
	_computing[c.id] = true
	_accumulate(game, c, out)
	_computing.erase(c.id)
	add_into(out, _age_adjust(game, c, out))
	game.stat_cache[c.id] = out
	return out


static func stat(game: Game, c: Dictionary, key: String) -> float:
	return float(char_stats(game, c).get(key, 0.0))


## Навык для отображения и формул: округлён, не меньше нуля.
static func skill(game: Game, c: Dictionary, key: String) -> int:
	return maxi(0, roundi(stat(game, c, key)))


## [{label, value}]
static func stat_breakdown(game: Game, c: Dictionary, key: String) -> Array:
	var parts := []
	var total := {}
	for s in _sources(game, c):
		add_into(total, s.mods)
		var v: Variant = s.mods.get(key)
		if (v is int or v is float) and v != 0:
			parts.append({"label": s.label, "value": float(v)})
	var adj: Variant = _age_adjust(game, c, total).get(key)
	if adj != null and adj != 0.0:
		parts.append({"label": game.loc.t("ui.age"), "value": adj})
	return parts


# ------------------------------------------------------------ провинции

static func prov_stats(game: Game, prov_id: String) -> Dictionary:
	var key := "prov:" + prov_id
	var cached: Variant = game.stat_cache.get(key)
	if cached != null:
		return cached
	var out := {}
	var def: Variant = game.content.get_def("provinces", prov_id)
	var st: Variant = game.state.provinces.get(prov_id)
	if def != null and st != null:
		for h in Data.as_array(def.get("holdings")):
			var hd: Variant = game.content.get_def("holdings", h)
			if hd != null:
				add_into(out, {"tax": Data.num(hd.get("tax")), "levy": Data.num(hd.get("levy")), "fort": Data.num(hd.get("fort"))})
		for b in st.buildings:
			var bd: Variant = game.content.get_def("buildings", b)
			if bd != null:
				add_into(out, bd.get("modifiers"))
		for m in st.modifiers:
			var md: Variant = game.content.get_def("modifiers", m.id)
			if md != null:
				add_into(out, md.get("modifiers"))
		var terrain: Variant = game.content.get_def("terrain", def.get("terrain"))
		add_into(out, {"development_growth": Data.num(terrain.get("development_growth")) if terrain != null else 0.0})
		var reg := game.engine.province_modifier_providers
		for id in reg.ids():
			add_into(out, reg.get_item(id).fn.call(game, prov_id))
	game.stat_cache[key] = out
	return out


static func prov_stat(game: Game, prov_id: String, key: String) -> float:
	return float(prov_stats(game, prov_id).get(key, 0.0))


## Встроенный поставщик: «владельческие» модификаторы зданий в домене.
static func building_owner_provider(game: Game, c: Dictionary) -> Variant:
	if c.titles.is_empty():
		return null
	var out := {}
	for county in Titles.domain_counties(game, c):
		var p: Variant = game.state.provinces.get(county)
		if p == null:
			continue
		for b in p.buildings:
			var bd: Variant = game.content.get_def("buildings", b)
			if bd != null:
				add_into(out, bd.get("owner_modifiers"))
	return out


## Встроенный поставщик: стресс снижает навыки на высоких уровнях.
static func stress_provider(game: Game, c: Dictionary) -> Variant:
	var lvl = floori(float(c.stress) / 100.0)
	if lvl <= 0:
		return null
	var per = game.def_num("character.stress_skill_penalty", 1)
	var out := {}
	for s in Chars.skill_ids(game):
		out[s] = -per * lvl
	return out

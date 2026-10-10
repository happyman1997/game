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


## Производные от навыков: доля навыков супруга (defines.character.spouse_skill_share),
## «за каждое очко» (skills.<id>.per_point), тень мастерства (skills.<id>.mastery)
## и связки навыков (skill_archetypes). Считаются после навыков и обратно на их
## пороги не влияют. labels = true — разбивка [{label, mods}] для подсказок;
## иначе (горячий путь) всё складывается прямо в into.
static func _derived(game: Game, c: Dictionary, totals: Dictionary, labels: bool, into: Dictionary = {}) -> Array:
	var out := []
	if not Chars.is_adult(game, c):
		return out
	var plan := _derived_plan(game)
	var sk := {}
	for s in plan.skills:
		sk[s] = maxf(0.0, Data.num(totals.get(s)))
	# Супруг правителя помогает советом: доля его собственных навыков (без бонусов —
	# иначе характеристики супругов считались бы друг через друга).
	var share: Dictionary = plan.share
	if not share.is_empty() and not c.titles.is_empty() and not c.spouses.is_empty():
		var sp: Variant = game.ch(c.spouses[0])
		if sp != null and sp.death == null and Chars.is_adult(game, sp):
			var m := {}
			for s in share:
				var v := floorf(Data.num(sp.skills.get(s)) * float(share[s]))
				if v > 0.0:
					m[s] = v
					sk[s] = float(sk.get(s, 0.0)) + v
			if not m.is_empty():
				if labels:
					out.append({"label": game.loc.t("modsrc.spouse", {"name": game.scope_name({"type": "character", "id": sp.id})}), "mods": m})
				else:
					add_into(into, m)
	var high := 0
	for item in plan.per_skill:
		var s: String = item[0]
		var v: float = sk[s]
		if v >= plan.archetype_min:
			high += 1
		if v <= 0.0:
			continue
		var pp: Dictionary = item[1].duplicate()
		if not c.titles.is_empty():
			for k in item[7]:
				pp[k] = float(pp.get(k, 0.0)) + float(item[7][k])
		if not pp.is_empty():
			if labels:
				var m := {}
				for k in pp:
					m[k] = float(pp[k]) * v
				out.append({"label": game.loc.t("modsrc.skill", {"name": game.name_of("skills", s)}), "mods": m})
			else:
				for k in pp:
					into[k] = float(into.get(k, 0.0)) + float(pp[k]) * v
		# Тень мастерства: у очень высокого навыка есть изнанка. Отметка
		# "mastery:<навык>" = 1 — по ней узнают, что тень легла (Personality, интерфейс).
		var ms: Variant = item[2]
		if ms != null and v >= float(ms[0]):
			var m := {"mastery:" + s: 1.0}
			add_into(m, ms[1])
			if labels:
				out.append({"label": game.loc.t("modsrc.mastery", {"name": game.loc.t("mastery." + s)}), "mods": m})
			else:
				add_into(into, m)
	# Связки навыков. С механикой trials — только заслуженные испытанием
	# (c.vars.archetypes, навсегда); без неё — два-три высоких навыка, не больше
	# defines.character.max_archetypes (тройки, затем пары с навыками повыше).
	if plan.earned:
		for aid in Data.as_array(c.vars.get("archetypes")):
			var a: Variant = plan.arch_by_id.get(aid)
			if a == null:
				continue
			var m := {a[5]: 1.0}
			add_into(m, a[3])
			if labels:
				out.append({"label": game.loc.t("modsrc.archetype", {"name": game.name_of("skill_archetypes", a[0])}), "mods": m})
			else:
				add_into(into, m)
	elif high >= 2:
		var fit := []
		for a in plan.archetypes:
			var total := 0.0
			var okk := true
			for s in a[1]:
				var v := float(sk.get(s, 0.0))
				if v < a[2]:
					okk = false
					break
				total += v
			if okk:
				fit.append([a, total])
		if not fit.is_empty():
			fit.sort_custom(func(x, y):
				if x[0][1].size() != y[0][1].size():
					return x[0][1].size() > y[0][1].size()
				return x[1] > y[1])
			for n in mini(fit.size(), plan.max_archetypes):
				var a: Array = fit[n][0]
				var m := {"archetype:" + str(a[0]): 1.0}
				add_into(m, a[3])
				if labels:
					out.append({"label": game.loc.t("modsrc.archetype", {"name": game.name_of("skill_archetypes", a[0])}), "mods": m})
				else:
					add_into(into, m)
	return out


## Горячий путь _derived: дописывает прямо в характеристики out (без подписей и
## промежуточных словарей). Дети (навыки ещё растут) — без производных.
static func _derived_fast(game: Game, c: Dictionary, out: Dictionary) -> void:
	var plan := _derived_plan(game)
	if game.date - int(c.birth) < plan.adult_days:
		return
	var ruler: bool = not c.titles.is_empty()
	var share: Dictionary = plan.share
	if ruler and not share.is_empty() and not c.spouses.is_empty():
		var sp: Variant = game.ch(c.spouses[0])
		if sp != null and sp.death == null:
			for s in share:
				var v := floorf(float(sp.skills.get(s, 0.0)) * float(share[s]))
				if v > 0.0:
					out[s] = float(out.get(s, 0.0)) + v
	var sk: Array = []
	var high := 0
	var amin: float = plan.archetype_min
	for item in plan.per_skill:
		var v := maxf(0.0, float(out.get(item[0], 0.0)))
		sk.append(v)
		if v >= amin:
			high += 1
	# мастерство и связки читают навыки до добавок (sk), поэтому порядок не важен
	var i := 0
	for item in plan.per_skill:
		var v: float = sk[i]
		i += 1
		if v <= 0.0:
			continue
		# у безземельных — только личные эффекты (ruler_per_point — правителям)
		var keys: PackedStringArray = item[3]
		var coefs: PackedFloat64Array = item[4]
		for j in keys.size():
			var k := keys[j]
			out[k] = float(out.get(k, 0.0)) + coefs[j] * v
		if ruler:
			keys = item[5]
			coefs = item[6]
			for j in keys.size():
				var k := keys[j]
				out[k] = float(out.get(k, 0.0)) + coefs[j] * v
		var ms: Variant = item[2]
		if ms != null and v >= float(ms[0]):
			out["mastery:" + item[0]] = 1.0
			add_into(out, ms[1])
	if plan.earned:
		var have: Variant = c.vars.get("archetypes")
		if have is Array:
			for aid in have:
				var a: Variant = plan.arch_by_id.get(aid)
				if a != null:
					out[a[5]] = 1.0
					add_into(out, a[3])
		return
	if high < 2:
		return
	# связки: индексы навыков заранее посчитаны в плане
	var fit := []
	for a in plan.archetypes:
		var idx: PackedInt32Array = a[4]
		var mn: float = a[2]
		var total := 0.0
		var okk := true
		for ix in idx:
			var v: float = sk[ix]
			if v < mn:
				okk = false
				break
			total += v
		if okk:
			fit.append([a, total])
	if fit.is_empty():
		return
	if fit.size() > plan.max_archetypes:
		fit.sort_custom(func(x, y):
			if x[0][4].size() != y[0][4].size():
				return x[0][4].size() > y[0][4].size()
			return x[1] > y[1])
	for n in mini(fit.size(), plan.max_archetypes):
		var a: Array = fit[n][0]
		out[a[5]] = 1.0
		add_into(out, a[3])


## Заранее разобранные данные для _derived (на движок).
static func _derived_plan(game: Game) -> Dictionary:
	var hit: Variant = game.engine.cache.get("stats:derived")
	if hit != null:
		return hit
	var per_skill := []
	for s in Chars.skill_ids(game):
		var d: Variant = game.content.get_def("skills", s)
		var pp: Variant = d.get("per_point") if d != null else null
		var ms: Variant = d.get("mastery") if d != null else null
		var keys := PackedStringArray()
		var coefs := PackedFloat64Array()
		if pp is Dictionary:
			for k in pp:
				keys.append(str(k))
				coefs.append(Data.num(pp[k]))
		var rp: Variant = d.get("ruler_per_point") if d != null else null
		var rkeys := PackedStringArray()
		var rcoefs := PackedFloat64Array()
		if rp is Dictionary:
			for k in rp:
				rkeys.append(str(k))
				rcoefs.append(Data.num(rp[k]))
		per_skill.append([s, pp if pp is Dictionary else {}, [Data.num(ms.get("at"), 18), ms.get("modifiers")] if ms is Dictionary else null, keys, coefs, rkeys, rcoefs, rp if rp is Dictionary else {}])
	var archetypes := []
	var amin := INF
	var ids: Array = Chars.skill_ids(game)
	for a in _archetype_defs(game):
		var mn := Data.num(a.get("min"), 12)
		var idx := PackedInt32Array()
		for sname in a.skills:
			idx.append(ids.find(str(sname)))
		if idx.has(-1):
			continue
		amin = minf(amin, mn)
		archetypes.append([str(a.id), a.skills, mn, a.get("modifiers"), idx, "archetype:" + str(a.id)])
	var share: Variant = game.def_val("character.spouse_skill_share", null)
	var by_id := {}
	for a in archetypes:
		by_id[a[0]] = a
	hit = {"skills": Chars.skill_ids(game), "per_skill": per_skill, "archetypes": archetypes, "archetype_min": amin,
		"earned": game.engine.has_feature("trials"), "arch_by_id": by_id,
		"adult_days": int(game.def_num("character.adult_age", 16) * GameDate.DAYS_PER_YEAR),
		"max_archetypes": int(game.def_num("character.max_archetypes", 2)), "share": share if share is Dictionary else {}}
	game.engine.cache["stats:derived"] = hit
	return hit


static func _archetype_defs(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("stats:archetypes")
	if hit == null:
		hit = game.content.all("skill_archetypes").filter(func(a): return a.get("skills") is Array)
		game.engine.cache["stats:archetypes"] = hit
	return hit


## Архетипы (связки навыков) персонажа: [id].
static func archetypes(game: Game, c: Dictionary) -> Array:
	var st := char_stats(game, c)
	return _archetype_defs(game).filter(func(a): return Data.num(st.get("archetype:" + str(a.id))) > 0.0).map(func(a): return str(a.id))


## Тени мастерства, которые легли на персонажа: [id навыка].
static func masteries(game: Game, c: Dictionary) -> Array:
	var st := char_stats(game, c)
	return Chars.skill_ids(game).filter(func(s): return Data.num(st.get("mastery:" + s)) > 0.0)


## Модификаторы записей контента, разобранные в пары массивов [ключи, числа]
## (на движок): {вид: {id: [PackedStringArray, PackedFloat64Array] | null}}.
static func _flat_of(game: Game, kind: String) -> Dictionary:
	var all: Dictionary = game.engine.cache.get_or_add("stats:flat", {})
	var hit: Variant = all.get(kind)
	if hit == null:
		hit = {}
		for d in game.content.all(kind):
			var m: Variant = d.get("modifiers")
			if m is Dictionary and not m.is_empty():
				var keys := PackedStringArray()
				var vals := PackedFloat64Array()
				for k in m:
					var v: Variant = m[k]
					if v is int or v is float:
						keys.append(str(k))
						vals.append(float(v))
				hit[str(d.id)] = [keys, vals]
		all[kind] = hit
	return hit


static func _add_flat(out: Dictionary, pair: Variant) -> void:
	if pair == null:
		return
	var keys: PackedStringArray = pair[0]
	var vals: PackedFloat64Array = pair[1]
	for j in keys.size():
		var k := keys[j]
		out[k] = float(out.get(k, 0.0)) + vals[j]


## То же, что сумма _sources(), но без промежуточных массивов (горячий путь).
static func _accumulate(game: Game, c: Dictionary, out: Dictionary) -> void:
	out["health"] = float(c.health)
	var skills: Dictionary = c.skills
	for s in Chars.skill_ids(game):
		out[s] = float(skills.get(s, 0.0))
	add_into(out, game.def_val("character.base_stats"))
	var ft := _flat_of(game, "traits")
	for t in c.traits:
		_add_flat(out, ft.get(t))
	if not c.modifiers.is_empty():
		var fm := _flat_of(game, "modifiers")
		for md in c.modifiers:
			_add_flat(out, fm.get(md.id))
	_add_flat(out, _flat_of(game, "cultures").get(c.culture))
	_add_flat(out, _flat_of(game, "faiths").get(c.faith))
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
	_derived_fast(game, c, out)
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
	var age_adj := _age_adjust(game, c, total)
	var adj: Variant = age_adj.get(key)
	if adj != null and adj != 0.0:
		parts.append({"label": game.loc.t("ui.age"), "value": adj})
	add_into(total, age_adj)
	for part in _derived(game, c, total, true):
		var v: Variant = part.mods.get(key)
		if (v is int or v is float) and v != 0:
			parts.append({"label": part.label, "value": float(v)})
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

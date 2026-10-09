class_name Chars
extends RefCounted
## Персонажи: возраст, имена, черты, родство, браки, создание.


static func is_alive(c: Variant) -> bool:
	return c != null and c.death == null


static func age_of(game: Game, c: Dictionary) -> int:
	var end: int = c.death if c.death != null else game.date
	return floori((end - int(c.birth)) / float(GameDate.DAYS_PER_YEAR))


static func is_adult(game: Game, c: Dictionary) -> bool:
	return age_of(game, c) >= game.def_num("character.adult_age", 16)


static func char_name(game: Game, c: Dictionary) -> String:
	var n: Variant = game.loc.raw_exact("name." + str(c.name))
	return n if n != null else str(c.name)


## «Король Гарольд Годвинсон» (with_rank) или «Гарольд Годвинсон».
static func full_name(game: Game, c: Dictionary, with_rank: bool) -> String:
	var parts := PackedStringArray()
	if with_rank and not c.titles.is_empty():
		parts.append(Titles.rank_name(game, c))
	parts.append(char_name(game, c))
	if c.get("nickname") != null:
		parts.append(game.loc.resolve(c.nickname))
	elif c.dynasty != null:
		parts.append(game.name_of("dynasties", c.dynasty))
	return " ".join(parts)


static func has_trait(c: Dictionary, t: String) -> bool:
	return c.traits.has(t)


static func trait_def(game: Game, t: String) -> Variant:
	return game.content.get_def("traits", t)


static func add_trait(game: Game, c: Dictionary, t: String) -> bool:
	var def: Variant = trait_def(game, t)
	if def == null:
		game.script_error("Нет черты \"%s\"" % t)
		return false
	if c.traits.has(t):
		return false
	# Убираем противоположные черты и другие уровни того же образования.
	var opp: Array = def.get("opposites", [])
	var kept := []
	for x in c.traits:
		if opp.has(x):
			continue
		var xd: Variant = trait_def(game, x)
		if xd != null:
			if xd.get("opposites", []).has(t):
				continue
			if def.get("education") != null and xd.get("education") != null:
				continue
			if def.get("group") != null and xd.get("group") == def.group:
				continue
		kept.append(x)
	kept.append(t)
	c.traits = kept
	if def.get("duration_days") != null:
		c.flags["trait_expires:" + t] = game.date + int(def.duration_days)
	game.stat_cache.erase(c.id)
	game.emit("character.trait_added", {"character": c, "trait": t})
	return true


static func remove_trait(game: Game, c: Dictionary, t: String) -> bool:
	var i: int = c.traits.find(t)
	if i < 0:
		return false
	c.traits.remove_at(i)
	c.flags.erase("trait_expires:" + t)
	game.stat_cache.erase(c.id)
	game.emit("character.trait_removed", {"character": c, "trait": t})
	return true


# ------------------------------------------------------------ родство

static func parents_of(game: Game, c: Dictionary) -> Array:
	var out := []
	var f: Variant = game.ch(c.father)
	var m: Variant = game.ch(c.mother)
	if f != null:
		out.append(f)
	if m != null:
		out.append(m)
	return out


static func siblings_of(game: Game, c: Dictionary) -> Array:
	var ids := {}
	for p in parents_of(game, c):
		for chid in p.children:
			if chid != c.id:
				ids[chid] = true
	var out := []
	for id in ids:
		var s: Variant = game.ch(id)
		if s != null:
			out.append(s)
	return out


static func is_parent_of(a: Dictionary, b: Dictionary) -> bool:
	return b.father == a.id or b.mother == a.id


static func is_sibling(a: Dictionary, b: Dictionary) -> bool:
	if a.id == b.id:
		return false
	return (a.father != null and a.father == b.father) or (a.mother != null and a.mother == b.mother)


## Близкие родственники: родители, дети, братья/сёстры, деды, внуки.
static func is_close_family(game: Game, a: Dictionary, b: Dictionary) -> bool:
	if a.id == b.id:
		return false
	if is_parent_of(a, b) or is_parent_of(b, a) or is_sibling(a, b):
		return true
	for p in parents_of(game, a):
		if is_parent_of(b, p):
			return true
	for p in parents_of(game, b):
		if is_parent_of(a, p):
			return true
	return false


## Слишком близкие для брака: близкие + дяди/тёти/племянники.
static func is_too_close_to_marry(game: Game, a: Dictionary, b: Dictionary) -> bool:
	if is_close_family(game, a, b):
		return true
	for p in parents_of(game, a):
		if is_sibling(p, b):
			return true
	for p in parents_of(game, b):
		if is_sibling(p, a):
			return true
	return false


static func is_married(c: Dictionary) -> bool:
	return not c.spouses.is_empty()


static func _polygamy(game: Game, c: Dictionary) -> bool:
	var f: Variant = game.content.get_def("faiths", c.faith)
	return f != null and f.get("doctrines", {}).get("polygamy", false) == true


static func can_marry(game: Game, a: Dictionary, b: Dictionary) -> bool:
	if not is_alive(a) or not is_alive(b) or a.id == b.id:
		return false
	if a.female == b.female or a.get("prison") != null or b.get("prison") != null:
		return false
	if is_married(a) and not _polygamy(game, a):
		return false
	if is_married(b) and not _polygamy(game, b):
		return false
	if a.spouses.has(b.id):
		return false
	var min_age = game.def_num("character.marriage_age", 16)
	if age_of(game, a) < min_age or age_of(game, b) < min_age:
		return false
	return not is_too_close_to_marry(game, a, b)


static func marry(game: Game, a: Dictionary, b: Dictionary) -> void:
	if not a.spouses.has(b.id):
		a.spouses.append(b.id)
	if not b.spouses.has(a.id):
		b.spouses.append(a.id)
	# Жена переезжает ко двору мужа (или наоборот, если муж безземельный, а жена правит).
	var host: Dictionary = a
	var guest: Dictionary = b
	if not b.titles.is_empty() and a.titles.is_empty():
		host = b
		guest = a
	elif a.female and not b.female:
		host = b
		guest = a
	if guest.titles.is_empty():
		set_liege(game, guest, host.id if not host.titles.is_empty() else host.liege)
	game.mark_people_dirty()
	game.on_action("on_marriage", {"type": "character", "id": a.id}, {"spouse": {"type": "character", "id": b.id}})
	game.emit("character.marriage", {"a": a, "b": b})


static func divorce(game: Game, a: Dictionary, b: Dictionary) -> void:
	a.spouses = a.spouses.filter(func(s): return s != b.id)
	b.spouses = b.spouses.filter(func(s): return s != a.id)
	if not a.former_spouses.has(b.id):
		a.former_spouses.append(b.id)
	if not b.former_spouses.has(a.id):
		b.former_spouses.append(a.id)
	game.mark_people_dirty()


static func set_liege(game: Game, c: Dictionary, liege: Variant) -> void:
	if liege == c.id:
		liege = null
	if c.liege == liege:
		return
	var old: Variant = c.liege
	c.liege = liege
	game.mark_index_dirty()
	# мнение о сюзерене зависит от сюзеренитета
	game.stat_cache.erase("op:%s>%s" % [c.id, old])
	game.stat_cache.erase("op:%s>%s" % [c.id, liege])
	game.emit("character.liege_changed", {"character": c, "old": old, "liege": liege})


# ------------------------------------------------------------ создание

static func create_dynasty(game: Game, culture: String, founder: Variant = null, dname: Variant = null) -> Dictionary:
	var cul: Variant = game.content.get_def("cultures", culture)
	var used := {}
	for d in game.state.dynasties.values():
		used[d.name] = true
	var n: Variant = dname
	var i := 0
	while n == null and i < 8:
		var key: Variant = null
		if cul != null and cul.get("dynasty_pattern") == "place":
			var provs := []
			for p in game.state.provinces.values():
				if p.culture == culture:
					provs.append(p.id)
			key = game.rng.pick(provs if not provs.is_empty() else game.state.provinces.keys())
		else:
			key = game.rng.pick(cul.get("male_names", []) if cul != null else [])
		var cand = "gen:%s:%s" % [culture, key if key != null else "Nameless"]
		if not used.has(cand) or i == 7:
			n = cand
		i += 1
	var d := {"id": game.new_id("dyn"), "name": n, "culture": culture, "prestige": 0.0, "founder": founder, "coa": null}
	game.state.dynasties[d.id] = d
	return d


static func pick_name(game: Game, culture: String, female: bool, father: Variant = null, mother: Variant = null) -> String:
	var cul: Variant = game.content.get_def("cultures", culture)
	var list: Array = (cul.get("female_names" if female else "male_names", []) if cul != null else [])
	# Иногда ребёнка называют в честь деда/бабки.
	var elders := []
	for p in [father, mother]:
		if p == null:
			continue
		for g in [game.ch(p.father), game.ch(p.mother)]:
			if g != null and g.female == female:
				elders.append(g)
	if not elders.is_empty() and game.rng.chance(game.def_num("character.name_after_relative_chance", 0.25)):
		return game.rng.pick(elders).name
	var n: Variant = game.rng.pick(list)
	return n if n != null else ("Anna" if female else "John")


static func skill_ids(game: Game) -> Array:
	var cached: Variant = game.engine.cache.get("skill_ids")
	if cached != null:
		return cached
	var skills: Array = game.content.all("skills").duplicate()
	Data.sort_by(skills, func(s): return Data.num(s.get("order")))
	var ids: Array = skills.map(func(s): return s.id)
	game.engine.cache["skill_ids"] = ids
	return ids


## Новый персонаж. opts: id, culture, faith, female, birth, age, name,
## dynasty ("new" — новая династия, null — без династии), father, mother,
## liege, traits, skills, gold, bare (без личности и образования).
static func create_character(game: Game, o: Dictionary) -> Dictionary:
	var rng := game.rng
	var father: Variant = game.ch(o.get("father"))
	var mother: Variant = game.ch(o.get("mother"))
	var female: bool = o.female if o.get("female") != null else rng.chance(0.5)
	var birth: int
	if o.get("birth") != null:
		birth = int(o.birth)
	else:
		birth = game.date - roundi((Data.num(o.get("age"), 20) + rng.next()) * GameDate.DAYS_PER_YEAR)
	var culture: String = o.culture
	var cul: Variant = game.content.get_def("cultures", culture)

	var dynasty: Variant
	if o.has("dynasty") and o.dynasty == null:
		dynasty = null
	elif o.get("dynasty") == "new":
		dynasty = create_dynasty(game, culture).id
	elif o.get("dynasty") != null:
		dynasty = o.dynasty
	else:
		dynasty = father.dynasty if (father != null and father.dynasty != null) else (mother.dynasty if mother != null else null)

	var skills := {}
	var given: Dictionary = o.get("skills", {}) if o.get("skills") != null else {}
	for s in skill_ids(game):
		var base: float
		if father != null and mother != null:
			base = (Data.num(father.skills.get(s)) + Data.num(mother.skills.get(s))) / 2.0 + rng.gauss(0, 3)
		else:
			base = rng.gauss(6, 5)
		skills[s] = maxi(0, roundi(Data.num(given.get(s), base)))

	var dna := {}
	for k in ["skin", "hair", "eyes", "face"]:
		if father != null and mother != null:
			dna[k] = Data.clampf01((Data.num(father.dna.get(k)) + Data.num(mother.dna.get(k))) / 2.0 + rng.gauss(0, 0.12))
		else:
			var rg: Variant = cul.get(k) if (cul != null and (k == "skin" or k == "hair")) else null
			var a := 0.0
			var b := 1.0
			if rg is Array and rg.size() >= 2:
				a = Data.num(rg[0])
				b = Data.num(rg[1])
			dna[k] = Data.clampf01(rng.range_float(a, b))

	var c := new_character_record()
	c.id = o.get("id") if o.get("id") != null else game.new_id("ch")
	c.name = o.name if o.get("name") != null else pick_name(game, culture, female, father, mother)
	c.female = female
	c.birth = birth
	c.dynasty = dynasty
	c.culture = culture
	c.faith = o.faith
	c.skills = skills
	c.gold = Data.num(o.get("gold"), 0.0)
	c.health = roundf(rng.gauss(game.def_num("character.base_health", 5), 1.5) * 10.0) / 10.0
	c.father = father.id if father != null else null
	c.mother = mother.id if mother != null else null
	c.liege = o.get("liege")
	c.dna = dna
	game.state.characters[c.id] = c
	if father != null:
		father.children.append(c.id)
	if mother != null:
		mother.children.append(c.id)

	for t in Data.as_array(o.get("traits")):
		add_trait(game, c, str(t))
	if not o.get("bare", false):
		assign_congenital(game, c, father, mother)
		assign_personality(game, c)
		if is_adult(game, c):
			assign_education(game, c)
	game.mark_people_dirty()
	return c


## Пустая запись персонажа со всеми полями (необязательные — null).
static func new_character_record() -> Dictionary:
	return {
		"id": "", "name": "", "nickname": null, "female": false, "birth": 0,
		"death": null, "death_reason": null, "killer": null,
		"dynasty": null, "culture": "", "faith": "",
		"traits": [], "skills": {}, "gold": 0.0, "prestige": 0.0, "piety": 0.0, "stress": 0.0, "health": 5.0,
		"father": null, "mother": null, "spouses": [], "former_spouses": [], "children": [],
		"liege": null, "titles": [], "capital": null, "claims": [],
		"opinions": {}, "modifiers": [], "hooks": [], "flags": {}, "vars": {},
		"pregnancy": null, "dna": {"skin": 0.5, "hair": 0.5, "eyes": 0.5, "face": 0.5},
		"succession_law": null, "levy_ratio": 1.0,
		"lifestyle": null, "council": null, "prison": null, "regiments": null, "secrets": null, "laws": null,
	}


static func assign_congenital(game: Game, c: Dictionary, father: Variant = null, mother: Variant = null) -> void:
	for t in game.content.all("traits"):
		if not t.get("genetic", false):
			continue
		var in_parents := 0
		for p in [father, mother]:
			if p != null and p.traits.has(t.id):
				in_parents += 1
		var chance: float = Data.num(t.get("inherit_chance"), 0.25) * in_parents if in_parents > 0 else Data.num(t.get("birth_chance"), 0.0)
		if chance > 0.0 and game.rng.chance(chance):
			add_trait(game, c, t.id)


static func assign_personality(game: Game, c: Dictionary, count: int = -1) -> void:
	var n: int = count if count >= 0 else int(game.def_num("character.personality_traits", 3))
	var pool: Array = game.content.all("traits").filter(func(t): return t.get("category") == "personality")
	var have := 0
	for t in c.traits:
		var d: Variant = trait_def(game, t)
		if d != null and d.get("category") == "personality":
			have += 1
	var guard := 0
	while have < n and guard < 50:
		guard += 1
		var blocked := {}
		for t in c.traits:
			blocked[t] = true
			var d: Variant = trait_def(game, t)
			if d != null:
				for o in d.get("opposites", []):
					blocked[o] = true
		var options := pool.filter(func(t):
			if blocked.has(t.id):
				return false
			for o in t.get("opposites", []):
				if c.traits.has(o):
					return false
			return true)
		var pick: Variant = game.rng.weighted(options, func(t): return Data.num(t.get("weight"), 1.0))
		if pick == null:
			break
		add_trait(game, c, pick.id)
		have += 1


static func assign_education(game: Game, c: Dictionary) -> void:
	for t in c.traits:
		var d: Variant = trait_def(game, t)
		if d != null and d.get("education") != null:
			return
	var edu: Array = game.content.all("traits").filter(func(t): return t.get("education") != null)
	if edu.is_empty():
		return
	var skills = Data.uniq(edu.map(func(t): return t.education.skill))
	var skill: Variant = game.rng.weighted(skills, func(s): return pow(maxf(1.0, Data.num(c.skills.get(s)) + 1.0), 2.0))
	var levels: Array = game.def_val("character.education_level_weights", [30, 40, 22, 8])
	var opts = edu.filter(func(t): return t.education.skill == skill)
	var pick: Variant = game.rng.weighted(opts, func(t):
		var lv = int(t.education.get("level", 1)) - 1
		return Data.num(levels[lv]) if lv >= 0 and lv < levels.size() else 1.0)
	if pick != null:
		add_trait(game, c, pick.id)


static func primary_tier_of(game: Game, c: Dictionary) -> int:
	return Titles.primary_tier(game, c)

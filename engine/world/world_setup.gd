class_name WorldSetup
extends RefCounted
## Создание новой партии по «закладке» (bookmarks): исторические персонажи
## и владельцы титулов из данных, недостающие правители и дворы
## генерируются.

const SAVE_VERSION := 2


static func empty_state(engine: GameEngine, bookmark: String, date: int, seed: int) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"bookmark": bookmark,
		"date": date,
		"start_date": date,
		"rng": {"s": seed & 0xFFFFFFFF},
		"next_id": 1,
		"player": null,
		"player_dynasty": null,
		"characters": {},
		"dynasties": {},
		"titles": {},
		"provinces": {},
		"wars": {},
		"armies": {},
		"schemes": {},
		"alliances": [],
		"truces": [],
		"scheduled": [],
		"pending_events": [],
		"pending_requests": [],
		"factions": {},
		"global_flags": {},
		"global_vars": {},
		"messages": [],
		"mod_data": {},
		"mods": engine.mods.map(func(m): return {"id": m.id, "version": m.manifest.get("version")}),
		"game_over": null,
	}


static func new_province_record(id: String, culture: String, faith: String, development: int, buildings: Array) -> Dictionary:
	return {"id": id, "culture": culture, "faith": faith, "development": development, "buildings": buildings,
		"construction": null, "occupant": null, "occupant_war": null, "siege": null, "modifiers": [], "flags": {}, "vars": {}}


static func setup_new_game(engine: GameEngine, bookmark_id: String, seed: int = -1) -> Game:
	var content := engine.content
	var bm: Variant = content.get_def("bookmarks", bookmark_id)
	if bm == null:
		push_error("Нет закладки \"%s\"" % bookmark_id)
		return null
	if seed < 0:
		seed = int(Time.get_unix_time_from_system() * 1000.0) % 2147483647
	var date = GameDate.parse(bm.date)
	var state := empty_state(engine, bookmark_id, date, seed)
	var game := Game.new(engine, state)
	game.quiet = true

	for d in content.all("provinces"):
		if d.get("impassable", false):
			continue
		state.provinces[d.id] = new_province_record(d.id, str(d.get("culture", "")), str(d.get("faith", "")), int(Data.num(d.get("development"), 5)), Data.as_array(d.get("buildings")).duplicate())
	for t in content.all("titles"):
		state.titles[t.id] = {"id": t.id, "holder": null, "history": []}
	for d in content.all("dynasties"):
		state.dynasties[d.id] = {"id": d.id, "name": "", "culture": d.get("culture"), "prestige": Data.num(d.get("prestige")), "founder": null, "coa": d.get("coa")}

	# Исторические персонажи
	var born = content.all("characters").filter(func(d): return GameDate.parse(d.birth) <= date)
	for d in born:
		var skills := {}
		var dsk: Dictionary = d.get("skills") if d.get("skills") is Dictionary else {}
		for s in Chars.skill_ids(game):
			# неуказанные навыки — по распределению навыка, на ступень выше среднего
			skills[s] = dsk[s] if dsk.has(s) else maxi(0, roundi(Chars.random_skill(game, s, 1.0, 6.0, 4.0)))
		var c := Chars.new_character_record()
		c.id = d.id
		c.name = d.name
		c.nickname = d.get("nickname")
		c.female = d.get("female", false) == true
		c.birth = GameDate.parse(d.birth)
		if d.get("death") != null and GameDate.parse(d.death) <= date:
			c.death = GameDate.parse(d.death)
		c.dynasty = d.get("dynasty")
		c.culture = d.culture
		c.faith = d.faith
		c.skills = skills
		c.gold = Data.num(d.get("gold"))
		c.prestige = Data.num(d.get("prestige"))
		c.piety = Data.num(d.get("piety"))
		c.health = Data.num(d.get("health"), 5)
		c.father = d.get("father")
		c.mother = d.get("mother")
		c.claims = Data.as_array(d.get("claims")).duplicate()
		var mods := []
		for m in Data.as_array(d.get("modifiers")):
			if m is String:
				mods.append({"id": m, "expires": null})
			else:
				mods.append({"id": m.id, "expires": date + roundi(Data.num(m.years) * GameDate.DAYS_PER_YEAR) if m.get("years") != null else null})
		c.modifiers = mods
		var dna: Dictionary = d.get("dna") if d.get("dna") is Dictionary else {}
		c.dna = {
			"skin": Data.num(dna.get("skin"), game.rng.next()),
			"hair": Data.num(dna.get("hair"), game.rng.next()),
			"eyes": Data.num(dna.get("eyes"), game.rng.next()),
			"face": Data.num(dna.get("face"), game.rng.next()),
		}
		state.characters[c.id] = c
		for t in Data.as_array(d.get("traits")):
			if Chars.trait_def(game, t) != null:
				Chars.add_trait(game, c, t)
			else:
				game.script_error("Персонаж %s: нет черты \"%s\"" % [d.id, t])
	for d in born:
		var c: Dictionary = state.characters[d.id]
		for p in [d.get("father"), d.get("mother")]:
			if p == null:
				continue
			var parent: Variant = state.characters.get(p)
			if parent != null:
				if not parent.children.has(c.id):
					parent.children.append(c.id)
			elif p == d.get("father"):
				c.father = null
			else:
				c.mother = null
		for sid in Data.as_array(d.get("spouse")):
			var s: Variant = state.characters.get(sid)
			if s == null:
				continue
			var both_alive: bool = c.death == null and s.death == null
			var key = "spouses" if both_alive else "former_spouses"
			if not c[key].has(s.id):
				c[key].append(s.id)
			if not s[key].has(c.id):
				s[key].append(c.id)
	game.mark_dirty()
	for c in game.living():
		Chars.assign_personality(game, c)
		if Chars.is_adult(game, c):
			Chars.assign_education(game, c)

	# Владельцы титулов
	var holders: Dictionary = bm.get("holders", {}) if bm.get("holders") is Dictionary else {}
	var holder_order := holders.keys()
	Data.sort_by(holder_order, func(t): return _tier_order(engine, t), true)
	for title in holder_order:
		var cid: Variant = holders[title]
		var c: Variant = state.characters.get(cid)
		if c == null or c.death != null or not state.titles.has(title):
			game.script_error("Закладка %s: не удалось выдать %s персонажу %s" % [bookmark_id, title, cid])
			continue
		Titles.transfer_title(game, title, cid)
	var bm_claims: Dictionary = bm.get("claims", {}) if bm.get("claims") is Dictionary else {}
	for cid in bm_claims:
		var c: Variant = state.characters.get(cid)
		if c != null:
			for t in Data.as_array(bm_claims[cid]):
				if not c.claims.has(t):
					c.claims.append(t)

	var generated := {}
	if bm.get("generate_missing", true) != false:
		generate_missing_holders(game, generated)

	# Сюзерены правителей
	var vassal_of: Variant = bm.get("vassal_of")
	var rulers := game.rulers().duplicate()
	Data.sort_by(rulers, func(r): return Titles.primary_tier(game, r))
	for c in rulers:
		if vassal_of is Dictionary and vassal_of.has(c.id):
			Chars.set_liege(game, c, vassal_of[c.id])
		else:
			var lh: Variant = Titles.de_jure_liege_holder(game, c)
			Chars.set_liege(game, c, lh.id if lh != null else null)
	for c in game.rulers():
		Titles.fix_liege_consistency(game, c)

	# Дворы безземельных
	for c in game.living():
		if not c.titles.is_empty() or c.liege != null:
			continue
		var court: Variant = _court_of(game, c, 0)
		if court == null:
			var same = game.rulers().filter(func(r): return r.culture == c.culture)
			Data.sort_by(same, func(r): return Titles.primary_tier(game, r), true)
			var pick: Variant = same[0] if not same.is_empty() else (game.rulers()[0] if not game.rulers().is_empty() else null)
			court = pick.id if pick != null else null
		Chars.set_liege(game, c, court)

	# Семьи и дворы сгенерированных правителей
	for id in generated:
		generate_family(game, state.characters[id])
	for r in game.rulers().duplicate():
		fill_court(game, r)

	for al in Data.as_array(bm.get("alliances")):
		if al is Array and al.size() >= 2 and game.is_alive(al[0]) and game.is_alive(al[1]):
			state.alliances.append({"a": al[0], "b": al[1], "since": date})

	# Стартовые казна и престиж
	var start_gold: Array = game.def_val("start_gold_by_tier", [0, 30, 80, 200, 400])
	var start_prestige: Array = game.def_val("start_prestige_by_tier", [0, 50, 150, 400, 800])
	for r in game.rulers():
		var d: Variant = content.get_def("characters", r.id)
		var tier := Titles.primary_tier(game, r)
		if d == null or d.get("gold") == null:
			r.gold = Data.num(start_gold[tier]) if tier < start_gold.size() else 0.0
		if d == null or d.get("prestige") == null:
			r.prestige = Data.num(start_prestige[tier]) if tier < start_prestige.size() else 0.0
	game.mark_dirty()
	game.quiet = false
	engine.hooks.emit("game.setup", {"game": game, "bookmark": bm})
	for r in game.rulers().duplicate():
		game.on_action("on_game_start", {"type": "character", "id": r.id})
	return game


static func _court_of(game: Game, c: Dictionary, depth: int) -> Variant:
	if depth > 6:
		return null
	var def: Variant = game.content.get_def("characters", c.id)
	if def != null and def.get("court") != null and game.state.characters.has(def.court):
		return def.court
	var rel := []
	for id in c.spouses + [c.father, c.mother]:
		var x: Variant = game.ch(id)
		if x != null and x.death == null:
			rel.append(x)
	for x in rel:
		if not x.titles.is_empty():
			return x.id
	for r in rel:
		var ct: Variant = _court_of(game, r, depth + 1)
		if ct != null:
			return ct
	return null


static func _tier_order(engine: GameEngine, title: String) -> int:
	var t: Variant = engine.content.get_def("titles", title)
	return Titles.TIERS.find(t.tier if t != null else "county")


static func _new_ruler(game: Game, county: String, generated: Dictionary) -> Dictionary:
	var p: Variant = game.state.provinces.get(county)
	var c := Chars.create_character(game, {
		"culture": p.culture if p != null else "unknown",
		"faith": p.faith if p != null else "unknown",
		"female": game.rng.chance(game.def_num("setup.female_ruler_chance", 0.04)),
		"age": game.rng.range_int(20, 55),
		"dynasty": "new",
	})
	generated[c.id] = true
	return c


static func generate_missing_holders(game: Game, generated: Dictionary) -> void:
	var content := game.content
	for d in content.all("titles"):
		if d.tier != "duchy":
			continue
		if game.state.titles[d.id].holder != null or d.get("no_generate", false):
			continue
		var counties = Titles.de_jure_counties(game, d.id).filter(func(c): return game.state.titles.has(c))
		if counties.size() < 2 or counties.any(func(c): return game.state.titles[c].holder != null):
			continue
		var cap: String = d.capital if (d.get("capital") != null and counties.has(d.capital)) else counties[0]
		var duke := _new_ruler(game, cap, generated)
		Titles.transfer_title(game, d.id, duke.id)
		Titles.transfer_title(game, cap, duke.id)
		if counties.size() >= 4:
			for c in counties:
				if c != cap:
					Titles.transfer_title(game, c, duke.id)
					break
	for d in content.all("titles"):
		if d.tier != "county":
			continue
		if game.state.titles[d.id].holder != null or not game.state.provinces.has(d.id):
			continue
		var count = _new_ruler(game, d.id, generated)
		Titles.transfer_title(game, d.id, count.id)


static func generate_family(game: Game, r: Dictionary) -> void:
	var age = floori((game.date - int(r.birth)) / float(GameDate.DAYS_PER_YEAR))
	if age < 18 or not r.spouses.is_empty():
		return
	if not game.rng.chance(game.def_num("setup.married_chance", 0.75)):
		return
	var spouse := Chars.create_character(game, {
		"culture": r.culture, "faith": r.faith, "female": not r.female,
		"age": maxi(16, age + game.rng.range_int(-8, 3)),
		"dynasty": "new" if game.rng.chance(0.6) else null,
		"liege": r.id,
	})
	r.spouses.append(spouse.id)
	spouse.spouses.append(r.id)
	var father: Dictionary = spouse if r.female else r
	var mother: Dictionary = r if r.female else spouse
	var mother_age = floori((game.date - int(mother.birth)) / float(GameDate.DAYS_PER_YEAR))
	var fertile_years := maxi(0, mini(mother_age, 45) - 17)
	var n := mini(5, game.rng.range_int(0, ceili(fertile_years / 4.0)))
	for i in n:
		var years_ago := game.rng.range_int(0, maxi(0, fertile_years - 1))
		Chars.create_character(game, {
			"culture": father.culture, "faith": father.faith, "father": father.id, "mother": mother.id,
			"birth": game.date - years_ago * GameDate.DAYS_PER_YEAR - game.rng.range_int(0, 300),
			"liege": r.id,
		})


static func fill_court(game: Game, r: Dictionary) -> void:
	var by_tier: Array = game.def_val("court.min_courtiers_by_tier", [0, 2, 3, 5, 6])
	var pt := Titles.primary_tier(game, r)
	var mn = int(Data.num(by_tier[pt])) if pt < by_tier.size() else 2
	var have = game.courtiers_of(r.id).size()
	while have < mn:
		Chars.create_character(game, {
			"culture": r.culture, "faith": r.faith, "age": game.rng.range_int(16, 45),
			"dynasty": "new" if game.rng.chance(game.def_num("court.noble_courtier_chance", 0.5)) else null,
			"liege": r.id,
		})
		have += 1

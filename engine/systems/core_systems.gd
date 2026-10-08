class_name CoreSystems
extends RefCounted
## Встроенные системы симуляции. Каждая — независимый модуль с методами
## on_day/on_month/on_year. Мод может заменить любую (api.systems.replace),
## удалить (api.systems.remove) или добавить свою.
##
## Система — словарь {id, order, on_day?: Callable(game), on_month?: ..., on_year?: ...};
## меньший order выполняется раньше.


static func builtin() -> Array:
	return [
		{"id": "upkeep", "order": 0, "on_month": _upkeep_month},
		{"id": "economy", "order": 10, "on_character_month": _economy_char},
		{"id": "demography", "order": 20, "on_character_month": _demography_char, "on_year": _demography_year},
		{"id": "events", "order": 30, "on_day": func(game: Game): game.events.process_scheduled(),
			"on_character_month": func(game: Game, c: Dictionary):
				if not c.titles.is_empty():
					game.on_action("on_monthly_pulse", {"type": "character", "id": c.id}),
			"on_year": func(game: Game): _pulse(game, "on_yearly_pulse")},
		{"id": "schemes", "order": 40, "on_month": Schemes.monthly_schemes},
		{"id": "military", "order": 50, "on_day": Military.daily_military, "on_month": Military.regen_levies},
		{"id": "war", "order": 55, "on_month": _war_month},
		{"id": "construction", "order": 60, "on_day": Decisions.daily_construction},
		{"id": "ai", "order": 70, "on_day": Ai.daily_ai},
		{"id": "development", "order": 80, "on_year": _development_year},
	]


static func _pulse(game: Game, action: String) -> void:
	for c in game.rulers().duplicate():
		if c.death == null:
			game.on_action(action, {"type": "character", "id": c.id})


static func _upkeep_month(game: Game) -> void:
	var now := game.date
	for c in game.living():
		if not c.modifiers.is_empty():
			c.modifiers = c.modifiers.filter(func(m): return m.get("expires") == null or m.expires > now)
		for k in c.flags.keys():
			var v: Variant = c.flags[k]
			if k.begins_with("trait_expires:") and v <= now:
				Chars.remove_trait(game, c, k.substr("trait_expires:".length()))
				c.flags.erase(k)
			elif k.begins_with("tmp:") and v <= now:
				c.flags.erase(k)
		c.hooks = c.hooks.filter(func(h): return h.get("expires") == null or h.expires > now)
	for p in game.state.provinces.values():
		if not p.modifiers.is_empty():
			p.modifiers = p.modifiers.filter(func(m): return m.get("expires") == null or m.expires > now)
	for k in game.state.global_flags.keys():
		var v: Variant = game.state.global_flags[k]
		if v != null and v != 0 and v <= now:
			game.state.global_flags.erase(k)
	Opinion.decay_opinions(game)
	Titles.enforce_landed_titles(game)
	game.stat_cache.clear()


## Помесячно для персонажа (в его день): доход, престиж и благочестие
## правителя, доход безземельных, снятие стресса.
static func _economy_char(game: Game, c: Dictionary) -> void:
	if not c.titles.is_empty():
		var gold := Economy.monthly_income(game, c)
		var prestige := Economy.monthly_prestige(game, c)
		var piety := Economy.monthly_piety(game, c)
		c.gold += gold
		c.prestige += prestige
		c.piety += piety
		var dyn: Variant = game.state.dynasties.get(c.dynasty) if c.dynasty != null else null
		if dyn != null and prestige > 0:
			dyn.prestige = float(dyn.prestige) + prestige * game.def_num("economy.dynasty_prestige_share", 0.1)
	else:
		var flat := Stats.stat(game, c, "monthly_income")
		if flat != 0.0:
			c.gold += flat
	if c.stress > 0:
		c.stress = maxf(0.0, float(c.stress) - game.def_num("character.stress_decay", 2))
	var lvl = floori(float(c.stress) / 100.0)
	var prev = int(Data.num(c.vars.get("stress_level")))
	if lvl > prev:
		c.vars["stress_level"] = lvl
		game.on_action("on_stress_level", {"type": "character", "id": c.id})
	elif lvl < prev:
		c.vars["stress_level"] = lvl


static func _yearly_mortality(game: Game, age: int) -> float:
	# Таблица по возрастам 0–120 — раз в месяц (defines могут поменять моды).
	var by_age: PackedFloat64Array = game.cached_monthly("mortality_by_age", func():
		var arr := PackedFloat64Array()
		for a in 121:
			arr.append(_mortality_at(game, a))
		return arr)
	return by_age[clampi(age, 0, 120)]


static func _mortality_at(game: Game, age: int) -> float:
	var table: Array = game.def_val("character.mortality", [[0, 0.03], [5, 0.008], [16, 0.006], [40, 0.015], [60, 0.05], [80, 0.25]])
	if age <= Data.num(table[0][0]):
		return Data.num(table[0][1])
	for i in range(1, table.size()):
		var a1 = Data.num(table[i - 1][0])
		var p1 = Data.num(table[i - 1][1])
		var a2 = Data.num(table[i][0])
		var p2 = Data.num(table[i][1])
		if age <= a2:
			return p1 + (age - a1) / (a2 - a1) * (p2 - p1)
	return Data.num(table[table.size() - 1][1])


static func monthly_death_chance(game: Game, c: Dictionary) -> float:
	var age := Chars.age_of(game, c)
	var health := Stats.stat(game, c, "health")
	var y = _yearly_mortality(game, age) * exp(-game.def_num("character.health_mortality_factor", 0.35) * (health - game.def_num("character.base_health", 5)))
	return 1.0 - pow(1.0 - minf(0.95, y), 1.0 / 12.0)


## Помесячно для персонажа (в его день): болезни, смерть, совершеннолетие, дети.
static func _demography_char(game: Game, c: Dictionary) -> void:
	var adult = game.def_num("character.adult_age", 16)
	# Черты-болезни: шанс смерти и излечения
	var trait_death := 0.0
	for t in c.traits.duplicate():
		var d: Variant = game.content.get_def("traits", t)
		if d == null:
			continue
		trait_death += Data.num(d.get("monthly_death_chance"))
		var cure := Data.num(d.get("monthly_cure_chance"))
		if cure > 0.0 and game.rng.chance(cure):
			Chars.remove_trait(game, c, t)
	if game.rng.chance(monthly_death_chance(game, c) + trait_death):
		var illness := false
		for t in c.traits:
			var d: Variant = game.content.get_def("traits", t)
			if d != null and Data.num(d.get("monthly_death_chance")) > 0.0:
				illness = true
				break
		Succession.kill_character(game, c, "illness" if illness else ("childhood" if Chars.age_of(game, c) < adult else "natural"))
		return
	# Совершеннолетие
	if not c.flags.has("adult") and Chars.age_of(game, c) >= adult:
		c.flags["adult"] = 0
		Chars.assign_education(game, c)
		game.on_action("on_coming_of_age", {"type": "character", "id": c.id})
	if c.female:
		_monthly_fertility(game, c)


static func _demography_year(game: Game) -> void:
	for r in game.rulers().duplicate():
		if r.death != null:
			continue
		WorldSetup.fill_court(game, r)
		_trim_court(game, r)
	_prune_dead(game)


static func _monthly_fertility(game: Game, mother: Dictionary) -> void:
	if mother.pregnancy != null:
		if mother.pregnancy.due <= game.date:
			_give_birth(game, mother)
		return
	var age := Chars.age_of(game, mother)
	if age < game.def_num("character.min_fertile_age", 16) or age > game.def_num("character.max_fertile_age", 45):
		return
	var husband: Variant = null
	for id in mother.spouses:
		var s: Variant = game.ch(id)
		if s != null and s.death == null and not s.female:
			husband = s
			break
	if husband == null:
		return
	var alive = Data.count(mother.children, func(id): return game.is_alive(id))
	# Мягкий предел численности мира: при перенаселении рожают реже (держит симуляцию быстрой).
	var pop := game.living().size()
	var soft = game.def_num("character.population_soft_cap", 900)
	var crowd = maxf(0.1, pow(soft / pop, 3.0)) if pop > soft else 1.0
	var p = crowd * game.def_num("character.base_conception", 0.05) \
		* maxf(0.0, Stats.stat(game, mother, "fertility")) \
		* maxf(0.0, Stats.stat(game, husband, "fertility")) \
		* 4.0 * pow(game.def_num("character.conception_child_decay", 0.85), alive)
	if game.rng.chance(p):
		mother.pregnancy = {"father": husband.id, "due": game.date + int(game.def_num("character.pregnancy_days", 270))}
		game.on_action("on_pregnancy", {"type": "character", "id": mother.id}, {"father": {"type": "character", "id": husband.id}})


static func _give_birth(game: Game, mother: Dictionary) -> void:
	var father: Variant = game.ch(mother.pregnancy.father)
	mother.pregnancy = null
	var court: Variant
	if not mother.titles.is_empty():
		court = mother.id
	elif father != null and not father.titles.is_empty():
		court = father.id
	else:
		court = mother.liege if mother.liege != null else (father.liege if father != null else null)
	var base: Dictionary = father if (father != null and mother.titles.is_empty()) else mother
	var child := Chars.create_character(game, {
		"culture": base.culture, "faith": base.faith,
		"father": father.id if father != null else null, "mother": mother.id,
		"birth": game.date, "liege": court,
	})
	var scopes = {"mother": {"type": "character", "id": mother.id}}
	if father != null:
		scopes["father"] = {"type": "character", "id": father.id}
	game.on_action("on_birth", {"type": "character", "id": child.id}, scopes)
	game.emit("character.birth", {"character": child, "mother": mother, "father": father})
	game.message(game.loc.t("msg.birth", {"child": game.scope_name({"type": "character", "id": child.id}), "mother": game.scope_name({"type": "character", "id": mother.id})}),
		"birth", {"type": "character", "id": child.id}, [mother.id, father.id if father != null else null])
	if game.rng.chance(game.def_num("character.childbirth_death_chance", 0.02)):
		Succession.kill_character(game, mother, "childbirth")


## Двор не растёт бесконечно: лишние безродные одинокие придворные
## (не родня правителю) покидают мир. Это держит численность персонажей
## в разумных пределах и симуляцию быстрой.
static func _trim_court(game: Game, r: Dictionary) -> void:
	var by_tier: Array = game.def_val("court.max_courtiers_by_tier", [0, 8, 12, 16, 20])
	var pt := Titles.primary_tier(game, r)
	var mx = int(Data.num(by_tier[pt])) if pt < by_tier.size() else 10
	var courtiers = game.courtiers_of(r.id)
	if courtiers.size() <= mx:
		return
	# Уходят одинокие взрослые без детей: чужаки, а затем и дальняя родня
	# (близкие правителя и ближайшие наследники остаются).
	var keep := {}
	for id in Succession.heirs_of(game, r).slice(0, 3):
		keep[id] = true
	var removable := courtiers.filter(func(c):
		return not game.is_player(c.id) and c.spouses.is_empty() \
			and not c.children.any(func(x): return game.is_alive(x)) \
			and not keep.has(c.id) and not Chars.is_close_family(game, c, r) \
			and not r.spouses.has(c.id) and c.get("prison") == null and Chars.is_adult(game, c))
	# сначала чужие, потом родня
	Data.sort_by(removable, func(c): return 1 if c.dynasty == r.dynasty else 0)
	for c in removable.slice(0, courtiers.size() - mx):
		for pid in [c.father, c.mother]:
			var p: Variant = game.ch(pid)
			if p != null:
				p.children = p.children.filter(func(x): return x != c.id)
		for s in game.state.schemes.values():
			if s.owner == c.id or s.target == c.id:
				game.state.schemes.erase(s.id)
		game.state.characters.erase(c.id)
	game.mark_index_dirty()
	game.month_cache.clear() # рыцари, советы и т. п. могли ссылаться на ушедших


static func _prune_dead(game: Game) -> void:
	var limit = game.date - roundi(game.def_num("character.prune_after_years", 60) * GameDate.DAYS_PER_YEAR)
	var player: Variant = game.state.player
	var founders := {}
	for d in game.state.dynasties.values():
		if d.get("founder") != null:
			founders[d.founder] = true
	for c in game.state.characters.values():
		if c.death == null or c.death > limit or c.id == player:
			continue
		if c.children.any(func(id): return game.is_alive(id)):
			continue
		if founders.has(c.id):
			continue
		game.state.characters.erase(c.id)
	game.mark_index_dirty()


static func _war_month(game: Game) -> void:
	Wars.validate_wars(game)
	for w in game.state.wars.values():
		Wars.update_ticking(game, w)


static func _development_year(game: Game) -> void:
	for p in game.state.provinces.values():
		var t: Variant = game.state.titles.get(p.id)
		var holder: Variant = game.ch(t.holder) if t != null else null
		var chance = game.def_num("development.base_growth", 0.12) + Stats.prov_stat(game, p.id, "development_growth")
		if holder != null:
			chance += Stats.skill(game, holder, "stewardship") * game.def_num("development.growth_per_stewardship", 0.01) + Stats.stat(game, holder, "development_growth")
		if p.occupant == null and game.rng.chance(maxf(0.0, chance)):
			p.development = mini(int(game.def_num("development.max", 100)), int(p.development) + 1)

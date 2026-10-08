class_name Succession
extends RefCounted
## Наследование. Закон наследования ссылается на «алгоритм» из реестра
## registries.successionAlgorithms — мод может добавить свой (например,
## выборную монархию), не трогая движок.
##
## Алгоритм — словарь:
##   label?: текст
##   heirs: Callable(game, c, law) -> Array[String]  — линия наследования, первый — основной
##   distribute?: Callable(game, c, law, heirs) -> Dictionary  — титул → наследник


static func law_of(game: Game, c: Dictionary) -> Variant:
	var id: Variant = c.succession_law
	if id == null:
		var cul: Variant = game.content.get_def("cultures", c.culture)
		id = cul.get("succession_law") if cul != null else null
	if id == null:
		id = game.def_val("succession.default_law")
	var law: Variant = game.content.get_def("succession_laws", id)
	if law != null:
		return law
	var all := game.content.all("succession_laws")
	return all[0] if not all.is_empty() else null


static func gender_sort(game: Game, list: Array, gender: Variant) -> Array:
	var by_age := list.duplicate()
	Data.sort_by(by_age, func(c): return c.birth)
	var men = by_age.filter(func(c): return not c.female)
	var women = by_age.filter(func(c): return c.female)
	match gender:
		"male_only": return men
		"female_only": return women
		"male_preference": return men + women
		"female_preference": return women + men
	return by_age


static func alive_children(game: Game, c: Dictionary) -> Array:
	var out := []
	for id in c.children:
		var x: Variant = game.ch(id)
		if Chars.is_alive(x):
			out.append(x)
	return out


## Линия наследования по крови: дети → внуки → братья/сёстры → племянники → династия.
static func blood_line(game: Game, c: Dictionary, gender: Variant) -> Array:
	var out := []
	var seen = {c.id: true}
	var push := func(list: Array) -> void:
		for x in gender_sort(game, list, gender):
			if not seen.has(x.id):
				seen[x.id] = true
				out.append(x.id)
	push.call(alive_children(game, c))
	var grand := []
	for id in c.children:
		var chd: Variant = game.ch(id)
		if chd != null:
			grand.append_array(alive_children(game, chd))
	push.call(grand)
	var sibs := Chars.siblings_of(game, c)
	push.call(sibs.filter(func(s): return Chars.is_alive(s)))
	var nephews := []
	for s in sibs:
		nephews.append_array(alive_children(game, s))
	push.call(nephews)
	if c.dynasty != null:
		var dyn = game.living().filter(func(x): return x.dynasty == c.dynasty and x.id != c.id)
		push.call(dyn.filter(func(x): return Chars.is_adult(game, x)))
		push.call(dyn)
	return out


static func builtin_algorithms() -> Dictionary:
	return {
		"primogeniture": {
			"heirs": func(game: Game, c: Dictionary, law: Dictionary) -> Array: return blood_line(game, c, law.get("gender")),
		},
		"partition": {
			"heirs": func(game: Game, c: Dictionary, law: Dictionary) -> Array: return blood_line(game, c, law.get("gender")),
			"distribute": func(game: Game, c: Dictionary, law: Dictionary, heirs: Array) -> Dictionary: return _partition(game, c, law, heirs),
		},
		"seniority": {
			"heirs": func(game: Game, c: Dictionary, law: Dictionary) -> Array:
				var dyn := []
				if c.dynasty != null:
					dyn = game.living().filter(func(x): return x.dynasty == c.dynasty and x.id != c.id and Chars.is_adult(game, x))
				var sorted := gender_sort(game, dyn, law.get("gender"))
				Data.sort_by(sorted, func(x): return x.birth)
				var ids = sorted.map(func(x): return x.id)
				for id in blood_line(game, c, law.get("gender")):
					if not ids.has(id):
						ids.append(id)
				return ids,
		},
	}


static func _partition(game: Game, c: Dictionary, law: Dictionary, heirs: Array) -> Dictionary:
	var out := {}
	if heirs.is_empty():
		return out
	var children = gender_sort(game, alive_children(game, c), law.get("gender")).map(func(x): return x.id)
	var sharers: Array = children.slice(0, int(game.def_num("succession.max_partition_heirs", 4))) if not children.is_empty() else [heirs[0]]
	var primary: String = c.titles[0]
	out[primary] = sharers[0]
	var cap: Variant = Titles.capital_of(game, c)
	if cap != null:
		out[cap] = sharers[0]
	var rest: Array = c.titles.filter(func(t): return not out.has(t))
	Data.sort_by(rest, func(t): return Titles.tier_of(game, t), true)
	var i := 1
	for t in rest:
		# Графство идёт тому, кто получил его де-юре герцогство (не дробим герцогства).
		var owner: Variant = null
		var up: Variant = Titles.de_jure_liege(game, t)
		while up != null and owner == null:
			owner = out.get(up)
			up = Titles.de_jure_liege(game, up)
		if owner == null:
			owner = sharers[i % sharers.size()]
			i += 1
		out[t] = owner
	return out


static func heirs_of(game: Game, c: Dictionary) -> Array:
	var law: Variant = law_of(game, c)
	if law == null:
		return blood_line(game, c, "male_preference")
	var algo: Variant = game.engine.succession_algorithms.get_item(str(law.get("algorithm")))
	if algo == null:
		game.script_error("Нет алгоритма наследования \"%s\"" % law.get("algorithm"))
		return blood_line(game, c, law.get("gender"))
	return algo.heirs.call(game, c, law)


static func primary_heir(game: Game, c: Dictionary) -> Variant:
	var h := heirs_of(game, c)
	return game.ch(h[0]) if not h.is_empty() else null


# ------------------------------------------------------------ смерть

static func kill_character(game: Game, c: Dictionary, reason: String = "natural", killer: Variant = null) -> void:
	if c.death != null:
		return
	if not game.engine.hooks.veto("character.before_death", {"game": game, "character": c, "reason": reason, "killer": killer}):
		return
	c.death = game.date
	c.death_reason = reason
	c.killer = killer
	game.mark_dirty()
	game.on_action("on_death", {"type": "character", "id": c.id}, {"killer": {"type": "character", "id": killer}} if killer != null else {})

	for sid in c.spouses:
		var s: Variant = game.ch(sid)
		if s == null:
			continue
		s.spouses = s.spouses.filter(func(x): return x != c.id)
		if not s.former_spouses.has(c.id):
			s.former_spouses.append(c.id)
	for x in c.spouses:
		if not c.former_spouses.has(x):
			c.former_spouses.append(x)
	c.spouses = []
	c.pregnancy = null
	for id in game.state.schemes.keys():
		var sch: Dictionary = game.state.schemes[id]
		if sch.owner == c.id or sch.target == c.id:
			game.state.schemes.erase(id)
	game.state.alliances = game.state.alliances.filter(func(a): return a.a != c.id and a.b != c.id)

	var was_player = game.is_player(c.id)
	var heir: Variant = inherit(game, c) if not c.titles.is_empty() else null
	game.mark_dirty()

	var nm = game.scope_name({"type": "character", "id": c.id}, "full_name")
	game.message(game.loc.t_or("death." + reason, game.loc.t("death.generic", {"who": nm}), {"who": nm}), "death", {"type": "character", "id": c.id}, [c.id, c.liege])
	game.emit("character.death", {"character": c, "reason": reason, "killer": killer, "heir": heir.id if heir != null else null})

	if was_player:
		if heir != null:
			game.state.player = heir.id
			game.message(game.loc.t("msg.you_now_play", {"who": game.scope_name({"type": "character", "id": heir.id}, "full_name")}), "event", {"type": "character", "id": heir.id})
			game.emit("player.succession", {"from": c.id, "to": heir.id})
			game.on_action("on_player_succession", {"type": "character", "id": heir.id}, {"predecessor": {"type": "character", "id": c.id}})
		else:
			game.state.game_over = {"reason": "no_heir", "date": game.date}
			game.emit("game.over", {"reason": "no_heir"})


## Распределяет титулы умершего. Возвращает основного наследника.
static func inherit(game: Game, c: Dictionary) -> Variant:
	var law: Variant = law_of(game, c)
	var algo: Variant = game.engine.succession_algorithms.get_item(str(law.get("algorithm"))) if law != null else null
	var heirs: Array = algo.heirs.call(game, c, law) if (law != null and algo != null) else blood_line(game, c, "male_preference")
	heirs = heirs.filter(func(id): return Chars.is_alive(game.ch(id)))
	var old_liege: Variant = game.ch(c.liege)
	var vassals = game.vassals_of(c.id)
	var courtiers = game.courtiers_of(c.id)
	var titles: Array = c.titles.duplicate()

	var primary: Variant = game.ch(heirs[0]) if not heirs.is_empty() else null
	var distribution := {}
	if primary == null:
		if old_liege != null and Chars.is_alive(old_liege):
			# Выморочные титулы возвращаются сюзерену.
			primary = old_liege
			for t in titles:
				distribution[t] = old_liege.id
		else:
			# Независимый правитель без наследников: появляется новый род.
			var cap: Variant = Titles.capital_of(game, c)
			var pst: Variant = game.state.provinces.get(cap) if cap != null else null
			var pdef: Variant = game.content.get_def("provinces", cap) if cap != null else null
			var culture: String = pst.culture if pst != null else (pdef.get("culture", c.culture) if pdef != null else c.culture)
			var faith: String = pst.faith if pst != null else (pdef.get("faith", c.faith) if pdef != null else c.faith)
			primary = Chars.create_character(game, {"culture": culture, "faith": faith, "female": false, "age": game.rng.range_int(20, 40), "dynasty": "new"})
			for t in titles:
				distribution[t] = primary.id
	else:
		if law != null and algo != null and algo.has("distribute"):
			distribution = algo.distribute.call(game, c, law, heirs)
		for t in titles:
			if distribution.get(t) == null:
				distribution[t] = primary.id

	var primary_was_landed: bool = not primary.titles.is_empty()
	# Передаём титулы (в порядке убывания ранга, чтобы основной титул был первым).
	var order := titles.duplicate()
	Data.sort_by(order, func(t): return Titles.tier_of(game, t), true)
	for t in order:
		Titles.transfer_title(game, t, distribution[t], primary.id)
	primary.gold += c.gold
	c.gold = 0.0

	# Сюзеренитет наследников.
	var heir_chars := []
	for id in Data.uniq(distribution.values()):
		var h: Variant = game.ch(id)
		if h != null:
			heir_chars.append(h)
	var old_liege_id: Variant = old_liege.id if old_liege != null else null
	for h in heir_chars:
		if h.id == primary.id:
			if not primary_was_landed or h.liege == c.id:
				Chars.set_liege(game, h, old_liege_id if old_liege_id != h.id else null)
			continue
		if h.liege == c.id or h.liege == null or h.liege == primary.liege:
			Chars.set_liege(game, h, primary.id if Titles.primary_tier(game, h) < Titles.primary_tier(game, primary) else old_liege_id)
	# Вассалы умершего уходят к наследнику, держащему их де-юре сюзеренный титул.
	for v in vassals:
		if not Chars.is_alive(v) or heir_chars.any(func(h): return h.id == v.id):
			continue
		var target: Variant = null
		var up: Variant = Titles.de_jure_liege(game, v.titles[0]) if not v.titles.is_empty() else null
		while up != null and target == null:
			var holder: Variant = distribution.get(up)
			if holder != null and Titles.primary_tier(game, game.ch(holder)) > Titles.primary_tier(game, v):
				target = holder
			up = Titles.de_jure_liege(game, up)
		Chars.set_liege(game, v, target if target != null else primary.id)
	# Придворные: к наследнику-родственнику или к основному наследнику.
	for ct in courtiers:
		if not Chars.is_alive(ct) or not ct.titles.is_empty():
			continue
		var kin: Variant = null
		for h in heir_chars:
			if not h.titles.is_empty() and (h.spouses.has(ct.id) or ct.father == h.id or ct.mother == h.id):
				kin = h
				break
		Chars.set_liege(game, ct, kin.id if kin != null else (primary.id if not primary.titles.is_empty() else primary.liege))
	# Войны и армии переходят к основному наследнику.
	for w in game.state.wars.values():
		if w.attackers.has(c.id) or w.defenders.has(c.id):
			w.attackers = Data.uniq(w.attackers.map(func(x): return primary.id if x == c.id else x))
			w.defenders = Data.uniq(w.defenders.map(func(x): return primary.id if x == c.id else x))
			if w.attacker == c.id:
				w.attacker = primary.id
			if w.defender == c.id:
				w.defender = primary.id
	for a in game.state.armies.values():
		if a.owner == c.id:
			a.owner = primary.id
			a.commander = null
		if a.commander == c.id:
			a.commander = null
	c.titles = []
	game.mark_dirty()
	for h in heir_chars:
		game.on_action("on_inheritance", {"type": "character", "id": h.id}, {"predecessor": {"type": "character", "id": c.id}})
	game.emit("succession", {"deceased": c, "heirs": heir_chars.map(func(h): return h.id), "primary": primary.id, "distribution": distribution})
	if Titles.domain_counties(game, primary).is_empty() and not primary.titles.is_empty():
		primary.capital = null
	return primary

class_name Upbringing
extends EngineFeature
## Детство, воспитание и регентство (как в CK3).
##
## Детство. В childhood_age лет ребёнок получает детскую черту (category:
## childhood) — буйный, обаятельный, любознательный… У черты есть
##   childhood: { aptitude: <навык>, personality: [черты характера] }
## aptitude — к чему у ребёнка склонность (воспитание в этом навыке идёт
## быстрее), personality — какими чертами характера она скорее всего
## обернётся. Если defines.character.personality_at_adulthood, характер
## складывается только к совершеннолетию: из детской черты, от опекуна и
## случайно.
##
## Воспитание. С education_age лет у ребёнка есть направление воспитания
## (навык с чертами образования) и опекун. Каждый месяц копятся очки
## воспитания: база + навык опекуна в этом направлении + склонность +
## собственный навык ребёнка (× 1 + education_gain_mult). Без опекуна —
## вдвое медленнее. В совершеннолетие очки (с разбросом) дают уровень
## черты образования: пороги level_thresholds. Опекун может передать
## воспитаннику одну из своих черт характера.
##
## Регентство. Пока правитель — ребёнок, державой правит регент: мать,
## канцлер, старшие родичи или лучший из придворных и вассалов. Его навыки
## дают державе мнение вассалов, налог и ополчение; честолюбивый и жадный
## регент тянет казну (секрет казнокрада), а регент-наследник может
## замыслить убийство. В совершеннолетие правителя — событие regency_end_event.
##
##   defines.upbringing: { childhood_age, education_age, base_points,
##     no_guardian_mult, per_guardian_skill, guardian_skill_cap, aptitude_bonus, own_skill_share,
##     initial_monthly, level_thresholds, final_spread, max_wards,
##     adopt_guardian_trait, childhood_bias, regent_*, child_ruler_opinion,
##     regency_end_event }
## Состояние: c.vars.edu_focus, c.vars.edu_points, c.vars.guardian (у ребёнка);
## c.vars.regent (у правителя-ребёнка).
## Хуки: upbringing.guardian_set — {child, guardian}; upbringing.educated —
## {character, trait, guardian}; regency.started — {ruler, regent};
## regency.ended — {ruler, regent}.

const OWNER := "core/upbringing"


func _init() -> void:
	id = "upbringing"
	doc = "Детство, опекуны и воспитание, регентство при малолетнем правителе"


static func _n(game: Game, key: String, def: float) -> float:
	return game.def_num("upbringing." + key, def)


# ------------------------------------------------------------ детство

## Все детские черты.
static func childhood_traits(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("upb:childhood")
	if hit == null:
		hit = game.content.all("traits").filter(func(t): return t.get("category") == "childhood")
		game.engine.cache["upb:childhood"] = hit
	return hit


static func childhood_trait(game: Game, c: Dictionary) -> Variant:
	for t in c.traits:
		var d: Variant = game.content.get_def("traits", t)
		if d != null and d.get("category") == "childhood":
			return t
	return null


## Направления воспитания — навыки, по которым есть черты образования (по порядку навыков).
static func focuses(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("upb:focuses")
	if hit == null:
		var have := {}
		for t in game.content.all("traits"):
			var e: Variant = t.get("education")
			if e is Dictionary and e.get("skill") != null:
				have[str(e.skill)] = true
		hit = Chars.skill_ids(game).filter(func(s): return have.has(s))
		game.engine.cache["upb:focuses"] = hit
	return hit


## Черта образования по навыку и уровню (или null).
static func education_trait(game: Game, skill: String, level: int) -> Variant:
	for t in game.content.all("traits"):
		var e: Variant = t.get("education")
		if e is Dictionary and str(e.get("skill")) == skill and int(e.get("level", 1)) == level:
			return t.id
	return null


static func max_level(game: Game) -> int:
	return Data.as_array(game.def_val("upbringing.level_thresholds", [70, 140, 195])).size() + 1


static func is_child(game: Game, c: Dictionary) -> bool:
	return Chars.is_alive(c) and not Chars.is_adult(game, c)


static func in_education(game: Game, c: Dictionary) -> bool:
	return is_child(game, c) and Chars.age_of(game, c) >= int(_n(game, "education_age", 6))


static func focus_of(game: Game, c: Dictionary) -> Variant:
	var f: Variant = c.vars.get("edu_focus")
	return f if f != null and focuses(game).has(f) else null


static func guardian_of(game: Game, c: Dictionary) -> Variant:
	var gid: Variant = c.vars.get("guardian")
	if gid == null:
		return null
	var g: Variant = game.ch(gid)
	return g if Chars.is_alive(g) else null


## Воспитанники персонажа (кэш на месяц).
static func wards_of(game: Game, g: Dictionary) -> Array:
	return game.cached_monthly("wards:" + g.id, func():
		var out := []
		for c in game.living():
			if c.vars.get("guardian") == g.id and Upbringing.is_child(game, c):
				out.append(c)
		return out)


## Кто распоряжается воспитанием ребёнка: правитель, при чьём дворе он
## живёт, родитель-правитель или сам ребёнок-правитель.
static func can_manage(game: Game, actor: Dictionary, child: Dictionary) -> bool:
	if not is_child(game, child) or not Chars.is_alive(actor):
		return false
	if child.id == actor.id:
		return not actor.titles.is_empty()
	if child.liege == actor.id:
		return true
	return (child.father == actor.id or child.mother == actor.id) and not actor.titles.is_empty()


## Распорядитель воспитания ребёнка (или null).
static func manager_of(game: Game, child: Dictionary) -> Variant:
	if not child.titles.is_empty():
		return child
	var l: Variant = game.ch(child.liege)
	if Chars.is_alive(l):
		return l
	for pid in [child.father, child.mother]:
		var p: Variant = game.ch(pid)
		if Chars.is_alive(p) and not p.titles.is_empty():
			return p
	return null


static func can_be_guardian(game: Game, g: Dictionary, child: Dictionary) -> bool:
	if not Chars.is_alive(g) or g.id == child.id or not Chars.is_adult(game, g) or g.get("prison") != null:
		return false
	if child.vars.get("guardian") == g.id:
		return true
	return wards_of(game, g).size() < int(_n(game, "max_wards", 3))


## Кандидаты в опекуны: сам распорядитель, супруги, придворные и вассалы —
## лучшие в направлении воспитания сначала.
static func guardian_candidates(game: Game, manager: Dictionary, child: Dictionary) -> Array:
	var pool := [manager]
	for s in manager.spouses:
		var sp: Variant = game.ch(s)
		if sp != null:
			pool.append(sp)
	pool.append_array(game.courtiers_of(manager.id))
	pool.append_array(game.vassals_of(manager.id))
	var seen := {}
	var out := []
	for x in pool:
		if seen.has(x.id) or not can_be_guardian(game, x, child):
			continue
		seen[x.id] = true
		out.append(x)
	var focus: Variant = focus_of(game, child)
	if focus != null:
		Data.sort_by(out, func(x): return Stats.skill(game, x, str(focus)), true)
	return out


static func set_guardian(game: Game, child: Dictionary, g: Variant) -> void:
	var old: Variant = guardian_of(game, child)
	_reset_gain(child)
	if g == null:
		child.vars.erase("guardian")
	else:
		if old != null and old.id == g.id:
			return
		child.vars["guardian"] = g.id
		game.month_cache.erase("wards:" + g.id)
	if old != null:
		game.month_cache.erase("wards:" + old.id)
		if g != null and old.id != g.id and game.content.has("opinion_modifiers", "removed_as_guardian"):
			Opinion.add_opinion(game, old, child, "removed_as_guardian")
	game.stat_cache.erase("op:%s>%s" % [child.id, old.id if old != null else ""])
	game.mark_chars_dirty([child.id, old.id if old != null else null, g.id if g != null else null])
	if g != null:
		game.emit("upbringing.guardian_set", {"child": child, "guardian": g})
		if game.is_player(g.id) and manager_of(game, child) != null and not game.is_player(manager_of(game, child).id):
			game.message(game.loc.t("msg.became_guardian", {"who": game.scope_name({"type": "character", "id": child.id})}), "good",
				{"type": "character", "id": child.id}, [g.id])


static func set_focus(game: Game, child: Dictionary, skill: String) -> void:
	if not focuses(game).has(skill):
		return
	child.vars["edu_focus"] = skill
	_reset_gain(child)
	game.mark_chars_dirty([child.id])


## Направление по склонности (детская черта), иначе — по лучшему навыку.
static func natural_focus(game: Game, c: Dictionary) -> String:
	var ct: Variant = childhood_trait(game, c)
	var d: Variant = game.content.get_def("traits", ct) if ct != null else null
	var apt: Variant = d.childhood.get("aptitude") if (d != null and d.get("childhood") is Dictionary) else null
	var fs := focuses(game)
	if apt != null and fs.has(str(apt)):
		return str(apt)
	var best: String = fs[0] if not fs.is_empty() else ""
	for s in fs:
		if Data.num(c.skills.get(s)) > Data.num(c.skills.get(best)):
			best = s
	return best


static func aptitude_matches(game: Game, c: Dictionary, focus: Variant) -> bool:
	var ct: Variant = childhood_trait(game, c)
	var d: Variant = game.content.get_def("traits", ct) if ct != null else null
	return d != null and d.get("childhood") is Dictionary and str(d.childhood.get("aptitude")) == str(focus)


## Прибавка очков воспитания за месяц и её разбивка [{label, value}].
static func monthly_gain(game: Game, c: Dictionary, parts: Variant = null) -> float:
	var focus: Variant = focus_of(game, c)
	if focus == null:
		return 0.0
	var add := func(key: String, v: float, args: Dictionary = {}) -> void:
		if parts is Array and absf(v) > 0.0001:
			parts.append({"label": game.loc.t("upbringing.gain." + key, args), "value": v})
	var base := _n(game, "base_points", 0.45)
	var g: Variant = guardian_of(game, c)
	var gain := base
	add.call("base", base)
	if g == null:
		var cut := base * (1.0 - _n(game, "no_guardian_mult", 0.5))
		gain -= cut
		add.call("no_guardian", -cut)
	else:
		var gv := minf(Stats.skill(game, g, str(focus)), _n(game, "guardian_skill_cap", 25)) * _n(game, "per_guardian_skill", 0.035)
		# мудрый наставник (стезя Династа) учит лучше
		gv *= maxf(0.0, 1.0 + Stats.stat(game, g, "ward_education_mult"))
		gain += gv
		add.call("guardian", gv, {"name": game.scope_name({"type": "character", "id": g.id})})
	if aptitude_matches(game, c, focus):
		var ab := _n(game, "aptitude_bonus", 0.15)
		gain += ab
		add.call("aptitude", ab)
	var own := Data.num(c.skills.get(focus)) * _n(game, "own_skill_share", 0.02)
	gain += own
	add.call("own", own)
	var mult := Stats.stat(game, c, "education_gain_mult")
	if mult != 0.0:
		add.call("mult", gain * mult)
		gain *= 1.0 + mult
	return maxf(0.0, gain)


## Прибавка за месяц, пересчитываемая раз в год (и при смене опекуна или
## направления): полный расчёт характеристик ребёнка каждый месяц дорог.
static func cached_gain(game: Game, c: Dictionary) -> float:
	var until: Variant = c.vars.get("edu_gain_until")
	if until == null or int(until) <= game.date or c.vars.get("edu_gain") == null:
		c.vars["edu_gain"] = monthly_gain(game, c)
		c.vars["edu_gain_until"] = game.date + GameDate.DAYS_PER_YEAR
	return float(c.vars.edu_gain)


static func _reset_gain(c: Dictionary) -> void:
	c.vars.erase("edu_gain")
	c.vars.erase("edu_gain_until")


static func points_of(game: Game, c: Dictionary) -> float:
	var p: Variant = c.vars.get("edu_points")
	if p != null:
		return float(p)
	# ребёнок, вступивший в возраст воспитания до начала партии
	var months := maxi(0, (game.date - int(c.birth)) / 30 - int(_n(game, "education_age", 6)) * 12)
	return months * _n(game, "initial_monthly", 0.85)


static func level_for(game: Game, points: float) -> int:
	var lv := 1
	for th in Data.as_array(game.def_val("upbringing.level_thresholds", [70, 140, 195])):
		if points >= Data.num(th):
			lv += 1
	return lv


## Ожидаемый уровень образования, если всё останется как есть.
static func predicted_points(game: Game, c: Dictionary) -> float:
	var adult := int(game.def_num("character.adult_age", 16))
	var months_left := maxi(0, (int(c.birth) + adult * GameDate.DAYS_PER_YEAR - game.date) / 30)
	var start := int(_n(game, "education_age", 6))
	if Chars.age_of(game, c) < start:
		months_left = (adult - start) * 12
	return points_of(game, c) + monthly_gain(game, c) * months_left


static func _pick_childhood_trait(game: Game, c: Dictionary) -> void:
	var pool := childhood_traits(game)
	var pick: Variant = game.rng.weighted(pool, func(t): return Data.num(t.get("weight"), 1.0))
	if pick != null:
		Chars.add_trait(game, c, pick.id)


## Помесячно для ребёнка: детская черта, направление, очки, проверка опекуна.
static func monthly_char(game: Game, c: Dictionary) -> void:
	if c.flags.has("adult"):
		if not c.titles.is_empty() and c.vars.has("regent"):
			_end_regency(game, c)
		return
	var age := Chars.age_of(game, c)
	if age >= int(game.def_num("character.adult_age", 16)):
		return
	if not c.titles.is_empty():
		_regency_month(game, c)
	if age >= int(_n(game, "childhood_age", 3)) and childhood_trait(game, c) == null and not childhood_traits(game).is_empty():
		_pick_childhood_trait(game, c)
	if age < int(_n(game, "education_age", 6)):
		return
	if focus_of(game, c) == null:
		c.vars["edu_focus"] = natural_focus(game, c)
	if c.vars.get("guardian") != null and not _guardian_ok(game, c):
		var old: Variant = game.ch(c.vars.guardian)
		c.vars.erase("guardian")
		_reset_gain(c)
		var mgr: Variant = manager_of(game, c)
		if mgr != null and game.is_player(mgr.id):
			game.message(game.loc.t("msg.guardian_lost", {"who": game.scope_name({"type": "character", "id": c.id}),
				"guardian": game.scope_name({"type": "character", "id": old.id}) if old != null else "?"}), "bad", {"type": "character", "id": c.id}, [mgr.id])
	c.vars["edu_points"] = points_of(game, c) + cached_gain(game, c)


static func _guardian_ok(game: Game, c: Dictionary) -> bool:
	var g: Variant = game.ch(c.vars.get("guardian"))
	return g != null and Chars.is_alive(g) and g.get("prison") == null


## ИИ правителя (и бездействующий игрок — только для чужих детей при дворе):
## назначить опекунов детям, у которых их нет.
static func ai_assign_guardians(game: Game, ruler: Dictionary) -> void:
	var player := game.is_player(ruler.id)
	for x in game.courtiers_of(ruler.id) + [ruler]:
		if not in_education(game, x) or x.vars.get("guardian") != null:
			continue
		# детей своей семьи игрок воспитывает сам
		if player and (x.id == ruler.id or x.father == ruler.id or x.mother == ruler.id or (x.dynasty != null and x.dynasty == ruler.dynasty)):
			continue
		if focus_of(game, x) == null:
			x.vars["edu_focus"] = natural_focus(game, x)
		var cands := guardian_candidates(game, ruler, x)
		if not cands.is_empty():
			set_guardian(game, x, cands[0])


# ------------------------------------------------------------ совершеннолетие

static func _personality_ok(game: Game, c: Dictionary, t: String) -> bool:
	if c.traits.has(t):
		return false
	var d: Variant = game.content.get_def("traits", t)
	if d == null or d.get("category") != "personality":
		return false
	for o in d.get("opposites", []):
		if c.traits.has(o):
			return false
	for x in c.traits:
		var xd: Variant = game.content.get_def("traits", x)
		if xd != null and xd.get("opposites", []).has(t):
			return false
	return true


static func _personality_count(game: Game, c: Dictionary) -> int:
	var n := 0
	for t in c.traits:
		var d: Variant = game.content.get_def("traits", t)
		if d != null and d.get("category") == "personality":
			n += 1
	return n


## Совершеннолетие: черта образования из очков воспитания, характер из
## детской черты и от опекуна.
static func on_coming_of_age(game: Game, c: Dictionary) -> void:
	var g: Variant = guardian_of(game, c)
	var limit := int(game.def_num("character.personality_traits", 3))
	# характер: от опекуна…
	if g != null and _personality_count(game, c) < limit:
		var from_g := []
		for t in g.traits:
			if _personality_ok(game, c, t) and game.rng.chance(_n(game, "adopt_guardian_trait", 0.2)):
				from_g.append(t)
		if not from_g.is_empty():
			Chars.add_trait(game, c, str(game.rng.pick(from_g)))
	# …и из детской черты
	var ct: Variant = childhood_trait(game, c)
	var cd: Variant = game.content.get_def("traits", ct) if ct != null else null
	if cd != null and cd.get("childhood") is Dictionary and _personality_count(game, c) < limit and game.rng.chance(_n(game, "childhood_bias", 0.6)):
		var opts: Array = Data.as_array(cd.childhood.get("personality")).filter(func(t): return Upbringing._personality_ok(game, c, str(t)))
		if not opts.is_empty():
			Chars.add_trait(game, c, str(game.rng.pick(opts)))
	if ct != null:
		Chars.remove_trait(game, c, str(ct))
	# образование
	var focus: Variant = focus_of(game, c)
	if focus == null:
		focus = natural_focus(game, c)
	var have_edu := false
	for t in c.traits:
		var d: Variant = game.content.get_def("traits", t)
		if d != null and d.get("education") != null:
			have_edu = true
	var edu: Variant = null
	if not have_edu and str(focus) != "":
		var pts := points_of(game, c) + game.rng.gauss(0.0, _n(game, "final_spread", 18))
		var lv := clampi(level_for(game, pts), 1, max_level(game))
		edu = education_trait(game, str(focus), lv)
		while edu == null and lv > 1:
			lv -= 1
			edu = education_trait(game, str(focus), lv)
		if edu != null:
			Chars.add_trait(game, c, str(edu))
	if g != null:
		for pair in [[c, g, "my_guardian"], [g, c, "my_ward"]]:
			if game.content.has("opinion_modifiers", pair[2]):
				Opinion.add_opinion(game, pair[0], pair[1], pair[2])
	c.vars.erase("guardian")
	c.vars.erase("edu_points")
	c.vars.erase("edu_focus")
	_reset_gain(c)
	if g != null:
		game.month_cache.erase("wards:" + g.id)
	game.emit("upbringing.educated", {"character": c, "trait": edu, "guardian": g.id if g != null else null})
	var mgr: Variant = manager_of(game, c)
	var p: Variant = game.state.player
	if edu != null and p != null and (c.id == p or c.father == p or c.mother == p or (mgr != null and mgr.id == p) or (g != null and g.id == p)):
		game.message(game.loc.t("msg.came_of_age", {"who": game.scope_name({"type": "character", "id": c.id}), "trait": game.name_of("traits", str(edu))}),
			"good", {"type": "character", "id": c.id}, [c.id])


# ------------------------------------------------------------ регентство

static func regent_of(game: Game, c: Dictionary) -> Variant:
	var rid: Variant = c.vars.get("regent")
	if rid == null:
		return null
	var r: Variant = game.ch(rid)
	return r if Chars.is_alive(r) else null


## Регентство персонажа-регента: ребёнок-правитель или null.
static func regency_of(game: Game, r: Dictionary) -> Variant:
	return game.cached_monthly("regency:" + r.id, func():
		for c in game.rulers():
			if c.vars.get("regent") == r.id and c.death == null:
				return c
		return null)


static func needs_regent(game: Game, c: Dictionary) -> bool:
	return Chars.is_alive(c) and not c.titles.is_empty() and not Chars.is_adult(game, c)


static func can_be_regent(game: Game, r: Dictionary, ruler: Dictionary) -> bool:
	return Chars.is_alive(r) and r.id != ruler.id and Chars.is_adult(game, r) and r.get("prison") == null \
		and (regency_of(game, r) == null or regency_of(game, r).id == ruler.id)


static func _regent_score(game: Game, r: Dictionary) -> float:
	return Stats.skill(game, r, "diplomacy") + Stats.skill(game, r, "stewardship") + Stats.skill(game, r, "martial") * 0.5


## Кандидаты в регенты: мать, канцлер, взрослые родичи при дворе, придворные и вассалы.
static func regent_candidates(game: Game, ruler: Dictionary) -> Array:
	var pool := []
	for pid in [ruler.mother, ruler.father]:
		var p: Variant = game.ch(pid)
		if p != null:
			pool.append(p)
	pool.append_array(game.courtiers_of(ruler.id))
	pool.append_array(game.vassals_of(ruler.id))
	var seen := {}
	var out := []
	for x in pool:
		if seen.has(x.id) or not can_be_regent(game, x, ruler):
			continue
		seen[x.id] = true
		out.append(x)
	Data.sort_by(out, func(x): return Upbringing._regent_score(game, x), true)
	return out


## Лучший регент: мать (если может), канцлер, близкий родич, лучший по навыкам.
static func pick_regent(game: Game, ruler: Dictionary) -> Variant:
	var mother: Variant = game.ch(ruler.mother)
	if mother != null and can_be_regent(game, mother, ruler) and mother.titles.is_empty():
		return mother
	if game.engine.has_feature("council"):
		var seat: Variant = Council.seat_of(ruler, str(_n_str(game, "regent_council_position", "chancellor")))
		var ch: Variant = game.ch(seat.get("holder")) if seat is Dictionary and seat.get("holder") != null else null
		if ch != null and can_be_regent(game, ch, ruler):
			return ch
	var cands := regent_candidates(game, ruler)
	for x in cands:
		if Chars.is_close_family(game, ruler, x):
			return x
	return cands[0] if not cands.is_empty() else null


static func _n_str(game: Game, key: String, def: String) -> String:
	var v: Variant = game.def_val("upbringing." + key, def)
	return str(v) if v != null else def


static func set_regent(game: Game, ruler: Dictionary, r: Variant) -> void:
	var old: Variant = regent_of(game, ruler)
	if r != null and old != null and old.id == r.id:
		return
	if r == null:
		ruler.vars.erase("regent")
	else:
		ruler.vars["regent"] = r.id
		ruler.vars["regent_since"] = game.date
		game.month_cache.erase("regency:" + r.id)
	if old != null:
		game.month_cache.erase("regency:" + old.id)
		if r != null and game.content.has("opinion_modifiers", "dismissed_regent"):
			Opinion.add_opinion(game, old, ruler, "dismissed_regent")
	game.stat_cache.erase(ruler.id)
	game.mark_chars_dirty([ruler.id, old.id if old != null else null, r.id if r != null else null])
	if r != null:
		game.emit("regency.started", {"ruler": ruler, "regent": r})
		if game.is_player(ruler.id):
			game.message(game.loc.t("msg.regent_appointed", {"who": game.scope_name({"type": "character", "id": r.id})}), "info",
				{"type": "character", "id": r.id}, [ruler.id])


## Честолюбие регента: >0 — опасен, <0 — верен.
static func regent_ambition(game: Game, r: Dictionary, ruler: Dictionary) -> float:
	var score := 0.0
	var w: Variant = game.def_val("upbringing.regent_ambition_traits", {})
	if w is Dictionary:
		for t in r.traits:
			score += Data.num(w.get(t))
	var op := Opinion.opinion(game, r, ruler)
	score += clampf(-op / 25.0, -2.0, 2.0)
	if Chars.is_parent_of(r, ruler):
		score -= 2.0
	return score


static func _regency_month(game: Game, c: Dictionary) -> void:
	var r: Variant = regent_of(game, c)
	if r == null or r.get("prison") != null or (regency_of(game, r) != null and regency_of(game, r).id != c.id):
		var nr: Variant = pick_regent(game, c)
		if nr != null:
			set_regent(game, c, nr)
		elif c.vars.has("regent"):
			c.vars.erase("regent")
		return
	var amb := regent_ambition(game, r, c)
	if amb <= 0.0:
		return
	# казнокрадство
	if c.gold > 30.0 and game.rng.chance(_n(game, "regent_embezzle_chance", 0.015) * amb):
		var take := roundf(minf(c.gold * _n(game, "regent_embezzle_share", 0.15), _n(game, "regent_embezzle_max", 60)))
		c.gold -= take
		r.gold += take
		if game.engine.has_feature("secrets") and game.content.has("secret_types", "secret_embezzler"):
			Secrets.add_secret(game, r, "secret_embezzler", c.id)
		game.emit("regency.embezzled", {"ruler": c, "regent": r, "gold": take})
	# регент-наследник и убийство
	if game.content.has("schemes", "murder") and game.rng.chance(_n(game, "regent_murder_chance", 0.004) * amb):
		var heirs := Succession.heirs_of(game, c).slice(0, 3)
		if heirs.has(r.id) and Stats.skill(game, r, "intrigue") >= _n(game, "regent_murder_min_intrigue", 8):
			for s in game.state.schemes.values():
				if s.owner == r.id and s.target == c.id:
					return
			Schemes.start_scheme(game, "murder", r, c)


static func _end_regency(game: Game, c: Dictionary) -> void:
	var r: Variant = regent_of(game, c)
	c.vars.erase("regent")
	c.vars.erase("regent_since")
	if r != null:
		game.month_cache.erase("regency:" + r.id)
	game.stat_cache.erase(c.id)
	game.mark_chars_dirty([c.id])
	game.emit("regency.ended", {"ruler": c, "regent": r.id if r != null else null})
	var ev: Variant = game.def_val("upbringing.regency_end_event", null)
	if r != null and ev != null and game.content.has("events", str(ev)):
		game.events.trigger(str(ev), {"type": "character", "id": c.id}, {"regent": {"type": "character", "id": r.id}})


## Влияние регента на державу: из его собственных навыков (не из бонусов —
## иначе характеристики регента и правителя считались бы друг через друга).
static func regency_modifiers(game: Game, c: Dictionary) -> Dictionary:
	var out := {"vassal_opinion": _n(game, "child_ruler_opinion", -5.0)}
	var r: Variant = regent_of(game, c)
	if r == null:
		out.vassal_opinion += _n(game, "no_regent_opinion", -10.0)
		return out
	var mid := _n(game, "regent_skill_mid", 8.0)
	var sk := func(s: String) -> float: return Data.num(r.skills.get(s)) - mid
	out.vassal_opinion += clampf(sk.call("diplomacy") * _n(game, "regent_opinion_per_skill", 0.8), -10.0, 12.0)
	out["tax_mult"] = clampf(sk.call("stewardship") * _n(game, "regent_tax_per_skill", 0.015), -0.1, 0.15)
	out["levy_mult"] = clampf(sk.call("martial") * _n(game, "regent_levy_per_skill", 0.015), -0.1, 0.15)
	return out


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("upbringing", {"id": "upbringing", "order": 21, "on_character_month": func(game: Game, c: Dictionary):
		Upbringing.monthly_char(game, c)
		if not c.titles.is_empty() and c.death == null:
			Upbringing.ai_assign_guardians(game, c)
	}, OWNER)
	engine.hooks.on("character.coming_of_age", func(p): Upbringing.on_coming_of_age(p.game, p.character), 0, OWNER)
	# престол достался ребёнку — регент нужен сразу, а не через месяц
	engine.hooks.on("character.death", func(p):
		var game: Game = p.game
		var heir: Variant = game.ch(p.get("heir")) if p.get("heir") != null else null
		if heir != null and Upbringing.needs_regent(game, heir) and Upbringing.regent_of(game, heir) == null:
			var r: Variant = Upbringing.pick_regent(game, heir)
			if r != null:
				Upbringing.set_regent(game, heir, r)
	, 0, OWNER)
	engine.modifier_providers.register("regency", {"fn": func(game: Game, c: Dictionary) -> Variant:
		if c.titles.is_empty() or c.death != null or Chars.is_adult(game, c):
			return null
		var cid: String = c.id
		return [{"label": func():
			var rr: Variant = Upbringing.regent_of(game, game.ch(cid))
			return game.loc.t("modsrc.regency", {"name": game.scope_name({"type": "character", "id": rr.id})}) if rr != null else game.loc.t("modsrc.no_regent"),
			"modifiers": Upbringing.regency_modifiers(game, c)}]
	}, OWNER)
	engine.opinion_providers.register("upbringing", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		if a.vars.get("guardian") == b.id and Upbringing.is_child(game, a):
			return {"label": game.loc.t("opinion.my_guardian_now"), "value": game.def_num("upbringing.ward_opinion", 15)}
		if b.vars.get("guardian") == a.id and Upbringing.is_child(game, b):
			return {"label": game.loc.t("opinion.my_ward_now"), "value": game.def_num("upbringing.guardian_opinion", 10)}
		return null
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

	r.triggers.register("has_guardian", {"scopes": CH, "doc": "У ребёнка есть опекун", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return (c != null and Upbringing.guardian_of(ctx.game, c) != null) == yes.call(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_guardian" + ("" if yes.call(arg) else ".not")),
	}, OWNER)
	r.triggers.register("is_guardian_of", {"scopes": CH, "doc": "Опекун этого ребёнка: is_guardian_of: scope:child", "eval": func(ctx, s, arg):
		var o: Variant = other.call(ctx, s, arg)
		return o != null and o.vars.get("guardian") == s.id,
		"describe": func(ctx, s, arg): return ctx.game.loc.t("tr.is_guardian_of", {"who": ctx.game.scope_name(Interp.resolve_scope(ctx, s, arg))}),
	}, OWNER)
	r.triggers.register("can_be_guardian_of", {"scopes": CH, "doc": "Может стать опекуном ребёнка: can_be_guardian_of: scope:recipient", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var o: Variant = other.call(ctx, s, arg)
		return c != null and o != null and Upbringing.in_education(ctx.game, o) and Upbringing.can_be_guardian(ctx.game, c, o) and o.vars.get("guardian") != c.id,
		"describe": func(ctx, _s, _arg): return ctx.game.loc.t("tr.can_be_guardian_of"),
	}, OWNER)
	r.triggers.register("in_education", {"scopes": CH, "doc": "Ребёнок в возрасте воспитания", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return (c != null and Upbringing.in_education(ctx.game, c)) == yes.call(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.in_education" + ("" if yes.call(arg) else ".not")),
	}, OWNER)
	r.triggers.register("education_focus", {"scopes": CH, "doc": "Направление воспитания: education_focus: martial", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return c != null and str(Upbringing.focus_of(ctx.game, c)) == str(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.education_focus", {"value": ctx.game.name_of("skills", str(arg))}),
	}, OWNER)
	r.triggers.register("can_manage_upbringing", {"scopes": CH, "doc": "Распоряжается воспитанием ребёнка: can_manage_upbringing: scope:recipient", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var o: Variant = other.call(ctx, s, arg)
		return c != null and o != null and Upbringing.can_manage(ctx.game, c, o),
		"describe": func(ctx, _s, _arg): return ctx.game.loc.t("tr.can_manage_upbringing"),
	}, OWNER)
	r.triggers.register("has_regent", {"scopes": CH, "doc": "Правителем-ребёнком правит регент", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return (c != null and Upbringing.regent_of(ctx.game, c) != null) == yes.call(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_regent" + ("" if yes.call(arg) else ".not")),
	}, OWNER)
	r.triggers.register("is_regent", {"scopes": CH, "doc": "Регент при правителе-ребёнке", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return (c != null and Upbringing.regency_of(ctx.game, c) != null) == yes.call(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_regent" + ("" if yes.call(arg) else ".not")),
	}, OWNER)
	r.triggers.register("can_be_regent_of", {"scopes": CH, "doc": "Может стать регентом: can_be_regent_of: scope:actor", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var o: Variant = other.call(ctx, s, arg)
		return c != null and o != null and Upbringing.needs_regent(ctx.game, o) and Upbringing.can_be_regent(ctx.game, c, o) and o.vars.get("regent") != c.id,
		"describe": func(ctx, _s, _arg): return ctx.game.loc.t("tr.can_be_regent_of"),
	}, OWNER)
	r.values.register("education_points", {"scopes": CH, "doc": "Очки воспитания ребёнка", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Upbringing.points_of(ctx.game, c) if c != null else 0.0
	}, OWNER)
	r.values.register("guardian_skill", {"scopes": CH, "doc": "Навык персонажа в направлении воспитания ребёнка: guardian_skill(scope:recipient)", "get": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var o: Variant = ctx.game.ch(arg.id) if (arg is Dictionary and arg.get("type") == "character") else null
		var f: Variant = Upbringing.focus_of(ctx.game, o) if o != null else null
		return Stats.skill(ctx.game, c, str(f)) if (c != null and f != null) else 0.0
	}, OWNER)
	r.values.register("regent_score", {"scopes": CH, "doc": "Пригодность в регенты (дипломатия + управление + ½ воинского дела)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Upbringing._regent_score(ctx.game, c) if c != null else 0.0
	}, OWNER)
	r.effects.register("set_guardian", {"scopes": CH, "doc": "Назначить ребёнку опекуна: set_guardian: scope:x", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var o: Variant = other.call(ctx, s, arg)
		if c != null and o != null and Upbringing.is_child(ctx.game, c) and Upbringing.can_be_guardian(ctx.game, o, c):
			Upbringing.set_guardian(ctx.game, c, o),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.set_guardian", {"who": ctx.game.scope_name(Interp.resolve_scope(ctx, s, arg)), "child": ctx.game.scope_name(s)}),
	}, OWNER)
	r.effects.register("remove_guardian", {"scopes": CH, "doc": "Отстранить опекуна ребёнка: remove_guardian: yes", "apply": func(ctx, s, _arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			Upbringing.set_guardian(ctx.game, c, null),
		"describe": func(ctx, s, _arg): return ctx.game.loc.t("fx.remove_guardian", {"child": ctx.game.scope_name(s)}),
	}, OWNER)
	r.effects.register("set_education_focus", {"scopes": CH, "doc": "Направление воспитания: set_education_focus: martial", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			Upbringing.set_focus(ctx.game, c, str(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.set_education_focus", {"value": ctx.game.name_of("skills", str(arg))}),
	}, OWNER)
	r.effects.register("add_education_points", {"scopes": CH, "doc": "Изменить очки воспитания ребёнка", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c != null and Upbringing.is_child(ctx.game, c):
			c.vars["edu_points"] = maxf(0.0, Upbringing.points_of(ctx.game, c) + Interp.eval_value(ctx, s, arg)),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.add_education_points", {"child": ctx.game.scope_name(s), "value": "%+d" % roundi(Interp.eval_value(ctx, s, arg))}),
	}, OWNER)
	r.effects.register("set_regent", {"scopes": CH, "doc": "Назначить регента правителю-ребёнку: set_regent: scope:x", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var o: Variant = other.call(ctx, s, arg)
		if c != null and o != null and Upbringing.needs_regent(ctx.game, c) and Upbringing.can_be_regent(ctx.game, o, c):
			Upbringing.set_regent(ctx.game, c, o),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.set_regent", {"who": ctx.game.scope_name(Interp.resolve_scope(ctx, s, arg))}),
	}, OWNER)
	r.links.register("guardian", {"from": CH, "doc": "Опекун ребёнка", "resolve": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		var g: Variant = Upbringing.guardian_of(ctx.game, c) if c != null else null
		return {"type": "character", "id": g.id} if g != null else null
	}, OWNER)
	r.links.register("regent", {"from": CH, "doc": "Регент правителя-ребёнка", "resolve": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		var g: Variant = Upbringing.regent_of(ctx.game, c) if c != null else null
		return {"type": "character", "id": g.id} if g != null else null
	}, OWNER)
	r.lists.register("ward", {"from": CH, "doc": "Воспитанники персонажа", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		if c == null:
			return []
		return Upbringing.wards_of(ctx.game, c).map(func(x): return {"type": "character", "id": x.id})
	}, OWNER)

class_name Populace
extends EngineFeature
## Народ графств (по образцу CK3): мнение графства о владельце, контроль и
## народные фракции — крестьянские и народные мятежи.
##
## Мнение графства (−100…100) — сумма частей:
##   чужая вера владельца (другая религия — defines.populace.foreign_religion,
##   та же религия — foreign_faith), чужая культура (другая группа —
##   foreign_culture_group, та же — foreign_culture), низкий контроль
##   (control_opinion за очко ниже 100), ополчение владельца, собранное
##   дольше levy_free_months (levy_opinion в месяц, не больше levy_opinion_max),
##   модификатор county_opinion владельца (черты, перки, законы) и графства
##   (постройки, модификаторы провинции), временные модификаторы из
##   opinion_modifiers (эффект add_county_opinion), части модов (хук
##   populace.opinion → [{label, value}]).
## Мнение меняет налог и ополчение графства: opinion_output за очко (не
## ниже opinion_output_min и не выше opinion_output_max) — довольный народ
## платит больше. Чужая вера и культура владельца сказываются только так
## (модификаторы механики lands действуют, лишь когда populace выключена).
## Контроль (0–100): падает до conquest_control, когда графство уходит в
## чужую державу при живом прежнем владельце, и на occupation_control_loss,
## когда его берёт враг; растёт на control_regen в месяц плюс control_gain
## владельца (задача маршала). Низкий контроль режет налог и ополчение
## графства: при нуле — на control_effect (доля).
##
## Народные фракции — записи factions с полем popular. Их члены — графства:
## графство с мнением не выше join_opinion вступает в первую подходящую
## (can_join; root — графство, scope:holder — владелец; порядок — order)
## против своего владельца и выходит, когда мнение выше leave_opinion.
##   popular: { join_opinion, leave_opinion, group_by: [faith, culture],
##              discontent_gain, power_threshold, army_mult,
##              leader: { traits, skills: {навык: [от, до]}, age: [от, до],
##                        dynasty: none | new } }
## Без power_threshold недовольство растёт всегда (крестьяне), с ним — пока
## сила фракции не ниже порога. На 100 — ультиматум, как у обычных фракций
## (ai_accept_demands, on_demands_accepted, ultimatum_event; root — вожак,
## scope:liege — владелец). Вожак — новый персонаж веры и культуры графств.
## Отказ — мятеж (повод cb): войско из ополчения графств × army_mult; каждое
## графство, взятое мятежниками, добавляет им ополчение × occupy_levy_mult.
## Мятежники без войска проиграли. Итог войны — в данных повода (эффект
## take_faction_counties: вожак забирает графства фракции и становится
## правителем). После мятежа графства revolt_cooldown_years не бунтуют,
## разбитые теряют crushed_control_loss контроля.
##
## Жалобы графств («ходоки»): графство домена с мнением не выше
## complaint_opinion шлёт челобитчиков — on_action on_county_complaint
## (root — владелец, scope:province — графство). Игроку — с шансом
## complaint_chance_player в месяц, остальным — complaint_chance_ai раз в год
## (в «свой» месяц); шанс умножается на Politics.complaint_mult (ступени
## страха: чем страшнее правитель, тем реже жалобы). После жалобы графство
## молчит complaint_cooldown_years.
## Причина жалобы — county_grievances: { <id>: { parts: [ключи частей мнения] } }:
## побеждает причина с самой большой суммой отрицательных частей (ключи —
## faith, religion, culture, culture_group, control, levies, holder, county,
## id модификаторов мнения графства и key у частей из хука populace.opinion).
## Народная фракция с can_rise (root — владелец) копит недовольство, только
## пока условие верно (например, при терроре крестьяне не бунтуют).
## Состояние: p.vars.control (нет — 100), p.vars.copinions =
## [{mod, value, expires}], p.vars.revolt_cd (до какого дня), p.vars.revolt
## (id войны); c.vars.levies_since — с какого дня собрано ополчение;
## фракция: {popular: true, counties, key, faith, culture, leader | null}.
## Хуки: populace.opinion (части мнения), populace.revolt — {faction, war}.

const OWNER := "core/populace"


func _init() -> void:
	id = "populace"
	doc = "Народ графств: мнение о владельце, контроль, крестьянские и народные мятежи"


static func _d(game: Game, key: String, default: float) -> float:
	return game.def_num("populace." + key, default)


# ------------------------------------------------------------ контроль

static func control(game: Game, prov_id: String) -> float:
	var p: Variant = game.state.provinces.get(prov_id)
	return Data.num(p.vars.get("control"), 100.0) if p != null else 100.0


static func set_control(game: Game, prov_id: String, v: float) -> void:
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null:
		return
	v = clampf(v, 0.0, 100.0)
	if v >= 100.0:
		if not p.vars.has("control"):
			return
		p.vars.erase("control")
	else:
		p.vars["control"] = v
	_forget(game, prov_id)


static func add_control(game: Game, prov_id: String, dv: float) -> void:
	set_control(game, prov_id, control(game, prov_id) + dv)


# ------------------------------------------------------------ мнение графства

## Части мнения графства о владельце: [{label, value}] (labels — с подписями).
static func opinion_parts(game: Game, prov_id: String, labels: bool = true) -> Array:
	var out := []
	var p: Variant = game.state.provinces.get(prov_id)
	var h: Variant = Titles.county_holder(game, prov_id)
	if p == null or h == null:
		return out
	var add := func(key: String, v: float) -> void:
		if v != 0.0:
			out.append({"label": game.loc.t("copinion." + key) if labels else key, "value": v})
	if str(p.faith) != str(h.faith):
		var fa: Variant = game.content.get_def("faiths", p.faith)
		var fb: Variant = game.content.get_def("faiths", h.faith)
		var same: bool = fa != null and fb != null and fa.get("religion") != null and fa.get("religion") == fb.get("religion")
		add.call("faith" if same else "religion", _d(game, "foreign_faith", -10) if same else _d(game, "foreign_religion", -25))
	if str(p.culture) != str(h.culture):
		var ca: Variant = game.content.get_def("cultures", p.culture)
		var cb: Variant = game.content.get_def("cultures", h.culture)
		var same: bool = ca != null and cb != null and ca.get("group") != null and ca.get("group") == cb.get("group")
		add.call("culture" if same else "culture_group", _d(game, "foreign_culture", -5) if same else _d(game, "foreign_culture_group", -15))
	var ctl := control(game, prov_id)
	if ctl < 100.0:
		add.call("control", roundf((ctl - 100.0) * _d(game, "control_opinion", 0.3)))
	var since: Variant = h.vars.get("levies_since")
	if since != null:
		var months := (game.date - int(since)) / 30.0 - _d(game, "levy_free_months", 12)
		if months > 0.0:
			add.call("levies", -minf(_d(game, "levy_opinion_max", 25), roundf(months * _d(game, "levy_opinion", 2))))
	add.call("holder", Stats.stat(game, h, "county_opinion"))
	add.call("county", _county_flat(game, p))
	for e in Data.as_array(p.vars.get("copinions")):
		if e.get("expires") == null or int(e.expires) > game.date:
			out.append({"label": game.name_of("opinion_modifiers", e.mod) if labels else e.mod, "value": float(e.value)})
	for x in game.engine.hooks.collect("populace.opinion", {"game": game, "province": prov_id, "holder": h}):
		for part in Data.as_array(x):
			if part is Dictionary and Data.num(part.get("value")) != 0.0:
				out.append(part if labels or part.get("key") == null else {"label": str(part.key), "value": part.value})
	return out


# ------------------------------------------------------------ жалобы графств

## Причина недовольства графства (id из county_grievances) или "".
static func grievance(game: Game, prov_id: String) -> String:
	var defs := game.content.all("county_grievances")
	if defs.is_empty():
		return ""
	var by_key := {}
	for part in opinion_parts(game, prov_id, false):
		var v := Data.num(part.value)
		if v < 0.0:
			by_key[str(part.label)] = float(by_key.get(str(part.label), 0.0)) + v
	var best := ""
	var worst := 0.0
	for d in defs:
		var sum := 0.0
		for k in Data.as_array(d.get("parts")):
			sum += float(by_key.get(str(k), 0.0))
		if sum < worst:
			worst = sum
			best = d.id
	return best


## Графство домена, которое пришлёт ходоков: самое недовольное из тех,
## чьё мнение не выше complaint_opinion (null — жаловаться некому).
static func complaining_county(game: Game, c: Dictionary) -> Variant:
	var thr := _d(game, "complaint_opinion", -10)
	var best: Variant = null
	var worst := INF
	for pid in Titles.domain_counties(game, c):
		var p: Variant = game.state.provinces.get(pid)
		if p == null or p.occupant != null or p.vars.has("revolt"):
			continue
		if p.vars.has("complaint_cd") and int(p.vars.complaint_cd) > game.date:
			continue
		var op := opinion(game, pid)
		if op <= thr and op < worst:
			worst = op
			best = pid
	return best


## Ходоки: раз в месяц для игрока, раз в год для остальных правителей.
static func monthly_char(game: Game, c: Dictionary) -> void:
	if c.death != null or c.titles.is_empty() or c.get("prison") != null:
		return
	var chance := 0.0
	if game.is_player(c.id):
		chance = _d(game, "complaint_chance_player", 4)
	elif (Rng.hash_string(c.id + ":plea") & 0x7FFFFFFF) % 12 == GameDate.parts(game.date).m - 1:
		chance = _d(game, "complaint_chance_ai", 25)
	else:
		return
	if game.engine.has_feature("politics"):
		chance *= Politics.complaint_mult(game, c)
	if chance <= 0.0 or game.rng.next() * 100.0 >= chance:
		return
	var pid: Variant = complaining_county(game, c)
	if pid == null:
		return
	game.state.provinces[pid].vars["complaint_cd"] = game.date + roundi(_d(game, "complaint_cooldown_years", 3) * GameDate.DAYS_PER_YEAR)
	game.on_action("on_county_complaint", {"type": "character", "id": c.id}, {"province": {"type": "province", "id": pid}})


## county_opinion построек и модификаторов графства (без поставщиков:
## поставщик налога сам спрашивает мнение графства).
static func _county_flat(game: Game, p: Dictionary) -> float:
	var v := 0.0
	for b in p.buildings:
		var bd: Variant = game.content.get_def("buildings", b)
		if bd != null and bd.get("modifiers") is Dictionary:
			v += Data.num(bd.modifiers.get("county_opinion"))
	for m in p.modifiers:
		var md: Variant = game.content.get_def("modifiers", m.id)
		if md != null and md.get("modifiers") is Dictionary:
			v += Data.num(md.modifiers.get("county_opinion"))
	return v


## Налог и ополчение графства от мнения: opinion_output за очко,
## в пределах [opinion_output_min, opinion_output_max].
static func output_mult(game: Game, prov_id: String) -> float:
	var op := opinion(game, prov_id)
	return clampf(op * _d(game, "opinion_output", 0.006), _d(game, "opinion_output_min", -0.5), _d(game, "opinion_output_max", 0.2))


## Мнение графства о владельце (−100…100), на месяц.
static func opinion(game: Game, prov_id: String) -> float:
	return game.cached_monthly("pop:op:" + prov_id, func():
		var s := 0.0
		for part in opinion_parts(game, prov_id, false):
			s += Data.num(part.value)
		return clampf(roundf(s), -100.0, 100.0))


## Временный модификатор мнения графства (из opinion_modifiers: value, years|months).
static func add_county_opinion(game: Game, prov_id: String, mod_id: String, value: Variant = null) -> void:
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null:
		return
	var def: Variant = game.content.get_def("opinion_modifiers", mod_id)
	var v: float = Data.num(value) if value != null else (Data.num(def.get("value")) if def != null else 0.0)
	var months: Variant = null
	if def != null:
		if def.get("months") != null:
			months = Data.num(def.months)
		elif def.get("years") != null:
			months = Data.num(def.years) * 12.0
	var e := {"mod": mod_id, "value": v, "expires": game.date + roundi(months * 30.0) if months != null else null}
	var list: Array = Data.as_array(p.vars.get("copinions")).filter(func(x): return x.mod != mod_id)
	list.append(e)
	p.vars["copinions"] = list
	_forget(game, prov_id)


static func remove_county_opinion(game: Game, prov_id: String, mod_id: String) -> void:
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null or not p.vars.has("copinions"):
		return
	var list: Array = p.vars.copinions.filter(func(x): return x.mod != mod_id)
	if list.is_empty():
		p.vars.erase("copinions")
	else:
		p.vars.copinions = list
	_forget(game, prov_id)


## Мнение графства изменилось: сбросить его и налог с ополчением графства.
static func _forget(game: Game, prov_id: String) -> void:
	game.month_cache.erase("pop:op:" + prov_id)
	game.stat_cache.erase("prov:" + prov_id)


static func _forget_domain_opinions(game: Game, c: Dictionary) -> void:
	for cid in Titles.domain_counties(game, c):
		_forget(game, cid)


# ------------------------------------------------------------ народные фракции

## Записи factions с полем popular (по order).
static func popular_defs(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("populace:defs")
	if hit == null:
		hit = game.content.all("factions").filter(func(d): return d.get("popular") is Dictionary)
		Data.sort_by(hit, func(d): return Data.num(d.get("order"), 99))
		game.engine.cache["populace:defs"] = hit
	return hit


static func _pop(def: Variant) -> Dictionary:
	return def.popular if def != null and def.get("popular") is Dictionary else {}


static func is_popular(f: Variant) -> bool:
	return f is Dictionary and f.get("popular", false)


## Народная фракция, в которой состоит графство.
static func faction_of_county(game: Game, prov_id: String) -> Variant:
	for f in game.state.factions.values():
		if is_popular(f) and f.counties.has(prov_id):
			return f
	return null


static func _group_key(game: Game, def: Dictionary, prov_id: String) -> String:
	var p: Dictionary = game.state.provinces[prov_id]
	var parts := []
	for k in Data.as_array(_pop(def).get("group_by")):
		parts.append("%s:%s" % [k, p.get(k)])
	return "|".join(parts)


static func join_county(game: Game, def: Dictionary, prov_id: String, holder: Dictionary) -> Dictionary:
	var key := _group_key(game, def, prov_id)
	for f in game.state.factions.values():
		if is_popular(f) and f.type == def.id and f.target == holder.id and str(f.get("key", "")) == key:
			if not f.counties.has(prov_id):
				f.counties.append(prov_id)
			game.emit("faction.joined", {"faction": f, "county": prov_id})
			return f
	var p: Dictionary = game.state.provinces[prov_id]
	var f := {"id": game.new_id("fac"), "type": def.id, "target": holder.id, "leader": null, "members": [], "claimant": null,
		"counties": [prov_id], "popular": true, "key": key, "faith": p.faith, "culture": p.culture,
		"discontent": 0.0, "created": game.date, "ultimatum": false}
	game.state.factions[f.id] = f
	game.emit("faction.created", {"faction": f})
	if game.is_player(holder.id):
		game.message(game.loc.t("msg.popular_faction_created", {"faction": game.name_of("factions", def.id), "place": game.name_of("provinces", prov_id)}),
			"bad", {"type": "province", "id": prov_id})
	return f


static func leave_county(game: Game, f: Dictionary, prov_id: String) -> void:
	f.counties = f.counties.filter(func(x): return x != prov_id)
	game.emit("faction.left", {"faction": f, "county": prov_id})


## Ополчение мятежников: ополчение графств фракции × army_mult.
static func army_size(game: Game, f: Dictionary) -> float:
	var s := 0.0
	for cid in f.counties:
		s += Economy.county_levy(game, cid)
	return s * Data.num(_pop(game.content.get_def("factions", f.type)).get("army_mult"), 1.0)


## Сила фракции в процентах от войска владельца.
static func power(game: Game, f: Dictionary) -> int:
	var liege: Variant = game.ch(f.target)
	if liege == null:
		return 0
	return roundi(army_size(game, f) / maxf(1.0, float(Economy.realm_levy(game, liege))) * 100.0)


static func _rand_in(game: Game, v: Variant, default: float) -> float:
	if v is Array and v.size() >= 2:
		return game.rng.range_float(Data.num(v[0]), Data.num(v[1]))
	return Data.num(v, default)


## Вожак фракции (создаётся, когда понадобится: к ультиматуму).
static func ensure_leader(game: Game, f: Dictionary) -> Variant:
	var cur: Variant = game.ch(f.get("leader"))
	if cur != null and Chars.is_alive(cur) and cur.get("prison") == null:
		return cur
	var ld: Dictionary = _pop(game.content.get_def("factions", f.type)).get("leader", {})
	var skills := {}
	var sk: Variant = ld.get("skills")
	if sk is Dictionary:
		for s in sk:
			skills[s] = roundi(_rand_in(game, sk[s], 8))
	var c := Chars.create_character(game, {
		"culture": f.culture, "faith": f.faith,
		"female": game.rng.chance(Data.num(ld.get("female_chance"), 0.05)),
		"age": _rand_in(game, ld.get("age"), 30),
		"dynasty": "new" if str(ld.get("dynasty", "none")) == "new" else null,
		"traits": Data.as_array(ld.get("traits")), "skills": skills,
	})
	c.flags["popular_leader"] = f.id
	f.leader = c.id
	return c


## Ультиматум владельцу (игроку — событие, ИИ решает сам).
static func _ultimatum(game: Game, f: Dictionary) -> void:
	if ensure_leader(game, f) == null:
		return
	Factions._issue_ultimatum(game, f)


## Отказ — мятеж.
static func revolt(game: Game, f: Dictionary) -> bool:
	var def: Variant = game.content.get_def("factions", f.type)
	var holder: Variant = game.ch(f.target)
	var leader: Variant = ensure_leader(game, f)
	if def == null or holder == null or leader == null or def.get("cb") == null:
		return false
	game.emit("faction.ultimatum", {"faction": f, "accepted": false})
	var counties: Array = f.counties.filter(func(cid):
		var t: Variant = game.state.titles.get(cid)
		return t != null and t.holder == holder.id)
	if counties.is_empty():
		Factions.dissolve(game, f, false)
		return false
	var scopes := {"faction": Factions.fref(f), "faction_leader": {"type": "character", "id": leader.id}}
	var w: Variant = Wars.declare_war(game, leader, {"cb": def.cb, "defender": holder.id, "title": null, "counties": counties},
		{"free": true, "scopes": scopes, "faction": f.id, "popular": true})
	if w == null:
		return false
	f.ultimatum = false
	var best: String = counties[0]
	var best_levy := -1.0
	for cid in counties:
		var p: Dictionary = game.state.provinces[cid]
		p.vars["revolt"] = w.id
		var lv := Economy.county_levy(game, cid)
		if p.occupant == null and lv > best_levy:
			best = cid
			best_levy = lv
	var a := Military.new_army_record()
	a.id = game.new_id("army")
	a.owner = leader.id
	a.size = maxi(roundi(army_size(game, f)), roundi(game.def_num("military.min_army", 50) * 2))
	a.max_size = a.size
	a.location = best
	game.state.armies[a.id] = a
	game.day_cache.clear()
	game.emit("army.raised", {"army": a})
	game.message(game.loc.t("msg.popular_revolt", {"faction": game.name_of("factions", f.type), "leader": game.scope_name({"type": "character", "id": leader.id}),
		"place": game.name_of("provinces", best), "holder": game.scope_name({"type": "character", "id": holder.id})}),
		"war", {"type": "war", "id": w.id}, [holder.id, holder.liege])
	game.emit("populace.revolt", {"faction": f, "war": w})
	game.notify("army")
	return true


## Переговоры удались: графства выслушаны и надолго успокоены.
static func on_negotiated(game: Game, f: Dictionary) -> void:
	var mod := str(game.def_val("populace.negotiated_modifier", "heard_out_people"))
	for cid in f.counties:
		if game.content.has("opinion_modifiers", mod):
			add_county_opinion(game, cid, mod)


## Фракция распалась (cooldown — после ультиматума: графства не бунтуют
## revolt_cooldown_years).
static func on_dissolved(game: Game, f: Dictionary, cooldown: bool) -> void:
	if not cooldown:
		return
	var until := game.date + roundi(_d(game, "revolt_cooldown_years", 10) * GameDate.DAYS_PER_YEAR)
	for cid in f.counties:
		var p: Variant = game.state.provinces.get(cid)
		if p != null:
			p.vars["revolt_cd"] = until


## Вожак забирает графства фракции, что ещё у владельца, и правит ими сам.
## create_titles — создать де-юре герцогство (королевство), если у вожака
## не меньше половины его графств, а титул ничей.
static func take_counties(game: Game, leader: Dictionary, f: Dictionary, create_titles: bool = false) -> void:
	var holder: Variant = game.ch(f.target)
	var counties: Array = f.counties.filter(func(cid):
		var t: Variant = game.state.titles.get(cid)
		return t != null and holder != null and t.holder == holder.id)
	if counties.is_empty():
		return
	if leader.get("prison") != null:
		Prison.release(game, leader)
	if leader.dynasty == null:
		leader.dynasty = Chars.create_dynasty(game, leader.culture, leader.id).id
	Chars.set_liege(game, leader, null)
	for cid in counties:
		Titles.transfer_title(game, cid, leader.id, holder.liege if holder != null else null)
		set_control(game, cid, _d(game, "victory_control", 50))
		var p: Dictionary = game.state.provinces[cid]
		p.vars.erase("revolt")
	if create_titles:
		var mine := {}
		for cid in counties:
			mine[cid] = true
		for tier_up in 2:
			var cands := {}
			for t in leader.titles.duplicate():
				var lg: Variant = Titles.de_jure_liege(game, t)
				if lg != null:
					cands[lg] = true
			for t in cands:
				var st: Variant = game.state.titles.get(t)
				if st == null or st.holder != null:
					continue
				var dj := Titles.de_jure_counties(game, t)
				var have := Data.count(dj, func(x): return Titles.county_holder(game, x) != null and Titles.county_holder(game, x).id == leader.id)
				if dj.size() > 0 and float(have) / dj.size() >= _d(game, "create_title_share", 0.5):
					Titles.transfer_title(game, t, leader.id)
	game.mark_dirty()
	game.message(game.loc.t("msg.popular_realm", {"leader": game.scope_name({"type": "character", "id": leader.id}), "n": counties.size()}),
		"war", {"type": "character", "id": leader.id}, [leader.id, f.target])


# ------------------------------------------------------------ помесячно

static func monthly(game: Game) -> void:
	var regen := _d(game, "control_regen", 1)
	for p in game.state.provinces.values():
		var t: Variant = game.state.titles.get(p.id)
		if t == null or t.holder == null:
			continue
		var ctl: Variant = p.vars.get("control")
		if ctl != null and p.occupant == null and not p.vars.has("revolt"):
			var h: Variant = game.ch(t.holder)
			set_control(game, p.id, float(ctl) + regen + (Stats.stat(game, h, "control_gain") if h != null else 0.0))
		var lst: Variant = p.vars.get("copinions")
		if lst != null:
			var keep: Array = lst.filter(func(e): return e.get("expires") == null or int(e.expires) > game.date)
			if keep.size() != lst.size():
				if keep.is_empty():
					p.vars.erase("copinions")
				else:
					p.vars.copinions = keep
				_forget(game, p.id)
		if p.vars.has("revolt_cd") and int(p.vars.revolt_cd) <= game.date:
			p.vars.erase("revolt_cd")
		if p.vars.has("complaint_cd") and int(p.vars.complaint_cd) <= game.date:
			p.vars.erase("complaint_cd")

	if not game.engine.has_feature("factions") or popular_defs(game).is_empty():
		return
	_update_membership(game)
	_update_discontent(game)
	_manage_revolts(game)


static func _at_war(game: Game, f: Dictionary) -> bool:
	return game.state.wars.values().any(func(w): return w.get("faction") == f.id)


static func _update_membership(game: Game) -> void:
	var defs := popular_defs(game)
	var max_join := -INF
	for d in defs:
		max_join = maxf(max_join, Data.num(_pop(d).get("join_opinion"), -30))
	var idx := {}
	for f in game.state.factions.values():
		if not is_popular(f):
			continue
		if _at_war(game, f):
			for cid in f.counties:
				idx[cid] = f
			continue
		f.counties = f.counties.filter(func(cid):
			var t: Variant = game.state.titles.get(cid)
			return t != null and t.holder == f.target)
		for cid in f.counties:
			idx[cid] = f
	var chance := _d(game, "join_chance", 0.3)
	for p in game.state.provinces.values():
		var t: Variant = game.state.titles.get(p.id)
		if t == null or t.holder == null:
			continue
		var f: Variant = idx.get(p.id)
		if f != null:
			if _at_war(game, f):
				continue
			var fdef: Variant = game.content.get_def("factions", f.type)
			if fdef == null or opinion(game, p.id) > Data.num(_pop(fdef).get("leave_opinion"), -15):
				leave_county(game, f, p.id)
			continue
		if p.occupant != null or p.vars.has("revolt_cd") or p.vars.has("revolt"):
			continue
		var op := opinion(game, p.id)
		if op > max_join or not game.rng.chance(chance):
			continue
		var h: Variant = game.ch(t.holder)
		if h == null or not Chars.is_alive(h):
			continue
		var ctx := ScriptContext.make(game, {"type": "province", "id": p.id}, {"holder": {"type": "character", "id": h.id}})
		for d in defs:
			if op > Data.num(_pop(d).get("join_opinion"), -30):
				continue
			if not Interp.eval_trigger(ctx, ctx.root, d.get("can_join")):
				continue
			join_county(game, d, p.id, h)
			break
	for f in game.state.factions.values():
		if is_popular(f) and f.counties.is_empty() and not _at_war(game, f):
			Factions.dissolve(game, f, false)


static func _update_discontent(game: Game) -> void:
	for f in game.state.factions.values():
		if not is_popular(f) or not game.state.factions.has(f.id) or _at_war(game, f):
			continue
		var holder: Variant = game.ch(f.target)
		var def: Variant = game.content.get_def("factions", f.type)
		if holder == null or def == null:
			continue
		var pop := _pop(def)
		var gain := Data.num(pop.get("discontent_gain"), 4)
		var thr: Variant = pop.get("power_threshold")
		var can_rise := true
		if def.get("can_rise") != null:
			var hctx := ScriptContext.make(game, {"type": "character", "id": holder.id})
			can_rise = Interp.eval_trigger(hctx, hctx.root, def.can_rise)
		if can_rise and (thr == null or power(game, f) >= Data.num(thr)):
			f.discontent = minf(100.0, float(f.discontent) + gain)
		else:
			f.discontent = maxf(0.0, float(f.discontent) - game.def_num("factions.discontent_decay", 4))
		if f.discontent >= 100.0 and holder.get("prison") == null:
			_ultimatum(game, f)


## Войны мятежников: без войска — разбиты; у ИИ-мятежников — победа по счёту.
static func _manage_revolts(game: Game) -> void:
	for w in game.state.wars.values():
		if not w.get("popular", false) or not game.state.wars.has(w.id):
			continue
		if Military.armies_of(game, w.attacker).is_empty():
			Wars.end_war(game, w, "defeat")
			continue
		var ws: float = Wars.warscore(game, w).total
		if ws >= 100.0:
			Wars.end_war(game, w, "victory")
		elif ws >= game.def_num("ai.enforce_at", 50) and game.ai_controls(w.defender) and Wars.ai_will_accept_surrender(game, w, "def"):
			Wars.end_war(game, w, "victory")


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("populace", {"id": "populace", "order": 59, "on_month": Populace.monthly, "on_character_month": Populace.monthly_char}, OWNER)
	# низкий контроль — меньше налога и ополчения
	# контроль (крепость власти) и мнение графства (отношение народа) —
	# налог и ополчение графства
	engine.province_modifier_providers.register("populace", {"fn": func(game: Game, prov_id: String) -> Variant:
		if Titles.county_holder(game, prov_id) == null:
			return null
		var ctl := Populace.control(game, prov_id)
		var m := Populace.output_mult(game, prov_id)
		if ctl < 100.0:
			m += (ctl / 100.0 - 1.0) * Populace._d(game, "control_effect", 0.75)
		return {"tax_mult": m, "levy_mult": m} if m != 0.0 else null
	}, OWNER)
	var H := engine.hooks
	# завоевание: графство ушло в чужую державу при живом прежнем владельце
	H.on("title.transferred", func(p):
		var game: Game = p.game
		var tid: String = p.title
		if Titles.tier_of(game, tid) != 1:
			return
		Populace._forget(game, tid)
		var old: Variant = game.ch(p.get("from"))
		var neo: Variant = game.ch(p.get("to"))
		if old == null or neo == null or old.death != null:
			return
		if Titles.top_liege(game, old).id != Titles.top_liege(game, neo).id:
			Populace.set_control(game, tid, minf(Populace.control(game, tid), Populace._d(game, "conquest_control", 25)))
	, 0, OWNER)
	H.on("siege.won", func(p):
		var game: Game = p.game
		var w: Dictionary = p.war
		var cid: String = p.province
		var holder: Variant = Titles.county_holder(game, cid)
		var a: Dictionary = p.army
		if holder != null and Wars.side_of(game, w, holder.id) != Wars.participant_side(w, a.owner):
			Populace.add_control(game, cid, -Populace._d(game, "occupation_control_loss", 40))
		# графство, взятое мятежниками, пополняет их войско
		if w.get("popular", false) and a.owner == w.attacker:
			var add := roundi(Economy.county_levy(game, cid) * Populace._d(game, "occupy_levy_mult", 0.5))
			a.size = int(a.size) + add
			a.max_size = int(a.max_size) + add
	, 0, OWNER)
	# ополчение под знамёнами: с какого дня
	H.on("army.raised", func(p):
		var c: Variant = p.game.ch(p.army.owner)
		if c != null and not c.vars.has("levies_since"):
			c.vars["levies_since"] = p.game.date
			Populace._forget_domain_opinions(p.game, c)
	, 0, OWNER)
	H.on("army.disbanded", func(p):
		var c: Variant = p.game.ch(p.army.owner)
		if c != null and c.vars.has("levies_since") and Military.armies_of(p.game, c.id).is_empty():
			c.vars.erase("levies_since")
			Populace._forget_domain_opinions(p.game, c)
	, 0, OWNER)
	H.on("war.ended", func(p):
		var game: Game = p.game
		var w: Dictionary = p.war
		if not w.get("popular", false):
			return
		var crushed: bool = p.outcome == "defeat"
		var until := game.date + roundi(Populace._d(game, "revolt_cooldown_years", 10) * GameDate.DAYS_PER_YEAR)
		for cid in w.target_counties:
			var pr: Variant = game.state.provinces.get(cid)
			if pr == null:
				continue
			pr.vars.erase("revolt")
			var t: Variant = game.state.titles.get(cid)
			if t != null and t.holder == w.defender:
				pr.vars["revolt_cd"] = until
				if crushed:
					Populace.add_control(game, cid, -Populace._d(game, "crushed_control_loss", 30))
		for a in Military.armies_of(game, w.attacker):
			Military.disband_army(game, a.id)
		# вожак, оставшийся без земли и не в темнице, уходит ко двору владельца
		var leader: Variant = game.ch(w.attacker)
		if leader != null and Chars.is_alive(leader) and leader.titles.is_empty() and leader.get("prison") == null and leader.liege == null and game.is_alive(w.defender):
			Chars.set_liege(game, leader, w.defender)
	, 10, OWNER)
	engine.content_validators.register("populace", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("factions"):
			var pop: Variant = d.get("popular")
			if pop == null:
				continue
			var w: String = "factions/" + d.id
			if not (pop is Dictionary):
				v.issue(w + ": popular — словарь")
				continue
			v.ref("casus_belli", d.get("cb"), w)
			v.trigger(d.get("can_join"), w + " can_join")
			var ld: Variant = pop.get("leader")
			if ld is Dictionary:
				for t in Data.as_array(ld.get("traits")):
					v.ref("traits", t, w + " leader")
			for k in Data.as_array(pop.get("group_by")):
				if not ["faith", "culture"].has(str(k)):
					v.issue(w + ": group_by — faith или culture, а не \"%s\"" % k)
		for gdef in e.content.all("county_grievances"):
			if Data.as_array(gdef.get("parts")).is_empty():
				v.issue("county_grievances/%s: нужен список parts" % gdef.id)
		var nm: Variant = e.content.singleton("defines").get("populace", {}).get("negotiated_modifier")
		if nm != null:
			v.ref("opinion_modifiers", nm, "defines.populace.negotiated_modifier")
	, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	const PR := ["province"]
	const CH := ["character"]
	const FA := ["faction"]
	r.values.register("county_opinion", {"scopes": PR, "doc": "Мнение графства о владельце (−100…100)", "get": func(ctx, s, _a):
		return Populace.opinion(ctx.game, s.id)
	}, OWNER)
	r.values.register("control", {"scopes": PR, "doc": "Контроль над графством (0–100)", "get": func(ctx, s, _a):
		return Populace.control(ctx.game, s.id)
	}, OWNER)
	r.triggers.register("in_popular_faction", {"scopes": PR, "doc": "Графство во народной фракции (yes/no или тип фракции)", "eval": func(ctx, s, arg):
		var f: Variant = Populace.faction_of_county(ctx.game, s.id)
		if arg is bool or (arg is String and (arg == "yes" or arg == "no")):
			return (f != null) == ScriptContext.is_yes(arg)
		return f != null and f.type == arg
	}, OWNER)
	r.triggers.register("is_in_revolt", {"scopes": PR, "doc": "Графство поднялось на мятеж", "eval": func(ctx, s, arg):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		return (p != null and p.vars.has("revolt")) == ScriptContext.is_yes(arg)
	}, OWNER)
	r.triggers.register("county_grievance", {"scopes": PR, "doc": "Главная причина недовольства графства (id из county_grievances; yes/no — есть ли она)", "eval": func(ctx, s, arg):
		var gr := Populace.grievance(ctx.game, s.id)
		if arg is bool or (arg is String and (arg == "yes" or arg == "no")):
			return (gr != "") == ScriptContext.is_yes(arg)
		return gr == str(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.county_grievance", {"value": ctx.game.name_of("county_grievances", str(arg))}),
	}, OWNER)
	r.effects.register("add_control", {"scopes": PR, "doc": "Изменить контроль над графством: add_control: 20", "apply": func(ctx, s, arg):
		Populace.add_control(ctx.game, s.id, Interp.eval_value(ctx, s, arg)),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.add_control", {"place": ctx.game.scope_name(s), "value": Builtins.signed(Interp.eval_value(ctx, s, arg))}),
	}, OWNER)
	r.effects.register("add_county_opinion", {"scopes": PR, "doc": "Модификатор мнения графства о владельце: add_county_opinion: <id из opinion_modifiers> или { modifier, value }",
		"apply": func(ctx, s, arg):
			var mod := str(arg.get("modifier")) if arg is Dictionary else str(arg)
			var val: Variant = Interp.eval_value(ctx, s, arg.value) if arg is Dictionary and arg.get("value") != null else null
			Populace.add_county_opinion(ctx.game, s.id, mod, val),
		"describe": func(ctx, s, arg):
			var mod := str(arg.get("modifier")) if arg is Dictionary else str(arg)
			var def: Variant = ctx.game.content.get_def("opinion_modifiers", mod)
			var val: float = Interp.eval_value(ctx, s, arg.value) if arg is Dictionary and arg.get("value") != null else (Data.num(def.get("value")) if def != null else 0.0)
			return ctx.game.loc.t("fx.add_county_opinion", {"place": ctx.game.scope_name(s), "value": Builtins.signed(val), "name": ctx.game.name_of("opinion_modifiers", mod)}),
	}, OWNER)
	r.effects.register("remove_county_opinion", {"scopes": PR, "doc": "Убрать модификатор мнения графства", "apply": func(ctx, s, arg):
		Populace.remove_county_opinion(ctx.game, s.id, str(arg))
	}, OWNER)
	var low_control := func(g: Game, c: Dictionary) -> int:
		var lim := g.def_num("populace.low_control", 60)
		return Data.count(Titles.domain_counties(g, c), func(cid): return Populace.control(g, cid) < lim)
	var unhappy := func(g: Game, c: Dictionary) -> int:
		var lim := g.def_num("populace.unhappy_opinion", -20)
		return Data.count(Titles.domain_counties(g, c), func(cid): return Populace.opinion(g, cid) <= lim)
	r.values.register("num_low_control_counties", {"scopes": CH, "doc": "Графств домена с низким контролем (ниже defines.populace.low_control)", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return float(low_control.call(ctx.game, c)) if c != null else 0.0
	}, OWNER)
	r.values.register("num_unhappy_counties", {"scopes": CH, "doc": "Графств домена, недовольных владельцем (мнение не выше defines.populace.unhappy_opinion)", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return float(unhappy.call(ctx.game, c)) if c != null else 0.0
	}, OWNER)
	r.values.register("num_faction_counties", {"scopes": FA, "doc": "Графств в народной фракции", "get": func(ctx, s, _a):
		var f: Variant = ctx.game.state.factions.get(s.id)
		return float(f.get("counties", []).size()) if f != null else 0.0
	}, OWNER)
	r.lists.register("faction_county", {"from": FA, "doc": "Графства народной фракции", "list": func(ctx, s):
		var f: Variant = ctx.game.state.factions.get(s.id) if s != null else null
		return f.get("counties", []).map(func(id): return {"type": "province", "id": id}) if f != null else []
	}, OWNER)
	r.effects.register("take_faction_counties", {"scopes": CH, "doc": "Вожак народной фракции (scope:faction) забирает её графства и правит сам: yes или { create_titles: yes }",
		"apply": func(ctx, s, arg):
			var c: Variant = ctx.game.ch(s.id)
			var fr: Variant = ctx.scopes.get("faction")
			var f: Variant = ctx.game.state.factions.get(fr.id) if fr is Dictionary else null
			if c != null and f != null:
				Populace.take_counties(ctx.game, c, f, arg is Dictionary and ScriptContext.is_yes(arg.get("create_titles"))),
		"describe": func(ctx, s, _arg):
			return ctx.game.loc.t("fx.take_faction_counties", {"who": ctx.game.scope_name(s)}),
	}, OWNER)

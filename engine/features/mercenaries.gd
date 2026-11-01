class_name Mercenaries
extends EngineFeature
## Наёмные роты: быстро, дорого, уходят без платы.
##
## Роты мира (state.mercenaries) — из common/retinue.yaml (mercenary_companies)
## и вольные роты, ушедшие из дружин (Retinue). У роты — капитан (живой
## человек без двора, флаг merc_captain), отряды с опытом, родное графство.
## Найм: разовая цена и плата в месяц (defines.mercenaries); отряды роты
## встают в дружину нанимателя (поле merc, вне предела отрядов) и сразу
## идут в его поднятую армию. Срок — contract_months; на войне контракт
## продлевается, пока платят. В долгах рота уходит; уходит и после смерти
## нанимателя. Свободная рота пополняется сама.
##
## Запись роты: {id, def, name?, icon, captain, home, employer, until, regiments}.

const OWNER := "core/mercenaries"


func _init() -> void:
	id = "mercenaries"
	doc = "Наёмные роты: найм, плата, контракт, уход без платы"


static func _n(game: Game, key: String, fallback: float) -> float:
	return game.def_num("mercenaries." + key, fallback)


static func all(game: Game) -> Dictionary:
	if not (game.state.get("mercenaries") is Dictionary):
		game.state["mercenaries"] = {}
	return game.state.mercenaries


static func get_company(game: Game, mid: Variant) -> Variant:
	return all(game).get(mid) if mid != null else null


static func name_of(game: Game, m: Dictionary) -> String:
	if m.get("name") is Array:
		return Retinue.name_from_parts(game, m.name)
	return game.name_of("mercenary_companies", m.get("def"))


## Отряды роты: у нанимателя или у неё самой.
static func regiments_of(game: Game, m: Dictionary) -> Array:
	var emp: Variant = game.ch(m.get("employer"))
	if emp != null:
		return Regiments.regs_of(emp).filter(func(r): return r.get("merc") == m.id)
	return Data.as_array(m.get("regiments"))


static func men_of(game: Game, m: Dictionary) -> int:
	var n := 0
	for r in regiments_of(game, m):
		n += int(r.size)
	return n


static func avg_xp(game: Game, m: Dictionary) -> float:
	var regs := regiments_of(game, m)
	if regs.is_empty():
		return 0.0
	var s := 0.0
	var w := 0.0
	for r in regs:
		s += float(r.get("xp", 0.0)) * float(r.size)
		w += float(r.size)
	return s / maxf(1.0, w)


static func hired_by(game: Game, cid: String) -> Array:
	return all(game).values().filter(func(m): return m.get("employer") == cid)


## Разовая цена найма: цена отрядов × hire_mult × (1 + опыт / xp_price).
static func hire_cost(game: Game, m: Dictionary) -> float:
	var g := 0.0
	for r in regiments_of(game, m):
		var def: Variant = game.content.get_def("regiment_types", r.type)
		if def != null:
			var cd: Variant = def.get("cost")
			g += Data.num(cd.get("gold") if cd is Dictionary else 0.0) * float(r.size) / maxf(1.0, Data.num(def.get("size"), 100))
	return roundf(g * _n(game, "hire_mult", 0.45) * (1.0 + avg_xp(game, m) / maxf(1.0, _n(game, "xp_price", 500))))


## Плата в месяц: жалованье отрядов × fee_mult.
static func fee(game: Game, m: Dictionary) -> float:
	var u := 0.0
	for r in regiments_of(game, m):
		var def: Variant = game.content.get_def("regiment_types", r.type)
		if def != null:
			u += Data.num(def.get("upkeep")) * Retinue.upkeep_mult(game, r)
	return snappedf(u * _n(game, "fee_mult", 3.0), 0.01)


static func hire_blockers(game: Game, c: Dictionary, m: Dictionary) -> Array:
	var out := []
	if c.titles.is_empty() or Titles.primary_tier(game, c) < int(_n(game, "min_tier", 1)):
		out.append(game.loc.t("tr.is_ruler"))
	if m.get("employer") != null:
		out.append(game.loc.t("merc.busy"))
	if hired_by(game, c.id).size() >= int(_n(game, "max_hired", 2)):
		out.append(game.loc.t("merc.max_hired", {"n": int(_n(game, "max_hired", 2))}))
	if men_of(game, m) <= 0:
		out.append(game.loc.t("merc.no_men"))
	var cost := hire_cost(game, m)
	if float(c.gold) < cost:
		out.append(game.loc.t("merc.no_gold", {"n": roundi(cost)}))
	return out


## Нанять роту: отряды встают в дружину и в поднятую армию нанимателя.
static func hire(game: Game, c: Dictionary, mid: String) -> bool:
	var m: Variant = get_company(game, mid)
	if m == null or not hire_blockers(game, c, m).is_empty():
		return false
	var cost := hire_cost(game, m)
	Treasury.add(game, c, -cost, "war")
	game.touch(c)
	var regs: Array = Data.as_array(m.get("regiments"))
	m["regiments"] = []
	if c.get("regiments") == null:
		c["regiments"] = []
	for r in regs:
		r["merc"] = mid
		r["captain"] = m.get("captain")
		c.regiments.append(r)
	m["employer"] = c.id
	m["until"] = game.date + int(_n(game, "contract_months", 12) * 30)
	# быстро: рота догоняет поднятую армию
	var main: Variant = null
	for a in Military.armies_of(game, c.id):
		if main == null or int(a.size) > int(main.size):
			main = a
	if main != null:
		if not (main.get("regiments") is Array):
			main["regiments"] = []
		for r in regs:
			if int(r.size) > 0:
				main.regiments.append(r.duplicate())
				main.size = int(main.size) + int(r.size)
				main.max_size = int(main.max_size) + int(r.size)
	game.emit("mercenaries.hired", {"character": c, "company": m})
	game.notify("army")
	return true


## Рота уходит от нанимателя: отряды возвращаются к ней (с потерями и опытом).
static func release(game: Game, mid: String, why: String = "contract") -> void:
	var m: Variant = get_company(game, mid)
	if m == null:
		return
	var emp: Variant = game.ch(m.get("employer"))
	if emp != null:
		for a in Military.armies_of(game, emp.id):
			Regiments._sync_from_army(game, a)
		var mine := Regiments.regs_of(emp).filter(func(r): return r.get("merc") == mid)
		for r in mine:
			Regiments.disband(game, emp, r.id)
		m["regiments"] = mine
		if game.is_player(emp.id):
			game.message(game.loc.t("msg.merc_left." + why, {"name": name_of(game, m)}), "bad" if why != "contract" else "info")
	m["employer"] = null
	m["until"] = null
	game.emit("mercenaries.released", {"company": m, "employer": emp.id if emp != null else null, "why": why})
	game.notify("army")


## Капитан роты: живой человек без двора.
static func _make_captain(game: Game, m: Dictionary, rng: Rng, culture: Variant = null) -> Variant:
	var p: Variant = game.prov(m.get("home"))
	var cul := str(culture) if culture != null else (str(p.culture) if p != null else "")
	if game.content.get_def("cultures", cul) == null:
		var cs := game.content.ids("cultures")
		if cs.is_empty():
			return null
		cul = str(cs[0])
	var faith := str(p.faith) if p != null and p.get("faith") != null else ""
	if faith == "" or game.content.get_def("faiths", faith) == null:
		var fs := game.content.ids("faiths")
		faith = str(fs[0]) if not fs.is_empty() else ""
	var d: Variant = game.content.get_def("mercenary_companies", m.get("def"))
	var sk: Dictionary = d.get("captain", {}) if d != null and d.get("captain") is Dictionary else {}
	var skills := {}
	for k in sk:
		skills[k] = maxi(0, roundi(Data.num(sk[k]) + rng.range_float(-2.0, 2.0)))
	# свой генератор: капитаны не сдвигают общий ход случайностей мира
	var saved := game.rng
	game.rng = rng
	var c := Chars.create_character(game, {"culture": cul, "faith": faith, "age": 28 + rng.range_int(0, 16), "female": rng.chance(0.15),
		"dynasty": null, "skills": skills, "liege": null})
	game.rng = saved
	c.flags["merc_captain"] = m.id
	game.touch(c)
	m["captain"] = c.id
	for r in regiments_of(game, m):
		r["captain"] = c.id
	return c


static func _new_regiment(game: Game, type: String, xp: float) -> Dictionary:
	var def: Variant = game.content.get_def("regiment_types", type)
	var r := {"id": game.new_id("reg"), "type": type, "size": int(Data.num(def.get("size"), 100)) if def != null else 100, "xp": xp, "since": game.date}
	r["name"] = Retinue.gen_name(game, r)
	return r


## Роты мира на старте (по записи mercenary_companies на каждую).
static func setup(game: Game) -> void:
	var rng := Rng.from_seed("mercs:%d" % int(game.rng.state.get("s", 0)))
	var homes: Array = game.state.provinces.keys().filter(func(pid): return game.state.titles.get(pid) != null and game.state.titles[pid].get("holder") != null)
	homes.sort()
	for d in game.content.all("mercenary_companies"):
		var mid := "merc_" + str(d.id)
		if all(game).has(mid):
			continue
		var regs := []
		var comp: Variant = d.get("regiments")
		if comp is Dictionary:
			for t in comp:
				if game.content.get_def("regiment_types", t) == null:
					continue
				for i in int(Data.num(comp[t])):
					regs.append(_new_regiment(game, str(t), Data.num(d.get("xp")) * rng.range_float(0.8, 1.2)))
		var m := {"id": mid, "def": str(d.id), "icon": d.get("icon", "⚔"), "home": rng.pick(homes) if not homes.is_empty() else null,
			"employer": null, "until": null, "regiments": regs, "captain": null}
		all(game)[mid] = m
		_make_captain(game, m, rng, d.get("culture"))


## Вольная рота из ушедшего отряда дружины: имя отряда, его капитан.
static func found_free(game: Game, r: Dictionary, captain: Dictionary, from: Dictionary) -> Dictionary:
	var mid := game.new_id("merc")
	var p: Variant = Titles.capital_of(game, from)
	var reg := r.duplicate(true)
	reg.erase("merc")
	reg["captain"] = captain.id
	var def: Variant = game.content.get_def("regiment_types", reg.type)
	var m := {"id": mid, "def": null, "name": Retinue.name_parts(game, r), "icon": def.get("icon", "⚔") if def != null else "⚔",
		"home": p, "employer": null, "until": null, "regiments": [reg], "captain": captain.id, "free_from": from.id}
	all(game)[mid] = m
	# капитан уходит со двора с отрядом
	captain.liege = null
	captain.flags["merc_captain"] = mid
	game.touch(captain)
	game.mark_people_dirty()
	game.emit("mercenaries.founded", {"company": m, "from": from.id})
	return m


static func monthly(game: Game) -> void:
	var rate := _n(game, "reinforce_rate", 0.08)
	for m in all(game).values().duplicate():
		var emp: Variant = game.ch(m.get("employer"))
		if m.get("employer") != null:
			if emp == null or not Chars.is_alive(emp) or emp.titles.is_empty():
				release(game, m.id, "employer")
			elif float(emp.gold) < 0.0:
				# без платы рота уходит
				release(game, m.id, "unpaid")
			elif m.get("until") != null and game.date >= int(m.until):
				if Wars.wars_of(game, emp.id).is_empty():
					release(game, m.id, "contract")
				else:
					m["until"] = game.date + 30
		# капитан пал — рота выбирает нового
		var cap: Variant = game.ch(m.get("captain"))
		if cap == null or not Chars.is_alive(cap):
			_make_captain(game, m, Rng.from_seed("merc_cap:%s:%d" % [m.id, game.date]))
		if m.get("employer") == null:
			for r in Data.as_array(m.get("regiments")):
				var def: Variant = game.content.get_def("regiment_types", r.type)
				var mx := int(Data.num(def.get("size"), r.size)) if def != null else int(r.size)
				if int(r.size) < mx:
					var before := int(r.size)
					r.size = mini(mx, roundi(float(r.size) + mx * rate))
					Retinue.on_reinforced(game, r, before)


## ИИ на войне нанимает роту, если не сильнее врага с запасом.
static func ai_monthly_char(game: Game, c: Dictionary) -> void:
	if c.titles.is_empty() or not game.ai_controls(c.id) or c.get("prison") != null:
		return
	var foes := Wars.enemies_of(game, c.id)
	if foes.is_empty() or hired_by(game, c.id).size() >= int(_n(game, "max_hired", 2)):
		return
	if not game.rng.chance(_n(game, "ai_hire_chance", 0.5)):
		return
	var theirs := 0.0
	for f in foes:
		var fc: Variant = game.ch(f)
		if fc != null:
			theirs = maxf(theirs, Economy.military_strength(game, fc))
	# нанимают, пока не сильнее врага с запасом (ai_hire_ratio)
	if Economy.military_strength(game, c) >= theirs * _n(game, "ai_hire_ratio", 1.15):
		return
	var best: Variant = null
	var best_v := 0.0
	var reserve := _n(game, "ai_gold_reserve", 20)
	for m in all(game).values():
		if not hire_blockers(game, c, m).is_empty() or float(c.gold) < hire_cost(game, m) + reserve:
			continue
		if Economy.monthly_income(game, c) < fee(game, m):
			continue
		var v := float(men_of(game, m)) * (1.0 + avg_xp(game, m) / 500.0)
		if v > best_v:
			best_v = v
			best = m
	if best != null:
		hire(game, c, best.id)


func install(engine: GameEngine) -> void:
	engine.systems.register("mercenaries", {"id": "mercenaries", "order": 54, "on_month": Mercenaries.monthly, "on_character_month": Mercenaries.ai_monthly_char}, OWNER)
	engine.hooks.on("game.setup", func(p): Mercenaries.setup(p.game), -10, OWNER)
	# старые сохранения и роты, добавленные модами позже, — дозаводим
	engine.hooks.on("game.loaded", func(p): Mercenaries.setup(p.game), 0, OWNER)
	# плата роте — строка в доходах
	engine.hooks.on("economy.income", func(p):
		var game: Game = p.game
		var v := 0.0
		for m in Mercenaries.hired_by(game, p.character.id):
			v += Mercenaries.fee(game, m)
		return {"label": game.loc.t("merc.fee_line"), "value": -v, "key": "mercenary_fees"} if v != 0.0 else null
	, 0, OWNER)
	# наниматель умер — роты уходят до того, как отряды перейдут к наследнику
	engine.hooks.on("succession", func(p):
		for m in Mercenaries.hired_by(p.game, p.deceased.id):
			Mercenaries.release(p.game, m.id, "employer")
	, 10, OWNER)
	engine.content_validators.register("mercenary_companies", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("mercenary_companies"):
			var w := "mercenary_companies/" + str(d.id)
			if not (d.get("regiments") is Dictionary) or d.regiments.is_empty():
				v.issue(w + ": нужен состав regiments")
			else:
				for t in d.regiments:
					v.ref("regiment_types", t, w + " regiments")
	, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	r.values.register("num_hired_companies", {"scopes": ["character"], "doc": "Наёмных рот на службе", "get": func(ctx, s, _a):
		return float(Mercenaries.hired_by(ctx.game, str(s.id)).size()),
	}, OWNER)

class_name Decisions
extends RefCounted
## Решения (decisions) и постройки.

# ------------------------------------------------------------ решения

static func context(game: Game, c: Dictionary) -> ScriptContext:
	return ScriptContext.make(game, {"type": "character", "id": c.id}, {"actor": {"type": "character", "id": c.id}})


static func _cost_of(ctx: ScriptContext, cost: Variant) -> Dictionary:
	var cd: Dictionary = cost if cost is Dictionary else {}
	return {
		"gold": roundf(Interp.eval_value(ctx, ctx.root, cd.get("gold", 0))),
		"prestige": roundf(Interp.eval_value(ctx, ctx.root, cd.get("prestige", 0))),
		"piety": roundf(Interp.eval_value(ctx, ctx.root, cd.get("piety", 0))),
	}


static func cost(game: Game, def: Dictionary, c: Dictionary) -> Dictionary:
	return _cost_of(context(game, c), def.get("cost"))


## ctx — готовый контекст персонажа (ИИ переиспользует один на все решения).
static func is_shown(game: Game, def: Dictionary, c: Dictionary, ctx: ScriptContext = null) -> bool:
	if ctx == null:
		ctx = context(game, c)
	return Interp.eval_trigger(ctx, ctx.root, def.get("is_shown"))


static func blockers(game: Game, def: Dictionary, c: Dictionary) -> Array:
	var ctx := context(game, c)
	var out := Interp.failed_triggers(ctx, ctx.root, def.get("is_valid"))
	out.append_array(Economy.cost_blockers(game, c, cost(game, def, c)))
	var cd: Variant = c.flags.get("dec:" + str(def.id))
	if cd != null and (cd == 0 or cd > game.date):
		out.append(game.loc.t("ui.on_cooldown", {"days": "∞" if cd == 0 else str(int(cd) - game.date)}))
	return out


## Быстрая проверка для ИИ — то же, что blockers().is_empty(), но без текстов
## причин: сначала перезарядка, затем условия, затем цена.
static func can_take(game: Game, def: Dictionary, c: Dictionary, ctx: ScriptContext = null) -> bool:
	var cd: Variant = c.flags.get("dec:" + str(def.id))
	if cd != null and (cd == 0 or cd > game.date):
		return false
	if ctx == null:
		ctx = context(game, c)
	if not Interp.eval_trigger(ctx, ctx.root, def.get("is_valid")):
		return false
	if def.get("cost") == null:
		return true
	var cst := _cost_of(ctx, def.cost)
	return (cst.gold <= 0 or float(c.gold) >= cst.gold) and (cst.prestige <= 0 or float(c.prestige) >= cst.prestige) \
		and (cst.piety <= 0 or float(c.piety) >= cst.piety)


static func take(game: Game, def: Dictionary, c: Dictionary) -> bool:
	if not is_shown(game, def, c) or not blockers(game, def, c).is_empty():
		return false
	if not game.engine.hooks.veto("decision.before", {"game": game, "decision": def.id, "character": c}):
		return false
	var cst := cost(game, def, c)
	Treasury.add(game, c, -cst.gold, Treasury.cat_of_src(game, "decision:" + str(def.id)))
	c.prestige -= cst.prestige
	c.piety -= cst.piety
	if def.get("cooldown") != null:
		c.flags["dec:" + str(def.id)] = game.date + GameDate.duration_days(def.cooldown)
	var ctx := context(game, c)
	ctx.values["__src"] = "decision:" + str(def.id)
	Interp.run_effect(ctx, ctx.root, def.get("effect"))
	game.emit("decision.taken", {"decision": def.id, "character": c.id})
	return true


# ------------------------------------------------------------ постройки

static func building_slots(game: Game, prov_id: String) -> int:
	var def: Variant = game.content.get_def("provinces", prov_id)
	var n: int = Data.as_array(def.get("holdings")).size() if def != null else 1
	return maxi(1, n) * int(game.def_num("buildings.slots_per_holding", 2))


## Особые постройки (special: yes) не строятся и не занимают места: они даны
## графству с начала игры или событием.
static func is_special_building(game: Game, b: String) -> bool:
	var d: Variant = game.content.get_def("buildings", b)
	return d != null and d.get("special", false)


## [{def, blockers}]
static func building_candidates(game: Game, c: Dictionary, prov_id: String) -> Array:
	var p: Variant = game.state.provinces.get(prov_id)
	var pdef: Variant = game.content.get_def("provinces", prov_id)
	if p == null or pdef == null:
		return []
	var out := []
	# постройки без района — по старинке, места по владениям
	var used := Data.count(p.buildings, func(b): return not is_special_building(game, b) and Districts.building_district(game, b) == null)
	var full: bool = used >= building_slots(game, prov_id)
	var holdings := Data.as_array(pdef.get("holdings"))
	var districts_on := Districts.on(game)
	for b in game.content.all("buildings"):
		if p.buildings.has(b.id) or b.get("special", false):
			continue
		if b.get("holding") != null and not holdings.has(b.holding):
			continue
		if Data.as_array(b.get("requires")).any(func(r): return not p.buildings.has(r)):
			continue
		var did: Variant = Districts.building_district(game, b.id) if districts_on else null
		# постройки района видны, когда район заложен
		if did != null and Districts.level(game, prov_id, did) <= 0:
			continue
		var bl := []
		var t: Variant = game.state.titles.get(prov_id)
		if t == null or t.holder != c.id:
			bl.append(game.loc.t("ui.not_your_domain"))
		if p.construction != null:
			bl.append(game.loc.t("ui.already_building"))
		if p.occupant != null:
			bl.append(game.loc.t("ui.occupied"))
		if did != null:
			var need := int(Data.num(b.get("level"), 1))
			if Districts.level(game, prov_id, did) < need:
				bl.append(game.loc.t("ui.needs_district_level", {"district": game.name_of("districts", did), "level": Districts.roman(need)}))
			elif Districts.buildings_in(game, prov_id, did).size() >= Districts.slots(game, prov_id, did):
				bl.append(game.loc.t("ui.district_full", {"district": game.name_of("districts", did)}))
		elif full:
			bl.append(game.loc.t("ui.no_slots"))
		# великие стройки: одна в мире (unique: world) или одна на державу (unique: realm)
		if b.get("unique") != null and bl.is_empty():
			var where: Variant = unique_taken(game, b.id, str(b.unique), c)
			if where != null:
				bl.append(game.loc.t("ui.unique_taken_" + str(b.unique), {"place": game.name_of("provinces", where)}))
		var ctx = ScriptContext.make(game, {"type": "province", "id": prov_id}, {"builder": {"type": "character", "id": c.id}})
		bl.append_array(Interp.failed_triggers(ctx, ctx.root, b.get("trigger")))
		var cost := building_cost(game, b, c, prov_id)
		var cb := Economy.cost_blockers(game, c, cost)
		# cost_only — мешает только нехватка золота (на это ИИ может накопить)
		out.append({"def": b, "blockers": bl + cb, "cost": cost, "cost_only": bl.is_empty() and not cb.is_empty() and float(c.prestige) >= float(cost.prestige)})
	return out


## Где уже стоит (или строится) единственная постройка: графство или null.
## kind: world — во всём мире; realm — в державе верховного сюзерена c.
static func unique_taken(game: Game, bid: String, kind: String, c: Dictionary) -> Variant:
	var pool: Array
	if kind == "realm":
		pool = Titles.realm_counties(game, Titles.top_liege(game, c))
	else:
		pool = game.state.provinces.keys()
	for pid in pool:
		var p: Variant = game.state.provinces.get(pid)
		if p == null:
			continue
		if p.buildings.has(bid):
			return pid
		var cons: Variant = p.get("construction")
		if cons is Dictionary and cons.get("building") == bid:
			return pid
	return null


static func building_cost(game: Game, b: Dictionary, c: Dictionary, prov_id: String) -> Dictionary:
	var ctx = ScriptContext.make(game, {"type": "province", "id": prov_id}, {"builder": {"type": "character", "id": c.id}})
	var mult := maxf(0.1, 1.0 + Stats.stat(game, c, "build_cost_mult"))
	var cd: Dictionary = b.get("cost") if b.get("cost") is Dictionary else {}
	return {
		"gold": roundf(Interp.eval_value(ctx, ctx.root, cd.get("gold", 0)) * mult),
		"prestige": roundf(Interp.eval_value(ctx, ctx.root, cd.get("prestige", 0))),
	}


static func start_building(game: Game, c: Dictionary, prov_id: String, building_id: String) -> bool:
	var cand: Variant = null
	for x in building_candidates(game, c, prov_id):
		if x.def.id == building_id:
			cand = x
			break
	if cand == null or not cand.blockers.is_empty():
		return false
	var cst = building_cost(game, cand.def, c, prov_id)
	Treasury.add(game, c, -cst.gold, "construction")
	c.prestige -= cst.prestige
	# build_time_mult — быстрее строят умелые управители (за очко управления)
	var days := Data.num(cand.def.get("days"), 365) * maxf(0.3, 1.0 + Stats.stat(game, c, "build_time_mult"))
	game.state.provinces[prov_id].construction = {"building": building_id, "done": game.date + int(days), "days": int(days), "by": c.id}
	game.state["build_ver"] = int(game.state.get("build_ver", 0)) + 1
	game.emit("building.started", {"province": prov_id, "building": building_id, "by": c.id})
	return true


static func daily_construction(game: Game) -> void:
	for p in game.state.provinces.values():
		if p.construction == null or p.construction.done > game.date:
			continue
		if p.construction.get("district") != null:
			Districts.complete(game, p)
			continue
		var b: String = p.construction.building
		var by: Variant = p.construction.get("by")
		p.buildings.append(b)
		p.construction = null
		game.state["build_ver"] = int(game.state.get("build_ver", 0)) + 1
		game.stat_cache.clear()
		var t: Variant = game.state.titles.get(p.id)
		game.message(game.loc.t("msg.building_done", {"building": game.name_of("buildings", b), "place": game.name_of("provinces", p.id)}), "good", {"type": "province", "id": p.id}, [t.holder if t != null else null])
		game.emit("building.completed", {"province": p.id, "building": b, "by": by})
		if by != null and game.ch(str(by)) != null:
			game.on_action("on_building_completed", {"type": "character", "id": str(by)}, {"province": {"type": "province", "id": p.id}})


## Название того, что строится в графстве (постройка или район с уровнем).
static func construction_name(game: Game, cons: Dictionary) -> String:
	if cons.get("district") != null:
		return "%s %s" % [game.name_of("districts", str(cons.district)), Districts.roman(int(cons.get("level", 1)))]
	return game.name_of("buildings", str(cons.get("building", "")))


## [{province, def}] — что ИИ может начать строить сейчас (графства без стройки).
## Что можно построить в домене: [{province, def, cost}]. with_unaffordable —
## и то, на что пока не хватает золота (для копилки ИИ).
static func domain_build_options(game: Game, c: Dictionary, with_unaffordable := false) -> Array:
	var out := []
	for p in Titles.domain_counties(game, c):
		var st: Variant = game.state.provinces.get(p)
		if st == null or st.construction != null or st.occupant != null:
			continue
		for x in building_candidates(game, c, p):
			if x.blockers.is_empty() or (with_unaffordable and x.cost_only):
				out.append({"province": p, "def": x.def, "cost": x.cost})
	return out

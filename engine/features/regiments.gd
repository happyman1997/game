class_name Regiments
extends EngineFeature
## Профессиональные войска (men-at-arms). Правитель нанимает отряды разных
## типов за золото и платит за них жалованье; поднятая армия берёт отряды с
## собой. Каждый воин отряда стоит power ополченцев, типы контрят друг друга
## (пикинёры — конницу, конница — лучников…), местность усиливает или
## ослабляет отряды.
##
## Данные:
##   regiment_types: { icon, size, power, cost, upkeep, counters, terrain, can_recruit, ai_will_do, order }
##   defines.regiments: { cap_by_tier, raised_upkeep_mult, reinforce_rate, max_counter,
##                        start_regiments_by_tier, ai_gold_reserve }
## Состояние: c.regiments = [{id, type, size}], army.regiments — копии в армии.

const OWNER := "core/regiments"


func _init() -> void:
	id = "regiments"
	doc = "Профессиональные войска: найм, жалованье, контры и местность в бою"


static func types(game: Game) -> Array:
	return game.engine.sorted_content("regiment_types")


static func regs_of(c: Dictionary) -> Array:
	return c.regiments if c.get("regiments") != null else []


static func cap(game: Game, c: Dictionary) -> int:
	var by_tier: Array = game.def_val("regiments.cap_by_tier", [0, 2, 3, 4, 6])
	var pt := Titles.primary_tier(game, c)
	return maxi(0, floori((Data.num(by_tier[pt]) if pt < by_tier.size() else 0.0) + Stats.stat(game, c, "regiment_cap")))


static func cost(game: Game, c: Dictionary, def: Dictionary) -> Dictionary:
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
	var cd: Dictionary = def.get("cost") if def.get("cost") is Dictionary else {}
	return {
		"gold": roundf(Interp.eval_value(ctx, ctx.root, cd.get("gold", 0))),
		"prestige": roundf(Interp.eval_value(ctx, ctx.root, cd.get("prestige", 0))),
	}


static func _raised_ids(game: Game, owner_id: Variant = null) -> Dictionary:
	var out := {}
	for a in game.state.armies.values():
		if owner_id != null and a.owner != owner_id:
			continue
		for r in Data.as_array(a.get("regiments")):
			out[r.id] = true
	return out


static func upkeep(game: Game, c: Dictionary) -> float:
	var mult := game.def_num("regiments.raised_upkeep_mult", 2)
	var raised := _raised_ids(game, c.id)
	var total := 0.0
	for r in regs_of(c):
		var def: Variant = game.content.get_def("regiment_types", r.type)
		if def == null:
			continue
		total += Data.num(def.get("upkeep")) * (mult if raised.has(r.id) else 1.0)
	return total * maxf(0.0, 1.0 + Stats.stat(game, c, "army_upkeep_mult"))


static func is_type_shown(game: Game, c: Dictionary, def: Dictionary) -> bool:
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
	return Interp.eval_trigger(ctx, ctx.root, def.get("can_recruit"))


static func recruit_blockers(game: Game, c: Dictionary, def: Dictionary) -> Array:
	var out := []
	if c.titles.is_empty():
		out.append(game.loc.t("tr.is_ruler"))
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
	out.append_array(Interp.failed_triggers(ctx, ctx.root, def.get("can_recruit")))
	if regs_of(c).size() >= cap(game, c):
		out.append(game.loc.t("ui.regiment_cap_reached", {"n": cap(game, c)}))
	out.append_array(Economy.cost_blockers(game, c, cost(game, c, def)))
	return out


static func recruit(game: Game, c: Dictionary, type: String, free: bool = false) -> Variant:
	var def: Variant = game.content.get_def("regiment_types", type)
	if def == null:
		return null
	if not free and not recruit_blockers(game, c, def).is_empty():
		return null
	if not free:
		var cst := cost(game, c, def)
		c.gold -= cst.gold
		c.prestige -= cst.prestige
	var r := {"id": game.new_id("reg"), "type": type, "size": int(Data.num(def.get("size"), 100))}
	if c.get("regiments") == null:
		c["regiments"] = []
	c.regiments.append(r)
	game.emit("regiment.recruited", {"character": c, "regiment": r})
	game.notify("army")
	return r


static func disband(game: Game, c: Dictionary, reg_id: String) -> void:
	if c.get("regiments") == null:
		return
	c.regiments = c.regiments.filter(func(r): return r.id != reg_id)
	for a in game.state.armies.values():
		if a.owner != c.id or a.get("regiments") == null:
			continue
		for r in a.regiments:
			if r.id == reg_id:
				a.size = maxi(0, int(a.size) - int(r.size))
				a.max_size = maxi(int(a.size), int(a.max_size) - int(r.size))
				a.regiments = a.regiments.filter(func(x): return x.id != reg_id)
				break
	game.notify("army")


## Сила полка с учётом контр противника и местности (в «ополченцах»).
static func effective(game: Game, r: Dictionary, enemy_men: Dictionary, my_men_of_type: float, terrain: Variant) -> float:
	var def: Variant = game.content.get_def("regiment_types", r.type)
	if def == null:
		return float(r.size)
	var penalty := 0.0
	for type in enemy_men:
		var edef: Variant = game.content.get_def("regiment_types", type)
		var counters: Variant = edef.get("counters") if edef != null else null
		var cv := Data.num(counters.get(r.type)) if counters is Dictionary else 0.0
		if cv != 0.0:
			penalty += cv * minf(1.0, enemy_men[type] / maxf(1.0, my_men_of_type))
	penalty = minf(game.def_num("regiments.max_counter", 0.75), penalty)
	var tm: Variant = def.get("terrain")
	var t := 1.0 + (Data.num(tm.get(terrain)) if (terrain != null and tm is Dictionary) else 0.0)
	return float(r.size) * Data.num(def.get("power"), 1.0) * (1.0 - penalty) * maxf(0.1, t)


## Прибавка к силе армии от отрядов (сверх их численности).
static func army_bonus(game: Game, a: Dictionary, enemies: Array = [], location: Variant = null) -> float:
	var regs := Data.as_array(a.get("regiments"))
	if regs.is_empty():
		return 0.0
	var enemy_men := {}
	for e in enemies:
		for r in Data.as_array(e.get("regiments")):
			enemy_men[r.type] = float(enemy_men.get(r.type, 0.0)) + float(r.size)
	var mine := {}
	for r in regs:
		mine[r.type] = float(mine.get(r.type, 0.0)) + float(r.size)
	var pd: Variant = game.content.get_def("provinces", location if location != null else a.location)
	var terrain: Variant = pd.get("terrain") if pd != null else null
	var bonus := 0.0
	for r in regs:
		bonus += effective(game, r, enemy_men, mine.get(r.type, float(r.size)), terrain) - float(r.size)
	return bonus


## Сила отрядов, не поднятых в армию (для оценок ИИ).
static func idle_power(game: Game, c: Dictionary) -> float:
	var raised := _raised_ids(game, c.id)
	var total := 0.0
	for r in regs_of(c):
		if raised.has(r.id):
			continue
		var def: Variant = game.content.get_def("regiment_types", r.type)
		total += float(r.size) * (Data.num(def.get("power"), 1.0) if def != null else 1.0)
	return total


static func _ai_pick_type(game: Game, c: Dictionary, ignore_cost: bool = false) -> Variant:
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
	var opts := []
	for d in types(game):
		if ignore_cost:
			if not is_type_shown(game, c, d):
				continue
		elif not recruit_blockers(game, c, d).is_empty():
			continue
		var w := maxf(0.0, Interp.eval_value(ctx, ctx.root, d.ai_will_do) if d.get("ai_will_do") != null else 10.0)
		if w > 0.0:
			opts.append({"d": d, "w": w})
	var pick: Variant = game.rng.weighted(opts, func(o): return o.w)
	return pick.d if pick != null else null


## Помесячно для правителя (в его день): пополнение, роспуск лишних, найм ИИ.
static func monthly_char(game: Game, c: Dictionary) -> void:
	if c.titles.is_empty():
		return
	var rate := game.def_num("regiments.reinforce_rate", 0.1)
	var in_army: Dictionary = game.cached_daily("regiments:raised", func(): return _raised_ids(game))
	# пополнение
	for r in regs_of(c):
		if in_army.has(r.id):
			continue
		var def: Variant = game.content.get_def("regiment_types", r.type)
		var mx: int = int(Data.num(def.get("size"), r.size)) if def != null else int(r.size)
		if r.size < mx:
			r.size = mini(mx, roundi(r.size + mx * rate))
	# лишние отряды (например, после потери титулов) распускаются
	var cp := cap(game, c)
	while regs_of(c).size() > cp:
		var victim: Variant = null
		for x in regs_of(c):
			if not in_army.has(x.id):
				victim = x
				break
		if victim == null:
			victim = regs_of(c)[regs_of(c).size() - 1]
		disband(game, c, victim.id)
	if game.is_player(c.id) or c.get("prison") != null:
		return
	# ИИ: нанять или распустить
	if c.gold < game.def_num("regiments.ai_disband_below_gold", -30) and not regs_of(c).is_empty():
		for x in regs_of(c):
			if not in_army.has(x.id):
				disband(game, c, x.id)
				break
		return
	if regs_of(c).size() >= cp or not game.rng.chance(game.def_num("regiments.ai_recruit_chance", 0.15)):
		return
	var pick: Variant = _ai_pick_type(game, c)
	if pick == null:
		return
	var gold_cost: float = cost(game, c, pick).gold
	if c.gold < gold_cost + game.def_num("regiments.ai_gold_reserve", 60):
		return
	if Economy.monthly_income(game, c) < Data.num(pick.get("upkeep")) * 1.5:
		return
	recruit(game, c, pick.id)


static func monthly(game: Game) -> void:
	for c in game.rulers().duplicate():
		if c.death == null:
			monthly_char(game, c)


static func _sync_from_army(game: Game, a: Dictionary) -> void:
	var owner: Variant = game.ch(a.owner)
	if owner == null or owner.get("regiments") == null or a.get("regiments") == null:
		return
	for r in a.regiments:
		for own in owner.regiments:
			if own.id == r.id:
				own.size = maxi(0, roundi(r.size))


func install(engine: GameEngine) -> void:
	engine.systems.register("regiments", {"id": "regiments", "order": 52, "on_character_month": Regiments.monthly_char}, OWNER)
	# Жалованье — строка в доходах.
	engine.hooks.on("economy.income", func(p):
		var v := Regiments.upkeep(p.game, p.character)
		return {"label": p.game.loc.t("ui.regiment_upkeep"), "value": -v} if v != 0.0 else null
	, 0, OWNER)
	# Поднятая армия забирает отряды.
	engine.hooks.on("army.raised", func(p):
		var game: Game = p.game
		var army: Dictionary = p.army
		var owner: Variant = game.ch(army.owner)
		if owner == null:
			return
		var used := {}
		for a in game.state.armies.values():
			if a.id != army.id:
				for x in Data.as_array(a.get("regiments")):
					used[x.id] = true
		var regs := Regiments.regs_of(owner).filter(func(r): return r.size > 0 and not used.has(r.id))
		if regs.is_empty():
			return
		army.regiments = regs.map(func(r): return r.duplicate())
		var men := 0
		for r in regs:
			men += int(r.size)
		army.size = int(army.size) + men
		army.max_size = int(army.max_size) + men
	, 0, OWNER)
	# Распущенная армия возвращает отряды (с потерями).
	engine.hooks.on("army.disbanded", func(p): Regiments._sync_from_army(p.game, p.army), 0, OWNER)
	# После сражения (до отступления и гибели армий) переносим потери в отряды правителей.
	engine.hooks.on("battle", func(p):
		for a in p.game.state.armies.values():
			Regiments._sync_from_army(p.game, a)
	, -10, OWNER)
	# Сила в бою и в оценках ИИ.
	engine.hooks.on("army.power_bonus", func(p): return Regiments.army_bonus(p.game, p.army, p.get("enemies", []), p.get("location")), 0, OWNER)
	engine.hooks.on("military.strength_bonus", func(p): return Regiments.idle_power(p.game, p.character), 0, OWNER)
	# Отряды переходят к основному наследнику.
	engine.hooks.on("succession", func(p):
		var game: Game = p.game
		var h: Variant = game.ch(p.primary)
		var deceased: Dictionary = p.deceased
		if h == null or Regiments.regs_of(deceased).is_empty() or h.id == deceased.id:
			return
		h.regiments = Regiments.regs_of(h) + deceased.regiments
		deceased.regiments = []
	, 0, OWNER)
	# Стартовые отряды правителей.
	engine.hooks.on("game.setup", func(p):
		var game: Game = p.game
		var by_tier: Array = game.def_val("regiments.start_regiments_by_tier", [0, 0, 1, 2, 3])
		for c in game.rulers():
			var pt := Titles.primary_tier(game, c)
			var n := int(Data.num(by_tier[pt])) if pt < by_tier.size() else 0
			for i in n:
				var pick: Variant = Regiments._ai_pick_type(game, c, true)
				if pick != null:
					Regiments.recruit(game, c, pick.id, true)
	, 0, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	r.triggers.register("has_regiment", {"scopes": CH, "doc": "Есть отряд этого типа (или любой: yes)", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var regs: Array = Regiments.regs_of(c) if c != null else []
		if ScriptContext.is_yes(arg):
			return not regs.is_empty()
		return regs.any(func(x): return x.type == arg)
	}, OWNER)
	r.values.register("num_regiments", {"scopes": CH, "doc": "Число отрядов", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(Regiments.regs_of(c).size()) if c != null else 0.0
	}, OWNER)
	r.values.register("regiment_cap", {"scopes": CH, "doc": "Предел отрядов", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(Regiments.cap(ctx.game, c)) if c != null else 0.0
	}, OWNER)
	r.values.register("regiment_power", {"scopes": CH, "doc": "Сила отрядов, не поднятых в армию (в ополченцах)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Regiments.idle_power(ctx.game, c) if c != null else 0.0
	}, OWNER)
	r.effects.register("add_regiment", {"scopes": CH, "doc": "Получить отряд бесплатно (сверх предела)",
		"apply": func(ctx, s, arg):
			var c: Variant = ch.call(ctx, s)
			if c != null:
				Regiments.recruit(ctx.game, c, str(arg), true),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.add_regiment", {"value": ctx.game.name_of("regiment_types", str(arg))}),
	}, OWNER)
	engine.content_validators.register("regiments", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("regiment_types"):
			var w: String = "regiment_types/" + d.id
			if not (Data.num(d.get("size")) > 0 and Data.num(d.get("power")) > 0):
				v.issue(w + ": нужны size > 0 и power > 0")
			if d.get("counters") is Dictionary:
				for t in d.counters:
					v.ref("regiment_types", t, w + " counters")
			if d.get("terrain") is Dictionary:
				for t in d.terrain:
					v.ref("terrain", t, w + " terrain")
			v.trigger(d.get("can_recruit"), w + " can_recruit")
	, OWNER)

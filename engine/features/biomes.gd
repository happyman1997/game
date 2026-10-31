class_name Biomes
extends EngineFeature
## Местность: у земли есть состояние, и его меняют люди, природа и война.
## Дремучий лес, лес, вырубка, равнина, тучная и истощённая пашня, топь и
## осушенный луг, пустошь, пожарище… Нынешнее состояние лежит в state
## провинции (p.terrain; нет — исходное из данных карты, Game.terrain_of);
## от него зависят доход и набор (modifiers местности), рост, оборона,
## движение, полки и районы (по состоянию или его группе — terrain.group:
## дремучий лес — тоже лес), здоровье живущих в столице (capital_modifiers).
##
## Люди: владелец графства начинает работу (land_works) — свести лес,
## распахать вырубку, осушить топь, оставить пашню под пар… Работа идёт
## месяцами (быстрее при хорошем управлении и land_work_speed), стоит
## золота, пока идёт — даёт свои модификаторы провинции (during), а по
## окончании меняет землю и запускает on_complete — изнанку (лесной народ
## ропщет, у соседей ниже разливы, и все знают, чьих рук дело).
## Природа: раз в год каждая земля может сама перейти в другое состояние
## (terrain.drift: вырубка зарастает, брошенная пашня дичает, пашня устаёт,
## пожарище затягивается) — пока на ней не идёт работа.
## Война и события: эффект set_terrain (пожар, разорение).
## Летопись земли: p.land_log — [дата, было, стало, кто, причина]; так видно,
## кто сделал мир таким.
##
## Данные:
##   terrain.<id>: { group, color, height, defense, movement, development_growth,
##     modifiers: { tax_mult, levy_mult, … },   — графству в этом состоянии
##     capital_modifiers: { health, … },       — правителю, чья столица здесь
##     drift: [ { to, years, trigger } ] }     — природа (шанс 1/years в год; root — провинция)
##   land_works.<id>: { icon, from: [состояния], to, months, cost: { gold },
##     potential: { … },      — где можно (скоуп — провинция; root и scope:actor — кто начинает)
##     during: { … },         — модификаторы провинции, пока идёт работа
##     on_complete: [ … ],    — по окончании (скоуп — провинция; root и scope:actor — кто начинал)
##     ai_will_do: { … } }    — желание ИИ (root — правитель, scope:province)
##   defines.land: { history_size, speed_per_stewardship, min_speed_mult,
##     ai_frequency_months, ai_reserve_gold, ai_counties_per_work }
## Хуки: land.changed {province, from, to, by, cause}, land.work_started,
## land.work_done {province, work, by}; on_action on_land_changed (root —
## владелец графства, scope:province, scope:actor — кто изменил).

const OWNER := "core/biomes"


func _init() -> void:
	id = "biomes"
	doc = "Местность: живая земля — работы правителей, природа и война меняют её; летопись земли"


static func _p(game: Game, pid: String) -> Variant:
	return game.state.provinces.get(pid)


# ------------------------------------------------------------ состояние и летопись

static func history_of(game: Game, pid: String) -> Array:
	var p: Variant = _p(game, pid)
	return Data.as_array(p.get("land_log")) if p != null else []


## Изменить местность; в летопись — кто и почему. Возвращает, изменилась ли.
static func set_terrain(game: Game, pid: String, to: String, by: Variant = null, cause: String = "") -> bool:
	var p: Variant = _p(game, pid)
	if p == null or not game.content.has("terrain", to):
		return false
	var from := game.terrain_of(pid)
	if from == to:
		return false
	p["terrain"] = to
	var log: Array = Data.as_array(p.get("land_log")).duplicate()
	log.append([game.date, from, to, by, cause])
	var n := int(game.def_num("land.history_size", 12))
	p["land_log"] = log.slice(maxi(0, log.size() - n))
	game.state["land_ver"] = int(game.state.get("land_ver", 0)) + 1
	game.stat_cache.erase("prov:" + pid)
	var t: Variant = game.state.titles.get(pid)
	var holder: Variant = game.ch(t.holder) if t != null else null
	if holder != null:
		game.mark_chars_dirty([holder.id])
	game.emit("land.changed", {"province": pid, "from": from, "to": to, "by": by, "cause": cause})
	if holder != null:
		var scopes := {"province": {"type": "province", "id": pid}}
		if by != null and game.ch(by) != null:
			scopes["actor"] = {"type": "character", "id": by}
		game.on_action("on_land_changed", {"type": "character", "id": holder.id}, scopes)
		if game.is_player(holder.id) and (by == null or not game.is_player(by)):
			game.message(game.loc.t("msg.land_changed", {"place": game.scope_name({"type": "province", "id": pid}),
				"from": game.name_of("terrain", from), "to": game.name_of("terrain", to)}), "info", {"type": "province", "id": pid})
	return true


# ------------------------------------------------------------ работы

static func work_of(game: Game, pid: String) -> Variant:
	var p: Variant = _p(game, pid)
	return p.get("land_work") if p != null else null


## Работы, которые подходят к нынешнему состоянию земли.
static func works_here(game: Game, pid: String) -> Array:
	var t := game.terrain_of(pid)
	return game.content.all("land_works").filter(func(d): return Data.as_array(d.get("from")).has(t))


static func months_for(game: Game, c: Dictionary, d: Dictionary) -> int:
	var speed := Stats.skill(game, c, "stewardship") * game.def_num("land.speed_per_stewardship", 0.02) + Stats.stat(game, c, "land_work_speed")
	var mult := clampf(1.0 - speed, game.def_num("land.min_speed_mult", 0.4), 1.5)
	return maxi(3, roundi(Data.num(d.get("months"), 24) * mult))


static func cost_for(game: Game, c: Dictionary, d: Dictionary) -> float:
	var cost: Variant = d.get("cost")
	var gold := Data.num(cost.get("gold")) if cost is Dictionary else 0.0
	return roundf(gold * maxf(0.0, 1.0 + Stats.stat(game, c, "build_cost_mult")))


static func _ctx(game: Game, c: Dictionary, pid: String) -> ScriptContext:
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id}, {"province": {"type": "province", "id": pid}, "actor": {"type": "character", "id": c.id}})
	ctx.values["__src"] = "land_work"
	return ctx


## Почему c не может начать работу wid на этой земле (пусто — может).
static func blockers(game: Game, c: Dictionary, pid: String, wid: String) -> Array:
	var d: Variant = game.content.get_def("land_works", wid)
	var p: Variant = _p(game, pid)
	if d == null or p == null:
		return ["land.no_work"]
	var out := []
	var t: Variant = game.state.titles.get(pid)
	if t == null or t.holder != c.id:
		out.append("land.not_yours")
	if not Data.as_array(d.get("from")).has(game.terrain_of(pid)):
		out.append("land.wrong_terrain")
	if p.get("land_work") != null:
		out.append("land.busy")
	if p.get("occupant") != null or p.get("siege") != null:
		out.append("land.at_war")
	if d.get("potential") != null:
		var ctx := _ctx(game, c, pid)
		if not Interp.eval_trigger(ctx, {"type": "province", "id": pid}, d.potential):
			out.append("land.not_here")
	if float(c.gold) < cost_for(game, c, d):
		out.append("land.no_gold")
	return out


static func start(game: Game, c: Dictionary, pid: String, wid: String) -> bool:
	if not blockers(game, c, pid, wid).is_empty():
		return false
	var d: Dictionary = game.content.get_def("land_works", wid)
	var cost := cost_for(game, c, d)
	if cost > 0.0:
		Treasury.add(game, c, -cost, "land_works")
	var months := months_for(game, c, d)
	_p(game, pid)["land_work"] = {"id": wid, "by": c.id, "start": game.date, "until": game.date + months * 30, "months": months}
	game.stat_cache.erase("prov:" + pid)
	game.emit("land.work_started", {"province": pid, "work": wid, "by": c.id})
	return true


static func cancel(game: Game, pid: String) -> void:
	var p: Variant = _p(game, pid)
	if p == null or p.get("land_work") == null:
		return
	p.erase("land_work")
	game.stat_cache.erase("prov:" + pid)


## Доля сделанного, 0…1.
static func progress(game: Game, pid: String) -> float:
	var w: Variant = work_of(game, pid)
	if w == null:
		return 0.0
	return clampf(float(game.date - int(w.start)) / maxf(1.0, float(int(w.until) - int(w.start))), 0.0, 1.0)


static func months_left(game: Game, pid: String) -> int:
	var w: Variant = work_of(game, pid)
	return maxi(0, ceili((int(w.until) - game.date) / 30.0)) if w != null else 0


static func _finish(game: Game, pid: String) -> void:
	var p: Dictionary = _p(game, pid)
	var w: Dictionary = p.land_work
	p.erase("land_work")
	game.stat_cache.erase("prov:" + pid)
	var d: Variant = game.content.get_def("land_works", str(w.id))
	if d == null:
		return
	var by: Variant = game.ch(w.by)
	set_terrain(game, pid, str(d.to), w.by, str(w.id))
	if by != null and Chars.is_alive(by):
		var ctx := _ctx(game, by, pid)
		Interp.run_effect(ctx, {"type": "province", "id": pid}, d.get("on_complete"))
	game.emit("land.work_done", {"province": pid, "work": str(w.id), "by": by})
	var t: Variant = game.state.titles.get(pid)
	for who in [w.by, t.holder if t != null else null]:
		if who != null and game.is_player(who):
			game.message(game.loc.t("msg.land_work_done", {"place": game.scope_name({"type": "province", "id": pid}),
				"work": game.name_of("land_works", str(w.id)), "to": game.name_of("terrain", str(d.to))}), "good", {"type": "province", "id": pid})
			break


# ------------------------------------------------------------ время

## Ежемесячно: работы, дошедшие до срока, кончаются; двенадцатая часть
## земель проверяет, не берёт ли своё природа.
static func monthly(game: Game) -> void:
	var month := int(GameDate.parts(game.date).m)
	var i := 0
	for pid in game.state.provinces:
		var p: Dictionary = game.state.provinces[pid]
		var w: Variant = p.get("land_work")
		if w != null:
			if game.date >= int(w.until):
				_finish(game, pid)
		elif i % 12 == month - 1:
			_drift(game, pid)
		i += 1


static func _drift(game: Game, pid: String) -> void:
	var td: Variant = game.terrain_def(pid)
	if td == null or not (td.get("drift") is Array):
		return
	for rule in td.drift:
		if not (rule is Dictionary) or not game.content.has("terrain", str(rule.get("to", ""))):
			continue
		var ctx := ScriptContext.make(game, {"type": "province", "id": pid}, {"province": {"type": "province", "id": pid}})
		if rule.get("trigger") != null and not Interp.eval_trigger(ctx, ctx.root, rule.trigger):
			continue
		var years := Interp.eval_value(ctx, ctx.root, rule.get("years", 20))
		if years > 0.0 and game.rng.chance(1.0 / years):
			set_terrain(game, pid, str(rule.to), null, str(rule.get("cause", "nature")))
			return


## ИИ-правитель раз в ai_frequency_months думает, не взяться ли за землю.
static func monthly_char(game: Game, c: Dictionary) -> void:
	if c.titles.is_empty() or not game.ai_controls(c.id) or c.get("prison") != null:
		return
	var freq := maxi(1, int(game.def_num("land.ai_frequency_months", 12)))
	if (Treasury.month_index(game.date) + absi(hash(c.id))) % freq != 0:
		return
	var dom := Titles.domain_counties(game, c)
	if dom.is_empty():
		return
	var busy := 0
	for pid in dom:
		var w: Variant = work_of(game, pid)
		if w != null and w.by == c.id:
			busy += 1
	if busy >= maxi(1, dom.size() / maxi(1, int(game.def_num("land.ai_counties_per_work", 4)))):
		return
	var reserve := game.def_num("land.ai_reserve_gold", 100)
	var best: Variant = null
	var best_w := 0.0
	for pid in dom:
		for d in works_here(game, pid):
			if float(c.gold) - cost_for(game, c, d) < reserve or not blockers(game, c, pid, d.id).is_empty():
				continue
			var ctx := _ctx(game, c, pid)
			var w := Interp.eval_value(ctx, ctx.root, d.get("ai_will_do", 0))
			if w > best_w:
				best_w = w
				best = [pid, d.id]
	if best != null and game.rng.next() * 100.0 < best_w:
		start(game, c, best[0], best[1])


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("biomes", {"id": "biomes", "order": 18, "on_month": Biomes.monthly, "on_character_month": Biomes.monthly_char}, OWNER)
	# пока идёт работа — её модификаторы графству
	engine.province_modifier_providers.register("biomes", {"fn": func(game: Game, pid: String) -> Variant:
		var w: Variant = Biomes.work_of(game, pid)
		if w == null:
			return null
		var d: Variant = game.content.get_def("land_works", str(w.id))
		return d.get("during") if d != null else null
	}, OWNER)
	# столица в топи — лихорадка и прочее (capital_modifiers местности)
	engine.modifier_providers.register("biomes", {"fn": func(game: Game, c: Dictionary) -> Variant:
		if c.titles.is_empty():
			return null
		var cap: Variant = Titles.capital_of(game, c)
		if cap == null:
			return null
		var td: Variant = game.terrain_def(cap)
		return td.get("capital_modifiers") if td != null else null
	}, OWNER)
	engine.content_validators.register("land_works", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("land_works"):
			var w := "land_works/" + str(d.id)
			for t in Data.as_array(d.get("from")):
				v.ref("terrain", t, w + " from")
			v.ref("terrain", d.get("to"), w + " to")
			v.trigger(d.get("potential"), w + " potential")
			v.effect(d.get("on_complete"), w + " on_complete")
			v.value(d.get("ai_will_do"), w + " ai_will_do")
		for t in e.content.all("terrain"):
			if t.get("group") != null:
				v.ref("terrain", t.group, "terrain/%s group" % t.id)
			for rule in Data.as_array(t.get("drift")):
				if rule is Dictionary:
					v.ref("terrain", rule.get("to"), "terrain/%s drift" % t.id)
					v.trigger(rule.get("trigger"), "terrain/%s drift" % t.id)
	, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var PR := ["province"]
	r.triggers.register("has_land_work", {"scopes": PR, "doc": "На земле идёт работа: has_land_work: yes | <id работы>", "eval": func(ctx, s, arg):
		var w: Variant = Biomes.work_of(ctx.game, s.id)
		if arg is String and arg != "yes" and arg != "no":
			return w != null and str(w.id) == arg
		return (w != null) == ScriptContext.is_yes(arg)
	}, OWNER)
	r.triggers.register("has_holder", {"scopes": PR, "doc": "У графства есть владелец (нет — земля брошена): has_holder: yes", "eval": func(ctx, s, arg):
		var t: Variant = ctx.game.state.titles.get(s.id)
		return (t != null and t.holder != null) == ScriptContext.is_yes(arg)
	}, OWNER)
	r.values.register("land_work_months_left", {"scopes": PR, "doc": "Сколько месяцев осталось работе на земле", "get": func(ctx, s, _a):
		return float(Biomes.months_left(ctx.game, s.id))
	}, OWNER)
	r.effects.register("set_terrain", {"scopes": PR, "doc": "Изменить местность: set_terrain: burnt или { to, cause } (в летопись — root, если это персонаж)",
		"apply": func(ctx, s, arg):
			var to := str(arg.get("to", "")) if arg is Dictionary else str(arg)
			var cause := str(arg.get("cause", "event")) if arg is Dictionary else "event"
			var by: Variant = ctx.root.id if ctx.root.get("type") == "character" else null
			Biomes.set_terrain(ctx.game, s.id, to, by, cause),
		"describe": func(ctx, s, arg):
			var to := str(arg.get("to", "")) if arg is Dictionary else str(arg)
			return ctx.game.loc.t("fx.set_terrain", {"place": ctx.game.scope_name(s), "to": ctx.game.name_of("terrain", to)}),
	}, OWNER)
	r.effects.register("start_land_work", {"scopes": PR, "doc": "Начать работу на земле от имени root (он платит): start_land_work: <id>",
		"apply": func(ctx, s, arg):
			var c: Variant = ctx.game.ch(ctx.root.id) if ctx.root.get("type") == "character" else null
			if c != null:
				Biomes.start(ctx.game, c, s.id, str(arg)),
		"describe": func(ctx, s, arg):
			return ctx.game.loc.t("fx.start_land_work", {"place": ctx.game.scope_name(s), "work": ctx.game.name_of("land_works", str(arg))}),
	}, OWNER)
	r.effects.register("end_land_work", {"scopes": PR, "doc": "Прервать работу на земле (без возврата затрат)",
		"apply": func(ctx, s, _a): Biomes.cancel(ctx.game, s.id),
		"describe": func(ctx, s, _a): return ctx.game.loc.t("fx.end_land_work", {"place": ctx.game.scope_name(s)}),
	}, OWNER)

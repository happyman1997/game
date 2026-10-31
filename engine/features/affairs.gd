class_name Affairs
extends EngineFeature
## Дела: всё, что затеяли люди в мире, — поручения, работы на земле и
## дорогах, стройка, интриги — одним списком: кто, что, где, сколько
## сделано. Свои дела видно всегда; чужие — если они в своей державе или в
## соседних с ней графствах, если посол или путник идёт к тебе или твоими
## землями. Чужие интриги не видно.
##
## В видимое чужое дело можно вмешаться (interventions в данных): помочь —
## открыто, хозяин дела запомнит добром; помешать — тайно, проверкой; от
## исхода зависит, раскроют ли (discovery, % по исходу) — раскрыли, хозяин
## запомнит (defines.affairs.discovered_opinion и on_discovered). В одно
## чужое дело каждый вмешивается один раз. ИИ вмешивается так же — по
## ai_will_do (root — он, scope:actor — хозяин дела).
##
## Данные:
##   interventions.<id>: {
##     affair: [land_work, road_work, construction, mission],  — к каким делам
##     works: [ ... ]        — только к этим (работа, поручение, район или постройка)
##     side: help | hinder
##     icon, cost: { gold }
##     potential: { ... }    — можно ли (root — кто вмешивается, scope:actor,
##                             scope:province — где дело, scope:agent — посланец;
##                             scope:affair_to_me, scope:affair_in_realm — 1 или 0)
##     effect: [ ... ]       — помощь (без проверки)
##     check: { ... } + success / partial / failure — вред (проверка)
##     discovery: { success, partial, failure }  — шанс раскрытия, %
##     on_discovered: [ ... ] — если раскрыли (root — кто вмешался, scope:actor)
##     ai_will_do: { ... } }
##   Эффекты над делом (только в вмешательстве): affair_hasten: 0.3 (доля
##   оставшегося срока долой), affair_delay: 0.4 (доля всего срока сверху),
##   affair_cancel: yes, affair_aid: 15 (поручению — к проверке по
##   возвращении), affair_escort: yes (путнику шайки не страшны),
##   affair_ambush: { foe } (посланец бьётся с наёмниками; проиграл — минус
##   к проверке).
##   defines.affairs: { ai_frequency_months, ai_reserve_gold, help_opinion,
##     discovered_opinion }
## Хук affair.meddled {who, affair, intervention, side, result, discovered}.

const OWNER := "core/affairs"


func _init() -> void:
	id = "affairs"
	doc = "Дела: свои и чужие дела в одном окне; вмешательство — помочь или тайно помешать"


# ------------------------------------------------------------ дела

## Все дела мира: [{key, kind, sub, actor, place, target, agent, progress, days}].
static func all(game: Game) -> Array:
	var out := []
	for pid in game.state.provinces:
		var p: Dictionary = game.state.provinces[pid]
		var w: Variant = p.get("land_work")
		if w is Dictionary:
			var d: Variant = game.content.get_def("land_works", str(w.id))
			out.append({"key": "work:" + pid, "kind": "road_work" if Biomes.is_road_work(d) else "land_work", "sub": str(w.id),
				"actor": w.get("by"), "place": pid, "progress": Biomes.progress(game, pid), "days": maxi(0, int(w.until) - game.date)})
		var cons: Variant = p.get("construction")
		if cons is Dictionary:
			var days := maxf(1.0, Data.num(cons.get("days"), 365))
			var sub := str(cons.get("building")) if cons.get("building") != null else str(cons.get("district", ""))
			out.append({"key": "build:" + pid, "kind": "construction", "sub": sub, "level": int(cons.get("level", 0)),
				"district": cons.get("district") != null and cons.get("building") == null,
				"actor": cons.get("by"), "place": pid, "progress": clampf(1.0 - (float(cons.done) - game.date) / days, 0.0, 1.0),
				"days": maxi(0, int(cons.done) - game.date)})
	for c in game.living():
		var m: Variant = c.vars.get("mission")
		if not (m is Dictionary):
			continue
		var place: Variant = null
		var t: Variant = Travel.travelers(game).get(m.get("trip")) if m.get("trip") != null and game.engine.has_feature("travel") else null
		if t != null:
			place = game.land().province_at_cell(Travel.cell_of(t))
		elif m.get("target") is Dictionary and m.target.get("type") == "province":
			place = m.target.id
		var span := maxf(1.0, float(int(m.until) - int(m.start)))
		out.append({"key": "mission:" + c.id, "kind": "mission", "sub": str(m.id), "actor": m.get("patron"), "agent": c.id,
			"target": m.get("target"), "place": place, "progress": clampf((game.date - int(m.start)) / span, 0.0, 1.0),
			"days": maxi(0, int(m.until) - game.date)})
	for s in game.state.schemes.values():
		out.append({"key": "scheme:" + str(s.id), "kind": "scheme", "sub": str(s.type), "actor": s.owner, "target": {"type": "character", "id": s.target},
			"place": null, "progress": clampf(float(s.progress) / 100.0, 0.0, 1.0), "days": -1, "discovered": s.get("discovered", false)})
	return out


## Дела, которые видит c: {mine, others}.
static func visible_to(game: Game, c: Dictionary) -> Dictionary:
	var realm := {}
	for pid in Titles.realm_counties(game, c):
		realm[pid] = true
	var near := realm.duplicate()
	for pid in realm:
		for n in game.engine.neighbors(pid):
			near[n] = true
	var mine := []
	var others := []
	for a in all(game):
		if a.actor == c.id:
			mine.append(a)
			continue
		if a.kind == "scheme":
			continue
		var to_me: bool = a.get("target") is Dictionary and a.target.get("type") == "character" and a.target.id == c.id
		if to_me or (a.place != null and near.has(a.place)):
			a["to_me"] = to_me
			a["in_realm"] = a.place != null and realm.has(a.place)
			others.append(a)
	return {"mine": mine, "others": others}


## Дело по ключу (или null).
static func find(game: Game, key: String) -> Variant:
	for a in all(game):
		if a.key == key:
			return a
	return null


## Запись дела в состоянии (где помечать вмешательства).
static func _record(game: Game, a: Dictionary) -> Variant:
	match str(a.kind):
		"land_work", "road_work":
			return game.state.provinces[a.place].get("land_work")
		"construction":
			return game.state.provinces[a.place].get("construction")
		"mission":
			var ag: Variant = game.ch(a.agent)
			return ag.vars.get("mission") if ag != null else null
	return null


# ------------------------------------------------------------ вмешательство

static func _ctx(game: Game, c: Dictionary, a: Dictionary, iid: String) -> ScriptContext:
	var scopes := {}
	if a.get("actor") != null:
		scopes["actor"] = {"type": "character", "id": a.actor}
	if a.get("place") != null:
		scopes["province"] = {"type": "province", "id": a.place}
	if a.get("agent") != null:
		scopes["agent"] = {"type": "character", "id": a.agent}
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id}, scopes)
	ctx.values["__affair"] = a.key
	ctx.values["__src"] = "intervention:" + iid
	# для условий: дело касается меня (посол ко мне) и идёт в моей державе
	var to_me: bool = a.get("target") is Dictionary and a.target.get("type") == "character" and a.target.id == c.id
	ctx.values["affair_to_me"] = 1.0 if to_me else 0.0
	ctx.values["affair_in_realm"] = 1.0 if a.get("place") != null and Titles.realm_counties(game, c).has(a.place) else 0.0
	return ctx


static func cost_for(game: Game, c: Dictionary, d: Dictionary) -> float:
	var cost: Variant = d.get("cost")
	return Data.num(cost.get("gold")) if cost is Dictionary else 0.0


## Вмешательства, которые подходят к делу (по виду и работе).
static func for_affair(game: Game, a: Dictionary) -> Array:
	return game.content.all("interventions").filter(func(d):
		if not Data.as_array(d.get("affair")).has(a.kind):
			return false
		var works := Data.as_array(d.get("works"))
		return works.is_empty() or works.has(a.sub))


## Почему c не может вмешаться (пусто — может).
static func blockers(game: Game, c: Dictionary, a: Dictionary, d: Dictionary) -> Array:
	var out := []
	if a.get("actor") == c.id:
		out.append("affairs.own")
	var rec: Variant = _record(game, a)
	if rec == null:
		return ["affairs.gone"]
	if rec.get("meddled") is Dictionary and rec.meddled.has(c.id):
		out.append("affairs.already")
	if float(c.gold) < cost_for(game, c, d):
		out.append("affairs.no_gold")
	if d.get("potential") != null:
		var ctx := _ctx(game, c, a, str(d.id))
		if not Interp.eval_trigger(ctx, ctx.root, d.potential):
			out.append("affairs.not_now")
	return out


## Вмешаться: заплатить, помочь или попробовать помешать. Возвращает исход
## ("help" | success | partial | failure | "").
static func meddle(game: Game, c: Dictionary, key: String, iid: String) -> String:
	var a: Variant = find(game, key)
	var d: Variant = game.content.get_def("interventions", iid)
	if a == null or d == null or not blockers(game, c, a, d).is_empty():
		return ""
	var rec: Dictionary = _record(game, a)
	if not (rec.get("meddled") is Dictionary):
		rec["meddled"] = {}
	rec.meddled[c.id] = true
	var cost := cost_for(game, c, d)
	if cost > 0.0:
		Treasury.add(game, c, -cost, "intrigue" if str(d.get("side")) == "hinder" else "gifts")
	var ctx := _ctx(game, c, a, iid)
	var actor: Variant = game.ch(a.get("actor"))
	var result := "help"
	var discovered := false
	if str(d.get("side", "help")) == "help":
		Interp.run_effect(ctx, ctx.root, d.get("effect"))
		if actor != null and Chars.is_alive(actor):
			Opinion.add_opinion(game, actor, c, "helped_my_affairs", game.def_num("affairs.help_opinion", 15))
			if game.is_player(actor.id):
				game.message(game.loc.t("msg.affair_helped", {"who": game.scope_name({"type": "character", "id": c.id}),
					"what": game.name_of("interventions", iid), "affair": title_of(game, a)}), "good", {"type": "character", "id": c.id})
	else:
		var spec: Dictionary = (d.get("check") if d.get("check") is Dictionary else {}).duplicate()
		for k in ["success", "partial", "failure"]:
			if d.get(k) != null:
				spec[k] = d[k]
		spec["name"] = "interventions." + iid
		result = Checks.run(ctx, ctx.root, spec)
		var disc: Variant = d.get("discovery")
		var chance := Data.num(disc.get(result), 30) if disc is Dictionary else 30.0
		discovered = game.rng.chance(chance / 100.0)
		if actor != null and Chars.is_alive(actor):
			if discovered:
				Opinion.add_opinion(game, actor, c, "meddled_in_my_affairs", game.def_num("affairs.discovered_opinion", -30))
				var dctx := _ctx(game, c, a, iid)
				Interp.run_effect(dctx, dctx.root, d.get("on_discovered"))
				if game.is_player(actor.id):
					game.message(game.loc.t("msg.affair_exposed", {"who": game.scope_name({"type": "character", "id": c.id}),
						"what": game.name_of("interventions", iid), "affair": title_of(game, a)}), "bad", {"type": "character", "id": c.id})
				if game.is_player(c.id):
					game.message(game.loc.t("msg.affair_caught", {"who": game.scope_name({"type": "character", "id": actor.id}),
						"what": game.name_of("interventions", iid)}), "bad", {"type": "character", "id": actor.id})
			elif result != "failure" and game.is_player(actor.id):
				game.message(game.loc.t("msg.affair_harmed", {"affair": title_of(game, a)}), "bad",
					{"type": "province", "id": a.place} if a.get("place") != null else null)
	game.emit("affair.meddled", {"who": c.id, "affair": a, "intervention": iid, "side": str(d.get("side", "help")),
		"result": result, "discovered": discovered})
	return result


## Название дела: «Свести лес — Суссекс», «Посольство — Сивард».
static func title_of(game: Game, a: Dictionary) -> String:
	var what := ""
	match str(a.kind):
		"land_work", "road_work":
			what = game.name_of("land_works", a.sub)
		"construction":
			what = game.name_of("districts", a.sub) if a.get("district", false) else game.name_of("buildings", a.sub)
		"mission":
			what = game.name_of("missions", a.sub)
		"scheme":
			what = game.name_of("schemes", a.sub)
	var where := ""
	if a.kind == "mission" and a.get("agent") != null:
		where = game.scope_name({"type": "character", "id": a.agent})
	elif a.get("place") != null:
		where = game.scope_name({"type": "province", "id": a.place})
	elif a.get("target") is Dictionary:
		where = game.scope_name(a.target)
	return what + (" — " + where if where != "" else "")


# ------------------------------------------------------------ над делом

static func _affair_of(ctx: ScriptContext) -> Variant:
	var key: Variant = ctx.values.get("__affair")
	return find(ctx.game, str(key)) if key != null else null


static func hasten(game: Game, a: Dictionary, share: float) -> void:
	var rec: Variant = _record(game, a)
	if rec == null:
		return
	match str(a.kind):
		"land_work", "road_work":
			var left := maxi(0, int(rec.until) - game.date)
			rec.until = int(rec.until) - roundi(left * share)
		"construction":
			var left := maxi(0, int(rec.done) - game.date)
			rec.done = int(rec.done) - roundi(left * share)
		"mission":
			var t: Variant = Travel.travelers(game).get(rec.get("trip")) if rec.get("trip") != null else null
			if t != null and t.phase == "stay":
				t.stay_until = int(t.stay_until) - roundi(maxi(0, int(t.stay_until) - game.date) * share)
			else:
				rec.until = int(rec.until) - roundi(maxi(0, int(rec.until) - game.date) * share)


static func delay(game: Game, a: Dictionary, share: float) -> void:
	var rec: Variant = _record(game, a)
	if rec == null:
		return
	match str(a.kind):
		"land_work", "road_work":
			rec.until = int(rec.until) + roundi((int(rec.until) - int(rec.start)) * share)
		"construction":
			rec.done = int(rec.done) + roundi(Data.num(rec.get("days"), 365) * share)
		"mission":
			var days := roundi(maxf(30.0, float(int(rec.until) - int(rec.start))) * share)
			rec.until = int(rec.until) + days
			var t: Variant = Travel.travelers(game).get(rec.get("trip")) if rec.get("trip") != null else null
			if t != null:
				if t.phase == "stay":
					t.stay_until = int(t.stay_until) + days
				else:
					t["wait_until"] = game.date + days


static func cancel(game: Game, a: Dictionary) -> void:
	match str(a.kind):
		"land_work", "road_work":
			Biomes.cancel(game, a.place)
		"construction":
			game.state.provinces[a.place].construction = null
			game.state["build_ver"] = int(game.state.get("build_ver", 0)) + 1
		"mission":
			var ag: Variant = game.ch(a.agent)
			if ag != null:
				Missions.finish(game, ag, "recalled")


# ------------------------------------------------------------ ИИ

## ИИ-правитель раз в ai_frequency_months смотрит на чужие дела рядом.
static func monthly_char(game: Game, c: Dictionary) -> void:
	if c.titles.is_empty() or not game.ai_controls(c.id) or c.get("prison") != null:
		return
	var freq := maxi(1, int(game.def_num("affairs.ai_frequency_months", 6)))
	if (Treasury.month_index(game.date) + absi(hash(c.id + "affairs"))) % freq != 0:
		return
	var reserve := game.def_num("affairs.ai_reserve_gold", 60)
	var best: Variant = null
	var best_w := 0.0
	for a in visible_to(game, c).others:
		for d in for_affair(game, a):
			if float(c.gold) - cost_for(game, c, d) < reserve or not blockers(game, c, a, d).is_empty():
				continue
			var ctx := _ctx(game, c, a, str(d.id))
			var w := Interp.eval_value(ctx, ctx.root, d.get("ai_will_do", 0))
			if w > best_w:
				best_w = w
				best = [a.key, str(d.id)]
	if best != null and game.rng.next() * 100.0 < best_w:
		meddle(game, c, best[0], best[1])


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("affairs", {"id": "affairs", "order": 19, "on_character_month": Affairs.monthly_char}, OWNER)
	engine.content_validators.register("interventions", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("interventions"):
			var w := "interventions/" + str(d.id)
			for k in Data.as_array(d.get("affair")):
				if not (str(k) in ["land_work", "road_work", "construction", "mission"]):
					v.issue("%s: affair — land_work, road_work, construction или mission" % w)
			if not (str(d.get("side", "help")) in ["help", "hinder"]):
				v.issue("%s: side — help или hinder" % w)
			v.trigger(d.get("potential"), w + " potential")
			v.effect(d.get("effect"), w + " effect")
			for k in ["success", "partial", "failure"]:
				v.effect(d.get(k), "%s %s" % [w, k])
			v.effect(d.get("on_discovered"), w + " on_discovered")
			v.value(d.get("ai_will_do"), w + " ai_will_do")
	, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	r.effects.register("affair_hasten", {"doc": "В вмешательстве: дело идёт быстрее — affair_hasten: 0.3 (доля оставшегося срока долой)",
		"apply": func(ctx, _s, arg):
			var a: Variant = Affairs._affair_of(ctx)
			if a != null:
				Affairs.hasten(ctx.game, a, clampf(Data.num(arg, 0.3), 0.0, 1.0)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.affair_hasten", {"n": roundi(Data.num(arg, 0.3) * 100.0)}),
	}, OWNER)
	r.effects.register("affair_delay", {"doc": "В вмешательстве: дело затянется — affair_delay: 0.4 (доля всего срока сверху)",
		"apply": func(ctx, _s, arg):
			var a: Variant = Affairs._affair_of(ctx)
			if a != null:
				Affairs.delay(ctx.game, a, maxf(0.0, Data.num(arg, 0.4))),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.affair_delay", {"n": roundi(Data.num(arg, 0.4) * 100.0)}),
	}, OWNER)
	r.effects.register("affair_cancel", {"doc": "В вмешательстве: дело сорвано — affair_cancel: yes",
		"apply": func(ctx, _s, _a):
			var a: Variant = Affairs._affair_of(ctx)
			if a != null:
				Affairs.cancel(ctx.game, a),
		"describe": func(ctx, _s, _a): return ctx.game.loc.t("fx.affair_cancel"),
	}, OWNER)
	r.effects.register("affair_aid", {"doc": "В вмешательстве: поручению — к проверке по возвращении: affair_aid: 15 (минус — вред)",
		"apply": func(ctx, _s, arg):
			var a: Variant = Affairs._affair_of(ctx)
			var rec: Variant = Affairs._record(ctx.game, a) if a != null else null
			if rec != null and a.kind == "mission":
				rec["aid"] = Data.num(rec.get("aid")) + Data.num(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.affair_aid", {"n": K_signed(Data.num(arg))}),
	}, OWNER)
	r.effects.register("affair_escort", {"doc": "В вмешательстве: путнику дать охрану — шайки ему не страшны: affair_escort: yes",
		"apply": func(ctx, _s, _a):
			var a: Variant = Affairs._affair_of(ctx)
			var rec: Variant = Affairs._record(ctx.game, a) if a != null else null
			if rec != null and rec.get("trip") != null:
				var t: Variant = Travel.travelers(ctx.game).get(rec.trip)
				if t != null:
					t["escort"] = true,
		"describe": func(ctx, _s, _a): return ctx.game.loc.t("fx.affair_escort"),
	}, OWNER)
	r.effects.register("affair_ambush", {"doc": "В вмешательстве: засада на посланца — affair_ambush: { foe: hedge_knight, aid: -30 } (проиграл схватку — минус к проверке)",
		"apply": func(ctx, _s, arg):
			var a: Variant = Affairs._affair_of(ctx)
			var ag: Variant = ctx.game.ch(a.agent) if a != null and a.get("agent") != null else null
			if ag == null:
				return
			var foe := str(arg.get("foe", "hedge_knight")) if arg is Dictionary else "hedge_knight"
			var w := Duels.duel(ctx.game, ag, null, {"foe": foe, "kind": "mortal"})
			if (w.is_empty() or w.id != ag.id) and Chars.is_alive(ag):
				var rec: Variant = Affairs._record(ctx.game, a)
				if rec != null:
					rec["aid"] = Data.num(rec.get("aid")) + (Data.num(arg.get("aid"), -30) if arg is Dictionary else -30.0),
		"describe": func(ctx, _s, _a): return ctx.game.loc.t("fx.affair_ambush"),
	}, OWNER)


static func K_signed(n: float) -> String:
	return ("+%d" % roundi(n)) if n >= 0 else str(roundi(n))

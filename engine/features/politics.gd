class_name Politics
extends EngineFeature
## Политика двора: у каждого вассала свои условия службы (привилегии или
## тяжкие повинности), самые сильные вассалы ждут места в совете, жестокий
## правитель внушает страх, а вассалы приходят с прошениями и тяжбами.
##
## Данные:
##   vassal_obligations: { <id>: { level, icon, default, tax, levy, opinion } }
##     tax/levy — доля к взносу вассала (−0.5 — вдвое меньше), opinion — его мнение
##   defines.politics: { powerful_vassals_by_tier, powerful_seat_opinion,
##     powerful_snub_opinion, council_seat_bonus, dread_max, dread_decay,
##     dread_decay_compassionate, intimidated_per_dread, defiant_per_dread,
##     defiant_traits, respect_from, respect_per_point, respect_max, petition_chance_ai,
##     petition_chance_player, discord_base_chance }
##   Дерзкие вассалы (defiant_traits) страха не знают, но уважают доблестного
##   сюзерена; dread_gain_mult правителя (доблесть) ускоряет рост страха.
##   on_actions.on_vassal_petition — события-прошения (root — сюзерен)
## Состояние: вассал — c.obligation = {liege, id} (с другим сюзереном
## действуют обычные условия); правитель — c.vars.dread.

const OWNER := "core/politics"


func _init() -> void:
	id = "politics"
	doc = "Политика двора: условия службы вассалов, влиятельные вассалы и совет, страх, прошения"


# ------------------------------------------------------------ условия службы

static func obligations(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("politics:obligations")
	if hit == null:
		hit = game.content.all("vassal_obligations").duplicate()
		Data.sort_by(hit, func(x): return Data.num(x.get("level")))
		game.engine.cache["politics:obligations"] = hit
	return hit


static func default_obligation(game: Game) -> Variant:
	for o in obligations(game):
		if o.get("default", false):
			return o
	for o in obligations(game):
		if Data.num(o.get("level")) == 0.0:
			return o
	return null


## Условия службы вассала при нынешнем сюзерене.
static func obligation_of(game: Game, v: Dictionary) -> Variant:
	var o: Variant = v.get("obligation")
	if o is Dictionary and o.get("liege") == v.liege and v.liege != null:
		var d: Variant = game.content.get_def("vassal_obligations", str(o.id))
		if d != null:
			return d
	return default_obligation(game)


static func set_obligation(game: Game, v: Dictionary, ob_id: String) -> void:
	if not game.content.has("vassal_obligations", ob_id) or v.liege == null:
		return
	v["obligation"] = {"liege": v.liege, "id": ob_id}
	game.stat_cache.erase(v.id)
	game.stat_cache.erase("op:%s>%s" % [v.id, v.liege])
	game.day_cache.erase("rlevy:" + str(v.liege))
	game.emit("politics.obligation_changed", {"vassal": v, "obligation": ob_id})


# ------------------------------------------------------------ влиятельные вассалы

## Самые сильные вассалы правителя (больше всего графств в их державах,
## при равенстве — выше ранг) — ждут места в совете. Графства, а не ополчение:
## мнение о сюзерене спрашивают постоянно, а размер державы уже в кэше.
static func powerful_vassals(game: Game, liege: Dictionary) -> Array:
	return game.cached_monthly("politics:powerful:" + liege.id, func():
		var by_tier: Array = game.def_val("politics.powerful_vassals_by_tier", [0, 0, 2, 3, 4])
		var pt := Titles.primary_tier(game, liege)
		var n := int(Data.num(by_tier[pt])) if pt < by_tier.size() else 0
		if n <= 0:
			return []
		var weight := {}
		for v in game.vassals_of(liege.id):
			if not v.titles.is_empty():
				weight[v.id] = Titles.realm_counties(game, v).size() * 10 + Titles.primary_tier(game, v)
		var ids := weight.keys()
		Data.sort_by(ids, func(id): return weight[id], true)
		return ids.slice(0, n))


static func is_powerful(game: Game, v: Dictionary) -> bool:
	if v.liege == null or v.titles.is_empty():
		return false
	var l: Variant = game.ch(v.liege)
	return l != null and powerful_vassals(game, l).has(v.id)


static func is_seated(game: Game, liege: Dictionary, v: Dictionary) -> bool:
	if liege.get("council") == null:
		return false
	for pos in liege.council:
		if liege.council[pos].get("holder") == v.id:
			return true
	return false


## Влиятельные вассалы, которым не нашлось места в совете.
static func snubbed(game: Game, liege: Dictionary) -> Array:
	if not game.engine.has_feature("council"):
		return []
	var out := []
	for id in powerful_vassals(game, liege):
		var v: Variant = game.ch(id)
		if v != null and not is_seated(game, liege, v):
			out.append(v)
	return out


## Посадить вассала в совет: на должность, где его навык лучше всего
## (прежний советник уходит с обидой).
static func seat_in_council(game: Game, liege: Dictionary, v: Dictionary) -> bool:
	if not game.engine.has_feature("council") or is_seated(game, liege, v):
		return false
	var best: Variant = null
	var best_sk := -1.0
	for pos in Council.positions(game):
		if not Council.is_position_shown(game, liege, pos) or not Council.can_hold_seat(game, liege, v, pos.id):
			continue
		var sk := Stats.skill(game, v, str(pos.get("skill")))
		if sk > best_sk:
			best_sk = sk
			best = pos.id
	return best != null and Council.appoint(game, liege, best, v.id)


# ------------------------------------------------------------ страх

static func dread(c: Dictionary) -> float:
	return Data.num(c.vars.get("dread"))


static func add_dread(game: Game, c: Dictionary, v: float) -> void:
	# dread_gain_mult — устрашение (доблесть): страх перед силачом копится быстрее
	if v > 0.0:
		v *= maxf(0.0, 1.0 + Stats.stat(game, c, "dread_gain_mult"))
	var before := dread(c)
	c.vars["dread"] = clampf(before + v, 0.0, game.def_num("politics.dread_max", 100))
	if dread(c) <= 0.0:
		c.vars.erase("dread")
	# мнение подданных о правителе изменилось
	for x in game.vassals_of(c.id) + game.courtiers_of(c.id):
		game.stat_cache.erase("op:%s>%s" % [x.id, c.id])


## Не склоняются перед страхом (храбрые, гневливые) — а ненавидят тирана.
static func is_defiant(game: Game, c: Dictionary) -> bool:
	for t in game.def_val("politics.defiant_traits", ["brave", "wrathful"]):
		if c.traits.has(t):
			return true
	return false


## Насколько персонаж боится своего сюзерена: его страх, если сам не из дерзких.
static func fear_of_liege(game: Game, c: Dictionary) -> float:
	if c.liege == null:
		return 0.0
	var l: Variant = game.ch(c.liege)
	if l == null or not l.vars.has("dread") or is_defiant(game, c):
		return 0.0
	return dread(l)


# ------------------------------------------------------------ интриги и тяжбы

## Посеять раздор: цель и её ближайший союзник среди вассалов становятся
## соперниками; соперник покидает фракцию, которую возглавляет другой.
## Шанс — от интриги правителя и его тайного советника против интриги цели.
static func sow_discord(game: Game, actor: Dictionary, target: Dictionary) -> bool:
	var ally: Variant = null
	var best := -1000
	for x in game.vassals_of(actor.id):
		if x.id == target.id or x.death != null:
			continue
		var op := Opinion.opinion(game, x, target)
		if op > best:
			best = op
			ally = x
	if ally == null:
		return false
	var spy := 0.0
	var seat: Variant = Council.seat_of(actor, "spymaster") if game.engine.has_feature("council") else null
	var sm: Variant = game.ch(seat.get("holder")) if seat != null else null
	if sm != null:
		spy = Stats.skill(game, sm, "intrigue")
	var chance := game.def_num("politics.discord_base_chance", 35) + (Stats.skill(game, actor, "intrigue") + spy) * 2.0 - Stats.skill(game, target, "intrigue") * 2.0 + Stats.stat(game, actor, "discord_chance")
	chance = clampf(chance, 10.0, 90.0)
	if game.rng.next() * 100.0 >= chance:
		if game.content.has("opinion_modifiers", "caught_sowing_discord"):
			Opinion.add_opinion(game, target, actor, "caught_sowing_discord")
		if game.is_player(actor.id):
			game.message(game.loc.t("msg.discord_failed", {"who": game.scope_name({"type": "character", "id": target.id})}), "bad", {"type": "character", "id": target.id})
		return false
	Opinion.add_opinion(game, target, ally, "rival")
	Opinion.add_opinion(game, ally, target, "rival")
	if game.engine.has_feature("factions"):
		var ft: Variant = Factions.faction_of(game, target)
		var fa: Variant = Factions.faction_of(game, ally)
		if ft != null and fa != null and ft.id == fa.id:
			# в одной фракции соперникам тесно: уходит тот, кто не ведёт её
			Factions.leave(game, ally if ft.leader == target.id else target)
	if game.is_player(actor.id):
		game.message(game.loc.t("msg.discord_sown", {"a": game.scope_name({"type": "character", "id": target.id}), "b": game.scope_name({"type": "character", "id": ally.id})}), "good", {"type": "character", "id": target.id})
	game.emit("politics.discord", {"actor": actor, "target": target, "ally": ally})
	return true


## Пожаловать просителю самое бедное графство домена (не столицу).
static func grant_minor_county(game: Game, liege: Dictionary, to: Dictionary) -> bool:
	var cap: Variant = liege.capital
	var pool := Titles.domain_counties(game, liege).filter(func(p): return p != cap and liege.titles.has(p))
	if pool.is_empty():
		return false
	Data.sort_by(pool, func(p): return Data.num(game.state.provinces[p].development) if game.state.provinces.has(p) else 0.0)
	var t: String = pool[0]
	Titles.transfer_title(game, t, to.id)
	if to.liege != liege.id and to.id != liege.id:
		Chars.set_liege(game, to, liege.id)
	return true


# ------------------------------------------------------------ месяц

static func monthly_char(game: Game, c: Dictionary) -> void:
	if c.death != null or c.titles.is_empty():
		return
	var d := dread(c)
	if d > 0.0:
		var decay := game.def_num("politics.dread_decay", 0.75)
		if c.traits.has("compassionate"):
			decay = game.def_num("politics.dread_decay_compassionate", 1.5)
		# dread_decay_mult — например, тень мастерства дипломата: страх перед ним быстро тает
		decay *= maxf(0.0, 1.0 + Stats.stat(game, c, "dread_decay_mult"))
		c.vars["dread"] = d - decay
		if dread(c) <= 0.0:
			c.vars.erase("dread")
	if game.vassals_of(c.id).is_empty() or c.get("prison") != null:
		return
	# Прошения вассалов: игрок — с небольшим шансом каждый месяц, остальные
	# правители — раз в год, в «свой» месяц.
	if game.is_player(c.id):
		if game.rng.next() * 100.0 < game.def_num("politics.petition_chance_player", 5):
			game.on_action("on_vassal_petition", {"type": "character", "id": c.id})
	elif (Rng.hash_string(c.id) & 0x7FFFFFFF) % 12 == GameDate.parts(game.date).m - 1:
		if game.rng.next() * 100.0 < game.def_num("politics.petition_chance_ai", 30):
			game.on_action("on_vassal_petition", {"type": "character", "id": c.id})


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("politics", {"id": "politics", "order": 57, "on_character_month": Politics.monthly_char}, OWNER)
	# Условия службы меняют взнос вассала сюзерену (налог и ополчение).
	engine.modifier_providers.register("vassal_obligation", {"fn": func(game: Game, c: Dictionary) -> Variant:
		if c.liege == null or c.titles.is_empty():
			return null
		var ob: Variant = Politics.obligation_of(game, c)
		if ob == null or (Data.num(ob.get("tax")) == 0.0 and Data.num(ob.get("levy")) == 0.0):
			return null
		var oid: String = ob.id
		return [{"label": func(): return game.name_of("vassal_obligations", oid),
			"modifiers": {"vassal_contribution_tax": Data.num(ob.get("tax")), "vassal_contribution_levy": Data.num(ob.get("levy"))}}]
	}, OWNER)
	# Мнение подданного о сюзерене: условия службы, место в совете, страх.
	engine.opinion_providers.register("politics", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		if a.liege != b.id:
			return null
		var out := []
		if not a.titles.is_empty():
			var ob: Variant = Politics.obligation_of(game, a)
			if ob != null and Data.num(ob.get("opinion")) != 0.0:
				out.append({"label": game.name_of("vassal_obligations", ob.id), "value": Data.num(ob.get("opinion"))})
			if game.engine.has_feature("council") and Politics.powerful_vassals(game, b).has(a.id):
				if Politics.is_seated(game, b, a):
					out.append({"label": game.loc.t("opinion.powerful_seated"), "value": game.def_num("politics.powerful_seat_opinion", 10)})
				else:
					out.append({"label": game.loc.t("opinion.powerful_snubbed"), "value": game.def_num("politics.powerful_snub_opinion", -15)})
		var d := Politics.dread(b)
		# дерзкие (храбрые, гневливые) не боятся, но уважают силу: доблестного сюзерена
		if Politics.is_defiant(game, a):
			var resp := minf(game.def_num("politics.respect_max", 15), (Stats.skill(game, b, "prowess") - game.def_num("politics.respect_from", 12)) * game.def_num("politics.respect_per_point", 1.5))
			if resp >= 1.0:
				out.append({"label": game.loc.t("opinion.respects_strength"), "value": roundf(resp)})
		if d >= 1.0:
			if Politics.is_defiant(game, a):
				out.append({"label": game.loc.t("opinion.defiant"), "value": roundf(d * game.def_num("politics.defiant_per_dread", -0.15))})
			else:
				out.append({"label": game.loc.t("opinion.intimidated"), "value": roundf(d * game.def_num("politics.intimidated_per_dread", 0.3))})
		return out if not out.is_empty() else null
	}, OWNER)
	# Совет: ИИ охотнее сажает влиятельных вассалов (их обида дороже).
	engine.hooks.on("council.candidate_score", func(p):
		return p.game.def_num("politics.council_seat_bonus", 4) if Politics.powerful_vassals(p.game, p.liege).has(p.candidate.id) else null
	, 0, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	var other := func(ctx: ScriptContext, s: Variant, arg: Variant) -> Variant:
		var o: Variant = Interp.resolve_scope(ctx, s, arg)
		return ctx.game.ch(o.id) if (o != null and o.type == "character") else null

	r.triggers.register("is_powerful_vassal", {"scopes": CH, "doc": "Один из влиятельных вассалов своего сюзерена", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return (c != null and Politics.is_powerful(ctx.game, c)) == ScriptContext.is_yes(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_powerful_vassal" if ScriptContext.is_yes(arg) else "tr.not_powerful_vassal"),
	}, OWNER)
	r.triggers.register("vassal_obligation", {"scopes": CH, "doc": "Условия службы вассала: vassal_obligation: heavy", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var ob: Variant = Politics.obligation_of(ctx.game, c) if (c != null and c.liege != null) else null
		return ob != null and ob.id == str(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.vassal_obligation", {"value": ctx.game.name_of("vassal_obligations", str(arg))}),
	}, OWNER)
	r.triggers.register("has_snubbed_powerful_vassal", {"scopes": CH, "doc": "Кто-то из влиятельных вассалов не получил места в совете", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return (c != null and not Politics.snubbed(ctx.game, c).is_empty()) == ScriptContext.is_yes(arg),
	}, OWNER)
	r.values.register("dread", {"scopes": CH, "doc": "Страх, который внушает правитель (0–100)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Politics.dread(c) if c != null else 0.0
	}, OWNER)
	r.values.register("fear_of_liege", {"scopes": CH, "doc": "Страх перед сюзереном (0 у храбрых и гневливых)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return Politics.fear_of_liege(ctx.game, c) if c != null else 0.0
	}, OWNER)
	r.values.register("num_powerful_vassals", {"scopes": CH, "doc": "Число влиятельных вассалов", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(Politics.powerful_vassals(ctx.game, c).size()) if c != null else 0.0
	}, OWNER)
	r.lists.register("powerful_vassal", {"from": CH, "doc": "Влиятельные вассалы", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		return Politics.powerful_vassals(ctx.game, c).map(func(id): return {"type": "character", "id": id}) if c != null else []
	}, OWNER)
	r.lists.register("snubbed_powerful_vassal", {"from": CH, "doc": "Влиятельные вассалы без места в совете", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		return Politics.snubbed(ctx.game, c).map(func(x): return {"type": "character", "id": x.id}) if c != null else []
	}, OWNER)

	r.effects.register("add_dread", {"scopes": CH, "doc": "Изменить страх, который внушает правитель", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			Politics.add_dread(ctx.game, c, Interp.eval_value(ctx, s, arg)),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.add_dread", {"value": "%+d" % roundi(Interp.eval_value(ctx, s, arg))}),
	}, OWNER)
	r.effects.register("set_vassal_obligation", {"scopes": CH, "doc": "Установить вассалу условия службы: set_vassal_obligation: privileged", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			Politics.set_obligation(ctx.game, c, str(arg)),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.set_vassal_obligation", {"who": ctx.game.scope_name(s), "value": ctx.game.name_of("vassal_obligations", str(arg))}),
	}, OWNER)
	r.effects.register("seat_in_council", {"scopes": CH, "doc": "Дать персонажу место в своём совете (на должность по его лучшему навыку)", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var v: Variant = other.call(ctx, s, arg)
		if c != null and v != null:
			Politics.seat_in_council(ctx.game, c, v),
		"describe": func(ctx, s, arg):
			var v: Variant = other.call(ctx, s, arg)
			return ctx.game.loc.t("fx.seat_in_council", {"who": ctx.game.scope_name({"type": "character", "id": v.id})}) if v != null else null,
	}, OWNER)
	r.effects.register("remove_from_council", {"scopes": CH, "doc": "Советник лишается места в совете сюзерена", "apply": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		var pos: Variant = Council.position_of(ctx.game, c) if (c != null and ctx.game.engine.has_feature("council")) else null
		if pos != null:
			Council.dismiss(ctx.game, pos.liege, pos.position),
		"describe": func(ctx, s, _a): return ctx.game.loc.t("fx.remove_from_council", {"who": ctx.game.scope_name(s)}),
	}, OWNER)
	r.effects.register("sow_discord", {"scopes": CH, "doc": "Посеять раздор между вассалом и его ближайшим союзником: sow_discord: scope:recipient", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var v: Variant = other.call(ctx, s, arg)
		if c != null and v != null:
			Politics.sow_discord(ctx.game, c, v),
		"describe": func(ctx, _s, _a): return ctx.game.loc.t("fx.sow_discord"),
	}, OWNER)
	r.effects.register("calm_factions", {"scopes": CH, "doc": "Снизить недовольство всех фракций против правителя: calm_factions: 40", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c == null or not ctx.game.engine.has_feature("factions"):
			return
		var v := Interp.eval_value(ctx, s, arg)
		for f in Factions.against(ctx.game, c.id):
			f.discontent = maxf(0.0, float(f.discontent) - v),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.calm_factions", {"value": roundi(Interp.eval_value(ctx, s, arg))}),
	}, OWNER)
	r.effects.register("grant_minor_county", {"scopes": CH, "doc": "Пожаловать персонажу самое бедное графство своего домена (не столицу)", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var v: Variant = other.call(ctx, s, arg)
		if c != null and v != null:
			Politics.grant_minor_county(ctx.game, c, v),
		"describe": func(ctx, s, arg):
			var v: Variant = other.call(ctx, s, arg)
			return ctx.game.loc.t("fx.grant_minor_county", {"who": ctx.game.scope_name({"type": "character", "id": v.id})}) if v != null else null,
	}, OWNER)
	engine.content_validators.register("politics", func(e: GameEngine, v: ScriptValidator):
		var defaults := e.content.all("vassal_obligations").filter(func(o): return o.get("default", false))
		if not e.content.all("vassal_obligations").is_empty() and defaults.size() != 1:
			v.issue("vassal_obligations: нужен ровно один вариант с default: yes")
	, OWNER)

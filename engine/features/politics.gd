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
##   dread_tiers: { <id>: { min, icon, modifiers, silence, stress_monthly,
##     stress_immune: [черты], dissolve_factions } } — ступени страха: по
##     порогу min; modifiers — правителю (complaint_mult — реже жалобы и
##     прошения), silence — их нет вовсе, stress_monthly — бессонница правителя
##     (кроме носителей stress_immune), dissolve_factions — фракции против него
##     распадаются (остаются только дерзкие).
##   Кто боится (stance): «сломленные» (побывали в темнице сюзерена) чувствуют
##   страх на ступень выше (politics.broken_fear) и не вступают во фракции;
##   «дерзкие» — черты defiant_traits, влиятельные вассалы и кровники
##   казнённых (defiant_modifiers) — не боятся, а злятся, но уважают
##   доблестного сюзерена; остальные — «покорные». dread_gain_mult правителя
##   (доблесть) ускоряет рост страха.
##   on_actions: on_vassal_petition — события-прошения (root — сюзерен),
##   on_dread_tier_up / on_dread_tier_down — страх перешёл ступень.
## Состояние: вассал — c.obligation = {liege, id} (с другим сюзереном
## действуют обычные условия); правитель — c.vars.dread, c.vars.dread_tier
## (номер ступени); c.vars.broken_by — в чьей темнице побывал.

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
	_set_dread(game, c, dread(c) + v)


static func _set_dread(game: Game, c: Dictionary, v: float) -> void:
	c.vars["dread"] = clampf(v, 0.0, game.def_num("politics.dread_max", 100))
	if dread(c) <= 0.0:
		c.vars.erase("dread")
	# мнение подданных о правителе изменилось
	for x in game.vassals_of(c.id) + game.courtiers_of(c.id):
		game.stat_cache.erase("op:%s>%s" % [x.id, c.id])
	_check_tier(game, c)


# ------------------------------------------------------------ ступени страха

## Ступени страха по возрастанию порога.
static func tiers(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("politics:tiers")
	if hit == null:
		hit = game.content.all("dread_tiers").duplicate()
		Data.sort_by(hit, func(x): return Data.num(x.get("min")))
		game.engine.cache["politics:tiers"] = hit
	return hit


## Номер ступени для такого страха (0 — нижняя; −1 — ступеней нет).
static func level_for(game: Game, d: float) -> int:
	var lvl := -1
	var ts := tiers(game)
	for i in ts.size():
		if d >= Data.num(ts[i].get("min")):
			lvl = i
	return lvl


## Номер ступени по её id (−1 — нет такой).
static func level_of_id(game: Game, id: String) -> int:
	var ts := tiers(game)
	for i in ts.size():
		if ts[i].id == id:
			return i
	return -1


static func tier_at(game: Game, lvl: int) -> Variant:
	var ts := tiers(game)
	return ts[lvl] if lvl >= 0 and lvl < ts.size() else null


## Ступень страха, которую внушает правитель.
static func tier_level(game: Game, c: Dictionary) -> int:
	return level_for(game, dread(c))


static func tier_of(game: Game, c: Dictionary) -> Variant:
	return tier_at(game, tier_level(game, c))


## Сравнение ступени со значением условия: "fear", ">= horror", "< unease".
static func compare_tier(game: Game, lvl: int, arg: Variant) -> bool:
	var p := _tier_arg(str(arg))
	var want := level_of_id(game, p[1])
	if want < 0:
		game.script_error("Неизвестная ступень страха \"%s\"" % p[1])
		return false
	match p[0]:
		">=":
			return lvl >= want
		">":
			return lvl > want
		"<=":
			return lvl <= want
		"<":
			return lvl < want
		"!=":
			return lvl != want
	return lvl == want


static func _tier_arg(a: String) -> Array:
	a = a.strip_edges()
	for op in [">=", "<=", "!=", ">", "<", "=="]:
		if a.begins_with(op):
			return [op, a.substr(op.length()).strip_edges()]
	return ["==", a]


static func describe_tier(game: Game, key: String, arg: Variant) -> String:
	var p := _tier_arg(str(arg))
	var op: String = {">=": "ge", ">": "gt", "<=": "le", "<": "lt", "!=": "ne", "==": "eq"}[p[0]]
	return game.loc.t(key, {"cond": game.loc.t("tr.tier_cmp." + op, {"tier": game.name_of("dread_tiers", p[1])})})


## Поднять страх до следующей ступени (с запасом в пять очков).
static func raise_tier(game: Game, c: Dictionary, steps: int = 1) -> void:
	var nxt: Variant = tier_at(game, tier_level(game, c) + maxi(1, steps))
	if nxt == null:
		_set_dread(game, c, game.def_num("politics.dread_max", 100))
	else:
		_set_dread(game, c, maxf(dread(c), Data.num(nxt.get("min")) + 5.0))


## Страх перешёл ступень: модификаторы правителя, мнения, on_action.
static func _check_tier(game: Game, c: Dictionary) -> void:
	var lvl := tier_level(game, c)
	var was := int(Data.num(c.vars.get("dread_tier"), 0.0))
	if lvl == was or lvl < 0:
		return
	if lvl <= 0:
		c.vars.erase("dread_tier")
	else:
		c.vars["dread_tier"] = lvl
	game.stat_cache.erase(c.id)
	game.emit("politics.dread_tier", {"character": c, "from": was, "to": lvl})
	var t: Variant = tier_at(game, lvl)
	if game.is_player(c.id) and t != null:
		game.message(game.loc.t("msg.dread_tier_up" if lvl > was else "msg.dread_tier_down", {"tier": game.name_of("dread_tiers", t.id)}),
			"war" if lvl > was else "info", {"type": "character", "id": c.id})
	game.on_action("on_dread_tier_up" if lvl > was else "on_dread_tier_down", {"type": "character", "id": c.id})


# ------------------------------------------------------------ кто боится

## Как подданный относится к страху сюзерена:
##   "broken"   — побывал в его темнице: боится на ступень сильнее, во фракции не идёт;
##   "defiant"  — дерзкий (храбрые, гневливые, влиятельные вассалы, кровники
##                казнённых): не боится, а злится;
##   "obedient" — покорный: ступени страха действуют как есть.
static func stance(game: Game, c: Dictionary, liege: Variant = null) -> String:
	if liege == null:
		liege = game.ch(c.liege) if c.liege != null else null
	if liege == null:
		return "obedient"
	if Data.as_array(c.vars.get("broken_by")).has(liege.id):
		return "broken"
	# «голос повелителя»: перед таким сюзереном дерзких не бывает
	for t in game.def_val("politics.commanding_traits", []):
		if liege.traits.has(t):
			return "obedient"
	for t in game.def_val("politics.defiant_traits", ["brave", "wrathful"]):
		if c.traits.has(t):
			return "defiant"
	var mods: Array = game.def_val("politics.defiant_modifiers", ["executed_relative"])
	for e in c.opinions.get(liege.id, []):
		if mods.has(e.mod):
			return "defiant"
	if c.liege == liege.id and is_powerful(game, c):
		return "defiant"
	return "obedient"


## Не склоняются перед страхом — а ненавидят тирана.
static func is_defiant(game: Game, c: Dictionary) -> bool:
	return stance(game, c) == "defiant"


## Насколько персонаж боится своего сюзерена: дерзкие — нисколько,
## сломленные — сильнее на politics.broken_fear (примерно ступень).
static func fear_of_liege(game: Game, c: Dictionary) -> float:
	if c.liege == null:
		return 0.0
	var l: Variant = game.ch(c.liege)
	if l == null:
		return 0.0
	match stance(game, c, l):
		"defiant":
			return 0.0
		"broken":
			return minf(game.def_num("politics.dread_max", 100), dread(l) + game.def_num("politics.broken_fear", 20))
	return dread(l)


## Ступень страха, которую чувствует подданный перед сюзереном.
static func felt_level(game: Game, c: Dictionary) -> int:
	return maxi(0, level_for(game, fear_of_liege(game, c)))


## Пленник вышел из темницы сломленным: боится тюремщика (и его наследника).
static func mark_broken(game: Game, c: Dictionary, jailer_id: String) -> void:
	var l: Array = Data.as_array(c.vars.get("broken_by")).duplicate()
	if l.has(jailer_id):
		return
	l.append(jailer_id)
	c.vars["broken_by"] = l.slice(maxi(0, l.size() - 6))
	game.stat_cache.erase("op:%s>%s" % [c.id, jailer_id])


## Во сколько раз реже приходят жалобы и прошения (0 — не приходят;
## ступень с silence — молчат все, что бы ни было).
static func complaint_mult(game: Game, c: Dictionary) -> float:
	var t: Variant = tier_of(game, c) if c.vars.has("dread_tier") else null
	if t != null and t.get("silence") != null and ScriptContext.is_yes(t.silence):
		return 0.0
	return clampf(1.0 + Stats.stat(game, c, "complaint_mult"), 0.0, 1.0)


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
		# dread_floor — ниже страх не опускается (Наместник Пепла)
		c.vars["dread"] = maxf(d - decay, Stats.stat(game, c, "dread_floor"))
		if dread(c) <= 0.0:
			c.vars.erase("dread")
		if level_for(game, dread(c)) != int(Data.num(c.vars.get("dread_tier"), 0.0)):
			_check_tier(game, c)
	var tier: Variant = tier_of(game, c) if c.vars.has("dread_tier") else null
	if tier != null:
		# бессонница: кто внушает ужас, тот и сам не спит (кроме бессердечных)
		var sm := Data.num(tier.get("stress_monthly"))
		if sm > 0.0 and not Data.as_array(tier.get("stress_immune")).any(func(t): return c.traits.has(t)):
			Chars.change_stress(game, c, sm, "dread_tier")
		# террор: фракции распадаются — остаются лишь дерзкие
		if tier.get("dissolve_factions") != null and ScriptContext.is_yes(tier.dissolve_factions) and game.engine.has_feature("factions"):
			for f in Factions.against(game, c.id):
				if f.get("popular", false) or game.state.wars.values().any(func(w): return w.get("faction") == f.id):
					continue
				for mid in f.members.duplicate():
					var m: Variant = game.ch(mid)
					if m != null and stance(game, m, c) != "defiant":
						Factions.leave(game, m)
	# Тиран: каждый пленник в темнице — немного страха в месяц
	var per_prisoner := Stats.stat(game, c, "dread_per_prisoner")
	if per_prisoner > 0.0 and game.engine.has_feature("prison"):
		var n := Prison.prisoners_of(game, c.id).size()
		if n > 0:
			add_dread(game, c, minf(float(n), game.def_num("politics.dread_prisoners_cap", 5)) * per_prisoner)
	if game.vassals_of(c.id).is_empty() or c.get("prison") != null:
		return
	# Прошения вассалов: игрок — с небольшим шансом каждый месяц, остальные
	# правители — раз в год, в «свой» месяц.
	# страх затыкает рты: complaint_mult ступени страха
	if game.is_player(c.id):
		if game.rng.next() * 100.0 < game.def_num("politics.petition_chance_player", 5) * complaint_mult(game, c):
			game.on_action("on_vassal_petition", {"type": "character", "id": c.id})
	elif (Rng.hash_string(c.id) & 0x7FFFFFFF) % 12 == GameDate.parts(game.date).m - 1:
		if game.rng.next() * 100.0 < game.def_num("politics.petition_chance_ai", 30) * complaint_mult(game, c):
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
		var st := Politics.stance(game, a, b)
		# дерзкие (храбрые, гневливые, влиятельные, кровники) не боятся, но уважают силу: доблестного сюзерена
		if st == "defiant":
			var resp := minf(game.def_num("politics.respect_max", 15), (Stats.skill(game, b, "prowess") - game.def_num("politics.respect_from", 12)) * game.def_num("politics.respect_per_point", 1.5))
			if resp >= 1.0:
				out.append({"label": game.loc.t("opinion.respects_strength"), "value": roundf(resp)})
			if d >= 1.0:
				out.append({"label": game.loc.t("opinion.defiant"), "value": roundf(d * game.def_num("politics.defiant_per_dread", -0.15))})
		else:
			var fear := Politics.fear_of_liege(game, a) if a.liege == b.id else d
			if fear >= 1.0:
				out.append({"label": game.loc.t("opinion.broken" if st == "broken" else "opinion.intimidated"), "value": roundf(fear * game.def_num("politics.intimidated_per_dread", 0.3))})
		return out if not out.is_empty() else null
	}, OWNER)
	# Ступень страха — модификаторы правителя (ступени выше нижней).
	engine.modifier_providers.register("dread_tier", {"fn": func(game: Game, c: Dictionary) -> Variant:
		if not c.vars.has("dread_tier"):
			return null
		var t: Variant = Politics.tier_at(game, int(c.vars.dread_tier))
		if t == null or not (t.get("modifiers") is Dictionary) or t.modifiers.is_empty():
			return null
		var tid: String = t.id
		return [{"label": func(): return game.loc.t("ui.dread_tier_mod", {"tier": game.name_of("dread_tiers", tid)}), "modifiers": t.modifiers}]
	}, OWNER)
	# enemy_thinning: перед боем войско врага тает от страха (Наместник Пепла)
	engine.hooks.on("army.power_bonus", func(p):
		var game: Game = p.game
		var thin := 0.0
		for e in p.get("enemies", []):
			var o: Variant = game.ch(e.get("owner"))
			if o != null:
				thin = maxf(thin, Stats.stat(game, o, "enemy_thinning"))
		return -float(p.army.size) * minf(thin, 0.9) if thin > 0.0 else null
	, 0, OWNER)
	# Темница ломает: вышедший из неё боится тюремщика сильнее и не бунтует.
	engine.hooks.on("prison.released", func(p):
		var game: Game = p.game
		var c: Dictionary = p.prisoner
		if Chars.is_alive(c) and game.ch(p.jailer) != null:
			Politics.mark_broken(game, c, str(p.jailer))
	, 0, OWNER)
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
	r.triggers.register("dread_tier", {"scopes": CH, "doc": "Ступень страха, которую внушает правитель: dread_tier: fear или dread_tier: \">= horror\"", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return c != null and Politics.compare_tier(ctx.game, Politics.tier_level(ctx.game, c), arg),
		"describe": func(ctx, _s, arg): return Politics.describe_tier(ctx.game, "tr.dread_tier", arg),
	}, OWNER)
	r.triggers.register("felt_dread_tier", {"scopes": CH, "doc": "Ступень страха, которую подданный чувствует перед сюзереном (дерзкие — нижняя, сломленные — выше): felt_dread_tier: \"< unease\"", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return c != null and Politics.compare_tier(ctx.game, Politics.felt_level(ctx.game, c), arg),
		"describe": func(ctx, _s, arg): return Politics.describe_tier(ctx.game, "tr.felt_dread_tier", arg),
	}, OWNER)
	r.triggers.register("fear_stance", {"scopes": CH, "doc": "Как подданный относится к страху сюзерена: defiant (дерзкий), broken (сломленный), obedient (покорный)", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return c != null and Politics.stance(ctx.game, c) == str(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.fear_stance", {"value": ctx.game.loc.t("ui.stance." + str(arg))}),
	}, OWNER)
	r.values.register("dread_tier_level", {"scopes": CH, "doc": "Номер ступени страха правителя (0 — нижняя)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		return float(maxi(0, Politics.tier_level(ctx.game, c))) if c != null else 0.0
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
	r.effects.register("raise_dread_tier", {"scopes": CH, "doc": "Поднять страх правителя на ступень (или на N ступеней): raise_dread_tier: 1", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c != null:
			Politics.raise_tier(ctx.game, c, maxi(1, roundi(Interp.eval_value(ctx, s, arg)) if not (arg is bool) else 1)),
		"describe": func(ctx, _s, _a): return ctx.game.loc.t("fx.raise_dread_tier"),
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
	engine.content_validators.register("dread_tiers", func(e: GameEngine, v: ScriptValidator):
		for t in e.content.all("dread_tiers"):
			if not (t.get("min") is float or t.get("min") is int):
				v.issue("dread_tiers/%s: нужен порог min" % t.id)
	, OWNER)
	engine.content_validators.register("politics", func(e: GameEngine, v: ScriptValidator):
		var defaults := e.content.all("vassal_obligations").filter(func(o): return o.get("default", false))
		if not e.content.all("vassal_obligations").is_empty() and defaults.size() != 1:
			v.issue("vassal_obligations: нужен ровно один вариант с default: yes")
	, OWNER)

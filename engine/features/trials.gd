class_name Trials
extends EngineFeature
## Испытания архетипов. Связка навыков не даётся даром: когда все её навыки
## дотягивают до порога (skill_archetypes.<id>.min), открывается решение
## «Встать на путь: …» (trial_<id> — создаётся само для каждой связки). Оно
## начинает испытание: цели на years лет. Выполнил все — архетип навсегда;
## не успел — стресс fail_stress и перерыв cooldown_years на этот путь.
## Одновременно — одно испытание, архетипов — не больше
## defines.character.max_archetypes.
##
##   skill_archetypes.<id>.trial: { years, ai_will_do,
##     goals: [ { deed: <деяние>, count: N } | { trigger: {...}, desc: <ключ> } ] }
##   defines.trials: { years, fail_stress, cooldown_years, ai_check_months,
##                     ai_goal_will, ai_goal_frequency, ai_war_chance }
## Цель-деяние считает деяния (механика deeds) с начала испытания (текст —
## deed_goal.<деяние>, прогресс показывается рядом); цель-условие
## проверяется раз в месяц. Без цели (нет trial) решение даёт архетип сразу.
## Без механики trials архетипы приходят сами, как только навыки дотянули.
## Состояние: c.vars.archetypes = [id]; c.vars.trial = {id, start, until, base}.
## Хуки: trial.started, trial.completed, trial.failed — {character, archetype}.

const OWNER := "core/trials"


func _init() -> void:
	id = "trials"
	doc = "Испытания архетипов: связку навыков нужно заслужить делами"


static func earned(c: Variant) -> Array:
	if not (c is Dictionary):
		return []
	var a: Variant = c.vars.get("archetypes")
	return a if a is Array else []


static func active(c: Variant) -> Variant:
	return c.vars.get("trial") if c is Dictionary else null


static func _def(game: Game, arch: String) -> Variant:
	return game.content.get_def("skill_archetypes", arch)


static func _trial(game: Game, arch: String) -> Dictionary:
	var d: Variant = _def(game, arch)
	return d.trial if d != null and d.get("trial") is Dictionary else {}


## Навыки дотягивают до порога связки.
static func skills_fit(game: Game, c: Dictionary, arch: String) -> bool:
	var d: Variant = _def(game, arch)
	if d == null or not (d.get("skills") is Array):
		return false
	var mn := Data.num(d.get("min"), 12)
	for s in d.skills:
		if Stats.skill(game, c, str(s)) < mn:
			return false
	return true


## Причины, по которым путь сейчас не начать (пусто — можно).
static func blockers(game: Game, c: Dictionary, arch: String) -> Array:
	var out := []
	if earned(c).has(arch):
		out.append(game.loc.t("ui.trial_have"))
	if earned(c).size() >= int(game.def_num("character.max_archetypes", 2)):
		out.append(game.loc.t("ui.trial_max", {"n": int(game.def_num("character.max_archetypes", 2))}))
	if active(c) != null:
		out.append(game.loc.t("ui.trial_busy"))
	var cd: Variant = c.flags.get("trial_cd:" + arch)
	if cd != null and int(cd) > game.date:
		out.append(game.loc.t("ui.on_cooldown", {"days": int(cd) - game.date}))
	if not skills_fit(game, c, arch):
		out.append(game.loc.t("ui.trial_skills"))
	return out


static func can_begin(game: Game, c: Dictionary, arch: String) -> bool:
	if c.death != null or c.get("prison") != null or not Chars.is_adult(game, c) or active(c) != null:
		return false
	if earned(c).has(arch) or earned(c).size() >= int(game.def_num("character.max_archetypes", 2)):
		return false
	var cd: Variant = c.flags.get("trial_cd:" + arch)
	if cd != null and int(cd) > game.date:
		return false
	return skills_fit(game, c, arch)


static func begin(game: Game, c: Dictionary, arch: String) -> void:
	var tr := _trial(game, arch)
	if Data.as_array(tr.get("goals")).is_empty():
		grant(game, c, arch)
		return
	var base := {}
	for g in Data.as_array(tr.goals):
		if g is Dictionary and g.get("deed") != null:
			base[str(g.deed)] = Deeds.count(c, str(g.deed))
	var years := Data.num(tr.get("years"), game.def_num("trials.years", 5))
	c.vars["trial"] = {"id": arch, "start": game.date, "until": game.date + roundi(years * GameDate.DAYS_PER_YEAR), "base": base}
	if game.is_player(c.id):
		game.message(game.loc.t("msg.trial_started", {"name": game.name_of("skill_archetypes", arch), "years": roundi(years)}), "event", {"type": "character", "id": c.id})
	game.emit("trial.started", {"character": c, "archetype": arch})
	game.notify("character")


## Архетип — навсегда (без испытания: решение без целей, эффект grant_archetype).
static func grant(game: Game, c: Dictionary, arch: String) -> void:
	var have := earned(c).duplicate()
	if have.has(arch):
		return
	have.append(arch)
	c.vars["archetypes"] = have
	game.stat_cache.erase(c.id)
	game.notify("character")


## Цели активного испытания: [{text, have, need, done}].
static func goals(game: Game, c: Dictionary) -> Array:
	var t: Variant = active(c)
	if t == null:
		return []
	return goals_of(game, c, str(t.id), t.get("base", {}))


## Цели испытания пути arch; base — счётчики деяний на начало (null — ещё не начато).
static func goals_of(game: Game, c: Dictionary, arch: String, base: Variant = null) -> Array:
	var out := []
	for g in Data.as_array(_trial(game, arch).get("goals")):
		if not (g is Dictionary):
			continue
		if g.get("deed") != null:
			var deed := str(g.deed)
			var need := int(Data.num(g.get("count"), 1))
			var have := 0
			if not game.engine.has_feature("deeds"):
				have = need   # без летописи деяний такие цели не считаются
			elif base is Dictionary:
				have = Deeds.count(c, deed) - int(base.get(deed, 0))
			out.append({"text": game.text(g.get("desc", "deed_goal." + deed), null, {"n": need}), "have": mini(have, need), "need": need, "done": have >= need})
		else:
			var ok := false
			if base is Dictionary:
				var ctx := ScriptContext.make(game, {"type": "character", "id": c.id})
				ok = Interp.eval_trigger(ctx, ctx.root, g.get("trigger"))
			out.append({"text": game.text(g.get("desc", "")), "have": 1 if ok else 0, "need": 1, "done": ok})
	return out


## ИИ на испытании охотнее делает то, что продвигает его цели:
## + trials.ai_goal_will к желанию решения или взаимодействия — источника
## нужного деяния (key — "decision:<id>" / "interaction:<id>").
static func ai_will_shift(game: Game, c: Dictionary, key: String) -> float:
	var t: Variant = active(c)
	if t == null or not game.engine.has_feature("deeds"):
		return 0.0
	var idx := Deeds._index(game)
	var deeds: Array = idx.get(key, []) + idx.get("hint:" + key, [])
	if deeds.is_empty():
		return 0.0
	for g in Data.as_array(_trial(game, str(t.id)).get("goals")):
		if g is Dictionary and deeds.has(str(g.get("deed"))):
			return game.def_num("trials.ai_goal_will", 40)
	return 0.0


## Цели испытания требуют войны (битвы, осады, победы).
static func ai_wants_war(game: Game, c: Dictionary) -> bool:
	var t: Variant = active(c)
	if t == null:
		return false
	for g in Data.as_array(_trial(game, str(t.id)).get("goals")):
		var d: Variant = game.content.get_def("deeds", str(g.get("deed"))) if g is Dictionary else null
		if d != null and ["battle_won", "siege_won", "war_won"].has(str(d.get("signal"))):
			return true
	return false


static func monthly_char(game: Game, c: Dictionary) -> void:
	var t: Variant = active(c)
	if t == null:
		return
	var arch := str(t.id)
	if _def(game, arch) == null:
		c.vars.erase("trial")
		return
	var gs := goals_of(game, c, arch, t.get("base", {}))
	if gs.all(func(x): return x.done):
		c.vars.erase("trial")
		grant(game, c, arch)
		if game.is_player(c.id) or game.is_player(str(c.get("liege"))):
			game.message(game.loc.t("msg.trial_completed", {"who": game.scope_name({"type": "character", "id": c.id}), "name": game.name_of("skill_archetypes", arch)}), "good", {"type": "character", "id": c.id})
		game.emit("trial.completed", {"character": c, "archetype": arch})
		return
	if game.date >= int(t.until):
		c.vars.erase("trial")
		c.flags["trial_cd:" + arch] = game.date + roundi(game.def_num("trials.cooldown_years", 5) * GameDate.DAYS_PER_YEAR)
		Chars.change_stress(game, c, game.def_num("trials.fail_stress", 30), "trial")
		if game.is_player(c.id):
			game.message(game.loc.t("msg.trial_failed", {"name": game.name_of("skill_archetypes", arch)}), "bad", {"type": "character", "id": c.id})
		game.emit("trial.failed", {"character": c, "archetype": arch})
		game.notify("character")


func install(engine: GameEngine) -> void:
	engine.systems.register("trials", {"id": "trials", "order": 14, "on_character_month": Trials.monthly_char}, OWNER)
	# решение «Встать на путь» для каждой связки (своё решение trial_<id> в данных не перезаписывается)
	for a in engine.content.all("skill_archetypes"):
		var did := "trial_" + str(a.id)
		if engine.content.has("decisions", did):
			continue
		var tr: Dictionary = a.trial if a.get("trial") is Dictionary else {}
		engine.content.set_def("decisions", did, {
			"icon": a.get("icon", "star"),
			"major": true,
			"name": {"key": "decision.begin_trial", "params": {"name": "skill_archetype." + str(a.id)}},
			"desc": "skill_archetype_desc." + str(a.id),
			"is_shown": {"can_begin_trial": str(a.id)},
			"effect": {"begin_trial": str(a.id)},
			"ai_will_do": tr.get("ai_will_do", 50),
			"ai_check_months": engine.content.singleton("defines").get("trials", {}).get("ai_check_months", 12),
		})
	engine.content_validators.register("trials", func(e: GameEngine, v: ScriptValidator):
		for a in e.content.all("skill_archetypes"):
			var tr: Variant = a.get("trial")
			if tr == null:
				continue
			if not (tr is Dictionary):
				v.issue("skill_archetypes/%s: trial — словарь { years, goals }" % a.id)
				continue
			for g in Data.as_array(tr.get("goals")):
				if g is Dictionary and g.get("deed") != null:
					v.ref("deeds", g.deed, "skill_archetypes/%s trial" % a.id)
				elif g is Dictionary:
					v.trigger(g.get("trigger"), "skill_archetypes/%s trial goal" % a.id)
				else:
					v.issue("skill_archetypes/%s: цель испытания — { deed, count } или { trigger, desc }" % a.id)
	)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	r.triggers.register("can_begin_trial", {"scopes": CH, "doc": "Может встать на путь связки навыков (испытание): can_begin_trial: <архетип>", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		return c != null and Trials.can_begin(ctx.game, c, str(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.can_begin_trial", {"name": ctx.game.name_of("skill_archetypes", str(arg))}),
	}, OWNER)
	r.triggers.register("has_active_trial", {"scopes": CH, "doc": "Проходит испытание (yes/no или id архетипа)", "eval": func(ctx, s, arg):
		var t: Variant = Trials.active(ctx.game.ch(s.id))
		if arg is String and arg != "yes" and arg != "no":
			return t != null and str(t.id) == arg
		return (t != null) == ScriptContext.is_yes(arg)
	}, OWNER)
	r.values.register("num_archetypes", {"scopes": CH, "doc": "Сколько архетипов заслужено", "get": func(ctx, s, _a):
		return float(Trials.earned(ctx.game.ch(s.id)).size())
	}, OWNER)
	r.effects.register("begin_trial", {"scopes": CH, "doc": "Начать испытание пути: begin_trial: <архетип>",
		"apply": func(ctx, s, arg):
			var c: Variant = ctx.game.ch(s.id)
			if c != null and Trials.can_begin(ctx.game, c, str(arg)):
				Trials.begin(ctx.game, c, str(arg)),
		"describe": func(ctx, s, arg):
			var g: Game = ctx.game
			var c: Variant = g.ch(s.id)
			var tr := Trials._trial(g, str(arg))
			var head := g.loc.t("fx.begin_trial", {"name": g.name_of("skill_archetypes", str(arg)), "years": roundi(Data.num(tr.get("years"), g.def_num("trials.years", 5)))})
			var lines := [head]
			for x in (Trials.goals_of(g, c, str(arg)) if c != null else []):
				lines.append("— %s (%d)" % [x.text, x.need] if x.need > 1 else "— " + str(x.text))
			lines.append(g.loc.t("fx.trial_fail", {"stress": roundi(g.def_num("trials.fail_stress", 30)), "years": roundi(g.def_num("trials.cooldown_years", 5))}))
			return lines,
	}, OWNER)
	r.effects.register("grant_archetype", {"scopes": CH, "doc": "Дать архетип без испытания: grant_archetype: <архетип>",
		"apply": func(ctx, s, arg):
			var c: Variant = ctx.game.ch(s.id)
			if c != null:
				Trials.grant(ctx.game, c, str(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.grant_archetype", {"name": ctx.game.name_of("skill_archetypes", str(arg))}),
	}, OWNER)

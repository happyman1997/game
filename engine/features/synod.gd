class_name Synod
extends EngineFeature
## Собор. Раз в years_min…years_max лет глава веры (механика temple) созывает
## единоверцев и ставит на голосование один вопрос (synod_questions). Через
## notice_days дней Собор собирается: голосуют правители, прошедшие условие
## defines.synod.voter (root — правитель, scope:synod_head — глава веры), с
## весом defines.synod.vote_weight (0 — голоса нет). ИИ голосует по ai_vote
## вопроса: больше vote_threshold — за, меньше −vote_threshold — против, иначе
## воздерживается. Игрок голосует в событии vote_event (за vote_event_days до
## Собора; эффект synod_vote). Голос можно склонить: эффект synod_sway — тогда
## правитель голосует, как обещал. Вопрос принят, если «за» весомее «против».
## Позиция сюзерена: при созыве правители с вассалами объявляют, за они или
## против (ИИ — по своему убеждению, если оно сильно; игрок — в событии
## call_event, эффект synod_declare). Предпочтение вассала сдвигается к
## позиции его сюзерена на liege_stance_weight (вдвое слабее, если вассал
## сюзерена не любит).
## Принятый вопрос с decree становится указом на decree.years лет (0 —
## бессрочно): ruler_modifiers — единоверцам главы, head_modifiers — ему самому;
## условие has_synod_decree. Новый глава веры созывает Собор не позже чем
## через after_election_years лет.
##
##   synod_questions: { <id>: { icon, weight, is_valid (root — глава), target,
##     ai_vote (root — голосующий), on_pass, on_fail (root — глава),
##     decree: { years, ruler_modifiers, head_modifiers, ai_war_mult, ai_holy_war_mult } } }
##   (ai_war_mult — желание ИИ воевать с единоверцем-не-еретиком, ai_holy_war_mult —
##   с еретиком, а при цели-культе — только с ним: хук ai.war_will)
##   target: { type: faith, heretic: yes|no, prefer: small|large } — культ той же религии, что у
##       главы, с правителями (кроме его собственного), еретический или нет;
##       в данных — synod_target_faith, условие of_synod_target_faith,
##       в текстах — [scope:synod_faith_ruler.faith_name]
##     | { type: character, trigger, order } — правитель, лучший по order
##     | { type: dead, years, trigger } — умерший не раньше years лет назад;
##       оба — scope:synod_target.
##   defines.synod: { years_min, years_max, first_years: [от, до],
##     after_election_years, notice_days, call_event, vote_event, vote_event_days,
##     liege_stance_weight,
##     vote_threshold, voter, vote_weight, head_opinion_weight — к предпочтению
##     ИИ прибавляется мнение о главе веры с этим множителем }
## Состояние: game.state.synod = { <титул главы>: { next, head, last,
##   active: { question, target, target_faith, convene, sway, votes, asked,
##     stances: { правитель: 1 | -1 } },
##   decrees: { <вопрос>: { until, target_faith } } } }.
## Хуки: synod.called, synod.result — {head_title, question, passed, for,
## against, target, target_faith}; on_actions on_synod_called, on_synod_result
## (root — глава веры, scope:synod_target).

const OWNER := "core/synod"


func _init() -> void:
	id = "synod"
	doc = "Собор: голосование единоверцев по вопросам веры, указы"


# ------------------------------------------------------------ состояние

static func _all(game: Game) -> Dictionary:
	if not game.state.has("synod"):
		game.state["synod"] = {}
	return game.state.synod


## Титулы глав вер (из head_title культов), без повторов.
static func head_titles(game: Game) -> Array:
	var hit: Variant = game.engine.cache.get("synod:head_titles")
	if hit == null:
		var seen := {}
		for f in game.content.all("faiths"):
			if f.get("head_title") != null:
				seen[str(f.head_title)] = true
		hit = seen.keys()
		game.engine.cache["synod:head_titles"] = hit
	return hit


static func state_of(game: Game, ht: String) -> Dictionary:
	var all := _all(game)
	if not all.has(ht):
		var fy: Array = Data.as_array(game.def_val("synod.first_years", [3, 6]))
		all[ht] = {"next": game.date + _years(game, fy), "head": null, "active": null, "decrees": {}, "last": null}
	return all[ht]


static func _years(game: Game, span: Array) -> int:
	var lo := Data.num(span[0]) if span.size() > 0 else 10.0
	var hi := Data.num(span[1]) if span.size() > 1 else lo
	return roundi((lo + game.rng.next() * maxf(0.0, hi - lo)) * 365.0)


## Собор, касающийся персонажа (по главе его веры), или null.
static func state_for(game: Game, c: Dictionary) -> Variant:
	var ht: Variant = Temple.head_title_of(game, c)
	if ht == null:
		return null
	return state_of(game, ht)


static func active_for(game: Game, c: Dictionary) -> Variant:
	var s: Variant = state_for(game, c)
	return s.active if s != null else null


## Культ-цель Собора, решение которого сейчас исполняется (или созванного).
static var _running_faith := ""


static func target_faith_now(game: Game) -> String:
	if _running_faith != "":
		return _running_faith
	for ht in head_titles(game):
		var a: Variant = state_of(game, ht).active
		if a != null and str(a.get("target_faith", "")) != "":
			return str(a.target_faith)
	return ""


static func has_decree(game: Game, c: Dictionary, qid: String) -> bool:
	var s: Variant = state_for(game, c)
	if s == null:
		return false
	var d: Variant = s.decrees.get(qid)
	return d != null and (int(d.until) == 0 or int(d.until) > game.date)


# ------------------------------------------------------------ голоса

static func _ctx(game: Game, root: Dictionary, head: Variant, active: Variant) -> ScriptContext:
	var scopes := {}
	if head != null:
		scopes["synod_head"] = {"type": "character", "id": head.id}
	if active != null and active.get("target") != null:
		scopes["synod_target"] = {"type": "character", "id": str(active.target)}
	return ScriptContext.make(game, {"type": "character", "id": root.id}, scopes)


static func is_voter(game: Game, c: Dictionary, head: Dictionary) -> bool:
	if c.id == head.id or c.titles.is_empty() or not Chars.is_alive(c):
		return false
	var ctx := _ctx(game, c, head, null)
	return Interp.eval_trigger(ctx, ctx.root, game.def_val("synod.voter", {}))


static func vote_weight(game: Game, c: Dictionary, head: Dictionary) -> float:
	var ctx := _ctx(game, c, head, null)
	return maxf(0.0, Interp.eval_value(ctx, ctx.root, game.def_val("synod.vote_weight", 1)))


static func voters(game: Game, head: Dictionary) -> Array:
	var out := []
	for c in game.rulers():
		if is_voter(game, c, head):
			var w := vote_weight(game, c, head)
			if w > 0.0:
				out.append({"c": c, "w": w})
	return out


## Насколько правитель за вопрос созванного Собора (ai_vote; больше нуля — за).
static func preference(game: Game, c: Dictionary, head: Dictionary, active: Dictionary) -> float:
	var q: Variant = game.content.get_def("synod_questions", str(active.question))
	if q == null:
		return 0.0
	var ctx := _ctx(game, c, head, active)
	_running_faith = str(active.get("target_faith", ""))
	var v := Interp.eval_value(ctx, ctx.root, q.get("ai_vote", 0))
	_running_faith = ""
	# верность Храму: кто расположен к главе веры, склоняется к его предложению
	if c.id != head.id:
		v += Opinion.opinion(game, c, head) * game.def_num("synod.head_opinion_weight", 0.0)
	v += liege_pull(game, c, active)
	return v


## Насколько позиция сюзерена тянет вассала (0 — сюзерен молчит).
static func liege_pull(game: Game, c: Dictionary, active: Dictionary) -> float:
	var st: Variant = active.get("stances", {}).get(c.liege) if c.liege != null else null
	if st == null:
		return 0.0
	var lg: Variant = game.ch(c.liege)
	var k := 1.0 if lg != null and Opinion.opinion(game, c, lg) >= 0 else 0.5
	return float(st) * game.def_num("synod.liege_stance_weight", 15) * k


## Голос правителя: 1 — за, -1 — против, 0 — воздержался.
static func choice(game: Game, c: Dictionary, head: Dictionary, active: Dictionary) -> int:
	if game.is_player(c.id):
		return int(active.votes.get(c.id, 0))
	if active.sway.has(c.id):
		return int(active.sway[c.id])
	var p := preference(game, c, head, active)
	var th := game.def_num("synod.vote_threshold", 5)
	return 1 if p >= th else (-1 if p <= -th else 0)


## Подсчёт: {for, against, voters: [{id, w, choice}]}.
static func tally(game: Game, head: Dictionary, active: Dictionary) -> Dictionary:
	var pro := 0.0
	var con := 0.0
	var list := []
	for v in voters(game, head):
		var ch := choice(game, v.c, head, active)
		if ch > 0:
			pro += v.w
		elif ch < 0:
			con += v.w
		list.append({"id": v.c.id, "w": v.w, "choice": ch})
	return {"for": pro, "against": con, "voters": list}


## Предварительный подсчёт для интерфейса (кэш на день).
static func preview(game: Game, head: Dictionary, active: Dictionary) -> Dictionary:
	var pv: Variant = active.get("preview")
	if pv is Dictionary and int(pv.get("date", -1)) == game.date:
		return pv
	var t := tally(game, head, active)
	active["preview"] = {"date": game.date, "for": t["for"], "against": t.against}
	return active.preview


# ------------------------------------------------------------ ход Собора

static func monthly(game: Game) -> void:
	if not game.engine.has_feature("temple"):
		return
	for ht in head_titles(game):
		_month(game, ht)


static func _month(game: Game, ht: String) -> void:
	var s := state_of(game, ht)
	var t: Variant = game.state.titles.get(ht)
	var head: Variant = game.ch(t.holder) if t != null and t.holder != null else null
	if head != null and not Chars.is_alive(head):
		head = null
	# новый глава веры — Собор не позже чем через after_election_years
	var hid: Variant = head.id if head != null else null
	if hid != s.head:
		if s.head != null and hid != null:
			s.next = mini(int(s.next), game.date + roundi(game.def_num("synod.after_election_years", 2) * 365.0))
		s.head = hid
	# указы истекают
	for qid in s.decrees.keys():
		var d: Dictionary = s.decrees[qid]
		if int(d.until) != 0 and int(d.until) <= game.date:
			s.decrees.erase(qid)
			game.stat_cache.clear()
			_news(game, ht, game.loc.t("msg.synod_decree_expired", {"decree": question_name(game, qid, d)}), "info")
	if head == null:
		return
	if s.active == null:
		if game.date >= int(s.next):
			call_synod(game, ht, head)
		return
	var a: Dictionary = s.active
	# игрок голосует незадолго до Собора
	if not a.get("asked", false) and game.date >= int(a.convene) - roundi(game.def_num("synod.vote_event_days", 60)):
		a["asked"] = true
		var p: Variant = game.player
		if p != null and is_voter(game, p, head) and vote_weight(game, p, head) > 0.0:
			game.events.trigger(str(game.def_val("synod.vote_event", "synod.0001")), {"type": "character", "id": p.id}, text_scopes(game, head, a))
	if game.date >= int(a.convene):
		convene(game, ht, head)


## Созвать Собор (вопрос — по весам из подходящих; qid — принудительно).
static func call_synod(game: Game, ht: String, head: Dictionary, qid: String = "") -> bool:
	var s := state_of(game, ht)
	var opts := []
	for q in game.content.all("synod_questions"):
		if qid != "" and q.id != qid:
			continue
		var ctx := _ctx(game, head, head, null)
		if q.get("is_valid") != null and not Interp.eval_trigger(ctx, ctx.root, q.is_valid):
			continue
		if q.get("decree") is Dictionary and s.decrees.has(q.id):
			continue
		var tgt: Variant = _pick_target(game, q, head)
		if q.get("target") is Dictionary and tgt == null:
			continue
		var w := Interp.eval_value(ctx, ctx.root, q.get("weight", 1)) if q.get("weight") != null else 1.0
		if w > 0.0:
			opts.append({"q": q, "w": w, "t": tgt})
	var pick: Variant = game.rng.weighted(opts, func(o): return o.w)
	if pick == null:
		s.next = game.date + _years(game, [1, 2])
		return false
	var tgt: Variant = pick.t
	s.active = {
		"question": pick.q.id,
		"target": tgt.id if tgt is Dictionary and tgt.get("id") != null else null,
		"target_faith": tgt.faith_id if tgt is Dictionary and tgt.get("faith_id") != null else "",
		"convene": game.date + roundi(game.def_num("synod.notice_days", 365)),
		"sway": {}, "votes": {}, "asked": false, "stances": {},
	}
	# правители с вассалами объявляют позицию (ИИ — если убеждён твёрдо)
	var th := game.def_num("synod.vote_threshold", 5) * 2.0
	for v in voters(game, head):
		var c: Dictionary = v.c
		if game.is_player(c.id) or game.vassals_of(c.id).is_empty():
			continue
		var pref := preference(game, c, head, s.active)
		if absf(pref) >= th:
			s.active.stances[c.id] = 1 if pref > 0.0 else -1
	var payload := {"head_title": ht, "question": pick.q.id, "target": s.active.target, "target_faith": s.active.target_faith}
	game.emit("synod.called", payload)
	game.on_action("on_synod_called", {"type": "character", "id": head.id}, _ctx(game, head, head, s.active).scopes)
	_news(game, ht, game.loc.t("msg.synod_called", {"head": game.scope_name({"type": "character", "id": head.id}), "question": question_name(game, pick.q.id, s.active)}), "event")
	# игрок узнаёт о созыве сразу: объявить позицию, пока есть время склонить голоса
	var p: Variant = game.player
	var ev := str(game.def_val("synod.call_event", ""))
	if p != null and ev != "" and Temple.head_title_of(game, p) == ht and is_voter(game, p, head):
		game.events.trigger(ev, {"type": "character", "id": p.id}, text_scopes(game, head, s.active))
	return true


## Цель вопроса: {id} (персонаж) или {faith_id} (культ) или null.
static func _pick_target(game: Game, q: Dictionary, head: Dictionary) -> Variant:
	var tg: Variant = q.get("target")
	if not (tg is Dictionary):
		return {}
	match str(tg.get("type", "")):
		"faith":
			var want := ScriptContext.is_yes(tg.get("heretic", false))
			var rel := Wars._religion(game, str(head.faith))
			var count := {}
			for c in game.rulers():
				count[c.faith] = int(count.get(c.faith, 0)) + 1
			var opts := []
			for f in game.content.all("faiths"):
				var fid := str(f.id)
				if not count.has(fid) or Wars._religion(game, fid) != rel or fid == str(head.faith):
					continue
				if Temple.faith_heretic(game, fid) != want:
					continue
				# prefer: small — чаще малые культы (горстку еретиков гнать легче), large — крупные
				var n := float(count[fid])
				opts.append({"faith_id": fid, "w": 1.0 / n if str(tg.get("prefer", "")) == "small" else n})
			var p: Variant = game.rng.weighted(opts, func(o): return o.w)
			return {"faith_id": p.faith_id} if p != null else null
		"character", "dead":
			var dead: bool = tg.type == "dead"
			var limit := game.date - roundi(Data.num(tg.get("years"), 30.0) * 365.0)
			var best: Variant = null
			var best_v := -INF
			var pool: Array = game.rulers() if not dead else game.state.characters.values().filter(func(x): return x.death != null and int(x.death) >= limit)
			for c in pool:
				if c.id == head.id:
					continue
				var ctx := _ctx(game, c, head, null)
				if not Interp.eval_trigger(ctx, ctx.root, tg.get("trigger")):
					continue
				var v := Interp.eval_value(ctx, ctx.root, tg.get("order", 0)) if tg.get("order") != null else game.rng.next()
				if v > best_v:
					best_v = v
					best = c
			return {"id": best.id} if best != null else null
	return {}


## Собрать Собор: подсчитать голоса и исполнить решение.
static func convene(game: Game, ht: String, head: Dictionary) -> Dictionary:
	var s := state_of(game, ht)
	var a: Dictionary = s.active
	var q: Variant = game.content.get_def("synod_questions", str(a.question))
	var t := tally(game, head, a)
	var passed: bool = t["for"] > t.against
	if q != null:
		var ctx := _ctx(game, head, head, a)
		_running_faith = str(a.get("target_faith", ""))
		Interp.run_effect(ctx, ctx.root, q.get("on_pass") if passed else q.get("on_fail"))
		_running_faith = ""
		if passed and q.get("decree") is Dictionary:
			var yrs := Data.num(q.decree.get("years"), 0.0)
			s.decrees[q.id] = {"until": game.date + roundi(yrs * 365.0) if yrs > 0.0 else 0, "target_faith": a.get("target_faith", ""), "target": a.get("target")}
			game.stat_cache.clear()
	var payload := {"head_title": ht, "question": a.question, "passed": passed, "for": t["for"], "against": t.against, "target": a.get("target"), "target_faith": a.get("target_faith", "")}
	s.last = {"question": a.question, "passed": passed, "for": t["for"], "against": t.against, "date": game.date, "target": a.get("target"), "target_faith": a.get("target_faith", "")}
	var qname := question_name(game, str(a.question), a)
	s.active = null
	s.next = game.date + _years(game, [game.def_num("synod.years_min", 10), game.def_num("synod.years_max", 15)])
	game.emit("synod.result", payload)
	game.on_action("on_synod_result", {"type": "character", "id": head.id}, _ctx(game, head, head, payload).scopes)
	_news(game, ht, game.loc.t("msg.synod_passed" if passed else "msg.synod_failed", {"question": qname, "for": roundi(t["for"]), "against": roundi(t.against)}), "good" if passed else "info")
	return payload


## Скоупы для текстов о Соборе: synod_head, synod_target и synod_faith_ruler —
## правитель культа-цели (для [scope:synod_faith_ruler.faith_name]).
static func text_scopes(game: Game, head: Dictionary, a: Dictionary) -> Dictionary:
	var out := {"synod_head": {"type": "character", "id": head.id}}
	if a.get("target") != null:
		out["synod_target"] = {"type": "character", "id": str(a.target)}
	var fid := str(a.get("target_faith", ""))
	if fid != "":
		for c in game.rulers():
			if str(c.faith) == fid:
				out["synod_faith_ruler"] = {"type": "character", "id": c.id}
				break
	return out


## Весть игроку, если его вера признаёт этого главу.
static func _news(game: Game, ht: String, text: String, kind: String) -> void:
	var p: Variant = game.player
	if p == null or Temple.head_title_of(game, p) != ht:
		return
	var t: Variant = game.state.titles.get(ht)
	game.message(text, kind, {"type": "character", "id": t.holder} if t != null and t.holder != null else null)


## Название вопроса с подстановкой цели: synod_question.<id> {faith, target}.
static func question_name(game: Game, qid: String, a: Variant = null) -> String:
	var params := {"faith": "", "target": ""}
	if a is Dictionary:
		if str(a.get("target_faith", "")) != "":
			params.faith = game.name_of("faiths", str(a.target_faith))
		if a.get("target") != null:
			params.target = game.scope_name({"type": "character", "id": str(a.target)})
	return game.loc.t("synod_question." + qid, params)


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("synod", {"id": "synod", "order": 59, "on_month": Synod.monthly}, OWNER)
	# указы Собора: единоверцам — ruler_modifiers, главе веры — head_modifiers
	engine.modifier_providers.register("synod_decrees", {"fn": func(game: Game, c: Dictionary) -> Variant:
		if c.titles.is_empty() or not game.state.has("synod"):
			return null
		var ht: Variant = Temple.head_title_of(game, c)
		if ht == null or not game.state.synod.has(ht):
			return null
		var s: Dictionary = game.state.synod[ht]
		if s.decrees.is_empty():
			return null
		var is_head: bool = c.titles.has(ht)
		if not is_head and Wars.is_heretic(game, c):
			return null
		var out := []
		for qid in s.decrees:
			var q: Variant = game.content.get_def("synod_questions", qid)
			if q == null or not (q.get("decree") is Dictionary):
				continue
			var mods: Variant = q.decree.get("head_modifiers" if is_head else "ruler_modifiers")
			if mods is Dictionary and not mods.is_empty():
				var name := Synod.question_name(game, qid, s.decrees[qid])
				out.append({"label": func(): return game.loc.t("ui.synod_decree_mod", {"decree": name}), "modifiers": mods})
		return out if not out.is_empty() else null
	}, OWNER)
	engine.content_validators.register("synod", func(e: GameEngine, v: ScriptValidator):
		for q in e.content.all("synod_questions"):
			var w := "synod_questions/%s" % q.id
			v.trigger(q.get("is_valid"), w + " is_valid")
			v.value(q.get("weight"), w + " weight")
			v.value(q.get("ai_vote"), w + " ai_vote")
			v.effect(q.get("on_pass"), w + " on_pass")
			v.effect(q.get("on_fail"), w + " on_fail")
			var tg: Variant = q.get("target")
			if tg is Dictionary:
				if not ["faith", "character", "dead"].has(str(tg.get("type", ""))):
					v.issue(w + ": target.type — faith, character или dead")
				v.trigger(tg.get("trigger"), w + " target.trigger")
				v.value(tg.get("order"), w + " target.order")
	)
	# Божий мир и подобные указы: ИИ охотнее хранит мир (ai_war_mult указа)
	engine.hooks.on("ai.war_will", Synod._ai_war_will, 0, OWNER)


## Множитель желания ИИ воевать с единоверцем от указов (decree.ai_war_mult).
static func _ai_war_will(p: Dictionary) -> Variant:
	var game: Game = p.game
	var att: Dictionary = p.attacker
	var dfn: Dictionary = p.defender
	var s: Variant = Synod.state_for(game, att)
	if s == null or s.decrees.is_empty() or Wars.is_heretic(game, att):
		return null
	# на еретика — ai_holy_war_mult (если указ о культе — только на этот культ),
	# на единоверца-не-еретика — ai_war_mult
	var key := ""
	if Wars.is_heretic(game, dfn):
		key = "ai_holy_war_mult"
	elif Temple.head_title_of(game, dfn) == Temple.head_title_of(game, att):
		key = "ai_war_mult"
	else:
		return null
	var m := 1.0
	for qid in s.decrees:
		var q: Variant = game.content.get_def("synod_questions", qid)
		if q == null or not (q.get("decree") is Dictionary) or q.decree.get(key) == null:
			continue
		var tf := str(s.decrees[qid].get("target_faith", ""))
		if key == "ai_holy_war_mult" and tf != "" and tf != str(dfn.faith):
			continue
		m *= Data.num(q.decree.get(key), 1.0)
	return m if m != 1.0 else null


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	var head_of := func(ctx: ScriptContext, c: Dictionary) -> Variant:
		var h: Variant = ctx.scopes.get("synod_head")
		return ctx.game.ch(h.id) if h != null else Temple.head_of(ctx.game, c)
	r.triggers.register("synod_active", {"scopes": CH, "doc": "Созван Собор веры персонажа: synod_active: yes", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return c != null and (Synod.active_for(ctx.game, c) != null) == ScriptContext.is_yes(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.synod_active" if ScriptContext.is_yes(arg) else "tr.synod_active.not"),
	}, OWNER)
	r.triggers.register("is_synod_voter", {"scopes": CH, "doc": "Голосует на Соборе своей веры (defines.synod.voter, вес больше нуля)", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var h: Variant = head_of.call(ctx, c) if c != null else null
		var yes: bool = h != null and Synod.is_voter(ctx.game, c, h) and Synod.vote_weight(ctx.game, c, h) > 0.0
		return yes == ScriptContext.is_yes(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_synod_voter" if ScriptContext.is_yes(arg) else "tr.is_synod_voter.not"),
	}, OWNER)
	r.triggers.register("synod_swayed", {"scopes": CH, "doc": "Голос уже склонён на созванном Соборе", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var a: Variant = Synod.active_for(ctx.game, c) if c != null else null
		return (a != null and a.sway.has(c.id)) == ScriptContext.is_yes(arg),
	}, OWNER)
	r.triggers.register("synod_question", {"scopes": CH, "doc": "Вопрос созванного Собора: synod_question: anathema", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var a: Variant = Synod.active_for(ctx.game, c) if c != null else null
		return a != null and str(a.question) == str(arg),
	}, OWNER)
	r.triggers.register("of_synod_target_faith", {"scopes": CH, "doc": "Персонаж исповедует культ — цель вопроса Собора (анафема, примирение)", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var f := Synod.target_faith_now(ctx.game)
		return (c != null and f != "" and str(c.faith) == f) == ScriptContext.is_yes(arg),
	}, OWNER)
	r.triggers.register("has_synod_decree", {"scopes": CH, "doc": "Действует указ Собора веры персонажа: has_synod_decree: <вопрос>", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return c != null and Synod.has_decree(ctx.game, c, str(arg)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.has_synod_decree", {"decree": Synod.question_name(ctx.game, str(arg))}),
	}, OWNER)
	r.values.register("synod_vote_weight", {"scopes": CH, "doc": "Вес голоса на Соборе (0 — нет голоса)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		var h: Variant = head_of.call(ctx, c) if c != null else null
		return Synod.vote_weight(ctx.game, c, h) if h != null and Synod.is_voter(ctx.game, c, h) else 0.0
	}, OWNER)
	r.values.register("synod_preference", {"scopes": CH, "doc": "Насколько персонаж за вопрос созванного Собора (больше нуля — за)", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		var a: Variant = Synod.active_for(ctx.game, c) if c != null else null
		var h: Variant = Temple.head_of(ctx.game, c) if c != null else null
		return Synod.preference(ctx.game, c, h, a) if a != null and h != null else 0.0
	}, OWNER)
	r.effects.register("synod_vote", {"scopes": CH, "doc": "Голос игрока на созванном Соборе: synod_vote: for | against | abstain", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var a: Variant = Synod.active_for(ctx.game, c) if c != null else null
		if a != null:
			a.votes[c.id] = {"for": 1, "against": -1}.get(str(arg), 0)
			a.erase("preview"),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.synod_vote." + str(arg)),
	}, OWNER)
	r.effects.register("synod_declare", {"scopes": CH, "doc": "Объявить позицию на созванном Соборе — вассалы склонятся к ней: synod_declare: for | against | none", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var a: Variant = Synod.active_for(ctx.game, c) if c != null else null
		if a == null:
			return
		if not a.has("stances"):
			a["stances"] = {}
		if str(arg) == "for" or str(arg) == "against":
			a.stances[c.id] = 1 if str(arg) == "for" else -1
		else:
			a.stances.erase(c.id)
		a.erase("preview"),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("fx.synod_declare." + str(arg)),
	}, OWNER)
	r.triggers.register("synod_declared", {"scopes": CH, "doc": "Позиция персонажа на созванном Соборе: synod_declared: for | against | yes | no", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var a: Variant = Synod.active_for(ctx.game, c) if c != null else null
		var st: Variant = a.get("stances", {}).get(c.id) if a != null else null
		match str(arg):
			"for": return st == 1
			"against": return st == -1
			"no": return st == null
		return st != null,
	}, OWNER)
	r.values.register("synod_vassal_voters", {"scopes": CH, "doc": "Сколько вассалов персонажа голосуют на созванном Соборе", "get": func(ctx, s, _a):
		var c: Variant = ch.call(ctx, s)
		var h: Variant = Temple.head_of(ctx.game, c) if c != null else null
		if h == null:
			return 0.0
		var n := 0
		for v in ctx.game.vassals_of(c.id):
			if Synod.is_voter(ctx.game, v, h) and Synod.vote_weight(ctx.game, v, h) > 0.0:
				n += 1
		return float(n)
	}, OWNER)
	r.effects.register("synod_sway", {"scopes": CH, "doc": "Склонить голос персонажа на созванном Соборе: synod_sway: for | against", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var a: Variant = Synod.active_for(ctx.game, c) if c != null else null
		if a != null:
			a.sway[c.id] = 1 if str(arg) == "for" else -1
			a.erase("preview"),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.synod_sway." + str(arg), {"who": ctx.game.scope_name(s)}),
	}, OWNER)
	r.effects.register("call_synod", {"doc": "Глава веры созывает Собор: call_synod: yes или <вопрос> (root — глава веры)", "apply": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		if c == null:
			return
		for ht in Synod.head_titles(ctx.game):
			if c.titles.has(ht) and Synod.state_of(ctx.game, ht).active == null:
				Synod.call_synod(ctx.game, ht, c, "" if ScriptContext.is_yes(arg) else str(arg)),
	}, OWNER)

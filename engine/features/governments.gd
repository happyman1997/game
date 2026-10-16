class_name Governments
extends EngineFeature
## Типы правления. Правление правителя: c.vars.government → поле government
## основного титула (titles) → поле government культуры → правление с
## default: yes.
##
##   governments: { <id>: {
##     icon, order, default,
##     succession: <закон наследования> — правитель не выбирает закон сам;
##     ruler_modifiers: {...}   — модификаторы правителю;
##     county_modifiers: {...}  — графствам его домена;
##     celibate: yes            — правитель не вступает в брак;
##     term_years: N            — правитель избирается на срок: по истечении
##                                срока новые выборы по закону succession
##                                (прежний правитель остаётся при дворе);
##     play_family: yes         — игрок, потерявший власть или умерший,
##                                продолжает играть за свой род, а не за
##                                нового правителя;
##     war_assembly: доля       — наступательную войну одобряет сход: нужна
##                                эта доля графств домена с мнением не ниже 0;
##     members: { trait, per_year: [от, до], age: [от, до], cultures: [...],
##                skills: {...}, max } — ежегодно ко двору приходят новые
##                члены (добровольцы ордена) с чертой trait;
##     war_cbs: [...]           — наступательные войны только по этим поводам;
##     ai_war_mult: множитель шанса ИИ начать войну } }
## Черта с celibate: yes запрещает брак её носителю; черты с race: <id> —
## браки только внутри своей расы (без поля — люди).
## Алгоритмы наследования (succession_laws.algorithm):
##   elected_member — избирают из членов (черта members.trait) при дворе и
##     среди вассалов: по навыкам (закон election_skills, по умолчанию
##     военное дело ×2, доблесть, учёность) и престижу;
##   best_master — правит лучший мастер своей культуры в державе
##     (законы: master_skill, second_skill);
##   republic_election — сход: каждое графство домена голосует за одного из
##     глав видных родов (членов державы без земли и вассалов), по престижу,
##     дипломатии и агитации (c.vars.campaign).
## Хуки: government.election — {ruler, winner, previous, term: bool}.

const OWNER := "core/governments"


func _init() -> void:
	id = "governments"
	doc = "Типы правления: феодалы, рыцарский орден, народная республика, совет мастеров"


static func default_id(game: Game) -> String:
	var hit: Variant = game.engine.cache.get("gov:default")
	if hit == null:
		hit = ""
		for d in game.content.all("governments"):
			if d.get("default", false):
				hit = str(d.id)
				break
		game.engine.cache["gov:default"] = hit
	return hit


## Правление персонажа (id).
static func of(game: Game, c: Variant) -> String:
	if not (c is Dictionary):
		return default_id(game)
	var v: Variant = c.vars.get("government")
	if v != null:
		return str(v)
	if not c.titles.is_empty():
		var td: Variant = game.content.get_def("titles", c.titles[0])
		if td != null and td.get("government") != null:
			return str(td.government)
	var cul: Variant = game.content.get_def("cultures", c.culture)
	if cul != null and cul.get("government") != null:
		return str(cul.government)
	return default_id(game)


static func def_of(game: Game, c: Variant) -> Dictionary:
	var d: Variant = game.content.get_def("governments", of(game, c))
	return d if d is Dictionary else {}


static func rule(game: Game, c: Variant, key: String, default: Variant = null) -> Variant:
	return def_of(game, c).get(key, default)


static func is_celibate(game: Game, c: Dictionary) -> bool:
	for t in c.traits:
		var td: Variant = game.content.get_def("traits", t)
		if td != null and td.get("celibate", false):
			return true
	return not c.titles.is_empty() and ScriptContext.is_yes(rule(game, c, "celibate", false))


static func race_of(game: Game, c: Dictionary) -> String:
	for t in c.traits:
		var td: Variant = game.content.get_def("traits", t)
		if td != null and td.get("race") != null:
			return str(td.race)
	return ""


# ------------------------------------------------------------ выборы

## Члены державы правителя: придворные и вассалы (взрослые, живые, на свободе).
static func _members(game: Game, ruler: Dictionary) -> Array:
	var out := []
	for x in game.courtiers_of(ruler.id) + game.vassals_of(ruler.id):
		if Chars.is_alive(x) and Chars.is_adult(game, x) and x.get("prison") == null:
			out.append(x)
	return out


static func _order_heirs(game: Game, ruler: Dictionary, law: Dictionary) -> Array:
	var mdef: Dictionary = def_of(game, ruler).get("members", {})
	var tr := str(mdef.get("trait", ""))
	var cands := _members(game, ruler).filter(func(x): return tr == "" or x.traits.has(tr))
	if cands.is_empty():
		var v: Variant = recruit(game, ruler)
		if v != null:
			cands = [v]
	var w: Dictionary = law.get("election_skills") if law.get("election_skills") is Dictionary else {"martial": 2.0, "prowess": 1.0, "learning": 1.0}
	Data.sort_by(cands, func(x):
		var score := float(x.prestige) / 100.0
		for k in w:
			score += Stats.skill(game, x, str(k)) * Data.num(w[k])
		return score, true)
	return cands.map(func(x): return x.id)


static func _master_heirs(game: Game, ruler: Dictionary, law: Dictionary) -> Array:
	var skill := str(law.get("master_skill", "stewardship"))
	var second := str(law.get("second_skill", "learning"))
	var cands := _members(game, ruler).filter(func(x): return x.culture == ruler.culture)
	for id in ruler.children:
		var chd: Variant = game.ch(id)
		if Chars.is_alive(chd) and Chars.is_adult(game, chd) and not cands.has(chd):
			cands.append(chd)
	Data.sort_by(cands, func(x): return Stats.skill(game, x, skill) + Stats.skill(game, x, second) * 0.5, true)
	var ids: Array = cands.map(func(x): return x.id)
	for id in Succession.blood_line(game, ruler, law.get("gender")):
		if not ids.has(id):
			ids.append(id)
	return ids


## Главы видных родов республики: по одному взрослому от каждой династии
## среди членов державы (и род самого правителя).
static func republic_candidates(game: Game, ruler: Dictionary) -> Array:
	var by_dyn := {}
	var pool := _members(game, ruler)
	if Chars.is_alive(ruler):
		pool.append(ruler)
	for x in pool:
		if x.dynasty == null or x.female:
			continue
		var cur: Variant = by_dyn.get(x.dynasty)
		if cur == null or x.birth < cur.birth:
			by_dyn[x.dynasty] = x
	return by_dyn.values()


## Голоса графств: {id кандидата: голоса}.
static func republic_votes(game: Game, ruler: Dictionary, cands: Array, noise: bool = true) -> Dictionary:
	var votes := {}
	for c in cands:
		votes[c.id] = 0
	if cands.is_empty():
		return votes
	for cid in Titles.domain_counties(game, ruler):
		var best: Variant = null
		var best_s := -INF
		for c in cands:
			var s := float(c.prestige) / 50.0 + Stats.skill(game, c, "diplomacy") + Data.num(c.vars.get("campaign"))
			# свой край: графство, где у рода земля или откуда он родом
			if c.capital == cid:
				s += 5.0
			# сход знает действующего вожака: и хорошее, и плохое
			if c.id == ruler.id and game.engine.has_feature("populace"):
				s += Populace.opinion(game, cid) / 10.0
			if noise:
				s += game.rng.range_float(0.0, 4.0)
			if s > best_s:
				best_s = s
				best = c
		votes[best.id] = int(votes[best.id]) + 1
	return votes


static func _republic_heirs(game: Game, ruler: Dictionary, law: Dictionary) -> Array:
	var cands := republic_candidates(game, ruler).filter(func(x): return x.id != ruler.id or Chars.is_alive(ruler))
	if ruler.death != null:
		cands = cands.filter(func(x): return x.id != ruler.id)
	var votes := republic_votes(game, ruler, cands)
	Data.sort_by(cands, func(x): return float(votes.get(x.id, 0)) + float(x.prestige) / 10000.0, true)
	var ids: Array = cands.map(func(x): return x.id)
	for id in Succession.blood_line(game, ruler, law.get("gender")):
		if not ids.has(id):
			ids.append(id)
	return ids


## Новый член (доброволец ордена) при дворе правителя.
static func recruit(game: Game, ruler: Dictionary) -> Variant:
	var mdef: Dictionary = def_of(game, ruler).get("members", {})
	if mdef.is_empty():
		return null
	var cultures: Array = Data.as_array(mdef.get("cultures"))
	var cul: String = str(game.rng.pick(cultures)) if not cultures.is_empty() else ruler.culture
	if not game.content.has("cultures", cul):
		cul = ruler.culture
	var skills := {}
	var sk: Variant = mdef.get("skills")
	if sk is Dictionary:
		for s in sk:
			var r: Variant = sk[s]
			skills[s] = roundi(game.rng.range_float(Data.num(r[0]), Data.num(r[1]))) if r is Array else roundi(Data.num(r))
	var age: Variant = mdef.get("age")
	var c := Chars.create_character(game, {
		"culture": cul, "faith": ruler.faith, "female": false,
		"age": game.rng.range_float(Data.num(age[0]), Data.num(age[1])) if age is Array else 25.0,
		"dynasty": null, "liege": ruler.id, "skills": skills,
		"traits": [mdef.get("trait")] if mdef.get("trait") != null else [],
	})
	game.emit("government.member_joined", {"ruler": ruler, "character": c})
	return c


## Передать державу избранному (выборы по сроку): все титулы правителя —
## победителю, прежний правитель остаётся при дворе нового.
static func hand_over(game: Game, ruler: Dictionary, winner: Dictionary) -> void:
	if winner.id == ruler.id:
		ruler.vars["term_start"] = game.date
		return
	var gov := of(game, ruler)
	var titles: Array = ruler.titles.duplicate()
	Data.sort_by(titles, func(t): return Titles.tier_of(game, t), true)
	var liege: Variant = ruler.liege
	Chars.set_liege(game, winner, liege)
	if ruler.vars.has("government"):
		winner.vars["government"] = gov
	for t in titles:
		Titles.transfer_title(game, t, winner.id, winner.id)
	for v in game.vassals_of(ruler.id):
		Chars.set_liege(game, v, winner.id)
	for ct in game.courtiers_of(ruler.id):
		Chars.set_liege(game, ct, winner.id)
	Chars.set_liege(game, ruler, winner.id)
	winner.vars["term_start"] = game.date
	ruler.vars.erase("term_start")
	game.mark_dirty()


## Выборы по сроку (term_years).
static func term_election(game: Game, ruler: Dictionary) -> void:
	var law: Variant = Succession.law_of(game, ruler)
	var heirs := Succession.heirs_of(game, ruler)
	var winner: Variant = game.ch(heirs[0]) if not heirs.is_empty() else null
	if winner == null:
		ruler.vars["term_start"] = game.date
		return
	game.emit("government.election", {"ruler": ruler, "winner": winner, "previous": ruler, "term": true})
	var involves := [ruler.id, winner.id]
	if winner.id == ruler.id:
		game.message(game.loc.t("msg.reelected", {"who": game.scope_name({"type": "character", "id": ruler.id})}), "good" if game.is_player(ruler.id) else "info",
			{"type": "character", "id": ruler.id}, involves)
	else:
		game.message(game.loc.t("msg.elected", {"who": game.scope_name({"type": "character", "id": winner.id}), "prev": game.scope_name({"type": "character", "id": ruler.id})}),
			"bad" if game.is_player(ruler.id) else "info", {"type": "character", "id": winner.id}, involves)
	hand_over(game, ruler, winner)
	for c in republic_candidates(game, winner):
		c.vars.erase("campaign")
	if law == null:
		return


static func monthly(game: Game) -> void:
	var by_gov := {}
	for d in game.content.all("governments"):
		if d.get("term_years") != null or d.get("members") is Dictionary:
			by_gov[d.id] = d
	if by_gov.is_empty():
		return
	var yearly: bool = GameDate.parts(game.date).m == 1
	for c in game.rulers().duplicate():
		if c.death != null or c.liege != null and Governments.of(game, game.ch(c.liege)) == Governments.of(game, c):
			continue
		var gid := of(game, c)
		var d: Variant = by_gov.get(gid)
		if d == null:
			continue
		if d.get("term_years") != null:
			if not c.vars.has("term_start"):
				c.vars["term_start"] = game.date
			elif game.date - int(c.vars.term_start) >= roundi(Data.num(d.term_years) * GameDate.DAYS_PER_YEAR):
				term_election(game, c)
				continue
		# ИИ-кандидаты агитируют перед выборами: тратят золото на голоса
		if yearly and d.get("term_years") != null:
			for cand in republic_candidates(game, c):
				if not game.ai_controls(cand.id) or float(cand.gold) < 60.0:
					continue
				var will := 0.25 + (0.25 if cand.traits.has("ambitious") else 0.0) - (0.15 if cand.traits.has("content") else 0.0)
				if game.rng.chance(will):
					cand.gold -= 40.0
					cand.vars["campaign"] = Data.num(cand.vars.get("campaign")) + 2.0
		if yearly and d.get("members") is Dictionary:
			var m: Dictionary = d.members
			var tr := str(m.get("trait", ""))
			var have := Data.count(game.courtiers_of(c.id), func(x): return Chars.is_alive(x) and (tr == "" or x.traits.has(tr)))
			if have < int(Data.num(m.get("max"), 12)):
				var r: Variant = m.get("per_year", [1, 1])
				var n := game.rng.range_int(int(Data.num(r[0])), int(Data.num(r[1]))) if r is Array else int(Data.num(r))
				for i in n:
					recruit(game, c)


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("governments", {"id": "governments", "order": 57, "on_month": Governments.monthly}, OWNER)
	engine.succession_algorithms.register("elected_member", {"label": {"ru": "Выборы среди братьев", "en": "Elected by the brethren"}, "heirs": Governments._order_heirs}, OWNER)
	engine.succession_algorithms.register("best_master", {"label": {"ru": "Лучший мастер", "en": "The best master"}, "heirs": Governments._master_heirs}, OWNER)
	engine.succession_algorithms.register("republic_election", {"label": {"ru": "Выборы схода", "en": "Elected by the assembly"}, "heirs": Governments._republic_heirs}, OWNER)
	engine.modifier_providers.register("governments", {"fn": func(game: Game, c: Dictionary) -> Variant:
		if c.titles.is_empty():
			return null
		var d := Governments.def_of(game, c)
		if not (d.get("ruler_modifiers") is Dictionary):
			return null
		var gid: String = d.id
		return [{"label": func(): return game.name_of("governments", gid), "modifiers": d.ruler_modifiers}]
	}, OWNER)
	engine.province_modifier_providers.register("governments", {"fn": func(game: Game, prov_id: String) -> Variant:
		var h: Variant = Titles.county_holder(game, prov_id)
		if h == null:
			return null
		var d := Governments.def_of(game, h)
		return d.get("county_modifiers") if d.get("county_modifiers") is Dictionary else null
	}, OWNER)
	var H := engine.hooks
	# закон наследования задаёт правление
	H.on("succession.law", func(p):
		var law: Variant = Governments.rule(p.game, p.character, "succession")
		return law
	, 0, OWNER)
	# безбрачие и браки внутри своей расы
	H.on("marriage.allowed", func(p):
		var game: Game = p.game
		if Governments.is_celibate(game, p.a) or Governments.is_celibate(game, p.b):
			return false
		return Governments.race_of(game, p.a) == Governments.race_of(game, p.b)
	, 0, OWNER)
	# сход одобряет наступательную войну
	H.on("war.allowed", func(p): return Governments.assembly_allows_war(p.game, p.attacker), 0, OWNER)
	# правление с war_cbs воюет только по этим поводам
	H.on("war.cb_allowed", func(p):
		var cbs: Variant = Governments.rule(p.game, p.attacker, "war_cbs")
		return cbs == null or Data.as_array(cbs).has(p.cb)
	, 0, OWNER)
	H.on("war.before_declare", func(p):
		var game: Game = p.game
		var opts: Dictionary = p.get("options", {})
		if opts.get("free", false):
			return true
		return Governments.assembly_allows_war(game, p.attacker)
	, 0, OWNER)
	# срок вожака из истории: characters.<id>.term_start: "1061.5.1"
	H.on("game.setup", func(p):
		var game: Game = p.game
		for d in game.content.all("characters"):
			var ch: Variant = game.state.characters.get(d.id)
			if d.get("term_start") != null and ch != null:
				ch.vars["term_start"] = GameDate.parse(str(d.term_start))
	, 0, OWNER)
	# игрок в правлении с play_family продолжает за свой род
	H.on("player.next_character", func(p):
		var game: Game = p.game
		var c: Dictionary = p.character
		if not ScriptContext.is_yes(Governments.rule(game, c, "play_family", false)) and not ScriptContext.is_yes(c.vars.get("play_family", false)):
			return null
		for id in Succession.blood_line(game, c, "male_preference"):
			var x: Variant = game.ch(id)
			if Chars.is_alive(x) and x.dynasty == c.dynasty:
				x.vars["play_family"] = true
				return x.id
		return null
	, 0, OWNER)
	engine.content_validators.register("governments", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("governments"):
			var w: String = "governments/" + d.id
			if d.get("succession") != null:
				v.ref("succession_laws", d.succession, w)
			var m: Variant = d.get("members")
			if m is Dictionary and m.get("trait") != null:
				v.ref("traits", m.trait, w + " members")
		for t in e.content.all("titles"):
			if t.get("government") != null:
				v.ref("governments", t.government, "titles/" + t.id)
		for c in e.content.all("cultures"):
			if c.get("government") != null:
				v.ref("governments", c.government, "cultures/" + c.id)
	, OWNER)


## Доля графств домена, довольных правителем (мнение не ниже 0).
static func assembly_support(game: Game, c: Dictionary) -> float:
	var dom := Titles.domain_counties(game, c)
	if dom.is_empty() or not game.engine.has_feature("populace"):
		return 1.0
	return float(Data.count(dom, func(cid): return Populace.opinion(game, cid) >= 0.0)) / dom.size()


static func assembly_allows_war(game: Game, c: Dictionary) -> bool:
	var need: Variant = rule(game, c, "war_assembly")
	return need == null or assembly_support(game, c) >= Data.num(need)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	const CH := ["character"]
	r.triggers.register("government", {"scopes": CH, "doc": "Правление персонажа (id из governments или список)", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		return c != null and Data.as_array(arg).has(Governments.of(ctx.game, c)),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.government", {"value": " / ".join(Data.as_array(arg).map(func(x): return ctx.game.name_of("governments", x)))}),
	}, OWNER)
	r.triggers.register("assembly_supports_war", {"scopes": CH, "doc": "Сход одобряет наступательную войну (или правление его не требует)", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		return c != null and Governments.assembly_allows_war(ctx.game, c) == ScriptContext.is_yes(arg)
	}, OWNER)
	r.triggers.register("is_celibate", {"scopes": CH, "doc": "Не может вступать в брак (обет или правление)", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		return c != null and Governments.is_celibate(ctx.game, c) == ScriptContext.is_yes(arg)
	}, OWNER)
	r.values.register("years_in_office", {"scopes": CH, "doc": "Лет у власти по сроку (для правлений с term_years)", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return (ctx.game.date - int(c.vars.term_start)) / float(GameDate.DAYS_PER_YEAR) if c != null and c.vars.has("term_start") else 0.0
	}, OWNER)
	r.effects.register("set_government", {"scopes": CH, "doc": "Сменить правление персонажа: set_government: <id>", "apply": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c != null and ctx.game.content.has("governments", str(arg)):
			c.vars["government"] = str(arg)
			ctx.game.stat_cache.erase(c.id),
		"describe": func(ctx, s, arg): return ctx.game.loc.t("fx.set_government", {"who": ctx.game.scope_name(s), "value": ctx.game.name_of("governments", str(arg))}),
	}, OWNER)
	r.effects.register("add_campaign", {"scopes": CH, "doc": "Агитация перед выборами: add_campaign: N (голосов сходу прибавится по N на графство)", "apply": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c != null:
			c.vars["campaign"] = Data.num(c.vars.get("campaign")) + Interp.eval_value(ctx, s, arg),
	}, OWNER)

class_name Retinue
extends EngineFeature
## Дружина: именные отряды с опытом, капитанами и летописью.
##
## У отряда (c.regiments[]) — имя (части из regiment_names), опыт и ранг
## (новобранцы → бывалые → ветераны → прославленные, defines.regiments.ranks),
## счёт боёв, побед и сражённых, летопись последних боёв и капитан — живой
## человек из двора (рыцарь или придворный). Опыт — от того, что отряд делал
## в бою (сражённые враги, победа); пополнение разбавляет опыт. Ранг даёт
## силу и дух в бою, прославленный отряд дороже и тянет добровольцев. Капитан
## прибавляет отряду силы (доблесть) и духа (военное дело) и может пасть в бою.
## Дружину кормят золотом: в долгах дольше unpaid_months — уходит по отряду
## в месяц (ветераны с капитаном — вольной ротой). После смерти господина
## ветераны идут за наследником, если капитан к нему расположен, иначе
## становятся вольной ротой (Mercenaries).
##
## Поля отряда: name: [adj, noun], xp, battles, wins, kills, chronicle:
## [{date, location, won, kills, lost, rank?}], captain, since, merc (рота).

const OWNER := "core/retinue"


func _init() -> void:
	id = "retinue"
	doc = "Дружина: именные отряды с опытом, капитанами и летописью"


static func _n(game: Game, key: String, fallback: float) -> float:
	return game.def_num("regiments." + key, fallback)


# ------------------------------------------------------------ имена

static func _parts(game: Game) -> Dictionary:
	var hit: Variant = game.engine.cache.get("retinue:names")
	if hit == null:
		var adj := []
		var nouns := []
		for d in game.content.all("regiment_names"):
			if d.get("part") == "adj":
				adj.append(str(d.id))
			elif d.get("part") == "noun":
				nouns.append(d)
		adj.sort()
		nouns.sort_custom(func(a, b): return str(a.id) < str(b.id))
		hit = {"adj": adj, "nouns": nouns}
		game.engine.cache["retinue:names"] = hit
	return hit


static func _hash(s: String) -> int:
	var h := 0
	for i in s.length():
		h = (h * 31 + s.unicode_at(i)) & 0x7FFFFFFF
	return h


## Имя для отряда: от его id (общий генератор случайностей не трогаем), не
## повторяя имён отрядов того же хозяина.
static func gen_name(game: Game, r: Dictionary, taken: Array = []) -> Array:
	var p := _parts(game)
	var cat := ""
	var def: Variant = game.content.get_def("regiment_types", str(r.get("type", "")))
	if def != null:
		cat = str(def.get("category", ""))
	var nouns: Array = p.nouns.filter(func(d): return d.get("categories") == null or Data.as_array(d.categories).has(cat))
	if nouns.is_empty():
		nouns = p.nouns
	if p.adj.is_empty() or nouns.is_empty():
		return []
	var h := _hash(str(r.get("id", "")))
	var used := {}
	for t in taken:
		used[str(t)] = true
	var best: Array = []
	for i in 24:
		var x := (h + i * 7919) & 0x7FFFFFFF
		var pair := [p.adj[x % p.adj.size()], str(nouns[(x / p.adj.size()) % nouns.size()].id)]
		best = pair
		if not used.has(str(pair)):
			break
	return best


## Имя отряда (или вида войск, если имён нет).
static func name_of(game: Game, r: Variant) -> String:
	if not (r is Dictionary):
		return ""
	var parts: Variant = r.get("name")
	if not (parts is Array) or parts.size() < 2:
		parts = gen_name(game, r)
	if parts is Array and parts.size() >= 2:
		return game.name_of("regiment_names", parts[0]) + " " + game.name_of("regiment_names", parts[1])
	return game.name_of("regiment_types", r.get("type"))


static func name_parts(game: Game, r: Dictionary) -> Array:
	var parts: Variant = r.get("name")
	return parts if parts is Array and parts.size() >= 2 else gen_name(game, r)


static func name_from_parts(game: Game, parts: Variant, type: Variant = null) -> String:
	if parts is Array and parts.size() >= 2:
		return game.name_of("regiment_names", parts[0]) + " " + game.name_of("regiment_names", parts[1])
	return game.name_of("regiment_types", type) if type != null else ""


# ------------------------------------------------------------ ранги

static func ranks(game: Game) -> Array:
	var r: Variant = game.def_val("regiments.ranks", [])
	return r if r is Array and not r.is_empty() else [{"id": "recruits", "xp": 0}]


static func rank_index(game: Game, xp: float) -> int:
	var rs := ranks(game)
	var i := 0
	for k in rs.size():
		if xp >= Data.num(rs[k].get("xp")):
			i = k
	return i


static func rank_of(game: Game, r: Dictionary) -> Dictionary:
	return ranks(game)[rank_index(game, float(r.get("xp", 0.0)))]


## Доля пути к следующему рангу (1 — высший).
static func rank_progress(game: Game, r: Dictionary) -> float:
	var rs := ranks(game)
	var xp := float(r.get("xp", 0.0))
	var i := rank_index(game, xp)
	if i >= rs.size() - 1:
		return 1.0
	var a := Data.num(rs[i].get("xp"))
	var b := Data.num(rs[i + 1].get("xp"))
	return clampf((xp - a) / maxf(1.0, b - a), 0.0, 1.0)


# ------------------------------------------------------------ отряды

## Запись отряда у хозяина по id (или null).
static func record(owner: Variant, reg_id: Variant) -> Variant:
	if not (owner is Dictionary):
		return null
	for r in Regiments.regs_of(owner):
		if r.id == reg_id:
			return r
	return null


## Отряд армии по ключу войск ядра («армия:отряд»): [хозяин, запись].
static func by_key(game: Game, key: String) -> Array:
	var i := key.find(":")
	if i < 0:
		return [null, null]
	var a: Variant = game.state.armies.get(key.substr(0, i))
	if a == null:
		return [null, null]
	var owner: Variant = game.ch(a.owner)
	var rid := key.substr(i + 1)
	var rec: Variant = record(owner, rid)
	if rec == null:
		for x in Data.as_array(a.get("regiments")):
			if str(x.id) == rid:
				rec = x
	return [owner, rec]


# ------------------------------------------------------------ капитаны

static func captain_score(game: Game, c: Dictionary) -> float:
	return float(Stats.skill(game, c, "prowess") + Stats.skill(game, c, "martial"))


## Капитан отряда (жив, взрослый, не в темнице, всё ещё при дворе) или null.
static func captain_of(game: Game, owner: Variant, r: Dictionary) -> Variant:
	var c: Variant = game.ch(r.get("captain"))
	if c == null or not Chars.is_alive(c) or c.get("prison") != null:
		return null
	# капитан наёмной роты служит роте, а не двору
	if r.get("merc") != null:
		return c
	if owner is Dictionary and c.liege != owner.id and c.id != owner.id:
		return null
	return c


## Кого можно поставить капитаном: рыцари и взрослые придворные хозяина, не
## капитаны других его отрядов.
static func captain_candidates(game: Game, owner: Dictionary, reg_id: Variant = null) -> Array:
	var busy := {}
	for r in Regiments.regs_of(owner):
		if r.id != reg_id and r.get("captain") != null:
			busy[r.captain] = true
	var pool: Array = game.courtiers_of(owner.id)
	if game.engine.has_feature("knights"):
		pool = Knights.knights_of(game, owner) + pool
	var out := []
	var seen := {}
	for x in pool:
		if x == null or seen.has(x.id) or busy.has(x.id) or x.id == owner.id:
			continue
		seen[x.id] = true
		if Chars.is_alive(x) and Chars.is_adult(game, x) and x.get("prison") == null and x.flags.get("merc_captain") == null:
			out.append(x)
	return out


static func set_captain(game: Game, owner: Dictionary, reg_id: Variant, cid: Variant) -> bool:
	var r: Variant = record(owner, reg_id)
	if r == null or r.get("merc") != null:
		return false
	if cid == null:
		r.captain = null
	elif captain_candidates(game, owner, reg_id).any(func(x): return x.id == cid):
		r["captain"] = cid
		game.emit("regiment.captain", {"character": owner, "regiment": r, "captain": cid})
	else:
		return false
	game.notify("army")
	return true


## Сила и дух отряда в бою: ранг и капитан. {quality (×), morale (+)}.
static func unit_mods(game: Game, owner: Variant, r: Dictionary) -> Dictionary:
	var rk := rank_of(game, r)
	var q := Data.num(rk.get("quality"), 1.0)
	var m := Data.num(rk.get("morale"))
	var cap: Variant = captain_of(game, owner, r)
	if cap != null:
		q *= 1.0 + minf(_n(game, "captain_quality_max", 0.25), Stats.skill(game, cap, "prowess") * _n(game, "captain_prowess", 0.012))
		m += Stats.skill(game, cap, "martial") * _n(game, "captain_martial", 0.6)
	return {"quality": q, "morale": m}


# ------------------------------------------------------------ после боя

static func _chronicle(game: Game, r: Dictionary, entry: Dictionary) -> void:
	var ch: Array = Data.as_array(r.get("chronicle")).duplicate()
	ch.append(entry)
	var mx := int(_n(game, "chronicle_max", 10))
	if ch.size() > mx:
		ch = ch.slice(ch.size() - mx)
	r["chronicle"] = ch


## Опыт, летопись и судьбы капитанов после боя (по отчёту ядра).
static func after_battle(game: Game, report: Dictionary, loc: String) -> void:
	var refused: bool = Data.as_array(report.events).any(func(e): return e.kind == "refused")
	var mult := _n(game, "xp_refused", 0.4) if refused or int(report.days) == 0 else 1.0
	var xp_max := _n(game, "xp_max", 800)
	for side in 2:
		if side >= report.units.size():
			continue
		var won := int(report.winner) == side
		for u in report.units[side]:
			if u.get("reg") == null:
				continue
			var found := by_key(game, str(u.key))
			var owner: Variant = found[0]
			var r: Variant = found[1]
			if r == null:
				continue
			var men := maxf(1.0, float(u.men))
			var kills := float(u.get("kills", 0))
			var lost := int(u.men) - int(u.left)
			var before := rank_index(game, float(r.get("xp", 0.0)))
			var gain := (_n(game, "xp_battle", 12) + (_n(game, "xp_win", 18) if won else 0.0) + _n(game, "xp_kills", 60) * kills / men) * mult
			r["xp"] = minf(xp_max, float(r.get("xp", 0.0)) + gain)
			r["battles"] = int(r.get("battles", 0)) + 1
			r["wins"] = int(r.get("wins", 0)) + (1 if won else 0)
			r["kills"] = int(r.get("kills", 0)) + roundi(kills)
			u["xp_gain"] = roundf(gain)
			var entry := {"date": game.date, "location": loc, "won": won, "kills": roundi(kills), "lost": lost}
			var after := rank_index(game, float(r.xp))
			if after > before:
				var rk: String = str(ranks(game)[after].id)
				entry["rank"] = rk
				report.events.append({"day": int(report.days), "kind": "rank_up", "side": side, "name": name_parts(game, r), "b": rk})
				if owner != null and game.is_player(owner.id):
					game.message(game.loc.t("msg.regiment_rank_up", {"name": name_of(game, r), "rank": game.name_of("regiment_ranks", rk)}), "good")
			_chronicle(game, r, entry)
			# капитан в гуще: гибель — по потерям отряда
			var cap: Variant = captain_of(game, owner, r)
			if cap != null and lost > 0:
				var chance := _n(game, "captain_death", 0.15) * float(lost) / men * (1.0 if won else 2.0) * Military._death_mult(game, cap)
				if game.rng.chance(minf(0.5, chance)):
					report.events.append({"day": int(report.days), "kind": "captain_fell", "side": side, "a": cap.id, "name": name_parts(game, r)})
					Succession.kill_character(game, cap, "battle", null)
					r.captain = null


# ------------------------------------------------------------ месяц

## Пополнение: новобранцы разбавляют опыт (reinforce_keep — сколько они
## перенимают). Прославленных пополнять легче (reinforce_mult ранга).
static func reinforce_mult(game: Game, r: Dictionary) -> float:
	return Data.num(rank_of(game, r).get("reinforce_mult"), 1.0)


static func on_reinforced(game: Game, r: Dictionary, before: int) -> void:
	var after := int(r.size)
	if after <= before or after <= 0:
		return
	var keep := _n(game, "reinforce_keep", 0.3)
	r["xp"] = float(r.get("xp", 0.0)) * (float(before) + float(after - before) * keep) / float(after)


## Жалованье отряда: прославленные дороже.
static func upkeep_mult(game: Game, r: Dictionary) -> float:
	return Data.num(rank_of(game, r).get("upkeep_mult"), 1.0)


static func monthly_char(game: Game, c: Dictionary) -> void:
	if c.titles.is_empty() or Regiments.regs_of(c).is_empty():
		return
	# долги: дружина ропщет и уходит
	if float(c.gold) < 0.0:
		var n := int(c.flags.get("retinue_unpaid", 0)) + 1
		c.flags["retinue_unpaid"] = n
		if n >= int(_n(game, "unpaid_months", 3)):
			_desert_unpaid(game, c)
	elif c.flags.has("retinue_unpaid"):
		c.flags.erase("retinue_unpaid")
	# ИИ ставит капитанов к отрядам без них
	if game.ai_controls(c.id) and c.get("prison") == null:
		var mn := _n(game, "ai_captain_min", 14)
		for r in Regiments.regs_of(c):
			if r.get("merc") != null or captain_of(game, c, r) != null:
				continue
			var best: Variant = null
			for x in captain_candidates(game, c, r.id):
				if captain_score(game, x) >= mn and (best == null or captain_score(game, x) > captain_score(game, best)):
					best = x
			if best == null:
				break
			r["captain"] = best.id


static func _desert_unpaid(game: Game, c: Dictionary) -> void:
	var own := Regiments.regs_of(c).filter(func(r): return r.get("merc") == null)
	if own.is_empty():
		return
	# уходят первыми те, кому есть куда: прославленные и бывалые
	own.sort_custom(func(a, b): return float(a.get("xp", 0.0)) > float(b.get("xp", 0.0)))
	var r: Dictionary = own[0]
	var nm := name_of(game, r)
	if not _go_free(game, c, r):
		Regiments.disband(game, c, r.id)
	if game.is_player(c.id):
		game.message(game.loc.t("msg.regiment_deserted", {"name": nm}), "bad")
	game.emit("regiment.deserted", {"character": c, "regiment": r, "why": "unpaid"})


## Ветераны с капитаном уходят вольной ротой (если есть наёмные роты).
static func _go_free(game: Game, c: Dictionary, r: Dictionary) -> bool:
	if not game.engine.has_feature("mercenaries") or rank_index(game, float(r.get("xp", 0.0))) < 2:
		return false
	var cap: Variant = captain_of(game, c, r)
	if cap == null:
		return false
	Regiments.disband(game, c, r.id)
	Mercenaries.found_free(game, r, cap, c)
	return true


## После смерти господина: ветераны, чей капитан не расположен к наследнику,
## уходят вольной ротой.
static func on_succession(game: Game, deceased: Dictionary, heir: Variant) -> void:
	if heir == null or heir.id == deceased.id:
		return
	var limit := _n(game, "desert_opinion", -20)
	for r in Regiments.regs_of(deceased).duplicate():
		if r.get("merc") != null or rank_index(game, float(r.get("xp", 0.0))) < 2:
			continue
		var cap: Variant = game.ch(r.get("captain"))
		if cap == null or not Chars.is_alive(cap) or cap.get("prison") != null:
			continue
		if Opinion.opinion(game, cap, heir) >= limit:
			continue
		var nm := name_of(game, r)
		if game.engine.has_feature("mercenaries"):
			deceased.regiments = Regiments.regs_of(deceased).filter(func(x): return x.id != r.id)
			Mercenaries.found_free(game, r, cap, deceased)
			if game.is_player(heir.id):
				game.message(game.loc.t("msg.regiment_left_heir", {"name": nm, "captain": game.scope_name({"type": "character", "id": cap.id})}), "bad")


func install(engine: GameEngine) -> void:
	engine.systems.register("retinue", {"id": "retinue", "order": 53, "on_character_month": Retinue.monthly_char}, OWNER)
	# новый отряд получает имя
	engine.hooks.on("regiment.recruited", func(p):
		var game: Game = p.game
		var r: Dictionary = p.regiment
		var c: Dictionary = p.character
		var taken := Regiments.regs_of(c).filter(func(x): return x.id != r.id and x.get("name") is Array).map(func(x): return str(x.name))
		r["name"] = Retinue.gen_name(game, r, taken)
		r["since"] = game.date
		if not r.has("xp"):
			r["xp"] = 0.0
	, 0, OWNER)
	# стартовые отряды уже бывали в деле
	engine.hooks.on("game.setup", func(p):
		var game: Game = p.game
		var rng := Rng.from_seed("retinue:%d" % int(game.rng.state.get("s", 0)))
		var span: Array = game.def_val("regiments.start_xp", [0, 200])
		for c in game.rulers():
			for r in Regiments.regs_of(c):
				r["xp"] = roundf(rng.range_float(Data.num(span[0]), Data.num(span[1]))) if span.size() >= 2 else 0.0
	, -5, OWNER)
	engine.hooks.on("battle", func(p):
		if p.get("report") is Dictionary:
			Retinue.after_battle(p.game, p.report, str(p.location))
	, -20, OWNER)
	# до того, как отряды перейдут к наследнику (Regiments, приоритет 0)
	engine.hooks.on("succession", func(p): Retinue.on_succession(p.game, p.deceased, p.game.ch(p.primary)), 5, OWNER)
	engine.content_validators.register("regiment_names", func(e: GameEngine, v: ScriptValidator):
		var adj := 0
		var nouns := 0
		for d in e.content.all("regiment_names"):
			if d.get("part") == "adj":
				adj += 1
			elif d.get("part") == "noun":
				nouns += 1
			else:
				v.issue("regiment_names/%s: part — adj или noun" % d.id)
		if not e.content.all("regiment_names").is_empty() and (adj == 0 or nouns == 0):
			v.issue("regiment_names: нужны и определения (adj), и существительные (noun)")
	, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	r.values.register("num_veteran_regiments", {"scopes": CH, "doc": "Отрядов ранга «ветераны» и выше", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		if c == null:
			return 0.0
		var n := 0
		for x in Regiments.regs_of(c):
			if Retinue.rank_index(ctx.game, float(x.get("xp", 0.0))) >= 2:
				n += 1
		return float(n),
	}, OWNER)
	r.triggers.register("is_regiment_captain", {"scopes": CH, "doc": "Капитан отряда (своего двора или наёмной роты)", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		if c == null:
			return not ScriptContext.is_yes(arg)
		var yes: bool = c.flags.get("merc_captain") != null
		if not yes and c.liege != null:
			for x in Regiments.regs_of(ctx.game.ch(c.liege)):
				if x.get("captain") == c.id:
					yes = true
					break
		return yes == ScriptContext.is_yes(arg),
	}, OWNER)

class_name Duels
extends EngineFeature
## Схватка — бой один на один: поединки чести, бой насмерть, учебный бой до
## первой крови, бой с врагом из данных (разбойник, зверь, чужой рыцарь).
##
## Бой идёт обменами. В каждом обмене бойцы выбирают стойку: натиск (attack),
## защита (guard) или хитрость (feint). Натиск сминает хитрость, хитрость
## обходит защиту, защита ловит натиск. Победивший в обмене бьёт: урон — от
## разницы силы стоек, проигравший может смягчить удар; два натиска — оба
## бьют; две защиты — кружат и переводят дух; две хитрости — ловчий жалит.
## Кто растерял стойкость — падает; можно сдаться раньше (позор); после
## defines.duels.max_rounds обменов верх за тем, у кого больше сил.
## Победитель решает судьбу павшего или сдавшегося: пощадить, ранить, убить.
##
## Профиль бойца: каждая стойка — доблесть × stance_base + duel_might /
## duel_guard / duel_guile (черты, вещи, перки, вживления); к хитрости — доля
## интриги. Стойкость — vigor_base + доблесть × vigor_per_prowess +
## duel_vigor, тает после old_age. Нрав ведёт руку ИИ: вспыльчивый и
## храбрый чаще идёт в натиск, трус и рассудительный — в защиту, лживый —
## в хитрость; умный читает привычки противника. Игроку противник выдаёт себя
## подсказкой — верной тем чаще, чем хитрее игрок и простодушнее противник.
##
## Если бьётся сам игрок (не на автопилоте), бой ждёт его ходов:
## state.pending_fights, окно схватки в интерфейсе. Остальные бои решаются
## сразу. За правителей в поединке чести могут биться поборники — лучшие из
## рыцарей, если доблестнее хозяина хотя бы на champion_margin.
##
## Данные:
##   defines.duels — числа боя и исходов (см. duels.yaml)
##   foes: { <id>: { icon, attack, guard, feint, vigor, style: { attack, guard, feint },
##                   bold, yields, fall: { death, wound, spare } } } — враги из данных
## Скрипт:
##   duel: scope:x | { target, kind: duel|mortal|friendly, champions, on_win, on_lose }
##   fight: { foe, kind, on_win, on_lose } — бой с врагом из данных
##   duel_odds(scope:x), foe_odds(<id>) — шанс победы, % (при равной игре)
##   has_champion
## Сигнал duel: {winner, loser, winner_fighter, loser_fighter, death, kind,
##   how: fall|yield|points|first_blood, mercy: spare|wound|kill|none, rounds}
## — только для боёв двух персонажей; бой с врагом — сигнал fight
## {character, foe, won, death, how}.

const OWNER := "core/duels"
const STANCES := ["attack", "guard", "feint"]
## что бьёт стойка
const BEATS := {"attack": "feint", "feint": "guard", "guard": "attack"}
## чем бить стойку
const COUNTER := {"attack": "guard", "guard": "feint", "feint": "attack"}
const MERCY := ["spare", "wound", "kill"]


func _init() -> void:
	id = "duels"
	doc = "Схватка: бой один на один обменами — поединки, бой насмерть, враги из данных"


# ------------------------------------------------------------ числа

const _DEFAULTS := {
	"stance_base": 0.5, "guile_intrigue": 0.2,
	"vigor_base": 7.0, "vigor_per_prowess": 0.2, "min_vigor": 3.0, "old_age": 50.0, "old_age_loss": 0.15,
	"damage": 3.0, "damage_per_power": 0.15, "damage_per_point": 0.3, "damage_spread": 1.0, "crit_chance": 0.1,
	"soften_base": 25.0, "soften_per_point": 4.0, "clash_mult": 0.75, "circle_recover": 1.0,
	"max_rounds": 8.0, "yield_at": 0.4, "yield_base": 0.35, "yield_per_bold": 0.1, "friendly_end": 0.5,
	"overkill": 3.0, "overkill_death": 0.3,
	"strength_pref": 0.08, "read_base": 0.3, "read_per_point": 0.05, "low_vigor_guard": 0.5,
	"tell_base": 45.0, "tell_per_point": 3.0, "tell_min": 30.0, "tell_max": 80.0,
	"odds_stance": 0.5, "odds_vigor": 0.19, "odds_peak": 0.08, "odds_bold": 0.065,
}


static func cfg(game: Game) -> Dictionary:
	var c: Variant = game.month_cache.get("duels:cfg")
	if c != null:
		return c
	var out := {}
	for k in _DEFAULTS:
		out[k] = game.def_num("duels." + k, _DEFAULTS[k])
	game.month_cache["duels:cfg"] = out
	return out


# ------------------------------------------------------------ бойцы

## Кто бьётся за персонажа: он сам или лучший из рыцарей, если тот сильнее.
static func champion_of(game: Game, c: Dictionary) -> Dictionary:
	if c.titles.is_empty() or not game.engine.has_feature("knights"):
		return c
	var own := Stats.skill(game, c, "prowess")
	var margin := int(game.def_num("duels.champion_margin", 2))
	var wound := str(game.def_val("military.wound_trait", "wounded"))
	for k in Knights.knights_of(game, c):
		if k.id == c.id or not Chars.is_alive(k) or k.get("prison") != null or k.traits.has(wound):
			continue
		# рыцари отсортированы по доблести: первый подходящий — лучший
		return k if Stats.skill(game, k, "prowess") >= own + margin else c
	return c


## Профиль бойца-персонажа: сила стоек, стойкость, нрав.
static func profile(game: Game, c: Dictionary) -> Dictionary:
	var k := cfg(game)
	var pr := maxf(0.0, Stats.stat(game, c, "prowess"))
	var base: float = pr * k.stance_base
	var vig: float = k.vigor_base + pr * k.vigor_per_prowess + Stats.stat(game, c, "duel_vigor")
	var age := Chars.age_of(game, c)
	if age > k.old_age:
		vig -= (age - k.old_age) * k.old_age_loss
	var ai := Ai.personality(game, c)
	var aggr := float(ai.get("aggression", 0.0))
	var bold := float(ai.get("boldness", 0.0))
	var honor := float(ai.get("honor", 0.0))
	var rat := float(ai.get("rationality", 0.0))
	return {
		"id": c.id,
		"attack": maxf(0.0, base + Stats.stat(game, c, "duel_might")),
		"guard": maxf(0.0, base + Stats.stat(game, c, "duel_guard")),
		"feint": maxf(0.0, base + Stats.stat(game, c, "duel_guile") + maxf(0.0, Stats.stat(game, c, "intrigue")) * k.guile_intrigue),
		"vigor": maxf(k.min_vigor, roundf(vig)),
		"style": {
			"attack": 1.0 + 0.25 * maxf(0.0, aggr) + 0.15 * maxf(0.0, bold) + 0.1 * maxf(0.0, -rat),
			"guard": 1.0 + 0.25 * maxf(0.0, -bold) + 0.15 * maxf(0.0, rat),
			"feint": 1.0 + 0.25 * maxf(0.0, -honor) + 0.1 * maxf(0.0, rat),
		},
		"bold": bold,
		"yields": true,
	}


## Профиль врага из данных (foes).
static func foe_profile(game: Game, foe_id: String) -> Variant:
	var d: Variant = game.content.get_def("foes", foe_id)
	if d == null:
		return null
	var st: Dictionary = d.get("style") if d.get("style") is Dictionary else {}
	return {
		"id": "", "foe": foe_id,
		"attack": Data.num(d.get("attack"), 4), "guard": Data.num(d.get("guard"), 4), "feint": Data.num(d.get("feint"), 4),
		"vigor": maxf(1.0, Data.num(d.get("vigor"), 8)),
		"style": {"attack": Data.num(st.get("attack"), 1), "guard": Data.num(st.get("guard"), 1), "feint": Data.num(st.get("feint"), 1)},
		"bold": Data.num(d.get("bold"), 0),
		"yields": ScriptContext.is_yes(d.get("yields", false)),
	}


## Разбор силы стойки персонажа для подсказки: [{label, value}].
static func stance_parts(game: Game, c: Dictionary, stance: String) -> Array:
	var k := cfg(game)
	var out := [{"label": game.loc.t("stat.prowess"), "value": maxf(0.0, Stats.stat(game, c, "prowess")) * k.stance_base}]
	var key: String = {"attack": "duel_might", "guard": "duel_guard", "feint": "duel_guile"}[stance]
	out.append_array(Stats.stat_breakdown(game, c, key))
	if stance == "feint":
		out.append({"label": game.loc.t("stat.intrigue"), "value": maxf(0.0, Stats.stat(game, c, "intrigue")) * k.guile_intrigue})
	return out.filter(func(p): return absf(float(p.value)) >= 0.05)


# ------------------------------------------------------------ бой: общее ядро

static func _new_fight(pa: Dictionary, pb: Dictionary, kind: String) -> Dictionary:
	return {
		"kind": kind, "prof": [pa, pb], "vig": [pa.vigor, pb.vigor], "max": [pa.vigor, pb.vigor],
		"round": 0, "hist": [], "log": [], "next": [null, null], "tell": null, "tell_acc": 0,
		"player": -1, "phase": "fight", "winner": -1, "how": "", "mercy": "", "dead": -1,
	}


static func _damage(k: Dictionary, pw: float, pl: float, rng: Rng) -> Array:
	var d: float = k.damage + pw * k.damage_per_power + (pw - pl) * k.damage_per_point + (rng.next() * 2.0 - 1.0) * k.damage_spread
	var crit: bool = rng.next() < k.crit_chance
	var v := maxi(1, roundi(d))
	return [v * 2 if crit else v, crit]


## Один обмен: стойки сторон, урон, запись в журнал.
static func exchange(k: Dictionary, f: Dictionary, sa: String, sb: String, rng: Rng) -> Dictionary:
	var st := [sa, sb]
	var p: Array = f.prof
	var e := {"r": int(f.round) + 1, "s": [sa, sb], "d": [0, 0], "k": "", "w": -1, "crit": false, "soft": false}
	if BEATS[sa] == sb or BEATS[sb] == sa:
		var w := 0 if BEATS[sa] == sb else 1
		var l := 1 - w
		var pw: float = p[w][st[w]]
		var pl: float = p[l][st[l]]
		var hit := _damage(k, pw, pl, rng)
		var dmg: int = hit[0]
		var soft := clampf((k.soften_base + (pl - pw) * k.soften_per_point) / 100.0, 0.05, 0.6)
		if rng.next() < soft:
			dmg = maxi(1, ceili(dmg / 2.0))
			e.soft = true
		e.d[l] = dmg
		e.w = w
		e.crit = hit[1]
		e.k = "beat_" + st[w]
	elif sa == "attack":
		var ha := _damage(k, p[0].attack, p[1].attack, rng)
		var hb := _damage(k, p[1].attack, p[0].attack, rng)
		e.d[1] = maxi(1, roundi(ha[0] * k.clash_mult))
		e.d[0] = maxi(1, roundi(hb[0] * k.clash_mult))
		e.crit = ha[1] or hb[1]
		e.k = "clash"
	elif sa == "guard":
		for i in 2:
			f.vig[i] = minf(f.max[i], f.vig[i] + k.circle_recover)
		e.k = "circle"
	else:
		var ra: float = p[0].feint + rng.next() * 4.0
		var rb: float = p[1].feint + rng.next() * 4.0
		var w := 0 if ra >= rb else 1
		var hit := _damage(k, p[w].feint, p[1 - w].feint, rng)
		e.d[1 - w] = maxi(1, roundi(hit[0] / 2.0))
		e.w = w
		e.k = "outwit"
	for i in 2:
		f.vig[i] = f.vig[i] - e.d[i]
	f.round = int(f.round) + 1
	f.hist.append([sa, sb])
	f.log.append(e)
	return e


## Чего ждать от стороны: её частые стойки, последняя — вдвое.
static func _predict(f: Dictionary, side: int) -> Variant:
	var h: Array = f.hist
	if h.is_empty():
		return null
	var w := {"attack": 0.0, "guard": 0.0, "feint": 0.0}
	var n := h.size()
	for j in range(maxi(0, n - 3), n):
		w[h[j][side]] += 2.0 if j == n - 1 else 1.0
	var best: String = h[n - 1][side]
	for s in STANCES:
		if w[s] > w[best]:
			best = s
	return best


## Стойка ИИ на следующий обмен.
static func ai_stance(k: Dictionary, f: Dictionary, i: int, rng: Rng) -> String:
	var p: Dictionary = f.prof[i]
	var w := {}
	var mean: float = (p.attack + p.guard + p.feint) / 3.0
	for s in STANCES:
		w[s] = float(p.style[s]) * clampf(1.0 + (p[s] - mean) * k.strength_pref, 0.5, 2.0)
	# читает противника: бьёт то, чего ждёт от него
	var pred: Variant = _predict(f, 1 - i)
	if pred != null:
		w[COUNTER[pred]] += k.read_base + p.feint * k.read_per_point
	# сил мало — осторожнее (вспыльчивый — наоборот)
	if f.vig[i] <= f.max[i] * k.yield_at:
		w["attack" if p.style.attack > 1.4 else "guard"] += k.low_vigor_guard
	return rng.weighted(STANCES, func(s): return maxf(0.01, w[s]))


## Сдаётся ли ИИ-сторона перед обменом.
static func ai_yields(k: Dictionary, f: Dictionary, i: int, rng: Rng) -> bool:
	if f.kind != "duel" or not f.prof[i].yields:
		return false
	var frac: float = f.vig[i] / maxf(1.0, f.max[i])
	if frac > k.yield_at or frac >= f.vig[1 - i] / maxf(1.0, f.max[1 - i]):
		return false
	return rng.next() < clampf(k.yield_base - f.prof[i].bold * k.yield_per_bold, 0.0, 0.9)


## Чем кончился бой после обмена: [победитель, как] или [] — бой идёт.
static func outcome(k: Dictionary, f: Dictionary, rng: Rng) -> Array:
	var v: Array = f.vig
	if f.kind == "friendly":
		var down := [v[0] <= f.max[0] * k.friendly_end, v[1] <= f.max[1] * k.friendly_end]
		if down[0] or down[1]:
			if down[0] and down[1]:
				return [0 if v[0] / f.max[0] >= v[1] / f.max[1] else 1, "first_blood"]
			return [1 if down[0] else 0, "first_blood"]
	if v[0] <= 0.0 or v[1] <= 0.0:
		if v[0] <= 0.0 and v[1] <= 0.0:
			if v[0] == v[1]:
				return [0 if rng.next() < 0.5 else 1, "fall"]
			return [0 if v[0] > v[1] else 1, "fall"]
		return [1 if v[0] <= 0.0 else 0, "fall"]
	if int(f.round) >= int(k.max_rounds):
		var fa: float = v[0] / maxf(1.0, f.max[0])
		var fb: float = v[1] / maxf(1.0, f.max[1])
		if fa == fb:
			return [0 if rng.next() < 0.5 else 1, "points"]
		return [0 if fa > fb else 1, "points"]
	return []


## Бой двух профилей без последствий; победитель (0 или 1).
static func simulate(k: Dictionary, pa: Dictionary, pb: Dictionary, kind: String, rng: Rng) -> int:
	var f := _new_fight(pa, pb, kind)
	while true:
		for i in 2:
			if ai_yields(k, f, i, rng):
				return 1 - i
		exchange(k, f, ai_stance(k, f, 0, rng), ai_stance(k, f, 1, rng), rng)
		var o := outcome(k, f, rng)
		if not o.is_empty():
			return o[0]
	return 0


## Шанс первого профиля прогоном n боёв своим генератором, %.
static func simulated_odds(game: Game, pa: Dictionary, pb: Dictionary, kind: String, n: int, salt: String = "") -> int:
	var k := cfg(game)
	var rng := Rng.from_seed(salt + ":" + str(game.date))
	var wins := 0
	for _i in n:
		if simulate(k, pa, pb, kind, rng) == 0:
			wins += 1
	return clampi(roundi(100.0 * wins / maxi(1, n)), 1, 99)


## Шанс первого профиля, % (при равной игре): быстрая оценка по разнице
## средней силы стоек, стойкости, сильнейшей стойки и храбрости (сдаётся
## ли), подобранная по прогонам боёв (odds_* в defines.duels).
static func profile_odds(game: Game, pa: Dictionary, pb: Dictionary, kind: String) -> int:
	var k := cfg(game)
	var ma: float = (pa.attack + pa.guard + pa.feint) / 3.0
	var mb: float = (pb.attack + pb.guard + pb.feint) / 3.0
	var peak: float = (maxf(pa.attack, maxf(pa.guard, pa.feint)) - ma) - (maxf(pb.attack, maxf(pb.guard, pb.feint)) - mb)
	var z: float = k.odds_stance * (ma - mb) + k.odds_vigor * (pa.vigor - pb.vigor) + k.odds_peak * peak
	if kind == "duel":
		z += k.odds_bold * ((pa.bold if pa.yields else 3.0) - (pb.bold if pb.yields else 3.0))
	return clampi(roundi(100.0 / (1.0 + exp(-z))), 1, 99)


## Шанс стороны a победить сторону b в поединке чести, %.
static func odds(game: Game, a: Dictionary, b: Dictionary, kind: String = "duel", champions: bool = true) -> int:
	var key := "duel_odds:%s:%s:%s:%s" % [a.id, b.id, kind, champions]
	var c: Variant = game.day_cache.get(key)
	if c != null:
		return c
	var fa := champion_of(game, a) if champions else a
	var fb := champion_of(game, b) if champions else b
	var v := profile_odds(game, profile(game, fa), profile(game, fb), kind)
	game.day_cache[key] = v
	return v


static func foe_odds(game: Game, c: Dictionary, foe_id: String, kind: String = "mortal") -> int:
	var fp: Variant = foe_profile(game, foe_id)
	if fp == null:
		return 0
	var key := "foe_odds:%s:%s:%s" % [c.id, foe_id, kind]
	var cached: Variant = game.day_cache.get(key)
	if cached != null:
		return cached
	# у врагов стойки перекошены — оценка формулой грубее, считаем прогоном
	var v := simulated_odds(game, profile(game, c), fp, kind, 200, c.id + "|" + foe_id)
	game.day_cache[key] = v
	return v


# ------------------------------------------------------------ бой в мире

static func pending(game: Game) -> Array:
	if not (game.state.get("pending_fights") is Array):
		game.state["pending_fights"] = []
	return game.state.pending_fights


static func find(game: Game, uid: String) -> Variant:
	for f in pending(game):
		if f.uid == uid:
			return f
	return null


## Начать бой a против b (персонажи) или a против врага opts.foe.
## opts: kind, champions, foe, on_win, on_lose, ctx {root, scopes}.
static func begin(game: Game, a: Dictionary, b: Variant, opts: Dictionary = {}) -> Dictionary:
	var kind := str(opts.get("kind", "duel"))
	var champions: bool = b != null and opts.get("champions", kind == "duel")
	var fa := champion_of(game, a) if champions else a
	var pb: Variant = null
	var fb: Variant = null
	if b != null:
		fb = champion_of(game, b) if champions else b
		pb = profile(game, fb)
	else:
		pb = foe_profile(game, str(opts.get("foe", "")))
	var f := _new_fight(profile(game, fa), pb, kind)
	f.merge({
		"uid": game.new_id("fight"),
		"side": [a.id, b.id if b != null else null],
		"fighter": [fa.id, fb.id if fb != null else null],
		"foe": str(opts.get("foe", "")) if b == null else "",
		"on_win": opts.get("on_win"), "on_lose": opts.get("on_lose"),
		"ctx": opts.get("ctx"),
	})
	for i in 2:
		var fid: Variant = f.fighter[i]
		if fid != null and game.is_player(fid) and not game.ai_controls(fid):
			f.player = i
	return f


## Бой: с игроком — ждёт его ходов (окно схватки), иначе решается сразу.
## Возвращает победившую сторону-персонажа (или {} — бой ещё идёт / победил враг).
static func duel(game: Game, a: Dictionary, b: Variant, opts: Dictionary = {}) -> Dictionary:
	var f := begin(game, a, b, opts)
	if f.player >= 0:
		pending(game).append(f)
		_prepare(game, f)
		game.emit("fight.started", {"fight": f})
		game.notify("fight")
		return {}
	while f.phase == "fight":
		_prepare(game, f)
		if f.phase != "fight":
			break
		_step(game, f, f.next[0], f.next[1])
	var w: Variant = game.ch(f.side[f.winner]) if f.winner >= 0 and f.side[f.winner] != null else null
	return w if w != null else {}


## Перед обменом: ИИ решает, не сдаться ли, и выбирает стойку; игроку —
## подсказка о намерении противника.
static func _prepare(game: Game, f: Dictionary) -> void:
	var k := cfg(game)
	for i in 2:
		if i != f.player and ai_yields(k, f, i, game.rng):
			_end(game, f, 1 - i, "yield")
			return
	for i in 2:
		f.next[i] = ai_stance(k, f, i, game.rng) if i != f.player else null
	if f.player >= 0:
		var o: int = 1 - f.player
		var acc := clampf(k.tell_base + (float(f.prof[f.player].feint) - float(f.prof[o].feint)) * k.tell_per_point, k.tell_min, k.tell_max)
		f.tell_acc = roundi(acc)
		if game.rng.next() * 100.0 < acc:
			f.tell = f.next[o]
		else:
			f.tell = game.rng.pick(STANCES.filter(func(s): return s != f.next[o]))
		f["tell_n"] = game.rng.range_int(1, 3)


static func _step(game: Game, f: Dictionary, sa: String, sb: String) -> void:
	var k := cfg(game)
	exchange(k, f, sa, sb, game.rng)
	var o := outcome(k, f, game.rng)
	if not o.is_empty():
		_end(game, f, o[0], o[1])


## Ход игрока: его стойка против загаданной противником.
static func player_move(game: Game, uid: String, stance: String) -> void:
	var f: Variant = find(game, uid)
	if f == null or f.phase != "fight" or f.player < 0 or not (stance in STANCES):
		return
	var st := [f.next[0], f.next[1]]
	st[f.player] = stance
	_step(game, f, st[0], st[1])
	if f.phase == "fight":
		_prepare(game, f)
	game.notify("fight")


static func player_yield(game: Game, uid: String) -> void:
	var f: Variant = find(game, uid)
	if f == null or f.phase != "fight" or f.player < 0 or not can_yield(f, f.player):
		return
	_end(game, f, 1 - f.player, "yield")
	game.notify("fight")


static func can_yield(f: Dictionary, i: int) -> bool:
	return f.kind == "duel" and f.prof[i].yields


static func player_mercy(game: Game, uid: String, choice: String) -> void:
	var f: Variant = find(game, uid)
	if f == null or f.phase != "mercy" or not (choice in MERCY):
		return
	_conclude(game, f, choice)
	game.notify("fight")


## Закрыть окно законченного боя.
static func dismiss(game: Game, uid: String) -> void:
	var f: Variant = find(game, uid)
	if f == null:
		return
	if f.phase != "over":
		ai_finish(game, uid)
	game.state.pending_fights = pending(game).filter(func(x): return x.uid != uid)
	game.notify("fight")


## Доиграть бой за игрока (автопилот, загрузка с мёртвыми бойцами).
static func ai_finish(game: Game, uid: String) -> void:
	var f: Variant = find(game, uid)
	if f == null:
		return
	for i in 2:
		var fid: Variant = f.fighter[i]
		if fid != null and not game.is_alive(fid) and f.phase == "fight":
			f.winner = 1 - i
			f.how = "fall"
			f.phase = "over"
	var p: int = f.player
	f.player = -1
	while f.phase == "fight":
		_prepare(game, f)
		if f.phase != "fight":
			break
		_step(game, f, f.next[0], f.next[1])
	if f.phase == "mercy":
		_conclude(game, f, ai_mercy(game, f, f.winner))
	f.player = p


## Бой кончился: победитель решает судьбу побеждённого (или исход ясен сам).
static func _end(game: Game, f: Dictionary, winner: int, how: String) -> void:
	f.winner = winner
	f.how = how
	f.next = [null, null]
	f.tell = null
	var l := 1 - winner
	if how == "points" or how == "first_blood":
		_conclude(game, f, "none")
	elif f.prof[l].get("foe") != null:
		_conclude(game, f, "none")
	elif f.prof[winner].get("foe") != null:
		_conclude(game, f, _foe_mercy(game, f, winner))
	elif f.kind == "mortal" and how == "fall":
		_conclude(game, f, "kill")
	elif f.player == winner:
		f.phase = "mercy"
	else:
		_conclude(game, f, ai_mercy(game, f, winner))


## Как поступит победитель-ИИ с побеждённым: по нраву, родству и вражде.
static func ai_mercy(game: Game, f: Dictionary, w: int) -> String:
	var wc: Variant = game.ch(f.fighter[w])
	var lc: Variant = game.ch(f.fighter[1 - w])
	if wc == null or lc == null:
		return "spare"
	var ai := Ai.personality(game, wc)
	var comp := float(ai.get("compassion", 0.0))
	var honor := float(ai.get("honor", 0.0))
	var weights := {
		"spare": game.def_num("duels.mercy_spare", 2.0) + 1.5 * maxf(0.0, comp) + 0.5 * maxf(0.0, honor) + (2.0 if f.how == "yield" else 0.0),
		"wound": game.def_num("duels.mercy_wound", 3.0) + 0.5 * maxf(0.0, float(ai.get("aggression", 0.0))),
		"kill": game.def_num("duels.mercy_kill", 0.3) + 0.8 * maxf(0.0, -comp) + 0.5 * maxf(0.0, float(ai.get("vengefulness", 0.0))),
	}
	if Opinion.opinion(game, wc, lc) <= -50:
		weights.kill += 1.5
	if f.how == "yield":
		weights.kill *= 0.3
	if Chars.is_close_family(game, wc, lc) or Chars.same_dynasty(game, wc, lc):
		weights.kill *= 0.1
	return game.rng.weighted(MERCY, func(m): return maxf(0.0, weights[m]))


static func _foe_mercy(game: Game, f: Dictionary, w: int) -> String:
	var d: Variant = game.content.get_def("foes", f.prof[w].foe)
	var fall: Dictionary = d.get("fall") if d != null and d.get("fall") is Dictionary else {}
	var lc: Variant = game.ch(f.fighter[1 - w])
	var dm := Military._death_mult(game, lc) if lc != null else 1.0
	var weights := {"spare": Data.num(fall.get("spare"), 20), "wound": Data.num(fall.get("wound"), 60), "kill": Data.num(fall.get("death"), 20) * dm}
	if f.how == "yield":
		weights.kill *= 0.3
	return game.rng.weighted(MERCY, func(m): return maxf(0.0, weights[m]))


## Последствия: слава и позор, судьба побеждённого, следы, весть, сигнал.
static func _conclude(game: Game, f: Dictionary, mercy: String) -> void:
	f.mercy = mercy
	f.phase = "over"
	var w: int = f.winner
	var l := 1 - w
	var k := cfg(game)
	var fw: Variant = game.ch(f.fighter[w]) if f.fighter[w] != null else null
	var fl: Variant = game.ch(f.fighter[l]) if f.fighter[l] != null else null
	var sw: Variant = game.ch(f.side[w]) if f.side[w] != null else null
	var sl: Variant = game.ch(f.side[l]) if f.side[l] != null else null
	var foe_fight: bool = f.foe != ""
	var friendly: bool = f.kind == "friendly"
	var mult := 0.5 if (friendly or f.how == "points") else 1.0
	var share := game.def_num("duels.champion_share", 0.5)
	# слава — тому, за кого бились; поборнику — его доля
	if sw != null:
		var wp := game.def_num("duels.foe_prestige" if foe_fight else "duels.win_prestige", 60) * mult
		sw.prestige += wp * (share if fw.id != sw.id else 1.0) * maxf(0.0, 1.0 + Stats.stat(game, sw, "duel_prestige_mult"))
		if fw.id != sw.id:
			fw.prestige += wp * share
		if not friendly and not foe_fight and not sw.titles.is_empty() and game.engine.has_feature("politics"):
			Politics.add_dread(game, sw, game.def_num("duels.win_dread", 5))
	if sl != null and not foe_fight:
		sl.prestige -= game.def_num("duels.lose_prestige", 40) * mult * (share if fl.id != sl.id else 1.0)
		if not friendly and game.content.has("opinion_modifiers", str(game.def_val("duels.loser_opinion", "bested_in_duel"))):
			Opinion.add_opinion(game, sl, sw, str(game.def_val("duels.loser_opinion", "bested_in_duel")))
	# сдался — позор, храбрецу и гордецу — мука
	if f.how == "yield" and fl != null:
		fl.prestige -= game.def_num("duels.yield_prestige", 30)
		if fl.traits.has("brave") or fl.traits.has("arrogant"):
			Chars.change_stress(game, fl, game.def_num("duels.yield_stress", 20), "duel")
	var died := false
	if fl != null:
		match mercy:
			"spare":
				if fw != null:
					fw.prestige += game.def_num("duels.spare_prestige", 20)
					if game.engine.has_feature("karma"):
						Karma.add(game, fw, game.def_num("duels.spare_karma", 1), "spared_foe")
					if game.content.has("opinion_modifiers", "spared_in_duel"):
						Opinion.add_opinion(game, fl, fw, "spared_in_duel")
			"wound":
				Military._wound(game, fl)
				if f.how == "fall" and game.rng.chance(game.def_num("duels.maim_chance", 0.25)) and game.content.has("traits", "maimed") and not fl.traits.has("maimed"):
					Chars.add_trait(game, fl, "maimed")
			"kill":
				died = true
		# удар насмерть: павший под тяжёлым ударом может не подняться
		if not died and f.how == "fall" and f.vig[l] <= -k.overkill and game.rng.chance(k.overkill_death * Military._death_mult(game, fl)):
			died = true
			f.mercy = "kill"
			f["fatal"] = true
	# шрамы: кто был на волосок и выжил
	for i in 2:
		var c: Variant = game.ch(f.fighter[i]) if f.fighter[i] != null else null
		if c == null or (i == l and died) or friendly:
			continue
		if f.vig[i] <= f.max[i] * game.def_num("duels.scar_at", 0.3) and game.rng.chance(game.def_num("duels.scar_chance", 0.2)) and game.content.has("traits", "scarred") and not c.traits.has("scarred"):
			Chars.add_trait(game, c, "scarred")
	if died and fw != null and fl != null and not foe_fight:
		if not fw.titles.is_empty() and game.engine.has_feature("politics"):
			Politics.add_dread(game, fw, game.def_num("duels.kill_dread", 10))
		if f.how == "yield" and game.engine.has_feature("karma"):
			Karma.add(game, fw, game.def_num("duels.kill_yielded_karma", -3), "slew_yielded")
		if game.content.has("opinion_modifiers", "slew_my_kin"):
			for kin in Chars.parents_of(game, fl) + Chars.siblings_of(game, fl) + fl.children.map(func(x): return game.ch(x)) + fl.spouses.map(func(x): return game.ch(x)):
				if kin != null and Chars.is_alive(kin) and kin.id != fw.id:
					Opinion.add_opinion(game, kin, fw, "slew_my_kin")
	# у оружия победителя — своя история
	if fw != null and not friendly and game.engine.has_feature("artifacts"):
		for it in Artifacts.equipped(game, fw):
			if Artifacts.slot_of(game, it) == "weapon":
				Artifacts._history(it, game, "duel_kill" if died else "duel_won", fl.id if fl != null else null, fw.id)
				break
	f["died"] = died
	_announce(game, f)
	if foe_fight:
		var c: Variant = game.ch(f.side[0])
		game.emit("fight", {"character": c, "foe": f.foe, "won": w == 0, "death": died, "how": f.how})
	elif sw != null and sl != null:
		game.emit("duel", {"winner": sw, "loser": sl, "winner_fighter": fw, "loser_fighter": fl, "death": died,
			"kind": f.kind, "how": f.how, "mercy": f.mercy, "rounds": f.round})
		# до гибели бойца: его вещи ещё при нём (трофеи рыцаря)
		game.on_action("on_duel_won", {"type": "character", "id": sw.id}, {"loser": {"type": "character", "id": sl.id}})
	_run_outcome(game, f)
	if died and fl != null:
		Succession.kill_character(game, fl, "duel", fw.id if fw != null else null)
	for i in 2:
		for key in ["side", "fighter"]:
			if f[key][i] != null:
				game.stat_cache.erase(f[key][i])
				game.stat_cache.erase("ai:" + str(f[key][i]))


## on_win / on_lose из эффекта: в скоупе стороны a (root — как у вызвавшего), scope:duel_foe — сторона b.
static func _run_outcome(game: Game, f: Dictionary) -> void:
	var block: Variant = f.on_win if f.winner == 0 else f.on_lose
	if block == null or f.side[0] == null or game.ch(f.side[0]) == null:
		return
	var c: Variant = f.get("ctx")
	var root: Dictionary = c.root if c is Dictionary and c.get("root") is Dictionary else {"type": "character", "id": f.side[0]}
	var scopes: Dictionary = c.scopes.duplicate() if c is Dictionary and c.get("scopes") is Dictionary else {}
	if f.side[1] != null:
		scopes["duel_foe"] = {"type": "character", "id": f.side[1]}
	var ctx := ScriptContext.make(game, root, scopes)
	Interp.run_effect(ctx, {"type": "character", "id": f.side[0]}, block)


## Весть игроку, если бой его касается.
static func _announce(game: Game, f: Dictionary) -> void:
	var mine := -1
	for i in 2:
		for key in ["side", "fighter"]:
			if f[key][i] != null and game.is_player(f[key][i]):
				mine = i
	if mine < 0:
		return
	var w: int = f.winner
	var params := {
		"winner": fighter_name(game, f, w),
		"loser": fighter_name(game, f, 1 - w),
		"rounds": f.round,
	}
	var key: String = "msg.duel_" + ("died" if f.died else (f.mercy if f.mercy in MERCY else f.how))
	var focus: Variant = f.fighter[1 - w] if f.fighter[1 - w] != null else f.fighter[w]
	game.message(game.loc.t(key, params), "good" if mine == w else "bad", {"type": "character", "id": focus} if focus != null else null)


static func fighter_name(game: Game, f: Dictionary, i: int) -> String:
	if f.fighter[i] != null:
		return game.scope_name({"type": "character", "id": f.fighter[i]})
	return game.loc.t("foe." + str(f.prof[i].get("foe", "")))


## Строка журнала обмена с точки зрения стороны me.
static func log_line(game: Game, f: Dictionary, e: Dictionary, me: int) -> String:
	var who := func(i: int) -> String:
		return game.loc.t("duel.you") if i == me else fighter_name(game, f, i)
	var p := {
		"a": who.call(0), "b": who.call(1),
		"sa": game.loc.t("duel.stance." + str(e.s[0])), "sb": game.loc.t("duel.stance." + str(e.s[1])),
		"da": e.d[0], "db": e.d[1],
	}
	var text := ""
	match str(e.k):
		"clash":
			text = game.loc.t("duel.log.clash", p)
		"circle":
			text = game.loc.t("duel.log.circle", p)
		_:
			var w: int = e.w
			p["w"] = who.call(w)
			p["l"] = who.call(1 - w)
			p["d"] = e.d[1 - w]
			p["sw"] = game.loc.t("duel.stance." + str(e.s[w]))
			p["sl"] = game.loc.t("duel.stance." + str(e.s[1 - w]))
			text = game.loc.t("duel.log." + str(e.k), p)
			if e.soft:
				text += " " + game.loc.t("duel.log.soft", p)
	if e.crit:
		text += " " + game.loc.t("duel.log.crit")
	return "%d. %s" % [e.r, text.left(1).to_upper() + text.substr(1)]


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	# поединок — сфера доблести: кураж и хандра бойцов
	engine.hooks.on("duel", func(p):
		var g: Game = p.game
		if g.engine.has_feature("momentum"):
			Momentum.record(g, p.winner_fighter, "prowess", true)
			Momentum.record(g, p.loser_fighter, "prowess", false)
	, 0, OWNER)
	engine.content_validators.register("foes", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("foes"):
			for key in ["attack", "guard", "feint", "vigor"]:
				if not (d.get(key) is int or d.get(key) is float):
					v.issue("foes/%s: нужно число %s" % [d.id, key])
	, OWNER)


static func _opts(ctx: ScriptContext, s: Dictionary, arg: Variant) -> Dictionary:
	var o := {"ctx": {"root": ctx.root, "scopes": ctx.scopes.duplicate()}}
	if arg is Dictionary and not arg.has("type"):
		for key in ["kind", "foe", "on_win", "on_lose"]:
			if arg.has(key):
				o[key] = arg[key]
		if arg.has("champions"):
			o["champions"] = ScriptContext.is_yes(arg.champions)
	return o


static func _target(ctx: ScriptContext, s: Dictionary, arg: Variant) -> Variant:
	var t: Variant = arg.get("target") if arg is Dictionary and not arg.has("type") else arg
	var r: Variant = Interp.resolve_scope(ctx, s, t)
	return ctx.game.ch(r.id) if r != null and r.type == "character" else null


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	r.effects.register("duel", {"scopes": CH, "doc": "Поединок с персонажем: duel: scope:x или { target: scope:x, kind: duel|mortal|friendly, champions: no, on_win: [...], on_lose: [...] } (эффекты исхода — в скоупе этой стороны, scope:duel_foe — противник; бьётся игрок — исход позже, после окна схватки)",
		"apply": func(ctx, s, arg):
			var a: Variant = ctx.game.ch(s.id)
			var b: Variant = Duels._target(ctx, s, arg)
			if a != null and b != null and a.id != b.id and Chars.is_alive(a) and Chars.is_alive(b):
				Duels.duel(ctx.game, a, b, Duels._opts(ctx, s, arg)),
		"describe": func(ctx, s, arg):
			var a: Variant = ctx.game.ch(s.id)
			var b: Variant = Duels._target(ctx, s, arg)
			if a == null or b == null:
				return null
			var o := Duels._opts(ctx, s, arg)
			var kind := str(o.get("kind", "duel"))
			var champs: bool = o.get("champions", kind == "duel")
			var fa: Dictionary = Duels.champion_of(ctx.game, a) if champs else a
			var fb: Dictionary = Duels.champion_of(ctx.game, b) if champs else b
			return ctx.game.loc.t("fx.duel" if kind == "duel" else "fx.duel_" + kind, {
				"a": ctx.game.scope_name({"type": "character", "id": fa.id}),
				"b": ctx.game.scope_name({"type": "character", "id": fb.id}),
				"chance": Duels.odds(ctx.game, a, b, kind, champs),
			}),
	}, OWNER)
	r.effects.register("fight", {"scopes": CH, "doc": "Бой с врагом из данных: fight: { foe: wolf, kind: mortal|duel|friendly, on_win: [...], on_lose: [...] } (эффекты исхода — в скоупе этого персонажа)",
		"apply": func(ctx, s, arg):
			var a: Variant = ctx.game.ch(s.id)
			var o := Duels._opts(ctx, s, arg)
			if not o.has("kind"):
				o["kind"] = "mortal"
			if a != null and Chars.is_alive(a) and ctx.game.content.has("foes", str(o.get("foe", ""))):
				Duels.duel(ctx.game, a, null, o),
		"describe": func(ctx, s, arg):
			var a: Variant = ctx.game.ch(s.id)
			var foe := str(arg.get("foe", "")) if arg is Dictionary else ""
			if a == null or not ctx.game.content.has("foes", foe):
				return null
			return ctx.game.loc.t("fx.fight", {"a": ctx.game.scope_name(s), "foe": ctx.game.loc.t("foe." + foe),
				"chance": Duels.foe_odds(ctx.game, a, foe, str(arg.get("kind", "mortal")))}),
	}, OWNER)
	r.values.register("duel_odds", {"scopes": CH, "doc": "Шанс победить персонажа в поединке, % (при равной игре): duel_odds(scope:x)", "get": func(ctx, s, arg):
		var a: Variant = ctx.game.ch(s.id)
		var b: Variant = ctx.game.ch(arg.id) if arg is Dictionary and arg.get("type") == "character" else null
		return float(Duels.odds(ctx.game, a, b)) if a != null and b != null and a.id != b.id else 0.0
	}, OWNER)
	r.values.register("foe_odds", {"scopes": CH, "doc": "Шанс одолеть врага из данных (foes), %: foe_odds(<id>)", "get": func(ctx, s, arg):
		var a: Variant = ctx.game.ch(s.id)
		return float(Duels.foe_odds(ctx.game, a, str(arg))) if a != null else 0.0
	}, OWNER)
	r.triggers.register("has_champion", {"scopes": CH, "doc": "За персонажа в поединке бьётся поборник", "eval": func(ctx, s, arg):
		var c: Variant = ctx.game.ch(s.id)
		var has: bool = c != null and Duels.champion_of(ctx.game, c).id != c.id
		return has == ScriptContext.is_yes(arg)
	}, OWNER)

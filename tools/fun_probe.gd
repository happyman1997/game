class_name FunProbe
extends RefCounted
## Замер интереса: что видит и делает игрок за партию. ИИ ведёт персонажа
## игрока на автопилоте (Game.autopilot) по тем же правилам, что всех, а
## зонд слушает хуки движка и раз в год снимает показатели державы и мира.
##
##   var p := FunProbe.new(game, years)   # подписка на хуки
##   p.day()                              # после каждого game.tick()
##   p.finish()                           # итог: p.metrics(), p.to_json()
##
## Что считаем:
##   окна    — события игрока с вариантами (окно на экране);
##   выбор   — окна, где вариантов два и больше;
##   вызов   — то, что мир бросает игроку: выбор, война против него или с ним,
##             фракция и ультиматум, бунт, заговор, смена правителя;
##   дело    — то, что делает игрок: решение, предложение, объявленная война.
## Пороги — tools/fun_gates.yaml, отчёт и прогоны — tools/fun_report.gd.

## Вариант очевиден, если у ИИ на него не меньше этой доли веса.
const OBVIOUS_SHARE := 0.85

var game: Game
var years: int
var start: String
var seed: int
var day0: int

var windows := 0
var choices := 0
var single := 0
var obvious := 0
var flat := 0
var seen := {}           # событие → сколько раз видел
var first_year := {}     # событие → год первой встречи
var ev_obvious := {}     # событие → сколько раз выбор был очевиден
var ev_flat := {}        # событие → сколько раз ИИ было всё равно
var by_year := []        # по годам: {choices, windows, calls, deeds, messages}
var call_days := []      # дни «вызовов»
var decisions := {}
var interactions := {}
var wars_declared := {}  # casus belli → сколько раз объявлял игрок
var wars := {"attack": 0, "defend": 0, "joined": 0, "won": 0, "lost": 0, "white": 0}
var threats := {"factions": 0, "ultimatums": 0, "revolts": 0, "schemes": 0, "prison": 0, "regency": 0}
var successions := []    # [{year, age}]
var game_over: Variant = null
var realm_lost: Variant = null  # {year} — игрок остался без земель: партия, по сути, проиграна
var snapshots := []      # раз в год
var news := 0
var _own_wars := {}


func _init(g: Game, total_years: int, run_seed: int = 0) -> void:
	game = g
	years = total_years
	seed = run_seed
	for i in years:
		by_year.append({"choices": 0, "windows": 0, "calls": 0, "deeds": 0, "messages": 0})
	if g == null:
		return # from_json
	start = str(g.state.player)
	day0 = g.date
	var h := g.engine.hooks
	h.on("event.fired", _on_event)
	h.on("decision.taken", func(p):
		if game.is_player(p.get("character")):
			_bump(decisions, str(p.decision))
			_deed())
	h.on("interaction", func(p):
		if game.is_player(p.get("actor")):
			_bump(interactions, str(p.interaction) + (" ✓" if p.accepted else " ✗"))
			_deed())
	h.on("war.declared", func(p):
		var w: Dictionary = p.war
		var me: Variant = game.state.player
		if w.attacker == me:
			wars.attack += 1
			_bump(wars_declared, str(w.cb))
			_deed()
		elif w.defender == me:
			wars.defend += 1
			_call()
		else:
			return
		_own_wars[w.id] = "att" if w.attacker == me else "def")
	h.on("war.ended", func(p):
		var w: Dictionary = p.war
		var side: Variant = _own_wars.get(w.id)
		if side == null:
			var me: Variant = game.state.player
			if me in Data.as_array(w.get("attackers")):
				side = "att"
			elif me in Data.as_array(w.get("defenders")):
				side = "def"
			if side == null:
				return
			wars.joined += 1
		_own_wars.erase(w.id)
		var out := str(p.outcome)
		if out == "victory":
			wars["won" if side == "att" else "lost"] += 1
		elif out == "defeat":
			wars["lost" if side == "att" else "won"] += 1
		else:
			wars.white += 1
		_call())
	h.on("faction.created", func(p):
		if game.is_player(p.faction.get("target")):
			threats.factions += 1
			_call())
	h.on("faction.ultimatum", func(p):
		if game.is_player(p.faction.get("target")):
			threats.ultimatums += 1
			_call())
	h.on("populace.revolt", func(p):
		var w: Variant = p.get("war")
		if w is Dictionary and game.is_player(w.get("defender")):
			threats.revolts += 1
			_call())
	h.on("scheme.discovered", func(p):
		if game.is_player(p.scheme.get("target")):
			threats.schemes += 1
			_call())
	h.on("prison.imprisoned", func(p):
		if game.is_player(p.prisoner.id):
			threats.prison += 1
			_call())
	h.on("regency.started", func(p):
		if game.is_player(p.ruler.id):
			threats.regency += 1)
	h.on("player.succession", func(p):
		var heir: Variant = game.ch(p.to)
		successions.append({"year": _year(), "age": Chars.age_of(game, heir) if heir != null else -1})
		_call())
	h.on("game.over", func(p): game_over = {"year": _year(), "reason": str(p.get("reason", ""))})
	snapshot()


func _year() -> int:
	return clampi(int((game.date - day0) / GameDate.DAYS_PER_YEAR), 0, years - 1)


func _bump(d: Dictionary, k: String, n: int = 1) -> void:
	d[k] = int(d.get(k, 0)) + n


func _deed() -> void:
	by_year[_year()].deeds += 1


func _call() -> void:
	by_year[_year()].calls += 1
	call_days.append(game.date)


func _on_event(p: Dictionary) -> void:
	var t: Variant = p.get("target")
	if not (t is Dictionary) or t.get("type") != "character" or not game.is_player(t.get("id")):
		return
	var ws: Array = Data.as_array(p.get("weights"))
	if ws.is_empty():
		return # скрытое событие или без вариантов — окна нет
	var id := str(p.event)
	var y := _year()
	windows += 1
	by_year[y].windows += 1
	_bump(seen, id)
	if not first_year.has(id):
		first_year[id] = y
	if ws.size() < 2:
		single += 1
		return
	choices += 1
	by_year[y].choices += 1
	_call()
	var total := 0.0
	var hi := 0.0
	var lo := INF
	for w in ws:
		total += float(w)
		hi = maxf(hi, float(w))
		lo = minf(lo, float(w))
	if is_equal_approx(hi, lo):
		flat += 1
		_bump(ev_flat, id)
	elif total > 0.0 and hi / total >= OBVIOUS_SHARE:
		obvious += 1
		_bump(ev_obvious, id)


## После каждого дня: сообщения игроку за день и годовой срез.
func day() -> void:
	var ms: Array = game.state.messages
	var i := ms.size() - 1
	var y := _year()
	while i >= 0 and int(ms[i].date) == game.date:
		by_year[y].messages += 1
		var txt := str(ms[i].text)
		if txt.begins_with("Весть") or txt.begins_with("News"):
			news += 1
		i -= 1
	if (game.date - day0) % 365 == 0:
		snapshot()


## Годовой срез: держава игрока и расклад сил в мире.
func snapshot() -> void:
	var p: Variant = game.player
	var indep := game.rulers().filter(func(c): return c.liege == null)
	var sizes := []
	var total := 0
	var top := {"c": null, "n": 0}
	for c in indep:
		var n := Titles.realm_counties(game, c).size()
		sizes.append(n)
		total += n
		if n > int(top.n):
			top = {"c": c, "n": n}
	var s := {"year": snapshots.size(), "independents": indep.size(), "counties_total": total,
		"top_id": str(top.c.id) if top.c != null else "", "top_counties": top.n,
		"top_name": Titles.full_name(game, top.c.titles[0]) if top.c != null and not top.c.titles.is_empty() else ""}
	if p != null and p.titles.is_empty() and realm_lost == null and game_over == null:
		# срез — на границе года: земли ушли в году, который только что кончился
		realm_lost = {"year": clampi(int((game.date - day0 - 1) / GameDate.DAYS_PER_YEAR), 0, years - 1)}
	if p != null and Chars.is_alive(p):
		var mine := Titles.realm_counties(game, p).size() if not p.titles.is_empty() else 0
		var rank := 1
		for n in sizes:
			if n > mine:
				rank += 1
		var avail := 0
		for d in game.content.all("decisions"):
			if Decisions.is_shown(game, d, p) and Decisions.can_take(game, d, p):
				avail += 1
		s.merge({"player": str(p.id), "counties": mine, "rank": rank, "tier": Titles.primary_tier(game, p) if not p.titles.is_empty() else -1,
			"gold": float(p.gold), "income": Economy.monthly_income(game, p), "strength": Economy.military_strength(game, p),
			"independent": p.liege == null, "decisions_available": avail})
	snapshots.append(s)


## Партия кончилась: род пресёкся или игрок потерял все земли.
func over() -> bool:
	return game_over != null or realm_lost != null


func finish() -> void:
	if snapshots.size() <= years:
		snapshot()


## Зонд из сохранённого итога (to_json) — пересчитать показатели без партии.
static func from_json(j: Dictionary) -> FunProbe:
	var p: FunProbe = FunProbe.new(null, int(j.years), int(j.seed))
	p.start = str(j.start)
	p.day0 = int(j.day0)
	p.call_days = Data.as_array(j.call_days).map(func(x): return int(x))
	var n: Dictionary = j.counts
	p.windows = int(n.windows)
	p.choices = int(n.choices)
	p.single = int(n.single)
	p.obvious = int(n.obvious)
	p.flat = int(n.flat)
	p.news = int(n.news)
	for k in ["seen", "first_year", "ev_obvious", "ev_flat", "decisions", "interactions", "wars_declared", "wars", "threats"]:
		p.set(k, j[k])
	p.by_year = j.by_year
	p.successions = j.successions
	p.game_over = j.get("game_over")
	p.realm_lost = j.get("realm_lost")
	p.snapshots = j.snapshots
	return p


# ------------------------------------------------------------ показатели

static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / a.size()


func _decade_sum(field: String, d: int) -> int:
	var s := 0
	for y in range(d * 10, mini((d + 1) * 10, years)):
		s += int(by_year[y][field])
	return s


## Сводные числа — плоский словарь «раздел.имя» → число (их сверяют пороги).
func metrics() -> Dictionary:
	var m := {}
	var lived := years
	if over():
		lived = mini(years, int((game_over if game_over != null else realm_lost).year) + 1)
	var decades := maxi(1, ceili(lived / 10.0))
	# поздняя игра — только у партий, доживших до конца (иначе «последнее
	# десятилетие» короткой партии — её же начало)
	var full := lived >= years
	# новизна: разные окна, новые по десятилетиям, доля самого частого
	m["novelty.distinct"] = seen.size()
	var fam := {}
	for id in seen:
		fam[str(id).get_slice(".", 0)] = true
	m["novelty.families"] = fam.size()
	var new_by := []
	for d in decades:
		new_by.append(first_year.values().filter(func(y): return int(y) / 10 == d).size())
	m["novelty.new_first_decade"] = new_by[0]
	if full:
		m["novelty.new_last_decade"] = new_by[-1]
	var top_n := 0
	for id in seen:
		top_n = maxi(top_n, int(seen[id]))
	m["novelty.top_share"] = float(top_n) / maxf(1.0, windows)
	# ритм: выбор в год, ранняя и поздняя игра, самое долгое затишье
	m["rhythm.windows_per_year"] = float(windows) / lived
	m["rhythm.choices_per_year"] = float(choices) / lived
	var early := _decade_sum("choices", 0)
	var late := _decade_sum("choices", decades - 1)
	if full:
		m["rhythm.late_vs_early"] = float(late) / maxf(1.0, early)
	var days := call_days.duplicate()
	days.push_front(day0)
	days.append(day0 + lived * 365)
	var gap := 0
	for i in range(1, days.size()):
		gap = maxi(gap, int(days[i]) - int(days[i - 1]))
	m["rhythm.longest_quiet_months"] = gap / 30.4
	var calls_late := _decade_sum("calls", decades - 1)
	var calls_early := _decade_sum("calls", 0)
	m["rhythm.calls_per_year"] = float(call_days.size()) / lived
	if full:
		m["rhythm.calls_late_vs_early"] = float(calls_late) / maxf(1.0, calls_early)
	m["rhythm.messages_per_year"] = _mean(by_year.slice(0, lived).map(func(b): return b.messages))
	m["rhythm.news_per_year"] = float(news) / lived
	# выбор: как часто ИИ за игрока выбирает почти наверняка или наугад
	m["choice.obvious_share"] = float(obvious) / maxf(1.0, choices)
	m["choice.flat_share"] = float(flat) / maxf(1.0, choices)
	m["choice.single_share"] = float(single) / maxf(1.0, windows)
	# дела игрока
	var deeds_early := _decade_sum("deeds", 0)
	var deeds_late := _decade_sum("deeds", decades - 1)
	var n_dec := 0
	for k in decisions:
		n_dec += int(decisions[k])
	var n_int := 0
	for k in interactions:
		n_int += int(interactions[k])
	m["agency.deeds_per_year"] = float(n_dec + n_int + int(wars.attack)) / lived
	m["agency.distinct_deeds"] = decisions.size() + interactions.size() + wars_declared.size()
	if full:
		m["agency.late_vs_early"] = float(deeds_late) / maxf(1.0, deeds_early)
	# снежный ком: держава игрока и самая большая держава мира
	var s0: Dictionary = snapshots[0]
	var sl: Dictionary = snapshots[-1]
	var peak := 0
	var low_after_peak := 1 << 30
	var world_max := 0.0
	for s in snapshots:
		world_max = maxf(world_max, float(s.top_counties) / maxf(1.0, s.counties_total))
		if s.has("counties"):
			if int(s.counties) > peak:
				peak = int(s.counties)
				low_after_peak = peak
			low_after_peak = mini(low_after_peak, int(s.counties))
	m["snowball.player_start"] = int(s0.get("counties", 0))
	m["snowball.player_end"] = int(sl.get("counties", 0))
	m["snowball.player_growth"] = float(sl.get("counties", 0)) / maxf(1.0, s0.get("counties", 0))
	m["snowball.player_worst_drop"] = 1.0 - float(low_after_peak) / maxf(1.0, peak) if peak > 0 else 0.0
	m["snowball.world_max_share"] = world_max
	m["snowball.independents_end_vs_start"] = float(sl.independents) / maxf(1.0, s0.independents)
	var tops := {}
	for s in snapshots:
		tops[s.top_name] = true
	m["snowball.top_changes"] = tops.size() - 1
	# поздняя игра: копится ли золото, есть ли решения
	var inc := float(sl.get("income", 0.0))
	if full:
		m["late.hoard_months"] = float(sl.get("gold", 0.0)) / inc if inc > 0.5 else 0.0
		m["late.decisions_available"] = int(sl.get("decisions_available", 0))
	# угрозы
	m["threat.defensive_wars"] = int(wars.defend)
	m["threat.wars_lost"] = int(wars.lost)
	m["threat.internal"] = int(threats.factions) + int(threats.revolts) + int(threats.schemes)
	m["threat.successions"] = successions.size()
	m["threat.game_over"] = 1 if game_over != null else 0
	m["threat.realm_lost"] = 1 if realm_lost != null else 0
	m["life.years"] = lived
	return m


func to_json() -> Dictionary:
	return {
		"start": start, "seed": seed, "years": years, "metrics": metrics(), "day0": day0, "call_days": call_days,
		"counts": {"windows": windows, "choices": choices, "single": single, "obvious": obvious, "flat": flat, "news": news},
		"seen": seen, "first_year": first_year, "ev_obvious": ev_obvious, "ev_flat": ev_flat,
		"by_year": by_year, "decisions": decisions, "interactions": interactions, "wars_declared": wars_declared,
		"wars": wars, "threats": threats, "successions": successions, "game_over": game_over, "realm_lost": realm_lost,
		"snapshots": snapshots,
	}

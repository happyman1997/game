class_name Treasury
extends RefCounted
## Казна: золото персонажа меняется только через Treasury.add — с указанием
## статьи (налоги с домена, жалованье отрядов, постройка, решение, событие,
## починка вещей…). У правителей и игрока ведётся книга: суммы по статьям
## за текущий месяц и за прошедшие (defines.treasury.history_months), запас
## казны в конце каждого месяца. Из книги — окно «Казна», прогноз и замеры.
##
## Статья — ключ, имя — локализация ledger.<ключ>. Мод может завести свои
## статьи: Treasury.add(game, c, -50, "grafts") и ключ ledger.grafts.
## Золото из скриптов (add_gold, pay_gold) попадает в статью по источнику:
## событие — events, решение — decisions, предложение — interactions,
## ежегодное постройки или района — estates; точнее — по
## defines.treasury.sources (например, on_action:on_siege_won → loot).


## Изменить казну c на amount по статье cat. regular — ежемесячная строка
## (налоги, жалованье, содержание): в окне она идёт отдельно от разовых.
static func add(game: Game, c: Dictionary, amount: float, cat: String, regular := false) -> void:
	if amount == 0.0:
		return
	c.gold = float(c.gold) + amount
	if c.titles.is_empty() and c.id != game.state.player:
		return
	var lg := _ledger(game, c)
	var cur: Dictionary = lg.cur
	cur[cat] = float(cur.get(cat, 0.0)) + amount
	if regular:
		lg.reg[cat] = true


## Статья для золота из скрипта по источнику ctx.values.__src ("event:id",
## "decision:id"…).
static func cat_of_src(game: Game, src: String) -> String:
	if src == "":
		return "other"
	var exact: Variant = game.def_val("treasury.sources", {}).get(src)
	if exact is String:
		return exact
	var kind := src.get_slice(":", 0)
	var by_kind: Variant = game.def_val("treasury.source_kinds", {}).get(kind)
	return by_kind if by_kind is String else "other"


static func month_index(date: int) -> int:
	var p := GameDate.parts(date)
	return int(p.y) * 12 + int(p.m) - 1


## Книга персонажа (заводится при первой записи): {m, cur, reg, hist}; hist —
## закрытые месяцы [{m, v: {статья: сумма}, g: казна в конце}], старые — в конце.
static func _ledger(game: Game, c: Dictionary) -> Dictionary:
	var m := month_index(game.date)
	var lg: Variant = c.get("ledger")
	if not (lg is Dictionary):
		lg = {"m": m, "cur": {}, "reg": {}, "hist": []}
		c["ledger"] = lg
	elif int(lg.m) != m:
		_roll(game, lg, m, float(c.gold))
	return lg


static func _roll(game: Game, lg: Dictionary, m: int, gold: float) -> void:
	var keep := int(game.def_num("treasury.history_months", 12))
	var hist: Array = lg.hist
	hist.push_front({"m": int(lg.m), "v": lg.cur, "g": gold})
	# пропущенные месяцы без движения — пустые
	for k in mini(m - int(lg.m) - 1, keep):
		hist.push_front({"m": int(lg.m) + 1 + k, "v": {}, "g": gold})
	while hist.size() > keep:
		hist.pop_back()
	lg.m = m
	lg.cur = {}


## Месяцы книги, от нового к старому: текущий (неполный) и закрытые.
## [{m, v: {статья: сумма}, g: казна в конце (у текущего — сейчас), current}]
static func months(game: Game, c: Dictionary) -> Array:
	var now := month_index(game.date)
	var lg: Variant = c.get("ledger")
	if not (lg is Dictionary):
		return [{"m": now, "v": {}, "g": float(c.gold), "current": true}]
	# книга не трогается: если месяц сменился без записей, он закрыт «на лету»
	if int(lg.m) == now:
		return [{"m": now, "v": lg.cur, "g": float(c.gold), "current": true}] + lg.hist
	var out := [{"m": now, "v": {}, "g": float(c.gold), "current": true}]
	for k in range(now - 1, int(lg.m), -1):
		out.append({"m": k, "v": {}, "g": float(c.gold)})
	out.append({"m": int(lg.m), "v": lg.cur, "g": float(c.gold)})
	out.append_array(lg.hist)
	return out.slice(0, int(game.def_num("treasury.history_months", 12)) + 1)


## Суммы по статьям за последние n закрытых месяцев (и текущий, если with_current).
static func totals(game: Game, c: Dictionary, n: int = 12, with_current := true) -> Dictionary:
	var out := {}
	var ms := months(game, c)
	var taken := 0
	for x in ms:
		if x.get("current", false) and not with_current:
			continue
		if not x.get("current", false):
			if taken >= n:
				break
			taken += 1
		for k in x.v:
			out[k] = float(out.get(k, 0.0)) + float(x.v[k])
	return out


## Ежемесячные статьи (налоги, жалованье, содержание) — их книга знает по
## записям; остальные — разовые.
static func is_regular(c: Dictionary, cat: String) -> bool:
	var lg: Variant = c.get("ledger")
	return lg is Dictionary and lg.reg.has(cat)


## Прогноз: {monthly — чистый ежемесячный доход сейчас, oneoff — среднее
## разовое сальдо в месяц за закрытые месяцы книги, months_left — через
## сколько месяцев казна уйдёт в минус (-1 — не уйдёт)}.
static func forecast(game: Game, c: Dictionary) -> Dictionary:
	var monthly := Economy.monthly_income(game, c)
	var closed := 0
	var oneoff := 0.0
	for x in months(game, c):
		if x.get("current", false):
			continue
		closed += 1
		for k in x.v:
			if not is_regular(c, k):
				oneoff += float(x.v[k])
	var avg := oneoff / closed if closed > 0 else 0.0
	var left := -1
	if monthly < 0.0:
		left = maxi(0, floori(maxf(0.0, float(c.gold)) / -monthly))
	return {"monthly": monthly, "oneoff": avg, "months_left": left}

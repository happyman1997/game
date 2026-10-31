class_name Biomes
extends EngineFeature
## Местность: у земли есть состояние, и его меняют люди, природа и война.
## Дремучий лес, лес, вырубка, равнина, тучная и истощённая пашня, топь и
## осушенный луг, пустошь, пожарище… Карта нарезана на клетки (Land,
## engine/world/land.gd; ядро на Rust), у каждой клетки — своё состояние;
## графство — смесь местностей. От долей зависят доход и набор (modifiers
## местностей), рост, оборона, движение, полки и районы (по состоянию или
## его группе — terrain.group: дремучий лес — тоже лес), здоровье живущих в
## столице (capital_modifiers).
##
## Люди: владелец графства начинает работу (land_works) — свести лес,
## распахать вырубку, осушить топь, оставить пашню под пар… Работа идёт
## участками: участок — доля клеток графства (share, по умолчанию
## defines.land.patch_share), растёт связным пятном от уже возделанной земли
## (grow_from — поле расширяют от поля, лес рубят от опушки). Участок идёт
## месяцами (быстрее при хорошем управлении и land_work_speed), стоит золота,
## пока идёт — даёт свои модификаторы графству (during, по доле участка), а
## по окончании меняет свои клетки и запускает on_complete — изнанку (лесной
## народ ропщет, у соседей ниже разливы, и все знают, чьих рук дело). Потом
## работа берётся за следующий участок — пока есть подходящая земля и
## золото, пока владелец не остановит её (repeat) и, у ИИ, пока ему хочется
## (ai_will_do × defines.land.ai_continue_mult, %).
## Природа: раз в год каждая клетка может сама перейти в другое состояние
## (terrain.drift: вырубка зарастает от опушки, брошенная пашня дичает, пашня
## устаёт, пожарище затягивается). Клетки под работой природа не трогает.
## Война и события: эффект set_terrain — участок графства (from, share).
## Летопись земли: p.land_log — [дата, было, стало, кто, причина, клеток];
## так видно, кто сделал мир таким. Одинаковые перемены за год — одной строкой.
##
## Данные:
##   terrain.<id>: { group, color, pattern, height, defense, movement, attrition,
##     development_growth,
##     modifiers: { tax_mult, levy_mult, … },   — графству (по доле клеток)
##     capital_modifiers: { health, … },       — правителю, чья столица здесь (по доле)
##     start: { местность: доля, … },          — начальная раскладка (Land)
##     drift: [ { to, years, near, trigger, cause } ] }  — природа (шанс клетки 1/years в год)
##   land_works.<id>: { icon, from: [состояния], to, grow_from: [местности или группы],
##     share, months, cost: { gold },  — участок: доля клеток, месяцы и золото на участок
##     potential: { … },      — где можно (скоуп — провинция; root и scope:actor — кто начинает)
##     during: { … },         — модификаторы графству, пока идёт работа (× доля участка)
##     on_complete: [ … ],    — по окончании участка (скоуп — провинция; root и scope:actor — кто ведёт)
##     ai_will_do: { … } }    — желание ИИ (root — правитель, scope:province)
##   defines.land: { cell_size, patch_share, history_size, speed_per_stewardship,
##     min_speed_mult, ai_frequency_months, ai_reserve_gold, ai_counties_per_work,
##     ai_continue_mult }
## Хуки: land.changed {province, from, to, by, cause, cells}, land.work_started,
## land.work_done {province, work, by, cells} (на каждый участок), land.work_ended
## {province, work, by, why}; on_action on_land_changed (root — владелец
## графства, scope:province, scope:actor — кто изменил; не для природы).

const OWNER := "core/biomes"


func _init() -> void:
	id = "biomes"
	doc = "Местность: живая земля по клеткам — работы правителей участками, природа и война меняют её; летопись земли"


static func _p(game: Game, pid: String) -> Variant:
	return game.state.provinces.get(pid)


static func _seed(game: Game) -> int:
	return int(game.rng.next() * 2147483647.0)


# ------------------------------------------------------------ состояние и летопись

static func history_of(game: Game, pid: String) -> Array:
	var p: Variant = _p(game, pid)
	return Data.as_array(p.get("land_log")) if p != null else []


static func _log(game: Game, p: Dictionary, from: String, to: String, by: Variant, cause: String, n: int) -> void:
	var log: Array = Data.as_array(p.get("land_log")).duplicate()
	if not log.is_empty():
		var last: Array = Data.as_array(log[-1])
		if last.size() > 5 and str(last[1]) == from and str(last[2]) == to and last[3] == by and str(last[4]) == cause \
				and GameDate.parts(int(last[0])).y == GameDate.parts(game.date).y:
			log[-1] = [game.date, from, to, by, cause, int(last[5]) + n]
			p["land_log"] = log
			return
	log.append([game.date, from, to, by, cause, n])
	var keep := int(game.def_num("land.history_size", 12))
	p["land_log"] = log.slice(maxi(0, log.size() - keep))


## Сменить местность клеток графства; в летопись — кто и почему.
## kind: "event" — с on_action и вестью владельцу-игроку, "work" — с
## on_action без вести, "nature" — тихо. Возвращает, сколько клеток изменилось.
static func set_cells(game: Game, pid: String, cells: PackedInt32Array, to: String, by: Variant = null, cause: String = "", kind: String = "event") -> int:
	var p: Variant = _p(game, pid)
	if p == null or not game.content.has("terrain", to):
		return 0
	var r := game.land().change(pid, cells, to)
	if int(r.n) <= 0:
		return 0
	var from := str(r.from)
	_log(game, p, from, to, by, cause, int(r.n))
	game.state["land_ver"] = int(game.state.get("land_ver", 0)) + 1
	game.stat_cache.erase("prov:" + pid)
	var t: Variant = game.state.titles.get(pid)
	var holder: Variant = game.ch(t.holder) if t != null else null
	if holder != null:
		game.mark_chars_dirty([holder.id])
	game.emit("land.changed", {"province": pid, "from": from, "to": to, "by": by, "cause": cause, "cells": int(r.n)})
	if holder != null and kind != "nature":
		var scopes := {"province": {"type": "province", "id": pid}}
		if by != null and game.ch(by) != null:
			scopes["actor"] = {"type": "character", "id": by}
		game.on_action("on_land_changed", {"type": "character", "id": holder.id}, scopes)
		if kind == "event" and game.is_player(holder.id) and (by == null or not game.is_player(by)):
			game.message(game.loc.t("msg.land_changed", {"place": game.scope_name({"type": "province", "id": pid}),
				"from": game.name_of("terrain", from), "to": game.name_of("terrain", to),
				"share": roundi(100.0 * int(r.n) / maxf(1.0, game.land().count(pid)))}), "info", {"type": "province", "id": pid})
	return int(r.n)


## Местности, подходящие под from (id или группы; null — любые), кроме to.
static func _expand(game: Game, from: Variant, to: String) -> Array:
	var land := game.land()
	var out := []
	for t in land.ids:
		if t != to and (from == null or land.matches(t, from)):
			out.append(t)
	return out


## Изменить местность участка графства: share — доля клеток (1 — всё
## подходящее), from — какие местности (id или группы; null — любые).
## Участок растёт связным пятном. Возвращает, сколько клеток изменилось.
static func set_terrain(game: Game, pid: String, to: String, by: Variant = null, cause: String = "", from: Variant = null, share: float = 1.0) -> int:
	var land := game.land()
	var n := land.count(pid)
	if n == 0 or not game.content.has("terrain", to):
		return 0
	var list := _expand(game, from, to)
	var want := n if share >= 1.0 else maxi(1, roundi(n * clampf(share, 0.0, 1.0)))
	var cells := land.patch(pid, list, [to], want, _seed(game))
	return set_cells(game, pid, cells, to, by, cause)


# ------------------------------------------------------------ работы

static func work_of(game: Game, pid: String) -> Variant:
	var p: Variant = _p(game, pid)
	return p.get("land_work") if p != null else null


## Работы, для которых в графстве есть подходящая земля.
static func works_here(game: Game, pid: String) -> Array:
	var land := game.land()
	var m := land.mix(pid)
	return game.content.all("land_works").filter(func(d):
		for t in Data.as_array(d.get("from")):
			if m.has(str(t)):
				return true
		return false)


## Клеток в участке работы.
static func patch_size(game: Game, pid: String, d: Dictionary) -> int:
	var n := game.land().count(pid)
	return maxi(1, roundi(n * Data.num(d.get("share"), game.def_num("land.patch_share", 0.25))))


## Доля земли графства, на которой работа ещё возможна (её from).
static func room_for(game: Game, pid: String, d: Dictionary) -> float:
	var m := game.land().mix(pid)
	var s := 0.0
	for t in Data.as_array(d.get("from")):
		s += float(m.get(str(t), 0.0))
	return s


static func months_for(game: Game, c: Dictionary, d: Dictionary) -> int:
	var speed := Stats.skill(game, c, "stewardship") * game.def_num("land.speed_per_stewardship", 0.02) + Stats.stat(game, c, "land_work_speed")
	var mult := clampf(1.0 - speed, game.def_num("land.min_speed_mult", 0.4), 1.5)
	return maxi(2, roundi(Data.num(d.get("months"), 12) * mult))


static func cost_for(game: Game, c: Dictionary, d: Dictionary) -> float:
	var cost: Variant = d.get("cost")
	var gold := Data.num(cost.get("gold")) if cost is Dictionary else 0.0
	return roundf(gold * maxf(0.0, 1.0 + Stats.stat(game, c, "build_cost_mult")))


static func _ctx(game: Game, c: Dictionary, pid: String) -> ScriptContext:
	var ctx := ScriptContext.make(game, {"type": "character", "id": c.id}, {"province": {"type": "province", "id": pid}, "actor": {"type": "character", "id": c.id}})
	ctx.values["__src"] = "land_work"
	return ctx


## Почему c не может начать работу wid на этой земле (пусто — может).
static func blockers(game: Game, c: Dictionary, pid: String, wid: String) -> Array:
	var d: Variant = game.content.get_def("land_works", wid)
	var p: Variant = _p(game, pid)
	if d == null or p == null:
		return ["land.no_work"]
	var out := []
	var t: Variant = game.state.titles.get(pid)
	if t == null or t.holder != c.id:
		out.append("land.not_yours")
	if room_for(game, pid, d) <= 0.0:
		out.append("land.wrong_terrain")
	if p.get("land_work") != null:
		out.append("land.busy")
	if p.get("occupant") != null or p.get("siege") != null:
		out.append("land.at_war")
	if d.get("potential") != null:
		var ctx := _ctx(game, c, pid)
		if not Interp.eval_trigger(ctx, {"type": "province", "id": pid}, d.potential):
			out.append("land.not_here")
	if float(c.gold) < cost_for(game, c, d):
		out.append("land.no_gold")
	return out


static func _grow_from(d: Dictionary) -> Array:
	var g: Variant = d.get("grow_from")
	return Data.as_array(g) if g != null else [d.get("to")]


## Взять следующий участок: заплатить, выбрать клетки, назначить срок.
static func _next_patch(game: Game, c: Dictionary, pid: String, d: Dictionary, w: Dictionary) -> bool:
	var cells := game.land().patch(pid, Data.as_array(d.get("from")), _grow_from(d), patch_size(game, pid, d), _seed(game))
	if cells.is_empty():
		return false
	var cost := cost_for(game, c, d)
	if cost > 0.0:
		Treasury.add(game, c, -cost, "land_works")
	var months := months_for(game, c, d)
	w["cells"] = Array(cells)
	w["start"] = game.date
	w["until"] = game.date + months * 30
	w["months"] = months
	game.state["land_ver"] = int(game.state.get("land_ver", 0)) + 1
	game.stat_cache.erase("prov:" + pid)
	return true


## Начать работу; repeat — браться за следующие участки, пока есть земля.
static func start(game: Game, c: Dictionary, pid: String, wid: String, repeat: bool = true) -> bool:
	if not blockers(game, c, pid, wid).is_empty():
		return false
	var d: Dictionary = game.content.get_def("land_works", wid)
	var w := {"id": wid, "by": c.id, "done": 0, "repeat": repeat}
	if not _next_patch(game, c, pid, d, w):
		return false
	_p(game, pid)["land_work"] = w
	game.emit("land.work_started", {"province": pid, "work": wid, "by": c.id})
	return true


## Вести работу дальше после этого участка или остановиться на нём.
static func set_repeat(game: Game, pid: String, on: bool) -> void:
	var w: Variant = work_of(game, pid)
	if w != null:
		w["repeat"] = on


static func cancel(game: Game, pid: String) -> void:
	var p: Variant = _p(game, pid)
	if p == null or p.get("land_work") == null:
		return
	p.erase("land_work")
	game.state["land_ver"] = int(game.state.get("land_ver", 0)) + 1
	game.stat_cache.erase("prov:" + pid)


## Клетки, на которых сейчас идёт работа (для карты).
static func work_cells(game: Game, pid: String) -> Array:
	var w: Variant = work_of(game, pid)
	return Data.as_array(w.get("cells")) if w != null else []


## Доля участка в графстве (для during).
static func patch_share_of(game: Game, pid: String) -> float:
	var n := game.land().count(pid)
	return clampf(float(work_cells(game, pid).size()) / maxf(1.0, n), 0.0, 1.0)


## Доля сделанного на нынешнем участке, 0…1.
static func progress(game: Game, pid: String) -> float:
	var w: Variant = work_of(game, pid)
	if w == null:
		return 0.0
	return clampf(float(game.date - int(w.start)) / maxf(1.0, float(int(w.until) - int(w.start))), 0.0, 1.0)


static func months_left(game: Game, pid: String) -> int:
	var w: Variant = work_of(game, pid)
	return maxi(0, ceili((int(w.until) - game.date) / 30.0)) if w != null else 0


## Почему работа не пойдёт на следующий участок ("" — пойдёт).
static func _stop_reason(game: Game, by: Variant, pid: String, d: Dictionary, w: Dictionary) -> String:
	var p: Dictionary = _p(game, pid)
	var t: Variant = game.state.titles.get(pid)
	if by == null or not Chars.is_alive(by) or t == null or t.holder != by.id:
		return "owner"
	if not bool(w.get("repeat", true)):
		return "stopped"
	if room_for(game, pid, d) <= 0.0:
		return "done"
	if p.get("occupant") != null or p.get("siege") != null:
		return "war"
	if d.get("potential") != null and not Interp.eval_trigger(_ctx(game, by, pid), {"type": "province", "id": pid}, d.potential):
		return "done"
	var cost := cost_for(game, by, d)
	if float(by.gold) < cost:
		return "gold"
	if game.ai_controls(by.id):
		if float(by.gold) - cost < game.def_num("land.ai_reserve_gold", 50):
			return "gold"
		var ctx := _ctx(game, by, pid)
		var will := Interp.eval_value(ctx, ctx.root, d.get("ai_will_do", 0)) * game.def_num("land.ai_continue_mult", 2.5)
		if game.rng.next() * 100.0 >= will:
			return "enough"
	return ""


static func _finish_patch(game: Game, pid: String) -> void:
	var p: Dictionary = _p(game, pid)
	var w: Dictionary = p.land_work
	var d: Variant = game.content.get_def("land_works", str(w.id))
	if d == null:
		cancel(game, pid)
		return
	var land := game.land()
	var from := Data.as_array(d.get("from"))
	# клетки, которые за это время не изменила природа или война
	var cells := PackedInt32Array()
	for c in Data.as_array(w.get("cells")):
		if from.has(land.terrain_at(int(c))):
			cells.append(int(c))
	var by: Variant = game.ch(w.by)
	var n := set_cells(game, pid, cells, str(d.to), w.by, str(w.id), "work")
	w["done"] = int(w.get("done", 0)) + 1
	if by != null and Chars.is_alive(by) and n > 0:
		var ctx := _ctx(game, by, pid)
		Interp.run_effect(ctx, {"type": "province", "id": pid}, d.get("on_complete"))
	game.emit("land.work_done", {"province": pid, "work": str(w.id), "by": w.by if by != null else null, "cells": n})
	var why := _stop_reason(game, by, pid, d, w)
	if why == "" and _next_patch(game, by, pid, d, w):
		return
	if why == "":
		why = "done"
	cancel(game, pid)
	game.emit("land.work_ended", {"province": pid, "work": str(w.id), "by": w.by, "why": why})
	var t: Variant = game.state.titles.get(pid)
	for who in [w.by, t.holder if t != null else null]:
		if who != null and game.is_player(who):
			game.message(game.loc.t("msg.land_work_done", {"place": game.scope_name({"type": "province", "id": pid}),
				"work": game.name_of("land_works", str(w.id)), "n": int(w.done), "why": game.loc.t("land.end." + why)}),
				"good" if why == "done" else "info", {"type": "province", "id": pid})
			break


# ------------------------------------------------------------ время

## Ежемесячно: участки, дошедшие до срока, кончаются; двенадцатая часть
## графств проверяет, не берёт ли своё природа.
static func monthly(game: Game) -> void:
	var month := int(GameDate.parts(game.date).m)
	var i := 0
	for pid in game.state.provinces:
		var p: Dictionary = game.state.provinces[pid]
		var w: Variant = p.get("land_work")
		if w != null and game.date >= int(w.until):
			_finish_patch(game, pid)
		if i % 12 == month - 1:
			_drift(game, pid)
		i += 1


## Природа графства за год: по правилам drift каждой его местности.
static func _drift(game: Game, pid: String) -> void:
	var land := game.land()
	var m := land.mix(pid)
	if m.is_empty():
		return
	var busy := {}
	for c in work_cells(game, pid):
		busy[int(c)] = true
	var ctx: ScriptContext = null
	for t in m.keys():
		var td: Variant = game.content.get_def("terrain", t)
		if td == null or not (td.get("drift") is Array):
			continue
		for rule in td.drift:
			if not (rule is Dictionary) or not game.content.has("terrain", str(rule.get("to", ""))):
				continue
			if ctx == null:
				ctx = ScriptContext.make(game, {"type": "province", "id": pid}, {"province": {"type": "province", "id": pid}})
			if rule.get("trigger") != null and not Interp.eval_trigger(ctx, ctx.root, rule.trigger):
				continue
			var years := Interp.eval_value(ctx, ctx.root, rule.get("years", 20))
			if years <= 0.0:
				continue
			var picked := land.drift_pick(pid, t, 1.0 / years, rule.get("near"), _seed(game))
			if picked.is_empty():
				continue
			var cells := PackedInt32Array()
			for c in picked:
				if not busy.has(c):
					cells.append(c)
			set_cells(game, pid, cells, str(rule.to), null, str(rule.get("cause", "nature")), "nature")


## ИИ-правитель раз в ai_frequency_months думает, не взяться ли за землю.
static func monthly_char(game: Game, c: Dictionary) -> void:
	if c.titles.is_empty() or not game.ai_controls(c.id) or c.get("prison") != null:
		return
	var freq := maxi(1, int(game.def_num("land.ai_frequency_months", 12)))
	if (Treasury.month_index(game.date) + absi(hash(c.id))) % freq != 0:
		return
	var dom := Titles.domain_counties(game, c)
	if dom.is_empty():
		return
	var busy := 0
	for pid in dom:
		var w: Variant = work_of(game, pid)
		if w != null and w.by == c.id:
			busy += 1
	if busy >= maxi(1, dom.size() / maxi(1, int(game.def_num("land.ai_counties_per_work", 4)))):
		return
	var reserve := game.def_num("land.ai_reserve_gold", 50)
	var best: Variant = null
	var best_w := 0.0
	for pid in dom:
		for d in works_here(game, pid):
			if float(c.gold) - cost_for(game, c, d) < reserve or not blockers(game, c, pid, d.id).is_empty():
				continue
			var ctx := _ctx(game, c, pid)
			var w := Interp.eval_value(ctx, ctx.root, d.get("ai_will_do", 0))
			if w > best_w:
				best_w = w
				best = [pid, d.id]
	if best != null and game.rng.next() * 100.0 < best_w:
		start(game, c, best[0], best[1])


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	engine.systems.register("biomes", {"id": "biomes", "order": 18, "on_month": Biomes.monthly, "on_character_month": Biomes.monthly_char}, OWNER)
	# пока идёт работа — её модификаторы графству (по доле участка)
	engine.province_modifier_providers.register("biomes", {"fn": func(game: Game, pid: String) -> Variant:
		var w: Variant = Biomes.work_of(game, pid)
		if w == null:
			return null
		var d: Variant = game.content.get_def("land_works", str(w.id))
		if d == null or not (d.get("during") is Dictionary):
			return null
		var k := Biomes.patch_share_of(game, pid)
		var out := {}
		for key in d.during:
			out[key] = Data.num(d.during[key]) * k
		return out
	}, OWNER)
	# столица в топи — лихорадка и прочее (capital_modifiers местностей по долям)
	engine.modifier_providers.register("biomes", {"fn": func(game: Game, c: Dictionary) -> Variant:
		if c.titles.is_empty():
			return null
		var cap: Variant = Titles.capital_of(game, c)
		if cap == null:
			return null
		var m := game.land().mods(cap, "capital_modifiers")
		return m if not m.is_empty() else null
	}, OWNER)
	engine.content_validators.register("land_works", func(e: GameEngine, v: ScriptValidator):
		for d in e.content.all("land_works"):
			var w := "land_works/" + str(d.id)
			for t in Data.as_array(d.get("from")):
				v.ref("terrain", t, w + " from")
			v.ref("terrain", d.get("to"), w + " to")
			for t in Data.as_array(d.get("grow_from")):
				Biomes._ref_terrain_or_group(e, v, t, w + " grow_from")
			v.trigger(d.get("potential"), w + " potential")
			v.effect(d.get("on_complete"), w + " on_complete")
			v.value(d.get("ai_will_do"), w + " ai_will_do")
		for t in e.content.all("terrain"):
			if t.get("group") != null:
				v.ref("terrain", t.group, "terrain/%s group" % t.id)
			if t.get("start") is Dictionary:
				for s in t.start:
					v.ref("terrain", s, "terrain/%s start" % t.id)
			for rule in Data.as_array(t.get("drift")):
				if rule is Dictionary:
					v.ref("terrain", rule.get("to"), "terrain/%s drift" % t.id)
					for n in Data.as_array(rule.get("near")):
						Biomes._ref_terrain_or_group(e, v, n, "terrain/%s drift near" % t.id)
					v.trigger(rule.get("trigger"), "terrain/%s drift" % t.id)
	, OWNER)
	# старые сохранения: работа на всё графство — продолжается участками
	engine.hooks.on("game.loaded", func(p):
		var g: Game = p.game
		for pid in g.state.provinces:
			var w: Variant = g.state.provinces[pid].get("land_work")
			if w is Dictionary and not w.has("cells"):
				var d: Variant = g.content.get_def("land_works", str(w.id))
				if d == null:
					continue
				var cells := g.land().patch(pid, Data.as_array(d.get("from")), Biomes._grow_from(d), Biomes.patch_size(g, pid, d), 1)
				w["cells"] = Array(cells)
				w["done"] = 0
				w["repeat"] = true
	, 0, OWNER)


static func _ref_terrain_or_group(e: GameEngine, v: ScriptValidator, t: Variant, where: String) -> void:
	for d in e.content.all("terrain"):
		if str(d.id) == str(t) or str(d.get("group", "")) == str(t):
			return
	v.ref("terrain", t, where)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var PR := ["province"]
	r.triggers.register("has_land_work", {"scopes": PR, "doc": "На земле идёт работа: has_land_work: yes | <id работы>", "eval": func(ctx, s, arg):
		var w: Variant = Biomes.work_of(ctx.game, s.id)
		if arg is String and arg != "yes" and arg != "no":
			return w != null and str(w.id) == arg
		return (w != null) == ScriptContext.is_yes(arg)
	}, OWNER)
	r.triggers.register("has_holder", {"scopes": PR, "doc": "У графства есть владелец (нет — земля брошена): has_holder: yes", "eval": func(ctx, s, arg):
		var t: Variant = ctx.game.state.titles.get(s.id)
		return (t != null and t.holder != null) == ScriptContext.is_yes(arg)
	}, OWNER)
	r.values.register("land_work_months_left", {"scopes": PR, "doc": "Сколько месяцев осталось нынешнему участку работы на земле", "get": func(ctx, s, _a):
		return float(Biomes.months_left(ctx.game, s.id))
	}, OWNER)
	r.effects.register("set_terrain", {"scopes": PR,
		"doc": "Изменить местность участка графства: set_terrain: burnt или { to, from: [местности или группы], share: 0.25, cause } (без from — любая земля, без share — вся; в летопись — root, если это персонаж)",
		"apply": func(ctx, s, arg):
			var to := str(arg.get("to", "")) if arg is Dictionary else str(arg)
			var cause := str(arg.get("cause", "event")) if arg is Dictionary else "event"
			var from: Variant = arg.get("from") if arg is Dictionary else null
			var share := Data.num(arg.get("share"), 1.0) if arg is Dictionary else 1.0
			var by: Variant = ctx.root.id if ctx.root.get("type") == "character" else null
			Biomes.set_terrain(ctx.game, s.id, to, by, cause, from, share),
		"describe": func(ctx, s, arg):
			var to := str(arg.get("to", "")) if arg is Dictionary else str(arg)
			var share := Data.num(arg.get("share"), 1.0) if arg is Dictionary else 1.0
			if share < 1.0:
				return ctx.game.loc.t("fx.set_terrain_part", {"place": ctx.game.scope_name(s), "to": ctx.game.name_of("terrain", to), "n": roundi(share * 100.0)})
			return ctx.game.loc.t("fx.set_terrain", {"place": ctx.game.scope_name(s), "to": ctx.game.name_of("terrain", to)}),
	}, OWNER)
	r.effects.register("start_land_work", {"scopes": PR, "doc": "Начать работу на земле от имени root (он платит): start_land_work: <id>",
		"apply": func(ctx, s, arg):
			var c: Variant = ctx.game.ch(ctx.root.id) if ctx.root.get("type") == "character" else null
			if c != null:
				Biomes.start(ctx.game, c, s.id, str(arg)),
		"describe": func(ctx, s, arg):
			return ctx.game.loc.t("fx.start_land_work", {"place": ctx.game.scope_name(s), "work": ctx.game.name_of("land_works", str(arg))}),
	}, OWNER)
	r.effects.register("end_land_work", {"scopes": PR, "doc": "Прервать работу на земле (без возврата затрат)",
		"apply": func(ctx, s, _a): Biomes.cancel(ctx.game, s.id),
		"describe": func(ctx, s, _a): return ctx.game.loc.t("fx.end_land_work", {"place": ctx.game.scope_name(s)}),
	}, OWNER)

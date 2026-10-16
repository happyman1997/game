extends SceneTree
## Замер интереса: партии из кресла игрока на автопилоте, отчёт и пороги.
##
## Всё сразу (партии идут параллельно отдельными процессами):
##   godot --headless --path . -s tools/fun_report.gd -- [--starts harold,bleddyn]
##       [--seeds 1,2] [--years 50] [--jobs 4] [--out docs/FUN_REPORT.md] [--strict]
## Одна партия в JSON:
##   godot --headless --path . -s tools/fun_report.gd -- --run --start harold --seed 1 --years 50 --json out.json
## Свести готовые JSON в отчёт:
##   godot --headless --path . -s tools/fun_report.gd -- --merge a.json,b.json --out report.md
##
## Старты, сиды, годы и пороги по умолчанию — tools/fun_gates.yaml.
## --strict: выйти с кодом 1, если провален порог уровня must.

const GATES := "res://tools/fun_gates.yaml"


func _init() -> void:
	var a := ToolCommon.args()
	if a.has("run"):
		_run_one(a)
	elif a.has("merge"):
		quit(_report(a, Array(str(a.merge).split(",", false))))
	else:
		_drive(a)


func _gates() -> Dictionary:
	var r := Yaml.parse(FileAccess.get_file_as_string(GATES), GATES)
	if not r.ok:
		push_error(r.error)
		return {}
	return r.value


# ------------------------------------------------------------ одна партия

func _run_one(a: Dictionary) -> void:
	var e := ToolCommon.engine(a)
	var years := int(a.get("years", 50))
	var seed := int(a.get("seed", 1))
	var start := str(a.get("start", "harold"))
	var bm: String = a.get("bookmark", e.bookmarks()[0].id)
	var g := e.new_game(bm, seed)
	if g.ch(start) == null:
		push_error("Нет персонажа \"%s\"" % start)
		quit(1)
		return
	g.select_player(start)
	g.autopilot = true
	var probe := FunProbe.new(g, years, seed)
	var t0 := Time.get_ticks_msec()
	for y in years:
		for d in 365:
			g.tick()
			probe.day()
		if probe.over():
			break
		if y % 10 == 9:
			print("[%s #%d] год %d (%.0f с)" % [start, seed, y + 1, (Time.get_ticks_msec() - t0) / 1000.0])
	probe.finish()
	var out := probe.to_json()
	out["bookmark"] = bm
	out["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
	var path := str(a.get("json", "user://fun_%s_%d.json" % [start, seed]))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	quit()


# ------------------------------------------------------------ все партии

func _drive(a: Dictionary) -> void:
	var cfg := _gates()
	var starts: Array = Array(str(a.starts).split(",", false)) if a.has("starts") else Data.as_array(cfg.get("starts", ["harold"]))
	var seeds: Array = Array(str(a.seeds).split(",", false)) if a.has("seeds") else Data.as_array(cfg.get("seeds", [1]))
	var years := int(a.get("years", cfg.get("years", 50)))
	var jobs := maxi(1, int(a.get("jobs", OS.get_processor_count())))
	var dir := str(a.get("dir", OS.get_user_data_dir().path_join("fun_runs")))
	DirAccess.make_dir_recursive_absolute(dir)
	var queue := []
	for s in starts:
		for sd in seeds:
			queue.append({"start": str(s), "seed": int(sd), "json": dir.path_join("fun_%s_%d.json" % [s, int(sd)])})
	for q in queue:
		if FileAccess.file_exists(q.json):
			DirAccess.remove_absolute(q.json)
	var exe := OS.get_executable_path()
	var root := ProjectSettings.globalize_path("res://")
	var running := []
	var t0 := Time.get_ticks_msec()
	print("Замер интереса: %d партий по %d лет, по %d одновременно" % [queue.size(), years, jobs])
	while not queue.is_empty() or not running.is_empty():
		while not queue.is_empty() and running.size() < jobs:
			var q: Dictionary = queue.pop_front()
			var args := ["--headless", "--path", root, "-s", "tools/fun_report.gd", "--", "--run",
				"--start", q.start, "--seed", str(q.seed), "--years", str(years), "--json", q.json]
			if a.has("mods"):
				args += ["--mods", str(a.mods)]
			q["pid"] = OS.create_process(exe, args)
			running.append(q)
		OS.delay_msec(1000)
		for r in running:
			if not OS.is_process_running(int(r.pid)):
				print("  сыграна: %s #%d%s (%.0f с)" % [r.start, int(r.seed), "" if FileAccess.file_exists(r.json) else " — без результата",
					(Time.get_ticks_msec() - t0) / 1000.0])
		running = running.filter(func(r): return OS.is_process_running(int(r.pid)))
	print("Партии сыграны за %.0f с" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var files := []
	for s in starts:
		for sd in seeds:
			files.append(dir.path_join("fun_%s_%d.json" % [s, int(sd)]))
	quit(_report(a, files))


# ------------------------------------------------------------ отчёт

## Пишет отчёт; возвращает код выхода (1 — провален must при --strict).
func _report(a: Dictionary, files: Array) -> int:
	var runs := []
	for p in files:
		if not FileAccess.file_exists(p):
			print("Нет результата партии: ", p)
			continue
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if j is Dictionary:
			# показатели — заново, по нынешним правилам зонда
			if j.has("counts"):
				j.metrics = FunProbe.from_json(j).metrics()
			runs.append(j)
	if runs.is_empty():
		print("Нечего сводить")
		return 1
	var e := ToolCommon.engine(a)
	var g := e.new_game(str(runs[0].get("bookmark", e.bookmarks()[0].id)), 1) # для имён
	var cfg := _gates()
	var lines := []
	var years := int(runs[0].years)
	lines.append("# Замер интереса")
	lines.append("")
	lines.append("Партий: %d по %d лет (%s). ИИ ведёт игрока на автопилоте по тем же правилам, что всех; отчёт собран %s." % [
		runs.size(), years, ", ".join(runs.map(func(r): return "%s #%d" % [_who(g, r.start), int(r.seed)])), Time.get_date_string_from_system()])
	lines.append("")
	lines.append("Как читать: «окно» — событие игрока с вариантами, «выбор» — окно с двумя вариантами и больше, «вызов» — то, что мир бросает игроку (выбор, война, фракция, бунт, заговор, смена правителя), «дело» — то, что делает игрок (решение, предложение, объявленная война). Пороги — `tools/fun_gates.yaml`, сборщик — `tools/fun_probe.gd`.")
	lines.append("")
	# пороги
	var failed_must := 0
	var failed_goal := 0
	lines.append("## Пороги")
	lines.append("")
	lines.append("| | Показатель | Значение | Порог | Смысл |")
	lines.append("|---|---|---|---|---|")
	var gates: Dictionary = cfg.get("gates", {})
	for gid in gates:
		var gd: Dictionary = gates[gid]
		var vals: Array = runs.filter(func(r): return r.metrics.has(gd.metric)).map(func(r): return float(r.metrics[gd.metric]))
		var agg := str(gd.get("agg", "mean"))
		var lim := ("≥ %s" % _num(gd.min)) if gd.get("min") != null else ("≤ %s" % _num(gd.max))
		if vals.is_empty():
			lines.append("| — | `%s` | нет данных | %s | %s |" % [gd.metric, lim, str(gd.get("doc", ""))])
			continue
		var v := _agg(vals, agg)
		var ok := (gd.get("min") == null or v >= float(gd.min)) and (gd.get("max") == null or v <= float(gd.max))
		var must := str(gd.get("level", "goal")) == "must"
		if not ok:
			if must:
				failed_must += 1
			else:
				failed_goal += 1
		var mark := "✅" if ok else ("❌" if must else "⚠️")
		lines.append("| %s | `%s`%s | %s | %s | %s |" % [mark, gd.metric, "" if agg == "mean" else " (%s)" % {"max": "наибольшее", "min": "наименьшее"}.get(agg, agg),
			_spread(vals, v), lim, str(gd.get("doc", ""))])
	lines.append("")
	lines.append("Итог: целей не достигнуто — %d, провалов здравого смысла — %d. Показатели поздней игры считаются только по партиям, дожившим до конца." % [failed_goal, failed_must])
	lines.append("")
	# по партиям
	lines.append("## По партиям")
	lines.append("")
	lines.append("| Старт | Окон | Разных | Выбор в год | Затишье, мес | Дел в год | Графств: начало → конец | Войн против | Смен правителя | Время счёта |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|")
	for r in runs:
		var m: Dictionary = r.metrics
		var wins := 0
		for k in r.seen:
			wins += int(r.seen[k])
		lines.append("| %s #%d | %d | %d | %.1f | %.0f | %.1f | %d → %d | %d | %d%s | %.0f с |" % [_who(g, r.start), int(r.seed), wins, int(m["novelty.distinct"]),
			m["rhythm.choices_per_year"], m["rhythm.longest_quiet_months"], m["agency.deeds_per_year"],
			int(m["snowball.player_start"]), int(m["snowball.player_end"]), int(m["threat.defensive_wars"]), int(m["threat.successions"]),
			_end_note(r), float(r.get("seconds", 0))])
	lines.append("")
	_section_rhythm(lines, runs, years)
	_section_novelty(lines, g, runs)
	_section_choice(lines, g, runs)
	_section_snowball(lines, g, runs, years)
	_section_deeds(lines, g, runs)
	_section_threats(lines, runs)
	var out := str(a.get("out", "user://fun_report.md"))
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("Отчёт: %s — целей не достигнуто %d, провалов здравого смысла %d" % [out, failed_goal, failed_must])
	return 1 if a.has("strict") and failed_must > 0 else 0


func _section_rhythm(lines: Array, runs: Array, years: int) -> void:
	lines.append("## Ритм по десятилетиям")
	lines.append("")
	lines.append("Среднее за десятилетие по партиям, которые до него дожили.")
	lines.append("")
	lines.append("| Годы | Партий | Окон | Выбор | Вызовов | Дел | Сообщений |")
	lines.append("|---|---|---|---|---|---|---|")
	for d in ceili(years / 10.0):
		var alive := runs.filter(func(r): return int(r.metrics.get("life.years", years)) > d * 10)
		if alive.is_empty():
			continue
		var row := []
		for field in ["windows", "choices", "calls", "deeds", "messages"]:
			var s := 0.0
			for r in alive:
				for y in range(d * 10, mini((d + 1) * 10, int(r.metrics.get("life.years", years)))):
					s += float(r.by_year[y][field])
			row.append("%.0f" % (s / alive.size()))
		lines.append("| %d–%d | %d | %s |" % [d * 10 + 1, mini((d + 1) * 10, years), alive.size(), " | ".join(row)])
	lines.append("")


func _section_novelty(lines: Array, g: Game, runs: Array) -> void:
	lines.append("## Новизна")
	lines.append("")
	var seen := {}
	var total := 0
	var first_by := {}
	for r in runs:
		for k in r.seen:
			seen[k] = int(seen.get(k, 0)) + int(r.seen[k])
			total += int(r.seen[k])
		for k in r.first_year:
			var dd := int(r.first_year[k]) / 10
			first_by[dd] = int(first_by.get(dd, 0)) + 1
	var parts := []
	for dd in range(0, ceili(int(runs[0].years) / 10.0)):
		var alive := runs.filter(func(r): return int(r.metrics.get("life.years", r.years)) > dd * 10).size()
		if alive > 0:
			parts.append("%d–%d: %.1f" % [dd * 10 + 1, dd * 10 + 10, float(first_by.get(dd, 0)) / alive])
	lines.append("Новых окон за десятилетие (впервые за партию; среднее по дожившим партиям): " + "; ".join(parts) + ".")
	lines.append("")
	# охват: сколько событий с вариантами вообще встретилось хоть в одной партии
	var with_opts := g.content.all("events").filter(func(d): return not Data.as_array(d.get("options")).is_empty() and not d.get("hidden", false))
	var fams_all := {}
	var fams_seen := {}
	for d in with_opts:
		var fam := str(d.id).get_slice(".", 0)
		fams_all[fam] = int(fams_all.get(fam, 0)) + 1
		if seen.has(d.id):
			fams_seen[fam] = int(fams_seen.get(fam, 0)) + 1
	lines.append("Охват: игрок хоть раз увидел %d из %d событий с вариантами (%.0f%%)." % [seen.size(), with_opts.size(), 100.0 * seen.size() / maxf(1.0, with_opts.size())])
	lines.append("")
	lines.append("| Семья событий | Увидено | Всего |")
	lines.append("|---|---|---|")
	var fk := fams_all.keys()
	fk.sort_custom(func(x, y): return float(fams_seen.get(x, 0)) / fams_all[x] < float(fams_seen.get(y, 0)) / fams_all[y])
	for fam in fk:
		lines.append("| %s | %d | %d |" % [fam, int(fams_seen.get(fam, 0)), int(fams_all[fam])])
	lines.append("")
	lines.append("Самые частые окна (все партии):")
	lines.append("")
	lines.append("| Событие | Раз | Доля окон |")
	lines.append("|---|---|---|")
	var ks := seen.keys()
	ks.sort_custom(func(x, y): return seen[x] > seen[y])
	for k in ks.slice(0, 12):
		lines.append("| %s | %d | %.0f%% |" % [_ev(g, k), int(seen[k]), 100.0 * seen[k] / maxf(1.0, total)])
	lines.append("")


func _section_choice(lines: Array, g: Game, runs: Array) -> void:
	lines.append("## Выбор")
	lines.append("")
	lines.append("Это взгляд ИИ, который играет за игрока: «очевидный» — один вариант весит не меньше 85%, «жребий» — у всех вариантов одинаковый вес (ai_chance не написан или ничего не меняет). Высокая очевидность ещё не значит, что выбор скучен человеку: ИИ решает по нраву. Но «жребий» прямо значит, что для мира вариант ничем не отличается.")
	lines.append("")
	for pair in [["ev_obvious", "Чаще всего очевидно"], ["ev_flat", "Чаще всего жребий"]]:
		var d := {}
		for r in runs:
			for k in r[pair[0]]:
				d[k] = int(d.get(k, 0)) + int(r[pair[0]][k])
		if d.is_empty():
			continue
		var ks := d.keys()
		ks.sort_custom(func(x, y): return d[x] > d[y])
		lines.append("%s: %s." % [pair[1], ", ".join(ks.slice(0, 10).map(func(k): return "%s ×%d" % [_ev(g, k), d[k]]))])
		lines.append("")


func _section_snowball(lines: Array, g: Game, runs: Array, years: int) -> void:
	lines.append("## Снежный ком")
	lines.append("")
	lines.append("| Год | %s | Крупнейшая держава мира: в среднем / наибольшая | Независимых |" % " | ".join(runs.map(func(r): return "%s #%d" % [_who(g, r.start), int(r.seed)])))
	lines.append("|---|%s---|---|" % "---|".repeat(runs.size()))
	for y in range(0, years + 1, 10):
		var row := []
		var shares := []
		var best := {"share": -1.0, "name": "", "run": ""}
		var ind := 0.0
		for r in runs:
			var s: Variant = r.snapshots[y] if y < r.snapshots.size() else null
			if s == null:
				row.append("—")
				continue
			row.append(("%d" % int(s.get("counties", 0))) + ("" if s.get("independent", true) else " (вассал)"))
			var sh := float(s.top_counties) / maxf(1.0, s.counties_total)
			shares.append(sh)
			if sh > float(best.share):
				best = {"share": sh, "name": str(s.get("top_name", s.top_id)), "run": "%s #%d" % [_who(g, r.start), int(r.seed)]}
			ind += float(s.independents)
		var top := "—" if shares.is_empty() else "%.0f%% / %s %.0f%% (%s)" % [100.0 * FunProbe._mean(shares), best.name, 100.0 * float(best.share), best.run]
		lines.append("| %d | %s | %s | %.0f |" % [y, " | ".join(row), top, ind / maxf(1.0, shares.size())])
	lines.append("")
	lines.append("В столбцах стартов — графств в державе игрока (его рода после смены правителя); «—» — партия кончилась.")
	lines.append("")


func _section_deeds(lines: Array, g: Game, runs: Array) -> void:
	lines.append("## Что делал игрок")
	lines.append("")
	for pair in [["decisions", "Решения", "decisions"], ["interactions", "Предложения", "interactions"], ["wars_declared", "Войны", "casus_belli"]]:
		var d := {}
		for r in runs:
			for k in r[pair[0]]:
				d[k] = int(d.get(k, 0)) + int(r[pair[0]][k])
		var ks := d.keys()
		ks.sort_custom(func(x, y): return d[x] > d[y])
		var names: Array = ks.slice(0, 14).map(func(k):
			var base := str(k).trim_suffix(" ✓").trim_suffix(" ✗")
			return "%s%s ×%d" % [g.name_of(pair[2], base), str(k).substr(base.length()), d[k]])
		lines.append("**%s** (%d видов): %s." % [pair[1], ks.size(), ", ".join(names) if not names.is_empty() else "—"])
		lines.append("")


func _section_threats(lines: Array, runs: Array) -> void:
	lines.append("## Угрозы и беды")
	lines.append("")
	lines.append("| Старт | Войн: напал / защищался / союзником | Побед / поражений / мир | Фракций | Ультиматумов | Бунтов | Заговоров раскрыто | Плен | Регентств | Смен правителя |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|")
	for r in runs:
		var w: Dictionary = r.wars
		var t: Dictionary = r.threats
		lines.append("| %s #%d | %d / %d / %d | %d / %d / %d | %d | %d | %d | %d | %d | %d | %d |" % [str(r.start), int(r.seed),
			int(w.attack), int(w.defend), int(w.joined), int(w.won), int(w.lost), int(w.white),
			int(t.factions), int(t.ultimatums), int(t.revolts), int(t.schemes), int(t.prison), int(t.regency), r.successions.size()])
	lines.append("")


# ------------------------------------------------------------ мелочи

static func _end_note(r: Dictionary) -> String:
	if r.get("game_over") != null:
		return " (род пресёкся на %d-й год)" % (int(r.game_over.year) + 1)
	if r.get("realm_lost") != null:
		return " (держава потеряна на %d-й год)" % (int(r.realm_lost.year) + 1)
	return ""


static func _agg(vals: Array, how: String) -> float:
	if vals.is_empty():
		return 0.0
	match how:
		"max":
			return vals.max()
		"min":
			return vals.min()
	return FunProbe._mean(vals)


static func _num(v: Variant) -> String:
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else "%.2f" % f


static func _spread(vals: Array, v: float) -> String:
	if vals.size() < 2:
		return _num(snappedf(v, 0.01))
	return "%s (%s–%s)" % [_num(snappedf(v, 0.01)), _num(snappedf(vals.min(), 0.01)), _num(snappedf(vals.max(), 0.01))]


static func _who(g: Game, id: Variant) -> String:
	return g.name_of("characters", str(id)) if g.content.has("characters", str(id)) else str(id)


static func _ev(g: Game, id: String) -> String:
	var t := g.loc.t_or("ev.%s.t" % id, "")
	return "%s «%s»" % [id, t] if t != "" else id

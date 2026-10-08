class_name TestEnv
extends RefCounted
## Общий движок для тестов (грузится один раз на прогон).

static var _engine: GameEngine


static func default_localization() -> Dictionary:
	var defaults := {}
	for lang in DirAccess.get_directories_at("res://locale"):
		defaults[lang] = []
		for f in DirAccess.get_files_at("res://locale/" + lang):
			if f.ends_with(".yaml"):
				defaults[lang].append(Yaml.parse(FileAccess.get_file_as_string("res://locale/%s/%s" % [lang, f]), f).value)
	return defaults


static func engine() -> GameEngine:
	if _engine == null:
		var issues := []
		var pkgs := ModPackage.scan_dir("res://mods", "builtin", "встроенный", issues)
		_engine = GameEngine.create(pkgs, {"default_localization": default_localization(), "lang": "ru"})
	return _engine


static func ticks(game: Game, days: int) -> void:
	for i in days:
		game.tick()


## Нарушения согласованности мира (пусто — всё в порядке).
static func invariants(game: Game) -> Array:
	var problems := []
	for t in game.state.titles.values():
		if t.holder == null:
			continue
		var h: Variant = game.ch(t.holder)
		if h == null:
			problems.append("%s: владелец %s не существует" % [t.id, t.holder])
		elif h.death != null:
			problems.append("%s: владелец мёртв" % t.id)
		elif not h.titles.has(t.id):
			problems.append("%s: нет в списке титулов владельца" % t.id)
	for c in game.living():
		for t in c.titles:
			if game.state.titles[t].holder != c.id:
				problems.append("%s: титул %s принадлежит другому" % [c.id, t])
		var cur: Dictionary = c
		for i in 40:
			if cur.liege == null:
				break
			var l: Variant = game.ch(cur.liege)
			if l == null:
				problems.append("%s: сюзерен %s не существует" % [cur.id, cur.liege])
				break
			cur = l
			if i == 39:
				problems.append("%s: цикл сюзеренитета" % c.id)
	for w in game.state.wars.values():
		if not game.is_alive(w.attacker) or not game.is_alive(w.defender):
			problems.append("%s: лидер войны мёртв" % w.id)
	return problems


## Первое различие двух структур (числа сравниваются по значению) или "".
static func first_diff(a: Variant, b: Variant, path: String = "") -> String:
	if (a is int or a is float) and (b is int or b is float):
		return "" if is_equal_approx(float(a), float(b)) else "%s: %s != %s" % [path, a, b]
	if typeof(a) != typeof(b):
		return "%s: тип %s != %s (%s / %s)" % [path, typeof(a), typeof(b), str(a).left(60), str(b).left(60)]
	if a is Dictionary:
		for k in a:
			if not b.has(k):
				return "%s/%s: нет во втором" % [path, k]
			var d := first_diff(a[k], b[k], "%s/%s" % [path, k])
			if d != "":
				return d
		for k in b:
			if not a.has(k):
				return "%s/%s: нет в первом" % [path, k]
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: длина %d != %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := first_diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s != %s" % [path, str(a).left(60), str(b).left(60)]

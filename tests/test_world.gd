extends TestCase
## Создание мира и симуляция без окна.

static var _engine: GameEngine


static func engine() -> GameEngine:
	if _engine == null:
		var issues := []
		var pkgs := ModPackage.scan_dir("res://mods", "builtin", "встроенный", issues)
		var defaults := {}
		for lang in DirAccess.get_directories_at("res://locale"):
			defaults[lang] = []
			for f in DirAccess.get_files_at("res://locale/" + lang):
				if f.ends_with(".yaml"):
					defaults[lang].append(Yaml.parse(FileAccess.get_file_as_string("res://locale/%s/%s" % [lang, f]), f).value)
		_engine = GameEngine.create(pkgs, {"default_localization": defaults, "lang": "ru"})
	return _engine


func test_engine_loads() -> void:
	var e := engine()
	check(e.content.all("traits").size() > 20, "черты загружены")
	for i in e.issues:
		check(i.level != "error", "ошибка: %s" % i)
	check(e.map.provinces.size() > 100, "карта построена")
	check(not e.neighbors("c_london").is_empty() if e.map.index.has("c_london") else true, "у Лондона есть соседи")


func test_new_game_and_year() -> void:
	var e := engine()
	var t := Time.get_ticks_msec()
	var game := e.new_game("b1066", 42)
	print("    новая партия: %d мс, правителей: %d, персонажей: %d" % [Time.get_ticks_msec() - t, game.rulers().size(), game.living().size()])
	check(game.rulers().size() > 50, "правители есть")
	var harold: Variant = game.ch("harold")
	check(harold != null and harold.titles.has("k_england"), "Гарольд — король Англии")
	t = Time.get_ticks_msec()
	for i in 365:
		game.tick()
	print("    год симуляции: %d мс, войн: %d, живых: %d" % [Time.get_ticks_msec() - t, game.state.wars.size(), game.living().size()])
	check(game.date > game.state.start_date, "время идёт")

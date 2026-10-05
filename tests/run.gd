extends SceneTree
## Запуск тестов без окна:
##   godot --headless --path . -s tests/run.gd            — все тесты
##   godot --headless --path . -s tests/run.gd -- core    — только файлы test_core*.gd
##
## Тест — файл tests/test_*.gd с классом, наследующим TestCase,
## и методами test_*(). Проверки: check(), check_eq().

func _init() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var files := Array(DirAccess.get_files_at("res://tests")).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	var total := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for f in files:
		if filter != "" and not f.begins_with("test_" + filter):
			continue
		var script: Script = load("res://tests/" + f)
		var methods := script.get_script_method_list().map(func(m): return m.name).filter(func(n): return n.begins_with("test_"))
		for m in methods:
			var tc: TestCase = script.new()
			tc.name = "%s::%s" % [f.trim_suffix(".gd"), m]
			var t := Time.get_ticks_msec()
			await tc.call(m)
			total += 1
			if tc.failures.is_empty():
				print("  ✓ %s (%d мс)" % [tc.name, Time.get_ticks_msec() - t])
			else:
				failed += 1
				print("  ✗ %s" % tc.name)
				for msg in tc.failures:
					print("      " + msg)
	print("\nТестов: %d, провалено: %d, время: %.1f с" % [total, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failed > 0 else 0)

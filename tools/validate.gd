extends SceneTree
## Проверка модов: синтаксис файлов, зависимости, ссылки между записями,
## ключи скриптов, пробный запуск всех закладок, расхождения локализаций.
##   godot --headless --path . -s tools/validate.gd [-- --mods core,my_mod]
## Код возврата 1, если есть ошибки.


func _init() -> void:
	var a := ToolCommon.args()
	var e := ToolCommon.engine(a)
	var errors := 0
	var warnings := 0
	for i in e.issues:
		var lvl: String = i.get("level", "warning")
		if lvl == "error":
			errors += 1
		else:
			warnings += 1
		print("[%s] %s%s%s" % [lvl, (str(i.mod) + ": ") if i.get("mod") != null else "", (str(i.file) + ": ") if i.get("file") != null else "", i.get("message", "")])
	# пробный запуск закладок
	for bm in e.bookmarks():
		var g := e.new_game(bm.id, 1)
		var problems := []
		g.engine.issue_reported.connect(func(issue): problems.append(issue))
		for d in 60:
			while not g.state.pending_events.is_empty():
				g.events.choose(g.state.pending_events[0].uid, 0)
			g.state.pending_requests.clear()
			g.tick()
		if g.living().is_empty():
			errors += 1
			print("[error] закладка %s: после запуска нет живых персонажей" % bm.id)
		for p in problems:
			errors += 1
			print("[error] закладка %s: %s" % [bm.id, p.get("message", p)])
		print("закладка %s: ок (персонажей %d, держав %d)" % [bm.id, g.living().size(), g.rulers().filter(func(c): return c.liege == null).size()])
	# расхождения локализаций
	var langs := ["ru", "en"]
	var keys := {}
	for l in langs:
		keys[l] = {}
		for k in e.loc.keys(l):
			keys[l][k] = true
	for l in langs:
		for other in langs:
			if l == other:
				continue
			var missing := []
			for k in keys[l]:
				# имена персонажей в английской версии берутся как есть
				if k.begins_with("name.") and other == "en":
					continue
				if not keys[other].has(k):
					missing.append(k)
			if not missing.is_empty():
				warnings += 1
				missing.sort()
				print("[warning] нет перевода (%s → %s), %d ключей: %s%s" % [l, other, missing.size(), ", ".join(missing.slice(0, 12)), " …" if missing.size() > 12 else ""])
	print("\nОшибок: %d, предупреждений: %d" % [errors, warnings])
	quit(1 if errors > 0 else 0)

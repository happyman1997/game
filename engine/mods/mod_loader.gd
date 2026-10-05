class_name ModLoader
extends RefCounted
## Загрузка модов: порядок загрузки, слияние данных в ContentStore,
## локализация, загрузка GDScript-скриптов (init вызывается позже,
## при создании GameEngine).


## Порядок загрузки: зависимости и load_after раньше, при прочих равных —
## по priority, затем по id.
static func resolve_load_order(packages: Array, issues: Array) -> Array:
	var by_id := {}
	for p: ModPackage in packages:
		if by_id.has(p.id):
			issues.append({"mod": p.id, "level": "warning", "message": "Мод с id \"%s\" найден дважды; используется последний (%s)" % [p.id, p.origin]})
		by_id[p.id] = p
	# Отбрасываем моды с отсутствующими зависимостями (рекурсивно).
	var changed := true
	while changed:
		changed = false
		for id in by_id.keys():
			var p: ModPackage = by_id[id]
			var missing := []
			for d in Data.as_array(p.manifest.get("dependencies")):
				if not by_id.has(d):
					missing.append(d)
			if not missing.is_empty():
				issues.append({"mod": id, "level": "error", "message": "Не хватает зависимостей: %s — мод отключён" % ", ".join(missing)})
				by_id.erase(id)
				changed = true
	var pkgs: Array = by_id.values()
	pkgs.sort_custom(func(a: ModPackage, b: ModPackage) -> bool:
		var pa := Data.num(a.manifest.get("priority"))
		var pb := Data.num(b.manifest.get("priority"))
		if pa != pb:
			return pa < pb
		return a.id < b.id)
	var before := {}
	for p: ModPackage in pkgs:
		var deps := []
		for d in Data.as_array(p.manifest.get("dependencies")) + Data.as_array(p.manifest.get("load_after")):
			if by_id.has(d) and not deps.has(d):
				deps.append(d)
		before[p.id] = deps
	var order := []
	var done := {}
	while order.size() < pkgs.size():
		var next: ModPackage = null
		for p: ModPackage in pkgs:
			if done.has(p.id):
				continue
			if before[p.id].all(func(d): return done.has(d)):
				next = p
				break
		if next == null:
			var rest := pkgs.filter(func(p): return not done.has(p.id))
			issues.append({"level": "error", "message": "Циклическая зависимость между модами: " + ", ".join(rest.map(func(p): return p.id))})
			for p: ModPackage in rest:
				order.append(p)
				done[p.id] = true
			break
		order.append(next)
		done[next.id] = true
	return order


## enabled: Array id включённых модов или null (все с default_enabled != false).
## preload_cb: Callable(pkg, instance) — сразу после загрузки скрипта мода.
static func load_mods(packages: Array, formats: FormatRegistry, enabled: Variant = null, preload_cb: Callable = Callable()) -> Dictionary:
	var issues := []
	var active := packages.filter(func(p: ModPackage) -> bool:
		if enabled is Array:
			return enabled.has(p.id)
		return p.manifest.get("default_enabled", true) != false)
	var order := resolve_load_order(active, issues)
	var content := ContentStore.new()
	var loc := Localization.new()
	var scripts := []

	for pkg: ModPackage in order:
		var m := pkg.manifest
		var files := pkg.source.list_files()
		for path in Data.as_array(m.get("scripts")):
			var sp := _script_path(pkg, str(path))
			if sp == "":
				continue
			var inst: Variant = pkg.source.load_script(sp)
			if inst is String:
				issues.append({"mod": pkg.id, "file": sp, "level": "error", "message": "Ошибка загрузки скрипта: " + inst})
				continue
			scripts.append({"mod": pkg.id, "path": sp, "instance": inst})
			if preload_cb.is_valid():
				preload_cb.call(pkg, inst)
		var data_dirs := []
		for d in Data.as_array(m.get("data", ["data"])):
			data_dirs.append(str(d).trim_suffix("/") + "/")
		var loc_dir := str(m.get("localization", "localization")).trim_suffix("/") + "/"

		for file in files:
			if not formats.can_parse(file):
				continue
			var is_data := data_dirs.any(func(d): return file.begins_with(d))
			var is_loc := file.begins_with(loc_dir)
			if not is_data and not is_loc:
				continue
			var text: Variant = pkg.source.read_text(file)
			if text == null:
				issues.append({"mod": pkg.id, "file": file, "level": "error", "message": "Не удалось прочитать файл"})
				continue
			var r := formats.parse(text, pkg.id + "/" + file)
			if not r.ok:
				issues.append({"mod": pkg.id, "file": file, "level": "error", "message": r.error})
				continue
			var parsed: Variant = r.value
			if parsed == null:
				continue
			if is_loc:
				# localization/ru/whatever.yaml → язык "ru"
				var lang := file.substr(loc_dir.length()).split("/")[0]
				if lang == "" or lang.contains("."):
					issues.append({"mod": pkg.id, "file": file, "level": "warning", "message": "Файл локализации должен лежать в папке языка, например localization/ru/"})
					continue
				loc.add(lang, parsed)
				continue
			if not (parsed is Dictionary):
				issues.append({"mod": pkg.id, "file": file, "level": "error", "message": "Файл данных должен быть словарём «тип контента → записи»"})
				continue
			for type in parsed:
				var err := content.merge_section(str(type), parsed[type], pkg.id)
				if err != "":
					issues.append({"mod": pkg.id, "file": file, "level": "error", "message": "%s: %s" % [type, err]})
	return {"order": order, "content": content, "loc": loc, "scripts": scripts, "issues": issues}


## Скрипт мода: путь из mod.json. Для совместимости с веб-прототипом
## main.js заменяется на main.gd, если такой файл есть.
static func _script_path(pkg: ModPackage, path: String) -> String:
	if path.ends_with(".gd"):
		return path
	var gd := path.get_basename() + ".gd"
	if pkg.source.exists(gd) or pkg.source.exists(gd + ".remap") or pkg.source.exists(gd.get_basename() + ".gdc"):
		return gd
	return ""

extends SceneTree
## Справочник скриптового языка из реестров движка и включённых модов:
##   godot --headless --path . -s tools/script_docs.gd [-- --out docs/SCRIPT_REFERENCE.md]


func _init() -> void:
	var a := ToolCommon.args()
	var e := ToolCommon.engine(a)
	var out := PackedStringArray()
	out.append("# Справочник скриптового языка\n")
	out.append("> Файл сгенерирован командой `godot --headless --path . -s tools/script_docs.gd` из реестров движка и включённых модов.")
	out.append("> Колонка «Источник» показывает, кто зарегистрировал элемент (core — движок, иначе id мода).\n")
	var sc := e.scripting
	_table(out, "Триггеры (условия)", sc.triggers, true)
	_table(out, "Эффекты", sc.effects, false)
	_table(out, "Значения", sc.values, true)
	_table(out, "Ссылки на скоупы", sc.links, true, "from")
	_table(out, "Списки (any_ / every_ / random_ / ordered_)", sc.lists, true, "from")
	out.append("## Константы\n")
	out.append("| Имя | Значение | Источник |")
	out.append("|---|---|---|")
	var cids := sc.constants.ids()
	cids.sort()
	for id in cids:
		out.append("| `%s` | %s | %s |" % [id, sc.constants.get_item(id), _owner(sc.constants, id)])
	out.append("\n## Механики\n")
	out.append("| Механика | Описание | Включена |")
	out.append("|---|---|---|")
	for id in e.features.ids():
		var f: EngineFeature = e.features.get_item(id)
		out.append("| `%s` | %s | %s |" % [id, f.doc, "да" if e.has_feature(id) else "нет"])
	out.append("\nОтключение: `defines.disabled_features: [id, ...]`.\n")
	out.append("## Реестры движка\n")
	var regs := e.registries()
	for k in regs:
		out.append("- **%s**: %s" % [k, ", ".join(regs[k].ids().map(func(x): return "`%s`" % x))])
	var systems := e.ordered_systems().map(func(s): return "`%s` (%s)" % [s.id, s.get("order", 0)])
	out.append("- **systems**: " + ", ".join(systems))
	out.append("- **ui.map_modes**: " + ", ".join(e.ui.map_modes.ids().map(func(x): return "`%s`" % x)))
	var text := "\n".join(out) + "\n"
	var path: String = a.get("out", "res://docs/SCRIPT_REFERENCE.md")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	print("Записано: ", path)
	quit()


func _owner(reg: Registry, id: String) -> String:
	var o := reg.owner_of(id)
	return o if o != "" else "core"


func _table(out: PackedStringArray, title: String, reg: Registry, with_scopes: bool, scope_key: String = "scopes") -> void:
	out.append("## %s\n" % title)
	if with_scopes:
		out.append("| Имя | Скоупы | Описание | Источник |")
		out.append("|---|---|---|---|")
	else:
		out.append("| Имя | Описание | Источник |")
		out.append("|---|---|---|")
	var ids := reg.ids()
	ids.sort()
	for id in ids:
		var d: Variant = reg.get_item(id)
		var doc: String = str(d.get("doc", "")) if d is Dictionary else ""
		doc = doc.replace("|", "\\|").replace("\n", " ")
		if with_scopes:
			var scopes: Variant = d.get(scope_key) if d is Dictionary else null
			var sc := ", ".join(scopes) if scopes is Array else "любой"
			out.append("| `%s` | %s | %s | %s |" % [id, sc, doc, _owner(reg, id)])
		else:
			out.append("| `%s` | %s | %s |" % [id, doc, _owner(reg, id)])
	out.append("")

class_name SaveGame
extends RefCounted
## Сохранения — это JSON состояния партии плюс список модов.
## Данные модов (state.mod_data) сохраняются автоматически.

const FORMAT := "crown-and-dynasty-save"


static func serialize(game: Game) -> String:
	game.emit("game.before_save", {})
	# Кэши сбрасываются и у текущей партии: так она продолжится точно так же,
	# как загруженная из этого сохранения (детерминированность).
	game.mark_dirty()
	game.month_cache.clear()
	game._def_cache.clear()
	return JSON.stringify({"format": FORMAT, "version": WorldSetup.SAVE_VERSION, "saved_at": Time.get_datetime_string_from_system(true), "state": game.state}, "", false, true)


## {game: Game|null, warnings: Array, error: String}
static func deserialize(engine: GameEngine, json: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(json) != OK:
		return {"game": null, "warnings": [], "error": "Файл повреждён: " + j.get_error_message()}
	var data: Variant = j.data
	if not (data is Dictionary) or data.get("format") != FORMAT or not (data.get("state") is Dictionary):
		return {"game": null, "warnings": [], "error": "Это не файл сохранения"}
	var state: Dictionary = Data.ints_from_json(data.state)
	var warnings := []
	if Data.num(data.get("version")) > WorldSetup.SAVE_VERSION:
		warnings.append("Сохранение сделано более новой версией (%s)" % data.version)
	var active := {}
	for m in engine.mods:
		active[m.id] = m.manifest.get("version")
	for m in Data.as_array(state.get("mods")):
		if not active.has(m.id):
			warnings.append("Мод \"%s\" был включён при сохранении, но сейчас отключён" % m.id)
		elif m.get("version") != null and active[m.id] != m.version:
			warnings.append("Версия мода \"%s\" изменилась: %s → %s" % [m.id, m.version, active[m.id]])
	_fill_defaults(engine, state)
	state.mods = engine.mods.map(func(m): return {"id": m.id, "version": m.manifest.get("version")})
	var game := Game.new(engine, state)
	game.mark_dirty()
	engine.hooks.emit("game.loaded", {"game": game})
	return {"game": game, "warnings": warnings, "error": ""}


## Дополняет записи недостающими полями (сохранения прежних версий, моды).
static func _fill_defaults(engine: GameEngine, state: Dictionary) -> void:
	var tpl := WorldSetup.empty_state(engine, "", 0, 0)
	for k in tpl:
		if not state.has(k):
			state[k] = tpl[k]
	var ch_tpl := Chars.new_character_record()
	for c in state.characters.values():
		for k in ch_tpl:
			if not c.has(k):
				c[k] = Data.clone(ch_tpl[k])
	var p_tpl := WorldSetup.new_province_record("", "", "", 0, [])
	for p in state.provinces.values():
		for k in p_tpl:
			if not p.has(k):
				p[k] = Data.clone(p_tpl[k])
	var w_tpl := Wars.new_war_record()
	for w in state.wars.values():
		for k in w_tpl:
			if not w.has(k):
				w[k] = Data.clone(w_tpl[k])
	var a_tpl := Military.new_army_record()
	for a in state.armies.values():
		for k in a_tpl:
			if not a.has(k):
				a[k] = Data.clone(a_tpl[k])
	for t in state.titles.values():
		if not t.has("holder"):
			t["holder"] = null
		if not t.has("history"):
			t["history"] = []

class_name Game
extends RefCounted
## Запущенная партия: состояние мира + ссылки на движок (контент, реестры).
## Логика мира разнесена по классам engine/world/*, системы — engine/systems/*.
##
## Состояние (state) — обычные словари и массивы, поэтому сохранение —
## это JSON.stringify(state).

signal changed(kind: String)

var engine: GameEngine
var state: Dictionary
var rng: Rng
var events: GameEvents

var _living_cache: Variant = null
var _rulers_cache: Variant = null
var _by_liege: Variant = null
## Кэш характеристик персонажей (сбрасывается раз в месяц и при изменениях).
var stat_cache := {}
## Кэш на день (сбрасывается каждый тик): для производных данных механик.
var day_cache := {}
## Кэш на месяц (сбрасывается 1-го числа): для дорогих производных данных механик.
var month_cache := {}
var _reported_errors := {}
## Во время генерации мира on_action и сообщения отключены.
var quiet := false


func _init(e: GameEngine, st: Dictionary) -> void:
	engine = e
	state = st
	rng = Rng.new(st.rng)
	events = GameEvents.new(self)


# ------------------------------------------------------------ доступ

var content: ContentStore:
	get:
		return engine.content

var loc: Localization:
	get:
		return engine.loc

var defines: Dictionary:
	get:
		return engine.content.singleton("defines")

var date: int:
	get:
		return state.date

var player: Variant:
	get:
		return state.characters.get(state.player) if state.player != null else null


func ch(id: Variant) -> Variant:
	if id == null:
		return null
	return state.characters.get(id)


func title(id: Variant) -> Variant:
	if id == null:
		return null
	return state.titles.get(id)


func title_def(id: Variant) -> Variant:
	return content.get_def("titles", id)


func prov(id: Variant) -> Variant:
	if id == null:
		return null
	return state.provinces.get(id)


func prov_def(id: Variant) -> Variant:
	return content.get_def("provinces", id)


## Значение из defines по пути "раздел.ключ". Найденные значения кэшируются
## до конца месяца (моды, меняющие defines на ходу, увидят изменение с нового месяца).
func def_num(path: String, fallback: float = 0.0) -> float:
	var cur: Variant = _def_lookup(path)
	return float(cur) if (cur is int or cur is float) else fallback


func def_val(path: String, fallback: Variant = null) -> Variant:
	var cur: Variant = _def_lookup(path)
	return cur if cur != null else fallback


const _NO_DEF := "<<нет значения>>"


func _def_lookup(path: String) -> Variant:
	var key := "def:" + path
	var hit: Variant = month_cache.get(key, _NO_DEF)
	if not (hit is String and hit == _NO_DEF):
		return hit
	var cur: Variant = defines
	for p in path.split("."):
		if not (cur is Dictionary) or not cur.has(p):
			cur = null
			break
		cur = cur[p]
	month_cache[key] = cur
	return cur


func exists(ref: Variant) -> bool:
	if ref == null:
		return false
	match ref.type:
		"character": return state.characters.has(ref.id)
		"title": return state.titles.has(ref.id)
		"province": return state.provinces.has(ref.id)
		"dynasty": return state.dynasties.has(ref.id)
		"war": return state.wars.has(ref.id)
		"scheme": return state.schemes.has(ref.id)
		"army": return state.armies.has(ref.id)
		"faction": return state.factions.has(ref.id)
	return false


func new_id(prefix: String) -> String:
	var n = int(state.next_id)
	state.next_id = n + 1
	return prefix + str(n)


# ------------------------------------------------------------ индексы

## Сбрасывает кэши индексов. Вызывайте после прямого изменения liege/titles.
func mark_dirty() -> void:
	mark_index_dirty()
	stat_cache.clear()


## Сбрасывает только индексы персонажей (без кэша характеристик): рождения, браки, смена двора.
func mark_index_dirty() -> void:
	_living_cache = null
	_rulers_cache = null
	_by_liege = null
	day_cache.clear()


func living() -> Array:
	if _living_cache == null:
		var out := []
		for c in state.characters.values():
			if c.death == null:
				out.append(c)
		_living_cache = out
	return _living_cache


func rulers() -> Array:
	if _rulers_cache == null:
		_rulers_cache = living().filter(func(c): return not c.titles.is_empty())
	return _rulers_cache


func _liege_index() -> Dictionary:
	if _by_liege == null:
		var idx := {}
		for c in living():
			if c.liege == null:
				continue
			if not idx.has(c.liege):
				idx[c.liege] = []
			idx[c.liege].append(c)
		_by_liege = idx
	return _by_liege


## Прямые вассалы (землевладельцы, чей сюзерен — id).
func vassals_of(id: String) -> Array:
	return _liege_index().get(id, []).filter(func(c): return not c.titles.is_empty())


## Придворные (безземельные персонажи при дворе id).
func courtiers_of(id: String) -> Array:
	return _liege_index().get(id, []).filter(func(c): return c.titles.is_empty())


# ------------------------------------------------------------ текст

static var _interp_re: RegEx

## Разрешает текст из данных (ключ локализации, {ru, en} или сырой текст)
## и подставляет [путь] из скриптового контекста:
##   "[actor.name] просит руки [scope:target|g:вашего сына|вашей дочери]"
func text(v: Variant, ctx: ScriptContext = null, params: Dictionary = {}) -> String:
	var s := loc.resolve(v, params)
	if s.find("[") < 0:
		return s
	var c := ctx
	if c == null:
		if state.player == null:
			return s
		c = ScriptContext.make(self, {"type": "character", "id": state.player})
	if _interp_re == null:
		_interp_re = RegEx.create_from_string("\\[([^\\]]+)\\]")
	var out := ""
	var last := 0
	for m in _interp_re.search_all(s):
		out += s.substr(last, m.get_start() - last)
		out += _interpolate(m.get_string(1), c)
		last = m.get_end()
	return out + s.substr(last)


const _TEXT_PROPS := ["name", "first_name", "full_name", "title_name", "rank", "culture_name", "faith_name", "dynasty_name", "age"]


func _interpolate(expr: String, ctx: ScriptContext) -> String:
	var bits := expr.split("|")
	var path = bits[0].strip_edges()
	var gender := ""
	for i in range(1, bits.size()):
		if bits[i].begins_with("g:"):
			gender = bits[i]
	var segs := Interp.split_path(path)
	var scope_path = path
	var prop := ""
	if segs.size() > 0 and _TEXT_PROPS.has(segs[segs.size() - 1]):
		prop = segs[segs.size() - 1]
		segs.remove_at(segs.size() - 1)
		scope_path = ".".join(segs) if segs.size() > 0 else "root"
	var sc: Variant = Interp.resolve_scope(ctx, ctx.root, scope_path)
	if gender != "" and sc != null and sc.type == "character":
		var mf := gender.substr(2).split("/")
		var c: Variant = ch(sc.id)
		return (mf[1] if mf.size() > 1 else mf[0]) if (c != null and c.female) else mf[0]
	if sc != null:
		return scope_name(sc, prop if prop != "" else "name")
	var num := Interp.eval_value(ctx, ctx.root, path)
	var r := roundf(num * 10.0) / 10.0
	return str(int(r)) if r == floorf(r) else str(r)


## Отображаемое имя объекта мира.
func scope_name(ref: Dictionary, prop: String = "name") -> String:
	match ref.type:
		"character":
			var c: Variant = ch(ref.id)
			if c == null:
				return "?"
			match prop:
				"first_name": return Chars.char_name(self, c)
				"full_name": return Chars.full_name(self, c, true)
				"title_name": return Titles.full_name(self, c.titles[0]) if not c.titles.is_empty() else ""
				"rank": return Chars.full_name(self, c, true).split(" ")[0]
				"culture_name": return name_of("cultures", c.culture)
				"faith_name": return name_of("faiths", c.faith)
				"dynasty_name": return name_of("dynasties", c.dynasty) if c.dynasty != null else ""
				"age": return str(floori((date - c.birth) / 365.0))
			return Chars.full_name(self, c, false)
		"title":
			return Titles.full_name(self, ref.id)
		"province":
			return name_of("provinces", ref.id)
		"dynasty":
			return name_of("dynasties", ref.id)
		"war":
			var w: Variant = state.wars.get(ref.id)
			return text(w.name if w.get("name") != null else "ui.war") if w != null else "?"
		"faction":
			var f: Variant = state.factions.get(ref.id)
			return name_of("factions", f.type) if f != null else "?"
	return str(ref.id)


## Имя записи контента: поле name, ключ "тип.id", ключ id, иначе id.
func name_of(type: String, id: Variant) -> String:
	if id == null:
		return ""
	var sid := str(id)
	if type == "dynasties":
		var st: Variant = state.dynasties.get(sid)
		if st != null and st.get("name") != null and str(st.name) != "":
			return dynasty_name(st.name)
	var def: Variant = content.get_def(type, sid)
	if def == null and type == "dynasties":
		def = state.dynasties.get(sid)
	if def is Dictionary and def.get("name") != null:
		return loc.resolve(def.name)
	var singular := singular_of(type)
	for k in [singular + "." + sid, type + "." + sid, sid]:
		var v: Variant = loc.raw(k)
		if v != null:
			return v
	return sid


## Название сгенерированной династии: "gen:<культура>:<имя или графство>".
func dynasty_name(raw: String) -> String:
	if not raw.begins_with("gen:"):
		var r: Variant = loc.raw("dynasty_name." + raw)
		return r if r != null else raw
	var bits := raw.split(":")
	var culture = bits[1] if bits.size() > 1 else ""
	var key = bits[2] if bits.size() > 2 else ""
	var is_place := content.has("provinces", key)
	var val: String
	if is_place:
		val = name_of("provinces", key)
	else:
		var n: Variant = loc.raw_exact("name." + key)
		val = n if n != null else key
	return loc.t_or("dynasty_pattern." + culture, "de {place}" if is_place else "{name}ing", {"name": val, "place": val})


func desc_of(type: String, id: String) -> String:
	var def: Variant = content.get_def(type, id)
	if def is Dictionary and def.get("desc") != null:
		return loc.resolve(def.desc)
	var r: Variant = loc.raw(singular_of(type) + "_desc." + id)
	return r if r != null else ""


func script_error(msg: String) -> void:
	if _reported_errors.has(msg):
		return
	_reported_errors[msg] = true
	engine.report_issue({"level": "warning", "message": "Скрипт: " + msg})


# ------------------------------------------------------------ хуки и сообщения

func emit(hook: String, payload: Dictionary = {}) -> void:
	var p := payload.duplicate()
	p["game"] = self
	engine.hooks.emit(hook, p)


## Запускает on_action из данных и одноимённый хук "on_action.<id>".
func on_action(id: String, root: Dictionary, scopes: Dictionary = {}) -> void:
	if quiet:
		return
	events.run_on_action(id, root, scopes)
	emit("on_action." + id, {"root": root, "scopes": scopes})


## Сообщение в журнал игрока. Сохраняется, только если касается игрока (или involves не задан).
func message(txt: String, kind: String = "info", ref: Variant = null, involves: Variant = null) -> void:
	if quiet:
		return
	if involves is Array and state.player != null and not involves.has(state.player):
		var p: String = state.player
		var touches := false
		for id in involves:
			var c: Variant = ch(id)
			if c != null and (c.liege == p or c.father == p or c.mother == p or c.spouses.has(p)):
				touches = true
				break
		if not touches:
			return
	state.messages.append({"date": date, "text": txt, "kind": kind, "ref": ref})
	if state.messages.size() > 300:
		state.messages = state.messages.slice(state.messages.size() - 300)
	notify("message")


func notify(kind: String) -> void:
	changed.emit(kind)


func is_player(id: Variant) -> bool:
	return id != null and id == state.player


# ------------------------------------------------------------ время

## Продвигает игру на один день.
func tick() -> void:
	if state.get("game_over") != null:
		return
	state.date = int(state.date) + 1
	# Характеристики кэшируются до конца месяца: всё, что их меняет (черты,
	# модификаторы, титулы, перки, законы), сбрасывает кэш явно.
	day_cache.clear()
	var p = GameDate.parts(state.date)
	var systems := engine.ordered_systems()
	for s in systems:
		if s.has("on_day"):
			s.on_day.call(self)
	if p.d == 1:
		month_cache.clear()
		mark_dirty()
	# Помесячная обработка персонажей (system.on_character_month): каждый
	# персонаж — в свой день месяца (1–28), так нагрузка ровная.
	if p.d <= 28:
		var char_systems := []
		for s in systems:
			if s.has("on_character_month"):
				char_systems.append(s)
		if not char_systems.is_empty():
			for c in month_bucket(p.d - 1):
				for s in char_systems:
					if c.death != null:
						break
					s.on_character_month.call(self, c)
	# Помесячные и годовые обработчики разнесены по первым дням месяца
	# (system.month_day или по порядку), чтобы не было одного тяжёлого дня.
	var spread := maxi(1, int(def_num("engine.month_spread_days", 4)))
	if p.d <= spread:
		var i := 0
		for s in systems:
			var day: int = int(s.get("month_day", 1 + i % spread))
			i += 1
			if day != p.d:
				continue
			if s.has("on_month"):
				s.on_month.call(self)
			if p.m == 1 and s.has("on_year"):
				s.on_year.call(self)
	emit("day")
	notify("tick")


static var _bucket_cache := {}


## День месяца (0–27), в который обрабатывается персонаж id.
static func bucket_of(id: String) -> int:
	var b: Variant = _bucket_cache.get(id)
	if b == null:
		b = absi(id.hash()) % 28
		_bucket_cache[id] = b
	return b


## Живые персонажи, чей день месяца — k (0–27).
func month_bucket(k: int) -> Array:
	var out := []
	for c in living():
		if bucket_of(c.id) == k:
			out.append(c)
	return out


## Значение из дневного кэша (или вычислить и запомнить).
func cached_daily(key: String, fn: Callable) -> Variant:
	if day_cache.has(key):
		return day_cache[key]
	var v: Variant = fn.call()
	day_cache[key] = v
	return v


## Значение из помесячного кэша (или вычислить и запомнить).
func cached_monthly(key: String, fn: Callable) -> Variant:
	if month_cache.has(key):
		return month_cache[key]
	var v: Variant = fn.call()
	month_cache[key] = v
	return v


## Для мода: персистентные данные мода в сохранении.
func mod_data(mod_id: String, init: Callable) -> Variant:
	if not state.mod_data.has(mod_id):
		state.mod_data[mod_id] = init.call()
	return state.mod_data[mod_id]


func is_alive(id: Variant) -> bool:
	return Chars.is_alive(ch(id))


## Ключ локализации записи: traits → trait, dynasties → dynasty, focuses → focus.
static func singular_of(type: String) -> String:
	if type.ends_with("ies"):
		return type.trim_suffix("ies") + "y"
	for suf in ["sses", "xes", "zes", "shes", "ches", "uses"]:
		if type.ends_with(suf):
			return type.trim_suffix("es")
	return type.trim_suffix("s")

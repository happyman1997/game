class_name Builtins
extends RefCounted
## Встроенная библиотека скриптового языка. Регистрируется в реестрах
## точно так же, как это делают моды, — поэтому любой элемент можно
## переопределить.

const CHAR := ["character"]
const PROV := ["province"]
const TITLE := ["title"]


static func _ch(ctx: ScriptContext, s: Variant) -> Variant:
	if s == null or s.type != "character":
		return null
	return ctx.game.ch(s.id)


static func _cref(id: Variant) -> Variant:
	return {"type": "character", "id": id} if id != null else null


static func _tref(id: Variant) -> Variant:
	return {"type": "title", "id": id} if id != null else null


static func _pref(id: Variant) -> Variant:
	return {"type": "province", "id": id} if id != null else null


static func _target_char(ctx: ScriptContext, scope: Variant, arg: Variant) -> Variant:
	return _ch(ctx, Interp.resolve_scope(ctx, scope, arg))


static func _num(ctx: ScriptContext, scope: Variant, arg: Variant) -> float:
	if arg is Dictionary and arg.has("value") and arg.size() == 1:
		return Interp.eval_value(ctx, scope, arg.value)
	return Interp.eval_value(ctx, scope, arg)


static func signed(n: float) -> String:
	var r := roundf(n * 10.0) / 10.0
	var s = str(int(r)) if r == floorf(r) else str(r)
	return "+" + s if r > 0 else s


static func _t(game: Game, key: String, params: Dictionary = {}) -> String:
	return game.loc.t(key, params)


static func _chars(arr: Array) -> Array:
	var out := []
	for c in arr:
		if Chars.is_alive(c):
			out.append({"type": "character", "id": c.id})
	return out


static func _ids_to_chars(game: Game, ids: Array) -> Array:
	return _chars(ids.map(func(id): return game.ch(id)))


static func _vars_of(ctx: ScriptContext, s: Variant) -> Variant:
	if s == null:
		return ctx.game.state.global_vars
	if s.type == "character":
		var c: Variant = ctx.game.ch(s.id)
		return c.vars if c != null else null
	if s.type == "province":
		var p: Variant = ctx.game.state.provinces.get(s.id)
		return p.vars if p != null else null
	return ctx.game.state.global_vars


static func _flag_args(game: Game, arg: Variant) -> Dictionary:
	if arg is String:
		return {"name": arg, "value": 0}
	var days := GameDate.duration_days(arg)
	return {"name": str(arg.get("name", arg.get("flag", ""))), "value": game.date + days if days > 0 else 0}


static func _yes(arg: Variant) -> bool:
	return arg == null or ScriptContext.is_yes(arg)


static func register(engine: GameEngine) -> void:
	var reg := engine.scripting
	var O := "core"

	# ============================================================ константы
	reg.constants.register("county", 1, O).register("duchy", 2, O).register("kingdom", 3, O).register("empire", 4, O)

	# ============================================================ ссылки
	var link := func(lname: String, from: Variant, doc: String, fn: Callable) -> void:
		var d := {"resolve": fn, "doc": doc}
		if from != null:
			d["from"] = from
		reg.links.register(lname, d, O)

	link.call("liege", CHAR, "Сюзерен (или владелец двора для придворных)", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _cref(c.liege) if c != null else null
	)
	link.call("employer", CHAR, "Синоним liege", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _cref(c.liege) if c != null else null
	)
	link.call("top_liege", CHAR, "Верховный сюзерен", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _cref(Titles.top_liege(ctx.game, c).id) if c != null else null
	)
	link.call("father", CHAR, "Отец", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _cref(c.father) if c != null else null
	)
	link.call("mother", CHAR, "Мать", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _cref(c.mother) if c != null else null
	)
	link.call("spouse", CHAR, "Супруг(а) (первый)", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _cref(c.spouses[0]) if (c != null and not c.spouses.is_empty()) else null
	)
	link.call("killer", CHAR, "Убийца", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _cref(c.killer) if c != null else null
	)
	link.call("primary_heir", CHAR, "Основной наследник", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		if c == null:
			return null
		var h := Succession.heirs_of(ctx.game, c)
		return _cref(h[0]) if not h.is_empty() else null
	)
	link.call("primary_title", CHAR, "Основной титул", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _tref(c.titles[0]) if (c != null and not c.titles.is_empty()) else null
	)
	link.call("capital", CHAR, "Столица (провинция)", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _pref(Titles.capital_of(ctx.game, c)) if c != null else null
	)
	link.call("dynasty", CHAR, "Династия", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return {"type": "dynasty", "id": c.dynasty} if (c != null and c.dynasty != null) else null
	)
	link.call("player", null, "Персонаж игрока", func(ctx, _s): return _cref(ctx.game.state.player))
	link.call("holder", ["title", "province"], "Владелец титула/графства", func(ctx, s):
		var t: Variant = ctx.game.state.titles.get(s.id)
		return _cref(t.holder) if t != null else null
	)
	link.call("controller", PROV, "Кто контролирует провинцию", func(ctx, s):
		var c: Variant = Titles.province_controller(ctx.game, s.id)
		return _cref(c.id) if c != null else null
	)
	link.call("county", PROV, "Графство провинции", func(ctx, s): return _tref(s.id) if ctx.game.state.titles.has(s.id) else null)
	link.call("province", TITLE, "Провинция графства", func(ctx, s): return _pref(s.id) if ctx.game.state.provinces.has(s.id) else null)
	link.call("de_jure_liege", TITLE, "Де-юре сюзеренный титул", func(ctx, s):
		var d: Variant = ctx.game.content.get_def("titles", s.id)
		return _tref(d.get("liege")) if d != null else null
	)
	link.call("capital_province", TITLE, "Столица титула", func(ctx, s):
		var d: Variant = ctx.game.content.get_def("titles", s.id)
		return _pref(d.get("capital")) if d != null else null
	)
	link.call("owner", ["scheme", "army"], "Владелец интриги/армии", func(ctx, s):
		var src: Variant = ctx.game.state.schemes.get(s.id) if s.type == "scheme" else ctx.game.state.armies.get(s.id)
		return _cref(src.owner) if src != null else null
	)
	link.call("target", ["scheme"], "Цель интриги", func(ctx, s):
		var sc: Variant = ctx.game.state.schemes.get(s.id)
		return _cref(sc.target) if sc != null else null
	)
	link.call("attacker", ["war"], "Нападающий", func(ctx, s):
		var w: Variant = ctx.game.state.wars.get(s.id)
		return _cref(w.attacker) if w != null else null
	)
	link.call("defender", ["war"], "Защитник", func(ctx, s):
		var w: Variant = ctx.game.state.wars.get(s.id)
		return _cref(w.defender) if w != null else null
	)
	link.call("founder", ["dynasty"], "Основатель династии", func(ctx, s):
		var d: Variant = ctx.game.state.dynasties.get(s.id)
		return _cref(d.get("founder")) if d != null else null
	)

	# ============================================================ списки
	var lst := func(lname: String, from: Variant, doc: String, fn: Callable) -> void:
		var d := {"list": fn, "doc": doc}
		if from != null:
			d["from"] = from
		reg.lists.register(lname, d, O)

	lst.call("self", null, "Сам этот объект (удобно для списков кандидатов)", func(_ctx, s): return [s])
	lst.call("liege", CHAR, "Сюзерен (список из одного персонажа)", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _chars([ctx.game.ch(c.liege)]) if c != null else []
	)
	lst.call("child", CHAR, "Живые дети", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _ids_to_chars(ctx.game, c.children) if c != null else []
	)
	lst.call("son", CHAR, "Сыновья", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		if c == null:
			return []
		return _chars(c.children.map(func(id): return ctx.game.ch(id)).filter(func(x): return x != null and not x.female))
	)
	lst.call("daughter", CHAR, "Дочери", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		if c == null:
			return []
		return _chars(c.children.map(func(id): return ctx.game.ch(id)).filter(func(x): return x != null and x.female))
	)
	lst.call("spouse", CHAR, "Супруги", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _ids_to_chars(ctx.game, c.spouses) if c != null else []
	)
	lst.call("parent", CHAR, "Родители", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _chars([ctx.game.ch(c.father), ctx.game.ch(c.mother)]) if c != null else []
	)
	lst.call("sibling", CHAR, "Братья и сёстры", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _chars(Chars.siblings_of(ctx.game, c)) if c != null else []
	)
	lst.call("grandchild", CHAR, "Внуки", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		if c == null:
			return []
		var ids := []
		for id in c.children:
			var x: Variant = ctx.game.ch(id)
			if x != null:
				ids.append_array(x.children)
		return _ids_to_chars(ctx.game, ids)
	)
	lst.call("close_family", CHAR, "Близкая семья (супруги, дети, родители, братья/сёстры)", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		if c == null:
			return []
		var ids: Array = c.children + c.spouses + [c.father, c.mother]
		for x in Chars.siblings_of(ctx.game, c):
			ids.append(x.id)
		return _ids_to_chars(ctx.game, Data.uniq(ids.filter(func(i): return i != null)))
	)
	lst.call("vassal", CHAR, "Прямые вассалы", func(ctx, s): return _chars(ctx.game.vassals_of(s.id)))
	lst.call("realm_vassal", CHAR, "Все вассалы державы", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return _chars(Titles.realm_members(ctx.game, c).filter(func(x): return x.id != c.id)) if c != null else []
	)
	lst.call("courtier", CHAR, "Придворные", func(ctx, s): return _chars(ctx.game.courtiers_of(s.id)))
	lst.call("dynasty_member", CHAR, "Живые члены династии", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		if c == null or c.dynasty == null:
			return []
		return _chars(ctx.game.living().filter(func(x): return x.dynasty == c.dynasty and x.id != c.id))
	)
	lst.call("ally", CHAR, "Союзники", func(ctx, s): return _ids_to_chars(ctx.game, Wars.allies_of(ctx.game, s.id)))
	lst.call("war_enemy", CHAR, "Враги по войнам", func(ctx, s): return _ids_to_chars(ctx.game, Wars.enemies_of(ctx.game, s.id)))
	lst.call("held_title", CHAR, "Титулы", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return c.titles.map(func(id): return {"type": "title", "id": id}) if c != null else []
	)
	lst.call("claim", CHAR, "Претензии", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return c.claims.map(func(id): return {"type": "title", "id": id}) if c != null else []
	)
	lst.call("domain_province", CHAR, "Провинции домена", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return Titles.domain_counties(ctx.game, c).map(func(id): return {"type": "province", "id": id}) if c != null else []
	)
	lst.call("realm_province", CHAR, "Провинции державы", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		return Titles.realm_counties(ctx.game, c).map(func(id): return {"type": "province", "id": id}) if c != null else []
	)
	lst.call("neighboring_ruler", CHAR, "Независимые правители по соседству", func(ctx, s):
		var c: Variant = _ch(ctx, s)
		if c == null:
			return []
		var g: Game = ctx.game
		var top := Titles.top_liege(g, c)
		var mine := {}
		for x in Titles.realm_counties(g, top):
			mine[x] = true
		var out := {}
		for p in mine:
			for n in g.engine.neighbors(p):
				if mine.has(n):
					continue
				var t: Variant = g.state.titles.get(n)
				var h: Variant = g.ch(t.holder) if t != null else null
				if h != null:
					out[Titles.top_liege(g, h).id] = true
		out.erase(c.id)
		return _ids_to_chars(g, out.keys())
	)
	lst.call("ruler", null, "Все правители (глобально)", func(ctx, _s): return _chars(ctx.game.rulers()))
	lst.call("independent_ruler", null, "Независимые правители", func(ctx, _s): return _chars(ctx.game.rulers().filter(func(r): return r.liege == null)))
	lst.call("living_character", null, "Все живые персонажи", func(ctx, _s): return _chars(ctx.game.living()))
	lst.call("province", null, "Все провинции", func(ctx, _s): return ctx.game.state.provinces.keys().map(func(id): return {"type": "province", "id": id}))
	lst.call("war", null, "Все войны", func(ctx, _s): return ctx.game.state.wars.keys().map(func(id): return {"type": "war", "id": id}))
	lst.call("neighbor", PROV, "Соседние провинции", func(ctx, s): return ctx.game.engine.neighbors(s.id).map(func(id): return {"type": "province", "id": id}))
	lst.call("de_jure_vassal_title", TITLE, "Де-юре вассальные титулы", func(ctx, s): return Titles.de_jure_vassal_titles(ctx.game, s.id).map(func(id): return {"type": "title", "id": id}))
	lst.call("de_jure_county", TITLE, "Де-юре графства", func(ctx, s): return Titles.de_jure_counties(ctx.game, s.id).map(func(id): return {"type": "title", "id": id}))

	# ============================================================ значения
	var val := func(vname: String, scopes: Variant, doc: String, fn: Callable) -> void:
		var d := {"get": fn, "doc": doc}
		if scopes != null:
			d["scopes"] = scopes
		reg.values.register(vname, d, O)
	# Значение персонажа: fn(game, c, arg_scope) -> float
	var cv := func(vname: String, doc: String, fn: Callable) -> void:
		reg.values.register(vname, {"scopes": CHAR, "doc": doc, "get": func(ctx, s, arg):
			var c: Variant = _ch(ctx, s)
			return float(fn.call(ctx.game, c, arg)) if c != null else 0.0
		}, O)

	cv.call("age", "Возраст", func(g, c, _a): return Chars.age_of(g, c))
	cv.call("gold", "Золото", func(_g, c, _a): return c.gold)
	cv.call("prestige", "Престиж", func(_g, c, _a): return c.prestige)
	cv.call("piety", "Благочестие", func(_g, c, _a): return c.piety)
	cv.call("stress", "Стресс", func(_g, c, _a): return c.stress)
	cv.call("stress_level", "Уровень стресса (стресс / 100)", func(_g, c, _a): return floori(float(c.stress) / 100.0))
	cv.call("health", "Здоровье", func(g, c, _a): return Stats.stat(g, c, "health"))
	cv.call("fertility", "Плодовитость", func(g, c, _a): return Stats.stat(g, c, "fertility"))
	cv.call("attraction", "Привлекательность", func(g, c, _a): return Stats.stat(g, c, "attraction_opinion"))
	cv.call("num_children", "Число живых детей", func(g, c, _a): return Data.count(c.children, func(id): return g.is_alive(id)))
	cv.call("num_spouses", "Число супругов", func(_g, c, _a): return c.spouses.size())
	cv.call("num_vassals", "Число прямых вассалов", func(g, c, _a): return g.vassals_of(c.id).size())
	cv.call("num_courtiers", "Число придворных", func(g, c, _a): return g.courtiers_of(c.id).size())
	cv.call("num_counties", "Графств в домене", func(g, c, _a): return Titles.domain_counties(g, c).size())
	cv.call("realm_size", "Графств в державе", func(g, c, _a): return Titles.realm_counties(g, c).size())
	cv.call("domain_limit", "Лимит домена", func(g, c, _a): return Economy.domain_limit(g, c))
	cv.call("levies", "Ополчение державы", func(g, c, _a): return Economy.realm_levy(g, c))
	cv.call("income", "Ежемесячный доход", func(g, c, _a): return Economy.monthly_income(g, c))
	cv.call("tier", "Ранг основного титула (0 — нет земель, 1 — граф ... 4 — император)", func(g, c, _a): return Titles.primary_tier(g, c))
	cv.call("num_claims", "Число претензий", func(_g, c, _a): return c.claims.size())
	cv.call("num_wars", "Число войн", func(g, c, _a): return Wars.wars_of(g, c.id).size())
	cv.call("num_traits", "Число черт", func(_g, c, _a): return c.traits.size())
	cv.call("dynasty_prestige", "Престиж династии", func(g, c, _a):
		var d: Variant = g.state.dynasties.get(c.dynasty) if c.dynasty != null else null
		return Data.num(d.prestige) if d != null else 0.0
	)
	cv.call("opinion", "Мнение о персонаже: opinion(scope:x)", func(g, c, arg):
		var o: Variant = g.ch(arg.id) if (arg != null and arg.type == "character") else null
		return Opinion.opinion(g, c, o) if o != null else 0
	)
	cv.call("reverse_opinion", "Мнение персонажа-аргумента об этом персонаже", func(g, c, arg):
		var o: Variant = g.ch(arg.id) if (arg != null and arg.type == "character") else null
		return Opinion.opinion(g, o, c) if o != null else 0
	)
	cv.call("levy_ratio", "Доля восстановленных ополчений", func(_g, c, _a): return c.levy_ratio)
	for k in ["aggression", "boldness", "compassion", "greed", "honor", "rationality", "sociability", "vengefulness", "zeal", "energy"]:
		cv.call("ai_" + k, "Личность ИИ: " + k, func(g, c, _a):
			var v := 0.0
			for tr in c.traits:
				var d: Variant = g.content.get_def("traits", tr)
				if d != null and d.get("ai") is Dictionary:
					v += Data.num(d.ai.get(k))
			return v
		)
	cv.call("num_hooks", "Число крюков персонажа на других", func(g, c, _a): return Data.count(c.hooks, func(h): return h.get("expires") == null or h.expires > g.date))

	val.call("development", PROV, "Развитие провинции", func(ctx, s, _a):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		return float(p.development) if p != null else 0.0
	)
	val.call("tax", PROV, "Налог провинции", func(ctx, s, _a): return Economy.county_tax(ctx.game, s.id))
	val.call("levy", PROV, "Ополчение провинции", func(ctx, s, _a): return Economy.county_levy(ctx.game, s.id))
	val.call("fort_level", PROV, "Уровень укреплений", func(ctx, s, _a): return Military.province_fort(ctx.game, s.id))
	val.call("num_buildings", PROV, "Число построек", func(ctx, s, _a):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		return float(p.buildings.size()) if p != null else 0.0
	)
	val.call("num_holdings", PROV, "Число владений", func(ctx, s, _a):
		var d: Variant = ctx.game.content.get_def("provinces", s.id)
		return float(Data.as_array(d.get("holdings")).size()) if d != null else 0.0
	)
	val.call("title_tier", TITLE, "Ранг титула", func(ctx, s, _a): return float(Titles.tier_of(ctx.game, s.id)))
	val.call("num_de_jure_counties", TITLE, "Де-юре графств в титуле", func(ctx, s, _a): return float(Titles.de_jure_counties(ctx.game, s.id).size()))
	val.call("current_year", null, "Текущий год", func(ctx, _s, _a): return float(GameDate.year_of(ctx.game.date)))
	val.call("days_since_start", null, "Дней с начала партии", func(ctx, _s, _a): return float(ctx.game.date - int(ctx.game.state.start_date)))
	val.call("war_duration_days", ["war"], "Длительность войны", func(ctx, s, _a):
		var w: Variant = ctx.game.state.wars.get(s.id)
		return float(ctx.game.date - int(w.start)) if w != null else 0.0
	)
	val.call("scheme_progress", ["scheme"], "Прогресс интриги", func(ctx, s, _a):
		var sc: Variant = ctx.game.state.schemes.get(s.id)
		return float(sc.progress) if sc != null else 0.0
	)
	# Навыки и любые характеристики регистрируются по данным (skills) — см. register_skill_values.

	# ============================================================ триггеры
	var trig := func(tname: String, scopes: Variant, doc: String, fn: Callable, describe: Variant = null) -> void:
		var d := {"eval": fn, "doc": doc}
		if scopes != null:
			d["scopes"] = scopes
		if describe != null:
			d["describe"] = describe
		reg.triggers.register(tname, d, O)
	# Триггер персонажа: fn(game, c, arg, ctx, s) -> bool
	var ct := func(tname: String, doc: String, fn: Callable, describe: Variant = null) -> void:
		trig.call(tname, CHAR, doc, func(ctx, s, arg):
			var c: Variant = _ch(ctx, s)
			return c != null and bool(fn.call(ctx.game, c, arg, ctx, s))
		, describe)
	# Да/нет-триггер персонажа: fn(game, c) -> bool
	var yesno := func(tname: String, doc: String, fn: Callable) -> void:
		ct.call(tname, doc, func(g, c, arg, _ctx, _s): return bool(fn.call(g, c)) == _yes(arg),
			func(ctx, _s, arg): return _t(ctx.game, "tr." + tname + ("" if _yes(arg) else ".not")))
	# Триггер «отношение к другому персонажу»: fn(game, c, other) -> bool
	var rel := func(tname: String, doc: String, fn: Callable, desc_key: String = "") -> void:
		ct.call(tname, doc, func(g, c, arg, ctx, s):
			var o: Variant = _target_char(ctx, s, arg)
			return o != null and bool(fn.call(g, c, o))
		, (func(ctx, _s, _arg): return _t(ctx.game, desc_key)) if desc_key != "" else null)

	yesno.call("is_alive", "Жив", func(_g, c): return c.death == null)
	yesno.call("is_female", "Женщина", func(_g, c): return c.female)
	yesno.call("is_male", "Мужчина", func(_g, c): return not c.female)
	yesno.call("is_adult", "Совершеннолетний", func(g, c): return Chars.is_adult(g, c))
	yesno.call("is_child", "Ребёнок", func(g, c): return not Chars.is_adult(g, c))
	yesno.call("is_ruler", "Владеет землями", func(_g, c): return not c.titles.is_empty())
	yesno.call("is_landed", "Владеет землями", func(_g, c): return not c.titles.is_empty())
	yesno.call("is_independent", "Независимый правитель", func(_g, c): return not c.titles.is_empty() and c.liege == null)
	yesno.call("is_vassal", "Вассал", func(_g, c): return not c.titles.is_empty() and c.liege != null)
	yesno.call("is_courtier", "Придворный", func(_g, c): return c.titles.is_empty() and c.liege != null)
	yesno.call("is_married", "В браке", func(_g, c): return not c.spouses.is_empty())
	yesno.call("is_pregnant", "Беременна", func(_g, c): return c.pregnancy != null)
	yesno.call("is_player", "Персонаж игрока", func(g, c): return g.is_player(c.id))
	yesno.call("is_ai", "Персонаж ИИ", func(g, c): return not g.is_player(c.id))
	yesno.call("is_lowborn", "Безродный", func(_g, c): return c.dynasty == null)
	yesno.call("is_at_war", "Ведёт войну", func(g, c): return Wars.is_at_war(g, c.id))
	yesno.call("has_any_claim", "Есть претензии", func(_g, c): return not c.claims.is_empty())

	ct.call("has_trait", "Есть черта", func(_g, c, arg, _ctx, _s):
		if arg is Array:
			return arg.any(func(x): return c.traits.has(x))
		return c.traits.has(str(arg))
	, func(ctx, _s, arg): return _t(ctx.game, "tr.has_trait", {"value": " / ".join(Data.as_array(arg).map(func(x): return ctx.game.name_of("traits", x)))}))
	ct.call("has_trait_category", "Есть черта категории", func(g, c, arg, _ctx, _s):
		return c.traits.any(func(x):
			var d: Variant = g.content.get_def("traits", x)
			return d != null and d.get("category") == arg)
	)
	ct.call("has_modifier", "Есть модификатор", func(_g, c, arg, _ctx, _s): return c.modifiers.any(func(m): return m.id == arg),
		func(ctx, _s, arg): return _t(ctx.game, "tr.has_modifier", {"value": ctx.game.name_of("modifiers", arg)}))
	ct.call("has_flag", "Есть флаг", func(g, c, arg, _ctx, _s):
		var v: Variant = c.flags.get(str(arg))
		return v != null and (v == 0 or v > g.date)
	)
	trig.call("has_global_flag", null, "Есть глобальный флаг", func(ctx, _s, arg):
		var v: Variant = ctx.game.state.global_flags.get(str(arg))
		return v != null and (v == 0 or v > ctx.game.date)
	)
	ct.call("has_var", "Есть переменная", func(_g, c, arg, _ctx, _s): return c.vars.has(str(arg)))
	trig.call("var", null, "Сравнение переменной: var: { name: x, value: \">= 2\" }", func(ctx, s, arg):
		var holder: Variant = _vars_of(ctx, s)
		var v = Data.num(holder.get(arg.get("name"))) if holder != null else 0.0
		return Interp.compare(ctx, s, v, arg.get("value", "!= 0"))
	)
	trig.call("global_var", null, "Сравнение глобальной переменной", func(ctx, s, arg):
		return Interp.compare(ctx, s, Data.num(ctx.game.state.global_vars.get(arg.get("name"))), arg.get("value", "!= 0"))
	)
	trig.call("culture", ["character", "province"], "Культура равна", func(ctx, s, arg):
		var src: Variant = ctx.game.ch(s.id) if s.type == "character" else ctx.game.state.provinces.get(s.id)
		var v: Variant = src.culture if src != null else null
		return arg.has(v) if arg is Array else v == arg
	, func(ctx, _s, arg): return _t(ctx.game, "tr.culture", {"value": ctx.game.name_of("cultures", arg)}))
	trig.call("faith", ["character", "province"], "Вера равна", func(ctx, s, arg):
		var src: Variant = ctx.game.ch(s.id) if s.type == "character" else ctx.game.state.provinces.get(s.id)
		var v: Variant = src.faith if src != null else null
		return arg.has(v) if arg is Array else v == arg
	, func(ctx, _s, arg): return _t(ctx.game, "tr.faith", {"value": ctx.game.name_of("faiths", arg)}))
	trig.call("religion", CHAR, "Религия равна", func(ctx, s, arg):
		var c: Variant = _ch(ctx, s)
		var f: Variant = ctx.game.content.get_def("faiths", c.faith) if c != null else null
		return f != null and f.get("religion") == arg
	)
	ct.call("dynasty", "Династия равна", func(_g, c, arg, _ctx, _s): return c.dynasty == arg)
	rel.call("same_culture_as", "Та же культура", func(_g, c, o): return o.culture == c.culture)
	rel.call("same_faith_as", "Та же вера", func(_g, c, o): return o.faith == c.faith, "tr.same_faith_as")
	rel.call("same_dynasty_as", "Та же династия", func(_g, c, o): return c.dynasty != null and o.dynasty == c.dynasty)
	rel.call("is_spouse_of", "Супруг(а) персонажа", func(_g, c, o): return c.spouses.has(o.id))
	rel.call("is_parent_of", "Родитель персонажа", func(_g, c, o): return Chars.is_parent_of(c, o))
	rel.call("is_child_of", "Ребёнок персонажа", func(_g, c, o): return Chars.is_parent_of(o, c))
	rel.call("is_sibling_of", "Брат/сестра персонажа", func(_g, c, o): return Chars.is_sibling(c, o))
	rel.call("is_close_family_of", "Близкая семья", func(g, c, o): return Chars.is_close_family(g, c, o) or c.spouses.has(o.id))
	rel.call("is_close_relative_of", "Слишком близкое родство для брака", func(g, c, o): return Chars.is_too_close_to_marry(g, c, o))
	rel.call("is_vassal_of", "Прямой вассал персонажа", func(_g, c, o): return not c.titles.is_empty() and c.liege == o.id, "tr.is_vassal_of")
	rel.call("is_liege_of", "Сюзерен персонажа", func(_g, c, o): return o.liege == c.id and not o.titles.is_empty())
	rel.call("is_courtier_of", "Придворный персонажа", func(_g, c, o): return c.titles.is_empty() and c.liege == o.id)
	rel.call("is_in_realm_of", "Состоит в державе персонажа", func(g, c, o): return Titles.is_in_realm_of(g, c, o))
	rel.call("is_at_war_with", "Воюет с персонажем", func(g, c, o): return Wars.is_at_war_with(g, c.id, o.id))
	rel.call("is_allied_with", "Союзник персонажа", func(g, c, o): return Wars.is_allied(g, c.id, o.id))
	rel.call("has_truce_with", "Перемирие с персонажем", func(g, c, o): return Wars.has_truce(g, c.id, o.id))
	rel.call("is_heir_of", "Основной наследник персонажа", func(g, c, o):
		# Расчёт наследников дорогой — для условий достаточно раз в день.
		var heir: Variant = g.cached_daily("heir:" + o.id, func():
			var h := Succession.heirs_of(g, o)
			return h[0] if not h.is_empty() else null)
		return heir == c.id
	)
	rel.call("can_marry", "Может вступить в брак с персонажем", func(g, c, o): return Chars.can_marry(g, c, o), "tr.can_marry")
	rel.call("has_hook_on", "Есть крюк на персонажа", func(g, c, o): return Leverage.hook_on(g, c, o.id) != null, "tr.has_hook_on")
	rel.call("has_strong_hook_on", "Есть сильный крюк на персонажа", func(g, c, o):
		var h: Variant = Leverage.hook_on(g, c, o.id)
		return h != null and h.get("strong", false)
	, "tr.has_strong_hook_on")
	rel.call("can_use_hook_on", "Крюк на персонажа можно использовать сейчас", func(g, c, o): return Leverage.can_use_hook(g, c, o.id))
	ct.call("has_claim_on", "Есть претензия на титул", func(_g, c, arg, ctx, s):
		var r: Variant = Interp.resolve_scope(ctx, s, arg)
		return r != null and c.claims.has(r.id)
	)
	ct.call("holds_title", "Владеет титулом", func(_g, c, arg, ctx, s):
		var r: Variant = Interp.resolve_scope(ctx, s, arg)
		return r != null and c.titles.has(r.id)
	)
	ct.call("has_scheme", "Ведёт интригу: has_scheme: murder или { type, target }", func(g, c, arg, ctx, s):
		var tgt: Variant = null
		var type: Variant = null
		if arg is Dictionary:
			if arg.get("target") != null:
				var r: Variant = Interp.resolve_scope(ctx, s, arg.target)
				tgt = r.id if r != null else null
			type = arg.get("type")
		elif not ScriptContext.is_yes(arg):
			type = arg
		for x in g.state.schemes.values():
			if x.owner == c.id and (type == null or x.type == type) and (tgt == null or x.target == tgt):
				return true
		return false
	)
	ct.call("is_scheme_target", "Является целью интриги", func(g, c, arg, _ctx, _s):
		for x in g.state.schemes.values():
			if x.target == c.id and (arg == null or ScriptContext.is_yes(arg) or x.type == arg):
				return true
		return false
	)
	ct.call("has_opinion_modifier", "Есть модификатор мнения: { target, modifier }", func(_g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg.get("target"))
		return o != null and c.opinions.has(o.id) and c.opinions[o.id].any(func(e): return e.mod == arg.get("modifier"))
	)
	ct.call("has_succession_law", "Закон наследования", func(g, c, arg, _ctx, _s):
		var law: Variant = Succession.law_of(g, c)
		return law != null and law.id == arg
	)
	ct.call("is_primary_heir", "Основной наследник своего сюзерена/отца", func(g, c, _arg, _ctx, _s):
		if c.liege == null or g.ch(c.liege) == null:
			return false
		var h = Succession.heirs_of(g, g.ch(c.liege))
		return not h.is_empty() and h[0] == c.id
	)

	trig.call("has_building", PROV, "Есть постройка", func(ctx, s, arg):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		return p != null and p.buildings.has(arg)
	)
	trig.call("has_holding", PROV, "Есть владение типа", func(ctx, s, arg):
		var d: Variant = ctx.game.content.get_def("provinces", s.id)
		return d != null and Data.as_array(d.get("holdings")).has(arg)
	)
	trig.call("terrain", PROV, "Местность", func(ctx, s, arg):
		var d: Variant = ctx.game.content.get_def("provinces", s.id)
		return d != null and d.get("terrain") == arg
	)
	trig.call("is_occupied", PROV, "Оккупирована", func(ctx, s, arg):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		return (p != null and p.occupant != null) == _yes(arg)
	)
	trig.call("is_coastal", PROV, "Прибрежная", func(ctx, s, arg): return ctx.game.engine.is_coastal(s.id) == _yes(arg))
	trig.call("has_province_modifier", PROV, "Есть модификатор провинции", func(ctx, s, arg):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		return p != null and p.modifiers.any(func(m): return m.id == arg)
	)
	trig.call("has_province_flag", PROV, "Есть флаг провинции", func(ctx, s, arg):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		return p != null and p.flags.has(str(arg))
	)
	trig.call("is_held", TITLE, "У титула есть владелец", func(ctx, s, arg):
		var t: Variant = ctx.game.state.titles.get(s.id)
		return (t != null and t.holder != null) == _yes(arg)
	)
	trig.call("tier_is", TITLE, "Ранг титула: county/duchy/kingdom/empire", func(ctx, s, arg):
		var d: Variant = ctx.game.content.get_def("titles", s.id)
		return d != null and d.tier == arg
	)
	# Проверка: тот же скоуп
	trig.call("is_same_as", null, "Тот же объект, что и путь", func(ctx, s, arg): return ScriptContext.same_scope(s, Interp.resolve_scope(ctx, s, arg)))
	# Шанс-триггер для данных (детерминирован RNG партии)
	trig.call("random_chance", null, "Случайный шанс в процентах (используйте осторожно в триггерах)", func(ctx, s, arg): return ctx.game.rng.next() * 100.0 < Interp.eval_value(ctx, s, arg))

	_register_effects(engine)


static func _register_effects(engine: GameEngine) -> void:
	var reg := engine.scripting
	var O := "core"
	var eff := func(ename: String, scopes: Variant, doc: String, apply: Callable, describe: Variant = null) -> void:
		var d := {"apply": apply, "doc": doc}
		if scopes != null:
			d["scopes"] = scopes
		if describe != null:
			d["describe"] = describe
		reg.effects.register(ename, d, O)
	# Эффект персонажа: apply(game, c, arg, ctx, s)
	var ce := func(ename: String, doc: String, apply: Callable, describe: Variant = null) -> void:
		eff.call(ename, CHAR, doc, func(ctx, s, arg):
			var c: Variant = _ch(ctx, s)
			if c != null:
				apply.call(ctx.game, c, arg, ctx, s)
		, describe)
	var silent := func(_ctx, _s, _arg): return null
	var share_key = "economy.dynasty_prestige_share"

	for res in [["add_gold", "gold"], ["add_prestige", "prestige"], ["add_piety", "piety"]]:
		var ename: String = res[0]
		var field: String = res[1]
		ce.call(ename, "Изменить " + field, func(g, c, arg, ctx, s):
			var v := _num(ctx, s, arg)
			c[field] = float(c[field]) + v
			if field == "prestige" and c.dynasty != null and v > 0:
				var d: Variant = g.state.dynasties.get(c.dynasty)
				if d != null:
					d.prestige = float(d.prestige) + v * g.def_num(share_key, 0.1)
		, func(ctx, s, arg): return _t(ctx.game, "fx." + ename, {"value": signed(_num(ctx, s, arg))}))
	ce.call("add_stress", "Изменить стресс", func(g, c, arg, ctx, s):
		var v := _num(ctx, s, arg)
		if v > 0:
			v *= maxf(0.0, 1.0 + Stats.stat(g, c, "stress_gain_mult"))
		c.stress = maxf(0.0, float(c.stress) + v)
	, func(ctx, s, arg): return _t(ctx.game, "fx.add_stress", {"value": signed(_num(ctx, s, arg))}))
	ce.call("add_health", "Изменить базовое здоровье", func(g, c, arg, ctx, s):
		c.health = float(c.health) + _num(ctx, s, arg)
		g.stat_cache.erase(c.id)
	, func(ctx, s, arg): return _t(ctx.game, "fx.add_health", {"value": signed(_num(ctx, s, arg))}))
	ce.call("add_dynasty_prestige", "Престиж династии", func(g, c, arg, ctx, s):
		var d: Variant = g.state.dynasties.get(c.dynasty) if c.dynasty != null else null
		if d != null:
			d.prestige = float(d.prestige) + _num(ctx, s, arg)
	, func(ctx, s, arg): return _t(ctx.game, "fx.add_dynasty_prestige", {"value": signed(_num(ctx, s, arg))}))
	ce.call("add_skill", "Навсегда изменить навык: { skill, value }", func(g, c, arg, ctx, s):
		var sk: String = arg.skill
		c.skills[sk] = maxf(0.0, Data.num(c.skills.get(sk)) + _num(ctx, s, arg.get("value", 1)))
		g.stat_cache.erase(c.id)
	, func(ctx, s, arg): return _t(ctx.game, "fx.add_skill", {"skill": ctx.game.name_of("skills", arg.skill), "value": signed(_num(ctx, s, arg.get("value", 1)))}))
	ce.call("add_trait", "Добавить черту", func(g, c, arg, _ctx, _s): Chars.add_trait(g, c, str(arg)),
		func(ctx, s, arg):
			var c: Variant = _ch(ctx, s)
			return null if (c != null and c.traits.has(arg)) else _t(ctx.game, "fx.add_trait", {"value": ctx.game.name_of("traits", arg)})
	)
	ce.call("remove_trait", "Убрать черту", func(g, c, arg, _ctx, _s): Chars.remove_trait(g, c, str(arg)),
		func(ctx, s, arg):
			var c: Variant = _ch(ctx, s)
			return _t(ctx.game, "fx.remove_trait", {"value": ctx.game.name_of("traits", arg)}) if (c != null and c.traits.has(arg)) else null
	)
	ce.call("add_modifier", "Добавить модификатор: id или { id, years/months/days }", func(g, c, arg, _ctx, _s):
		var id: String = arg if arg is String else arg.id
		var days = 0 if arg is String else GameDate.duration_days(arg)
		c.modifiers = c.modifiers.filter(func(m): return m.id != id)
		c.modifiers.append({"id": id, "expires": g.date + days if days > 0 else null})
		g.stat_cache.erase(c.id)
	, func(ctx, _s, arg):
		var id: String = arg if arg is String else arg.id
		var days = 0 if arg is String else GameDate.duration_days(arg)
		var md: Variant = ctx.game.content.get_def("modifiers", id)
		var mods: Dictionary = md.get("modifiers", {}) if md != null else {}
		var detail = ", ".join(mods.keys().map(func(k): return "%s %s" % [ctx.game.loc.t_or("stat." + k, k), signed(Data.num(mods[k]))]))
		return _t(ctx.game, "fx.add_modifier_timed" if days > 0 else "fx.add_modifier", {"value": ctx.game.name_of("modifiers", id), "days": roundi(days / 30.0), "detail": detail})
	)
	ce.call("remove_modifier", "Убрать модификатор", func(g, c, arg, _ctx, _s):
		c.modifiers = c.modifiers.filter(func(m): return m.id != arg)
		g.stat_cache.erase(c.id)
	, func(ctx, _s, arg): return _t(ctx.game, "fx.remove_modifier", {"value": ctx.game.name_of("modifiers", arg)}))
	var op_args := func(ctx, s, arg) -> Dictionary:
		return {
			"o": _target_char(ctx, s, arg.get("target", arg.get("who"))),
			"mod": str(arg.get("modifier", "generic")),
			"value": _num(ctx, s, arg.value) if arg.get("value") != null else null,
		}
	var op_value := func(ctx, a) -> float:
		if a.value != null:
			return a.value
		var md: Variant = ctx.game.content.get_def("opinion_modifiers", a.mod)
		return Data.num(md.get("value")) if md != null else 0.0
	ce.call("add_opinion", "Мнение этого персонажа о target: { target, modifier, value? }", func(g, c, arg, ctx, s):
		var a: Dictionary = op_args.call(ctx, s, arg)
		if a.o != null:
			Opinion.add_opinion(g, c, a.o, a.mod, a.value)
	, func(ctx, s, arg):
		var a: Dictionary = op_args.call(ctx, s, arg)
		if a.o == null:
			return null
		return _t(ctx.game, "fx.add_opinion", {"who": ctx.game.scope_name(s), "target": ctx.game.scope_name({"type": "character", "id": a.o.id}), "value": signed(op_value.call(ctx, a)), "mod": ctx.game.name_of("opinion_modifiers", a.mod)})
	)
	ce.call("reverse_add_opinion", "Мнение target об этом персонаже: { target, modifier, value? }", func(g, c, arg, ctx, s):
		var a: Dictionary = op_args.call(ctx, s, arg)
		if a.o != null:
			Opinion.add_opinion(g, a.o, c, a.mod, a.value)
	, func(ctx, s, arg):
		var a: Dictionary = op_args.call(ctx, s, arg)
		if a.o == null:
			return null
		return _t(ctx.game, "fx.add_opinion", {"who": ctx.game.scope_name({"type": "character", "id": a.o.id}), "target": ctx.game.scope_name(s), "value": signed(op_value.call(ctx, a)), "mod": ctx.game.name_of("opinion_modifiers", a.mod)})
	)
	ce.call("remove_opinion", "Убрать модификатор мнения: { target, modifier }", func(g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg.get("target"))
		if o != null:
			Opinion.remove_opinion(g, c, o, str(arg.get("modifier")))
	)
	ce.call("set_flag", "Установить флаг: name или { name, days/months/years }", func(g, c, arg, _ctx, _s):
		var f := _flag_args(g, arg)
		c.flags[f.name] = f.value
	, silent)
	ce.call("remove_flag", "Убрать флаг", func(_g, c, arg, _ctx, _s): c.flags.erase(str(arg)), silent)
	eff.call("set_global_flag", null, "Глобальный флаг", func(ctx, _s, arg):
		var f := _flag_args(ctx.game, arg)
		ctx.game.state.global_flags[f.name] = f.value
	, silent)
	eff.call("remove_global_flag", null, "Убрать глобальный флаг", func(ctx, _s, arg): ctx.game.state.global_flags.erase(str(arg)), silent)
	eff.call("set_var", null, "Переменная: { name, value }", func(ctx, s, arg):
		var h: Variant = _vars_of(ctx, s)
		if h == null:
			return
		var v: Variant = arg.get("value", 1)
		if v is String and not v.contains(".") and not v.contains(":") and not v.is_valid_float() and not ctx.game.engine.scripting.values.has(v):
			h[arg.name] = v
		else:
			h[arg.name] = Interp.eval_value(ctx, s, v)
	, silent)
	eff.call("change_var", null, "Изменить переменную: { name, add }", func(ctx, s, arg):
		var h: Variant = _vars_of(ctx, s)
		if h != null:
			h[arg.name] = Data.num(h.get(arg.name)) + Interp.eval_value(ctx, s, arg.get("add", arg.get("value", 1)))
	, silent)
	eff.call("remove_var", null, "Удалить переменную", func(ctx, s, arg):
		var h: Variant = _vars_of(ctx, s)
		if h != null:
			h.erase(str(arg))
	, silent)
	eff.call("set_global_var", null, "Глобальная переменная", func(ctx, s, arg): ctx.game.state.global_vars[arg.name] = Interp.eval_value(ctx, s, arg.get("value", 1)), silent)

	ce.call("death", "Смерть: yes, причина или { reason, killer }", func(g, c, arg, ctx, s):
		var reason := "natural"
		var killer: Variant = null
		if arg is Dictionary:
			reason = str(arg.get("reason", "natural"))
			if arg.get("killer") != null:
				var k: Variant = _target_char(ctx, s, arg.killer)
				killer = k.id if k != null else null
		elif arg is String and arg != "yes":
			reason = arg
		Succession.kill_character(g, c, reason, killer)
	, func(ctx, s, _arg): return _t(ctx.game, "fx.death", {"who": ctx.game.scope_name(s)}))
	ce.call("add_claim", "Претензия на титул", func(_g, c, arg, ctx, s):
		var r: Variant = Interp.resolve_scope(ctx, s, arg)
		if r != null and r.type == "title" and not c.claims.has(r.id):
			c.claims.append(r.id)
			ctx.game.mark_claims_dirty()
	, func(ctx, s, arg):
		var r: Variant = Interp.resolve_scope(ctx, s, arg)
		return _t(ctx.game, "fx.add_claim", {"value": ctx.game.scope_name(r)}) if r != null else null
	)
	ce.call("remove_claim", "Убрать претензию", func(_g, c, arg, ctx, s):
		var r: Variant = Interp.resolve_scope(ctx, s, arg)
		if r != null:
			c.claims = c.claims.filter(func(x): return x != r.id)
	)
	ce.call("marry", "Заключить брак", func(g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg)
		if o != null and Chars.can_marry(g, c, o):
			Chars.marry(g, c, o)
	, func(ctx, s, arg):
		var o: Variant = _target_char(ctx, s, arg)
		return _t(ctx.game, "fx.marry", {"a": ctx.game.scope_name(s), "b": ctx.game.scope_name({"type": "character", "id": o.id})}) if o != null else null
	)
	ce.call("divorce", "Развод", func(g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg)
		if o != null:
			Chars.divorce(g, c, o)
	)
	ce.call("add_hook", "Крюк на персонажа: path или { target, strong, years }", func(g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg.get("target") if arg is Dictionary else arg)
		if o == null:
			return
		var days = GameDate.duration_days(arg) if arg is Dictionary else 0
		Leverage.add_hook(g, c, o, arg is Dictionary and ScriptContext.is_yes(arg.get("strong")), days)
	, func(ctx, s, arg):
		var o: Variant = _target_char(ctx, s, arg.get("target") if arg is Dictionary else arg)
		var strong: bool = arg is Dictionary and ScriptContext.is_yes(arg.get("strong"))
		return _t(ctx.game, "fx.add_strong_hook" if strong else "fx.add_hook", {"value": ctx.game.scope_name({"type": "character", "id": o.id})}) if o != null else null
	)
	ce.call("remove_hook", "Убрать крюк", func(_g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg)
		if o != null:
			Leverage.remove_hook(c, o.id)
	)
	ce.call("become_vassal_of", "Стать вассалом", func(g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg)
		if o != null and o.id != c.id and not Titles.is_in_realm_of(g, o, c):
			Chars.set_liege(g, c, o.id)
	, func(ctx, s, arg):
		var o: Variant = _target_char(ctx, s, arg)
		return _t(ctx.game, "fx.become_vassal_of", {"who": ctx.game.scope_name(s), "liege": ctx.game.scope_name({"type": "character", "id": o.id})}) if o != null else null
	)
	ce.call("become_independent", "Стать независимым", func(g, c, _arg, _ctx, _s): Chars.set_liege(g, c, null),
		func(ctx, s, _arg): return _t(ctx.game, "fx.become_independent", {"who": ctx.game.scope_name(s)}))
	ce.call("move_to_court", "Переехать ко двору персонажа", func(g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg)
		if o != null and c.titles.is_empty():
			Chars.set_liege(g, c, o.id if not o.titles.is_empty() else o.liege)
	, func(ctx, s, arg):
		var o: Variant = _target_char(ctx, s, arg)
		return _t(ctx.game, "fx.move_to_court", {"who": ctx.game.scope_name(s), "court": ctx.game.scope_name({"type": "character", "id": o.id})}) if o != null else null
	)
	ce.call("add_courtier", "Принять ко двору", func(g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg)
		if o != null and o.titles.is_empty():
			Chars.set_liege(g, o, c.id)
	)
	ce.call("gain_title", "Получить титул", func(g, c, arg, ctx, s):
		var r: Variant = Interp.resolve_scope(ctx, s, arg)
		if r != null and (r.type == "title" or r.type == "province"):
			Titles.transfer_title(g, r.id, c.id)
	, func(ctx, s, arg):
		var r: Variant = Interp.resolve_scope(ctx, s, arg)
		return _t(ctx.game, "fx.gain_title", {"who": ctx.game.scope_name(s), "value": ctx.game.scope_name({"type": "title", "id": r.id})}) if r != null else null
	)
	ce.call("give_title", "Пожаловать титул: { title, to } — получатель становится вассалом", func(g, c, arg, ctx, s):
		var title: Variant = Interp.resolve_scope(ctx, s, arg.get("title"))
		var to: Variant = _target_char(ctx, s, arg.get("to"))
		if title == null or to == null or not c.titles.has(title.id):
			return
		Titles.transfer_title(g, title.id, to.id)
		if to.liege != c.id and to.id != c.id and not Titles.is_in_realm_of(g, c, to) and Titles.primary_tier(g, to) < Titles.primary_tier(g, c):
			Chars.set_liege(g, to, c.id)
	, func(ctx, s, arg):
		var title: Variant = Interp.resolve_scope(ctx, s, arg.get("title"))
		var to: Variant = _target_char(ctx, s, arg.get("to"))
		if title == null or to == null:
			return null
		return _t(ctx.game, "fx.give_title", {"value": ctx.game.scope_name({"type": "title", "id": title.id}), "to": ctx.game.scope_name({"type": "character", "id": to.id})})
	)
	ce.call("lose_title", "Потерять титул (переходит к сюзерену)", func(g, c, arg, ctx, s):
		var r: Variant = Interp.resolve_scope(ctx, s, arg)
		if r != null and c.titles.has(r.id):
			Titles.transfer_title(g, r.id, c.liege)
	)
	ce.call("take_title", "Отобрать титул себе: { title, from? }", func(g, c, arg, ctx, s):
		var r: Variant = Interp.resolve_scope(ctx, s, arg.get("title", arg) if arg is Dictionary else arg)
		var from: Variant = _target_char(ctx, s, arg.from) if (arg is Dictionary and arg.get("from") != null) else null
		if r == null:
			return
		var t: Variant = g.state.titles.get(r.id)
		if from != null and (t == null or t.holder != from.id):
			return
		Titles.transfer_title(g, r.id, c.id, c.id)
	, func(ctx, s, arg):
		var r: Variant = Interp.resolve_scope(ctx, s, arg.get("title", arg) if arg is Dictionary else arg)
		return _t(ctx.game, "fx.gain_title", {"who": ctx.game.scope_name(s), "value": ctx.game.scope_name({"type": "title", "id": r.id})}) if r != null else null
	)
	ce.call("annex_war_targets", "Присоединить цели войны (в контексте войны)", func(g, c, _arg, ctx, _s):
		var wr: Variant = ctx.scopes.get("war")
		var war: Variant = g.state.wars.get(wr.id) if wr != null else null
		if war == null:
			return
		var defender: Variant = g.ch(war.defender)
		for county in war.target_counties:
			var t: Variant = g.state.titles.get(county)
			var h: Variant = g.ch(t.holder) if t != null else null
			if h == null or (defender != null and not Titles.is_in_realm_of(g, h, defender)):
				continue
			if h.id == c.id or Titles.is_in_realm_of(g, h, c):
				continue
			if (defender != null and h.id == defender.id) or Titles.primary_tier(g, h) >= Titles.primary_tier(g, c):
				Titles.transfer_title(g, county, c.id, c.id)
			else:
				Chars.set_liege(g, h, c.id)
		# Титулы защитника, все земли которых теперь у победителя, тоже переходят к нему.
		if defender != null and defender.death == null:
			var mine := {}
			for x in Titles.realm_counties(g, c):
				mine[x] = true
			for tt in defender.titles.duplicate():
				if Titles.tier_of(g, tt) < 2:
					continue
				var dj := Titles.de_jure_counties(g, tt)
				if not dj.is_empty() and dj.all(func(x): return mine.has(x) or g.state.titles.get(x) == null or g.state.titles[x].holder == null):
					Titles.transfer_title(g, tt, c.id, c.id)
	, func(ctx, _s, _arg): return _t(ctx.game, "fx.annex_war_targets"))
	ce.call("lose_all_titles", "Потерять все титулы", func(g, c, _arg, _ctx, _s):
		for tt in c.titles.duplicate():
			Titles.transfer_title(g, tt, c.liege)
		if c.titles.is_empty():
			Titles.become_unlanded(g, c, c.liege)
	)
	ce.call("set_succession_law", "Закон наследования", func(g, c, arg, _ctx, _s):
		if g.content.has("succession_laws", arg):
			c.succession_law = arg
	, func(ctx, _s, arg): return _t(ctx.game, "fx.set_succession_law", {"value": ctx.game.name_of("succession_laws", arg)}))
	ce.call("make_pregnant", "Беременность: { father }", func(g, c, arg, ctx, s):
		var f: Variant = _target_char(ctx, s, arg.get("father", arg) if arg is Dictionary else arg)
		if f != null and c.female and c.pregnancy == null:
			c.pregnancy = {"father": f.id, "due": g.date + int(g.def_num("character.pregnancy_days", 270))}
	, silent)
	ce.call("add_alliance", "Союз с персонажем", func(g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg)
		if o != null and o.id != c.id and not Wars.is_allied(g, c.id, o.id):
			g.state.alliances.append({"a": c.id, "b": o.id, "since": g.date})
	, func(ctx, s, arg):
		var o: Variant = _target_char(ctx, s, arg)
		return _t(ctx.game, "fx.add_alliance", {"value": ctx.game.scope_name({"type": "character", "id": o.id})}) if o != null else null
	)
	ce.call("break_alliance", "Разорвать союз", func(g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg)
		if o != null:
			g.state.alliances = g.state.alliances.filter(func(a): return not ((a.a == c.id and a.b == o.id) or (a.a == o.id and a.b == c.id)))
	)
	ce.call("pay_gold", "Передать золото: { target, value }", func(_g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg.get("target"))
		var v := _num(ctx, s, arg.get("value"))
		if o != null:
			c.gold -= v
			o.gold += v
	, func(ctx, s, arg):
		var o: Variant = _target_char(ctx, s, arg.get("target"))
		return _t(ctx.game, "fx.pay_gold", {"value": roundi(_num(ctx, s, arg.get("value"))), "to": ctx.game.scope_name({"type": "character", "id": o.id})}) if o != null else null
	)
	ce.call("start_scheme", "Начать интригу: { type, target }", func(g, c, arg, ctx, s):
		var o: Variant = _target_char(ctx, s, arg.get("target"))
		if o != null:
			Schemes.start_scheme(g, str(arg.type), c, o)
	)
	ce.call("set_nickname", "Прозвище (ключ локализации или текст)", func(_g, c, arg, _ctx, _s): c.nickname = str(arg),
		func(ctx, s, arg): return _t(ctx.game, "fx.set_nickname", {"who": ctx.game.scope_name(s), "value": ctx.game.loc.resolve(arg)}))
	ce.call("send_message", "Сообщение игроку (если этот персонаж — игрок)", func(g, c, arg, ctx, _s):
		if not g.is_player(c.id):
			return
		var txt: Variant = arg if not (arg is Dictionary) else arg.get("text")
		g.message(g.text(txt, ctx), str(arg.get("kind", "event")) if arg is Dictionary else "event")
	, silent)
	ce.call("create_character", "Создать персонажа: { culture, faith, female, age, traits, dynasty: new|none|path, court, save_scope_as }", func(g, c, arg, ctx, s):
		var a: Dictionary = arg if arg is Dictionary else {}
		var court: Variant = _target_char(ctx, s, a.court) if a.get("court") != null else c
		var dynasty: Variant = null
		if a.get("dynasty") == "new":
			dynasty = "new"
		elif a.get("dynasty") != null and a.dynasty != "none":
			var dc: Variant = _target_char(ctx, s, a.dynasty)
			dynasty = dc.dynasty if dc != null else null
		var opts := {
			"culture": a.get("culture", c.culture), "faith": a.get("faith", c.faith),
			"age": Interp.eval_value(ctx, s, a.age) if a.get("age") != null else g.rng.range_int(18, 40),
			"name": a.get("name"), "dynasty": dynasty, "traits": a.get("traits"),
			"liege": (court.id if not court.titles.is_empty() else court.liege) if court != null else null,
		}
		if a.get("female") != null and a.female != "random":
			opts["female"] = ScriptContext.is_yes(a.female)
		var n := Chars.create_character(g, opts)
		if a.get("save_scope_as") != null:
			ctx.scopes[str(a.save_scope_as)] = {"type": "character", "id": n.id}
	, silent)
	eff.call("end_war", null, "Завершить войну: victory/white_peace/defeat", func(ctx, s, arg):
		var w: Variant = null
		if ctx.scopes.get("war") != null:
			w = ctx.game.state.wars.get(ctx.scopes.war.id)
		elif s != null and s.type == "war":
			w = ctx.game.state.wars.get(s.id)
		if w != null:
			var outcome: Variant = arg.get("outcome") if arg is Dictionary else arg
			Wars.end_war(ctx.game, w, str(outcome) if outcome != null else "white_peace")
	)
	eff.call("change_culture", ["character", "province"], "Сменить культуру", func(ctx, s, arg):
		var src: Variant = ctx.game.ch(s.id) if s.type == "character" else ctx.game.state.provinces.get(s.id)
		if src != null:
			src.culture = str(arg)
	, func(ctx, s, arg): return _t(ctx.game, "fx.change_culture", {"who": ctx.game.scope_name(s), "value": ctx.game.name_of("cultures", arg)}))
	eff.call("change_faith", ["character", "province"], "Сменить веру", func(ctx, s, arg):
		var src: Variant = ctx.game.ch(s.id) if s.type == "character" else ctx.game.state.provinces.get(s.id)
		if src != null:
			src.faith = str(arg)
	, func(ctx, s, arg): return _t(ctx.game, "fx.change_faith", {"who": ctx.game.scope_name(s), "value": ctx.game.name_of("faiths", arg)}))
	eff.call("add_development", PROV, "Изменить развитие", func(ctx, s, arg):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		if p != null:
			p.development = maxi(0, int(p.development) + roundi(_num(ctx, s, arg)))
	, func(ctx, s, arg): return _t(ctx.game, "fx.add_development", {"place": ctx.game.scope_name(s), "value": signed(_num(ctx, s, arg))}))
	eff.call("add_building", PROV, "Добавить постройку", func(ctx, s, arg):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		if p != null and not p.buildings.has(arg):
			p.buildings.append(arg)
			ctx.game.stat_cache.clear()
	, func(ctx, s, arg): return _t(ctx.game, "fx.add_building", {"place": ctx.game.scope_name(s), "value": ctx.game.name_of("buildings", arg)}))
	eff.call("remove_building", PROV, "Убрать постройку", func(ctx, s, arg):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		if p != null:
			p.buildings = p.buildings.filter(func(b): return b != arg)
		ctx.game.stat_cache.clear()
	)
	eff.call("add_province_modifier", PROV, "Модификатор провинции", func(ctx, s, arg):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		if p == null:
			return
		var id: String = arg if arg is String else arg.id
		var days = 0 if arg is String else GameDate.duration_days(arg)
		p.modifiers = p.modifiers.filter(func(m): return m.id != id)
		p.modifiers.append({"id": id, "expires": ctx.game.date + days if days > 0 else null})
		ctx.game.stat_cache.clear()
	, func(ctx, s, arg): return _t(ctx.game, "fx.add_province_modifier", {"place": ctx.game.scope_name(s), "value": ctx.game.name_of("modifiers", arg if arg is String else arg.id)}))
	eff.call("remove_province_modifier", PROV, "Убрать модификатор провинции", func(ctx, s, arg):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		if p != null:
			p.modifiers = p.modifiers.filter(func(m): return m.id != arg)
		ctx.game.stat_cache.clear()
	)
	eff.call("set_province_flag", PROV, "Флаг провинции", func(ctx, s, arg):
		var p: Variant = ctx.game.state.provinces.get(s.id)
		if p != null:
			var f := _flag_args(ctx.game, arg)
			p.flags[f.name] = f.value
	, silent)


## Регистрирует навыки и характеристики из данных (skills) как значения.
static func register_skill_values(engine: GameEngine) -> void:
	for s in engine.content.all("skills"):
		var sid: String = s.id
		engine.scripting.values.register(sid, {"scopes": CHAR, "doc": "Навык: " + sid, "get": func(ctx, scope, _a):
			var c: Variant = ctx.game.ch(scope.id)
			return float(Stats.skill(ctx.game, c, sid)) if c != null else 0.0
		}, "core")
	for key in Data.as_array(engine.content.singleton("defines").get("script_stat_values")):
		if engine.scripting.values.has(key):
			continue
		var k: String = key
		engine.scripting.values.register(k, {"scopes": CHAR, "doc": "Характеристика: " + k, "get": func(ctx, scope, _a):
			var c: Variant = ctx.game.ch(scope.id)
			return Stats.stat(ctx.game, c, k) if c != null else 0.0
		}, "core")

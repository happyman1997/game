class_name Temple
extends EngineFeature
## Вера: добродетели и грехи культов и глава веры.
##
## Данные (поля культа в faiths):
##   virtues, sins — черты, которые культ чтит и осуждает. Единоверец того же
##     культа ценит видимую добродетель правителя (defines.faith.virtue_opinion)
##     и осуждает видимый грех (defines.faith.sin_opinion). Это «лицо»:
##     судят по чертам, а не по душе.
##   head_title — титул главы веры (в ядре — Престол Светоча). Его держатель —
##     глава веры (Великий Светоч) для всех культов с этим полем; пустой титул —
##     престол пуст. Глава веры судит единоверцев по «лицу»: благочестию
##     (defines.faith.head_piety_opinion — по уровням), страху
##     (head_dread_opinion — по ступеням) и ереси (head_heretic_opinion).
##     Его мнение решает в данных отлучение, коронацию, развод.
##   heretic: yes — еретический культ: его последователи — законная цель
##     священной войны (Wars.is_heretic).
## Скрипт: ссылка и список faith_head, условия is_faith_head, faith_doctrine.

const OWNER := "core/temple"


func _init() -> void:
	id = "temple"
	doc = "Вера: добродетели и грехи культов, глава веры"


static func faith_def(game: Game, c: Dictionary) -> Variant:
	return game.content.get_def("faiths", str(c.faith))


## Добродетели и грехи культа: {черта: 1 | -1} (кэш на движке).
static func morals(game: Game, faith_id: String) -> Dictionary:
	var key := "temple:morals:" + faith_id
	var hit: Variant = game.engine.cache.get(key)
	if hit == null:
		hit = {}
		var f: Variant = game.content.get_def("faiths", faith_id)
		if f != null:
			for t in Data.as_array(f.get("virtues")):
				hit[str(t)] = 1
			for t in Data.as_array(f.get("sins")):
				hit[str(t)] = -1
		game.engine.cache[key] = hit
	return hit


## Титул главы веры персонажа (или null).
static func head_title_of(game: Game, c: Dictionary) -> Variant:
	var f: Variant = faith_def(game, c)
	return str(f.head_title) if f != null and f.get("head_title") != null else null


## Глава веры персонажа: держатель head_title его культа (null — престол пуст
## или у культа нет главы).
static func head_of(game: Game, c: Dictionary) -> Variant:
	var ht: Variant = head_title_of(game, c)
	if ht == null:
		return null
	var t: Variant = game.state.titles.get(ht)
	if t == null or t.holder == null:
		return null
	var h: Variant = game.ch(t.holder)
	return h if Chars.is_alive(h) else null


## Держит ли персонаж титул главы какой-либо веры.
static func is_head(game: Game, c: Dictionary) -> bool:
	for f in game.content.all("faiths"):
		if f.get("head_title") != null and c.titles.has(str(f.head_title)):
			return true
	return false


static func _table(game: Game, key: String, lv: int) -> float:
	var arr: Array = Data.as_array(game.def_val(key, []))
	return Data.num(arr[clampi(lv, 0, arr.size() - 1)]) if not arr.is_empty() else 0.0


# ------------------------------------------------------------ установка

func install(engine: GameEngine) -> void:
	# единоверцы того же культа: видимые добродетели и грехи правителя
	engine.opinion_providers.register("faith_morals", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		if a.id == b.id or a.faith != b.faith or b.titles.is_empty():
			return null
		var table := Temple.morals(game, str(a.faith))
		if table.is_empty():
			return null
		var out := []
		for t in b.traits:
			var m: Variant = table.get(t)
			if m == null or not Chars.trait_visible(game, b, t, a.id):
				continue
			var good: bool = m > 0
			var v := game.def_num("faith.virtue_opinion" if good else "faith.sin_opinion", 5.0 if good else -5.0)
			out.append({"label": game.loc.t("opinion.faith_virtue" if good else "opinion.faith_sin", {"trait": game.name_of("traits", t)}), "value": v})
		return out if not out.is_empty() else null
	}, OWNER)
	# глава веры о единоверце: его «лицо» — благочестие, страх, ересь
	engine.opinion_providers.register("faith_head", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		if a.id == b.id or a.titles.is_empty() or b.titles.is_empty():
			return null
		var ht: Variant = Temple.head_title_of(game, b)
		if ht == null or not a.titles.has(ht):
			return null
		var out := []
		var lp := Renown.level_of(game, b, "piety") if game.engine.has_feature("renown") else 1
		var vp := Temple._table(game, "faith.head_piety_opinion", lp)
		if vp != 0.0:
			out.append({"label": game.loc.t("opinion.head_piety", {"name": Renown.level_name(game, "piety", lp)}), "value": vp})
		if game.engine.has_feature("politics"):
			var lv := Politics.tier_level(game, b)
			var vd := Temple._table(game, "faith.head_dread_opinion", lv)
			if vd != 0.0:
				var t: Variant = Politics.tier_at(game, lv)
				out.append({"label": game.loc.t("opinion.head_dread", {"tier": game.name_of("dread_tiers", t.id) if t != null else ""}), "value": vd})
		if Wars.is_heretic(game, b):
			out.append({"label": game.loc.t("opinion.head_heretic"), "value": game.def_num("faith.head_heretic_opinion", -50)})
		return out if not out.is_empty() else null
	}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	var CH := ["character"]
	var ch := func(ctx: ScriptContext, s: Variant) -> Variant:
		return ctx.game.ch(s.id) if (s != null and s.type == "character") else null
	r.links.register("faith_head", {"from": CH, "doc": "Глава веры персонажа (Великий Светоч); нет — престол пуст", "resolve": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		var h: Variant = Temple.head_of(ctx.game, c) if c != null else null
		return {"type": "character", "id": h.id} if h != null else null
	}, OWNER)
	# список из одного главы веры — цель взаимодействий ИИ (ai_targets: faith_head)
	r.lists.register("faith_head", {"from": CH, "doc": "Глава веры персонажа (список из одного или пустой)", "list": func(ctx, s):
		var c: Variant = ch.call(ctx, s)
		var h: Variant = Temple.head_of(ctx.game, c) if c != null else null
		return [{"type": "character", "id": h.id}] if h != null else []
	}, OWNER)
	# учение культа: faith_doctrine: { divorce: approval, polygamy: no }
	r.triggers.register("faith_doctrine", {"scopes": CH, "doc": "Учение культа персонажа (faiths.doctrines): faith_doctrine: { divorce: approval }", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		var f: Variant = Temple.faith_def(ctx.game, c) if c != null else null
		if f == null or not (arg is Dictionary):
			return false
		var d: Dictionary = f.get("doctrines") if f.get("doctrines") is Dictionary else {}
		for k in arg:
			var have: Variant = d.get(k)
			var want: Variant = arg[k]
			if want is String and (want == "yes" or want == "no"):
				want = want == "yes"
			if have is bool or want is bool:
				if bool(have == true) != bool(want == true):
					return false
			elif str(have) != str(want):
				return false
		return true,
		"describe": func(ctx, _s, arg):
			var parts := []
			if arg is Dictionary:
				for k in arg:
					parts.append(ctx.game.loc.t("doctrine.%s.%s" % [k, str(arg[k])]))
			return ctx.game.loc.t("tr.faith_doctrine", {"value": ", ".join(parts)}),
	}, OWNER)
	r.triggers.register("is_faith_head", {"scopes": CH, "doc": "Глава веры (держит титул head_title какого-либо культа): is_faith_head: yes", "eval": func(ctx, s, arg):
		var c: Variant = ch.call(ctx, s)
		return c != null and Temple.is_head(ctx.game, c) == ScriptContext.is_yes(arg),
		"describe": func(ctx, _s, arg): return ctx.game.loc.t("tr.is_faith_head" if ScriptContext.is_yes(arg) else "tr.is_faith_head.not"),
	}, OWNER)

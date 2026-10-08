class_name Titles
extends RefCounted
## Титулы: иерархия де-юре, владения, имена, передача, создание и узурпация.

const TIERS := ["county", "duchy", "kingdom", "empire"]


static func tier_rank(t: Variant) -> int:
	return TIERS.find(t) + 1 if t != null else 0


static func tier_of(game: Game, title_id: Variant) -> int:
	var d: Variant = game.content.get_def("titles", title_id)
	return tier_rank(d.tier) if d != null else 0


static func primary_tier(game: Game, c: Dictionary) -> int:
	return tier_of(game, c.titles[0]) if not c.titles.is_empty() else 0


static func de_jure_liege(game: Game, title_id: String) -> Variant:
	var d: Variant = game.content.get_def("titles", title_id)
	return d.get("liege") if d != null else null


## Все графства, входящие де-юре в титул (для графства — оно само).
static func de_jure_counties(game: Game, title_id: String) -> Array:
	var key := "dejure:" + title_id
	if game.engine.cache.has(key):
		return game.engine.cache[key]
	var children := game.engine.de_jure_children()
	var out := []
	var stack := [title_id]
	while not stack.is_empty():
		var id: String = stack.pop_back()
		var d: Variant = game.content.get_def("titles", id)
		if d == null:
			continue
		if d.tier == "county":
			out.append(id)
		var kids: Array = children.get(id, [])
		for i in range(kids.size() - 1, -1, -1):
			stack.append(kids[i])
	game.engine.cache[key] = out
	return out


## Непосредственные де-юре вассальные титулы.
static func de_jure_vassal_titles(game: Game, title_id: String) -> Array:
	return game.engine.de_jure_children().get(title_id, [])


static func domain_counties(game: Game, c: Dictionary) -> Array:
	return c.titles.filter(func(t): return tier_of(game, t) == 1)


static func top_liege(game: Game, c: Dictionary) -> Dictionary:
	var cur := c
	for i in 30:
		if cur.liege == null:
			break
		var l: Variant = game.ch(cur.liege)
		if l == null or l.death != null:
			break
		cur = l
	return cur


static func is_independent(c: Dictionary) -> bool:
	return not c.titles.is_empty() and c.liege == null


## Правитель и все его вассалы рекурсивно.
static func realm_members(game: Game, c: Dictionary) -> Array:
	var hit: Variant = game.realm_cache.get("m:" + c.id)
	if hit != null:
		return hit.duplicate()
	var out := []
	var stack := [c]
	var seen := {}
	while not stack.is_empty():
		var x: Dictionary = stack.pop_back()
		if seen.has(x.id):
			continue
		seen[x.id] = true
		out.append(x)
		for v in game.vassals_of(x.id):
			stack.append(v)
	game.realm_cache["m:" + c.id] = out
	return out.duplicate()


static func realm_counties(game: Game, c: Dictionary) -> Array:
	var hit: Variant = game.realm_cache.get("c:" + c.id)
	if hit != null:
		return hit.duplicate()
	var out := []
	for m in realm_members(game, c):
		out.append_array(domain_counties(game, m))
	game.realm_cache["c:" + c.id] = out
	return out.duplicate()


## Состоит ли x в державе ruler (x == ruler или ruler — сюзерен x по цепочке).
static func is_in_realm_of(game: Game, x: Dictionary, ruler: Dictionary) -> bool:
	var cur: Variant = x
	for i in 30:
		if cur == null:
			return false
		if cur.id == ruler.id:
			return true
		cur = game.ch(cur.liege)
	return false


static func county_holder(game: Game, county_id: String) -> Variant:
	var t: Variant = game.state.titles.get(county_id)
	return game.ch(t.holder) if t != null else null


## Кто контролирует провинцию: оккупант или владелец графства.
static func province_controller(game: Game, prov_id: String) -> Variant:
	var p: Variant = game.state.provinces.get(prov_id)
	if p == null:
		return null
	var occ: Variant = game.ch(p.occupant)
	return occ if occ != null else county_holder(game, prov_id)


static func capital_of(game: Game, c: Dictionary) -> Variant:
	var dom := domain_counties(game, c)
	if c.capital != null and dom.has(c.capital):
		return c.capital
	return dom[0] if not dom.is_empty() else null


# ------------------------------------------------------------ имена

static func tier_name(game: Game, tier: String) -> String:
	return game.loc.t("tier." + tier)


static func short_name(game: Game, id: String) -> String:
	return game.name_of("titles", id)


static func full_name(game: Game, id: String) -> String:
	var full: Variant = game.loc.raw(id + "_full")
	if full != null:
		return full
	var d: Variant = game.content.get_def("titles", id)
	if d == null:
		return id
	return tier_name(game, d.tier) + " " + short_name(game, id)


static func rank_name(game: Game, c: Dictionary) -> String:
	if c.titles.is_empty():
		return ""
	var t: String = c.titles[0]
	var d: Variant = game.content.get_def("titles", t)
	if d == null:
		return ""
	var g = "f" if c.female else "m"
	for k in ["%s_rank_%s" % [t, g], "rank.%s.%s.%s" % [c.culture, d.tier, g], "rank.%s.%s" % [d.tier, g]]:
		var v: Variant = game.loc.raw(k)
		if v != null:
			return v
	return d.tier


# ------------------------------------------------------------ передача титулов

static func _sort_titles(game: Game, c: Dictionary) -> void:
	var prev_primary: Variant = c.titles[0] if not c.titles.is_empty() else null
	Data.stable_sort(c.titles, func(a, b):
		var d := tier_of(game, b) - tier_of(game, a)
		if d != 0:
			return d
		if a == prev_primary:
			return -1
		if b == prev_primary:
			return 1
		return 0)


## Передаёт титул новому владельцу (или делает его вакантным при null).
## Следит за согласованностью: основной титул, столица, сюзеренитет.
static func transfer_title(game: Game, title_id: String, new_holder_id: Variant, court: Variant = null) -> void:
	var t: Variant = game.state.titles.get(title_id)
	if t == null:
		return
	var old: Variant = game.ch(t.holder)
	var neo: Variant = game.ch(new_holder_id)
	if (old.id if old != null else null) == (neo.id if neo != null else null):
		return
	var old_primary_tier = primary_tier(game, neo) if neo != null else 0
	game.realm_cache.clear()

	if old != null:
		old.titles = old.titles.filter(func(x): return x != title_id)
		if old.capital == title_id:
			var dom := domain_counties(game, old)
			old.capital = dom[0] if not dom.is_empty() else null
		if old.titles.is_empty() and old.death == null:
			become_unlanded(game, old, court if court != null else (neo.id if neo != null else null))
	t.holder = neo.id if neo != null else null
	if neo != null:
		t.history.append({"holder": neo.id, "from": game.date})
		if t.history.size() > 30:
			t.history = t.history.slice(t.history.size() - 30)
		neo.titles.append(title_id)
		_sort_titles(game, neo)
		neo.claims = neo.claims.filter(func(x): return x != title_id)
		if neo.capital == null or not neo.titles.has(neo.capital):
			var td: Variant = game.content.get_def("titles", neo.titles[0])
			var cap: Variant = td.get("capital") if td != null else null
			if cap != null and neo.titles.has(cap):
				neo.capital = cap
			else:
				var dom := domain_counties(game, neo)
				neo.capital = dom[0] if not dom.is_empty() else null
		fix_liege_consistency(game, neo)
		if primary_tier(game, neo) > old_primary_tier:
			for v in game.vassals_of(neo.id):
				fix_liege_consistency(game, v)
	game.mark_chars_dirty([old.id if old != null else null, neo.id if neo != null else null])
	game.emit("title.transferred", {"title": title_id, "from": old.id if old != null else null, "to": neo.id if neo != null else null})
	if neo != null:
		game.on_action("on_title_gained", {"type": "character", "id": neo.id}, {"title": {"type": "title", "id": title_id}})


## Персонаж потерял все земли: его вассалы уходят к его сюзерену, сам он — ко двору.
static func become_unlanded(game: Game, c: Dictionary, court: Variant = null) -> void:
	var new_liege: Variant = c.liege if c.liege != null else court
	for v in game.vassals_of(c.id):
		Chars.set_liege(game, v, new_liege if (new_liege != null and new_liege != v.id) else null)
	var target: Variant = new_liege if (new_liege != null and new_liege != c.id) else null
	for ct in game.courtiers_of(c.id):
		Chars.set_liege(game, ct, target)
	Chars.set_liege(game, c, target)
	c.capital = null


## Вассал не может быть рангом выше или равным сюзерену; нет циклов.
static func fix_liege_consistency(game: Game, c: Dictionary) -> void:
	if c.liege == null or c.titles.is_empty():
		return
	var l: Variant = game.ch(c.liege)
	if l == null or l.death != null or l.titles.is_empty():
		Chars.set_liege(game, c, l.liege if l != null else null)
		return
	if primary_tier(game, c) >= primary_tier(game, l):
		Chars.set_liege(game, c, null)
		return
	# защита от циклов
	var cur: Variant = l
	for i in 30:
		if cur == null:
			break
		if cur.liege == c.id:
			Chars.set_liege(game, c, null)
			return
		cur = game.ch(cur.liege)


## «Естественный» сюзерен правителя по де-юре иерархии:
## владелец ближайшего вышестоящего де-юре титула.
static func de_jure_liege_holder(game: Game, c: Dictionary) -> Variant:
	if c.titles.is_empty():
		return null
	var my_tier := primary_tier(game, c)
	var t: Variant = de_jure_liege(game, c.titles[0])
	while t != null:
		var st: Variant = game.state.titles.get(t)
		var h: Variant = game.ch(st.holder) if st != null else null
		if h != null and h.id != c.id and primary_tier(game, h) > my_tier:
			return h
		t = de_jure_liege(game, t)
	return null


# ------------------------------------------------------------ создание и узурпация

## {have, total}
static func controlled_share(game: Game, c: Dictionary, title_id: String) -> Dictionary:
	var counties := de_jure_counties(game, title_id)
	var mine := {}
	for x in realm_counties(game, c):
		mine[x] = true
	return {"have": Data.count(counties, func(x): return mine.has(x)), "total": counties.size()}


## {gold, prestige}
static func title_action_cost(game: Game, title_id: String, kind: String) -> Dictionary:
	var d: Variant = game.title_def(title_id)
	var table: Variant = game.def_val("titles.%s_cost.%s" % [kind, d.tier], {})
	return {"gold": Data.num(table.get("gold")), "prestige": Data.num(table.get("prestige"))}


## {ok, reasons}
static func _title_action_check(game: Game, c: Dictionary, title_id: String, kind: String) -> Dictionary:
	var reasons := []
	var d: Variant = game.content.get_def("titles", title_id)
	var st: Variant = game.state.titles.get(title_id)
	if d == null or st == null:
		return {"ok": false, "reasons": ["?"]}
	if kind == "create":
		if d.tier == "county" or d.get("no_create", false):
			reasons.append(game.loc.t("ui.cannot_create_tier"))
		if st.holder != null:
			reasons.append(game.loc.t("ui.title_already_held"))
	else:
		if d.tier == "county":
			reasons.append(game.loc.t("ui.cannot_create_tier"))
		if st.holder == null or st.holder == c.id:
			reasons.append(game.loc.t("ui.title_not_held_by_other"))
	if c.liege != null and game.ch(c.liege) != null and tier_rank(d.tier) >= primary_tier(game, game.ch(c.liege)):
		reasons.append(game.loc.t("ui.would_outrank_liege"))
	var share := controlled_share(game, c, title_id)
	var need = ceili(share.total * game.def_num("titles.create_fraction", 0.51))
	if share.have < need:
		reasons.append(game.loc.t("ui.need_counties", {"have": share.have, "need": need}))
	var cost := title_action_cost(game, title_id, kind)
	if cost.gold > 0 and c.gold < cost.gold:
		reasons.append(game.loc.t("ui.need_gold", {"value": cost.gold}))
	if cost.prestige > 0 and c.prestige < cost.prestige:
		reasons.append(game.loc.t("ui.need_prestige", {"value": cost.prestige}))
	return {"ok": reasons.is_empty(), "reasons": reasons}


static func can_create_title(game: Game, c: Dictionary, title_id: String) -> Dictionary:
	return _title_action_check(game, c, title_id, "create")


static func create_title(game: Game, c: Dictionary, title_id: String) -> bool:
	if not can_create_title(game, c, title_id).ok:
		return false
	if not game.engine.hooks.veto("title.create", {"game": game, "character": c, "title": title_id}):
		return false
	var cost := title_action_cost(game, title_id, "create")
	c.gold -= cost.gold
	c.prestige -= cost.prestige
	transfer_title(game, title_id, c.id)
	game.message(game.loc.t("msg.title_created", {"who": game.scope_name({"type": "character", "id": c.id}), "title": full_name(game, title_id)}), "good", {"type": "title", "id": title_id})
	return true


static func can_usurp_title(game: Game, c: Dictionary, title_id: String) -> Dictionary:
	return _title_action_check(game, c, title_id, "usurp")


static func usurp_title(game: Game, c: Dictionary, title_id: String) -> bool:
	if not can_usurp_title(game, c, title_id).ok:
		return false
	if not game.engine.hooks.veto("title.usurp", {"game": game, "character": c, "title": title_id}):
		return false
	var old: Dictionary = game.ch(game.state.titles[title_id].holder)
	var cost := title_action_cost(game, title_id, "usurp")
	c.gold -= cost.gold
	c.prestige -= cost.prestige
	transfer_title(game, title_id, c.id)
	game.message(
		game.loc.t("msg.title_usurped", {"who": game.scope_name({"type": "character", "id": c.id}), "title": full_name(game, title_id), "from": game.scope_name({"type": "character", "id": old.id})}),
		"bad", {"type": "title", "id": title_id}, [c.id, old.id])
	return true


## Титул без земли не держится: правитель без единого графства передаёт
## титулы сюзерену, а независимый — сильнейшему вассалу (или титулы пустеют).
static func enforce_landed_titles(game: Game) -> void:
	for c in game.rulers().duplicate():
		if c.death != null or c.titles.is_empty() or not domain_counties(game, c).is_empty():
			continue
		var titles: Array = c.titles.duplicate()
		var liege: Variant = game.ch(c.liege)
		var heir: Variant = liege if (liege != null and liege.death == null) else null
		if heir == null:
			var vassals = game.vassals_of(c.id)
			Data.sort_by(vassals, func(v): return domain_counties(game, v).size(), true)
			heir = vassals[0] if not vassals.is_empty() else null
		Data.sort_by(titles, func(t): return tier_of(game, t), true)
		for t in titles:
			transfer_title(game, t, heir.id if heir != null else null, heir.id if heir != null else null)
		if heir != null and heir.liege == null:
			for v in game.vassals_of(c.id):
				Chars.set_liege(game, v, heir.id)

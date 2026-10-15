class_name Alerts
extends RefCounted
## Оповещения вверху экрана. Встроенные регистрируются здесь в общий реестр
## engine.ui.alerts — моды добавляют свои так же:
##   api.ui.alerts.register("my_alert", {"id": "my_alert", "check": func(game): return {"icon": "🔔", "text": "…", "action": {"tab": "realm"}}})

static var _cache := {}


static func register_builtin(engine: GameEngine) -> void:
	var reg := func(id: String, order: int, check: Callable) -> void:
		if not engine.ui.alerts.has(id):
			engine.ui.alerts.register(id, {"id": id, "order": order, "check": check}, "core")

	reg.call("perk_available", 10, func(g: Game):
		var p: Dictionary = g.player
		if not g.engine.has_feature("lifestyles"):
			return null
		var l: Variant = Lifestyles.current(g, p)
		if l == null or Lifestyles.available_perks(g, p, l.id).is_empty():
			return null
		if Lifestyles.xp_of(p, l.id) < Lifestyles.perk_cost(g, p, l.id):
			return null
		return {"icon": "leaf", "kind": "good", "text": g.loc.t("alert.perk_available", {"lifestyle": g.name_of("lifestyles", l.id)}), "action": {"tab": "lifestyle"}})
	reg.call("council_vacant", 20, func(g: Game):
		var p: Dictionary = g.player
		if not g.engine.has_feature("council") or p.titles.is_empty():
			return null
		var empty := []
		for pos in Council.positions(g):
			if not Council.is_position_shown(g, p, pos):
				continue
			var seat: Variant = Council.seat_of(p, pos.id)
			if (seat == null or seat.get("holder") == null) and not Council.candidates(g, p, pos.id).is_empty():
				empty.append(g.name_of("council_positions", pos.id))
		if empty.is_empty():
			return null
		return {"icon": "council", "kind": "info", "text": g.loc.t("alert.council_vacant", {"list": ", ".join(empty)}), "action": {"tab": "realm"}})
	reg.call("legacy_available", 12, func(g: Game):
		var p: Dictionary = g.player
		if not g.engine.has_feature("dynasties") or p.dynasty == null or not Dynasties.is_head(g, p):
			return null
		var root: Variant = Chars.dynasty_root(g, p.dynasty)
		if Dynasties.renown(g, root) < Dynasties.legacy_cost(g, root):
			return null
		for l in g.content.all("dynasty_legacies"):
			if Dynasties.legacy_blockers(g, p, l.id).is_empty():
				return {"icon": "dynasty", "kind": "good", "text": g.loc.t("alert.legacy_available", {"n": roundi(Dynasties.renown(g, root))}), "action": {"tab": "dynasty"}}
		return null)
	# созван Собор: вопрос, срок и нынешний расклад голосов
	reg.call("synod", 14, func(g: Game):
		var p: Dictionary = g.player
		if not g.engine.has_feature("synod") or p.titles.is_empty():
			return null
		var a: Variant = Synod.active_for(g, p)
		var head: Variant = Temple.head_of(g, p)
		if a == null or head == null:
			return null
		var pv := Synod.preview(g, head, a)
		var months := maxi(0, roundi((int(a.convene) - g.date) / 30.0))
		return {"icon": "piety", "kind": "info", "text": g.loc.t("alert.synod", {"question": Synod.question_name(g, str(a.question), a), "months": months, "for": roundi(pv["for"]), "against": roundi(pv.against)}), "action": {"character": head.id}})
	reg.call("child_no_guardian", 15, func(g: Game):
		var p: Dictionary = g.player
		if not g.engine.has_feature("upbringing"):
			return null
		var kids := []
		var seen := {}
		for x in g.courtiers_of(p.id) + Succession.alive_children(g, p) + [p]:
			if seen.has(x.id) or not Upbringing.in_education(g, x) or Upbringing.guardian_of(g, x) != null or not Upbringing.can_manage(g, p, x):
				continue
			# чужих детей при дворе опекуном обеспечивает сам двор
			if not (x.id == p.id or x.father == p.id or x.mother == p.id or (x.dynasty != null and x.dynasty == p.dynasty)):
				continue
			seen[x.id] = true
			kids.append(x)
		if kids.is_empty():
			return null
		var first: String = kids[0].id
		return {"icon": "baby", "kind": "bad", "text": g.loc.t("alert.child_no_guardian", {"list": ", ".join(kids.map(func(k): return Chars.char_name(g, k)))}), "action": {"character": first, "subtab": ["character", "family"]}})
	reg.call("artifact_wearing", 24, func(g: Game):
		var p: Dictionary = g.player
		if not g.engine.has_feature("artifacts"):
			return null
		var worn: Array = Artifacts.equipped(g, p).filter(func(it): return not Artifacts.indestructible(g, it) and Artifacts.durability_frac(it) < 0.25)
		if worn.is_empty():
			return null
		return {"icon": "hammer", "kind": "bad", "text": g.loc.t("alert.artifact_wearing", {"list": ", ".join(worn.slice(0, 3).map(func(it): return Artifacts.name_of(g, it)))}),
			"action": {"character": p.id, "subtab": ["character", "inventory"]}})
	reg.call("artifact_free_slot", 34, func(g: Game):
		var p: Dictionary = g.player
		if not g.engine.has_feature("artifacts"):
			return null
		var fit := []
		for it in Artifacts.storage(g, p):
			var slot := Artifacts.slot_of(g, it)
			if Artifacts.in_slot(g, p, slot).size() < Artifacts.slot_capacity(g, p, slot):
				fit.append(it)
		if fit.is_empty():
			return null
		return {"icon": "bag", "kind": "info", "text": g.loc.t("alert.artifact_free_slot", {"list": ", ".join(fit.slice(0, 3).map(func(it): return Artifacts.name_of(g, it)))}),
			"action": {"character": p.id, "subtab": ["character", "inventory"]}})
	reg.call("choose_ambition", 16, func(g: Game):
		var p: Dictionary = g.player
		if not g.engine.has_feature("ambitions") or Ambitions.offers(p).is_empty():
			return null
		return {"icon": "star", "kind": "info", "text": g.loc.t("alert.choose_ambition"), "action": {"character": p.id}})
	reg.call("ambitions_frustrated", 21, func(g: Game):
		var p: Dictionary = g.player
		if not g.engine.has_feature("ambitions"):
			return null
		var list := Ambitions.frustrated_of(g, p)
		if list.is_empty():
			return null
		var first: String = list[0].id
		return {"icon": "star", "kind": "bad", "text": g.loc.t("alert.ambitions_frustrated", {"list": ", ".join(list.slice(0, 4).map(func(x): return Chars.char_name(g, x)))}),
			"action": {"character": first}})
	reg.call("powerful_snubbed", 22, func(g: Game):
		var p: Dictionary = g.player
		if not g.engine.has_feature("politics") or p.titles.is_empty():
			return null
		var list := Politics.snubbed(g, p)
		if list.is_empty():
			return null
		return {"icon": "crown", "kind": "bad", "text": g.loc.t("alert.powerful_snubbed", {"list": ", ".join(list.map(func(v): return g.scope_name({"type": "character", "id": v.id})))}), "action": {"tab": "realm"}})
	# Страх правителя — в верхней панели, пока он есть.
	if not engine.ui.top_bar.has("dread"):
		engine.ui.top_bar.register("dread", {"id": "dread", "order": 5, "render": func(g: Game) -> Variant:
			var p: Variant = g.player
			if p == null or not g.engine.has_feature("politics"):
				return null
			var d := Politics.dread(p)
			if d < 1.0:
				return null
			var t: Variant = Politics.tier_of(g, p)
			var tip := func() -> String:
				return FeatureSections.dread_tip(App.instance, p) if App.instance != null else BB.esc(g.loc.t("ui.dread_tip"))
			return {"icon": t.get("icon", "chain") if t != null else "chain", "text": str(roundi(d)), "tooltip": tip}}, "core")
	reg.call("title_creatable", 30, func(g: Game):
		var p: Dictionary = g.player
		var cands := {}
		for c in Titles.realm_counties(g, p):
			var d: Variant = g.title_def(c)
			var tt: Variant = d.get("liege") if d != null else null
			while tt != null:
				if not p.titles.has(tt):
					cands[tt] = true
				var td: Variant = g.title_def(tt)
				tt = td.get("liege") if td != null else null
		var ok := []
		for x in cands:
			if Titles.can_create_title(g, p, x).ok:
				ok.append(g.scope_name({"type": "title", "id": x}))
		if ok.is_empty():
			return null
		return {"icon": "crown", "kind": "good", "text": g.loc.t("alert.title_creatable", {"list": ", ".join(ok)}), "action": {"tab": "realm"}})
	reg.call("faction_threat", 40, func(g: Game):
		if not g.engine.has_feature("factions"):
			return null
		var p: Dictionary = g.player
		var out := []
		var worst := 0.0
		for f in Factions.against(g, p.id):
			if float(f.discontent) >= 50:
				worst = maxf(worst, float(f.discontent))
		if worst > 0:
			out.append({"icon": "fist", "kind": "bad", "text": g.loc.t("alert.faction_threat", {"n": roundi(worst)}), "action": {"tab": "realm"}})
		var mine: Variant = Factions.faction_of(g, p)
		if mine != null and mine.leader == p.id and float(mine.discontent) >= 100:
			out.append({"icon": "banner", "kind": "good", "text": g.loc.t("alert.faction_ready"), "action": {"tab": "realm"}})
		return out)
	reg.call("no_heir", 50, func(g: Game):
		var p: Dictionary = g.player
		if p.titles.is_empty() or not Succession.heirs_of(g, p).is_empty():
			return null
		return {"icon": "warning", "kind": "bad", "text": g.loc.t("alert.no_heir"), "action": {"character": p.id}})
	reg.call("unmarried", 55, func(g: Game):
		var p: Dictionary = g.player
		var age := Chars.age_of(g, p)
		if not p.spouses.is_empty() or age < g.def_num("character.marriage_age", 16) or age > 60:
			return null
		return {"icon": "ring", "kind": "info", "text": g.loc.t("alert.unmarried"), "action": {"character": p.id}})
	reg.call("debt", 60, func(g: Game):
		if float(g.player.gold) >= 0:
			return null
		return {"icon": "gold", "kind": "bad", "text": g.loc.t("alert.debt"), "action": {"tab": "realm"}})
	reg.call("over_domain", 65, func(g: Game):
		var p: Dictionary = g.player
		var n := Titles.domain_counties(g, p).size()
		var lim := Economy.domain_limit(g, p)
		if n <= lim:
			return null
		return {"icon": "castle", "kind": "bad", "text": g.loc.t("alert.over_domain", {"n": n, "limit": lim}), "action": {"tab": "realm"}})
	reg.call("enemy_in_realm", 70, func(g: Game):
		var p: Dictionary = g.player
		var wars := Wars.wars_of(g, p.id)
		if wars.is_empty():
			return null
		var war_ids := {}
		for w in wars:
			war_ids[w.id] = true
		var occupied := []
		for c in Titles.realm_counties(g, p):
			var st: Variant = g.prov(c)
			if st != null and st.occupant != null and war_ids.has(st.get("occupant_war")):
				occupied.append(c)
		if occupied.is_empty():
			return null
		return {"icon": "fire", "kind": "bad", "text": g.loc.t("alert.occupied", {"n": occupied.size()}), "action": {"province": occupied[0]}})
	reg.call("schemes_against", 75, func(g: Game):
		var n := 0
		for s in g.state.schemes.values():
			if s.target == g.state.player and s.get("discovered", false):
				n += 1
		if n == 0:
			return null
		return {"icon": "dagger", "kind": "bad", "text": g.loc.t("alert.schemes_against", {"n": n}), "action": {"tab": "intrigue"}})
	reg.call("prisoners", 80, func(g: Game):
		if not g.engine.has_feature("prison"):
			return null
		var n := Prison.prisoners_of(g, g.state.player).size()
		if n == 0:
			return null
		return {"icon": "chain", "kind": "info", "text": g.loc.t("alert.prisoners", {"n": n}), "action": {"tab": "intrigue"}})
	reg.call("imprisoned", 81, func(g: Game):
		var p: Dictionary = g.player
		if p.get("prison") == null:
			return null
		return {"icon": "chain", "kind": "bad", "text": g.loc.t("alert.imprisoned", {"jailer": g.scope_name({"type": "character", "id": p.prison.by})}), "action": {"character": p.prison.by}})
	reg.call("can_recruit", 90, func(g: Game):
		if not g.engine.has_feature("regiments"):
			return null
		var p: Dictionary = g.player
		if p.titles.is_empty() or float(p.gold) < 150:
			return null
		for d in Regiments.types(g):
			if Regiments.recruit_blockers(g, p, d).is_empty():
				return {"icon": "shield", "kind": "info", "text": g.loc.t("alert.can_recruit"), "action": {"tab": "military"}}
		return null)


static func collect(game: Game, force: bool = false) -> Array:
	if game.state.player == null or game.player == null:
		return []
	if not force and _cache.get("date") == game.date and _cache.get("player") == game.state.player and _cache.get("game") == game.get_instance_id():
		return _cache.alerts
	var out := []
	var specs: Array = game.engine.ui.alerts.values()
	Data.sort_by(specs, func(s): return Data.num(s.get("order")))
	for spec in specs:
		var r: Variant = spec.check.call(game)
		if r == null:
			continue
		for a in (r if r is Array else [r]):
			if a is Dictionary:
				out.append(a)
	_cache = {"date": game.date, "player": game.state.player, "game": game.get_instance_id(), "alerts": out}
	return out


static func invalidate() -> void:
	_cache = {}


static func run_action(app: App, a: Variant) -> void:
	if not (a is Dictionary):
		return
	# нужная вкладка окна: subtab: [вид окна, вкладка]
	if a.get("subtab") is Array and a.subtab.size() == 2:
		app.subtabs[str(a.subtab[0])] = str(a.subtab[1])
	if a.get("tab") != null:
		if not (app.panel_ref != null and app.panel_ref.kind == "tab" and app.panel_ref.id == a.tab):
			app.open_tab(a.tab)
	elif a.get("character") != null:
		app.open_character(a.character)
	elif a.get("title") != null:
		app.open_title(a.title)
	elif a.get("province") != null:
		app.open_province(a.province, true)

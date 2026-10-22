class_name TabPanels
extends RefCounted
## Вкладки «Интриги», «Решения», «Держава» (с внутренними вкладками: обзор,
## вассалы, совет, законы, политика), «Летопись» и выбор персонажа.


static func intrigue(app: App) -> Control:
	var g := app.game
	var p: Dictionary = g.player
	var root := K.vbox([], 10)
	root.add_child(K.para(app.t("ui.scheme_hint"), "SmallLabel"))
	var mine: Array = g.state.schemes.values().filter(func(s): return s.owner == p.id)
	var rows := []
	for s in mine:
		var def: Variant = g.content.get_def("schemes", s.type)
		var sid: String = s.id
		var target: Variant = g.ch(s.target)
		var info := K.vbox([
			K.hbox([K.label(g.name_of("schemes", s.type) + " →", "SubheaderLabel"), W.char_link(app, s.target, true)], 4),
			K.bar(s.progress, 100, Color("#7a4ab0")),
			K.label(app.t("ui.scheme_stats", {"progress": int(s.progress), "speed": K.fmt(Schemes.monthly_progress(g, s), 1), "chance": Schemes.success_chance(g, s)}) + (" · " + app.t("ui.discovered") if s.get("discovered", false) else ""), "SmallLabel"),
		], 3)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := K.hbox([K.icon(def.get("icon", "dagger") if def != null else "dagger", 26), info], 8)
		if target != null:
			row.add_child(W.portrait(app, target, 48))
		row.add_child(K.button("", func():
			Schemes.end_scheme(g, sid)
			app.mark_dirty(true), {"icon": "close", "tip": app.t("ui.abandon")}))
		rows.append([W.category_of(g, "schemes", def) if def != null else "other", K.panel(row, "InsetPanel")])
	var mine_box: Control = W.grouped(app, "schemes", rows) if not rows.is_empty() else K.label(app.t("ui.none"), "MutedLabel")
	root.add_child(K.section(app.t("ui.my_schemes"), [mine_box], "dagger"))
	var against: Array = g.state.schemes.values().filter(func(s): return s.target == p.id and s.get("discovered", false))
	if not against.is_empty():
		var al := []
		for s in against:
			al.append(K.hbox([K.label(g.name_of("schemes", s.type) + ":", "BadLabel"), W.char_link(app, s.owner, true), K.label("(%d%%)" % int(s.progress), "MutedLabel")], 4))
		root.add_child(K.section(app.t("ui.schemes_against"), al, "warning"))
	for sec in FeatureSections.secrets_intrigue(app):
		root.add_child(sec)
	if g.engine.has_feature("prison"):
		var prisoners := Prison.prisoners_of(g, p.id)
		if not prisoners.is_empty():
			var pl := []
			for c in prisoners:
				pl.append(W.char_row(app, c, [app.t("ui.prison_months", {"n": int((g.date - c.prison.since) / 30)}) + " · " + app.t("ui.ransom_n", {"n": Prison.ransom_cost(g, c)})]))
			root.add_child(K.section("%s (%d)" % [app.t("ui.prisoners"), prisoners.size()], pl, "chain"))
	return root


static func decisions(app: App) -> Control:
	var g := app.game
	var p: Dictionary = g.player
	var root := K.vbox([], 8)
	var defs: Array = g.content.all("decisions").filter(func(d): return Decisions.is_shown(g, d, p))
	# запертые ключами — в конец: видно, к чему стремиться
	var kctx := Decisions.context(g, p)
	Data.sort_by(defs, func(d): return (0 if d.get("major", false) else 1) + (0 if Keys.opened(kctx, kctx.root, d) else 2))
	var items := []
	for d in defs:
		var blockers := Decisions.blockers(g, d, p)
		var cost := Decisions.cost(g, d, p)
		var did: String = d.id
		var info := K.vbox([
			K.label(g.name_of("decisions", d.id), "SubheaderLabel"),
			K.para(g.desc_of("decisions", d.id), "MutedLabel"),
			K.hbox([K.rich(BB.cost(g, cost), false), K.expand(), K.button(app.t("ui.take_decision"), func():
				if Decisions.take(g, d, p):
					app.toast(g.name_of("decisions", did), "good")
				app.mark_dirty(true), {"variation": "GoldButton", "disabled": not blockers.is_empty(),
				"tip": func(): return BB.effect(g, d.get("effect"), {"type": "character", "id": p.id}, {"actor": {"type": "character", "id": p.id}}, app.t("ui.effects")) + W.keys_tip(app, d, p) + ("\n" + BB.reasons(blockers) if not blockers.is_empty() else "")})], 6),
		], 3)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card := K.panel(K.hbox([K.icon(d.get("icon", "scroll"), 34), info], 10), "InsetPanel")
		if not blockers.is_empty():
			card.modulate = Color(0.8, 0.8, 0.8)
		items.append([W.category_of(g, "decisions", d), card])
	if not items.is_empty():
		root.add_child(W.grouped(app, "decisions", items))
	if defs.is_empty():
		root.add_child(K.label(app.t("ui.no_decisions"), "MutedLabel"))
	return root


static func realm(app: App) -> Control:
	var g := app.game
	var p: Dictionary = g.player
	var vassals := g.vassals_of(p.id)
	var tabs := [
		{"id": "overview", "name": app.t("ui.rtab.overview"), "icon": "castle"},
		{"id": "vassals", "name": app.t("ui.rtab.vassals"), "icon": "shield", "badge": vassals.size()},
	]
	if g.engine.has_feature("council"):
		tabs.append({"id": "council", "name": app.t("ui.rtab.council"), "icon": "council"})
	tabs.append({"id": "laws", "name": app.t("ui.rtab.laws"), "icon": "scroll"})
	tabs.append({"id": "treasury", "name": app.t("ui.treasury"), "icon": "gold"})
	if g.engine.has_feature("politics") or g.engine.has_feature("factions"):
		var against := 0
		if g.engine.has_feature("factions"):
			against = g.state.factions.values().filter(func(f): return f.get("target") == p.id).size()
		tabs.append({"id": "politics", "name": app.t("ui.rtab.politics"), "icon": "fist", "badge": against})
	return W.tabs(app, "realm", tabs, func(tab_id: String) -> Control:
		var root := K.vbox([], 10)
		match tab_id:
			"vassals":
				root.add_child(vassal_table(app, p, vassals))
			"council":
				var council: Variant = FeatureSections.council(app, p)
				if council != null:
					root.add_child(council)
			"laws":
				root.add_child(_succession(app, p))
				var laws: Variant = FeatureSections.laws(app, p)
				if laws != null:
					root.add_child(laws)
			"treasury":
				root.add_child(TreasuryPanel.build(app, p))
			"politics":
				var politics: Variant = FeatureSections.politics(app, p)
				if politics != null:
					root.add_child(politics)
				for f in FeatureSections.factions(app, p):
					root.add_child(f)
			_:
				_realm_overview(app, p, root)
		return root)


## Обзор державы: домен, доход, наследник, титулы, двор, династия.
static func _realm_overview(app: App, p: Dictionary, root: VBoxContainer) -> void:
	var g := app.game
	var dom := Titles.domain_counties(g, p)
	var limit := Economy.domain_limit(g, p)
	var income := Economy.monthly_income(g, p)
	root.add_child(ProvincePanel._kv([
		[app.t("ui.domain"), K.label("%d / %d" % [dom.size(), limit], "BadLabel" if dom.size() > limit else "", app.t("ui.domain_tip"))],
		[app.t("ui.realm_size"), K.fmt(Titles.realm_counties(g, p).size())],
		[app.t("ui.levies"), W.stat("levies", K.fmt(Economy.realm_levy(g, p)))],
		[app.t("ui.income"), W.stat("gold", K.signed(income, 1), BB.breakdown(Economy.income_breakdown(g, p), 1), UiArt.C_GOOD if income >= 0 else UiArt.C_BAD)],
	]))
	# наследники — коротко (закон и его смена — на вкладке «Законы»)
	var heirs := Succession.heirs_of(g, p).slice(0, 5)
	var heir_row := K.flow([], 6)
	for i in heirs.size():
		var hc: Variant = g.ch(heirs[i])
		if hc == null:
			continue
		var cap := K.label("%d. %s" % [i + 1, app.t("ui.age_n", {"n": Chars.age_of(g, hc)})], "SmallLabel")
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heir_row.add_child(K.vbox([W.portrait(app, hc, 56), cap], 0))
	var law: Variant = Succession.law_of(g, p)
	var succ := [K.label(g.name_of("succession_laws", law.id) if law != null else "—", "MutedLabel")]
	succ.append(heir_row if not heirs.is_empty() else K.label(app.t("ui.no_heir"), "BadLabel"))
	root.add_child(K.section(app.t("ui.succession"), succ, "crown"))

	# титулы
	var titles: Array = p.titles.duplicate()
	Data.sort_by(titles, func(t): return Titles.TIERS.find(g.title_def(t).tier) if g.title_def(t) != null else 0, true)
	var tl := K.flow([], 8)
	for t in titles:
		var box := K.hbox([W.coa(app, t, 26), W.title_link(app, t)], 6)
		box.custom_minimum_size.x = 280
		tl.add_child(box)
	root.add_child(K.section("%s (%d)" % [app.t("ui.titles"), titles.size()], [tl], "crown"))
	var candidates := {}
	for c in Titles.realm_counties(g, p):
		var d: Variant = g.title_def(c)
		var t: Variant = d.get("liege") if d != null else null
		while t != null:
			if not p.titles.has(t):
				candidates[t] = true
			var td: Variant = g.title_def(t)
			t = td.get("liege") if td != null else null
	var cands := []
	for t in candidates:
		cands.append({"t": t, "ok": Titles.can_create_title(g, p, t).ok})
	cands.sort_custom(func(a, b): return int(a.ok) > int(b.ok))
	var rows := []
	for item in cands.slice(0, 8):
		var row := K.hbox([W.coa(app, item.t, 20), W.title_link(app, item.t)], 6)
		var act: Variant = ProvincePanel.title_actions(app, item.t)
		if act != null:
			rows.append(K.vbox([row, act], 2))
		else:
			rows.append(row)
	if not rows.is_empty():
		root.add_child(K.section(app.t("ui.claimable_titles"), rows, "crown"))

	# двор
	var court := g.courtiers_of(p.id)
	var cf := K.flow([], 6)
	for c in court:
		var cap := K.label(str(Chars.age_of(g, c)), "SmallLabel")
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cf.add_child(K.vbox([W.portrait(app, c, 48), cap], 0))
	root.add_child(K.section("%s (%d)" % [app.t("ui.court"), court.size()], [cf], "castle"))
	if p.dynasty != null and g.engine.has_feature("dynasties"):
		root.add_child(K.section(app.t("ui.dynasty"), [DynastyPanel.summary(app, p)], "dynasty"))
	elif p.dynasty != null:
		var d: Variant = g.state.dynasties.get(p.dynasty)
		var members := g.living().filter(func(x): return x.dynasty == p.dynasty)
		root.add_child(K.section(app.t("ui.dynasty"), [K.hbox([
			W.dynasty_coa(app, p.dynasty, 40),
			K.vbox([K.label(app.t("ui.dynasty_n", {"name": g.name_of("dynasties", p.dynasty)}), "SubheaderLabel"),
				K.hbox([W.stat("prestige", K.fmt(d.prestige if d != null else 0)), K.label(app.t("ui.members_n", {"n": members.size()}), "MutedLabel")], 12)], 2),
		], 10)], "dynasty"))


## Закон наследования, наследники и смена закона.
static func _succession(app: App, p: Dictionary) -> Control:
	var g := app.game
	var law: Variant = Succession.law_of(g, p)
	var heirs := Succession.heirs_of(g, p).slice(0, 5)
	var succ := K.vbox([], 4)
	var law_l := K.hbox([K.icon("scroll", 18), K.label(g.name_of("succession_laws", law.id) if law != null else "—", "SubheaderLabel")], 6)
	if law != null:
		K.tip(law_l, BB.i(g.desc_of("succession_laws", law.id)))
	succ.add_child(law_l)
	var heir_row := K.flow([], 6)
	for i in heirs.size():
		var hc: Variant = g.ch(heirs[i])
		if hc == null:
			continue
		var cap := K.label("%d. %s" % [i + 1, app.t("ui.age_n", {"n": Chars.age_of(g, hc)})], "SmallLabel")
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heir_row.add_child(K.vbox([W.portrait(app, hc, 56), cap], 0))
	if heirs.is_empty():
		succ.add_child(K.label(app.t("ui.no_heir"), "BadLabel"))
	succ.add_child(heir_row)
	var forced: bool = g.engine.has_feature("governments") and Governments.rule(g, p, "succession") != null
	if forced:
		succ.add_child(K.label(app.t("ui.law_by_government", {"gov": g.name_of("governments", Governments.of(g, p))}), "SmallLabel"))
	if not p.titles.is_empty() and not forced:
		var btns := K.flow([], 4)
		for l in g.content.all("succession_laws"):
			if (law != null and l.id == law.id) or l.get("government_only", false):
				continue
			var ctx := ScriptContext.make(g, {"type": "character", "id": p.id})
			var cc: Variant = l.get("change_cost")
			var cost := roundi(Interp.eval_value(ctx, ctx.root, cc.get("prestige", 0) if cc is Dictionary else 0))
			var reasons: Array = Interp.failed_triggers(ctx, ctx.root, l.get("can_change"))
			if cost > 0 and float(p.prestige) < cost:
				reasons.append(app.t("ui.need_prestige", {"value": cost}))
			var lid: String = l.id
			btns.add_child(K.button(g.name_of("succession_laws", l.id), func():
				p.prestige -= cost
				p.succession_law = lid
				app.toast(app.t("ui.law_changed"), "good")
				app.mark_dirty(true), {"disabled": not reasons.is_empty(),
				"tip": BB.i(g.desc_of("succession_laws", lid)) + "\n" + BB.cost(g, {"prestige": cost}) + ("\n" + BB.reasons(reasons) if not reasons.is_empty() else "")}))
		succ.add_child(K.label(app.t("ui.change_law"), "SmallLabel"))
		succ.add_child(btns)
	return K.section(app.t("ui.succession"), [succ], "crown")


## Таблица вассалов (как в CK3): портрет и титул, мнение, налог и войско,
## которые вассал даёт сюзерену; значки — влиятельный, во фракции, повинность.
static func vassal_table(app: App, liege: Dictionary, vassals: Array) -> Control:
	var g := app.game
	if vassals.is_empty():
		return K.label(app.t("ui.no_vassals"), "MutedLabel")
	var powerful := Politics.powerful_vassals(g, liege) if g.engine.has_feature("politics") else []
	var rows := []
	var total_tax := 0.0
	var total_levy := 0
	for v in vassals:
		var tax := Economy.vassal_tax_to(g, liege, v)
		var levy := Economy.vassal_levy_to(g, liege, v)
		total_tax += tax
		total_levy += levy
		rows.append({"v": v, "tax": tax, "levy": levy, "op": Opinion.opinion(g, v, liege)})
	rows.sort_custom(func(a, b): return a.levy > b.levy)
	var box := K.vbox([], 2)
	box.add_child(K.para(app.t("ui.vassals_total", {"tax": K.fmt(total_tax, 1), "levy": K.fmt(total_levy)}), "MutedLabel"))
	var head := K.hbox([K.label(app.t("ui.col.vassal"), "SmallLabel"), K.expand()], 6)
	for col in ["opinion", "tax", "levy"]:
		var l := K.label(app.t("ui.col." + col), "SmallLabel")
		l.custom_minimum_size.x = 64
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(l)
	box.add_child(K.margin(head, 8, 2, 8, 2))
	for r in rows:
		var v: Dictionary = r.v
		var badges := K.hbox([], 4)
		if powerful.has(v.id):
			badges.add_child(K.tip(K.icon("crown", 14), app.t("ui.vassal_powerful")))
		if g.engine.has_feature("factions"):
			var f: Variant = Factions.faction_of(g, v)
			if f != null:
				badges.add_child(K.tip(K.icon("fist", 14, "red"), app.t("ui.vassal_in_faction", {"name": g.name_of("factions", f.type)})))
		# повинность — значком (обычная — без значка)
		if g.engine.has_feature("politics"):
			var ob: Variant = Politics.obligation_of(g, v)
			var lvl := Data.num(ob.get("level")) if ob != null else 0.0
			if ob != null and lvl != 0.0:
				var ob_name := g.name_of("vassal_obligations", ob.id)
				badges.add_child(K.tip(K.icon("scales", 14, "red" if lvl > 0 else "green"), BB.title(ob_name) + "\n" + BB.esc(app.t("ui.obligation_tip"))))
		var t0: String = v.titles[0] if not v.titles.is_empty() else ""
		var sub := K.label(Titles.full_name(g, t0) if t0 != "" else "", "SmallLabel")
		sub.clip_text = true
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub.custom_minimum_size.x = 60
		var info := K.vbox([W.char_link(app, v.id, true), K.hbox([sub, badges], 6)], 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.custom_minimum_size.x = 120
		var row := K.hbox([W.portrait(app, v, 40, {"coa": true}), info], 8)
		var op_l := K.rich("[right]%s[/right]" % BB.signed(r.op), false)
		op_l.custom_minimum_size.x = 64
		op_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		K.tip(op_l, func(): return BB.title(app.t("ui.opinion_of_you")) + "\n" + BB.breakdown(Opinion.breakdown(g, v, liege)))
		row.add_child(op_l)
		var tax_l := W.stat("gold", K.fmt(r.tax, 1), app.t("ui.vassal_tip_tax"), UiArt.C_TEXT, 14) as HBoxContainer
		tax_l.custom_minimum_size.x = 64
		tax_l.alignment = BoxContainer.ALIGNMENT_END
		tax_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tax_l)
		var levy_l := W.stat("levies", K.fmt(r.levy), app.t("ui.vassal_tip_levy"), UiArt.C_TEXT, 14) as HBoxContainer
		levy_l.custom_minimum_size.x = 64
		levy_l.alignment = BoxContainer.ALIGNMENT_END
		levy_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(levy_l)
		box.add_child(K.panel(row, "RowPanel"))
	return box


static func log(app: App) -> Control:
	var g := app.game
	var root := K.vbox([], 2)
	var msgs: Array = g.state.messages.duplicate()
	msgs.reverse()
	for m in msgs.slice(0, 150):
		var d := GameDate.parts(m.date)
		var color := "#e9dfc6"
		match m.get("kind"):
			"good": color = BB.GOOD
			"bad": color = BB.BAD
			"war": color = BB.WARN
		var r := K.rich("%s  %s" % [BB.muted("%d.%d.%d" % [d.d, d.m, d.y]), BB.c(m.text, color)])
		var ref: Variant = m.get("ref")
		if ref is Dictionary:
			K.on_click(r, func(): app.open_ref(ref))
		root.add_child(r)
	if msgs.is_empty():
		root.add_child(K.label(app.t("ui.none"), "MutedLabel"))
	return root


## Выбор персонажа в начале партии.
static func pick(app: App) -> Control:
	var g := app.game
	var bm: Variant = g.content.get_def("bookmarks", g.state.bookmark)
	var root := K.vbox([K.para(app.t("ui.pick_text"), "MutedLabel")], 8)
	for id in Data.as_array(bm.get("playable") if bm != null else []):
		var c: Variant = g.ch(id)
		if c == null or c.death != null:
			continue
		var row := W.char_row(app, c, [Titles.full_name(g, c.titles[0]) if not c.titles.is_empty() else ""], [], 56)
		K.on_click(row, func(): app.open_character(c.id))
		root.add_child(row)
	return root

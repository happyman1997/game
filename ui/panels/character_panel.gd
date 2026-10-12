class_name CharacterPanel
extends RefCounted
## Окно персонажа (как в CK3): шапка с портретом, титулом, сюзереном, верой
## и культурой; мнение, навыки и ресурсы; вкладки «Обзор» (действия, черты,
## модификаторы, реликвии, правление, образ жизни, тайны, летопись, разделы
## модов), «Семья и связи» (родные, друзья и соперники, династия) и
## «Владения» (держава, титулы, претензии, вассалы).


static func fmt_date(app: App, n: int) -> String:
	var d := GameDate.parts(n)
	return "%d %s %d" % [d.d, app.t("month.%d" % d.m), d.y]


static func build(app: App, id: String) -> Control:
	var g := app.game
	var c: Variant = g.ch(id)
	if c == null:
		return K.label(app.t("ui.unknown_character"), "MutedLabel")
	var p: Variant = g.player
	var is_me: bool = p != null and p.id == c.id
	var alive: bool = c.death == null
	var root := K.vbox([], 10)

	root.add_child(_header(app, c))
	if app.pick_mode and alive and not c.titles.is_empty():
		root.add_child(K.button(app.t("ui.play_as"), func(): app.set_player(c.id), {"variation": "GoldButton", "min_h": 42}))

	# ---------------------------------------------------- мнение
	if p != null and not is_me and alive:
		var theirs := Opinion.opinion(g, c, p)
		var mine := Opinion.opinion(g, p, c)
		var op1 := K.rich("%s: %s" % [BB.esc(app.t("ui.opinion_of_you")), BB.signed(theirs)], false)
		K.tip(op1, func(): return BB.title(app.t("ui.opinion_of_you")) + "\n" + BB.breakdown(Opinion.breakdown(g, c, p)))
		var op2 := K.rich("%s: %s" % [BB.esc(app.t("ui.your_opinion")), BB.signed(mine)], false)
		K.tip(op2, func(): return BB.title(app.t("ui.your_opinion")) + "\n" + BB.breakdown(Opinion.breakdown(g, p, c)))
		root.add_child(K.panel(K.hbox([op1, K.expand(), op2], 12), "InsetPanel"))

	# ---------------------------------------------------- навыки и ресурсы
	var stats := Stats.char_stats(g, c)
	var res := K.hbox([
		W.stat("gold", K.fmt(c.gold), BB.title(app.t("ui.gold"))),
		W.stat("prestige", K.fmt(c.prestige), func(): return BB.title(app.t("ui.prestige")) + ("\n" + BB.esc(Renown.describe(g, c, "prestige")) if g.engine.has_feature("renown") else "")),
		W.stat("piety", K.fmt(c.piety), func(): return BB.title(app.t("ui.piety")) + ("\n" + BB.esc(Renown.describe(g, c, "piety")) if g.engine.has_feature("renown") else "")),
		W.stat("heart", K.fmt(float(stats.get("health", 0.0)), 1), func(): return BB.title(app.t("ui.health")) + "\n" + BB.breakdown(Stats.stat_breakdown(g, c, "health"), 1)),
		W.stat("stress", K.fmt(c.stress), func(): return W.stress_tip(app, c), UiArt.C_BAD if float(c.stress) >= 100 else UiArt.C_TEXT),
	], 14)
	var skill_box := K.vbox([W.skills(app, c), res], 6)
	# полоса стресса: каждые 100 очков — новый уровень
	if alive and float(c.stress) > 0:
		var lvl := floori(float(c.stress) / 100.0)
		var sb := K.bar(fmod(float(c.stress), 100.0), 100, Color("#a04a6a") if lvl == 0 else Color("#c03a3a"), 16,
			app.t("ui.stress_level", {"n": K.fmt(c.stress)}) + ("  ·  ×%d" % lvl if lvl > 0 else ""))
		K.tip(sb, func(): return W.stress_tip(app, c))
		skill_box.add_child(sb)
	root.add_child(K.panel(skill_box, "InsetPanel"))

	# ---------------------------------------------------- вкладки
	var tabs := [{"id": "overview", "name": app.t("ui.ctab.overview"), "icon": "person"}]
	tabs.append({"id": "family", "name": app.t("ui.ctab.family"), "icon": "dynasty"})
	if not c.titles.is_empty() or not c.claims.is_empty():
		tabs.append({"id": "realm", "name": app.t("ui.ctab.realm"), "icon": "crown", "badge": c.titles.size()})
	root.add_child(W.tabs(app, "character", tabs, func(tab_id: String) -> Control:
		match tab_id:
			"family": return _family_tab(app, c)
			"realm": return _realm_tab(app, c)
		return _overview_tab(app, c)))
	return root


## Шапка: портрет, имя, титул, сюзерен, возраст, вера и культура, династия, герб.
static func _header(app: App, c: Dictionary) -> Control:
	var g := app.game
	var alive: bool = c.death == null
	var age := Chars.age_of(g, c)
	var info := K.vbox([], 3)
	var name := K.label(Chars.full_name(g, c, true), "HeaderLabel")
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.custom_minimum_size.x = 220
	info.add_child(name)
	if not c.titles.is_empty():
		info.add_child(W.title_link(app, c.titles[0]))
		if c.liege != null:
			info.add_child(K.rich(BB.muted(app.t("ui.vassal_of")) + BB.char_link(g, c.liege, true), false))
		else:
			info.add_child(K.label(app.t("ui.independent_ruler"), "GoldLabel"))
	elif c.liege != null:
		info.add_child(K.rich(BB.muted(app.t("ui.courtier_of", {"who": ""})) + BB.char_link(g, c.liege, true), false))
	else:
		info.add_child(K.label(app.t("ui.wanderer"), "MutedLabel"))
	var line := (app.t("ui.age_n", {"n": age}) + "  " + BB.muted("(" + app.t("ui.born_on", {"date": fmt_date(app, c.birth)}) + ")")) if alive else app.t("ui.died", {
		"date": fmt_date(app, c.death), "age": age, "reason": app.t("ui.death_reason." + str(c.get("death_reason") if c.get("death_reason") != null else "natural"))})
	info.add_child(K.rich(line if alive else BB.muted(line), false))
	# вера и культура — с подсказками
	var fdef: Variant = g.content.get_def("faiths", c.faith)
	var faith_l := K.hbox([K.icon(fdef.get("icon", "piety") if fdef != null else "piety", 16), K.label(g.name_of("faiths", c.faith))], 4)
	K.tip(faith_l, func():
		var bb := BB.title(g.name_of("faiths", c.faith))
		var d := g.desc_of("faiths", c.faith)
		if d != "":
			bb += "\n" + BB.i(d)
		if fdef != null and not Data.as_array(fdef.get("virtues")).is_empty():
			bb += "\n" + BB.good("+ ") + ", ".join(Data.as_array(fdef.virtues).map(func(x): return g.name_of("traits", x)))
		if fdef != null and not Data.as_array(fdef.get("sins")).is_empty():
			bb += "\n" + BB.bad("− ") + ", ".join(Data.as_array(fdef.sins).map(func(x): return g.name_of("traits", x)))
		return bb)
	var cdef: Variant = g.content.get_def("cultures", c.culture)
	var cul_l := K.hbox([K.icon("speech", 16), K.label(g.name_of("cultures", c.culture))], 4)
	K.tip(cul_l, func():
		var bb := BB.title(g.name_of("cultures", c.culture))
		if cdef != null and cdef.get("modifiers") is Dictionary:
			bb += "\n" + BB.modifiers(g, cdef.modifiers)
		return bb)
	info.add_child(K.hbox([faith_l, K.label("·", "MutedLabel"), cul_l], 6))
	if c.dynasty != null:
		var d: Variant = g.state.dynasties.get(c.dynasty)
		var dl := K.hbox([W.dynasty_coa(app, c.dynasty, 20), K.label(app.t("ui.dynasty_n", {"name": g.name_of("dynasties", c.dynasty)}))], 6)
		K.tip(dl, app.t("ui.dynasty_prestige", {"n": K.fmt(d.prestige if d != null else 0)}))
		info.add_child(dl)
	else:
		info.add_child(K.label(app.t("ui.lowborn"), "MutedLabel"))
	var badge: Variant = FeatureSections.council_badge(app, c)
	if badge != null:
		info.add_child(badge)
	if c.get("prison") != null:
		info.add_child(K.rich(BB.icon("chain") + " " + BB.bad(app.t("ui.in_prison_of", {"jailer": ""})) + BB.char_link(g, c.prison.by, true)))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := K.hbox([W.portrait(app, c, 140, {"clickable": false}), info], 12)
	var right := K.vbox([], 6)
	if not c.titles.is_empty():
		right.add_child(W.coa(app, c.titles[0], 64))
	# закрепить в обзоре справа
	if g.player != null and c.id != g.player.id:
		var pinned := app.is_pinned(c.id)
		var cid: String = c.id
		right.add_child(K.round_button("star", func(): app.toggle_pin(cid), app.t("ui.unpin" if pinned else "ui.pin"), 34, pinned))
	head.add_child(right)
	return head


## Вкладка «Обзор»: черты, модификаторы, реликвии, правление, образ жизни,
## тайны, действия, летопись и разделы модов.
static func _overview_tab(app: App, c: Dictionary) -> Control:
	var g := app.game
	var p: Variant = g.player
	var is_me: bool = p != null and p.id == c.id
	var alive: bool = c.death == null
	var root := K.vbox([], 10)

	# действия — первыми: ради них окно и открывают
	if p != null and alive and not app.pick_mode and g.state.game_over == null:
		var acts := K.flow([], 6)
		for def in Interactions.defs(g):
			if not Interactions.is_shown(g, def, p, c):
				continue
			acts.add_child(_interaction_button(app, def, p.id, c.id))
		if not is_me and not c.titles.is_empty():
			var top := Titles.top_liege(g, c)
			var targets := Wars.available_war_targets(g, p).filter(func(tt): return tt.defender == c.id or tt.defender == top.id)
			if not targets.is_empty():
				var def_id: String = targets[0].defender
				acts.add_child(K.button(app.t("ui.declare_war"), func(): WarsPanel.open_declare_war(app, def_id), {"icon": "swords", "variation": "GoldButton"}))
		if acts.get_child_count() > 0:
			root.add_child(K.section(app.t("ui.self_actions" if is_me else "ui.interactions"), [acts], "scroll"))

	var tf := W.traits(app, c)
	if tf.get_child_count() > 0:
		root.add_child(tf)
	var shown_mods: Array = c.modifiers.filter(func(m): return Chars.modifier_visible(g, c, m.id, g.state.player))
	if not shown_mods.is_empty():
		var mods := K.flow([], 4)
		for m in shown_mods:
			var def: Variant = g.content.get_def("modifiers", m.id)
			var left: Variant = null
			if m.get("expires") != null:
				left = maxi(0, roundi((m.expires - g.date) / 30.0))
			var good: bool = def != null and def.get("good", false)
			var chip := K.panel(K.hbox([K.icon(def.get("icon", "star") if def != null else "star", 16), K.label(g.name_of("modifiers", m.id), "SmallLabel")], 3))
			chip.add_theme_stylebox_override("panel", UiArt.flat(Color("#2e4230") if good else Color("#4a2a2a"), Color(UiArt.BRONZE, 0.6), 1, 3, 3))
			var tipbb := BB.title(g.name_of("modifiers", m.id))
			if left != null:
				tipbb += "\n" + BB.muted(app.t("ui.months_left", {"n": left}))
			var mbb := BB.modifiers(g, def.get("modifiers") if def != null else null)
			if mbb != "":
				tipbb += "\n" + mbb
			K.tip(chip, tipbb)
			mods.add_child(chip)
		root.add_child(mods)

	# реликвии: венец, меч, печать…
	var arts: Variant = FeatureSections.artifacts(app, c)
	if arts != null:
		root.add_child(arts)
	# правление (не феодальное): выборы, обеты, члены
	var gov: Variant = FeatureSections.government(app, c)
	if gov != null:
		root.add_child(K.section(app.t("ui.government"), [gov], "scales"))
	var ls: Variant = LifestylePanel.summary(app, c)
	if ls != null:
		root.add_child(K.section(app.t("ui.lifestyle"), [ls], "leaf"))
	var secrets: Variant = FeatureSections.secrets_character(app, c)
	if secrets != null:
		root.add_child(secrets)
	var chron: Variant = W.deeds(app, c)
	if chron != null:
		root.add_child(chron)

	# разделы модов
	var secs: Array = g.engine.ui.character_sections.values()
	Data.sort_by(secs, func(s): return Data.num(s.get("order")))
	for s in secs:
		var r: Variant = s.render.call(g, c.id, app)
		if r is String and r != "":
			root.add_child(K.section(g.loc.resolve(s.get("title", s.id)), [K.rich(r)]))
		elif r is Control:
			root.add_child(K.section(g.loc.resolve(s.get("title", s.id)), [r]))
	return root


## Вкладка «Семья и связи»: родные портретами, друзья и соперники, династия.
static func _family_tab(app: App, c: Dictionary) -> Control:
	var g := app.game
	var alive: bool = c.death == null
	var root := K.vbox([], 10)
	var fam := K.flow([], 8)
	var add_people := func(label: String, ids: Array) -> void:
		for x in ids:
			var cc: Variant = g.ch(x)
			if cc == null:
				continue
			var cap := K.label(label, "SmallLabel")
			cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var box := K.vbox([W.portrait(app, cc, 64), cap], 0)
			box.custom_minimum_size.x = 72
			fam.add_child(box)
	if c.liege != null:
		add_people.call(app.t("ui.liege" if not c.titles.is_empty() else "ui.court"), [c.liege])
	if not c.titles.is_empty() and alive:
		var heirs := Succession.heirs_of(g, c)
		if not heirs.is_empty():
			add_people.call(app.t("ui.heir"), [heirs[0]])
	add_people.call(app.t("ui.spouse"), c.spouses)
	var parents := []
	for x in [c.father, c.mother]:
		if x != null:
			parents.append(x)
	add_people.call(app.t("ui.parent"), parents)
	add_people.call(app.t("ui.child"), c.children)
	var sibs := Chars.siblings_of(g, c).map(func(s): return s.id)
	add_people.call(app.t("ui.sibling"), sibs.slice(0, 8))
	add_people.call(app.t("ui.former_spouse"), c.former_spouses)
	var fam_children := [fam]
	if not c.titles.is_empty() and alive and Succession.heirs_of(g, c).is_empty():
		fam_children.append(K.label(app.t("ui.no_heir"), "BadLabel"))
	if c.get("pregnancy") != null:
		fam_children.append(K.label("%s: %s" % [app.t("ui.pregnant"), app.t("ui.due", {"date": fmt_date(app, c.pregnancy.due)})], "MutedLabel"))
	root.add_child(K.section(app.t("ui.family"), fam_children, "dynasty"))

	# связи: друзья, соперники, возлюбленные, вражда
	var rel_rows := []
	for tid in c.opinions:
		var other: Variant = g.ch(tid)
		if other == null or other.death != null:
			continue
		for e in c.opinions[tid]:
			var kind := ""
			if e.mod in ["friend", "rival", "lover"]:
				kind = e.mod
			else:
				var od: Variant = g.content.get_def("opinion_modifiers", e.mod)
				if od != null and od.get("feud", false):
					kind = "feud"
			if kind == "":
				continue
			var label := app.t("ui.rel." + ("lover_m" if kind == "lover" and not other.female else kind))
			var op := Opinion.opinion(g, c, other)
			var lab := K.label(label, "GoodLabel" if kind in ["friend", "lover"] else "BadLabel")
			rel_rows.append(W.char_row(app, other, [lab], [K.rich(BB.signed(op), false)], 40))
			break
	if rel_rows.is_empty():
		rel_rows.append(K.label(app.t("ui.no_relations"), "MutedLabel"))
	root.add_child(K.section(app.t("ui.relations"), rel_rows, "heart"))

	# династия
	if c.dynasty != null:
		var d: Variant = g.state.dynasties.get(c.dynasty)
		var members := g.living().filter(func(x): return x.dynasty == c.dynasty)
		var rulers := members.filter(func(x): return not x.titles.is_empty())
		Data.sort_by(rulers, func(x): return Titles.primary_tier(g, x), true)
		var dyn := K.vbox([K.hbox([
			W.dynasty_coa(app, c.dynasty, 44),
			K.vbox([K.label(app.t("ui.dynasty_n", {"name": g.name_of("dynasties", c.dynasty)}), "SubheaderLabel"),
				K.hbox([W.stat("prestige", K.fmt(d.prestige if d != null else 0), BB.title(app.t("ui.dynasty_prestige", {"n": K.fmt(d.prestige if d != null else 0)}))),
					K.label(app.t("ui.dynasty_members_n", {"n": members.size()}), "MutedLabel")], 12)], 2),
		], 10)], 6)
		var rf := K.flow([], 6)
		for r in rulers.slice(0, 10):
			rf.add_child(W.portrait(app, r, 48, {"coa": true}))
		if rf.get_child_count() > 0:
			dyn.add_child(rf)
		root.add_child(K.section(app.t("ui.dynasty"), [dyn], "dynasty"))
	return root


## Вкладка «Владения»: держава, титулы, претензии, вассалы.
static func _realm_tab(app: App, c: Dictionary) -> Control:
	var g := app.game
	var root := K.vbox([], 10)
	if not c.titles.is_empty():
		var dom := Titles.domain_counties(g, c)
		var limit := Economy.domain_limit(g, c)
		root.add_child(ProvincePanel._kv([
			[app.t("ui.domain"), K.label("%d / %d" % [dom.size(), limit], "BadLabel" if dom.size() > limit else "", app.t("ui.domain_tip"))],
			[app.t("ui.realm_size"), K.fmt(Titles.realm_counties(g, c).size())],
			[app.t("ui.levies"), W.stat("levies", K.fmt(Economy.realm_levy(g, c)))],
			[app.t("ui.income"), W.stat("gold", K.signed(Economy.monthly_income(g, c), 1), BB.breakdown(Economy.income_breakdown(g, c), 1))],
		]))
		# титулы — от высших к графствам
		var titles: Array = c.titles.duplicate()
		Data.sort_by(titles, func(t): return Titles.TIERS.find(g.title_def(t).tier) if g.title_def(t) != null else 0, true)
		var tl := K.flow([], 8)
		for tt in titles:
			var box := K.hbox([W.coa(app, tt, 28), W.title_link(app, tt)], 6)
			box.custom_minimum_size.x = 280
			tl.add_child(box)
		root.add_child(K.section("%s (%d)" % [app.t("ui.titles"), titles.size()], [tl], "crown"))
	if not c.claims.is_empty():
		var cl := K.vbox([], 2)
		for tt in c.claims:
			var row := K.hbox([W.coa(app, tt, 22), W.title_link(app, tt)], 6)
			var holder: Variant = g.state.titles.get(tt)
			if holder != null and holder.holder != null:
				row.add_child(K.rich(BB.muted("(") + BB.char_link(g, holder.holder) + BB.muted(")"), false))
			cl.add_child(row)
		root.add_child(K.section(app.t("ui.claims"), [cl], "scroll"))
	var vassals := g.vassals_of(c.id)
	if not vassals.is_empty():
		root.add_child(K.section("%s (%d)" % [app.t("ui.vassals"), vassals.size()], [TabPanels.vassal_table(app, c, vassals)], "shield"))
	return root


static func _interaction_button(app: App, def: Dictionary, actor_id: String, recipient_id: String) -> Control:
	var g := app.game
	var actor: Dictionary = g.ch(actor_id)
	var recipient: Dictionary = g.ch(recipient_id)
	var needs_choice: bool = def.get("secondary_actor") != null or def.get("target") != null
	var blockers := Interactions.blockers(g, def, actor, recipient)
	return K.button(g.name_of("interactions", def.id), func(): InteractionWindow.open(app, def, actor_id, recipient_id), {
		"icon": def.get("icon", "scroll"),
		"disabled": not blockers.is_empty(),
		"tip": func():
			var bb := BB.title(g.name_of("interactions", def.id))
			var desc := g.desc_of("interactions", def.id)
			if desc != "":
				bb += "\n" + BB.i(desc)
			if not blockers.is_empty():
				bb += "\n" + BB.reasons(blockers)
			elif not needs_choice:
				var acc := Interactions.acceptance(g, def, actor, recipient)
				if not acc.get("auto", false):
					var ok: bool = float(acc.total) > 0
					bb += "\n" + BB.c("%s (%s)" % [app.t("ui.will_accept" if ok else "ui.will_decline"), K.signed(acc.total)], BB.GOOD if ok else BB.BAD)
			else:
				var n := Interactions.secondary_candidates(g, def, actor, recipient).size() if def.get("secondary_actor") != null else Interactions.target_options(g, def, actor, recipient).size()
				bb += "\n" + BB.muted(app.t("ui.options_n", {"n": n}))
			return bb,
	})

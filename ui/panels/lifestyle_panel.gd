class_name LifestylePanel
extends RefCounted
## Вкладка «Образ жизни»: образы жизни, фокусы, опыт и деревья перков
## (столбцы круглых значков, как в CK3).


static func build(app: App) -> Control:
	var g := app.game
	var p: Dictionary = g.player
	var root := K.vbox([], 10)
	var all := Lifestyles.all(g)
	if all.is_empty():
		return root
	var cur: Variant = Lifestyles.current(g, p)
	var view_id: String = app.lifestyle_view
	if not all.any(func(l): return l.id == view_id):
		view_id = cur.id if cur != null else all[0].id

	var tabs := K.hbox([], 6, BoxContainer.ALIGNMENT_CENTER)
	for l in all:
		var lid: String = l.id
		var b := K.round_button(l.get("icon", "leaf"), func():
			app.lifestyle_view = lid
			app.mark_dirty(true), BB.title(g.name_of("lifestyles", l.id)) + "\n" + BB.esc(app.t("ui.lifestyle_skill", {"skill": g.name_of("skills", l.get("skill"))})), 52, l.id == view_id)
		if cur != null and l.id == cur.id:
			b.self_modulate = Color(1.0, 0.95, 0.75)
		tabs.add_child(b)
	root.add_child(tabs)

	var view: Dictionary = all.filter(func(l): return l.id == view_id)[0]
	var xp := floori(Lifestyles.xp_of(p, view.id))
	var cost := Lifestyles.perk_cost(g, p, view.id)
	var trees := Lifestyles.trees_of(g, view.id)
	var all_done := trees.all(func(t): return t.perks.all(func(x): return Lifestyles.has_perk(p, x.id)))
	var head := K.vbox([K.label(g.name_of("lifestyles", view.id), "HeaderLabel")], 4)
	head.get_child(0).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if all_done:
		head.add_child(K.label(app.t("ui.lifestyle_all_done"), "GoodLabel"))
	else:
		head.add_child(K.label(app.t("ui.lifestyle_xp", {"xp": K.fmt(xp), "cost": K.fmt(cost)})))
		head.add_child(K.bar(xp, cost, Color(view.get("color", "#b8913f")), 10))
	if cur != null and view.id == cur.id:
		head.add_child(K.label(app.t("ui.lifestyle_xp_month", {"n": K.fmt(Lifestyles.monthly_xp(g, p), 1)}), "MutedLabel"))
	root.add_child(K.panel(head, "InsetPanel"))

	# фокусы
	var block := Lifestyles.focus_change_blocked_until(g, p)
	var focus_row := K.hbox([], 10, BoxContainer.ALIGNMENT_CENTER)
	var st := Lifestyles.state_of(p)
	for f in Lifestyles.focuses_of(g, view.id):
		if not Lifestyles.is_focus_shown(g, p, f.id):
			continue
		var active: bool = st.focus == f.id
		var fid: String = f.id
		var b := K.round_button(f.get("icon", "star"), func():
			if active or block > 0:
				return
			Lifestyles.set_focus(g, p, fid)
			app.mark_dirty(true), func():
			var bb := BB.title(g.name_of("focuses", fid)) + "\n" + BB.i(g.desc_of("focuses", fid)) + "\n" + BB.modifiers(g, f.get("modifiers"))
			if not active and block > 0:
				bb += "\n" + BB.bad(app.t("ui.focus_cooldown", {"days": block - g.date}))
			return bb, 56, active)
		var cap := K.label(g.name_of("focuses", f.id), "SmallLabel" if not active else "GoldLabel")
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cap.custom_minimum_size.x = 100
		focus_row.add_child(K.vbox([K.center(b), cap], 2))
	root.add_child(K.section(app.t("ui.focus"), [focus_row], "star"))

	# деревья перков
	var trees_row := K.hbox([], 4, BoxContainer.ALIGNMENT_CENTER)
	for t in trees:
		var col := K.vbox([], 0)
		col.custom_minimum_size.x = 140
		var tname := K.label(g.loc.t_or("perk_tree." + t.tree, t.tree), "SubheaderLabel")
		tname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(tname)
		for i in t.perks.size():
			if i > 0:
				var link := ColorRect.new()
				var prev_owned := Lifestyles.has_perk(p, t.perks[i - 1].id)
				link.color = Color(UiArt.GOLD, 0.8) if prev_owned else Color(UiArt.BRONZE, 0.4)
				link.custom_minimum_size = Vector2(3, 16)
				link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				col.add_child(link)
			col.add_child(_perk_node(app, p, t.perks[i], xp, cost))
		trees_row.add_child(col)
	root.add_child(trees_row)
	return root


static func _perk_node(app: App, p: Dictionary, perk: Dictionary, xp: int, cost: int) -> Control:
	var g := app.game
	var owned := Lifestyles.has_perk(p, perk.id)
	var req_ok := Lifestyles.requirements_met(g, p, perk)
	var can := Lifestyles.can_unlock(g, p, perk.id)
	var pid: String = perk.id
	var b := K.round_button(perk.get("icon", "star"), func():
		if not can:
			return
		Lifestyles.unlock_perk(g, p, pid)
		app.mark_dirty(true), func(): return perk_tip(app, p, perk, owned, req_ok, xp, cost), 50, owned)
	if not owned and not can:
		b.modulate = Color(0.55, 0.55, 0.55) if not req_ok else Color(0.8, 0.8, 0.8)
	elif can:
		b.self_modulate = Color(0.85, 1.0, 0.75)
	var cap := K.label(g.name_of("perks", perk.id), "GoldLabel" if owned else "SmallLabel")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.custom_minimum_size.x = 130
	cap.add_theme_font_size_override("font_size", 12)
	return K.vbox([K.center(b), cap], 0)


static func perk_tip(app: App, p: Dictionary, perk: Dictionary, owned: bool, req_ok: bool, xp: int, cost: int) -> String:
	var g := app.game
	var bb := BB.title(g.name_of("perks", perk.id))
	var desc := g.desc_of("perks", perk.id)
	if desc != "":
		bb += "\n" + BB.i(desc)
	var mods := BB.modifiers(g, perk.get("modifiers"))
	if mods != "":
		bb += "\n" + mods
	if perk.get("trait") != null:
		bb += "\n" + BB.good(app.t("ui.perk_grants_trait", {"trait": g.name_of("traits", perk.trait)}))
		var td: Variant = g.content.get_def("traits", perk.trait)
		if td != null:
			bb += "\n" + BB.modifiers(g, td.get("modifiers"))
	if perk.get("effect") != null:
		var ctx := ScriptContext.make(g, {"type": "character", "id": p.id})
		bb += "\n" + BB.desc_lines(Interp.describe_effect(ctx, ctx.root, perk.effect))
	if owned:
		bb += "\n" + BB.good("✔ " + app.t("ui.perk_owned"))
	elif not req_ok:
		bb += "\n" + BB.bad("✗ " + app.t("ui.perk_locked"))
	elif xp < cost:
		bb += "\n" + BB.bad("✗ " + app.t("ui.perk_need_xp", {"cost": K.fmt(cost), "xp": K.fmt(xp)}))
	else:
		bb += "\n" + BB.good(app.t("ui.perk_unlock"))
	return bb


## Компактный блок для окна любого персонажа: фокус и открытые перки.
static func summary(app: App, c: Dictionary) -> Variant:
	var g := app.game
	var st: Variant = c.get("lifestyle")
	if st == null or (st.focus == null and st.perks.is_empty()):
		return null
	var row := K.flow([], 4)
	if st.focus != null:
		var f: Variant = g.content.get_def("focuses", st.focus)
		if f != null:
			var chip := K.panel(K.hbox([K.icon(f.get("icon", "star"), 18), K.label(g.name_of("focuses", f.id))], 4), "InsetPanel")
			K.tip(chip, BB.title(app.t("ui.focus_n", {"name": g.name_of("focuses", f.id)})) + "\n" + BB.modifiers(g, f.get("modifiers")))
			row.add_child(chip)
	for id in st.perks:
		var perk: Variant = g.content.get_def("perks", id)
		if perk == null:
			continue
		var ic := K.icon(perk.get("icon", "star"), 26)
		K.tip(ic, func(): return perk_tip(app, c, perk, true, true, 0, 0))
		row.add_child(ic)
	return row

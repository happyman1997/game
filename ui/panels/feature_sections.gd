class_name FeatureSections
extends RefCounted
## Разделы окон для механик движка: совет, законы державы, фракции,
## профессиональные войска, тайны и крюки, рыцари.


# ------------------------------------------------------------ политика двора

## Страх и влиятельные вассалы правителя (механика politics).
static func politics(app: App, liege: Dictionary) -> Variant:
	var g := app.game
	if not g.engine.has_feature("politics") or liege.titles.is_empty():
		return null
	var box := K.vbox([], 6)
	var d := Politics.dread(liege)
	if d >= 1.0:
		var row := K.hbox([K.icon("chain", 20), K.label(app.t("ui.dread"), "SubheaderLabel")], 6)
		K.tip(row, BB.title(app.t("ui.dread")) + "\n" + BB.esc(app.t("ui.dread_tip")))
		box.add_child(row)
		box.add_child(K.bar(d, g.def_num("politics.dread_max", 100), Color("#8a2a2a"), 8, str(roundi(d))))
	var pw := Politics.powerful_vassals(g, liege)
	var head := K.hbox([K.icon("crown", 20), K.label(app.t("ui.powerful_vassals"), "SubheaderLabel")], 6)
	K.tip(head, BB.title(app.t("ui.powerful_vassals")) + "\n" + BB.esc(app.t("ui.powerful_tip")))
	box.add_child(head)
	if pw.is_empty():
		box.add_child(K.label(app.t("ui.no_powerful"), "MutedLabel"))
	for id in pw:
		var v: Variant = g.ch(id)
		if v == null:
			continue
		var seated := Politics.is_seated(g, liege, v)
		var status := K.label(app.t("ui.in_council") if seated else app.t("ui.not_in_council"), "GoodLabel" if seated else "BadLabel")
		box.add_child(W.char_row(app, v, [status], [K.rich(BB.signed(Opinion.opinion(g, v, liege)), false)], 40))
	if d < 1.0 and pw.is_empty():
		return null
	return K.section(app.t("ui.politics"), [box], "council")


## Подпись условий службы вассала (для строк списка вассалов).
static func obligation_chip(app: App, v: Dictionary) -> Variant:
	var g := app.game
	if not g.engine.has_feature("politics") or v.liege == null:
		return null
	var ob: Variant = Politics.obligation_of(g, v)
	if ob == null:
		return null
	var text := g.name_of("vassal_obligations", ob.id)
	if Politics.is_powerful(g, v):
		text = app.t("tr.is_powerful_vassal") + " · " + text
	var l := K.label(text, "SmallLabel")
	var lvl := Data.num(ob.get("level"))
	if lvl > 0:
		l.add_theme_color_override("font_color", UiArt.C_BAD)
	elif lvl < 0:
		l.add_theme_color_override("font_color", UiArt.C_GOOD)
	K.tip(l, BB.title(app.t("ui.obligation")) + "\n" + BB.esc(app.t("ui.obligation_tip")))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


# ------------------------------------------------------------ совет

static func council(app: App, liege: Dictionary) -> Variant:
	var g := app.game
	if not g.engine.has_feature("council"):
		return null
	var positions := Council.positions(g).filter(func(p): return Council.is_position_shown(g, liege, p))
	if positions.is_empty():
		return null
	var mine := g.is_player(liege.id)
	var list := K.vbox([], 6)
	for pos in positions:
		var seat: Variant = Council.seat_of(liege, pos.id)
		var holder: Variant = g.ch(seat.get("holder")) if seat != null else null
		var sdef: Variant = g.content.get_def("skills", pos.get("skill"))
		var title := K.hbox([K.icon(pos.get("icon", "council"), 20), K.label(g.name_of("council_positions", pos.id), "SubheaderLabel")], 6)
		K.tip(title, BB.title(g.name_of("council_positions", pos.id)) + "\n" + BB.i(g.desc_of("council_positions", pos.id)))
		var who: Control
		if holder != null:
			who = K.hbox([W.portrait(app, holder, 40), K.vbox([W.char_link(app, holder.id),
				W.stat(sdef.get("icon", "star") if sdef != null else "star", str(Stats.skill(g, holder, pos.skill)), null, UiArt.C_TEXT, 16)], 0)], 6)
		else:
			who = K.label(app.t("ui.vacant"), "MutedLabel")
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := K.hbox([who], 6)
		if mine:
			var pid: String = pos.id
			row.add_child(K.button(app.t("ui.replace" if holder != null else "ui.appoint"), func(): _pick_councillor(app, liege, pid)))
			if holder != null:
				row.add_child(K.button("", func():
					Council.dismiss(g, liege, pid)
					app.mark_dirty(true), {"icon": "close", "tip": app.t("ui.dismiss")}))
		var tasks := K.flow([], 4)
		for t in Council.tasks_of(g, pos.id):
			var active: bool = seat != null and seat.get("task") == t.id
			var tid: String = t.id
			var pid2: String = pos.id
			tasks.add_child(K.button(g.name_of("council_tasks", t.id), func():
				if not mine or active:
					return
				Council.set_task(g, liege, pid2, tid)
				app.mark_dirty(true), {"icon": t.get("icon", "scroll"), "toggled": active, "disabled": not mine and not active,
				"tip": func(): return _task_tip(app, liege, pid2, t, holder)}))
		list.add_child(K.panel(K.vbox([title, row, tasks], 4), "InsetPanel"))
	return K.section(app.t("ui.council"), [K.para(app.t("ui.council_hint"), "SmallLabel"), list], "council")


static func _task_tip(app: App, liege: Dictionary, pos_id: String, t: Dictionary, holder: Variant) -> String:
	var g := app.game
	var bb := BB.title(g.name_of("council_tasks", t.id)) + "\n" + BB.i(g.desc_of("council_tasks", t.id))
	if holder != null:
		var ctx := ScriptContext.make(g, {"type": "character", "id": holder.id}, {"liege": {"type": "character", "id": liege.id}, "councillor": {"type": "character", "id": holder.id}})
		bb += "\n" + BB.modifiers(g, EngineFeature.eval_modifiers(ctx, ctx.root, t.get("liege_modifiers")))
		if t.get("monthly_effect") != null:
			var seat: Variant = Council.seat_of(liege, pos_id)
			if seat != null and seat.get("task") == t.id:
				bb += "\n" + BB.muted(app.t("ui.task_monthly_chance", {"n": snappedf(Council.task_monthly_chance(g, liege, pos_id), 0.1)}))
			bb += "\n" + BB.desc_lines(Interp.describe_effect(ctx, ctx.root, t.monthly_effect))
	return bb


static func _pick_councillor(app: App, liege: Dictionary, pos_id: String) -> void:
	var g := app.game
	var pos: Dictionary = g.content.get_def("council_positions", pos_id)
	var seat: Variant = Council.seat_of(liege, pos_id)
	var cur: Variant = seat.get("holder") if seat != null else null
	var cands := Council.candidates(g, liege, pos_id).filter(func(c): return c.id != cur)
	var sdef: Variant = g.content.get_def("skills", pos.get("skill"))
	Data.sort_by(cands, func(c): return -Stats.skill(g, c, pos.skill))
	var close_ref := [Callable()]
	var list := K.vbox([], 3)
	for c in cands:
		var other: Variant = Council.position_of(g, c)
		var cid: String = c.id
		var op := Opinion.opinion(g, c, liege)
		var info := K.vbox([K.label(Chars.full_name(g, c, true)), K.label(app.t("ui.age_n", {"n": Chars.age_of(g, c)}) + (" · " + g.name_of("council_positions", other.position) if other != null else ""), "SmallLabel")], 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var inner := K.hbox([W.portrait(app, c, 40, {"clickable": false}), info,
			W.stat(sdef.get("icon", "star") if sdef != null else "star", str(Stats.skill(g, c, pos.skill))),
			K.rich(BB.signed(op), false)], 8)
		var btn := K.button("", func():
			Council.appoint(g, liege, pos_id, cid)
			close_ref[0].call()
			app.mark_dirty(true), {"variation": "FlatButton", "min_h": 54})
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for ch in inner.get_children():
			ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(inner)
		list.add_child(btn)
	if cands.is_empty():
		list.add_child(K.para(app.t("ui.no_council_candidates"), "MutedLabel"))
	var sc := K.scroll(list)
	sc.custom_minimum_size = Vector2(520, mini(440, 58 * maxi(1, cands.size())))
	var body := K.vbox([
		K.header(app.t("ui.choose_councillor", {"position": g.name_of("council_positions", pos_id)})), sc,
		K.hbox([K.expand(), K.button(app.t("ui.cancel"), func(): close_ref[0].call(), {"min_w": 120})]),
	], 10)
	close_ref[0] = app.modal(K.panel(body))


## «Маршал при дворе …» для окна персонажа.
static func council_badge(app: App, c: Dictionary) -> Variant:
	var g := app.game
	if not g.engine.has_feature("council"):
		return null
	var pos: Variant = Council.position_of(g, c)
	if pos == null:
		return null
	var def: Variant = g.content.get_def("council_positions", pos.position)
	return K.rich("%s %s%s" % [BB.icon(def.get("icon", "council") if def != null else "council"), BB.esc(app.t("ui.councillor_of", {"position": g.name_of("council_positions", pos.position), "liege": ""})), BB.char_link(g, pos.liege.id, true)])


# ------------------------------------------------------------ законы

static func laws(app: App, p: Dictionary) -> Variant:
	var g := app.game
	if not g.engine.has_feature("laws"):
		return null
	var groups := Laws.groups(g).filter(func(gd): return Laws.is_group_shown(g, p, gd))
	if groups.is_empty():
		return null
	var out := []
	for gd in groups:
		var cur: Variant = Laws.current(g, p, gd.id)
		var ladder := K.flow([], 4)
		for l in Laws.laws_of_group(g, gd.id):
			var active: bool = cur != null and l.id == cur.id
			var blockers := [] if active else Laws.change_blockers(g, p, l)
			var lid: String = l.id
			var cost := Laws.change_cost(g, p, l)
			ladder.add_child(K.button(g.name_of("realm_laws", l.id), func():
				if active:
					return
				Laws.change(g, p, lid)
				app.mark_dirty(true), {"icon": l.get("icon", "scales"), "toggled": active, "disabled": not active and not blockers.is_empty(),
				"tip": func():
					var bb := BB.title(g.name_of("realm_laws", lid)) + "\n" + BB.i(g.desc_of("realm_laws", lid)) + "\n" + BB.modifiers(g, l.get("modifiers"))
					if not active:
						bb += "\n" + BB.cost(g, cost)
					if not blockers.is_empty():
						bb += "\n" + BB.reasons(blockers)
					return bb}))
		var name := K.hbox([K.icon(gd.get("icon", "scales"), 18), K.label(g.name_of("law_groups", gd.id), "SubheaderLabel")], 6)
		K.tip(name, BB.i(g.desc_of("law_groups", gd.id)))
		out.append(K.vbox([name, ladder], 4))
	return K.section(app.t("ui.realm_laws"), out, "scales")


# ------------------------------------------------------------ фракции

static func factions(app: App, p: Dictionary) -> Array:
	var g := app.game
	var out := []
	if not g.engine.has_feature("factions"):
		return out
	var types: Array = g.content.all("factions")
	if types.is_empty():
		return out
	var threshold := g.def_num("factions.power_threshold", 80)
	if not g.vassals_of(p.id).is_empty():
		var against := Factions.against(g, p.id)
		var cards := [K.para(app.t("ui.faction_hint", {"n": threshold}), "SmallLabel")]
		for f in against:
			cards.append(_faction_card(app, f, false))
		if against.is_empty():
			cards.append(K.label(app.t("ui.no_factions"), "MutedLabel"))
		out.append(K.section(app.t("ui.factions_against_you"), cards, "fist"))
	var liege: Variant = g.ch(p.liege)
	if liege != null and not p.titles.is_empty():
		var mine: Variant = Factions.faction_of(g, p)
		var against := Factions.against(g, liege.id)
		var cards := []
		for f in against:
			cards.append(_faction_card(app, f, true))
		var cooldown: bool = p.flags.get("faction_cooldown") != null and float(p.flags.faction_cooldown) > g.date
		if mine == null:
			for def in types:
				if against.any(func(f): return f.type == def.id):
					continue
				var claimant: Variant = null
				if def.get("claimant", false):
					var cands := Factions.claimant_candidates(g, liege)
					for c in cands:
						if c.id == p.id:
							claimant = c.id
					if claimant == null and not cands.is_empty():
						claimant = cands[0].id
					if claimant == null:
						continue
				var ok := Factions.can_join(g, p, def, liege, claimant)
				var did: String = def.id
				var card := K.vbox([K.hbox([K.icon(def.get("icon", "fist"), 20), K.label(g.name_of("factions", def.id), "SubheaderLabel")], 6)], 4)
				K.tip(card, BB.i(g.desc_of("factions", def.id)))
				if claimant != null:
					card.add_child(K.hbox([K.label(app.t("ui.faction_claimant") + ":", "MutedLabel"), W.char_link(app, claimant, true)], 4))
				card.add_child(K.button(app.t("ui.create_faction"), func():
					Factions.create(g, did, p, claimant)
					app.mark_dirty(true), {"disabled": not ok, "tip": app.t("ui.faction_cooldown") if cooldown else null}))
				cards.append(K.panel(card, "InsetPanel"))
		if not cards.is_empty():
			out.append(K.section(app.t("ui.factions_against_liege"), [K.para(app.t("ui.faction_hint", {"n": threshold}), "SmallLabel")] + cards, "fist"))
	return out


static func _faction_card(app: App, f: Dictionary, as_vassal: bool) -> Control:
	var g := app.game
	var p: Dictionary = g.player
	var def: Variant = g.content.get_def("factions", f.type)
	var power := Factions.power(g, f)
	var box := K.vbox([], 3)
	var head := K.hbox([K.icon(def.get("icon", "fist") if def != null else "fist", 20), K.label(g.name_of("factions", f.type), "SubheaderLabel")], 6)
	K.tip(head, BB.i(g.desc_of("factions", f.type)))
	box.add_child(head)
	box.add_child(K.hbox([K.label(app.t("ui.faction_leader") + ":", "MutedLabel"), W.char_link(app, f.leader, true)], 4))
	if f.get("claimant") != null:
		box.add_child(K.hbox([K.label(app.t("ui.faction_claimant") + ":", "MutedLabel"), W.char_link(app, f.claimant, true)], 4))
	box.add_child(K.label(app.t("ui.faction_power", {"n": power}), "BadLabel" if power >= g.def_num("factions.power_threshold", 80) else "MutedLabel"))
	box.add_child(K.label(app.t("ui.faction_discontent", {"n": roundi(f.discontent)}), "MutedLabel"))
	box.add_child(K.bar(f.discontent, 100, Color("#b8443a")))
	var members := K.flow([], 3)
	for id in f.members:
		var c: Variant = g.ch(id)
		if c != null:
			members.add_child(W.portrait(app, c, 34))
	box.add_child(K.label(app.t("ui.faction_members", {"n": f.members.size()}), "SmallLabel"))
	box.add_child(members)
	if as_vassal and def != null:
		var liege: Variant = g.ch(f.target)
		var member: bool = f.members.has(p.id)
		var btns := K.hbox([], 6)
		if member:
			btns.add_child(K.button(app.t("ui.leave_faction"), func():
				Factions.leave(g, p)
				app.mark_dirty(true)))
			if f.leader == p.id:
				btns.add_child(K.button(app.t("ui.send_ultimatum"), func():
					Factions.player_ultimatum(g, f)
					app.mark_dirty(true), {"variation": "GoldButton", "disabled": float(f.discontent) < 100}))
		elif Factions.faction_of(g, p) == null and liege != null:
			var ok := Factions.can_join(g, p, def, liege, f.get("claimant"))
			btns.add_child(K.button(app.t("ui.join_faction"), func():
				Factions.join(g, p, f)
				app.mark_dirty(true), {"disabled": not ok}))
		box.add_child(btns)
	return K.panel(box, "InsetPanel")


# ------------------------------------------------------------ войска

static func regiment_tip(app: App, def: Dictionary) -> String:
	var g := app.game
	var name := func(id): return g.name_of("regiment_types", id)
	var countered_by := []
	for d in g.content.all("regiment_types"):
		if d.get("counters") is Dictionary and d.counters.has(def.id):
			countered_by.append(name.call(d.id))
	var bb := BB.title(name.call(def.id))
	var desc := g.desc_of("regiment_types", def.id)
	if desc != "":
		bb += "\n" + BB.i(desc)
	bb += "\n" + BB.esc(app.t("ui.regiment_stats", {"size": def.get("size", 0), "power": def.get("power", 0)}))
	bb += "\n" + BB.muted(app.t("ui.regiment_upkeep_n", {"n": K.fmt(Data.num(def.get("upkeep")), 2), "mult": g.def_num("regiments.raised_upkeep_mult", 2)}))
	var counters: Array = def.get("counters").keys() if def.get("counters") is Dictionary else []
	if not counters.is_empty():
		bb += "\n" + BB.good(app.t("ui.regiment_counters", {"list": ", ".join(counters.map(func(x): return name.call(x)))}))
	if not countered_by.is_empty():
		bb += "\n" + BB.bad(app.t("ui.regiment_countered_by", {"list": ", ".join(countered_by)}))
	if def.get("terrain") is Dictionary and not def.terrain.is_empty():
		var parts := []
		for tt in def.terrain:
			parts.append("%s %s%%" % [g.name_of("terrain", tt), K.signed(roundi(float(def.terrain[tt]) * 100))])
		bb += "\n" + BB.muted(app.t("ui.regiment_terrain", {"list": ", ".join(parts)}))
	return bb


static func regiments(app: App, p: Dictionary) -> Variant:
	var g := app.game
	if not g.engine.has_feature("regiments"):
		return null
	var types := Regiments.types(g)
	if types.is_empty() or p.titles.is_empty():
		return null
	var cap := Regiments.cap(g, p)
	var regs := Regiments.regs_of(p)
	var list := K.vbox([], 4)
	var raised_ids := {}
	for a in g.state.armies.values():
		if a.owner == p.id and a.get("regiments") is Array:
			for x in a.regiments:
				raised_ids[x.id] = true
	for r in regs:
		var def: Variant = g.content.get_def("regiment_types", r.type)
		if def == null:
			continue
		var raised: bool = raised_ids.has(r.id)
		var status := ""
		if raised:
			status = " · " + app.t("ui.regiment_in_army")
		elif float(r.size) < Data.num(def.get("size")):
			status = " · " + app.t("ui.regiment_reinforcing")
		var rid: String = r.id
		var main := K.vbox([
			K.label(g.name_of("regiment_types", r.type) + status),
			K.bar(r.size, Data.num(def.get("size"), 1)),
			K.label("%s / %s · %s" % [K.fmt(r.size), K.fmt(Data.num(def.get("size"))), app.t("ui.regiment_power", {"n": K.fmt(float(r.size) * Data.num(def.get("power")))})], "SmallLabel"),
		], 2)
		main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := K.panel(K.hbox([K.icon(def.get("icon", "spear"), 26), main, K.button("", func():
			Regiments.disband(g, p, rid)
			app.mark_dirty(true), {"icon": "close", "tip": app.t("ui.dismiss_regiment")})], 8), "RowPanel")
		K.tip(row, func(): return regiment_tip(app, def))
		list.add_child(row)
	if regs.is_empty():
		list.add_child(K.label(app.t("ui.no_regiments"), "MutedLabel"))
	var shop := K.flow([], 4)
	for def in types:
		if not Regiments.is_type_shown(g, p, def) and def.get("can_recruit") != null and JSON.stringify(def.can_recruit).contains("culture"):
			continue
		var blockers := Regiments.recruit_blockers(g, p, def)
		var cost := Regiments.cost(g, p, def)
		var did: String = def.id
		shop.add_child(K.button(g.name_of("regiment_types", def.id), func():
			Regiments.recruit(g, p, did)
			app.mark_dirty(true), {"icon": def.get("icon", "spear"), "disabled": not blockers.is_empty(),
			"tip": func(): return regiment_tip(app, def) + "\n" + BB.cost(g, cost) + ("\n" + BB.reasons(blockers) if not blockers.is_empty() else "")}))
	return K.section("%s — %s" % [app.t("ui.regiments"), app.t("ui.regiments_n", {"n": regs.size(), "cap": cap})],
		[K.para(app.t("ui.regiments_hint"), "SmallLabel"), list, K.label(app.t("ui.recruit_regiment"), "GoldLabel"), shop], "shield")


static func army_regiments(app: App, a: Dictionary) -> Variant:
	var g := app.game
	if not (a.get("regiments") is Array) or a.regiments.is_empty():
		return null
	var rows := []
	for r in a.regiments:
		var def: Variant = g.content.get_def("regiment_types", r.type)
		var row := K.hbox([K.icon(def.get("icon", "spear") if def != null else "spear", 20), K.label("%s — %s" % [g.name_of("regiment_types", r.type), K.fmt(r.size)])], 6)
		if def != null:
			K.tip(row, func(): return regiment_tip(app, def))
		rows.append(row)
	return K.section(app.t("ui.army_regiments"), rows, "shield")


# ------------------------------------------------------------ тайны

static func _secret_chip(app: App, s: Dictionary, show_known: bool) -> Control:
	var g := app.game
	var def: Variant = g.content.get_def("secret_types", s.type)
	var row := K.hbox([K.icon(def.get("icon", "eye") if def != null else "eye", 18), K.label(g.name_of("secret_types", s.type))], 6)
	if s.get("target") != null:
		row.add_child(K.label("—", "MutedLabel"))
		row.add_child(W.char_link(app, s.target))
	if show_known:
		var n: int = s.get("known", []).size()
		row.add_child(K.label("· " + app.t("ui.secret_known_by_n", {"n": n}), "BadLabel" if n > 0 else "MutedLabel"))
	K.tip(row, BB.title(g.name_of("secret_types", s.type)) + "\n" + BB.i(g.desc_of("secret_types", s.type)))
	return row


static func _hook_kind(app: App, strong: Variant) -> String:
	return app.t("ui.hook_strong" if strong else "ui.hook_weak")


static func secrets_character(app: App, c: Dictionary) -> Variant:
	var g := app.game
	var p: Variant = g.player
	if p == null or not g.engine.has_feature("secrets"):
		return null
	var rows := []
	if c.id == p.id:
		for s in Secrets.secrets_of(c):
			rows.append(_secret_chip(app, s, true))
	else:
		var mine: Variant = Leverage.hook_on(g, p, c.id)
		if mine != null:
			var cd := ""
			if not Leverage.can_use_hook(g, p, c.id):
				cd = " (%s)" % app.t("ui.hook_cooldown", {"days": int(p.flags.get("hook_cd:" + c.id, g.date)) - g.date})
			rows.append(K.label(app.t("ui.you_have_hook", {"kind": _hook_kind(app, mine.get("strong"))}) + cd, "GoodLabel"))
		var theirs: Variant = Leverage.hook_on(g, c, p.id)
		if theirs != null:
			rows.append(K.label(app.t("ui.has_hook_on_you", {"kind": _hook_kind(app, theirs.get("strong"))}), "BadLabel"))
		for s in Secrets.known_secrets_of(g, c, p.id):
			rows.append(_secret_chip(app, s, false))
	if rows.is_empty():
		return null
	return K.section(app.t("ui.secrets"), rows, "eye")


static func secrets_intrigue(app: App) -> Array:
	var g := app.game
	var p: Dictionary = g.player
	if not g.engine.has_feature("secrets"):
		return []
	var out := []
	var own := Secrets.secrets_of(p)
	var rows := []
	for s in own:
		rows.append(_secret_chip(app, s, true))
	if own.is_empty():
		rows.append(K.label(app.t("ui.no_secrets"), "MutedLabel"))
	out.append(K.section(app.t("ui.my_secrets"), rows, "eye"))
	var known := []
	for o in g.living():
		for s in Secrets.known_secrets_of(g, o, p.id):
			known.append(K.hbox([W.char_link(app, o.id, true), K.label(":"), _secret_chip(app, s, false)], 4))
	if not known.is_empty():
		out.append(K.section(app.t("ui.known_secrets"), known, "eye"))
	var my_hooks: Array = p.get("hooks", []).filter(func(x): return x.get("expires") == null or x.expires > g.date)
	var on_me := g.living().filter(func(o): return Leverage.hook_on(g, o, p.id) != null)
	if not my_hooks.is_empty() or not on_me.is_empty():
		var hk := []
		for x in my_hooks:
			hk.append(K.hbox([W.char_link(app, x.target, true), K.label("— " + _hook_kind(app, x.get("strong")), "GoodLabel")], 4))
		for o in on_me:
			hk.append(K.hbox([W.char_link(app, o.id, true), K.label("→ %s (%s)" % [app.t("ui.hooks_on_me"), _hook_kind(app, Leverage.hook_on(g, o, p.id).get("strong"))], "BadLabel")], 4))
		out.append(K.section(app.t("ui.hooks"), hk, "chain"))
	return out


# ------------------------------------------------------------ рыцари

static func knights(app: App, p: Dictionary) -> Variant:
	var g := app.game
	if not g.engine.has_feature("knights") or p.titles.is_empty():
		return null
	var ks := Knights.knights_of(g, p)
	var cap := Knights.cap(g, p)
	var rows: Array = [K.para(app.t("ui.knights_hint", {"n": K.fmt(Knights.power(g, p))}), "SmallLabel")]
	var flow := K.flow([], 6)
	for k in ks:
		var cap_l := K.label(str(Stats.skill(g, k, "prowess")), "SmallLabel")
		cap_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flow.add_child(K.vbox([W.portrait(app, k, 48), K.hbox([K.icon("swords", 14), cap_l], 2, BoxContainer.ALIGNMENT_CENTER)], 0))
	if ks.is_empty():
		rows.append(K.label(app.t("ui.no_knights"), "MutedLabel"))
	else:
		rows.append(flow)
	return K.section("%s — %d / %d" % [app.t("ui.knights"), ks.size(), cap], rows, "helm")

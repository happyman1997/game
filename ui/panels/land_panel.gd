class_name LandPanel
extends RefCounted
## Раздел «Земля» в окне провинции (механика biomes, земля по клеткам):
## состав земли — полоса долей местностей и что она даёт графству; идущая
## работа (участок, срок, «дальше — следующий участок»); работы, которые
## можно начать (владельцу); летопись земли — кто и когда её менял.

const LOG_LINES := 6


static func build(app: App, pid: String) -> Control:
	var g := app.game
	var box := K.vbox([], 6)
	var land := g.land()
	var title: Variant = g.state.titles.get(pid)
	var holder: Variant = g.ch(title.holder) if title != null else null
	var mine: bool = holder != null and g.is_player(holder.id)
	# состав земли
	var mix := land.mix(pid) if land.ready() else {}
	if not mix.is_empty():
		box.add_child(_mix_bar(app, pid, mix))
		var parts := []
		for t in mix:
			parts.append("%s %d%%" % [g.name_of("terrain", t), roundi(float(mix[t]) * 100.0)])
		var lbl := K.label(" · ".join(parts), "SmallLabel")
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		K.tip(lbl, func(): return effects_tip(app, pid))
		box.add_child(lbl)
	else:
		var t := g.terrain_of(pid)
		var chip := K.panel(K.hbox([K.icon("mountain", 18), K.label(g.name_of("terrain", t), "SubheaderLabel")], 6), "InsetPanel")
		K.tip(chip, func(): return terrain_tip(app, t))
		box.add_child(chip)
	# идут работы
	var w: Variant = Biomes.work_of(g, pid)
	if w != null:
		var cells := Biomes.work_cells(g, pid).size()
		var row := K.hbox([K.label(app.t("land.work_now", {"work": g.name_of("land_works", str(w.id)), "n": Biomes.months_left(g, pid),
			"patch": int(w.get("done", 0)) + 1, "share": roundi(100.0 * Biomes.patch_share_of(g, pid))}))], 8)
		row.get_child(0).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if mine:
			var cancel := K.button(app.t("land.cancel"), func():
				Biomes.cancel(g, pid)
				app.mark_dirty(true), {"variation": "FlatButton"})
			K.tip(cancel, BB.bad(app.t("land.cancel_tip")))
			row.add_child(cancel)
		box.add_child(row)
		box.add_child(K.bar(Biomes.progress(g, pid), 1.0, Color("#8fae5a"), 8))
		if mine:
			var on := bool(w.get("repeat", true))
			var rep := K.button(app.t("land.repeat_on" if on else "land.repeat_off"), func():
				Biomes.set_repeat(g, pid, not on)
				app.mark_dirty(true), {"variation": "FlatButton", "toggled": on})
			K.tip(rep, app.t("land.repeat_tip"))
			box.add_child(rep)
		if cells == 0:
			box.add_child(K.label(app.t("land.patch_gone"), "MutedLabel"))
	# что можно сделать (владельцу)
	elif mine:
		var works := Biomes.works_here(g, pid)
		if works.is_empty():
			box.add_child(K.label(app.t("land.none_here"), "MutedLabel"))
		for d in works:
			box.add_child(_work_row(app, holder, pid, d))
	# летопись земли
	var hist := Biomes.history_of(g, pid)
	if not hist.is_empty():
		var lines := []
		for i in range(hist.size() - 1, maxi(-1, hist.size() - 1 - LOG_LINES), -1):
			lines.append(BB.muted("• ") + BB.esc(log_line(app, pid, hist[i])))
		box.add_child(K.rich(BB.gold(app.t("land.history")) + "\n" + "\n".join(lines)))
	return K.section(app.t("land.section"), [box], "mountain")


## Полоса долей местностей цветами карты.
static func _mix_bar(app: App, pid: String, mix: Dictionary) -> Control:
	var g := app.game
	var bar := K.hbox([], 0)
	bar.custom_minimum_size.y = 14
	for t in mix:
		var td: Variant = g.content.get_def("terrain", t)
		var col := Color("#9a9a7a")
		if td != null and td.get("color") is String:
			col = Color(td.color)
		var seg := ColorRect.new()
		seg.color = col
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = maxf(0.01, float(mix[t]))
		seg.mouse_filter = Control.MOUSE_FILTER_STOP
		var tt: String = t
		K.tip(seg, func(): return BB.gold("%d%%" % roundi(float(mix[tt]) * 100.0)) + " " + terrain_tip(app, tt))
		bar.add_child(seg)
	return K.panel(bar, "InsetPanel")


## Что земля даёт графству сейчас (по долям) и господствующая местность.
static func effects_tip(app: App, pid: String) -> String:
	var g := app.game
	var land := g.land()
	var bb := BB.title(app.t("land.effects")) + "\n" + BB.muted(app.t("land.dominant", {"t": g.name_of("terrain", g.terrain_of(pid))}))
	var mods := land.mods(pid)
	if not mods.is_empty():
		bb += "\n" + BB.modifiers(g, mods)
	var df := land.num(pid, "defense")
	if df != 0.0:
		bb += "\n" + BB.muted(app.t("land.defense", {"n": roundi(df * 100)}))
	var mv := land.num(pid, "movement", 1.0)
	if absf(mv - 1.0) > 0.01:
		bb += "\n" + BB.muted(app.t("land.movement", {"n": K.fmt(mv, 2)}))
	var cap := land.mods(pid, "capital_modifiers")
	if not cap.is_empty():
		bb += "\n" + BB.muted(app.t("land.capital")) + "\n" + BB.modifiers(g, cap)
	bb += "\n\n" + BB.small(BB.muted(app.t("land.cells_hint", {"n": land.count(pid)})))
	return bb


static func _work_row(app: App, c: Dictionary, pid: String, d: Dictionary) -> Control:
	var g := app.game
	var wid: String = d.id
	var why := Biomes.blockers(g, c, pid, wid)
	var cost := Biomes.cost_for(g, c, d)
	var months := Biomes.months_for(g, c, d)
	var cells := Biomes.patch_size(g, pid, d)
	var share := roundi(100.0 * cells / maxf(1.0, g.land().count(pid)))
	var info := "%s · %s" % [app.t("land.patch", {"n": share, "m": months}), app.t("land.becomes", {"to": g.name_of("terrain", str(d.to))})]
	if cost > 0.0:
		info = "%s · %s" % [info, app.t("land.cost", {"n": roundi(cost)})]
	var name := K.label("%s %s" % [str(d.get("icon", "")), g.name_of("land_works", wid)])
	var sub := K.label(info, "SmallLabel")
	sub.add_theme_color_override("font_color", UiArt.C_MUTED)
	var b := K.button(app.t("land.start"), func():
		Biomes.start(g, c, pid, wid)
		app.mark_dirty(true), {"min_w": 100})
	b.disabled = not why.is_empty()
	var row := K.hbox([K.vbox([name, sub], 0), K.expand(), b], 8)
	var tip := func() -> String:
		var bb := BB.title(g.name_of("land_works", wid)) + "\n" + BB.esc(app.t("land_work_desc." + wid))
		bb += "\n" + BB.muted(app.t("land.room", {"n": roundi(100.0 * Biomes.room_for(g, pid, d))}))
		bb += "\n" + BB.muted(app.t("land.patches_hint"))
		if d.get("during") is Dictionary:
			var during := {}
			for k in d.during:
				during[k] = Data.num(d.during[k]) * cells / maxf(1.0, g.land().count(pid))
			bb += "\n" + BB.muted(app.t("land.during")) + "\n" + BB.modifiers(g, during)
		var ctx := Biomes._ctx(g, c, pid)
		var lines: Array = Interp.describe_effect(ctx, {"type": "province", "id": pid}, d.get("on_complete"))
		if not lines.is_empty():
			bb += "\n" + BB.muted(app.t("land.each_patch")) + "\n" + BB.desc_lines(lines)
		bb += "\n\n" + terrain_tip(app, str(d.to))
		if not why.is_empty():
			bb += "\n" + BB.bad("\n".join(why.map(func(k): return app.t(k))))
		return bb
	K.tip(row, tip)
	K.tip(b, tip)
	return row


## Подсказка о состоянии земли: описание и что оно даёт (всей земле графства).
static func terrain_tip(app: App, t: String) -> String:
	var g := app.game
	var td: Variant = g.content.get_def("terrain", t)
	var bb := BB.title(g.name_of("terrain", t))
	var desc: Variant = g.loc.raw("terrain_desc." + t)
	if desc != null:
		bb += "\n" + BB.i(BB.esc(desc))
	if td == null:
		return bb
	var mods := {}
	if td.get("modifiers") is Dictionary:
		mods.merge(td.modifiers)
	if Data.num(td.get("development_growth")) != 0.0:
		mods["development_growth"] = Data.num(td.development_growth)
	if not mods.is_empty():
		bb += "\n" + BB.muted(app.t("land.full_county")) + "\n" + BB.modifiers(g, mods)
	if Data.num(td.get("defense")) != 0.0:
		bb += "\n" + BB.muted(app.t("land.defense", {"n": roundi(Data.num(td.defense) * 100)}))
	if Data.num(td.get("movement"), 1.0) != 1.0:
		bb += "\n" + BB.muted(app.t("land.movement", {"n": K.fmt(Data.num(td.movement), 1)}))
	if td.get("capital_modifiers") is Dictionary:
		bb += "\n" + BB.muted(app.t("land.capital")) + "\n" + BB.modifiers(g, td.capital_modifiers)
	return bb


## Строка летописи: «1072: Лес → Вырубка, 27% (Свести лес — Гарольд Годвинсон)».
static func log_line(app: App, pid: String, h: Array) -> String:
	var g := app.game
	var cause := str(h[4]) if h.size() > 4 else ""
	var why := g.name_of("land_works", cause) if g.content.has("land_works", cause) else app.t("land.cause." + cause) if cause != "" else ""
	var who: Variant = h[3] if h.size() > 3 else null
	if who != null and g.ch(who) != null:
		why = (why + " — " if why != "" else "") + g.scope_name({"type": "character", "id": who})
	var share := ""
	if h.size() > 5:
		share = ", %d%%" % maxi(1, roundi(100.0 * int(h[5]) / maxf(1.0, g.land().count(pid))))
	return app.t("land.log_line", {"year": GameDate.parts(int(h[0])).y, "from": g.name_of("terrain", str(h[1])), "to": g.name_of("terrain", str(h[2])), "share": share, "why": why})

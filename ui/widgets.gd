class_name W
extends RefCounted
## Игровые элементы интерфейса: портреты, гербы, ссылки на персонажей,
## титулы и провинции, строки списков.


## Портрет в рамке. opts: clickable (true), coa (герб в углу), round (медальон),
## tip (своя подсказка), dim (затемнить — недоступный выбор).
static func portrait(app: App, c: Variant, width: int = 72, opts: Dictionary = {}) -> Control:
	var v := PortraitView.new()
	v.app = app
	v.game = app.game
	v.character = c
	v.round = opts.get("round", false)
	v.show_coa = opts.get("coa", false)
	v.custom_minimum_size = Vector2(width, width if v.round else roundi(width * 1.2))
	v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if c == null:
		return v
	# Текстуры готовим сразу (под замком мира): отрисовка идёт позже, когда
	# мир может считаться в потоке симуляции.
	v.tex = Portraits.texture(app.game, c, maxi(48, width * 2 if width < 64 else width))
	v.dead = c.death != null
	if v.show_coa and not c.titles.is_empty():
		v.coa_tex = Coa.of_title(app.game, c.titles[0], int(width * 0.36))
	if opts.get("clickable", true):
		K.on_click(v, func(): app.open_character(c.id))
	K.tip(v, opts.get("tip", func(): return app.character_tooltip(c.id)))
	if opts.get("dim", false):
		v.modulate = Color(0.6, 0.6, 0.6)
	return v


static func coa(app: App, title_id: Variant, width: int = 32, clickable: bool = true) -> Control:
	if title_id == null:
		return K.spacer(width, width * 1.12)
	var r := K.tex(Coa.of_title(app.game, title_id, width), Vector2(width, roundi(width * 1.12)))
	r.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if clickable:
		K.on_click(r, func(): app.open_title(title_id))
	K.tip(r, BB.title(Titles.full_name(app.game, title_id)))
	return r


static func dynasty_coa(app: App, dyn_id: Variant, width: int = 32) -> Control:
	var r := K.tex(Coa.of_dynasty(app.game, dyn_id, width), Vector2(width, roundi(width * 1.12)))
	if dyn_id != null:
		K.tip(r, BB.title(app.game.name_of("dynasties", dyn_id)))
	return r


static func _link(text: String, color: Color, cb: Callable, tip_content: Variant = null) -> Button:
	var b := Button.new()
	b.theme_type_variation = "LinkText"
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", color)
	b.add_theme_constant_override("h_separation", 0)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func(): App.locked(cb))
	if tip_content != null:
		K.tip(b, tip_content)
	return b


static func char_link(app: App, id: Variant, with_rank: bool = false) -> Control:
	var g := app.game
	var c: Variant = g.ch(id)
	if c == null:
		return K.label("—", "MutedLabel")
	var dead: bool = c.death != null
	var color := Color("#b0a38a") if dead else (Color("#ffe08a") if g.is_player(c.id) else Color("#f0d48a"))
	var name := Chars.full_name(g, c, with_rank) + (" ✝" if dead else "")
	return _link(name, color, func(): app.open_character(c.id), func(): return app.character_tooltip(c.id))


static func title_link(app: App, id: Variant) -> Control:
	if id == null:
		return K.label("—", "MutedLabel")
	return _link(Titles.full_name(app.game, id), Color("#f0d48a"), func(): app.open_title(id))


static func prov_link(app: App, id: Variant) -> Control:
	if id == null:
		return K.label("—", "MutedLabel")
	return _link(app.game.name_of("provinces", id), Color("#f0d48a"), func(): app.open_province(id, true),
		func(): return app.province_tooltip(id))


static func scope_link(app: App, ref: Variant) -> Control:
	if not (ref is Dictionary):
		return null
	match ref.get("type"):
		"character": return char_link(app, ref.id)
		"title": return title_link(app, ref.id)
		"province": return prov_link(app, ref.id)
	return K.label(app.game.scope_name(ref))


## Строка списка персонажей: портрет, имя и строки под ним.
static func char_row(app: App, c: Dictionary, lines: Array = [], right: Array = [], width: int = 44) -> Control:
	var info := K.vbox([char_link(app, c.id, true)], 0)
	for l in lines:
		if l is String:
			info.add_child(K.label(l, "SmallLabel"))
		elif l is Control:
			info.add_child(l)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := K.hbox([portrait(app, c, width, {"coa": not c.titles.is_empty()}), info], 8)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	for r in right:
		if r != null:
			row.add_child(r)
	return K.panel(row, "RowPanel")


## Значок со значением (иконка + число) с подсказкой.
static func stat(icon_name: Variant, text: String, tip_content: Variant = null, color: Color = UiArt.C_TEXT, size: int = 18) -> Control:
	var l := K.label(text)
	l.add_theme_color_override("font_color", color)
	var box := K.hbox([K.icon(icon_name, size), l], 4)
	if tip_content != null:
		K.tip(box, tip_content)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	return box


## Навыки персонажа: значки с числами.
static func skills(app: App, c: Dictionary) -> Control:
	var g := app.game
	var row := K.hbox([], 10)
	for s in Chars.skill_ids(g):
		var d: Variant = g.content.get_def("skills", s)
		var v := int(Stats.skill(g, c, s))
		# редкие навыки (колдовство) у большинства нулевые — не показываем
		if v == 0 and d != null and d.get("hide_if_zero", false):
			continue
		var ic: Variant = d.get("icon", "star") if d != null else "star"
		var sid: String = s
		row.add_child(stat(ic, str(v), func(): return skill_tip(g, c, sid), UiArt.C_TEXT, 18))
	return row


## Подсказка навыка: из чего сложился, что даёт (описание и «за каждое очко»).
static func skill_tip(g: Game, c: Dictionary, sid: String) -> String:
	var bb := BB.title(g.name_of("skills", sid)) + "\n" + BB.breakdown(Stats.stat_breakdown(g, c, sid))
	var desc := g.loc.t_or("skill_desc." + sid, "")
	if desc != "":
		bb += "\n" + BB.i(desc)
	var d: Variant = g.content.get_def("skills", sid)
	var pp: Variant = d.get("per_point") if d != null else null
	if pp is Dictionary and not pp.is_empty():
		bb += "\n" + BB.muted(g.loc.t("ui.per_skill_point")) + "\n" + BB.modifiers(g, pp)
	var rp: Variant = d.get("ruler_per_point") if d != null else null
	if rp is Dictionary and not rp.is_empty():
		bb += "\n" + BB.muted(g.loc.t("ui.per_skill_point_ruler")) + "\n" + BB.modifiers(g, rp)
	return bb


## Подсказка стресса: состояние, что оно значит, откуда стресс в последнее время.
static func stress_tip(app: App, c: Dictionary) -> String:
	var g := app.game
	var st := float(c.stress)
	var lvl := floori(st / 100.0)
	var state := 0 if st < 50.0 else (1 if lvl == 0 else mini(4, lvl + 1))
	var state_txt := app.t("ui.stress_state_%d" % state)
	var bb := BB.title(app.t("ui.stress")) + "\n" + (BB.bad(state_txt) if state >= 2 else BB.muted(state_txt))
	bb += "\n" + BB.esc(app.t("ui.stress_tip"))
	var log: Array = c.vars.get("stress_log", [])
	if not log.is_empty():
		var rows := []
		for i in range(log.size() - 1, -1, -1):
			var e: Array = log[i]
			rows.append([BB.esc(stress_source(g, str(e[2]))), BB.bad(K.signed(float(e[1]))) if float(e[1]) > 0 else BB.good(K.signed(float(e[1])))])
		bb += "\n" + BB.muted(app.t("ui.stress_recent")) + "\n" + BB.rows(rows)
	return bb


## Подпись источника стресса из журнала (Chars.change_stress).
static func stress_source(g: Game, src: String) -> String:
	if src == "":
		return g.loc.t("stress_src.other")
	var i := src.find(":")
	var kind := src.substr(0, i) if i >= 0 else src
	var id := src.substr(i + 1) if i >= 0 else ""
	match kind:
		"event":
			return g.loc.t("stress_src.event", {"name": g.loc.t_or("ev.%s.t" % id, id)})
		"decision":
			return g.loc.t("stress_src.decision", {"name": g.name_of("decisions", id)})
		"interaction":
			return g.loc.t("stress_src.interaction", {"name": g.name_of("interactions", id)})
		"action":
			return g.loc.t("stress_src.action", {"name": Personality.action_name(g, id)})
		"trait":
			return g.loc.t("stress_src.trait", {"name": Personality.source_name(g, id)})
		"momentum":
			return g.loc.t("stress_src.momentum", {"name": g.name_of("skills", id)})
	return g.loc.t_or("stress_src." + kind, g.loc.t("stress_src.other"))


## Плашка испытания пути: название, сколько целей выполнено; в подсказке —
## цели с прогрессом и срок.
static func trial_chip(app: App, c: Dictionary, trial: Dictionary) -> Control:
	var g := app.game
	var aid := str(trial.id)
	var ad: Variant = g.content.get_def("skill_archetypes", aid)
	var gs := Trials.goals(g, c)
	var done := gs.filter(func(x): return x.done).size()
	var aname := g.name_of("skill_archetypes", aid)
	var chip := K.panel(K.hbox([K.icon("⏳", 16), K.label(app.t("ui.trial_chip", {"name": aname, "done": done, "total": gs.size()}), "SmallLabel")], 3))
	chip.add_theme_stylebox_override("panel", UiArt.flat(Color("#25303a"), Color(UiArt.GOLD, 0.45), 1, 3, 3))
	var months := maxi(0, ceili((int(trial.until) - g.date) / 30.4))
	var tb := BB.title(app.t("ui.trial_title", {"name": aname})) + "\n" + BB.muted(app.t("ui.trial_left", {"months": months}))
	for x in gs:
		var line := "%s %s (%d/%d)" % ["✓" if x.done else "•", x.text, x.have, x.need] if x.need > 1 or not x.done else "✓ " + str(x.text)
		tb += "\n" + (BB.good(line) if x.done else BB.esc(line))
	var adesc := g.desc_of("skill_archetypes", aid) if ad != null else ""
	if adesc != "":
		tb += "\n" + BB.i(adesc)
	tb += "\n" + BB.muted(app.t("ui.trial_fail_note", {"stress": roundi(g.def_num("trials.fail_stress", 30))}))
	K.tip(chip, tb)
	return chip


## Черты персонажа: значки-плашки.
static func traits(app: App, c: Dictionary) -> Control:
	var g := app.game
	var f := K.flow([], 4)
	var viewer: Variant = g.state.player
	for t in c.traits:
		var d: Variant = Chars.trait_def(g, t)
		if d == null or not Chars.trait_visible(g, c, t, viewer):
			continue
		var name := g.name_of("traits", t)
		var col: Color = {
			"personality": Color("#2e3a40"), "education": Color("#24384e"), "congenital": Color("#3e2e48"),
			"health": Color("#4a2a2a"), "lifestyle": Color("#2e4230"), "fame": Color("#4a3c20"),
			"supernatural": Color("#3a2448"),
		}.get(d.get("category", ""), Color("#2e3a40"))
		if d.get("color") is String:
			col = Color(d.color).darkened(0.45)
		var chip := K.panel(K.hbox([K.icon(d.get("icon"), 16), K.label(name, "SmallLabel")], 3))
		chip.add_theme_stylebox_override("panel", UiArt.flat(col, Color(UiArt.BRONZE, 0.7), 1, 3, 3))
		var tipbb := BB.title(name)
		var desc := g.loc.t_or("trait_desc." + t, "")
		if desc != "":
			tipbb += "\n" + BB.i(desc)
		var mods := BB.modifiers(g, d.get("modifiers"))
		if mods != "":
			tipbb += "\n" + mods
		if g.engine.has_feature("personality"):
			# характер: что претит и что по душе (стресс)
			var ps := Personality.trait_summary(g, d)
			if ps.bad != "":
				tipbb += "\n" + BB.bad(app.t("ui.stress_dislikes", {"list": ps.bad}))
			if ps.good != "":
				tipbb += "\n" + BB.good(app.t("ui.stress_likes", {"list": ps.good}))
			if ps.monthly != "":
				tipbb += "\n" + BB.bad(ps.monthly)
		if Chars.trait_concealed(g, c, t):
			# тайная черта: видна только носителю и посвящённым
			tipbb += "\n" + BB.muted(app.t("ui.concealed_trait"))
			chip.modulate = Color(1, 1, 1, 0.8)
		K.tip(chip, tipbb)
		f.add_child(chip)
	# архетипы: связки высоких навыков
	for aid in Stats.archetypes(g, c):
		var ad: Variant = g.content.get_def("skill_archetypes", aid)
		var aname := g.name_of("skill_archetypes", aid)
		var chip := K.panel(K.hbox([K.icon(ad.get("icon", "star"), 16), K.label(aname, "SmallLabel")], 3))
		chip.add_theme_stylebox_override("panel", UiArt.flat(Color("#4a3c20"), Color(UiArt.GOLD, 0.8), 1, 3, 3))
		var need := " + ".join(Data.as_array(ad.get("skills")).map(func(x): return g.name_of("skills", x)))
		var tb := BB.title(aname) + "\n" + BB.muted(app.t("ui.archetype_needs", {"skills": need, "min": int(Data.num(ad.get("min"), 12))}))
		var adesc := g.desc_of("skill_archetypes", aid)
		if adesc != "":
			tb += "\n" + BB.i(adesc)
		var amods := {}
		var raw: Variant = ad.get("modifiers")
		if raw is Dictionary:
			for k in raw:
				# правила-флаги описаны в тексте архетипа
				if k != "self_knight" and k != "scapegoat":
					amods[k] = raw[k]
		var mtxt := BB.modifiers(g, amods)
		if mtxt != "":
			tb += "\n" + mtxt
		K.tip(chip, tb)
		f.add_child(chip)
	# испытание пути: цели и срок
	var trial: Variant = Trials.active(c) if g.engine.has_feature("trials") else null
	if trial != null:
		f.add_child(trial_chip(app, c, trial))
	# тени мастерства: изнанка очень высоких навыков
	for s in Stats.masteries(g, c):
		var sd: Variant = g.content.get_def("skills", s)
		var ms: Dictionary = sd.mastery
		var mname := g.loc.t("mastery." + s)
		var chip := K.panel(K.hbox([K.icon(sd.get("icon", "star"), 16), K.label(mname, "SmallLabel")], 3))
		chip.add_theme_stylebox_override("panel", UiArt.flat(Color("#3a2a3e"), Color(UiArt.BRONZE, 0.7), 1, 3, 3))
		var tb := BB.title(app.t("modsrc.mastery", {"name": mname})) + "\n" + BB.i(g.loc.t_or("mastery_desc." + s, ""))
		var mods := BB.modifiers(g, ms.get("modifiers"))
		if mods != "":
			tb += "\n" + mods
		if g.engine.has_feature("personality"):
			var ps := Personality.trait_summary(g, ms)
			if ps.bad != "":
				tb += "\n" + BB.bad(app.t("ui.stress_dislikes", {"list": ps.bad}))
			if ps.good != "":
				tb += "\n" + BB.good(app.t("ui.stress_likes", {"list": ps.good}))
			if ps.monthly != "":
				tb += "\n" + BB.bad(ps.monthly)
		K.tip(chip, tb)
		f.add_child(chip)
	return f


## Портрет с рамкой (прямоугольный или круглый медальон).
class PortraitView:
	extends Control
	var app: App
	var game: Game
	var character: Variant
	var round := false
	var show_coa := false
	var tex: Texture2D
	var coa_tex: Texture2D
	var dead := false
	static var _frame: StyleBoxTexture

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	static func frame_box() -> StyleBoxTexture:
		if _frame == null:
			var svg := """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
<defs><linearGradient id="br" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="%s"/><stop offset="0.4" stop-color="%s"/><stop offset="0.6" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>
<linearGradient id="sh" x1="0" y1="0" x2="0" y2="1"><stop offset="0.6" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.45"/></linearGradient></defs>
<rect x="0" y="0" width="48" height="48" fill="url(#sh)"/>
<rect x="0.5" y="0.5" width="47" height="47" fill="none" stroke="%s" stroke-width="1"/>
<rect x="2" y="2" width="44" height="44" fill="none" stroke="url(#br)" stroke-width="2.4"/>
<rect x="3.7" y="3.7" width="40.6" height="40.6" fill="none" stroke="%s" stroke-opacity="0.8" stroke-width="0.8"/>
</svg>""" % [UiArt.BRONZE_DARK, UiArt.GOLD_LIGHT, UiArt.GOLD, UiArt.BRONZE_DARK, UiArt.INK, UiArt.INK]
			var sb := StyleBoxTexture.new()
			sb.texture = UiArt.texture("portrait_frame", svg)
			sb.texture_margin_left = 6
			sb.texture_margin_right = 6
			sb.texture_margin_top = 6
			sb.texture_margin_bottom = 6
			_frame = sb
		return _frame

	func _draw() -> void:
		if tex == null:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.4))
			return
		if round:
			var c := size / 2
			var r := minf(size.x, size.y) / 2 - 1
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i in 48:
				var a := TAU * i / 48.0
				var p := Vector2(cos(a), sin(a))
				pts.append(c + p * r)
				# лицо в круге: верхние 5/6 портрета
				uvs.append(Vector2(0.5 + p.x * 0.5, 0.42 + p.y * 0.42))
			draw_colored_polygon(pts, Color.WHITE, uvs, tex)
			var ring := UiArt.texture("medallion_%d" % int(size.x), UiArt.medallion_svg(int(size.x)))
			draw_texture_rect(ring, Rect2(Vector2.ZERO, size), false)
		else:
			draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
			draw_style_box(frame_box(), Rect2(Vector2.ZERO, size))
		if coa_tex != null:
			var cw := int(size.x * 0.36)
			draw_texture_rect(coa_tex, Rect2(Vector2(size.x - cw - 1, size.y - cw * 1.12 - 1), Vector2(cw, cw * 1.12)), false)
		if dead and not round:
			var f := Fonts.bold()
			draw_string(f, Vector2(4, size.y - 6), "✝", HORIZONTAL_ALIGNMENT_LEFT, -1, int(size.x * 0.22), Color(1, 1, 1, 0.8))

class_name FightWindow
extends RefCounted
## Окно схватки, где бьётся сам игрок: бойцы с полосами стойкости и силой
## стоек, подсказка о намерении противника, три стойки, сдача, журнал
## обменов; в конце — милость победителя и исход. Окно перестраивает себя
## после каждого хода (Duels.player_move / player_yield / player_mercy).

const THEME := Color("#7a2f22")
const LOG_LINES := 6


static func build(app: App, uid: String, on_close: Callable) -> Control:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var refresh_ref := [Callable()]
	var refresh := func() -> void:
		K.clear(holder)
		var f: Variant = Duels.find(app.game, uid)
		if f == null:
			on_close.call_deferred()
			return
		holder.add_child(_body(app, f, refresh_ref[0], on_close))
	refresh_ref[0] = refresh
	refresh.call()
	return holder


static func _body(app: App, f: Dictionary, refresh: Callable, on_close: Callable) -> Control:
	var g := app.game
	var me: int = maxi(0, int(f.player))
	var o := 1 - me
	var kind := "foe" if str(f.foe) != "" else str(f.kind)
	var head := K.label(app.t("duel.title." + kind), "TitleLabel")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 30)
	var scene := EventWindow.EventScene.new()
	scene.color = THEME
	scene.icon_name = Icons.resolve("sword")
	scene.custom_minimum_size = Vector2(0, 250)
	var row := K.hbox([_fighter(app, f, me), _vs(app, f), _fighter(app, f, o)], 24, BoxContainer.ALIGNMENT_CENTER)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(row)

	var parts := []
	match str(f.phase):
		"fight":
			parts.append_array(_fight_part(app, f, me, refresh))
		"mercy":
			parts.append_array(_mercy_part(app, f, refresh))
		_:
			parts.append_array(_over_part(app, f, me, on_close))
	var log_box: Variant = _log(app, f, me)
	if log_box != null:
		parts.append(K.spacer(0, 4))
		parts.append(log_box)
	var parchment := K.panel(K.vbox(parts, 8), "ParchmentPanel")
	var body := K.vbox([K.panel(head, "HeaderPanel"), scene, parchment], 8)
	body.custom_minimum_size = Vector2(700, 0)
	return K.panel(body)


## Боец: портрет (или знак врага), имя, стойкость, сила стоек.
static func _fighter(app: App, f: Dictionary, i: int) -> Control:
	var g := app.game
	var fid: Variant = f.fighter[i]
	var c: Variant = g.ch(fid) if fid != null else null
	var pic: Control
	if c != null:
		pic = W.portrait(app, c, 120, {"clickable": false})
	else:
		var d: Variant = g.content.get_def("foes", str(f.prof[i].get("foe", "")))
		var l := K.label(str(d.get("icon", "⚔")) if d != null else "⚔")
		l.add_theme_font_size_override("font_size", 84)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pic = K.min_size(l, 120, 150)
	var name := K.label(_cap(Duels.fighter_name(g, f, i)), "SmallLabel")
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_color_override("font_color", UiArt.C_TEXT)
	var v: float = maxf(0.0, f.vig[i])
	var m: float = f.max[i]
	var col := UiArt.C_GOOD if v > m * 0.6 else (UiArt.C_WARN if v > m * 0.3 else UiArt.C_BAD)
	var bar := K.bar(v, m, col, 10, app.t("duel.vigor", {"v": roundi(v), "m": roundi(m)}))
	bar.custom_minimum_size.x = 220
	var p: Dictionary = f.prof[i]
	var stances := K.hbox([], 10, BoxContainer.ALIGNMENT_CENTER)
	for s in Duels.STANCES:
		var l := K.label("%s %d" % [app.t("duel.stance_t." + s), roundi(float(p[s]))], "SmallLabel")
		l.add_theme_color_override("font_color", UiArt.C_GOLD)
		if c != null:
			K.tip(l, func(): return BB.title(app.t("duel.stance_t." + s)) + "\n" + BB.breakdown(Duels.stance_parts(g, c, s), 1))
		stances.add_child(l)
	var col_box := K.vbox([pic, name, bar, stances], 4)
	col_box.alignment = BoxContainer.ALIGNMENT_CENTER
	return col_box


static func _vs(app: App, f: Dictionary) -> Control:
	var l := K.label("⚔", "TitleLabel")
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", UiArt.C_GOLD)
	var r := K.label(app.t("duel.round", {"n": mini(int(f.round) + 1, int(Duels.cfg(app.game).max_rounds)), "m": int(Duels.cfg(app.game).max_rounds)}), "SmallLabel")
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.add_theme_color_override("font_color", UiArt.C_MUTED)
	var box := K.vbox([l, r] if f.phase == "fight" else [l], 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	return box


## Ход игрока: что выдаёт противник, три стойки, сдаться.
static func _fight_part(app: App, f: Dictionary, me: int, refresh: Callable) -> Array:
	var g := app.game
	var o := 1 - me
	var out := []
	var text := ""
	if f.log.is_empty():
		text = BB.i(BB.esc(app.t("duel.intro." + ("foe" if str(f.foe) != "" else str(f.kind)))))
	if f.tell != null:
		var tell := _cap(app.t("duel.tell.%s.%d" % [f.tell, int(f.get("tell_n", 1))], {"who": Duels.fighter_name(g, f, o)}))
		text += ("\n" if text != "" else "") + BB.esc(tell) + "\n" + BB.muted(app.t("duel.tell_acc", {"n": int(f.tell_acc)}))
	if text != "":
		var desc := K.rich(text, true, "InkText")
		desc.custom_minimum_size = Vector2(620, 0)
		out.append(desc)
	var row := K.hbox([], 8, BoxContainer.ALIGNMENT_CENTER)
	for s in Duels.STANCES:
		var stance: String = s
		var b := K.button(app.t("duel.stance_t." + stance), func():
			Duels.player_move(g, str(f.uid), stance)
			_sound(f)
			refresh.call()
			app.mark_dirty(true), {"variation": "EventOption", "min_w": 190, "min_h": 40})
		K.tip(b, func():
			return BB.title(app.t("duel.stance_t." + stance)) + "\n" + BB.esc(app.t("duel.stance_tip." + stance)) + "\n" + BB.gold(app.t("duel.power", {"n": K.fmt(float(f.prof[me][stance]), 1)})))
		row.add_child(b)
	out.append(row)
	if Duels.can_yield(f, me):
		var y := K.button(app.t("duel.yield"), func():
			Duels.player_yield(g, str(f.uid))
			refresh.call()
			app.mark_dirty(true), {"min_w": 160})
		K.tip(y, BB.title(app.t("duel.yield")) + "\n" + BB.bad(app.t("duel.yield_tip")))
		out.append(K.center(y))
	return out


## Победа игрока: судьба противника.
static func _mercy_part(app: App, f: Dictionary, refresh: Callable) -> Array:
	var g := app.game
	var t := K.rich("[b]%s[/b]" % BB.esc(app.t("duel.mercy_title_yield" if f.how == "yield" else "duel.mercy_title")), true, "InkText")
	var row := K.hbox([], 8, BoxContainer.ALIGNMENT_CENTER)
	for m in Duels.MERCY:
		var choice: String = m
		var b := K.button(app.t("duel.mercy." + choice), func():
			Duels.player_mercy(g, str(f.uid), choice)
			refresh.call()
			app.mark_dirty(true), {"variation": "EventOption", "min_w": 190, "min_h": 40})
		var tip := app.t("duel.mercy_tip." + choice)
		K.tip(b, BB.title(app.t("duel.mercy." + choice)) + "\n" + (BB.bad(tip) if choice == "kill" else BB.esc(tip)))
		row.add_child(b)
	return [t, row]


## Бой окончен: исход и кнопка «Закрыть».
static func _over_part(app: App, f: Dictionary, me: int, on_close: Callable) -> Array:
	var g := app.game
	var won: bool = f.winner == me
	var w: int = f.winner
	var p := {"w": Duels.fighter_name(g, f, w), "l": Duels.fighter_name(g, f, 1 - w)}
	if 1 - w == me:
		p.l = app.t("duel.you")
	if w == me:
		p.w = app.t("duel.you")
	var lines := ["[b]%s[/b]" % BB.c(app.t("duel.result.win" if won else "duel.result.lose"), "#3d6b1f" if won else "#8a2a1c")]
	lines.append(BB.esc(app.t("duel.how." + str(f.how), p)))
	var fate := app.t("duel.fate." + str(f.mercy)) if str(f.mercy) in Duels.MERCY else ""
	if fate != "":
		lines.append(BB.esc(fate))
	if f.get("fatal", false):
		lines.append(BB.esc(app.t("duel.fatal")))
	var t := K.rich("\n".join(lines), true, "InkText")
	t.custom_minimum_size = Vector2(620, 0)
	var close := K.button(app.t("duel.close"), func():
		Duels.dismiss(g, str(f.uid))
		on_close.call()
		app.mark_dirty(true), {"variation": "GoldButton", "min_w": 200})
	return [t, K.center(close)]


static func _log(app: App, f: Dictionary, me: int) -> Variant:
	var lg: Array = f.log
	if lg.is_empty():
		return null
	var lines := []
	for j in range(maxi(0, lg.size() - LOG_LINES), lg.size()):
		var e: Dictionary = lg[j]
		var raw := Duels.log_line(app.game, f, e, me)
		var mine_hit: bool = int(e.d[me]) > 0
		var their_hit: bool = int(e.d[1 - me]) > 0
		var line := BB.esc(raw)
		if mine_hit and not their_hit:
			line = BB.c(raw, "#8a2a1c")
		elif their_hit and not mine_hit:
			line = BB.c(raw, "#3d6b1f")
		if j == lg.size() - 1:
			line = "[b]%s[/b]" % line
		lines.append(line)
	var r := K.rich(BB.muted(app.t("duel.log_title")) + "\n" + "\n".join(lines), true, "InkText")
	r.custom_minimum_size = Vector2(620, 0)
	return r


## С заглавной: «зверь-людоед подаётся вперёд» → «Зверь-людоед…».
static func _cap(s: String) -> String:
	return s.left(1).to_upper() + s.substr(1) if s != "" else s


static func _sound(f: Dictionary) -> void:
	if f.log.is_empty():
		return
	var e: Dictionary = f.log[-1]
	if str(e.k) == "circle":
		return
	UiSound.play("clash" if str(e.k) in ["clash", "beat_guard"] else "blow")

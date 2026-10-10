class_name EventWindow
extends RefCounted
## Окно события (как в CK3): заголовок, «сцена» с участниками на фоне цвета
## темы, текст на пергаменте и варианты ответа с подсказкой последствий.

const LETTERS := "abcdefghij"


static func _scene(app: App, theme_color: Color, icon_name: Variant, people: Array) -> Control:
	var scene := EventScene.new()
	scene.color = theme_color
	scene.icon_name = Icons.resolve(icon_name)
	scene.custom_minimum_size = Vector2(0, 190)
	var row := K.hbox([], 18, BoxContainer.ALIGNMENT_CENTER)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in people:
		var cap := K.label(Chars.full_name(app.game, c, false), "SmallLabel")
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_color_override("font_color", UiArt.C_TEXT)
		var col := K.vbox([W.portrait(app, c, 112, {"clickable": false}), cap], 2)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
	scene.add_child(row)
	return scene


static func _frame(title: String, scene: Control, text: String, options: Array) -> Control:
	var head := K.label(title, "TitleLabel")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_size_override("font_size", 30)
	var desc := K.rich(text, true, "InkText")
	desc.custom_minimum_size = Vector2(580, 0)
	var opts := K.vbox(options, 6)
	var parchment := K.panel(K.vbox([desc, K.spacer(0, 6), opts], 8), "ParchmentPanel")
	var body := K.vbox([K.panel(head, "HeaderPanel"), scene, parchment], 8)
	body.custom_minimum_size = Vector2(660, 0)
	return K.panel(body)


## Окно события с вариантами.
static func build(app: App, pe: Dictionary, on_close: Callable) -> Control:
	var g := app.game
	var def: Variant = g.content.get_def("events", pe.event)
	if def == null:
		g.state.pending_events = g.state.pending_events.filter(func(p): return p.uid != pe.uid)
		on_close.call_deferred()
		return Control.new()
	var ctx := g.events.context_for(pe)
	var theme: Variant = g.content.get_def("event_themes", def.get("theme", "default"))
	if theme == null:
		theme = g.content.get_def("event_themes", "default")
	var title := g.text(def.get("title", "ev.%s.t" % def.id), ctx)
	var desc_raw: Variant = def.get("desc", "ev.%s.desc" % def.id)
	if desc_raw is Array:
		var hit: Variant = null
		for d in desc_raw:
			if d is Dictionary and Interp.eval_trigger(ctx, ctx.root, d.get("trigger")):
				hit = d
				break
		desc_raw = hit.get("desc", "") if hit != null else ""
	var desc := g.text(desc_raw, ctx)
	var people := []
	var target: Variant = g.ch(pe.target.id) if pe.target.get("type") == "character" else null
	if target != null:
		people.append(target)
	for k in pe.scopes:
		var r: Variant = pe.scopes[k]
		if r is Dictionary and r.get("type") == "character" and r.id != pe.target.id and g.ch(r.id) != null:
			var cc: Variant = g.ch(r.id)
			if not people.has(cc):
				people.append(cc)
		if people.size() >= 3:
			break
	var theme_color := Color(theme.get("color", "#8a6d3b")) if theme != null else Color("#8a6d3b")
	var scene := _scene(app, theme_color, def.get("icon", theme.get("icon") if theme != null else "scroll"), people)
	var options := []
	var visible: Array = g.events.visible_options(def, ctx, pe.target, true)
	for item in visible:
		var opt: Dictionary = item.opt
		var index: int = item.index
		var label := g.text(opt.get("name", "ev.%s.%s" % [def.id, LETTERS[index]]), ctx)
		var voice := _voice_label(app, opt, pe.target, item.locked)
		if voice != "":
			label = voice + " " + label
		var b := _option(label, func():
			g.events.choose(pe.uid, index)
			on_close.call()
			app.mark_dirty(true), func():
			var c2 := ScriptContext.make(g, pe.target, pe.scopes)
			var lines: Array = Interp.describe_effect(c2, pe.target, opt.get("effect"))
			var extra := BB.i(g.text(opt.tooltip, c2)) + "\n" if opt.get("tooltip") != null else ""
			var bb := extra + BB.desc_lines(lines) if not lines.is_empty() or extra != "" else ""
			if item.locked:
				bb = BB.bad(_voice_need(app, opt)) + ("\n" + bb if bb != "" else "")
			# проверка навыка: что будет при успехе и при неудаче
			if g.events.check_chance(opt, pe.target) >= 0:
				var ls := Interp.describe_effect(c2, pe.target, opt.get("success"))
				var lf := Interp.describe_effect(c2, pe.target, opt.get("failure"))
				if not ls.is_empty():
					bb += ("\n" if bb != "" else "") + BB.good(app.t("ui.check_success")) + "\n" + BB.desc_lines(ls)
				if not lf.is_empty():
					bb += ("\n" if bb != "" else "") + BB.bad(app.t("ui.check_failure")) + "\n" + BB.desc_lines(lf)
			return bb)
		if item.locked:
			b.disabled = true
		options.append(b)
	if visible.filter(func(x): return not x.locked).is_empty():
		options.append(_option("OK", func():
			g.events.choose(pe.uid, -1)
			on_close.call(), null))
	return _frame(title, scene, BB.esc(desc), options)


## Метка «голоса навыка»: [Учёность], [Интриги: 65%], [Третейский судья].
static func _voice_label(app: App, opt: Dictionary, target: Dictionary, locked: bool = false) -> String:
	var g := app.game
	var sp: Variant = GameEvents.skill_spec(opt)
	if sp == null:
		return ""
	if sp.get("archetype") != null:
		return "[%s]" % g.name_of("skill_archetypes", sp.archetype)
	var sname := g.name_of("skills", str(sp.get("skill")))
	var ch := g.events.check_chance(opt, target)
	if ch >= 0:
		return "[%s: %d%%]" % [sname, ch]
	if locked and sp.get("min") != null:
		return "[%s %d]" % [sname, int(Data.num(sp.min))]
	return "[%s]" % sname


static func _voice_need(app: App, opt: Dictionary) -> String:
	var g := app.game
	var sp: Variant = GameEvents.skill_spec(opt)
	if sp == null:
		return ""
	if sp.get("archetype") != null:
		return app.t("ui.voice_needs_archetype", {"name": g.name_of("skill_archetypes", sp.archetype)})
	return app.t("ui.voice_needs_skill", {"skill": g.name_of("skills", str(sp.get("skill"))), "min": int(Data.num(sp.get("min")))})


static func _option(label: String, cb: Callable, tip_content: Variant) -> Button:
	var b := K.button(label, cb, {"variation": "EventOption", "align": HORIZONTAL_ALIGNMENT_LEFT, "min_h": 38})
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if tip_content != null:
		K.tip(b, tip_content)
	return b


## Предложение от ИИ игроку (брак, вассалитет…).
static func build_request(app: App, rq: Dictionary, on_close: Callable) -> Control:
	var g := app.game
	var def: Variant = g.content.get_def("interactions", rq.interaction)
	var actor: Variant = g.ch(rq.actor)
	var recipient: Variant = g.ch(rq.recipient)
	if def == null or actor == null or recipient == null:
		Interactions.resolve_request(g, rq.uid, false)
		on_close.call_deferred()
		return Control.new()
	var ctx := Interactions.context(g, def, actor, recipient, {"secondary": rq.get("secondary"), "target": rq.get("target")})
	var lines: Array = Interp.describe_effect(ctx, ctx.root, def.get("on_accept"))
	var people := [actor]
	if rq.get("secondary") != null and g.ch(rq.secondary) != null:
		people.append(g.ch(rq.secondary))
	people.append(recipient)
	var scene := _scene(app, Color("#6a5a2a"), def.get("icon", "scroll"), people)
	var text := BB.esc(app.t("ui.request_text", {"who": app.ranked_name(actor.id), "what": g.name_of("interactions", def.id)}))
	if not lines.is_empty():
		text += "\n\n" + BB.desc_lines(lines)
	var options := [
		_option(app.t("ui.accept"), func():
			Interactions.resolve_request(g, rq.uid, true)
			on_close.call()
			app.mark_dirty(true), null),
		_option(app.t("ui.decline"), func():
			Interactions.resolve_request(g, rq.uid, false)
			on_close.call()
			app.mark_dirty(true), null),
	]
	return _frame(g.name_of("interactions", def.id), scene, text, options)


## Фон сцены события: градиент цвета темы, крупная полупрозрачная иконка.
class EventScene:
	extends Control
	var color := Color("#8a6d3b")
	var icon_name := ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var top := color.darkened(0.15)
		var bottom := color.darkened(0.75)
		var steps := 24
		for i in steps:
			var y0 := size.y * i / steps
			var y1 := size.y * (i + 1) / steps
			draw_rect(Rect2(0, y0, size.x, y1 - y0 + 1), top.lerp(bottom, float(i) / steps))
		# лучи света
		var c := Vector2(size.x * 0.5, -size.y * 0.3)
		for k in 7:
			var a := -0.5 + k * 0.17
			var p1 := c + Vector2(sin(a - 0.04), cos(a - 0.04)) * size.y * 2.0
			var p2 := c + Vector2(sin(a + 0.04), cos(a + 0.04)) * size.y * 2.0
			draw_colored_polygon(PackedVector2Array([c, p1, p2]), Color(1, 0.95, 0.8, 0.035))
		if icon_name != "":
			var tex := Icons.texture(icon_name, 160)
			draw_texture_rect(tex, Rect2(size.x - 190, size.y * 0.5 - 80, 160, 160), false, Color(1, 1, 1, 0.12))
			draw_texture_rect(tex, Rect2(30, size.y * 0.5 - 80, 160, 160), false, Color(1, 1, 1, 0.07))
		draw_rect(r, Color(0, 0, 0, 0.6), false, 2.0)
		draw_rect(Rect2(0, size.y - 30, size.x, 30), Color(0, 0, 0, 0.18))

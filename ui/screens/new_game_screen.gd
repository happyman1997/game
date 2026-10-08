class_name NewGameScreen
extends RefCounted
## Новая игра: выбор эпохи (закладки) и персонажа. Персонажи показаны
## портретами с гербами, как в CK3; можно выбрать любого на карте.


static func _rank(t: String) -> int:
	if t.begins_with("e_"):
		return 4
	if t.begins_with("k_"):
		return 3
	if t.begins_with("d_"):
		return 2
	return 1


static func open(app: App) -> void:
	var e := app.engine
	var bms := e.bookmarks()
	var state := {"index": 0}
	var body := K.hbox([], 14)
	var panel := K.panel(K.margin(body, 6))
	panel.custom_minimum_size = Vector2(1060, 620)
	var close_ref := [Callable()]
	var render_ref := [Callable()]
	var render := func() -> void:
		K.clear(body)
		# слева — список эпох
		var left := K.vbox([K.label(app.t("ui.choose_bookmark"), "HeaderLabel")], 8)
		left.custom_minimum_size.x = 300
		for i in bms.size():
			var b: Dictionary = bms[i]
			var name := e.loc.resolve(b.get("name", "bookmark." + b.id))
			var year := int(GameDate.parse(b.date) / 365)
			var idx := i
			var btn := K.button("", func():
				state.index = idx
				render_ref[0].call(), {"variation": "FlatButton", "toggled": state.index == i, "min_h": 64})
			var inner := K.hbox([K.label(str(year), "TitleLabel"), K.label(name, "SubheaderLabel")], 12)
			inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
			inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(inner)
			left.add_child(btn)
		if bms.is_empty():
			left.add_child(K.label(app.t("ui.no_bookmarks"), "BadLabel"))
		left.add_child(K.expand())
		body.add_child(left)
		var vsep := VSeparator.new()
		body.add_child(vsep)
		# справа — описание и персонажи
		var right := K.vbox([], 10)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(right)
		if bms.is_empty():
			return
		var bm: Dictionary = bms[state.index]
		right.add_child(K.label(e.loc.resolve(bm.get("name", "bookmark." + bm.id)), "TitleLabel"))
		right.add_child(K.para(e.loc.resolve(bm.get("desc", "bookmark_desc." + bm.id)), "MutedLabel"))
		right.add_child(K.sep())
		var preview := e.new_game(bm.id, 1)
		var prev_app_game := app.game
		app.game = preview
		var grid := K.grid(3, [], 10, 10)
		var holders: Dictionary = bm.get("holders", {}) if bm.get("holders") is Dictionary else {}
		for id in Data.as_array(bm.get("playable")):
			var c: Variant = preview.ch(id)
			if c == null:
				continue
			var titles := []
			for tt in holders:
				if holders[tt] == id:
					titles.append(tt)
			titles.sort_custom(func(a, z): return _rank(a) > _rank(z))
			var main_title: Variant = titles[0] if not titles.is_empty() else (c.titles[0] if not c.titles.is_empty() else null)
			var cid: String = id
			var card := K.button("", func():
				close_ref[0].call()
				app.start_new_game(bm.id, cid), {"variation": "FlatButton", "min_h": 96})
			card.custom_minimum_size.x = 230
			var info := K.vbox([K.label(Chars.full_name(preview, c, false), "SubheaderLabel")], 0)
			if main_title != null:
				info.add_child(K.para(Titles.full_name(preview, main_title), "SmallLabel"))
			info.add_child(K.label(app.t("ui.age_n", {"n": Chars.age_of(preview, c)}), "SmallLabel"))
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var inner := K.hbox([W.portrait(app, c, 64, {"clickable": false, "tip": null}), info], 8)
			if main_title != null:
				var coa := K.tex(Coa.of_title(preview, main_title, 30), Vector2(30, 34))
				inner.add_child(coa)
			inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
			inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for ch in inner.get_children():
				ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(inner)
			grid.add_child(card)
		app.game = prev_app_game
		right.add_child(K.scroll(grid))
		right.add_child(K.hbox([
			K.button(app.t("ui.pick_on_map"), func():
				close_ref[0].call()
				app.start_new_game(bm.id), {"icon": "map", "min_w": 220}),
			K.expand(),
			K.button(app.t("ui.cancel"), func(): close_ref[0].call(), {"min_w": 140}),
		], 10))
	render_ref[0] = render
	render.call()
	close_ref[0] = app.modal(panel)

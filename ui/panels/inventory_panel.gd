class_name InventoryPanel
extends RefCounted
## Инвентарь (как в CK3): личное снаряжение — шлем, регалия, доспех, оружие,
## безделушки; убранство двора правителя — трон, стены, постаменты;
## хранилище; карточка выбранной вещи (модификаторы, прочность, история,
## притязания) с действиями — надеть, снять, починить, переплавить; заказ
## мастеру; притязания на чужие вещи.

const CELL := 76

## Выбранная вещь (id) — общая для окна, чтобы пережить перерисовку.
static var selected := ""


static func _color(g: Game, it: Variant) -> Color:
	if it == null:
		return Color(UiArt.BRONZE, 0.45)
	return Color(str(Artifacts.rarity_def(g, it.rarity).get("color", "#c9c3b4")))


## Подсказка вещи: имя цветом редкости, тип и редкость, модификаторы,
## прочность, ценность, притязания, недавняя история.
static func item_tip(app: App, iid: String) -> String:
	var g := app.game
	var it: Variant = Artifacts.item(g, iid)
	if it == null:
		return ""
	var col := _color(g, it).to_html(false)
	var bb := "[b][color=#%s]%s[/color][/b]" % [col, BB.esc(Artifacts.name_of(g, it))]
	bb += "\n" + BB.muted(app.t("ui.inv_type_rarity", {"type": g.name_of("artifact_types", it.get("type")) if it.get("type") != null else g.name_of("artifact_slots", Artifacts.slot_of(g, it)),
		"rarity": g.name_of("artifact_rarities", it.rarity)}))
	if Artifacts.is_unique(it):
		var desc := g.desc_of("artifacts", str(it.def))
		if desc != "":
			bb += "\n" + BB.i(desc)
	var mods := Artifacts.modifiers_of(g, it)
	if not mods.is_empty():
		bb += "\n" + BB.muted(app.t("ui.inv_equipped_mods" if it.get("slot") != null else "ui.inv_stored_mods")) + "\n" + BB.modifiers(g, mods)
	if Artifacts.indestructible(g, it):
		bb += "\n" + BB.good(app.t("ui.inv_indestructible"))
	else:
		var pct := roundi(Artifacts.durability_frac(it) * 100.0)
		var line := app.t("ui.inv_durability", {"n": pct})
		bb += "\n" + (BB.bad(line) if pct < 30 else BB.muted(line))
	bb += "\n" + BB.muted(app.t("ui.inv_value", {"n": roundi(Artifacts.value_of(g, it))}))
	var house: Variant = it.get("house")
	if house != null:
		bb += "\n" + BB.gold(app.t("ui.inv_house_claim", {"name": g.name_of("dynasties", house)}))
	var claims: Array = Data.as_array(it.get("claims")).filter(func(x): return g.is_alive(x))
	if not claims.is_empty():
		bb += "\n" + BB.warn(app.t("ui.inv_claims") + ": " + ", ".join(claims.map(func(x): return g.scope_name({"type": "character", "id": x}))))
	return bb


static func _hist_line(app: App, h: Array) -> String:
	var g := app.game
	var who := func(id: Variant) -> String:
		return g.scope_name({"type": "character", "id": id}) if id != null and g.ch(id) != null else "—"
	var text := g.loc.t_or("inv_hist." + str(h[1]), str(h[1]))
	text = text.format({"from": who.call(h[2]), "to": who.call(h[3])})
	var d := GameDate.parts(int(h[0]))
	return "%d — %s" % [d.y, text]


## Ячейка слота или вещи: рамка цвета редкости, иконка, полоска прочности.
static func cell(app: App, it: Variant, slot_icon: Variant = null, on_click: Callable = Callable()) -> Control:
	var g := app.game
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL, CELL)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if it != null else Control.CURSOR_ARROW
	var col := _color(g, it)
	var sel: bool = it != null and selected == it.id
	var bg := Color("#1a140d") if it != null else Color("#151009")
	b.add_theme_stylebox_override("normal", UiArt.flat(bg, col if not sel else Color("#fff2c0"), 3 if sel else 2, 5))
	b.add_theme_stylebox_override("hover", UiArt.flat(bg.lightened(0.08), col.lightened(0.25), 3 if sel else 2, 5))
	b.add_theme_stylebox_override("pressed", UiArt.flat(bg.darkened(0.1), col, 3, 5))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(center)
	if it != null:
		var ic := Icons.node(Artifacts.icon_of(g, it), 46)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(ic)
		if not Artifacts.indestructible(g, it):
			var frac := Artifacts.durability_frac(it)
			var bar := ColorRect.new()
			bar.color = Color("#5aa050") if frac >= 0.5 else (Color("#d0a040") if frac >= 0.3 else Color("#d04a3a"))
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.position = Vector2(6, CELL - 9)
			bar.size = Vector2((CELL - 12) * frac, 4)
			b.add_child(bar)
		if Artifacts.is_unique(it):
			var star := Icons.node("star", 14)
			star.mouse_filter = Control.MOUSE_FILTER_IGNORE
			star.position = Vector2(CELL - 19, 4)
			b.add_child(star)
		var iid: String = it.id
		K.tip(b, func(): return item_tip(app, iid))
	elif slot_icon != null:
		var ic := Icons.node(slot_icon, 34, "ink")
		ic.modulate = Color(1, 1, 1, 0.55)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(ic)
	if on_click.is_valid():
		b.pressed.connect(on_click)
	return b


## Ячейки слотов группы (personal / court) с подписями; skip — слоты,
## уже показанные на фигуре или в зале (остаются слоты из модов).
static func _slot_row(app: App, c: Dictionary, group: String, skip: Array = []) -> Control:
	var g := app.game
	var row := K.flow([], 8)
	for sd in Artifacts.slots(g, group):
		var sid: String = sd.id
		if skip.has(sid):
			continue
		var cap := Artifacts.slot_capacity(g, c, sid)
		var items := Artifacts.in_slot(g, c, sid)
		for i in cap:
			var it: Variant = items[i] if i < items.size() else null
			var cb := Callable()
			if it != null:
				var iid: String = it.id
				cb = func(): open_detail(app, iid)
			var cl := cell(app, it, sd.get("icon", "star"), cb)
			if it == null:
				K.tip(cl, BB.muted(app.t("ui.inv_empty_slot", {"slot": g.name_of("artifact_slots", sid)})))
			var lbl := K.label(g.name_of("artifact_slots", sid), "SmallLabel")
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.custom_minimum_size.x = CELL
			lbl.clip_text = true
			row.add_child(K.vbox([cl, lbl], 2))
	return row


# ------------------------------------------------------------ на человеке

const DOLL_W := 560
const DOLL_H := 400
const FIG_W := 240
const FIG_POS := Vector2(160, 8)
## Ячейки вокруг фигуры (левый верхний угол): слева — шлем, доспех, оружие;
## справа — регалия и безделушки.
const DOLL_SPOTS := {
	"helmet": [Vector2(36, 12)], "armor": [Vector2(36, 140)], "weapon": [Vector2(36, 268)],
	"regalia": [Vector2(448, 12)], "trinket": [Vector2(448, 112), Vector2(448, 212), Vector2(448, 312)],
}


## Линии от ячеек к частям тела.
class Connectors extends Control:
	var segs: Array = []

	func _draw() -> void:
		for sg in segs:
			var a: Vector2 = sg[0]
			var b: Vector2 = sg[1]
			var col: Color = sg[2]
			var mid := Vector2(lerpf(a.x, b.x, 0.45), a.y)
			draw_polyline(PackedVector2Array([a, mid, b]), col, 1.6, true)
			draw_circle(b, 3.2, col)
			draw_circle(b, 1.4, Color(1, 1, 1, col.a))


static func _centered(child: Control) -> Control:
	var cc := CenterContainer.new()
	cc.add_child(child)
	return cc


static func _anchor_for(g: Game, slot: String, it: Variant) -> Vector2:
	var key := slot
	if it != null:
		var t := str(it.get("type", ""))
		if slot == "regalia" and t == "scepter":
			key = "scepter"
		elif slot == "trinket" and PaperDoll.ANCHORS.has(t):
			key = t
	var a: Vector2 = PaperDoll.ANCHORS.get(key, PaperDoll.ANCHORS.trinket)
	var k := FIG_W / float(PaperDoll.W)
	return FIG_POS + a * k


## Фигура персонажа в полный рост с надетыми вещами и ячейки вокруг.
static func _doll(app: App, c: Dictionary) -> Control:
	var g := app.game
	var root := Control.new()
	root.custom_minimum_size = Vector2(DOLL_W, DOLL_H)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	var fig := K.tex(PaperDoll.figure_texture(g, c, FIG_W), Vector2(FIG_W, FIG_W * PaperDoll.H / float(PaperDoll.W)))
	fig.position = FIG_POS
	fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fig)
	var frame := Panel.new()
	frame.position = FIG_POS - Vector2(3, 3)
	frame.size = fig.custom_minimum_size + Vector2(6, 6)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UiArt.flat(Color(0, 0, 0, 0), Color(UiArt.BRONZE, 0.9), 2, 4))
	root.add_child(frame)
	var lines := Connectors.new()
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines.size = root.custom_minimum_size
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lines)
	for sid in DOLL_SPOTS:
		var sd: Variant = Artifacts.slot_def(g, sid)
		if sd == null:
			continue
		var cap := Artifacts.slot_capacity(g, c, sid)
		var items := Artifacts.in_slot(g, c, sid)
		var spots: Array = DOLL_SPOTS[sid]
		for i in mini(cap, spots.size()):
			var it: Variant = items[i] if i < items.size() else null
			var pos: Vector2 = spots[i]
			var cb := Callable()
			if it != null:
				var iid: String = it.id
				cb = func(): open_detail(app, iid)
			var cl := cell(app, it, sd.get("icon", "star"), cb)
			cl.position = pos
			if it == null:
				K.tip(cl, BB.muted(app.t("ui.inv_empty_slot", {"slot": g.name_of("artifact_slots", sid)})))
			root.add_child(cl)
			if it != null:
				var left := pos.x < FIG_POS.x
				var from := Vector2(pos.x + CELL if left else pos.x, pos.y + CELL / 2.0)
				var col := _color(g, it)
				col.a = 0.8
				lines.segs.append([from, _anchor_for(g, sid, it), col])
	lines.queue_redraw()
	return root


## Тронный зал: трон, стены, постаменты — вещи на своих местах.
const HALL_HOT := {
	"throne": [Rect2(214, 36, 92, 120)],
	"wall": [Rect2(46, 20, 92, 108), Rect2(382, 20, 92, 108)],
	"pedestal": [Rect2(146, 132, 52, 56), Rect2(322, 132, 52, 56)],
}


static func _hall(app: App, c: Dictionary) -> Control:
	var g := app.game
	var root := Control.new()
	root.custom_minimum_size = Vector2(PaperDoll.HALL_W, PaperDoll.HALL_H)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := K.tex(PaperDoll.hall_texture(g, c, PaperDoll.HALL_W), root.custom_minimum_size)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	for sid in HALL_HOT:
		var sd: Variant = Artifacts.slot_def(g, sid)
		if sd == null:
			continue
		var items := Artifacts.in_slot(g, c, sid)
		var rects: Array = HALL_HOT[sid]
		for i in mini(Artifacts.slot_capacity(g, c, sid), rects.size()):
			var it: Variant = items[i] if i < items.size() else null
			var r: Rect2 = rects[i]
			var b := Button.new()
			b.position = r.position
			b.custom_minimum_size = r.size
			b.size = r.size
			b.focus_mode = Control.FOCUS_NONE
			var col := _color(g, it)
			b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			b.add_theme_stylebox_override("hover", UiArt.flat(Color(1, 0.9, 0.6, 0.08), col, 2, 6))
			b.add_theme_stylebox_override("pressed", UiArt.flat(Color(1, 0.9, 0.6, 0.12), col, 2, 6))
			if it != null:
				var iid: String = it.id
				b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				b.pressed.connect(func(): open_detail(app, iid))
				K.tip(b, func(): return item_tip(app, iid))
				# на постаменте вещь стоит сама — рисуем её иконку
				if sid == "pedestal":
					var ic := Icons.node(Artifacts.icon_of(g, it), 42)
					ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
					ic.position = Vector2((r.size.x - 42) / 2.0, r.size.y - 46)
					b.add_child(ic)
			else:
				K.tip(b, BB.muted(app.t("ui.inv_empty_slot", {"slot": g.name_of("artifact_slots", sid)})))
			root.add_child(b)
	return root


static func build(app: App, c: Dictionary) -> Control:
	var g := app.game
	var p: Variant = g.player
	var is_me: bool = p != null and p.id == c.id
	var root := K.vbox([], 10)
	if not g.engine.has_feature("artifacts"):
		return root
	var items := Artifacts.items_of(g, c)
	# снаряжение — на самом человеке
	var eq_children: Array = [_centered(_doll(app, c))]
	var extra := _slot_row(app, c, "personal", DOLL_SPOTS.keys())
	if extra.get_child_count() > 0:
		eq_children.append(extra)
	root.add_child(K.section(app.t("ui.inv_equipment"), eq_children, "helm"))
	# убранство двора — тронный зал
	if not c.titles.is_empty():
		var court_children: Array = [_centered(_hall(app, c))]
		var cextra := _slot_row(app, c, "court", PaperDoll.HALL_SPOTS.keys())
		if cextra.get_child_count() > 0:
			court_children.append(cextra)
		var court := K.section(app.t("ui.inv_court"), court_children, "throne")
		K.tip(court.get_child(0), BB.title(app.t("ui.inv_court")) + "\n" + BB.i(app.t("ui.inv_court_tip")))
		root.add_child(court)
	if not items.is_empty():
		root.add_child(K.label(app.t("ui.inv_select_hint"), "MutedLabel"))
	# хранилище
	var store := Artifacts.storage(g, c)
	store.sort_custom(func(a, b): return Artifacts.score(g, a) > Artifacts.score(g, b))
	var sflow := K.flow([], 8)
	for it in store:
		var iid: String = it.id
		sflow.add_child(cell(app, it, null, func(): open_detail(app, iid)))
	var scont: Array = [sflow] if not store.is_empty() else [K.label(app.t("ui.inv_storage_empty"), "MutedLabel")]
	root.add_child(K.section("%s (%d)" % [app.t("ui.inv_storage"), store.size()], scont, "bag"))
	# заказ мастеру
	if is_me:
		root.add_child(_commission_block(app, c))
	# притязания: свои на чужое и чужие на своё
	if p != null:
		var cl: Variant = _claims_block(app, c, is_me)
		if cl != null:
			root.add_child(cl)
	return root


## Окно вещи (по клику): карточка с действиями; закрывается, если вещи
## больше нет у владельца.
static func open_detail(app: App, iid: String) -> void:
	selected = iid
	app.mark_dirty(true)
	var close_ref := [Callable()]
	var holder := K.vbox([], 10)
	holder.custom_minimum_size.x = 520
	var render := [Callable()]
	render[0] = func():
		K.clear(holder)
		var it: Variant = Artifacts.item(app.game, iid)
		var owner: Variant = app.game.ch(it.owner) if it != null and it.get("owner") != null else null
		if owner == null:
			if close_ref[0].is_valid():
				close_ref[0].call()
			return
		holder.add_child(detail(app, owner, it, func():
			render[0].call()
			app.mark_dirty(true)))
		holder.add_child(K.hbox([K.expand(), K.button(app.t("ui.close"), func(): close_ref[0].call(), {"min_w": 140}), K.expand()]))
	render[0].call()
	close_ref[0] = app.modal(K.panel(K.margin(holder, 12)), {"on_close": func():
		selected = ""
		app.mark_dirty(true)})


## Карточка вещи: модификаторы, прочность, история и действия.
static func detail(app: App, c: Dictionary, it: Dictionary, on_change: Callable = Callable()) -> Control:
	var g := app.game
	var p: Variant = g.player
	var is_me: bool = p != null and p.id == c.id
	var iid: String = it.id
	var col := _color(g, it)
	var box := K.vbox([], 6)
	var name := K.label(Artifacts.name_of(g, it), "SubheaderLabel")
	name.add_theme_color_override("font_color", col)
	var sub := K.label(app.t("ui.inv_type_rarity", {"type": g.name_of("artifact_types", it.get("type")) if it.get("type") != null else g.name_of("artifact_slots", Artifacts.slot_of(g, it)),
		"rarity": g.name_of("artifact_rarities", it.rarity)}) + ("  ·  " + app.t("ui.inv_unique") if Artifacts.is_unique(it) else ""), "MutedLabel")
	box.add_child(K.hbox([Icons.node(Artifacts.icon_of(g, it), 40), K.vbox([name, sub], 0)], 10))
	if Artifacts.is_unique(it):
		var desc := g.desc_of("artifacts", str(it.def))
		if desc != "":
			box.add_child(K.para(desc, "MutedLabel"))
	var mods := Artifacts.modifiers_of(g, it)
	if not mods.is_empty():
		box.add_child(K.rich(BB.muted(app.t("ui.inv_equipped_mods" if it.get("slot") != null else "ui.inv_stored_mods")) + "\n" + BB.modifiers(g, mods)))
	# прочность и ремонт
	if Artifacts.indestructible(g, it):
		box.add_child(K.label(app.t("ui.inv_indestructible"), "GoodLabel"))
	else:
		var frac := Artifacts.durability_frac(it)
		var bar := K.bar(frac * 100.0, 100.0, Color("#5a8a40") if frac >= 0.3 else Color("#a83a30"), 20, app.t("ui.inv_durability", {"n": roundi(frac * 100.0)}))
		K.tip(bar, BB.title(app.t("ui.inv_durability", {"n": roundi(frac * 100.0)})) + "\n" + BB.i(app.t("ui.inv_durability_tip")))
		var row := K.hbox([bar], 8)
		if is_me and frac < 0.999:
			var cost := Artifacts.repair_cost(g, it)
			var rb := K.button(app.t("ui.inv_repair"), func():
				var x: Variant = Artifacts.item(app.game, iid)
				if x != null:
					Artifacts.repair(app.game, app.game.player, x)
				_changed(app, on_change), {"icon": "hammer", "disabled": float(c.gold) < cost, "min_w": 130})
			K.tip(rb, BB.title(app.t("ui.inv_repair")) + "\n" + BB.cost(g, {"gold": cost}))
			row.add_child(rb)
		box.add_child(row)
	# действия
	if is_me:
		var acts := K.flow([], 6)
		var court := str(Artifacts.slot_def(g, Artifacts.slot_of(g, it)).get("group", "personal")) == "court" if Artifacts.slot_def(g, Artifacts.slot_of(g, it)) != null else false
		if it.get("slot") != null:
			acts.add_child(K.button(app.t("ui.inv_remove" if court else "ui.inv_unequip"), func():
				var x: Variant = Artifacts.item(app.game, iid)
				if x != null:
					Artifacts.unequip(app.game, app.game.player, x)
				_changed(app, on_change), {"icon": "minus", "min_w": 120}))
		elif Artifacts.can_equip(g, c, it):
			acts.add_child(K.button(app.t("ui.inv_place" if court else "ui.inv_equip"), func():
				var x: Variant = Artifacts.item(app.game, iid)
				if x != null:
					Artifacts.equip(app.game, app.game.player, x)
				_changed(app, on_change), {"icon": "plus", "variation": "GoldButton", "min_w": 120}))
		if not Artifacts.is_unique(it):
			var mv := Artifacts.melt_value(g, it)
			var mb := K.button(app.t("ui.inv_melt"), func(): _confirm_melt(app, iid, on_change), {"icon": "fire", "min_w": 120})
			K.tip(mb, BB.title(app.t("ui.inv_melt")) + "\n" + BB.bad(app.t("ui.inv_melt_tip", {"n": roundi(mv)})))
			acts.add_child(mb)
		box.add_child(acts)
	# история и притязания
	var hist: Array = Data.as_array(it.get("history"))
	if not hist.is_empty():
		var lines := []
		for i in range(hist.size() - 1, maxi(-1, hist.size() - 6), -1):
			lines.append(BB.muted("• ") + BB.esc(_hist_line(app, hist[i])))
		box.add_child(K.rich(BB.gold(app.t("ui.inv_history")) + "\n" + "\n".join(lines)))
	var claims: Array = Data.as_array(it.get("claims")).filter(func(x): return g.is_alive(x))
	if it.get("house") != null:
		box.add_child(K.rich(BB.gold(app.t("ui.inv_house_claim", {"name": g.name_of("dynasties", it.house)}))))
	if not claims.is_empty():
		box.add_child(K.rich(BB.warn(app.t("ui.inv_claims") + ": ") + BB.esc(", ".join(claims.map(func(x): return g.scope_name({"type": "character", "id": x}))))))
	var panel := K.panel(K.margin(box, 12, 10), "RowPanel")
	panel.add_theme_stylebox_override("panel", UiArt.flat(Color("#1d1710"), col, 2, 6, 0))
	return panel


static func _changed(app: App, on_change: Callable) -> void:
	if on_change.is_valid():
		on_change.call()
	else:
		app.mark_dirty(true)


static func _confirm_melt(app: App, iid: String, on_change: Callable = Callable()) -> void:
	var g := app.game
	var it: Variant = Artifacts.item(g, iid)
	if it == null:
		return
	var close_ref := [Callable()]
	var body := K.vbox([
		K.label(app.t("ui.inv_melt"), "HeaderLabel"),
		K.para(app.t("ui.inv_melt_tip", {"n": roundi(Artifacts.melt_value(g, it))}), ""),
		K.rich(item_tip(app, iid)),
		K.hbox([K.expand(), K.button(app.t("ui.inv_melt"), func():
			var x: Variant = Artifacts.item(app.game, iid)
			if x != null:
				Artifacts.melt(app.game, app.game.player, x)
			close_ref[0].call()
			_changed(app, on_change), {"variation": "GoldButton", "icon": "fire", "min_w": 140}),
			K.button(app.t("ui.cancel"), func(): close_ref[0].call(), {"min_w": 120}), K.expand()], 10),
	], 10)
	body.custom_minimum_size.x = 460
	close_ref[0] = app.modal(K.panel(K.margin(body, 14)))


## Заказ мастеру: идущий заказ или кнопка.
static func _commission_block(app: App, c: Dictionary) -> Control:
	var g := app.game
	var o: Variant = Artifacts.commission_of(c)
	var box := K.vbox([], 6)
	if o != null:
		var total := maxf(1.0, float(int(o.done) - int(o.start)))
		var done := clampf(float(g.date - int(o.start)), 0.0, total)
		box.add_child(K.label(app.t("ui.inv_commission_in_progress", {"type": g.name_of("artifact_types", o.type), "tier": g.name_of("commission_tiers", o.tier),
			"date": CharacterPanel.fmt_date(app, int(o.done))}), ""))
		box.add_child(K.bar(done, total, Color("#b8913f"), 12))
	else:
		var b := K.button(app.t("ui.inv_commission"), func(): open_commission(app), {"icon": "hammer", "variation": "GoldButton", "min_w": 220})
		K.tip(b, BB.title(app.t("ui.inv_commission")) + "\n" + BB.i(app.t("ui.inv_commission_tip")))
		box.add_child(b)
	return K.section(app.t("ui.inv_commission"), [box], "hammer")


## Притязания: вещи, которые вы можете потребовать, и ваши, на которые
## притязают другие.
static func _claims_block(app: App, c: Dictionary, is_me: bool) -> Variant:
	var g := app.game
	var p: Dictionary = g.player
	var rows := K.vbox([], 4)
	if is_me:
		for it in Artifacts.claims_of(g, p):
			var holder: Variant = g.ch(it.owner)
			if holder == null:
				continue
			var hid: String = holder.id
			var right := [cell_small(app, it)]
			var def: Variant = g.content.get_def("interactions", "demand_artifact")
			if def != null:
				right.append(K.button(app.t("ui.inv_demand"), func(): InteractionWindow.open(app, def, app.game.player.id, hid), {"icon": "fist"}))
			rows.add_child(W.char_row(app, holder, [Artifacts.name_of(g, it)], right, 40))
		if rows.get_child_count() > 0:
			return K.section(app.t("ui.inv_your_claims"), [rows], "fist")
		return null
	# чужой инвентарь: что из него принадлежит вам по праву
	var mine := Artifacts.claimed_from(g, p, c)
	if mine.is_empty():
		return null
	var fl := K.flow([], 6)
	for it in mine:
		fl.add_child(cell_small(app, it))
	var def: Variant = g.content.get_def("interactions", "demand_artifact")
	var cid: String = c.id
	if def != null:
		fl.add_child(K.button(app.t("ui.inv_demand"), func(): InteractionWindow.open(app, def, app.game.player.id, cid), {"icon": "fist", "variation": "GoldButton"}))
	return K.section(app.t("ui.inv_your_claims"), [fl], "fist")


static func cell_small(app: App, it: Dictionary) -> Control:
	var g := app.game
	var col := _color(g, it)
	var pc := K.panel(Icons.node(Artifacts.icon_of(g, it), 26))
	pc.add_theme_stylebox_override("panel", UiArt.flat(Color("#1a140d"), col, 2, 4, 3))
	var iid: String = it.id
	K.tip(pc, func(): return item_tip(app, iid))
	return pc


## Окно заказа: тип вещи, качество работы, шансы редкости.
static func open_commission(app: App) -> void:
	var g := app.game
	var st := {"type": "", "tier": ""}
	var tiers := Artifacts.commission_tiers(g)
	if not tiers.is_empty():
		st.tier = tiers[mini(1, tiers.size() - 1)].id
	var close_ref := [Callable()]
	var body := K.vbox([], 10)
	body.custom_minimum_size = Vector2(620, 0)
	var render_ref := [Callable()]
	render_ref[0] = func():
		K.clear(body)
		var p: Dictionary = app.game.player
		body.add_child(K.label(app.t("ui.inv_commission"), "HeaderLabel"))
		body.add_child(K.para(app.t("ui.inv_commission_tip"), "MutedLabel"))
		# типы — по слотам
		body.add_child(K.label(app.t("ui.inv_commission_type"), "SubheaderLabel"))
		var grid := K.flow([], 6)
		for t in Artifacts.commission_types(g):
			var tid: String = t.id
			var b := K.button(g.name_of("artifact_types", tid), func():
				st.type = tid
				render_ref[0].call(), {"icon": t.get("icon", "star"), "icon_size": 20, "variation": "WindowTab", "toggled": st.type == tid, "min_w": 140})
			var tip := BB.title(g.name_of("artifact_types", tid)) + "\n" + BB.muted(g.name_of("artifact_slots", str(t.get("slot", "trinket"))))
			tip += "\n" + BB.modifiers(g, t.get("modifiers"))
			K.tip(b, tip)
			grid.add_child(b)
		var sc := K.scroll(grid)
		sc.custom_minimum_size.y = 230
		body.add_child(sc)
		# качество
		body.add_child(K.label(app.t("ui.inv_commission_tier"), "SubheaderLabel"))
		var trow := K.hbox([], 6)
		for t in tiers:
			var tid: String = t.id
			var b := K.button("%s\n%s" % [g.name_of("commission_tiers", tid), app.t("ui.inv_commission_cost", {"n": roundi(Artifacts.commission_cost(g, p, tid)), "m": roundi(Data.num(t.get("months")))})], func():
				st.tier = tid
				render_ref[0].call(), {"variation": "WindowTab", "toggled": st.tier == tid, "min_w": 190, "min_h": 54})
			trow.add_child(b)
		body.add_child(trow)
		# шансы
		if st.tier != "":
			var parts := []
			var ch := Artifacts.commission_chances(g, p, st.tier)
			var total := 0.0
			for x in ch:
				total += float(x.weight)
			for x in ch:
				var col := Color(str(Artifacts.rarity_def(g, x.rarity).get("color", "#ffffff"))).to_html(false)
				parts.append("[color=#%s]%s[/color] %d%%" % [col, BB.esc(g.name_of("artifact_rarities", x.rarity)), roundi(100.0 * float(x.weight) / maxf(1.0, total))])
			body.add_child(K.rich(BB.gold(app.t("ui.inv_commission_chances") + ": ") + "  ".join(parts)))
		var blockers := Artifacts.commission_blockers(g, p, st.tier) if st.tier != "" else []
		if not blockers.is_empty():
			body.add_child(K.rich(BB.reasons(blockers)))
		var ready: bool = st.type != "" and st.tier != "" and blockers.is_empty()
		body.add_child(K.hbox([K.expand(), K.button(app.t("ui.inv_order"), func():
			if Artifacts.commission(app.game, app.game.player, st.type, st.tier):
				close_ref[0].call()
				app.mark_dirty(true), {"variation": "GoldButton", "icon": "hammer", "disabled": not ready, "min_w": 160}),
			K.button(app.t("ui.cancel"), func(): close_ref[0].call(), {"min_w": 120}), K.expand()], 10))
	render_ref[0].call()
	close_ref[0] = app.modal(K.panel(K.margin(body, 14)))

class_name TreasuryPanel
extends RefCounted
## Вкладка «Казна» окна «Держава»: сколько в казне и куда она идёт — строки
## дохода каждый месяц, доходы и траты по статьям за год (книга казны,
## Treasury), сальдо месяцев на графике и прогноз.


static func build(app: App, p: Dictionary) -> Control:
	var g := app.game
	var root := K.vbox([], 10)
	root.add_child(_summary(app, p))
	root.add_child(K.section(app.t("ui.treasury_history"), [_chart(app, p)], "scroll"))
	root.add_child(K.section(app.t("ui.treasury_monthly"), [_monthly(app, p)], "gold"))
	root.add_child(K.section(app.t("ui.treasury_oneoff"), [_year(app, p)], "bag"))
	return root


## Казна, сальдо в месяц и прогноз.
static func _summary(app: App, p: Dictionary) -> Control:
	var g := app.game
	var fc := Treasury.forecast(g, p)
	var gold := K.label(K.fmt(p.gold), "TitleLabel")
	gold.add_theme_color_override("font_color", UiArt.C_GOLD if float(p.gold) >= 0.0 else UiArt.C_BAD)
	var net := float(fc.monthly)
	var net_l := K.label(app.t("ui.treasury_monthly_net") + ": " + K.signed(net, 1), "GoodLabel" if net >= 0.0 else "BadLabel")
	var head := K.hbox([K.icon("gold", 34), gold, K.spacer(12), net_l], 8)
	var notes := K.vbox([], 2)
	if float(p.gold) < 0.0:
		notes.add_child(K.para(app.t("ui.treasury_in_debt"), "BadLabel"))
	if net < 0.0:
		var left := int(fc.months_left)
		notes.add_child(K.para(app.t("ui.treasury_empty_now") if left <= 0 else app.t("ui.treasury_runs_out", {"n": left}), "BadLabel"))
	elif net > 0.0:
		notes.add_child(K.para(app.t("ui.treasury_grows", {"value": K.signed(net, 1)}), "MutedLabel"))
	if absf(float(fc.oneoff)) >= 0.05:
		notes.add_child(K.para(app.t("ui.treasury_oneoff_avg", {"value": K.signed(float(fc.oneoff), 1)}), "MutedLabel"))
	var goal: Variant = Ai.goal_of(g, p) if p.id != g.state.player or g.autopilot else null
	if goal is Dictionary:
		notes.add_child(K.para(app.t("ui.treasury_goal", {"name": Ai.goal_name(g, goal), "cost": K.fmt(goal.cost)}), "GoldLabel"))
	return K.panel(K.vbox([head, notes], 6), "InsetPanel")


## Строки дохода, начисляемые каждый месяц.
static func _monthly(app: App, p: Dictionary) -> Control:
	var g := app.game
	var parts := Economy.income_breakdown(g, p)
	var grid := K.grid(2, [], 16, 2)
	var total := 0.0
	for part in parts:
		var v := float(part.value)
		total += v
		grid.add_child(K.expand_h(K.label(str(part.label))))
		grid.add_child(K.label(K.signed(v, 1), "GoodLabel" if v >= 0.0 else "BadLabel"))
	grid.add_child(K.expand_h(K.label(app.t("ui.treasury_monthly_net"), "GoldLabel")))
	grid.add_child(K.label(K.signed(total, 1), "GoodLabel" if total >= 0.0 else "BadLabel"))
	return grid


## Доходы и траты по статьям за последние 12 месяцев (с текущим);
## ежемесячные статьи — приглушённым цветом, разовые — обычным.
static func _year(app: App, p: Dictionary) -> Control:
	var g := app.game
	var tot := Treasury.totals(g, p, 12, true)
	var inc := []
	var exp := []
	var inc_sum := 0.0
	var exp_sum := 0.0
	for k in tot:
		var v := float(tot[k])
		if absf(v) < 0.5:
			continue
		if v > 0.0:
			inc.append([k, v])
			inc_sum += v
		else:
			exp.append([k, v])
			exp_sum += v
	if inc.is_empty() and exp.is_empty():
		return K.para(app.t("ui.treasury_oneoff_none"), "MutedLabel")
	inc.sort_custom(func(a, b): return a[1] > b[1])
	exp.sort_custom(func(a, b): return a[1] < b[1])
	var top := maxf(inc_sum, -exp_sum)
	var cols := K.hbox([_column(app, p, app.t("ui.treasury_income"), inc, top, UiArt.C_GOOD), _column(app, p, app.t("ui.treasury_expense"), exp, top, UiArt.C_BAD)], 18)
	var total := K.label(app.t("ui.treasury_year_total", {"income": K.fmt(inc_sum), "expense": K.fmt(-exp_sum)}), "MutedLabel")
	return K.vbox([cols, total], 8)


static func _column(app: App, p: Dictionary, title: String, rows: Array, top: float, col: Color) -> Control:
	var box := K.vbox([K.label(title, "SubheaderLabel")], 3)
	for r in rows:
		var name := ledger_name(app.game, str(r[0]))
		var reg := Treasury.is_regular(p, str(r[0]))
		var line := K.hbox([K.expand_h(K.label(name, "" if not reg else "MutedLabel")), K.label(K.fmt(absf(float(r[1]))), "GoodLabel" if r[1] > 0 else "BadLabel")], 8)
		box.add_child(line)
		box.add_child(K.bar(absf(float(r[1])), top, col.darkened(0.25), 4))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box


static func ledger_name(g: Game, key: String) -> String:
	return g.loc.t_or("ledger." + key, key)


## График: столбцы — сальдо месяцев, линия — казна в конце месяца.
static func _chart(app: App, p: Dictionary) -> Control:
	var g := app.game
	var ms := Treasury.months(g, p)
	ms.reverse()
	var ch := Chart.new()
	ch.months = ms
	ch.custom_minimum_size = Vector2(0, 150)
	ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# подсказки по месяцам — прозрачные колонки поверх графика
	var cols := K.hbox([], 0)
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for x in ms:
		var cell := Control.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		var month: Dictionary = x
		K.tip(cell, func(): return _month_tip(app, p, month))
		cols.add_child(cell)
	ch.add_child(cols)
	K.tip(ch, BB.muted(app.t("ui.treasury_history_tip")))
	return ch


static func month_label(g: Game, m: int) -> String:
	return "%s %d" % [g.loc.t_or("month_short.%d" % (posmod(m, 12) + 1), str(posmod(m, 12) + 1)), floori(m / 12.0)]


static func _month_tip(app: App, p: Dictionary, x: Dictionary) -> String:
	var g := app.game
	var bb := BB.title(month_label(g, int(x.m)))
	var rows := []
	var keys: Array = x.v.keys()
	keys.sort_custom(func(a, b): return absf(float(x.v[a])) > absf(float(x.v[b])))
	var net := 0.0
	for k in keys:
		var v := float(x.v[k])
		net += v
		if absf(v) >= 0.05:
			rows.append([BB.esc(ledger_name(g, str(k))), BB.good(K.signed(v, 1)) if v >= 0.0 else BB.bad(K.signed(v, 1))])
	if not rows.is_empty():
		bb += "\n" + BB.rows(rows)
	bb += "\n" + BB.b(app.t("ui.treasury_monthly_net") + ": ") + (BB.good(K.signed(net, 1)) if net >= 0.0 else BB.bad(K.signed(net, 1)))
	bb += "\n" + BB.muted(app.t("ui.treasury_now", {"gold": K.fmt(float(x.g))}))
	return bb


class Chart extends Control:
	var months: Array = []

	func _draw() -> void:
		var n := months.size()
		if n == 0:
			return
		var w := size.x
		var h := size.y - 16.0
		var nets := []
		var golds := []
		var top := 1.0
		var gmax := 1.0
		var gmin := 0.0
		for x in months:
			var net := 0.0
			for k in x.v:
				net += float(x.v[k])
			nets.append(net)
			golds.append(float(x.g))
			top = maxf(top, absf(net))
			gmax = maxf(gmax, float(x.g))
			gmin = minf(gmin, float(x.g))
		var mid := h * 0.5
		var cw := w / n
		var font := get_theme_default_font()
		draw_line(Vector2(0, mid), Vector2(w, mid), Color(UiArt.C_MUTED, 0.5), 1.0)
		for i in n:
			var v: float = nets[i]
			var bh := absf(v) / top * (mid - 6.0)
			var x0 := i * cw + cw * 0.2
			var r := Rect2(x0, mid - bh if v >= 0.0 else mid, cw * 0.6, maxf(1.0, bh))
			var col := UiArt.C_GOOD if v >= 0.0 else UiArt.C_BAD
			if months[i].get("current", false):
				col = col.darkened(0.35)
			draw_rect(r, Color(col, 0.85))
			draw_rect(r, Color(0, 0, 0, 0.35), false, 1.0)
			var lbl := TreasuryPanel.month_label(App.instance.game, int(months[i].m)).get_slice(" ", 0)
			var fs := 11
			var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(i * cw + (cw - tw) * 0.5, size.y - 2.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiArt.C_MUTED)
		# линия казны
		var pts := PackedVector2Array()
		var span := maxf(1.0, gmax - gmin)
		for i in n:
			pts.append(Vector2(i * cw + cw * 0.5, h - 4.0 - (float(golds[i]) - gmin) / span * (h - 8.0)))
		if pts.size() >= 2:
			draw_polyline(pts, Color(0, 0, 0, 0.5), 4.0, true)
			draw_polyline(pts, UiArt.C_GOLD, 2.0, true)
		for q in pts:
			draw_circle(q, 3.0, UiArt.C_GOLD)

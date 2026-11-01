class_name HostSection
extends RefCounted
## Раздел «Воинство» во вкладке армии: нынешнее воинство (стойкость, умения,
## условия, особые отряды) и какие ещё можно собрать.


## Строки умений воинства (BBCode).
static func abilities_text(app: App, d: Dictionary) -> String:
	var g := app.game
	var out := PackedStringArray()
	var ab: Variant = d.get("abilities")
	if not (ab is Dictionary):
		return ""
	for k in ab:
		var spec: Variant = ab[k]
		var v: Variant = spec.get("value") if spec is Dictionary else spec
		var n := Data.num(v) if (v is int or v is float) else 0.0
		var line := app.t("host.ab." + str(k), {"n": K.signed(n) if str(k) == "morale" else str(roundi(absf(n))), "pct": roundi(absf(n) * 100.0)})
		if spec is Dictionary:
			if spec.get("where") is Dictionary:
				line += app.t("host.where", {"terrain": ", ".join(Data.as_array(spec.where.get("terrain")).map(func(t): return g.name_of("terrains", t)))})
			if spec.get("enemy") != null:
				line += app.t("host.enemy")
			if spec.get("when") != null:
				line += app.t("host.when")
		out.append("• " + BB.esc(line))
	return "\n".join(out)


## Условия стойкости: правила keep и события on.
static func keep_text(app: App, d: Dictionary, c: Variant = null) -> String:
	var g := app.game
	var out := PackedStringArray()
	var now := {}
	if c is Dictionary:
		for p in Hosts.keep_parts(g, c, d):
			now[p.key] = true
	for rule in Data.as_array(d.get("keep")):
		if not (rule is Dictionary):
			continue
		var key := str(rule.get("key", ""))
		var txt := g.loc.t_or("host_rule.%s.%s" % [d.id, key], key)
		var v := Data.num(rule.get("monthly"))
		var line := "%s: %s" % [BB.esc(txt), (BB.good(K.signed(v)) if v > 0 else BB.bad(K.signed(v)))]
		if c is Dictionary:
			line = ("▶ " if now.has(key) else "   ") + line
		out.append(line)
	if d.get("on") is Dictionary:
		for ev in d.on:
			var v := Data.num(d.on[ev])
			out.append("• " + app.t("host.on." + str(ev), {"n": BB.good(K.signed(v)) if v > 0 else BB.bad(K.signed(v))}))
	return "\n".join(out)


static func _regiments_of(app: App, d: Dictionary) -> Array:
	var g := app.game
	var out := []
	for t in g.content.all("regiment_types"):
		var cr: Variant = t.get("can_recruit")
		if cr is Dictionary and cr.get("has_host") == d.id:
			out.append(g.name_of("regiment_types", t.id))
	return out


static func tip(app: App, d: Dictionary, c: Variant = null) -> String:
	var g := app.game
	var bb := BB.title(g.name_of("army_specializations", d.id))
	var desc := g.loc.t_or("army_specialization_desc." + str(d.id), "")
	if desc != "":
		bb += "\n" + BB.i(BB.esc(desc))
	bb += "\n\n" + BB.gold(app.t("host.abilities")) + "\n" + abilities_text(app, d)
	var kt := keep_text(app, d, c)
	if kt != "":
		bb += "\n\n" + BB.gold(app.t("host.keep")) + "\n" + kt
	var regs := _regiments_of(app, d)
	if not regs.is_empty():
		bb += "\n\n" + BB.muted(app.t("host.regiments", {"list": ", ".join(regs)}))
	if d.get("modifiers") is Dictionary and not d.modifiers.is_empty():
		bb += "\n" + BB.modifiers(g, d.modifiers)
	return bb


static func build(app: App, p: Dictionary) -> Variant:
	var g := app.game
	if not g.engine.has_feature("hosts") or p.titles.is_empty():
		return null
	var items: Array = []
	var h: Variant = Hosts.host_of(p)
	var d: Variant = Hosts.def_of(g, h.id) if h != null else null
	if d != null:
		var mx := g.def_num("hosts.max_devotion", 100)
		var delta := 0.0
		for x in Hosts.keep_parts(g, p, d):
			delta += float(x.value)
		var head := K.hbox([K.icon(d.get("icon", "banner"), 30), K.vbox([
			K.label(g.name_of("army_specializations", d.id), "GoldLabel"),
			K.label(app.t("host.devotion", {"n": roundi(float(h.devotion)), "max": roundi(mx)}) + " · " + app.t("host.month", {"n": K.signed(delta)}), "SmallLabel"),
		], 2)], 8)
		K.tip(head, func(): return tip(app, d, p))
		items.append(head)
		var bar := K.bar(float(h.devotion), mx, Color(str(d.get("color", "#b8913f"))), 8)
		K.tip(bar, app.t("host.devotion_tip"))
		items.append(bar)
		items.append(K.rich(abilities_text(app, d), true))
		var keep := K.rich(BB.muted(app.t("host.keep")) + "\n" + keep_text(app, d, p), true)
		items.append(keep)
		if g.is_player(p.id):
			items.append(K.button(app.t("host.abandon"), func():
				Hosts.dissolve(g, p, "abandoned")
				app.mark_dirty(true), {"variation": "FlatButton"}))
	else:
		items.append(K.para(app.t("host.none"), "SmallLabel"))
	# какие ещё можно собрать
	var opts := Hosts.available(g, p).filter(func(x): return d == null or x.id != d.id)
	if not opts.is_empty():
		items.append(K.label(app.t("host.available"), "GoldLabel"))
		for x in opts:
			var hid: String = x.id
			var blockers := Hosts.adopt_blockers(g, p, x)
			var cost: Dictionary = x.get("cost", {}) if x.get("cost") is Dictionary else {}
			var row := K.hbox([K.icon(x.get("icon", "banner"), 22), K.label(g.name_of("army_specializations", hid))], 6)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var line := K.hbox([row], 6)
			if g.is_player(p.id):
				line.add_child(K.button(app.t("host.adopt"), func():
					Hosts.adopt(g, p, hid)
					app.mark_dirty(true), {"variation": "GoldButton", "disabled": not blockers.is_empty(),
					"tip": func(): return BB.cost(g, cost) + ("\n" + BB.reasons(blockers) if not blockers.is_empty() else "")}))
			var pan := K.panel(line, "RowPanel")
			K.tip(pan, func(): return tip(app, x) + "\n\n" + BB.cost(g, cost))
			items.append(pan)
	if d == null and opts.is_empty():
		return null
	return K.section(app.t("host.title"), items, "banner")

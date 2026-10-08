class_name MapModes
extends RefCounted
## Встроенные режимы карты. Регистрируются в engine.ui.map_modes так же,
## как режимы из модов (GDScript) и из данных (map_modes).


static func realm_color(game: Game, prov: String) -> Variant:
	var t: Variant = game.title(prov)
	var h: Variant = game.ch(t.holder) if t != null else null
	if h == null:
		return "#7a7468"
	var top := Titles.top_liege(game, h)
	if top.titles.is_empty():
		return "#7a7468"
	var d: Variant = game.title_def(top.titles[0])
	return d.get("color", "#7a7468") if d != null else "#7a7468"


static func de_jure_ancestor(game: Game, prov: String, tier: String) -> Variant:
	var t: Variant = prov
	for i in 10:
		if t == null:
			break
		var d: Variant = game.title_def(t)
		if d == null:
			break
		if d.get("tier") == tier:
			return d.get("color")
		t = d.get("liege")
	return null


static func gradient_color(stops: Array, t: float) -> Color:
	if stops.is_empty():
		return Color.GRAY
	if stops.size() == 1:
		return Color(stops[0])
	var x := clampf(t, 0.0, 1.0) * (stops.size() - 1)
	var i := mini(stops.size() - 2, floori(x))
	return Color(stops[i]).lerp(Color(stops[i + 1]), x - i)


static func register_builtin(engine: GameEngine) -> void:
	var reg := engine.ui.map_modes
	var add := func(id: String, spec: Dictionary) -> void:
		if not reg.has(id):
			spec.id = id
			reg.register(id, spec, "core")
	add.call("realms", {"name": "ui.mapmode.realms", "icon": "crown", "order": 10, "color": realm_color})
	add.call("de_jure_duchy", {"name": "ui.mapmode.de_jure_duchy", "icon": "shield", "order": 20,
		"color": func(g: Game, p: String): return de_jure_ancestor(g, p, "duchy")})
	add.call("de_jure_kingdom", {"name": "ui.mapmode.de_jure_kingdom", "icon": "castle", "order": 21,
		"color": func(g: Game, p: String): return de_jure_ancestor(g, p, "kingdom")})
	add.call("culture", {"name": "ui.mapmode.culture", "icon": "speech", "order": 30,
		"color": func(g: Game, p: String):
			var st: Variant = g.prov(p)
			var d: Variant = g.content.get_def("cultures", st.culture) if st != null and st.culture != null else null
			return d.get("color") if d != null else null,
		"tooltip": func(g: Game, p: String):
			var st: Variant = g.prov(p)
			return g.name_of("cultures", st.culture) if st != null and st.culture != null else ""})
	add.call("faith", {"name": "ui.mapmode.faith", "icon": "cross", "order": 31,
		"color": func(g: Game, p: String):
			var st: Variant = g.prov(p)
			var d: Variant = g.content.get_def("faiths", st.faith) if st != null and st.faith != null else null
			return d.get("color") if d != null else null,
		"tooltip": func(g: Game, p: String):
			var st: Variant = g.prov(p)
			return g.name_of("faiths", st.faith) if st != null and st.faith != null else ""})
	add.call("terrain", {"name": "ui.mapmode.terrain", "icon": "mountain", "order": 40, "transparent": true,
		"color": func(g: Game, p: String): return null,
		"tooltip": func(g: Game, p: String):
			var d: Variant = g.prov_def(p)
			return g.name_of("terrain", d.get("terrain")) if d != null and d.get("terrain") != null else ""})
	add.call("diplomacy", {"name": "ui.mapmode.diplomacy", "icon": "handshake", "order": 15,
		"color": func(g: Game, p: String):
			var pl: Variant = g.player
			var t: Variant = g.title(p)
			var h: Variant = g.ch(t.holder) if t != null else null
			if pl == null or h == null:
				return "#6a665e"
			var top := Titles.top_liege(g, h)
			if h.id == pl.id:
				return "#3f8f4a"
			if Titles.is_in_realm_of(g, h, pl):
				return "#7bbf6a"
			if top.id == Titles.top_liege(g, pl).id:
				return "#a8b880"
			if Wars.is_at_war_with(g, pl.id, top.id) or Wars.is_at_war_with(g, pl.id, h.id):
				return "#b83a32"
			if Wars.is_allied(g, pl.id, top.id):
				return "#4a78c0"
			return "#8a857a"})
	# Режимы из данных: map_modes { value, min, max, gradient }
	for mm in engine.content.all("map_modes"):
		if reg.has(mm.id):
			continue
		var spec := {
			"id": mm.id, "name": mm.get("name", "ui.mapmode." + mm.id), "icon": mm.get("icon", "map"),
			"order": Data.num(mm.get("order"), 100),
			"color": func(g: Game, p: String):
				if g.prov(p) == null:
					return null
				var ctx := ScriptContext.make(g, {"type": "province", "id": p})
				var v := float(Interp.eval_value(ctx, ctx.root, mm.get("value", 0)))
				var lo := Data.num(mm.get("min"), 0.0)
				var hi := Data.num(mm.get("max"), 1.0)
				return gradient_color(Data.as_array(mm.get("gradient", ["#333333", "#ffffff"])), (v - lo) / maxf(1e-9, hi - lo)),
			"tooltip": func(g: Game, p: String):
				if g.prov(p) == null:
					return null
				var ctx := ScriptContext.make(g, {"type": "province", "id": p})
				return str(snappedf(float(Interp.eval_value(ctx, ctx.root, mm.get("value", 0))), 0.1)),
		}
		reg.register(mm.id, spec, "data")

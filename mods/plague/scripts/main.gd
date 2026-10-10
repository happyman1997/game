extends RefCounted
## Пример мода на GDScript «Моровые поветрия».
## Скрипт получает api в init(api): реестры скриптового языка, систем,
## хуков и интерфейса. Состояние мода хранится в game.mod_data("plague", ...)
## и автоматически попадает в сохранения.

const MOD := "plague"


## Состояние эпидемий в партии: { infected: { провинция: {disease, months} }, outbreaks }
static func state_of(game: Game) -> Dictionary:
	return game.mod_data(MOD, func(): return {"infected": {}, "outbreaks": 0})


## Где живёт персонаж: столица правителя или его двора.
static func home_of(game: Game, c: Dictionary) -> Variant:
	if not c.titles.is_empty():
		return c.capital
	var l: Variant = game.ch(c.liege)
	return l.capital if l != null else null


static func is_quarantined(game: Game, prov: String) -> bool:
	var p: Variant = game.state.provinces.get(prov)
	return p != null and p.modifiers.any(func(m): return m.id == "quarantine")


static func infect(game: Game, prov: String, disease: String) -> void:
	var st := state_of(game)
	if st.infected.has(prov) or not game.state.provinces.has(prov):
		return
	st.infected[prov] = {"disease": disease, "months": 0}
	st.outbreaks = int(st.outbreaks) + 1
	var t: Variant = game.state.titles.get(prov)
	var holder: Variant = game.ch(t.holder) if t != null else null
	var player: Variant = game.player
	if holder != null and player != null and (holder.id == player.id or holder.liege == player.id):
		game.message(game.loc.t("plague.msg_outbreak", {"place": game.name_of("provinces", prov), "disease": game.name_of("diseases", disease)}), "bad", {"type": "province", "id": prov})
		if holder.id == player.id and player.capital == prov:
			game.events.trigger("plague.0001", {"type": "character", "id": player.id}, {})
	game.emit("plague.outbreak", {"province": prov, "disease": disease})


func init(api: ModApi) -> void:
	# ------------------------------------------------ скриптовый язык
	api.trigger("province_has_disease", {
		"scopes": ["province"],
		"doc": "В провинции эпидемия. Аргумент: yes или id болезни.",
		"eval": func(ctx, scope, arg):
			var e: Variant = state_of(ctx.game).infected.get(scope.id)
			if (arg is String and arg == "no") or (arg is bool and not arg):
				return e == null
			return e != null and (ScriptContext.is_yes(arg) or e.disease == arg),
	})
	api.trigger("capital_has_disease", {
		"scopes": ["character"],
		"doc": "В столице персонажа (или его сюзерена) эпидемия.",
		"eval": func(ctx, scope, arg):
			var c: Variant = ctx.game.ch(scope.id)
			var cap: Variant = home_of(ctx.game, c) if c != null else null
			var yes: bool = cap != null and state_of(ctx.game).infected.has(cap)
			return not yes if ((arg is String and arg == "no") or (arg is bool and not arg)) else yes,
	})
	api.effect("start_disease", {
		"scopes": ["province"],
		"doc": "Начать эпидемию в провинции: start_disease: bubonic_plague",
		"apply": func(ctx, scope, arg): infect(ctx.game, scope.id, arg if (arg is String and arg != "yes") else "bubonic_plague"),
		"describe": func(ctx, scope, _arg): return ctx.game.scope_name(scope) + (": вспышка болезни" if ctx.game.loc.lang == "ru" else ": disease outbreak"),
	})
	api.value("infected_provinces", {
		"doc": "Число заражённых провинций в мире.",
		"get": func(ctx, _scope, _a): return float(state_of(ctx.game).infected.size()),
	})

	# ------------------------------------------------ система симуляции
	api.add_system({"id": "plague", "order": 65, "on_month": _monthly})

	# ------------------------------------------------ модификатор: страх эпидемии
	api.registries.modifier_providers.register("plague_fear", {
		"label": {"ru": "Страх эпидемии", "en": "Fear of pestilence"},
		"fn": func(game: Game, c: Dictionary) -> Variant:
			var infected: Dictionary = state_of(game).infected
			if infected.is_empty():
				return null
			var cap: Variant = home_of(game, c)
			return {"stress_gain_mult": 0.25, "fertility": -0.2} if (cap != null and infected.has(cap)) else null,
	}, api.owner)

	# ------------------------------------------------ интерфейс
	api.ui.map_modes.register("plague", {
		"id": "plague",
		"name": {"ru": "Эпидемии", "en": "Epidemics"},
		"icon": "☠",
		"order": 90,
		"color": func(game: Game, p: String) -> Variant:
			var e: Variant = state_of(game).infected.get(p)
			if e != null:
				var d: Variant = game.content.get_def("diseases", e.disease)
				return d.get("color", "#7a1f1f") if d != null else "#7a1f1f"
			var st: Variant = game.state.provinces.get(p)
			if st != null and st.modifiers.any(func(m): return m.id == "plague_aftermath"):
				return "#6a5a4a"
			return "#b8b0a0",
		"tooltip": func(game: Game, p: String) -> Variant:
			var e: Variant = state_of(game).infected.get(p)
			return "%s (%d)" % [game.name_of("diseases", e.disease), e.months] if e != null else null,
	}, api.owner)
	api.ui.top_bar.register("plague", {
		"id": "plague",
		"order": 10,
		"render": func(game: Game) -> Variant:
			var n: int = state_of(game).infected.size()
			if n == 0:
				return null
			return {"icon": "☠", "text": str(n), "tooltip": game.loc.t("plague.widget_tip", {"n": n})},
	}, api.owner)
	api.ui.panels.register("plague", {
		"id": "plague",
		"name": {"ru": "Эпидемии", "en": "Epidemics"},
		"icon": "☠",
		"order": 50,
		"render": func(game: Game, ui: Object) -> Control:
			var st := state_of(game)
			var box := VBoxContainer.new()
			var hint := Label.new()
			hint.text = game.loc.t("plague.panel_hint")
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(hint)
			var total := Label.new()
			total.text = game.loc.t("plague.outbreaks", {"n": st.outbreaks})
			box.add_child(total)
			if st.infected.is_empty():
				var none := Label.new()
				none.text = game.loc.t("plague.none")
				box.add_child(none)
			for prov in st.infected:
				var e: Dictionary = st.infected[prov]
				var b := Button.new()
				b.text = "☠ %s — %s, %s" % [game.name_of("provinces", prov), game.name_of("diseases", e.disease), game.loc.t("plague.months", {"n": e.months})]
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.flat = true
				b.pressed.connect(func(): ui.open_province(prov, true))
				box.add_child(b)
			return box,
	}, api.owner)
	api.ui.province_sections.register("plague", {
		"id": "plague",
		"title": {"ru": "Эпидемия", "en": "Epidemic"},
		"render": func(game: Game, prov: String, _ui: Object) -> Variant:
			var e: Variant = state_of(game).infected.get(prov)
			return "☠ %s — %s" % [game.name_of("diseases", e.disease), game.loc.t("plague.months", {"n": e.months})] if e != null else null,
	}, api.owner)

	api.log("мод загружен: болезней — %d" % api.content.all("diseases").size())


static func _monthly(game: Game) -> void:
	var st := state_of(game)
	# новые вспышки
	for d in game.content.all("diseases"):
		if game.rng.next() < Data.num(d.get("outbreak_chance")):
			var p: Variant = game.rng.pick(game.state.provinces.keys())
			if p != null and not st.infected.has(p):
				infect(game, p, d.id)
	# распространение, смерти, затухание
	for prov in st.infected.keys():
		var e: Dictionary = st.infected[prov]
		var d: Variant = game.content.get_def("diseases", e.disease)
		if d == null:
			st.infected.erase(prov)
			continue
		var quarantined := is_quarantined(game, prov)
		for n in game.engine.neighbors(prov):
			if st.infected.has(n):
				continue
			var chance := Data.num(d.get("spread_chance"), 0.1) * (0.3 if quarantined else 1.0) * (0.3 if is_quarantined(game, n) else 1.0)
			if game.rng.next() < chance:
				infect(game, n, e.disease)
		var death_chance := Data.num(d.get("monthly_death_chance"), 0.02) * (0.4 if quarantined else 1.0)
		for c in game.living().duplicate():
			if home_of(game, c) != prov or game.rng.next() >= death_chance:
				continue
			Succession.kill_character(game, c, "plague")
		e.months = int(e.months) + 1
		if e.months >= Data.num(d.get("duration_months"), 12):
			st.infected.erase(prov)
			var p: Variant = game.state.provinces.get(prov)
			if p != null:
				p.development = maxi(0, int(p.development) - int(Data.num(d.get("development_loss"))))
				p.modifiers.append({"id": "plague_aftermath", "expires": game.date + 365 * 2})
	game.notify("map")

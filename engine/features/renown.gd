class_name Renown
extends EngineFeature
## Слава и благочестие. Престиж и благочестие правителя складываются в
## уровни; подданные уважают славного сюзерена, а единоверцы — набожного:
##   defines.renown: { prestige_levels: [пороги], prestige_opinion: [мнение по уровням],
##                     piety_levels: [пороги], piety_opinion: [мнение по уровням] }
## Уровень 0 — ниже первого порога (позор, нечестие), дальше — по числу
## пройденных порогов. Названия — renown.prestige_<n>, renown.piety_<n>.

const OWNER := "core/renown"


func _init() -> void:
	id = "renown"
	doc = "Слава и благочестие: уровни престижа и благочестия меняют мнение подданных"


static func level(game: Game, kind: String, value: float) -> int:
	var lv := 0
	for th in game.def_val("renown.%s_levels" % kind, []):
		if value >= Data.num(th):
			lv += 1
	return lv


static func level_of(game: Game, c: Dictionary, kind: String) -> int:
	return level(game, kind, float(c.get(kind, 0.0)))


static func opinion_for(game: Game, kind: String, lv: int) -> float:
	var arr: Array = game.def_val("renown.%s_opinion" % kind, [])
	return Data.num(arr[clampi(lv, 0, arr.size() - 1)]) if not arr.is_empty() else 0.0


static func level_name(game: Game, kind: String, lv: int) -> String:
	return game.loc.t("renown.%s_%d" % [kind, lv])


## Строки подсказки: уровень, что он даёт и сколько до следующего.
static func describe(game: Game, c: Dictionary, kind: String) -> String:
	var lv := level_of(game, c, kind)
	var lines := [game.loc.t("ui.renown_level", {"name": level_name(game, kind, lv)})]
	var op := opinion_for(game, kind, lv)
	if op != 0.0:
		lines.append(game.loc.t("ui.renown_%s_effect" % kind, {"value": "%+d" % roundi(op)}))
	var ths: Array = game.def_val("renown.%s_levels" % kind, [])
	if lv < ths.size():
		lines.append(game.loc.t("ui.renown_next", {"name": level_name(game, kind, lv + 1), "value": roundi(Data.num(ths[lv]) - float(c.get(kind, 0.0)))}))
	return "\n".join(lines)


func install(engine: GameEngine) -> void:
	# Подданные (вассалы и двор) о сюзерене: его слава; единоверцы — его благочестие.
	engine.opinion_providers.register("renown", {"fn": func(game: Game, a: Dictionary, b: Dictionary) -> Variant:
		if a.liege != b.id:
			return null
		var out := []
		var lp := Renown.level_of(game, b, "prestige")
		var vp := Renown.opinion_for(game, "prestige", lp)
		if vp != 0.0:
			out.append({"label": game.loc.t("opinion.renown_prestige", {"name": Renown.level_name(game, "prestige", lp)}), "value": vp})
		if a.faith == b.faith:
			var lf := Renown.level_of(game, b, "piety")
			var vf := Renown.opinion_for(game, "piety", lf)
			if vf != 0.0:
				out.append({"label": game.loc.t("opinion.renown_piety", {"name": Renown.level_name(game, "piety", lf)}), "value": vf})
		return out if not out.is_empty() else null
	}, OWNER)


func register_script(engine: GameEngine) -> void:
	var r := engine.scripting
	r.values.register("prestige_level", {"scopes": ["character"], "doc": "Уровень славы (0 — позор)", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return float(Renown.level_of(ctx.game, c, "prestige")) if c != null else 0.0
	}, OWNER)
	r.values.register("piety_level", {"scopes": ["character"], "doc": "Уровень благочестия (0 — нечестие)", "get": func(ctx, s, _a):
		var c: Variant = ctx.game.ch(s.id)
		return float(Renown.level_of(ctx.game, c, "piety")) if c != null else 0.0
	}, OWNER)

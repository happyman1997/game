class_name Economy
extends RefCounted
## Экономика: налоги с графств, ополчения, лимит домена, ежемесячные
## престиж и благочестие. Все коэффициенты — в defines.economy.


static func county_tax(game: Game, county_id: String) -> float:
	var p: Variant = game.state.provinces.get(county_id)
	if p == null:
		return 0.0
	var base := Stats.prov_stat(game, county_id, "tax")
	return base * (1.0 + Data.num(p.development) * game.def_num("economy.development_tax", 0.02)) * (1.0 + Stats.prov_stat(game, county_id, "tax_mult"))


static func county_levy(game: Game, county_id: String) -> float:
	var p: Variant = game.state.provinces.get(county_id)
	if p == null:
		return 0.0
	var base := Stats.prov_stat(game, county_id, "levy")
	return base * (1.0 + Data.num(p.development) * game.def_num("economy.development_levy", 0.01)) * (1.0 + Stats.prov_stat(game, county_id, "levy_mult"))


static func domain_limit(game: Game, c: Dictionary) -> int:
	var by_tier: Array = game.def_val("economy.domain_limit_by_tier", [0, 0, 1, 2, 3])
	var pt := Titles.primary_tier(game, c)
	var tier_bonus = Data.num(by_tier[pt]) if pt < by_tier.size() else 0.0
	var sk = Stats.skill(game, c, str(game.def_val("economy.domain_skill", "stewardship")))
	return floori(game.def_num("economy.domain_limit_base", 2) + sk / game.def_num("economy.domain_limit_per_skill", 5) + tier_bonus + Stats.stat(game, c, "domain_limit"))


static func _is_occupied(game: Game, county_id: String) -> bool:
	var p: Variant = game.state.provinces.get(county_id)
	return p != null and p.occupant != null


## Валовый налог с собственного домена (без вассалов).
static func domain_tax(game: Game, c: Dictionary) -> float:
	return game.cached_daily("dtax:" + c.id, func(): return _compute_domain_tax(game, c))


static func _compute_domain_tax(game: Game, c: Dictionary) -> float:
	var counties := Titles.domain_counties(game, c)
	var total := 0.0
	for cid in counties:
		if not _is_occupied(game, cid):
			total += county_tax(game, cid)
	var skill_mult = 1.0 + Stats.skill(game, c, str(game.def_val("economy.tax_skill", "stewardship"))) * game.def_num("economy.tax_per_skill", 0.02)
	var over := maxi(0, counties.size() - domain_limit(game, c))
	var over_mult = maxf(0.2, 1.0 - over * game.def_num("economy.over_domain_penalty", 0.2))
	return total * skill_mult * (1.0 + Stats.stat(game, c, "tax_mult")) * over_mult


static func vassal_tax_share(game: Game) -> float:
	return game.def_num("economy.vassal_tax_share", 0.15)


static func army_maintenance(game: Game, c: Dictionary) -> float:
	var per100 = game.def_num("economy.levy_maintenance_per_100", 0.25)
	var men := 0.0
	for a in game.state.armies.values():
		if a.owner == c.id:
			men += Data.num(a.size)
			for r in Data.as_array(a.get("regiments")):
				men -= Data.num(r.size)
	return maxf(0.0, men / 100.0 * per100 * (1.0 + Stats.stat(game, c, "army_upkeep_mult")))


## [{label, value}]
static func income_breakdown(game: Game, c: Dictionary) -> Array:
	var parts := []
	if c.titles.is_empty():
		var flat0 := Stats.stat(game, c, "monthly_income")
		if flat0 != 0.0:
			parts.append({"label": game.loc.t("ui.other_income"), "value": flat0})
		return parts
	var dom := domain_tax(game, c)
	parts.append({"label": game.loc.t("ui.domain_tax"), "value": dom})
	var share := vassal_tax_share(game)
	var from_vassals := 0.0
	var tax_mult := maxf(0.0, 1.0 + Stats.stat(game, c, "vassal_tax_mult"))
	for v in game.vassals_of(c.id):
		if not in_revolt(game, v.id, c.id):
			# vassal_contribution_tax — личные условия службы вассала (привилегии, повинности)
			from_vassals += domain_tax(game, v) * share * tax_mult * maxf(0.0, 1.0 + Stats.stat(game, v, "vassal_contribution_tax"))
	if from_vassals != 0.0:
		parts.append({"label": game.loc.t("ui.vassal_tax"), "value": from_vassals})
	if c.liege != null:
		var l: Variant = game.ch(c.liege)
		var lm = maxf(0.0, 1.0 + Stats.stat(game, l, "vassal_tax_mult")) if l != null else 1.0
		parts.append({"label": game.loc.t("ui.liege_tax"), "value": -dom * share * lm * maxf(0.0, 1.0 + Stats.stat(game, c, "vassal_contribution_tax"))})
	var flat := Stats.stat(game, c, "monthly_income")
	if flat != 0.0:
		parts.append({"label": game.loc.t("ui.other_income"), "value": flat})
	var army := army_maintenance(game, c)
	if army != 0.0:
		parts.append({"label": game.loc.t("ui.army_upkeep"), "value": -army})
	for extra in game.engine.hooks.collect("economy.income", {"game": game, "character": c}):
		parts.append(extra)
	return parts


static func monthly_income(game: Game, c: Dictionary) -> float:
	var s := 0.0
	for p in income_breakdown(game, c):
		s += Data.num(p.value)
	return s


static func monthly_prestige(game: Game, c: Dictionary) -> float:
	var by_tier: Array = game.def_val("economy.monthly_prestige_by_tier", [0, 0.2, 0.5, 1, 1.5])
	var pt := Titles.primary_tier(game, c)
	var v = (Data.num(by_tier[pt]) if pt < by_tier.size() else 0.0) + Stats.stat(game, c, "monthly_prestige")
	if c.gold < 0:
		v -= minf(5.0, -float(c.gold) / game.def_num("economy.debt_prestige_divisor", 50))
	return v


static func monthly_piety(game: Game, c: Dictionary) -> float:
	return Stats.skill(game, c, "learning") * game.def_num("economy.piety_per_learning", 0.03) + Stats.stat(game, c, "monthly_piety")


## Ополчения своего домена с учётом восстановления.
static func domain_levy(game: Game, c: Dictionary) -> float:
	var total := 0.0
	for cid in Titles.domain_counties(game, c):
		if not _is_occupied(game, cid):
			total += county_levy(game, cid)
	return total * (1.0 + Stats.stat(game, c, "levy_mult")) * float(c.levy_ratio)


## Всё ополчение державы: свой домен + доля вассалов (рекурсивно) + бонусы.
static func realm_levy(game: Game, c: Dictionary, depth: int = 0) -> int:
	if depth > 10:
		return 0
	var key = "rlevy:" + c.id
	if game.day_cache.has(key):
		return game.day_cache[key]
	var share = game.def_num("economy.vassal_levy_share", 0.35) * maxf(0.0, 1.0 + Stats.stat(game, c, "vassal_levy_mult"))
	var total := domain_levy(game, c) + Stats.stat(game, c, "levy_flat")
	for v in game.vassals_of(c.id):
		if not in_revolt(game, v.id, c.id):
			total += realm_levy(game, v, depth + 1) * share * maxf(0.0, 1.0 + Stats.stat(game, v, "vassal_contribution_levy"))
	var r := roundi(total)
	game.day_cache[key] = r
	return r


## Вассал воюет против своего сюзерена (мятеж): не платит налогов и не даёт войск.
static func in_revolt(game: Game, vassal: String, liege: String) -> bool:
	for w in game.state.wars.values():
		if (w.attackers.has(vassal) and w.defenders.has(liege)) or (w.defenders.has(vassal) and w.attackers.has(liege)):
			return true
	return false


## Приблизительная «военная сила» для ИИ: ополчение + уже поднятые армии.
static func military_strength(game: Game, c: Dictionary) -> float:
	return game.cached_daily("milstr:" + c.id, func(): return _compute_military_strength(game, c))


static func _compute_military_strength(game: Game, c: Dictionary) -> float:
	var raised := 0.0
	for a in game.state.armies.values():
		if a.owner != c.id:
			continue
		raised += Data.num(a.size)
		for b in game.engine.hooks.collect("army.power_bonus", {"game": game, "army": a, "enemies": [], "location": a.location}):
			raised += Data.num(b)
	var extra := 0.0
	for b in game.engine.hooks.collect("military.strength_bonus", {"game": game, "character": c}):
		extra += Data.num(b)
	return (raised if raised > 0.0 else float(realm_levy(game, c))) + extra


## Причины, по которым персонаж не может заплатить цену (пусто — может). Нулевая цена всегда доступна.
static func cost_blockers(game: Game, c: Dictionary, cost: Dictionary) -> Array:
	var out := []
	var g := Data.num(cost.get("gold"))
	var p := Data.num(cost.get("prestige"))
	var pi := Data.num(cost.get("piety"))
	if g > 0 and c.gold < g:
		out.append(game.loc.t("ui.need_gold", {"value": _n(g)}))
	if p > 0 and c.prestige < p:
		out.append(game.loc.t("ui.need_prestige", {"value": _n(p)}))
	if pi > 0 and c.piety < pi:
		out.append(game.loc.t("ui.need_piety", {"value": _n(pi)}))
	return out


static func _n(v: float) -> Variant:
	return int(v) if v == floorf(v) else v

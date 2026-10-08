extends RefCounted
## Пример мода на GDScript: новый алгоритм наследования «elective».
## Кандидаты — взрослые члены династии и могущественные вассалы;
## голосуют вассалы правителя (по мнению о кандидатах и их престижу).


func init(api: ModApi) -> void:
	api.registries.succession_algorithms.register("elective", {
		"label": {"ru": "Выборы", "en": "Election"},
		"heirs": _elective_heirs,
	}, api.owner)

	# Хук: сообщаем игроку, кто победил на выборах.
	api.on("succession", func(p):
		var game: Game = p.game
		if p.deceased.get("succession_law") != "feudal_elective":
			return
		var who := game.scope_name({"type": "character", "id": p.primary}, "full_name")
		game.message(("Выборы: новым правителем избран " if game.loc.lang == "ru" else "Election: the new ruler is ") + who,
			"info", {"type": "character", "id": p.primary}, [p.deceased.id, p.primary])
	)


func _elective_heirs(game: Game, ruler: Dictionary, law: Dictionary) -> Array:
	var candidates := {}
	if ruler.dynasty != null:
		for c in game.living():
			if c.dynasty == ruler.dynasty and c.id != ruler.id and Chars.is_adult(game, c):
				candidates[c.id] = c
	for v in game.vassals_of(ruler.id):
		if Chars.is_adult(game, v):
			candidates[v.id] = v
	var list: Array = candidates.values()
	if law.get("gender") == "male_only":
		list = list.filter(func(c): return not c.female)
	if list.is_empty():
		return Succession.blood_line(game, ruler, law.get("gender"))
	var electors := game.vassals_of(ruler.id).filter(func(v): return v.death == null)
	var score := func(cand: Dictionary) -> float:
		var s := 0.0
		for e in electors:
			s += Opinion.opinion(game, e, cand)
		return s + float(cand.prestige) / 50.0 + (15.0 if cand.dynasty == ruler.dynasty else 0.0)
	Data.sort_by(list, score, true)
	var ranked: Array = list.map(func(c): return c.id)
	for id in Succession.blood_line(game, ruler, law.get("gender")):
		if not ranked.has(id):
			ranked.append(id)
	return ranked

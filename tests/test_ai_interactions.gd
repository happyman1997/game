extends TestCase
## ИИ пользуется прежде «спящими» предложениями: дарит лишнюю вещь
## прохладному сюзерену, глава рода берёт дань с богатого родича и чтит
## недовольного, при абсолютной власти отзывает титул у вассала, который его
## ненавидит, а без неё и без повода — нет.


func _game() -> Game:
	var g := TestEnv.engine().new_game("b1066", 5)
	g.state.player = null
	return g


## Сделает ли ИИ предложение id (кому — to, если задано) за n раздумий.
func _does(g: Game, c: Dictionary, id: String, to: String = "", n: int = 80) -> bool:
	var hit := [false]
	var fn := func(p):
		if p.interaction == id and p.actor == c.id and (to == "" or p.recipient == to):
			hit[0] = true
	g.engine.hooks.on("interaction", fn, 0, "test")
	for k in n:
		if hit[0]:
			break
		Ai._consider_interactions(g, c)
	g.engine.hooks.off("interaction", fn)
	return hit[0]


func _vassal(g: Game, liege: Dictionary) -> Dictionary:
	for v in g.vassals_of(liege.id):
		if Chars.is_adult(g, v) and v.get("prison") == null:
			return v
	return {}


func test_gift_artifact_to_cold_liege() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v := _vassal(g, h)
	for k in 3:
		Artifacts.create(g, "ring", "common", v)
	check(not Artifacts.storage(g, v).is_empty(), "у вассала есть лишняя вещь")
	Opinion.add_opinion(g, h, v, "generic", -60)
	check(_does(g, v, "gift_artifact", h.id), "вассал дарит вещь прохладному сюзерену")


func test_dynasty_head_tribute_and_honor() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var head: Variant = Dynasties.head_of(g, h.dynasty)
	check(head != null, "у рода есть глава")
	var kin: Variant = null
	for x in g.living():
		if x.id != head.id and not x.titles.is_empty() and Chars.same_dynasty(g, x, head):
			kin = x
			break
	check(kin != null, "у главы рода есть родич-правитель")
	head.gold = 80.0
	kin.gold = 400.0
	Chars.add_dynasty_renown(g, head.dynasty, 400)
	check(_does(g, head, "demand_family_tribute", kin.id, 120), "глава рода берёт дань с богатого родича")
	Opinion.add_opinion(g, kin, head, "generic", -60)
	Chars.add_dynasty_renown(g, head.dynasty, 400)
	check(_does(g, head, "honor_kin", kin.id, 120), "и чтит недовольного родича")


func test_revoke_needs_authority_or_reason() -> void:
	var g := _game()
	var h: Dictionary = g.ch("harold")
	var v := _vassal(g, h)
	Opinion.add_opinion(g, v, h, "generic", -250)
	check(not _does(g, h, "revoke_title", v.id, 40), "без власти и повода — титул не отнимает")
	check(Laws.change(g, h, "crown_authority_3", true), "абсолютная власть")
	h.prestige = 1000.0
	check(_does(g, h, "revoke_title", v.id, 300), "при абсолютной власти — отнимает у ненавидящего")

extends TestCase


func test_yaml_basics() -> void:
	var r := Yaml.parse("""
# комментарий
a: 1
b: [1, 2.5, "x", {c: d}]
nested:
  list:
    - one
    - k: v
      n: null
  flag: true
quoted: "строка # не комментарий"
apostrophe: Жанна д'Арк
""", "test")
	check(r.ok, r.error)
	var v: Dictionary = r.value
	check_eq(v.a, 1)
	check_eq(typeof(v.a), TYPE_INT, "тип a")
	check_eq(v.b, [1, 2.5, "x", {"c": "d"}])
	check_eq(v.nested.list, ["one", {"k": "v", "n": null}])
	check_eq(v.nested.flag, true)
	check_eq(v.quoted, "строка # не комментарий")
	check_eq(v.apostrophe, "Жанна д'Арк")
	check(not Yaml.parse("a: 1\na: 2", "dup").ok, "повтор ключа — ошибка")


func test_rng_matches_web_version() -> void:
	# Последовательность mulberry32 должна совпадать с веб-версией (TS).
	var r := Rng.from_seed(42)
	var got := []
	for i in 3:
		got.append(snappedf(r.next(), 0.000001))
	check_eq(got, [0.601104, 0.448291, 0.852466], "mulberry32(42)")
	check_eq(Rng.hash_string("abc"), 440920331, "FNV-1a")


func test_dates() -> void:
	var d := GameDate.parse("1066.9.15")
	check_eq(GameDate.to_str(d), "1066.9.15")
	check_eq(GameDate.parts(d).m, 9)
	check_eq(GameDate.duration_days({"years": 1, "months": 2}), 425)


func test_deep_merge() -> void:
	var base := {"a": {"x": 1, "y": 2}, "list": [1, 2, 3], "gone": 5}
	var m: Dictionary = Data.deep_merge(base, {"a": {"y": 3}, "list": {"$append": [4], "$remove": [1]}, "gone": {"$delete": true}})
	check_eq(m, {"a": {"x": 1, "y": 3}, "list": [2, 3, 4]})
	var rep: Dictionary = Data.deep_merge(base, {"a": {"$replace": true, "z": 1}})
	check_eq(rep.a, {"z": 1})


func test_localization() -> void:
	var loc := Localization.new()
	loc.add("ru", {"trait": {"brave": "Храбрый"}, "hello": "Привет, {name}!"})
	check_eq(loc.t("trait.brave"), "Храбрый")
	check_eq(loc.t("hello", {"name": "Гарольд"}), "Привет, Гарольд!")
	check_eq(loc.resolve({"ru": "А", "en": "B"}), "А")


func test_load_all_mods() -> void:
	var issues := []
	var pkgs := ModPackage.scan_dir("res://mods", "builtin", "встроенный", issues)
	check(pkgs.size() >= 4, "найдено модов: %d" % pkgs.size())
	var res := ModLoader.load_mods(pkgs, FormatRegistry.create_default())
	for i in res.issues:
		check(i.level != "error", "ошибка мода: %s" % i)
	var content: ContentStore = res.content
	check(content.all("characters").size() > 100, "персонажи загружены")
	check(content.has("titles", "k_england"), "есть k_england")
	check_eq(res.order[0].id, "core", "core грузится первым")

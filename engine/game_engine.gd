class_name GameEngine
extends RefCounted
## Движок: загруженные моды, контент, реестры. Не зависит от конкретной
## партии — партии (Game) создаются через new_game/load_game.

signal issue_reported(issue: Dictionary)

var formats := FormatRegistry.create_default()
var scripting := ScriptRegistry.new()
var hooks := HookBus.new()
var systems := Registry.new("система")
var ui := UiRegistry.new()
## Реестры расширения мира (см. соответствующие классы в engine/world).
var succession_algorithms := Registry.new("алгоритм наследования")
var cb_targets := Registry.new("поставщик целей войны")
var interaction_targets := Registry.new("поставщик целей взаимодействия")
var interaction_deciders := Registry.new("решающий во взаимодействии")
var modifier_providers := Registry.new("поставщик модификаторов")
var province_modifier_providers := Registry.new("поставщик модификаторов провинции")
var opinion_providers := Registry.new("поставщик мнения")
var content_validators := Registry.new("проверка контента")
## Механики (образ жизни, совет, темница, фракции, отряды…).
var features := Registry.new("механика")
## Включённые (установленные) механики.
var installed_features := {}

var content: ContentStore
var loc: Localization
var mods: Array = []
var issues: Array = []
## Кэш производных данных контента (не состояния партии).
var cache := {}
var _map: MapData = null
var _children: Variant = null
var _dist_cache := {}
var _path_rows := {}


func has_feature(id: String) -> bool:
	return installed_features.has(id)


## Все реестры — для API модов (api.registries).
func registries() -> Dictionary:
	return {
		"succession_algorithms": succession_algorithms, "cb_targets": cb_targets,
		"interaction_targets": interaction_targets, "interaction_deciders": interaction_deciders,
		"modifier_providers": modifier_providers, "province_modifier_providers": province_modifier_providers,
		"opinion_providers": opinion_providers, "content_validators": content_validators,
	}


## opts: enabled (Array id или null), lang, default_localization ({lang: [документы]}),
## on_progress (Callable(msg)).
static func create(packages: Array, opts: Dictionary = {}) -> GameEngine:
	var e := GameEngine.new()
	var progress: Callable = opts.get("on_progress", Callable())
	var res := ModLoader.load_mods(packages, e.formats, opts.get("enabled"), func(pkg: ModPackage, inst: Object):
		if inst.has_method("preload_mod"):
			inst.preload_mod({"mod": pkg.manifest, "formats": e.formats})
	)
	e.content = res.content
	e.loc = res.loc
	e.mods = res.order
	e.issues.append_array(res.issues)
	if opts.get("lang") != null:
		e.loc.lang = opts.lang
	var defaults: Dictionary = opts.get("default_localization", {})
	for lang in defaults:
		for doc in defaults[lang]:
			e.loc.add_defaults(lang, doc)

	ContentNormalize.normalize(e.content)
	Builtins.register(e)
	Builtins.register_skill_values(e)
	e._register_defaults()
	var disabled := Data.as_array(e.content.singleton("defines").get("disabled_features"))
	for f in FeatureList.builtin():
		e.features.register(f.id, f, "core")
		if f.has_method("register_script"):
			f.register_script(e)
		if not disabled.has(f.id):
			f.install(e)
			e.installed_features[f.id] = true
	# Записи, требующие отключённой механики, убираются из контента.
	for type in e.content.types():
		for id in e.content.ids(type):
			var def: Variant = e.content.get_def(type, id)
			if def is Dictionary and def.get("requires_feature") != null:
				for x in Data.as_array(def.requires_feature):
					if not e.installed_features.has(x):
						e.content.remove(type, id)
						break

	for s in res.scripts:
		var inst: Object = s.instance
		if not inst.has_method("init"):
			continue
		var manifest: Dictionary = {}
		for p in e.mods:
			if p.id == s.mod:
				manifest = p.manifest
		if progress.is_valid():
			progress.call("Инициализация %s/%s" % [s.mod, s.path])
		inst.init(ModApi.new(e, manifest))
	e.issues.append_array(ContentValidate.validate(e))
	e.hooks.emit("engine.ready", {"engine": e})
	return e


func _register_defaults() -> void:
	for s in CoreSystems.builtin():
		systems.register(s.id, s, "core")
	var algos := Succession.builtin_algorithms()
	for id in algos:
		succession_algorithms.register(id, algos[id], "core")
	var cbs := Wars.builtin_cb_targets()
	for id in cbs:
		cb_targets.register(id, cbs[id], "core")
	var ops := Opinion.builtin_providers()
	for id in ops:
		opinion_providers.register(id, {"fn": ops[id]}, "core")
	modifier_providers.register("buildings", {"label": "modsrc.buildings", "fn": Stats.building_owner_provider}, "core")
	modifier_providers.register("stress", {"label": "modsrc.stress", "fn": Stats.stress_provider}, "core")

	var title_opt := func(game: Game, id: String) -> Dictionary:
		return {"id": id, "label": Titles.full_name(game, id), "ref": {"type": "title", "id": id}}
	interaction_targets.register("grantable_titles", {"options": func(game: Game, actor: Dictionary, _r: Dictionary) -> Array:
		var cap: Variant = actor.capital
		var counties := Titles.domain_counties(game, actor).filter(func(c): return c != cap)
		var duchies: Array = actor.titles.filter(func(t):
			var d: Variant = game.content.get_def("titles", t)
			return d != null and d.tier == "duchy" and t != actor.titles[0])
		return (duchies + counties).map(func(id): return title_opt.call(game, id))
	}, "core")
	interaction_targets.register("revocable_titles", {"options": func(game: Game, actor: Dictionary, recipient: Dictionary) -> Array:
		if recipient.liege != actor.id:
			return []
		return recipient.titles.map(func(id): return title_opt.call(game, id))
	}, "core")
	interaction_targets.register("recipient_claims", {"options": func(game: Game, actor: Dictionary, recipient: Dictionary) -> Array:
		return recipient.titles.filter(func(t): return not actor.claims.has(t)).map(func(id): return title_opt.call(game, id))
	}, "core")
	ui.event_themes.register("default", {"icon": "📜", "color": "#8a6d3b"}, "core")


# ------------------------------------------------------------ карта и иерархия

var map: MapData:
	get:
		if _map == null:
			_map = MapBuilder.load_or_build(content)
		return _map


## Сбрасывает карту (например, если мод изменил провинции из скрипта).
func invalidate_map() -> void:
	_map = null
	_path_rows.clear()
	_dist_cache.clear()
	cache.clear()


func de_jure_children() -> Dictionary:
	if _children == null:
		var m := {}
		for t in content.all("titles"):
			var l: Variant = t.get("liege")
			if l == null:
				continue
			if not m.has(l):
				m[l] = []
			m[l].append(t.id)
		_children = m
	return _children


func neighbors(prov_id: String) -> Array:
	return map.neighbors.get(prov_id, [])


func is_coastal(prov_id: String) -> bool:
	var i: int = map.index.get(prov_id, -1)
	return i >= 0 and map.coastal[i] == 1


func distance(a: String, b: String) -> float:
	var key = (a + "|" + b) if a < b else (b + "|" + a)
	if _dist_cache.has(key):
		return _dist_cache[key]
	var m := map
	var i: int = m.index.get(a, -1)
	var j: int = m.index.get(b, -1)
	var v := 100.0
	if i >= 0 and j >= 0:
		v = Vector2(m.centers[i * 2], m.centers[i * 2 + 1]).distance_to(Vector2(m.centers[j * 2], m.centers[j * 2 + 1]))
	_dist_cache[key] = v
	return v


## Кратчайшие пути от провинции src ко всем (с учётом местности):
## {dist: PackedFloat32Array, pred: PackedInt32Array}. Считается лениво и кэшируется.
func _path_row(src: int) -> Dictionary:
	if _path_rows.has(src):
		return _path_rows[src]
	var m := map
	var n := m.provinces.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var pred := PackedInt32Array()
	pred.resize(n)
	pred.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	dist[src] = 0.0
	if not cache.has("adj"):
		_build_adjacency()
	var adj: Array = cache["adj"]
	while true:
		var u := -1
		var best := INF
		for i in n:
			if done[i] == 0 and dist[i] < best:
				best = dist[i]
				u = i
		if u < 0:
			break
		done[u] = 1
		for e in adj[u]:
			var nd: float = best + e[1]
			if nd < dist[e[0]]:
				dist[e[0]] = nd
				pred[e[0]] = u
	var row := {"dist": dist, "pred": pred}
	_path_rows[src] = row
	return row


func _build_adjacency() -> void:
	var m := map
	var adj := []
	for a in m.provinces:
		var list := []
		for b in m.neighbors.get(a, []):
			var pd: Variant = content.get_def("provinces", b)
			var terrain: Variant = content.get_def("terrain", pd.get("terrain")) if pd != null else null
			var mv = Data.num(terrain.get("movement"), 1.0) if terrain != null else 1.0
			list.append([m.index[b], distance(a, b) * mv])
		adj.append(list)
	cache["adj"] = adj


## Длина кратчайшего пути (INF, если пути нет).
func path_length(a: String, b: String) -> float:
	var m := map
	var i: int = m.index.get(a, -1)
	var j: int = m.index.get(b, -1)
	if i < 0 or j < 0:
		return INF
	return _path_row(i).dist[j]


## Путь без стартовой провинции или null.
func find_path(a: String, b: String) -> Variant:
	var m := map
	var i: int = m.index.get(a, -1)
	var j: int = m.index.get(b, -1)
	if i < 0 or j < 0:
		return null
	var row := _path_row(i)
	if is_inf(row.dist[j]):
		return null
	var path := []
	var cur := j
	var guard := 0
	while cur != i and guard < m.provinces.size():
		path.append(m.provinces[cur])
		cur = row.pred[cur]
		guard += 1
		if cur < 0:
			return null
	path.reverse()
	return path


func ordered_systems() -> Array:
	var list := systems.values()
	Data.sort_by(list, func(s): return Data.num(s.get("order"), 100))
	return list


# ------------------------------------------------------------ проблемы модов

func report_issue(i: Dictionary) -> void:
	issues.append(i)
	if issues.size() > 500:
		issues = issues.slice(issues.size() - 500)
	issue_reported.emit(i)
	if i.get("level") == "error":
		push_error(i.message)
	else:
		push_warning(i.message)


# ------------------------------------------------------------ партии

func bookmarks() -> Array:
	return content.all("bookmarks")


func new_game(bookmark_id: String, seed: int = -1) -> Game:
	return WorldSetup.setup_new_game(self, bookmark_id, seed)


## {game, warnings, error}
func load_game(json: String) -> Dictionary:
	return SaveGame.deserialize(self, json)

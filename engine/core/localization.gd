class_name Localization
extends RefCounted
## Локализация. Файлы модов лежат в localization/<язык>/*.yaml и содержат
## вложенные словари, которые «сплющиваются» в ключи через точку:
##
##   trait:
##     brave: Храбрый      →  trait.brave
##
## Подстановки {name} заполняются параметрами из кода, а [путь]
## вычисляется скриптовым движком (см. Game.text).

var _tables := {}
var lang := "ru"
var fallbacks: Array[String] = ["en", "ru"]


func _table(l: String) -> Dictionary:
	if not _tables.has(l):
		_tables[l] = {}
	return _tables[l]


func add(l: String, entries: Variant, prefix: String = "") -> void:
	_walk(_table(l), entries, prefix, true)


## Добавляет строки, не перезаписывая уже существующие (строки модов важнее).
func add_defaults(l: String, entries: Variant) -> void:
	_walk(_table(l), entries, "", false)


func _walk(table: Dictionary, obj: Variant, pre: String, overwrite: bool) -> void:
	if obj is Dictionary:
		for k in obj:
			_walk(table, obj[k], (pre + "." + str(k)) if pre != "" else str(k), overwrite)
	elif obj != null:
		if overwrite or not table.has(pre):
			table[pre] = _to_text(obj)


static func _to_text(v: Variant) -> String:
	if v is float and v == floorf(v):
		return str(int(v))
	if v is bool:
		return "true" if v else "false"
	return str(v)


func languages() -> Array:
	return _tables.keys()


## Строка по ключу (с запасными языками) или null.
func raw(key: String) -> Variant:
	var t: Dictionary = _tables.get(lang, {})
	if t.has(key):
		return t[key]
	for fb in fallbacks:
		var ft: Dictionary = _tables.get(fb, {})
		if ft.has(key):
			return ft[key]
	return null


## Только текущий язык, без запасных (для имён: лучше «сырое» имя, чем перевод с другого языка).
func raw_exact(key: String) -> Variant:
	return _tables.get(lang, {}).get(key)


func has(key: String) -> bool:
	return raw(key) != null


func t(key: String, params: Dictionary = {}) -> String:
	var s: Variant = raw(key)
	if s == null:
		return format(key, params) if not params.is_empty() else key
	return format(s, params) if not params.is_empty() else s


## Как t, но возвращает fallback, если ключа нет.
func t_or(key: String, fallback: String, params: Dictionary = {}) -> String:
	var s: Variant = raw(key)
	return format(s if s != null else fallback, params)


## Разрешает «текстовое значение» из данных мода:
##  - словарь {ru: "...", en: "..."} — выбирается текущий язык;
##  - строка, совпадающая с ключом локализации — переводится;
##  - иначе строка используется как есть (можно писать текст прямо в данных);
##  - {key, params} — ключ с параметрами (значения-строки тоже переводятся).
func resolve(v: Variant, params: Dictionary = {}) -> String:
	if v == null:
		return ""
	# { key, params } — ключ с параметрами; строки-параметры тоже переводятся
	if v is Dictionary and v.has("key"):
		var ps := params.duplicate()
		var vp: Variant = v.get("params")
		if vp is Dictionary:
			for k in vp:
				ps[k] = resolve(vp[k])
		return resolve(v.key, ps)
	if v is Dictionary:
		var s: Variant = v.get(lang)
		if s == null:
			for f in fallbacks:
				if v.has(f):
					s = v[f]
					break
		if s == null:
			s = v.values()[0] if not v.is_empty() else ""
		return format(str(s), params) if not params.is_empty() else str(s)
	var key := _to_text(v)
	var r: Variant = raw(key)
	var out: String = r if r != null else key
	return format(out, params) if not params.is_empty() else out


func keys(l: String = "") -> Array:
	return _tables.get(l if l != "" else lang, {}).keys()


static var _fmt_re: RegEx

## Подставляет {param} из словаря.
static func format(template: String, params: Dictionary) -> String:
	if params.is_empty() or template.find("{") < 0:
		return template
	if _fmt_re == null:
		_fmt_re = RegEx.create_from_string("\\{(\\w+)\\}")
	var out := ""
	var last := 0
	for m in _fmt_re.search_all(template):
		out += template.substr(last, m.get_start() - last)
		var k := m.get_string(1)
		out += _to_text(params[k]) if params.has(k) else m.get_string()
		last = m.get_end()
	return out + template.substr(last)

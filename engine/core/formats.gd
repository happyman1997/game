class_name FormatRegistry
extends RefCounted
## Реестр форматов файлов данных. Из коробки поддерживаются YAML и JSON;
## мод может зарегистрировать свой парсер (например, Paradox-скрипт)
## через api.formats.register("txt", parser).
##
## Парсер — Callable(text: String, path: String) -> Dictionary
## {"ok": bool, "value": Variant, "error": String}.

var _parsers := {}


func register(ext: String, parser: Callable) -> void:
	_parsers[ext.to_lower().trim_prefix(".")] = parser


func ext_of(path: String) -> String:
	return path.get_extension().to_lower()


func can_parse(path: String) -> bool:
	return _parsers.has(ext_of(path))


func parse(text: String, path: String) -> Dictionary:
	var p: Variant = _parsers.get(ext_of(path))
	if p == null:
		return {"ok": false, "value": null, "error": "Нет парсера для файла " + path}
	return p.call(text, path)


func extensions() -> Array:
	return _parsers.keys()


static func create_default() -> FormatRegistry:
	var f := FormatRegistry.new()
	var yaml := func(text: String, path: String) -> Dictionary: return Yaml.parse(text, path)
	f.register("yaml", yaml)
	f.register("yml", yaml)
	f.register("json", func(text: String, path: String) -> Dictionary:
		var j := JSON.new()
		var err := j.parse(_strip_json_comments(text))
		if err != OK:
			return {"ok": false, "value": null, "error": "%s:%d: %s" % [path, j.get_error_line(), j.get_error_message()]}
		return {"ok": true, "value": Data.ints_from_json(j.data), "error": ""})
	return f


## Разрешаем // и /* */ комментарии в JSON (JSONC), не трогая строки.
static func _strip_json_comments(text: String) -> String:
	if text.find("/") < 0:
		return text
	var out := PackedStringArray()
	var in_str := false
	var i := 0
	var n := text.length()
	var start := 0
	while i < n:
		var c = text[i]
		if in_str:
			if c == "\\":
				i += 1
			elif c == "\"":
				in_str = false
			i += 1
			continue
		if c == "\"":
			in_str = true
		elif c == "/" and i + 1 < n and text[i + 1] == "/":
			out.append(text.substr(start, i - start))
			while i < n and text[i] != "\n":
				i += 1
			start = i
			continue
		elif c == "/" and i + 1 < n and text[i + 1] == "*":
			out.append(text.substr(start, i - start))
			i += 2
			while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
				i += 1
			i += 2
			start = i
			continue
		i += 1
	out.append(text.substr(start))
	return "".join(out)

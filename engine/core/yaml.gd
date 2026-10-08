class_name Yaml
extends RefCounted
## Парсер YAML (подмножество YAML 1.2, схема core) — без внешних зависимостей.
##
## Поддерживается всё, что нужно файлам модов: блочные словари и списки,
## словари внутри элементов списка, flow-коллекции [a, b] и {k: v} (в том числе
## вложенные и многострочные), строки в двойных и одинарных кавычках,
## комментарии, null/bool/int/float. Не поддерживаются якоря (&, *), теги (!)
## и блочные скаляры (|, >) — для таких файлов парсер возвращает ошибку.
##
## Результат: { "ok": bool, "value": Variant, "error": String }.
## Ключи словарей — всегда строки; порядок ключей сохраняется.

static func parse(text: String, path: String = "") -> Dictionary:
	var p := _Parser.new(text, path)
	var value: Variant = p.parse_document()
	if p.error != "":
		return {"ok": false, "value": null, "error": p.error}
	return {"ok": true, "value": value, "error": ""}


## Разбор одного скаляра без кавычек по правилам схемы core.
static func resolve_plain(s: String) -> Variant:
	if s == "" or s == "~" or s == "null" or s == "Null" or s == "NULL":
		return null
	if s == "true" or s == "True" or s == "TRUE":
		return true
	if s == "false" or s == "False" or s == "FALSE":
		return false
	var c := s.unicode_at(0)
	# Быстрый выход: число начинается с цифры, знака или точки.
	if not ((c >= 48 and c <= 57) or c == 45 or c == 43 or c == 46):
		return s
	if _INT_RE().search(s) != null:
		return int(s)
	if s.begins_with("0x") and s.length() > 2 and s.substr(2).is_valid_hex_number():
		return s.substr(2).hex_to_int()
	if s.begins_with("0o") and s.length() > 2:
		var v := 0
		for i in range(2, s.length()):
			var d := s.unicode_at(i) - 48
			if d < 0 or d > 7:
				return s
			v = v * 8 + d
		return v
	if _FLOAT_RE().search(s) != null:
		return float(s)
	match s:
		".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF":
			return INF
		"-.inf", "-.Inf", "-.INF":
			return -INF
		".nan", ".NaN", ".NAN":
			return NAN
	return s


static var _int_re: RegEx
static var _float_re: RegEx

static func _INT_RE() -> RegEx:
	if _int_re == null:
		_int_re = RegEx.create_from_string("^[-+]?[0-9]+$")
	return _int_re


static func _FLOAT_RE() -> RegEx:
	if _float_re == null:
		_float_re = RegEx.create_from_string("^[-+]?(\\.[0-9]+|[0-9]+(\\.[0-9]*)?)([eE][-+]?[0-9]+)?$")
	return _float_re


class _Line:
	var indent: int
	var text: String
	var num: int

	func _init(i: int, t: String, n: int) -> void:
		indent = i
		text = t
		num = n


class _Parser:
	var path: String
	var lines: Array[_Line] = []
	var pos := 0
	var error := ""

	func _init(src: String, p: String) -> void:
		path = p
		_split(src)

	func fail(msg: String, line_num: int) -> void:
		if error == "":
			error = "%s:%d: %s" % [path, line_num, msg]

	# ---------------------------------------------------------- строки

	## Делит текст на логические строки: без комментариев и пустых строк,
	## многострочные flow-коллекции склеиваются в одну строку.
	func _split(src: String) -> void:
		var raw := src.replace("\r\n", "\n").replace("\r", "\n").split("\n")
		var i := 0
		while i < raw.size():
			var line: String = raw[i]
			var num := i + 1
			i += 1
			if i == 1 and line.begins_with("﻿"):
				line = line.substr(1)
			var stripped := _strip_comment(line).strip_edges(false, true)
			if stripped.strip_edges() == "" or stripped == "---":
				continue
			if stripped == "...":
				break
			var indent := 0
			while indent < stripped.length() and stripped[indent] == " ":
				indent += 1
			if indent < stripped.length() and stripped[indent] == "\t":
				fail("табуляция в отступе", num)
				return
			var text := stripped.substr(indent)
			# Незакрытые [ или { — склеиваем со следующими строками.
			var depth := _bracket_depth(text)
			while depth > 0 and i < raw.size():
				var more = _strip_comment(raw[i]).strip_edges()
				i += 1
				if more != "":
					text += " " + more
				depth = _bracket_depth(text)
			lines.append(_Line.new(indent, text, num))

	## Может ли в этой позиции начаться строка в кавычках.
	static func _quote_allowed(s: String, i: int) -> bool:
		var j := i - 1
		while j >= 0 and s[j] == " ":
			j -= 1
		if j < 0:
			return true
		return s[j] in [":", "-", "[", "{", ",", "?"]

	static func _strip_comment(s: String) -> String:
		var q := ""
		var i := 0
		var n := s.length()
		while i < n:
			var c = s[i]
			if q == "\"":
				if c == "\\":
					i += 1
				elif c == "\"":
					q = ""
			elif q == "'":
				if c == "'":
					if i + 1 < n and s[i + 1] == "'":
						i += 1
					else:
						q = ""
			elif (c == "\"" or c == "'") and _quote_allowed(s, i):
				q = c
			elif c == "#" and (i == 0 or s[i - 1] == " " or s[i - 1] == "\t"):
				return s.substr(0, i)
			i += 1
		return s

	static func _bracket_depth(s: String) -> int:
		var depth := 0
		var q := ""
		var i := 0
		var n := s.length()
		while i < n:
			var c = s[i]
			if q == "\"":
				if c == "\\":
					i += 1
				elif c == "\"":
					q = ""
			elif q == "'":
				if c == "'":
					q = ""
			elif (c == "\"" or c == "'") and _quote_allowed(s, i):
				q = c
			elif c == "[" or c == "{":
				depth += 1
			elif c == "]" or c == "}":
				depth -= 1
			i += 1
		return depth

	# ---------------------------------------------------------- блоки

	func parse_document() -> Variant:
		if error != "" or lines.is_empty():
			return null
		var v: Variant = parse_block(lines[0].indent)
		if error == "" and pos < lines.size():
			fail("неожиданный отступ", lines[pos].num)
		return v

	func _is_seq_item(t: String) -> bool:
		return t == "-" or t.begins_with("- ")

	func parse_block(indent: int) -> Variant:
		if pos >= lines.size():
			return null
		var line = lines[pos]
		if _is_seq_item(line.text):
			return parse_seq(line.indent)
		if _key_split(line.text) >= 0:
			return parse_map(line.indent)
		pos += 1
		return parse_inline(line.text, line.num)

	func parse_map(indent: int) -> Dictionary:
		var out := {}
		while error == "" and pos < lines.size():
			var line = lines[pos]
			if line.indent != indent or _is_seq_item(line.text):
				break
			var colon = _key_split(line.text)
			if colon < 0:
				fail("ожидался ключ «ключ: значение»", line.num)
				break
			var key = _parse_key(line.text.substr(0, colon).strip_edges(), line.num)
			var rest = line.text.substr(colon + 1).strip_edges()
			pos += 1
			var value: Variant = null
			if rest == "":
				if pos < lines.size():
					var nxt = lines[pos]
					if nxt.indent > indent or (nxt.indent == indent and _is_seq_item(nxt.text)):
						value = parse_block(nxt.indent)
			else:
				value = parse_inline(rest, line.num)
			if out.has(key):
				fail("ключ «%s» повторяется" % key, line.num)
				break
			out[key] = value
		if error == "" and pos < lines.size() and lines[pos].indent > indent:
			fail("неожиданный отступ", lines[pos].num)
		return out

	func parse_seq(indent: int) -> Array:
		var out := []
		while error == "" and pos < lines.size():
			var line = lines[pos]
			if line.indent != indent or not _is_seq_item(line.text):
				break
			var rest = line.text.substr(1)
			var spaces := 0
			while spaces < rest.length() and rest[spaces] == " ":
				spaces += 1
			rest = rest.substr(spaces)
			if rest == "":
				pos += 1
				if pos < lines.size() and lines[pos].indent > indent:
					out.append(parse_block(lines[pos].indent))
				else:
					out.append(null)
			elif _is_seq_item(rest) or _key_split(rest) >= 0:
				# «- ключ: значение» или «- - …»: содержимое элемента начинается
				# в той же строке; подменяем строку виртуальной с нужным отступом.
				var col := indent + 1 + spaces
				lines[pos] = _Line.new(col, rest, line.num)
				out.append(parse_block(col))
			else:
				pos += 1
				out.append(parse_inline(rest, line.num))
		return out

	## Позиция двоеточия, отделяющего ключ, или -1.
	func _key_split(t: String) -> int:
		if t == "" or t[0] == "[" or t[0] == "{":
			return -1
		var i := 0
		var n := t.length()
		if t[0] == "\"" or t[0] == "'":
			var q = t[0]
			i = 1
			while i < n:
				if q == "\"" and t[i] == "\\":
					i += 2
					continue
				if t[i] == q:
					if q == "'" and i + 1 < n and t[i + 1] == "'":
						i += 2
						continue
					break
				i += 1
			i += 1
			while i < n and t[i] == " ":
				i += 1
			if i < n and t[i] == ":" and (i + 1 == n or t[i + 1] == " "):
				return i
			return -1
		while i < n:
			if t[i] == ":" and (i + 1 == n or t[i + 1] == " "):
				return i
			i += 1
		return -1

	func _parse_key(k: String, num: int) -> String:
		if k.begins_with("\"") or k.begins_with("'"):
			var fp := _Flow.new(k, self, num)
			var v: Variant = fp.parse_quoted()
			return str(v)
		return k

	## Значение в той же строке, что и ключ: flow-коллекция, строка в кавычках или скаляр.
	func parse_inline(t: String, num: int) -> Variant:
		var c = t[0]
		if c == "[" or c == "{" or c == "\"" or c == "'":
			var fp := _Flow.new(t, self, num)
			var v: Variant = fp.parse_value(false)
			fp.skip_ws()
			if fp.i < t.length() and error == "":
				fail("лишние символы после значения: «%s»" % t.substr(fp.i), num)
			return v
		if c == "&" or c == "*" or c == "!":
			fail("якоря, ссылки и теги YAML не поддерживаются", num)
			return null
		if (c == "|" or c == ">") and (t.length() == 1 or t[1] in ["-", "+", " "] or t.substr(1).is_valid_int()):
			fail("блочные строки (| и >) не поддерживаются — используйте строку в кавычках", num)
			return null
		return Yaml.resolve_plain(t)


## Разбор flow-синтаксиса и строк в кавычках внутри одной строки.
class _Flow:
	var s: String
	var i := 0
	var parser: _Parser
	var num: int

	func _init(text: String, p: _Parser, line_num: int) -> void:
		s = text
		parser = p
		num = line_num

	func skip_ws() -> void:
		while i < s.length() and s[i] == " ":
			i += 1

	func parse_value(in_flow: bool) -> Variant:
		skip_ws()
		if i >= s.length():
			return null
		var c = s[i]
		if c == "[":
			return parse_list()
		if c == "{":
			return parse_map()
		if c == "\"" or c == "'":
			return parse_quoted()
		return parse_plain(in_flow, false)

	func parse_list() -> Array:
		var out := []
		i += 1
		while parser.error == "":
			skip_ws()
			if i >= s.length():
				parser.fail("не закрыта скобка ]", num)
				break
			if s[i] == "]":
				i += 1
				break
			out.append(parse_value(true))
			skip_ws()
			if i < s.length() and s[i] == ",":
				i += 1
			elif i < s.length() and s[i] != "]":
				parser.fail("ожидалась запятая или ]", num)
				break
		return out

	func parse_map() -> Dictionary:
		var out := {}
		i += 1
		while parser.error == "":
			skip_ws()
			if i >= s.length():
				parser.fail("не закрыта скобка }", num)
				break
			if s[i] == "}":
				i += 1
				break
			var key: String
			if s[i] == "\"" or s[i] == "'":
				key = str(parse_quoted())
			else:
				key = str(parse_plain(true, true))
			skip_ws()
			var value: Variant = null
			if i < s.length() and s[i] == ":":
				i += 1
				value = parse_value(true)
			if out.has(key):
				parser.fail("ключ «%s» повторяется" % key, num)
				break
			out[key] = value
			skip_ws()
			if i < s.length() and s[i] == ",":
				i += 1
			elif i < s.length() and s[i] != "}":
				parser.fail("ожидалась запятая или }", num)
				break
		return out

	func parse_plain(in_flow: bool, is_key: bool) -> Variant:
		var start := i
		var n := s.length()
		while i < n:
			var c = s[i]
			if in_flow and (c == "," or c == "]" or c == "}"):
				break
			if is_key and c == ":" and (i + 1 == n or s[i + 1] in [" ", ",", "}", "]"]):
				break
			if in_flow and not is_key and c == ":" and i + 1 < n and s[i + 1] == " ":
				break
			i += 1
		var t := s.substr(start, i - start).strip_edges()
		return t if is_key else Yaml.resolve_plain(t)

	func parse_quoted() -> String:
		var q = s[i]
		i += 1
		var out := ""
		var n := s.length()
		while i < n:
			var c = s[i]
			if q == "'":
				if c == "'":
					if i + 1 < n and s[i + 1] == "'":
						out += "'"
						i += 2
						continue
					i += 1
					return out
				out += c
				i += 1
				continue
			if c == "\"":
				i += 1
				return out
			if c == "\\" and i + 1 < n:
				var e = s[i + 1]
				i += 2
				match e:
					"n": out += "\n"
					"t": out += "\t"
					"r": out += "\r"
					"0": pass  # NUL в строках не нужен
					"\\": out += "\\"
					"\"": out += "\""
					"/": out += "/"
					" ": out += " "
					"_": out += " "
					"e": out += char(27)
					"x", "u", "U":
						var len = 2 if e == "x" else (4 if e == "u" else 8)
						out += char(s.substr(i, len).hex_to_int())
						i += len
					_: out += e
				continue
			out += c
			i += 1
		parser.fail("не закрыта кавычка", num)
		return out

class_name BB
extends RefCounted
## Сборка BBCode для подсказок и текстов: цвета, ссылки, иконки, таблицы
## разбивки («Доход: +3,2 …»).

const GOLD := "#e3c06a"
const GOOD := "#8fd16a"
const BAD := "#ef6d5c"
const WARN := "#e8b84a"
const MUTED := "#a49577"
const LINK := "#f0d48a"


static func esc(s: Variant) -> String:
	return str(s).replace("[", "[lb]")


static func c(s: Variant, color: String) -> String:
	return "[color=%s]%s[/color]" % [color, esc(s)]


static func good(s: Variant) -> String:
	return c(s, GOOD)


static func bad(s: Variant) -> String:
	return c(s, BAD)


static func warn(s: Variant) -> String:
	return c(s, WARN)


static func muted(s: Variant) -> String:
	return c(s, MUTED)


static func gold(s: Variant) -> String:
	return c(s, GOLD)


static func b(s: Variant) -> String:
	return "[b]%s[/b]" % esc(s)


static func i(s: Variant) -> String:
	return "[i]%s[/i]" % esc(s)


static func small(s: String) -> String:
	return "[font_size=13]%s[/font_size]" % s


## Заголовок подсказки.
static func title(s: Variant) -> String:
	return "[font_size=17][color=%s][b]%s[/b][/color][/font_size]" % [GOLD, esc(s)]


static func link(kind: String, id: Variant, text: Variant, color: String = LINK) -> String:
	return "[url=%s:%s][color=%s]%s[/color][/url]" % [kind, id, color, esc(text)]


static func char_link(game: Game, id: Variant, with_rank: bool = false) -> String:
	var ch: Variant = game.ch(id)
	if ch == null:
		return muted("—")
	var name := Chars.full_name(game, ch, with_rank)
	if ch.death != null:
		return link("char", id, name + " ✝", "#b0a38a")
	return link("char", id, name, "#ffe08a" if game.is_player(id) else LINK)


static func title_link(game: Game, id: Variant) -> String:
	if id == null:
		return muted("—")
	return link("title", id, Titles.full_name(game, id))


static func prov_link(game: Game, id: Variant) -> String:
	if id == null:
		return muted("—")
	return link("prov", id, game.name_of("provinces", id))


static func icon(name: Variant, size: int = 16) -> String:
	var n := Icons.resolve(name)
	if n == "":
		return esc(str(name))
	return "[img=%dx%d]%s[/img]" % [size, size, Icons.bb_path(n, size)]


## Число со знаком и цветом (positive_good = false — для «плохих» величин).
static func signed(v: float, digits: int = 0, positive_good: bool = true) -> String:
	var s := K.signed(v, digits)
	if absf(v) < pow(10.0, -digits) * 0.5:
		return muted(s)
	return good(s) if (v > 0) == positive_good else bad(s)


## Таблица «название — значение».
static func rows(pairs: Array) -> String:
	if pairs.is_empty():
		return ""
	var out := "[table=2]"
	for p in pairs:
		out += "[cell expand=1]%s[/cell][cell]   %s[/cell]" % [p[0], p[1]]
	return out + "[/table]"


## Разбивка величины: [{label, value}] → таблица со знаками.
static func breakdown(parts: Array, digits: int = 0) -> String:
	var pairs := []
	for p in parts:
		if p == null:
			continue
		pairs.append([esc(p.label), signed(float(p.value), digits)])
	return rows(pairs)


## Модификаторы {stat: value} → таблица.
static func modifiers(game: Game, mods: Variant) -> String:
	if not (mods is Dictionary) or mods.is_empty():
		return ""
	var pairs := []
	for k in mods:
		var v := float(mods[k])
		var is_bad := v > 0 if k == "stress_gain_mult" else v < 0
		var pct: bool = "mult" in k or k == "fertility"
		var val := ("%s%d%%" % ["+" if v > 0 else "", roundi(v * 100)]) if pct else K.signed(v, 1 if absf(v) < 1 else 0)
		pairs.append([esc(game.loc.t_or("stat." + k, k)), bad(val) if is_bad else good(val)])
	return rows(pairs)


## Строки описания эффекта [{text, depth}].
static func desc_lines(lines: Array) -> String:
	var out := PackedStringArray()
	for l in lines:
		out.append("   ".repeat(int(l.depth)) + "• " + esc(l.text))
	return "\n".join(out)


static func effect(game: Game, block: Variant, root: Dictionary, scopes: Dictionary = {}, header: String = "") -> String:
	var ctx := ScriptContext.make(game, root, scopes)
	var lines: Array = Interp.describe_effect(ctx, root, block)
	var out := title(header) + "\n" if header != "" else ""
	return out + desc_lines(lines)


static func reasons(list: Array) -> String:
	if list.is_empty():
		return ""
	var out := PackedStringArray()
	for r in list:
		out.append(bad("✗ " + str(r)))
	return "\n".join(out)


static func cost(game: Game, cost_d: Variant) -> String:
	if not (cost_d is Dictionary):
		return muted(game.loc.t("ui.free"))
	var parts := PackedStringArray()
	if Data.num(cost_d.get("gold")) != 0:
		parts.append("%s %s" % [icon("gold"), K.fmt(Data.num(cost_d.gold))])
	if Data.num(cost_d.get("prestige")) != 0:
		parts.append("%s %s" % [icon("prestige"), K.fmt(Data.num(cost_d.prestige))])
	if Data.num(cost_d.get("piety")) != 0:
		parts.append("%s %s" % [icon("piety"), K.fmt(Data.num(cost_d.piety))])
	return "  ".join(parts) if not parts.is_empty() else muted(game.loc.t("ui.free"))

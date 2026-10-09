class_name Morph
extends RefCounted
## Обновление показанного дерева интерфейса «на месте». Новое содержимое
## собирается вне сцены; если его структура совпадает со старой (те же типы
## узлов и число детей), в старые узлы переносятся тексты, текстуры,
## переопределения темы, метаданные (подсказки) и обработчики сигналов.
## Вставка нового дерева в сцену дорогая (тема, раскладка, шейпинг текста),
## а перенос — нет; к тому же сохраняются прокрутка и наведение.
##
## Обработчики переносятся как есть, поэтому они не должны ссылаться на узлы
## собираемого дерева (только на данные, app и т. п.) — так устроены панели.

const _P_CONTROL := ["visible", "modulate", "self_modulate", "custom_minimum_size",
	"size_flags_horizontal", "size_flags_vertical", "mouse_filter", "mouse_default_cursor_shape", "theme_type_variation"]
const _P_LABEL := ["text", "horizontal_alignment", "vertical_alignment", "autowrap_mode",
	"clip_text", "text_overrun_behavior", "label_settings", "uppercase"]
const _P_RICH := ["bbcode_enabled", "fit_content", "scroll_active", "autowrap_mode", "horizontal_alignment", "text"]
const _P_BUTTON := ["text", "icon", "disabled", "toggle_mode", "flat", "alignment", "expand_icon", "icon_alignment", "clip_text"]
const _P_TEXRECT := ["texture", "expand_mode", "stretch_mode", "flip_h", "flip_v"]
const _P_RANGE := ["min_value", "max_value", "step"]
const _P_BOX := ["alignment"]
const _P_GRID := ["columns"]
const _P_COLORRECT := ["color"]
const _P_SCROLL := ["horizontal_scroll_mode", "vertical_scroll_mode"]

const _C_TEXT := ["font_color", "font_outline_color", "font_hover_color", "font_pressed_color", "default_color"]
const _K_TEXT := ["outline_size", "line_spacing", "h_separation"]
const _F_TEXT := ["font", "normal_font", "bold_font"]
const _S_TEXT := ["font_size", "normal_font_size", "bold_font_size", "italics_font_size"]
const _ST_BUTTON := ["normal", "hover", "pressed", "disabled", "focus"]
const _ST_PANEL := ["panel"]
const _ST_RANGE := ["fill", "background"]
const _K_CONTAINER := ["separation", "h_separation", "v_separation",
	"margin_left", "margin_top", "margin_right", "margin_bottom"]

const _SIG_CONTROL := ["gui_input"]
const _SIG_BUTTON := ["pressed", "toggled"]
const _SIG_RICH := ["meta_clicked", "meta_hover_started"]
const _SIG_OPTION := ["item_selected"]
const _SIG_RANGE := ["value_changed"]


## Перенести neo в old. false — структура отличается (old не тронут).
static func apply(old: Node, neo: Node) -> bool:
	if not same_shape(old, neo):
		return false
	_copy(old, neo)
	return true


static func same_shape(a: Node, b: Node) -> bool:
	if a.get_class() != b.get_class() or a.get_script() != b.get_script():
		return false
	var n := a.get_child_count()
	if n != b.get_child_count():
		return false
	for i in n:
		if not same_shape(a.get_child(i), b.get_child(i)):
			return false
	return true


static func _copy(a: Node, b: Node) -> void:
	if a is Control:
		_node(a, b)
	for i in a.get_child_count():
		_copy(a.get_child(i), b.get_child(i))


static func _node(a: Control, b: Control) -> void:
	_props(a, b, _P_CONTROL)
	_signals(a, b, _SIG_CONTROL)
	if a is Label:
		_props(a, b, _P_LABEL)
		_text_overrides(a, b)
	elif a is RichTextLabel:
		_props(a, b, _P_RICH)
		_text_overrides(a, b)
		_signals(a, b, _SIG_RICH)
	elif a is BaseButton:
		_props(a, b, _P_BUTTON)
		var bb := b as BaseButton
		if (a as BaseButton).button_pressed != bb.button_pressed:
			(a as BaseButton).set_pressed_no_signal(bb.button_pressed)
		_text_overrides(a, b)
		_styles(a, b, _ST_BUTTON)
		_signals(a, b, _SIG_BUTTON)
		if a is OptionButton:
			_signals(a, b, _SIG_OPTION)
	elif a is TextureRect:
		_props(a, b, _P_TEXRECT)
	elif a is Range:
		_props(a, b, _P_RANGE)
		if (a as Range).value != (b as Range).value:
			(a as Range).set_value_no_signal((b as Range).value)
		if a is ProgressBar:
			_props(a, b, ["show_percentage"])
		_styles(a, b, _ST_RANGE)
		_text_overrides(a, b)
		_signals(a, b, _SIG_RANGE)
	elif a is ColorRect:
		_props(a, b, _P_COLORRECT)
	elif a is Container:
		_consts(a, b, _K_CONTAINER)
		if a is BoxContainer or a is FlowContainer:
			_props(a, b, _P_BOX)
		elif a is GridContainer:
			_props(a, b, _P_GRID)
		elif a is ScrollContainer:
			_props(a, b, _P_SCROLL)
		if a is PanelContainer:
			_styles(a, b, _ST_PANEL)
	elif a is Panel:
		_styles(a, b, _ST_PANEL)
	_metas(a, b)
	if a.get_script() != null:
		_script_vars(a, b)
		a.queue_redraw()


static func _differs(x: Variant, y: Variant) -> bool:
	return typeof(x) != typeof(y) or x != y


static func _props(a: Object, b: Object, names: Array) -> void:
	for p in names:
		var v: Variant = b.get(p)
		if _differs(a.get(p), v):
			a.set(p, v)


static func _script_vars(a: Object, b: Object) -> void:
	for p in (b.get_script() as Script).get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v: Variant = b.get(p.name)
			if _differs(a.get(p.name), v):
				a.set(p.name, v)


static func _metas(a: Object, b: Object) -> void:
	for m in a.get_meta_list():
		if not b.has_meta(m):
			a.remove_meta(m)
	for m in b.get_meta_list():
		a.set_meta(m, b.get_meta(m))


static func _signals(a: Object, b: Object, names: Array) -> void:
	for s in names:
		var bc := b.get_signal_connection_list(s)
		var ac := a.get_signal_connection_list(s)
		if bc.is_empty() and ac.is_empty():
			continue
		for c in ac:
			if _scripted(c.callable):
				a.disconnect(s, c.callable)
		for c in bc:
			if _scripted(c.callable):
				a.connect(s, c.callable, c.flags)


## Обработчик из скрипта (лямбда или метод скрипта), а не внутренний
## обработчик движка (например, полосы прокрутки) — только такие переносим.
static func _scripted(c: Callable) -> bool:
	var o: Object = c.get_object()
	return o == null or o is Script or o.get_script() != null


static func _text_overrides(a: Control, b: Control) -> void:
	for n in _C_TEXT:
		if b.has_theme_color_override(n):
			var v := b.get_theme_color(n)
			if not a.has_theme_color_override(n) or a.get_theme_color(n) != v:
				a.add_theme_color_override(n, v)
		elif a.has_theme_color_override(n):
			a.remove_theme_color_override(n)
	_consts(a, b, _K_TEXT)
	for n in _F_TEXT:
		if b.has_theme_font_override(n):
			var f := b.get_theme_font(n)
			if not a.has_theme_font_override(n) or a.get_theme_font(n) != f:
				a.add_theme_font_override(n, f)
		elif a.has_theme_font_override(n):
			a.remove_theme_font_override(n)
	for n in _S_TEXT:
		if b.has_theme_font_size_override(n):
			var v := b.get_theme_font_size(n)
			if not a.has_theme_font_size_override(n) or a.get_theme_font_size(n) != v:
				a.add_theme_font_size_override(n, v)
		elif a.has_theme_font_size_override(n):
			a.remove_theme_font_size_override(n)


static func _consts(a: Control, b: Control, names: Array) -> void:
	for n in names:
		if b.has_theme_constant_override(n):
			var v := b.get_theme_constant(n)
			if not a.has_theme_constant_override(n) or a.get_theme_constant(n) != v:
				a.add_theme_constant_override(n, v)
		elif a.has_theme_constant_override(n):
			a.remove_theme_constant_override(n)


static func _styles(a: Control, b: Control, names: Array) -> void:
	for n in names:
		if b.has_theme_stylebox_override(n):
			var v := b.get_theme_stylebox(n)
			if not a.has_theme_stylebox_override(n) or not _same_style(a.get_theme_stylebox(n), v):
				a.add_theme_stylebox_override(n, v)
		elif a.has_theme_stylebox_override(n):
			a.remove_theme_stylebox_override(n)


## Одинаковые ли стили (новые StyleBoxFlat создаются при каждой сборке).
static func _same_style(x: StyleBox, y: StyleBox) -> bool:
	if x == y:
		return true
	if not (x is StyleBoxFlat and y is StyleBoxFlat):
		return false
	var p := x as StyleBoxFlat
	var q := y as StyleBoxFlat
	return p.bg_color == q.bg_color and p.border_color == q.border_color \
		and p.border_width_left == q.border_width_left and p.border_width_top == q.border_width_top \
		and p.border_width_right == q.border_width_right and p.border_width_bottom == q.border_width_bottom \
		and p.corner_radius_top_left == q.corner_radius_top_left and p.corner_radius_bottom_right == q.corner_radius_bottom_right \
		and p.content_margin_left == q.content_margin_left and p.content_margin_top == q.content_margin_top \
		and p.content_margin_right == q.content_margin_right and p.content_margin_bottom == q.content_margin_bottom \
		and p.shadow_size == q.shadow_size and p.shadow_color == q.shadow_color \
		and p.expand_margin_left == q.expand_margin_left and p.expand_margin_bottom == q.expand_margin_bottom

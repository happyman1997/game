class_name TooltipLayer
extends Control
## Подсказки в стиле CK3: появляются у курсора с небольшой задержкой.
## Источник — метаданные «tip» у элемента под курсором (или его предков):
## строка BBCode или Callable, возвращающая строку/Control (вычисляется лениво
## и обновляется, пока подсказка видна — так работает подсказка карты).

const DELAY := 0.35
const MAX_W := 400.0

var panel: PanelContainer
var text: RichTextLabel
var custom_holder: Control
var _owner: Control
var _since := 0.0
var _shown := false
var _refresh := 0.0
var _last_content: Variant = null
var _blocked_at: Variant = null
## Если задано: подсказки только у элементов внутри этого узла (открыто модальное окно).
var scope: Callable


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.theme_type_variation = "TooltipPanel"
	panel.add_theme_stylebox_override("panel", UiArt.tooltip_box())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_size_override("normal_font_size", 14)
	text.add_theme_font_size_override("bold_font_size", 14)
	text.add_theme_font_size_override("italics_font_size", 14)
	box.add_child(text)
	custom_holder = VBoxContainer.new()
	custom_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(custom_holder)


func _find_owner(c: Control) -> Control:
	var n: Node = c
	while n != null and n is Control:
		if n.has_meta("tip"):
			return n
		n = n.get_parent()
	return null


func hide_tip() -> void:
	panel.visible = false
	_shown = false
	_last_content = null


## Скрыть и не показывать, пока мышь не сдвинется (после открытия окна).
func block() -> void:
	hide_tip()
	_owner = null
	_blocked_at = get_viewport().get_mouse_position()


func _process(delta: float) -> void:
	var vp := get_viewport()
	var hovered := vp.gui_get_hovered_control()
	var owner := _find_owner(hovered) if hovered != null else null
	if _blocked_at != null:
		if get_viewport().get_mouse_position().distance_to(_blocked_at) < 3.0:
			owner = null
		else:
			_blocked_at = null
	if owner != null and scope.is_valid():
		var root: Variant = scope.call()
		if root is Node and not (root as Node).is_ancestor_of(owner):
			owner = null
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		owner = null
		_since = -0.2
	if owner != _owner:
		_owner = owner
		_since = 0.0
		hide_tip()
	if _owner == null:
		return
	_since += delta
	if not _shown and _since >= DELAY:
		_shown = _update_content()
		_refresh = 0.15
	elif _shown:
		_refresh -= delta
		if _refresh <= 0.0:
			_refresh = 0.15
			_shown = _update_content()
	if _shown:
		_place()


func _resolve() -> Variant:
	if _owner == null or not is_instance_valid(_owner):
		return null
	var c: Variant = _owner.get_meta("tip")
	if c is Callable:
		c = (c as Callable).call()
	return c


func _update_content() -> bool:
	var content: Variant = _resolve()
	if content == null or (content is String and content == ""):
		panel.visible = false
		_last_content = null
		return false
	if content is String:
		if content != _last_content:
			_last_content = content
			for ch in custom_holder.get_children():
				ch.queue_free()
			text.visible = true
			_set_text(content)
	elif content is Control:
		if _last_content is Control and is_instance_valid(_last_content):
			_last_content.queue_free()
		for ch in custom_holder.get_children():
			ch.queue_free()
		text.visible = false
		custom_holder.add_child(content)
		_last_content = content
	panel.visible = true
	return true


func _set_text(bb: String) -> void:
	# Ширина по содержимому (не больше MAX_W): меряем самую длинную строку.
	var plain := bb
	var re := RegEx.create_from_string("\\[[^\\]]*\\]")
	plain = re.sub(plain, "", true)
	var font := Fonts.regular()
	var w := 0.0
	for line in plain.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	if bb.contains("[table"):
		w += 40
	text.custom_minimum_size.x = clampf(w + 6, 60.0, MAX_W)
	text.text = bb
	panel.reset_size()


func _place() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var m := get_viewport().get_mouse_position()
	panel.reset_size()
	var s := panel.size
	var p := m + Vector2(18, 20)
	if p.x + s.x > vp_size.x - 4:
		p.x = m.x - s.x - 14
	if p.y + s.y > vp_size.y - 4:
		p.y = maxf(4.0, vp_size.y - s.y - 4)
	panel.position = p.max(Vector2(4, 4))

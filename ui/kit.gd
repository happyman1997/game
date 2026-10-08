class_name K
extends RefCounted
## Короткие конструкторы элементов интерфейса, чтобы панели собирались
## декларативно: K.vbox([K.header("…"), K.hbox([...])]).
## Подсказка: K.tip(node, "BBCode" | Callable() -> String|Control).

const BODY := 15


static func _add_all(parent: Node, children: Array) -> void:
	for c in children:
		if c == null:
			continue
		if c is Array:
			_add_all(parent, c)
		elif c is Node:
			parent.add_child(c)
		else:
			parent.add_child(label(str(c)))


static func label(text: Variant, variation: String = "", tip_content: Variant = null) -> Label:
	var l := Label.new()
	l.text = str(text) if text != null else ""
	if variation != "":
		l.theme_type_variation = variation
	if tip_content != null:
		tip(l, tip_content)
	return l


## Надпись с переносом строк по ширине родителя.
static func para(text: Variant, variation: String = "") -> Label:
	var l := label(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 40
	return l


## BBCode-текст. wrap = false — одна строка по ширине содержимого.
static func rich(bbcode: String, wrap: bool = true, variation: String = "") -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = false
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	if variation != "":
		r.theme_type_variation = variation
	if wrap:
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.custom_minimum_size.x = 40
	else:
		r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.text = bbcode
	r.meta_clicked.connect(func(meta): App.locked(_on_meta.bind(meta)))
	r.meta_hover_started.connect(func(_m): pass)
	return r


## Ссылки в BBCode: [url=char:ID], [url=title:ID], [url=prov:ID], [url=tab:ID].
static func _on_meta(meta: Variant) -> void:
	var s := str(meta)
	var app: Variant = App.instance
	if app == null:
		return
	var i := s.find(":")
	if i < 0:
		return
	var kind := s.substr(0, i)
	var id := s.substr(i + 1)
	match kind:
		"char": app.open_character(id)
		"title": app.open_title(id)
		"prov": app.open_province(id, true)
		"tab": app.open_tab(id)


static func hbox(children: Array = [], sep: int = -1, align: int = BoxContainer.ALIGNMENT_BEGIN) -> HBoxContainer:
	var b := HBoxContainer.new()
	if sep >= 0:
		b.add_theme_constant_override("separation", sep)
	b.alignment = align
	_add_all(b, children)
	return b


static func vbox(children: Array = [], sep: int = -1) -> VBoxContainer:
	var b := VBoxContainer.new()
	if sep >= 0:
		b.add_theme_constant_override("separation", sep)
	_add_all(b, children)
	return b


static func grid(columns: int, children: Array = [], hsep: int = -1, vsep: int = -1) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	if hsep >= 0:
		g.add_theme_constant_override("h_separation", hsep)
	if vsep >= 0:
		g.add_theme_constant_override("v_separation", vsep)
	_add_all(g, children)
	return g


static func flow(children: Array = [], sep: int = -1) -> HFlowContainer:
	var f := HFlowContainer.new()
	if sep >= 0:
		f.add_theme_constant_override("h_separation", sep)
		f.add_theme_constant_override("v_separation", sep)
	_add_all(f, children)
	return f


static func panel(child: Variant = null, variation: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	if child != null:
		_add_all(p, [child])
	return p


static func margin(child: Variant, l: int, t: int = -1, r: int = -1, b: int = -1) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t if t >= 0 else l)
	m.add_theme_constant_override("margin_right", r if r >= 0 else l)
	m.add_theme_constant_override("margin_bottom", b if b >= 0 else (t if t >= 0 else l))
	if child != null:
		_add_all(m, [child])
	return m


static func center(child: Variant) -> CenterContainer:
	var c := CenterContainer.new()
	_add_all(c, [child])
	return c


static func scroll(child: Variant, horizontal: bool = false) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if child is Control:
		(child as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_all(s, [child])
	return s


## Кнопка. opts: disabled, tip, variation, icon (имя или эмодзи), icon_size,
## min_w, min_h, toggled (bool — нажатое состояние), align.
static func button(text: Variant, on_press: Callable, opts: Dictionary = {}) -> Button:
	var b := Button.new()
	b.text = str(text) if text != null else ""
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if opts.has("variation"):
		b.theme_type_variation = opts.variation
	if opts.get("disabled", false):
		b.disabled = true
	if opts.has("icon") and opts.icon != null:
		var n := Icons.resolve(opts.icon)
		if n != "":
			b.icon = Icons.texture(n, int(opts.get("icon_size", 18)))
		else:
			b.text = str(opts.icon) + (" " + b.text if b.text != "" else "")
	if opts.has("min_w"):
		b.custom_minimum_size.x = opts.min_w
	if opts.has("min_h"):
		b.custom_minimum_size.y = opts.min_h
	if opts.has("align"):
		b.alignment = opts.align
	if opts.get("toggled", false):
		b.toggle_mode = true
		b.button_pressed = true
	if opts.has("tip") and opts.tip != null:
		tip(b, opts.tip)
	b.pressed.connect(func():
		if b.toggle_mode:
			b.set_pressed_no_signal(opts.get("toggled", false))
		App.locked(on_press))
	return b


## Круглая кнопка с нарисованной иконкой (вкладки, режимы карты).
static func round_button(icon: Variant, on_press: Callable, tip_content: Variant = null, size: int = 40, active: bool = false) -> Button:
	var b := Button.new()
	b.theme_type_variation = "RoundButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(size, size)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var n := Icons.resolve(icon)
	if n != "":
		b.icon = Icons.texture(n, int(size * 0.5))
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = false
	else:
		b.text = str(icon)
		b.add_theme_font_size_override("font_size", int(size * 0.42))
	if active:
		b.toggle_mode = true
		b.button_pressed = true
	if tip_content != null:
		tip(b, tip_content)
	b.pressed.connect(func():
		if b.toggle_mode:
			b.set_pressed_no_signal(active)
		App.locked(on_press))
	return b


static func icon(name: Variant, size: int = 20, tint: String = "gold") -> Control:
	return Icons.node(name, size, tint)


static func tex(texture: Texture2D, size: Vector2 = Vector2.ZERO) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = size if size != Vector2.ZERO else (texture.get_size() if texture != null else Vector2.ZERO)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


static func spacer(w: float = 0, h: float = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func expand() -> Control:
	var c := spacer()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func sep() -> HSeparator:
	return HSeparator.new()


static func header(text: String, variation: String = "HeaderLabel") -> Label:
	return label(text, variation)


## Секция окна: заголовок с орнаментом и содержимое.
static func section(title: String, children: Array = [], icon_name: Variant = null) -> VBoxContainer:
	var head := hbox([], 6)
	if icon_name != null:
		head.add_child(icon(icon_name, 18))
	head.add_child(label(title, "SubheaderLabel"))
	var box := vbox([head], 4)
	var line := ColorRect.new()
	line.color = Color(UiArt.GOLD, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	_add_all(box, children)
	return box


static func bar(value: float, max_value: float, color: Color = Color("#b8913f"), height: int = 8, text: String = "") -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = maxf(1e-9, max_value)
	p.value = clampf(value, 0.0, p.max_value)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(40, height)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("fill", UiArt.bar_fill(color))
	if text != "":
		p.show_percentage = false
		var l := label(text, "SmallLabel")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


## Подсказка: BBCode-строка или Callable, возвращающая строку или Control.
static func tip(node: Control, content: Variant) -> Control:
	if content == null or (content is String and content == ""):
		if node.has_meta("tip"):
			node.remove_meta("tip")
		return node
	node.set_meta("tip", content)
	if node.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	return node


## Клик левой кнопкой по любому элементу.
static func on_click(node: Control, cb: Callable, right_cb: Callable = Callable()) -> Control:
	if node.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				App.locked(cb)
				node.accept_event()
			elif e.button_index == MOUSE_BUTTON_RIGHT and right_cb.is_valid():
				App.locked(right_cb)
				node.accept_event())
	return node


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func expand_h(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func min_size(c: Control, w: float, h: float = 0) -> Control:
	c.custom_minimum_size = Vector2(w, h)
	return c


# ------------------------------------------------------------ числа

static func fmt(n: float, digits: int = 0) -> String:
	var v := snappedf(n, pow(10.0, -digits)) if digits > 0 else roundf(n)
	var neg := v < 0
	var s := String.num(absf(v), digits)
	if digits > 0 and not s.contains("."):
		s += "." + "0".repeat(digits)
	var int_part := s.split(".")[0]
	var frac := s.substr(int_part.length())
	var grouped := ""
	var cnt := 0
	for i in range(int_part.length() - 1, -1, -1):
		grouped = int_part[i] + grouped
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			grouped = " " + grouped
	return ("-" if neg else "") + grouped + frac.replace(".", ",")


static func signed(n: float, digits: int = 0) -> String:
	var v := snappedf(n, pow(10.0, -digits)) if digits > 0 else roundf(n)
	var s := fmt(n, digits)
	return "+" + s if v > 0 else s

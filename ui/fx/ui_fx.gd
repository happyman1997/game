class_name UiFx
extends RefCounted
## Живость интерфейса (как в CK3): каждая кнопка — где бы её ни создали —
## мягко подсвечивается при наведении и «вдавливается» при нажатии, щёлкает
## и шелестит; окна выезжают, модальные окна раскрываются, подсказки и
## уведомления проявляются. Подключается один раз: UiFx.install(app).
## Кнопка с метой "silent" не звучит при нажатии (звук даёт само действие).

const HOVER_TINT := Color(1.16, 1.12, 1.04)
const PRESS_TINT := Color(0.82, 0.8, 0.76)

static var _last_motion := -100000


static func install(app: Node) -> void:
	UiSound.setup(app)
	app.get_tree().node_added.connect(_on_node_added)
	UiSound.warm_up.call_deferred()


## Мышь двигалась — наведение настоящее, а не кнопка, пересобранная под курсором.
static func note_motion() -> void:
	_last_motion = Time.get_ticks_msec()


static func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("fx"):
		_wire(n)


static func _wire(b: BaseButton) -> void:
	b.set_meta("fx", true)
	b.mouse_entered.connect(func(): _hover(b, true))
	b.mouse_exited.connect(func(): _hover(b, false))
	b.button_down.connect(func(): _press(b, true))
	b.button_up.connect(func(): _press(b, false))
	b.pressed.connect(func():
		if not b.has_meta("silent"):
			UiSound.play(_click_sound(b)))
	b.gui_input.connect(func(e: InputEvent):
		if b.disabled and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			UiSound.play("error"))


static func _round(b: BaseButton) -> bool:
	var v := b.theme_type_variation
	return v == &"RoundButton" or v == &"TabButton" or v == &"CloseButton"


static func _click_sound(b: BaseButton) -> String:
	match b.theme_type_variation:
		&"GoldButton": return "click_gold"
		&"FlatButton", &"LinkText": return "click_soft"
		&"WindowTab": return "tab"
		&"EventOption": return "click"
	if b is CheckBox or b is CheckButton:
		return "click_soft"
	return "click"


static func _tween(b: Control) -> Tween:
	if b.has_meta("fx_tween"):
		var old: Variant = b.get_meta("fx_tween")
		if old is Tween and old.is_valid():
			old.kill()
	var tw := b.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	b.set_meta("fx_tween", tw)
	return tw


static func _hover(b: BaseButton, on: bool) -> void:
	# погасшая кнопка не подсвечивается, но подсветку снимает
	if not b.is_inside_tree() or (on and b.disabled):
		return
	var tw := _tween(b)
	tw.tween_property(b, "modulate", HOVER_TINT if on else Color.WHITE, 0.12 if on else 0.2)
	if _round(b):
		b.pivot_offset = b.size / 2.0
		tw.tween_property(b, "scale", Vector2(1.08, 1.08) if on else Vector2.ONE, 0.14 if on else 0.2)
	if on and Time.get_ticks_msec() - _last_motion < 150:
		UiSound.play("hover")


static func _press(b: BaseButton, down: bool) -> void:
	if not b.is_inside_tree() or b.disabled:
		return
	var tw := _tween(b)
	var hovered := b.is_hovered()
	if down:
		tw.tween_property(b, "modulate", PRESS_TINT, 0.05)
		if _round(b):
			b.pivot_offset = b.size / 2.0
			tw.tween_property(b, "scale", Vector2(0.93, 0.93), 0.05)
	else:
		tw.tween_property(b, "modulate", HOVER_TINT if hovered else Color.WHITE, 0.14)
		if _round(b):
			tw.tween_property(b, "scale", Vector2(1.08, 1.08) if hovered else Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)


# ------------------------------------------------------------ переходы

## Окно выезжает слева и проявляется.
static func slide_in(c: Control, dx: float = -36.0, dur: float = 0.2) -> void:
	var x := _home_x(c)
	c.modulate.a = 0.0
	c.position.x = x + dx
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "position:x", x, dur)
	tw.tween_property(c, "modulate:a", 1.0, dur * 0.8)
	tw.chain().tween_callback(func(): c.remove_meta("fx_home_x"))
	c.set_meta("fx_move", tw)


## Окно уезжает и гаснет; затем done (например, скрыть).
static func slide_out(c: Control, done: Callable, dx: float = -28.0, dur: float = 0.14) -> void:
	var x := _home_x(c)
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "position:x", x + dx, dur)
	tw.tween_property(c, "modulate:a", 0.0, dur)
	tw.chain().tween_callback(func():
		c.position.x = x
		c.remove_meta("fx_home_x")
		done.call())
	c.set_meta("fx_move", tw)


## Остановить прежний сдвиг и вернуть окно на его место: повторное открытие
## посреди закрытия не должно «уводить» окно.
static func _home_x(c: Control) -> float:
	_kill(c)
	if c.has_meta("fx_home_x"):
		c.position.x = float(c.get_meta("fx_home_x"))
	else:
		c.set_meta("fx_home_x", c.position.x)
	return c.position.x


## Содержимое сменилось (другая вкладка или окно) — быстрое проявление.
static func fade_in(c: Control, from: float = 0.0, dur: float = 0.16) -> void:
	_kill(c)
	c.modulate.a = from
	var tw := c.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur)
	c.set_meta("fx_move", tw)


## Модальное окно: затемнение проявляется, окно раскрывается из чуть меньшего.
static func pop_in(root: Control, content: Control) -> void:
	root.modulate.a = 0.0
	content.scale = Vector2(0.94, 0.94)
	var tw := root.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "modulate:a", 1.0, 0.16)
	tw.tween_property(content, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	# центр масштаба — после раскладки, когда размер окна известен
	content.resized.connect(func(): content.pivot_offset = content.size / 2.0)
	(func(): content.pivot_offset = content.size / 2.0).call_deferred()


static func pop_out(root: Control, done: Callable) -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in root.get_children():
		if ch is Control:
			ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := root.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(root, "modulate:a", 0.0, 0.12)
	tw.tween_callback(done)


static func _kill(c: Control) -> void:
	if c.has_meta("fx_move"):
		var old: Variant = c.get_meta("fx_move")
		if old is Tween and old.is_valid():
			old.kill()

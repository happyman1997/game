class_name SimRunner
extends RefCounted
## Симуляция мира в отдельном потоке. Поток считает дни, пока игра идёт;
## интерфейс читает состояние мира только «в окне доступа»:
##   • неблокирующе — try_enter(): если поток сейчас считает день, он
##     остановится на границе дня, и доступ появится в следующем кадре;
##   • блокирующе — enter(): для действий игрока (ждёт конца текущего дня).
## Мьютекс рекурсивный, вложенные enter()/leave() допустимы.
## Пока поток не запущен (меню, пауза до старта), доступ всегда свободен.

var game: Game
## Разрешено ли считать дни (пауза, события, модальные окна — нет).
var allowed := false
## Сколько дней осталось посчитать (пополняет интерфейс по скорости игры).
var pending_days := 0
## Дней, посчитанных потоком всего (для статистики скорости).
var days_done := 0
## Последний снимок для карты (армии, осады) — пишет поток, читает интерфейс.
var snapshot: Dictionary = {}
## Вызывается в потоке симуляции после каждого дня (под замком мира):
## Callable(game) -> Dictionary — снимок для карты.
var snapshot_fn: Callable

var _mutex := Mutex.new()
var _queue := Mutex.new()
var _snap_lock := Mutex.new()
var _thread: Thread
var _alive := false
var _want_frame := -10
var _frame := 0
var _depth := 0
var _tick_us := 0.0


func start(g: Game) -> void:
	stop()
	game = g
	_alive = true
	allowed = false
	pending_days = 0
	_thread = Thread.new()
	_thread.start(_run, Thread.PRIORITY_NORMAL)


## Остановить поток. Можно вызывать и из «окна доступа» (вложенные замки
## интерфейса временно снимаются, чтобы поток мог доработать и выйти).
func stop() -> void:
	if _thread != null:
		_alive = false
		var held := _depth
		for i in held:
			_mutex.unlock()
		_thread.wait_to_finish()
		for i in held:
			_mutex.lock()
		_thread = null
	game = null


func is_running() -> bool:
	return _thread != null


## Начало кадра интерфейса.
func begin_frame() -> void:
	_frame += 1


func add_days(n: int, max_pending: int) -> void:
	_queue.lock()
	pending_days = mini(pending_days + n, max_pending)
	_queue.unlock()


func clear_days() -> void:
	_queue.lock()
	pending_days = 0
	_queue.unlock()


## Средняя длительность дня (мс).
func tick_ms() -> float:
	return _tick_us / 1000.0


# ------------------------------------------------------------ доступ к миру

## Блокирующий доступ (ждёт окончания текущего дня).
func enter() -> void:
	_want_frame = _frame
	_mutex.lock()
	_depth += 1


## Неблокирующий доступ: true — можно читать мир до leave().
func try_enter() -> bool:
	_want_frame = _frame
	if _mutex.try_lock():
		_depth += 1
		return true
	return false


func leave() -> void:
	_depth -= 1
	_mutex.unlock()
	if _depth == 0:
		_want_frame = -10


## Выполнить fn с доступом к миру (блокирующе) и вернуть результат.
func with_state(fn: Callable) -> Variant:
	enter()
	var r: Variant = fn.call()
	leave()
	return r


func get_snapshot() -> Dictionary:
	_snap_lock.lock()
	var s := snapshot
	_snap_lock.unlock()
	return s


func set_snapshot(s: Dictionary) -> void:
	_snap_lock.lock()
	snapshot = s
	_snap_lock.unlock()


# ------------------------------------------------------------ поток

func _blocked(g: Game) -> bool:
	return not g.state.pending_events.is_empty() or not g.state.pending_requests.is_empty() or g.state.game_over != null


func _run() -> void:
	while _alive:
		# Интерфейс просил доступ в этом или прошлом кадре — уступаем.
		if not allowed or pending_days <= 0 or _want_frame >= _frame - 1:
			OS.delay_usec(500)
			continue
		_mutex.lock()
		if not _alive:
			_mutex.unlock()
			break
		var g := game
		if g == null or _blocked(g):
			_mutex.unlock()
			OS.delay_usec(1000)
			continue
		var t0 := Time.get_ticks_usec()
		g.tick()
		var dt := Time.get_ticks_usec() - t0
		_tick_us = dt if _tick_us == 0.0 else _tick_us * 0.95 + dt * 0.05
		if snapshot_fn.is_valid():
			set_snapshot(snapshot_fn.call(g))
		_mutex.unlock()
		_queue.lock()
		pending_days -= 1
		days_done += 1
		_queue.unlock()

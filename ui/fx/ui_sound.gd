class_name UiSound
extends RefCounted
## Звуки интерфейса. Как и графика (ui/art рисует всё из SVG), звуки
## синтезируются кодом при первом проигрывании: щелчки дерева и пергамента,
## шелест страниц, перебор арфы у события, барабан войны, звон монет. Свой файл
## res://assets/sounds/<имя>.ogg или .wav заменяет синтезированный звук.
## Громкость — настройка ui_volume (0–1), шина «UI».
##
## Звуки: hover, click, click_soft, click_gold, tab, open, close, error,
## event, notify, notify_good, notify_bad, coin, war, pause, unpause, select.

const RATE := 44100
const BUS := "UI"
const POOL := 10
const DEFAULT_VOLUME := 0.6

static var _cache := {}
static var _players: Array = []
static var _next := 0
static var _last_played := {}
static var _last_any := -100000
static var _rng := RandomNumberGenerator.new()
## Не чаще (мс) для одного и того же звука.
const MIN_GAP := {"hover": 80, "war": 1500, "event": 400, "notify": 250, "notify_good": 250, "notify_bad": 250}


## Создать плееры и шину (вызывается один раз приложением).
static func setup(host: Node) -> void:
	if not _players.is_empty():
		return
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	set_volume(float(Platform.setting("ui_volume", DEFAULT_VOLUME)))
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		host.add_child(p)
		_players.append(p)


static func set_volume(v: float) -> void:
	var idx := AudioServer.get_bus_index(BUS)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(v, 0.001, 1.0)))


## Проиграть звук. pitch — множитель высоты (лёгкий разброс добавляется сам).
static func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if _players.is_empty():
		return
	var now := Time.get_ticks_msec()
	var gap: int = MIN_GAP.get(sound, 30)
	if now - int(_last_played.get(sound, -100000)) < gap:
		return
	_last_played[sound] = now
	_last_any = now
	var stream := _stream(sound)
	if stream == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = pitch * _rng.randf_range(0.985, 1.015)
	p.volume_db = volume_db
	p.play()


## Ничего не звучало последние ms миллисекунд (чтобы не наслаивать звуки
## одного действия: щелчок по ссылке уже прозвучал — шелест окна не нужен).
static func quiet_for(ms: int) -> bool:
	return Time.get_ticks_msec() - _last_any >= ms


## Звук-следствие (окно открылось, закрылось): если его вызвал щелчок,
## прозвучавший только что, он идёт заметно тише и не спорит со щелчком.
static func follow(sound: String) -> void:
	play(sound, 1.0, 0.0 if quiet_for(150) else -7.0)


## Подготовить все звуки заранее (чтобы первый щелчок не запинался).
static func warm_up() -> void:
	for s in ["hover", "click", "click_soft", "click_gold", "tab", "open", "close", "error", "notify", "notify_good", "notify_bad", "event", "coin", "war", "select", "pause", "unpause"]:
		_stream(s)
		# по звуку за кадр — меню не замирает
		if not _players.is_empty() and _players[0].is_inside_tree():
			await _players[0].get_tree().process_frame


static func _stream(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var st: AudioStream = null
	for ext in ["ogg", "wav"]:
		var path := "res://assets/sounds/%s.%s" % [sound, ext]
		if ResourceLoader.exists(path):
			st = load(path)
			break
	if st == null:
		var data := _synth(sound)
		if data.is_empty():
			_cache[sound] = null
			return null
		st = _to_wav(data)
	_cache[sound] = st
	return st


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


# ------------------------------------------------------------ синтез

static func _synth(sound: String) -> PackedFloat32Array:
	_rng.seed = hash(sound)
	# Всё приглушено и тепло (выше 2–3 кГц почти ничего нет), атаки мягкие,
	# громкость задана «на слух» (_level): звук чувствуется, но не отвлекает.
	match sound:
		"hover": return _level(_warm(_noise_burst(0.025, 900.0, 2400.0, 0.004, 0.006), 2600.0), 0.007)
		"click": return _level(_warm(_mix([_thock(0.07, 340.0, 250.0, 0.015), _scale(_noise_burst(0.025, 500.0, 2200.0, 0.003, 0.006), 0.35)]), 3000.0), 0.065)
		"click_soft": return _level(_warm(_mix([_thock(0.05, 460.0, 360.0, 0.01), _scale(_noise_burst(0.02, 700.0, 2600.0, 0.003, 0.004), 0.3)]), 3200.0), 0.04)
		"select": return _level(_warm(_mix([_thock(0.07, 380.0, 290.0, 0.013), _scale(_paper(0.08, 600.0, 1800.0, 0.01, 0.025), 0.45)]), 2800.0), 0.05)
		"click_gold": return _level(_warm(_mix([_thock(0.08, 300.0, 220.0, 0.017), _scale(_noise_burst(0.025, 500.0, 2200.0, 0.003, 0.006), 0.3),
			_scale(_bell(0.45, 1046.5, [1.0, 2.0, 3.0], [0.13, 0.07, 0.04], [1.0, 0.22, 0.06], 0.006), 0.22)]), 3200.0), 0.075)
		"tab": return _level(_warm(_paper(0.12, 700.0, 2000.0, 0.02, 0.035), 2400.0), 0.035)
		"open": return _level(_warm(_mix([_paper(0.26, 350.0, 1800.0, 0.06, 0.08), _scale(_thock(0.2, 180.0, 150.0, 0.06, 0.02), 0.3)]), 2200.0), 0.055)
		"close": return _level(_warm(_paper(0.2, 1800.0, 350.0, 0.015, 0.06), 2000.0), 0.035)
		"error": return _level(_warm(_seq([[0.0, _thock(0.12, 230.0, 190.0, 0.035, 0.006)], [0.09, _thock(0.12, 195.0, 160.0, 0.035, 0.006)]]), 1800.0), 0.07)
		"pause": return _level(_warm(_seq([[0.0, _thock(0.07, 300.0, 260.0, 0.02)], [0.07, _thock(0.08, 230.0, 200.0, 0.025)]]), 2000.0), 0.045)
		"unpause": return _level(_warm(_seq([[0.0, _thock(0.07, 230.0, 200.0, 0.02)], [0.07, _thock(0.08, 300.0, 260.0, 0.025)]]), 2000.0), 0.045)
		# событие: тихий перебор арфы в низком регистре (ре — соль — си малой
		# октавы) с лёгким эхом зала — не звонок, а «к вам пришли»
		"event": return _level(_warm(_hall(_seq([
			[0.0, _harp(1.4, 146.83, 0.7, 0.28)],
			[0.08, _harp(1.35, 196.0, 0.65, 0.26)],
			[0.16, _harp(1.3, 246.94, 0.6, 0.24)],
		]), 0.28), 1200.0), 0.045)
		"notify": return _level(_warm(_pluck(0.55, 440.0, 0.995), 2200.0), 0.04)
		"notify_good": return _level(_warm(_seq([[0.0, _pluck(0.5, 523.25, 0.995)], [0.1, _pluck(0.6, 783.99, 0.995)]]), 2200.0), 0.045)
		"notify_bad": return _level(_warm(_seq([[0.0, _pluck(0.55, 329.63, 0.994)], [0.13, _pluck(0.7, 261.63, 0.994)]]), 1800.0), 0.045)
		"coin": return _level(_warm(_seq([
			[0.0, _bell(0.35, 1318.5, [1.0, 2.0, 2.52], [0.14, 0.08, 0.05], [1.0, 0.3, 0.15], 0.004)],
			[0.08, _bell(0.35, 1568.0, [1.0, 2.0, 2.52], [0.12, 0.07, 0.04], [0.8, 0.25, 0.12], 0.004)],
		]), 3500.0), 0.04)
		"war": return _level(_warm(_seq([[0.0, _drum(0.6, 1.0)], [0.26, _drum(0.6, 0.7)], [0.52, _drum(0.7, 0.9)]]), 1400.0), 0.1)
	return PackedFloat32Array()


static func _n(dur: float) -> int:
	return int(dur * RATE)


## Громкость «на слух»: наибольшая rms в окне 20 мс равна loud.
static func _level(s: PackedFloat32Array, loud: float) -> PackedFloat32Array:
	var win := RATE / 50
	var m := 0.0
	var i0 := 0
	while i0 < s.size():
		var e := 0.0
		for i in range(i0, mini(i0 + win, s.size())):
			e += s[i] * s[i]
		m = maxf(m, sqrt(e / win))
		i0 += win / 2
	if m <= 0.0:
		return s
	var k := loud / m
	for i in s.size():
		s[i] *= k
	return _norm_edges(s)


## Мягкие края — без щелчков в начале и конце.
static func _norm_edges(s: PackedFloat32Array) -> PackedFloat32Array:
	var fade := mini(64, s.size() / 4)
	for i in fade:
		s[i] *= float(i) / fade
		s[s.size() - 1 - i] *= float(i) / fade
	return s


## Тёплый тембр: двойной фильтр нижних частот (12 дБ на октаву).
static func _warm(s: PackedFloat32Array, fc: float) -> PackedFloat32Array:
	return _lowpass(_lowpass(s, fc), fc)


static func _scale(s: PackedFloat32Array, k: float) -> PackedFloat32Array:
	for i in s.size():
		s[i] *= k
	return s


static func _mix(list: Array) -> PackedFloat32Array:
	var n := 0
	for s in list:
		n = maxi(n, s.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for s in list:
		for i in s.size():
			out[i] += s[i]
	return out


## Последовательность: [[смещение в секундах, звук], ...].
static func _seq(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, _n(p[0]) + p[1].size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		var off := _n(p[0])
		var s: PackedFloat32Array = p[1]
		for i in s.size():
			out[off + i] += s[i]
	return out


static func _alpha(fc: float) -> float:
	return 1.0 - exp(-TAU * fc / RATE)


static func _lowpass(s: PackedFloat32Array, fc: float) -> PackedFloat32Array:
	var a := _alpha(fc)
	var y := 0.0
	for i in s.size():
		y += a * (s[i] - y)
		s[i] = y
	return s


## Короткий шум в полосе частот: щелчок, шорох.
static func _noise_burst(dur: float, hp: float, lp: float, attack: float, tau: float) -> PackedFloat32Array:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var ah := _alpha(hp)
	var al := _alpha(lp)
	var low := 0.0
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := _rng.randf_range(-1.0, 1.0)
		low += ah * (x - low)
		var hi := x - low
		y += al * (hi - y)
		var env := minf(1.0, t / maxf(attack, 1e-4)) * exp(-maxf(0.0, t - attack) / tau)
		out[i] = y * env
	return out


## Шелест бумаги: шум, у которого полоса плавно сдвигается (страница, окно).
static func _paper(dur: float, f_from: float, f_to: float, attack: float, tau: float) -> PackedFloat32Array:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var y := 0.0
	var ah := _alpha(300.0)
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var fc := f_from * pow(f_to / f_from, k)
		var x := _rng.randf_range(-1.0, 1.0)
		low += ah * (x - low)
		y += _alpha(fc) * ((x - low) - y)
		# зернистость бумаги: случайные всплески
		var grain := 0.6 + 0.4 * _rng.randf()
		var env := minf(1.0, t / maxf(attack, 1e-4)) * exp(-maxf(0.0, t - attack) / tau)
		out[i] = y * env * grain
	return out


## Глухой удар дерева: синус с падающей высотой и быстрым затуханием.
static func _thock(dur: float, f_from: float, f_to: float, tau: float, attack: float = 0.004) -> PackedFloat32Array:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := f_to + (f_from - f_to) * exp(-t / (tau * 0.7))
		ph += TAU * f / RATE
		var env := minf(1.0, t / attack) * exp(-t / tau)
		out[i] = (sin(ph) + 0.12 * sin(ph * 2.0)) * env
	return out


## Колокол: набор частичных тонов, у каждого своё затухание.
static func _bell(dur: float, f: float, ratios: Array, taus: Array, amps: Array, attack: float = 0.003) -> PackedFloat32Array:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in ratios.size():
		var fk := f * float(ratios[k])
		var tau := float(taus[k])
		var amp := float(amps[k])
		var w := TAU * fk / RATE
		for i in n:
			var t := float(i) / RATE
			out[i] += sin(w * i) * amp * exp(-t / tau) * minf(1.0, t / attack)
	return out


## Мягкая струна арфы: почти чистый тон с тёплой второй гармоникой (h2;
## у низких струн она нужна, чтобы их было слышно и на маленьких динамиках), едва
## расстроенный двойник (медленные биения — «живой» звук) и плавная атака.
static func _harp(dur: float, f: float, tau: float, h2: float = 0.12) -> PackedFloat32Array:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var w1 := TAU * f / RATE
	var w2 := TAU * f * 2.0 / RATE
	var wd := TAU * f * 1.0025 / RATE
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.018) * exp(-t / tau)
		out[i] = (sin(w1 * i) + 0.35 * sin(wd * i) + h2 * sin(w2 * i) * exp(-t / (tau * 0.5))) * env
	return out


## Эхо зала: несколько затухающих приглушённых отражений, хвост ~0,5 с.
static func _hall(s: PackedFloat32Array, wet: float) -> PackedFloat32Array:
	var delays := [0.0297, 0.0371, 0.0411, 0.0437]
	var tail := _n(0.5)
	var out := PackedFloat32Array()
	out.resize(s.size() + tail)
	for i in s.size():
		out[i] = s[i]
	for d in delays:
		var dn := _n(d)
		var buf := PackedFloat32Array()
		buf.resize(dn)
		var lp := 0.0
		var fb := pow(0.001, d / 1.1)
		for i in out.size():
			var x := s[i] if i < s.size() else 0.0
			var y := buf[i % dn]
			lp += 0.35 * (y - lp)
			buf[i % dn] = x + lp * fb
			out[i] += y * wet / delays.size()
	return out


## Щипок струны (Карплус — Стронг): мягкий звук уведомлений.
static func _pluck(dur: float, f: float, damp: float) -> PackedFloat32Array:
	var n := _n(dur)
	var period := maxi(2, int(RATE / f))
	var buf := PackedFloat32Array()
	buf.resize(period)
	# мягкий начальный шум — тёплый тембр
	var y := 0.0
	for i in period:
		y += 0.3 * (_rng.randf_range(-1.0, 1.0) - y)
		buf[i] = y
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var j := i % period
		var v := buf[j]
		out[i] = v
		buf[j] = damp * 0.5 * (v + buf[(j + 1) % period])
	return out


## Удар барабана: низкий тон с падающей высотой и шум кожи.
static func _drum(dur: float, amp: float) -> PackedFloat32Array:
	var body := _thock(dur, 90.0, 52.0, 0.2, 0.008)
	var skin := _lowpass(_noise_burst(dur, 120.0, 1400.0, 0.002, 0.035), 1000.0)
	return _scale(_mix([body, _scale(skin, 0.9)]), amp)

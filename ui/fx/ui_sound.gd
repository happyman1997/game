class_name UiSound
extends RefCounted
## Звуки интерфейса. Как и графика (ui/art рисует всё из SVG), звуки
## синтезируются кодом при первом проигрывании: щелчки дерева и пергамента,
## шелест страниц, колокол события, барабан войны, звон монет. Свой файл
## res://assets/sounds/<имя>.ogg или .wav заменяет синтезированный звук.
## Громкость — настройка ui_volume (0–1), шина «UI».
##
## Звуки: hover, click, click_soft, click_gold, tab, open, close, error,
## event, notify, notify_good, notify_bad, coin, war, pause, unpause, select.

const RATE := 44100
const BUS := "UI"
const POOL := 10

static var _cache := {}
static var _players: Array = []
static var _next := 0
static var _last_played := {}
static var _last_any := -100000
static var _rng := RandomNumberGenerator.new()
## Не чаще (мс) для одного и того же звука.
const MIN_GAP := {"hover": 45, "war": 1500, "event": 400, "notify": 250, "notify_good": 250, "notify_bad": 250}


## Создать плееры и шину (вызывается один раз приложением).
static func setup(host: Node) -> void:
	if not _players.is_empty():
		return
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	set_volume(float(Platform.setting("ui_volume", 0.7)))
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
	p.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
	p.volume_db = volume_db
	p.play()


## Ничего не звучало последние ms миллисекунд (чтобы не наслаивать звуки
## одного действия: щелчок по ссылке уже прозвучал — шелест окна не нужен).
static func quiet_for(ms: int) -> bool:
	return Time.get_ticks_msec() - _last_any >= ms


## Подготовить все звуки заранее (чтобы первый щелчок не запинался).
static func warm_up() -> void:
	for s in ["hover", "click", "click_soft", "click_gold", "tab", "open", "close", "error", "notify", "notify_good", "notify_bad", "event", "coin", "war", "select"]:
		_stream(s)


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
	match sound:
		"hover": return _norm(_noise_burst(0.03, 2600.0, 6500.0, 0.002, 0.006), 0.10)
		"click": return _norm(_mix([_thock(0.08, 260.0, 165.0, 0.018), _scale(_noise_burst(0.03, 1200.0, 4200.0, 0.001, 0.006), 0.45)]), 0.42)
		"click_soft": return _norm(_mix([_thock(0.06, 430.0, 300.0, 0.012), _scale(_noise_burst(0.025, 2000.0, 6000.0, 0.001, 0.004), 0.35)]), 0.26)
		"select": return _norm(_mix([_thock(0.07, 340.0, 250.0, 0.015), _scale(_paper(0.09, 900.0, 3000.0, 0.008, 0.025), 0.6)]), 0.28)
		"click_gold": return _norm(_mix([_thock(0.09, 240.0, 160.0, 0.02), _scale(_noise_burst(0.03, 1200.0, 4200.0, 0.001, 0.006), 0.4),
			_scale(_bell(0.25, 1760.0, [1.0, 1.5, 2.24], [0.07, 0.05, 0.03], [1.0, 0.5, 0.3]), 0.35)]), 0.45)
		"tab": return _norm(_paper(0.13, 1200.0, 4500.0, 0.012, 0.035), 0.30)
		"open": return _norm(_mix([_paper(0.28, 500.0, 3600.0, 0.05, 0.08), _scale(_thock(0.2, 110.0, 90.0, 0.08), 0.35)]), 0.32)
		"close": return _norm(_paper(0.2, 3200.0, 500.0, 0.01, 0.06), 0.26)
		"error": return _norm(_mix([_thock(0.15, 150.0, 105.0, 0.05), _scale(_thock(0.15, 450.0, 315.0, 0.03), 0.25)]), 0.38)
		"pause": return _norm(_seq([[0.0, _thock(0.07, 330.0, 280.0, 0.02)], [0.06, _thock(0.08, 250.0, 210.0, 0.025)]]), 0.3)
		"unpause": return _norm(_seq([[0.0, _thock(0.07, 250.0, 210.0, 0.02)], [0.06, _thock(0.08, 330.0, 280.0, 0.025)]]), 0.3)
		"event": return _norm(_lowpass(_seq([
			[0.0, _bell(1.7, 523.25, [1.0, 2.0, 2.76, 4.07], [1.3, 0.8, 0.5, 0.3], [1.0, 0.45, 0.3, 0.12])],
			[0.16, _bell(1.5, 783.99, [1.0, 2.0, 2.76, 4.07], [1.1, 0.7, 0.45, 0.25], [0.8, 0.35, 0.22, 0.08])],
		]), 5200.0), 0.36)
		"notify": return _norm(_pluck(0.6, 587.33, 0.996), 0.26)
		"notify_good": return _norm(_seq([[0.0, _pluck(0.5, 659.25, 0.996)], [0.09, _pluck(0.6, 987.77, 0.996)]]), 0.3)
		"notify_bad": return _norm(_seq([[0.0, _pluck(0.55, 293.66, 0.995)], [0.12, _pluck(0.7, 233.08, 0.995)]]), 0.32)
		"coin": return _norm(_seq([
			[0.0, _bell(0.3, 2093.0, [1.0, 1.5, 2.0, 2.52], [0.12, 0.09, 0.07, 0.05], [1.0, 0.6, 0.4, 0.3])],
			[0.07, _bell(0.3, 2349.0, [1.0, 1.5, 2.0, 2.52], [0.1, 0.08, 0.06, 0.04], [0.8, 0.5, 0.35, 0.25])],
		]), 0.3)
		"war": return _norm(_seq([[0.0, _drum(0.6, 1.0)], [0.24, _drum(0.6, 0.75)], [0.48, _drum(0.7, 1.0)]]), 0.55)
	return PackedFloat32Array()


static func _n(dur: float) -> int:
	return int(dur * RATE)


static func _norm(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	for x in s:
		m = maxf(m, absf(x))
	if m <= 0.0:
		return s
	var k := peak / m
	for i in s.size():
		s[i] *= k
	# мягкие края — без щелчков в начале и конце
	var fade := mini(64, s.size() / 4)
	for i in fade:
		s[s.size() - 1 - i] *= float(i) / fade
	return s


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
static func _thock(dur: float, f_from: float, f_to: float, tau: float) -> PackedFloat32Array:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := f_to + (f_from - f_to) * exp(-t / (tau * 0.7))
		ph += TAU * f / RATE
		var env := minf(1.0, t / 0.0015) * exp(-t / tau)
		out[i] = (sin(ph) + 0.18 * sin(ph * 2.0)) * env
	return out


## Колокол: набор частичных тонов, у каждого своё затухание.
static func _bell(dur: float, f: float, ratios: Array, taus: Array, amps: Array) -> PackedFloat32Array:
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
			out[i] += sin(w * i) * amp * exp(-t / tau) * minf(1.0, t / 0.003)
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
		y += 0.5 * (_rng.randf_range(-1.0, 1.0) - y)
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
	var body := _thock(dur, 95.0, 52.0, 0.2)
	var skin := _lowpass(_noise_burst(dur, 40.0, 900.0, 0.001, 0.04), 600.0)
	return _scale(_mix([body, _scale(skin, 0.6)]), amp)

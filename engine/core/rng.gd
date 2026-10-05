class_name Rng
extends RefCounted
## Детерминированный генератор случайных чисел (mulberry32).
## Состояние — обычный словарь {"s": int}, поэтому оно попадает в сохранения.

var state: Dictionary


func _init(st: Dictionary = {"s": 0}) -> void:
	state = st


static func from_seed(seed: Variant) -> Rng:
	var s: int = (int(seed) & 0xFFFFFFFF) if (seed is int or seed is float) else (hash_string(str(seed)) & 0xFFFFFFFF)
	return Rng.new({"s": s})


## Умножение 32-битных чисел без переполнения (аналог Math.imul).
static func _imul(a: int, b: int) -> int:
	var al := a & 0xFFFF
	var ah := (a >> 16) & 0xFFFF
	var bl := b & 0xFFFF
	var bh := (b >> 16) & 0xFFFF
	return (al * bl + (((ah * bl + al * bh) & 0xFFFF) << 16)) & 0xFFFFFFFF


## Число в [0, 1).
func next() -> float:
	var s: int = (int(state["s"]) + 0x6D2B79F5) & 0xFFFFFFFF
	state["s"] = s
	var t := s
	t = _imul(t ^ (t >> 15), t | 1)
	t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


## Целое в диапазоне [lo, hi] включительно.
func range_int(lo: int, hi: int) -> int:
	return lo + int(floor(next() * (hi - lo + 1)))


func range_float(lo: float, hi: float) -> float:
	return lo + next() * (hi - lo)


func chance(p: float) -> bool:
	return next() < p


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[int(floor(next() * arr.size()))]


## Взвешенный выбор: weight — Callable(item) -> float.
func weighted(items: Array, weight: Callable) -> Variant:
	var total := 0.0
	var ws: Array[float] = []
	for it in items:
		var w: Variant = weight.call(it)
		var wf := maxf(0.0, float(w) if w != null else 0.0)
		ws.append(wf)
		total += wf
	if total <= 0.0:
		return null
	var r := next() * total
	for i in items.size():
		r -= ws[i]
		if r < 0.0:
			return items[i]
	return items[items.size() - 1]


func shuffle(arr: Array) -> Array:
	var i := arr.size() - 1
	while i > 0:
		var j := int(floor(next() * (i + 1)))
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
		i -= 1
	return arr


## Приближённо нормальное распределение (сумма трёх равномерных).
func gauss(mean: float, spread: float) -> float:
	var u := (next() + next() + next()) / 3.0 - 0.5
	return mean + u * 2.0 * spread


## FNV-1a хеш строки (32 бита, со знаком) — для детерминированных «случайных» величин.
static func hash_string(s: String) -> int:
	var h := 0x811C9DC5
	for i in s.length():
		h ^= s.unicode_at(i) & 0xFFFF
		h = _imul(h, 0x01000193)
	return h - 0x100000000 if h >= 0x80000000 else h

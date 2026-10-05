class_name GameDate
extends RefCounted
## Игровой календарь: 365 дней в году, без високосных лет (как в CK3).
## Дата — целое число дней от 1 января 0 года.

const MONTH_DAYS: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const MONTH_START: Array[int] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
const DAYS_PER_YEAR := 365
const DAYS_PER_MONTH := 30


static func make(y: int, m: int = 1, d: int = 1) -> int:
	return y * DAYS_PER_YEAR + MONTH_START[m - 1] + (d - 1)


## {"y": год, "m": месяц 1..12, "d": день 1..31}
static func parts(n: int) -> Dictionary:
	var y := floori(n / float(DAYS_PER_YEAR))
	var r := n - y * DAYS_PER_YEAR
	var m := 0
	while m < 11 and r >= MONTH_START[m + 1]:
		m += 1
	return {"y": y, "m": m + 1, "d": r - MONTH_START[m] + 1}


static func year_of(n: int) -> int:
	return floori(n / float(DAYS_PER_YEAR))


## Принимает "1066.9.15", "1066.9", "1066" или число лет. Возвращает -1 при ошибке.
static func parse(s: Variant) -> int:
	if s is int or s is float:
		return make(floori(float(s)))
	var text := str(s).strip_edges().replace("-", ".").replace("/", ".")
	var bits := text.split(".")
	var nums: Array[int] = []
	for b in bits:
		if not b.is_valid_int():
			push_error("Некорректная дата: \"%s\"" % s)
			return -1
		nums.append(int(b))
	return make(nums[0], nums[1] if nums.size() > 1 else 1, nums[2] if nums.size() > 2 else 1)


static func to_str(n: int) -> String:
	var p := parts(n)
	return "%d.%d.%d" % [p.y, p.m, p.d]


static func age_at(birth: int, date: int) -> int:
	return floori((date - birth) / float(DAYS_PER_YEAR))


## {days, months, years} или число дней → количество дней.
static func duration_days(spec: Variant) -> int:
	if spec == null:
		return 0
	if spec is int or spec is float:
		return roundi(float(spec))
	if spec is Dictionary:
		return roundi(float(spec.get("days", 0)) + float(spec.get("months", 0)) * DAYS_PER_MONTH + float(spec.get("years", 0)) * DAYS_PER_YEAR)
	return 0

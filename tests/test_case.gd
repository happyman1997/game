class_name TestCase
extends RefCounted
## База для тестов (см. tests/run.gd).

var name := ""
var failures: Array[String] = []


func check(cond: bool, msg: String = "проверка не прошла") -> bool:
	if not cond:
		failures.append(msg)
	return cond


func check_eq(actual: Variant, expected: Variant, msg: String = "") -> bool:
	var same: bool = actual == expected
	if (actual is int or actual is float) and (expected is int or expected is float):
		same = is_equal_approx(float(actual), float(expected))
	if not same:
		failures.append("%s: ожидалось %s, получено %s" % [msg if msg != "" else "значение", var_to_str(expected), var_to_str(actual)])
	return same

extends RefCounted
## Base mínima de tests (sin dependencias). Cada método test_* es un caso;
## el runner crea una instancia nueva por caso.

var failures: Array[String] = []
var asserts := 0
var current := ""


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current, msg])


func assert_true(cond: bool, msg: String = "") -> void:
	asserts += 1
	if not cond:
		fail("se esperaba verdadero. " + msg)


func assert_false(cond: bool, msg: String = "") -> void:
	asserts += 1
	if cond:
		fail("se esperaba falso. " + msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	asserts += 1
	if not equal(actual, expected):
		fail("esperado %s, obtenido %s. %s" % [var_to_str(expected), var_to_str(actual), msg])


## Pasa si algún error contiene el fragmento.
func assert_has_error(errors: Array, fragment: String) -> void:
	asserts += 1
	for e in errors:
		if fragment in str(e):
			return
	fail("ningún error contiene '%s'. Errores: %s" % [fragment, str(errors)])


## Igualdad profunda tolerante int/float (JSON.parse_string da float siempre).
static func equal(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	var nums := [TYPE_INT, TYPE_FLOAT]
	if ta in nums and tb in nums:
		return float(a) == float(b)
	if ta != tb:
		return false
	if ta == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not equal(a[k], b[k]):
				return false
		return true
	if ta == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not equal(a[i], b[i]):
				return false
		return true
	return a == b

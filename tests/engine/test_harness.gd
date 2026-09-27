extends "res://tests/engine/TestCase.gd"


func test_equal_tolerates_int_float() -> void:
	assert_eq(45.0, 45)
	assert_eq({"a": [1, {"b": 2}]}, {"a": [1.0, {"b": 2.0}]})
	assert_false(equal({"a": 1}, {"a": 1, "b": 2}))
	assert_false(equal("1", 1))


func test_assert_has_error_matches_fragment() -> void:
	assert_has_error(["x: campo desconocido"], "desconocido")

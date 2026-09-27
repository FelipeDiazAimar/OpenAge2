extends "res://tests/engine/TestCase.gd"

const Rng := preload("res://engine/sim/Rng.gd")


func test_known_sequence() -> void:
	var r := Rng.new(1)
	assert_eq([r.next_u32(), r.next_u32(), r.next_u32()], [270369, 67634689, 2647435461])
	var r42 := Rng.new(42)
	assert_eq([r42.next_u32(), r42.next_u32()], [11355432, 2836018348])
	assert_eq(Rng.new(0).next_u32(), 1359758873, "semilla 0 no se queda en 0")


func test_range_inclusive_and_bounded() -> void:
	var r := Rng.new(7)
	var seen := {}
	for i in 500:
		var v := r.range_i(-2, 2)
		assert_true(v >= -2 and v <= 2)
		seen[v] = true
	assert_eq(seen.size(), 5)

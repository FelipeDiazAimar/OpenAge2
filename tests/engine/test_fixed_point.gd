extends "res://tests/engine/TestCase.gd"

const FP := preload("res://engine/sim/FixedPoint.gd")


func test_from_tiles_and_data() -> void:
	assert_eq(FP.from_tiles(3), 3000)
	assert_eq(FP.from_data(0.96), 960)
	assert_eq(FP.from_data(0.39), 390)
	assert_eq(FP.from_data(-1.2346), -1235)


func test_mul_rounds_half_away_from_zero() -> void:
	assert_eq(FP.mul(1500, 2000), 3000)
	assert_eq(FP.mul(-1500, 2000), -3000)
	assert_eq(FP.mul(1, 500), 1)
	assert_eq(FP.mul(-1, 500), -1)


func test_div() -> void:
	assert_eq(FP.div(1000, 3000), 333)
	assert_eq(FP.div(2000, 3000), 667)
	assert_eq(FP.div(-2000, 3000), -667)
	assert_eq(FP.div(3000, 2000), 1500)


func test_floordiv_negative() -> void:
	assert_eq(FP.floordiv(7, 4), 1)
	assert_eq(FP.floordiv(-1, 4000), -1)
	assert_eq(FP.floordiv(-4000, 4000), -1)
	assert_eq(FP.floordiv(-4001, 4000), -2)


func test_isqrt_and_dist() -> void:
	assert_eq(FP.isqrt(0), 0)
	assert_eq(FP.isqrt(2), 1)
	assert_eq(FP.isqrt(15), 3)
	assert_eq(FP.isqrt(16), 4)
	assert_eq(FP.isqrt(1000000000000), 1000000)
	assert_eq(FP.dist(Vector2i(0, 0), Vector2i(3000, 4000)), 5000)
	assert_eq(FP.dist(Vector2i(1000, 1000), Vector2i(1000, 1000)), 0)

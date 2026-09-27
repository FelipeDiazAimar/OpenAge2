extends "res://tests/engine/TestCase.gd"

const Grid := preload("res://engine/sim/Grid.gd")


func test_grid_bounds_and_blocking() -> void:
	var g := Grid.new(10, 8)
	assert_true(g.in_bounds(Vector2i(9, 7)))
	assert_false(g.in_bounds(Vector2i(10, 0)))
	assert_false(g.in_bounds(Vector2i(0, -1)))
	assert_true(g.is_walkable(Vector2i(3, 3)))
	g.block_rect(Vector2i(2, 2), Vector2i(2, 3))
	assert_false(g.is_walkable(Vector2i(3, 4)))
	assert_true(g.is_walkable(Vector2i(4, 4)))
	g.set_blocked(Vector2i(3, 4), false)
	assert_true(g.is_walkable(Vector2i(3, 4)))
	assert_false(g.is_walkable(Vector2i(-1, 0)), "fuera del mapa no es caminable")
	assert_eq(g.clamp_tile(Vector2i(-5, 20)), Vector2i(0, 7))


func test_tile_conversions() -> void:
	assert_eq(Grid.tile_of(Vector2i(2999, 1000)), Vector2i(2, 1))
	assert_eq(Grid.tile_of(Vector2i(-1, -1000)), Vector2i(-1, -1))
	assert_eq(Grid.center_of(Vector2i(3, 4)), Vector2i(3500, 4500))

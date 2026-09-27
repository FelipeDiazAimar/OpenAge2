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


const Pathfinder := preload("res://engine/sim/Pathfinder.gd")


func test_straight_path() -> void:
	var g := Grid.new(10, 10)
	var p := Pathfinder.find_path(g, Vector2i(1, 1), Vector2i(4, 1))
	assert_eq(p, [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)])
	assert_eq(Pathfinder.find_path(g, Vector2i(1, 1), Vector2i(1, 1)), [])


func test_path_around_wall_without_corner_cutting() -> void:
	var g := Grid.new(10, 10)
	g.block_rect(Vector2i(3, 0), Vector2i(1, 6))
	var p := Pathfinder.find_path(g, Vector2i(1, 2), Vector2i(5, 2))
	assert_eq(p[p.size() - 1], Vector2i(5, 2))
	var prev := Vector2i(1, 2)
	for c in p:
		assert_true(g.is_walkable(c), "pisa bloqueada: %s" % c)
		var d: Vector2i = c - prev
		if d.x != 0 and d.y != 0:
			assert_true(g.is_walkable(Vector2i(prev.x + d.x, prev.y)) and g.is_walkable(Vector2i(prev.x, prev.y + d.y)), "corta esquina en %s" % c)
		prev = c


func test_blocked_goal_goes_to_nearest() -> void:
	var g := Grid.new(10, 10)
	g.block_rect(Vector2i(4, 4), Vector2i(3, 3))
	assert_eq(Pathfinder.nearest_walkable(g, Vector2i(5, 5)), Vector2i(5, 3))
	var p := Pathfinder.find_path(g, Vector2i(0, 5), Vector2i(5, 5))
	assert_true(g.is_walkable(p[p.size() - 1]))
	assert_eq(p[p.size() - 1], Pathfinder.nearest_walkable(g, Vector2i(5, 5)))
	var full := Grid.new(2, 2)
	full.block_rect(Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(Pathfinder.nearest_walkable(full, Vector2i(0, 0)), Vector2i(-1, -1))


func test_start_on_blocked_edge_can_leave() -> void:
	var g := Grid.new(10, 10)
	g.block_rect(Vector2i(2, 2), Vector2i(3, 3))
	var p := Pathfinder.find_path(g, Vector2i(4, 3), Vector2i(8, 3))
	assert_eq(p[p.size() - 1], Vector2i(8, 3))


func test_unreachable_goes_closest() -> void:
	var g := Grid.new(12, 12)
	# anillo cerrado alrededor de (8,8)
	for x in range(6, 11):
		g.set_blocked(Vector2i(x, 6), true)
		g.set_blocked(Vector2i(x, 10), true)
	for y in range(6, 11):
		g.set_blocked(Vector2i(6, y), true)
		g.set_blocked(Vector2i(10, y), true)
	var p := Pathfinder.find_path(g, Vector2i(1, 1), Vector2i(8, 8))
	assert_false(p.is_empty())
	var end: Vector2i = p[p.size() - 1]
	assert_true(g.is_walkable(end))
	assert_true(absi(end.x - 8) + absi(end.y - 8) <= 4, "termina pegado al anillo: %s" % end)


func test_path_is_deterministic() -> void:
	var g := Grid.new(30, 30)
	g.block_rect(Vector2i(10, 5), Vector2i(2, 20))
	assert_eq(Pathfinder.find_path(g, Vector2i(2, 15), Vector2i(25, 15)), Pathfinder.find_path(g, Vector2i(2, 15), Vector2i(25, 15)))


func test_unblock_updates_regions_incrementally() -> void:
	var g := Grid.new(10, 10)
	g.block_rect(Vector2i(5, 0), Vector2i(1, 10))
	var left := g.region_of(Vector2i(1, 1))
	g.set_blocked(Vector2i(3, 3), true)
	assert_eq(g.region_of(Vector2i(1, 1)), left)
	var runs := g.relabel_count
	g.set_blocked(Vector2i(3, 3), false)
	assert_eq(g.region_of(Vector2i(3, 3)), left, "casilla liberada entre vecinos de una región")
	assert_eq(g.relabel_count, runs, "un árbol talado no re-etiqueta todo el mapa")
	g.block_rect(Vector2i(7, 7), Vector2i(3, 3))
	g.region_of(Vector2i(0, 0))
	runs = g.relabel_count
	g.set_blocked(Vector2i(8, 8), false)
	var iso := g.region_of(Vector2i(8, 8))
	assert_true(iso >= 0 and iso != left and iso != g.region_of(Vector2i(8, 1)), "casilla aislada: región nueva")
	assert_eq(g.relabel_count, runs)
	g.set_blocked(Vector2i(5, 5), false)
	assert_eq(g.region_of(Vector2i(1, 1)), g.region_of(Vector2i(8, 1)), "unir dos regiones sí recalcula")


func test_regions_split_by_walls_and_update() -> void:
	var g := Grid.new(10, 10)
	g.block_rect(Vector2i(5, 0), Vector2i(1, 10))
	assert_eq(g.region_of(Vector2i(1, 1)), g.region_of(Vector2i(4, 9)))
	assert_true(g.region_of(Vector2i(1, 1)) != g.region_of(Vector2i(8, 1)))
	assert_eq(g.region_of(Vector2i(5, 5)), -1, "bloqueada no tiene región")
	g.set_blocked(Vector2i(5, 5), false)
	assert_eq(g.region_of(Vector2i(1, 1)), g.region_of(Vector2i(8, 1)), "abrir un hueco une regiones")

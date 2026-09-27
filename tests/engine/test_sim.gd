extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const Grid := preload("res://engine/sim/Grid.gd")


func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 60, 60)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	return s


func test_spawn_building_blocks_footprint() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	assert_eq(s.world.entities[tc]["pos"], Vector2i(12000, 12000), "centro del footprint 4x4")
	assert_false(s.grid.is_walkable(Vector2i(13, 13)))
	assert_true(s.grid.is_walkable(Vector2i(14, 13)))
	assert_eq(s.spawn("no_existe", 0, Vector2i(1, 1)), -1)
	var v := s.spawn("aldeano", 0, Vector2i(15, 12))
	assert_eq(s.world.entities[v]["pos"], Vector2i(15500, 12500))
	assert_eq(s.def_for(v)["id"], "aldeano")


func test_move_command_respects_input_delay() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(5, 5))
	s.queue_command(0, "move", {"ids": [v], "pos": [15500, 5500]})
	s.step()
	assert_false(s.world.comp(v, "Move")["moving"], "tick 1: todavía no")
	s.step()
	assert_true(s.world.comp(v, "Move")["moving"], "tick 2: aplicada")
	for i in 124:
		s.step()
	assert_eq(s.world.entities[v]["pos"], Vector2i(15500, 5500))


func test_commands_validate_owner_and_ids() -> void:
	var s := _sim()
	var mine := s.spawn("aldeano", 0, Vector2i(5, 5))
	var theirs := s.spawn("aldeano", 1, Vector2i(8, 8))
	var tc := s.spawn("centro_urbano", 0, Vector2i(20, 20))
	s.queue_command(0, "move", {"ids": [theirs, 9999, tc, float(mine), mine], "pos": [10500.0, 5500.0]})
	for i in 3:
		s.step()
	assert_true(s.world.comp(mine, "Move")["moving"])
	assert_false(s.world.comp(theirs, "Move")["moving"])
	s.queue_command(0, "volar", {})
	s.step()
	s.step()
	assert_eq(s.world.tick, 5, "un tipo desconocido se ignora sin error")


func test_move_outside_map_clamps() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(5, 5))
	s.queue_command(0, "move", {"ids": [v], "pos": [-50000, 999999]})
	for i in 1500:
		s.step()
	var p: Vector2i = s.world.entities[v]["pos"]
	assert_true(s.grid.in_bounds(Grid.tile_of(p)), "quedó dentro del mapa: %s" % p)
	assert_false(s.world.comp(v, "Move")["moving"])


func test_group_move_spreads_units() -> void:
	var s := _sim()
	var ids: Array = []
	for i in 5:
		ids.append(s.spawn("aldeano", 0, Vector2i(5 + i, 5)))
	s.queue_command(0, "move", {"ids": ids, "pos": [30500, 30500]})
	for i in 600:
		s.step()
	var seen := {}
	for id in ids:
		seen[s.world.entities[id]["pos"]] = true
	assert_eq(seen.size(), 5, "cada aldeano en un punto distinto")
	assert_eq(Sim.spread_offsets(3), [Vector2i(0, 0), Vector2i(0, -1000), Vector2i(-1000, 0)])


func test_same_commands_same_hash() -> void:
	var hashes := []
	for run in 2:
		var s := _sim()
		var a := s.spawn("aldeano", 0, Vector2i(5, 5))
		var b := s.spawn("aldeano", 1, Vector2i(40, 40))
		s.spawn("centro_urbano", 0, Vector2i(20, 20))
		s.queue_command(0, "move", {"ids": [a], "pos": [45500, 45500]})
		s.queue_command(1, "move", {"ids": [b], "pos": [2500, 2500]})
		for i in 300:
			s.step()
		hashes.append(s.world.state_hash())
	assert_eq(hashes[0], hashes[1])

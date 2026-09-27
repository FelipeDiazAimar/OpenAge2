extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const Grid := preload("res://engine/sim/Grid.gd")


func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	return s


func test_start_resources_and_add() -> void:
	var s := _sim()
	assert_eq(s.res_of(0), {"wood": 200, "food": 200, "gold": 100, "stone": 200})
	s.add_res(0, "wood", 9999)
	assert_eq(s.res_of(0)["wood"], 209, "milésimas: 9.999 se muestra como 9")
	s.add_res(0, "mana", 5000)
	assert_eq(s.res_of(0).size(), 4)
	assert_eq(s.res_of(1)["wood"], 200)


func test_resource_spawn_blocks_and_remove_unblocks() -> void:
	var s := _sim()
	var t := s.spawn("tree", -1, Vector2i(5, 5))
	assert_eq(s.world.entities[t]["pos"], Vector2i(5500, 5500))
	assert_false(s.grid.is_walkable(Vector2i(5, 5)))
	assert_eq(s.world.comp(t, "ResourceSource")["amount"], 100000)
	s.remove(t)
	assert_true(s.grid.is_walkable(Vector2i(5, 5)))
	assert_false(s.world.entities.has(t))
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	s.remove(tc)
	assert_true(s.grid.is_walkable(Vector2i(13, 13)), "footprint del TC liberado")
	s.remove(9999)


func test_population_and_counts() -> void:
	var s := _sim()
	s.spawn("centro_urbano", 0, Vector2i(10, 10))
	for i in 3:
		s.spawn("aldeano", 0, Vector2i(16 + i, 16))
	assert_eq(s.population(0), Vector2i(3, 5))
	assert_eq(s.population(1), Vector2i(0, 0))
	assert_eq(s.gatherer_counts(0), {"wood": 0, "food": 0, "gold": 0, "stone": 0})


func test_state_hash_covers_resources() -> void:
	var a := _sim()
	var b := _sim()
	assert_eq(a.state_hash(), b.state_hash())
	b.add_res(1, "gold", 1)
	assert_true(a.state_hash() != b.state_hash())

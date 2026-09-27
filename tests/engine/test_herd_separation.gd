extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const FP := preload("res://engine/sim/FixedPoint.gd")


func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	return s


func _steps(s: Sim, n: int) -> void:
	for i in n:
		s.step()


func test_sheep_capture_and_steal() -> void:
	var s := _sim()
	var sheep := s.spawn("sheep", -1, Vector2i(10, 10))
	var sc := s.spawn("scout", 1, Vector2i(12, 10))
	_steps(s, 12)
	assert_eq(s.world.entities[sheep]["owner"], 1, "sin dueño: la toma quien la ve")
	var v := s.spawn("aldeano", 0, Vector2i(9, 10))
	_steps(s, 12)
	assert_eq(s.world.entities[sheep]["owner"], 1, "el dueño sigue cerca: no se la roban")
	s.queue_command(1, "move", {"ids": [sc], "pos": [35500, 35500]})
	_steps(s, 120)
	assert_eq(s.world.entities[sheep]["owner"], 0, "sola junto a un enemigo: cambia de dueño")
	assert_true(s.world.entities.has(v))


func _stack(s: Sim, n: int) -> Array:
	var ids: Array = []
	for i in n:
		ids.append(s.world.spawn(s.registry.get_def("milicia"), 0, Vector2i(10500, 10500)))
	return ids


func _min_dist(s: Sim, ids: Array) -> int:
	var best := 1 << 30
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			best = mini(best, FP.dist(s.world.entities[ids[i]]["pos"], s.world.entities[ids[j]]["pos"]))
	return best


func test_separation_spreads_stacked_units() -> void:
	var s := _sim()
	var ids := _stack(s, 5)
	assert_eq(_min_dist(s, ids), 0)
	_steps(s, 20)
	assert_true(_min_dist(s, ids) >= 250, "separadas: %d" % _min_dist(s, ids))


func test_separation_leaves_single_unit() -> void:
	var s := _sim()
	var m := s.spawn("milicia", 0, Vector2i(10, 10))
	_steps(s, 20)
	assert_eq(s.world.entities[m]["pos"], Vector2i(10500, 10500))


func test_separation_never_into_blocked() -> void:
	var s := _sim()
	for y in range(8, 13):
		for x in range(8, 13):
			if not (x == 10 and y == 10):
				s.grid.set_blocked(Vector2i(x, y), true)
	var ids := _stack(s, 3)
	_steps(s, 20)
	for id in ids:
		var t := Vector2i(s.world.entities[id]["pos"].x / 1000, s.world.entities[id]["pos"].y / 1000)
		assert_eq(t, Vector2i(10, 10), "no sale a una casilla bloqueada")


func test_separation_deterministic() -> void:
	var hashes := []
	for run in 2:
		var s := _sim()
		_stack(s, 6)
		_steps(s, 30)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])

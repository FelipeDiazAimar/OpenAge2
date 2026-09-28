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


func test_separation_does_not_cut_corners() -> void:
	var s := _sim()
	s.grid.set_blocked(Vector2i(11, 10), true)
	s.grid.set_blocked(Vector2i(10, 11), true)
	var a: int = s.world.spawn(s.registry.get_def("milicia"), 0, Vector2i(10950, 10950))
	s.world.spawn(s.registry.get_def("milicia"), 0, Vector2i(10850, 10850))
	_steps(s, 5)
	var p: Vector2i = s.world.entities[a]["pos"]
	assert_eq(Vector2i(p.x / 1000, p.y / 1000), Vector2i(10, 10), "no cruza la esquina en diagonal: %s" % p)



## Ticks hasta que n aldeanos con una orden de grupo terminan de moverse.
func _group_ticks(n: int) -> int:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 60, 60)
	s.add_player(0, "britones", 0)
	var ids := []
	for i in n:
		ids.append(s.spawn("aldeano", 0, Vector2i(5 + i, 5)))
	s.queue_command(0, "move", {"ids": ids, "pos": [45500, 40500]})
	for t in range(1, 3000):
		s.step()
		if t > 5 and ids.all(func(id): return not s.world.comp(id, "Move")["moving"]):
			return t
	return -1


func test_walkers_on_same_path_do_not_drag() -> void:
	# En marcha no se empujan: el grupo llega como un aldeano solo.
	var solo := _group_ticks(1)
	var group := _group_ticks(3)
	assert_true(group <= solo + 3, "grupo %d ticks, solo %d" % [group, solo])

func test_idle_unit_steps_aside_for_walker() -> void:
	var s := _sim()
	var idle := s.spawn("aldeano", 0, Vector2i(10, 10))
	var w := s.spawn("aldeano", 0, Vector2i(5, 10))
	s.queue_command(0, "move", {"ids": [w], "pos": [15500, 10500]})
	_steps(s, 200)
	assert_true(s.world.entities[w]["pos"].x >= 15000, "el que camina llega: %s" % s.world.entities[w]["pos"])
	assert_true(s.world.entities.has(idle))

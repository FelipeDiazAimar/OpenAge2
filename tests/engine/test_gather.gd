extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")


func _sim(with_tc: bool = true) -> Array:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10)) if with_tc else -1
	var tree := s.spawn("tree", -1, Vector2i(20, 12))
	var v := s.spawn("aldeano", 0, Vector2i(19, 12))
	return [s, tc, tree, v]


func _steps(s: Sim, n: int) -> void:
	for i in n:
		s.step()


func test_gather_wood_trip() -> void:
	var w := _sim()
	var s: Sim = w[0]
	var v: int = w[3]
	s.queue_command(0, "gather", {"ids": [v], "target": w[2]})
	_steps(s, 300)
	var g: Dictionary = s.world.comp(v, "Gather")
	assert_eq(s.res_of(0)["wood"], 200, "aún no depositó")
	assert_eq(g["carry"], 10000, "carga llena: 10 de madera (257 ticks a 0.39/s)")
	assert_eq(g["state"], "to_drop")
	assert_eq(s.gatherer_counts(0)["wood"], 1)
	_steps(s, 100)
	assert_eq(s.res_of(0)["wood"], 210, "primer viaje depositado en el TC")
	assert_true(g["state"] == "to_resource" or g["state"] == "gathering", "vuelve al árbol")
	assert_eq(s.world.comp(w[2], "ResourceSource")["amount"], 90000)


func test_depletion_retargets_and_unblocks() -> void:
	var w := _sim()
	var s: Sim = w[0]
	var tree: int = w[2]
	var v: int = w[3]
	var tree2 := s.spawn("tree", -1, Vector2i(21, 14))
	s.world.comp(tree, "ResourceSource")["amount"] = 5000
	s.queue_command(0, "gather", {"ids": [v], "target": tree})
	_steps(s, 200)
	assert_false(s.world.entities.has(tree), "árbol agotado eliminado")
	assert_true(s.grid.is_walkable(Vector2i(20, 12)), "casilla liberada")
	var g: Dictionary = s.world.comp(v, "Gather")
	assert_eq(g["target"], tree2, "busca el árbol más cercano")
	assert_true(g["carry"] >= 5000, "conserva lo recolectado")


func test_target_removed_while_walking() -> void:
	var w := _sim()
	var s: Sim = w[0]
	var v: int = w[3]
	var far := s.spawn("tree", -1, Vector2i(30, 30))
	s.queue_command(0, "gather", {"ids": [v], "target": far})
	_steps(s, 5)
	s.remove(far)
	_steps(s, 5)
	var g: Dictionary = s.world.comp(v, "Gather")
	assert_true(g["target"] != far)
	assert_true(g["state"] == "idle" or s.world.entities.has(g["target"]))


func test_no_dropsite_idles_with_carry() -> void:
	var w := _sim(false)
	var s: Sim = w[0]
	var v: int = w[3]
	s.queue_command(0, "gather", {"ids": [v], "target": w[2]})
	_steps(s, 320)
	var g: Dictionary = s.world.comp(v, "Gather")
	assert_eq(g["state"], "idle")
	assert_eq(g["carry"], 10000)
	assert_eq(s.res_of(0)["wood"], 200)


func test_switch_resource_drops_carry() -> void:
	var w := _sim()
	var s: Sim = w[0]
	var v: int = w[3]
	var gold := s.spawn("gold_mine", -1, Vector2i(19, 13))
	s.queue_command(0, "gather", {"ids": [v], "target": w[2]})
	_steps(s, 60)
	var g: Dictionary = s.world.comp(v, "Gather")
	assert_true(g["carry"] > 0)
	s.queue_command(0, "gather", {"ids": [v], "target": gold})
	_steps(s, 3)
	assert_eq(g["carry_res"], "gold")
	assert_true(g["carry"] < 200, "la madera se perdió; solo lo recién minado")


func test_move_cancels_gather() -> void:
	var w := _sim()
	var s: Sim = w[0]
	var v: int = w[3]
	s.queue_command(0, "gather", {"ids": [v], "target": w[2]})
	_steps(s, 10)
	s.queue_command(0, "move", {"ids": [v], "pos": [30500, 30500]})
	_steps(s, 3)
	assert_eq(s.world.comp(v, "Gather")["state"], "idle")
	assert_true(s.world.comp(v, "Move")["moving"])


func test_invalid_gather_commands_ignored() -> void:
	var w := _sim()
	var s: Sim = w[0]
	var v: int = w[3]
	var enemy := s.spawn("aldeano", 1, Vector2i(25, 25))
	s.queue_command(0, "gather", {"ids": [v], "target": w[1]})
	s.queue_command(0, "gather", {"ids": [enemy], "target": w[2]})
	s.queue_command(0, "gather", {"ids": "x", "target": w[2]})
	s.queue_command(0, "gather", {"ids": [v], "target": "arbol"})
	s.queue_command(0, "gather", {"ids": [v], "target": NAN})
	_steps(s, 3)
	assert_eq(s.world.comp(v, "Gather")["state"], "idle")
	assert_eq(s.world.comp(enemy, "Gather")["state"], "idle")
	s.queue_command(0, "gather", {"ids": [float(v)], "target": float(w[2])})
	_steps(s, 3)
	assert_eq(s.world.comp(v, "Gather")["state"], "gathering", "ids/target float de JSON sí valen")


func test_gather_is_deterministic() -> void:
	var hashes := []
	for run in 2:
		var w := _sim()
		var s: Sim = w[0]
		s.spawn("tree", -1, Vector2i(21, 13))
		s.queue_command(0, "gather", {"ids": [w[3]], "target": w[2]})
		_steps(s, 700)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])

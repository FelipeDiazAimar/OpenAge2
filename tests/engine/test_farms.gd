extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")


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


func _farm(s: Sim) -> int:
	for id in s.world.ids_with("Farm"):
		return id
	return -1


func test_farm_is_walkable_and_blocks_other_buildings() -> void:
	var s := _sim()
	var f := s.spawn("granja", 0, Vector2i(10, 10))
	assert_true(s.grid.is_walkable(Vector2i(10, 10)) and s.grid.is_walkable(Vector2i(11, 11)), "se pisa")
	assert_true(s.world.has_ability(f, "ResourceSource"))
	assert_eq(s.can_place(0, "casa", Vector2i(11, 11)), "lugar ocupado", "no se construye encima")
	assert_eq(s.can_place(0, "casa", Vector2i(12, 10)), "")
	s.remove(f)
	assert_true(s.grid.is_walkable(Vector2i(10, 10)))


func test_builder_farms_and_food_reaches_mill() -> void:
	var s := _sim()
	s.spawn("molino", 0, Vector2i(14, 10))
	var v := s.spawn("aldeano", 0, Vector2i(10, 13))
	s.queue_command(0, "place", {"ids": [v], "def": "granja", "tile": [10, 10]})
	_steps(s, 40)
	var f := _farm(s)
	assert_true(f >= 0)
	assert_false(s.world.has_ability(f, "ResourceSource"), "el cimiento aún no da comida")
	_steps(s, 120)
	assert_true(s.is_built(f))
	assert_eq(s.world.comp(v, "Gather")["target"], f, "quien la construye la cultiva")
	assert_eq(s.world.comp(v, "Gather")["kind"], "food_farm")
	_steps(s, 600)
	assert_true(s.res_of(0)["food"] > 200, "la comida llega al molino: %d" % s.res_of(0)["food"])


func test_one_farmer_per_farm() -> void:
	var s := _sim()
	s.spawn("centro_urbano", 0, Vector2i(2, 2))
	var f := s.spawn("granja", 0, Vector2i(10, 10))
	var a := s.spawn("aldeano", 0, Vector2i(9, 9))
	var b := s.spawn("aldeano", 0, Vector2i(9, 12))
	s.queue_command(0, "gather", {"ids": [a], "target": f})
	_steps(s, 5)
	s.queue_command(0, "gather", {"ids": [b], "target": f})
	_steps(s, 5)
	assert_eq(s.world.comp(a, "Gather")["target"], f)
	assert_true(s.world.comp(b, "Gather")["target"] != f, "ocupada: el segundo no entra")


func test_farm_reseeds_with_wood_or_disappears() -> void:
	var s := _sim()
	s.spawn("centro_urbano", 0, Vector2i(2, 2))
	var f := s.spawn("granja", 0, Vector2i(10, 10))
	var v := s.spawn("aldeano", 0, Vector2i(10, 12))
	s.world.comp(f, "ResourceSource")["amount"] = 500
	s.queue_command(0, "gather", {"ids": [v], "target": f})
	_steps(s, 60)
	assert_true(s.world.entities.has(f), "se resiembra")
	assert_eq(s.res_of(0)["wood"], 140, "cuesta 60 de madera")
	assert_true(int(s.world.comp(f, "ResourceSource")["amount"]) > 150000, "llena de nuevo: %d" % int(s.world.comp(f, "ResourceSource")["amount"]))
	s.players[0]["res"]["wood"] = 0
	s.world.comp(f, "ResourceSource")["amount"] = 500
	_steps(s, 60)
	assert_false(s.world.entities.has(f), "sin madera se agota y desaparece")

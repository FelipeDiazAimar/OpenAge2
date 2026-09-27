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


func _steps(s: Sim, n: int) -> void:
	for i in n:
		s.step()


func _find(s: Sim, def_id: String, owner: int) -> int:
	for id in s.world.ids_with("Hitpoints"):
		var e: Dictionary = s.world.entities[id]
		if e["def_id"] == def_id and int(e["owner"]) == owner:
			return id
	return -1


func test_place_creates_foundation_and_charges() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	s.queue_command(0, "place", {"ids": [v], "def": "casa", "tile": [12, 12]})
	_steps(s, 3)
	var h := _find(s, "casa", 0)
	assert_true(h >= 0, "cimiento creado")
	assert_true(s.world.has_ability(h, "Foundation"))
	assert_false(s.is_built(h))
	assert_eq(int(s.world.comp(h, "Hitpoints")["hp"]), 1, "empieza con 1 HP")
	assert_eq(s.res_of(0)["wood"], 175, "cobra 25 de madera")
	assert_false(s.grid.is_walkable(Vector2i(13, 13)), "bloquea su huella")


func test_place_rejects_blocked_unaffordable_and_locked() -> void:
	var s := _sim()
	s.spawn("tree", -1, Vector2i(13, 12))
	assert_eq(s.can_place(0, "casa", Vector2i(12, 12)), "lugar ocupado")
	assert_eq(s.can_place(0, "casa", Vector2i(39, 39)), "lugar ocupado", "fuera del mapa")
	assert_eq(s.can_place(0, "casa", Vector2i(20, 20)), "")
	assert_true(s.can_place(0, "herreria", Vector2i(20, 20)).begins_with("requiere"), "herrería requiere feudal")
	assert_eq(s.can_place(0, "aldeano", Vector2i(20, 20)), "no es un edificio")
	s.players[0]["res"]["wood"] = 10 * 1000
	assert_eq(s.can_place(0, "casa", Vector2i(20, 20)), "recursos insuficientes")
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	s.queue_command(0, "place", {"ids": [v], "def": "casa", "tile": [20, 20]})
	s.queue_command(0, "place", {"ids": [v], "def": "casa", "tile": "basura"})
	_steps(s, 3)
	assert_eq(_find(s, "casa", 0), -1, "sin recursos no se coloca")
	assert_eq(s.res_of(0)["wood"], 10, "no se cobra nada")


func test_foundation_not_functional() -> void:
	var s := _sim()
	var pop0: Vector2i = s.population(0)
	var h := s.place_foundation(0, "casa", Vector2i(12, 12))
	assert_eq(s.population(0).y, pop0.y, "el cimiento no da población")
	var camp := s.place_foundation(0, "campamento_maderero", Vector2i(20, 20))
	var v := s.spawn("aldeano", 0, Vector2i(20, 24))
	var tree := s.spawn("tree", -1, Vector2i(21, 24))
	s.queue_command(0, "gather", {"ids": [v], "target": tree})
	_steps(s, 80)
	assert_true(s.world.comp(v, "Gather")["state"] != "to_drop" or int(s.world.comp(v, "Gather")["dropsite"]) != camp, "no deposita en un cimiento")
	s.world.remove_component(h, "Foundation")
	assert_eq(s.population(0).y, pop0.y + 5, "terminada sí")


func test_place_displaces_units() -> void:
	var s := _sim()
	var u := s.spawn("milicia", 1, Vector2i(13, 13))
	var h := s.place_foundation(0, "casa", Vector2i(12, 12))
	assert_true(h >= 0)
	var t := Grid.tile_of(s.world.entities[u]["pos"])
	assert_false(t.x >= 12 and t.x < 14 and t.y >= 12 and t.y < 14, "la unidad sale de la huella: %s" % t)
	assert_true(s.grid.is_walkable(t))


## Ticks hasta terminar un cimiento de def_id con n aldeanos pegados a él.
func _build_ticks(def_id: String, n: int) -> int:
	var s := _sim()
	var ids: Array = []
	for i in n:
		ids.append(s.spawn("aldeano", 0, Vector2i(11, 12 + i)))
	var h := s.place_foundation(0, def_id, Vector2i(12, 12))
	s.queue_command(0, "build", {"ids": ids, "target": h})
	for t in 2000:
		s.step()
		if s.is_built(h):
			return t + 1 - Sim.INPUT_DELAY
	return -1


func test_build_time_single() -> void:
	var t := _build_ticks("casa", 1)
	assert_true(absi(t - 200) <= 3, "casa con 1 aldeano: 20 s (%d ticks)" % t)


func test_build_time_three() -> void:
	var t := _build_ticks("casa", 3)
	assert_true(absi(t - 120) <= 3, "casa con 3 aldeanos: 20×3/5 = 12 s (%d ticks)" % t)


func test_foundation_hp_grows() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(11, 12))
	var h := s.place_foundation(0, "casa", Vector2i(12, 12))
	s.queue_command(0, "build", {"ids": [v], "target": h})
	_steps(s, 102)
	var hp := int(s.world.comp(h, "Hitpoints")["hp"])
	assert_true(hp > 250 and hp < 300, "mitad de la obra, mitad del HP: %d" % hp)
	_steps(s, 120)
	assert_true(s.is_built(h))
	assert_eq(int(s.world.comp(h, "Hitpoints")["hp"]), 550)
	assert_true(s.drain_events().any(func(e): return e["type"] == "built" and e["id"] == h))


func test_builder_goes_to_gather_after_camp() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	var tree := s.spawn("tree", -1, Vector2i(15, 10))
	s.queue_command(0, "place", {"ids": [v], "def": "campamento_maderero", "tile": [12, 10]})
	_steps(s, 700)
	var camp := _find(s, "campamento_maderero", 0)
	assert_true(s.is_built(camp))
	var g: Dictionary = s.world.comp(v, "Gather")
	assert_eq(g["target"], tree, "se pone a talar junto al campamento")
	assert_true(s.res_of(0)["wood"] > 100 or int(g["carry"]) > 0)


func test_move_stops_building() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(11, 12))
	var h := s.place_foundation(0, "casa", Vector2i(12, 12))
	s.queue_command(0, "build", {"ids": [v], "target": h})
	_steps(s, 20)
	assert_eq(s.world.comp(v, "Build")["state"], "building")
	s.queue_command(0, "move", {"ids": [v], "pos": [5500, 5500]})
	_steps(s, 3)
	assert_eq(s.world.comp(v, "Build")["state"], "idle")
	var p: int = s.world.comp(h, "Foundation")["progress"]
	_steps(s, 20)
	assert_eq(int(s.world.comp(h, "Foundation")["progress"]), p, "sin constructores no avanza")


func test_build_command_resumes_foundation() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(4, 4))
	var enemy := s.spawn("aldeano", 1, Vector2i(11, 13))
	var h := s.place_foundation(0, "casa", Vector2i(12, 12))
	s.queue_command(1, "build", {"ids": [enemy], "target": h})
	s.queue_command(0, "build", {"ids": [v], "target": h})
	_steps(s, 400)
	assert_true(s.is_built(h), "el aldeano camina y la termina")
	assert_eq(s.world.comp(enemy, "Build")["target"], -1, "no se construye un cimiento ajeno")


func test_construction_deterministic() -> void:
	var hashes := []
	for run in 2:
		var s := _sim()
		s.spawn("centro_urbano", 0, Vector2i(2, 2))
		var a := s.spawn("aldeano", 0, Vector2i(10, 10))
		var b := s.spawn("aldeano", 0, Vector2i(10, 11))
		s.spawn("tree", -1, Vector2i(18, 12))
		s.queue_command(0, "place", {"ids": [a, b], "def": "campamento_maderero", "tile": [14, 12]})
		_steps(s, 300)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])

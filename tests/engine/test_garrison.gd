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


func _inside(s: Sim, id: int) -> bool:
	var g: Dictionary = s.world.comp(id, "Garrisoned")
	return not g.is_empty() and bool(g["inside"])


func test_garrison_hides_and_protects() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	var v := s.spawn("aldeano", 0, Vector2i(16, 12))
	var enemy := s.spawn("milicia", 1, Vector2i(20, 12))
	s.queue_command(0, "garrison", {"ids": [v], "target": tc})
	_steps(s, 60)
	assert_true(_inside(s, v), "entró")
	assert_eq(s.world.comp(tc, "Garrison")["units"], [v])
	s.queue_command(1, "attack", {"ids": [enemy], "target": v})
	s.queue_command(0, "move", {"ids": [v], "pos": [30500, 30500]})
	_steps(s, 40)
	assert_eq(int(s.world.comp(v, "Hitpoints")["hp"]), 25, "dentro no lo alcanzan")
	assert_true(_inside(s, v), "no sale con una orden de mover")
	assert_eq(s.population(0).x, 1, "cuenta población")


func test_ungarrison_to_free_tiles() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	var ids := []
	for i in 3:
		ids.append(s.spawn("aldeano", 0, Vector2i(15, 10 + i)))
	s.queue_command(0, "garrison", {"ids": ids, "target": tc})
	_steps(s, 80)
	assert_eq((s.world.comp(tc, "Garrison")["units"] as Array).size(), 3)
	s.queue_command(0, "ungarrison", {"ids": [tc]})
	_steps(s, 3)
	assert_eq((s.world.comp(tc, "Garrison")["units"] as Array).size(), 0)
	for id in ids:
		assert_false(_inside(s, id))
		assert_true(s.grid.is_walkable(Grid.tile_of(s.world.entities[id]["pos"])), "sale a casilla libre")


func test_building_death_ejects() -> void:
	var s := _sim()
	var t := s.spawn("torre_vigia", 0, Vector2i(10, 10))
	var v := s.spawn("aldeano", 0, Vector2i(13, 10))
	s.queue_command(0, "garrison", {"ids": [v], "target": t})
	_steps(s, 40)
	assert_true(_inside(s, v))
	s.kill(t)
	assert_true(s.world.entities.has(v), "sobrevive")
	assert_false(_inside(s, v))
	assert_true(s.world.spatial.query_radius(s.world.entities[v]["pos"], 10).has(v), "vuelve al mapa")


func test_garrison_adds_arrows() -> void:
	var s := _sim()
	var t := s.spawn("torre_vigia", 0, Vector2i(10, 10))
	for i in 3:
		var v := s.spawn("aldeano", 0, Vector2i(13, 10 + i))
		s.queue_command(0, "garrison", {"ids": [v], "target": t})
	_steps(s, 50)
	s.spawn("milicia", 1, Vector2i(16, 11))
	var most := 0
	for i in 60:
		s.step()
		most = maxi(most, s.projectiles.size())
	assert_true(most >= 4, "1 + 3 flechas: %d" % most)


func test_garrison_capacity_and_owner() -> void:
	var s := _sim()
	var t := s.spawn("torre_vigia", 0, Vector2i(10, 10))
	var mine := []
	for i in 7:
		mine.append(s.spawn("aldeano", 0, Vector2i(14, 6 + i)))
	var theirs := s.spawn("aldeano", 1, Vector2i(13, 13))
	s.queue_command(0, "garrison", {"ids": mine, "target": t})
	s.queue_command(1, "garrison", {"ids": [theirs], "target": t})
	_steps(s, 100)
	assert_eq((s.world.comp(t, "Garrison")["units"] as Array).size(), 5, "capacidad 5")
	assert_false(_inside(s, theirs), "no entra en edificio ajeno")


func test_bell_round_trip() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	var vs := []
	for i in 4:
		vs.append(s.spawn("aldeano", 0, Vector2i(18, 8 + i)))
	var m := s.spawn("milicia", 0, Vector2i(17, 14))
	var enemy_v := s.spawn("aldeano", 1, Vector2i(16, 16))
	s.queue_command(0, "bell", {"id": tc})
	_steps(s, 120)
	for v in vs:
		assert_true(_inside(s, v), "campana: aldeanos adentro")
	assert_false(_inside(s, m), "la milicia no")
	assert_false(_inside(s, enemy_v), "los enemigos no")
	s.queue_command(0, "bell", {"id": tc})
	_steps(s, 3)
	for v in vs:
		assert_false(_inside(s, v), "segunda campana: salen")


func test_garrison_deterministic() -> void:
	var hashes := []
	for run in 2:
		var s := _sim()
		var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
		for i in 3:
			s.spawn("aldeano", 0, Vector2i(18, 8 + i))
		s.queue_command(0, "bell", {"id": tc})
		_steps(s, 150)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])

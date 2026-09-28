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


func test_upgrade_converts_live_units() -> void:
	var s := _sim()
	var mine := s.spawn("lancero", 0, Vector2i(10, 10))
	var theirs := s.spawn("lancero", 1, Vector2i(20, 20))
	s.world.comp(mine, "Hitpoints")["hp"] = 30 # 30/45
	s.complete_research(0, "piquero_up")
	assert_eq(s.world.entities[mine]["def_id"], "piquero")
	assert_eq(int(s.world.comp(mine, "Hitpoints")["max"]), 55)
	assert_eq(int(s.world.comp(mine, "Hitpoints")["hp"]), 36, "HP proporcional: 30/45 de 55")
	assert_eq(s.world.comp(mine, "Attack")["params"], s.players[0]["defs"].get_def("piquero")["abilities"]["Attack"])
	assert_eq(s.world.entities[theirs]["def_id"], "lancero", "solo las del jugador")
	var ev := s.drain_events()
	assert_true(ev.any(func(e): return e["type"] == "upgraded" and e["to"] == "piquero"))
	# Sigue funcionando: se mueve y ataca.
	s.queue_command(0, "move", {"ids": [mine], "pos": [15500, 10500]})
	_steps(s, 80)
	assert_true(s.world.entities[mine]["pos"].x > 12000)


func test_train_list_follows_upgrades() -> void:
	var s := _sim()
	s.players[0]["age"] = 2
	var bk := s.spawn("cuartel", 0, Vector2i(10, 10))
	assert_eq(s.train_error(0, bk, "lancero"), "")
	assert_true(s.train_error(0, bk, "piquero") != "", "sin la mejora no hay piquero")
	assert_false(s.trainable_units(0, bk).has("piquero"))
	s.complete_research(0, "piquero_up")
	assert_true(s.train_error(0, bk, "lancero").begins_with("mejorada a"), "ya no se entrena el lancero")
	assert_eq(s.train_error(0, bk, "piquero"), "", "el cuartel entrena la versión mejorada")
	assert_true(s.trainable_units(0, bk).has("piquero") and not s.trainable_units(0, bk).has("lancero"))
	s.queue_command(0, "train", {"id": bk, "def": "piquero"})
	_steps(s, 3)
	assert_eq((s.world.comp(bk, "Queue")["items"] as Array).size(), 1)


func test_upgrade_deterministic() -> void:
	var hashes := []
	for run in 2:
		var s := _sim()
		for i in 3:
			s.spawn("lancero", 0, Vector2i(10 + i, 10))
		s.complete_research(0, "piquero_up")
		_steps(s, 10)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])

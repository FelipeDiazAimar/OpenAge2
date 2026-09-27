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


func test_villager_hunts_deer_then_gathers() -> void:
	var s := _sim()
	s.spawn("centro_urbano", 0, Vector2i(4, 8))
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	var deer := s.spawn("deer", -1, Vector2i(13, 10))
	s.queue_command(0, "gather", {"ids": [v], "target": deer})
	_steps(s, 3)
	assert_eq(s.world.comp(v, "Gather")["state"], "hunting")
	_steps(s, 80)
	assert_true(s.world.entities.has(deer), "la carcasa queda en el suelo")
	assert_false(s.world.has_ability(deer, "Hitpoints"), "ciervo muerto")
	assert_true(s.world.comp(deer, "ResourceSource")["killed"])
	var ev := s.drain_events()
	assert_true(ev.any(func(e): return e["type"] == "carcass" and e["id"] == deer))
	_steps(s, 500)
	assert_true(s.res_of(0)["food"] > 200, "carne depositada en el TC")


func test_boar_fights_back() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	var boar := s.spawn("boar", -1, Vector2i(12, 10))
	s.queue_command(0, "gather", {"ids": [v], "target": boar})
	_steps(s, 60)
	assert_eq(s.world.comp(boar, "Attack")["target"], v, "el jabalí persigue al que lo atacó")
	assert_true(not s.world.entities.has(v) or int(s.world.comp(v, "Hitpoints")["hp"]) < 25)


func test_retarget_after_carcass_skips_boar() -> void:
	var s := _sim()
	s.spawn("centro_urbano", 0, Vector2i(2, 2))
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	var deer := s.spawn("deer", -1, Vector2i(11, 10))
	var boar := s.spawn("boar", -1, Vector2i(10, 12))
	var deer2 := s.spawn("deer", -1, Vector2i(14, 10))
	s.queue_command(0, "gather", {"ids": [v], "target": deer})
	_steps(s, 40)
	s.world.comp(deer, "ResourceSource")["amount"] = 1000
	_steps(s, 200)
	var g: Dictionary = s.world.comp(v, "Gather")
	assert_true(g["target"] != boar, "no ataca un jabalí por su cuenta")
	assert_eq(int(s.world.comp(boar, "Hitpoints")["hp"]), 75)
	assert_true(g["target"] == deer2 or not s.world.has_ability(deer2, "Hitpoints"), "sigue con el siguiente ciervo")


func test_cannot_gather_enemy_sheep() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	var sheep := s.spawn("sheep", 1, Vector2i(11, 10))
	s.queue_command(0, "gather", {"ids": [v], "target": sheep})
	_steps(s, 30)
	assert_eq(s.world.comp(v, "Gather")["state"], "idle")
	assert_eq(int(s.world.comp(sheep, "Hitpoints")["hp"]), 7)
	var own := s.spawn("sheep", 0, Vector2i(9, 10))
	s.queue_command(0, "gather", {"ids": [v], "target": own})
	_steps(s, 80) # 7 HP / 3 por golpe = 3 golpes con recarga de 20 ticks
	assert_false(s.world.has_ability(own, "Hitpoints"), "la propia sí")


func test_military_retaliates_out_of_sight() -> void:
	var s := _sim()
	var m := s.spawn("milicia", 0, Vector2i(10, 10))
	var a := s.spawn("arquero", 1, Vector2i(15, 10))
	s.queue_command(1, "attack", {"ids": [a], "target": m})
	_steps(s, 20)
	assert_eq(s.world.comp(m, "Attack")["target"], a, "atacado desde fuera de su vista (4), responde")
	var v := s.spawn("aldeano", 0, Vector2i(10, 12))
	s.queue_command(1, "attack", {"ids": [a], "target": v})
	_steps(s, 30)
	assert_eq(s.world.comp(v, "Attack")["target"], -1, "los aldeanos no contraatacan")


func test_animals_do_not_block() -> void:
	var s := _sim()
	var deer := s.spawn("deer", -1, Vector2i(5, 5))
	assert_true(s.grid.is_walkable(Vector2i(5, 5)))
	s.kill(deer)
	assert_true(s.grid.is_walkable(Vector2i(5, 5)))
	var tree := s.spawn("tree", -1, Vector2i(6, 6))
	assert_false(s.grid.is_walkable(Vector2i(6, 6)), "los árboles sí bloquean")
	s.remove(tree)
	assert_true(s.grid.is_walkable(Vector2i(6, 6)))


func test_hunting_deterministic() -> void:
	var hashes := []
	for run in 2:
		var s := _sim()
		s.spawn("centro_urbano", 0, Vector2i(4, 8))
		var v := s.spawn("aldeano", 0, Vector2i(10, 10))
		var boar := s.spawn("boar", -1, Vector2i(13, 10))
		s.spawn("deer", -1, Vector2i(10, 14))
		s.queue_command(0, "gather", {"ids": [v], "target": boar})
		_steps(s, 200)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])

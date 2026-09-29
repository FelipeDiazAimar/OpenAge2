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


func _count(s: Sim, def_id: String, owner: int) -> int:
	var n := 0
	for id in s.world.ids_with("Hitpoints"):
		var e: Dictionary = s.world.entities[id]
		if e["def_id"] == def_id and int(e["owner"]) == owner:
			n += 1
	return n


func _items(s: Sim, b: int) -> Array:
	return s.world.comp(b, "Queue")["items"]


func _rich(s: Sim, pid: int) -> void:
	for k in ["wood", "food", "gold", "stone"]:
		s.players[pid]["res"][k] = 5000 * 1000


func test_train_villager() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
	_steps(s, 3)
	assert_eq(s.res_of(0)["food"], 150, "cobra 50 de alimento al encolar")
	assert_eq(_items(s, tc).size(), 1)
	_steps(s, 197) # encolado en el tick 2: 200 ticks de entrenamiento
	assert_eq(_count(s, "aldeano", 0), 0, "aún entrenando")
	_steps(s, 1)
	assert_eq(_count(s, "aldeano", 0), 1, "sale a los 20 s")
	assert_eq(_items(s, tc).size(), 0)
	for id in s.world.ids_with("Gather"):
		var t := Grid.tile_of(s.world.entities[id]["pos"])
		assert_true(s.grid.is_walkable(t), "sale en casilla libre")
		assert_true(maxi(absi(t.x - 12), absi(t.y - 12)) <= 3, "junto al centro: %s" % t)


func test_queue_limit_and_cost() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	_rich(s, 0)
	for i in 7:
		s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
	s.queue_command(0, "train", {"id": tc, "def": "milicia"})
	_steps(s, 3)
	assert_eq(_items(s, tc).size(), 5, "cola de 5")
	assert_eq(s.res_of(0)["food"], 5000 - 250)


func test_cancel_refunds() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
	s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
	_steps(s, 50)
	assert_eq(s.res_of(0)["food"], 100)
	s.queue_command(0, "cancel", {"id": tc, "index": 1})
	s.queue_command(0, "cancel", {"id": tc, "index": 0})
	s.queue_command(0, "cancel", {"id": tc, "index": 5})
	s.queue_command(1, "cancel", {"id": tc, "index": 0})
	_steps(s, 3)
	assert_eq(s.res_of(0)["food"], 200, "reembolso íntegro")
	assert_eq(_items(s, tc).size(), 0)
	assert_eq(int(s.world.comp(tc, "Queue")["progress"]), 0)


func test_housed_pauses_and_resumes() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	for i in 5:
		s.spawn("aldeano", 0, Vector2i(20 + i, 20))
	s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
	_steps(s, 260)
	assert_eq(_count(s, "aldeano", 0), 5, "5/5: sin casas")
	assert_true(s.world.comp(tc, "Queue")["housed"])
	s.spawn("casa", 0, Vector2i(30, 30))
	_steps(s, 202)
	assert_eq(_count(s, "aldeano", 0), 6, "con casa sigue")
	assert_false(s.world.comp(tc, "Queue")["housed"])


func test_housed_no_overshoot_two_buildings() -> void:
	var s := _sim()
	var a := s.spawn("centro_urbano", 0, Vector2i(4, 4))
	var b := s.spawn("centro_urbano", 0, Vector2i(20, 20))
	for i in 9:
		s.spawn("aldeano", 0, Vector2i(10 + i, 12))
	s.queue_command(0, "train", {"id": a, "def": "aldeano"})
	s.queue_command(0, "train", {"id": b, "def": "aldeano"})
	_steps(s, 250)
	assert_eq(s.population(0), Vector2i(10, 10), "no supera el tope")
	assert_eq(_items(s, a).size() + _items(s, b).size(), 1, "uno queda esperando")


func test_rally_move_and_gather() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	var tree := s.spawn("tree", -1, Vector2i(22, 12))
	s.queue_command(0, "rally", {"ids": [tc], "pos": [22500, 12500], "target": tree})
	s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
	_steps(s, 210)
	var v := -1
	for id in s.world.ids_with("Gather"):
		v = id
	assert_true(v >= 0)
	assert_eq(s.world.comp(v, "Gather")["target"], tree, "punto de reunión en un árbol: tala")
	s.queue_command(0, "rally", {"ids": [tc], "pos": [5500, 20500]})
	s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
	_steps(s, 400)
	var far := false
	for id in s.world.ids_with("Gather"):
		far = far or Grid.tile_of(s.world.entities[id]["pos"]) == Vector2i(5, 20)
	assert_true(far, "el segundo camina al punto de reunión")


func test_requirements_block_training() -> void:
	var s := _sim()
	_rich(s, 0)
	var tc := s.spawn("centro_urbano", 0, Vector2i(4, 4))
	var bk := s.spawn("cuartel", 0, Vector2i(20, 20))
	var enemy_bk := s.spawn("cuartel", 1, Vector2i(30, 30))
	assert_eq(s.train_error(0, tc, "milicia"), "este edificio no la entrena")
	assert_true(s.train_error(0, bk, "hombre_armas").begins_with("requiere"), "hombre de armas requiere feudal")
	assert_eq(s.train_error(0, bk, "milicia"), "")
	s.players[0]["defs"].disabled["milicia"] = true
	assert_eq(s.train_error(0, bk, "milicia"), "no disponible para esta civilización")
	s.queue_command(0, "train", {"id": bk, "def": "milicia"})
	s.queue_command(0, "train", {"id": enemy_bk, "def": "lancero"})
	s.queue_command(0, "train", {"id": bk, "def": "hombre_armas"})
	_steps(s, 3)
	assert_eq(_items(s, bk).size(), 0)
	assert_eq(_items(s, enemy_bk).size(), 0, "no se usa un edificio ajeno")
	assert_eq(s.res_of(0)["food"], 5000, "nada cobrado")


func test_foundation_does_not_produce() -> void:
	var s := _sim()
	var tc := s.place_foundation(0, "centro_urbano", Vector2i(10, 10))
	s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
	_steps(s, 3)
	assert_eq(_items(s, tc).size(), 0)


func test_research_updates_live_units() -> void:
	var s := _sim()
	_rich(s, 0)
	s.players[0]["age"] = 1
	var bs := s.spawn("herreria", 0, Vector2i(10, 10))
	var m := s.spawn("milicia", 0, Vector2i(20, 20))
	var before := float(s.world.comp(m, "Attack")["params"]["damage"]["melee"])
	s.queue_command(0, "research", {"id": bs, "tech": "forja"})
	s.queue_command(0, "research", {"id": bs, "tech": "forja"})
	s.queue_command(0, "research", {"id": bs, "tech": "armadura_inf_2"})
	_steps(s, 3)
	assert_eq(_items(s, bs).size(), 1, "una sola vez; cota de malla requiere castillos y la previa")
	assert_eq(s.res_of(0)["food"], 5000 - 150)
	_steps(s, 300)
	assert_true(s.researched(0).has("forja"))
	assert_eq(float(s.world.comp(m, "Attack")["params"]["damage"]["melee"]), before + 1.0, "la milicia viva pega más")
	assert_eq(s.research_error(0, bs, "forja"), "ya investigada o en curso")


func test_refresh_caches_speed_and_hp() -> void:
	var s := _sim()
	var m := s.spawn("milicia", 0, Vector2i(20, 20))
	var step0: int = s.world.comp(m, "Move")["step"]
	s.players[0]["defs"].apply_effects([
		{"target": "id:milicia", "op": "mul", "path": "abilities.Move.speed", "value": 2},
		{"target": "id:milicia", "op": "add", "path": "abilities.Hitpoints.max", "value": 10}])
	s.refresh_caches(0)
	assert_eq(int(s.world.comp(m, "Move")["step"]), step0 * 2)
	assert_eq(int(s.world.comp(m, "Hitpoints")["max"]), 55)
	assert_eq(int(s.world.comp(m, "Hitpoints")["hp"]), 55)


func test_age_up_needs_buildings() -> void:
	var s := _sim()
	_rich(s, 0)
	var tc := s.spawn("centro_urbano", 0, Vector2i(4, 4))
	assert_true(s.age_error(0, tc).begins_with("requiere"))
	s.queue_command(0, "age_up", {"id": tc})
	_steps(s, 3)
	assert_eq(_items(s, tc).size(), 0)
	s.spawn("cuartel", 0, Vector2i(20, 20))
	s.place_foundation(0, "molino", Vector2i(30, 30))
	assert_true(s.age_error(0, tc).begins_with("requiere"), "un cimiento no cuenta")
	s.spawn("molino", 0, Vector2i(30, 20))
	assert_eq(s.age_error(0, tc), "")
	s.queue_command(0, "age_up", {"id": tc})
	s.queue_command(0, "age_up", {"id": tc})
	_steps(s, 3)
	assert_eq(_items(s, tc).size(), 1, "una sola vez")
	assert_eq(s.res_of(0)["food"], 4500)
	_steps(s, 1300)
	assert_eq(s.age_of(0), 1, "feudal")
	assert_eq(s.train_error(0, s.spawn("cuartel", 0, Vector2i(34, 4)), "hombre_armas"), "")


func test_economy_cycle_deterministic() -> void:
	var hashes := []
	for run in 2:
		var s := _sim()
		var tc := s.spawn("centro_urbano", 0, Vector2i(4, 4))
		var v := s.spawn("aldeano", 0, Vector2i(10, 10))
		var tree := s.spawn("tree", -1, Vector2i(14, 12))
		s.queue_command(0, "place", {"ids": [v], "def": "casa", "tile": [12, 4]})
		s.queue_command(0, "rally", {"ids": [tc], "pos": [14500, 12500], "target": tree})
		for i in 3:
			s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
		_steps(s, 700)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])


func test_destroyed_building_releases_pending_age() -> void:
	var s := _sim()
	_rich(s, 0)
	var tc := s.spawn("centro_urbano", 0, Vector2i(4, 4))
	s.spawn("cuartel", 0, Vector2i(20, 20))
	s.spawn("molino", 0, Vector2i(30, 20))
	s.queue_command(0, "age_up", {"id": tc})
	_steps(s, 3)
	assert_eq(s.age_error(0, tc), "ya en curso")
	s.kill(tc)
	var tc2 := s.spawn("centro_urbano", 0, Vector2i(10, 30))
	assert_eq(s.age_error(0, tc2), "", "la edad se puede volver a investigar")


func test_blocked_exit_keeps_unit() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	for y in range(0, 40):
		for x in range(0, 40):
			var inside := x >= 10 and x < 14 and y >= 10 and y < 14
			if not inside and maxi(absi(x - 11), absi(y - 11)) <= 12:
				s.grid.set_blocked(Vector2i(x, y), true)
	s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
	_steps(s, 260)
	assert_eq(_count(s, "aldeano", 0), 0)
	assert_eq(_items(s, tc).size(), 1, "la unidad espera lista, no se pierde")
	assert_eq(s.res_of(0)["food"], 150)
	s.grid.set_blocked(Vector2i(12, 15), false)
	_steps(s, 2)
	assert_eq(_count(s, "aldeano", 0), 1, "sale al liberarse una casilla")


func test_exit_avoids_sealed_pocket() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	# Hueco cerrado de una casilla junto a la salida por defecto (12, 14).
	for t in [Vector2i(11, 14), Vector2i(13, 14), Vector2i(11, 15), Vector2i(12, 15), Vector2i(13, 15)]:
		s.grid.set_blocked(t, true)
	s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
	_steps(s, 205)
	for id in s.world.ids_with("Gather"):
		assert_true(Grid.tile_of(s.world.entities[id]["pos"]) != Vector2i(12, 14), "no aparece en el hueco")


func test_enemy_payloads_are_inert() -> void:
	var s := _sim()
	_rich(s, 1)
	s.players[0]["age"] = 1
	var tc := s.spawn("centro_urbano", 0, Vector2i(4, 4))
	var bs := s.spawn("herreria", 0, Vector2i(20, 20))
	s.queue_command(1, "train", {"id": tc, "def": "aldeano"})
	s.queue_command(1, "research", {"id": bs, "tech": "forja"})
	s.queue_command(1, "rally", {"ids": [tc], "pos": [30000, 30000]})
	s.queue_command(1, "age_up", {"id": tc})
	_steps(s, 3)
	assert_eq(_items(s, tc).size() + _items(s, bs).size(), 0)
	assert_eq(s.world.comp(tc, "Queue")["rally"], Vector2i(-1, -1))
	assert_eq(s.res_of(1)["food"], 5000)


func test_population_unlimited_by_default() -> void:
	var s := _sim()
	for i in 45:
		s.spawn("casa", 0, Vector2i(2 * (i % 15) + 1, 2 * (i / 15) + 1))
	assert_eq(s.population(0).y, 225, "sin tope: 45 casas × 5")
	s.pop_max = 200
	assert_eq(s.population(0).y, 200, "con tope de AoE2")

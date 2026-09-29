extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const MapGen := preload("res://engine/sim/MapGen.gd")


## Mapa 40×40 con un lago rectangular x 15..29, y 5..34.
func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	for y in range(5, 35):
		for x in range(15, 30):
			s.grid.set_water(Vector2i(x, y))
	return s


func _steps(s: Sim, n: int) -> void:
	for i in n:
		s.step()


func _tile(s: Sim, id: int) -> Vector2i:
	return Grid.tile_of(s.world.entities[id]["pos"])


func test_domains_land_unit_stays_on_land() -> void:
	var s := _sim()
	var u := s.spawn("milicia", 0, Vector2i(10, 20))
	s.queue_command(0, "move", {"ids": [u], "pos": [22500, 20500]})
	_steps(s, 200)
	assert_false(s.grid.is_water(_tile(s, u)), "se queda en la orilla: %s" % _tile(s, u))
	assert_true(_tile(s, u).x <= 14)


func test_domains_ship_stays_on_water() -> void:
	var s := _sim()
	var ship := s.spawn("galera", 0, Vector2i(20, 20))
	assert_true(s.world.has_ability(ship, "Naval"))
	s.queue_command(0, "move", {"ids": [ship], "pos": [27500, 30500]})
	_steps(s, 200)
	assert_eq(_tile(s, ship), Vector2i(27, 30), "navega")
	s.queue_command(0, "move", {"ids": [ship], "pos": [5500, 20500]})
	_steps(s, 300)
	assert_true(s.grid.is_water(_tile(s, ship)), "no sale a tierra: %s" % _tile(s, ship))


func test_domains_separation_respects_water() -> void:
	var s := _sim()
	var ids := []
	for i in 4:
		ids.append(s.world.spawn(s.registry.get_def("milicia"), 0, Vector2i(14500, 20500)))
	var ships := []
	for i in 4:
		var sh: int = s.spawn("galera", 0, Vector2i(15, 20))
		s.world.set_pos(sh, Vector2i(15500, 20500))
		ships.append(sh)
	_steps(s, 20)
	for id in ids:
		assert_false(s.grid.is_water(_tile(s, id)), "nadie empujado al agua")
	for id in ships:
		assert_true(s.grid.is_water(_tile(s, id)), "ningún barco empujado a tierra")


func test_domains_fish_removal_keeps_water() -> void:
	var s := _sim()
	var f := s.spawn("shore_fish", -1, Vector2i(16, 20))
	assert_false(s.grid.naval.is_walkable(Vector2i(16, 20)), "el pez es obstáculo para barcos")
	s.remove(f)
	assert_false(s.grid.is_walkable(Vector2i(16, 20)), "sigue siendo agua para la tierra")
	assert_true(s.grid.naval.is_walkable(Vector2i(16, 20)))


func test_domains_deterministic() -> void:
	var hashes := []
	for run in 2:
		var s := _sim()
		var ship := s.spawn("galera", 0, Vector2i(20, 20))
		var u := s.spawn("milicia", 0, Vector2i(10, 20))
		s.queue_command(0, "move", {"ids": [ship], "pos": [27500, 30500]})
		s.queue_command(0, "move", {"ids": [u], "pos": [22500, 20500]})
		_steps(s, 150)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])


func test_dock_only_on_coast() -> void:
	var s := _sim()
	s.players[0]["res"]["wood"] = 5000 * 1000
	assert_eq(s.can_place(0, "muelle", Vector2i(15, 10)), "", "en el agua junto a la orilla")
	assert_eq(s.can_place(0, "muelle", Vector2i(20, 15)), "el muelle debe tocar la costa", "mar adentro")
	assert_eq(s.can_place(0, "muelle", Vector2i(13, 10)), "el muelle va en el agua", "medio en tierra")
	assert_eq(s.can_place(0, "casa", Vector2i(16, 10)), "lugar ocupado", "una casa no va en el agua")
	var d := s.spawn("muelle", 0, Vector2i(15, 10))
	assert_false(s.grid.naval.is_walkable(Vector2i(16, 11)), "bloquea a los barcos")
	s.remove(d)
	assert_true(s.grid.naval.is_walkable(Vector2i(16, 11)))
	assert_false(s.grid.is_walkable(Vector2i(16, 11)), "sigue siendo agua")


func test_dock_trains_ships_on_water() -> void:
	var s := _sim()
	s.players[0]["res"]["wood"] = 5000 * 1000
	s.players[0]["res"]["food"] = 5000 * 1000
	var d := s.spawn("muelle", 0, Vector2i(15, 10))
	s.spawn("casa", 0, Vector2i(5, 5))
	s.queue_command(0, "train", {"id": d, "def": "barco_pesquero"})
	_steps(s, 600)
	var boats := []
	for id in s.world.ids_with("Naval"):
		boats.append(id)
	assert_eq(boats.size(), 1, "sale el barco")
	assert_true(s.grid.is_water(_tile(s, boats[0])), "en el agua")


func test_villager_builds_dock_from_shore() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(13, 11))
	s.players[0]["res"]["wood"] = 5000 * 1000
	s.queue_command(0, "place", {"ids": [v], "def": "muelle", "tile": [15, 10]})
	_steps(s, 700)
	var docks := []
	for id in s.world.ids_with("Dock"):
		docks.append(id)
	assert_eq(docks.size(), 1)
	assert_true(s.is_built(docks[0]), "lo construye desde la orilla")


func test_fishing_boat_round_trip_to_dock() -> void:
	var s := _sim()
	s.spawn("centro_urbano", 0, Vector2i(5, 18)) # más cerca, pero en tierra
	var d := s.spawn("muelle", 0, Vector2i(15, 10))
	var fish := s.spawn("deep_fish", -1, Vector2i(22, 22))
	var boat := s.spawn("barco_pesquero", 0, Vector2i(18, 14))
	s.queue_command(0, "gather", {"ids": [boat], "target": fish})
	_steps(s, 700)
	assert_true(s.res_of(0)["food"] > 200, "descarga en el muelle: %d" % s.res_of(0)["food"])
	assert_true(s.grid.is_water(_tile(s, boat)))
	assert_true(d > 0)


func test_boat_rejects_land_resources_and_villager_fishes_from_shore() -> void:
	var s := _sim()
	s.spawn("centro_urbano", 0, Vector2i(8, 18))
	var tree := s.spawn("tree", -1, Vector2i(12, 20))
	var boat := s.spawn("barco_pesquero", 0, Vector2i(18, 14))
	s.queue_command(0, "gather", {"ids": [boat], "target": tree})
	_steps(s, 5)
	assert_eq(s.world.comp(boat, "Gather")["state"], "idle", "un barco no tala")
	var shore := s.spawn("shore_fish", -1, Vector2i(15, 20))
	var v := s.spawn("aldeano", 0, Vector2i(12, 22))
	s.queue_command(0, "gather", {"ids": [v], "target": shore})
	_steps(s, 120)
	assert_eq(s.world.comp(v, "Gather")["state"], "gathering", "llega a la orilla y pesca")
	_steps(s, 400)
	assert_true(s.res_of(0)["food"] > 200, "el aldeano pesca desde la orilla")
	assert_false(s.grid.is_water(_tile(s, v)))


func test_galley_sinks_fishing_boat_and_shoots_shore() -> void:
	var s := _sim()
	var gal := s.spawn("galera", 0, Vector2i(20, 12))
	var boat := s.spawn("barco_pesquero", 1, Vector2i(26, 28))
	s.queue_command(0, "attack", {"ids": [gal], "target": boat})
	_steps(s, 600)
	assert_false(s.world.entities.has(boat), "hunde al pesquero")
	assert_true(s.grid.is_water(_tile(s, gal)))
	var v := s.spawn("aldeano", 1, Vector2i(13, 20))
	s.queue_command(0, "attack", {"ids": [gal], "target": v})
	_steps(s, 400)
	assert_true(not s.world.entities.has(v) or int(s.world.comp(v, "Hitpoints")["hp"]) < 25, "dispara a la orilla")
	assert_true(s.grid.is_water(_tile(s, gal)), "sin salir del agua")


func test_land_villager_skips_dock_for_berries() -> void:
	var s := _sim()
	s.spawn("centro_urbano", 0, Vector2i(3, 20))
	s.spawn("muelle", 0, Vector2i(15, 10))
	var bush := s.spawn("berry_bush", -1, Vector2i(12, 12))
	var v := s.spawn("aldeano", 0, Vector2i(12, 13))
	s.queue_command(0, "gather", {"ids": [v], "target": bush})
	for i in 400:
		s.step()
		if s.world.comp(v, "Gather")["state"] == "to_drop":
			break
	var d: int = s.world.comp(v, "Gather")["dropsite"]
	assert_eq(s.world.entities[d]["def_id"], "centro_urbano", "las bayas van al centro, no al muelle")


func test_unreachable_dropsite_falls_back() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(3, 25))
	var camp := s.spawn("campamento_maderero", 0, Vector2i(3, 3))
	for t in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(2, 3), Vector2i(5, 3),
			Vector2i(2, 4), Vector2i(5, 4), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5)]:
		s.grid.set_blocked(t, true) # campamento encerrado
	var tree := s.spawn("tree", -1, Vector2i(8, 12))
	var v := s.spawn("aldeano", 0, Vector2i(8, 13))
	s.queue_command(0, "gather", {"ids": [v], "target": tree})
	_steps(s, 900)
	assert_true(s.res_of(0)["wood"] > 200, "descarga en el centro urbano: %d" % s.res_of(0)["wood"])
	assert_true(tc > 0 and camp > 0)


func test_dock_over_ships_and_debug_spawn_domain() -> void:
	var s := _sim()
	s.players[0]["res"]["wood"] = 5000 * 1000
	var mine := s.spawn("galera", 0, Vector2i(16, 11))
	var theirs := s.spawn("galera", 1, Vector2i(16, 25))
	assert_eq(s.can_place(0, "muelle", Vector2i(15, 24)), "hay unidades de otro jugador")
	var d := s.place_foundation(0, "muelle", Vector2i(15, 10))
	assert_true(d >= 0)
	assert_true(s.grid.is_water(_tile(s, mine)), "mi barco sale al agua")
	assert_false(_tile(s, mine).x >= 15 and _tile(s, mine).x < 18 and _tile(s, mine).y >= 10 and _tile(s, mine).y < 13)
	s.debug_enabled = true
	s.queue_command(0, "debug_spawn", {"def": "galera", "n": 3, "pos": [5500, 5500], "owner": 0})
	_steps(s, 3)
	for id in s.world.ids_with("Naval"):
		assert_true(s.grid.is_water(_tile(s, id)), "ningún barco en tierra")
	assert_true(theirs > 0)


func test_lake_skips_occupied_and_start_tiles() -> void:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 60, 60)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	var tc := s.spawn("centro_urbano", 0, Vector2i(28, 28))
	var starts: Array[Vector2i] = [Vector2i(30, 30), Vector2i(50, 50)]
	MapGen.generate(s, 1, starts)
	assert_false(s.grid.is_water(Vector2i(30, 30)), "no inunda el inicio")
	s.remove(tc)
	assert_false(s.grid.is_water(Vector2i(29, 29)))


func test_transport_carries_units_across_lake() -> void:
	var s := _sim()
	var ship := s.spawn("transporte", 0, Vector2i(15, 20))
	var ids := []
	for i in 3:
		ids.append(s.spawn("milicia", 0, Vector2i(12, 19 + i)))
	s.queue_command(0, "garrison", {"ids": ids, "target": ship})
	_steps(s, 80)
	assert_eq((s.world.comp(ship, "Garrison")["units"] as Array).size(), 3, "suben desde la orilla")
	# Cruza al otro lado (x 30+ es tierra) y desembarca.
	s.queue_command(0, "unload", {"ids": [ship], "pos": [31500, 20500]})
	_steps(s, 400)
	for u in ids:
		assert_true(s.world.comp(u, "Garrisoned").is_empty(), "bajaron")
		var t := _tile(s, u)
		assert_true(t.x >= 30 and not s.grid.is_water(t), "del otro lado, en tierra: %s" % t)


func test_sinking_transport_kills_passengers_and_bell_ignores_ships() -> void:
	var s := _sim()
	var ship := s.spawn("transporte", 0, Vector2i(15, 20))
	var u := s.spawn("milicia", 0, Vector2i(13, 20))
	s.queue_command(0, "garrison", {"ids": [u], "target": ship})
	_steps(s, 60)
	assert_true(bool(s.world.comp(u, "Garrisoned").get("inside", false)))
	s.kill(ship)
	assert_false(s.world.entities.has(u), "se hunde con el barco")
	var tc := s.spawn("centro_urbano", 0, Vector2i(3, 3))
	var ship2 := s.spawn("transporte", 0, Vector2i(15, 8))
	var v := s.spawn("aldeano", 0, Vector2i(13, 8))
	s.queue_command(0, "bell", {"id": tc})
	_steps(s, 150)
	assert_true((s.world.comp(ship2, "Garrison")["units"] as Array).is_empty(), "la campana no manda al barco")
	assert_true(v > 0)

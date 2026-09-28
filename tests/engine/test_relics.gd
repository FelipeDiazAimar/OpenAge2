extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const MapGen := preload("res://engine/sim/MapGen.gd")


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


func _relic_count(s: Sim) -> int:
	return s.world.ids_with("Relic").size()


func test_monk_brings_relic_to_monastery_for_gold() -> void:
	var s := _sim()
	var mon := s.spawn("monasterio", 0, Vector2i(4, 4))
	var monk := s.spawn("monje", 0, Vector2i(10, 10))
	var relic := s.spawn("reliquia", -1, Vector2i(14, 10))
	assert_true(s.grid.is_walkable(Vector2i(14, 10)), "la reliquia no bloquea")
	s.queue_command(0, "pick_relic", {"ids": [monk], "target": relic})
	_steps(s, 80)
	assert_true(s.world.has_ability(monk, "Carrying"), "la lleva")
	assert_false(s.world.spatial.query_radius(s.world.entities[monk]["pos"], 2000).has(relic), "fuera del mapa mientras la lleva")
	s.queue_command(0, "store_relic", {"ids": [monk], "target": mon})
	_steps(s, 200)
	assert_eq(s.world.comp(mon, "RelicHolder")["relics"], [relic])
	var gold0: int = s.res_of(0)["gold"]
	_steps(s, 100)
	assert_eq(s.res_of(0)["gold"] - gold0, 5, "0,5 de oro por segundo")


func test_only_monks_pick_relics() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	var relic := s.spawn("reliquia", -1, Vector2i(11, 10))
	s.queue_command(0, "pick_relic", {"ids": [v], "target": relic})
	_steps(s, 30)
	assert_false(s.world.has_ability(relic, "Held"))


func test_relic_drops_when_monk_dies_or_monastery_falls() -> void:
	var s := _sim()
	var mon := s.spawn("monasterio", 0, Vector2i(4, 4))
	var monk := s.spawn("monje", 0, Vector2i(10, 10))
	var relic := s.spawn("reliquia", -1, Vector2i(11, 10))
	s.queue_command(0, "pick_relic", {"ids": [monk], "target": relic})
	_steps(s, 40)
	assert_true(s.world.has_ability(monk, "Carrying"))
	s.kill(monk)
	assert_false(s.world.has_ability(relic, "Held"), "vuelve al suelo")
	assert_eq(int(s.world.entities[relic]["owner"]), -1)
	assert_true(s.world.spatial.query_radius(s.world.entities[relic]["pos"], 10).has(relic))
	var monk2 := s.spawn("monje", 0, Vector2i(9, 9))
	s.queue_command(0, "pick_relic", {"ids": [monk2], "target": relic})
	_steps(s, 60)
	s.queue_command(0, "store_relic", {"ids": [monk2], "target": mon})
	_steps(s, 200)
	assert_eq((s.world.comp(mon, "RelicHolder")["relics"] as Array).size(), 1)
	s.kill(mon)
	assert_eq(_relic_count(s), 1, "nunca se pierde")
	assert_false(s.world.has_ability(relic, "Held"))


func test_monk_with_relic_does_not_convert() -> void:
	var s := _sim()
	var monk := s.spawn("monje", 0, Vector2i(10, 10))
	var relic := s.spawn("reliquia", -1, Vector2i(11, 10))
	s.queue_command(0, "pick_relic", {"ids": [monk], "target": relic})
	_steps(s, 40)
	var u := s.spawn("arquero", 1, Vector2i(13, 10))
	s.queue_command(0, "convert", {"ids": [monk], "target": u})
	_steps(s, 150)
	assert_eq(int(s.world.entities[u]["owner"]), 1)


func test_mapgen_places_relics_far_from_starts() -> void:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 144, 144)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	var starts: Array[Vector2i] = [Vector2i(39, 39), Vector2i(105, 105)]
	MapGen.generate(s, 3, starts)
	assert_eq(_relic_count(s), MapGen.RELICS)


func test_auto_heal_does_not_steal_pick_order() -> void:
	for off in 10:
		var s := _sim()
		var monk := s.spawn("monje", 0, Vector2i(10, 10))
		var relic := s.spawn("reliquia", -1, Vector2i(14 + off % 3, 10))
		var hurt := s.spawn("milicia", 0, Vector2i(10, 14))
		s.world.comp(hurt, "Hitpoints")["hp"] = 5
		_steps(s, off)
		s.queue_command(0, "pick_relic", {"ids": [monk], "target": relic})
		_steps(s, 100)
		assert_true(s.world.has_ability(monk, "Carrying"), "recoge la reliquia (desfase %d)" % off)


func test_convert_order_cancels_pending_pick() -> void:
	var s := _sim()
	var monk := s.spawn("monje", 0, Vector2i(10, 10))
	var relic := s.spawn("reliquia", -1, Vector2i(20, 10))
	var foe := s.spawn("arquero", 1, Vector2i(10, 15))
	s.queue_command(0, "pick_relic", {"ids": [monk], "target": relic})
	_steps(s, 5)
	s.queue_command(0, "convert", {"ids": [monk], "target": foe})
	_steps(s, 150)
	assert_false(s.world.has_ability(monk, "RelicTask"))
	assert_eq(int(s.world.entities[foe]["owner"]), 0, "convierte en vez de ir por la reliquia")


func test_converting_monk_obeys_garrison() -> void:
	var s := _sim()
	s.players[0]["age"] = 1
	var tower := s.spawn("torre_vigia", 0, Vector2i(6, 10))
	var monk := s.spawn("monje", 0, Vector2i(10, 10))
	var foe := s.spawn("arquero", 1, Vector2i(16, 10))
	s.queue_command(0, "convert", {"ids": [monk], "target": foe})
	_steps(s, 20)
	s.queue_command(0, "garrison", {"ids": [monk], "target": tower})
	_steps(s, 120)
	assert_true(bool(s.world.comp(monk, "Garrisoned").get("inside", false)), "se guarece")
	assert_eq(int(s.world.entities[foe]["owner"]), 1)


func test_mapgen_seeds_match_rng() -> void:
	var r := Registry.new()
	r.load_mods("res://mods")
	var starts: Array[Vector2i] = [Vector2i(39, 39), Vector2i(105, 105)]
	var draws := []
	for sd in [1, 2]:
		var s := Sim.new(r, 144, 144)
		s.add_player(0, "britones", 0)
		s.add_player(1, "francos", 1)
		MapGen.generate(s, sd, starts)
		draws.append(s.rng.next_u32())
	assert_true(draws[0] != draws[1], "cada mapa, su azar de conversiones")

extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const MapGen := preload("res://engine/sim/MapGen.gd")
const Grid := preload("res://engine/sim/Grid.gd")

const STARTS: Array[Vector2i] = [Vector2i(39, 39), Vector2i(105, 105)]


func _gen(sd: int) -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 144, 144)
	for i in STARTS.size():
		s.add_player(i, "britones", i)
		s.spawn("centro_urbano", i, STARTS[i] - Vector2i(2, 2))
		s.spawn("aldeano", i, STARTS[i] + Vector2i(3, -1))
	MapGen.generate(s, sd, STARTS)
	return s


func _count_near(s: Sim, c: Vector2i, def_id: String, r: int) -> int:
	var n := 0
	for id in s.world.entities:
		var e: Dictionary = s.world.entities[id]
		if e["def_id"] != def_id:
			continue
		var t := Grid.tile_of(e["pos"])
		if maxi(absi(t.x - c.x), absi(t.y - c.y)) <= r:
			n += 1
	return n


func test_mine_piles_are_compact() -> void:
	for sd in [1, 2, 3]:
		var s := _gen(sd)
		for c in STARTS:
			var lo := Vector2i(9999, 9999)
			var hi := Vector2i(-9999, -9999)
			for id in s.world.entities:
				var e: Dictionary = s.world.entities[id]
				if e["def_id"] != "gold_mine":
					continue
				var t := Grid.tile_of(e["pos"])
				if maxi(absi(t.x - c.x), absi(t.y - c.y)) > 14:
					continue
				lo = Vector2i(mini(lo.x, t.x), mini(lo.y, t.y))
				hi = Vector2i(maxi(hi.x, t.x), maxi(hi.y, t.y))
			var size := hi - lo + Vector2i.ONE
			assert_true(size.x <= 4 and size.y <= 4, "pila de oro compacta (semilla %d): %s" % [sd, size])


func test_deterministic() -> void:
	assert_eq(_gen(7).state_hash(), _gen(7).state_hash())
	assert_true(_gen(7).state_hash() != _gen(8).state_hash())


func test_players_get_resources_and_are_connected() -> void:
	for sd in [1, 2, 3]:
		var s := _gen(sd)
		var region := -1
		for c in STARTS:
			assert_true(_count_near(s, c, "gold_mine", 16) >= 7, "oro cerca (semilla %d)" % sd)
			assert_true(_count_near(s, c, "stone_mine", 16) >= 5, "piedra cerca (semilla %d)" % sd)
			assert_true(_count_near(s, c, "berry_bush", 14) >= 6, "bayas cerca (semilla %d)" % sd)
			assert_true(_count_near(s, c, "tree", 22) >= 30, "bosque cerca (semilla %d)" % sd)
			for def_id in ["tree", "gold_mine", "stone_mine", "berry_bush"]:
				assert_eq(_count_near(s, c, def_id, MapGen.CLEAR_R), 0, "claro alrededor del TC (semilla %d)" % sd)
			var r: int = s.grid.region_of(c + Vector2i(3, -1))
			assert_true(r >= 0)
			if region < 0:
				region = r
			assert_eq(r, region, "todos los inicios conectados (semilla %d)" % sd)
		var total_trees := _count_near(s, Vector2i(72, 72), "tree", 80)
		assert_true(total_trees > 400, "bosques generales: %d" % total_trees)


func test_animals_per_player() -> void:
	for sd in [1, 2]:
		var s := _gen(sd)
		for i in STARTS.size():
			var c: Vector2i = STARTS[i]
			var own_sheep := 0
			for id in s.world.entities:
				var e: Dictionary = s.world.entities[id]
				if e["def_id"] == "sheep" and e["owner"] == i:
					var t := Grid.tile_of(e["pos"])
					if maxi(absi(t.x - c.x), absi(t.y - c.y)) <= 7:
						own_sheep += 1
					assert_true(s.grid.is_walkable(t), "oveja en casilla libre")
			assert_eq(own_sheep, 4, "4 ovejas propias junto al TC (semilla %d)" % sd)
			assert_eq(_count_near(s, c, "boar", 18), 2, "2 jabalíes (semilla %d)" % sd)
			assert_true(_count_near(s, c, "deer", 24) >= 3, "ciervos (semilla %d)" % sd)


func test_mapgen_water() -> void:
	var s := _gen(5)
	var c := Vector2i(72, 72)
	assert_true(s.grid.is_water(c), "lago en el centro")
	var fish := 0
	for id in s.world.entities:
		var e: Dictionary = s.world.entities[id]
		var t := Grid.tile_of(e["pos"])
		if e["def_id"] == "shore_fish" or e["def_id"] == "deep_fish":
			fish += 1
			assert_true(s.grid.is_water(t), "peces en el agua")
		elif str(e["type"]) != "unit":
			assert_false(s.grid.is_water(t), "%s fuera del agua" % e["def_id"])
	assert_eq(fish, MapGen.SHORE_FISH + MapGen.DEEP_FISH)

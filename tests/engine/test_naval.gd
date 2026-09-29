extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const Grid := preload("res://engine/sim/Grid.gd")


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

extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const Grid := preload("res://engine/sim/Grid.gd")


## Muro vertical en x=20 (y 0..39) con una puerta del jugador 0 en y 19-20.
func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	s.add_player(2, "godos", 0) # aliado del 0
	for y in 40:
		if y == 19 or y == 20:
			continue
		s.spawn("muro", 0, Vector2i(20, y))
		s.spawn("muro", 0, Vector2i(21, y))
	return s


func _steps(s: Sim, n: int) -> void:
	for i in n:
		s.step()


func test_gate_lets_owner_and_allies_through() -> void:
	var s := _sim()
	var gate := s.spawn("puerta", 0, Vector2i(20, 19))
	assert_true(gate >= 0)
	var mine := s.spawn("milicia", 0, Vector2i(10, 19))
	var ally := s.spawn("milicia", 2, Vector2i(10, 21))
	s.queue_command(0, "move", {"ids": [mine], "pos": [30500, 19500]})
	s.queue_command(2, "move", {"ids": [ally], "pos": [30500, 21500]})
	_steps(s, 300)
	assert_true(Grid.tile_of(s.world.entities[mine]["pos"]).x >= 28, "el dueño cruza")
	assert_true(Grid.tile_of(s.world.entities[ally]["pos"]).x >= 28, "el aliado cruza")


func test_gate_stops_enemies_until_broken() -> void:
	var s := _sim()
	var gate := s.spawn("puerta", 0, Vector2i(20, 19))
	var foe := s.spawn("milicia", 1, Vector2i(10, 19))
	s.queue_command(1, "move", {"ids": [foe], "pos": [30500, 19500]})
	_steps(s, 300)
	assert_true(Grid.tile_of(s.world.entities[foe]["pos"]).x < 20, "el enemigo no pasa: %s" % Grid.tile_of(s.world.entities[foe]["pos"]))
	s.kill(gate)
	s.queue_command(1, "move", {"ids": [foe], "pos": [30500, 19500]})
	_steps(s, 300)
	assert_true(Grid.tile_of(s.world.entities[foe]["pos"]).x >= 28, "rota la puerta, pasa")


func test_nothing_built_on_a_gate() -> void:
	var s := _sim()
	s.spawn("puerta", 0, Vector2i(20, 19))
	s.players[0]["res"]["stone"] = 1000000
	s.players[0]["age"] = 1
	assert_eq(s.can_place(0, "muro", Vector2i(20, 19)), "lugar ocupado")


func test_enemy_army_breaks_the_gate() -> void:
	var s := _sim()
	var gate := s.spawn("puerta", 0, Vector2i(20, 19))
	s.world.comp(gate, "Hitpoints")["hp"] = 200 # (2750 enteros: ~5 min con 6 milicias)
	var foes := []
	for i in 6:
		foes.append(s.spawn("milicia", 1, Vector2i(10, 17 + i)))
	s.queue_command(1, "move", {"ids": foes, "pos": [30500, 19500]})
	_steps(s, 1200)
	assert_false(s.world.entities.has(gate), "la rompen al chocar con ella")


func test_crowd_cannot_be_pushed_through_enemy_gate() -> void:
	var s := _sim()
	s.spawn("puerta", 0, Vector2i(20, 19))
	var foes := []
	for i in 10:
		foes.append(s.spawn("aldeano", 1, Vector2i(14 + i % 3, 18 + i / 3)))
	for k in 6:
		s.queue_command(1, "move", {"ids": foes, "pos": [30500, 19500]})
		_steps(s, 200)
	for f in foes:
		var t := Grid.tile_of(s.world.entities[f]["pos"])
		assert_true(t.x < 20, "nadie cruza a empujones: %s" % t)


func test_gate_foundation_does_not_block() -> void:
	var s := _sim()
	s.place_foundation(0, "puerta", Vector2i(20, 19))
	var foe := s.spawn("aldeano", 1, Vector2i(10, 19))
	s.queue_command(1, "move", {"ids": [foe], "pos": [30500, 19500]})
	_steps(s, 400)
	assert_true(Grid.tile_of(s.world.entities[foe]["pos"]).x >= 28, "un cimiento todavía no cierra")

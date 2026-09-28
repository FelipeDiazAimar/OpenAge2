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


func test_repair_restores_hp() -> void:
	var s := _sim()
	var h := s.spawn("casa", 0, Vector2i(12, 12))
	s.world.comp(h, "Hitpoints")["hp"] = 250
	var v := s.spawn("aldeano", 0, Vector2i(8, 12))
	s.queue_command(0, "repair", {"ids": [v], "target": h})
	_steps(s, 90)
	assert_eq(s.world.comp(v, "Build")["state"], "repairing")
	var hp1 := int(s.world.comp(h, "Hitpoints")["hp"])
	assert_true(hp1 > 250, "sube el HP: %d" % hp1)
	_steps(s, 400)
	assert_eq(int(s.world.comp(h, "Hitpoints")["hp"]), 550, "queda entera")
	assert_eq(s.world.comp(v, "Build")["state"], "idle", "al terminar se detiene")
	var spent := 200 - int(s.res_of(0)["wood"])
	assert_true(spent >= 6 and spent <= 8, "300 HP de 550 al 50%% de 25 madera ≈ 7: %d" % spent)


func test_repair_costs_and_stops() -> void:
	var s := _sim()
	var h := s.spawn("casa", 0, Vector2i(12, 12))
	s.world.comp(h, "Hitpoints")["hp"] = 100
	s.players[0]["res"]["wood"] = 2 * 1000
	var v := s.spawn("aldeano", 0, Vector2i(11, 12))
	s.queue_command(0, "repair", {"ids": [v], "target": h})
	_steps(s, 600)
	assert_eq(s.world.comp(v, "Build")["state"], "idle", "sin madera se detiene")
	var hp := int(s.world.comp(h, "Hitpoints")["hp"])
	assert_true(hp > 100 and hp < 550, "reparó lo que pagó: %d" % hp)
	assert_true(int(s.players[0]["res"]["wood"]) >= 0)


func test_no_repair_of_foundation_or_enemy() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(8, 12))
	var f := s.place_foundation(0, "casa", Vector2i(12, 12))
	var e := s.spawn("casa", 1, Vector2i(20, 20))
	s.world.comp(e, "Hitpoints")["hp"] = 100
	var full := s.spawn("casa", 0, Vector2i(25, 12))
	s.queue_command(0, "repair", {"ids": [v], "target": f})
	_steps(s, 3)
	assert_eq(s.world.comp(v, "Build")["state"], "idle", "un cimiento se construye, no se repara")
	s.queue_command(0, "repair", {"ids": [v], "target": e})
	s.queue_command(0, "repair", {"ids": [v], "target": full})
	s.queue_command(1, "repair", {"ids": [v], "target": e})
	_steps(s, 30)
	assert_eq(int(s.world.comp(e, "Hitpoints")["hp"]), 100)
	assert_eq(s.world.comp(v, "Build")["state"], "idle")

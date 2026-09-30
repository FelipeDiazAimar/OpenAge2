extends "res://tests/engine/TestCase.gd"
const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const Cards := preload("res://engine/sim/systems/CardSystem.gd")
func _sim() -> Sim:
	var r := Registry.new(); r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40); s.add_player(0, "britones", 0); return s
func test_buff_aplica_hp() -> void:
	var s := _sim(); s.players[0]["age"] = 3
	var u := s.spawn("aldeano", 0, Vector2i(10, 10))
	assert_eq(Cards.play_card(s, 0, "neut_telar_2"), "")
	assert_eq(int(s.world.comp(u, "Hitpoints")["max"]), 40)
func test_envio_res_suma() -> void:
	var s := _sim(); s.players[0]["age"] = 3
	assert_eq(Cards.play_card(s, 0, "neut_madera_1"), "")
	assert_eq(s.res_of(0)["wood"], 500)
func test_coste_se_cobra() -> void:
	var s := _sim(); s.players[0]["age"] = 3
	assert_eq(Cards.play_card(s, 0, "brit_levas_1"), "")
	assert_eq(s.res_of(0)["food"], 140)
func test_edad_insuficiente_bloquea() -> void:
	var s := _sim(); var w0: int = s.res_of(0)["wood"]
	var e := Cards.play_card(s, 0, "neut_campeon_elite_4")
	assert_true(e != "", "bloquea por edad")
	assert_eq(s.res_of(0)["wood"], w0)

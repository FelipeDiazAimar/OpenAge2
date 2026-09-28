extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const TradeSystem := preload("res://engine/sim/systems/TradeSystem.gd")


## Jugadores 0 y 1 aliados (equipo 0); 2 enemigo.
func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 60, 60)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 0)
	s.add_player(2, "godos", 1)
	return s


func _steps(s: Sim, n: int) -> void:
	for i in n:
		s.step()


func test_trade_with_ally_brings_gold_by_distance() -> void:
	var s := _sim()
	var home := s.spawn("mercado", 0, Vector2i(5, 5))
	var ally := s.spawn("mercado", 1, Vector2i(35, 5))
	var cart := s.spawn("carreta_comercio", 0, Vector2i(9, 6))
	s.queue_command(0, "trade", {"ids": [cart], "target": ally})
	_steps(s, 3)
	assert_eq(s.world.comp(cart, "Trade")["state"], "to_target")
	var per_trip: int = TradeSystem.trip_gold(s, cart, home, ally)
	assert_eq(per_trip, 20000 + 300 * 30, "20 + 0,3 × 30 casillas")
	var gold0: int = s.res_of(0)["gold"]
	_steps(s, 700)
	assert_true(s.res_of(0)["gold"] >= gold0 + 29, "al menos un viaje de ida y vuelta: %d" % (s.res_of(0)["gold"] - gold0))
	assert_eq(s.res_of(1)["gold"], 100, "el aliado no pierde nada")


func test_no_trade_with_self_or_enemy() -> void:
	var s := _sim()
	s.spawn("mercado", 0, Vector2i(5, 5))
	var own2 := s.spawn("mercado", 0, Vector2i(35, 5))
	var enemy := s.spawn("mercado", 2, Vector2i(35, 35))
	var cart := s.spawn("carreta_comercio", 0, Vector2i(9, 6))
	assert_eq(TradeSystem.trade_error(s, cart, own2), "comercia con el mercado de otro jugador")
	assert_eq(TradeSystem.trade_error(s, cart, enemy), "mercado enemigo")
	s.queue_command(0, "trade", {"ids": [cart], "target": enemy})
	_steps(s, 5)
	assert_eq(s.world.comp(cart, "Trade")["state"], "idle")


func test_trade_stops_if_market_destroyed() -> void:
	var s := _sim()
	s.spawn("mercado", 0, Vector2i(5, 5))
	var ally := s.spawn("mercado", 1, Vector2i(35, 5))
	var cart := s.spawn("carreta_comercio", 0, Vector2i(9, 6))
	s.queue_command(0, "trade", {"ids": [cart], "target": ally})
	_steps(s, 20)
	s.kill(ally)
	_steps(s, 2)
	assert_eq(s.world.comp(cart, "Trade")["state"], "idle")


func test_drop_off() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(30, 30))
	var near := s.spawn("campamento_maderero", 0, Vector2i(12, 8))
	var v := s.spawn("aldeano", 0, Vector2i(10, 12))
	var tree := s.spawn("tree", -1, Vector2i(10, 13))
	s.queue_command(0, "gather", {"ids": [v], "target": tree})
	_steps(s, 60)
	var g: Dictionary = s.world.comp(v, "Gather")
	assert_true(int(g["carry"]) > 0 and int(g["carry"]) < 10000, "a medio cargar")
	var carried: int = g["carry"]
	s.queue_command(0, "drop", {"ids": [v], "target": near})
	_steps(s, 80)
	assert_true(s.res_of(0)["wood"] >= 200 + carried / 1000, "descargó")
	assert_eq(s.world.comp(v, "Gather")["target"], tree, "vuelve a su árbol")
	var e := s.spawn("campamento_maderero", 2, Vector2i(20, 20))
	s.queue_command(0, "drop", {"ids": [v], "target": e})
	_steps(s, 3)
	assert_true(str(s.world.comp(v, "Gather")["dropsite"]) != str(e), "no en depósito ajeno")
	assert_true(tc > 0)

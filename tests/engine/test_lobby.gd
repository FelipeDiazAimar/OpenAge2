extends "res://tests/engine/TestCase.gd"

const MatchConfig := preload("res://game/MatchConfig.gd")
const FakeNet := preload("res://tests/engine/fixtures/FakeNet.gd")
const LOBBY := "res://game/scenes/Lobby.tscn"
const MATCH := "res://game/scenes/Match.tscn"


func test_lobby_builds() -> void:
	var l = load(LOBBY).instantiate()
	Engine.get_main_loop().root.add_child(l)
	assert_true(l.civs.size() >= 5, "civilizaciones en la sala")
	assert_true(l._connect_box.visible, "primero: crear o unirse")
	assert_false(l._room.visible)
	l.queue_free()
	var n = Engine.get_main_loop().root.get_node_or_null("NetSession")
	if n != null:
		n.queue_free()


func _net_match(local: int) -> Array:
	var net := FakeNet.new()
	net.local_pid = local
	MatchConfig.slots = [{"civ": "britones", "team": 0, "name": "Ana"}, {"civ": "francos", "team": 1, "name": "Beto"}]
	MatchConfig.map_seed = 99
	MatchConfig.net = net
	var m = load(MATCH).instantiate()
	Engine.get_main_loop().root.add_child(m)
	return [m, net]


func test_match_waits_for_remote_turns() -> void:
	var p := _net_match(1)
	var m = p[0]
	var net = p[1]
	assert_eq(m.local_pid, 1, "juega con su pid de la red")
	assert_true(m.ais.is_empty(), "el rival es humano")
	# Sin los turnos del otro, solo avanza lo que permite el retraso.
	var steps := 0
	for i in 10:
		if m._step_sim():
			steps += 1
	assert_eq(steps, 1, "espera los turnos del otro jugador")
	assert_eq(m.lockstep.waiting_for(), [0])
	# Llegan los turnos: sigue.
	for t in 5:
		net.packet.emit(0, {"k": "turn", "tick": t, "cmds": []})
	assert_true(m._step_sim())
	assert_true(net.sent.size() >= 2, "envía su turno cada tick")
	m.queue_free()


func test_local_orders_travel_with_turn() -> void:
	var p := _net_match(0)
	var m = p[0]
	var net = p[1]
	m._cmd("move", {"units": [], "target": [10000, 10000]})
	m._step_sim()
	assert_eq(net.sent[0]["k"], "turn")
	assert_eq(net.sent[0]["cmds"].size(), 1, "la orden viaja con el turno")
	assert_eq(net.sent[0]["cmds"][0]["type"], "move")
	m.queue_free()


func test_peer_left_stops_waiting() -> void:
	var p := _net_match(0)
	var m = p[0]
	var net = p[1]
	for i in 3:
		m._step_sim()
	assert_false(m._step_sim())
	net.peer_left.emit(1)
	assert_true(m._step_sim(), "sin el que se fue, sigue")
	m.queue_free()

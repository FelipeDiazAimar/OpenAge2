extends "res://tests/engine/TestCase.gd"

const NetSession := preload("res://game/net/NetSession.gd")

var _port := 17780


## Anfitrión y cliente en el mismo proceso, cada uno con su SceneMultiplayer.
func _pair(host_hash: String, client_hash: String) -> Array:
	_port += 1
	var tree := Engine.get_main_loop()
	var out: Array = []
	for i in 2:
		var holder := Node.new()
		holder.name = "NetRoot%d_%d" % [_port, i]
		tree.root.add_child(holder)
		var s = NetSession.new()
		s.name = "NetSession"
		holder.add_child(s)
		var mp := SceneMultiplayer.new()
		tree.set_multiplayer(mp, holder.get_path())
		s.setup(host_hash if i == 0 else client_hash, "Ana" if i == 0 else "Beto", mp)
		out.append(s)
	assert_eq(out[0].host(_port), "")
	assert_eq(out[1].join("127.0.0.1", _port), "")
	return out


func _pump(sessions: Array, cond: Callable, max_iter: int = 400) -> bool:
	for i in max_iter:
		for s in sessions:
			s.poll(0.01)
		if cond.call():
			return true
		OS.delay_msec(5)
	return false


func _close(sessions: Array) -> void:
	for s in sessions:
		s.leave()
		s.get_parent().queue_free()


func test_join_lobby_ready_and_start() -> void:
	var p := _pair("H", "H")
	var h = p[0]
	var c = p[1]
	assert_true(_pump(p, func(): return h.slots.size() == 2 and c.slots.size() == 2), "el cliente entra a la sala")
	assert_eq(h.start_error(), "Beto no está listo")
	c.set_mine({"ready": true, "civ": "godos"})
	assert_true(_pump(p, func(): return bool(h.slots[1]["ready"]) and h.slots[1]["civ"] == "godos"), "listo y civ")
	h.host_add_ai("vikingos")
	assert_true(_pump(p, func(): return c.slots.size() == 3), "el cliente ve la IA")
	var got := [{}, {}]
	h.started.connect(func(cfg): got[0] = cfg)
	c.started.connect(func(cfg): got[1] = cfg)
	assert_eq(h.start(4321, 0, true), "")
	assert_true(_pump(p, func(): return not got[1].is_empty()), "arranca en las dos PC")
	assert_eq(h.local_pid, 0)
	assert_eq(c.local_pid, 1)
	assert_eq(got[1]["map_seed"], 4321)
	assert_eq(got[1]["slots"].size(), 3)
	assert_true(got[1]["slots"][2]["ai"])
	assert_eq(c.human_pids(), [0, 1])
	# Paquetes del lockstep: llegan con el pid de quien los mandó.
	var recv := []
	h.packet.connect(func(pid, pkt): recv.append([pid, pkt]))
	c.send({"k": "turn", "tick": 0, "cmds": []})
	assert_true(_pump(p, func(): return not recv.is_empty()))
	assert_eq(recv[0][0], 1, "pid del cliente")
	_close(p)


func test_different_data_cannot_start() -> void:
	var p := _pair("H", "OTRO")
	var h = p[0]
	var c = p[1]
	assert_true(_pump(p, func(): return h.slots.size() == 2))
	c.set_mine({"ready": true})
	_pump(p, func(): return bool(h.slots[1]["ready"]))
	assert_true(h.start_error().contains("otros datos"), h.start_error())
	_close(p)


func test_disconnect_in_game_is_reported() -> void:
	var p := _pair("H", "H")
	var h = p[0]
	var c = p[1]
	_pump(p, func(): return h.slots.size() == 2)
	c.set_mine({"ready": true})
	_pump(p, func(): return bool(h.slots[1]["ready"]))
	h.start(1, 0, true)
	_pump(p, func(): return c.in_game)
	var left := []
	h.peer_left.connect(func(pid): left.append(pid))
	c.leave()
	assert_true(_pump([h], func(): return not left.is_empty(), 600), "el anfitrión se entera")
	assert_eq(left[0], 1)
	h.leave()
	h.get_parent().queue_free()
	c.get_parent().queue_free()

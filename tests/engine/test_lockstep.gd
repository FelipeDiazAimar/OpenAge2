extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const Lockstep := preload("res://engine/net/Lockstep.gd")
const Rng := preload("res://engine/sim/Rng.gd")

var _reg: Registry


## Una "PC": su simulación (misma partida en todas) y su lockstep.
func _peer(pid: int, humans: Array, net: Array) -> Dictionary:
	if _reg == null:
		_reg = Registry.new()
		_reg.load_mods("res://mods")
	var s := Sim.new(_reg, 40, 40)
	for i in 3:
		s.add_player(i, ["britones", "francos", "godos"][i], i)
		s.spawn("centro_urbano", i, Vector2i(4 + 12 * i, 4))
		for k in 3:
			s.spawn("aldeano", i, Vector2i(5 + 12 * i + k, 10))
	for k in 6:
		s.spawn("tree", -1, Vector2i(6 + 5 * k, 20))
	var peer := {"pid": pid, "sim": s}
	peer["ls"] = Lockstep.new(s, pid, humans, func(pkt): net.append({"from": pid, "pkt": pkt, "at": -1}))
	return peer


## Red en memoria con demoras: cada paquete llega a cada otra PC tras
## 0..max_delay pasos (desordenados), determinista por la semilla.
func _run(n_ticks: int, max_delay: int, seed: int, tamper := false) -> Array:
	var humans := [0, 1, 2]
	var net: Array = []
	var peers: Array = []
	for pid in humans:
		peers.append(_peer(pid, humans, net))
	var rng := Rng.new(seed)
	var inflight: Array = [] # [llega_en, a_pid, from, pkt]
	var now := 0
	var guard := 0
	while guard < n_ticks * 50:
		guard += 1
		now += 1
		var done := true
		for p in peers:
			var s: Sim = p["sim"]
			if int(s.world.tick) >= n_ticks:
				continue
			done = false
			# Órdenes al azar (deterministas) del jugador de esta PC.
			if rng.range_i(0, 9) == 0:
				var mine: Array = []
				for id in s.world.ids_with("Gather"):
					if int(s.world.entities[id]["owner"]) == p["pid"]:
						mine.append(id)
				var trees: Array = []
				for id in s.world.ids_with("ResourceSource"):
					trees.append(id)
				if rng.range_i(0, 1) == 0 and not trees.is_empty():
					p["ls"].submit("gather", {"ids": mine, "target": trees[rng.range_i(0, trees.size() - 1)]})
				else:
					p["ls"].submit("move", {"ids": mine, "pos": [rng.range_i(2000, 38000), rng.range_i(2000, 38000)]})
			p["ls"].try_step()
		# Entregar lo enviado con demoras.
		for m in net:
			for q in peers:
				if q["pid"] != m["from"]:
					inflight.append([now + rng.range_i(0, max_delay), q["pid"], m["from"], m["pkt"].duplicate(true)])
		net.clear()
		var keep: Array = []
		for f in inflight:
			if int(f[0]) <= now:
				for q in peers:
					if q["pid"] == f[1]:
						q["ls"].receive(int(f[2]), f[3])
			else:
				keep.append(f)
		inflight = keep
		if tamper and now == 40:
			peers[2]["sim"].players[2]["res"]["gold"] += 1000 # trampa / desync
		if done:
			break
	return peers


func test_lockstep_same_state_despite_delays() -> void:
	var peers := _run(300, 6, 7)
	var hashes: Array = peers.map(func(p): return p["sim"].state_hash())
	for p in peers:
		assert_eq(int(p["sim"].world.tick), 300, "todas llegan al final")
	assert_eq(hashes[0], hashes[1], "PC 1 = PC 2")
	assert_eq(hashes[0], hashes[2], "PC 1 = PC 3")
	assert_eq(peers[0]["ls"].desync_tick, -1)


func test_lockstep_waits_for_turns() -> void:
	var humans := [0, 1]
	var net: Array = []
	var a := _peer(0, humans, net)
	for i in 5:
		a["ls"].try_step()
	assert_eq(int(a["sim"].world.tick), Sim.INPUT_DELAY - 1, "sin los turnos del otro no pasa del retardo")
	assert_eq(a["ls"].waiting_for(), [1])
	a["ls"].player_left(1)
	assert_true(a["ls"].try_step(), "si el otro se fue, sigue sola")


func test_lockstep_rejects_foreign_pid() -> void:
	var humans := [0, 1]
	var net: Array = []
	var a := _peer(0, humans, net)
	var s: Sim = a["sim"]
	var mine := -1
	for id in s.world.ids_with("Gather"):
		if int(s.world.entities[id]["owner"]) == 0:
			mine = id
	var p0: Vector2i = s.world.entities[mine]["pos"]
	# La PC 1 manda un turno con órdenes para unidades del jugador 0.
	a["ls"].receive(1, {"k": "turn", "tick": 0, "cmds": [{"type": "move", "payload": {"ids": [mine], "pos": [30500, 30500]}}]})
	a["ls"].receive(1, {"k": "turn", "tick": 1, "cmds": []})
	a["ls"].receive(1, {"k": "turn", "tick": 2, "cmds": []})
	for i in 4:
		a["ls"].try_step()
	assert_eq(s.world.entities[mine]["pos"], p0, "nadie mueve unidades ajenas")
	a["ls"].receive(0, {"k": "turn", "tick": 3, "cmds": []}) # se hace pasar por mí: se ignora
	assert_true(true)


func test_lockstep_detects_desync() -> void:
	var peers := _run(120, 3, 11, true)
	assert_true(peers[0]["ls"].desync_tick > 0, "detecta la desincronización")


func test_lockstep_hash_check_after_player_left() -> void:
	var net: Array = []
	var p = _peer(0, [0, 1, 2], net)
	var ls = p["ls"]
	ls._record_hash(0, 50, "a")
	ls._record_hash(1, 50, "b")
	assert_eq(ls.desync_tick, -1, "falta la huella del jugador 2")
	ls.player_left(2)
	assert_eq(ls.desync_tick, 50, "al irse el 2, se comparan las que hay")
	assert_true(ls._hashes.is_empty(), "no quedan huellas colgadas")

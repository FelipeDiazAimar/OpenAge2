extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const MatchSetup := preload("res://game/MatchSetup.gd")
const MatchLogger := preload("res://game/diag/MatchLogger.gd")
const AIPlayer := preload("res://engine/ai/AIPlayer.gd")
const Replay := preload("res://tools/replay_log.gd")

const TEST_DIR := "user://logs/test_partidas"
const CFG := {"slots": [{"civ": "britones", "team": 0}, {"civ": "francos", "team": 1, "ai": true}],
	"map_seed": 99, "pop_max": 0, "lake": true}


func _lines(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	while f != null and not f.eof_reached():
		var l := f.get_line().strip_edges()
		if l != "":
			out.append(JSON.parse_string(l))
	return out


func _kinds(lines: Array) -> Array:
	return lines.map(func(d): return str(d.get("t", "")))


func _logged_match(ticks: int) -> Array:
	var r := Registry.new()
	r.load_mods("res://mods")
	var sim = MatchSetup.build(r, CFG)
	var ai := AIPlayer.new(sim, 1)
	var log := MatchLogger.new()
	log.dir = TEST_DIR
	Engine.get_main_loop().root.add_child(log)
	log.start(sim, CFG, 0, [1], r)
	# Órdenes del jugador: aldeanos a juntar y el TC a entrenar.
	var vs := []
	for id in sim.world.ids_with("Gather"):
		if int(sim.world.entities[id]["owner"]) == 0:
			vs.append(id)
	sim.queue_command(0, "move", {"ids": vs, "pos": [45500, 45500]})
	for t in ticks:
		sim.step()
		ai.tick()
		log.after_tick(10, 5)
		log.frame(0.016)
	return [sim, log]


func test_log_has_header_commands_pulses_and_end() -> void:
	var r := _logged_match(320)
	var log = r[1]
	log.finish()
	var lines := _lines(log.path)
	var kinds := _kinds(lines)
	assert_eq(kinds[0], "inicio")
	assert_eq(lines[0]["cfg"]["map_seed"], 99.0, "guarda las opciones para rearmar la partida")
	assert_true(lines.any(func(d): return d["t"] == "cmd" and d["src"] == "jugador"), "órdenes del jugador")
	assert_true(lines.any(func(d): return d["t"] == "cmd" and d["src"] == "ia"), "órdenes de la IA")
	assert_eq(kinds.count("pulso"), 3, "un pulso cada 100 ticks")
	assert_eq(kinds[kinds.size() - 1], "fin")
	log.queue_free()


func test_replay_reproduces_the_match() -> void:
	var r := _logged_match(320)
	var log = r[1]
	log.finish()
	assert_eq(Replay.run(log.path), 0, "la repetición coincide pulso a pulso")
	log.queue_free()


func test_invariants_detect_anomalies() -> void:
	var r := _logged_match(5)
	var sim = r[0]
	var log = r[1]
	sim.players[0]["res"]["gold"] = -5000
	var v := -1
	for id in sim.world.ids_with("Gather"):
		v = id
	sim.grid.set_blocked(Vector2i(sim.world.entities[v]["pos"] / 1000), true)
	log.check_invariants()
	log.finish()
	var lines := _lines(log.path)
	var que := lines.filter(func(d): return d["t"] == "anomalia").map(func(d): return d["que"])
	assert_true(que.has("recurso_negativo"))
	assert_true(que.has("unidad_en_casilla_bloqueada"))
	log.queue_free()


func test_watchdog_logs_freeze() -> void:
	var r := _logged_match(2)
	var log = r[1]
	log.freeze_ms = 300
	for i in MatchLogger.ARM_FRAMES:
		log.frame(0.016)
	OS.delay_msec(900) # el hilo principal "se traba"
	log.frame(0.9)
	log.finish()
	var kinds := _kinds(_lines(log.path))
	assert_true(kinds.has("congelado"), "el vigilante lo anota")
	assert_true(kinds.has("descongelado"), "y cuánto duró")
	log.queue_free()


func test_unfinished_log_is_reported() -> void:
	var r := _logged_match(150)
	var log = r[1]
	# Sin finish(): como si el juego se hubiera cerrado de golpe.
	var lines := _lines(log.path)
	assert_false(_kinds(lines).has("fin"), "sin línea fin = la partida se cortó")
	log.finish()
	log.queue_free()


func test_mark_saves_screenshot_line() -> void:
	var r := _logged_match(3)
	var log = r[1]
	log.mark(null, "prueba")
	log.finish()
	assert_true(_lines(log.path).any(func(d): return d["t"] == "marca" and d["nota"] == "prueba"))
	log.queue_free()

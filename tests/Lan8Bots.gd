extends SceneTree
# tests/Lan8Bots.gd - Test LAN 8 bots headless (Godot 4.4).
#
# Uso:
#   godot --headless --path . -s tests/Lan8Bots.gd -- --ticks 3600 --seed 42 --map arabia
#   sh tests/run_all.sh [ticks]
#
# Que hace:
#   1. Monta un lobby de 8 bots (equipos 0/1, 4 civs) con semilla fija.
#   2. Simula TICKS ticks lockstep a 10 Hz (3600 ticks = 6 min de partida):
#      cada bot emite ordenes deterministas (mover, gather, build casa,
#      train aldeano, attack-move) via SimAPI.queue_command(). GameManager
#      las ejecuta con retardo INPUT_DELAY y orden total determinista.
#   3. Cada 300 ticks cada bot envia tributo de madera al companero
#      (comando "tribute", que SI muta el estado de GameManager) para que
#      sim_hash_state() evolucione durante el test.
#   4. Registra sim_hash_state() cada 30 ticks (igual que DesyncDetector en
#      red) mas un acumulado FNV de los lotes de comandos de cada tick.
#   5. Repite la pasada A/B con la MISMA semilla (= 2 instancias logicamente
#      identicas) y compara checkpoint a checkpoint: cualquier diferencia
#      significa DESYNC y el test falla.
#
# Determinismo: NO se usa randi/randf/Time/OS en la generacion de ordenes;
# solo un LCG propio con semilla reseteada por pasada.
# Salida: 0 = PASS sin desync, 1 = FAIL desync/error, 2 = error de entorno.

const DEFAULT_TICKS := 3600
const NUM_BOTS := 8
const DEFAULT_SEED := 42
const CHECK_EVERY := 30 # igual que DesyncDetector en red
const PROGRESS_EVERY := 600
const TRIBUTE_EVERY := 300
const DRAIN_TICKS := 2 # debe coincidir con SimAPI.INPUT_DELAY
const ORDER_CHANCE := 25 # % por bot y tick de emitir orden (media 2/tick)
const MAP_SIZE := 120
const CIVS := ["britones", "francos", "godos", "bizantinos"]
const RES_KINDS := ["wood", "food", "gold", "stone"]

var Sim = null # autoload SimAPI (lockstep, buffer, hash)
var GM = null # autoload GameManager (estado, tick, sim_hash_state)
var _rng := 0
var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	quit(_main())
	return true


func _main() -> int:
	var ticks := DEFAULT_TICKS
	var seed := DEFAULT_SEED
	var map_name := "arabia"
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--ticks="):
			ticks = maxi(60, int(s.get_slice("=", 1)))
		elif s.begins_with("--seed="):
			seed = int(s.get_slice("=", 1))
		elif s.begins_with("--map="):
			map_name = s.get_slice("=", 1).to_lower()
	GM = root.get_node_or_null("GameManager")
	Sim = root.get_node_or_null("SimAPI")
	if GM == null or Sim == null:
		printerr("[Lan8Bots] ERROR entorno: autoloads GameManager/SimAPI no encontrados. Ejecuta desde la raiz del proyecto.")
		return 2
	print("[Lan8Bots] mapa=%s ticks=%d seed=%d bots=%d" % [map_name, ticks, seed, NUM_BOTS])
	var pass_a := _run_pass("A", ticks, seed)
	if int(pass_a.get("error", 0)) != 0:
		return 1
	var pass_b := _run_pass("B", ticks, seed)
	if int(pass_b.get("error", 0)) != 0:
		return 1
	return _compare_passes(pass_a, pass_b, ticks)


func _make_slots() -> Array:
	var slots: Array = []
	for i in NUM_BOTS:
		slots.append({"civ": CIVS[i % CIVS.size()], "team": i % 2})
	return slots


func _run_pass(tag: String, ticks: int, seed: int) -> Dictionary:
	Sim.reset()
	GM.setup_match(_make_slots(), seed)
	if GM.players.size() != NUM_BOTS:
		printerr("[Lan8Bots:%s] FAIL: lobby con %d jugadores (esperado %d)" % [tag, GM.players.size(), NUM_BOTS])
		return {"error": 1}
	_srand(seed)
	var hashes := {}
	var accum := 0
	var issued := [0] # contador mutable (Array de 1 elem)
	var total := ticks + DRAIN_TICKS
	for t in range(1, total + 1):
		if t <= ticks:
			_issue_bot_orders(issued)
			_maybe_tribute(t, issued)
		var batch: Array = Sim.peek_commands_for_tick(t)
		accum = (accum * 31 + Sim.sim_hash(batch)) & 0xFFFFFFFF
		GM._on_tick(t)
		if t <= ticks and t % CHECK_EVERY == 0:
			hashes[t] = GM.sim_hash_state()
		if t <= ticks and t % PROGRESS_EVERY == 0:
			print("[Lan8Bots:%s] tick %d ok hash=%d cmds=%d" % [tag, t, GM.sim_hash_state(), issued[0]])
	Sim.discard_ticks_older_than(total + 1)
	print("[Lan8Bots:%s] fin: %d ticks, %d checkpoints, %d comandos, accum=%d" % [tag, total, hashes.size(), issued[0], accum])
	return {"error": 0, "hashes": hashes, "accum": accum, "cmds": issued[0]}


func _issue_bot_orders(issued: Array) -> void:
	for pid in NUM_BOTS:
		if _rnd(100) >= ORDER_CHANCE:
			continue
		match _rnd(5):
			0:
				Sim.queue_command(pid, "move", {"x": _rnd(MAP_SIZE), "y": _rnd(MAP_SIZE)})
			1:
				Sim.queue_command(pid, "gather", {"res": RES_KINDS[_rnd(RES_KINDS.size())], "x": _rnd(MAP_SIZE), "y": _rnd(MAP_SIZE)})
			2:
				Sim.queue_command(pid, "build", {"building": "casa", "x": _rnd(MAP_SIZE), "y": _rnd(MAP_SIZE)})
			3:
				Sim.queue_command(pid, "train", {"unit": "aldeano", "building": "centro_urbano"})
			_:
				Sim.queue_command(pid, "attack_move", {"x": _rnd(MAP_SIZE), "y": _rnd(MAP_SIZE)})
		issued[0] = int(issued[0]) + 1


func _maybe_tribute(t: int, issued: Array) -> void:
	# Muta el estado via lockstep para que el hash evolucione (las ordenes de
	# movimiento/recoleccion las consumen los sistemas en una partida real;
	# aqui GameManager solo aplica tribute/research/resign).
	if t % TRIBUTE_EVERY != 0:
		return
	for pid in NUM_BOTS:
		var mate := (pid + 2) % NUM_BOTS # mismo equipo (equipos = pid % 2)
		if GM.has_resources(pid, {"wood": 10.0}):
			Sim.queue_command(pid, "tribute", {"to": mate, "res": "wood", "amount": 10.0})
			issued[0] = int(issued[0]) + 1


func _compare_passes(pass_a: Dictionary, pass_b: Dictionary, ticks: int) -> int:
	var ha: Dictionary = pass_a["hashes"]
	var hb: Dictionary = pass_b["hashes"]
	var mismatches: Array = []
	for t in ha.keys():
		if int(ha[t]) != int(hb.get(t, -1)):
			mismatches.append(t)
	mismatches.sort()
	var ok := true
	if int(pass_a["cmds"]) != int(pass_b["cmds"]):
		printerr("[Lan8Bots] FAIL: comandos emitidos A=%d B=%d" % [int(pass_a["cmds"]), int(pass_b["cmds"])])
		ok = false
	if int(pass_a["accum"]) != int(pass_b["accum"]):
		printerr("[Lan8Bots] FAIL: acumulado de lotes A=%d B=%d (orden de comandos no determinista)" % [int(pass_a["accum"]), int(pass_b["accum"])])
		ok = false
	if not mismatches.is_empty():
		ok = false
		printerr("[Lan8Bots] FAIL: DESYNC en %d/%d checkpoints, primeros: %s" % [mismatches.size(), ha.size(), str(mismatches.slice(0, 5))])
		for t in mismatches.slice(0, 3):
			printerr("[Lan8Bots]   tick %d: A=%d B=%d" % [int(t), int(ha[t]), int(hb.get(t, -1))])
	if not ok:
		printerr("[Lan8Bots] LAN_8_BOTS FAIL con desync")
		return 1
	print("[Lan8Bots] LAN_8_BOTS PASS sin desync (%d ticks, %d bots, %d cmds, %d checkpoints cada %d ticks)" % [ticks, NUM_BOTS, int(pass_a["cmds"]), ha.size(), CHECK_EVERY])
	return 0


# --- LCG determinista propio (prohibido randi/randf en logica/tests) ---

func _srand(seed: int) -> void:
	_rng = seed & 0xFFFFFFFF


func _rnd(m: int) -> int:
	_rng = (_rng * 1664525 + 1013904223) & 0xFFFFFFFF
	return int(_rng % maxi(m, 1))

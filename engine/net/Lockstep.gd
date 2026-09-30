extends RefCounted
## Lockstep determinista (sin red: el transporte lo pone game/net).
##
## Cada PC ejecuta la misma simulación. Las órdenes que da un jugador en su
## tick T se aplican en T + INPUT_DELAY en todas las PC. Al terminar el turno
## T, cada PC envía {tick: T, cmds} (aunque esté vacío). El tick N solo se
## simula cuando llegaron los turnos N - INPUT_DELAY de todos los humanos
## que siguen en la partida: así nadie se adelanta y nadie recibe una orden
## tarde. Cada HASH_EVERY ticks se comparan las huellas (state_hash); si
## difieren, hay desincronización.
##
## La IA corre igual en todas las PC (determinista) y sus órdenes no viajan.

const HASH_EVERY := 50
const KEEP_TICKS := 64

var sim
var local_pid := 0
## Jugadores humanos (cuyos turnos se esperan).
var humans: Array = []
## send.call(paquete: Dictionary): lo envía a las demás PC.
var send := Callable()
## on_desync.call(tick, {pid: hash}).
var on_desync := Callable()
## Primer tick con huellas distintas (-1: ninguno).
var desync_tick := -1
## Jugadores que se fueron (no se los espera más).
var left: Dictionary = {}

var _out: Array = []
var _ended := -1
var _turns: Dictionary = {} # pid -> {tick: true}
var _hashes: Dictionary = {} # tick -> {pid: hash}


func _init(p_sim, p_local: int, p_humans: Array, p_send: Callable) -> void:
	sim = p_sim
	local_pid = p_local
	humans = p_humans.duplicate()
	humans.sort()
	send = p_send
	for p in humans:
		_turns[p] = {}


## Orden del jugador local: se aplica aquí y viaja con el turno. Si el turno
## del tick actual ya se envió (esperando a otros), pertenece al siguiente,
## también aquí: si no, se aplicaría en ticks distintos en cada PC.
func submit(type: String, payload: Dictionary) -> void:
	var t: int = sim.world.tick
	if _ended == t:
		t += 1
	sim.queue_command_at(t, local_pid, type, payload)
	_out.append({"type": type, "payload": payload})


## Cierra el turno del tick actual (una vez por tick) y lo envía.
func end_turn() -> void:
	var t: int = sim.world.tick
	if _ended == t:
		return
	_ended = t
	if send.is_valid():
		send.call({"k": "turn", "tick": t, "cmds": _out})
	_out = []
	(_turns[local_pid] as Dictionary)[t] = true
	if t > 0 and t % HASH_EVERY == 0:
		var h: String = sim.state_hash()
		if send.is_valid():
			send.call({"k": "hash", "tick": t, "hash": h})
		_record_hash(local_pid, t, h)


## Paquete de otra PC. from_pid lo fija el transporte (no el paquete): nadie
## puede dar órdenes por otro jugador.
func receive(from_pid: int, pkt: Dictionary) -> void:
	if from_pid == local_pid or not humans.has(from_pid) or left.has(from_pid):
		return
	match str(pkt.get("k", "")):
		"turn":
			var t := int(pkt.get("tick", -1))
			var got: Dictionary = _turns[from_pid]
			if t < 0 or got.has(t):
				return # duplicado o basura
			for c in pkt.get("cmds", []):
				if c is Dictionary and c.get("payload") is Dictionary:
					sim.queue_command_at(t, from_pid, str(c.get("type", "")), c["payload"])
			got[t] = true
		"hash":
			_record_hash(from_pid, int(pkt.get("tick", -1)), str(pkt.get("hash", "")))


## ¿Se puede simular el próximo tick?
func can_step() -> bool:
	var need: int = int(sim.world.tick) + 1 - sim.INPUT_DELAY
	if need < 0:
		return true
	for p in humans:
		if left.has(p):
			continue
		if not (_turns[p] as Dictionary).has(need):
			return false
	return true


## Humanos cuyo turno falta para avanzar (para "Esperando a...").
func waiting_for() -> Array:
	var need: int = int(sim.world.tick) + 1 - sim.INPUT_DELAY
	var out: Array = []
	if need < 0:
		return out
	for p in humans:
		if not left.has(p) and not (_turns[p] as Dictionary).has(need):
			out.append(p)
	return out


## Avanza un tick si se puede (cerrando antes el turno actual).
func try_step() -> bool:
	end_turn()
	if not can_step():
		return false
	sim.step()
	_prune()
	return true


func player_left(pid: int) -> void:
	left[pid] = true


func _record_hash(pid: int, t: int, h: String) -> void:
	if t <= 0:
		return
	if not _hashes.has(t):
		_hashes[t] = {}
	_hashes[t][pid] = h
	var got: Dictionary = _hashes[t]
	var all := true
	for p in humans:
		if not left.has(p) and not got.has(p):
			all = false
	if not all:
		return
	var first := ""
	for p in got:
		if first == "":
			first = got[p]
		elif got[p] != first:
			if desync_tick < 0:
				desync_tick = t
				if on_desync.is_valid():
					on_desync.call(t, got.duplicate())
			break
	_hashes.erase(t)


func _prune() -> void:
	var limit: int = int(sim.world.tick) - KEEP_TICKS
	for p in _turns:
		var d: Dictionary = _turns[p]
		for t in d.keys():
			if int(t) < limit:
				d.erase(t)

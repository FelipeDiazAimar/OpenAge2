extends Node
# SimAPI - interfaz que todos los agentes deben respetar.
# Todo comando multijugador pasa por queue_command() -> lockstep 10Hz, 8 jugadores.
# Lockstep real: los comandos se fechan a tick+INPUT_DELAY, se agrupan por tick en
# tick_input_buffer y solo se ejecutan cuando todos los jugadores activos confirman.
# Determinismo: orden total (player_id, type, payload serializado), RNG en SimRNG,
# hash FNV-1a sobre estado serializado canónico. PROHIBIDO randf/Time/OS en lógica.

const TICK_RATE := 10
const TICK_INTERVAL := 0.1 # 1.0 / TICK_RATE, sin Time ni delta flotante en lógica
const MAX_PLAYERS := 8
const INPUT_DELAY := 2 # ticks de retardo entrada -> ejecución (compensa latencia LAN)
# Colores AoE2 oficiales
const PLAYER_COLORS := [
	Color("#2a4bff"), Color("#ff0000"), Color("#00ff00"), Color("#ffff00"),
	Color("#00c8ff"), Color("#c800ff"), Color("#969696"), Color("#ff8c00")
]

# FNV-1a 32-bit
const FNV_OFFSET_BASIS := 2166136261
const FNV_PRIME := 16777619
const FNV_MASK := 0xFFFFFFFF

var tick: int = 0
# Buffer lockstep: int tick -> Array[Dictionary] Command{tick, player_id, type, payload}
var tick_input_buffer: Dictionary = {}
# Confirmaciones: int tick -> Dictionary int player_id -> bool (true = input recibido,
# aunque sea vacío; permite avanzar el tick sin esperar a jugadores silenciosos)
var _confirmations: Dictionary = {}
# Cola legacy (compatibilidad). queue_command escribe en ambos; pop lee del buffer.
var _queue: Array = [] # Array[Dictionary] Command{tick, player_id, type, payload}
var SimRNGNode: Node

func _ready() -> void:
	SimRNGNode = load("res://core/SimRNG.gd").new()
	add_child(SimRNGNode)

# --- Ciclo de vida -----------------------------------------------------------

func reset() -> void:
	tick = 0
	tick_input_buffer.clear()
	_confirmations.clear()
	_queue.clear()

func _ensure_tick_slot(t: int) -> void:
	if not tick_input_buffer.has(t):
		tick_input_buffer[t] = []
	if not _confirmations.has(t):
		_confirmations[t] = {}

func _is_valid_player(player_id: int) -> bool:
	return player_id >= 0 and player_id < MAX_PLAYERS

# --- Entrada de comandos -----------------------------------------------------

func queue_command(player_id: int, type: String, payload: Dictionary = {}) -> void:
	if not _is_valid_player(player_id):
		push_error("SimAPI.queue_command: player_id fuera de rango: %d" % player_id)
		return
	if type.is_empty():
		push_error("SimAPI.queue_command: type vacío (player %d)" % player_id)
		return
	var target_tick: int = tick + INPUT_DELAY
	var cmd := {"tick": target_tick, "player_id": player_id, "type": type, "payload": payload}
	_ensure_tick_slot(target_tick)
	(tick_input_buffer[target_tick] as Array).append(cmd)
	(_confirmations[target_tick] as Dictionary)[player_id] = true
	_queue.append(cmd)
	EventBus.command_issued.emit(cmd)

## Llamado por NetManager al recibir el lote de un peer remoto para un tick.
## Registra los comandos y marca al jugador como confirmado.
func submit_remote_commands(t: int, player_id: int, cmds: Array) -> void:
	if not _is_valid_player(player_id):
		push_error("SimAPI.submit_remote_commands: player_id fuera de rango: %d" % player_id)
		return
	_ensure_tick_slot(t)
	for c in cmds:
		if c is Dictionary and int(c.get("tick", t)) == t and int(c.get("player_id", player_id)) == player_id:
			(tick_input_buffer[t] as Array).append(c)
	_confirmations[t][player_id] = true

## Confirma input vacío (jugador sin órdenes este tick). Imprescindible para
## que el lockstep no se bloquee esperando a jugadores silenciosos.
func confirm_player_input(t: int, player_id: int) -> void:
	if not _is_valid_player(player_id):
		push_error("SimAPI.confirm_player_input: player_id fuera de rango: %d" % player_id)
		return
	_ensure_tick_slot(t)
	(_confirmations[t] as Dictionary)[player_id] = true

func is_player_confirmed(t: int, player_id: int) -> bool:
	if not _confirmations.has(t):
		return false
	return bool((_confirmations[t] as Dictionary).get(player_id, false))

## true si todos los jugadores activos confirmaron el tick t.
## active_players: Array[int] con los slots en partida (ej. [0,1]).
## Si viene vacío, exige los MAX_PLAYERS (partida completa 8p).
func is_tick_confirmed(t: int, active_players: Array = []) -> bool:
	var expected: Array = active_players if not active_players.is_empty() else _all_slots()
	if not _confirmations.has(t):
		return false
	var conf: Dictionary = _confirmations[t]
	for pid in expected:
		if not bool(conf.get(int(pid), false)):
			return false
	return true

## Alias legible para NetManager/GameManager: ¿puedo ejecutar el tick t?
func can_execute_tick(t: int, active_players: Array = []) -> bool:
	return is_tick_confirmed(t, active_players)

func _all_slots() -> Array:
	var out: Array = []
	for i in MAX_PLAYERS:
		out.append(i)
	return out

# --- Consumo por tick --------------------------------------------------------

func pop_commands_for_tick(t: int) -> Array:
	# Drena primero el buffer nuevo; si está vacío, drena la cola legacy
	# (compatibilidad con partidas guardadas / tests antiguos).
	var out: Array = []
	if tick_input_buffer.has(t):
		out = (tick_input_buffer[t] as Array).duplicate()
		tick_input_buffer.erase(t)
	# Drenar cola legacy con mismo tick (por si algún agente antiguo la usó)
	if not _queue.is_empty():
		var rest: Array = []
		for c in _queue:
			if c is Dictionary and int((c as Dictionary).get("tick", -1)) == t:
				if not _contains_command(out, c):
					out.append(c)
			else:
				rest.append(c)
		_queue = rest
	# Orden determinista: player_id, type, payload serializado canónico
	out.sort_custom(_sort_commands)
	return out

func _contains_command(arr: Array, cmd: Dictionary) -> bool:
	for c in arr:
		if c is Dictionary and str(c.get("player_id")) == str(cmd.get("player_id")) and str(c.get("type")) == str(cmd.get("type")) and serialize_state(c.get("payload", {})) == serialize_state(cmd.get("payload", {})):
			return true
	return false

func _sort_commands(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("player_id", 0))
	var pb := int(b.get("player_id", 0))
	if pa != pb:
		return pa < pb
	var ta := str(a.get("type", ""))
	var tb := str(b.get("type", ""))
	if ta != tb:
		return ta < tb
	return serialize_state(a.get("payload", {})) < serialize_state(b.get("payload", {}))

## Lectura no destructiva (para NetManager: inspección / reenvío).
func peek_commands_for_tick(t: int) -> Array:
	if tick_input_buffer.has(t):
		var out: Array = (tick_input_buffer[t] as Array).duplicate()
		out.sort_custom(_sort_commands)
		return out
	return []

## Nº de comandos pendientes de ejecutar (ticks >= actual). Útil para HUD de
## lag, detección de stall y tests (NetManager lo usa para decidir esperar).
func get_pending_count() -> int:
	var n := 0
	for k in tick_input_buffer.keys():
		if int(k) >= tick:
			n += (tick_input_buffer[k] as Array).size()
	for c in _queue:
		if c is Dictionary and int((c as Dictionary).get("tick", -1)) >= tick:
			n += 1
	return n

func get_pending_count_for_tick(t: int) -> int:
	if tick_input_buffer.has(t):
		return (tick_input_buffer[t] as Array).size()
	return 0

## Nº de ticks con datos bufferados (no el nº de comandos).
func get_buffered_tick_count() -> int:
	return tick_input_buffer.size()

## Libera memoria de ticks ya ejecutados. Llamar tras tick_finished.
func discard_ticks_older_than(t: int) -> void:
	var drop_ticks: Array = []
	for k in tick_input_buffer.keys():
		if int(k) < t:
			drop_ticks.append(k)
	for k in drop_ticks:
		tick_input_buffer.erase(k)
	var drop_conf: Array = []
	for k in _confirmations.keys():
		if int(k) < t:
			drop_conf.append(k)
	for k in drop_conf:
		_confirmations.erase(k)

# --- Determinismo: serialización + hash --------------------------------------

## Serializa cualquier Variant a String canónica determinista:
## - Dictionary: claves ordenadas (por str), recursivo.
## - Array: orden conservado (el llamante debe ordenar si necesita).
## - float: formato fijo con 6 decimales (evita divergencia por to_string).
## - Vector2/Vector3/Vector2i/Vector3i/Color: componentes con formato fijo.
## - resto: str().
func serialize_state(state) -> String:
	return _serialize_sorted(state)

func _serialize_sorted(v) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys: Array = d.keys()
			keys.sort_custom(func(a, b): return str(a) < str(b))
			var parts: PackedStringArray = []
			for k in keys:
				parts.append(str(k) + ":" + _serialize_sorted(d[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for e in (v as Array):
				parts.append(_serialize_sorted(e))
			return "[" + ",".join(parts) + "]"
		TYPE_FLOAT:
			return "%0.6f" % float(v)
		TYPE_VECTOR2:
			var v2: Vector2 = v
			return "v2(%0.6f,%0.6f)" % [v2.x, v2.y]
		TYPE_VECTOR3:
			var v3: Vector3 = v
			return "v3(%0.6f,%0.6f,%0.6f)" % [v3.x, v3.y, v3.z]
		TYPE_VECTOR2I:
			var vi2: Vector2i = v
			return "v2i(%d,%d)" % [vi2.x, vi2.y]
		TYPE_VECTOR3I:
			var vi3: Vector3i = v
			return "v3i(%d,%d,%d)" % [vi3.x, vi3.y, vi3.z]
		TYPE_COLOR:
			var col: Color = v
			return "c(%0.6f,%0.6f,%0.6f,%0.6f)" % [col.r, col.g, col.b, col.a]
		TYPE_BOOL:
			return "true" if bool(v) else "false"
		TYPE_NIL:
			return "null"
		_:
			return str(v)

## Hash determinista FNV-1a 32-bit sobre los bytes UTF-8 del String.
## Estable entre ejecuciones y plataformas (String.hash() de Godot NO lo es).
func fnv1a_hash(s: String) -> int:
	var h: int = FNV_OFFSET_BASIS
	for b in s.to_utf8_buffer():
		h = ((h ^ int(b)) * FNV_PRIME) & FNV_MASK
	return h

## Hash del estado serializado. Acepta String (canónico o no) o cualquier
## Variant (se serializa primero). Lo usa NetManager._check_desync cada 30 ticks.
func sim_hash(state) -> int:
	if state is String:
		return fnv1a_hash(state)
	return fnv1a_hash(serialize_state(state))

func get_player_color(pid: int) -> Color:
	return PLAYER_COLORS[pid % MAX_PLAYERS]

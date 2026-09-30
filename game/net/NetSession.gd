extends Node
## Sesión de red LAN (ENet). Un nodo con el mismo nombre en cada PC:
## anfitrión (peer 1) o cliente. El anfitrión es la autoridad de la sala:
## valida pedidos, arma la lista de jugadores y arranca la partida.
##
## Sala: slots = [{peer (0 = IA), name, civ, team, ai, ready, hash_ok}].
## Partida: reenvía los paquetes del lockstep (engine/net/Lockstep) y avisa
## desconexiones. El pid de quien envía lo pone esta sesión a partir del
## peer ENet (nadie puede hacerse pasar por otro jugador).

signal lobby_changed
signal started(cfg: Dictionary)
signal packet(from_pid: int, pkt: Dictionary)
signal peer_left(pid: int)
signal failed(reason: String)

const PORT := 7778
const DISCOVERY_PORT := 7777
const MAX_PLAYERS := 8
const ANNOUNCE := "OpenAge-LAN"

var is_host := false
var my_name := "Jugador"
var content_hash := ""
var slots: Array = []
## Durante la partida: peer -> pid y el pid de esta PC.
var pid_of_peer: Dictionary = {}
var local_pid := -1
var in_game := false
## Partidas vistas en la LAN: ip -> {name, players, port, seen_ms}.
var found: Dictionary = {}

var _mp: SceneMultiplayer
var _peer: ENetMultiplayerPeer
var _udp: PacketPeerUDP
var _announce_t := 0.0


## mp: SceneMultiplayer propio (pruebas con dos sesiones en un proceso);
## null = el del árbol.
func setup(p_hash: String, p_name: String, mp: SceneMultiplayer = null) -> void:
	content_hash = p_hash
	my_name = p_name
	_mp = mp
	var api := _api()
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	api.connected_to_server.connect(_on_connected)
	api.connection_failed.connect(func(): failed.emit("no se pudo conectar"))
	api.server_disconnected.connect(func(): failed.emit("el anfitrión cerró la partida"))


func _api() -> MultiplayerAPI:
	return _mp if _mp != null else multiplayer


func my_peer() -> int:
	return _api().get_unique_id()


## Crea la partida. Devuelve "" o el motivo del error.
func host(port: int = PORT) -> String:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return "no se pudo abrir el puerto %d (¿otra partida abierta?)" % port
	_api().multiplayer_peer = _peer
	is_host = true
	slots = [{"peer": 1, "name": my_name, "civ": "britones", "team": 0, "ai": false, "ready": true, "hash_ok": true}]
	lobby_changed.emit()
	return ""


func join(ip: String, port: int = PORT) -> String:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port)
	if err != OK:
		return "dirección inválida"
	_api().multiplayer_peer = _peer
	is_host = false
	return ""


func leave() -> void:
	if _peer != null:
		_peer.close()
	_api().multiplayer_peer = null
	_peer = null
	slots = []
	in_game = false
	stop_discovery()


## Llamar cada frame (o a mano en pruebas): red y descubrimiento.
func poll(delta: float = 0.0) -> void:
	if _mp != null:
		_mp.poll()
	_poll_discovery(delta)


func _process(delta: float) -> void:
	if _mp == null:
		_poll_discovery(delta)


# --- sala --------------------------------------------------------------------

func _on_connected() -> void:
	_request.rpc_id(1, {"op": "hello", "name": my_name, "hash": content_hash})


func _on_peer_connected(_id: int) -> void:
	pass # el cliente se presenta con "hello"


func _on_peer_disconnected(id: int) -> void:
	if in_game:
		if pid_of_peer.has(id):
			peer_left.emit(int(pid_of_peer[id]))
		return
	if is_host:
		slots = slots.filter(func(s): return int(s["peer"]) != id)
		_broadcast_lobby()


## Pedidos de los clientes (solo el anfitrión los atiende).
@rpc("any_peer", "call_remote", "reliable")
func _request(req: Dictionary) -> void:
	if not is_host or in_game:
		return
	var from := _api().get_remote_sender_id()
	var s := _slot_of_peer(from)
	match str(req.get("op", "")):
		"hello":
			if s.is_empty() and slots.size() < MAX_PLAYERS:
				slots.append({"peer": from, "name": str(req.get("name", "?")).left(24), "civ": "francos",
					"team": slots.size(), "ai": false, "ready": false,
					"hash_ok": str(req.get("hash", "")) == content_hash})
		"set":
			if not s.is_empty():
				_apply_set(s, req)
	_broadcast_lobby()


## Cambios del anfitrión sobre cualquier hueco (IA incluida) o del jugador
## sobre el suyo.
func _apply_set(s: Dictionary, req: Dictionary) -> void:
	if req.has("civ"):
		s["civ"] = str(req["civ"]).left(40)
	if req.has("team"):
		s["team"] = clampi(int(req["team"]), 0, MAX_PLAYERS - 1)
	if req.has("ready"):
		s["ready"] = bool(req["ready"])


func _slot_of_peer(peer: int) -> Dictionary:
	for s in slots:
		if int(s["peer"]) == peer:
			return s
	return {}


## Cambiar lo propio (civ, equipo, listo).
func set_mine(req: Dictionary) -> void:
	if is_host:
		_apply_set(_slot_of_peer(1), req)
		_broadcast_lobby()
	else:
		req["op"] = "set"
		_request.rpc_id(1, req)


## Anfitrión: agregar/quitar IA o cambiar un hueco.
func host_add_ai(civ: String) -> void:
	if is_host and slots.size() < MAX_PLAYERS:
		slots.append({"peer": 0, "name": "IA", "civ": civ, "team": slots.size(), "ai": true, "ready": true, "hash_ok": true})
		_broadcast_lobby()


func host_remove_slot(i: int) -> void:
	if is_host and i > 0 and i < slots.size():
		if int(slots[i]["peer"]) > 1 and _peer != null:
			_peer.disconnect_peer(int(slots[i]["peer"]))
		slots.remove_at(i)
		_broadcast_lobby()


func host_set_slot(i: int, req: Dictionary) -> void:
	if is_host and i >= 0 and i < slots.size():
		_apply_set(slots[i], req)
		_broadcast_lobby()


func _broadcast_lobby() -> void:
	lobby_changed.emit()
	if is_host and _peer != null:
		_lobby_state.rpc(slots)


@rpc("authority", "call_remote", "reliable")
func _lobby_state(p_slots: Array) -> void:
	slots = p_slots
	lobby_changed.emit()


## "" si se puede empezar; si no, el motivo.
func start_error() -> String:
	if not is_host:
		return "solo el anfitrión empieza"
	if slots.size() < 2:
		return "hacen falta al menos 2 jugadores"
	for s in slots:
		if not bool(s["hash_ok"]):
			return "%s tiene otros datos del juego (mods distintos)" % s["name"]
		if not bool(s["ready"]):
			return "%s no está listo" % s["name"]
	return ""


## Anfitrión: arranca la partida en todas las PC.
func start(map_seed: int, pop_max: int, lake: bool) -> String:
	var err := start_error()
	if err != "":
		return err
	var cfg := {"slots": [], "map_seed": map_seed, "pop_max": pop_max, "lake": lake, "peers": {}}
	for i in slots.size():
		var s: Dictionary = slots[i]
		cfg["slots"].append({"civ": s["civ"], "team": int(s["team"]), "ai": bool(s["ai"]), "name": s["name"]})
		if int(s["peer"]) > 0:
			cfg["peers"][str(s["peer"])] = i
	_start.rpc(cfg)
	_start(cfg)
	return ""


@rpc("authority", "call_remote", "reliable")
func _start(cfg: Dictionary) -> void:
	pid_of_peer = {}
	for k in cfg["peers"]:
		pid_of_peer[int(k)] = int(cfg["peers"][k])
	local_pid = int(pid_of_peer.get(my_peer(), -1))
	in_game = true
	stop_discovery()
	started.emit(cfg)


## Humanos de la partida (pids).
func human_pids() -> Array:
	var out: Array = pid_of_peer.values()
	out.sort()
	return out


# --- partida -----------------------------------------------------------------

## Paquete del lockstep hacia todas las demás PC.
func send(pkt: Dictionary) -> void:
	if _peer != null:
		_net_packet.rpc(pkt)


@rpc("any_peer", "call_remote", "reliable")
func _net_packet(pkt: Dictionary) -> void:
	var from := _api().get_remote_sender_id()
	if pid_of_peer.has(from):
		packet.emit(int(pid_of_peer[from]), pkt)


# --- descubrimiento LAN -------------------------------------------------------

## Anfitrión: anuncia la partida; cliente: escucha anuncios.
func start_discovery() -> void:
	stop_discovery()
	_udp = PacketPeerUDP.new()
	if is_host:
		_udp.set_broadcast_enabled(true)
		_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	else:
		_udp.bind(DISCOVERY_PORT)


func stop_discovery() -> void:
	if _udp != null:
		_udp.close()
	_udp = null


func _poll_discovery(delta: float) -> void:
	if _udp == null:
		return
	if is_host:
		_announce_t -= delta
		if _announce_t <= 0.0:
			_announce_t = 1.0
			_udp.put_packet(("%s|%s|%d/%d|%d" % [ANNOUNCE, my_name, slots.size(), MAX_PLAYERS, PORT]).to_utf8_buffer())
		return
	while _udp.get_available_packet_count() > 0:
		var txt := _udp.get_packet().get_string_from_utf8()
		var ip := _udp.get_packet_ip()
		var parts := txt.split("|")
		if parts.size() >= 4 and parts[0] == ANNOUNCE:
			found[ip] = {"name": parts[1], "players": parts[2], "port": int(parts[3]) if parts.size() > 3 else PORT,
				"seen_ms": Time.get_ticks_msec()}

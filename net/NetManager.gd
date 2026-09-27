extends Node
# NetManager - LAN 8p gratis con ENet. Sin internet, sin servidores.
# Host: 7778 TCP/UDP (ENet). Discovery: 7777 UDP broadcast.
# Godot 4.4 ENet: ENetMultiplayerPeer + RPCs @rpc.
#
# Autoridad:
# - Lobby slots: SOLO el host escribe y reemite (clientes piden via _net_hello/_net_set_slot).
# - Countdown: SOLO el host descuenta en _process y reemite; clientes solo muestran.
# - start_game: SOLO el host; llama GameManager.setup_lobby(cfgs hasta 8) en todos via _net_start.
# - Chat y ping: any_peer, con validacion de longitud/remitente.

const DISCOVERY_PORT := 7777
const GAME_PORT := 7778
const MAX_PLAYERS := 8
const COUNTDOWN_DEFAULT := 3.0
const PING_INTERVAL := 2.0
const CHAT_MAX_LEN := 120
const NAME_MAX_LEN := 16
const CIVS: Array[String] = ["britones", "francos", "godos", "bizantinos"]
const SLOT_COLORS: Array[String] = [
	"#2a4bff", "#ff0000", "#00ff00", "#ffff00",
	"#00c8ff", "#c800ff", "#969696", "#ff8c00",
]

signal lobby_updated(slots: Array)
signal chat_received(peer_id: int, who: String, text: String)
signal countdown_ticked(seconds_left: float)
signal game_started(cfgs: Array)
signal peer_left(peer_id: int)
signal host_migrated(new_host_id: int)
signal ping_updated(peer_id: int, ms: int)

var peer: ENetMultiplayerPeer
var is_host := false
var my_id := 0
var map_name := "arabia"
var lobby_slots: Array = [] # 8x {name,civ,team,ready,color,occupied,peer_id}

var countdown_total := COUNTDOWN_DEFAULT
var countdown_left := -1.0 # <0 = inactivo
var latencies := {} # peer_id -> ms
var game_seed := 1234

var _tick := 0
var _tick_timer := 0.0
var _udp: PacketPeerUDP
var _broadcasting := false
var _broadcast_msg := ""
var _b_time := 0.0
var _last_hashes := {}
var _ping_sent := {} # peer_id -> msec envio
var _ping_timer := 0.0

func _ready() -> void:
	_init_lobby_slots()
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)

# ------------------------------------------------------------------
# Host / Join / Leave
# ------------------------------------------------------------------

func host_game(p_map_name: String = "arabia") -> String:
	leave_lobby()
	map_name = p_map_name.strip_edges().to_lower()
	if map_name.is_empty():
		map_name = "arabia"
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_PLAYERS - 1)
	if err != OK:
		return "Error host: %s" % err
	multiplayer.multiplayer_peer = peer
	is_host = true
	my_id = 1
	_init_lobby_slots()
	lobby_slots[0]["occupied"] = true
	lobby_slots[0]["peer_id"] = 1
	lobby_slots[0]["name"] = "Anfitrion"
	lobby_slots[0]["ready"] = true # el host siempre listo (no se bloquea a si mismo)
	cancel_countdown()
	game_seed = randi() & 0x7FFFFFFF
	_start_broadcast("OpenAge-LAN|%s|1/%d" % [map_name, MAX_PLAYERS])
	_broadcast_lobby()
	return "Host OK en %s:%d" % [get_local_ip(), GAME_PORT]

func join_game(ip: String) -> String:
	leave_lobby()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), GAME_PORT)
	if err != OK:
		return "Error join: %s" % err
	multiplayer.multiplayer_peer = peer
	is_host = false
	my_id = 0 # se resuelve en _on_connected_to_server
	_init_lobby_slots()
	cancel_countdown()
	return "Conectando a %s..." % ip

func leave_lobby() -> void:
	cancel_countdown()
	_stop_broadcast()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	peer = null
	is_host = false
	my_id = 0
	latencies.clear()
	_ping_sent.clear()
	_init_lobby_slots()

func get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return "127.0.0.1"

func _start_broadcast(msg: String) -> void:
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_broadcasting = true
	_broadcast_msg = msg

func _stop_broadcast() -> void:
	_broadcasting = false
	if _udp:
		_udp.close()
	_udp = null

func discover_servers(_timeout_sec: float = 3.0) -> Array:
	# Obsoleto: el listado asyncrono lo lleva net/LanDiscovery.gd.
	# Se conserva por compatibilidad con tests/UI antigua.
	push_warning("NetManager.discover_servers esta obsoleto; usa LanDiscovery.start_listen().")
	return []

# ------------------------------------------------------------------
# Slots: modelo autoritativo (host)
# ------------------------------------------------------------------

func _init_lobby_slots() -> void:
	lobby_slots.clear()
	for i in MAX_PLAYERS:
		lobby_slots.append({
			"name": "Anfitrion" if i == 0 else "— Abierto —",
			"civ": CIVS[i % CIVS.size()],
			"team": 0 if i % 2 == 0 else 1, # 1v1 por defecto: equipos 0/1
			"ready": false,
			"color": SLOT_COLORS[i],
			"occupied": false,
			"peer_id": 0,
		})
	lobby_updated.emit(lobby_slots.duplicate(true))

func _first_free_slot() -> int:
	for i in lobby_slots.size():
		if not bool(lobby_slots[i]["occupied"]):
			return i
	return -1

func my_slot_index() -> int:
	for i in lobby_slots.size():
		if int(lobby_slots[i].get("peer_id", 0)) == my_id and my_id != 0:
			return i
	return -1

func get_slot_by_peer(pid: int) -> int:
	for i in lobby_slots.size():
		if int(lobby_slots[i].get("peer_id", 0)) == pid:
			return i
	return -1

func all_ready() -> bool:
	var n := 0
	for s in lobby_slots:
		if bool((s as Dictionary).get("occupied", false)):
			n += 1
			if not bool((s as Dictionary).get("ready", false)):
				return false
	return n >= 1

func occupied_count() -> int:
	var n := 0
	for s in lobby_slots:
		if bool((s as Dictionary).get("occupied", false)):
			n += 1
	return n

# Cliente: pide slot al host (o el host se auto-asigna). Llamar tras conectar.
func claim_my_slot(player_name: String = "") -> void:
	var pname := player_name.strip_edges().left(NAME_MAX_LEN)
	if pname.is_empty():
		pname = "Anfitrion" if is_host else ("Invitado %d" % my_id)
	if is_host:
		var idx := _first_free_slot()
		# El host siempre ocupa el slot 0 si esta libre.
		if not bool(lobby_slots[0]["occupied"]):
			idx = 0
		if idx < 0:
			return
		lobby_slots[idx]["occupied"] = true
		lobby_slots[idx]["peer_id"] = my_id
		lobby_slots[idx]["name"] = pname
		_broadcast_lobby()
	else:
		if not multiplayer.has_multiplayer_peer():
			return
		rpc_id(1, "_net_hello", pname, str(_my_civ_default()), int(_my_team_default()))

func _my_civ_default() -> String:
	var idx := my_slot_index()
	if idx >= 0:
		return str(lobby_slots[idx].get("civ", CIVS[0]))
	return CIVS[0]

func _my_team_default() -> int:
	var idx := my_slot_index()
	if idx >= 0:
		return int(lobby_slots[idx].get("team", 0))
	return 0

# UI local: cambia un campo propio (civ/team/ready/name). Valida y propaga.
func set_my_slot_field(field: String, value: Variant) -> void:
	var idx := my_slot_index()
	if idx < 0:
		# Sin slot aun (cliente recien conectado): pedir uno primero.
		if not is_host:
			claim_my_slot()
		return
	set_slot_field(idx, field, value)

func set_slot_field(idx: int, field: String, value: Variant) -> void:
	if idx < 0 or idx >= lobby_slots.size():
		return
	if field not in ["name", "civ", "team", "ready"]:
		return
	value = _sanitize_field(field, idx, value)
	if is_host:
		lobby_slots[idx][field] = value
		_cancel_countdown_if_not_ready()
		_broadcast_lobby()
	else:
		rpc_id(1, "_net_set_slot", idx, field, value)

func _sanitize_field(field: String, idx: int, value: Variant) -> Variant:
	match field:
		"name":
			var t := str(value).strip_edges().left(NAME_MAX_LEN)
			return t if not t.is_empty() else str(lobby_slots[idx].get("name", "Jugador"))
		"civ":
			var c := str(value).strip_edges().to_lower()
			return c if c in CIVS else str(lobby_slots[idx].get("civ", CIVS[0]))
		"team":
			return clampi(int(value), 0, 3)
		"ready":
			return bool(value)
	return value

func _broadcast_lobby() -> void:
	lobby_updated.emit(lobby_slots.duplicate(true))
	if is_host and multiplayer.has_multiplayer_peer():
		rpc("_net_sync_lobby", lobby_slots.duplicate(true), map_name)

# ------------------------------------------------------------------
# Countdown host-autoritativo + start_game
# ------------------------------------------------------------------

func start_countdown(seconds: float = COUNTDOWN_DEFAULT) -> bool:
	if not is_host:
		return false
	if not all_ready():
		return false
	countdown_total = maxf(1.0, seconds)
	countdown_left = countdown_total
	rpc("_net_countdown", countdown_left)
	countdown_ticked.emit(countdown_left)
	return true

func cancel_countdown() -> void:
	if countdown_left >= 0.0:
		countdown_left = -1.0
		if is_host and multiplayer.has_multiplayer_peer():
			rpc("_net_countdown", -1.0)
		countdown_ticked.emit(-1.0)

func _cancel_countdown_if_not_ready() -> void:
	if countdown_left >= 0.0 and not all_ready():
		cancel_countdown()

func is_countdown_active() -> bool:
	return countdown_left >= 0.0

# Host: construye cfgs de los slots ocupados (max 8, orden de slot = orden
# determinista de pid) y los ejecuta en TODOS via _net_start.
func start_game(seed: int = -1) -> bool:
	if not is_host:
		return false
	if not all_ready():
		return false
	var cfgs := build_match_cfgs()
	if cfgs.is_empty():
		return false
	var use_seed := seed if seed >= 0 else int(game_seed)
	_apply_start(cfgs, use_seed)
	rpc("_net_start", cfgs, use_seed)
	return true

func build_match_cfgs() -> Array:
	var cfgs: Array = []
	for i in lobby_slots.size():
		var s: Dictionary = lobby_slots[i]
		if bool(s.get("occupied", false)):
			cfgs.append({
				"civ": str(s.get("civ", CIVS[0])),
				"team": int(s.get("team", 0)),
				"color": str(s.get("color", SLOT_COLORS[i])),
				"name": str(s.get("name", "Jugador")),
			})
	return cfgs

func _apply_start(cfgs: Array, seed: int) -> void:
	cancel_countdown()
	_stop_broadcast()
	game_seed = seed
	GameManager.map_seed = seed
	# GameManager.setup_lobby acepta 1..8; cfgs ya viene filtrado a ocupados (<=8).
	GameManager.setup_match(_to_gm_slots(cfgs), seed)
	game_started.emit(cfgs.duplicate(true))

func _to_gm_slots(cfgs: Array) -> Array:
	# GameManager solo entiende {civ, team}; el resto (color/name) es HUD.
	var out: Array = []
	for c in cfgs:
		if c is Dictionary:
			out.append({"civ": str((c as Dictionary).get("civ", "britones")),
				"team": int((c as Dictionary).get("team", 0))})
	return out

# ------------------------------------------------------------------
# Chat RPC
# ------------------------------------------------------------------

func send_chat(text: String) -> void:
	var t := text.strip_edges().left(CHAT_MAX_LEN)
	if t.is_empty():
		return
	var who := _my_display_name()
	if is_host or not multiplayer.has_multiplayer_peer():
		_receive_chat(my_id, who, t)
		if multiplayer.has_multiplayer_peer():
			rpc("_net_chat", who.left(NAME_MAX_LEN), t)
	else:
		rpc("_net_chat", who.left(NAME_MAX_LEN), t)

func _my_display_name() -> String:
	var idx := my_slot_index()
	if idx >= 0:
		return str(lobby_slots[idx].get("name", "Jugador"))
	return "Anfitrion" if is_host else ("Invitado %d" % my_id)

func _receive_chat(from_id: int, who: String, text: String) -> void:
	chat_received.emit(from_id, who.left(NAME_MAX_LEN), text.left(CHAT_MAX_LEN))
	if EventBus.has_signal("chat_msg"):
		EventBus.emit_signal("chat_msg", from_id, text.left(CHAT_MAX_LEN))

# ------------------------------------------------------------------
# Ping / latencia (ms)
# ------------------------------------------------------------------

func ping_all() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var now := Time.get_ticks_msec()
	for pid in multiplayer.get_peers():
		_ping_sent[int(pid)] = now
		rpc_id(int(pid), "_net_ping", now)

func get_latency(pid: int) -> int:
	return int(latencies.get(pid, -1))

# ------------------------------------------------------------------
# Conexiones ENet / migracion de host
# ------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_host:
		# Asigna primer slot libre al recien llegado; el nombre real llega con _net_hello.
		var idx := _first_free_slot()
		if idx >= 0:
			lobby_slots[idx]["occupied"] = true
			lobby_slots[idx]["peer_id"] = id
			lobby_slots[idx]["name"] = "Invitado %d" % id
			lobby_slots[idx]["ready"] = false
		_broadcast_lobby()
		_start_broadcast("OpenAge-LAN|%s|%d/%d" % [map_name, occupied_count(), MAX_PLAYERS])

func _on_peer_disconnected(id: int) -> void:
	_free_slot_of_peer(id)
	latencies.erase(id)
	_ping_sent.erase(id)
	peer_left.emit(id)
	if is_host:
		# Si se fue alguien en plena cuenta atras, se cancela (ya no hay all_ready).
		_cancel_countdown_if_not_ready()
		_broadcast_lobby()
	else:
		if id == 1:
			# Se cayo el host: eleccion determinista -> menor peer_id vivo es nuevo host.
			_try_host_migration()

func _free_slot_of_peer(pid: int) -> void:
	var changed := false
	for i in lobby_slots.size():
		if int(lobby_slots[i].get("peer_id", 0)) == pid:
			lobby_slots[i] = {"name": "— Abierto —", "civ": CIVS[i % CIVS.size()],
				"team": 0 if i % 2 == 0 else 1, "ready": false,
				"color": SLOT_COLORS[i], "occupied": false, "peer_id": 0}
			changed = true
	if changed:
		lobby_updated.emit(lobby_slots.duplicate(true))

func _try_host_migration() -> void:
	# ENet es cliente/servidor: al morir el servidor los clientes quedan
	# desconectados. Migracion best-effort para el lobby: el peer vivo con
	# menor id se autoproclama host y re-abre servidor; el resto debe re-join.
	var candidates: Array = []
	if my_id != 0:
		candidates.append(my_id)
	for s in lobby_slots:
		var pid := int((s as Dictionary).get("peer_id", 0))
		if pid > 1:
			candidates.append(pid)
	for pid in multiplayer.get_peers():
		if int(pid) > 1 and not candidates.has(int(pid)):
			candidates.append(int(pid))
	if candidates.is_empty():
		return
	candidates.sort()
	var new_host := int(candidates[0])
	host_migrated.emit(new_host)
	if new_host == my_id:
		_become_migrated_host()

func _become_migrated_host() -> void:
	# Solo el elegido ejecuta esto: re-abre servidor y conserva slots ocupados.
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_PLAYERS - 1)
	if err != OK:
		push_error("NetManager migracion: no se pudo reabrir servidor: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	my_id = 1
	# Reasigna mi slot al id 1 y limpia el slot del host caido.
	for i in lobby_slots.size():
		if int(lobby_slots[i].get("peer_id", 0)) == 1:
			lobby_slots[i] = {"name": "— Abierto —", "civ": CIVS[i % CIVS.size()],
				"team": 0 if i % 2 == 0 else 1, "ready": false,
				"color": SLOT_COLORS[i], "occupied": false, "peer_id": 0}
	var idx := my_slot_index()
	if idx < 0:
		idx = _first_free_slot()
	if idx >= 0:
		lobby_slots[idx]["occupied"] = true
		lobby_slots[idx]["peer_id"] = 1
		lobby_slots[idx]["ready"] = true
	cancel_countdown()
	_start_broadcast("OpenAge-LAN|%s|%d/%d" % [map_name, occupied_count(), MAX_PLAYERS])
	_broadcast_lobby()

func _on_connected_to_server() -> void:
	my_id = multiplayer.get_unique_id()
	is_host = false
	claim_my_slot()

func _on_connection_failed() -> void:
	is_host = false
	my_id = 0

func _on_server_disconnected() -> void:
	# El servidor (host) cerro: intentamos eleccion de nuevo host.
	_try_host_migration()

# ------------------------------------------------------------------
# RPCs de red
# ------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _net_hello(pname: String, civ: String, team: int) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var idx := get_slot_by_peer(sender)
	if idx < 0:
		idx = _first_free_slot()
		if idx < 0:
			return
		lobby_slots[idx]["occupied"] = true
		lobby_slots[idx]["peer_id"] = sender
	lobby_slots[idx]["name"] = pname.strip_edges().left(NAME_MAX_LEN) if not pname.strip_edges().is_empty() else ("Invitado %d" % sender)
	lobby_slots[idx]["civ"] = civ.strip_edges().to_lower() if civ.strip_edges().to_lower() in CIVS else str(lobby_slots[idx]["civ"])
	lobby_slots[idx]["team"] = clampi(team, 0, 3)
	lobby_slots[idx]["ready"] = false
	_broadcast_lobby()

@rpc("any_peer", "reliable")
func _net_set_slot(idx: int, field: String, value: Variant) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if idx < 0 or idx >= lobby_slots.size():
		return
	# Solo el dueño del slot (o el host) puede editarlo.
	if int(lobby_slots[idx].get("peer_id", 0)) != sender and sender != 1:
		return
	if not (field in ["name", "civ", "team", "ready"]):
		return
	lobby_slots[idx][field] = _sanitize_field(field, idx, value)
	_cancel_countdown_if_not_ready()
	_broadcast_lobby()

@rpc("authority", "reliable")
func _net_sync_lobby(remote: Array, remote_map: String) -> void:
	if remote.size() != MAX_PLAYERS:
		return
	lobby_slots = remote.duplicate(true)
	# Repara color canonico por indice (el color es fijo AoE2, no elegible).
	for i in lobby_slots.size():
		(lobby_slots[i] as Dictionary)["color"] = SLOT_COLORS[i]
	if not remote_map.is_empty():
		map_name = remote_map
	lobby_updated.emit(lobby_slots.duplicate(true))

@rpc("authority", "reliable")
func _net_countdown(v: float) -> void:
	countdown_left = v
	countdown_ticked.emit(v)

@rpc("authority", "reliable")
func _net_start(cfgs: Array, seed: int) -> void:
	_apply_start(cfgs.duplicate(true), seed)

@rpc("any_peer", "reliable")
func _net_chat(who: String, text: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var clean := text.strip_edges().left(CHAT_MAX_LEN)
	if clean.is_empty():
		return
	_receive_chat(sender, who.strip_edges().left(NAME_MAX_LEN), clean)
	# El host reemite para que lo vean todos los demas clientes (malla via servidor).
	if is_host:
		for pid in multiplayer.get_peers():
			if int(pid) != sender:
				rpc_id(int(pid), "_net_chat", who.strip_edges().left(NAME_MAX_LEN), clean)

@rpc("any_peer", "reliable")
func _net_ping(t_ms: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	rpc_id(sender, "_net_pong", t_ms)

@rpc("any_peer", "reliable")
func _net_pong(t_ms: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec()
	var ms := int(now) - int(t_ms)
	if ms < 0:
		ms = 0
	latencies[sender] = ms
	ping_updated.emit(sender, ms)

# ------------------------------------------------------------------
# _process: broadcast discovery + countdown host + ping + lockstep 10 Hz
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _broadcasting and _udp:
		_b_time += delta
		if _b_time >= 1.0:
			_b_time = 0.0
			_udp.put_packet(_broadcast_msg.to_utf8_buffer())
			if is_host:
				_broadcast_msg = "OpenAge-LAN|%s|%d/%d" % [map_name, occupied_count(), MAX_PLAYERS]
	# Countdown host-autoritativo: solo el host descuenta y reemite por segundo.
	if is_host and countdown_left >= 0.0:
		var before := ceili(countdown_left)
		countdown_left -= delta
		if ceili(countdown_left) != before:
			rpc("_net_countdown", maxf(0.0, countdown_left))
			countdown_ticked.emit(maxf(0.0, countdown_left))
		if countdown_left <= 0.0:
			countdown_left = -1.0
			start_game()
	# Ping periodico de latencia.
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_ping_timer += delta
		if _ping_timer >= PING_INTERVAL:
			_ping_timer = 0.0
			ping_all()
	# Lockstep 10 Hz solo con peer activo.
	if multiplayer.multiplayer_peer and (is_host or multiplayer.get_peers().size() > 0 or not is_host):
		_tick_timer += delta
		if _tick_timer >= 1.0 / float(SimAPI.TICK_RATE):
			_tick_timer = 0.0
			_tick += 1
			if is_host:
				_check_desync(_tick)
			GameManager._on_tick(_tick)

func _check_desync(t: int) -> void:
	if t % 30 != 0:
		return
	# Hash canonico del estado real (no solo nº de jugadores).
	var h := SimAPI.sim_hash(GameManager.sim_hash_state())
	_last_hashes[t] = h
	rpc("_remote_hash", t, h)

@rpc("any_peer", "unreliable")
func _remote_hash(t: int, h: int) -> void:
	if _last_hashes.has(t) and int(_last_hashes[t]) != h:
		EventBus.desync_detected.emit(t, int(_last_hashes[t]), h)

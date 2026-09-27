extends Node
# LanDiscovery - escucha/busca partidas en red local. 100% UDP, gratis.
# UI lo usa para listar: "Arabia de Juan - 3/8 - 192.168.1.50"

const PORT := 7777
var _sock: PacketPeerUDP
var servers := {} # ip -> {name, map, players, last_seen}

signal servers_updated(list: Array)

func start_listen() -> void:
	_sock = PacketPeerUDP.new()
	_sock.bind(PORT)
	set_process(true)

func stop() -> void:
	set_process(false)
	if _sock: _sock.close()

func _process(_d: float) -> void:
	if not _sock: return
	while _sock.get_available_packet_count() > 0:
		var pkt := _sock.get_packet()
		var ip := _sock.get_packet_ip()
		var txt := pkt.get_string_from_utf8()
		# Formato: OpenAge-LAN|mapa|1/8
		if txt.begins_with("OpenAge-LAN|"):
			var parts := txt.split("|")
			servers[ip] = {"ip": ip, "map": parts[1] if parts.size() > 1 else "?", "info": parts[2] if parts.size() > 2 else "", "last_seen": Time.get_ticks_msec()}
			servers_updated.emit(get_list())

func get_list() -> Array:
	return servers.values()

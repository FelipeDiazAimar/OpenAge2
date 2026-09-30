extends Node
## Sesión de red falsa para probar Match en red sin sockets.

signal packet(from_pid: int, pkt: Dictionary)
signal peer_left(pid: int)
signal failed(reason: String)

var local_pid := 0
var humans: Array = [0, 1]
var sent: Array = []
var gone: Array = []


func human_pids() -> Array:
	return humans


func send(pkt: Dictionary) -> void:
	sent.append(pkt)


func flush_pending() -> void:
	pass


func leave() -> void:
	pass

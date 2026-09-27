extends Node
# DesyncDetector - anti-desync lockstep 10 Hz, LAN 8p.
# Cada 30 ticks: pide estado canonico a GameManager + Economy + Combat +
# Construction + Production, calcula hash FNV-1a (SimAPI.sim_hash) y lo
# compara entre peers via RPC. Si difiere: emite EventBus.desync_detected,
# guarda dump user://desync_tick_N.json, pausa la partida y muestra mensaje.
#
# Uso: instanciar una vez en la escena de partida (o autoload) y asignar las
# 5 referencias (en editor o por codigo). GameManager se resuelve solo al
# autoload si no se asigna. Tambien se auto-engancha a EventBus.tick_finished,
# asi NetManager/GameManager no necesitan cambios: el check corre solo.
# NOTA determinismo: NADA de randf/Time/OS aqui; solo tick + strings + FNV-1a.

const CHECK_INTERVAL := 30

# Sistemas simulados. GameManager = autoload por defecto; el resto se asigna
# desde la escena de partida (son nodos de systems/, no autoloads).
@export var game_manager: Node
@export var economy: Node
@export var combat: Node
@export var construction: Node
@export var production: Node

var _local_hashes: Dictionary = {} # int tick -> int hash local
var _remote_hashes: Dictionary = {} # int tick -> Dictionary int peer_id -> int hash
var _reported_ticks: Dictionary = {} # int tick -> bool (evita dump/pausa repetidos)
var _banner: CanvasLayer # overlay ALWAYS con el mensaje de desync

func _ready() -> void:
	if game_manager == null and has_node("/root/GameManager"):
		game_manager = get_node("/root/GameManager")
	if typeof(EventBus) != TYPE_NIL and EventBus != null:
		if not EventBus.tick_finished.is_connected(_on_tick_finished):
			EventBus.tick_finished.connect(_on_tick_finished)
		if not EventBus.desync_detected.is_connected(_on_desync_signal):
			EventBus.desync_detected.connect(_on_desync_signal)

func _on_tick_finished(t: int) -> void:
	check_tick(t)

## Punto de entrada manual (NetManager puede llamarlo tras GameManager._on_tick).
## Solo actua en ticks multiplos de CHECK_INTERVAL.
func check_tick(t: int) -> void:
	if t <= 0 or t % CHECK_INTERVAL != 0:
		return
	if _reported_ticks.get(t, false):
		return
	var local_h := compute_local_hash()
	_local_hashes[t] = local_h
	# Comparar con hashes remotos que hayan llegado antes que el local.
	if _remote_hashes.has(t):
		for peer_id in (_remote_hashes[t] as Dictionary).keys():
			var rh := int((_remote_hashes[t] as Dictionary)[peer_id])
			if rh != local_h:
				_handle_desync(t, local_h, rh, int(peer_id))
				return
	# Difundir a todos los peers (no-op sin multijugador: rpc sin peer falla
	# silencioso -> proteger para tests/headless y menu local).
	if multiplayer.has_multiplayer_peer():
		rpc("_remote_desync_hash", t, local_h)

## Hash FNV-1a combinado del estado canonico de los 5 sistemas.
func compute_local_hash() -> int:
	var joined := collect_state_string()
	if typeof(SimAPI) != TYPE_NIL and SimAPI != null and SimAPI.has_method("sim_hash"):
		return int(SimAPI.sim_hash(joined))
	return _fnv1a_fallback(joined)

## Concatena el estado canonico de cada sistema en orden fijo (determinista).
## GameManager expone sim_hash_state() -> int; el resto sim_state_string().
func collect_state_string() -> String:
	var parts: PackedStringArray = []
	parts.append("game:" + _game_state_string())
	parts.append("eco:" + _node_state_string(economy))
	parts.append("combat:" + _node_state_string(combat))
	parts.append("const:" + _node_state_string(construction))
	parts.append("prod:" + _node_state_string(production))
	return "|".join(parts)

func _game_state_string() -> String:
	if game_manager != null and is_instance_valid(game_manager):
		if game_manager.has_method("sim_state_string"):
			return str(game_manager.call("sim_state_string"))
		if game_manager.has_method("sim_hash_state"):
			return "h%d" % int(game_manager.call("sim_hash_state"))
	return "h0"

func _node_state_string(n: Node) -> String:
	if n != null and is_instance_valid(n):
		if n.has_method("sim_state_string"):
			return str(n.call("sim_state_string"))
		if n.has_method("sim_hash_state"):
			return "h%d" % int(n.call("sim_hash_state"))
		if n.has_method("sim_hash"):
			return "h%d" % int(n.call("sim_hash"))
	return "-"

@rpc("any_peer", "unreliable")
func _remote_desync_hash(t: int, h: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _reported_ticks.get(t, false):
		return
	if _local_hashes.has(t):
		if int(_local_hashes[t]) != h:
			_handle_desync(t, int(_local_hashes[t]), h, sender)
	else:
		# Llego antes que el hash local: se guarda y se compara en check_tick().
		if not _remote_hashes.has(t):
			_remote_hashes[t] = {}
		(_remote_hashes[t] as Dictionary)[sender] = h

## Llega tambien via senal local (p. ej. el _check_desync legacy de NetManager).
func _on_desync_signal(t: int, hash_local: int, hash_remote: int) -> void:
	if _reported_ticks.get(t, false):
		return
	_handle_desync(t, hash_local, hash_remote, -1)

func _handle_desync(t: int, hash_local: int, hash_remote: int, remote_peer: int) -> void:
	_reported_ticks[t] = true
	_save_dump(t, hash_local, hash_remote, remote_peer)
	if typeof(EventBus) != TYPE_NIL and EventBus != null:
		EventBus.desync_detected.emit(t, hash_local, hash_remote)
		EventBus.chat_msg.emit(0, "DESYNC en tick %d (local %d vs remoto %d). Partida pausada." % [t, hash_local, hash_remote])
	push_error("DesyncDetector: DESYNC tick %d local=%d remoto=%d peer=%d. Dump en user://desync_tick_%d.json" % [t, hash_local, hash_remote, remote_peer, t])
	_pause_and_notify(t, hash_local, hash_remote)

func _save_dump(t: int, hash_local: int, hash_remote: int, remote_peer: int) -> void:
	var data := {
		"tick": t,
		"sim_tick": int(SimAPI.tick) if (typeof(SimAPI) != TYPE_NIL and SimAPI != null) else -1,
		"hash_local": hash_local,
		"hash_remote": hash_remote,
		"remote_peer": remote_peer,
		"remote_hashes": (_remote_hashes.get(t, {}) as Dictionary).duplicate(true),
		"state": {
			"game": _game_state_string(),
			"economy": _node_state_string(economy),
			"combat": _node_state_string(combat),
			"construction": _node_state_string(construction),
			"production": _node_state_string(production),
		},
	}
	var path := "user://desync_tick_%d.json" % t
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("DesyncDetector: no se pudo abrir " + path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("DesyncDetector: dump guardado en " + path)

func _pause_and_notify(t: int, hash_local: int, hash_remote: int) -> void:
	if is_inside_tree():
		get_tree().paused = true
	show_message("⚠ DESYNC tick %d\nlocal %d ≠ remoto %d\nPartida pausada. Revisa user://desync_tick_%d.json" % [t, hash_local, hash_remote, t])

## Overlay ALWAYS (visible con get_tree().paused = true) + print. Idempotente.
func show_message(text: String) -> void:
	print(text)
	if not is_inside_tree():
		return
	if _banner == null or not is_instance_valid(_banner):
		_banner = CanvasLayer.new()
		_banner.layer = 200
		_banner.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_banner)
		var panel := PanelContainer.new()
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.custom_minimum_size = Vector2(420, 0)
		_banner.add_child(panel)
		var vb := VBoxContainer.new()
		vb.name = "VB"
		vb.add_theme_constant_override("separation", 8)
		panel.add_child(vb)
		var label := Label.new()
		label.name = "Msg"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", Color("#ff5555"))
		label.add_theme_font_size_override("font_size", 18)
		vb.add_child(label)
		var btn := Button.new()
		btn.text = "Cerrar (la partida sigue pausada)"
		btn.pressed.connect(func() -> void: _banner.visible = false)
		vb.add_child(btn)
	_banner.visible = true
	var msg: Label = _banner.get_node("VB/Msg") as Label
	if msg != null:
		msg.text = text

## Limpia hashes/dumps reportados. Llamar al empezar nueva partida.
func reset() -> void:
	_local_hashes.clear()
	_remote_hashes.clear()
	_reported_ticks.clear()
	if _banner != null and is_instance_valid(_banner):
		_banner.visible = false
	if is_inside_tree() and get_tree().paused:
		get_tree().paused = false

## FNV-1a 32-bit local (solo fallback si SimAPI no esta disponible, p. ej. tests).
func _fnv1a_fallback(s: String) -> int:
	var h: int = 2166136261
	for b in s.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	return h

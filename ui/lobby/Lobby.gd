extends Control
# Lobby LAN 8 slots estilo AoE2. Programatico (sin .tscn) como MainMenu.gd.
# Integra: NetManager (is_host, MAX_PLAYERS=8) + GameManager.setup_lobby().
# Fila por slot: color fijo | nombre | dropdown civ (5) | dropdown equipo | boton Listo.
# Chat + boton Iniciar (solo host) + countdown 3s cancelable.

const CIVS: Array[String] = ["britones", "francos", "godos", "bizantinos", "vikingos"]
# Mismo orden que GameManager._color_hex_for(): azul, rojo, verde, amarillo,
# celeste, morado, gris, naranja (colores fijos AoE2, no elegibles).
const SLOT_COLORS: Array[String] = ["#2a4bff", "#ff0000", "#00ff00", "#ffff00", "#00c8ff", "#c800ff", "#969696", "#ff8c00"]
const TEAMS: Array[String] = ["1", "2", "3", "4"]

var slots: Array = [] # 8x {name, civ_idx, team_idx, ready, occupied, peer_id}
var my_slot := 0
var countdown := -1.0
var _count_label: Label
var _start_btn: Button
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _rows: Array = []

func _ready() -> void:
	_init_slots()
	_resolve_my_slot()
	_build_ui()
	_refresh_all()
	if multiplayer.peer_connected.is_connected(_on_peer_connected) == false:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _init_slots() -> void:
	slots.clear()
	for i in NetManager.MAX_PLAYERS:
		slots.append({
			"name": ("Jugador %d" % (i + 1)) if i == 0 else ("— Abierto —" if i > 1 else "Jugador 2"),
			"civ_idx": i % CIVS.size(),
			"team_idx": 0 if i % 2 == 0 else 1, # 1v1 por defecto: equipos 1 y 2
			"ready": false,
			"occupied": i < 2, # slots 0-1 ocupados por defecto (host + 1), resto abiertos
			"peer_id": 1 if i == 0 else 0,
		})

func _resolve_my_slot() -> void:
	if NetManager.is_host:
		my_slot = 0
		slots[0]["peer_id"] = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		slots[0]["occupied"] = true
	else:
		# Cliente: ocupa el primer slot libre y lo anuncia al host.
		my_slot = _first_free_slot()
		if my_slot >= 0:
			slots[my_slot]["occupied"] = true
			slots[my_slot]["peer_id"] = multiplayer.get_unique_id()
			slots[my_slot]["name"] = "Invitado %d" % multiplayer.get_unique_id()
			rpc_id(1, "_rpc_claim_slot", my_slot, str(slots[my_slot]["name"]))

func _first_free_slot() -> int:
	for i in slots.size():
		if not bool(slots[i]["occupied"]):
			return i
	return -1

# ---------------------------------------------------------------- UI --

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Sala multijugador LAN (hasta 8) — " + ("HOST" if NetManager.is_host else "CLIENTE")
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	for i in slots.size():
		_rows.append(_build_row(grid, i))

	_count_label = Label.new()
	_count_label.text = ""
	_count_label.add_theme_font_size_override("font_size", 20)
	vb.add_child(_count_label)

	_chat_log = RichTextLabel.new()
	_chat_log.custom_minimum_size = Vector2(640, 140)
	_chat_log.scroll_following = true
	_chat_log.bbcode_enabled = true
	vb.add_child(_chat_log)

	var chat_row := HBoxContainer.new()
	vb.add_child(chat_row)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Chat (Enter para enviar)..."
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.max_length = 120
	_chat_input.text_submitted.connect(_on_chat_submitted)
	chat_row.add_child(_chat_input)
	var send := Button.new()
	send.text = "Enviar"
	send.pressed.connect(func() -> void: _on_chat_submitted(_chat_input.text))
	chat_row.add_child(send)

	var bot := HBoxContainer.new()
	vb.add_child(bot)
	_start_btn = Button.new()
	_start_btn.text = "▶ Iniciar partida"
	_start_btn.custom_minimum_size = Vector2(220, 44)
	# Solo el host puede iniciar (requisito).
	_start_btn.visible = NetManager.is_host
	_start_btn.pressed.connect(_on_start_pressed)
	bot.add_child(_start_btn)
	var back := Button.new()
	back.text = "← Salir"
	back.pressed.connect(_on_exit)
	bot.add_child(back)
	if not NetManager.is_host:
		var wait := Label.new()
		wait.text = "Esperando al host... marca Listo."
		bot.add_child(wait)

func _build_row(grid: GridContainer, i: int) -> Dictionary:
	var dot := ColorRect.new()
	dot.color = Color(SLOT_COLORS[i])
	dot.custom_minimum_size = Vector2(28, 28)
	grid.add_child(dot)

	var name_edit := LineEdit.new()
	name_edit.custom_minimum_size = Vector2(200, 32)
	name_edit.max_length = 16
	name_edit.text = str(slots[i]["name"])
	name_edit.editable = (i == my_slot)
	name_edit.text_changed.connect(func(t: String) -> void: _on_my_field(i, "name", t))
	grid.add_child(name_edit)

	var civ := OptionButton.new()
	for c in CIVS:
		civ.add_item(c.capitalize())
	civ.selected = int(slots[i]["civ_idx"])
	civ.disabled = (i != my_slot)
	civ.custom_minimum_size = Vector2(140, 32)
	civ.item_selected.connect(func(idx: int) -> void: _on_my_field(i, "civ_idx", idx))
	grid.add_child(civ)

	var team := OptionButton.new()
	for t in TEAMS:
		team.add_item("Equipo " + t)
	team.selected = int(slots[i]["team_idx"])
	team.disabled = (i != my_slot)
	team.item_selected.connect(func(idx: int) -> void: _on_my_field(i, "team_idx", idx))
	grid.add_child(team)

	var ready := Button.new()
	ready.text = "Listo"
	ready.toggle_mode = true
	ready.custom_minimum_size = Vector2(110, 32)
	ready.disabled = (i != my_slot)
	ready.toggled.connect(func(on: bool) -> void: _on_my_field(i, "ready", on))
	grid.add_child(ready)
	return {"name": name_edit, "civ": civ, "team": team, "ready": ready}

# ------------------------------------------------------------ Logica --

func _on_my_field(i: int, field: String, value: Variant) -> void:
	if i != my_slot:
		return
	slots[i][field] = value
	if NetManager.is_host:
		rpc("_rpc_sync_slots", slots)
	else:
		rpc_id(1, "_rpc_push_slot", i, str(field), value)
	_refresh_row(i)
	_cancel_countdown_if_needed()

func _on_chat_submitted(text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty():
		return
	_chat_input.clear()
	var who := str(slots[my_slot]["name"])
	_append_chat(who, t)
	rpc("_rpc_chat", who, t)
	EventBus.chat_msg.emit(multiplayer.get_unique_id(), t)

func _append_chat(who: String, text: String) -> void:
	_chat_log.append_text("[b]%s:[/b] %s\n" % [who.xml_escape(), text.xml_escape()])

func _on_start_pressed() -> void:
	if not NetManager.is_host:
		return
	if not _all_occupied_ready():
		_append_chat("Sistema", "No se puede iniciar: todos los ocupados deben estar Listos.")
		return
	# Host inicia countdown 3s (cancelable si alguien quita Listo).
	countdown = 3.0
	rpc("_rpc_countdown", 3.0)

func _all_occupied_ready() -> bool:
	var n := 0
	for s in slots:
		if bool(s["occupied"]):
			n += 1
			if not bool(s["ready"]):
				return false
	return n >= 1

func _cancel_countdown_if_needed() -> void:
	if countdown >= 0.0 and not _all_occupied_ready():
		countdown = -1.0
		_count_label.text = "Inicio cancelado (falta Listo)."
		if NetManager.is_host:
			rpc("_rpc_countdown", -1.0)

func _process(delta: float) -> void:
	if countdown >= 0.0:
		countdown -= delta
		var left := maxi(0, ceili(countdown))
		_count_label.text = "Iniciando en %d..." % left if countdown > 0.0 else ""
		if countdown <= 0.0:
			countdown = -1.0
			_launch_game()

func _launch_game() -> void:
	var cfgs: Array = []
	for s in slots:
		if bool(s["occupied"]):
			cfgs.append({"civ": CIVS[int(s["civ_idx"])], "team": int(s["team_idx"])})
	GameManager.setup_lobby(cfgs)
	print("Lobby: partida lanzada con %d jugadores." % cfgs.size())
	# TODO: get_tree().change_scene_to_file("res://ui/hud/Game.tscn")

func _on_exit() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	NetManager.is_host = false
	get_tree().change_scene_to_file("res://ui/menus/MainMenu.tscn")

func _on_peer_connected(id: int) -> void:
	if NetManager.is_host:
		rpc("_rpc_sync_slots", slots)

func _on_peer_disconnected(id: int) -> void:
	for i in slots.size():
		if int(slots[i].get("peer_id", 0)) == id:
			slots[i] = {"name": "— Abierto —", "civ_idx": i % CIVS.size(),
				"team_idx": 0, "ready": false, "occupied": false, "peer_id": 0}
	if NetManager.is_host:
		rpc("_rpc_sync_slots", slots)
	_refresh_all()

# --------------------------------------------------------------- RPC --

@rpc("any_peer", "reliable")
func _rpc_claim_slot(i: int, pname: String) -> void:
	if not NetManager.is_host or not multiplayer.has_multiplayer_peer():
		return
	var sender := multiplayer.get_remote_sender_id()
	if i < 0 or i >= slots.size() or bool(slots[i]["occupied"]):
		i = _first_free_slot()
		if i < 0:
			return
	slots[i]["occupied"] = true
	slots[i]["peer_id"] = sender
	slots[i]["name"] = pname.left(16) if not pname.is_empty() else ("Invitado %d" % sender)
	rpc("_rpc_sync_slots", slots)
	_refresh_all()

@rpc("any_peer", "reliable")
func _rpc_push_slot(i: int, field: String, value: Variant) -> void:
	if not NetManager.is_host:
		return
	if i < 0 or i >= slots.size():
		return
	slots[i][field] = value
	rpc("_rpc_sync_slots", slots)
	_refresh_all()

@rpc("authority", "reliable")
func _rpc_sync_slots(remote: Array) -> void:
	if remote.size() == slots.size():
		slots = remote.duplicate(true)
		_refresh_all()

@rpc("any_peer", "reliable")
func _rpc_chat(who: String, text: String) -> void:
	_append_chat(who.left(16), text.left(120))
	EventBus.chat_msg.emit(multiplayer.get_remote_sender_id(), text.left(120))

@rpc("authority", "reliable")
func _rpc_countdown(v: float) -> void:
	countdown = v
	if v < 0.0:
		_count_label.text = "Inicio cancelado por el host."

# ------------------------------------------------------------ Refresh --

func _refresh_row(i: int) -> void:
	var r: Dictionary = _rows[i]
	(r["name"] as LineEdit).text = str(slots[i]["name"])
	(r["civ"] as OptionButton).selected = int(slots[i]["civ_idx"])
	(r["team"] as OptionButton).selected = int(slots[i]["team_idx"])
	(r["ready"] as Button).button_pressed = bool(slots[i]["ready"])
	var dim := not bool(slots[i]["occupied"])
	(r["name"] as LineEdit).modulate = Color(1, 1, 1, 0.5 if dim else 1.0)

func _refresh_all() -> void:
	for i in slots.size():
		_refresh_row(i)
	if _start_btn:
		_start_btn.disabled = not _all_occupied_ready()

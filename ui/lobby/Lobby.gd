extends Control
# Lobby LAN 8 slots estilo AoE2. Diseno visual renovado, logica de red intacta.
# Conserva: slots locales 8, reclamado de slot, sincronia por RPC del propio
# script (_rpc_claim_slot / _rpc_push_slot / _rpc_sync_slots), chat por RPC
# (_rpc_chat), countdown 3s cancelable (_rpc_countdown) y arranque con
# GameManager.setup_lobby(). Solo cambia la presentacion (fondo, paneles,
# panel de mapa y lista LAN condicional). No toca net/ ni otros archivos.
# Godot 4.4, tabs, comentarios en espanol.

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
# Solo visual (no cambian la red): panel de mapa y lista LAN condicional.
var _map_name_label: Label
var _map_info_label: Label
var _discovery_list: ItemList
var _discovery_status: Label
var _lan_node: Node = null # LanDiscovery si existe como autoload /root/LanDiscovery

func _ready() -> void:
	_init_slots()
	_resolve_my_slot()
	_build_ui()
	_refresh_all()
	_try_init_discovery()
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
# Rediseño AoE2: fondo marron oscuro, titulos dorados, paneles con borde.
# Izquierda: 8 filas de jugador. Derecha: mapa, partidas LAN, chat,
# countdown visible y botones (Iniciar solo host). Sin cambios de red.

func _build_ui() -> void:
	# Fondo estilo AoE (marron oscuro, sin assets).
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.08, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	margin.add_child(main)

	var title := Label.new()
	title.text = "Sala multijugador LAN (hasta 8) — " + ("HOST" if NetManager.is_host else "CLIENTE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	main.add_child(title)

	var sub := Label.new()
	sub.text = "Colores fijos AoE2 · tu fila es editable · el host inicia cuando todos estan Listos"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.70, 0.64, 0.54))
	main.add_child(sub)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(content)

	_build_players_panel(content)
	_build_side_column(content)

func _make_panel() -> PanelContainer:
	# Panel pergamino oscuro con borde dorado (recursos del editor, sin assets).
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.13, 0.10)
	sb.border_color = Color(0.65, 0.52, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_top = 10
	sb.content_margin_right = 12
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	return p

func _section_title(text: String) -> Label:
	# Cabecera dorada de cada panel.
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	return l

func _build_players_panel(content: HBoxContainer) -> void:
	# Panel izquierdo: cabecera + rejilla de 5 columnas con las 8 filas.
	var panel := _make_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.6
	content.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	vb.add_child(_section_title("Jugadores — 8 slots (color fijo, no elegible)"))
	var head := GridContainer.new()
	head.columns = 5
	head.add_theme_constant_override("h_separation", 8)
	vb.add_child(head)
	for h in ["Color", "Nombre", "Civilización", "Equipo", "¿Listo?"]:
		var hl := Label.new()
		hl.text = h
		hl.add_theme_color_override("font_color", Color(0.70, 0.64, 0.54))
		head.add_child(hl)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(grid)
	for i in slots.size():
		_rows.append(_build_row(grid, i))

func _build_side_column(content: HBoxContainer) -> void:
	# Columna derecha: mapa, partidas LAN, chat, countdown y botones.
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(400, 0)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 1.0
	side.add_theme_constant_override("separation", 10)
	content.add_child(side)
	_build_map_panel(side)
	_build_discovery_panel(side)
	_build_chat_panel(side)
	_build_bottom_bar(side)

func _build_map_panel(side: VBoxContainer) -> void:
	# Panel de mapa: solo lectura de NetManager.map_name (no crea red nueva).
	var panel := _make_panel()
	side.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(_section_title("Mapa"))
	_map_name_label = Label.new()
	_map_name_label.add_theme_font_size_override("font_size", 18)
	_map_name_label.add_theme_color_override("font_color", Color(0.90, 0.85, 0.70))
	vb.add_child(_map_name_label)
	_map_info_label = Label.new()
	_map_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_info_label.add_theme_color_override("font_color", Color(0.70, 0.64, 0.54))
	_map_info_label.text = "Arabia clásica: mapa abierto para 8. El mapa lo fija el host al crear (host_game); aquí solo se muestra."
	vb.add_child(_map_info_label)

func _build_discovery_panel(side: VBoxContainer) -> void:
	# Lista de partidas LAN descubiertas, solo si el proyecto la soporta:
	# autoload /root/LanDiscovery con señal servers_updated y get_list().
	# Si no existe, se muestra aviso y no se rompe nada (NetManager.discover_servers
	# está obsoleto y devuelve vacío, por eso no se llama para evitar warnings).
	var panel := _make_panel()
	side.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(_section_title("Partidas LAN descubiertas"))
	_discovery_list = ItemList.new()
	_discovery_list.custom_minimum_size = Vector2(360, 90)
	_discovery_list.tooltip_text = "Anuncios UDP 7777 con formato OpenAge-LAN|mapa|n/8"
	vb.add_child(_discovery_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var refresh := Button.new()
	refresh.text = "Actualizar"
	refresh.tooltip_text = "Relee la lista de LanDiscovery si está disponible"
	refresh.pressed.connect(_on_discovery_refresh)
	row.add_child(refresh)
	_discovery_status = Label.new()
	_discovery_status.add_theme_color_override("font_color", Color(0.70, 0.64, 0.54))
	_discovery_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_discovery_status)

func _build_chat_panel(side: VBoxContainer) -> void:
	# Chat con historial (misma logica de red, solo cambia el marco).
	var panel := _make_panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	vb.add_child(_section_title("Chat (historial)"))
	_chat_log = RichTextLabel.new()
	_chat_log.custom_minimum_size = Vector2(360, 140)
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.scroll_following = true
	_chat_log.bbcode_enabled = true
	vb.add_child(_chat_log)
	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 8)
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

func _build_bottom_bar(side: VBoxContainer) -> void:
	# Countdown visible + Iniciar (solo host) + Salir. Sin cambios de red.
	_count_label = Label.new()
	_count_label.text = ""
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", 22)
	_count_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.50))
	side.add_child(_count_label)
	var bot := HBoxContainer.new()
	bot.alignment = BoxContainer.ALIGNMENT_CENTER
	bot.add_theme_constant_override("separation", 10)
	side.add_child(bot)
	_start_btn = Button.new()
	_start_btn.text = "▶ Iniciar partida"
	_start_btn.custom_minimum_size = Vector2(220, 48)
	_start_btn.tooltip_text = "Solo el host. Requiere que todos los ocupados estén Listos."
	# Solo el host puede iniciar (requisito).
	_start_btn.visible = NetManager.is_host
	_start_btn.pressed.connect(_on_start_pressed)
	bot.add_child(_start_btn)
	var back := Button.new()
	back.text = "← Salir"
	back.custom_minimum_size = Vector2(120, 40)
	back.tooltip_text = "Cierra el peer y vuelve al menú principal"
	back.pressed.connect(_on_exit)
	bot.add_child(back)
	if not NetManager.is_host:
		var wait := Label.new()
		wait.text = "Esperando al host... marca Listo."
		wait.add_theme_color_override("font_color", Color(0.70, 0.64, 0.54))
		side.add_child(wait)

func _build_row(grid: GridContainer, i: int) -> Dictionary:
	# Una fila: color fijo | nombre editable propio | civ (5) | equipo | Listo.
	# Misma firma y conexiones que antes; solo tooltips y tamaños AoE2.
	var dot := ColorRect.new()
	dot.color = Color(SLOT_COLORS[i])
	dot.custom_minimum_size = Vector2(28, 28)
	dot.tooltip_text = "Jugador %d — color fijo AoE2 (no elegible)" % (i + 1)
	grid.add_child(dot)

	var name_edit := LineEdit.new()
	name_edit.custom_minimum_size = Vector2(180, 32)
	name_edit.max_length = 16
	name_edit.text = str(slots[i]["name"])
	name_edit.editable = (i == my_slot)
	name_edit.tooltip_text = "Tu nombre (solo tu fila es editable)"
	name_edit.text_changed.connect(func(t: String) -> void: _on_my_field(i, "name", t))
	grid.add_child(name_edit)

	var civ := OptionButton.new()
	for c in CIVS:
		civ.add_item(c.capitalize())
	civ.selected = int(slots[i]["civ_idx"])
	civ.disabled = (i != my_slot)
	civ.custom_minimum_size = Vector2(140, 32)
	civ.tooltip_text = "Civilización (5 disponibles)"
	civ.item_selected.connect(func(idx: int) -> void: _on_my_field(i, "civ_idx", idx))
	grid.add_child(civ)

	var team := OptionButton.new()
	for t in TEAMS:
		team.add_item("Equipo " + t)
	team.selected = int(slots[i]["team_idx"])
	team.disabled = (i != my_slot)
	team.custom_minimum_size = Vector2(130, 32)
	team.tooltip_text = "Equipo diplomático (1-4)"
	team.item_selected.connect(func(idx: int) -> void: _on_my_field(i, "team_idx", idx))
	grid.add_child(team)

	var ready := Button.new()
	ready.text = "Listo"
	ready.toggle_mode = true
	ready.custom_minimum_size = Vector2(100, 32)
	ready.disabled = (i != my_slot)
	ready.tooltip_text = "Marca que estás preparado"
	ready.toggled.connect(func(on: bool) -> void: _on_my_field(i, "ready", on))
	grid.add_child(ready)
	return {"name": name_edit, "civ": civ, "team": team, "ready": ready}

# ------------------------------------------------- Descubrimiento LAN --
# Todo opcional y defensivo: si no hay autoload LanDiscovery, solo avisa.

func _try_init_discovery() -> void:
	# Busca /root/LanDiscovery sin romper si no es autoload (caso actual).
	_lan_node = get_node_or_null("/root/LanDiscovery")
	if _lan_node != null and _lan_node.has_signal("servers_updated"):
		_lan_node.connect("servers_updated", _refresh_discovery_list)
		if _lan_node.has_method("start_listen") and not NetManager.is_host:
			_lan_node.call("start_listen")
		if _lan_node.has_method("get_list"):
			_refresh_discovery_list(_lan_node.call("get_list"))
		else:
			_discovery_status.text = "Escuchando anuncios LAN..."
	else:
		_lan_node = null
		_discovery_status.text = "Descubrimiento LAN no disponible (LanDiscovery no es autoload)."
		_refresh_discovery_list([])

func _refresh_discovery_list(list: Array) -> void:
	# Rellena el ItemList con "ip — mapa — n/8". Solo visual.
	if _discovery_list == null:
		return
	_discovery_list.clear()
	for s in list:
		if s is Dictionary:
			var d: Dictionary = s
			_discovery_list.add_item("%s — %s — %s" % [str(d.get("ip", "?")), str(d.get("map", "?")), str(d.get("info", ""))])
	if _lan_node != null:
		_discovery_status.text = "%d partida(s) vista(s). Únete desde Multijugador → Buscar LAN." % list.size()
	else:
		if _discovery_status.text.is_empty():
			_discovery_status.text = "Sin soporte de descubrimiento en este proyecto."

func _on_discovery_refresh() -> void:
	# Relee la lista si hay soporte; si no, mantiene el aviso.
	if _lan_node != null and _lan_node.has_method("get_list"):
		_refresh_discovery_list(_lan_node.call("get_list"))
	else:
		_discovery_status.text = "Descubrimiento LAN no disponible (LanDiscovery no es autoload)."

# ------------------------------------------------------------ Logica --
# A partir de aquí, lógica de red intacta del lobby original.

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
# RPCs propios del lobby original, sin cambios de protocolo.

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
	# Sincroniza una fila con slots[i]; el texto del botón es solo visual.
	var r: Dictionary = _rows[i]
	(r["name"] as LineEdit).text = str(slots[i]["name"])
	(r["civ"] as OptionButton).selected = int(slots[i]["civ_idx"])
	(r["team"] as OptionButton).selected = int(slots[i]["team_idx"])
	(r["ready"] as Button).button_pressed = bool(slots[i]["ready"])
	(r["ready"] as Button).text = "¡Listo!" if bool(slots[i]["ready"]) else "Listo"
	var dim := not bool(slots[i]["occupied"])
	(r["name"] as LineEdit).modulate = Color(1, 1, 1, 0.5 if dim else 1.0)

func _refresh_all() -> void:
	for i in slots.size():
		_refresh_row(i)
	if _start_btn:
		_start_btn.disabled = not _all_occupied_ready()
	# Solo visual: nombre del mapa (NetManager) y conteo de ocupados.
	if _map_name_label:
		_map_name_label.text = "Mapa: %s  ·  %d/8 jugadores" % [str(NetManager.map_name).capitalize(), _occupied_count()]
	if _map_info_label and not NetManager.is_host:
		_map_info_label.text = "El mapa lo fija el host (%s). Tu fila es la única editable." % str(NetManager.map_name).capitalize()

func _occupied_count() -> int:
	# Conteo local para el panel (no sustituye a NetManager.occupied_count()).
	var n := 0
	for s in slots:
		if bool((s as Dictionary).get("occupied", false)):
			n += 1
	return n

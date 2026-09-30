extends Control
## Sala de partida LAN: crear o unirse (por IP o de la lista de la red),
## elegir civilización y equipo, "Listo" y, el anfitrión, IA y "Empezar".
## Al empezar, todas las PC abren Match con la misma configuración y la
## sesión de red (MatchConfig.net) para el lockstep.

const MatchConfig := preload("res://game/MatchConfig.gd")
const Registry := preload("res://engine/data/Registry.gd")
const NetSession := preload("res://game/net/NetSession.gd")
const MenuStyle := preload("res://ui/menus/MenuStyle.gd")

const MATCH := "res://game/scenes/Match.tscn"
const SETUP := "res://game/scenes/Setup.tscn"
const POP_OPTIONS := [[0, "Sin límite"], [200, "200 (AoE2)"], [500, "500"]]
const COLORS: Array[Color] = [Color("#2a4bff"), Color("#ff2020"), Color("#20c020"), Color("#ffe020"),
	Color("#00c8ff"), Color("#c800ff"), Color("#969696"), Color("#ff8c00")]

var net
var civs: Array = [] # [[id, nombre]]
var _hash := ""
var _name: LineEdit
var _ip: LineEdit
var _found: ItemList
var _status: Label
var _connect_box: VBoxContainer
var _room: VBoxContainer
var _rows: VBoxContainer
var _host_opts: GridContainer
var _seed: SpinBox
var _pop: OptionButton
var _lake: CheckBox
var _start: Button
var _ready_box: CheckBox
var _add_ai: Button
var _refresh_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var r := Registry.new()
	r.load_mods("res://mods")
	_hash = r.content_hash
	for id in r.ids_of_type("civ"):
		civs.append([id, str(r.get_def(id).get("name", id))])
	civs.sort_custom(func(a, b): return str(a[1]) < str(b[1]))
	_build_ui()
	net = get_tree().root.get_node_or_null("NetSession")
	if net == null:
		net = NetSession.new()
		net.name = "NetSession"
		get_tree().root.add_child.call_deferred(net)
		await get_tree().process_frame
		if not is_inside_tree() or not net.is_inside_tree():
			return # la sala se cerró antes de terminar de abrir
		net.setup(_hash, _default_name())
	net.valid_civs = civs.map(func(c): return str(c[0]))
	net.lobby_changed.connect(_refresh_room)
	net.started.connect(_on_started)
	net.failed.connect(_on_failed)
	# Mientras no hay sala, se escuchan partidas de la LAN.
	net.start_discovery()


func _default_name() -> String:
	var n := OS.get_environment("USERNAME")
	return n if n != "" else "Jugador"


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", MenuStyle.panel_madera())
	center.add_child(frame)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	frame.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(760, 0)
	margin.add_child(vb)
	var title := MenuStyle.titulo_medieval("Partida en red (LAN)", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	# Conectar.
	_connect_box = VBoxContainer.new()
	vb.add_child(_connect_box)
	var row := HBoxContainer.new()
	row.add_child(_label("Tu nombre"))
	_name = LineEdit.new()
	_name.text = _default_name()
	_name.custom_minimum_size = Vector2(200, 0)
	row.add_child(_name)
	var host := MenuStyle.boton_medieval("Crear partida")
	host.pressed.connect(_on_host)
	row.add_child(host)
	_connect_box.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_child(_label("IP del anfitrión"))
	_ip = LineEdit.new()
	_ip.placeholder_text = "192.168.1.50"
	_ip.custom_minimum_size = Vector2(200, 0)
	row2.add_child(_ip)
	var join := MenuStyle.boton_medieval("Unirse")
	join.pressed.connect(func(): _on_join(_ip.text.strip_edges()))
	row2.add_child(join)
	_connect_box.add_child(row2)
	_connect_box.add_child(_label("Partidas encontradas en la red (doble clic para unirse):"))
	_found = ItemList.new()
	_found.custom_minimum_size = Vector2(0, 110)
	_found.item_activated.connect(func(i): _on_join(str(_found.get_item_metadata(i))))
	_connect_box.add_child(_found)
	# Sala.
	_room = VBoxContainer.new()
	_room.visible = false
	vb.add_child(_room)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	_room.add_child(_rows)
	var mine := HBoxContainer.new()
	_ready_box = CheckBox.new()
	_ready_box.text = "Estoy listo"
	_ready_box.toggled.connect(func(on): net.set_mine({"ready": on}))
	mine.add_child(_ready_box)
	_add_ai = Button.new()
	_add_ai.text = "+ IA"
	_add_ai.pressed.connect(func(): net.host_add_ai(civs[randi() % civs.size()][0]))
	mine.add_child(_add_ai)
	_room.add_child(mine)
	_host_opts = GridContainer.new()
	_host_opts.columns = 2
	_host_opts.add_child(_label("Semilla del mapa"))
	_seed = SpinBox.new()
	_seed.min_value = 1
	_seed.max_value = 999999
	_seed.value = randi_range(1, 999999)
	_host_opts.add_child(_seed)
	_host_opts.add_child(_label("Población máxima"))
	_pop = OptionButton.new()
	for o in POP_OPTIONS:
		_pop.add_item(str(o[1]))
	_host_opts.add_child(_pop)
	_host_opts.add_child(_label("Lago central"))
	_lake = CheckBox.new()
	_lake.button_pressed = true
	_host_opts.add_child(_lake)
	_room.add_child(_host_opts)
	# Pie.
	_status = _label("")
	vb.add_child(_status)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 24)
	var back := MenuStyle.boton_medieval("Volver")
	back.pressed.connect(_on_back)
	actions.add_child(back)
	_start = MenuStyle.boton_medieval("¡Empezar!")
	_start.pressed.connect(_on_start)
	_start.visible = false
	actions.add_child(_start)
	vb.add_child(actions)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	return l


func _set_status(t: String) -> void:
	_status.text = t


func _on_host() -> void:
	net.my_name = _name.text.strip_edges().left(24)
	net.stop_discovery()
	var err: String = net.host()
	if err != "":
		_set_status(err)
		net.start_discovery()
		return
	net.start_discovery() # ahora anuncia la partida
	_enter_room()
	_set_status("Partida creada. Tu IP: %s" % ", ".join(_local_ips()))


func _on_join(ip: String) -> void:
	if ip == "":
		_set_status("Escribe la IP del anfitrión o elige una partida de la lista")
		return
	net.my_name = _name.text.strip_edges().left(24)
	net.stop_discovery()
	var err: String = net.join(ip)
	if err != "":
		_set_status(err)
		return
	_enter_room()
	_set_status("Conectando con %s…" % ip)


func _enter_room() -> void:
	_connect_box.visible = false
	_room.visible = true
	_host_opts.visible = net.is_host
	_start.visible = net.is_host
	_add_ai.visible = net.is_host
	_ready_box.visible = not net.is_host
	_refresh_room()


func _local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			out.append(a)
	return out


func _refresh_room() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var me: int = net.my_peer() if net._peer != null else -1
	for i: int in net.slots.size():
		var s: Dictionary = net.slots[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var sw := ColorRect.new()
		sw.color = COLORS[i % COLORS.size()]
		sw.custom_minimum_size = Vector2(16, 16)
		row.add_child(sw)
		var who := _label("%s%s" % [s["name"], " (tú)" if int(s["peer"]) == me else ""])
		who.custom_minimum_size = Vector2(170, 0)
		row.add_child(who)
		var editable: bool = int(s["peer"]) == me or (net.is_host and bool(s["ai"]))
		var civ := OptionButton.new()
		civ.custom_minimum_size = Vector2(200, 0)
		for c in civs:
			civ.add_item(str(c[1]))
			civ.set_item_metadata(civ.item_count - 1, str(c[0]))
			if str(c[0]) == str(s["civ"]):
				civ.select(civ.item_count - 1)
		civ.disabled = not editable
		var idx: int = i
		civ.item_selected.connect(func(k): _set_slot(idx, {"civ": str(civ.get_item_metadata(k))}))
		row.add_child(civ)
		var team := OptionButton.new()
		for t in 8:
			team.add_item("Equipo %d" % (t + 1))
		team.select(int(s["team"]))
		team.disabled = not editable
		team.item_selected.connect(func(k): _set_slot(idx, {"team": k}))
		row.add_child(team)
		var state := "IA" if bool(s["ai"]) else ("listo" if bool(s["ready"]) else "no listo")
		if not bool(s["hash_ok"]):
			state = "¡datos distintos!"
		row.add_child(_label(state))
		if net.is_host and i > 0:
			var rm := Button.new()
			rm.text = "Quitar"
			rm.pressed.connect(func(): net.host_remove_slot(idx))
			row.add_child(rm)
		_rows.add_child(row)
	if net.is_host:
		var why: String = net.start_error()
		_start.disabled = why != ""
		_start.tooltip_text = why
		if why != "":
			_set_status(why)
		else:
			_set_status("Todo listo: ¡a jugar!")


func _set_slot(i: int, req: Dictionary) -> void:
	var me: int = net.my_peer()
	if int(net.slots[i]["peer"]) == me:
		net.set_mine(req)
	elif net.is_host:
		net.host_set_slot(i, req)


func _process(delta: float) -> void:
	_refresh_t -= delta
	if _refresh_t > 0.0 or net == null or _room.visible:
		return
	_refresh_t = 0.5
	_found.clear()
	var now := Time.get_ticks_msec()
	for ip in net.found:
		var g: Dictionary = net.found[ip]
		if now - int(g["seen_ms"]) > 4000:
			continue
		_found.add_item("%s — %s jugadores — %s" % [g["name"], g["players"], ip])
		_found.set_item_metadata(_found.item_count - 1, ip)


func _on_start() -> void:
	var err: String = net.start(int(_seed.value), int(POP_OPTIONS[maxi(0, _pop.selected)][0]), _lake.button_pressed)
	if err != "":
		_set_status(err)


func _on_started(cfg: Dictionary) -> void:
	MatchConfig.slots = cfg["slots"]
	MatchConfig.map_seed = int(cfg["map_seed"])
	MatchConfig.pop_max = int(cfg["pop_max"])
	MatchConfig.lake = bool(cfg["lake"])
	MatchConfig.net = net
	get_tree().change_scene_to_file(MATCH)


func _on_back() -> void:
	if net != null:
		net.leave()
		net.get_parent().remove_child(net) # libera el nombre /root/NetSession ya
		net.queue_free()
	get_tree().change_scene_to_file(SETUP)


## Conexión rechazada o anfitrión caído: volver a la pantalla de conectar.
func _on_failed(why: String) -> void:
	if net.in_game:
		return
	net.leave()
	_room.visible = false
	_start.visible = false
	_connect_box.visible = true
	net.start_discovery()
	_set_status(why)

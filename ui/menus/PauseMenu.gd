extends CanvasLayer
# Menú de pausa visual estilo AoE2 (Esc / F10).
# Panel centrado semitransparente con: Continuar, Guardar, Cargar, Opciones, Rendirse, Salir.
# Pausa el árbol con get_tree().paused; este CanvasLayer usa process_mode ALWAYS
# para seguir recibiendo input y dibujar el menú aunque el juego esté pausado.
# Atajos: Esc cierra el menú, F10 lo abre (o lo alterna si ya está abierto).
# La interfaz se construye por código; PauseMenu.tscn solo instancia este script.
# Guardado: serializa GameManager (players, map_seed, tick de SimAPI) a user://savegame.json.
# Godot 4.4: indentación con tabs.

const SAVE_PATH := "user://savegame.json"
const MAIN_MENU := "res://ui/menus/MainMenu.tscn"
const SETTINGS_CFG := "user://settings.cfg"

var _dim: ColorRect
var _center: CenterContainer
var _panel: PanelContainer
var _options_box: VBoxContainer
var _status: Label
var _btn_continue: Button
var _vol_slider: HSlider
var _vol_label: Label
var _edge_check: CheckButton
var _visible_menu := false


func _ready() -> void:
	# Capa alta para flotar sobre el HUD y proceso siempre, incluso en pausa.
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_load_quick_options()
	set_menu_visible(false)


func _build_ui() -> void:
	# Fondo oscuro semitransparente que bloquea clics a la partida.
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	# Contenedor que centra el panel en cualquier resolución.
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	# Panel estilo AoE2: pergamino oscuro semitransparente con borde dorado.
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(360, 0)
	_panel.add_theme_stylebox_override("panel", _aoe_panel_style())
	_center.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)
	# Título del menú.
	var title := Label.new()
	title.text = "Pausa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	vb.add_child(title)
	# Botones principales del menú.
	_btn_continue = _make_button(vb, "Continuar (Esc)")
	_btn_continue.pressed.connect(_on_continue)
	var save := _make_button(vb, "Guardar partida")
	save.pressed.connect(_on_save)
	var load := _make_button(vb, "Cargar partida")
	load.pressed.connect(_on_load)
	var opts := _make_button(vb, "Opciones")
	opts.pressed.connect(_on_options)
	var surrender := _make_button(vb, "Rendirse")
	surrender.pressed.connect(_on_surrender)
	var quit := _make_button(vb, "Salir al menú")
	quit.pressed.connect(_on_quit)
	# Subpanel plegable de opciones rápidas (no saca de la partida).
	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 6)
	_options_box.visible = false
	vb.add_child(_options_box)
	_build_quick_options()
	# Pista de atajos y línea de estado.
	var hint := Label.new()
	hint.text = "Esc cierra · F10 abre"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.65, 0.60, 0.52))
	vb.add_child(hint)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	vb.add_child(_status)


func _aoe_panel_style() -> StyleBoxFlat:
	# Estilo pergamino semitransparente con borde dorado redondeado.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.12, 0.08, 0.95)
	sb.border_color = Color(0.72, 0.58, 0.30)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 20.0
	sb.content_margin_bottom = 20.0
	return sb


func _make_button(parent: Container, text: String) -> Button:
	# Crea un botón ancho centrado listo para teclado y ratón.
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_ALL
	parent.add_child(b)
	return b


func _build_quick_options() -> void:
	# Volumen general con deslizante.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_options_box.add_child(row)
	var lab := Label.new()
	lab.text = "Volumen"
	lab.custom_minimum_size = Vector2(90, 0)
	row.add_child(lab)
	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 100.0
	_vol_slider.step = 1.0
	_vol_slider.value = 80.0
	_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol_slider.value_changed.connect(_on_volume_changed)
	row.add_child(_vol_slider)
	_vol_label = Label.new()
	_vol_label.custom_minimum_size = Vector2(52, 0)
	_vol_label.text = "80%"
	row.add_child(_vol_label)
	# Interruptor de edge-pan de cámara.
	_edge_check = CheckButton.new()
	_edge_check.text = "Edge-pan de cámara"
	_edge_check.button_pressed = true
	_edge_check.toggled.connect(_on_edge_pan_toggled)
	_options_box.add_child(_edge_check)


func _unhandled_input(event: InputEvent) -> void:
	# Esc cierra el menú si está abierto.
	if event.is_action_pressed("ui_cancel"):
		if _visible_menu:
			set_menu_visible(false)
			get_viewport().set_input_as_handled()
		return
	# F10 abre el menú (o lo alterna) sin depender del InputMap.
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_F10 or k.physical_keycode == KEY_F10):
			toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	# Alterna el estado visible/pausado del menú.
	set_menu_visible(not _visible_menu)


func show_menu() -> void:
	# Abre el menú y pausa el árbol de escena.
	set_menu_visible(true)


func hide_menu() -> void:
	# Cierra el menú y reanuda el árbol de escena.
	set_menu_visible(false)


func is_menu_open() -> bool:
	# Indica si el menú de pausa está visible.
	return _visible_menu


func set_menu_visible(v: bool) -> void:
	# Muestra u oculta el menú y pausa o reanuda el juego.
	_visible_menu = v
	if is_node_ready():
		_dim.visible = v
		_center.visible = v
		if v and is_instance_valid(_btn_continue):
			_btn_continue.grab_focus()
	get_tree().paused = v


func _on_continue() -> void:
	# Botón Continuar: cierra el menú y reanuda.
	set_menu_visible(false)


func _on_options() -> void:
	# Pliega o despliega las opciones rápidas sin salir de la partida.
	_options_box.visible = not _options_box.visible


func _on_surrender() -> void:
	# Marca al jugador local como eliminado (derrota) y reanuda como observador.
	var pid := _local_pid()
	if GameManager.has_method("eliminate_player"):
		GameManager.eliminate_player(pid, "rendición")
	elif pid >= 0 and pid < GameManager.players.size():
		GameManager.players[pid]["alive"] = false
	_set_status("Te has rendido. Sigues como observador.")
	set_menu_visible(false)


func _on_quit() -> void:
	# Sale al menú principal: reanuda, limpia el peer y cambia de escena.
	set_menu_visible(false)
	get_tree().paused = false
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	NetManager.is_host = false
	get_tree().change_scene_to_file(MAIN_MENU)


func _local_pid() -> int:
	# Resuelve el índice de jugador local (slot LAN o 0 en solitario).
	if multiplayer.has_multiplayer_peer() and NetManager.has_method("my_slot_index"):
		var slot := int(NetManager.my_slot_index())
		if slot >= 0:
			return slot
	return 0


func _set_status(msg: String) -> void:
	# Muestra un aviso corto bajo los botones.
	if is_instance_valid(_status):
		_status.text = msg


# ------------------------------------------------------------ Guardado --

func _on_save() -> void:
	# Guarda semilla, tick y jugadores en user://savegame.json.
	var data := {
		"map_seed": GameManager.map_seed,
		"tick": SimAPI.tick,
		"players": GameManager.players,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("PauseMenu: no se pudo abrir " + SAVE_PATH)
		_set_status("No se pudo guardar.")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("PauseMenu: partida guardada en " + SAVE_PATH)
	_set_status("Partida guardada.")
	set_menu_visible(false)


func _on_load() -> void:
	# Carga semilla, tick y jugadores desde user://savegame.json.
	if not FileAccess.file_exists(SAVE_PATH):
		push_error("PauseMenu: no hay guardado en " + SAVE_PATH)
		_set_status("No hay partida guardada.")
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("PauseMenu: guardado corrupto.")
		_set_status("Guardado corrupto.")
		return
	GameManager.map_seed = int(parsed.get("map_seed", 1234))
	SimAPI.tick = int(parsed.get("tick", 0))
	var cfgs: Array = []
	for p in (parsed.get("players", []) as Array):
		if typeof(p) == TYPE_DICTIONARY:
			cfgs.append({"civ": str(p.get("civ", "britones")), "team": int(p.get("team", 0))})
	if not cfgs.is_empty():
		GameManager.setup_lobby(cfgs)
		# Restaura recursos/población/edad exactas del guardado.
		for i in mini(cfgs.size(), (parsed["players"] as Array).size()):
			var src: Dictionary = (parsed["players"] as Array)[i]
			GameManager.players[i]["res"] = (src.get("res", {}) as Dictionary).duplicate(true)
			GameManager.players[i]["pop"] = int(src.get("pop", 3))
			GameManager.players[i]["pop_cap"] = int(src.get("pop_cap", 5))
			GameManager.players[i]["age"] = str(src.get("age", "alta_edad_media"))
			GameManager.players[i]["alive"] = bool(src.get("alive", true))
	print("PauseMenu: partida cargada de " + SAVE_PATH)
	_set_status("Partida cargada.")
	set_menu_visible(false)


# ------------------------------------------------- Opciones rápidas --

func _on_volume_changed(v: float) -> void:
	# Aplica volumen al bus Master y lo persiste en settings.cfg.
	_vol_label.text = "%d%%" % int(v)
	var db := lerpf(-40.0, 0.0, v / 100.0) if v > 0.0 else -80.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), v <= 0.0)
	_save_quick_options()


func _on_edge_pan_toggled(on: bool) -> void:
	# Guarda la preferencia de edge-pan para la cámara.
	_save_quick_options()


func _save_quick_options() -> void:
	# Persiste volumen y edge-pan sin salir de la partida.
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_CFG)
	cfg.set_value("audio", "volume", _vol_slider.value)
	cfg.set_value("camera", "edge_pan", _edge_check.button_pressed)
	cfg.save(SETTINGS_CFG)


func _load_quick_options() -> void:
	# Recupera volumen y edge-pan al abrir el menú.
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_CFG) != OK:
		_on_volume_changed(_vol_slider.value)
		return
	var vol := float(cfg.get_value("audio", "volume", 80.0))
	_vol_slider.value = vol
	_on_volume_changed(vol)
	_edge_check.button_pressed = bool(cfg.get_value("camera", "edge_pan", true))

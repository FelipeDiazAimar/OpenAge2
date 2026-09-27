extends Control
# Pantalla de Opciones estilo AoE2 con pestañas: Video, Audio y Controles.
# Usa nodos de Settings.tscn si existen; si falta alguno, lo crea por código.
# Video: resolución, pantalla completa y VSync. Audio: sliders Master/Música/Efectos.
# Controles: rebind de teclas del InputMap (se conserva la lógica previa).
# Persiste todo en user://settings.cfg. Botón Volver regresa al MainMenu.
# Sin assets de pago: solo colores y StyleBoxFlat generados por código.

const CFG_PATH := "user://settings.cfg"
const VOL_MIN_DB := -40.0
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
# Acciones definidas en project.godot [input] (no tocar ese archivo desde aquí).
const KEY_ACTIONS: Array[String] = ["attack_move", "patrol", "stop_action", "garrison",
	"build_menu", "go_tc", "bell", "idle_villager", "smart_action", "select_single"]

var edge_pan_enabled := true
var _res_opt: OptionButton = null
var _full_check: CheckButton = null
var _vsync_check: CheckButton = null
var _edge_check: CheckButton = null
var _master_slider: HSlider = null
var _musica_slider: HSlider = null
var _efectos_slider: HSlider = null
var _master_label: Label = null
var _musica_label: Label = null
var _efectos_label: Label = null
var _keys_box: VBoxContainer = null
var _waiting_action := ""
var _waiting_btn: Button = null

func _ready() -> void:
	# Orden: buses primero, luego estilo, luego nodos, luego carga y lista.
	_garantizar_buses_audio()
	_aplicar_estilo_aoe2()
	_enlazar_nodos()
	_cargar_settings()
	_refrescar_lista_teclas()

# ------------------------------------------------------- Buses de audio --
func _garantizar_buses_audio() -> void:
	# Crea Music y SFX en ejecución si el proyecto no los trae (no tocamos project.godot).
	for bus in ["Music", "SFX"]:
		_indice_bus(bus)

func _indice_bus(nombre: String) -> int:
	# Devuelve el índice del bus; lo crea colgando de Master si no existe.
	var idx := AudioServer.get_bus_index(nombre)
	if idx != -1:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, nombre)
	AudioServer.set_bus_send(idx, "Master")
	return idx

func _aplicar_volumen(nombre_bus: String, valor: float, etiqueta: Label) -> void:
	# Convierte 0-100 a dB y lo aplica al bus indicado; 0 = muteado.
	if etiqueta != null:
		etiqueta.text = "%d%%" % int(valor)
	var idx := _indice_bus(nombre_bus)
	var db := lerpf(VOL_MIN_DB, 0.0, valor / 100.0) if valor > 0.0 else -80.0
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, valor <= 0.0)

# ------------------------------------------------------------- Estilo AoE2 --
func _aplicar_estilo_aoe2() -> void:
	# Paleta piedra / pergamino / madera con borde dorado, sin texturas externas.
	var fondo := get_node_or_null("%Fondo") as ColorRect
	if fondo != null:
		fondo.color = Color(0.13, 0.09, 0.06)
	var panel := get_node_or_null("%Panel") as PanelContainer
	if panel != null:
		var estilo := StyleBoxFlat.new()
		estilo.bg_color = Color(0.24, 0.16, 0.10)
		estilo.border_color = Color(0.85, 0.65, 0.25)
		estilo.set_border_width_all(3)
		estilo.set_corner_radius_all(8)
		estilo.content_margin_left = 24
		estilo.content_margin_right = 24
		estilo.content_margin_top = 16
		estilo.content_margin_bottom = 16
		panel.add_theme_stylebox_override("panel", estilo)
	var titulo := get_node_or_null("%Titulo") as Label
	if titulo != null:
		titulo.add_theme_font_size_override("font_size", 32)
		titulo.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	for n in ["%GuardarButton", "%VolverButton"]:
		_estilar_boton(get_node_or_null(n) as Button)

func _estilar_boton(b: Button) -> void:
	# Botón madera con borde dorado y letra clara.
	if b == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.45, 0.28, 0.13)
	normal.border_color = Color(0.85, 0.65, 0.25)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.55, 0.35, 0.17)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.35, 0.21, 0.10)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color(1.0, 0.94, 0.80))

# ------------------------------------------------------- Enlace con el .tscn --
func _encontrar(porcentaje: String) -> Node:
	# Atajo para buscar nodos únicos del tscn sin romper si faltan.
	return get_node_or_null(porcentaje)

func _enlazar_nodos() -> void:
	# Recupera los nodos del tscn; si falta lo esencial, construye por código.
	_res_opt = _encontrar("%ResolucionOption") as OptionButton
	_full_check = _encontrar("%PantallaCompletaCheck") as CheckButton
	_vsync_check = _encontrar("%VSyncCheck") as CheckButton
	_edge_check = _encontrar("%EdgeCheck") as CheckButton
	_master_slider = _encontrar("%MasterSlider") as HSlider
	_musica_slider = _encontrar("%MusicaSlider") as HSlider
	_efectos_slider = _encontrar("%EfectosSlider") as HSlider
	_master_label = _encontrar("%MasterValor") as Label
	_musica_label = _encontrar("%MusicaValor") as Label
	_efectos_label = _encontrar("%EfectosValor") as Label
	_keys_box = _encontrar("%TeclasBox") as VBoxContainer
	if _res_opt == null or _master_slider == null or _keys_box == null:
		_construir_ui_programatica()
		return
	_rellenar_resoluciones()
	_conectar_senales()

func _rellenar_resoluciones() -> void:
	# Llena el OptionButton solo si el tscn lo dejó vacío.
	if _res_opt.item_count > 0:
		return
	for r in RESOLUTIONS:
		_res_opt.add_item("%dx%d" % [r.x, r.y])

func _conectar_senales() -> void:
	# Conecta cada señal una sola vez para no duplicar llamadas.
	if not _res_opt.item_selected.is_connected(_on_resolucion_elegida):
		_res_opt.item_selected.connect(_on_resolucion_elegida)
	if _full_check != null and not _full_check.toggled.is_connected(_on_fullscreen):
		_full_check.toggled.connect(_on_fullscreen)
	if _vsync_check != null and not _vsync_check.toggled.is_connected(_on_vsync):
		_vsync_check.toggled.connect(_on_vsync)
	if _edge_check != null and not _edge_check.toggled.is_connected(_on_edge_pan):
		_edge_check.toggled.connect(_on_edge_pan)
	if not _master_slider.value_changed.is_connected(_on_master):
		_master_slider.value_changed.connect(_on_master)
	if not _musica_slider.value_changed.is_connected(_on_musica):
		_musica_slider.value_changed.connect(_on_musica)
	if not _efectos_slider.value_changed.is_connected(_on_efectos):
		_efectos_slider.value_changed.connect(_on_efectos)
	var guardar := _encontrar("%GuardarButton") as Button
	if guardar != null and not guardar.pressed.is_connected(_guardar_settings):
		guardar.pressed.connect(_guardar_settings)
	var volver := _encontrar("%VolverButton") as Button
	if volver != null and not volver.pressed.is_connected(_on_volver):
		volver.pressed.connect(_on_volver)

func _construir_ui_programatica() -> void:
	# Respaldo: si el tscn está vacío o roto, levanta las pestañas por código.
	for c in get_children():
		c.queue_free()
	_res_opt = null
	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	margen.add_theme_constant_override("margin_left", 48)
	margen.add_theme_constant_override("margin_right", 48)
	margen.add_theme_constant_override("margin_top", 24)
	margen.add_theme_constant_override("margin_bottom", 24)
	add_child(margen)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margen.add_child(vb)
	var t := Label.new()
	t.text = "OPCIONES"
	t.add_theme_font_size_override("font_size", 32)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var tabs := TabContainer.new()
	tabs.name = "Pestanas"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)
	# Pestaña Video.
	var video := Control.new()
	video.name = "Video"
	tabs.add_child(video)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	video.add_child(vbox)
	var fila := HBoxContainer.new()
	vbox.add_child(fila)
	var rl := Label.new()
	rl.text = "Resolución"
	rl.custom_minimum_size = Vector2(200, 0)
	fila.add_child(rl)
	_res_opt = OptionButton.new()
	fila.add_child(_res_opt)
	_rellenar_resoluciones()
	_full_check = CheckButton.new()
	_full_check.text = "Pantalla completa"
	vbox.add_child(_full_check)
	_vsync_check = CheckButton.new()
	_vsync_check.text = "VSync (sincronización vertical)"
	_vsync_check.button_pressed = true
	vbox.add_child(_vsync_check)
	_edge_check = CheckButton.new()
	_edge_check.text = "Edge-pan (mover cámara al borde) activado"
	vbox.add_child(_edge_check)
	# Pestaña Audio.
	var audio := Control.new()
	audio.name = "Audio"
	tabs.add_child(audio)
	var abox := VBoxContainer.new()
	abox.set_anchors_preset(Control.PRESET_FULL_RECT)
	audio.add_child(abox)
	_master_slider = _crear_fila_volumen(abox, "Volumen general", _master_label)
	_musica_slider = _crear_fila_volumen(abox, "Volumen música", _musica_label)
	_efectos_slider = _crear_fila_volumen(abox, "Volumen efectos", _efectos_label)
	_master_label = _master_slider.get_parent().get_node("Valor") as Label
	_musica_label = _musica_slider.get_parent().get_node("Valor2") as Label
	_efectos_label = _efectos_slider.get_parent().get_node("Valor3") as Label
	# Pestaña Controles.
	var controles := Control.new()
	controles.name = "Controles"
	tabs.add_child(controles)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	controles.add_child(scroll)
	_keys_box = VBoxContainer.new()
	_keys_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_keys_box)
	var pie := HBoxContainer.new()
	pie.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(pie)
	var guardar := Button.new()
	guardar.text = "Guardar"
	pie.add_child(guardar)
	guardar.pressed.connect(_guardar_settings)
	var volver := Button.new()
	volver.text = "← Volver al menú"
	pie.add_child(volver)
	volver.pressed.connect(_on_volver)
	_conectar_senales()

func _crear_fila_volumen(padre: Container, texto: String, _ignorado: Label) -> HSlider:
	# Crea una fila etiqueta + slider + valor para la pestaña Audio.
	var fila := HBoxContainer.new()
	padre.add_child(fila)
	var lab := Label.new()
	lab.text = texto
	lab.custom_minimum_size = Vector2(200, 0)
	fila.add_child(lab)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.value = 80
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(s)
	var v := Label.new()
	v.name = "Valor" if texto == "Volumen general" else ("Valor2" if texto == "Volumen música" else "Valor3")
	v.custom_minimum_size = Vector2(60, 0)
	v.text = "80%"
	fila.add_child(v)
	return s

# ---------------------------------------------------------- Video y audio --
func _on_resolucion_elegida(idx: int) -> void:
	# Aplica la resolución elegida y guarda el cambio.
	_aplicar_video()
	_guardar_settings()

func _on_fullscreen(on: bool) -> void:
	# Alterna entre ventana y pantalla completa.
	_aplicar_video()
	_guardar_settings()

func _on_vsync(on: bool) -> void:
	# Activa o desactiva la sincronización vertical.
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)
	_guardar_settings()

func _aplicar_video() -> void:
	# Aplica resolución + pantalla completa según los controles actuales.
	if _res_opt == null:
		return
	var idx := clampi(_res_opt.selected, 0, RESOLUTIONS.size() - 1)
	var pantalla_completa := _full_check != null and _full_check.button_pressed
	if pantalla_completa:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(RESOLUTIONS[idx])

func _on_master(v: float) -> void:
	# Slider general: aplica al bus Master.
	_aplicar_volumen("Master", v, _master_label)
	_guardar_settings()

func _on_musica(v: float) -> void:
	# Slider de música: aplica al bus Music.
	_aplicar_volumen("Music", v, _musica_label)
	_guardar_settings()

func _on_efectos(v: float) -> void:
	# Slider de efectos: aplica al bus SFX.
	_aplicar_volumen("SFX", v, _efectos_label)
	_guardar_settings()

func _on_edge_pan(on: bool) -> void:
	# Guarda si la cámara se mueve al llevar el ratón al borde.
	edge_pan_enabled = on
	_guardar_settings()

func _on_volver() -> void:
	# Guarda y regresa al menú principal.
	_guardar_settings()
	get_tree().change_scene_to_file("res://ui/menus/MainMenu.tscn")

# --------------------------------------------------------------- Controles --
func _refrescar_lista_teclas() -> void:
	# Dibuja una fila por acción con su botón de rebind (lógica conservada).
	if _keys_box == null:
		return
	for c in _keys_box.get_children():
		c.queue_free()
	for action in KEY_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var fila := HBoxContainer.new()
		_keys_box.add_child(fila)
		var lab := Label.new()
		lab.text = action
		lab.custom_minimum_size = Vector2(200, 0)
		fila.add_child(lab)
		var b := Button.new()
		if _waiting_action == action:
			b.text = "... pulsa tecla ..."
		else:
			b.text = _texto_tecla_accion(action)
		b.custom_minimum_size = Vector2(160, 32)
		_estilar_boton(b)
		b.pressed.connect(_on_rebind_click.bind(action, b))
		fila.add_child(b)

func _texto_tecla_accion(action: String) -> String:
	# Texto legible de la primera tecla/ratón asignada a la acción.
	var evs := InputMap.action_get_events(action)
	if evs.is_empty():
		return "(sin tecla)"
	var e: InputEvent = evs[0]
	if e is InputEventKey:
		var k := e as InputEventKey
		var kc: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return OS.get_keycode_string(kc)
	if e is InputEventMouseButton:
		return "Ratón %d" % (e as InputEventMouseButton).button_index
	return e.as_text()

func _on_rebind_click(action: String, _btn: Button) -> void:
	# Marca la acción como pendiente y espera la próxima pulsación.
	_waiting_action = action
	_refrescar_lista_teclas()

func _unhandled_input(event: InputEvent) -> void:
	# Captura la tecla o botón de ratón para la acción en espera (Esc cancela).
	if _waiting_action.is_empty():
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
			_waiting_action = ""
			_refrescar_lista_teclas()
			get_viewport().set_input_as_handled()
			return
		InputMap.action_erase_events(_waiting_action)
		var nev := InputEventKey.new()
		nev.physical_keycode = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		InputMap.action_add_event(_waiting_action, nev)
		_waiting_action = ""
		_refrescar_lista_teclas()
		_guardar_settings()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		InputMap.action_erase_events(_waiting_action)
		InputMap.action_add_event(_waiting_action, event)
		_waiting_action = ""
		_refrescar_lista_teclas()
		_guardar_settings()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------ Persistencia --
func _guardar_settings() -> void:
	# Guarda video, audio, cámara y teclas en user://settings.cfg.
	if _res_opt == null or _master_slider == null:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", _master_slider.value)
	cfg.set_value("audio", "music", _musica_slider.value)
	cfg.set_value("audio", "sfx", _efectos_slider.value)
	cfg.set_value("video", "resolution_idx", _res_opt.selected)
	cfg.set_value("video", "fullscreen", _full_check.button_pressed if _full_check != null else false)
	cfg.set_value("video", "vsync", _vsync_check.button_pressed if _vsync_check != null else true)
	cfg.set_value("camera", "edge_pan", _edge_check.button_pressed if _edge_check != null else edge_pan_enabled)
	for action in KEY_ACTIONS:
		if InputMap.has_action(action):
			var evs := InputMap.action_get_events(action)
			if not evs.is_empty() and evs[0] is InputEventKey:
				cfg.set_value("keys", action, int((evs[0] as InputEventKey).physical_keycode))
	cfg.save(CFG_PATH)

func _cargar_settings() -> void:
	# Lee el cfg, aplica video/audio y restaura teclas (compatible con el formato previo).
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		_aplicar_volumen("Master", _master_slider.value, _master_label)
		_aplicar_volumen("Music", _musica_slider.value, _musica_label)
		_aplicar_volumen("SFX", _efectos_slider.value, _efectos_label)
		_aplicar_video()
		return
	# Audio: acepta claves nuevas (master/music/sfx) y la antigua (volume).
	var master := float(cfg.get_value("audio", "master", cfg.get_value("audio", "volume", 80.0)))
	var musica := float(cfg.get_value("audio", "music", master))
	var efectos := float(cfg.get_value("audio", "sfx", master))
	_master_slider.set_value_no_signal(master)
	_musica_slider.set_value_no_signal(musica)
	_efectos_slider.set_value_no_signal(efectos)
	_aplicar_volumen("Master", master, _master_label)
	_aplicar_volumen("Music", musica, _musica_label)
	_aplicar_volumen("SFX", efectos, _efectos_label)
	# Video: índice válido + pantalla completa + vsync.
	var idx := int(cfg.get_value("video", "resolution_idx", 0))
	if idx >= RESOLUTIONS.size():
		idx = RESOLUTIONS.size() - 1
	_res_opt.select(clampi(idx, 0, maxi(0, _res_opt.item_count - 1)))
	if _full_check != null:
		_full_check.set_pressed_no_signal(bool(cfg.get_value("video", "fullscreen", false)))
	if _vsync_check != null:
		var vs := bool(cfg.get_value("video", "vsync", true))
		_vsync_check.set_pressed_no_signal(vs)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vs else DisplayServer.VSYNC_DISABLED)
	_aplicar_video()
	# Cámara edge-pan.
	edge_pan_enabled = bool(cfg.get_value("camera", "edge_pan", true))
	if _edge_check != null:
		_edge_check.set_pressed_no_signal(edge_pan_enabled)
	# Teclas guardadas.
	for action in KEY_ACTIONS:
		if InputMap.has_action(action) and cfg.has_section_key("keys", action):
			var code := int(cfg.get_value("keys", action, 0))
			if code != 0:
				InputMap.action_erase_events(action)
				var nev := InputEventKey.new()
				nev.physical_keycode = code as Key
				InputMap.action_add_event(action, nev)

static func is_edge_pan_on() -> bool:
	# Las cámaras llaman Settings.is_edge_pan_on() o leen el cfg directamente.
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		return bool(cfg.get_value("camera", "edge_pan", true))
	return true

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
# Paleta medieval local (MenuStyle.gd no existe; se define aquí mismo).
# Madera para el marco, pergamino para opciones, oro para bordes y pomos,
# carmesí para acentos y hierro para botones. Todo procedural, sin assets.
const MED_MADERA_OSCURA := Color(0.28, 0.18, 0.10)
const MED_MADERA_BORDE := Color(0.16, 0.10, 0.06)
const MED_PERGAMINO := Color(0.87, 0.76, 0.55)
const MED_PERGAMINO_OSCURO := Color(0.76, 0.63, 0.42)
const MED_ORO := Color(0.85, 0.65, 0.25)
const MED_ORO_CLARO := Color(1.0, 0.82, 0.38)
const MED_CARMESI := Color(0.55, 0.12, 0.14)
const MED_HIERRO := Color(0.24, 0.25, 0.28)
const MED_HIERRO_CLARO := Color(0.34, 0.35, 0.39)
const MED_HIERRO_OSCURO := Color(0.14, 0.15, 0.17)
const MED_TINTA := Color(0.22, 0.14, 0.07)

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
	# Panel estilo medieval: marco de madera con remaches y borde dorado.
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(360, 0)
	_panel.add_theme_stylebox_override("panel", _aoe_panel_style())
	_center.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)
	_med_agregar_remaches(_panel)
	# Título del menú.
	var title := Label.new()
	title.text = "Pausa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", MED_ORO_CLARO)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
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
	# Subpanel plegable de opciones rápidas en pergamino (no saca de la partida).
	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 6)
	_options_box.visible = false
	vb.add_child(_options_box)
	_build_quick_options()
	# Pista de atajos y línea de estado.
	var hint := Label.new()
	hint.text = "Esc cierra · F10 abre"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", MED_PERGAMINO)
	vb.add_child(hint)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", MED_ORO_CLARO)
	vb.add_child(_status)


func _aoe_panel_style() -> StyleBoxFlat:
	# Marco de madera con borde dorado y sombra. Procedural puro.
	# Se conserva el nombre para no romper llamadas; la piel ahora es medieval.
	var sb := StyleBoxFlat.new()
	sb.bg_color = MED_MADERA_OSCURA
	sb.border_color = MED_ORO
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 20.0
	sb.content_margin_bottom = 20.0
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 14
	return sb


func _med_caja_pergamino() -> StyleBoxFlat:
	# Pergamino para el subpanel de opciones rápidas. Procedural puro.
	var sb := StyleBoxFlat.new()
	sb.bg_color = MED_PERGAMINO
	sb.border_color = MED_MADERA_BORDE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


func _med_agregar_remaches(panel: PanelContainer) -> void:
	# Remaches dorados en las esquinas del marco de madera.
	# Overlay para no romper el layout del PanelContainer.
	if panel == null:
		return
	if panel.has_meta("med_remaches"):
		return
	panel.set_meta("med_remaches", true)
	var overlay := Control.new()
	overlay.name = "RemachesOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(overlay)
	var esquinas := [Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT,
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]
	for preset in esquinas:
		var r := Panel.new()
		r.custom_minimum_size = Vector2(12, 12)
		r.size = Vector2(12, 12)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var estilo := StyleBoxFlat.new()
		estilo.bg_color = MED_ORO
		estilo.border_color = MED_MADERA_BORDE
		estilo.set_border_width_all(2)
		estilo.set_corner_radius_all(6)
		estilo.shadow_color = Color(0, 0, 0, 0.5)
		estilo.shadow_size = 3
		r.add_theme_stylebox_override("panel", estilo)
		overlay.add_child(r)
		r.set_anchors_preset(preset)
		match preset:
			Control.PRESET_TOP_LEFT:
				r.position = Vector2(6, 6)
			Control.PRESET_TOP_RIGHT:
				r.anchor_left = 1.0
				r.anchor_right = 1.0
				r.offset_left = -18.0
				r.offset_right = -6.0
				r.offset_top = 6.0
				r.offset_bottom = 18.0
			Control.PRESET_BOTTOM_LEFT:
				r.anchor_top = 1.0
				r.anchor_bottom = 1.0
				r.offset_left = 6.0
				r.offset_right = 18.0
				r.offset_top = -18.0
				r.offset_bottom = -6.0
			Control.PRESET_BOTTOM_RIGHT:
				r.anchor_left = 1.0
				r.anchor_right = 1.0
				r.anchor_top = 1.0
				r.anchor_bottom = 1.0
				r.offset_left = -18.0
				r.offset_right = -6.0
				r.offset_top = -18.0
				r.offset_bottom = -6.0


func _med_pomo_oro(tam: int = 18, resaltado: bool = false) -> ImageTexture:
	# Pomo dorado procedural para el slider, sin assets externos.
	var img := Image.create(tam, tam, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var centro := Vector2(tam, tam) * 0.5
	var radio := float(tam) * 0.5 - 1.0
	for y in range(tam):
		for x in range(tam):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centro)
			if d <= radio:
				var t := d / radio
				var col := MED_ORO_CLARO.lerp(MED_ORO, t)
				if d > radio - 2.0:
					col = MED_MADERA_BORDE
				if resaltado:
					col = col.lightened(0.15)
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _med_estilar_slider(s: HSlider) -> void:
	# Ranura de madera oscura, tramo dorado y pomo circular. Simple y procedural.
	if s == null:
		return
	var ranura := StyleBoxFlat.new()
	ranura.bg_color = MED_MADERA_BORDE
	ranura.set_corner_radius_all(4)
	ranura.content_margin_top = 4
	ranura.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", ranura)
	var relleno := StyleBoxFlat.new()
	relleno.bg_color = MED_ORO
	relleno.set_corner_radius_all(4)
	relleno.content_margin_top = 4
	relleno.content_margin_bottom = 4
	s.add_theme_stylebox_override("grabber_area", relleno)
	s.add_theme_icon_override("grabber", _med_pomo_oro(18, false))
	s.add_theme_icon_override("grabber_highlight", _med_pomo_oro(20, true))
	s.custom_minimum_size = Vector2(120, 22)


func _make_button(parent: Container, text: String) -> Button:
	# Botón de hierro ancho con hover dorado. Lógica intacta, solo piel medieval.
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_ALL
	var normal := StyleBoxFlat.new()
	normal.bg_color = MED_HIERRO
	normal.border_color = Color(0.10, 0.10, 0.11)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	normal.shadow_color = Color(0, 0, 0, 0.5)
	normal.shadow_size = 4
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = MED_HIERRO_CLARO
	hover.border_color = MED_ORO
	b.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = MED_HIERRO_OSCURO
	pressed.border_color = MED_ORO
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86))
	b.add_theme_color_override("font_hover_color", MED_ORO_CLARO)
	b.add_theme_color_override("font_pressed_color", MED_ORO)
	parent.add_child(b)
	return b


func _build_quick_options() -> void:
	# Volumen general con deslizante sobre pergamino; lógica intacta.
	var marco := PanelContainer.new()
	marco.add_theme_stylebox_override("panel", _med_caja_pergamino())
	_options_box.add_child(marco)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	marco.add_child(inner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	inner.add_child(row)
	var lab := Label.new()
	lab.text = "Volumen"
	lab.custom_minimum_size = Vector2(90, 0)
	lab.add_theme_color_override("font_color", MED_TINTA)
	row.add_child(lab)
	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 100.0
	_vol_slider.step = 1.0
	_vol_slider.value = 80.0
	_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_med_estilar_slider(_vol_slider)
	_vol_slider.value_changed.connect(_on_volume_changed)
	row.add_child(_vol_slider)
	_vol_label = Label.new()
	_vol_label.custom_minimum_size = Vector2(52, 0)
	_vol_label.text = "80%"
	_vol_label.add_theme_color_override("font_color", MED_TINTA)
	row.add_child(_vol_label)
	# Interruptor de edge-pan de cámara.
	_edge_check = CheckButton.new()
	_edge_check.text = "Edge-pan de cámara"
	_edge_check.button_pressed = true
	_edge_check.add_theme_color_override("font_color", MED_TINTA)
	_edge_check.toggled.connect(_on_edge_pan_toggled)
	inner.add_child(_edge_check)


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

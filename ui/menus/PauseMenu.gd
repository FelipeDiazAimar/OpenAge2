extends CanvasLayer
# Pausa v2: Continuar + Opciones-inline + Salir. Sin Guardar/Cargar/Rendirse (sin sistema v2).
# Estilo MainMenu via MenuStyle (panel madera, titulo oro, botones, pergamino). Sin paleta propia.
# Toggle ESC (ui_cancel) y F10. En LAN (multiplayer peer) no pausa el arbol (rompe lockstep).

const MAIN_MENU := "res://ui/menus/MainMenu.tscn"
const CFG := "user://settings.cfg"

var _dim: ColorRect
var _center: CenterContainer
var _options_box: VBoxContainer
var _status: Label
var _btn_continue: Button
var _vol: HSlider
var _vol_lab: Label
var _edge: CheckButton
var _open := false


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_load_opts()
	set_menu_visible(false)


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	panel.add_theme_stylebox_override("panel", MenuStyle.panel_madera())
	_center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	vb.add_child(MenuStyle.titulo_medieval("Pausa", 32))
	_btn_continue = MenuStyle.boton_medieval("Continuar (Esc)")
	_btn_continue.pressed.connect(_on_continue)
	vb.add_child(_btn_continue)
	var opts := MenuStyle.boton_medieval("Opciones")
	opts.pressed.connect(_on_options)
	vb.add_child(opts)
	_options_box = VBoxContainer.new()
	_options_box.visible = false
	vb.add_child(_options_box)
	_build_opts()
	var quit := MenuStyle.boton_medieval("Salir al menú")
	quit.pressed.connect(_on_quit)
	vb.add_child(quit)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", MenuStyle.ORO)
	vb.add_child(_status)


func _build_opts() -> void:
	var marco := PanelContainer.new()
	marco.add_theme_stylebox_override("panel", MenuStyle.pergamino())
	_options_box.add_child(marco)
	var inner := VBoxContainer.new()
	marco.add_child(inner)
	var row := HBoxContainer.new()
	inner.add_child(row)
	var lab := Label.new()
	lab.text = "Volumen"
	lab.custom_minimum_size = Vector2(90, 0)
	row.add_child(lab)
	_vol = HSlider.new()
	_vol.min_value = 0.0
	_vol.max_value = 100.0
	_vol.step = 1.0
	_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol.value_changed.connect(_on_vol)
	row.add_child(_vol)
	_vol_lab = Label.new()
	_vol_lab.custom_minimum_size = Vector2(52, 0)
	row.add_child(_vol_lab)
	_edge = CheckButton.new()
	_edge.text = "Edge-pan de cámara"
	_edge.toggled.connect(_on_edge)
	inner.add_child(_edge)


func _input(event: InputEvent) -> void:
	# ESC solo cierra si esta abierto (si esta cerrado, Match decide:
	# placing/panel o abrir el menu). F10 siempre alterna (Match no lo usa).
	if event.is_action_pressed("ui_cancel"):
		if _open:
			set_menu_visible(false)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_F10 or k.physical_keycode == KEY_F10):
			toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	set_menu_visible(not _open)


func show_menu() -> void:
	set_menu_visible(true)


func hide_menu() -> void:
	set_menu_visible(false)


func is_menu_open() -> bool:
	return _open


func set_menu_visible(v: bool) -> void:
	_open = v
	if is_node_ready():
		_dim.visible = v
		_center.visible = v
		if v:
			_status.text = "Pausa no disponible en LAN: la simulación sigue." if _is_lan() else ""
			_btn_continue.grab_focus()
	get_tree().paused = false if _is_lan() else v


func _is_lan() -> bool:
	# Solo hay LAN con un peer de red real (el peer offline de serie no cuenta).
	if not multiplayer.has_multiplayer_peer():
		return false
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer)


func _on_continue() -> void:
	set_menu_visible(false)


func _on_options() -> void:
	_options_box.visible = not _options_box.visible


func _on_quit() -> void:
	set_menu_visible(false)
	get_tree().paused = false
	var p := get_parent()
	if p != null and p.has_method("leave_to"):
		p.call("leave_to", MAIN_MENU)
	else:
		get_tree().change_scene_to_file(MAIN_MENU)


func _on_vol(v: float) -> void:
	_vol_lab.text = "%d%%" % int(v)
	var i := AudioServer.get_bus_index("Master")
	if i >= 0:
		AudioServer.set_bus_volume_db(i, lerpf(-40.0, 0.0, v / 100.0) if v > 0.0 else -80.0)
		AudioServer.set_bus_mute(i, v <= 0.0)
	_save_opts()


func _on_edge(on: bool) -> void:
	var p := get_parent()
	if p != null and p.get("cam") != null and "edge_scroll" in p.get("cam"):
		p.get("cam").set("edge_scroll", on)
	_save_opts()


func _save_opts() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("audio", "master", _vol.value)
	cfg.set_value("audio", "volume", _vol.value)
	cfg.set_value("camera", "edge_pan", _edge.button_pressed)
	cfg.save(CFG)


func _load_opts() -> void:
	var cfg := ConfigFile.new()
	var vol := 80.0
	var edge := true
	if cfg.load(CFG) == OK:
		vol = float(cfg.get_value("audio", "master", cfg.get_value("audio", "volume", 80.0)))
		edge = bool(cfg.get_value("camera", "edge_pan", true))
	_vol.set_value_no_signal(vol)
	_edge.set_pressed_no_signal(edge)
	_on_vol(vol)

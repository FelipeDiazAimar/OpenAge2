extends Control
# Settings estilo AoE2 (Opciones). Programatico como MainMenu.gd.
# Volumen, resolucion, edge-pan on/off, teclas (rebind de InputMap).
# Persiste en user://settings.cfg. Boton Volver -> MainMenu.

const CFG_PATH := "user://settings.cfg"
const VOL_MIN_DB := -40.0
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
# Acciones definidas en project.godot [input] + ui_cancel (Esc por defecto).
const KEY_ACTIONS: Array[String] = ["attack_move", "patrol", "stop_action", "garrison",
	"build_menu", "go_tc", "bell", "idle_villager", "smart_action", "select_single"]

var edge_pan_enabled := true
var _vol_slider: HSlider
var _vol_label: Label
var _res_opt: OptionButton
var _edge_check: CheckButton
var _keys_box: VBoxContainer
var _waiting_action := "" # accion pendiente de pulsar tecla
var _waiting_btn: Button = null

func _ready() -> void:
	_build_ui()
	_load_settings()
	_refresh_keys_list()

func _build_ui() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		m.add_theme_constant_override(side, 48)
	for side in ["margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, 24)
	add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	m.add_child(vb)

	var t := Label.new()
	t.text = "Opciones"
	t.add_theme_font_size_override("font_size", 26)
	vb.add_child(t)

	# --- Volumen ---
	var vrow := HBoxContainer.new()
	vb.add_child(vrow)
	var vl := Label.new()
	vl.text = "Volumen general"
	vl.custom_minimum_size = Vector2(200, 0)
	vrow.add_child(vl)
	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0
	_vol_slider.max_value = 100
	_vol_slider.step = 1
	_vol_slider.value = 80
	_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol_slider.value_changed.connect(_on_volume_changed)
	vrow.add_child(_vol_slider)
	_vol_label = Label.new()
	_vol_label.custom_minimum_size = Vector2(60, 0)
	vrow.add_child(_vol_label)

	# --- Resolucion ---
	var rrow := HBoxContainer.new()
	vb.add_child(rrow)
	var rl := Label.new()
	rl.text = "Resolución"
	rl.custom_minimum_size = Vector2(200, 0)
	rrow.add_child(rl)
	_res_opt = OptionButton.new()
	for r in RESOLUTIONS:
		_res_opt.add_item("%dx%d" % [r.x, r.y])
	_res_opt.add_item("Pantalla completa")
	_res_opt.item_selected.connect(_on_resolution_selected)
	rrow.add_child(_res_opt)

	# --- Edge-pan ---
	_edge_check = CheckButton.new()
	_edge_check.text = "Edge-pan (mover cámara al borde) activado"
	_edge_check.toggled.connect(_on_edge_pan_toggled)
	vb.add_child(_edge_check)

	# --- Teclas ---
	var kl := Label.new()
	kl.text = "Teclas (clic en botón y pulsa la nueva tecla):"
	vb.add_child(kl)
	_keys_box = VBoxContainer.new()
	vb.add_child(_keys_box)

	var bot := HBoxContainer.new()
	vb.add_child(bot)
	var save := Button.new()
	save.text = "Guardar"
	save.pressed.connect(_save_settings)
	bot.add_child(save)
	var back := Button.new()
	back.text = "← Volver"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/menus/MainMenu.tscn"))
	bot.add_child(back)

func _refresh_keys_list() -> void:
	for c in _keys_box.get_children():
		c.queue_free()
	for action in KEY_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var row := HBoxContainer.new()
		_keys_box.add_child(row)
		var lab := Label.new()
		lab.text = action
		lab.custom_minimum_size = Vector2(200, 0)
		row.add_child(lab)
		var b := Button.new()
		b.text = _action_key_text(action) if _waiting_action != action else "... pulsa tecla ..."
		b.custom_minimum_size = Vector2(160, 32)
		b.pressed.connect(_on_rebind_click.bind(action, b))
		row.add_child(b)

func _action_key_text(action: String) -> String:
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

func _on_rebind_click(action: String, btn: Button) -> void:
	_waiting_action = action
	_waiting_btn = btn
	_refresh_keys_list()

func _unhandled_input(event: InputEvent) -> void:
	if _waiting_action.is_empty():
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		InputMap.action_erase_events(_waiting_action)
		var nev := InputEventKey.new()
		nev.physical_keycode = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		InputMap.action_add_event(_waiting_action, nev)
		_waiting_action = ""
		_refresh_keys_list()
		_save_settings()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		InputMap.action_erase_events(_waiting_action)
		InputMap.action_add_event(_waiting_action, event)
		_waiting_action = ""
		_refresh_keys_list()
		_save_settings()
		get_viewport().set_input_as_handled()

# --------------------------------------------------- Audio / video --

func _on_volume_changed(v: float) -> void:
	_vol_label.text = "%d%%" % int(v)
	var db := lerpf(VOL_MIN_DB, 0.0, v / 100.0) if v > 0.0 else -80.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), v <= 0.0)

func _on_resolution_selected(idx: int) -> void:
	if idx < RESOLUTIONS.size():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(RESOLUTIONS[idx])
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _on_edge_pan_toggled(on: bool) -> void:
	edge_pan_enabled = on

static func is_edge_pan_on() -> bool:
	# Los scripts de camara llaman Settings.is_edge_pan_on() o leen el cfg.
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		return bool(cfg.get_value("camera", "edge_pan", true))
	return true

# ------------------------------------------------------ Persistencia --

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", _vol_slider.value)
	cfg.set_value("video", "resolution_idx", _res_opt.selected)
	cfg.set_value("video", "fullscreen", _res_opt.selected >= RESOLUTIONS.size())
	cfg.set_value("camera", "edge_pan", _edge_check.button_pressed)
	for action in KEY_ACTIONS:
		if InputMap.has_action(action):
			var evs := InputMap.action_get_events(action)
			if not evs.is_empty() and evs[0] is InputEventKey:
				cfg.set_value("keys", action, int((evs[0] as InputEventKey).physical_keycode))
	cfg.save(CFG_PATH)
	print("Settings guardados en " + CFG_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		_on_volume_changed(_vol_slider.value)
		_edge_check.button_pressed = true
		_res_opt.selected = 0
		return
	var vol := float(cfg.get_value("audio", "volume", 80.0))
	_vol_slider.value = vol
	_on_volume_changed(vol)
	_res_opt.selected = int(cfg.get_value("video", "resolution_idx", 0))
	_on_resolution_selected(_res_opt.selected)
	edge_pan_enabled = bool(cfg.get_value("camera", "edge_pan", true))
	_edge_check.button_pressed = edge_pan_enabled
	for action in KEY_ACTIONS:
		if InputMap.has_action(action) and cfg.has_section_key("keys", action):
			var code := int(cfg.get_value("keys", action, 0))
			if code != 0:
				InputMap.action_erase_events(action)
				var nev := InputEventKey.new()
				nev.physical_keycode = code as Key
				InputMap.action_add_event(action, nev)

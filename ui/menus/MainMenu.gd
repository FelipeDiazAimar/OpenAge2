extends Control
# MainMenu clon AoE2: Un jugador / Multijugador LAN / Campaña / Editor / Opciones
# Layout con CenterContainer (centrado real en cualquier resolución).

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Fondo estilo AoE (marrón oscuro, sin assets).
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.08, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	center.add_child(vb)

	var title := Label.new()
	title.text = "OpenAge-LAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "RTS tipo AoE2 — LAN hasta 8 jugadores — 100% gratis"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.75, 0.70, 0.60))
	vb.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vb.add_child(spacer)

	_add_btn(vb, "Un Jugador (vs IA)", _on_single)
	_add_btn(vb, "Multijugador LAN (hasta 8)", _on_multi)
	_add_btn(vb, "Campaña", _on_campaign)
	_add_btn(vb, "Editor Mapas", _on_editor)
	_add_btn(vb, "Opciones", _on_options)
	_add_btn(vb, "Partida (nuevo motor, beta)", _on_new_engine)

	var ver := Label.new()
	ver.text = "v0.1 — Godot 4.4 — Presiona el modo para empezar"
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_color_override("font_color", Color(0.55, 0.52, 0.48))
	vb.add_child(ver)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	vb.add_child(_status)

var _status: Label

func _add_btn(parent: Container, text: String, fn: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(420, 52)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_ALL
	btn.pressed.connect(fn)
	parent.add_child(btn)

func _on_single() -> void:
	# Partida local inmediata vs bots (GameWorld usa driver solo-local sin peer).
	get_tree().change_scene_to_file("res://ui/hud/Game.tscn")

func _on_multi() -> void:
	var msg: String = NetManager.host_game("arabia")
	_status.text = msg + " — tus amigos: Multijugador -> Buscar LAN"
	# Pequeña espera para que el host ENet quede activo antes del cambio.
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://ui/hud/Game.tscn")

func _on_campaign() -> void:
	if ResourceLoader.exists("res://ui/menus/CampaignMenu.tscn"):
		get_tree().change_scene_to_file("res://ui/menus/CampaignMenu.tscn")
	else:
		_status.text = "Campaña no encontrada (falta CampaignMenu.tscn)"

func _on_editor() -> void:
	_status.text = "Editor: abre tools/MapEditor como escena en el editor Godot"

func _on_options() -> void:
	if ResourceLoader.exists("res://ui/menus/Settings.tscn"):
		get_tree().change_scene_to_file("res://ui/menus/Settings.tscn")
	else:
		_status.text = "Opciones: volumen y resolución desde Settings (solo editor)"


func _on_new_engine() -> void:
	get_tree().change_scene_to_file("res://game/scenes/Match.tscn")

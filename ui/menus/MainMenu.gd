extends Control
# MainMenu estilo AoE2 DE: título dorado con sombra y botones anchos.
# Conserva rutas: Un Jugador, LAN, Campaña, Editor, Opciones y beta v2.
# Todo procedural con StyleBoxFlat, sin assets externos de pago.

var _status: Label
var _botones: Array[Button] = []

func _ready() -> void:
	# Asegura pantalla completa al abrir la escena.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Fondo: usa MenuBackdrop del TSCN o crea degradado oscuro.
	_aplicar_fondo()
	# Marco de piedra/madera procedural sobre el panel central.
	_estilizar_marco()
	# Título dorado grande con sombra y subtítulo pergamino.
	_estilizar_titulos()
	# Botones anchos con hover brillante y rutas originales.
	_conectar_y_estilizar_botones()
	# Versión abajo y ayudas de controles visibles.
	_asegurar_version_y_hints()
	# Localiza el estado y deja foco inicial para teclado.
	_localizar_status()
	_arrancar_musica()
	if not _botones.is_empty():
		_botones[0].call_deferred("grab_focus")


func _arrancar_musica() -> void:
	# Música de menú procedural (se libera sola al cambiar de escena).
	if not FileAccess.file_exists("res://audio/MenuMusic.gd"):
		return
	var mm: Node = load("res://audio/MenuMusic.gd").new()
	mm.name = "MenuMusic"
	add_child(mm)
	if mm.has_method("start_menu_music"):
		mm.call("start_menu_music")

func _aplicar_fondo() -> void:
	# Si el TSCN trae MenuBackdrop, le pone degradado procedural.
	var fondo := get_node_or_null("MenuBackdrop") as TextureRect
	if fondo != null:
		if fondo.texture == null:
			fondo.texture = _crear_degradado_fondo()
		fondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		fondo.show()
		return
	# Sin nodo en escena: crea fondo degradado oscuro de respaldo.
	var respaldo := TextureRect.new()
	respaldo.name = "MenuBackdropAuto"
	respaldo.set_anchors_preset(Control.PRESET_FULL_RECT)
	respaldo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	respaldo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	respaldo.texture = _crear_degradado_fondo()
	respaldo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(respaldo)
	move_child(respaldo, 0)

func _crear_degradado_fondo() -> GradientTexture2D:
	# Degradado vertical oscuro marrón-negro a rojizo, 100% procedural.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([
		Color(0.07, 0.05, 0.04),
		Color(0.13, 0.09, 0.06),
		Color(0.05, 0.03, 0.02)
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 512
	tex.height = 512
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex

func _estilizar_marco() -> void:
	# Marco piedra/madera con StyleBoxFlat: borde dorado-piedra y sombra.
	var panel := get_node_or_null("CenterContainer/MainFrame") as PanelContainer
	if panel == null:
		return
	var marco := StyleBoxFlat.new()
	marco.bg_color = Color(0.13, 0.09, 0.06, 0.95)
	marco.border_width_left = 3
	marco.border_width_top = 3
	marco.border_width_right = 3
	marco.border_width_bottom = 3
	marco.border_color = Color(0.72, 0.58, 0.30)
	marco.corner_radius_top_left = 10
	marco.corner_radius_top_right = 10
	marco.corner_radius_bottom_right = 10
	marco.corner_radius_bottom_left = 10
	marco.shadow_color = Color(0, 0, 0, 0.6)
	marco.shadow_size = 18
	panel.add_theme_stylebox_override("panel", marco)

func _estilizar_titulos() -> void:
	# Título dorado grande con sombra y contorno oscuro.
	var titulo := get_node_or_null("CenterContainer/MainFrame/Margin/MenuVBox/TitleLabel") as Label
	if titulo != null:
		titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		titulo.add_theme_font_size_override("font_size", 68)
		titulo.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
		titulo.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.05))
		titulo.add_theme_constant_override("outline_size", 8)
		titulo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		titulo.add_theme_constant_override("shadow_offset_x", 3)
		titulo.add_theme_constant_override("shadow_offset_y", 3)
	# Subtítulo color pergamino con sombra suave.
	var sub := get_node_or_null("CenterContainer/MainFrame/Margin/MenuVBox/SubtitleLabel") as Label
	if sub != null:
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 16)
		sub.add_theme_color_override("font_color", Color(0.82, 0.76, 0.64))
		sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		sub.add_theme_constant_override("shadow_offset_x", 2)
		sub.add_theme_constant_override("shadow_offset_y", 2)

func _conectar_y_estilizar_botones() -> void:
	# Mapea cada botón del TSCN a su ruta existente, sin cambiar destinos.
	var rutas: Dictionary = {
		"CenterContainer/MainFrame/Margin/MenuVBox/SingleButton": _on_single,
		"CenterContainer/MainFrame/Margin/MenuVBox/MultiButton": _on_multi,
		"CenterContainer/MainFrame/Margin/MenuVBox/CampaignButton": _on_campaign,
		"CenterContainer/MainFrame/Margin/MenuVBox/EditorButton": _on_editor,
		"CenterContainer/MainFrame/Margin/MenuVBox/OptionsButton": _on_options,
		"CenterContainer/MainFrame/Margin/MenuVBox/NewEngineButton": _on_new_engine,
	}
	_botones.clear()
	for ruta: String in rutas.keys():
		var btn := get_node_or_null(ruta) as Button
		if btn == null:
			continue
		_estilo_boton_aoe(btn)
		var fn: Callable = rutas[ruta]
		if not btn.pressed.is_connected(fn):
			btn.pressed.connect(fn)
		_botones.append(btn)
	# Respaldo: si el TSCN viniera vacío, recrea los 6 botones originales.
	if _botones.is_empty():
		var vb := get_node_or_null("CenterContainer/MainFrame/Margin/MenuVBox") as VBoxContainer
		if vb != null:
			_add_btn(vb, "Un Jugador (vs IA)", _on_single)
			_add_btn(vb, "Multijugador LAN (hasta 8)", _on_multi)
			_add_btn(vb, "Campaña", _on_campaign)
			_add_btn(vb, "Editor Mapas", _on_editor)
			_add_btn(vb, "Opciones", _on_options)
			_add_btn(vb, "Partida (nuevo motor, beta)", _on_new_engine)

func _estilo_boton_aoe(btn: Button) -> void:
	# Botón ancho estilo AoE2 DE: madera oscura, borde piedra y hover brillante.
	btn.custom_minimum_size = Vector2(460, 54)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.70))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.88, 0.55))
	btn.add_theme_color_override("font_focus_color", Color(1.0, 0.95, 0.70))
	# Estado normal: madera oscura con borde dorado apagado.
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.28, 0.19, 0.11)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(0.62, 0.48, 0.26)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_right = 6
	normal.corner_radius_bottom_left = 6
	normal.shadow_color = Color(0, 0, 0, 0.5)
	normal.shadow_size = 8
	btn.add_theme_stylebox_override("normal", normal)
	# Hover brillante: fondo cálido y borde dorado vivo.
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.52, 0.36, 0.18)
	hover.border_color = Color(1.0, 0.86, 0.48)
	hover.shadow_color = Color(1.0, 0.80, 0.35, 0.35)
	hover.shadow_size = 12
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", hover)
	# Pulsado: madera quemada más oscura.
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.18, 0.12, 0.07)
	pressed.border_color = Color(0.85, 0.68, 0.35)
	btn.add_theme_stylebox_override("pressed", pressed)
	# Deshabilitado: gris piedra apagado.
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.16, 0.15, 0.13)
	disabled.border_color = Color(0.35, 0.33, 0.30)
	btn.add_theme_stylebox_override("disabled", disabled)

func _asegurar_version_y_hints() -> void:
	# Versión abajo a la izquierda, siempre visible.
	var ver := get_node_or_null("VersionLabel") as Label
	if ver != null:
		ver.add_theme_font_size_override("font_size", 14)
		ver.add_theme_color_override("font_color", Color(0.60, 0.57, 0.52))
		ver.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		ver.add_theme_constant_override("shadow_offset_x", 1)
		ver.add_theme_constant_override("shadow_offset_y", 1)
	# Ayudas de controles abajo a la derecha.
	var hints := get_node_or_null("HintsLabel") as Label
	if hints != null:
		hints.add_theme_font_size_override("font_size", 14)
		hints.add_theme_color_override("font_color", Color(0.68, 0.63, 0.55))
		hints.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		hints.add_theme_constant_override("shadow_offset_x", 1)
		hints.add_theme_constant_override("shadow_offset_y", 1)

func _localizar_status() -> void:
	# Etiqueta de mensajes dentro del marco, con color dorado suave.
	_status = get_node_or_null("CenterContainer/MainFrame/Margin/MenuVBox/StatusLabel") as Label
	if _status != null:
		_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.50))

func _add_btn(parent: Container, text: String, fn: Callable) -> void:
	# Creador de respaldo con el mismo estilo AoE2 DE.
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL
	btn.pressed.connect(fn)
	parent.add_child(btn)
	_estilo_boton_aoe(btn)
	_botones.append(btn)

func _on_single() -> void:
	# Partida local inmediata vs bots (GameWorld usa driver solo-local sin peer).
	get_tree().change_scene_to_file("res://ui/hud/Game.tscn")

func _on_multi() -> void:
	# Crea host LAN y avisa cómo unirse antes de entrar al juego.
	var msg: String = NetManager.host_game("arabia")
	_status.text = msg + " — tus amigos: Multijugador -> Buscar LAN"
	# Pequeña espera para que el host ENet quede activo antes del cambio.
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://ui/hud/Game.tscn")

func _on_campaign() -> void:
	# Abre la campaña si existe, o muestra aviso en el estado.
	if ResourceLoader.exists("res://ui/menus/CampaignMenu.tscn"):
		get_tree().change_scene_to_file("res://ui/menus/CampaignMenu.tscn")
	else:
		_status.text = "Campaña no encontrada (falta CampaignMenu.tscn)"

func _on_editor() -> void:
	# El editor se abre como escena en el editor Godot.
	_status.text = "Editor: abre tools/MapEditor como escena en el editor Godot"

func _on_options() -> void:
	# Abre ajustes si existe, o indica la vía alternativa.
	if ResourceLoader.exists("res://ui/menus/Settings.tscn"):
		get_tree().change_scene_to_file("res://ui/menus/Settings.tscn")
	else:
		_status.text = "Opciones: volumen y resolución desde Settings (solo editor)"

func _on_new_engine() -> void:
	# Botón beta conservado: abre la escena v2 del nuevo motor.
	get_tree().change_scene_to_file("res://game/scenes/Match.tscn")

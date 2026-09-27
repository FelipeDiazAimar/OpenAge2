extends Control
# MainMenu estilo medieval: marco madera, título dorado y botones con hover.
# Conserva rutas: Un Jugador, LAN, Campaña, Editor, Opciones y beta v2.
# Usa ui/menus/MenuStyle.gd, todo procedural sin assets de pago.

var _status: Label
var _botones: Array[Button] = []

func _ready() -> void:
	# Asegura pantalla completa al abrir la escena.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Fondo: usa MenuBackdrop del TSCN o crea degradado oscuro.
	_aplicar_fondo()
	# Marco de madera procedural vía MenuStyle.
	_estilizar_marco()
	# Título dorado con sombra de antorcha y subtítulo pergamino.
	_estilizar_titulos()
	# Botones con borde hierro y hover brillante, rutas originales.
	_conectar_y_estilizar_botones()
	# Estandartes laterales carmesí con color de civ.
	_asegurar_estandartes()
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
	# Marco madera central con ayuda de MenuStyle.
	var panel := get_node_or_null("CenterContainer/MainFrame") as PanelContainer
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", MenuStyle.panel_madera())

func _estilizar_titulos() -> void:
	# Título dorado con sombra de antorcha vía MenuStyle.
	var titulo := get_node_or_null("CenterContainer/MainFrame/Margin/MenuVBox/TitleLabel") as Label
	if titulo != null:
		MenuStyle.aplicar_titulo(titulo, 68)
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
		"CenterContainer/MainFrame/Margin/MenuVBox/PlayButton": _on_new_engine,
		"CenterContainer/MainFrame/Margin/MenuVBox/CampaignButton": _on_campaign,
		"CenterContainer/MainFrame/Margin/MenuVBox/EditorButton": _on_editor,
		"CenterContainer/MainFrame/Margin/MenuVBox/OptionsButton": _on_options,
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
	# Respaldo: si el TSCN viniera vacío, recrea los botones del motor nuevo.
	if _botones.is_empty():
		var vb := get_node_or_null("CenterContainer/MainFrame/Margin/MenuVBox") as VBoxContainer
		if vb != null:
			_add_btn(vb, "Jugar", _on_new_engine)
			_add_btn(vb, "Campaña", _on_campaign)
			_add_btn(vb, "Editor Mapas", _on_editor)
			_add_btn(vb, "Opciones", _on_options)

func _estilo_boton_aoe(btn: Button) -> void:
	# Delega en MenuStyle: borde hierro y hover dorado brillante.
	MenuStyle.aplicar_boton(btn)

func _asegurar_estandartes() -> void:
	# Estandartes heráldicos colgados (no pilares): paño oscuro arriba con
	# dobladillo dorado. Sobrios para no competir con el panel central.
	_hacer_estandarte("LeftBanner", true, Color(0.36, 0.07, 0.09))
	_hacer_estandarte("RightBanner", false, Color(0.10, 0.15, 0.33))


func _hacer_estandarte(nombre: String, izquierda: bool, color: Color) -> void:
	# Reutiliza el nodo del TSCN si existe; si no, lo crea colgado arriba.
	var viejo := get_node_or_null(nombre) as ColorRect
	if viejo != null:
		viejo.queue_free()
	var paño := ColorRect.new()
	paño.name = nombre
	paño.color = color
	paño.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if izquierda:
		paño.set_anchors_preset(Control.PRESET_TOP_LEFT)
		paño.offset_left = 26.0
		paño.offset_right = 72.0
	else:
		paño.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		paño.offset_left = -72.0
		paño.offset_right = -26.0
	paño.offset_top = 0.0
	paño.anchor_bottom = 0.40
	paño.offset_bottom = 0.0
	add_child(paño)
	move_child(paño, 1)
	# Dobladillo dorado abajo + franja central oscura para dar forma.
	var dob := ColorRect.new()
	dob.color = Color(0.72, 0.58, 0.30)
	dob.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dob.offset_top = -12.0
	dob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paño.add_child(dob)
	var faja := ColorRect.new()
	faja.color = Color(0, 0, 0, 0.25)
	faja.anchor_left = 0.5
	faja.anchor_right = 0.5
	faja.offset_left = -7.0
	faja.offset_right = 7.0
	faja.anchor_bottom = 1.0
	faja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paño.add_child(faja)

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
	# Creador de respaldo con botón medieval ya estilizado.
	var btn := MenuStyle.boton_medieval(text)
	btn.pressed.connect(fn)
	parent.add_child(btn)
	_botones.append(btn)

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

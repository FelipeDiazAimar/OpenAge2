class_name LoadingScreen
extends Control
# Pantalla de carga estilo AoE2: fondo oscuro, escudo/título, barra animada y consejos.
# Sin autoload: la escena se instancia bajo tree.root y sobrevive a change_scene_to_file.
# Uso desde cualquier menú (MainMenu u otro, sin editarlos):
# 	LoadingScreen.change_to("res://ui/hud/Game.tscn")
# Si se coloca LoadingScreen.tscn a mano (vista previa), solo anima barra y consejos.
# Todo dibujado por código, sin assets de pago. Godot 4.4, indentación con tabs.

const RUTA_ESCENA := "res://ui/menus/LoadingScreen.tscn"
const TIEMPO_FUNDIDO := 0.35
const TIEMPO_CONSEJO := 2.8
# Consejos rotativos de controles reales (ver project.godot [input]) más LAN y pausa.
const CONSEJOS: Array[String] = [
	"Clic izquierdo: seleccionar. Clic derecho: mover / atacar (acción inteligente).",
	"A: orden de ataque. Pulsa A y clic en el suelo para avanzar atacando.",
	"P: patrullar. S: detener. G: guarecer a los aldeanos.",
	"B: menú de construcción. H: ir al Centro Urbano. T: tocar la campana.",
	"Punto (.): saltar al aldeano inactivo. No dejes aldeanos de brazos cruzados.",
	"En LAN: el anfitrión crea en Multijugador; el resto entra en Buscar LAN.",
	"Esc: pausa. Guarda la partida antes de salir al menú.",
]

var _destino: String = ""
var _velo: ColorRect
var _barra: ProgressBar
var _consejo: Label
var _porcentaje: Label
var _tiempo_consejo := 0.0
var _idx_consejo := 0


# Muestra fundido a negro, cambia de escena y funde de vuelta. Ignora llamadas duplicadas.
static func change_to(ruta_destino: String) -> void:
	# Se usa Engine.get_main_loop() para no depender de ningún autoload ni escena actual.
	var arbol := Engine.get_main_loop() as SceneTree
	if arbol == null:
		push_error("LoadingScreen: sin SceneTree activo.")
		return
	if ruta_destino.is_empty() or not ResourceLoader.exists(ruta_destino):
		push_error("LoadingScreen: destino inválido: " + ruta_destino)
		return
	for hijo in arbol.root.get_children():
		if hijo is LoadingScreen:
			return
	var escena := load(RUTA_ESCENA) as PackedScene
	if escena == null:
		push_error("LoadingScreen: no se pudo cargar " + RUTA_ESCENA)
		return
	var pantalla := escena.instantiate() as LoadingScreen
	if pantalla == null:
		push_error("LoadingScreen: la escena raíz no es LoadingScreen.")
		return
	# Se fija el destino antes de añadir para que _ready() lo vea y arranque solo.
	pantalla._destino = ruta_destino
	arbol.root.add_child(pantalla)


# Fundido genérico reutilizable: anima el alfa de cualquier CanvasItem y devuelve el Tween.
static func fade_simple(item: CanvasItem, alfa_objetivo: float, duracion: float = 0.35) -> Tween:
	if item == null or not item.is_inside_tree():
		push_error("LoadingScreen.fade_simple: item fuera del árbol.")
		return null
	var tween := item.create_tween()
	tween.tween_property(item, "modulate:a", clampf(alfa_objetivo, 0.0, 1.0), maxf(duracion, 0.01))
	return tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Bloquea clics mientras carga para evitar dobles pulsaciones en el menú anterior.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_construir_ui()
	_mostrar_consejo(0)
	if not _destino.is_empty():
		_ejecutar_cambio.call_deferred()


func _process(delta: float) -> void:
	# Rota el consejo cada TIEMPO_CONSEJO segundos.
	_tiempo_consejo += delta
	if _tiempo_consejo >= TIEMPO_CONSEJO:
		_tiempo_consejo = 0.0
		_mostrar_consejo(_idx_consejo + 1)
	# En vista previa (sin destino) la barra gira en bucle sola.
	if _destino.is_empty() and is_instance_valid(_barra):
		_barra.value = fmod(_barra.value + delta * 40.0, 100.0)
		_actualizar_porcentaje()


# Fundido a negro -> cambio de escena -> fundido de vuelta y autoliberación.
func _ejecutar_cambio() -> void:
	if not is_inside_tree():
		return
	# Avanza la barra al 60% mientras funde a negro.
	var pre := create_tween()
	pre.tween_property(_barra, "value", 60.0, TIEMPO_FUNDIDO)
	var fundido := fade_simple(_velo, 1.0, TIEMPO_FUNDIDO)
	if fundido != null:
		await fundido.finished
	var err := get_tree().change_scene_to_file(_destino)
	if err != OK:
		push_error("LoadingScreen: no se pudo abrir " + _destino)
		_consejo.text = "No se pudo cargar la escena. Volviendo..."
		var vuelta := fade_simple(_velo, 0.0, TIEMPO_FUNDIDO)
		if vuelta != null:
			await vuelta.finished
		queue_free()
		return
	# Deja dos frames para que la escena nueva se asiente bajo el velo negro.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_barra):
		return
	_barra.value = 85.0
	_actualizar_porcentaje()
	var fin := create_tween()
	fin.tween_property(_barra, "value", 100.0, TIEMPO_FUNDIDO * 0.8)
	await fin.finished
	var destape := fade_simple(_velo, 0.0, TIEMPO_FUNDIDO)
	if destape != null:
		await destape.finished
	queue_free()


func _mostrar_consejo(idx: int) -> void:
	if CONSEJOS.is_empty() or not is_instance_valid(_consejo):
		return
	_idx_consejo = posmod(idx, CONSEJOS.size())
	_consejo.text = "Consejo: " + CONSEJOS[_idx_consejo]


func _actualizar_porcentaje() -> void:
	if is_instance_valid(_porcentaje) and is_instance_valid(_barra):
		_porcentaje.text = "%d%%" % int(_barra.value)


# Construye toda la UI por código (la .tscn solo trae la raíz Control + este script).
func _construir_ui() -> void:
	# Fondo marrón oscuro estilo AoE.
	var fondo := ColorRect.new()
	fondo.color = Color(0.07, 0.055, 0.04)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)
	# Marco dorado fino interior, solo decorativo (Panel con borde, visible en juego).
	var marco := Panel.new()
	marco.set_anchors_preset(Control.PRESET_FULL_RECT)
	marco.offset_left = 18.0
	marco.offset_top = 18.0
	marco.offset_right = -18.0
	marco.offset_bottom = -18.0
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estilo_marco := StyleBoxFlat.new()
	estilo_marco.draw_center = false
	estilo_marco.set_border_width_all(2)
	estilo_marco.border_color = Color(0.55, 0.42, 0.22)
	marco.add_theme_stylebox_override("panel", estilo_marco)
	add_child(marco)

	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centro)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	centro.add_child(vb)

	# Escudo dibujado con emoji (sin assets): vale como emblema temporal.
	var escudo := Label.new()
	escudo.text = "🛡️"
	escudo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	escudo.add_theme_font_size_override("font_size", 84)
	vb.add_child(escudo)

	var titulo := Label.new()
	titulo.text = "OpenAge-LAN"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 52)
	titulo.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	vb.add_child(titulo)

	var subtitulo := Label.new()
	subtitulo.text = "Cargando batalla..."
	subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitulo.add_theme_font_size_override("font_size", 20)
	subtitulo.add_theme_color_override("font_color", Color(0.75, 0.70, 0.60))
	vb.add_child(subtitulo)

	var separador := Control.new()
	separador.custom_minimum_size = Vector2(0, 8)
	vb.add_child(separador)

	# Barra de progreso dorada sobre fondo oscuro.
	_barra = ProgressBar.new()
	_barra.min_value = 0.0
	_barra.max_value = 100.0
	_barra.value = 0.0
	_barra.show_percentage = false
	_barra.custom_minimum_size = Vector2(440, 22)
	_barra.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_barra.add_theme_stylebox_override("background", _estilo_caja(Color(0.12, 0.10, 0.08), 6))
	_barra.add_theme_stylebox_override("fill", _estilo_caja(Color(0.85, 0.65, 0.25), 6))
	vb.add_child(_barra)

	_porcentaje = Label.new()
	_porcentaje.text = "0%"
	_porcentaje.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_porcentaje.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62))
	vb.add_child(_porcentaje)
	# La barra emite value_changed al animarla con Tween: refleja el % sin _process.
	_barra.value_changed.connect(_actualizar_porcentaje)

	_consejo = Label.new()
	_consejo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_consejo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_consejo.custom_minimum_size = Vector2(480, 0)
	_consejo.add_theme_font_size_override("font_size", 16)
	_consejo.add_theme_color_override("font_color", Color(0.80, 0.74, 0.60))
	vb.add_child(_consejo)

	# Velo negro para los fundidos: empieza transparente y queda encima de todo.
	_velo = ColorRect.new()
	_velo.color = Color(0, 0, 0, 1)
	_velo.modulate.a = 0.0
	_velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_velo)


func _estilo_caja(color: Color, radio: int = 6) -> StyleBoxFlat:
	var caja := StyleBoxFlat.new()
	caja.bg_color = color
	caja.set_corner_radius_all(radio)
	return caja

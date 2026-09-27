extends Control
# Galería medieval de civilizaciones: parrilla con emblema, bonus y nº de cartas.
# Lee los bonus de res://data/factions/*.json y cuenta cartas de res://mods/aoe2_base/cards/*.json.
# Cada tarjeta muestra nombre, color, bonus resumidos, nº de cartas y escudo procedural con la inicial.
# Al pulsar una tarjeta se abre el detalle y se emite civ_picked(civ) para que otra pantalla la use.
# Estilo medieval 100 % procedural, sin assets externos. GDScript 4.4 con tabs.

signal civ_picked(civ: String)

const FACTIONS_DIR := "res://data/factions"
const CARDS_DIR := "res://mods/aoe2_base/cards"
const ORO := Color(1.0, 0.84, 0.42)
const PERGAMINO := Color(0.82, 0.76, 0.64)
const MAX_RESUMEN := 90

var _civs: Array = []
var _propias := {}
var _neutrales := 0
var _seleccion := ""

var _grid: GridContainer
var _detalle_marco: PanelContainer
var _detalle_muestra: TextureRect
var _detalle_inicial: Label
var _detalle_titulo: Label
var _detalle_bonus: Label
var _detalle_cartas: Label


func _ready() -> void:
	# Ocupa toda la pantalla y monta la galería sobre el TSCN.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_localizar_nodos()
	_aplicar_estilo_medieval()
	_cargar_civs()
	_contar_cartas()
	_construir_parrilla()
	if not _civs.is_empty():
		_mostrar_detalle(str((_civs[0] as Dictionary).get("id", "")))
	_conectar_volver()


func _localizar_nodos() -> void:
	# Recupera los nodos del TSCN; si falta alguno se sigue sin romper.
	_grid = get_node_or_null("Margen/Principal/CivGrid") as GridContainer
	_detalle_marco = get_node_or_null("Margen/Principal/DetalleFrame") as PanelContainer
	_detalle_muestra = get_node_or_null("Margen/Principal/DetalleFrame/DetalleMargen/DetalleCaja/DetalleEmblema/DetalleMuestra") as TextureRect
	_detalle_inicial = get_node_or_null("Margen/Principal/DetalleFrame/DetalleMargen/DetalleCaja/DetalleEmblema/DetalleInicial") as Label
	_detalle_titulo = get_node_or_null("Margen/Principal/DetalleFrame/DetalleMargen/DetalleCaja/DetalleVBox/DetalleTitulo") as Label
	_detalle_bonus = get_node_or_null("Margen/Principal/DetalleFrame/DetalleMargen/DetalleCaja/DetalleVBox/DetalleBonus") as Label
	_detalle_cartas = get_node_or_null("Margen/Principal/DetalleFrame/DetalleMargen/DetalleCaja/DetalleVBox/DetalleCartas") as Label


func _aplicar_estilo_medieval() -> void:
	# Título dorado con sombra de antorcha.
	var titulo := get_node_or_null("Margen/Principal/Titulo") as Label
	if titulo != null:
		titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		titulo.add_theme_font_size_override("font_size", 40)
		titulo.add_theme_color_override("font_color", ORO)
		titulo.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.05))
		titulo.add_theme_constant_override("outline_size", 6)
		titulo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		titulo.add_theme_constant_override("shadow_offset_x", 2)
		titulo.add_theme_constant_override("shadow_offset_y", 2)
	# Subtítulo color pergamino.
	var sub := get_node_or_null("Margen/Principal/Subtitulo") as Label
	if sub != null:
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 15)
		sub.add_theme_color_override("font_color", PERGAMINO)
	# Marco de madera del detalle.
	if _detalle_marco != null:
		_detalle_marco.add_theme_stylebox_override("panel", _marco_madera())
	if _detalle_titulo != null:
		_detalle_titulo.add_theme_font_size_override("font_size", 22)
		_detalle_titulo.add_theme_color_override("font_color", ORO)
	if _detalle_bonus != null:
		_detalle_bonus.add_theme_font_size_override("font_size", 14)
		_detalle_bonus.add_theme_color_override("font_color", PERGAMINO)
	if _detalle_cartas != null:
		_detalle_cartas.add_theme_font_size_override("font_size", 14)
		_detalle_cartas.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	if _detalle_inicial != null:
		_detalle_inicial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_detalle_inicial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_detalle_inicial.add_theme_font_size_override("font_size", 40)
		_detalle_inicial.add_theme_color_override("font_color", ORO)
		_detalle_inicial.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_detalle_inicial.add_theme_constant_override("outline_size", 6)
	# Botón volver con madera oscura y hover dorado.
	var volver := get_node_or_null("Margen/Principal/FilaBotones/BotonVolver") as Button
	if volver != null:
		_estilo_boton(volver)


func _cargar_civs() -> void:
	# Lee cada data/factions/*.json: id, nombre, roof_color y descripciones de bonus.
	_civs.clear()
	var dir := DirAccess.open(FACTIONS_DIR)
	if dir == null:
		return
	var archivos: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			archivos.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	archivos.sort()
	for nombre in archivos:
		var texto := FileAccess.get_file_as_string(FACTIONS_DIR + "/" + nombre)
		if texto.strip_edges().is_empty():
			continue
		var datos: Variant = JSON.parse_string(texto)
		if not (datos is Dictionary):
			continue
		var d: Dictionary = datos
		var bonus: Array[String] = []
		var lista: Variant = d.get("bonus", [])
		if lista is Array:
			for b in (lista as Array):
				if b is Dictionary and (b as Dictionary).has("descripcion"):
					bonus.append(str((b as Dictionary)["descripcion"]))
		_civs.append({
			"id": str(d.get("id", nombre.get_basename())),
			"nombre": str(d.get("name", d.get("id", nombre.get_basename()))),
			"color": str(d.get("roof_color", d.get("color", "#73706a"))),
			"bonus": bonus,
		})
	_civs.sort_custom(func(a: Variant, b: Variant) -> bool: return str((a as Dictionary)["nombre"]) < str((b as Dictionary)["nombre"]))


func _contar_cartas() -> void:
	# Cuenta en mods/aoe2_base/cards/*.json cuántas cartas tienen civ == id de facción.
	_propias.clear()
	_neutrales = 0
	var dir := DirAccess.open(CARDS_DIR)
	if dir == null:
		return
	var archivos: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			archivos.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	archivos.sort()
	for nombre in archivos:
		var texto := FileAccess.get_file_as_string(CARDS_DIR + "/" + nombre)
		if texto.strip_edges().is_empty():
			continue
		var datos: Variant = JSON.parse_string(texto)
		var lista: Array = []
		if datos is Array:
			lista = datos
		elif datos is Dictionary:
			lista = [datos]
		for c in lista:
			if not (c is Dictionary):
				continue
			var cciv := str((c as Dictionary).get("civ", "")).strip_edges().to_lower()
			if cciv == "" or cciv == "todas" or cciv == "todas_las" or cciv == "neutral" or cciv == "neutrales":
				_neutrales += 1
			else:
				_propias[cciv] = int(_propias.get(cciv, 0)) + 1


func _construir_parrilla() -> void:
	# Una tarjeta por civilización: escudo con inicial, nombre, bonus resumidos y nº de cartas.
	if _grid == null:
		return
	for hijo in _grid.get_children():
		hijo.queue_free()
	for civ in _civs:
		_grid.add_child(_crear_tarjeta(civ))


func _crear_tarjeta(civ: Dictionary) -> PanelContainer:
	# Tarjeta clicable con el color de la civ en el borde.
	var id := str(civ.get("id", ""))
	var nombre := str(civ.get("nombre", id))
	var color := Color.html(str(civ.get("color", "#73706a")))
	var tarjeta := PanelContainer.new()
	tarjeta.name = "Civ_" + id
	tarjeta.set_meta("civ", id)
	tarjeta.add_theme_stylebox_override("panel", _marco_tarjeta(color, id == _seleccion))
	var margen := MarginContainer.new()
	margen.add_theme_constant_override("margin_left", 12)
	margen.add_theme_constant_override("margin_top", 10)
	margen.add_theme_constant_override("margin_right", 12)
	margen.add_theme_constant_override("margin_bottom", 10)
	tarjeta.add_child(margen)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	margen.add_child(caja)
	# Emblema procedural (escudo de CivEmblems) con la inicial encima.
	var emblema := Control.new()
	emblema.custom_minimum_size = Vector2(80, 80)
	emblema.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(emblema)
	var escudo := TextureRect.new()
	escudo.set_anchors_preset(Control.PRESET_FULL_RECT)
	escudo.texture = CivEmblems.emblem(id, 80)
	escudo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	escudo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	escudo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblema.add_child(escudo)
	var inicial := Label.new()
	inicial.set_anchors_preset(Control.PRESET_FULL_RECT)
	inicial.text = nombre.left(1).to_upper()
	inicial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inicial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inicial.add_theme_font_size_override("font_size", 34)
	inicial.add_theme_color_override("font_color", ORO)
	inicial.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	inicial.add_theme_constant_override("outline_size", 6)
	inicial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblema.add_child(inicial)
	# Nombre con el color de la civ.
	var etiqueta := Label.new()
	etiqueta.text = nombre
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.add_theme_font_size_override("font_size", 22)
	etiqueta.add_theme_color_override("font_color", color.lightened(0.35))
	etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(etiqueta)
	# Bonus resumidos (dos primeros, recortados).
	var bonus := Label.new()
	bonus.text = _resumen(civ)
	bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bonus.custom_minimum_size = Vector2(220, 66)
	bonus.add_theme_font_size_override("font_size", 13)
	bonus.add_theme_color_override("font_color", PERGAMINO)
	bonus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(bonus)
	# Nº de cartas propias más neutrales utilizables.
	var propias := int(_propias.get(id.to_lower(), 0))
	var cartas := Label.new()
	cartas.text = "%d cartas (+%d neutrales)" % [propias, _neutrales]
	cartas.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cartas.add_theme_font_size_override("font_size", 14)
	cartas.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	cartas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(cartas)
	# Botón para teclado y click directo sobre la tarjeta.
	var ver := Button.new()
	ver.text = "Ver detalle"
	ver.focus_mode = Control.FOCUS_ALL
	_estilo_boton(ver)
	ver.pressed.connect(_on_elegir.bind(id))
	caja.add_child(ver)
	tarjeta.gui_input.connect(_on_tarjeta_input.bind(id))
	return tarjeta


func _resumen(civ: Dictionary) -> String:
	# Dos primeros bonus recortados a una línea cada uno.
	var bonus: Variant = civ.get("bonus", [])
	if not (bonus is Array) or (bonus as Array).is_empty():
		return "Sin bonus registrados."
	var lineas: Array[String] = []
	var total := mini(2, (bonus as Array).size())
	for i in total:
		lineas.append("• " + _recortar(str((bonus as Array)[i]), MAX_RESUMEN))
	if (bonus as Array).size() > total:
		lineas.append("• (+%d bonus más)" % ((bonus as Array).size() - total))
	return "\n".join(lineas)


func _recortar(texto: String, maximo: int) -> String:
	# Recorta sin partir palabras cuando es posible.
	var limpio := texto.strip_edges()
	if limpio.length() <= maximo:
		return limpio
	var corte := limpio.left(maximo - 1)
	var espacio := corte.rfind(" ")
	if espacio > maximo / 2:
		corte = corte.left(espacio)
	return corte + "…"


func _on_tarjeta_input(evento: InputEvent, id: String) -> void:
	# Click en cualquier punto de la tarjeta abre su detalle.
	if evento is InputEventMouseButton:
		var raton := evento as InputEventMouseButton
		if raton.button_index == MOUSE_BUTTON_LEFT and raton.pressed:
			_on_elegir(id)


func _on_elegir(id: String) -> void:
	# Abre el detalle, resalta la tarjeta y avisa a la otra pantalla.
	_seleccion = id
	_mostrar_detalle(id)
	_refrescar_bordes()
	civ_picked.emit(id)


func _mostrar_detalle(id: String) -> void:
	# Rellena el panel inferior con todos los bonus y el conteo de cartas.
	var civ := _buscar(id)
	if civ.is_empty():
		return
	var nombre := str(civ.get("nombre", id))
	var bonus: Array = civ.get("bonus", [])
	var propias := int(_propias.get(id.to_lower(), 0))
	if _detalle_muestra != null:
		_detalle_muestra.texture = CivEmblems.emblem(id, 96)
	if _detalle_inicial != null:
		_detalle_inicial.text = nombre.left(1).to_upper()
	if _detalle_titulo != null:
		_detalle_titulo.text = nombre
	if _detalle_bonus != null:
		if bonus.is_empty():
			_detalle_bonus.text = "Sin bonus registrados."
		else:
			var lineas: Array[String] = []
			for b in bonus:
				lineas.append("• " + str(b))
			_detalle_bonus.text = "\n".join(lineas)
	if _detalle_cartas != null:
		_detalle_cartas.text = "Cartas propias: %d  ·  Neutrales utilizables: %d" % [propias, _neutrales]


func _buscar(id: String) -> Dictionary:
	# Localiza la civ por id en lo ya cargado de data/factions.
	for civ in _civs:
		if str((civ as Dictionary).get("id", "")).to_lower() == id.to_lower():
			return civ
	return {}


func _refrescar_bordes() -> void:
	# La tarjeta elegida lleva borde dorado; las demás, el color de su civ.
	if _grid == null:
		return
	for tarjeta in _grid.get_children():
		if not (tarjeta is PanelContainer):
			continue
		var id := str((tarjeta as PanelContainer).get_meta("civ", ""))
		var civ := _buscar(id)
		var color := Color.html(str(civ.get("color", "#73706a")))
		(tarjeta as PanelContainer).add_theme_stylebox_override("panel", _marco_tarjeta(color, id == _seleccion))


func _conectar_volver() -> void:
	# Vuelve al menú principal si existe la escena.
	var volver := get_node_or_null("Margen/Principal/FilaBotones/BotonVolver") as Button
	if volver != null and not volver.pressed.is_connected(_on_volver):
		volver.pressed.connect(_on_volver)


func _on_volver() -> void:
	# Regresa al menú principal; si falta, no hace nada.
	if ResourceLoader.exists("res://ui/menus/MainMenu.tscn"):
		get_tree().change_scene_to_file("res://ui/menus/MainMenu.tscn")


func _marco_madera() -> StyleBoxFlat:
	# Marco de madera oscura con ribete dorado para el panel de detalle.
	var marco := StyleBoxFlat.new()
	marco.bg_color = Color(0.13, 0.09, 0.06, 0.95)
	marco.border_width_left = 3
	marco.border_width_top = 3
	marco.border_width_right = 3
	marco.border_width_bottom = 3
	marco.border_color = ORO
	marco.corner_radius_top_left = 10
	marco.corner_radius_top_right = 10
	marco.corner_radius_bottom_right = 10
	marco.corner_radius_bottom_left = 10
	marco.shadow_color = Color(0, 0, 0, 0.6)
	marco.shadow_size = 18
	return marco


func _marco_tarjeta(color: Color, elegida: bool) -> StyleBoxFlat:
	# Tarjeta de madera con borde del color de la civ (oro si está elegida).
	var marco := StyleBoxFlat.new()
	marco.bg_color = Color(0.13, 0.09, 0.06, 0.95)
	marco.border_width_left = 3
	marco.border_width_top = 3
	marco.border_width_right = 3
	marco.border_width_bottom = 3
	marco.border_color = ORO if elegida else color
	marco.corner_radius_top_left = 8
	marco.corner_radius_top_right = 8
	marco.corner_radius_bottom_right = 8
	marco.corner_radius_bottom_left = 8
	marco.shadow_color = Color(0, 0, 0, 0.6)
	marco.shadow_size = 12
	return marco


func _estilo_boton(boton: Button) -> void:
	# Botón de madera oscura con hover dorado, coherente con el menú.
	boton.custom_minimum_size = Vector2(220, 44)
	boton.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	boton.add_theme_font_size_override("font_size", 17)
	boton.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	boton.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.70))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.30, 0.20, 0.12)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(0.25, 0.26, 0.29)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_right = 6
	normal.corner_radius_bottom_left = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.45, 0.31, 0.16)
	hover.border_color = ORO
	var pulsado := normal.duplicate() as StyleBoxFlat
	pulsado.bg_color = Color(0.19, 0.12, 0.07)
	pulsado.border_color = Color(0.85, 0.68, 0.35)
	boton.add_theme_stylebox_override("normal", normal)
	boton.add_theme_stylebox_override("hover", hover)
	boton.add_theme_stylebox_override("focus", hover)
	boton.add_theme_stylebox_override("pressed", pulsado)

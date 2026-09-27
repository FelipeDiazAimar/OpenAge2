extends Control
# Visor de tecnologías (solo lectura): árbol por edades I-IV con secciones por edificio.
# Lee mods/aoe2_base/techs/*.json (formato techs con effects) y data/ages/ages.json.
# Filtra por civilización atenuando vetadas según data/factions/*/tech_tree.
# No investiga nada: no toca SimAPI ni GameManager, solo FileAccess + DirAccess.

const RUTA_EDADES := "res://data/ages/ages.json"
const RUTA_TECNOLOGIAS := "res://mods/aoe2_base/techs"
const RUTA_FACCIONES := "res://data/factions"
const ESCENA_MENU := "res://ui/menus/MainMenu.tscn"

# Orden canónico de edades (I-IV) y de edificios del visor.
const ORDEN_EDADES := {"alta_edad_media": 0, "feudal": 1, "castillos": 2, "imperial": 3}
const NUMEROS_EDAD := ["I", "II", "III", "IV"]
const ORDEN_EDIFICIOS: Array = ["herreria", "universidad", "monasterio", "castillo"]
const NOMBRES_EDIFICIOS := {
	"herreria": "Herrería",
	"universidad": "Universidad",
	"monasterio": "Monasterio",
	"castillo": "Castillo",
}
const ORDEN_COSTE: Array = ["food", "wood", "gold", "stone"]
const ETIQUETAS_COSTE := {"food": "comida", "wood": "madera", "gold": "oro", "stone": "piedra"}

var _edades: Array = []
var _tecs: Array = []
var _civs: Array = []
var _civ_actual: String = "todas"
var _ocultar_vetadas: bool = false

@onready var _filtro: OptionButton = get_node_or_null("Margen/Columna/Barra/FiltroCiv")
@onready var _contenido: VBoxContainer = get_node_or_null("Margen/Columna/Scroll/Contenido")
@onready var _info: Label = get_node_or_null("Margen/Columna/Info")
@onready var _volver: Button = get_node_or_null("Margen/Columna/Barra/BotonVolver")


func _ready() -> void:
	# Pantalla completa y estilos medievales de respaldo.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_aplicar_estilos_base()
	_cargar_edades()
	_cargar_tecnologias()
	_cargar_civilizaciones()
	_rellenar_filtro()
	_conectar_senales()
	_construir_arbol()


func _conectar_senales() -> void:
	# Filtro de civ, interruptor de vetadas y botón Volver; nada de research real.
	if _filtro != null and not _filtro.item_selected.is_connected(_al_elegir_civ):
		_filtro.item_selected.connect(_al_elegir_civ)
		var oculta := CheckButton.new()
		oculta.text = "Ocultar no disponibles"
		oculta.button_pressed = _ocultar_vetadas
		oculta.toggled.connect(_al_cambiar_ocultar)
		(_filtro.get_parent() as Container).add_child(oculta)
	if _volver != null and not _volver.pressed.is_connected(_on_volver):
		_volver.pressed.connect(_on_volver)


func _al_cambiar_ocultar(valor: bool) -> void:
	# Muestra solo lo disponible de la civ o todo atenuado.
	_ocultar_vetadas = valor
	_construir_arbol()


func _on_volver() -> void:
	# Vuelve al menú principal si existe; si no, avisa en la info.
	if ResourceLoader.exists(ESCENA_MENU):
		get_tree().change_scene_to_file(ESCENA_MENU)
	elif _info != null:
		_info.text = "No se encontró el menú principal (ui/menus/MainMenu.tscn)."


func _al_elegir_civ(indice: int) -> void:
	# Guarda la civ elegida y reconstruye el árbol atenuando vetadas.
	if _filtro != null and _filtro.has_meta("_ids"):
		var ids: Array = _filtro.get_meta("_ids")
		if indice >= 0 and indice < ids.size():
			_civ_actual = str(ids[indice])
	_construir_arbol()


# ---------------------------------------------------------- carga de datos ---

func _leer_json(ruta: String) -> Variant:
	# Lee un JSON y lo devuelve parseado, o null si falla.
	if not FileAccess.file_exists(ruta):
		return null
	var f := FileAccess.open(ruta, FileAccess.READ)
	if f == null:
		return null
	var texto := f.get_as_text()
	f.close()
	return JSON.parse_string(texto)


func _cargar_edades() -> void:
	# Lee data/ages/ages.json (4 edades); si falla usa las 4 canónicas.
	_edades.clear()
	var datos: Variant = _leer_json(RUTA_EDADES)
	if datos is Dictionary and datos.get("ages") is Array:
		for e in datos["ages"]:
			if e is Dictionary and e.get("id") is String:
				_edades.append({
					"id": str(e["id"]),
					"name": str(e.get("name", e["id"])),
					"cost": e.get("cost", {}),
				})
	if _edades.is_empty():
		_edades = [
			{"id": "alta_edad_media", "name": "Alta Edad Media", "cost": {}},
			{"id": "feudal", "name": "Feudal", "cost": {"food": 500}},
			{"id": "castillos", "name": "Castillos", "cost": {"food": 800, "gold": 200}},
			{"id": "imperial", "name": "Imperial", "cost": {"food": 1000, "gold": 800}},
		]
	_edades.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(ORDEN_EDADES.get(a["id"], 99)) < int(ORDEN_EDADES.get(b["id"], 99)))


func _cargar_tecnologias() -> void:
	# Lee cada mods/aoe2_base/techs/*.json y lo normaliza a una ficha común.
	_tecs.clear()
	var dir := DirAccess.open(RUTA_TECNOLOGIAS)
	if dir == null:
		push_warning("TechViewer: no se pudo abrir " + RUTA_TECNOLOGIAS)
		return
	var archivos: Array = Array(dir.get_files())
	archivos.sort()
	for archivo in archivos:
		if not str(archivo).ends_with(".json"):
			continue
		var datos: Variant = _leer_json(RUTA_TECNOLOGIAS + "/" + str(archivo))
		if not (datos is Dictionary):
			continue
		_tecs.append(_normalizar_tec(datos))
	_tecs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ea: int = int(ORDEN_EDADES.get(str(a["edad"]), 99))
		var eb: int = int(ORDEN_EDADES.get(str(b["edad"]), 99))
		if ea != eb:
			return ea < eb
		var ba: int = ORDEN_EDIFICIOS.find(str(a["edificio"]))
		var bb: int = ORDEN_EDIFICIOS.find(str(b["edificio"]))
		if ba != bb:
			return ba < bb
		return str(a["id"]) < str(b["id"]))


func _normalizar_tec(d: Dictionary) -> Dictionary:
	# Acepta claves en inglés (id/name/cost/at/requires) y en español (nombre/coste/edificio/edad).
	var req: Dictionary = {}
	if d.get("requires") is Dictionary:
		req = d["requires"]
	var edad := str(req.get("age", d.get("edad", "feudal")))
	var coste: Dictionary = {}
	if d.get("cost") is Dictionary:
		coste = (d["cost"] as Dictionary).duplicate()
	elif d.get("coste") is Dictionary:
		coste = (d["coste"] as Dictionary).duplicate()
	return {
		"id": str(d.get("id", "?")),
		"nombre": str(d.get("name", d.get("nombre", d.get("id", "?")))),
		"coste": coste,
		"tiempo": int(d.get("research_time", d.get("tiempo_sec", 0))),
		"edificio": str(d.get("at", d.get("edificio", "herreria"))),
		"edad": edad,
		"descripcion": str(d.get("description", d.get("descripcion", "Sin descripción."))),
		"effects": d.get("effects", []),
		"legacy": d.get("legacy_effects", d.get("efectos", {})),
	}


func _cargar_civilizaciones() -> void:
	# Lee data/factions/*.json (id, name, tech_tree); si no hay, se muestran todas.
	_civs.clear()
	var dir := DirAccess.open(RUTA_FACCIONES)
	if dir == null:
		return
	var archivos: Array = Array(dir.get_files())
	archivos.sort()
	for archivo in archivos:
		if not str(archivo).ends_with(".json"):
			continue
		var datos: Variant = _leer_json(RUTA_FACCIONES + "/" + str(archivo))
		if not (datos is Dictionary):
			continue
		_civs.append({
			"id": str(datos.get("id", str(archivo).get_basename())),
			"nombre": str(datos.get("name", datos.get("id", "?"))),
			"tech_tree": datos.get("tech_tree", {}),
		})
	_civs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["nombre"]) < str(b["nombre"]))


func _rellenar_filtro() -> void:
	# Primera opción "Todas"; luego una por civ encontrada.
	if _filtro == null:
		return
	_filtro.clear()
	var ids: Array = ["todas"]
	_filtro.add_item("Todas las civilizaciones")
	for c in _civs:
		_filtro.add_item(str(c["nombre"]))
		ids.append(str(c["id"]))
	_filtro.set_meta("_ids", ids)
	_filtro.selected = 0
	_civ_actual = "todas"


func _nombre_civ() -> String:
	# Nombre visible de la civ filtrada (para la etiqueta de veto).
	for c in _civs:
		if str(c["id"]) == _civ_actual:
			return str(c["nombre"])
	return "Todas"


func _esta_vetada(id_tec: String, edificio: String) -> bool:
	# Vetada si su tech_tree la marca en false o está en no_disponible_resumen.
	# Ausencia de clave: en castillo (techs únicas) cuenta como veto; en el resto se muestra.
	if _civ_actual == "todas":
		return false
	for c in _civs:
		if str(c["id"]) != _civ_actual:
			continue
		var tree: Variant = c.get("tech_tree", {})
		if not (tree is Dictionary) or (tree as Dictionary).is_empty():
			return false
		if tree.get("no_disponible_resumen") is Array and (tree["no_disponible_resumen"] as Array).has(id_tec):
			return true
		var seccion: Variant = (tree as Dictionary).get(edificio, null)
		if not (seccion is Dictionary):
			return false
		if (seccion as Dictionary).has(id_tec):
			return not bool((seccion as Dictionary)[id_tec])
		return edificio == "castillo"
	return false


# ---------------------------------------------------------- formato de texto ---

func _texto_coste(coste: Variant) -> String:
	# "150 comida · 100 oro" o "Sin coste" si viene vacío.
	if not (coste is Dictionary) or (coste as Dictionary).is_empty():
		return "Sin coste"
	var partes: Array = []
	for clave in ORDEN_COSTE:
		if (coste as Dictionary).has(clave):
			partes.append("%d %s" % [int((coste as Dictionary)[clave]), str(ETIQUETAS_COSTE[clave])])
	for clave in (coste as Dictionary).keys():
		if not ORDEN_COSTE.has(str(clave)):
			partes.append("%d %s" % [int((coste as Dictionary)[clave]), str(clave)])
	return " · ".join(partes)


func _texto_efecto(tec: Dictionary) -> String:
	# Descripción + tiempo + effects (target/op/path/valor) + legacy_effects en texto.
	var lineas: Array = [str(tec.get("descripcion", ""))]
	if int(tec.get("tiempo", 0)) > 0:
		lineas.append("Investigación: %ds." % int(tec.get("tiempo", 0)))
	var efectos: Variant = tec.get("effects", [])
	if efectos is Array:
		for e in efectos:
			if e is Dictionary:
				lineas.append("• %s %s %s %+d" % [
					str(e.get("target", "efecto")),
					str(e.get("op", "aplica")),
					str(e.get("path", "")),
					int(e.get("value", 0)),
				])
	var legado: Variant = tec.get("legacy", {})
	if legado is Dictionary:
		for clave in (legado as Dictionary).keys():
			if str(clave) == "categoria":
				continue
			lineas.append("• %s: %s" % [str(clave), _valor_texto((legado as Dictionary)[clave])])
	return "\n".join(lineas)


func _valor_texto(v: Variant) -> String:
	# Convierte un valor de legacy_effects a texto legible.
	if v is Array:
		var partes: Array = []
		for x in (v as Array):
			partes.append(str(x))
		return ", ".join(partes)
	if v is bool:
		return "sí" if bool(v) else "no"
	return str(v)


# ---------------------------------------------------------- construcción UI ---

func _limpiar(contenedor: Container) -> void:
	# Vacía un contenedor liberando sus hijos.
	for hijo in contenedor.get_children():
		hijo.queue_free()


func _construir_arbol() -> void:
	# Reconstruye el árbol completo: una sección por edad I-IV y subsecciones por edificio.
	if _contenido == null:
		return
	_limpiar(_contenido)
	var nombre_civ := _nombre_civ()
	var total_vetadas := 0
	for indice_edad in _edades.size():
		var edad: Dictionary = _edades[indice_edad]
		var id_edad := str(edad["id"])
		var de_edad: Array = _tecs.filter(func(t: Dictionary) -> bool: return str(t["edad"]) == id_edad)
		_contenido.add_child(_crear_cabecera_edad(indice_edad, edad, de_edad.size()))
		if de_edad.is_empty():
			_contenido.add_child(_crear_aviso("Sin tecnologías registradas en esta edad."))
			continue
		for edificio in ORDEN_EDIFICIOS:
			var lote: Array = de_edad.filter(func(t: Dictionary) -> bool: return str(t["edificio"]) == str(edificio))
			if lote.is_empty():
				continue
			_contenido.add_child(_crear_cabecera_edificio(edificio, lote.size()))
			var rejilla := GridContainer.new()
			rejilla.columns = 2
			rejilla.add_theme_constant_override("h_separation", 8)
			rejilla.add_theme_constant_override("v_separation", 8)
			rejilla.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_contenido.add_child(rejilla)
			for tec in lote:
				var vetada := _esta_vetada(str(tec["id"]), str(tec["edificio"]))
				if vetada:
					total_vetadas += 1
					if _ocultar_vetadas:
						continue
				rejilla.add_child(_crear_tarjeta(tec, vetada, nombre_civ))
	_actualizar_info(nombre_civ, total_vetadas)


func _actualizar_info(nombre_civ: String, vetadas: int) -> void:
	# Resume el contenido y el filtro activo bajo la barra superior.
	if _info == null:
		return
	if _civs.is_empty():
		_info.text = "%d tecnologías · %d edades · Sin datos de civs (se muestran todas)." % [_tecs.size(), _edades.size()]
	elif _civ_actual == "todas":
		_info.text = "%d tecnologías · %d edades · Civ: todas (%d civs cargadas)." % [_tecs.size(), _edades.size(), _civs.size()]
	else:
		_info.text = "%d tecnologías · %d edades · Civ: %s (%d no disponibles atenuadas)." % [_tecs.size(), _edades.size(), nombre_civ, vetadas]


func _crear_cabecera_edad(indice: int, edad: Dictionary, cantidad: int) -> Control:
	# Franja de edad: "II · Feudal (6) — Coste de avance: 500 comida".
	var numero: String = NUMEROS_EDAD[indice] if indice < NUMEROS_EDAD.size() else "•"
	var texto := "%s · %s (%d)" % [numero, str(edad.get("name", "?")), cantidad]
	var coste: Variant = edad.get("cost", {})
	if coste is Dictionary and not (coste as Dictionary).is_empty():
		texto += " — Avance: " + _texto_coste(coste)
	elif str(edad.get("id", "")) == "alta_edad_media":
		texto += " — Edad inicial"
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", 22)
	etiqueta.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	etiqueta.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	etiqueta.add_theme_constant_override("shadow_offset_x", 2)
	etiqueta.add_theme_constant_override("shadow_offset_y", 2)
	etiqueta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var marco := PanelContainer.new()
	marco.add_theme_stylebox_override("panel", _estilo_seccion())
	marco.add_child(etiqueta)
	return marco


func _crear_cabecera_edificio(edificio: String, cantidad: int) -> Label:
	# Subtítulo de edificio dentro de cada edad: "Herrería (3)".
	var etiqueta := Label.new()
	etiqueta.text = "%s (%d)" % [str(NOMBRES_EDIFICIOS.get(edificio, edificio)), cantidad]
	etiqueta.add_theme_font_size_override("font_size", 17)
	etiqueta.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62))
	return etiqueta


func _crear_aviso(texto: String) -> Label:
	# Mensaje discreto para secciones vacías.
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", 14)
	etiqueta.add_theme_color_override("font_color", Color(0.68, 0.63, 0.55))
	etiqueta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return etiqueta


func _crear_tarjeta(tec: Dictionary, vetada: bool, nombre_civ: String) -> Control:
	# Tarjeta solo lectura: nombre + coste + efecto en texto; vetada queda atenuada.
	var tarjeta := PanelContainer.new()
	tarjeta.add_theme_stylebox_override("panel", _estilo_tarjeta(vetada))
	tarjeta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 4)
	tarjeta.add_child(caja)
	var nombre := Label.new()
	nombre.text = str(tec.get("nombre", "?"))
	nombre.add_theme_font_size_override("font_size", 16)
	nombre.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(nombre)
	var coste := Label.new()
	coste.text = "Coste: " + _texto_coste(tec.get("coste", {}))
	coste.add_theme_font_size_override("font_size", 13)
	coste.add_theme_color_override("font_color", Color(0.82, 0.76, 0.64))
	coste.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(coste)
	var efecto := Label.new()
	efecto.text = _texto_efecto(tec)
	efecto.add_theme_font_size_override("font_size", 13)
	efecto.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76))
	efecto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(efecto)
	if vetada:
		var veto := Label.new()
		veto.text = "✕ NO DISPONIBLE para %s." % nombre_civ
		veto.add_theme_font_size_override("font_size", 13)
		veto.add_theme_color_override("font_color", Color(1.0, 0.40, 0.35))
		veto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caja.add_child(veto)
		tarjeta.modulate = Color(1, 1, 1, 0.25)
		tarjeta.tooltip_text = "No disponible para %s." % nombre_civ
	else:
		tarjeta.tooltip_text = str(tec.get("descripcion", ""))
	return tarjeta


# ---------------------------------------------------------- estilos medievales ---

func _aplicar_estilos_base() -> void:
	# Paleta madera/oro/pergamino sobre el esqueleto del TSCN.
	var fondo := get_node_or_null("Fondo") as ColorRect
	if fondo != null:
		fondo.color = Color(0.07, 0.05, 0.04)
	var titulo := get_node_or_null("Margen/Columna/Titulo") as Label
	if titulo != null:
		titulo.add_theme_font_size_override("font_size", 34)
		titulo.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
		titulo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		titulo.add_theme_constant_override("shadow_offset_x", 2)
		titulo.add_theme_constant_override("shadow_offset_y", 2)
	var subtitulo := get_node_or_null("Margen/Columna/Subtitulo") as Label
	if subtitulo != null:
		subtitulo.add_theme_font_size_override("font_size", 14)
		subtitulo.add_theme_color_override("font_color", Color(0.82, 0.76, 0.64))
	if _volver != null:
		_volver.add_theme_font_size_override("font_size", 16)


func _estilo_seccion() -> StyleBoxFlat:
	# Franja de edad: fondo oscuro con borde dorado fino.
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(0.13, 0.09, 0.06, 0.95)
	caja.border_width_left = 2
	caja.border_width_top = 2
	caja.border_width_right = 2
	caja.border_width_bottom = 2
	caja.border_color = Color(0.72, 0.58, 0.30)
	caja.corner_radius_top_left = 8
	caja.corner_radius_top_right = 8
	caja.corner_radius_bottom_right = 8
	caja.corner_radius_bottom_left = 8
	caja.content_margin_left = 12.0
	caja.content_margin_top = 8.0
	caja.content_margin_right = 12.0
	caja.content_margin_bottom = 8.0
	return caja


func _estilo_tarjeta(vetada: bool) -> StyleBoxFlat:
	# Pergamino oscuro para disponibles; gris apagado con borde rojo para vetadas.
	var caja := StyleBoxFlat.new()
	if vetada:
		caja.bg_color = Color(0.10, 0.09, 0.09, 0.95)
		caja.border_color = Color(0.85, 0.25, 0.20)
	else:
		caja.bg_color = Color(0.16, 0.12, 0.08, 0.97)
		caja.border_color = Color(0.55, 0.44, 0.24)
	caja.border_width_left = 1
	caja.border_width_top = 1
	caja.border_width_right = 1
	caja.border_width_bottom = 1
	caja.corner_radius_top_left = 6
	caja.corner_radius_top_right = 6
	caja.corner_radius_bottom_right = 6
	caja.corner_radius_bottom_left = 6
	caja.content_margin_left = 10.0
	caja.content_margin_top = 8.0
	caja.content_margin_right = 10.0
	caja.content_margin_bottom = 8.0
	return caja

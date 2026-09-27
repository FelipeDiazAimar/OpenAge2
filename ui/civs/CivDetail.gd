extends Control
# CivDetail: ficha medieval a pantalla completa por civilización.
# Lee data/factions/<id>.json, data/units/<unidad>.json y
# mods/aoe2_base/cards/<id>.json. Solo lectura, no modifica nada.
# Uso: instanciar la escena y llamar a set_civ("britones").
# El botón "Ver mazo sugerido" solo emite señal, no implementa nada.

signal mazo_sugerido_pedido(civ_id: String)
signal volver_pedido

const RUTA_FACCION := "res://data/factions/%s.json"
const RUTA_UNIDAD := "res://data/units/%s.json"
const RUTA_CARTAS := "res://mods/aoe2_base/cards/%s.json"

const NOMBRES_EDAD := {
	1: "Edad I — Alta Edad Media",
	2: "Edad II — Feudal",
	3: "Edad III — Castillos",
	4: "Edad IV — Imperial",
}

const ORO := Color(1.0, 0.84, 0.42)
const PERGAMINO := Color(0.85, 0.78, 0.62)
const TEXTO := Color(0.92, 0.87, 0.74)

var _civ_id: String = ""
var _civ_nombre: String = ""

@onready var _titulo: Label = %Titulo
@onready var _subtitulo: Label = %Subtitulo
@onready var _estandarte: ColorRect = %Estandarte
@onready var _sec_bonus: VBoxContainer = %SecBonus
@onready var _sec_unidad: VBoxContainer = %SecUnidad
@onready var _sec_techs: VBoxContainer = %SecTechs
@onready var _lbl_fortalezas: Label = %LblFortalezas
@onready var _lbl_debilidades: Label = %LblDebilidades
@onready var _sec_cartas: VBoxContainer = %SecCartas
@onready var _btn_mazo: Button = %BtnMazo
@onready var _btn_volver: Button = %BtnVolver


func _ready() -> void:
	# Pantalla completa, estilo medieval y botones conectados.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_aplicar_estilo()
	_btn_mazo.pressed.connect(_on_mazo_pulsado)
	_btn_volver.pressed.connect(_on_volver_pulsado)
	if _civ_id != "":
		set_civ(_civ_id)


func set_civ(id_civ: String) -> void:
	# Carga la ficha de la civilización pedida desde los JSON del proyecto.
	_civ_id = id_civ.strip_edges().to_lower()
	if _civ_id == "":
		return
	var faccion: Dictionary = _leer_json(RUTA_FACCION % _civ_id)
	if faccion.is_empty():
		_titulo.text = "Civilización desconocida"
		_subtitulo.text = "No existe data/factions/%s.json" % _civ_id
		return
	_civ_nombre = str(faccion.get("name", _civ_id))
	_titulo.text = _civ_nombre
	_subtitulo.text = "Ficha de civilización · %s" % _civ_id
	_estandarte.color = _color_tejado(str(faccion.get("roof_color", "#8a2a2a")))
	_mostrar_bonus(faccion)
	_mostrar_unidades(faccion)
	_mostrar_techs(faccion)
	_mostrar_analisis(faccion)
	_mostrar_cartas()


func _on_mazo_pulsado() -> void:
	# Solo avisa; el mazo sugerido lo implementa otra pantalla.
	mazo_sugerido_pedido.emit(_civ_id)


func _on_volver_pulsado() -> void:
	# Solo avisa; la navegación la decide quien instancie la ficha.
	volver_pedido.emit()


func _mostrar_bonus(faccion: Dictionary) -> void:
	# Lista cada bonus de la facción más el bonus de equipo.
	_limpiar(_sec_bonus)
	var bonus: Array = faccion.get("bonus", [])
	for b in bonus:
		if b is Dictionary:
			_anadir_linea(_sec_bonus, "• " + str((b as Dictionary).get("descripcion", "")))
	var equipo: Dictionary = faccion.get("team_bonus", {})
	if not equipo.is_empty():
		_anadir_linea(_sec_bonus, "• Equipo: " + str(equipo.get("descripcion", "")))
	if _sec_bonus.get_child_count() == 0:
		_anadir_linea(_sec_bonus, "• Sin bonos registrados.")


func _mostrar_unidades(faccion: Dictionary) -> void:
	# Toma unique_unit de la facción y la completa con data/units si existe.
	_limpiar(_sec_unidad)
	var lista: Array = []
	var uu: Variant = faccion.get("unique_unit", {})
	if uu is Dictionary:
		lista = [uu]
	elif uu is Array:
		lista = uu as Array
	for u in lista:
		if u is Dictionary:
			_anadir_linea(_sec_unidad, _texto_unidad(u as Dictionary))
	if _sec_unidad.get_child_count() == 0:
		_anadir_linea(_sec_unidad, "• Sin unidad única registrada.")


func _mostrar_techs(faccion: Dictionary) -> void:
	# Lista las tecnologías únicas con edad, coste y descripción.
	_limpiar(_sec_techs)
	var techs: Array = faccion.get("unique_techs", [])
	for t in techs:
		if t is Dictionary:
			_anadir_linea(_sec_techs, _texto_tech(t as Dictionary))
	if _sec_techs.get_child_count() == 0:
		_anadir_linea(_sec_techs, "• Sin tecnologías únicas registradas.")


func _mostrar_analisis(faccion: Dictionary) -> void:
	# Fortalezas desde los bonos; debilidades desde lo no disponible.
	var lineas: Array[String] = []
	var bonus: Array = faccion.get("bonus", [])
	for b in bonus:
		if b is Dictionary:
			lineas.append("• " + str((b as Dictionary).get("descripcion", "")))
	var uu: Dictionary = faccion.get("unique_unit", {})
	if not uu.is_empty():
		lineas.append("• Unidad única: " + str(uu.get("name", uu.get("id", ""))))
	_lbl_fortalezas.text = "Fortalezas: apuesta por " + _civ_nombre + " si buscas:\n" + "\n".join(lineas)
	var arbol: Dictionary = faccion.get("tech_tree", {})
	var ausencias: Array = arbol.get("no_disponible_resumen", [])
	var pulidas: Array[String] = []
	for a in ausencias:
		pulidas.append(str(a).replace("_", " "))
	if pulidas.is_empty():
		_lbl_debilidades.text = "Debilidades: árbol casi completo, sin carencias claras."
	else:
		_lbl_debilidades.text = "Debilidades: evita pelear donde falta (" + ", ".join(pulidas) + "). Cubre esos huecos con tus puntos fuertes y con aliados."


func _mostrar_cartas() -> void:
	# Carga las 20 cartas del mod y las agrupa por edad I-IV.
	_limpiar(_sec_cartas)
	var cartas: Array = _leer_lista(RUTA_CARTAS % _civ_id)
	if cartas.is_empty():
		_anadir_linea(_sec_cartas, "• Sin cartas en mods/aoe2_base/cards/%s.json." % _civ_id)
		return
	var por_edad := {1: [], 2: [], 3: [], 4: []}
	for c in cartas:
		if c is Dictionary:
			var edad: int = int((c as Dictionary).get("age", 1))
			if not por_edad.has(edad):
				por_edad[edad] = []
			(por_edad[edad] as Array).append(c)
	for edad in [1, 2, 3, 4]:
		var grupo: Array = por_edad[edad]
		_anadir_cabecera(_sec_cartas, "%s (%d)" % [str(NOMBRES_EDAD[edad]), grupo.size()])
		for c in grupo:
			_anadir_linea(_sec_cartas, _texto_carta(c as Dictionary))


func _texto_unidad(uu: Dictionary) -> String:
	# Combina la ficha de la facción con data/units/<id>.json si existe.
	var base: Dictionary = _leer_json(RUTA_UNIDAD % str(uu.get("id", "")))
	var nombre: String = str(uu.get("name", base.get("name", uu.get("id", "Unidad"))))
	var hp: String = str(uu.get("hp", base.get("hp", "?")))
	var ataque: String = str(uu.get("attack", base.get("attack", "?")))
	var alcance: String = str(uu.get("range", base.get("range", "—")))
	var am: String = str(uu.get("armor_melee", base.get("armor_melee", "?")))
	var ap: String = str(uu.get("armor_pierce", base.get("armor_pierce", "?")))
	var coste: String = _texto_coste(_mezclar_costes(base, uu))
	var tiempo: String = str(uu.get("train_time_sec", base.get("train_time_sec", "?")))
	var entrena: String = str(uu.get("trained_at", base.get("trained_at", "castillo")))
	var texto: String = "• %s — HP %s · Ataque %s · Alcance %s · Armadura %s/%s · %s · %ss en %s" % [nombre, hp, ataque, alcance, am, ap, coste, tiempo, entrena]
	if uu.has("hp_elite") or uu.has("attack_elite"):
		texto += " · Élite: HP %s, ataque %s" % [str(uu.get("hp_elite", "?")), str(uu.get("attack_elite", "?"))]
	var extra: Dictionary = base.get("bonus_vs", {})
	if not extra.is_empty():
		var partes: Array[String] = []
		for k in extra.keys():
			partes.append("%s +%s" % [str(k).replace("_", " "), str(extra[k])])
		texto += " · Bonus: " + ", ".join(partes)
	return texto


func _texto_tech(tech: Dictionary) -> String:
	# Una línea por tecnología: nombre, edad, coste y efecto.
	var nombre: String = str(tech.get("nombre", tech.get("id", "Tecnología")))
	var edad: String = str(tech.get("edad", "—"))
	var coste: String = _texto_coste(tech.get("coste", {}))
	var desc: String = str(tech.get("descripcion", ""))
	return "• %s (%s) — %s. %s" % [nombre, edad, coste, desc]


func _texto_carta(carta: Dictionary) -> String:
	# Una línea por carta: nombre, tipo, rareza y descripción.
	var nombre: String = str(carta.get("name", carta.get("id", "Carta")))
	var tipo: String = str(carta.get("type", "—"))
	var rareza: String = str(carta.get("rarity", "común"))
	var desc: String = str(carta.get("desc", ""))
	return "• %s [%s, %s] — %s" % [nombre, tipo, rareza, desc]


func _texto_coste(coste: Variant) -> String:
	# Acepta claves en inglés (wood/food/gold/stone) o español.
	if not (coste is Dictionary):
		return "sin coste"
	var c: Dictionary = coste as Dictionary
	var partes: Array[String] = []
	_agregar_coste(partes, c, ["food", "alimento"], "A")
	_agregar_coste(partes, c, ["wood", "madera"], "M")
	_agregar_coste(partes, c, ["gold", "oro"], "O")
	_agregar_coste(partes, c, ["stone", "piedra"], "P")
	if partes.is_empty():
		return "sin coste"
	return "Coste " + " ".join(partes)


func _agregar_coste(partes: Array[String], c: Dictionary, claves: Array, letra: String) -> void:
	# Suma la primera clave presente para no duplicar idiomas.
	for k in claves:
		if c.has(k) and float(c[k]) > 0.0:
			partes.append("%d%s" % [int(float(c[k])), letra])
			return


func _mezclar_costes(base: Dictionary, uu: Dictionary) -> Dictionary:
	# Prefiere el coste de la facción; si falta, usa el de data/units.
	if uu.has("cost") and uu["cost"] is Dictionary:
		return uu["cost"] as Dictionary
	if base.has("cost") and base["cost"] is Dictionary:
		return base["cost"] as Dictionary
	return {}


func _leer_json(ruta: String) -> Dictionary:
	# Lee un JSON objeto; devuelve {} si falta o está roto.
	if not FileAccess.file_exists(ruta):
		return {}
	var texto: String = FileAccess.get_file_as_string(ruta)
	var datos: Variant = JSON.parse_string(texto)
	if datos is Dictionary:
		return datos as Dictionary
	return {}


func _leer_lista(ruta: String) -> Array:
	# Lee un JSON lista (las cartas del mod); [] si falta o está roto.
	if not FileAccess.file_exists(ruta):
		return []
	var texto: String = FileAccess.get_file_as_string(ruta)
	var datos: Variant = JSON.parse_string(texto)
	if datos is Array:
		return datos as Array
	return []


func _color_tejado(hex: String) -> Color:
	# Tiñe el estandarte con el roof_color de la facción.
	var limpio: String = hex.strip_edges()
	if limpio.is_valid_html_color():
		return Color.html(limpio)
	return Color(0.54, 0.16, 0.16)


func _limpiar(nodo: Container) -> void:
	# Vacía una sección antes de rellenarla con la nueva civ.
	for hijo in nodo.get_children():
		hijo.queue_free()


func _anadir_linea(padre: Container, texto: String) -> void:
	# Etiqueta pergamino con ajuste de línea para listas largas.
	var lbl := Label.new()
	lbl.text = texto
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", TEXTO)
	padre.add_child(lbl)


func _anadir_cabecera(padre: Container, texto: String) -> void:
	# Cabecera dorada que agrupa las cartas de cada edad.
	var lbl := Label.new()
	lbl.text = texto
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", ORO)
	padre.add_child(lbl)


func _aplicar_estilo() -> void:
	# Paleta medieval procedural: fondo oscuro, marco madera y botones.
	var fondo := get_node_or_null("Fondo") as ColorRect
	if fondo != null:
		fondo.color = Color(0.07, 0.05, 0.04)
	var marco := get_node_or_null("Margen/Columna/Contenido") as ScrollContainer
	if marco != null:
		var caja := StyleBoxFlat.new()
		caja.bg_color = Color(0.13, 0.09, 0.06, 0.95)
		caja.border_width_left = 3
		caja.border_width_top = 3
		caja.border_width_right = 3
		caja.border_width_bottom = 3
		caja.border_color = Color(0.72, 0.58, 0.30)
		caja.corner_radius_top_left = 10
		caja.corner_radius_top_right = 10
		caja.corner_radius_bottom_right = 10
		caja.corner_radius_bottom_left = 10
		marco.add_theme_stylebox_override("panel", caja)
	_titulo.add_theme_color_override("font_color", ORO)
	_titulo.add_theme_font_size_override("font_size", 40)
	_subtitulo.add_theme_color_override("font_color", PERGAMINO)
	_subtitulo.add_theme_font_size_override("font_size", 16)
	for seccion in get_tree().get_nodes_in_group("civ_seccion"):
		if seccion is Label:
			(seccion as Label).add_theme_color_override("font_color", ORO)
			(seccion as Label).add_theme_font_size_override("font_size", 20)
	_estilizar_boton(_btn_mazo)
	_estilizar_boton(_btn_volver)


func _estilizar_boton(btn: Button) -> void:
	# Botón madera con borde hierro, coherente con el menú principal.
	btn.custom_minimum_size = Vector2(240, 48)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.70))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.30, 0.20, 0.12)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(0.25, 0.26, 0.29)
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_right = 8
	normal.corner_radius_bottom_left = 8
	btn.add_theme_stylebox_override("normal", normal)
	var encima := normal.duplicate() as StyleBoxFlat
	encima.border_color = ORO
	encima.bg_color = Color(0.45, 0.31, 0.16)
	btn.add_theme_stylebox_override("hover", encima)
	btn.add_theme_stylebox_override("focus", encima)
	var pulsado := normal.duplicate() as StyleBoxFlat
	pulsado.bg_color = Color(0.19, 0.12, 0.07)
	btn.add_theme_stylebox_override("pressed", pulsado)

extends Control
# Galería de civilizaciones: parrilla con scroll, pros/contras claros,
# selección simple (detalle) o doble (comparar). Todo construido en código.
# Lee data/factions/*.json (ventajas, debilidades, unique_unit) y cuenta
# cartas de mods/aoe2_base/cards/*.json. Emite civ_picked(civ).

signal civ_picked(civ: String)

const FACTIONS_DIR := "res://mods/aoe2_base/cards"
const CIVS_DIR := "res://data/factions"
const ORO := Color(1.0, 0.84, 0.42)
const VERDE := Color(0.45, 0.9, 0.45)
const ROJO := Color(1.0, 0.45, 0.42)
const PERGAMINO := Color(0.82, 0.76, 0.64)
const RUTA_MENU := "res://ui/menus/MainMenu.tscn"

var _civs: Array = []
var _propias := {}
var _neutrales := 0
var _sel: Array[String] = []
var _grid: GridContainer
var _lado_der: VBoxContainer
var _pista: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_cargar_civs()
	_contar_cartas()
	_construir()
	_actualizar_lado()


func _cargar_civs() -> void:
	# id, nombre, color, bonus, ventajas, debilidades, unique_unit.
	_civs.clear()
	var dir := DirAccess.open(CIVS_DIR)
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
		var texto := FileAccess.get_file_as_string(CIVS_DIR + "/" + nombre)
		if texto.strip_edges().is_empty():
			continue
		var d: Variant = JSON.parse_string(texto)
		if not (d is Dictionary):
			continue
		_civs.append({
			"id": str(d.get("id", nombre.get_basename())),
			"nombre": str(d.get("name", d.get("id", "?"))),
			"color": str(d.get("roof_color", d.get("color", "#73706a"))),
			"bonus": d.get("bonus", []),
			"ventajas": d.get("ventajas", []),
			"debilidades": d.get("debilidades", []),
			"unique": d.get("unique_unit", {}),
		})
	_civs.sort_custom(func(a: Variant, b: Variant) -> bool: return str((a as Dictionary)["nombre"]) < str((b as Dictionary)["nombre"]))


func _contar_cartas() -> void:
	# Propias por civ + neutrales utilizables por todas.
	_propias.clear()
	_neutrales = 0
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
		var datos: Variant = JSON.parse_string(FileAccess.get_file_as_string(FACTIONS_DIR + "/" + nombre))
		var lista: Array = []
		if datos is Array:
			lista = datos
		elif datos is Dictionary:
			lista = [datos]
		for c in lista:
			if not (c is Dictionary):
				continue
			var cciv := str((c as Dictionary).get("civ", "")).strip_edges().to_lower()
			if cciv == "" or cciv == "todas" or cciv == "neutral" or cciv == "neutrales":
				_neutrales += 1
			else:
				_propias[cciv] = int(_propias.get(cciv, 0)) + 1


func _construir() -> void:
	# Fondo oscuro + barra superior + dos columnas con scroll.
	var fondo := ColorRect.new()
	fondo.color = Color(0.07, 0.05, 0.04)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)
	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	margen.add_theme_constant_override("margin_left", 14)
	margen.add_theme_constant_override("margin_top", 10)
	margen.add_theme_constant_override("margin_right", 14)
	margen.add_theme_constant_override("margin_bottom", 10)
	add_child(margen)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 8)
	margen.add_child(caja)
	var barra := HBoxContainer.new()
	barra.add_theme_constant_override("separation", 12)
	caja.add_child(barra)
	var titulo := Label.new()
	titulo.text = "CIVILIZACIONES"
	titulo.add_theme_font_size_override("font_size", 30)
	titulo.add_theme_color_override("font_color", ORO)
	barra.add_child(titulo)
	_pista = Label.new()
	_pista.text = "Pulsa 1 para ver detalle · 2 para comparar"
	_pista.add_theme_font_size_override("font_size", 14)
	_pista.add_theme_color_override("font_color", PERGAMINO)
	_pista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	barra.add_child(_pista)
	var volver := Button.new()
	volver.text = "VOLVER"
	volver.custom_minimum_size = Vector2(140, 40)
	volver.pressed.connect(_on_volver)
	barra.add_child(volver)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(cols)
	var scroll_izq := ScrollContainer.new()
	scroll_izq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_izq.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(scroll_izq)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_izq.add_child(_grid)
	for civ in _civs:
		_grid.add_child(_tarjeta(civ))
	var marco_der := PanelContainer.new()
	marco_der.custom_minimum_size = Vector2(430, 0)
	marco_der.add_theme_stylebox_override("panel", _marco())
	cols.add_child(marco_der)
	var scroll_der := ScrollContainer.new()
	scroll_der.size_flags_vertical = Control.SIZE_EXPAND_FILL
	marco_der.add_child(scroll_der)
	_lado_der = VBoxContainer.new()
	_lado_der.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lado_der.add_theme_constant_override("separation", 8)
	scroll_der.add_child(_lado_der)


func _marco(borde: Color = ORO) -> StyleBoxFlat:
	var m := StyleBoxFlat.new()
	m.bg_color = Color(0.13, 0.09, 0.06, 0.96)
	m.set_border_width_all(2)
	m.border_color = borde
	m.set_corner_radius_all(8)
	return m


func _tarjeta(civ: Dictionary) -> PanelContainer:
	# Compacta: emblema + nombre + 3 pros + 2 contras + UU + cartas. Clic alterna.
	var id := str(civ.get("id", ""))
	var color := Color.html(str(civ.get("color", "#73706a")))
	var t := PanelContainer.new()
	t.name = "Civ_" + id
	t.set_meta("civ", id)
	t.custom_minimum_size = Vector2(300, 0)
	t.add_theme_stylebox_override("panel", _marco(color if not _sel.has(id) else ORO))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_bottom", 8)
	t.add_child(m)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 4)
	m.add_child(caja)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 10)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(fila)
	var emb := TextureRect.new()
	emb.texture = CivEmblems.emblem(id, 56)
	emb.custom_minimum_size = Vector2(56, 56)
	emb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(emb)
	var nom := Label.new()
	nom.text = str(civ.get("nombre", id))
	nom.add_theme_font_size_override("font_size", 22)
	nom.add_theme_color_override("font_color", color.lightened(0.35))
	nom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(nom)
	for v in _primeros(civ.get("ventajas", []), 3):
		caja.add_child(_linea("✔ " + str(v), VERDE, 13))
	for w in _primeros(civ.get("debilidades", []), 2):
		caja.add_child(_linea("✕ " + str(w), ROJO, 13))
	var uu: Dictionary = civ.get("unique", {})
	var pie := Label.new()
	var txt_uu := str(uu.get("name", uu.get("id", "?"))) if not uu.is_empty() else "?"
	var propias := int(_propias.get(id.to_lower(), 0))
	pie.text = "UU: %s · %d cartas" % [txt_uu, propias]
	pie.add_theme_font_size_override("font_size", 12)
	pie.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	pie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_child(pie)
	t.gui_input.connect(_on_tarjeta.bind(id))
	return t


func _primeros(v: Variant, n: int) -> Array:
	var salida: Array = []
	if v is Array:
		for x in (v as Array):
			if salida.size() >= n:
				break
			salida.append(x)
	return salida


func _linea(texto: String, color: Color, tam: int) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _on_tarjeta(evento: InputEvent, id: String) -> void:
	if evento is InputEventMouseButton:
		var r := evento as InputEventMouseButton
		if r.button_index == MOUSE_BUTTON_LEFT and r.pressed:
			_alternar(id)


func _alternar(id: String) -> void:
	# Máximo 2: la tercera sustituye a la más antigua.
	if _sel.has(id):
		_sel.erase(id)
	elif _sel.size() >= 2:
		_sel.pop_front()
		_sel.append(id)
	else:
		_sel.append(id)
	if _sel.size() == 1:
		civ_picked.emit(_sel[0])
	_refrescar_bordes()
	_actualizar_lado()


func _refrescar_bordes() -> void:
	if _grid == null:
		return
	for t in _grid.get_children():
		if t is PanelContainer and (t as PanelContainer).has_meta("civ"):
			var id := str((t as PanelContainer).get_meta("civ"))
			var civ := _buscar(id)
			var color := Color.html(str(civ.get("color", "#73706a")))
			(t as PanelContainer).add_theme_stylebox_override("panel", _marco(ORO if _sel.has(id) else color))


func _actualizar_lado() -> void:
	for h in _lado_der.get_children():
		h.queue_free()
	if _sel.is_empty():
		_lado_der.add_child(_linea("Pulsa una civilización para ver su detalle, o dos para compararlas.", PERGAMINO, 15))
		_pista.text = "Pulsa 1 para ver detalle · 2 para comparar"
		return
	if _sel.size() == 1:
		_detalle(_buscar(_sel[0]))
		_pista.text = "1 elegida: %s · pulsa otra para comparar" % str(_buscar(_sel[0]).get("nombre", "?"))
	else:
		_comparar(_buscar(_sel[0]), _buscar(_sel[1]))
		_pista.text = "Comparando: %s vs %s" % [str(_buscar(_sel[0]).get("nombre", "?")), str(_buscar(_sel[1]).get("nombre", "?"))]


func _detalle(civ: Dictionary) -> void:
	# Ficha completa: bonus, UU con stats, cartas.
	if civ.is_empty():
		return
	var color := Color.html(str(civ.get("color", "#73706a")))
	var tit := Label.new()
	tit.text = str(civ.get("nombre", "?"))
	tit.add_theme_font_size_override("font_size", 26)
	tit.add_theme_color_override("font_color", color.lightened(0.35))
	_lado_der.add_child(tit)
	_lado_der.add_child(_linea("VENTAJAS", ORO, 14))
	for v in (civ.get("ventajas", []) as Array):
		_lado_der.add_child(_linea("✔ " + str(v), VERDE, 14))
	_lado_der.add_child(_linea("DEBILIDADES", ORO, 14))
	for w in (civ.get("debilidades", []) as Array):
		_lado_der.add_child(_linea("✕ " + str(w), ROJO, 14))
	_lado_der.add_child(_linea("BONUS COMPLETOS", ORO, 14))
	for b in (civ.get("bonus", []) as Array):
		_lado_der.add_child(_linea("• " + str(b), PERGAMINO, 13))
	var uu: Dictionary = civ.get("unique", {})
	if not uu.is_empty():
		_lado_der.add_child(_linea("UNIDAD ÚNICA", ORO, 14))
		_lado_der.add_child(_linea("%s · HP %s · ATK %s · %s" % [
			str(uu.get("name", uu.get("id", "?"))), str(uu.get("hp", "?")),
			str(uu.get("attack", "?")), _coste_corto(uu.get("cost", {}))], PERGAMINO, 14))
	var propias := int(_propias.get(str(civ.get("id", "")).to_lower(), 0))
	_lado_der.add_child(_linea("Cartas: %d propias + %d neutrales" % [propias, _neutrales], Color(0.95, 0.90, 0.78), 14))


func _comparar(a: Dictionary, b: Dictionary) -> void:
	# Tres columnas flexibles (título | A | B): los textos envuelven normal,
	# sin el colapso de la rejilla que los ponía en vertical.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	_lado_der.add_child(cols)
	var col_tit := _columna_comp(cols, "")
	var col_a := _columna_comp(cols, str(a.get("nombre", "?")), Color.html(str(a.get("color", "#73706a"))).lightened(0.35))
	var col_b := _columna_comp(cols, str(b.get("nombre", "?")), Color.html(str(b.get("color", "#73706a"))).lightened(0.35))
	_fila_comp(col_tit, col_a, col_b, "Ventajas",
		_bullets(a.get("ventajas", []), "✔ "), _bullets(b.get("ventajas", []), "✔ "), VERDE)
	_fila_comp(col_tit, col_a, col_b, "Debilidades",
		_bullets(a.get("debilidades", []), "✕ "), _bullets(b.get("debilidades", []), "✕ "), ROJO)
	_fila_comp(col_tit, col_a, col_b, "UU",
		_uu_corto(a.get("unique", {})), _uu_corto(b.get("unique", {})), PERGAMINO)
	_fila_comp(col_tit, col_a, col_b, "Cartas",
		str(int(_propias.get(str(a.get("id", "")).to_lower(), 0))),
		str(int(_propias.get(str(b.get("id", "")).to_lower(), 0))), PERGAMINO)


func _columna_comp(padre: Container, titulo: String, color_tit: Color = PERGAMINO) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	padre.add_child(col)
	if not titulo.is_empty():
		var t := _linea(titulo, color_tit, 16)
		col.add_child(t)
	return col


func _fila_comp(col_tit: VBoxContainer, col_a: VBoxContainer, col_b: VBoxContainer, titulo: String, va: String, vb: String, color: Color) -> void:
	col_tit.add_child(_linea(titulo, ORO, 13))
	col_a.add_child(_linea(va if not va.is_empty() else "—", color, 13))
	col_b.add_child(_linea(vb if not vb.is_empty() else "—", color, 13))


func _bullets(v: Variant, marca: String) -> String:
	var partes: Array[String] = []
	if v is Array:
		for x in (v as Array):
			partes.append(marca + str(x))
	return "\n".join(partes)


func _uu_corto(uu: Variant) -> String:
	if not (uu is Dictionary) or (uu as Dictionary).is_empty():
		return "—"
	var u: Dictionary = uu
	return "%s (HP %s/ATK %s)" % [str(u.get("name", u.get("id", "?"))), str(u.get("hp", "?")), str(u.get("attack", "?"))]


func _coste_corto(coste: Variant) -> String:
	if not (coste is Dictionary) or (coste as Dictionary).is_empty():
		return "sin coste"
	var partes: Array[String] = []
	for k in (coste as Dictionary).keys():
		partes.append("%s %s" % [str((coste as Dictionary)[k]), str(k)])
	return ", ".join(partes)


func _buscar(id: String) -> Dictionary:
	for civ in _civs:
		if str((civ as Dictionary).get("id", "")).to_lower() == id.to_lower():
			return civ
	return {}


func _on_volver() -> void:
	if ResourceLoader.exists(RUTA_MENU):
		get_tree().change_scene_to_file(RUTA_MENU)

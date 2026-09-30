extends Control
# DeckBuilder: constructor de barajas estilo Age 3 (Godot 4.4).
# Izquierda: mazos guardados + crear/guardar/borrar/copiar + filtro por edad.
# Centro: baraja actual en filas I-IV con contador TAMAÑO N/25 + LIMPIAR.
# Abajo/derecha: inventario en filas I-IV; clic añade, clic en baraja quita.
# Usa game/cards/Deck.gd, DeckValidator.gd y ui/decks/CardWidget (tscn o gd).

const DeckScript := preload("res://game/cards/Deck.gd")
const Validador := preload("res://game/cards/DeckValidator.gd")

const RUTA_MENU := "res://ui/menus/MainMenu.tscn"
const RUTA_WIDGET_TSCN := "res://ui/decks/CardWidget.tscn"
const RUTA_WIDGET_GD := "res://ui/decks/CardWidget.gd"

const MAX_CARTAS := 25
const COLUMNAS_REJILLA := 8
const PAGE_SIZE := 96 # 8 cols x 12 filas: nunca 900 nodos de golpe.

var _civ: String = "britones"
var _mazo = null
var _todas: Array = []
var _filtro_edad: int = 0
var _texto_busqueda: String = ""
var _pagina: int = 0
var _listo: bool = false
var _civs_disponibles: Array = []
var _filtro_civ: String = ""
var _buscador_civ: LineEdit = null
var _lista_civs: ItemList = null
var _bonus_civ: Label = null
# Arrastre manual (drag & drop sin la API de Godot, más predecible).
var _arrastrando_desde := Vector2.ZERO
var _arrastrando: Dictionary = {}
var _fantasma: PanelContainer = null
var _widget_escena: PackedScene = null
var _widget_script: Script = null
var _card_art: Script = null

@onready var _titulo: Label = $MainMargin/MainVBox/TopBar/TopHBox/TitleLabel
@onready var _etiqueta_civ: Label = $MainMargin/MainVBox/TopBar/TopHBox/CivLabel
@onready var _etiqueta_cuenta: Label = $MainMargin/MainVBox/TopBar/TopHBox/CountLabel
@onready var _boton_limpiar: Button = $MainMargin/MainVBox/TopBar/TopHBox/ClearButton
@onready var _boton_volver: Button = $MainMargin/MainVBox/TopBar/TopHBox/BackButton
@onready var _lista_mazos: ItemList = $MainMargin/MainVBox/Columns/LeftPanel/LeftVBox/DecksList
@onready var _boton_crear: Button = $MainMargin/MainVBox/Columns/LeftPanel/LeftVBox/CreateButton
@onready var _boton_guardar: Button = $MainMargin/MainVBox/Columns/LeftPanel/LeftVBox/SaveButton
@onready var _boton_borrar: Button = $MainMargin/MainVBox/Columns/LeftPanel/LeftVBox/DeleteButton
@onready var _boton_copiar: Button = $MainMargin/MainVBox/Columns/LeftPanel/LeftVBox/CopyButton
@onready var _opt_edad: OptionButton = $MainMargin/MainVBox/Columns/LeftPanel/LeftVBox/AgeOption
@onready var _buscador: LineEdit = $MainMargin/MainVBox/Columns/LeftPanel/LeftVBox/SearchEdit
@onready var _nombre_mazo: LineEdit = $MainMargin/MainVBox/Columns/CenterPanel/CenterVBox/DeckNameEdit
@onready var _filas_mazo: VBoxContainer = $MainMargin/MainVBox/Columns/CenterPanel/CenterVBox/DeckScroll/DeckRows
@onready var _scroll_mazo: ScrollContainer = $MainMargin/MainVBox/Columns/CenterPanel/CenterVBox/DeckScroll
@onready var _scroll_inv: ScrollContainer = $MainMargin/MainVBox/Columns/InventoryPanel/InvVBox/InvScroll
@onready var _estado: Label = $MainMargin/MainVBox/Columns/CenterPanel/CenterVBox/StatusLabel
@onready var _errores_fijo: Label = $MainMargin/MainVBox/Columns/CenterPanel/CenterVBox/ErrorsLabel
@onready var _filas_inv: VBoxContainer = $MainMargin/MainVBox/Columns/InventoryPanel/InvVBox/InvScroll/InvRows


func set_civ(civ_nueva: String) -> void:
	# Recibe la civ desde fuera (antes o despues de _ready).
	var limpia: String = civ_nueva.strip_edges().to_lower()
	if limpia.is_empty():
		return
	_civ = limpia
	_pagina = 0
	if not _listo:
		return
	_nuevo_mazo(false)
	_actualizar_bonus_civ()


func set_available_civs(civs: Array) -> void:
	_civs_disponibles.clear()
	for v in civs:
		_civs_disponibles.append(str(v).strip_edges().to_lower())
	_civs_disponibles.sort()
	_refrescar_lista_civs()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(RUTA_WIDGET_TSCN):
		_widget_escena = load(RUTA_WIDGET_TSCN) as PackedScene
	if ResourceLoader.exists(RUTA_WIDGET_GD):
		_widget_script = load(RUTA_WIDGET_GD) as Script
	if ResourceLoader.exists("res://ui/decks/CardArt.gd"):
		_card_art = load("res://ui/decks/CardArt.gd") as Script
	_todas = Validador.load_all_cards()
	if _mazo == null:
		_mazo = DeckScript.new()
		_mazo.civ = _civ
	_opt_edad.clear()
	_opt_edad.add_item("Todas las edades", 0)
	_opt_edad.add_item("Edad I", 1)
	_opt_edad.add_item("Edad II", 2)
	_opt_edad.add_item("Edad III", 3)
	_opt_edad.add_item("Edad IV", 4)
	_opt_edad.selected = 0
	_buscador.text_changed.connect(_on_buscar)
	_opt_edad.item_selected.connect(_on_edad)
	_boton_limpiar.pressed.connect(_on_limpiar)
	_boton_volver.pressed.connect(_on_volver)
	_boton_crear.pressed.connect(_on_nuevo)
	_boton_guardar.pressed.connect(_on_guardar)
	_boton_borrar.pressed.connect(_on_borrar)
	_boton_copiar.pressed.connect(_on_copiar)
	_lista_mazos.item_selected.connect(_on_mazo_elegido)
	_listo = true
	_nuevo_mazo(false)
	_asegurar_picker_civ()
	if _civs_disponibles.is_empty():
		_civs_disponibles = _civs_auto()
	_refrescar_lista_civs()


func _nuevo_mazo(limpiar: bool) -> void:
	# (Re)inicia el editor para la civ actual.
	if _mazo == null:
		_mazo = DeckScript.new()
	_mazo.civ = _civ
	if limpiar:
		_mazo.card_ids.clear()
	_etiqueta_civ.text = "Civ: %s" % _civ
	_refrescar_todo()
	_estado.text = "Mazo nuevo para %s: pulsa cartas del inventario." % _civ


func _refrescar_todo() -> void:
	_refrescar_inventario()
	_refrescar_mazo()
	_refrescar_lista_mazos()
	_validar_en_vivo()


func _cartas_civ() -> Array:
	# Cartas jugables por la civ actual (propias + neutrales).
	var salida: Array = []
	for c in Validador.cards_for_civ(_todas, _civ):
		if c is Dictionary:
			salida.append(c)
	return salida


func _filtradas() -> Array:
	# Inventario con filtro de edad y búsqueda.
	var salida: Array = []
	for c in _cartas_civ():
		if _filtro_edad >= 1 and int(c.get("age", 0)) != _filtro_edad:
			continue
		if not _texto_busqueda.is_empty() and not _texto_busqueda in str(c.get("name", "")).to_lower():
			continue
		salida.append(c)
	return salida


func _por_edad(cartas: Array) -> Dictionary:
	# Agrupa fichas por edad 1-4 (ordenadas por id dentro de cada edad).
	var grupos := {1: [], 2: [], 3: [], 4: []}
	for c in cartas:
		var e: int = clampi(int((c as Dictionary).get("age", 1)), 1, 4)
		(grupos[e] as Array).append(c)
	for e in grupos:
		(grupos[e] as Array).sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return grupos


func _limpiar(nodo: Node) -> void:
	for h in nodo.get_children():
		h.queue_free()


func _fila_edad(padre: VBoxContainer, edad: int, cartas: Array, en_mazo: bool) -> void:
	# Fila estilo Age 3: número romano + rejilla de losetas cuadradas.
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	padre.add_child(fila)
	var rom := Label.new()
	rom.text = _romano(edad)
	rom.custom_minimum_size = Vector2(30, 0)
	rom.add_theme_font_size_override("font_size", 22)
	rom.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	fila.add_child(rom)
	var rejilla := GridContainer.new()
	rejilla.columns = COLUMNAS_REJILLA
	rejilla.add_theme_constant_override("h_separation", 6)
	rejilla.add_theme_constant_override("v_separation", 6)
	rejilla.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(rejilla)
	if cartas.is_empty():
		var vacio := Label.new()
		vacio.text = "—"
		vacio.add_theme_color_override("font_color", Color(0.5, 0.48, 0.44))
		rejilla.add_child(vacio)
		return
	for carta in cartas:
		rejilla.add_child(_loseta(carta, en_mazo))


func _loseta(carta: Dictionary, en_mazo: bool) -> Control:
	# CardWidget si existe; si no, botón cuadrado de respaldo.
	var w: Control = null
	if _widget_escena != null:
		w = _widget_escena.instantiate() as Control
	elif _widget_script != null:
		var obj: Variant = _widget_script.new()
		if obj is Control:
			w = obj as Control
	if w == null:
		var b := Button.new()
		b.text = str(carta.get("name", "?")).left(12)
		b.tooltip_text = str(carta.get("desc", ""))
		b.custom_minimum_size = Vector2(72, 72)
		w = b
	w.set_meta("card_id", str(carta.get("id", "")))
	if w.has_method("setup"):
		w.call("setup", carta)
	if w.has_signal("picked"):
		if not w.is_connected("picked", _on_loseta):
			w.connect("picked", _on_loseta.bind(en_mazo))
	elif w is BaseButton:
		if en_mazo:
			(w as BaseButton).pressed.connect(_on_quitar.bind(str(carta.get("id", ""))))
		else:
			(w as BaseButton).pressed.connect(_on_anadir.bind(carta))
	if w.has_method("set_selected"):
		w.call("set_selected", _mazo.card_ids.has(str(carta.get("id", ""))))
	return w


func _on_loseta(id_carta: Variant, en_mazo: bool) -> void:
	# Signal picked(card_id, en_mazo): en baraja quita, en inventario añade.
	var cid := str(id_carta)
	if en_mazo:
		_on_quitar(cid)
		return
	for c in _cartas_civ():
		if str(c.get("id", "")) == cid:
			_on_anadir(c)
			return


func _refrescar_inventario() -> void:
	_limpiar(_filas_inv)
	var todo := _filtradas()
	var pags := maxi(1, int(ceil(todo.size() / float(PAGE_SIZE))))
	_pagina = clampi(_pagina, 0, pags - 1)
	var grupos := _por_edad(todo.slice(_pagina * PAGE_SIZE, _pagina * PAGE_SIZE + PAGE_SIZE))
	var hay := false
	for e in [1, 2, 3, 4]:
		if (grupos[e] as Array).is_empty():
			continue
		hay = true
		_fila_edad(_filas_inv, e, grupos[e], false)
	if not hay:
		var l := Label.new(); l.text = "Sin cartas para este filtro."; _filas_inv.add_child(l); return
	if pags > 1:
		var bar := HBoxContainer.new(); var a := Button.new(); var n := Button.new(); var t := Label.new()
		a.text = "◀"; a.disabled = _pagina == 0; a.pressed.connect(func(): _pagina -= 1; _refrescar_inventario())
		t.text = "Pág %d/%d (%d)" % [_pagina + 1, pags, todo.size()]
		n.text = "▶"; n.disabled = _pagina >= pags - 1; n.pressed.connect(func(): _pagina += 1; _refrescar_inventario())
		bar.add_child(a); bar.add_child(t); bar.add_child(n); _filas_inv.add_child(bar); _scroll_inv.scroll_vertical = 0


func _refrescar_mazo() -> void:
	_limpiar(_filas_mazo)
	var fichas: Array = []
	for cid in _mazo.card_ids:
		for c in _todas:
			if c is Dictionary and str((c as Dictionary).get("id", "")) == str(cid):
				fichas.append(c)
				break
	if fichas.is_empty():
		var ayuda := Label.new()
		ayuda.text = "⬇ Baraja vacía: arrastra aquí tu primera carta o pulsa en el inventario."
		ayuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ayuda.add_theme_color_override("font_color", Color(0.75, 0.70, 0.60))
		_filas_mazo.add_child(ayuda)
		return
	var grupos := _por_edad(fichas)
	for e in [1, 2, 3, 4]:
		if (grupos[e] as Array).is_empty():
			continue
		_fila_edad(_filas_mazo, e, grupos[e], true)


func _on_anadir(carta: Dictionary) -> void:
	var motivo: String = _mazo.add_card(str(carta.get("id", "")))
	if motivo.is_empty():
		_estado.text = "Añadida: %s (%d/%d)." % [str(carta.get("name", "?")), _mazo.card_ids.size(), MAX_CARTAS]
	else:
		_estado.text = "No se añade: %s." % motivo
	_refrescar_inventario()
	_refrescar_mazo()
	_validar_en_vivo()


func _on_quitar(id_carta: String) -> void:
	if _mazo.remove_card(id_carta):
		_estado.text = "Quitada (%d/%d)." % [_mazo.card_ids.size(), MAX_CARTAS]
	_refrescar_inventario()
	_refrescar_mazo()
	_validar_en_vivo()


func _on_limpiar() -> void:
	_mazo.card_ids.clear()
	_estado.text = "Baraja vaciada."
	_refrescar_mazo()
	_validar_en_vivo()


func _validar_en_vivo() -> void:
	var fichas: Array = []
	for cid in _mazo.card_ids:
		for c in _todas:
			if c is Dictionary and str((c as Dictionary).get("id", "")) == str(cid):
				fichas.append(c)
				break
	var errores: Array = _mazo.validate(fichas)
	var n: int = _mazo.card_ids.size()
	_etiqueta_cuenta.text = "TAMAÑO: %d / %d" % [n, MAX_CARTAS]
	if errores.is_empty():
		_errores_label().text = "Baraja válida ✔ (%d cartas, puede ir con menos de %d)." % [n, MAX_CARTAS]
		_errores_label().add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	else:
		_errores_label().text = "\n".join(PackedStringArray(errores))
		_errores_label().add_theme_color_override("font_color", Color(1.0, 0.55, 0.50))


func _errores_label() -> Label:
	# Etiqueta de errores bajo las filas del mazo (ya existe en la escena).
	return _errores_fijo


func _on_mazo_elegido(_indice: int) -> void:
	# ItemList pasa el índice; se carga por nombre seleccionado.
	_on_cargar()


func _on_buscar(texto: String) -> void:
	_texto_busqueda = texto.strip_edges().to_lower()
	_pagina = 0
	_refrescar_inventario()


func _on_edad(indice: int) -> void:
	_filtro_edad = _opt_edad.get_item_id(indice)
	_pagina = 0
	_refrescar_inventario()


func _on_guardar() -> void:
	# Guarda con el nombre del campo (los botones viven en el panel izquierdo).
	var nombre: String = _nombre_mazo_actual()
	if nombre.is_empty():
		_estado.text = "Escribe un nombre para guardar (campo bajo la baraja)."
		return
	if _mazo.save(nombre):
		_estado.text = "Guardada: %s (%d/%d)." % [nombre, _mazo.card_ids.size(), MAX_CARTAS]
		_refrescar_lista_mazos()
	else:
		_estado.text = "No se pudo guardar."


func _nombre_mazo_actual() -> String:
	var campo := get_node_or_null("MainMargin/MainVBox/Columns/CenterPanel/CenterVBox/DeckNameEdit") as LineEdit
	if campo == null:
		return "baraja"
	return campo.text.strip_edges()


func _on_nuevo() -> void:
	_mazo = DeckScript.new()
	_mazo.civ = _civ
	_refrescar_mazo()
	_validar_en_vivo()
	_estado.text = "Baraja nueva para %s." % _civ


func _on_borrar() -> void:
	var sel := _mazo_elegido()
	if sel.is_empty():
		_estado.text = "Elige un mazo guardado para borrar."
		return
	var ruta := "user://decks/" + sel
	if sel.ends_with(".json"):
		ruta = "user://decks/" + sel
	else:
		ruta += ".json"
	if FileAccess.file_exists(ruta):
		DirAccess.remove_absolute(ruta)
		_estado.text = "Borrada: %s." % sel
		_refrescar_lista_mazos()
	else:
		_estado.text = "No existe: %s." % sel


func _on_copiar() -> void:
	# Copia la baraja actual con otro nombre (del campo de nombre).
	var nombre := _nombre_mazo_actual()
	if nombre.is_empty():
		nombre = "copia"
	var copia = DeckScript.new()
	copia.civ = _mazo.civ
	copia.card_ids.assign(_mazo.card_ids)
	if copia.save(nombre + " copia"):
		_estado.text = "Copiada como '%s copia'." % nombre
		_refrescar_lista_mazos()
	else:
		_estado.text = "No se pudo copiar."


func _on_cargar() -> void:
	# Carga el mazo elegido de la lista izquierda.
	var sel := _mazo_elegido()
	if sel.is_empty():
		_estado.text = "Elige un mazo guardado."
		return
	var tmp = DeckScript.new()
	if not tmp.load_deck(sel):
		_estado.text = "No se pudo cargar: %s." % sel
		return
	_mazo = tmp
	_civ = str(_mazo.civ)
	_pagina = 0
	_etiqueta_civ.text = "Civ: %s" % _civ
	_refrescar_todo_nombre()
	_refrescar_inventario()
	_refrescar_mazo()
	_validar_en_vivo()
	_estado.text = "Cargada: %s (%d/%d)." % [sel, _mazo.card_ids.size(), MAX_CARTAS]


func _mazo_elegido() -> String:
	var sel: Array = _lista_mazos.get_selected_items()
	if sel.is_empty():
		return ""
	return _lista_mazos.get_item_text(sel[0])


func _refrescar_todo_nombre() -> void:
	var campo := get_node_or_null("MainMargin/MainVBox/Columns/CenterPanel/CenterVBox/DeckNameEdit") as LineEdit
	if campo != null:
		campo.text = _mazo_elegido().trim_suffix(".json")


func _refrescar_lista_mazos() -> void:
	_lista_mazos.clear()
	for n in DeckScript.list_decks():
		_lista_mazos.add_item(str(n))


func _on_volver() -> void:
	if ResourceLoader.exists(RUTA_MENU):
		get_tree().change_scene_to_file(RUTA_MENU)
	else:
		_estado.text = "Falta el menú principal."


func _romano(edad: int) -> String:
	match clampi(edad, 1, 4):
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
		4:
			return "IV"
	return "?"


## Drag & drop: pulsar loseta, arrastrar >10px y soltar en el otro panel.
## Clic simple conserva su comportamiento (lo emite la propia loseta).
func _input(evento: InputEvent) -> void:
	if evento is InputEventMouseButton:
		var r := evento as InputEventMouseButton
		if r.button_index != MOUSE_BUTTON_LEFT:
			return
		if r.pressed:
			var encontrada := _loseta_bajo_raton()
			if not encontrada.is_empty():
				_arrastrando = encontrada
				_arrastrando_desde = get_global_mouse_position()
		else:
			if not _arrastrando.is_empty() and _fantasma != null:
				_soltar_arrastre()
			_arrastrando = {}
	elif evento is InputEventMouseMotion and not _arrastrando.is_empty():
		if _fantasma != null:
			_mover_fantasma()
		elif get_global_mouse_position().distance_to(_arrastrando_desde) > 10.0:
			_crear_fantasma()


func _losetas() -> Array:
	# Todas las losetas con card_id bajo las filas de baraja e inventario.
	var salida: Array = []
	for raiz in [_filas_mazo, _filas_inv]:
		if raiz == null:
			continue
		salida.append_array(_con_meta(raiz))
	return salida


func _con_meta(nodo: Node) -> Array:
	var salida: Array = []
	for h in nodo.get_children():
		if h is Control and (h as Control).has_meta("card_id"):
			salida.append(h)
		salida.append_array(_con_meta(h))
	return salida


func _loseta_bajo_raton() -> Dictionary:
	# Busca loseta bajo el ratón sin precondiciones de zona (la zona se
	# evalúa al soltar, y la baraja vacía no tiene filas que la delimiten).
	var mp := get_global_mouse_position()
	for w in _losetas():
		var c := w as Control
		if c != null and c.visible and c.get_global_rect().has_point(mp):
			var en_mazo := _dentro_de(mp, _scroll_mazo)
			return {"control": c, "id": str(c.get_meta("card_id")), "en_mazo": en_mazo}
	return {}


func _dentro_de(mp: Vector2, zona: Control) -> bool:
	return zona != null and zona.visible and zona.get_global_rect().grow(6.0).has_point(mp)


func _crear_fantasma() -> void:
	# Copia visual que sigue al ratón mientras se arrastra.
	_fantasma = PanelContainer.new()
	_fantasma.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fantasma.custom_minimum_size = Vector2(72, 72)
	_fantasma.add_theme_stylebox_override("panel", _marco_fantasma())
	var icono := Label.new()
	icono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icono.add_theme_font_size_override("font_size", 36)
	icono.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cid := str(_arrastrando.get("id", ""))
	for c in _cartas_civ():
		if str(c.get("id", "")) == cid and c is Dictionary:
			icono.text = _icono_de(c)
			break
	_fantasma.add_child(icono)
	add_child(_fantasma)
	_mover_fantasma()


func _marco_fantasma() -> StyleBoxFlat:
	var m := StyleBoxFlat.new()
	m.bg_color = Color(0.13, 0.09, 0.06, 0.85)
	m.set_border_width_all(3)
	m.border_color = Color(1.0, 0.84, 0.42)
	m.set_corner_radius_all(6)
	return m


func _mover_fantasma() -> void:
	if _fantasma != null:
		_fantasma.global_position = get_global_mouse_position() - Vector2(36, 36)


func _soltar_arrastre() -> void:
	# Suelta: en el otro panel aplica, en el mismo no hace nada.
	var mp := get_global_mouse_position()
	var id := str(_arrastrando.get("id", ""))
	var venia_mazo := bool(_arrastrando.get("en_mazo", false))
	_fantasma.queue_free()
	_fantasma = null
	get_viewport().set_input_as_handled()
	if id.is_empty():
		return
	# Zonas = los scrolls completos (las filas se vacían y su rect colapsa).
	if _dentro_de(mp, _scroll_mazo) and not venia_mazo:
		for c in _cartas_civ():
			if c is Dictionary and str((c as Dictionary).get("id", "")) == id:
				_on_anadir(c)
				return
	elif _dentro_de(mp, _scroll_inv) and venia_mazo:
		_on_quitar(id)
		return
	_estado.text = "Arrastra cartas entre baraja e inventario."


func _icono_de(carta: Dictionary) -> String:
	if _card_art != null and _card_art.has_method("icon_for"):
		return str(_card_art.call("icon_for", str(carta.get("icon", ""))))
	return "◆"


func _asegurar_picker_civ() -> void:
	if _lista_civs != null:
		return
	var padre := _lista_mazos.get_parent() as Control
	if padre == null:
		return
	var t := Label.new()
	t.text = "Civ:"
	padre.add_child(t)
	_buscador_civ = LineEdit.new()
	_buscador_civ.placeholder_text = "Buscar civ..."
	padre.add_child(_buscador_civ)
	_buscador_civ.text_changed.connect(_on_filtro_civ)
	_lista_civs = ItemList.new()
	_lista_civs.custom_minimum_size = Vector2(0, 120)
	padre.add_child(_lista_civs)
	_lista_civs.item_selected.connect(_on_civ_elegida)
	_bonus_civ = Label.new()
	_bonus_civ.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	padre.add_child(_bonus_civ)


func _civs_auto() -> Array:
	var set := {}
	set[_civ] = true
	for c in _todas:
		if c is Dictionary:
			if c.has("civ") and str(c["civ"]) != "":
				set[str(c["civ"]).to_lower()] = true
			if c.has("civs") and c["civs"] is Array:
				for v in c["civs"]:
					set[str(v).to_lower()] = true
	var a := set.keys()
	a.sort()
	return a


func _civs_filtradas() -> Array:
	var s: Array = []
	for v in _civs_disponibles:
		if _filtro_civ.is_empty() or _filtro_civ in str(v).to_lower():
			s.append(str(v))
	s.sort_custom(func(a, b): return str(a).to_lower() < str(b).to_lower())
	return s


func _refrescar_lista_civs() -> void:
	if _lista_civs == null or not _listo:
		return
	_lista_civs.clear()
	for v in _civs_filtradas():
		var n: int = Validador.cards_for_civ(_todas, str(v)).size()
		_lista_civs.add_item("%s (%d)" % [str(v), n])
	_actualizar_bonus_civ()


func _actualizar_bonus_civ() -> void:
	if _bonus_civ == null or not _listo:
		return
	var n: int = Validador.cards_for_civ(_todas, _civ).size()
	_bonus_civ.text = "%s: %d cartas" % [_civ, n]


func _on_filtro_civ(t: String) -> void:
	_filtro_civ = t.strip_edges().to_lower()
	_refrescar_lista_civs()


func _on_civ_elegida(idx: int) -> void:
	var lista := _civs_filtradas()
	if idx >= 0 and idx < lista.size():
		set_civ(str(lista[idx]))
		_refrescar_lista_civs()

extends Control
# DeckBuilder: constructor de mazos 0-20 estilo medieval (Godot 4.4).
# Usa game/cards/Deck.gd (add_card, save/load/list_decks, validate)
# y game/cards/DeckValidator.gd (validate, load_all_cards, cards_for_civ).
# Tolera que CardWidget no exista: programa contra su API supuesta
# (setup(card), set_selected(bool), signal picked(card)) y si falta
# usa botones de respaldo. No modifica esos archivos.

const DeckScript := preload("res://game/cards/Deck.gd")
const Validador := preload("res://game/cards/DeckValidator.gd")

const RUTA_MENU := "res://ui/menus/MainMenu.tscn"
const RUTA_WIDGET_TSCN := "res://ui/decks/CardWidget.tscn"
const RUTA_WIDGET_GD := "res://ui/decks/CardWidget.gd"
const RUTA_CARD_ART := "res://ui/decks/CardArt.gd"

const TIPOS: Array[String] = ["unidad", "mejora", "recurso", "edificio"]

var _civ: String = "britones"
var _mazo = null
var _todas: Array = []
var _filtradas: Array = []
var _seleccion: Dictionary = {}
var _filtro_edad: int = 0
var _filtro_tipo: String = "todos"
var _texto_busqueda: String = ""
var _listo: bool = false
var _widget_escena: PackedScene = null
var _widget_script: Script = null
var _card_art: Script = null

@onready var _etiqueta_civ: Label = $MainMargin/MainVBox/TopBar/TopMargin/TopHBox/CivLabel
@onready var _etiqueta_cuenta: Label = $MainMargin/MainVBox/TopBar/TopMargin/TopHBox/CountLabel
@onready var _buscador: LineEdit = $MainMargin/MainVBox/Columns/LeftPanel/LeftMargin/LeftVBox/SearchEdit
@onready var _opt_edad: OptionButton = $MainMargin/MainVBox/Columns/LeftPanel/LeftMargin/LeftVBox/FiltersHBox/AgeFilter
@onready var _opt_tipo: OptionButton = $MainMargin/MainVBox/Columns/LeftPanel/LeftMargin/LeftVBox/FiltersHBox/TypeFilter
@onready var _lista_coleccion: VBoxContainer = $MainMargin/MainVBox/Columns/LeftPanel/LeftMargin/LeftVBox/CollectionScroll/CollectionList
@onready var _cuenta_mazo: Label = $MainMargin/MainVBox/Columns/CenterPanel/CenterMargin/CenterVBox/DeckCountLabel
@onready var _lista_mazo: VBoxContainer = $MainMargin/MainVBox/Columns/CenterPanel/CenterMargin/CenterVBox/DeckScroll/DeckList
@onready var _nombre_detalle: Label = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/DetailName
@onready var _info_detalle: Label = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/DetailInfo
@onready var _coste_detalle: Label = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/DetailCost
@onready var _desc_detalle: Label = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/DetailDesc
@onready var _efecto_detalle: Label = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/DetailEffect
@onready var _boton_anadir: Button = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/DetailButtons/AddButton
@onready var _boton_quitar: Button = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/DetailButtons/RemoveButton
@onready var _nombre_mazo: LineEdit = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/DeckNameEdit
@onready var _boton_guardar: Button = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/SaveRow/SaveButton
@onready var _boton_nuevo: Button = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/SaveRow/NewButton
@onready var _opcion_mazos: OptionButton = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/LoadRow/DecksOption
@onready var _boton_cargar: Button = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/LoadRow/LoadButton
@onready var _boton_refrescar: Button = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/LoadRow/RefreshButton
@onready var _etiqueta_errores: Label = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/ErrorsLabel
@onready var _etiqueta_estado: Label = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/StatusLabel
@onready var _boton_volver: Button = $MainMargin/MainVBox/Columns/RightPanel/RightMargin/RightVBox/BackButton


func set_civ(civ_nueva: String) -> void:
	# Recibe la civ desde fuera (antes o despues de _ready).
	var limpia: String = civ_nueva.strip_edges().to_lower()
	if limpia.is_empty():
		return
	_civ = limpia
	if not _listo:
		return
	_aplicar_civ_nueva(true)


func _ready() -> void:
	# Prepara mazo, cartas, filtros y estilo medieval.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_detectar_widget_y_arte()
	_cargar_cartas()
	if _mazo == null:
		_mazo = DeckScript.new()
		_mazo.civ = _civ
	_poblar_filtros()
	_conectar_senales()
	_aplicar_estilo()
	_listo = true
	_aplicar_civ_nueva(false)


func _detectar_widget_y_arte() -> void:
	# Localiza CardWidget (tscn o gd) y CardArt sin romper si faltan.
	if ResourceLoader.exists(RUTA_WIDGET_TSCN):
		_widget_escena = load(RUTA_WIDGET_TSCN) as PackedScene
	if ResourceLoader.exists(RUTA_WIDGET_GD):
		_widget_script = load(RUTA_WIDGET_GD) as Script
	if ResourceLoader.exists(RUTA_CARD_ART):
		_card_art = load(RUTA_CARD_ART) as Script


func _cargar_cartas() -> void:
	# Lee todos los JSON y construye el indice por id.
	_todas = Validador.load_all_cards()


func _poblar_filtros() -> void:
	# Rellena edad I-IV y tipos de carta.
	_opt_edad.clear()
	_opt_edad.add_item("Todas las edades", 0)
	_opt_edad.add_item("Edad I", 1)
	_opt_edad.add_item("Edad II", 2)
	_opt_edad.add_item("Edad III", 3)
	_opt_edad.add_item("Edad IV", 4)
	_opt_edad.selected = 0
	_opt_tipo.clear()
	_opt_tipo.add_item("Todos los tipos", 0)
	for i in TIPOS.size():
		_opt_tipo.add_item(TIPOS[i].capitalize(), i + 1)
	_opt_tipo.selected = 0


func _conectar_senales() -> void:
	# Une buscador, filtros y botones con sus manejadores.
	if not _buscador.text_changed.is_connected(_on_buscar):
		_buscador.text_changed.connect(_on_buscar)
	if not _opt_edad.item_selected.is_connected(_on_edad):
		_opt_edad.item_selected.connect(_on_edad)
	if not _opt_tipo.item_selected.is_connected(_on_tipo):
		_opt_tipo.item_selected.connect(_on_tipo)
	if not _boton_anadir.pressed.is_connected(_on_anadir_detalle):
		_boton_anadir.pressed.connect(_on_anadir_detalle)
	if not _boton_quitar.pressed.is_connected(_on_quitar_detalle):
		_boton_quitar.pressed.connect(_on_quitar_detalle)
	if not _boton_guardar.pressed.is_connected(_on_guardar):
		_boton_guardar.pressed.connect(_on_guardar)
	if not _boton_nuevo.pressed.is_connected(_on_nuevo):
		_boton_nuevo.pressed.connect(_on_nuevo)
	if not _boton_cargar.pressed.is_connected(_on_cargar):
		_boton_cargar.pressed.connect(_on_cargar)
	if not _boton_refrescar.pressed.is_connected(_on_refrescar_lista):
		_boton_refrescar.pressed.connect(_on_refrescar_lista)
	if not _boton_volver.pressed.is_connected(_on_volver):
		_boton_volver.pressed.connect(_on_volver)


func _aplicar_estilo() -> void:
	# Viste paneles y titulos con paleta medieval (madera, oro, piedra).
	var marco := _marco_madera()
	var piedra := _marco_piedra()
	for ruta in ["MainMargin/MainVBox/TopBar", "MainMargin/MainVBox/Columns/LeftPanel", "MainMargin/MainVBox/Columns/CenterPanel", "MainMargin/MainVBox/Columns/RightPanel"]:
		var panel := get_node_or_null(ruta) as PanelContainer
		if panel == null:
			continue
		if ruta.ends_with("TopBar"):
			panel.add_theme_stylebox_override("panel", marco)
		else:
			panel.add_theme_stylebox_override("panel", piedra)
	for b in [_boton_anadir, _boton_quitar, _boton_guardar, _boton_nuevo, _boton_cargar, _boton_refrescar, _boton_volver]:
		(b as Button).custom_minimum_size = Vector2(0, 40)


func _marco_madera() -> StyleBoxFlat:
	# Marco madera con ribete dorado (igual que el menu principal).
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
	marco.shadow_size = 12
	return marco


func _marco_piedra() -> StyleBoxFlat:
	# Recuadro secundario con borde de piedra clara.
	var marco := StyleBoxFlat.new()
	marco.bg_color = Color(0.16, 0.15, 0.13, 0.95)
	marco.border_width_left = 2
	marco.border_width_top = 2
	marco.border_width_right = 2
	marco.border_width_bottom = 2
	marco.border_color = Color(0.55, 0.52, 0.47)
	marco.corner_radius_top_left = 8
	marco.corner_radius_top_right = 8
	marco.corner_radius_bottom_right = 8
	marco.corner_radius_bottom_left = 8
	marco.shadow_color = Color(0, 0, 0, 0.55)
	marco.shadow_size = 8
	return marco


func _aplicar_civ_nueva(limpiar_mazo: bool) -> void:
	# Aplica la civ: ajusta mazo, filtros y refresca todo.
	if _mazo == null:
		_mazo = DeckScript.new()
	_mazo.civ = _civ
	if limpiar_mazo:
		_mazo.card_ids.clear()
		_seleccion = {}
	_etiqueta_civ.text = "Civ: %s" % _civ
	_aplicar_filtros()
	_refrescar_coleccion()
	_refrescar_mazo()
	_refrescar_lista_mazos()
	_mostrar_detalle(_seleccion)
	_validar_en_vivo()


func _aplicar_filtros() -> void:
	# Filtra por civ, edad, tipo y nombre (insensible a mayusculas).
	_filtradas.clear()
	var base: Array = Validador.cards_for_civ(_todas, _civ)
	for c in base:
		if not (c is Dictionary):
			continue
		var carta: Dictionary = c
		if _filtro_edad >= 1 and int(carta.get("age", 0)) != _filtro_edad:
			continue
		if _filtro_tipo != "todos" and str(carta.get("type", "")) != _filtro_tipo:
			continue
		if not _texto_busqueda.is_empty():
			var nombre: String = str(carta.get("name", "")).to_lower()
			if not _texto_busqueda in nombre:
				continue
		_filtradas.append(carta)


func _refrescar_coleccion() -> void:
	# Reconstruye la lista izquierda con CardWidget o boton simple.
	_limpiar_hijos(_lista_coleccion)
	if _filtradas.is_empty():
		var vacio := Label.new()
		vacio.text = "Sin cartas para esta civ o filtro."
		vacio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lista_coleccion.add_child(vacio)
		return
	for carta in _filtradas:
		if carta is Dictionary:
			_lista_coleccion.add_child(_crear_widget_coleccion(carta))


func _crear_widget_coleccion(carta: Dictionary) -> Control:
	# Intenta CardWidget (tscn, luego gd) y cae a boton medieval.
	if _widget_escena != null:
		var w: Control = _widget_escena.instantiate() as Control
		if w != null:
			_preparar_widget(w, carta)
			return w
	if _widget_script != null:
		var obj: Variant = _widget_script.new()
		if obj is Control:
			var w2: Control = obj as Control
			_preparar_widget(w2, carta)
			return w2
	return _crear_boton_coleccion(carta)


func _preparar_widget(w: Control, carta: Dictionary) -> void:
	# Aplica setup(card), picked(card) y resaltado de seleccion.
	w.set_meta("card_id", str(carta.get("id", "")))
	if w.has_method("setup"):
		w.call("setup", carta)
	if w.has_signal("picked"):
		if not w.is_connected("picked", _on_carta_recibida):
			w.connect("picked", _on_carta_recibida)
	elif w is BaseButton:
		var bb := w as BaseButton
		if not bb.pressed.is_connected(_on_coleccion_pulsada):
			bb.pressed.connect(_on_coleccion_pulsada.bind(carta))
	if w.has_method("set_selected"):
		var es: bool = str(_seleccion.get("id", "")) == str(carta.get("id", ""))
		w.call("set_selected", es)


func _crear_boton_coleccion(carta: Dictionary) -> Control:
	# Respaldo cuando CardWidget aun no existe en el repo.
	var b := Button.new()
	b.text = "＋ [%s] %s (%s)" % [_edad_romano(int(carta.get("age", 1))), str(carta.get("name", "?")), str(carta.get("type", "?"))]
	b.tooltip_text = str(carta.get("desc", ""))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_on_coleccion_pulsada.bind(carta))
	return b


func _refrescar_mazo() -> void:
	# Reconstruye el mazo central con boton Ver + boton Quitar.
	_limpiar_hijos(_lista_mazo)
	var ids: Array = _mazo.card_ids
	if ids.is_empty():
		var vacio := Label.new()
		vacio.text = "Mazo vacío: pulsa una carta de la colección para añadirla."
		vacio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lista_mazo.add_child(vacio)
		return
	for id_carta in ids:
		_lista_mazo.add_child(_crear_fila_mazo(str(id_carta)))


func _crear_fila_mazo(id_carta: String) -> Control:
	# Fila con nombre (ver detalle) y boton ✕ para quitar.
	var carta: Dictionary = _buscar_por_id(id_carta)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 6)
	var ver := Button.new()
	ver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ver.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if carta.is_empty():
		ver.text = "？ " + id_carta
		ver.tooltip_text = "Carta desconocida."
	else:
		ver.text = "[%s] %s" % [_edad_romano(int(carta.get("age", 1))), str(carta.get("name", id_carta))]
		ver.tooltip_text = str(carta.get("desc", ""))
	ver.pressed.connect(_on_ver_mazo.bind(id_carta))
	fila.add_child(ver)
	var quitar := Button.new()
	quitar.text = "✕"
	quitar.tooltip_text = "Quitar del mazo"
	quitar.custom_minimum_size = Vector2(48, 0)
	quitar.pressed.connect(_on_quitar_pulsada.bind(id_carta))
	fila.add_child(quitar)
	return fila


func _buscar_por_id(id_carta: String) -> Dictionary:
	# Busca la ficha completa en todas las cartas cargadas.
	for c in _todas:
		if c is Dictionary and str((c as Dictionary).get("id", "")) == id_carta:
			return c
	return {}


func _limpiar_hijos(nodo: Node) -> void:
	# Vacia una lista antes de reconstruirla.
	for h in nodo.get_children():
		h.queue_free()


func _mostrar_detalle(carta: Dictionary) -> void:
	# Pinta el panel derecho con icono, coste, efecto y descripcion.
	if carta.is_empty():
		_nombre_detalle.text = "—"
		_info_detalle.text = "Pulsa una carta para verla."
		_coste_detalle.text = ""
		_desc_detalle.text = ""
		_efecto_detalle.text = ""
		_boton_anadir.disabled = true
		_boton_quitar.disabled = true
		return
	var icono: String = _icono_carta(carta)
	_nombre_detalle.text = "%s %s" % [icono, str(carta.get("name", "?"))]
	_info_detalle.text = "Edad %s · %s · %s" % [_edad_romano(int(carta.get("age", 1))), str(carta.get("type", "?")), str(carta.get("rarity", "común"))]
	_coste_detalle.text = "Coste: %s" % _coste_texto(carta)
	_desc_detalle.text = str(carta.get("desc", ""))
	_efecto_detalle.text = _texto_efecto(carta)
	var en_mazo: bool = _mazo.card_ids.has(str(carta.get("id", "")))
	_boton_anadir.disabled = en_mazo or _mazo.card_ids.size() >= 20
	_boton_quitar.disabled = not en_mazo


func _texto_efecto(carta: Dictionary) -> String:
	# Resume el efecto en una linea legible.
	var ef: Variant = carta.get("effect", null)
	if not (ef is Dictionary):
		return "Efecto: —"
	var e: Dictionary = ef
	return "Efecto: %s %s %s = %s" % [str(e.get("op", "?")), str(e.get("target", "?")), str(e.get("path", "?")), str(e.get("value", "?"))]


func _edad_romano(edad: int) -> String:
	# Convierte 1-4 a I-IV para los filtros y listas.
	match edad:
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
		4:
			return "IV"
	return "?"


func _icono_carta(carta: Dictionary) -> String:
	# Usa CardArt.icon_for si existe, si no un rombo simple.
	if _card_art != null and _card_art.has_method("icon_for"):
		return str(_card_art.call("icon_for", str(carta.get("icon", ""))))
	return "◆"


func _coste_texto(carta: Dictionary) -> String:
	# Usa CardArt.cost_text si existe, si no lista clave:valor.
	var coste: Variant = carta.get("cost", {})
	if _card_art != null and (coste is Dictionary) and _card_art.has_method("cost_text"):
		return str(_card_art.call("cost_text", coste))
	if not (coste is Dictionary) or (coste as Dictionary).is_empty():
		return "Gratis"
	var partes: Array[String] = []
	for k in (coste as Dictionary).keys():
		partes.append("%s:%s" % [str(k), str((coste as Dictionary)[k])])
	return " ".join(partes)


func _validar_en_vivo() -> void:
	# Valida con Deck.validate y pinta mensajes + contadores.
	var errores: Array = _mazo.validate(_todas)
	var n: int = _mazo.card_ids.size()
	_etiqueta_cuenta.text = "Mazo %d/20" % n
	_cuenta_mazo.text = "%d/20 cartas" % n
	if errores.is_empty():
		_etiqueta_errores.text = "Mazo válido ✔ (20/20)."
		_etiqueta_errores.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	else:
		_etiqueta_errores.text = "\n".join(PackedStringArray(errores))
		_etiqueta_errores.add_theme_color_override("font_color", Color(1.0, 0.55, 0.50))


func _refrescar_lista_mazos() -> void:
	# Lista los mazos de user://decks/ en el desplegable.
	_opcion_mazos.clear()
	var nombres: Array = DeckScript.list_decks()
	if nombres.is_empty():
		_opcion_mazos.add_item("(sin mazos)", 0)
		_opcion_mazos.selected = 0
		_opcion_mazos.disabled = true
		return
	_opcion_mazos.disabled = false
	for i in nombres.size():
		_opcion_mazos.add_item(str(nombres[i]), i)
	_opcion_mazos.selected = 0


func _resaltar_seleccion() -> void:
	# Marca el CardWidget elegido cuando ese metodo existe.
	for h in _lista_coleccion.get_children():
		if h.has_method("set_selected") and h.has_meta("card_id"):
			h.call("set_selected", str(h.get_meta("card_id")) == str(_seleccion.get("id", "")))


func _intentar_anadir(carta: Dictionary) -> void:
	# Anade por id y refresca mazo + validacion + detalle.
	var id_carta: String = str(carta.get("id", "")).strip_edges()
	if id_carta.is_empty():
		_etiqueta_estado.text = "Carta sin id."
		return
	var motivo: String = _mazo.add_card(id_carta)
	if not motivo.is_empty():
		_etiqueta_estado.text = "No se añade: %s." % motivo
	else:
		_etiqueta_estado.text = "Añadida: %s (%d/20)." % [str(carta.get("name", id_carta)), _mazo.card_ids.size()]
	_refrescar_mazo()
	_mostrar_detalle(carta)
	_validar_en_vivo()


func _on_buscar(texto: String) -> void:
	# Buscador por nombre de la coleccion izquierda.
	_texto_busqueda = texto.strip_edges().to_lower()
	_aplicar_filtros()
	_refrescar_coleccion()


func _on_edad(indice: int) -> void:
	# Filtro de edad: 0 todas, 1-4 edad exacta.
	_filtro_edad = _opt_edad.get_item_id(indice)
	_aplicar_filtros()
	_refrescar_coleccion()


func _on_tipo(indice: int) -> void:
	# Filtro de tipo: 0 todos, resto segun lista TIPOS.
	var id_tipo: int = _opt_tipo.get_item_id(indice)
	if id_tipo <= 0:
		_filtro_tipo = "todos"
	else:
		_filtro_tipo = TIPOS[clampi(id_tipo - 1, 0, TIPOS.size() - 1)]
	_aplicar_filtros()
	_refrescar_coleccion()


func _on_carta_recibida(carta: Variant) -> void:
	# Senal picked(card) del CardWidget supuesto.
	if not (carta is Dictionary):
		return
	_seleccion = carta
	_intentar_anadir(carta)


func _on_coleccion_pulsada(carta: Dictionary) -> void:
	# Clic en la coleccion: ver detalle y anadir al mazo.
	_seleccion = carta
	_intentar_anadir(carta)


func _on_ver_mazo(id_carta: String) -> void:
	# Muestra el detalle de una carta que ya esta en el mazo.
	var carta: Dictionary = _buscar_por_id(id_carta)
	if carta.is_empty():
		_etiqueta_estado.text = "Carta desconocida: %s." % id_carta
		return
	_seleccion = carta
	_mostrar_detalle(carta)


func _on_quitar_pulsada(id_carta: String) -> void:
	# Quita una carta del mazo central y revalida.
	if _mazo.remove_card(id_carta):
		_etiqueta_estado.text = "Quitada: %s (%d/20)." % [id_carta, _mazo.card_ids.size()]
	else:
		_etiqueta_estado.text = "No estaba en el mazo: %s." % id_carta
	_refrescar_mazo()
	_mostrar_detalle(_seleccion)
	_validar_en_vivo()


func _on_anadir_detalle() -> void:
	# Boton Anadir del panel de detalle.
	if _seleccion.is_empty():
		return
	_intentar_anadir(_seleccion)


func _on_quitar_detalle() -> void:
	# Boton Quitar del panel de detalle.
	if _seleccion.is_empty():
		return
	_on_quitar_pulsada(str(_seleccion.get("id", "")))


func _on_guardar() -> void:
	# Guarda el mazo en user://decks/ con el nombre escrito.
	var nombre: String = _nombre_mazo.text.strip_edges()
	if nombre.is_empty():
		_etiqueta_estado.text = "Escribe un nombre para guardar."
		return
	if _mazo.save(nombre):
		_etiqueta_estado.text = "Guardado: %s (%d/20)." % [nombre, _mazo.card_ids.size()]
		_refrescar_lista_mazos()
	else:
		_etiqueta_estado.text = "No se pudo guardar: %s." % nombre


func _on_cargar() -> void:
	# Carga el mazo elegido del desplegable (user://decks/).
	if _opcion_mazos.disabled or _opcion_mazos.item_count <= 0:
		_etiqueta_estado.text = "No hay mazos guardados."
		return
	var nombre: String = _opcion_mazos.get_item_text(_opcion_mazos.selected)
	if nombre == "(sin mazos)":
		return
	var tmp = DeckScript.new()
	if not tmp.load_deck(nombre):
		_etiqueta_estado.text = "No se pudo cargar: %s." % nombre
		return
	_mazo = tmp
	_civ = str(_mazo.civ)
	_seleccion = {}
	_nombre_mazo.text = nombre
	_etiqueta_civ.text = "Civ: %s" % _civ
	_aplicar_filtros()
	_refrescar_coleccion()
	_refrescar_mazo()
	_mostrar_detalle(_seleccion)
	_validar_en_vivo()
	_etiqueta_estado.text = "Cargado: %s (%d/20)." % [nombre, _mazo.card_ids.size()]


func _on_refrescar_lista() -> void:
	# Relee user://decks/ por si se anadio algo fuera.
	_refrescar_lista_mazos()
	_etiqueta_estado.text = "Lista de mazos actualizada."


func _on_nuevo() -> void:
	# Empieza un mazo vacio para la civ actual.
	_mazo = DeckScript.new()
	_mazo.civ = _civ
	_seleccion = {}
	_refrescar_mazo()
	_mostrar_detalle(_seleccion)
	_validar_en_vivo()
	_etiqueta_estado.text = "Mazo nuevo para %s." % _civ


func _on_volver() -> void:
	# Vuelve al menu principal.
	if ResourceLoader.exists(RUTA_MENU):
		get_tree().change_scene_to_file(RUTA_MENU)
	else:
		_etiqueta_estado.text = "Falta el menú principal."

class_name CardWidget
extends PanelContainer
# Tarjeta visual reutilizable de 150x210 para mazos.
# Solo UI: muestra datos y emite signal, nunca toca la sim.
# Usa helpers de CardArt (card_frame, icon_for, rarity_color, cost_text).

# Se emite al pulsar la tarjeta con clic o Enter/Espacio.
signal card_pressed(card_id: String)

# Arte procedural compartido (marcos, iconos, rarezas, costes).
const CardArtScript := preload("res://ui/decks/CardArt.gd")

# Id de la carta mostrada (se devuelve en el signal).
var _card_id: String = ""
# Edad numerica 1-4 para el marco y el sello.
var _edad: int = 1
# Si esta seleccionada (resalte dorado).
var _selected: bool = false
# Marco base sin seleccionar (se regenera en cada setup).
var _base_style: StyleBoxFlat = null
# Ficha pendiente si setup llega antes del _ready.
var _pending_card: Dictionary = {}

@onready var _cost_label: Label = $Margin/CardVBox/TopBar/CostLabel
@onready var _age_seal: Label = $Margin/CardVBox/TopBar/AgeSeal
@onready var _icon_label: Label = $Margin/CardVBox/IconLabel
@onready var _name_label: Label = $Margin/CardVBox/NameLabel
@onready var _rarity_label: Label = $Margin/CardVBox/RarityLabel
@onready var _rarity_bar: ColorRect = $Margin/CardVBox/RarityBar


func _ready() -> void:
	# La tarjeta recibe foco y clics para emitir el signal.
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(150, 210)
	if _base_style == null:
		_base_style = CardArtScript.card_frame(_edad)
		add_theme_stylebox_override("panel", _base_style)
	# Aplica la ficha que llego antes de estar lista.
	if not _pending_card.is_empty():
		var ficha: Dictionary = _pending_card
		_pending_card = {}
		setup(ficha)


func _gui_input(event: InputEvent) -> void:
	# Solo UI: clic izquierdo o tecla de confirmacion emiten signal.
	if event is InputEventMouseButton:
		var clic: InputEventMouseButton = event as InputEventMouseButton
		if clic.button_index == MOUSE_BUTTON_LEFT and clic.pressed:
			accept_event()
			grab_focus()
			card_pressed.emit(_card_id)
	elif event is InputEventKey:
		var tecla: InputEventKey = event as InputEventKey
		if tecla.pressed and not tecla.echo:
			if tecla.keycode == KEY_ENTER or tecla.keycode == KEY_KP_ENTER or tecla.keycode == KEY_SPACE:
				accept_event()
				card_pressed.emit(_card_id)


func setup(card: Dictionary) -> void:
	# Rellena la tarjeta desde una ficha {id, name, icon, age, cost, rarity, desc, effect/effects}.
	# Si los nodos aun no estan listos, guarda y aplica en _ready.
	if not is_node_ready():
		_pending_card = card.duplicate()
		# Guarda id y edad para el marco aunque no haya nodos.
		_card_id = str(card.get("id", ""))
		_edad = _edad_desde(card)
		return
	_card_id = str(card.get("id", ""))
	_edad = _edad_desde(card)
	# Icono grande desde el campo icon (acepta "icon:xxx" o id directo).
	var icono_raw := str(card.get("icon", ""))
	icono_raw = icono_raw.replace("icon:", "").strip_edges()
	if icono_raw.is_empty():
		icono_raw = _card_id
	_icon_label.text = CardArtScript.icon_for(icono_raw)
	# Nombre visible (puede venir como "@str:clave", se muestra tal cual).
	var nombre := str(card.get("name", _card_id))
	_name_label.text = nombre if not nombre.strip_edges().is_empty() else _card_id
	# Coste corto con el helper ("200O 100M" o "Gratis").
	var coste: Dictionary = {}
	if card.get("cost", null) is Dictionary:
		coste = card["cost"]
	elif card.get("coste", null) is Dictionary:
		coste = card["coste"]
	_cost_label.text = CardArtScript.cost_text(coste)
	# Sello de edad en romano I/II/III/IV.
	_age_seal.text = _romano(_edad)
	# Borde de rareza: tira inferior + etiqueta con el color.
	var rareza_raw := str(card.get("rarity", card.get("rareza", "comun")))
	var color_rareza: Color = CardArtScript.rarity_color(rareza_raw)
	_rarity_bar.color = color_rareza
	_rarity_label.text = rareza_raw.strip_edges().capitalize()
	_rarity_label.add_theme_color_override("font_color", color_rareza)
	# Marco de madera con ribete segun edad.
	_base_style = CardArtScript.card_frame(_edad)
	_aplicar_marco()
	# Tooltip con descripcion + efecto legible.
	var desc := str(card.get("desc", card.get("descripcion", "")))
	var efecto_txt := _texto_efecto(card.get("effect", card.get("effects", null)))
	if desc.strip_edges().is_empty():
		desc = nombre
	tooltip_text = desc if efecto_txt.is_empty() else "%s\n\nEfecto: %s" % [desc, efecto_txt]


func set_selected(valor: bool) -> void:
	# Resalta en dorado cuando esta seleccionada, restaura el marco si no.
	_selected = valor
	_aplicar_marco()


func _aplicar_marco() -> void:
	# Aplica el marco base o su variante dorada de seleccion.
	if _base_style == null:
		_base_style = CardArtScript.card_frame(_edad)
	if _selected:
		var dorado := _base_style.duplicate() as StyleBoxFlat
		dorado.border_color = CardArtScript.ORO
		dorado.border_width_left = 5
		dorado.border_width_top = 5
		dorado.border_width_right = 5
		dorado.border_width_bottom = 5
		add_theme_stylebox_override("panel", dorado)
	else:
		add_theme_stylebox_override("panel", _base_style)


func _edad_desde(card: Dictionary) -> int:
	# Acepta age/edad como int 1-4 o romano I/II/III/IV.
	var v: Variant = card.get("age", card.get("edad", 1))
	if v is int or v is float:
		return clampi(int(v), 1, 4)
	var s := str(v).strip_edges().to_upper()
	match s:
		"I":
			return 1
		"II":
			return 2
		"III":
			return 3
		"IV":
			return 4
	return 1


func _romano(edad: int) -> String:
	# Sello de edad para la esquina de la tarjeta.
	match clampi(edad, 1, 4):
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
		4:
			return "IV"
	return "I"


func _texto_efecto(efecto: Variant) -> String:
	# Resume el efecto para el tooltip (dict unico o array de parches).
	if efecto == null:
		return ""
	if efecto is Dictionary:
		return _resumen_parche(efecto as Dictionary)
	if efecto is Array:
		var partes: Array[String] = []
		for p in (efecto as Array):
			if p is Dictionary:
				partes.append(_resumen_parche(p as Dictionary))
		return " + ".join(partes)
	return str(efecto)


func _resumen_parche(p: Dictionary) -> String:
	# Texto corto tipo "add Attack.damage.melee +2 (tag:infanteria)".
	var op := str(p.get("op", "?"))
	var ruta := str(p.get("path", p.get("at", "")))
	var valor := str(p.get("value", p.get("valor", "")))
	var objetivo := str(p.get("target", p.get("id", "")))
	var txt := op
	if not ruta.is_empty():
		txt += " " + ruta
	if not valor.is_empty():
		txt += " " + valor
	if not objetivo.is_empty():
		txt += " (%s)" % objetivo
	return txt.strip_edges()

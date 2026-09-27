extends Control
# Menú de campaña estilo AoE2: lista con estados, briefing y retrato del héroe.
# Fuente de datos: CampaignManager (autoload /root/CampaignManager).
# Si el autoload no existe (tests), se instancia el script como fallback.
# Conserva la lógica: lista, briefing, desbloqueo y start_scenario.
# Visual: madera oscura, pergamino, dorado, retrato procedural (sin assets de pago).

const MAIN_MENU := "res://ui/menus/MainMenu.tscn"
const MANAGER_PATH := "/root/CampaignManager"
const MANAGER_SCRIPT := "res://systems/campaign/CampaignManager.gd"

# Paleta AoE2 (madera, pergamino y dorado).
const COLOR_DORADO := Color("e8c15a")
const COLOR_PERGAMINO := Color("e8d5a3")
const COLOR_TINTA := Color("2a1c10")
const COLOR_SUBTITULO := Color("b8a684")
const COLOR_VERDE := Color("7bc47f")
const COLOR_GRIS := Color("9a9a9a")
const COLOR_ROJO := Color("e08a7a")

# Retrato procedural: un color por héroe/escenario y un icono rotativo.
const COLORES_HEROE: Array[Color] = [
	Color("8b1a1a"), Color("1a4a8b"), Color("2e6b2e"),
	Color("6b2e6b"), Color("b5651d"), Color("1d6b6b"),
]
const ICONOS_HEROE: Array[String] = ["🛡️", "⚔️", "👑", "🏹", "🐺", "🔥", "🗡️"]

var _manager: Node = null
var _fallback_owned := false
var _selected := ""
var _orden_ids: Array[String] = []
var _indice_actual := -1

@onready var _titulo: Label = %Titulo
@onready var _subtitulo: Label = %Subtitulo
@onready var _panel_lista: PanelContainer = %PanelLista
@onready var _lista: VBoxContainer = %ListaEscenarios
@onready var _progreso: Label = %ProgresoLabel
@onready var _panel_briefing: PanelContainer = %PanelBriefing
@onready var _retrato_marco: PanelContainer = %RetratoMarco
@onready var _retrato_icono: Label = %RetratoIcono
@onready var _nombre: Label = %NombreEscenario
@onready var _estado_esc: Label = %EstadoEscenario
@onready var _briefing: RichTextLabel = %BriefingTexto
@onready var _objetivos_vb: VBoxContainer = %ObjetivosLista
@onready var _intro: RichTextLabel = %IntroTexto
@onready var _play_btn: Button = %BotonJugar
@onready var _back_btn: Button = %BotonVolver
@onready var _status: Label = %EstadoLabel


func _ready() -> void:
	_resolver_manager()
	_aplicar_estilo_aoe2()
	_play_btn.pressed.connect(_on_play)
	_back_btn.pressed.connect(_on_back)
	refresh_list()
	# Conecta victoria/derrota para refrescar desbloqueo y mensajes.
	if _manager != null and _manager.has_signal("campaign_won"):
		_manager.campaign_won.connect(_on_won)
	if _manager != null and _manager.has_signal("campaign_lost"):
		_manager.campaign_lost.connect(_on_lost)


func _exit_tree() -> void:
	# Libera el manager solo si lo creamos como fallback.
	if _fallback_owned and is_instance_valid(_manager):
		_manager.queue_free()


# Busca el autoload o crea un fallback para tests.
func _resolver_manager() -> void:
	_manager = get_node_or_null(MANAGER_PATH)
	if _manager == null:
		_manager = (load(MANAGER_SCRIPT) as GDScript).new()
		_fallback_owned = true
		add_child(_manager)


# Aplica toda la piel AoE2 por código (tscn solo define estructura).
func _aplicar_estilo_aoe2() -> void:
	_titulo.add_theme_font_size_override("font_size", 32)
	_titulo.add_theme_color_override("font_color", COLOR_DORADO)
	_subtitulo.add_theme_font_size_override("font_size", 15)
	_subtitulo.add_theme_color_override("font_color", COLOR_SUBTITULO)
	# Paneles de madera oscura con borde dorado.
	_panel_lista.add_theme_stylebox_override("panel", _hacer_panel(Color("241a10"), Color("c9a227"), 2, 10))
	_panel_briefing.add_theme_stylebox_override("panel", _hacer_panel(Color("2e2115"), Color("c9a227"), 2, 10))
	# Cabecera del briefing.
	_nombre.add_theme_font_size_override("font_size", 22)
	_nombre.add_theme_color_override("font_color", COLOR_DORADO)
	_estado_esc.add_theme_font_size_override("font_size", 15)
	# Zonas de pergamino para briefing e intro.
	_briefing.add_theme_stylebox_override("normal", _hacer_panel(COLOR_PERGAMINO, Color("8a6d3b"), 1, 6))
	_briefing.add_theme_color_override("default_color", COLOR_TINTA)
	_briefing.add_theme_font_size_override("normal_font_size", 16)
	_intro.add_theme_stylebox_override("normal", _hacer_panel(Color("dfcba0"), Color("8a6d3b"), 1, 6))
	_intro.add_theme_color_override("default_color", COLOR_TINTA)
	_intro.add_theme_font_size_override("normal_font_size", 15)
	_retrato_icono.add_theme_font_size_override("font_size", 46)
	_progreso.add_theme_color_override("font_color", COLOR_DORADO)
	_progreso.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", COLOR_PERGAMINO)
	_status.add_theme_font_size_override("font_size", 15)
	# Botones Jugar (rojo) y Volver (marrón).
	_estilizar_boton(_play_btn, Color("8b1a1a"), Color("a92222"), Color("5a0f0f"))
	_estilizar_boton(_back_btn, Color("4a3826"), Color("5d4730"), Color("33271a"))


# Crea un panel con fondo, borde y esquinas redondeadas.
func _hacer_panel(fondo: Color, borde: Color, grosor: int, radio: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fondo
	sb.border_color = borde
	sb.set_border_width_all(grosor)
	sb.set_corner_radius_all(radio)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb


# Da a un botón su aspecto AoE2 en los cuatro estados.
func _estilizar_boton(b: Button, normal: Color, hover: Color, pressed: Color) -> void:
	var sn := StyleBoxFlat.new()
	sn.bg_color = normal
	sn.border_color = Color("c9a227")
	sn.set_border_width_all(2)
	sn.set_corner_radius_all(6)
	sn.content_margin_left = 12.0
	sn.content_margin_right = 12.0
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = hover
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = pressed
	var sd := sn.duplicate() as StyleBoxFlat
	sd.bg_color = Color("2a2a2a")
	sd.border_color = Color("666666")
	b.add_theme_stylebox_override("normal", sn)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_stylebox_override("disabled", sd)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color("f5e6c4"))
	b.add_theme_color_override("font_hover_color", Color("ffe9a8"))
	b.add_theme_color_override("font_disabled_color", Color("888888"))
	b.add_theme_font_size_override("font_size", 20)


## Reconstruye la lista desde CampaignManager.list_campaigns().
func refresh_list() -> void:
	# Limpia filas anteriores.
	for c in _lista.get_children():
		c.remove_from_parent()
		c.queue_free()
	_orden_ids.clear()
	if _manager == null:
		_progreso.text = "(sin CampaignManager)"
		return
	var items: Array = _manager.call("list_campaigns")
	if items.is_empty():
		var none := Label.new()
		none.text = "(no hay campañas en data/campaigns/*.json)"
		none.add_theme_color_override("font_color", COLOR_SUBTITULO)
		_lista.add_child(none)
		_progreso.text = "🏆 Progreso: 0/0"
		return
	# Detecta el escenario actual: primer desbloqueado sin completar.
	_indice_actual = -1
	for i in items.size():
		var dd: Dictionary = items[i]
		if bool(dd.get("unlocked", false)) and not bool(dd.get("completed", false)):
			_indice_actual = i
			break
	# Crea una fila por escenario con su icono de estado.
	for i in items.size():
		var d: Dictionary = items[i]
		var sid := str(d.get("id", "?"))
		_orden_ids.append(sid)
		_lista.add_child(_crear_fila(d, i, i == _indice_actual))
	_actualizar_progreso(items)
	# Mantiene la selección si sigue válida; si no, salta al actual.
	if _selected.is_empty() or not _orden_ids.has(_selected) or not _esta_desbloqueado(items, _selected):
		if _indice_actual >= 0:
			_selected = _orden_ids[_indice_actual]
		else:
			_selected = _orden_ids[0]
	_refrescar_seleccion_visual()
	if not _selected.is_empty():
		_show_briefing(_selected)


# Comprueba si un escenario está desbloqueado en la lista dada.
func _esta_desbloqueado(items: Array, sid: String) -> bool:
	for e in items:
		var d: Dictionary = e
		if str(d.get("id", "")) == sid:
			return bool(d.get("unlocked", false))
	return false


# Actualiza el contador de progreso bajo la lista.
func _actualizar_progreso(items: Array) -> void:
	var hechos := 0
	for e in items:
		if bool((e as Dictionary).get("completed", false)):
			hechos += 1
	var pct := 0
	if not items.is_empty():
		pct = int(round(100.0 * float(hechos) / float(items.size())))
	_progreso.text = "🏆 Progreso: %d/%d · %d%%" % [hechos, items.size(), pct]


# Crea el botón-fila de un escenario con icono y color según estado.
func _crear_fila(d: Dictionary, indice: int, es_actual: bool) -> Button:
	var sid := str(d.get("id", "?"))
	var nombre := str(d.get("name", sid))
	var completado := bool(d.get("completed", false))
	var desbloqueado := bool(d.get("unlocked", false))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(320, 46)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.text = "%s  %02d · %s" % [_icono_estado(completado, desbloqueado, es_actual), indice + 1, nombre]
	btn.tooltip_text = _texto_estado(completado, desbloqueado, es_actual)
	btn.disabled = not desbloqueado
	btn.set_meta("sid", sid)
	btn.pressed.connect(_on_select.bind(sid))
	# Color de fila: verde completado, dorado actual, gris bloqueado.
	var fondo := Color("3a2c1c")
	var borde := Color("8a6d3b")
	if completado:
		fondo = Color("2e4a2a")
		borde = Color("7bc47f")
	elif es_actual:
		fondo = Color("5a1a12")
		borde = Color("e8c15a")
	elif not desbloqueado:
		fondo = Color("222222")
		borde = Color("555555")
	_estilizar_fila(btn, fondo, borde)
	btn.add_theme_font_size_override("font_size", 16)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return btn


# Estilo compacto para las filas (reusa la idea de _estilizar_boton).
func _estilizar_fila(b: Button, fondo: Color, borde: Color) -> void:
	var sn := StyleBoxFlat.new()
	sn.bg_color = fondo
	sn.border_color = borde
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(6)
	sn.content_margin_left = 10.0
	sn.content_margin_right = 10.0
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = fondo.lightened(0.12)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = fondo.darkened(0.15)
	var sd := sn.duplicate() as StyleBoxFlat
	sd.bg_color = Color("1e1e1e")
	sd.border_color = Color("444444")
	b.add_theme_stylebox_override("normal", sn)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_stylebox_override("disabled", sd)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color("f0dfb8"))
	b.add_theme_color_override("font_hover_color", Color("ffe9a8"))
	b.add_theme_color_override("font_disabled_color", Color("777777"))


# Icono de estado: candado, tick, estrella del actual o flecha disponible.
func _icono_estado(completado: bool, desbloqueado: bool, es_actual: bool) -> String:
	if completado:
		return "✅"
	if es_actual:
		return "⭐"
	if desbloqueado:
		return "▶"
	return "🔒"


# Texto corto de estado para tooltip y panel.
func _texto_estado(completado: bool, desbloqueado: bool, es_actual: bool) -> String:
	if completado:
		return "Completado"
	if es_actual:
		return "Escenario actual — ¡a la batalla!"
	if desbloqueado:
		return "Disponible"
	return "Bloqueado — completa el anterior"


# Resalta la fila seleccionada con un borde dorado más grueso.
func _refrescar_seleccion_visual() -> void:
	for c in _lista.get_children():
		if c is Button and (c as Button).has_meta("sid"):
			var b := c as Button
			var es_sel := str(b.get_meta("sid")) == _selected
			# El foco dorado marca la selección sin romper el color de estado.
			if es_sel and not b.disabled:
				b.add_theme_stylebox_override("focus", _hacer_panel(Color(0, 0, 0, 0), COLOR_DORADO, 2, 6))
			else:
				b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _on_select(sid: String) -> void:
	_selected = sid
	_refrescar_seleccion_visual()
	_show_briefing(sid)


# Muestra briefing, objetivos, intro y retrato del escenario elegido.
func _show_briefing(sid: String) -> void:
	if _manager == null:
		return
	var texto: String = _manager.call("get_briefing_text", sid)
	var intro: Array = _manager.call("get_dialogues", sid, "intro")
	var objetivos: Array[String] = _extraer_objetivos(sid, texto)
	var datos := _buscar_datos(sid)
	var nombre := sid
	var completado := false
	var desbloqueado := true
	if not datos.is_empty():
		nombre = str(datos.get("name", sid))
		completado = bool(datos.get("completed", false))
		desbloqueado = bool(datos.get("unlocked", true))
	var es_actual := _orden_ids.find(sid) == _indice_actual
	# Cabecera: nombre + estado con color.
	_nombre.text = nombre
	_estado_esc.text = _etiqueta_estado(completado, desbloqueado, es_actual)
	_estado_esc.add_theme_color_override("font_color", _color_estado(completado, desbloqueado, es_actual))
	# Cuerpo del briefing en pergamino.
	_briefing.text = "[b]BRIEFING[/b]\n" + texto.strip_edges()
	_mostrar_objetivos(objetivos)
	# Diálogos de introducción con el hablante destacado.
	if intro.is_empty():
		_intro.text = "[i]Sin diálogos de introducción.[/i]"
	else:
		var bb := ""
		for l in intro:
			var dl: Dictionary = l
			bb += "[color=#8b1a1a][b]%s:[/b][/color] %s\n" % [str(dl.get("speaker", "?")), str(dl.get("text", ""))]
		_intro.text = bb.strip_edges()
	_actualizar_retrato(sid)
	_play_btn.disabled = not desbloqueado or sid.is_empty()
	_status.text = ""


# Busca el diccionario del escenario en la lista del manager.
func _buscar_datos(sid: String) -> Dictionary:
	var items: Array = _manager.call("list_campaigns")
	for e in items:
		var d: Dictionary = e
		if str(d.get("id", "")) == sid:
			return d
	return {}


# Etiqueta de estado para la cabecera del briefing.
func _etiqueta_estado(completado: bool, desbloqueado: bool, es_actual: bool) -> String:
	if completado:
		return "✅ COMPLETADO"
	if es_actual:
		return "⭐ ESCENARIO ACTUAL — ¡A la batalla!"
	if desbloqueado:
		return "▶ DISPONIBLE"
	return "🔒 BLOQUEADO — Completa el escenario anterior"


# Color de la etiqueta de estado.
func _color_estado(completado: bool, desbloqueado: bool, es_actual: bool) -> Color:
	if completado:
		return COLOR_VERDE
	if es_actual:
		return COLOR_DORADO
	if desbloqueado:
		return COLOR_PERGAMINO
	return COLOR_GRIS


# Intenta leer objetivos del manager; si no hay API, los deduce del briefing.
func _extraer_objetivos(sid: String, briefing: String) -> Array[String]:
	var out: Array[String] = []
	# Vía API nueva si existe (no rompe managers antiguos).
	if _manager.has_method("get_objectives"):
		var raw: Array = _manager.call("get_objectives", sid)
		for o in raw:
			out.append(str(o))
		return out
	# Vía diccionario de escenario si trae clave "objectives".
	if _manager.has_method("get_scenario"):
		var sc: Variant = _manager.call("get_scenario", sid)
		if sc is Dictionary and (sc as Dictionary).has("objectives"):
			for o in (sc as Dictionary)["objectives"]:
				out.append(str(o))
			if not out.is_empty():
				return out
	# Fallback: líneas del briefing con viñetas o numeración.
	for linea in briefing.split("\n"):
		var t := linea.strip_edges()
		if t.begins_with("- ") or t.begins_with("* ") or t.begins_with("• ") or t.begins_with("· "):
			out.append(t.substr(2).strip_edges())
		elif t.length() > 3 and t[0].is_valid_int() and (t[1] == "." or t[1] == ")"):
			out.append(t.substr(2).strip_edges())
		if out.size() >= 8:
			break
	return out


# Pinta la lista de objetivos con viñetas doradas.
func _mostrar_objetivos(objetivos: Array[String]) -> void:
	for c in _objetivos_vb.get_children():
		c.remove_from_parent()
		c.queue_free()
	if objetivos.is_empty():
		var vacio := Label.new()
		vacio.text = "• Sin objetivos definidos: sobrevive y vence."
		vacio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vacio.add_theme_color_override("font_color", COLOR_PERGAMINO)
		_objetivos_vb.add_child(vacio)
		return
	for o in objetivos:
		var lbl := Label.new()
		lbl.text = "◆  " + o
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_color_override("font_color", COLOR_PERGAMINO)
		lbl.add_theme_font_size_override("font_size", 15)
		_objetivos_vb.add_child(lbl)


# Retrato procedural: color por hash del id e icono rotativo por posición.
func _actualizar_retrato(sid: String) -> void:
	var idx := maxi(0, _orden_ids.find(sid))
	_retrato_icono.text = ICONOS_HEROE[idx % ICONOS_HEROE.size()]
	var color_heroe := COLORES_HEROE[abs(hash(sid)) % COLORES_HEROE.size()]
	var marco := StyleBoxFlat.new()
	marco.bg_color = color_heroe
	marco.border_color = COLOR_DORADO
	marco.set_border_width_all(3)
	marco.set_corner_radius_all(8)
	marco.shadow_color = Color(0, 0, 0, 0.5)
	marco.shadow_size = 6
	_retrato_marco.add_theme_stylebox_override("panel", marco)


func _on_play() -> void:
	if _selected.is_empty():
		_status.text = "Selecciona un escenario primero."
		return
	var ok: bool = _manager.call("start_scenario", _selected)
	if not ok:
		_status.text = "No se pudo iniciar (¿bloqueado?): " + _selected
		return
	_status.text = "¡En marcha! Intro en el chat. Cambia a la escena de juego para luchar."
	# TODO agente 26: change_scene_to_file("res://ui/game/Game.tscn") al arrancar.


func _on_won(sid: String, ticks_used: int) -> void:
	var mins := snappedf(float(ticks_used) / 600.0, 0.1)
	_status.text = "🏆 ¡Victoria en %s (%s min)! Siguiente escenario desbloqueado." % [sid, str(mins)]
	refresh_list()


func _on_lost(sid: String, reason: String) -> void:
	_status.text = "💀 Derrota en %s (%s). Inténtalo de nuevo." % [sid, reason]


func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)

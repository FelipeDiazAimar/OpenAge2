extends Control
# Diplomacia - panel de diplomacia estilo AoE2 (solo cliente, no entra en hash).
# - Lista 8 jugadores (GameManager.players): color, civ, equipo, vivo/muerto.
# - Estado Aliado/Neutral/Enemigo: DERIVADO de equipos de lobby (mismo team =
#   Aliado, distinto = Enemigo). El boton de estado es override VISUAL local
#   (ciclo Aliado -> Neutral -> Enemigo); los teams reales son fijos de lobby
#   y la victoria es por equipos (GameManager._check_conquest). No toca la sim.
# - Tributo: 100 de recurso via lockstep:
#     SimAPI.queue_command(mi_pid, "tribute", {"to": pid, "res": "food|wood|gold|stone", "amount": 100.0})
#   (GameManager._tribute valida fondos y vivos; todo determinista).
# - Taunts: chat via lockstep:
#     SimAPI.queue_command(mi_pid, "chat", {"text": "/11", "taunt": 11})
#   Incluye el clasico /11 jajaja.
# REDISENO VISUAL (sin tocar logica): marco pergamino oscuro estilo AoE2,
# cabecera de columnas, filas uniformes con highlight de objetivo seleccionado,
# panel inferior de objetivo con tributo directo y doble fila de taunts rapidos.

const TRIBUTE_AMOUNT := 100.0
const RES_KEYS := ["food", "wood", "gold", "stone"]
const RES_LABEL := {"food": "Alim", "wood": "Mad", "gold": "Oro", "stone": "Pied"}
const STANCES := ["Aliado", "Neutral", "Enemigo"]
# Taunts canon AoE2 (numero -> texto). El 11 es la risa.
const TAUNTS := {
	1: "Si.",
	2: "No.",
	3: "Comida, por favor.",
	4: "Madera, por favor.",
	5: "Oro, por favor.",
	6: "Piedra, por favor.",
	7: "Aaah!",
	8: "Salve, rey de los perdedores.",
	9: "Oooh.",
	10: "Jamas me ganaras.",
	11: "Jajaja! (11)",
	30: "Voy a atacar.",
	105: "Puedes quedarte con mi-CN si quieres.",
}
# Fila principal de taunts rapidos (se conserva igual que antes).
const QUICK_TAUNTS := [1, 2, 11, 30]
# Paleta AoE2: pergamino oscuro, dorado viejo, verde aliado, rojo enemigo.
const AOEC_BG := Color(0.13, 0.09, 0.05, 0.97)
const AOEC_BORDER := Color(0.72, 0.58, 0.30)
const AOEC_TEXT := Color(0.93, 0.86, 0.68)
const AOEC_DIM := Color(0.70, 0.62, 0.46)
const AOEC_ROW := Color(0.20, 0.14, 0.08, 0.95)
const AOEC_ROW_SEL := Color(0.32, 0.24, 0.11, 0.98)
const AOEC_ALLY := Color(0.45, 0.85, 0.45)
const AOEC_ENEMY := Color(1.0, 0.45, 0.40)
const AOEC_SELF := Color(1.0, 0.85, 0.40)

var local_player: int = 0
var selected_target: int = -1 # tributo/taunt van a este pid
var _stance_override := {} # pid int -> String (solo visual, ver cabecera)
var _rows := {} # pid int -> Dictionary de controles de la fila
var _list_box: VBoxContainer
var _status_label: Label
# Solo visual extra: panel de objetivo y barras de taunts (no afectan a la sim).
var _target_title: Label
var _target_tribute_bar: HBoxContainer
var _target_hint: Label

func _ready() -> void:
	_build_ui()
	refresh()

func set_local_player(pid: int) -> void:
	local_player = clampi(pid, 0, 7)
	refresh()

# ------------------------------------------------------------- UI ---
func _build_ui() -> void:
	# Marco exterior estilo AoE2: panel oscuro con borde dorado.
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel", _aoe2_frame_style())
	add_child(frame)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	frame.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)
	# Titulo centrado estilo AoE2.
	var title := Label.new()
	title.text = "DIPLOMACIA  (F4)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", AOEC_SELF)
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Click en una fila = objetivo de tributo  -  Tributo = 100"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", AOEC_DIM)
	subtitle.add_theme_font_size_override("font_size", 12)
	root.add_child(subtitle)
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", AOEC_TEXT)
	_status_label.add_theme_font_size_override("font_size", 13)
	root.add_child(_status_label)
	root.add_child(HSeparator.new())
	# Cabecera de columnas alineada con las filas.
	root.add_child(_make_header_row())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 3)
	scroll.add_child(_list_box)
	root.add_child(HSeparator.new())
	# Panel de objetivo seleccionado: tributo directo al objetivo.
	_target_title = Label.new()
	_target_title.text = ""
	_target_title.add_theme_color_override("font_color", AOEC_SELF)
	_target_title.add_theme_font_size_override("font_size", 13)
	root.add_child(_target_title)
	_target_tribute_bar = HBoxContainer.new()
	_target_tribute_bar.add_theme_constant_override("separation", 4)
	root.add_child(_target_tribute_bar)
	_target_hint = Label.new()
	_target_hint.text = "Tributo al objetivo: 100 de recurso por boton."
	_target_hint.add_theme_color_override("font_color", AOEC_DIM)
	_target_hint.add_theme_font_size_override("font_size", 12)
	root.add_child(_target_hint)
	# Barras de taunts rapidos (la principal incluye /11).
	root.add_child(_make_taunt_bar(QUICK_TAUNTS, 13))
	root.add_child(_make_taunt_bar([3, 4, 5, 6, 7, 8, 9, 10, 30, 105], 11))
	var hint := Label.new()
	hint.text = "Los taunts usan chat lockstep (global en la sim actual)."
	hint.add_theme_color_override("font_color", AOEC_DIM)
	hint.add_theme_font_size_override("font_size", 12)
	root.add_child(hint)

func _clear_rows() -> void:
	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()
	_rows.clear()

# Estilo del marco exterior: fondo pergamino oscuro + borde dorado.
func _aoe2_frame_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = AOEC_BG
	sb.border_color = AOEC_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

# Estilo de cada fila: resalta la fila del objetivo seleccionado.
func _aoe2_row_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = AOEC_ROW_SEL if selected else AOEC_ROW
	sb.border_color = AOEC_SELF if selected else Color(0.42, 0.33, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb

# Cabecera de columnas con los mismos anchos que las filas.
func _make_header_row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(16, 10)
	h.add_child(spacer)
	h.add_child(_header_label("Jugador", 170))
	h.add_child(_header_label("Equipo", 52))
	h.add_child(_header_label("Estado", 62))
	h.add_child(_header_label("Postura", 92))
	for res in RES_KEYS:
		h.add_child(_header_label(str(RES_LABEL.get(res, res)), 52))
	return h

func _header_label(text: String, min_w: float) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(min_w, 0)
	l.add_theme_color_override("font_color", AOEC_DIM)
	l.add_theme_font_size_override("font_size", 12)
	return l

# Fila de botones de taunt: mismo comando, solo cambia el numero.
func _make_taunt_bar(nums: Array, font_size: int) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for n in nums:
		var b := Button.new()
		b.text = "/%d" % n
		b.tooltip_text = "%d: %s" % [n, str(TAUNTS.get(n, ""))]
		b.add_theme_font_size_override("font_size", font_size)
		b.pressed.connect(_on_taunt_pressed.bind(n))
		bar.add_child(b)
	return bar

# ---------------------------------------------------------- datos ---
func _players_snapshot() -> Array:
	if typeof(GameManager) != TYPE_NIL and GameManager != null and GameManager.get("players") != null:
		return (GameManager.get("players") as Array).duplicate()
	return []

func get_stance(pid: int) -> String:
	if pid == local_player:
		return "Yo"
	if _stance_override.has(pid):
		return str(_stance_override[pid])
	return _team_stance(pid)

func _team_stance(pid: int) -> String:
	var pls := _players_snapshot()
	if pid < 0 or pid >= pls.size() or local_player < 0 or local_player >= pls.size():
		return "Neutral"
	var mine: Dictionary = pls[local_player]
	var other: Dictionary = pls[pid]
	if int(mine.get("team", local_player)) == int(other.get("team", pid)):
		return "Aliado"
	return "Enemigo"

func cycle_stance(pid: int) -> void:
	# Solo visual: no existe cambio de equipo en la sim (lobby fijo).
	var cur := get_stance(pid)
	var next := "Neutral"
	match cur:
		"Aliado":
			next = "Neutral"
		"Neutral":
			next = "Enemigo"
		_:
			next = "Aliado"
	_stance_override[pid] = next
	refresh()

func refresh() -> void:
	if _list_box == null:
		return
	_clear_rows()
	var pls := _players_snapshot()
	# Siempre 8 filas: slots vacios se muestran como "---".
	for pid in 8:
		_add_row(pid, pls[pid] if pid < pls.size() else {})
	_update_status()
	_rebuild_target_bar()

func _add_row(pid: int, p: Dictionary) -> void:
	var selected := pid == selected_target
	# Panel por fila para el highlight del objetivo (puro visual).
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _aoe2_row_style(selected))
	_list_box.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	var empty := p.is_empty()
	# Muestra de color del jugador (misma fuente: SimAPI.get_player_color).
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(16, 16)
	if not empty and typeof(SimAPI) != TYPE_NIL and SimAPI != null and SimAPI.has_method("get_player_color"):
		swatch.color = SimAPI.get_player_color(pid)
	else:
		swatch.color = Color(0.3, 0.3, 0.3)
	row.add_child(swatch)
	# Nombre = selector de objetivo (mismo texto y senal que antes).
	var alive := bool(p.get("alive", true)) if not empty else false
	var name_l := Button.new()
	name_l.flat = true
	name_l.custom_minimum_size = Vector2(170, 0)
	name_l.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if empty:
		name_l.text = "%d: ---" % (pid + 1)
		name_l.disabled = true
	else:
		name_l.text = "%d:%s Eq%d%s" % [pid + 1, str(p.get("civ", "?")), int(p.get("team", pid)), "" if alive else " (X)"]
		if selected:
			name_l.text = "> " + name_l.text
		name_l.tooltip_text = "Objetivo tributo/taunt"
		name_l.pressed.connect(_on_target_pressed.bind(pid))
		if selected:
			name_l.modulate = Color(1, 1, 0.5)
	row.add_child(name_l)
	# Columnas equipo y vivo/muerto (derivadas de los mismos datos, visual).
	var team_l := Label.new()
	team_l.custom_minimum_size = Vector2(52, 0)
	team_l.text = "-" if empty else "Eq%d" % int(p.get("team", pid))
	team_l.add_theme_color_override("font_color", AOEC_TEXT)
	team_l.add_theme_font_size_override("font_size", 12)
	row.add_child(team_l)
	var alive_l := Label.new()
	alive_l.custom_minimum_size = Vector2(62, 0)
	if empty:
		alive_l.text = "-"
		alive_l.add_theme_color_override("font_color", AOEC_DIM)
	elif alive:
		alive_l.text = "Vivo"
		alive_l.add_theme_color_override("font_color", AOEC_ALLY)
	else:
		alive_l.text = "Muerto"
		alive_l.add_theme_color_override("font_color", AOEC_ENEMY)
	alive_l.add_theme_font_size_override("font_size", 12)
	row.add_child(alive_l)
	# Boton de postura (mismo ciclo visual Aliado -> Neutral -> Enemigo).
	var stance_b := Button.new()
	stance_b.custom_minimum_size = Vector2(92, 0)
	if pid == local_player and not empty:
		stance_b.text = "Yo"
		stance_b.disabled = true
		stance_b.modulate = AOEC_SELF
	elif empty:
		stance_b.text = "-"
		stance_b.disabled = true
	else:
		stance_b.text = get_stance(pid)
		stance_b.tooltip_text = "Click para cambiar vista Aliado/Neutral/Enemigo (solo visual)"
		stance_b.pressed.connect(cycle_stance.bind(pid))
		match get_stance(pid):
			"Aliado":
				stance_b.modulate = Color(0.5, 1, 0.5)
			"Enemigo":
				stance_b.modulate = Color(1, 0.5, 0.5)
			_:
				stance_b.modulate = Color(0.9, 0.9, 0.9)
	row.add_child(stance_b)
	# Tributo 100 por recurso (deshabilitado si soy yo, slot vacio o muerto).
	for res in RES_KEYS:
		var tb := Button.new()
		tb.text = str(RES_LABEL.get(res, res))
		tb.custom_minimum_size = Vector2(52, 0)
		tb.tooltip_text = "Tributo 100 %s a J%d" % [res, pid + 1]
		tb.disabled = empty or pid == local_player or not bool(p.get("alive", true))
		tb.pressed.connect(send_tribute.bind(pid, res))
		row.add_child(tb)
	_rows[pid] = {"row": row, "stance": stance_b, "panel": panel, "name": name_l}

func _on_target_pressed(pid: int) -> void:
	selected_target = pid
	refresh()

func _update_status() -> void:
	if selected_target >= 0:
		_status_label.text = "Objetivo: J%d (%s)" % [selected_target + 1, get_stance(selected_target)]
	else:
		_status_label.text = "Sin objetivo (click en un jugador)"

# Panel inferior: tributo directo al objetivo (reusa send_tribute, 100 fijo).
func _rebuild_target_bar() -> void:
	if _target_tribute_bar == null:
		return
	for c in _target_tribute_bar.get_children():
		_target_tribute_bar.remove_child(c)
		c.queue_free()
	var pls := _players_snapshot()
	var valid := selected_target >= 0 and selected_target < 8 and selected_target != local_player
	var p: Dictionary = pls[selected_target] if valid and selected_target < pls.size() else {}
	var target_alive := valid and not p.is_empty() and bool(p.get("alive", true))
	if selected_target >= 0 and not p.is_empty():
		_target_title.text = "Objetivo J%d: %s Eq%d (%s)" % [selected_target + 1, str(p.get("civ", "?")), int(p.get("team", selected_target)), get_stance(selected_target)]
	elif selected_target >= 0:
		_target_title.text = "Objetivo J%d: slot vacio" % (selected_target + 1)
	else:
		_target_title.text = "Sin objetivo: haz click en una fila."
	_target_hint.visible = valid and target_alive
	for res in RES_KEYS:
		var tb := Button.new()
		tb.text = "100 %s > J%d" % [str(RES_LABEL.get(res, res)), selected_target + 1]
		tb.tooltip_text = "Tributo 100 %s a J%d" % [res, selected_target + 1]
		tb.disabled = not target_alive
		tb.pressed.connect(send_tribute.bind(selected_target, res))
		_target_tribute_bar.add_child(tb)

# -------------------------------------------------------- comandos ---
func send_tribute(to_pid: int, res: String) -> void:
	if to_pid == local_player or to_pid < 0 or to_pid >= 8:
		return
	if typeof(SimAPI) == TYPE_NIL or SimAPI == null:
		return
	SimAPI.queue_command(local_player, "tribute", {"to": to_pid, "res": res, "amount": TRIBUTE_AMOUNT})

func send_taunt(num: int) -> void:
	if typeof(SimAPI) == TYPE_NIL or SimAPI == null:
		return
	var text := "/%d" % num
	SimAPI.queue_command(local_player, "chat", {"text": text, "taunt": num, "msg": str(TAUNTS.get(num, text))})

func _on_taunt_pressed(num: int) -> void:
	# Si hay objetivo, el taunt se dirige (payload "to" informativo; el chat
	# es global en la sim actual). Si no, chat global igualmente.
	send_taunt(num)

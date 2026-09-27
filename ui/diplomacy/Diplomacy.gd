extends Control
# Diplomacy - panel de diplomacia estilo AoE2 (solo cliente, no entra en hash).
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

var local_player: int = 0
var selected_target: int = -1 # tributo/taunt van a este pid
var _stance_override := {} # pid int -> String (solo visual, ver cabecera)
var _rows := {} # pid int -> Dictionary de controles de la fila
var _list_box: VBoxContainer
var _status_label: Label

func _ready() -> void:
	_build_ui()
	refresh()

func set_local_player(pid: int) -> void:
	local_player = clampi(pid, 0, 7)
	refresh()

# ------------------------------------------------------------- UI ---
func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	var title := Label.new()
	title.text = "Diplomacia (F4)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	_status_label = Label.new()
	_status_label.text = ""
	root.add_child(_status_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)
	# Barra inferior: taunts rapidos (incluye /11).
	var taunt_row := HBoxContainer.new()
	root.add_child(taunt_row)
	for n in [1, 2, 11, 30]:
		var b := Button.new()
		b.text = "/%d" % n
		b.tooltip_text = "%d: %s" % [n, str(TAUNTS.get(n, ""))]
		b.pressed.connect(_on_taunt_pressed.bind(n))
		taunt_row.add_child(b)
	var hint := Label.new()
	hint.text = "Click fila = objetivo tributo. Tributo = 100."
	hint.add_theme_font_size_override("font_size", 12)
	root.add_child(hint)

func _clear_rows() -> void:
	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()
	_rows.clear()

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

func _add_row(pid: int, p: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_list_box.add_child(row)
	var empty := p.is_empty()
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(14, 14)
	if not empty and typeof(SimAPI) != TYPE_NIL and SimAPI != null and SimAPI.has_method("get_player_color"):
		swatch.color = SimAPI.get_player_color(pid)
	else:
		swatch.color = Color(0.3, 0.3, 0.3)
	row.add_child(swatch)
	var name_l := Button.new()
	name_l.flat = true
	if empty:
		name_l.text = "%d: ---" % (pid + 1)
		name_l.disabled = true
	else:
		var alive := bool(p.get("alive", true))
		name_l.text = "%d:%s Eq%d%s" % [pid + 1, str(p.get("civ", "?")), int(p.get("team", pid)), "" if alive else " (X)"]
		name_l.tooltip_text = "Objetivo tributo/taunt"
		name_l.pressed.connect(_on_target_pressed.bind(pid))
		if pid == selected_target:
			name_l.modulate = Color(1, 1, 0.5)
	row.add_child(name_l)
	var stance_b := Button.new()
	if pid == local_player and not empty:
		stance_b.text = "Yo"
		stance_b.disabled = true
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
		tb.tooltip_text = "Tributo 100 %s a J%d" % [res, pid + 1]
		tb.disabled = empty or pid == local_player or not bool(p.get("alive", true))
		tb.pressed.connect(send_tribute.bind(pid, res))
		row.add_child(tb)
	_rows[pid] = {"row": row, "stance": stance_b}

func _on_target_pressed(pid: int) -> void:
	selected_target = pid
	refresh()

func _update_status() -> void:
	if selected_target >= 0:
		_status_label.text = "Objetivo: J%d (%s)" % [selected_target + 1, get_stance(selected_target)]
	else:
		_status_label.text = "Sin objetivo (click en un jugador)"

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

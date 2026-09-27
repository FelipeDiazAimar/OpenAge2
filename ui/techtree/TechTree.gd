extends Control
# TechTree - arbol de tecnologias estilo AoE2 (solo cliente, no entra en hash).
# - Agrupado por edad (Feudal / Castillos / Imperial) con secciones por edificio.
# - Iconos TEXTO (sin assets): cada tech lleva glifo segun edificio + nombre.
# - Color: VERDE = disponible (can_research ok), GRIS = bloqueado (con motivo
#   en tooltip: need_age / missing_prereq / civ_disabled / no_resources /
#   missing_building / already_researching), AZUL = completada, AMARILLO = en curso.
# - Click en disponible investiga via lockstep (Tech.gd usa "research_tech"):
#     SimAPI.queue_command(mi_pid, "research_tech", {"tech_id": "forja"})
#   (NUNCA "research": reservado a avance de edad en GameManager.)
# - Fuente de datos: nodo Techs si existe en escena (systems/research/Techs.gd);
#   si no, FALLBACK local (replica Techs.FALLBACK_TECHS) + edad de GameManager.

const AGE_ORDER := ["feudal", "castillos", "imperial"]
const AGE_TITLE := {"feudal": "II - Feudal", "castillos": "III - Castillos", "imperial": "IV - Imperial"}
const BUILDING_ICON := {"herreria": "[Forja]", "universidad": "[Univ]", "monasterio": "[Mon]", "castillo": "[Cast]"}
const BUILDING_ORDER := ["herreria", "universidad", "monasterio", "castillo"]
# Fallback si no hay nodo Techs en escena (mismos campos que Techs.FALLBACK_TECHS).
const FALLBACK_TECHS := [
	{"id": "forja", "building": "herreria", "edad": "feudal"},
	{"id": "armadura_inf_1", "building": "herreria", "edad": "feudal"},
	{"id": "ataque_arq_1", "building": "herreria", "edad": "feudal"},
	{"id": "armadura_arq_1", "building": "herreria", "edad": "feudal"},
	{"id": "ataque_cab_1", "building": "herreria", "edad": "feudal"},
	{"id": "armadura_cab_1", "building": "herreria", "edad": "feudal"},
	{"id": "hierro_fundido", "building": "herreria", "edad": "castillos"},
	{"id": "armadura_inf_2", "building": "herreria", "edad": "castillos"},
	{"id": "ataque_arq_2", "building": "herreria", "edad": "castillos"},
	{"id": "armadura_arq_2", "building": "herreria", "edad": "castillos"},
	{"id": "ataque_cab_2", "building": "herreria", "edad": "castillos"},
	{"id": "armadura_cab_2", "building": "herreria", "edad": "castillos"},
	{"id": "balistica", "building": "universidad", "edad": "castillos"},
	{"id": "redencion", "building": "monasterio", "edad": "castillos"},
	{"id": "fervor", "building": "monasterio", "edad": "castillos"},
	{"id": "santidad", "building": "monasterio", "edad": "castillos"},
	{"id": "alto_horno", "building": "herreria", "edad": "imperial"},
	{"id": "armadura_inf_3", "building": "herreria", "edad": "imperial"},
	{"id": "ataque_arq_3", "building": "herreria", "edad": "imperial"},
	{"id": "armadura_arq_3", "building": "herreria", "edad": "imperial"},
	{"id": "ataque_cab_3", "building": "herreria", "edad": "imperial"},
	{"id": "armadura_cab_3", "building": "herreria", "edad": "imperial"},
	{"id": "quimica", "building": "universidad", "edad": "imperial"},
	{"id": "iluminacion", "building": "monasterio", "edad": "imperial"},
	{"id": "teocracia", "building": "monasterio", "edad": "imperial"},
]

const COL_AVAIL := Color(0.35, 1.0, 0.35) # verde disponible
const COL_BLOCK := Color(0.45, 0.45, 0.45) # gris bloqueado
const COL_DONE := Color(0.4, 0.7, 1.0) # azul completada
const COL_BUSY := Color(1.0, 0.9, 0.3) # amarillo en curso

var local_player: int = 0
var _techs_node: Node = null
var _tree_box: VBoxContainer
var _status_label: Label

func _ready() -> void:
	_techs_node = _find_techs()
	_build_ui()
	refresh()
	# Refrescar cuando la sim avanza (progreso/investigacion terminada).
	if typeof(EventBus) != TYPE_NIL and EventBus != null:
		if EventBus.has_signal("tech_researched") and not EventBus.tech_researched.is_connected(_on_tech_signal):
			EventBus.tech_researched.connect(_on_tech_signal)
		if EventBus.has_signal("tech_progress") and not EventBus.tech_progress.is_connected(_on_tech_signal):
			EventBus.tech_progress.connect(_on_tech_signal)
		if EventBus.has_signal("tech_cancelled") and not EventBus.tech_cancelled.is_connected(_on_tech_signal):
			EventBus.tech_cancelled.connect(_on_tech_signal)
		if not EventBus.tick_finished.is_connected(_on_tick_refresh):
			EventBus.tick_finished.connect(_on_tick_refresh)

func set_local_player(pid: int) -> void:
	local_player = clampi(pid, 0, 7)
	refresh()

func _on_tech_signal(_a = null, _b = null, _c = null, _d = null) -> void:
	refresh()

var _last_refresh_tick := -100
func _on_tick_refresh(t: int) -> void:
	# Refresco barato: 1 vez/sec (10 ticks). La UI es solo cliente.
	if t - _last_refresh_tick >= 10:
		_last_refresh_tick = t
		refresh()

# ------------------------------------------------------------- UI ---
func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var title := Label.new()
	title.text = "Arbol de tecnologias (T)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	_status_label = Label.new()
	_status_label.text = ""
	root.add_child(_status_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_tree_box = VBoxContainer.new()
	_tree_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tree_box)

func refresh() -> void:
	if _tree_box == null:
		return
	if _techs_node == null or not is_instance_valid(_techs_node):
		_techs_node = _find_techs()
	for c in _tree_box.get_children():
		_tree_box.remove_child(c)
		c.queue_free()
	var busy_id := _researching_id()
	_update_status(busy_id)
	for age in AGE_ORDER:
		var header := Label.new()
		header.text = str(AGE_TITLE.get(age, age))
		_tree_box.add_child(header)
		for building in BUILDING_ORDER:
			var ids := _tech_ids_for(age, building)
			if ids.is_empty():
				continue
			var sec := Label.new()
			sec.text = "  %s %s" % [str(BUILDING_ICON.get(building, "[?]")), building.capitalize()]
			_tree_box.add_child(sec)
			var grid := GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", 4)
			grid.add_theme_constant_override("v_separation", 4)
			_tree_box.add_child(grid)
			for tid in ids:
				grid.add_child(_make_tech_button(tid, busy_id))

func _make_tech_button(tid: String, busy_id: String) -> Button:
	var b := Button.new()
	var d := _tech_data(tid)
	var nombre := str(d.get("nombre", tid))
	var icon := str(BUILDING_ICON.get(str(d.get("building", "")), "[?]"))
	var state := tech_state(local_player, tid)
	var cost_txt := _cost_text(d)
	match state:
		"done":
			b.text = "[OK] %s %s" % [icon, nombre]
			b.modulate = COL_DONE
			b.disabled = true
			b.tooltip_text = "%s: completada" % tid
		"busy":
			b.text = "[...] %s %s" % [icon, nombre]
			b.modulate = COL_BUSY
			b.disabled = true
			b.tooltip_text = "%s: investigando %s" % [tid, busy_id]
		"avail":
			b.text = "%s %s\n%s" % [icon, nombre, cost_txt]
			b.modulate = COL_AVAIL
			b.disabled = false
			b.tooltip_text = "%s: click para investigar (%s)" % [tid, cost_txt]
			b.pressed.connect(research.bind(tid))
		_:
			var reason := str(state)
			b.text = "[X] %s %s\n%s" % [icon, nombre, cost_txt]
			b.modulate = COL_BLOCK
			b.disabled = true # gris bloqueado: no clicable
			b.tooltip_text = "%s: bloqueada (%s)" % [tid, reason]
	return b

func _cost_text(d: Dictionary) -> String:
	var cost: Dictionary = d.get("coste", d.get("cost", {}))
	if cost.is_empty():
		return "sin coste"
	var parts: PackedStringArray = []
	for k in ["food", "wood", "gold", "stone"]:
		if cost.has(k):
			parts.append("%s %d" % [str(k).left(1).to_upper(), int(float(cost[k]))])
	return " ".join(parts) if not parts.is_empty() else str(cost)

func _update_status(busy_id: String) -> void:
	if not busy_id.is_empty():
		_status_label.text = "Investigando: %s (una a la vez)" % busy_id
	elif _techs_node != null and _techs_node.has_method("is_researching") and bool(_techs_node.call("is_researching", local_player)):
		_status_label.text = "Investigando... (una a la vez)"
	else:
		_status_label.text = "J%d - verde=disponible, gris=bloqueada" % (local_player + 1)

# ---------------------------------------------------------- datos ---
func _find_techs() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for path in ["/root/Main/Techs", "/root/Techs", "/root/Game/Techs"]:
		var n := tree.root.get_node_or_null(path)
		if n != null:
			return n
	var cur := tree.current_scene
	if cur != null and cur.has_node("Techs"):
		return cur.get_node("Techs")
	if cur != null:
		var found := cur.find_child("Techs", true, false)
		if found != null:
			return found
	# Ultimo recurso: cualquier nodo con metodo can_research/is_completed.
	for n in tree.get_nodes_in_group("techs"):
		return n as Node
	return null

func _all_tech_ids() -> Array:
	if _techs_node != null and ( _techs_node.get("techs_db") is Dictionary ):
		var ids: Array = (_techs_node.get("techs_db") as Dictionary).keys()
		ids.sort()
		return ids
	var out: Array = []
	for t in FALLBACK_TECHS:
		out.append(str(t["id"]))
	out.sort()
	return out

func _tech_data(tid: String) -> Dictionary:
	if _techs_node != null and _techs_node.has_method("get_tech_data"):
		return _techs_node.call("get_tech_data", tid)
	for t in FALLBACK_TECHS:
		if str(t["id"]) == tid:
			return (t as Dictionary).duplicate(true)
	return {"id": tid, "nombre": tid}

func _tech_ids_for(age: String, building: String) -> Array:
	var out: Array = []
	for tid in _all_tech_ids():
		var d := _tech_data(str(tid))
		if str(d.get("edad", d.get("age", ""))) == age and str(d.get("building", d.get("edificio", ""))) == building:
			out.append(str(tid))
	out.sort()
	return out

func _researching_id() -> String:
	if _techs_node != null and _techs_node.has_method("get_progress"):
		var r: Dictionary = _techs_node.call("get_progress", local_player)
		return str(r.get("tech_id", ""))
	return ""

# --------------------------------------------------------- estado ---
# Devuelve "done" | "busy" | "avail" | reason_bloqueo (gris).
func tech_state(pid: int, tech_id: String) -> String:
	var tid := tech_id.to_lower().strip_edges()
	if _techs_node != null and _techs_node.has_method("is_completed") and bool(_techs_node.call("is_completed", pid, tid)):
		return "done"
	if _techs_node != null and _techs_node.has_method("is_researching") and bool(_techs_node.call("is_researching", pid)):
		var cur := _researching_id() if pid == local_player else ""
		if cur == tid or pid != local_player:
			return "busy" if cur == tid or pid != local_player else "busy"
	if _techs_node != null and _techs_node.has_method("can_research"):
		var chk: Dictionary = _techs_node.call("can_research", pid, tid)
		if bool(chk.get("ok", false)):
			return "avail"
		return str(chk.get("reason", "blocked"))
	# Fallback sin nodo Techs: edad + prerequisitos minimos.
	return _fallback_state(pid, tid)

func _fallback_state(pid: int, tid: String) -> String:
	var order := ["alta_edad_media", "feudal", "castillos", "imperial"]
	var cur_age := "feudal"
	if typeof(GameManager) != TYPE_NIL and GameManager != null and GameManager.has_method("get_player"):
		cur_age = str((GameManager.call("get_player", pid) as Dictionary).get("age", "feudal"))
	var need := str(_tech_data(tid).get("edad", "feudal"))
	if order.find(cur_age) < order.find(need):
		return "need_age:" + need
	return "avail"

# -------------------------------------------------------- comandos ---
func research(tech_id: String) -> void:
	if typeof(SimAPI) == TYPE_NIL or SimAPI == null:
		return
	SimAPI.queue_command(local_player, "research_tech", {"tech_id": tech_id.to_lower().strip_edges()})

func cancel() -> void:
	if typeof(SimAPI) == TYPE_NIL or SimAPI == null:
		return
	SimAPI.queue_command(local_player, "cancel_research_tech", {})

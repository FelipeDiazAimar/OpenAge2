extends Control
class_name SelectionSystem
# Selection - seleccion RTS estilo AoE2, SOLO CLIENTE.
#
# NO toca la sim: nada de SimAPI / tick / RNG / hash desync. Todo lo visual
# (camara, viewport, Time para doble-click) esta permitido aqui porque nunca
# entra en el lockstep. Los sistemas de sim (VillagerAI, MilitaryAI, Economy)
# leen la seleccion solo via EventBus.selection_changed (Array[int] de ids).
#
# Funciones (todas locales al jugador `local_player_id`):
#   - Click izq: selecciona la unidad propia mas cercana (radio PICK_RADIUS px).
#   - Drag-box izq: rectangulo de seleccion (propias dentro del rect).
#   - Doble-click izq: todas las visibles en pantalla del mismo unit_type.
#   - Shift + click/box: anade (si no estaba) / quita (si estaba) en vez de
#     reemplazar. Sin Shift se reemplaza.
#   - Ctrl+1..9: guarda grupo. 1..9: recupera. Doble-pulsacion del numero:
#     centra camara en el centroide. Shift+Numero: anade el grupo a la actual.
#   - "." (KEY_PERIOD): siguiente aldeano idle (round-robin, centra camara).
#   - "/" (KEY_SLASH): todos los militares idle (sin mover camara).
#   - Tope MAX_SELECTION = 60. Todo cambio emite EventBus.selection_changed.
#
# Registro: las unidades se registran con register_unit(). Como fallback se
# puede escanear el grupo "selectable" (nodos con metas unit_id/player_id/
# unit_type). Campos por unidad: {node, player_id, unit_type, military, idle,
# pos}. `idle`/`military` los actualizan los dueños (set_idle) o los tests.
# Uso headless: set_test_screen_pos() inyecta posiciones de pantalla.

const MAX_SELECTION := 60
const PICK_RADIUS := 24.0 # px alrededor del click para single-pick
const DRAG_THRESHOLD := 6.0 # px para distinguir click de drag-box
const DOUBLE_CENTER_MS := 400 # doble-pulsacion de grupo -> centrar camara
const VILLAGER_TYPES: Array[String] = ["aldeano", "villager", "aldeana"]
const _CAM_FALLBACK_OFFSET := Vector3(20.0, 20.0, 20.0) # = AoeCamera inicial

## Jugador dueno del teclado/raton. Solo sus unidades son seleccionables.
var local_player_id := 0

# id -> {node: Node (puede ser null en tests), player_id: int,
#         unit_type: String (minusculas), military: bool, idle: bool,
#         pos: Vector3 (fallback si node es null o invalido)}
var _units := {}
# Seleccion actual: Array[int] ordenada, sin duplicados, max 60.
var selected: Array[int] = []
# 1..9 -> Array[int] de ids (se podan los que ya no existen al recuperar).
var _groups := {}
# id -> Vector2 pantalla (override para tests headless sin camara).
var _test_screen_pos := {}

var _pressing := false
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO
var _suppress_click := false # el doble-click ya resolvio en press: no click en release
var _idle_cursor := 0
var _last_group_press := {} # num -> msec del ultimo recall


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in range(1, 10):
		_groups[n] = []
	if not EventBus.unit_died.is_connected(_on_unit_died):
		EventBus.unit_died.connect(_on_unit_died)


# ------------------------------------------------------------- registro ---

func register_unit(unit_id: int, node: Node = null, player_id: int = -1, unit_type: String = "", opts: Dictionary = {}) -> void:
	var pid := local_player_id if player_id < 0 else player_id
	var pos := Vector3.ZERO
	if is_instance_valid(node) and node is Node3D:
		pos = (node as Node3D).global_position
	elif opts.has("pos"):
		pos = _as_vec3(opts["pos"])
	_units[unit_id] = {
		"node": node, "player_id": pid,
		"unit_type": unit_type.to_lower().strip_edges(),
		"military": bool(opts.get("military", false)),
		"idle": bool(opts.get("idle", unit_type.to_lower().strip_edges() in VILLAGER_TYPES or bool(opts.get("military", false)))),
		"pos": pos,
	}
	if opts.has("military"):
		_units[unit_id]["military"] = bool(opts["military"])
	if opts.has("idle"):
		_units[unit_id]["idle"] = bool(opts["idle"])


func unregister_unit(unit_id: int) -> void:
	_units.erase(unit_id)
	_test_screen_pos.erase(unit_id)
	if selected.has(unit_id):
		selected.erase(unit_id)
		_emit_changed()
	for n in _groups.keys():
		(_groups[n] as Array).erase(unit_id)


func clear_units() -> void:
	_units.clear()
	_test_screen_pos.clear()
	_idle_cursor = 0
	clear_selection(false)
	for n in _groups.keys():
		_groups[n] = []


func set_idle(unit_id: int, idle: bool) -> void:
	if _units.has(unit_id):
		_units[unit_id]["idle"] = idle


func set_military(unit_id: int, military: bool) -> void:
	if _units.has(unit_id):
		_units[unit_id]["military"] = military


func set_test_screen_pos(unit_id: int, screen_pos: Vector2) -> void:
	_test_screen_pos[unit_id] = screen_pos


func clear_test_screen_pos() -> void:
	_test_screen_pos.clear()


## Escanea el grupo "selectable" (nodos con metas unit_id/player_id/unit_type).
## Llamar tras spawnear oleadas si no se registra a mano.
func refresh_from_group() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("selectable"):
		if not (n is Node):
			continue
		var uid := -1
		if n.has_meta("unit_id"):
			uid = int(n.get_meta("unit_id"))
		elif n.has_method("get") and n.get("unit_id") != null:
			uid = int(n.get("unit_id"))
		if uid < 0:
			continue
		var pid := local_player_id
		if n.has_meta("player_id"):
			pid = int(n.get_meta("player_id"))
		var utype := ""
		if n.has_meta("unit_type"):
			utype = str(n.get_meta("unit_type"))
		if not _units.has(uid):
			register_unit(uid, n, pid, utype)
		else:
			_units[uid]["node"] = n


# ------------------------------------------------------------ consulta ---

func get_selected() -> Array[int]:
	return selected.duplicate()


## Tipo ("aldeano", "centro_urbano"...) de una unidad registrada. "" si no existe.
func get_unit_type(unit_id: int) -> String:
	if _units.has(unit_id):
		return str((_units[unit_id] as Dictionary).get("unit_type", ""))
	return ""


func is_selected(unit_id: int) -> bool:
	return selected.has(unit_id)


func get_group(num: int) -> Array[int]:
	if not _groups.has(num):
		return []
	return (_groups[num] as Array).duplicate()


func clear_selection(emit_signal := true) -> void:
	selected.clear()
	if emit_signal:
		_emit_changed()


## Reemplaza la seleccion (ordena, dedup, poda inexistentes, tope 60).
func set_selection(ids: Array, emit_signal := true) -> void:
	_apply_selection(_dedup_sorted(ids, true), emit_signal)


# ---------------------------------------------------------------- input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_press(mb)
			else:
				_on_left_release(mb)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pressing:
		var mm := event as InputEventMouseMotion
		_drag_current = mm.position
		if not _dragging and _drag_start.distance_to(_drag_current) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			queue_redraw()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and _handle_hotkey(k):
			get_viewport().set_input_as_handled()


func _on_left_press(mb: InputEventMouseButton) -> void:
	_pressing = true
	_dragging = false
	_drag_start = mb.position
	_drag_current = mb.position
	_suppress_click = false
	if mb.double_click:
		# Doble-click: mismo tipo visible en pantalla (respeta Shift).
		var picked := pick_unit(mb.position)
		if picked >= 0:
			_suppress_click = true
			select_same_type_on_screen(picked, Input.is_key_pressed(KEY_SHIFT))


func _on_left_release(mb: InputEventMouseButton) -> void:
	_pressing = false
	var was_drag := _dragging
	_dragging = false
	queue_redraw()
	if _suppress_click:
		_suppress_click = false
		return
	var add_mode := Input.is_key_pressed(KEY_SHIFT)
	if was_drag:
		select_in_rect(_rect_from_points(_drag_start, mb.position), add_mode)
	else:
		_click_select(mb.position, add_mode)


func _handle_hotkey(k: InputEventKey) -> bool:
	# Grupos 1..9 (keycode fisico o logico).
	var num := _digit_of(k)
	if num >= 1 and num <= 9:
		if k.ctrl_pressed and not k.shift_pressed:
			save_group(num)
			return true
		if k.shift_pressed and not k.ctrl_pressed:
			add_group_to_selection(num)
			return true
		if not k.ctrl_pressed and not k.shift_pressed:
			recall_group(num)
			return true
		return false
	match k.keycode:
		KEY_PERIOD:
			select_next_idle_villager()
			return true
		KEY_SLASH:
			select_all_idle_military()
			return true
		_:
			pass
	# Fallback: physical_keycode (teclados no-latinos).
	match k.physical_keycode:
		KEY_PERIOD:
			select_next_idle_villager()
			return true
		KEY_SLASH:
			select_all_idle_military()
			return true
		_:
			return false


static func _digit_of(k: InputEventKey) -> int:
	for code in [k.keycode, k.physical_keycode]:
		match code:
			KEY_1: return 1
			KEY_2: return 2
			KEY_3: return 3
			KEY_4: return 4
			KEY_5: return 5
			KEY_6: return 6
			KEY_7: return 7
			KEY_8: return 8
			KEY_9: return 9
	return -1


# -------------------------------------------------------- seleccion ---

## Click simple: unidad propia mas cercana al punto (radio PICK_RADIUS).
func _click_select(screen_pos: Vector2, add_mode: bool) -> void:
	var picked := pick_unit(screen_pos)
	if picked < 0:
		if not add_mode:
			clear_selection()
		return
	if add_mode:
		_toggle_ids([picked])
	else:
		_apply_selection([picked])


## Unidad propia viva mas cercana a un punto de pantalla. -1 si ninguna.
func pick_unit(screen_pos: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS + 0.000001
	var ids: Array = _units.keys()
	ids.sort()
	for uid in ids:
		var u: Dictionary = _units[uid]
		if int(u["player_id"]) != local_player_id:
			continue
		var sp := _screen_pos_of(int(uid))
		if sp.x < -900000.0:
			continue
		var d := sp.distance_to(screen_pos)
		if d < best_d - 0.000001 or (absf(d - best_d) <= 0.000001 and int(uid) < best):
			best_d = d
			best = int(uid)
	return best


## Todas las propias dentro del rect de pantalla (ordenadas, tope 60).
func select_in_rect(rect: Rect2, add_mode: bool) -> void:
	var r := rect.abs()
	var found: Array = []
	var ids: Array = _units.keys()
	ids.sort()
	for uid in ids:
		var u: Dictionary = _units[uid]
		if int(u["player_id"]) != local_player_id:
			continue
		var sp := _screen_pos_of(int(uid))
		if sp.x < -900000.0:
			continue
		if r.has_point(sp):
			found.append(int(uid))
	if add_mode:
		_toggle_ids(found)
	else:
		_apply_selection(found)


## Doble-click: mismo unit_type, propias y visibles en pantalla.
func select_same_type_on_screen(unit_id: int, add_mode: bool) -> void:
	if not _units.has(unit_id):
		return
	var want := str(_units[unit_id]["unit_type"])
	var vp_rect := _viewport_rect()
	var found: Array = []
	var ids: Array = _units.keys()
	ids.sort()
	for uid in ids:
		var u: Dictionary = _units[uid]
		if int(u["player_id"]) != local_player_id:
			continue
		if str(u["unit_type"]) != want:
			continue
		var sp := _screen_pos_of(int(uid))
		if sp.x < -900000.0:
			continue
		if vp_rect.has_point(sp):
			found.append(int(uid))
	if add_mode:
		_merge_ids(found)
	else:
		_apply_selection(found)


# -------------------------------------------------------------- grupos ---

func save_group(num: int) -> void:
	_groups[num] = selected.duplicate()


func recall_group(num: int) -> void:
	var g := _pruned_group(num)
	var now_msec := Time.get_ticks_msec()
	var last := int(_last_group_press.get(num, -1000000))
	_last_group_press[num] = now_msec
	_apply_selection(g)
	# Doble-pulsacion del mismo numero: centrar camara en el centroide.
	if not g.is_empty() and now_msec - last < DOUBLE_CENTER_MS:
		center_on_ids(g)


## Shift+Numero: union del grupo con la seleccion actual.
func add_group_to_selection(num: int) -> void:
	_merge_ids(_pruned_group(num))


func _pruned_group(num: int) -> Array:
	var out: Array = []
	for uid in (_groups.get(num, []) as Array):
		if _units.has(int(uid)):
			out.append(int(uid))
	out.sort()
	return out


# --------------------------------------------------------------- hotkeys ---

## ".": siguiente aldeano idle propio (round-robin por id, centra camara).
## Devuelve el id o -1 si no hay.
func select_next_idle_villager(player_id: int = -1) -> int:
	var pid := local_player_id if player_id < 0 else player_id
	var idles: Array = []
	for uid in _units.keys():
		var u: Dictionary = _units[uid]
		if int(u["player_id"]) != pid:
			continue
		if not _is_villager(u):
			continue
		if bool(u.get("idle", false)):
			idles.append(int(uid))
	idles.sort()
	if idles.is_empty():
		return -1
	_idle_cursor = _idle_cursor % idles.size()
	var chosen := int(idles[_idle_cursor])
	_idle_cursor = (_idle_cursor + 1) % idles.size()
	_apply_selection([chosen])
	center_on_ids([chosen])
	return chosen


## "/": todos los militares idle propios (tope 60, sin mover camara).
func select_all_idle_military(player_id: int = -1) -> Array:
	var pid := local_player_id if player_id < 0 else player_id
	var found: Array = []
	for uid in _units.keys():
		var u: Dictionary = _units[uid]
		if int(u["player_id"]) != pid:
			continue
		if not bool(u.get("military", false)):
			continue
		if not bool(u.get("idle", false)):
			continue
		found.append(int(uid))
	_apply_selection(found)
	return selected.duplicate()


# -------------------------------------------------------------- camara ---

## Centra la camara en el centroide de los ids (via focus_camera + fallback).
func center_on_ids(ids: Array) -> void:
	var wpos := centroid_of(ids)
	if wpos.x < -900000.0:
		return
	if EventBus.has_signal("focus_camera"):
		EventBus.emit_signal("focus_camera", wpos)
	_center_camera_on(wpos)


## Centroide mundo de los ids. Vector3(-1e6,0,0) si vacio/desconocido.
func centroid_of(ids: Array) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for uid in ids:
		if not _units.has(int(uid)):
			continue
		acc += _world_pos_of(int(uid))
		n += 1
	if n == 0:
		return Vector3(-1000000.0, 0.0, 0.0)
	return acc / float(n)


func _center_camera_on(world_pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	var rect := vp.get_visible_rect().size
	var origin := cam.project_ray_origin(rect * 0.5)
	var normal := cam.project_ray_normal(rect * 0.5)
	var offset := _CAM_FALLBACK_OFFSET
	if absf(normal.y) > 0.000001:
		var t := -origin.y / normal.y
		if t > 0.0:
			offset = cam.global_position - (origin + normal * t)
	cam.global_position = world_pos + offset


# ---------------------------------------------------------------- draw ---

func _draw() -> void:
	if _dragging and is_inside_tree():
		var r := _rect_from_points(_drag_start, _drag_current).abs()
		draw_rect(r, Color(0.2, 0.9, 0.2, 0.15), true)
		draw_rect(r, Color(0.2, 0.9, 0.2, 0.9), false, 1.0)


# -------------------------------------------------------------- internas ---

func _on_unit_died(unit_id: int, _killer_id: int) -> void:
	if _units.has(unit_id):
		unregister_unit(unit_id)


func _emit_changed() -> void:
	EventBus.selection_changed.emit(selected.duplicate())


func _apply_selection(ids: Array, emit_signal := true) -> void:
	var clean := _dedup_sorted(ids, true)
	if clean.size() > MAX_SELECTION:
		clean.resize(MAX_SELECTION)
	selected.assign(clean)
	if emit_signal:
		_emit_changed()


func _merge_ids(ids: Array) -> void:
	var union := selected.duplicate()
	for uid in ids:
		if not union.has(int(uid)):
			union.append(int(uid))
	_apply_selection(union)


func _toggle_ids(ids: Array) -> void:
	var cur := selected.duplicate()
	for uid in ids:
		var id := int(uid)
		if cur.has(id):
			cur.erase(id)
		else:
			cur.append(id)
	_apply_selection(cur)


func _dedup_sorted(ids: Array, prune_missing: bool) -> Array[int]:
	var seen := {}
	var out: Array[int] = []
	for v in ids:
		var id := int(v)
		if seen.has(id):
			continue
		if prune_missing and not _units.has(id):
			continue
		seen[id] = true
		out.append(id)
	out.sort()
	return out


func _is_villager(u: Dictionary) -> bool:
	if str(u.get("unit_type", "")) in VILLAGER_TYPES:
		return true
	# Registros sin tipo pero marcados no-militares cuentan como aldeanos.
	return not bool(u.get("military", false)) and str(u.get("unit_type", "")).is_empty()


## Pantalla de una unidad: override de test, si no camara.unproject_position.
## Vector2(-1e6, 0) si no proyectable (fuera de arbol, sin camara...).
func _screen_pos_of(unit_id: int) -> Vector2:
	if _test_screen_pos.has(unit_id):
		return _test_screen_pos[unit_id]
	if not is_inside_tree():
		return Vector2(-1000000.0, 0.0)
	var vp := get_viewport()
	if vp == null:
		return Vector2(-1000000.0, 0.0)
	var cam := vp.get_camera_3d()
	if cam == null or not is_instance_valid(cam):
		return Vector2(-1000000.0, 0.0)
	var w := _world_pos_of(unit_id)
	if not cam.is_position_behind(w):
		return cam.unproject_position(w)
	return Vector2(-1000000.0, 0.0)


func _world_pos_of(unit_id: int) -> Vector3:
	var u: Dictionary = _units[unit_id]
	var n: Variant = u.get("node", null)
	if is_instance_valid(n) and n is Node3D:
		return (n as Node3D).global_position
	return u.get("pos", Vector3.ZERO)


func _viewport_rect() -> Rect2:
	if is_inside_tree() and get_viewport() != null:
		return get_viewport().get_visible_rect()
	return Rect2(Vector2.ZERO, Vector2(100000.0, 100000.0))


static func _rect_from_points(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(a, b - a)


static func _as_vec3(v) -> Vector3:
	if v is Vector3:
		return v
	if v is Vector2:
		return Vector3(v.x, 0.0, v.y)
	if typeof(v) == TYPE_ARRAY:
		if v.size() >= 3:
			return Vector3(float(v[0]), float(v[1]), float(v[2]))
		if v.size() == 2:
			return Vector3(float(v[0]), 0.0, float(v[1]))
	return Vector3.ZERO

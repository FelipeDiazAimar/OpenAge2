extends Node
# VillagerAI - FSM de aldeanos (lado IA/UI, Godot 4.4, determinista).
#
# Estados IA (intencion de tarea, NO el estado de simulacion de Economy):
#   idle                  -> sin tarea. Es el unico que lista la tecla ".".
#   buscar_recurso_cercano-> con tarea de recoleccion (buscando nodo, en ruta,
#                            recolectando o entregando; el detalle lo lleva Economy).
#   construir             -> con tarea de construccion (comando "build").
#   reparar               -> con tarea de reparacion (comando "repair").
#   huir                  -> campana activa: ordenado al TC en radio 4.
#
# Reglas de determinismo (lockstep 10 Hz):
#   - PROHIBIDO randf/randi/Time/OS en este archivo.
#   - Todo efecto en simulacion sale por SimAPI.queue_command() (tick + INPUT_DELAY,
#     orden total por player_id/type/payload). Economy aplica "gather" via su
#     _on_cmd -> order_gather(); NUNCA se llama a Economy.order_gather() directo
#     desde aqui, porque saltaria la replicacion LAN y desincronizaria peers.
#   - Busquedas: iteracion ordenada por id, distancia Manhattan, desempate por
#     menor id (igual que Economy.nearest_dropoff).
#   - Input/camara/seleccion son UI local: no tocan la sim, pueden usar viewport.
#
# Campana (actions.json "bell", hotkey T):
#   - T (accion InputMap "bell") -> ring_bell(): guarda la tarea de cada aldeano
#     y manda a todos al TC en radio BELL_RADIUS = 4.0 (un solo comando "move"
#     con los ids ordenados).
#   - U -> unbell(): restaura la tarea guardada re-emitiendo gather/build/repair
#     por SimAPI. U no existe en el InputMap de project.godot: se escucha como
#     tecla fisica (KEY_U) salvo que se anada la accion "unbell", que tiene
#     prioridad si existe.
#
# Aldeano inactivo (accion InputMap "idle_villager", tecla "."):
#   - focus_next_idle(): round-robin sobre aldeanos idle del jugador local,
#     emite EventBus.selection_changed y centra camara via EventBus
#     (signal "focus_camera" si existe; si no, mueve la Camera3D actual
#     conservando su offset). Para activar la via EventBus, anadir a
#     core/EventBus.gd:  signal focus_camera(world_pos: Vector3)
#
# Auto-reatacar tras dropoff:
#   - Economy ya re-buclea al mismo nodo solo; cuando el nodo se agota el
#     aldeano queda eco-idle con tarea pendiente -> en el siguiente tick_finished
#     se busca el recurso mas cercano de la misma clase y se re-ordena con
#     SimAPI.queue_command("gather") (Economy lo aplica con order_gather).
#   - Si no queda recurso, la tarea se libera (pasa a idle) para no spamear.
#
# Registro: la IA mantiene su propio registro (register_*) y, si hay nodo
# Economy enlazado (grupo "economy", NodePath exportado o set_economy()),
# lo adopta como autoritativo cada tick (ids, posiciones, cantidades, TCs).
# Sin Economy enlazado funciona standalone (tests headless).

# --- Estados canonicos IA ---
const ST_IDLE := "idle"
const ST_SEEK := "buscar_recurso_cercano"
const ST_BUILD := "construir"
const ST_REPAIR := "reparar"
const ST_FLEE := "huir"

const BELL_RADIUS := 4.0 # campana: todos al TC en este radio (tiles)
const NO_ID := -1
const _CAM_FALLBACK_OFFSET := Vector3(20.0, 20.0, 20.0) # = posicion inicial AoeCamera

## Jugador local (dueno del teclado). La API acepta pid explicito para bots/tests.
var local_player_id := 0
## Como localizar al sistema Economy (no es autoload). Prioridad:
## 1) set_economy(nodo), 2) economy_path del editor, 3) grupo "economy".
@export var economy_path: NodePath
var economy: Node = null

# Registro propio: vid -> {player_id:int, pos:Vector2}
var _villagers := {}
# tcid -> {player_id:int, pos:Vector2}
var _tcs := {}
# nid -> {kind:String, amount:float, pos:Vector2}
var _nodes := {}
# vid -> estado IA (uno de ST_*). Solo vids conocidos.
var _state := {}
# vid -> tarea {kind:"gather"/"build"/"repair", node_id/target/pos/kinds}
var _task := {}
# vid -> Array de kinds preferidos, busqueda pendiente de resolver en el tick.
var _pending_search := {}
# pid -> bool (campana sonando)
var _bell_active := {}
# vid -> tarea guardada al sonar la campana (se restaura con U)
var _bell_saved := {}
# Round-robin para focus_next_idle (indice sobre la lista ordenada de idles).
var _idle_cursor := 0


func _ready() -> void:
	if economy == null and not economy_path.is_empty():
		var n := get_node_or_null(economy_path)
		if n != null:
			economy = n
	_resolve_economy()
	if not EventBus.tick_finished.is_connected(_on_tick):
		EventBus.tick_finished.connect(_on_tick)
	if not EventBus.command_issued.is_connected(_on_cmd):
		EventBus.command_issued.connect(_on_cmd)


## Enlaza el nodo Economy manualmente (tests, escenas sin grupo).
func set_economy(node: Node) -> void:
	economy = node


func _resolve_economy() -> void:
	if is_instance_valid(economy):
		return
	if not is_inside_tree():
		return
	var found := get_tree().get_nodes_in_group("economy")
	if not found.is_empty() and found[0] is Node:
		economy = found[0]


func _eco() -> Node:
	if not is_instance_valid(economy):
		_resolve_economy()
	return economy if is_instance_valid(economy) else null


# ------------------------------------------------------------- registro ---

func register_villager(villager_id: int, player_id: int, pos) -> void:
	_villagers[villager_id] = {"player_id": player_id, "pos": _as_vec2(pos)}
	if not _state.has(villager_id):
		_state[villager_id] = ST_IDLE


func unregister_villager(villager_id: int) -> void:
	_villagers.erase(villager_id)
	_state.erase(villager_id)
	_task.erase(villager_id)
	_pending_search.erase(villager_id)
	_bell_saved.erase(villager_id)


func register_tc(tc_id: int, player_id: int, pos) -> void:
	_tcs[tc_id] = {"player_id": player_id, "pos": _as_vec2(pos)}


func unregister_tc(tc_id: int) -> void:
	_tcs.erase(tc_id)


func register_node(node_id: int, kind: String, amount: float, pos) -> void:
	_nodes[node_id] = {"kind": kind, "amount": float(amount), "pos": _as_vec2(pos)}


func set_node_amount(node_id: int, amount: float) -> void:
	if _nodes.has(node_id):
		_nodes[node_id]["amount"] = float(amount)


func remove_node(node_id: int) -> void:
	_nodes.erase(node_id)


func clear() -> void:
	_villagers.clear()
	_tcs.clear()
	_nodes.clear()
	_state.clear()
	_task.clear()
	_pending_search.clear()
	_bell_active.clear()
	_bell_saved.clear()
	_idle_cursor = 0


func get_state(villager_id: int) -> String:
	return str(_state.get(villager_id, ST_IDLE))


func is_idle(villager_id: int) -> bool:
	return get_state(villager_id) == ST_IDLE


func is_bell_active(player_id: int = -1) -> bool:
	var pid := local_player_id if player_id < 0 else player_id
	return bool(_bell_active.get(pid, false))


# ---------------------------------------------------- asignar tareas ---

## Encarga recoleccion del recurso mas cercano (kinds vacio = cualquiera).
## Fija estado buscar_recurso_cercano y resuelve en el proximo tick (determinista).
func assign_gather_nearest(villager_id: int, kinds: Array = []) -> bool:
	if not _villagers.has(villager_id):
		return false
	var pid := int(_villagers[villager_id]["player_id"])
	if bool(_bell_active.get(pid, false)):
		return false # bajo campana no se aceptan tareas (U primero)
	_state[villager_id] = ST_SEEK
	_task[villager_id] = {"kind": "gather", "node_id": NO_ID, "kinds": kinds.duplicate()}
	_pending_search[villager_id] = kinds.duplicate()
	return true


## Encarga un nodo concreto (via SimAPI -> Economy.order_gather en el destino).
func assign_gather_node(villager_id: int, node_id: int) -> bool:
	if not _villagers.has(villager_id) or not _nodes.has(node_id):
		return false
	var pid := int(_villagers[villager_id]["player_id"])
	if bool(_bell_active.get(pid, false)):
		return false
	_pending_search.erase(villager_id)
	_state[villager_id] = ST_SEEK
	_task[villager_id] = {"kind": "gather", "node_id": node_id,
		"kinds": [str(_nodes[node_id]["kind"])]}
	_cmd(pid, "gather", {"unit_ids": [villager_id], "node_id": node_id})
	return true


## Encarga construir en un blueprint (lo ejecuta el futuro sistema construction).
func assign_build(villager_id: int, building_id: String, pos) -> bool:
	if not _villagers.has(villager_id):
		return false
	var pid := int(_villagers[villager_id]["player_id"])
	if bool(_bell_active.get(pid, false)):
		return false
	_pending_search.erase(villager_id)
	_state[villager_id] = ST_BUILD
	var p := _as_vec2(pos)
	_task[villager_id] = {"kind": "build", "target": building_id, "pos": [p.x, p.y]}
	_cmd(pid, "build", {"unit_ids": [villager_id], "building": building_id,
		"pos": [p.x, p.y]})
	return true


## Encarga reparar un edificio danado (actions.json repair: 15 hp/s).
func assign_repair(villager_id: int, building_id: int, pos) -> bool:
	if not _villagers.has(villager_id):
		return false
	var pid := int(_villagers[villager_id]["player_id"])
	if bool(_bell_active.get(pid, false)):
		return false
	_pending_search.erase(villager_id)
	_state[villager_id] = ST_REPAIR
	var p := _as_vec2(pos)
	_task[villager_id] = {"kind": "repair", "target": building_id, "pos": [p.x, p.y]}
	_cmd(pid, "repair", {"unit_ids": [villager_id], "target": building_id,
		"pos": [p.x, p.y]})
	return true


## Suelta la tarea y vuelve a idle (emite "stop" para futuros consumidores).
func stop_to_idle(villager_id: int) -> bool:
	if not _villagers.has(villager_id):
		return false
	var pid := int(_villagers[villager_id]["player_id"])
	_task.erase(villager_id)
	_pending_search.erase(villager_id)
	_bell_saved.erase(villager_id)
	_state[villager_id] = ST_IDLE
	_cmd(pid, "stop", {"unit_ids": [villager_id]})
	return true


# ---------------------------------------------------------------- campana ---

## T: guarda tareas y manda TODOS los aldeanos del jugador al TC (radio 4).
## Un solo comando "move" con ids ordenadas -> determinista y barato en LAN.
func ring_bell(player_id: int = -1) -> bool:
	var pid := local_player_id if player_id < 0 else player_id
	var tc_pos := _tc_pos_of(pid)
	if tc_pos.x < -900000.0: # sin TC conocido: no hay a donde huir
		push_warning("VillagerAI.ring_bell: jugador %d sin TC registrado." % pid)
		return false
	var ids := _villager_ids_of(pid)
	if ids.is_empty():
		_bell_active[pid] = true
		return true
	for vid in ids:
		if get_state(vid) != ST_FLEE and _task.has(vid):
			_bell_saved[vid] = (_task[vid] as Dictionary).duplicate(true)
		_state[vid] = ST_FLEE
		_pending_search.erase(vid)
	_bell_active[pid] = true
	_cmd(pid, "move", {"unit_ids": ids, "target": [tc_pos.x, tc_pos.y],
		"radius": BELL_RADIUS, "bell": true})
	return true


## U: des-campana. Re-emite la tarea guardada de cada aldeano via SimAPI.
func unbell(player_id: int = -1) -> bool:
	var pid := local_player_id if player_id < 0 else player_id
	if not bool(_bell_active.get(pid, false)):
		return false
	_bell_active[pid] = false
	var ids := _villager_ids_of(pid)
	for vid in ids:
		_state[vid] = ST_IDLE
		if not _bell_saved.has(vid):
			_task.erase(vid)
			continue
		var t: Dictionary = (_bell_saved[vid] as Dictionary).duplicate(true)
		_bell_saved.erase(vid)
		match str(t.get("kind", "")):
			"gather":
				var nid := int(t.get("node_id", NO_ID))
				if nid >= 0 and _node_has_amount(nid):
					assign_gather_node(vid, nid)
				else:
					assign_gather_nearest(vid, (t.get("kinds", []) as Array).duplicate())
			"build":
				assign_build(vid, str(t.get("target", "")), _as_vec2(t.get("pos", [0, 0])))
			"repair":
				assign_repair(vid, int(t.get("target", NO_ID)), _as_vec2(t.get("pos", [0, 0])))
			_:
				_task.erase(vid)
	return true


## Huida individual al TC (p. ej. al recibir dano). Equivale a campana de 1.
func flee(villager_id: int) -> bool:
	if not _villagers.has(villager_id):
		return false
	var pid := int(_villagers[villager_id]["player_id"])
	var tc_pos := _tc_pos_of(pid)
	if tc_pos.x < -900000.0:
		return false
	if get_state(villager_id) != ST_FLEE and _task.has(villager_id):
		_bell_saved[villager_id] = (_task[villager_id] as Dictionary).duplicate(true)
	_task.erase(villager_id)
	_pending_search.erase(villager_id)
	_state[villager_id] = ST_FLEE
	_cmd(pid, "move", {"unit_ids": [villager_id], "target": [tc_pos.x, tc_pos.y],
		"radius": BELL_RADIUS, "bell": true})
	return true


# ---------------------------------------------------------- aldeano idle ---

## Tecla ".": siguiente aldeano idle del jugador local (round-robin por id),
## lo selecciona via EventBus y centra la camara via EventBus. -1 si no hay.
func focus_next_idle(player_id: int = -1) -> int:
	var pid := local_player_id if player_id < 0 else player_id
	var idles: Array = []
	for vid in _villagers.keys():
		if int(_villagers[vid]["player_id"]) == pid and get_state(vid) == ST_IDLE:
			idles.append(int(vid))
	idles.sort()
	if idles.is_empty():
		return NO_ID
	_idle_cursor = _idle_cursor % idles.size()
	var chosen := int(idles[_idle_cursor])
	_idle_cursor = (_idle_cursor + 1) % idles.size()
	var wpos := Vector3((_villagers[chosen]["pos"] as Vector2).x, 0.0,
		(_villagers[chosen]["pos"] as Vector2).y)
	EventBus.selection_changed.emit([chosen])
	if EventBus.has_signal("focus_camera"):
		EventBus.emit_signal("focus_camera", wpos)
	_center_camera_on(wpos)
	return chosen


func _center_camera_on(world_pos: Vector3) -> void:
	# UI local (no sim): conserva el offset de la camara respecto al punto
	# de suelo bajo el centro de pantalla para no romper pan/zoom del jugador.
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


# ------------------------------------------------------------------ tick ---

func _on_tick(_t: int) -> void:
	_sync_from_economy()
	_resolve_pending_searches()
	_auto_retake_after_dropoff()


## Economy manda: adopta aldeanos/nodos/TCs nuevos y actualiza pos/cantidad.
## Solo lee (el get_villager de Economy devuelve referencia: no mutar).
func _sync_from_economy() -> void:
	var eco := _eco()
	if eco == null:
		return
	var ev: Variant = eco.get("_villagers")
	if typeof(ev) == TYPE_DICTIONARY:
		for vid in (ev as Dictionary).keys():
			var d: Dictionary = (ev as Dictionary)[vid]
			var id := int(vid)
			if not _villagers.has(id):
				_villagers[id] = {"player_id": int(d.get("player_id", 0)),
					"pos": _as_vec2(d.get("pos", Vector2.ZERO))}
				if not _state.has(id):
					_state[id] = ST_IDLE
			else:
				_villagers[id]["pos"] = _as_vec2(d.get("pos",
					_villagers[id]["pos"]))
	var en: Variant = eco.get("_nodes")
	if typeof(en) == TYPE_DICTIONARY:
		# Economy manda en nodos: reconstruir (los agotados/retirados deben
		# desaparecer; si no, se emitirian gather fantasma cada tick).
		var seen := {}
		for nid in (en as Dictionary).keys():
			var n: Dictionary = (en as Dictionary)[nid]
			_nodes[int(nid)] = {"kind": str(n.get("kind", "")),
				"amount": float(n.get("amount", 0.0)),
				"pos": _as_vec2(n.get("pos", Vector2.ZERO))}
			seen[int(nid)] = true
		for nid in _nodes.keys():
			if not seen.has(int(nid)):
				_nodes.erase(nid)
	var ed: Variant = eco.get("_dropoffs")
	if typeof(ed) == TYPE_DICTIONARY:
		for did in (ed as Dictionary).keys():
			var dd: Dictionary = (ed as Dictionary)[did]
			if str(dd.get("building", "")) == "centro_urbano":
				_tcs[int(did)] = {"player_id": int(dd.get("player_id", 0)),
					"pos": _as_vec2(dd.get("pos", Vector2.ZERO))}


## Resuelve busquedas pendientes en orden de id (determinista).
func _resolve_pending_searches() -> void:
	var ids: Array = _pending_search.keys()
	ids.sort()
	for vid in ids:
		if not _villagers.has(int(vid)):
			_pending_search.erase(vid)
			continue
		var pid := int(_villagers[int(vid)]["player_id"])
		if bool(_bell_active.get(pid, false)):
			continue # la campana congela; U reencolara la busqueda
		var kinds: Array = (_pending_search[vid] as Array).duplicate()
		var from: Vector2 = _villagers[int(vid)]["pos"]
		var nid := nearest_resource(from, kinds)
		if nid < 0:
			continue # sin recurso aun: reintenta el proximo tick
		_pending_search.erase(vid)
		_state[int(vid)] = ST_SEEK
		_task[int(vid)] = {"kind": "gather", "node_id": nid,
			"kinds": [str(_nodes[nid]["kind"])]}
		_cmd(pid, "gather", {"unit_ids": [int(vid)], "node_id": nid})


## Tras dropoff con nodo agotado, Economy deja al aldeano en idle: re-atacar
## la tarea con el recurso mas cercano de la misma clase (via SimAPI, que
## Economy aplica con order_gather). Sin recurso -> libera a idle (no spamea).
func _auto_retake_after_dropoff() -> void:
	var eco := _eco()
	if eco == null:
		return
	var ev: Variant = eco.get("_villagers")
	if typeof(ev) != TYPE_DICTIONARY:
		return
	var ids: Array = _task.keys()
	ids.sort()
	for vid in ids:
		var id := int(vid)
		if _pending_search.has(id) or not _villagers.has(id):
			continue
		var t: Dictionary = _task[id]
		if str(t.get("kind", "")) != "gather":
			continue
		var pid := int(_villagers[id]["player_id"])
		if bool(_bell_active.get(pid, false)):
			continue
		if not (ev as Dictionary).has(id):
			continue
		var ed: Dictionary = (ev as Dictionary)[id]
		if str(ed.get("state", "")) != "idle":
			continue # aun trabajando/entregando: nada que hacer
		var old_nid := int(t.get("node_id", NO_ID))
		if old_nid >= 0 and _node_has_amount(old_nid):
			# Nodo con resto (carrera dropoff/vacio): re-ordenar al mismo.
			_cmd(pid, "gather", {"unit_ids": [id], "node_id": old_nid})
			continue
		var kinds: Array = (t.get("kinds", []) as Array).duplicate()
		var nid := nearest_resource(_villagers[id]["pos"], kinds)
		if nid < 0 and not kinds.is_empty():
			nid = nearest_resource(_villagers[id]["pos"], []) # cualquier resto
		if nid < 0:
			_task.erase(id) # agotado total: idle para que "." lo encuentre
			if get_state(id) == ST_SEEK:
				_state[id] = ST_IDLE
			continue
		_task[id] = {"kind": "gather", "node_id": nid,
			"kinds": [str(_nodes[nid]["kind"])]}
		_cmd(pid, "gather", {"unit_ids": [id], "node_id": nid})


# -------------------------------------------------------- observador sim ---

## Mantiene la FSM coherente con ordenes externas (clicks del jugador, bots):
## toda orden sim pasa por command_issued, asi que se refleja sin polling.
func _on_cmd(cmd: Dictionary) -> void:
	if typeof(cmd) != TYPE_DICTIONARY:
		return
	var type := str(cmd.get("type", ""))
	if type not in ["gather", "build", "repair", "stop"]:
		return
	var pid := int(cmd.get("player_id", NO_ID))
	if bool(_bell_active.get(pid, false)):
		return # bajo campana la FSM la gobierna ring/unbell
	var payload: Dictionary = cmd.get("payload", {})
	for vid in _parse_unit_ids(payload):
		if not _villagers.has(vid):
			continue
		match type:
			"gather":
				var nid := int(payload.get("node_id",
					payload.get("resource_id", payload.get("target", NO_ID))))
				# _cmd() emite command_issued de forma sincrona: conservar los
				# kinds que ya tenia la tarea (el payload no trae el recurso).
				var keep_kinds: Array = []
				if _task.has(vid):
					var old: Dictionary = _task[vid]
					if str(old.get("kind", "")) == "gather":
						keep_kinds = (old.get("kinds", []) as Array).duplicate()
				_pending_search.erase(vid)
				_state[vid] = ST_SEEK
				_task[vid] = {"kind": "gather", "node_id": nid, "kinds": keep_kinds}
			"build":
				_pending_search.erase(vid)
				_state[vid] = ST_BUILD
				_task[vid] = {"kind": "build",
					"target": str(payload.get("building", payload.get("target", ""))),
					"pos": payload.get("pos", [0, 0])}
			"repair":
				_pending_search.erase(vid)
				_state[vid] = ST_REPAIR
				_task[vid] = {"kind": "repair",
					"target": int(payload.get("target", NO_ID)),
					"pos": payload.get("pos", [0, 0])}
			"stop":
				_task.erase(vid)
				_pending_search.erase(vid)
				_state[vid] = ST_IDLE


# ----------------------------------------------------------------- input ---

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("bell"):
		ring_bell(local_player_id)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("idle_villager"):
		focus_next_idle(local_player_id)
		get_viewport().set_input_as_handled()
	elif _is_unbell_event(event):
		unbell(local_player_id)
		get_viewport().set_input_as_handled()


func _is_unbell_event(event: InputEvent) -> bool:
	if InputMap.has_action("unbell"):
		return event.is_action_pressed("unbell")
	return event is InputEventKey and (event as InputEventKey).pressed \
		and not (event as InputEventKey).echo \
		and ((event as InputEventKey).physical_keycode == KEY_U \
			or (event as InputEventKey).keycode == KEY_U)


# ---------------------------------------------------------------- helpers ---

## Unica salida hacia la sim: SimAPI fecha a tick+INPUT_DELAY y replica en LAN.
func _cmd(player_id: int, type: String, payload: Dictionary) -> void:
	SimAPI.queue_command(player_id, type, payload)


## Recurso con cantidad del kind pedido mas cercano (Manhattan, desempate id).
## kinds vacio = cualquier recurso. -1 si no hay.
func nearest_resource(from_pos, kinds: Array = []) -> int:
	var fp := _as_vec2(from_pos)
	var best := NO_ID
	var best_d := 1e18
	var ids: Array = _nodes.keys()
	ids.sort()
	for nid in ids:
		var n: Dictionary = _nodes[nid]
		if float(n.get("amount", 0.0)) <= 0.0:
			continue
		if not kinds.is_empty() and not kinds.has(str(n.get("kind", ""))):
			continue
		var dist := absf(fp.x - (n["pos"] as Vector2).x) \
			+ absf(fp.y - (n["pos"] as Vector2).y)
		if dist < best_d - 0.000001 \
				or (absf(dist - best_d) <= 0.000001 and int(nid) < best):
			best_d = dist
			best = int(nid)
	return best


## TC del jugador mas cercano a una posicion (Manhattan, desempate id).
func nearest_tc(player_id: int, from_pos) -> int:
	var fp := _as_vec2(from_pos)
	var best := NO_ID
	var best_d := 1e18
	var ids: Array = _tcs.keys()
	ids.sort()
	for tid in ids:
		var t: Dictionary = _tcs[tid]
		if int(t.get("player_id", NO_ID)) != player_id:
			continue
		var dist := absf(fp.x - (t["pos"] as Vector2).x) \
			+ absf(fp.y - (t["pos"] as Vector2).y)
		if dist < best_d - 0.000001 \
				or (absf(dist - best_d) <= 0.000001 and int(tid) < best):
			best_d = dist
			best = int(tid)
	return best


func _tc_pos_of(player_id: int) -> Vector2:
	var tid := NO_ID
	var ids: Array = _tcs.keys()
	ids.sort()
	for cand in ids:
		var t: Dictionary = _tcs[cand]
		if int(t.get("player_id", NO_ID)) != player_id:
			continue
		# Primer TC por id = determinista (suele ser el inicial).
		if tid < 0 or int(cand) < tid:
			tid = int(cand)
	if tid < 0:
		return Vector2(-1000000.0, 0.0)
	return _tcs[tid]["pos"]


func _villager_ids_of(player_id: int) -> Array:
	var out: Array = []
	for vid in _villagers.keys():
		if int(_villagers[vid]["player_id"]) == player_id:
			out.append(int(vid))
	out.sort()
	return out


func _node_has_amount(node_id: int) -> bool:
	return _nodes.has(node_id) and float(_nodes[node_id].get("amount", 0.0)) > 0.0


func _parse_unit_ids(payload: Dictionary) -> Array:
	# Mismo convenio que Economy._parse_unit_ids (unit_ids/villager_ids/units...).
	var out: Array = []
	for key in ["unit_ids", "villager_ids", "units"]:
		if payload.has(key) and typeof(payload[key]) == TYPE_ARRAY:
			for v in payload[key]:
				out.append(int(v))
	for key in ["unit_id", "villager_id", "unit", "villager"]:
		if payload.has(key):
			out.append(int(payload[key]))
	var seen := {}
	var dedup: Array = []
	for v in out:
		if not seen.has(v):
			seen[v] = true
			dedup.append(v)
	dedup.sort()
	return dedup


## Acepta Vector2 / Vector3 / Array [x,y(,z)] y normaliza a Vector2 (x,z).
static func _as_vec2(pos) -> Vector2:
	if pos is Vector2:
		return pos
	if pos is Vector3:
		return Vector2(pos.x, pos.z)
	if typeof(pos) == TYPE_ARRAY:
		if pos.size() >= 3:
			return Vector2(float(pos[0]), float(pos[2]))
		if pos.size() == 2:
			return Vector2(float(pos[0]), float(pos[1]))
	return Vector2.ZERO


## Cadena canonica de la intencion IA (debug; no entra en el hash anti-desync,
## que solo cubre estado sim de Economy/GameManager).
func sim_state_string() -> String:
	var parts: Array = []
	var ids: Array = _state.keys()
	ids.sort()
	for vid in ids:
		var t: Dictionary = _task.get(vid, {})
		parts.append("%d:%s:%s" % [int(vid), str(_state[vid]),
			str(t.get("kind", "-")) + str(t.get("node_id", t.get("target", "-")))])
	var bells: Array = _bell_active.keys()
	bells.sort()
	for pid in bells:
		if bool(_bell_active[pid]):
			parts.append("bell%d" % int(pid))
	return "|".join(parts)

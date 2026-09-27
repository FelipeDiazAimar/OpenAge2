extends Node
# Production - colas de entrenamiento AoE2 por edificio (lockstep 10 Hz).
#
# - Cola x5 por edificio (actions.json train.queue_max = 5).
#   Comando: SimAPI.queue_command(pid, "train", {"building_id": uid, "unit_id": "aldeano"})
# - Tiempos: train_time_sec (data/units/*.json) * TICK_RATE ticks. Solo avanza en _on_tick.
# - Coste: GameManager.try_spend(pid, cost). Sin recursos -> se rechaza, sin deuda.
# - Reserva de poblacion al encolar (GameManager.add_pop); al cancelar se libera
#   (remove_pop) + reembolso 50% via GameManager.refund_cancel.
# - Rally point: SimAPI.queue_command(pid, "set_rally", {"building_id": uid, "pos": [x, y]})
#   (click derecho con el edificio seleccionado; la UI convierte el raton a mundo/celda
#   y lo envia como pos). La unidad spawneada guarda ese rally como destino inicial.
# - Spawn: primera baldosa libre adyacente al footprint en orden determinista
#   (barrido row-major del perimetro). Si hay nodo Pathfinding con is_walkable(x, y)
#   se usa para filtrar; si no existe (o todo ocupado) se usa offset determinista
#   esquina exterior SE: origen + Vector2i(size.x, size.y), clamped al grid 144x144.
#
# Determinismo: NADA de randf/randi/Time/SceneTreeTimer en logica. Iteracion siempre
# ordenada por uid de edificio. Carga de JSON solo en _ready (fuera del tick).

const TICK_RATE := 10 # debe coincidir con SimAPI.TICK_RATE y GameManager.TICK_RATE
const QUEUE_MAX := 5 # actions.json -> train.queue_max
const GRID_W := 144 # replica Pathfinding.GRID_W para clampear el fallback
const GRID_H := 144 # replica Pathfinding.GRID_H
const UNITS_DIR := "res://data/units"
const BUILDINGS_DIR := "res://data/buildings"

# Fallback si los JSON no son legibles. Debe coincidir con data/.
const FALLBACK_UNITS := {
	"aldeano": {"cost": {"food": 50}, "train_time_sec": 20, "pop_cost": 1, "trained_at": "centro_urbano"},
	"milicia": {"cost": {"food": 60, "gold": 20}, "train_time_sec": 21, "pop_cost": 1, "trained_at": "cuartel"},
	"arquero": {"cost": {"wood": 25, "gold": 45}, "train_time_sec": 27, "pop_cost": 1, "trained_at": "arqueria"},
	"monje": {"cost": {"gold": 100}, "train_time_sec": 51, "pop_cost": 1, "trained_at": "monasterio"},
}
const FALLBACK_BUILDINGS := {
	"centro_urbano": {"trains": ["aldeano"], "size": Vector2i(4, 4)},
	"cuartel": {"trains": ["milicia", "lancero"], "size": Vector2i(3, 3)},
	"casa": {"trains": [], "size": Vector2i(2, 2)},
	"arqueria": {"trains": ["arquero"], "size": Vector2i(3, 3)},
	"monasterio": {"trains": ["monje"], "size": Vector2i(3, 3)},
}

# DB cargada: unit_id -> {cost:Dictionary, train_time_sec:int, pop_cost:int, trained_at:String}
var units_db := {}
# building_type -> {trains:Array[String], size:Vector2i}
var buildings_db := {}
# uid int -> {uid, player_id, building:String, cell:Vector2i, size:Vector2i,
#             queue:Array[Dictionary], rally:Vector2i, rally_set:bool}
var _buildings := {}
# Unidades ya producidas (para AI/tests/desync): [{uid, unit_id, player_id, cell, rally}]
var _spawned: Array = []
var _next_unit_uid := 1
var _pathfinding: Node = null


func _ready() -> void:
	_load_db()
	_resolve_pathfinding()
	EventBus.command_issued.connect(_on_cmd)
	EventBus.tick_finished.connect(_on_tick)


# ------------------------------------------------------------------ datos ---

func _load_db() -> void:
	units_db.clear()
	buildings_db.clear()
	_load_units_dir()
	_load_buildings_dir()
	if units_db.is_empty():
		for k in FALLBACK_UNITS.keys():
			units_db[k] = (FALLBACK_UNITS[k] as Dictionary).duplicate(true)
	if buildings_db.is_empty():
		for k in FALLBACK_BUILDINGS.keys():
			var b: Dictionary = (FALLBACK_BUILDINGS[k] as Dictionary).duplicate(true)
			buildings_db[k] = b


func _load_units_dir() -> void:
	var dir := DirAccess.open(UNITS_DIR)
	if dir == null:
		return
	var files: Array = []
	for _f in dir.get_files():
		files.append(_f)
	files.sort() # orden alfabetico = determinista
	for fname in files:
		if not str(fname).ends_with(".json"):
			continue
		var f := FileAccess.open(UNITS_DIR + "/" + str(fname), FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("id"):
			continue
		var uid := str(parsed["id"]).to_lower().strip_edges()
		units_db[uid] = {
			"cost": (parsed.get("cost", {}) as Dictionary).duplicate(true),
			"train_time_sec": int(parsed.get("train_time_sec", 0)),
			"pop_cost": int(parsed.get("pop_cost", 1)),
			"trained_at": str(parsed.get("trained_at", "")).to_lower().strip_edges(),
		}


func _load_buildings_dir() -> void:
	var dir := DirAccess.open(BUILDINGS_DIR)
	if dir == null:
		return
	var files: Array = []
	for _f in dir.get_files():
		files.append(_f)
	files.sort()
	for fname in files:
		if not str(fname).ends_with(".json"):
			continue
		var f := FileAccess.open(BUILDINGS_DIR + "/" + str(fname), FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("id"):
			continue
		var bid := str(parsed["id"]).to_lower().strip_edges()
		var trains: Array = []
		for t in (parsed.get("trains", []) as Array):
			trains.append(str(t).to_lower().strip_edges())
		buildings_db[bid] = {"trains": trains, "size": _parse_size(parsed.get("size_tiles", [3, 3]))}


func _parse_size(v) -> Vector2i:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return Vector2i(maxi(1, int(v[0])), maxi(1, int(v[1])))
	return Vector2i(3, 3)


func get_unit_data(unit_id: String) -> Dictionary:
	return (units_db.get(unit_id.to_lower().strip_edges(), {}) as Dictionary).duplicate(true)


func get_train_time_ticks(unit_id: String) -> int:
	var d: Dictionary = units_db.get(unit_id.to_lower().strip_edges(), {})
	return maxi(1, int(d.get("train_time_sec", 0)) * TICK_RATE)


# --------------------------------------------------------------- registro ---

func register_building(uid: int, player_id: int, building_type: String, cell, size = null) -> bool:
	var btype := building_type.to_lower().strip_edges()
	if _buildings.has(uid):
		return false
	var footprint := _as_size(size) if size != null else _building_size(btype)
	_buildings[uid] = {
		"uid": uid, "player_id": player_id, "building": btype,
		"cell": _as_cell(cell), "size": footprint,
		"queue": [], "rally": _as_cell(cell), "rally_set": false,
	}
	return true


func unregister_building(uid: int) -> bool:
	# Edificio destruido: se reembolsa (50%) y libera pop de TODA la cola pendiente.
	if not _buildings.has(uid):
		return false
	var b: Dictionary = _buildings[uid]
	var q: Array = b["queue"]
	for entry in q:
		GameManager.refund_cancel(int(b["player_id"]), (entry.get("cost", {}) as Dictionary))
		GameManager.remove_pop(int(b["player_id"]), int(entry.get("pop_cost", 1)))
	_buildings.erase(uid)
	return true


func has_building(uid: int) -> bool:
	return _buildings.has(uid)


func get_queue(uid: int) -> Array:
	if not _buildings.has(uid):
		return []
	return (_buildings[uid]["queue"] as Array).duplicate(true)


func get_rally(uid: int) -> Dictionary:
	if not _buildings.has(uid):
		return {}
	var b: Dictionary = _buildings[uid]
	return {"cell": b["rally"], "set": bool(b["rally_set"])}


func get_spawned() -> Array:
	return _spawned.duplicate(true)


func clear() -> void:
	_buildings.clear()
	_spawned.clear()
	_next_unit_uid = 1


func set_pathfinding(node: Node) -> void:
	_pathfinding = node


func _building_size(btype: String) -> Vector2i:
	if buildings_db.has(btype):
		return buildings_db[btype]["size"]
	return Vector2i(3, 3)


func _can_train_here(btype: String, unit_id: String) -> bool:
	var u := unit_id.to_lower().strip_edges()
	if buildings_db.has(btype):
		var trains: Array = buildings_db[btype]["trains"]
		if not trains.is_empty():
			return trains.has(u)
	# Edificio sin lista "trains": aceptar si el unit declara trained_at coincidente.
	if units_db.has(u):
		return str(units_db[u].get("trained_at", "")) == btype
	return false


# --------------------------------------------------------------- comandos ---

func _on_cmd(cmd: Dictionary) -> void:
	if typeof(cmd) != TYPE_DICTIONARY:
		return
	var t := str(cmd.get("type", ""))
	var pid := int(cmd.get("player_id", -1))
	var payload: Dictionary = cmd.get("payload", {})
	match t:
		"train":
			var b := _parse_building_id(payload)
			var u := str(payload.get("unit_id", payload.get("unit", "")))
			if b >= 0 and not u.is_empty():
				train(b, u, pid)
		"cancel_train", "cancel_production", "cancel":
			var b2 := _parse_building_id(payload)
			var idx := int(payload.get("index", payload.get("slot", -1)))
			if b2 >= 0:
				cancel_train(b2, idx, pid)
		"set_rally", "rally":
			var b3 := _parse_building_id(payload)
			if b3 >= 0 and (payload.has("pos") or payload.has("target") or payload.has("cell")):
				var raw = payload.get("pos", payload.get("target", payload.get("cell")))
				set_rally(b3, raw, pid)


func _parse_building_id(payload: Dictionary) -> int:
	for k in ["building_id", "building_uid", "building", "source", "id", "from"]:
		if payload.has(k):
			# "building" puede venir como String tipo ("cuartel"); en ese caso no es uid.
			if k == "building" and typeof(payload[k]) == TYPE_STRING and not str(payload[k]).is_valid_int():
				continue
			if typeof(payload[k]) == TYPE_INT or typeof(payload[k]) == TYPE_FLOAT:
				return int(payload[k])
			if typeof(payload[k]) == TYPE_STRING and str(payload[k]).is_valid_int():
				return int(payload[k])
	return -1


## Encola 1 unidad. Cobra coste + reserva pop al encolar. False si se rechaza.
func train(building_uid: int, unit_id: String, cmd_player_id: int = -1) -> bool:
	if not _buildings.has(building_uid):
		return false
	var b: Dictionary = _buildings[building_uid]
	var pid := int(b["player_id"])
	if cmd_player_id >= 0 and cmd_player_id != pid:
		return false # un jugador no encola en edificios ajenos
	var u := unit_id.to_lower().strip_edges()
	if not units_db.has(u):
		return false
	if not _can_train_here(str(b["building"]), u):
		return false
	var q: Array = b["queue"]
	if q.size() >= QUEUE_MAX:
		return false
	var udata: Dictionary = units_db[u]
	var cost: Dictionary = (udata.get("cost", {}) as Dictionary).duplicate(true)
	var pop_cost := int(udata.get("pop_cost", 1))
	if not GameManager.can_train(pid, pop_cost):
		return false
	if not GameManager.try_spend(pid, cost):
		return false
	if not GameManager.add_pop(pid, pop_cost):
		# Carrera por supply en el mismo tick: devolver cobro integro.
		for k in cost.keys():
			GameManager.add_resource(pid, str(k), float(cost[k]))
		return false
	q.append({
		"unit_id": u, "cost": cost,
		"ticks_left": maxi(1, int(udata.get("train_time_sec", 0)) * TICK_RATE),
		"ticks_total": maxi(1, int(udata.get("train_time_sec", 0)) * TICK_RATE),
		"pop_cost": pop_cost,
	})
	_emit_guarded("train_queued", [building_uid, u, q.size()])
	return true


## Cancela un slot (por defecto el ultimo). Reembolso 50% + libera pop. False si nada.
func cancel_train(building_uid: int, index: int = -1, cmd_player_id: int = -1) -> bool:
	if not _buildings.has(building_uid):
		return false
	var b: Dictionary = _buildings[building_uid]
	var pid := int(b["player_id"])
	if cmd_player_id >= 0 and cmd_player_id != pid:
		return false
	var q: Array = b["queue"]
	if q.is_empty():
		return false
	var i := int(index)
	if i < 0:
		i = q.size() - 1
	if i < 0 or i >= q.size():
		return false
	var entry: Dictionary = q[i]
	q.remove_at(i)
	GameManager.refund_cancel(pid, (entry.get("cost", {}) as Dictionary))
	GameManager.remove_pop(pid, int(entry.get("pop_cost", 1)))
	_emit_guarded("train_cancelled", [building_uid, str(entry.get("unit_id", "")), q.size()])
	return true


## Rally point (click derecho con el edificio seleccionado). Acepta celda o mundo.
func set_rally(building_uid: int, pos, cmd_player_id: int = -1) -> bool:
	if not _buildings.has(building_uid):
		return false
	var b: Dictionary = _buildings[building_uid]
	if cmd_player_id >= 0 and cmd_player_id != int(b["player_id"]):
		return false
	b["rally"] = _clamp_cell(_as_cell(pos))
	b["rally_set"] = true
	_emit_guarded("rally_set", [building_uid, b["rally"]])
	return true


# ------------------------------------------------------------------ tick ---

func _on_tick(t: int) -> void:
	tick(t)


## Avanza 1 tick: solo el frontal de cada cola descuenta. Orden por uid.
func tick(_t: int) -> void:
	var ids: Array = _buildings.keys()
	ids.sort()
	for uid in ids:
		if not _buildings.has(uid):
			continue
		var b: Dictionary = _buildings[uid]
		var q: Array = b["queue"]
		if q.is_empty():
			continue
		var front: Dictionary = q[0]
		front["ticks_left"] = int(front["ticks_left"]) - 1
		if int(front["ticks_left"]) <= 0:
			_complete_training(b)


func _complete_training(b: Dictionary) -> void:
	var q: Array = b["queue"]
	if q.is_empty():
		return
	var entry: Dictionary = q.pop_front()
	# La pop ya se reservo al encolar: no se toca.
	var spawn_cell := _find_spawn_cell(b)
	var rally_cell: Vector2i = b["rally"] if bool(b["rally_set"]) else spawn_cell
	var record := {
		"uid": _next_unit_uid, "unit_id": str(entry.get("unit_id", "")),
		"player_id": int(b["player_id"]), "cell": spawn_cell, "rally": rally_cell,
	}
	_spawned.append(record)
	_next_unit_uid += 1
	_emit_guarded("unit_trained", [
		int(record["uid"]), str(record["unit_id"]),
		int(record["player_id"]), spawn_cell, rally_cell,
	])


# ----------------------------------------------------------------- spawn ---

func _resolve_pathfinding() -> void:
	if is_instance_valid(_pathfinding):
		return
	var tree := get_tree()
	if tree == null:
		return
	var grouped: Array = tree.get_nodes_in_group("pathfinding")
	if not grouped.is_empty():
		grouped.sort_custom(func(a, b): return str(a.name) < str(b.name))
		_pathfinding = grouped[0]
		return
	var cur: Node = tree.current_scene
	if cur != null:
		var cand := cur.get_node_or_null("Pathfinding")
		if cand != null:
			_pathfinding = cand


func _is_walkable_cell(c: Vector2i) -> bool:
	if not is_instance_valid(_pathfinding):
		_resolve_pathfinding()
	if is_instance_valid(_pathfinding) and _pathfinding.has_method("is_walkable"):
		return bool(_pathfinding.call("is_walkable", c.x, c.y))
	return false


func _has_pathfinding() -> bool:
	if not is_instance_valid(_pathfinding):
		_resolve_pathfinding()
	return is_instance_valid(_pathfinding) and _pathfinding.has_method("is_walkable")


## Primera baldosa libre adyacente en barrido row-major del perimetro.
## Sin Pathfinding (o todo ocupado): offset determinista SE exterior.
func _find_spawn_cell(b: Dictionary) -> Vector2i:
	var origin: Vector2i = b["cell"]
	var size: Vector2i = b["size"]
	var perimeter: Array = []
	for dy in range(-1, size.y + 1):
		for dx in range(-1, size.x + 1):
			if dx >= 0 and dx < size.x and dy >= 0 and dy < size.y:
				continue # interior del footprint
			perimeter.append(origin + Vector2i(dx, dy))
	if _has_pathfinding():
		for c in perimeter:
			if _is_walkable_cell(c):
				return c
	# Fallback determinista: esquina exterior SE.
	return _clamp_cell(origin + Vector2i(size.x, size.y))


func _clamp_cell(c: Vector2i) -> Vector2i:
	return Vector2i(clampi(c.x, 0, GRID_W - 1), clampi(c.y, 0, GRID_H - 1))


# ---------------------------------------------------------------- helpers ---

func _emit_guarded(sig_name: String, args: Array) -> void:
	if EventBus.has_signal(sig_name):
		EventBus.callv("emit_signal", [sig_name] + args)


## Acepta Vector2i / Vector2 / Vector3 / Array [x, y] o [x, y, z]. Resto -> (0,0).
static func _as_cell(pos) -> Vector2i:
	if pos is Vector2i:
		return pos
	if pos is Vector2:
		return Vector2i(floori(pos.x), floori(pos.y))
	if pos is Vector3:
		return Vector2i(floori(pos.x), floori(pos.z))
	if typeof(pos) == TYPE_ARRAY:
		var a: Array = pos
		if a.size() >= 3:
			return Vector2i(floori(float(a[0])), floori(float(a[2])))
		if a.size() == 2:
			return Vector2i(floori(float(a[0])), floori(float(a[1])))
	return Vector2i.ZERO


static func _as_size(v) -> Vector2i:
	if v is Vector2i:
		return Vector2i(maxi(1, v.x), maxi(1, v.y))
	if v is Vector2:
		return Vector2i(maxi(1, floori(v.x)), maxi(1, floori(v.y)))
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return Vector2i(maxi(1, int(v[0])), maxi(1, int(v[1])))
	return Vector2i(3, 3)


## Cadena canonica del estado (para hash anti-desync en NetManager).
func sim_state_string() -> String:
	var parts: Array = []
	var ids: Array = _buildings.keys()
	ids.sort()
	for uid in ids:
		var b: Dictionary = _buildings[uid]
		var q: Array = b["queue"]
		var qparts: Array = []
		for e in q:
			qparts.append("%s:%d" % [str(e.get("unit_id", "")), int(e.get("ticks_left", 0))])
		var r: Vector2i = b["rally"]
		parts.append("b%d:%s:%s:r%d,%d" % [
			int(uid), str(b["building"]), "|".join(qparts), r.x, r.y])
	parts.append("spawned:%d:next:%d" % [_spawned.size(), _next_unit_uid])
	return ";".join(parts)

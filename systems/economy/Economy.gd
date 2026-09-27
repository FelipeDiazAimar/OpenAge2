extends Node
# Economy - recoleccion AoE2 determinista por tick (lockstep 10Hz).
#
# Maquina de estados por aldeano:
#   idle -> goto -> gather (gather_tick cada 1s = 10 ticks) -> return -> dropoff -> goto ...
#   El paso a "return" ocurre al llenar carry (10) o al agotarse el nodo.
#
# Rates (data/actions.json -> gather.rates_per_sec):
#   wood 0.39 | food_forage 0.41 | food_farm 0.32 | food_fish 0.43 | gold 0.38 | stone 0.36
# Drop-off: TC / campamento / molino mas cercano del mismo jugador (Manhattan).
# Granja: comida finita 250, auto-reconstruccion si hay 60 de madera.
# Determinismo: sin randf/Time/fisica; iteracion ordenada por id; movimiento lineal
#   con velocidad fija (aldeano.json speed 0.8 tiles/s).

const TICK_RATE := 10 # debe coincidir con SimAPI.TICK_RATE
const GATHER_TICKS := 10 # 1 segundo de recoleccion = 10 ticks
const CARRY_CAPACITY := 10.0 # gather_carry de aldeano.json / carry_capacity de actions.json
const VILLAGER_SPEED := 0.8 # tiles/s (aldeano.json speed)
const ARRIVE_EPS := 0.05 # tolerancia de llegada en tiles
const FARM_FOOD_MAX := 250.0
const FARM_REBUILD_WOOD_COST := 60.0

# Estados canonicos.
const ST_IDLE := "idle"
const ST_GOTO := "goto"
const ST_GATHER := "gather"
const ST_RETURN := "return"
const ST_DROPOFF := "dropoff"

# Rates por defecto = actions.json gather.rates_per_sec. Se re-cargan en _ready
# desde res://data/actions.json si el fichero existe (solo lectura, no afecta al tick).
var rates := {
	"wood": 0.39,
	"food_forage": 0.41,
	"food_farm": 0.32,
	"food_fish": 0.43,
	"gold": 0.38,
	"stone": 0.36,
}

# id -> {id, player_id, pos:Vector2, state, node_id, res_kind, carry_kind, carry_amount, tick_in_gather, dropoff_id, speed}
var _villagers := {}
# id -> {id, kind, amount, pos:Vector2, farm:bool, owner:int}
var _nodes := {}
# id -> {id, player_id, pos:Vector2, building:String, accepts:Array}
var _dropoffs := {}


func _ready() -> void:
	_load_rates_from_actions_json()
	if Engine.has_singleton("EventBus"):
		pass # autoloads reales, no singletons de engine; se accede por nombre
	EventBus.command_issued.connect(_on_cmd)
	EventBus.tick_finished.connect(_on_tick)


func _load_rates_from_actions_json() -> void:
	if not FileAccess.file_exists("res://data/actions.json"):
		return
	var f := FileAccess.open("res://data/actions.json", FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var r = parsed.get("actions", {}).get("gather", {}).get("rates_per_sec", {})
	if typeof(r) != TYPE_DICTIONARY:
		return
	for k in rates.keys():
		if r.has(k):
			rates[k] = float(r[k])
	var cap = parsed.get("actions", {}).get("gather", {}).get("carry_capacity", CARRY_CAPACITY)
	# CARRY_CAPACITY es const; solo se usa como referencia si difiere (aviso, no rompe determinismo).
	if float(cap) != CARRY_CAPACITY:
		push_warning("Economy: carry_capacity actions.json (%s) != const %s; se usa const." % [str(cap), str(CARRY_CAPACITY)])


# ---------------------------------------------------------------- comandos ---

func _on_cmd(cmd: Dictionary) -> void:
	if cmd.get("type", "") != "gather":
		return
	var payload: Dictionary = cmd.get("payload", {})
	var unit_ids: Array = _parse_unit_ids(payload)
	var node_id := int(payload.get("node_id", payload.get("resource_id", payload.get("target", -1))))
	if unit_ids.is_empty() or node_id < 0:
		return
	for vid in unit_ids:
		order_gather(int(vid), node_id)


func _parse_unit_ids(payload: Dictionary) -> Array:
	var out: Array = []
	for key in ["unit_ids", "villager_ids", "units"]:
		if payload.has(key) and typeof(payload[key]) == TYPE_ARRAY:
			for v in payload[key]:
				out.append(int(v))
	for key in ["unit_id", "villager_id", "unit", "villager"]:
		if payload.has(key):
			out.append(int(payload[key]))
	# Deduplicar preservando orden (determinista: luego se ordena por id al tick).
	var seen := {}
	var dedup: Array = []
	for v in out:
		if not seen.has(v):
			seen[v] = true
			dedup.append(v)
	return dedup


## Ordena a un aldeano recolectar un nodo. Llamado por _on_cmd o por Villager AI.
func order_gather(villager_id: int, node_id: int) -> bool:
	if not _villagers.has(villager_id):
		return false
	if not _nodes.has(node_id):
		return false
	var v: Dictionary = _villagers[villager_id]
	var n: Dictionary = _nodes[node_id]
	v["node_id"] = node_id
	v["res_kind"] = str(n["kind"])
	if float(v["carry_amount"]) <= 0.0:
		v["carry_kind"] = str(n["kind"])
	v["tick_in_gather"] = 0
	v["dropoff_id"] = -1
	# Si ya esta lleno (caso raro: re-orden con carga de otro recurso), primero entregar.
	if float(v["carry_amount"]) >= CARRY_CAPACITY - 0.0001 and str(v["carry_kind"]) != str(n["kind"]):
		v["state"] = ST_RETURN
		v["dropoff_id"] = nearest_dropoff(int(v["player_id"]), str(v["carry_kind"]), v["pos"])
	else:
		v["state"] = ST_GOTO
	return true


# --------------------------------------------------------------- registro ---

func register_villager(villager_id: int, player_id: int, pos, speed: float = VILLAGER_SPEED) -> void:
	_villagers[villager_id] = {
		"id": villager_id, "player_id": player_id, "pos": _as_vec2(pos),
		"state": ST_IDLE, "node_id": -1, "res_kind": "",
		"carry_kind": "", "carry_amount": 0.0,
		"tick_in_gather": 0, "dropoff_id": -1, "speed": speed,
	}


func register_node(node_id: int, kind: String, amount: float, pos, farm: bool = false, owner: int = -1) -> void:
	_nodes[node_id] = {
		"id": node_id, "kind": kind, "amount": float(amount),
		"pos": _as_vec2(pos), "farm": farm, "owner": owner,
	}


func register_dropoff(dropoff_id: int, player_id: int, pos, building: String = "centro_urbano", accepts: Array = []) -> void:
	# accepts vacio = acepta todo (TC). Campamentos/muelle filtran por recurso.
	_dropoffs[dropoff_id] = {
		"id": dropoff_id, "player_id": player_id, "pos": _as_vec2(pos),
		"building": building, "accepts": accepts.duplicate(),
	}


func remove_node(node_id: int) -> void:
	_nodes.erase(node_id)


func clear() -> void:
	_villagers.clear()
	_nodes.clear()
	_dropoffs.clear()


func get_villager(villager_id: int) -> Dictionary:
	return _villagers.get(villager_id, {})


# ------------------------------------------------------------------ tick ---

func _on_tick(t: int) -> void:
	tick(t)


## Avanza 1 tick de simulacion (0.1s). Orden determinista por id de aldeano.
func tick(_t: int) -> void:
	var ids: Array = _villagers.keys()
	ids.sort()
	for vid in ids:
		_step_villager(_villagers[vid])


func _step_villager(v: Dictionary) -> void:
	match str(v["state"]):
		ST_IDLE:
			pass # espera orden gather
		ST_GOTO:
			_step_goto(v)
		ST_GATHER:
			_step_gather(v)
		ST_RETURN:
			_step_return(v)
		ST_DROPOFF:
			_step_dropoff(v)
		_:
			v["state"] = ST_IDLE


func _step_goto(v: Dictionary) -> void:
	if not _nodes.has(int(v["node_id"])):
		v["state"] = ST_IDLE # nodo desaparecido (agotado y retirado)
		return
	var n: Dictionary = _nodes[int(v["node_id"])]
	v["pos"] = _move_towards(v["pos"], n["pos"], float(v["speed"]) / float(TICK_RATE))
	if _dist_euclid(v["pos"], n["pos"]) <= ARRIVE_EPS:
		v["state"] = ST_GATHER
		v["tick_in_gather"] = 0


func _step_gather(v: Dictionary) -> void:
	var nid := int(v["node_id"])
	if not _nodes.has(nid):
		# Nodo retirado: si lleva algo, entregarlo; si no, idle.
		if float(v["carry_amount"]) > 0.0:
			v["state"] = ST_RETURN
			v["dropoff_id"] = nearest_dropoff(int(v["player_id"]), str(v["carry_kind"]), v["pos"])
		else:
			v["state"] = ST_IDLE
		return
	var n: Dictionary = _nodes[nid]
	if float(n["amount"]) <= 0.0:
		_on_node_empty(v, n)
		return
	v["tick_in_gather"] = int(v["tick_in_gather"]) + 1
	if int(v["tick_in_gather"]) < GATHER_TICKS:
		return # gather_tick solo cada 1s
	v["tick_in_gather"] = 0
	var rate := float(rates.get(str(n["kind"]), 0.0))
	if rate <= 0.0:
		return
	var want: float = minf(rate, CARRY_CAPACITY - float(v["carry_amount"]))
	var got: float = minf(want, float(n["amount"]))
	n["amount"] = float(n["amount"]) - got
	v["carry_amount"] = float(v["carry_amount"]) + got
	v["carry_kind"] = str(n["kind"])
	if float(n["amount"]) <= 0.0:
		_on_node_empty(v, n)
		return
	if float(v["carry_amount"]) >= CARRY_CAPACITY - 0.0001:
		v["carry_amount"] = minf(float(v["carry_amount"]), CARRY_CAPACITY)
		v["state"] = ST_RETURN
		v["dropoff_id"] = nearest_dropoff(int(v["player_id"]), str(v["carry_kind"]), v["pos"])


## Nodo a cero: granja -> intentar reconstruir; otro recurso -> entregar lo que lleve.
func _on_node_empty(v: Dictionary, n: Dictionary) -> void:
	if bool(n.get("farm", false)):
		if _try_farm_rebuild(v, n):
			v["state"] = ST_GATHER # granja nueva, seguir picando
			v["tick_in_gather"] = 0
			return
		# Sin madera: buscar otra granja con comida del mismo jugador.
		var other := _find_fresh_farm(int(v["player_id"]))
		if other >= 0:
			v["node_id"] = other
			v["res_kind"] = str(_nodes[other]["kind"])
			v["state"] = ST_GOTO
			return
	if float(v["carry_amount"]) > 0.0:
		v["state"] = ST_RETURN
		v["dropoff_id"] = nearest_dropoff(int(v["player_id"]), str(v["carry_kind"]), v["pos"])
	else:
		v["state"] = ST_IDLE
		v["node_id"] = -1


func _step_return(v: Dictionary) -> void:
	var did := int(v["dropoff_id"])
	if did < 0 or not _dropoffs.has(did):
		did = nearest_dropoff(int(v["player_id"]), str(v["carry_kind"]), v["pos"])
		v["dropoff_id"] = did
	if did < 0:
		return # sin punto de entrega: espera (no pierde carga, determinista)
	var d: Dictionary = _dropoffs[did]
	v["pos"] = _move_towards(v["pos"], d["pos"], float(v["speed"]) / float(TICK_RATE))
	if _dist_euclid(v["pos"], d["pos"]) <= ARRIVE_EPS:
		v["state"] = ST_DROPOFF
		_step_dropoff(v) # entrega inmediata en el mismo tick (1 transicion/tick)


func _step_dropoff(v: Dictionary) -> void:
	var amount := float(v["carry_amount"])
	if amount > 0.0:
		GameManager.add_resource(int(v["player_id"]), _bank_kind(str(v["carry_kind"])), amount)
		v["carry_amount"] = 0.0
		v["carry_kind"] = ""
	# Bucle AoE2: volver al mismo nodo si aun tiene recurso.
	var nid := int(v["node_id"])
	if _nodes.has(nid) and float(_nodes[nid]["amount"]) > 0.0:
		v["state"] = ST_GOTO
		v["tick_in_gather"] = 0
		v["dropoff_id"] = -1
	elif _nodes.has(nid) and bool(_nodes[nid].get("farm", false)):
		# Granja agotada justo al entregar: reconstruir o reasignar.
		_on_node_empty(v, _nodes[nid])
	else:
		v["state"] = ST_IDLE
		v["node_id"] = -1
		v["dropoff_id"] = -1


# ------------------------------------------------------- granja / dropoff ---

## Granja agotada: cobra 60 madera y la rellena a 250. True si reconstruye.
func _try_farm_rebuild(v: Dictionary, n: Dictionary) -> bool:
	var pid := int(v["player_id"])
	if GameManager.try_spend(pid, {"wood": FARM_REBUILD_WOOD_COST}):
		n["amount"] = FARM_FOOD_MAX
		return true
	return false


## Otra granja con comida del mismo jugador (menor id = determinista).
func _find_fresh_farm(player_id: int) -> int:
	var best := -1
	for nid in _nodes.keys():
		var n: Dictionary = _nodes[nid]
		if bool(n.get("farm", false)) and float(n.get("amount", 0.0)) > 0.0:
			if int(n.get("owner", player_id)) == player_id:
				if best < 0 or int(nid) < best:
					best = int(nid)
	return best


## Drop-off mas cercano (Manhattan) del jugador que acepte el recurso. -1 si no hay.
func nearest_dropoff(player_id: int, res_kind: String, from_pos) -> int:
	var fp := _as_vec2(from_pos)
	var best := -1
	var best_d := 1e18
	var ids: Array = _dropoffs.keys()
	ids.sort()
	for did in ids:
		var d: Dictionary = _dropoffs[did]
		if int(d["player_id"]) != player_id:
			continue
		var accepts: Array = d.get("accepts", [])
		if not accepts.is_empty() and not accepts.has(res_kind):
			continue
		var dist := _manhattan(fp, d["pos"])
		if dist < best_d - 0.000001 or (absf(dist - best_d) <= 0.000001 and int(did) < best):
			best_d = dist
			best = int(did)
	return best


# ---------------------------------------------------------------- helpers ---

## food_forage / food_farm / food_fish -> food (GameManager solo guarda wood/food/gold/stone).
func _bank_kind(res_kind: String) -> String:
	if res_kind.begins_with("food"):
		return "food"
	return res_kind


func _manhattan(a: Vector2, b: Vector2) -> float:
	return absf(a.x - b.x) + absf(a.y - b.y)


func _dist_euclid(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)


func _move_towards(pos: Vector2, target: Vector2, max_step: float) -> Vector2:
	var d := pos.distance_to(target)
	if d <= max_step or d <= 0.000001:
		return target
	var t := max_step / d
	return Vector2(lerpf(pos.x, target.x, t), lerpf(pos.y, target.y, t))


## Acepta Vector2 / Vector3 / Array [x,y(,z)] y normaliza a Vector2 de tiles (x,z).
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


## Cadena canonica del estado (para hash anti-desync en NetManager).
func sim_state_string() -> String:
	var parts: Array = []
	var ids: Array = _villagers.keys()
	ids.sort()
	for vid in ids:
		var v: Dictionary = _villagers[vid]
		var p: Vector2 = v["pos"]
		parts.append("%d:%s:%d:%.3f:%d" % [
			int(vid), str(v["state"]), int(v["node_id"]),
			float(v["carry_amount"]), int(v["dropoff_id"])])
	var nids: Array = _nodes.keys()
	nids.sort()
	for nid in nids:
		parts.append("n%d:%.2f" % [int(nid), float(_nodes[nid]["amount"])])
	return "|".join(parts)

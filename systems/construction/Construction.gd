extends Node
# Construction - colocacion, obra y reparacion AoE2, determinista por tick (lockstep 10Hz).
#
# Comandos (via SimAPI.queue_command -> EventBus.command_issued):
#   build:  SimAPI.queue_command(pid, "build", {"building": "casa", "pos": [x, y],
#               "villager_ids": [vid1, vid2]})
#           aliases de payload: "unit_ids", "builders", "units" para aldeanos;
#           "building"/"building_id"/"id" para el edificio; "pos"/"position" [x,y] o [x,y,z].
#   cancel: SimAPI.queue_command(pid, "cancel", {"site_id": 3})
#           (alias de tipo: "cancel_build"; alias de payload: "id", "building_id").
#   repair: SimAPI.queue_command(pid, "repair", {"site_id": 3, "villager_ids": [vid]})
#           (alias de payload: "target_id", "target").
#
# Reglas:
#   - Fantasma: dentro del mapa, sin solape de huella (AABB) con ninguna obra o
#     edificio terminado, y para granja ("granja"/"farm") el aldeano constructor
#     debe estar a <= 8 tiles del sitio (FARM_MAX_DIST).
#   - Al colocar se cobra el coste via GameManager.try_spend; la obra nace con
#     10% del HP maximo y crece lineal hasta 100% con el progreso.
#   - Varios aldeanos aceleran lineal: progreso_por_tick = nº_constructores / ticks_totales_1_aldeano.
#   - Cancelar solo durante la obra reembolsa 50% via GameManager.refund_cancel.
#   - Reparar solo edificios terminados de aliados (mismo jugador o mismo equipo),
#     rate 15 hp/s (actions.json repair.rate_hp_per_sec) y coste 0.5x
#     (actions.json repair.cost_factor) proporcional al HP restaurado.
#   - Determinismo: sin randf/Time/fisica; toda la mutacion de HP/progreso ocurre
#     en tick() con iteracion ordenada por site_id; las ordenes solo asignan.
#   - DB de edificios: se carga de res://data/buildings/*.json en _ready
#     (coste, hp, size_tiles, build_time_sec); fallback para casa/cuartel/
#     centro_urbano + granja si el JSON falta.

const TICK_RATE := 10 # debe coincidir con SimAPI.TICK_RATE
const BUILDINGS_DIR := "res://data/buildings"
const ACTIONS_PATH := "res://data/actions.json"
const MAP_PATH := "res://data/maps/arabia.json"

const FOUNDATION_HP_FACTOR := 0.1 # la obra nace al 10% del HP
const FARM_MAX_DIST := 8.0 # tiles: granja a max 8 del aldeano (requisito)
const BUILDER_RANGE := 5.0 # tiles: constructor mas lejos no aporta ese tick
const REPAIR_RANGE := 5.0 # tiles: reparador mas lejos no aporta ese tick

# Fallback si los JSON no son legibles (debe coincidir con data/buildings/*.json).
const FALLBACK_BUILDINGS := [
	{"id": "casa", "hp": 550, "size_tiles": [2, 2], "cost": {"wood": 25.0}, "build_time_sec": 20},
	{"id": "cuartel", "hp": 1200, "size_tiles": [3, 3], "cost": {"wood": 175.0}, "build_time_sec": 50},
	{"id": "centro_urbano", "hp": 2400, "size_tiles": [4, 4], "cost": {"wood": 275.0}, "build_time_sec": 120},
	{"id": "granja", "hp": 100, "size_tiles": [2, 2], "cost": {"wood": 60.0}, "build_time_sec": 15},
]

const ST_CONSTRUCTION := "construction"
const ST_COMPLETE := "complete"

# id normalizado -> {id, hp_max, size:Vector2i, cost:Dictionary, build_time_sec:int}
var buildings_db := {}
# site_id -> {id, building, player_id, pos:Vector2 (centro, tiles), size:Vector2i,
#   hp, hp_max, progress:float 0..1, state, cost:Dictionary, total_ticks:int,
#   builders:Array[int], repairers:Array[int]}
var sites := {}
# villager_id -> {player_id, pos:Vector2}
var villagers := {}
var map_size := Vector2i(144, 144) # por defecto arabia.json size_tiles
var repair_rate := 15.0 # hp/s (actions.json repair.rate_hp_per_sec)
var repair_cost_factor := 0.5 # (actions.json repair.cost_factor)
var _next_site_id := 1


func _ready() -> void:
	_load_buildings_db()
	_load_repair_params()
	_load_map_size()
	EventBus.command_issued.connect(_on_cmd)
	EventBus.tick_finished.connect(_on_tick)


# ------------------------------------------------------- carga de datos ---

func _load_buildings_db() -> void:
	buildings_db.clear()
	# 1) Fallback primero (garantiza casa/cuartel/TC/granja siempre).
	for b in FALLBACK_BUILDINGS:
		_register_building_data(b)
	# 2) JSON reales sobrescriben el fallback.
	var dir := DirAccess.open(BUILDINGS_DIR)
	if dir == null:
		return
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		var f := FileAccess.open(BUILDINGS_DIR + "/" + fname, FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("id"):
			_register_building_data(parsed)


func _register_building_data(b: Dictionary) -> void:
	var bid := str(b.get("id", "")).to_lower().strip_edges()
	if bid.is_empty():
		return
	var size_arr: Array = b.get("size_tiles", [2, 2])
	var cost: Dictionary = {}
	for k in (b.get("cost", {}) as Dictionary).keys():
		cost[str(k)] = float((b["cost"] as Dictionary)[k])
	buildings_db[bid] = {
		"id": bid,
		"hp_max": float(b.get("hp", 100)),
		"size": Vector2i(int(size_arr[0]), int(size_arr[1])),
		"cost": cost,
		"build_time_sec": maxi(1, int(b.get("build_time_sec", 20))),
	}
	# Alias granja <-> farm (FarmingTrade usa "farm", el mapa de teclas "granja").
	if bid == "granja" and not buildings_db.has("farm"):
		buildings_db["farm"] = (buildings_db[bid] as Dictionary).duplicate(true)
	if bid == "farm" and not buildings_db.has("granja"):
		buildings_db["granja"] = (buildings_db[bid] as Dictionary).duplicate(true)


func _load_repair_params() -> void:
	if not FileAccess.file_exists(ACTIONS_PATH):
		return
	var f := FileAccess.open(ACTIONS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var rep: Dictionary = (parsed as Dictionary).get("actions", {}).get("repair", {})
	if rep.has("rate_hp_per_sec"):
		repair_rate = float(rep["rate_hp_per_sec"])
	if rep.has("cost_factor"):
		repair_cost_factor = float(rep["cost_factor"])


func _load_map_size() -> void:
	if not FileAccess.file_exists(MAP_PATH):
		return
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("size_tiles"):
		var s: Array = parsed["size_tiles"]
		if s.size() >= 2:
			map_size = Vector2i(maxi(8, int(s[0])), maxi(8, int(s[1])))


func set_map_size(w: int, h: int) -> void:
	map_size = Vector2i(maxi(8, w), maxi(8, h))


# ------------------------------------------------------------- registro ---

func register_villager(villager_id: int, player_id: int, pos) -> void:
	villagers[villager_id] = {"player_id": player_id, "pos": _as_vec2(pos)}


func update_villager_pos(villager_id: int, pos) -> void:
	if villagers.has(villager_id):
		(villagers[villager_id] as Dictionary)["pos"] = _as_vec2(pos)


func remove_villager(villager_id: int) -> void:
	villagers.erase(villager_id)
	for sid in sites.keys():
		(sites[sid]["builders"] as Array).erase(villager_id)
		(sites[sid]["repairers"] as Array).erase(villager_id)


func clear() -> void:
	sites.clear()
	villagers.clear()
	_next_site_id = 1


func get_site(site_id: int) -> Dictionary:
	return sites.get(site_id, {})


func get_sites_of(player_id: int) -> Array:
	var out: Array = []
	for sid in sites.keys():
		if int(sites[sid]["player_id"]) == player_id:
			out.append(sid)
	out.sort()
	return out


# ------------------------------------------------------- datos edificio ---

func is_known_building(building_id: String) -> bool:
	return buildings_db.has(_norm_building(building_id))


func get_building_data(building_id: String) -> Dictionary:
	return (buildings_db.get(_norm_building(building_id), {}) as Dictionary).duplicate(true)


func get_cost(building_id: String) -> Dictionary:
	return get_building_data(building_id).get("cost", {})


func get_hp_max(building_id: String) -> float:
	return float(get_building_data(building_id).get("hp_max", 0.0))


func get_build_time_ticks(building_id: String) -> int:
	return maxi(1, int(get_building_data(building_id).get("build_time_sec", 20)) * TICK_RATE)


func _norm_building(b: String) -> String:
	var s := b.to_lower().strip_edges()
	if s == "farm":
		return "granja"
	return s


func _is_farm(building_id: String) -> bool:
	return _norm_building(building_id) in ["granja", "farm"]


# -------------------------------------------------------------- fantasma ---

## Validacion pura (para el fantasma verde/rojo del HUD). No muta ni cobra.
## builder_id >= 0 y registrado se usa para la regla de distancia de granja.
func can_place(player_id: int, building_id: String, pos, builder_id: int = -1) -> Dictionary:
	var bid := _norm_building(building_id)
	if not buildings_db.has(bid):
		return {"ok": false, "reason": "unknown_building"}
	if not GameManager.is_alive(player_id):
		return {"ok": false, "reason": "dead_or_over"}
	var data: Dictionary = buildings_db[bid]
	var p := _as_vec2(pos)
	var size: Vector2i = data["size"]
	if not _inside_map(p, size):
		return {"ok": false, "reason": "outside_map"}
	if _overlaps_any(p, size):
		return {"ok": false, "reason": "overlaps"}
	if _is_farm(bid):
		var chk := _check_farm_distance(player_id, p, builder_id)
		if not bool(chk.get("ok", false)):
			return chk
	if not GameManager.has_resources(player_id, (data["cost"] as Dictionary)):
		return {"ok": false, "reason": "no_resources"}
	return {"ok": true, "reason": "ok"}


## Coloca la obra: valida, cobra via try_spend y crea el site al 10% HP.
## builders: Array[int] de aldeanos asignados (aportan desde el proximo tick).
## Devuelve {ok, reason, site_id (-1 si falla)}.
func place_ghost(player_id: int, building_id: String, pos, builders: Array = []) -> Dictionary:
	var first_builder := int(builders[0]) if not builders.is_empty() else -1
	var chk := can_place(player_id, building_id, pos, first_builder)
	if not bool(chk.get("ok", false)):
		_emit_opt("ghost_rejected", [player_id, _norm_building(building_id), str(chk.get("reason", ""))])
		return {"ok": false, "reason": str(chk.get("reason", "")), "site_id": -1}
	var bid := _norm_building(building_id)
	var data: Dictionary = buildings_db[bid]
	var cost: Dictionary = (data["cost"] as Dictionary).duplicate(true)
	if not GameManager.try_spend(player_id, cost):
		return {"ok": false, "reason": "no_resources", "site_id": -1}
	var sid := _next_site_id
	_next_site_id += 1
	var hp_max := float(data["hp_max"])
	var clean_builders: Array = []
	for b in builders:
		var bv := int(b)
		if not clean_builders.has(bv):
			clean_builders.append(bv)
	clean_builders.sort()
	sites[sid] = {
		"id": sid, "building": bid, "player_id": player_id,
		"pos": _as_vec2(pos), "size": data["size"],
		"hp": hp_max * FOUNDATION_HP_FACTOR, "hp_max": hp_max,
		"progress": 0.0, "state": ST_CONSTRUCTION,
		"cost": cost, "total_ticks": maxi(1, int(data["build_time_sec"]) * TICK_RATE),
		"builders": clean_builders, "repairers": [],
	}
	return {"ok": true, "reason": "ok", "site_id": sid}


## Alias de place_ghost para agentes que hablan en terminos de ordenes.
func order_build(player_id: int, building_id: String, pos, builders: Array = []) -> Dictionary:
	return place_ghost(player_id, building_id, pos, builders)


func _check_farm_distance(player_id: int, pos: Vector2, builder_id: int) -> Dictionary:
	# Regla pedida: granja a max 8 tiles del aldeano que la coloca.
	if builder_id >= 0 and villagers.has(builder_id):
		var v: Dictionary = villagers[builder_id]
		if (pos - (v["pos"] as Vector2)).length() > FARM_MAX_DIST + 0.001:
			return {"ok": false, "reason": "farm_too_far"}
		return {"ok": true, "reason": "ok"}
	# Sin aldeano registrado no se puede verificar: se permite (el HUD deberia
	# pasar builder_id) pero se deja constancia para tests.
	return {"ok": true, "reason": "ok_no_builder_check"}


func _inside_map(pos: Vector2, size: Vector2i) -> bool:
	var half := Vector2(float(size.x) * 0.5, float(size.y) * 0.5)
	var min_c := pos - half
	var max_c := pos + half
	return min_c.x >= 0.0 and min_c.y >= 0.0 and max_c.x <= float(map_size.x) and max_c.y <= float(map_size.y)


func _overlaps_any(pos: Vector2, size: Vector2i) -> bool:
	for sid in sites.keys():
		var s: Dictionary = sites[sid]
		if _rects_overlap(pos, size, s["pos"], s["size"]):
			return true
	return false


func _rects_overlap(pa: Vector2, sa: Vector2i, pb: Vector2, sb: Vector2i) -> bool:
	var aha_x := float(sa.x) * 0.5
	var aha_y := float(sa.y) * 0.5
	var ahb_x := float(sb.x) * 0.5
	var ahb_y := float(sb.y) * 0.5
	return absf(pa.x - pb.x) < aha_x + ahb_x - 0.000001 and absf(pa.y - pb.y) < aha_y + ahb_y - 0.000001


# -------------------------------------------------------------- comandos ---

func _on_cmd(cmd: Dictionary) -> void:
	# Solo asignaciones; el HP/progreso avanza en tick() (determinista).
	var t := str(cmd.get("type", ""))
	if t not in ["build", "cancel", "cancel_build", "repair"]:
		return
	var pid := int(cmd.get("player_id", -1))
	var payload: Dictionary = cmd.get("payload", {})
	match t:
		"build":
			var bid := str(payload.get("building", payload.get("building_id", payload.get("id", ""))))
			var pos = payload.get("pos", payload.get("position", Vector2.ZERO))
			order_build(pid, bid, pos, _parse_ids(payload))
		"cancel", "cancel_build":
			cancel_construction(int(payload.get("site_id", payload.get("id", payload.get("building_id", -1)))), pid)
		"repair":
			order_repair(_parse_ids(payload), int(payload.get("site_id", payload.get("target_id", payload.get("target", -1)))), pid)


func _parse_ids(payload: Dictionary) -> Array:
	var out: Array = []
	for key in ["villager_ids", "unit_ids", "builders", "repairers", "units"]:
		if payload.has(key) and typeof(payload[key]) == TYPE_ARRAY:
			for v in payload[key]:
				out.append(int(v))
	for key in ["villager_id", "unit_id", "villager", "builder"]:
		if payload.has(key):
			out.append(int(payload[key]))
	var seen := {}
	var dedup: Array = []
	for v in out:
		if not seen.has(v):
			seen[v] = true
			dedup.append(v)
	return dedup


## Cancela una obra y reembolsa el 50% via GameManager.refund_cancel.
## Solo durante la construccion; ya terminado devuelve false.
func cancel_construction(site_id: int, by_player: int = -1) -> bool:
	if not sites.has(site_id):
		return false
	var s: Dictionary = sites[site_id]
	if str(s["state"]) != ST_CONSTRUCTION:
		return false
	if by_player >= 0 and int(s["player_id"]) != by_player and not _is_ally(by_player, int(s["player_id"])):
		return false
	GameManager.refund_cancel(int(s["player_id"]), (s["cost"] as Dictionary))
	var owner := int(s["player_id"])
	var bid := str(s["building"])
	sites.erase(site_id)
	_emit_opt("construction_cancelled", [owner, bid, site_id])
	return true


## Asigna reparadores a un edificio terminado aliado danado.
func order_repair(repairer_ids: Array, site_id: int, ordering_player: int = -1) -> bool:
	if not sites.has(site_id) or repairer_ids.is_empty():
		return false
	var s: Dictionary = sites[site_id]
	if str(s["state"]) != ST_COMPLETE:
		return false # la obra se construye con build, no con repair
	if float(s["hp"]) >= float(s["hp_max"]) - 0.000001:
		return false # nada que reparar
	var owner := int(s["player_id"])
	for vid in repairer_ids:
		var vowner := ordering_player
		if villagers.has(int(vid)):
			vowner = int((villagers[int(vid)] as Dictionary)["player_id"])
		if vowner >= 0 and not _is_ally(vowner, owner):
			return false # solo aliados (mismo jugador o equipo)
	var arr: Array = s["repairers"]
	for vid in repairer_ids:
		if not arr.has(int(vid)):
			arr.append(int(vid))
	arr.sort()
	return true


func stop_repair(site_id: int, repairer_id: int = -1) -> void:
	if not sites.has(site_id):
		return
	if repairer_id < 0:
		(sites[site_id]["repairers"] as Array).clear()
	else:
		(sites[site_id]["repairers"] as Array).erase(repairer_id)


func _is_ally(a: int, b: int) -> bool:
	if a == b:
		return true
	var pa := GameManager.get_player(a)
	var pb := GameManager.get_player(b)
	if pa.is_empty() or pb.is_empty():
		return false
	return int(pa.get("team", a)) == int(pb.get("team", b))


# ------------------------------------------------------------------ tick ---

func _on_tick(t: int) -> void:
	tick(t)


## Avanza 1 tick (0.1s). Orden determinista por site_id.
func tick(_t: int) -> void:
	var ids: Array = sites.keys()
	ids.sort()
	for sid in ids:
		if not sites.has(sid):
			continue # pudo cancelarse/completarse este mismo tick
		var s: Dictionary = sites[sid]
		if str(s["state"]) == ST_CONSTRUCTION:
			_step_construction(s)
		elif str(s["state"]) == ST_COMPLETE:
			_step_repair(s)


func _active_in_range(ids: Array, site_pos: Vector2, radius: float) -> Array:
	# Constructores/reparadores que aportan este tick: los no registrados aportan
	# (compatibilidad con tests sin registro); los registrados solo en rango.
	var out: Array = []
	for vid in ids:
		var v := int(vid)
		if not villagers.has(v):
			out.append(v)
			continue
		var vv: Dictionary = villagers[v]
		if ((vv["pos"] as Vector2) - site_pos).length() <= radius + 0.001:
			out.append(v)
	return out


func _step_construction(s: Dictionary) -> void:
	var active := _active_in_range(s["builders"], s["pos"], BUILDER_RANGE)
	if active.is_empty():
		return # sin aldeanos (o todos lejos): la obra espera, determinista
	var total := maxi(1, int(s["total_ticks"]))
	# Varios aldeanos aceleran lineal: N aldeanos = N veces mas rapido.
	s["progress"] = clampf(float(s["progress"]) + float(active.size()) / float(total), 0.0, 1.0)
	s["hp"] = float(s["hp_max"]) * lerpf(FOUNDATION_HP_FACTOR, 1.0, float(s["progress"]))
	if float(s["progress"]) >= 1.0 - 0.000001:
		_complete_site(s)


func _complete_site(s: Dictionary) -> void:
	s["progress"] = 1.0
	s["hp"] = float(s["hp_max"])
	s["state"] = ST_COMPLETE
	(s["builders"] as Array).clear()
	var pid := int(s["player_id"])
	GameManager.register_building(pid, str(s["building"]))
	if _norm_building(str(s["building"])) == "casa":
		GameManager.on_house_completed(pid)
	var p3 := Vector3((s["pos"] as Vector2).x, 0.0, (s["pos"] as Vector2).y)
	EventBus.building_placed.emit(pid, str(s["building"]), p3)
	_emit_opt("building_completed", [pid, str(s["building"]), int(s["id"])])


func _step_repair(s: Dictionary) -> void:
	var missing := float(s["hp_max"]) - float(s["hp"])
	if missing <= 0.000001:
		(s["repairers"] as Array).clear()
		return
	var active := _active_in_range(s["repairers"], s["pos"], REPAIR_RANGE)
	if active.is_empty():
		return
	# HP de este tick, repartido lineal entre reparadores (15 hp/s en total por aldeano).
	var gain: float = minf(missing, repair_rate * float(active.size()) / float(TICK_RATE))
	var cost_tick := _repair_cost_for(float(s["hp_max"]), (s["cost"] as Dictionary), gain)
	var owner := int(s["player_id"])
	if not cost_tick.is_empty() and not GameManager.has_resources(owner, cost_tick):
		return # sin fondos: la reparacion espera (no HP gratis)
	if not cost_tick.is_empty() and not GameManager.try_spend(owner, cost_tick):
		return
	s["hp"] = minf(float(s["hp_max"]), float(s["hp"]) + gain)
	_emit_opt("building_repaired", [owner, int(s["id"]), float(s["hp"])])


## Coste de reparar `gain` HP: fraccion del coste original * cost_factor (0.5x).
func _repair_cost_for(hp_max: float, cost: Dictionary, gain: float) -> Dictionary:
	var out := {}
	if hp_max <= 0.0 or gain <= 0.0:
		return out
	var frac := gain / hp_max * repair_cost_factor
	for k in cost.keys():
		var amount := float(cost[k]) * frac
		if amount > 0.000001:
			out[k] = amount
	return out


# --------------------------------------------------------------- helpers ---

func damage_site(site_id: int, amount: float) -> bool:
	# Utilidad para combate/tests: dana (nunca bajo 0). Casa destruida -> -pop_cap.
	if not sites.has(site_id) or amount <= 0.0:
		return false
	var s: Dictionary = sites[site_id]
	s["hp"] = maxf(0.0, float(s["hp"]) - amount)
	if float(s["hp"]) <= 0.0:
		_destroy_site(s)
	return true


func _destroy_site(s: Dictionary) -> void:
	var pid := int(s["player_id"])
	var was_complete := str(s["state"]) == ST_COMPLETE
	var bid := str(s["building"])
	sites.erase(int(s["id"]))
	GameManager.unregister_building(pid, bid)
	if _norm_building(bid) == "casa" and was_complete:
		GameManager.on_house_destroyed(pid)
	_emit_opt("building_destroyed", [pid, bid, int(s["id"])])


func _emit_opt(signal_name: String, args: Array) -> void:
	# Senales opcionales (compatibilidad): solo se emiten si existen en EventBus.
	if not EventBus.has_signal(signal_name):
		return
	match args.size():
		2:
			EventBus.emit_signal(signal_name, args[0], args[1])
		3:
			EventBus.emit_signal(signal_name, args[0], args[1], args[2])
		_:
			EventBus.emit_signal(signal_name)


## Acepta Vector2 / Vector3 / Array [x,y(,z)] y normaliza a Vector2 en tiles (x,z).
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
	var ids: Array = sites.keys()
	ids.sort()
	for sid in ids:
		var s: Dictionary = sites[sid]
		parts.append("%d:%s:%d:%.1f:%.3f:%s" % [
			int(sid), str(s["building"]), int(s["player_id"]),
			float(s["hp"]), float(s["progress"]), str(s["state"])])
	return "|".join(parts)


func sim_hash() -> int:
	return SimAPI.sim_hash(sim_state_string())

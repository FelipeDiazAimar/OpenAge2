extends Node
# EnemyAI - bot RTS determinista: economía, casas, ejército y ataques.
# SOLO la ejecuta el anfitrión (en LAN solo el host; en solo siempre hay
# "host" implícito). Así los comandos del bot entran una sola vez al lockstep
# y todos los peers los replican igual. Determinista: solo lee estado sim
# (Economy/Production/GameManager) y ordena por SimAPI en ticks fijos.

const CHECK_EVERY := 20 # ticks entre pasadas de micro (2s)
const CASA_FIRST_TICK := 1200 # ~2min: primera oleada de casas si hace falta
const CUARTEL_TICK := 1800 # ~3min: cuartel
const ATTACK_TICK := 4800 # ~8min: primer ataque
const REATTACK_EVERY := 2400 # re-atacar cada ~4min con lo que haya

const COST_ALDEANO := {"food": 50.0}
const COST_CASA := {"wood": 25.0}
const COST_CUARTEL := {"wood": 175.0}
const COST_MILICIA := {"food": 60.0, "gold": 20.0}
const CASA_OFFSETS := [Vector2i(5, 1), Vector2i(-5, 1), Vector2i(1, 5), Vector2i(-1, 5), Vector2i(5, -3)]

var economy: Node = null
var production: Node = null
var combat: Node = null
var ai_pids: Array = []
var tc_tiles := {} # pid -> Vector2i
var tc_uids := {} # pid -> uid edificio TC en Production
var _flags := {} # pid -> {casas:int, cuartel:bool, attacked:int, last_attack:int}


func setup(p_economy: Node, p_production: Node, p_combat: Node, p_pids: Array, p_tc_tiles: Dictionary, p_tc_uids: Dictionary) -> void:
	economy = p_economy
	production = p_production
	combat = p_combat
	ai_pids = p_pids.duplicate()
	tc_tiles = p_tc_tiles.duplicate(true)
	tc_uids = p_tc_uids.duplicate(true)
	for pid in ai_pids:
		_flags[int(pid)] = {"casas": 0, "cuartel": false, "attacked": 0, "last_attack": -100000}


func _ready() -> void:
	EventBus.tick_finished.connect(_on_tick)


func _should_run() -> bool:
	if ai_pids.is_empty() or economy == null:
		return false
	if multiplayer.has_multiplayer_peer():
		return bool(NetManager.is_host)
	return true # solo/local: el bot juega


func _on_tick(t: int) -> void:
	if not _should_run() or t % CHECK_EVERY != 0:
		return
	for pid in ai_pids:
		_bot_tick(int(pid), t)


func _bot_tick(pid: int, t: int) -> void:
	_assign_gatherers(pid)
	_maybe_house(pid, t)
	_maybe_train_villager(pid)
	_maybe_barracks(pid, t)
	_maybe_train_army(pid, t)
	_maybe_attack(pid, t)


# ------------------------------------------------------------- economía ---

## Aldeanos idle -> recurso con cantidad más cercano (uno por nodo, máx 5).
func _assign_gatherers(pid: int) -> void:
	var evills = economy.get("_villagers")
	var enodes = economy.get("_nodes")
	if typeof(evills) != TYPE_DICTIONARY or typeof(enodes) != TYPE_DICTIONARY:
		return
	var idle: Array = []
	for vid in (evills as Dictionary).keys():
		var v: Dictionary = (evills as Dictionary)[vid]
		if int(v.get("player_id", -1)) == pid and str(v.get("state", "idle")) == "idle":
			idle.append(int(vid))
	idle.sort()
	if idle.is_empty():
		return
	var per_node := {} # node_id -> Array[vid]
	for vid in idle:
		var vp: Vector2 = (evills as Dictionary)[vid]["pos"]
		var best := -1
		var best_d := 1e18
		var nids: Array = (enodes as Dictionary).keys()
		nids.sort()
		for nid in nids:
			var n: Dictionary = (enodes as Dictionary)[nid]
			if float(n.get("amount", 0.0)) <= 0.0:
				continue
			if (per_node.get(int(nid), []) as Array).size() >= 5:
				continue
			var d := vp.distance_to(n.get("pos", Vector2.ZERO))
			if d < best_d:
				best_d = d
				best = int(nid)
		if best < 0:
			continue
		if not per_node.has(best):
			per_node[best] = []
		(per_node[best] as Array).append(vid)
	for nid in per_node.keys():
		SimAPI.queue_command(pid, "gather", {"unit_ids": (per_node[nid] as Array).duplicate(), "node_id": int(nid)})


func _first_villager(pid: int) -> int:
	var evills = economy.get("_villagers")
	if typeof(evills) != TYPE_DICTIONARY:
		return -1
	var ids: Array = (evills as Dictionary).keys()
	ids.sort()
	for vid in ids:
		if int((evills as Dictionary)[vid].get("player_id", -1)) == pid:
			return int(vid)
	return -1


func _maybe_house(pid: int, t: int) -> void:
	if t < CASA_FIRST_TICK:
		return
	var fl: Dictionary = _flags[pid]
	if int(fl.get("casas", 0)) >= CASA_OFFSETS.size():
		return
	if GameManager.get_free_supply(pid) > 1:
		return
	if not GameManager.has_resources(pid, COST_CASA):
		return
	var v := _first_villager(pid)
	if v < 0 or not tc_tiles.has(pid):
		return
	var tc: Vector2i = tc_tiles[pid]
	var off: Vector2i = CASA_OFFSETS[int(fl["casas"]) % CASA_OFFSETS.size()]
	var pos := Vector2i(clampi(tc.x + off.x, 6, 137), clampi(tc.y + off.y, 6, 137))
	SimAPI.queue_command(pid, "build", {"unit_ids": [v], "building": "casa", "pos": [pos.x, pos.y]})
	fl["casas"] = int(fl["casas"]) + 1


func _maybe_train_villager(pid: int) -> void:
	if not tc_uids.has(pid) or not GameManager.can_train(pid, 1):
		return
	if not GameManager.has_resources(pid, COST_ALDEANO):
		return
	if production.has_method("get_queue") and (production.get_queue(int(tc_uids[pid])) as Array).size() >= 2:
		return
	SimAPI.queue_command(pid, "train", {"building_id": int(tc_uids[pid]), "unit_id": "aldeano"})


# -------------------------------------------------------------- ejército ---

func _cuartel_uid(pid: int) -> int:
	if production == null:
		return -1
	var all = production.get("_buildings")
	if typeof(all) != TYPE_DICTIONARY:
		return -1
	for uid in (all as Dictionary).keys():
		var b: Dictionary = (all as Dictionary)[uid]
		if int(b.get("player_id", -1)) == pid and str(b.get("building", "")) == "cuartel":
			return int(uid)
	return -1


func _maybe_barracks(pid: int, t: int) -> void:
	if t < CUARTEL_TICK or bool(_flags[pid].get("cuartel", false)):
		return
	if _cuartel_uid(pid) >= 0:
		_flags[pid]["cuartel"] = true
		return
	if not GameManager.has_resources(pid, COST_CUARTEL):
		return
	var v := _first_villager(pid)
	if v < 0 or not tc_tiles.has(pid):
		return
	var tc: Vector2i = tc_tiles[pid]
	var pos := Vector2i(clampi(tc.x + 7, 6, 137), clampi(tc.y + 7, 6, 137))
	SimAPI.queue_command(pid, "build", {"unit_ids": [v], "building": "cuartel", "pos": [pos.x, pos.y]})
	_flags[pid]["cuartel"] = true # un intento por partida (si falla, a pelear igual)


func _army_uids(pid: int) -> Array:
	var out: Array = []
	if production == null or not production.has_method("get_spawned"):
		return out
	for rec in production.get_spawned():
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		if int(rec.get("player_id", -1)) != pid:
			continue
		if str(rec.get("unit_id", "aldeano")) == "aldeano":
			continue
		var uid := int(rec.get("uid", -1))
		if combat != null and combat.has_method("is_alive") and not bool(combat.is_alive(uid)):
			continue
		out.append(uid)
	out.sort()
	return out


func _maybe_train_army(pid: int, t: int) -> void:
	if t < CUARTEL_TICK:
		return
	var q := _cuartel_uid(pid)
	if q < 0 or not GameManager.can_train(pid, 1):
		return
	if _army_uids(pid).size() >= 6:
		return
	if production.has_method("get_queue") and (production.get_queue(q) as Array).size() >= 1:
		return
	if not GameManager.has_resources(pid, COST_MILICIA):
		return
	SimAPI.queue_command(pid, "train", {"building_id": q, "unit_id": "milicia"})


func _maybe_attack(pid: int, t: int) -> void:
	var army := _army_uids(pid)
	if army.size() < 2:
		return
	var fl: Dictionary = _flags[pid]
	var first := t >= ATTACK_TICK and int(fl.get("attacked", 0)) == 0
	var repeat := int(fl.get("attacked", 0)) > 0 and t - int(fl.get("last_attack", 0)) >= REATTACK_EVERY and army.size() >= 4
	if not (first or repeat):
		return
	var target := _enemy_tc_tile(pid)
	SimAPI.queue_command(pid, "attack_move", {"unit_ids": army, "pos": [target.x, target.y]})
	fl["attacked"] = int(fl.get("attacked", 0)) + 1
	fl["last_attack"] = t


func _enemy_tc_tile(pid: int) -> Vector2i:
	var ids: Array = tc_tiles.keys()
	ids.sort()
	for other in ids:
		if int(other) != pid:
			return tc_tiles[other]
	return Vector2i(72, 72)

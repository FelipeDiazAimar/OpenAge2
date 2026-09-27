extends RefCounted
## Simulación de una partida: jugadores, spawn, cola de comandos con retardo
## de entrada y tick determinista. El render solo lee `world`.

const World := preload("res://engine/sim/World.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const FP := preload("res://engine/sim/FixedPoint.gd")
const PlayerDefs := preload("res://engine/data/PlayerDefs.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")
const GatherSystem := preload("res://engine/sim/systems/GatherSystem.gd")

const INPUT_DELAY := 2
const START_RES := {"wood": 200, "food": 200, "gold": 100, "stone": 200}
const POP_MAX := 200

var registry
var world := World.new()
var grid
var players: Array[Dictionary] = []
var _pending: Dictionary = {}
var _seq := 0


func _init(p_registry, map_w: int, map_h: int) -> void:
	registry = p_registry
	grid = Grid.new(map_w, map_h)


func add_player(pid: int, civ: String, team: int) -> void:
	var res := {}
	for k in START_RES:
		res[k] = int(START_RES[k]) * FP.SCALE
	players.append({"id": pid, "civ": civ, "team": team, "defs": PlayerDefs.new(registry.defs, civ), "res": res})


func def_for(id: int) -> Dictionary:
	if not world.entities.has(id):
		return {}
	var e: Dictionary = world.entities[id]
	var owner: int = e["owner"]
	if owner >= 0 and owner < players.size():
		return players[owner]["defs"].get_def(e["def_id"])
	return registry.get_def(e["def_id"])


func spawn(def_id: String, owner: int, tile: Vector2i) -> int:
	var def: Dictionary
	if owner >= 0 and owner < players.size():
		def = players[owner]["defs"].get_def(def_id)
	else:
		def = registry.get_def(def_id)
	if def.is_empty():
		return -1
	if str(def["type"]) == "building":
		var size := Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
		grid.block_rect(tile, size)
		return world.spawn(def, owner, tile * FP.SCALE + size * (FP.SCALE / 2))
	if str(def["type"]) == "resource":
		grid.set_blocked(tile, true)
	return world.spawn(def, owner, Grid.center_of(tile))


func remove(id: int) -> void:
	if not world.entities.has(id):
		return
	var e: Dictionary = world.entities[id]
	var pos: Vector2i = e["pos"]
	match str(e["type"]):
		"building":
			var def := def_for(id)
			var size := Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
			grid.block_rect(Grid.tile_of(pos - size * (FP.SCALE / 2)), size, false)
		"resource":
			grid.set_blocked(Grid.tile_of(pos), false)
	world.despawn(id)


func res_of(pid: int) -> Dictionary:
	var out := {}
	var res: Dictionary = players[pid]["res"]
	for k in START_RES:
		out[k] = int(res[k]) / FP.SCALE
	return out


func add_res(pid: int, res: String, milli: int) -> void:
	var r: Dictionary = players[pid]["res"]
	if r.has(res):
		r[res] = int(r[res]) + milli


func population(pid: int) -> Vector2i:
	var used := 0
	var cap := 0
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if int(e["owner"]) != pid:
			continue
		var def := def_for(id)
		if str(e["type"]) == "unit":
			used += int(def.get("pop_cost", 0))
		elif world.has_ability(id, "ProvidesPop"):
			cap += int(world.comp(id, "ProvidesPop")["params"]["amount"])
	return Vector2i(used, mini(cap, POP_MAX))


func gatherer_counts(pid: int) -> Dictionary:
	var out := {"wood": 0, "food": 0, "gold": 0, "stone": 0}
	for id in world.ids_with("Gather"):
		if int(world.entities[id]["owner"]) != pid:
			continue
		var r := GatherSystem.task_resource(self, id)
		if out.has(r):
			out[r] += 1
	return out


func state_hash() -> String:
	var parts := PackedStringArray([world.state_hash()])
	for p in players:
		var r: Dictionary = p["res"]
		parts.append("%d:%d,%d,%d,%d" % [p["id"], r["wood"], r["food"], r["gold"], r["stone"]])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(parts).to_utf8_buffer())
	return ctx.finish().hex_encode()


func queue_command(pid: int, type: String, payload: Dictionary) -> void:
	var t := world.tick + INPUT_DELAY
	if not _pending.has(t):
		_pending[t] = []
	_pending[t].append({"pid": pid, "seq": _seq, "type": type, "payload": payload})
	_seq += 1


func step() -> void:
	world.tick += 1
	var cmds: Array = _pending.get(world.tick, [])
	_pending.erase(world.tick)
	cmds.sort_custom(func(a, b): return a["pid"] < b["pid"] or (a["pid"] == b["pid"] and a["seq"] < b["seq"]))
	for c in cmds:
		_apply(c)
	MoveSystem.step(world)
	GatherSystem.step(self)


## Desplazamientos (milésimas) para repartir un grupo: casillas en espiral
## ordenadas por (distancia², y, x). El primero es (0,0).
static func spread_offsets(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := 0
	while out.size() < n:
		var ring: Array = []
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(y)) == r:
					ring.append([x * x + y * y, y, x])
		ring.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
		for k in ring:
			if out.size() < n:
				out.append(Vector2i(k[2], k[1]) * FP.SCALE)
		r += 1
	return out


func _apply(c: Dictionary) -> void:
	if not (c["payload"] is Dictionary):
		return
	match str(c["type"]):
		"move":
			_cmd_move(int(c["pid"]), c["payload"])
		"gather":
			_cmd_gather(int(c["pid"]), c["payload"])


## Número utilizable de un payload (puede venir de JSON: floats, basura).
static func _num_ok(x: Variant) -> bool:
	if typeof(x) == TYPE_INT:
		return true
	return typeof(x) == TYPE_FLOAT and is_finite(x) and absf(x) < 1.0e9


## Ids válidos de un payload: numéricos, existentes, propios, con la habilidad.
func _own_ids(pid: int, raw_ids: Variant, ability: String) -> Array[int]:
	var ids: Array[int] = []
	if not (raw_ids is Array):
		return ids
	for raw in raw_ids:
		if not _num_ok(raw):
			continue
		var id := int(raw)
		if ids.has(id) or not world.entities.has(id):
			continue
		if int(world.entities[id]["owner"]) != pid or not world.has_ability(id, ability):
			continue
		ids.append(id)
	ids.sort()
	return ids


func _cmd_move(pid: int, payload: Dictionary) -> void:
	var pos: Variant = payload.get("pos")
	if not (pos is Array) or pos.size() != 2 or not _num_ok(pos[0]) or not _num_ok(pos[1]):
		return
	var target := Vector2i(int(pos[0]), int(pos[1]))
	var ids := _own_ids(pid, payload.get("ids"), "Move")
	var offs := spread_offsets(ids.size())
	var lo := Vector2i(0, 0)
	var hi := Vector2i(grid.width * FP.SCALE - 1, grid.height * FP.SCALE - 1)
	for i in ids.size():
		GatherSystem.stop(self, ids[i])
		MoveSystem.order_move(world, grid, ids[i], (target + offs[i]).clamp(lo, hi))


func _cmd_gather(pid: int, payload: Dictionary) -> void:
	var raw_t: Variant = payload.get("target")
	if not _num_ok(raw_t):
		return
	var target := int(raw_t)
	if not world.has_ability(target, "ResourceSource"):
		return
	for id in _own_ids(pid, payload.get("ids"), "Gather"):
		GatherSystem.order_gather(self, id, target)

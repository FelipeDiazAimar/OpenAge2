extends RefCounted
## Simulación de una partida: jugadores, spawn, cola de comandos con retardo
## de entrada y tick determinista. El render solo lee `world`.

const World := preload("res://engine/sim/World.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const FP := preload("res://engine/sim/FixedPoint.gd")
const PlayerDefs := preload("res://engine/data/PlayerDefs.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")

const INPUT_DELAY := 2

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
	players.append({"id": pid, "civ": civ, "team": team, "defs": PlayerDefs.new(registry.defs, civ)})


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
	return world.spawn(def, owner, Grid.center_of(tile))


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


## Número utilizable de un payload (puede venir de JSON: floats, basura).
static func _num_ok(x: Variant) -> bool:
	if typeof(x) == TYPE_INT:
		return true
	return typeof(x) == TYPE_FLOAT and is_finite(x) and absf(x) < 1.0e9


func _cmd_move(pid: int, payload: Dictionary) -> void:
	var pos: Variant = payload.get("pos")
	var raw_ids: Variant = payload.get("ids")
	if not (pos is Array) or pos.size() != 2 or not _num_ok(pos[0]) or not _num_ok(pos[1]):
		return
	if not (raw_ids is Array):
		return
	var target := Vector2i(int(pos[0]), int(pos[1]))
	var ids: Array[int] = []
	for raw in raw_ids:
		if not _num_ok(raw):
			continue
		var id := int(raw)
		if ids.has(id) or not world.entities.has(id):
			continue
		if int(world.entities[id]["owner"]) != pid or not world.has_ability(id, "Move"):
			continue
		ids.append(id)
	ids.sort()
	var offs := spread_offsets(ids.size())
	var lo := Vector2i(0, 0)
	var hi := Vector2i(grid.width * FP.SCALE - 1, grid.height * FP.SCALE - 1)
	for i in ids.size():
		var dest := (target + offs[i]).clamp(lo, hi)
		MoveSystem.order_move(world, grid, ids[i], dest)

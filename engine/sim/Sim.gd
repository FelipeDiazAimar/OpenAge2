extends RefCounted
## Simulación de una partida: jugadores, spawn, cola de comandos con retardo
## de entrada y tick determinista. El render solo lee `world`.

const World := preload("res://engine/sim/World.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const FP := preload("res://engine/sim/FixedPoint.gd")
const PlayerDefs := preload("res://engine/data/PlayerDefs.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")
const GatherSystem := preload("res://engine/sim/systems/GatherSystem.gd")
const CombatSystem := preload("res://engine/sim/systems/CombatSystem.gd")
const HerdSystem := preload("res://engine/sim/systems/HerdSystem.gd")
const SeparationSystem := preload("res://engine/sim/systems/SeparationSystem.gd")
const BuildSystem := preload("res://engine/sim/systems/BuildSystem.gd")

const INPUT_DELAY := 2
const START_RES := {"wood": 200, "food": 200, "gold": 100, "stone": 200}
const POP_MAX := 200

var registry
var world := World.new()
var grid
var players: Array[Dictionary] = []
var _pending: Dictionary = {}
var _seq := 0
## Proyectiles en vuelo: {id, owner, target, from, pos, to, speed, damage, area, age, total}.
var projectiles: Array = []
## Eventos para el render ({"type": "death", ...}); se consumen con drain_events().
var events: Array = []
## Solo partidas locales: habilita el comando debug_spawn (tropas de prueba).
var debug_enabled := false
var _next_projectile := 1


func _init(p_registry, map_w: int, map_h: int) -> void:
	registry = p_registry
	grid = Grid.new(map_w, map_h)


func add_player(pid: int, civ: String, team: int) -> void:
	var res := {}
	for k in START_RES:
		res[k] = int(START_RES[k]) * FP.SCALE
	# age: índice de la edad actual; pending: techs/edades encoladas (no se repiten).
	players.append({"id": pid, "civ": civ, "team": team, "defs": PlayerDefs.new(registry.defs, civ), "res": res,
		"age": 0, "pending": {}})


func age_of(pid: int) -> int:
	return int(players[pid]["age"])


func researched(pid: int) -> Array[String]:
	return players[pid]["defs"].researched


## Coste de datos ({recurso: número}) en milésimas.
static func cost_milli(cost: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = cost.keys()
	keys.sort()
	for k in keys:
		out[str(k)] = FP.from_data(float(cost[k]))
	return out


func can_afford(pid: int, cost: Dictionary) -> bool:
	var r: Dictionary = players[pid]["res"]
	var c := cost_milli(cost)
	for k in c:
		if int(r.get(k, 0)) < int(c[k]):
			return false
	return true


func pay(pid: int, cost: Dictionary) -> void:
	var c := cost_milli(cost)
	for k in c:
		add_res(pid, k, -int(c[k]))


func refund(pid: int, cost: Dictionary) -> void:
	var c := cost_milli(cost)
	for k in c:
		add_res(pid, k, int(c[k]))


## "" si el jugador puede usar def (unidad, edificio, tech); si no, el motivo.
func requirements_met(pid: int, def: Dictionary) -> String:
	var d = players[pid]["defs"]
	var id := str(def.get("id", ""))
	if not d.is_available(id):
		return "no disponible para esta civilización"
	var req: Dictionary = def.get("requires", {})
	if req.has("age"):
		var a: Dictionary = registry.get_def(str(req["age"]))
		if int(a.get("index", 0)) > age_of(pid):
			return "requiere %s" % str(a.get("name", req["age"]))
	for t in req.get("techs", []):
		if not d.researched.has(str(t)):
			return "requiere %s" % str(registry.get_def(str(t)).get("name", t))
	return ""


func footprint_of(def: Dictionary) -> Vector2i:
	return Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))


## "" si pid puede colocar un cimiento de def_id con esquina en tile.
func can_place(pid: int, def_id: String, tile: Vector2i) -> String:
	if pid < 0 or pid >= players.size():
		return "jugador inválido"
	var def: Dictionary = players[pid]["defs"].get_def(def_id)
	if def.is_empty() or str(def.get("type", "")) != "building" or bool(def.get("abstract", false)):
		return "no es un edificio"
	var req := requirements_met(pid, def)
	if req != "":
		return req
	if not can_afford(pid, def.get("cost", {})):
		return "recursos insuficientes"
	var size := footprint_of(def)
	for y in size.y:
		for x in size.x:
			if not grid.is_walkable(tile + Vector2i(x, y)):
				return "lugar ocupado"
	for id in _ids_in_rect(tile, size):
		if world.has_ability(id, "ResourceSource") and not world.has_ability(id, "Move"):
			return "lugar ocupado" # carcasas
	return ""


## Entidades cuya casilla cae dentro del rectángulo (orden por id).
func _ids_in_rect(tile: Vector2i, size: Vector2i) -> Array[int]:
	var out: Array[int] = []
	var center := tile * FP.SCALE + size * (FP.SCALE / 2)
	for id in world.spatial.query_radius(center, maxi(size.x, size.y) * FP.SCALE):
		var t := Grid.tile_of(world.entities[id]["pos"])
		if t.x >= tile.x and t.y >= tile.y and t.x < tile.x + size.x and t.y < tile.y + size.y:
			out.append(id)
	return out


## Edificio terminado (no es cimiento).
func is_built(id: int) -> bool:
	return world.entities.has(id) and not world.has_ability(id, "Foundation")


## Cimiento: el edificio con Foundation y 1 HP; no funciona hasta terminarlo.
## Las unidades dentro de la huella salen a la casilla libre más cercana.
func place_foundation(pid: int, def_id: String, tile: Vector2i) -> int:
	var def: Dictionary = players[pid]["defs"].get_def(def_id)
	var size := footprint_of(def)
	var inside := _ids_in_rect(tile, size)
	var id := spawn(def_id, pid, tile)
	if id < 0:
		return -1
	var total := int(round(float(def["build_time"]) * World.TICK_RATE)) * 3
	world.add_component(id, "Foundation", {"params": {}, "progress": 0, "total": maxi(3, total)})
	var hp: Dictionary = world.comp(id, "Hitpoints")
	if not hp.is_empty():
		hp["hp"] = 1
	for u in inside:
		if world.has_ability(u, "Move"):
			_eject(u, tile, size)
	return id


func _eject(id: int, tile: Vector2i, size: Vector2i) -> void:
	var from := Grid.tile_of(world.entities[id]["pos"])
	for off in spread_offsets(400):
		var t: Vector2i = from + off / FP.SCALE
		var inside := t.x >= tile.x and t.y >= tile.y and t.x < tile.x + size.x and t.y < tile.y + size.y
		if not inside and grid.is_walkable(t):
			world.set_pos(id, Grid.center_of(t))
			var m: Dictionary = world.comp(id, "Move")
			(m["waypoints"] as Array).clear()
			m["moving"] = false
			return


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
	if _blocks_tile(def):
		grid.set_blocked(tile, true)
	return world.spawn(def, owner, Grid.center_of(tile))


## Recursos fijos (árboles, minas, bayas) bloquean su casilla; los animales
## (tienen Move en la definición) no, ni vivos ni como carcasa.
static func _blocks_tile(def: Dictionary) -> bool:
	return str(def.get("type", "")) == "resource" and not (def.get("abilities", {}) as Dictionary).has("Move")


func next_projectile_id() -> int:
	_next_projectile += 1
	return _next_projectile - 1


func team_of(pid: int) -> int:
	if pid < 0 or pid >= players.size():
		return -1
	return int(players[pid]["team"])


## Dueños jugadores distintos y de equipos distintos (gaia -1 nunca es enemigo).
func is_enemy(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and a != b and team_of(a) != team_of(b)


## Muerte: evento para el render (cadáver) y eliminación de la entidad. Los
## animales (ResourceSource con requires_kill) quedan como carcasa recolectable.
func kill(id: int) -> void:
	if not world.entities.has(id):
		return
	var e: Dictionary = world.entities[id]
	var facing := Vector2i(1000, 1000)
	if world.has_ability(id, "Move"):
		facing = world.comp(id, "Move")["facing"]
	var src: Dictionary = world.comp(id, "ResourceSource")
	if not src.is_empty() and bool(src["params"].get("requires_kill", false)):
		for ability in ["Hitpoints", "Attack", "Armor", "Move"]:
			world.remove_component(id, ability)
		src["killed"] = true
		events.append({"type": "carcass", "id": id, "def_id": e["def_id"], "pos": e["pos"], "facing": facing})
		return
	events.append({"type": "death", "id": id, "def_id": e["def_id"], "owner": e["owner"], "pos": e["pos"], "facing": facing, "kind": e["type"]})
	remove(id)


func drain_events() -> Array:
	var out := events
	events = []
	return out


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
			if _blocks_tile(def_for(id)):
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
	# Solo unidades (tienen Move) y proveedores de población: no recorre los
	# miles de árboles y minas del mapa.
	var used := 0
	var cap := 0
	for id in world.ids_with("Move"):
		var e: Dictionary = world.entities[id]
		if int(e["owner"]) == pid and str(e["type"]) == "unit":
			used += int(def_for(id).get("pop_cost", 0))
	for id in world.ids_with("ProvidesPop"):
		if int(world.entities[id]["owner"]) == pid and is_built(id):
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
	for p in projectiles:
		parts.append("P%d:%d,%d,%d" % [p["id"], p["pos"].x, p["pos"].y, p["target"]])
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
	SeparationSystem.step(self)
	CombatSystem.step(self)
	GatherSystem.step(self)
	BuildSystem.step(self)
	HerdSystem.step(self)


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
		"attack":
			_cmd_attack(int(c["pid"]), c["payload"])
		"stop":
			_cmd_stop(int(c["pid"]), c["payload"])
		"place":
			_cmd_place(int(c["pid"]), c["payload"])
		"build":
			_cmd_build(int(c["pid"]), c["payload"])
		"debug_spawn":
			_cmd_debug_spawn(c["payload"])


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
		CombatSystem.stop(self, ids[i])
		BuildSystem.stop(self, ids[i])
		MoveSystem.order_move(world, grid, ids[i], (target + offs[i]).clamp(lo, hi))


func _cmd_gather(pid: int, payload: Dictionary) -> void:
	var raw_t: Variant = payload.get("target")
	if not _num_ok(raw_t):
		return
	var target := int(raw_t)
	if not world.has_ability(target, "ResourceSource"):
		return
	for id in _own_ids(pid, payload.get("ids"), "Gather"):
		CombatSystem.stop(self, id)
		GatherSystem.order_gather(self, id, target)


func _cmd_attack(pid: int, payload: Dictionary) -> void:
	var raw_t: Variant = payload.get("target")
	if not _num_ok(raw_t):
		return
	var t := int(raw_t)
	if not world.entities.has(t) or not world.has_ability(t, "Hitpoints"):
		return
	if not is_enemy(pid, int(world.entities[t]["owner"])):
		return
	for id in _own_ids(pid, payload.get("ids"), "Attack"):
		GatherSystem.stop(self, id)
		BuildSystem.stop(self, id)
		CombatSystem.order_attack(self, id, t)


func _cmd_stop(pid: int, payload: Dictionary) -> void:
	for id in _own_ids(pid, payload.get("ids"), "Move"):
		GatherSystem.stop(self, id)
		CombatSystem.stop(self, id)
		BuildSystem.stop(self, id)
		var m: Dictionary = world.comp(id, "Move")
		(m["waypoints"] as Array).clear()
		m["moving"] = false


func _cmd_place(pid: int, payload: Dictionary) -> void:
	var t: Variant = payload.get("tile")
	if not (t is Array) or t.size() != 2 or not _num_ok(t[0]) or not _num_ok(t[1]):
		return
	var def_id := str(payload.get("def", ""))
	var tile := Vector2i(int(t[0]), int(t[1]))
	if can_place(pid, def_id, tile) != "":
		return
	pay(pid, players[pid]["defs"].get_def(def_id).get("cost", {}))
	var f := place_foundation(pid, def_id, tile)
	for id in _own_ids(pid, payload.get("ids"), "Build"):
		BuildSystem.order_build(self, id, f)


func _cmd_build(pid: int, payload: Dictionary) -> void:
	var raw_t: Variant = payload.get("target")
	if not _num_ok(raw_t):
		return
	var t := int(raw_t)
	if not world.has_ability(t, "Foundation") or int(world.entities[t]["owner"]) != pid:
		return
	for id in _own_ids(pid, payload.get("ids"), "Build"):
		BuildSystem.order_build(self, id, t)


## Tropas de prueba (solo con debug_enabled): n unidades cerca de pos.
func _cmd_debug_spawn(payload: Dictionary) -> void:
	if not debug_enabled:
		return
	var pos: Variant = payload.get("pos")
	if not (pos is Array) or pos.size() != 2 or not _num_ok(pos[0]) or not _num_ok(pos[1]):
		return
	if not _num_ok(payload.get("n")) or not _num_ok(payload.get("owner")):
		return
	var owner := int(payload["owner"])
	if owner < 0 or owner >= players.size():
		return
	var center := Grid.tile_of(Vector2i(int(pos[0]), int(pos[1])))
	var want := clampi(int(payload["n"]), 0, 40)
	var placed := 0
	for off in spread_offsets(128):
		if placed >= want:
			break
		var tile: Vector2i = center + off / FP.SCALE
		if grid.is_walkable(tile) and spawn(str(payload.get("def", "")), owner, tile) >= 0:
			placed += 1

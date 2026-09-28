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
const ProductionSystem := preload("res://engine/sim/systems/ProductionSystem.gd")

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
	# age: índice de la edad actual.
	players.append({"id": pid, "civ": civ, "team": team, "defs": PlayerDefs.new(registry.defs, civ), "res": res,
		"age": 0})


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
	for f in world.ids_with("Farm"):
		# Las granjas no bloquean la grilla: se comprueba su huella aparte.
		var fs := footprint_of(def_for(f))
		var fo := Grid.tile_of(world.entities[f]["pos"] - fs * (FP.SCALE / 2))
		if fo.x < tile.x + size.x and tile.x < fo.x + fs.x and fo.y < tile.y + size.y and tile.y < fo.y + fs.y:
			return "lugar ocupado"
	for id in _ids_in_rect(tile, size):
		if world.has_ability(id, "ResourceSource") and not world.has_ability(id, "Move"):
			return "lugar ocupado" # carcasas
		var o := int(world.entities[id]["owner"])
		if o >= 0 and o != pid:
			return "hay unidades de otro jugador" # (AoE2) no se las aparta
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


## Granja: su comida es un ResourceSource de tiempo de ejecución.
func _add_farm_food(id: int) -> void:
	var farm: Dictionary = world.comp(id, "Farm")["params"]
	var params := {"resource": "food", "amount": farm["food"], "rate_key": farm["rate_key"]}
	world.add_component(id, "ResourceSource", {"params": params, "amount": FP.from_data(float(farm["food"])), "killed": false})


## Obra terminada (BuildSystem): las granjas empiezan a dar comida.
func on_built(id: int) -> void:
	if world.has_ability(id, "Farm") and not world.has_ability(id, "ResourceSource"):
		_add_farm_food(id)


## Granja agotada: se resiembra sola si el dueño tiene la madera (DE); si no,
## desaparece. true si se resembró.
func reseed_farm(id: int) -> bool:
	var owner := int(world.entities[id]["owner"])
	var cost: Dictionary = def_for(id).get("cost", {})
	if owner < 0 or not can_afford(owner, cost):
		return false
	pay(owner, cost)
	var src: Dictionary = world.comp(id, "ResourceSource")
	src["amount"] = FP.from_data(float(world.comp(id, "Farm")["params"]["food"]))
	events.append({"type": "reseed", "id": id, "owner": owner})
	return true


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
	if world.has_ability(id, "Farm"):
		world.remove_component(id, "ResourceSource") # da comida al terminarla
		return id
	for u in inside:
		if world.has_ability(u, "Move"):
			_eject(u, tile, size)
	return id


func _eject(id: int, tile: Vector2i, size: Vector2i) -> void:
	var t := exit_tile(tile, size, Grid.tile_of(world.entities[id]["pos"]))
	if t.x < 0:
		return
	world.set_pos(id, Grid.center_of(t))
	var m: Dictionary = world.comp(id, "Move")
	(m["waypoints"] as Array).clear()
	m["moving"] = false


## Casilla libre alrededor de una huella, la más cercana a goal (desempate
## y, x), dentro de la zona conectada con más casillas libres alrededor: así
## nadie aparece en un hueco cerrado. (-1, -1) si no hay ninguna.
func exit_tile(origin: Vector2i, size: Vector2i, goal: Vector2i) -> Vector2i:
	var cands: Array[Vector2i] = []
	var count := {}
	for r in range(1, 10):
		for y in range(origin.y - r, origin.y + size.y + r):
			for x in range(origin.x - r, origin.x + size.x + r):
				var inner := x > origin.x - r and x < origin.x + size.x + r - 1 and y > origin.y - r and y < origin.y + size.y + r - 1
				var t := Vector2i(x, y)
				if inner or not grid.is_walkable(t):
					continue
				cands.append(t)
				var rg: int = grid.region_of(t)
				count[rg] = int(count.get(rg, 0)) + 1
		if r >= 3 and not cands.is_empty():
			break
	if cands.is_empty():
		return Vector2i(-1, -1)
	var region := -1
	var keys: Array = count.keys()
	keys.sort()
	for rg in keys:
		if region < 0 or int(count[rg]) > int(count[region]):
			region = rg
	var best := Vector2i(-1, -1)
	var best_key := 0
	for t in cands:
		if grid.region_of(t) != region:
			continue
		var d := t - goal
		var key: int = (d.x * d.x + d.y * d.y) * 16777216 + t.y * 4096 + t.x
		if best.x < 0 or key < best_key:
			best = t
			best_key = key
	return best


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
		var ab: Dictionary = def.get("abilities", {})
		if not ab.has("Farm"):
			grid.block_rect(tile, size) # las granjas se pisan
		var b := world.spawn(def, owner, tile * FP.SCALE + size * (FP.SCALE / 2))
		if ab.has("Farm"):
			_add_farm_food(b)
		if ab.has("Train") or ab.has("Research") or ab.has("AgeAdvance"):
			world.add_component(b, "Queue", ProductionSystem.new_queue())
		return b
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
			if not world.has_ability(id, "Farm"):
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
		parts.append("%d:%d,%d,%d,%d|a%d|%s" % [p["id"], r["wood"], r["food"], r["gold"], r["stone"], p["age"], ",".join(p["defs"].researched)])
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
	ProductionSystem.step(self)
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
		"repair":
			_cmd_repair(int(c["pid"]), c["payload"])
		"train":
			_cmd_train(int(c["pid"]), c["payload"])
		"research":
			_cmd_research(int(c["pid"]), c["payload"])
		"age_up":
			_cmd_age_up(int(c["pid"]), c["payload"])
		"cancel":
			_cmd_cancel(int(c["pid"]), c["payload"])
		"rally":
			_cmd_rally(int(c["pid"]), c["payload"])
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
	var builders := _own_ids(pid, payload.get("ids"), "Build")
	if builders.is_empty() or can_place(pid, def_id, tile) != "":
		return # sin aldeano propio no se coloca nada
	pay(pid, players[pid]["defs"].get_def(def_id).get("cost", {}))
	var f := place_foundation(pid, def_id, tile)
	for id in builders:
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


func _cmd_repair(pid: int, payload: Dictionary) -> void:
	var raw_t: Variant = payload.get("target")
	if not _num_ok(raw_t):
		return
	for id in _own_ids(pid, payload.get("ids"), "Repair"):
		BuildSystem.order_repair(self, id, int(raw_t))


## Edificio propio, terminado y con cola; si no, -1.
func _own_queue(pid: int, raw: Variant) -> int:
	if not _num_ok(raw):
		return -1
	var b := int(raw)
	if not world.has_ability(b, "Queue") or int(world.entities[b]["owner"]) != pid or not is_built(b):
		return -1
	return b


func _enqueue(pid: int, b: int, kind: String, id: String, cost: Dictionary, seconds: Variant) -> void:
	pay(pid, cost)
	# Copia del coste: el reembolso devuelve lo pagado aunque luego se parchee.
	(world.comp(b, "Queue")["items"] as Array).append({"kind": kind, "id": id, "cost": cost.duplicate(true), "total": ProductionSystem.ticks_of(seconds)})


## Tech o edad en alguna cola del jugador. Se deriva de las colas vivas: si el
## edificio cae, deja de estar "en curso".
func is_pending(pid: int, id: String) -> bool:
	for b in world.ids_with("Queue"):
		if int(world.entities[b]["owner"]) != pid:
			continue
		for it in world.comp(b, "Queue")["items"]:
			if str(it["id"]) == id and str(it["kind"]) != "unit":
				return true
	return false


func _cmd_train(pid: int, payload: Dictionary) -> void:
	var b := _own_queue(pid, payload.get("id"))
	var def_id := str(payload.get("def", ""))
	if b < 0 or train_error(pid, b, def_id) != "":
		return
	var def: Dictionary = players[pid]["defs"].get_def(def_id)
	_enqueue(pid, b, "unit", def_id, def.get("cost", {}), def["train_time"])


func _cmd_research(pid: int, payload: Dictionary) -> void:
	var b := _own_queue(pid, payload.get("id"))
	var tech := str(payload.get("tech", ""))
	if b < 0 or research_error(pid, b, tech) != "":
		return
	var def: Dictionary = players[pid]["defs"].get_def(tech)
	_enqueue(pid, b, "tech", tech, def.get("cost", {}), def["research_time"])


func _cmd_age_up(pid: int, payload: Dictionary) -> void:
	var b := _own_queue(pid, payload.get("id"))
	if b < 0 or age_error(pid, b) != "":
		return
	var def := next_age(pid)
	_enqueue(pid, b, "age", str(def["id"]), def.get("cost", {}), def["research_time"])


func _cmd_cancel(pid: int, payload: Dictionary) -> void:
	var b := _own_queue(pid, payload.get("id"))
	if b < 0 or not _num_ok(payload.get("index")):
		return
	var q: Dictionary = world.comp(b, "Queue")
	var items: Array = q["items"]
	var i := int(payload["index"])
	if i < 0 or i >= items.size():
		return
	var it: Dictionary = items[i]
	items.remove_at(i)
	if i == 0:
		q["progress"] = 0
	refund(pid, it["cost"])


func _cmd_rally(pid: int, payload: Dictionary) -> void:
	var pos: Variant = payload.get("pos")
	if not (pos is Array) or pos.size() != 2 or not _num_ok(pos[0]) or not _num_ok(pos[1]):
		return
	var hi := Vector2i(grid.width * FP.SCALE - 1, grid.height * FP.SCALE - 1)
	var p := Vector2i(int(pos[0]), int(pos[1])).clamp(Vector2i.ZERO, hi)
	var t := -1
	if _num_ok(payload.get("target")) and world.entities.has(int(payload["target"])):
		t = int(payload["target"])
	for b in _own_ids(pid, payload.get("ids"), "Queue"):
		var q: Dictionary = world.comp(b, "Queue")
		q["rally"] = p
		q["rally_target"] = t


## "" si el edificio b de pid puede entrenar def_id ahora; si no, el motivo.
func train_error(pid: int, b: int, def_id: String) -> String:
	var tr: Dictionary = world.comp(b, "Train")
	var d = players[pid]["defs"]
	if tr.is_empty() or not trainable_units(pid, b).has(def_id) and not (tr["params"]["units"] as Array).has(def_id):
		return "este edificio no la entrena"
	var def: Dictionary = d.get_def(def_id)
	if def.is_empty() or str(def.get("type", "")) != "unit":
		return "no es una unidad"
	var cur: String = d.resolve_unit(def_id)
	if cur != def_id:
		return "mejorada a %s" % str(d.get_def(cur).get("name", cur))
	if is_upgrade_target(def_id) and not d.upgrades.values().has(def_id):
		return "requiere mejora"
	return _queue_error(pid, b, def)


func research_error(pid: int, b: int, tech: String) -> String:
	var rs: Dictionary = world.comp(b, "Research")
	if rs.is_empty() or not (rs["params"]["techs"] as Array).has(tech):
		return "aquí no se investiga"
	var def: Dictionary = players[pid]["defs"].get_def(tech)
	if def.is_empty() or str(def.get("type", "")) != "tech":
		return "no es una tecnología"
	if researched(pid).has(tech) or is_pending(pid, tech):
		return "ya investigada o en curso"
	return _queue_error(pid, b, def)


## Unidades que entrena el edificio para pid: cada una de su lista en su
## versión mejorada actual (lancero -> piquero), sin repetir.
func trainable_units(pid: int, b: int) -> Array[String]:
	var out: Array[String] = []
	var tr: Dictionary = world.comp(b, "Train")
	if tr.is_empty():
		return out
	var d = players[pid]["defs"]
	for u in tr["params"]["units"]:
		var cur: String = d.resolve_unit(str(u))
		if not out.has(cur):
			out.append(cur)
	return out


## Siguiente edad del jugador ({} si ya está en la última).
func next_age(pid: int) -> Dictionary:
	for id in registry.ids_of_type("age"):
		var a: Dictionary = registry.get_def(id)
		if int(a.get("index", -1)) == age_of(pid) + 1:
			return a
	return {}


func age_error(pid: int, b: int) -> String:
	if not world.has_ability(b, "AgeAdvance"):
		return "aquí no se avanza de edad"
	var a := next_age(pid)
	if a.is_empty():
		return "última edad"
	if is_pending(pid, str(a["id"])):
		return "ya en curso"
	var pre: Dictionary = a.get("prerequisite_buildings", {})
	if not pre.is_empty():
		var kinds := {}
		var any_of: Array = pre.get("any_of", [])
		for id in world.ids_with("Hitpoints"):
			var e: Dictionary = world.entities[id]
			if int(e["owner"]) == pid and str(e["type"]) == "building" and any_of.has(e["def_id"]) and is_built(id):
				kinds[e["def_id"]] = true
		if kinds.size() < int(pre.get("count", 1)):
			return "requiere %d edificios de la edad actual" % int(pre.get("count", 1))
	return _queue_error(pid, b, a)


func _queue_error(pid: int, b: int, def: Dictionary) -> String:
	if not is_built(b):
		return "en construcción"
	if str(def.get("type", "")) != "age":
		var req := requirements_met(pid, def)
		if req != "":
			return req
	if (world.comp(b, "Queue")["items"] as Array).size() >= ProductionSystem.capacity(self, b):
		return "cola llena"
	if not can_afford(pid, def.get("cost", {})):
		return "recursos insuficientes"
	return ""


## Tecnología terminada: parchea la vista del jugador (las entidades vivas
## leen de ella) y refresca los valores que se guardan precalculados.
func complete_research(pid: int, tech: String) -> void:
	var d = players[pid]["defs"]
	d.research(tech)
	for e in d.get_def(tech).get("effects", []):
		if str(e.get("op", "")) == "replace_entity":
			_convert_line(pid, str(e["from"]))
	refresh_caches(pid)
	events.append({"type": "researched", "owner": pid, "id": tech})


func complete_age(pid: int, age_id: String) -> void:
	var a: Dictionary = registry.get_def(age_id)
	players[pid]["age"] = maxi(age_of(pid), int(a.get("index", 0)))
	events.append({"type": "age", "owner": pid, "id": age_id})


## Mejora de línea: las unidades vivas de `from` pasan a su versión actual.
func _convert_line(pid: int, from: String) -> void:
	var d = players[pid]["defs"]
	var to: String = d.resolve_unit(from)
	if to == from or d.get_def(to).is_empty():
		return
	for id in world.ids_with("Hitpoints"):
		var e: Dictionary = world.entities[id]
		if int(e["owner"]) == pid and str(e["def_id"]) == from:
			world.convert_entity(id, d.get_def(to))
	events.append({"type": "upgraded", "owner": pid, "from": from, "to": to})


var _upgrade_targets: Dictionary = {}
var _upgrade_targets_ready := false


## Unidades a las que solo se llega por una mejora (piquero, alabardero...).
func is_upgrade_target(def_id: String) -> bool:
	if not _upgrade_targets_ready:
		_upgrade_targets_ready = true
		for id in registry.ids_of_type("tech"):
			for e in registry.get_def(id).get("effects", []):
				if str(e.get("op", "")) == "replace_entity":
					_upgrade_targets[str(e["to"])] = true
	return _upgrade_targets.has(def_id)


func refresh_caches(pid: int) -> void:
	for id in world.ids_with("Move"):
		if int(world.entities[id]["owner"]) != pid:
			continue
		var m: Dictionary = world.comp(id, "Move")
		m["step"] = FP.from_data(float(m["params"]["speed"])) / World.TICK_RATE
	for id in world.ids_with("Hitpoints"):
		if int(world.entities[id]["owner"]) != pid:
			continue
		var hp: Dictionary = world.comp(id, "Hitpoints")
		var mx := int(round(float(hp["params"]["max"])))
		if mx != int(hp["max"]):
			hp["hp"] = maxi(1, int(hp["hp"]) + mx - int(hp["max"]))
			hp["max"] = mx


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

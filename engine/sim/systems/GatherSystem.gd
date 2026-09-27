extends RefCounted
## Recolección estilo AoE2: ir al recurso, recolectar a la tasa de la unidad,
## llevar la carga al depósito propio más cercano que acepte ese recurso y
## volver. Recurso agotado -> se elimina y el aldeano busca uno igual cerca.
## Estados: idle, to_resource, gathering, to_drop.

const FP := preload("res://engine/sim/FixedPoint.gd")
const World := preload("res://engine/sim/World.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")

const REACH := 1500
const DROP_REACH := 800
const RETARGET_R := 10000


static func order_gather(sim, id: int, target: int) -> void:
	var w = sim.world
	var g: Dictionary = w.comp(id, "Gather")
	var src: Dictionary = w.comp(target, "ResourceSource")
	if g.is_empty() or src.is_empty():
		return
	var kind := str(src["params"]["rate_key"])
	if not (g["params"]["rates"] as Dictionary).has(kind):
		return
	var res := str(src["params"]["resource"])
	if int(g["carry"]) > 0 and str(g["carry_res"]) != res:
		g["carry"] = 0
	g["carry_res"] = res
	g["target"] = target
	g["kind"] = kind
	var tpos: Vector2i = w.entities[target]["pos"]
	if FP.dist(w.entities[id]["pos"], tpos) <= REACH:
		_start_gathering(w, id, g, tpos)
	else:
		g["state"] = "to_resource"
		MoveSystem.order_move(w, sim.grid, id, tpos)


static func stop(sim, id: int) -> void:
	var g: Dictionary = sim.world.comp(id, "Gather")
	if not g.is_empty():
		g["state"] = "idle"
		g["target"] = -1
		g["dropsite"] = -1


## Recurso de la tarea actual ("" si está ociosa).
static func task_resource(sim, id: int) -> String:
	var g: Dictionary = sim.world.comp(id, "Gather")
	if g.is_empty() or str(g["state"]) == "idle":
		return ""
	return str(g["carry_res"])


static func step(sim) -> void:
	var w = sim.world
	for id in w.ids_with("Gather"):
		var g: Dictionary = w.comp(id, "Gather")
		match str(g["state"]):
			"to_resource":
				_to_resource(sim, id, g)
			"gathering":
				_gather_tick(sim, id, g)
			"to_drop":
				_to_drop(sim, id, g)


static func _to_resource(sim, id: int, g: Dictionary) -> void:
	var w = sim.world
	if not w.entities.has(int(g["target"])):
		_retarget(sim, id, g)
		return
	if bool(w.comp(id, "Move").get("moving", false)):
		return
	var tpos: Vector2i = w.entities[int(g["target"])]["pos"]
	if FP.dist(w.entities[id]["pos"], tpos) <= REACH:
		_start_gathering(w, id, g, tpos)
	else:
		g["state"] = "idle"


static func _start_gathering(w, id: int, g: Dictionary, tpos: Vector2i) -> void:
	g["state"] = "gathering"
	var m: Dictionary = w.comp(id, "Move")
	if m.is_empty():
		return
	(m["waypoints"] as Array).clear()
	m["moving"] = false
	var d: Vector2i = tpos - w.entities[id]["pos"]
	if d != Vector2i.ZERO:
		m["facing"] = d


static func _gather_tick(sim, id: int, g: Dictionary) -> void:
	var w = sim.world
	var t: int = g["target"]
	if not w.entities.has(t):
		_retarget(sim, id, g)
		return
	var src: Dictionary = w.comp(t, "ResourceSource")
	var cap := FP.from_data(float(g["params"]["capacity"]))
	var rate := FP.from_data(float(g["params"]["rates"][g["kind"]])) / World.TICK_RATE
	var infinite := bool(src["params"].get("infinite", false))
	var take := mini(rate, cap - int(g["carry"]))
	if not infinite:
		take = mini(take, int(src["amount"]))
	g["carry"] = int(g["carry"]) + take
	if not infinite:
		src["amount"] = int(src["amount"]) - take
		if int(src["amount"]) <= 0:
			sim.remove(t)
	if int(g["carry"]) >= cap:
		_go_drop(sim, id, g)
	elif not w.entities.has(t):
		_retarget(sim, id, g)


static func _go_drop(sim, id: int, g: Dictionary) -> void:
	var w = sim.world
	var pos: Vector2i = w.entities[id]["pos"]
	var d := _nearest_dropsite(sim, int(w.entities[id]["owner"]), str(g["carry_res"]), pos)
	if d < 0:
		g["state"] = "idle"
		return
	g["dropsite"] = d
	g["state"] = "to_drop"
	var r := _rect(sim, d)
	var lo: Vector2i = r[0]
	var hi: Vector2i = r[1]
	MoveSystem.order_move(w, sim.grid, id, Vector2i(clampi(pos.x, lo.x, hi.x - 1), clampi(pos.y, lo.y, hi.y - 1)))


static func _to_drop(sim, id: int, g: Dictionary) -> void:
	var w = sim.world
	var d: int = g["dropsite"]
	if not w.entities.has(d):
		_go_drop(sim, id, g)
		return
	if bool(w.comp(id, "Move").get("moving", false)):
		return
	if _rect_dist(w.entities[id]["pos"], _rect(sim, d)) > DROP_REACH:
		g["state"] = "idle"
		return
	sim.add_res(int(w.entities[id]["owner"]), str(g["carry_res"]), int(g["carry"]))
	g["carry"] = 0
	var t: int = g["target"]
	if w.entities.has(t):
		g["state"] = "to_resource"
		MoveSystem.order_move(w, sim.grid, id, w.entities[t]["pos"])
	else:
		_retarget(sim, id, g)


static func _retarget(sim, id: int, g: Dictionary) -> void:
	var w = sim.world
	var pos: Vector2i = w.entities[id]["pos"]
	var best := -1
	var best_d := 0
	for c in w.spatial.query_radius(pos, RETARGET_R):
		var src: Dictionary = w.comp(c, "ResourceSource")
		if src.is_empty() or str(src["params"]["rate_key"]) != str(g["kind"]):
			continue
		var dd := FP.dist(pos, w.entities[c]["pos"])
		if best < 0 or dd < best_d:
			best = c
			best_d = dd
	if best >= 0:
		order_gather(sim, id, best)
	elif int(g["carry"]) > 0:
		_go_drop(sim, id, g)
	else:
		g["state"] = "idle"
		g["target"] = -1


static func _nearest_dropsite(sim, owner: int, res: String, pos: Vector2i) -> int:
	var w = sim.world
	var best := -1
	var best_d := 0
	for d in w.ids_with("DropSite"):
		if int(w.entities[d]["owner"]) != owner:
			continue
		if not (w.comp(d, "DropSite")["params"]["accepts"] as Array).has(res):
			continue
		var dd := _rect_dist(pos, _rect(sim, d))
		if best < 0 or dd < best_d:
			best = d
			best_d = dd
	return best


## [esquina_min, esquina_max] del footprint (milésimas).
static func _rect(sim, id: int) -> Array:
	var def: Dictionary = sim.def_for(id)
	var size := Vector2i.ONE
	if def.get("footprint") is Array:
		size = Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
	var half := size * (FP.SCALE / 2)
	var c: Vector2i = sim.world.entities[id]["pos"]
	return [c - half, c + half]


static func _rect_dist(p: Vector2i, r: Array) -> int:
	var lo: Vector2i = r[0]
	var hi: Vector2i = r[1]
	var dx := maxi(maxi(lo.x - p.x, 0), p.x - hi.x)
	var dy := maxi(maxi(lo.y - p.y, 0), p.y - hi.y)
	return FP.length(dx, dy)

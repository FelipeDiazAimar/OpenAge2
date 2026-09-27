extends RefCounted
## Colas de producción estilo AoE2 (5 puestos compartidos por unidades,
## tecnologías y edades). El coste se cobra al encolar y cancelar lo devuelve.
## Una unidad no avanza si el jugador no tiene población libre ("sin casas").
## Al salir va al punto de reunión (o recolecta / construye si es aldeano).

const FP := preload("res://engine/sim/FixedPoint.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const World := preload("res://engine/sim/World.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")
const GatherSystem := preload("res://engine/sim/systems/GatherSystem.gd")
const BuildSystem := preload("res://engine/sim/systems/BuildSystem.gd")

const DEFAULT_QUEUE := 5
const NO_RALLY := Vector2i(-1, -1)


static func new_queue() -> Dictionary:
	return {"params": {}, "items": [], "progress": 0, "housed": false, "rally": NO_RALLY, "rally_target": -1}


static func capacity(sim, id: int) -> int:
	var t: Dictionary = sim.world.comp(id, "Train")
	if t.is_empty():
		return DEFAULT_QUEUE
	return int(t["params"].get("queue", DEFAULT_QUEUE))


static func ticks_of(seconds: Variant) -> int:
	return maxi(1, int(round(float(seconds) * World.TICK_RATE)))


static func step(sim) -> void:
	var w = sim.world
	var pops := {}
	for id in w.ids_with("Queue"):
		var q: Dictionary = w.comp(id, "Queue")
		var items: Array = q["items"]
		if items.is_empty():
			q["housed"] = false
			continue
		if w.has_ability(id, "Foundation"):
			continue
		var owner := int(w.entities[id]["owner"])
		var it: Dictionary = items[0]
		var pc := 0
		if str(it["kind"]) == "unit":
			pc = int(sim.players[owner]["defs"].get_def(str(it["id"])).get("pop_cost", 1))
			if not pops.has(owner):
				pops[owner] = sim.population(owner)
			var pop: Vector2i = pops[owner]
			if pop.x + pc > pop.y:
				q["housed"] = true
				continue
			q["housed"] = false
		q["progress"] = mini(int(q["progress"]) + 1, int(it["total"]))
		if int(q["progress"]) < int(it["total"]):
			continue
		match str(it["kind"]):
			"unit":
				# Sin casilla de salida (edificio rodeado) la unidad espera lista.
				if _release(sim, id, q, str(it["id"])) < 0:
					q["housed"] = true
					continue
				pops[owner] = pops[owner] + Vector2i(pc, 0)
			"tech":
				sim.complete_research(owner, str(it["id"]))
			"age":
				sim.complete_age(owner, str(it["id"]))
		items.pop_front()
		q["progress"] = 0


## Genera la unidad en la casilla libre junto al edificio más cercana al
## punto de reunión (o al frente) y le da la orden de reunión.
static func _release(sim, b: int, q: Dictionary, def_id: String) -> int:
	var w = sim.world
	var owner := int(w.entities[b]["owner"])
	var def: Dictionary = sim.def_for(b)
	var size := Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
	var origin := Grid.tile_of(w.entities[b]["pos"] - size * (FP.SCALE / 2))
	var rally: Vector2i = q["rally"]
	var goal := origin + Vector2i(size.x / 2, size.y)
	if rally != NO_RALLY:
		goal = Grid.tile_of(rally)
	var tile: Vector2i = sim.exit_tile(origin, size, goal)
	if tile.x < 0:
		return -1
	var unit_id: String = sim.players[owner]["defs"].resolve_unit(def_id)
	var u: int = sim.spawn(unit_id, owner, tile)
	if u < 0:
		return -1
	var t: int = q["rally_target"]
	if t >= 0 and w.entities.has(t):
		if w.has_ability(t, "ResourceSource") and w.has_ability(u, "Gather"):
			GatherSystem.order_gather(sim, u, t)
			return u
		if w.has_ability(t, "Foundation") and w.has_ability(u, "Build"):
			BuildSystem.order_build(sim, u, t)
			return u
	if rally != NO_RALLY and w.has_ability(u, "Move"):
		MoveSystem.order_move(w, sim.grid, u, rally)
	return u


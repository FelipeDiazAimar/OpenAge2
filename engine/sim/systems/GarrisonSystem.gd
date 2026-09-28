extends RefCounted
## Guarnición estilo AoE2: unidades con Garrisonable entran en edificios
## propios con Garrison (hasta `capacity`). Dentro quedan fuera del
## SpatialHash: no se mueven, no atacan ni pueden ser atacadas, pero cuentan
## población. Salen a casillas libres junto al edificio (o al morir este).
## La campana del centro urbano mete a los aldeanos y los vuelve a sacar.
##
## Estado en la unidad: componente de tiempo de ejecución
## Garrisoned {in, inside}; en el edificio: Garrison.units (ids ordenados).

const FP := preload("res://engine/sim/FixedPoint.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")
const GatherSystem := preload("res://engine/sim/systems/GatherSystem.gd")
const CombatSystem := preload("res://engine/sim/systems/CombatSystem.gd")
const BuildSystem := preload("res://engine/sim/systems/BuildSystem.gd")

const REACH := 800
## Radio de la campana alrededor del centro urbano que la toca.
const BELL_R := 30000


static func is_inside(w, id: int) -> bool:
	var g: Dictionary = w.comp(id, "Garrisoned")
	return not g.is_empty() and bool(g["inside"])


## Plazas libres contando a los que ya caminan hacia el edificio.
static func free_slots(w, b: int) -> int:
	var gar: Dictionary = w.comp(b, "Garrison")
	if gar.is_empty():
		return 0
	var used: int = (gar["units"] as Array).size()
	for u in w.ids_with("Garrisoned"):
		var g: Dictionary = w.comp(u, "Garrisoned")
		if int(g["in"]) == b and not bool(g["inside"]):
			used += 1
	return int(gar["params"]["capacity"]) - used


## "" si id puede guarecerse en b.
static func garrison_error(sim, id: int, b: int) -> String:
	var w = sim.world
	if not w.has_ability(id, "Garrisonable") or not w.has_ability(id, "Move") or is_inside(w, id):
		return "no puede guarecerse"
	if not w.entities.has(b) or str(w.entities[b]["type"]) != "building":
		return "no es un edificio" # (los barcos de transporte, más adelante)
	if not w.has_ability(b, "Garrison") or not sim.is_built(b):
		return "no admite guarnición"
	if int(w.entities[b]["owner"]) != int(w.entities[id]["owner"]):
		return "edificio ajeno"
	return ""


## Una orden nueva del jugador anula la de guarecerse si aún camina hacia el
## edificio (los que ya están dentro solo salen con "ungarrison").
static func cancel(w, id: int) -> void:
	var g: Dictionary = w.comp(id, "Garrisoned")
	if not g.is_empty() and not bool(g["inside"]):
		w.remove_component(id, "Garrisoned")


static func order_garrison(sim, id: int, b: int) -> void:
	var w = sim.world
	if garrison_error(sim, id, b) != "" or free_slots(w, b) <= 0:
		return
	GatherSystem.stop(sim, id)
	CombatSystem.stop(sim, id)
	BuildSystem.stop(sim, id)
	w.add_component(id, "Garrisoned", {"params": {}, "in": b, "inside": false})
	var pos: Vector2i = w.entities[id]["pos"]
	var r := GatherSystem._rect(sim, b)
	if GatherSystem._rect_dist(pos, r) > REACH:
		var lo: Vector2i = r[0]
		var hi: Vector2i = r[1]
		MoveSystem.order_move(w, sim.grid, id, Vector2i(clampi(pos.x, lo.x, hi.x - 1), clampi(pos.y, lo.y, hi.y - 1)))


static func step(sim) -> void:
	var w = sim.world
	for id in w.ids_with("Garrisoned"):
		var g: Dictionary = w.comp(id, "Garrisoned")
		if bool(g["inside"]):
			continue
		var b: int = g["in"]
		if garrison_error(sim, id, b) != "":
			w.remove_component(id, "Garrisoned")
			continue
		var m: Dictionary = w.comp(id, "Move")
		if bool(m["moving"]):
			continue
		var gar: Dictionary = w.comp(b, "Garrison")
		var full: bool = (gar["units"] as Array).size() >= int(gar["params"]["capacity"])
		if full or GatherSystem._rect_dist(w.entities[id]["pos"], GatherSystem._rect(sim, b)) > REACH:
			w.remove_component(id, "Garrisoned") # lleno o inalcanzable
			continue
		_enter(sim, id, b, g)


static func _enter(sim, id: int, b: int, g: Dictionary) -> void:
	var w = sim.world
	# Dentro no se recolecta, construye, repara ni ataca.
	GatherSystem.stop(sim, id)
	CombatSystem.stop(sim, id)
	BuildSystem.stop(sim, id)
	g["inside"] = true
	var units: Array = w.comp(b, "Garrison")["units"]
	units.append(id)
	units.sort()
	var m: Dictionary = w.comp(id, "Move")
	(m["waypoints"] as Array).clear()
	m["moving"] = false
	w.spatial.remove(id)
	w.entities[id]["pos"] = w.entities[b]["pos"]


## Saca a los guarecidos (todos, o solo los que cumplan `only`) a casillas
## libres junto al edificio; con punto de reunión van hacia él.
## force: si no hay casilla libre, la unidad sale igual sobre el edificio
## (se usa cuando el edificio desaparece: nadie queda atrapado).
static func eject(sim, b: int, only: Callable = Callable(), force: bool = false) -> void:
	var w = sim.world
	var gar: Dictionary = w.comp(b, "Garrison")
	if gar.is_empty():
		return
	var def: Dictionary = sim.def_for(b)
	var size := Vector2i.ONE
	if def.get("footprint") is Array:
		size = Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
	var origin := Grid.tile_of(w.entities[b]["pos"] - size * (FP.SCALE / 2))
	var rally := Vector2i(-1, -1)
	var q: Dictionary = w.comp(b, "Queue")
	if not q.is_empty():
		rally = q["rally"]
	var goal := origin + Vector2i(size.x / 2, size.y)
	if rally.x >= 0:
		goal = Grid.tile_of(rally)
	var keep: Array = []
	for u in (gar["units"] as Array).duplicate():
		if only.is_valid() and not only.call(u):
			keep.append(u)
			continue
		var t: Vector2i = sim.exit_tile(origin, size, goal)
		var p: Vector2i = w.entities[b]["pos"]
		if t.x >= 0:
			p = Grid.center_of(t)
		elif not force:
			keep.append(u) # sin salida: sigue dentro
			continue
		w.entities[u]["pos"] = p
		w.spatial.insert(u, p)
		w.remove_component(u, "Garrisoned")
		if rally.x >= 0:
			MoveSystem.order_move(w, sim.grid, u, rally)
	gar["units"] = keep


## Una entidad desaparece: si era edificio, salen sus guarecidos; si estaba
## dentro, deja su plaza.
static func on_remove(sim, id: int) -> void:
	var w = sim.world
	if w.has_ability(id, "Garrison"):
		eject(sim, id, Callable(), true)
	var g: Dictionary = w.comp(id, "Garrisoned")
	if not g.is_empty() and bool(g["inside"]) and w.has_ability(int(g["in"]), "Garrison"):
		(w.comp(int(g["in"]), "Garrison")["units"] as Array).erase(id)


## Flechas extra de un edificio guarecido (AoE2): n × arrows_per_unit.
static func extra_arrows(w, b: int) -> int:
	var gar: Dictionary = w.comp(b, "Garrison")
	if gar.is_empty():
		return 0
	var per := FP.from_data(float(gar["params"].get("arrows_per_unit", 0.0)))
	return (gar["units"] as Array).size() * per / FP.SCALE


## Campana: la primera vez, los aldeanos propios cerca del centro urbano se
## guarecen en el edificio con sitio más cercano; la siguiente, salen todos.
static func ring_bell(sim, pid: int, tc: int) -> void:
	var w = sim.world
	var p: Dictionary = sim.players[pid]
	if bool(p.get("bell", false)):
		p["bell"] = false
		for v in w.ids_with("Gather"):
			if int(w.entities[v]["owner"]) == pid:
				cancel(w, v) # los que aún caminan hacia dentro se quedan fuera
		for b in w.ids_with("Garrison"):
			if int(w.entities[b]["owner"]) == pid and str(w.entities[b]["type"]) == "building":
				eject(sim, b, func(u): return w.has_ability(u, "Gather"))
		return
	p["bell"] = true
	var center: Vector2i = w.entities[tc]["pos"]
	for v in w.ids_with("Gather"):
		var e: Dictionary = w.entities[v]
		if int(e["owner"]) != pid or is_inside(w, v) or FP.dist(e["pos"], center) > BELL_R:
			continue
		var best := -1
		var best_d := 0
		for b in w.ids_with("Garrison"):
			if garrison_error(sim, v, b) != "" or free_slots(w, b) <= 0:
				continue
			var d := GatherSystem._rect_dist(e["pos"], GatherSystem._rect(sim, b))
			if best < 0 or d < best_d:
				best = b
				best_d = d
		if best >= 0:
			order_garrison(sim, v, best)

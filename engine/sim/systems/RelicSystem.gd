extends RefCounted
## Reliquias estilo AoE2: solo los monjes (Convert) las recogen; se llevan a
## un monasterio propio (RelicHolder) y allí dan oro (Relic.gold_per_sec).
## Un monje que lleva una reliquia no convierte ni cura. Si el monje muere o
## el monasterio cae, la reliquia vuelve al suelo: nunca se pierde.
##
## Tiempo de ejecución: la reliquia tiene Held {by} mientras la lleva un monje
## o está guardada (fuera del SpatialHash); el monje, Carrying {relic}; la
## orden en curso, RelicTask {kind: "pick"|"store", target}.

const FP := preload("res://engine/sim/FixedPoint.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const World := preload("res://engine/sim/World.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")
const GatherSystem := preload("res://engine/sim/systems/GatherSystem.gd")

const REACH := 800


static func pick_error(sim, monk: int, relic: int) -> String:
	var w = sim.world
	if not w.has_ability(monk, "Convert") or w.has_ability(monk, "Carrying"):
		return "no puede llevarla"
	if not w.has_ability(relic, "Relic") or w.has_ability(relic, "Held"):
		return "no hay reliquia libre"
	return ""


static func store_error(sim, monk: int, b: int) -> String:
	var w = sim.world
	if not w.has_ability(monk, "Carrying"):
		return "no lleva reliquia"
	if not w.has_ability(b, "RelicHolder") or not sim.is_built(b):
		return "no guarda reliquias"
	if int(w.entities[b]["owner"]) != int(w.entities[monk]["owner"]):
		return "monasterio ajeno"
	return ""


static func order(sim, monk: int, kind: String, target: int) -> void:
	var err := pick_error(sim, monk, target) if kind == "pick" else store_error(sim, monk, target)
	if err != "":
		return
	var w = sim.world
	w.add_component(monk, "RelicTask", {"params": {}, "kind": kind, "target": target})
	var pos: Vector2i = w.entities[monk]["pos"]
	var dest: Vector2i = w.entities[target]["pos"]
	if kind == "store":
		var r := GatherSystem._rect(sim, target)
		var lo: Vector2i = r[0]
		var hi: Vector2i = r[1]
		dest = Vector2i(clampi(pos.x, lo.x, hi.x - 1), clampi(pos.y, lo.y, hi.y - 1))
	MoveSystem.order_move(w, sim.grid, monk, dest)


static func cancel(w, id: int) -> void:
	w.remove_component(id, "RelicTask")


static func step(sim) -> void:
	var w = sim.world
	for monk in w.ids_with("RelicTask"):
		var task: Dictionary = w.comp(monk, "RelicTask")
		var t: int = task["target"]
		var kind := str(task["kind"])
		var err := pick_error(sim, monk, t) if kind == "pick" else store_error(sim, monk, t)
		if err != "":
			cancel(w, monk)
			continue
		if bool(w.comp(monk, "Move")["moving"]):
			continue
		var pos: Vector2i = w.entities[monk]["pos"]
		var d := FP.dist(pos, w.entities[t]["pos"]) if kind == "pick" else GatherSystem._rect_dist(pos, GatherSystem._rect(sim, t))
		if d > REACH:
			cancel(w, monk) # inalcanzable
			continue
		if kind == "pick":
			_pick(w, monk, t)
		else:
			_store(w, monk, t)
		cancel(w, monk)
	# La reliquia acompaña al monje; las guardadas dan oro.
	for monk in w.ids_with("Carrying"):
		var r: int = w.comp(monk, "Carrying")["relic"]
		w.entities[r]["pos"] = w.entities[monk]["pos"]
		w.entities[r]["owner"] = w.entities[monk]["owner"]
	for b in w.ids_with("RelicHolder"):
		var relics: Array = w.comp(b, "RelicHolder")["relics"]
		if relics.is_empty() or not sim.is_built(b):
			continue
		var owner := int(w.entities[b]["owner"])
		for r in relics:
			sim.add_res(owner, "gold", FP.from_data(float(w.comp(r, "Relic")["params"]["gold_per_sec"])) / World.TICK_RATE)


static func _pick(w, monk: int, relic: int) -> void:
	w.add_component(relic, "Held", {"params": {}, "by": monk})
	w.spatial.remove(relic)
	w.add_component(monk, "Carrying", {"params": {}, "relic": relic})


static func _store(w, monk: int, b: int) -> void:
	var relic: int = w.comp(monk, "Carrying")["relic"]
	w.remove_component(monk, "Carrying")
	w.comp(relic, "Held")["by"] = b
	w.entities[relic]["pos"] = w.entities[b]["pos"]
	w.entities[relic]["owner"] = w.entities[b]["owner"]
	var relics: Array = w.comp(b, "RelicHolder")["relics"]
	relics.append(relic)
	relics.sort()


## Deja la reliquia en el suelo en pos (sin dueño).
static func _drop(w, relic: int, pos: Vector2i) -> void:
	w.remove_component(relic, "Held")
	w.entities[relic]["pos"] = pos
	w.entities[relic]["owner"] = -1
	w.spatial.insert(relic, pos)


## Antes de quitar una entidad: el monje suelta su reliquia; el monasterio,
## las guardadas (en casillas libres alrededor).
static func on_remove(sim, id: int) -> void:
	var w = sim.world
	var c: Dictionary = w.comp(id, "Carrying")
	if not c.is_empty():
		_drop(w, int(c["relic"]), w.entities[id]["pos"])
		w.remove_component(id, "Carrying")
	var h: Dictionary = w.comp(id, "RelicHolder")
	if not h.is_empty() and not (h["relics"] as Array).is_empty():
		var def: Dictionary = sim.def_for(id)
		var size := Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
		var origin := Grid.tile_of(w.entities[id]["pos"] - size * (FP.SCALE / 2))
		var i := 0
		for r in (h["relics"] as Array).duplicate():
			var t: Vector2i = sim.exit_tile(origin, size, origin + Vector2i(i, size.y))
			_drop(w, r, Grid.center_of(t) if t.x >= 0 else w.entities[id]["pos"])
			i += 1
		h["relics"] = []

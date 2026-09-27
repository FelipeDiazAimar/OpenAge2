extends RefCounted
## Construcción estilo AoE2: los aldeanos van al borde del cimiento y lo
## levantan juntos. Con n constructores el avance por tick es n + 2 tercios
## (tiempo = base × 3 / (n + 2)). El HP del edificio crece con el avance.
## Estados: idle, to_site, building.

const FP := preload("res://engine/sim/FixedPoint.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")
const GatherSystem := preload("res://engine/sim/systems/GatherSystem.gd")
const CombatSystem := preload("res://engine/sim/systems/CombatSystem.gd")

const REACH := 800
## Radio para seguir con otro cimiento propio al terminar.
const NEXT_R := 12000


static func order_build(sim, id: int, target: int) -> void:
	var w = sim.world
	var b: Dictionary = w.comp(id, "Build")
	if b.is_empty() or not w.has_ability(target, "Foundation"):
		return
	if int(w.entities[target]["owner"]) != int(w.entities[id]["owner"]):
		return
	GatherSystem.stop(sim, id)
	CombatSystem.stop(sim, id)
	b["target"] = target
	b["state"] = "to_site"
	var pos: Vector2i = w.entities[id]["pos"]
	var r := GatherSystem._rect(sim, target)
	if GatherSystem._rect_dist(pos, r) <= REACH:
		_start(w, id, b, target)
		return
	var lo: Vector2i = r[0]
	var hi: Vector2i = r[1]
	MoveSystem.order_move(w, sim.grid, id, Vector2i(clampi(pos.x, lo.x, hi.x - 1), clampi(pos.y, lo.y, hi.y - 1)))


static func stop(sim, id: int) -> void:
	var b: Dictionary = sim.world.comp(id, "Build")
	if not b.is_empty():
		b["state"] = "idle"
		b["target"] = -1


static func _start(w, id: int, b: Dictionary, target: int) -> void:
	b["state"] = "building"
	var m: Dictionary = w.comp(id, "Move")
	if m.is_empty():
		return
	(m["waypoints"] as Array).clear()
	m["moving"] = false
	var d: Vector2i = w.entities[target]["pos"] - w.entities[id]["pos"]
	if d != Vector2i.ZERO:
		m["facing"] = d


static func step(sim) -> void:
	var w = sim.world
	var counts := {}
	for id in w.ids_with("Build"):
		var b: Dictionary = w.comp(id, "Build")
		if str(b["state"]) == "idle":
			continue
		var t: int = b["target"]
		if not w.entities.has(t) or not w.has_ability(t, "Foundation"):
			_after(sim, id, b, t)
			continue
		if str(b["state"]) == "to_site":
			if bool(w.comp(id, "Move").get("moving", false)):
				continue
			if GatherSystem._rect_dist(w.entities[id]["pos"], GatherSystem._rect(sim, t)) > REACH:
				stop(sim, id) # inalcanzable
				continue
			_start(w, id, b, t)
		counts[t] = int(counts.get(t, 0)) + 1
	var targets: Array = counts.keys()
	targets.sort()
	for t in targets:
		_advance(sim, t, int(counts[t]))


static func _advance(sim, t: int, n: int) -> void:
	var w = sim.world
	var f: Dictionary = w.comp(t, "Foundation")
	var total: int = f["total"]
	var before: int = f["progress"]
	var after := mini(total, before + n + 2)
	f["progress"] = after
	var hp: Dictionary = w.comp(t, "Hitpoints")
	if not hp.is_empty():
		var mx: int = hp["max"]
		var gained: int = mx * after / total - mx * before / total
		hp["hp"] = mini(mx, int(hp["hp"]) + gained)
	if after >= total:
		w.remove_component(t, "Foundation")
		sim.events.append({"type": "built", "id": t, "def_id": w.entities[t]["def_id"], "owner": w.entities[t]["owner"]})


## Terminado (o destruido): otro cimiento propio cerca; si era un depósito
## (sin Train, como un campamento), recolectar lo que acepta; si no, ocioso.
static func _after(sim, id: int, b: Dictionary, done: int) -> void:
	var w = sim.world
	stop(sim, id)
	var e: Dictionary = w.entities[id]
	var pos: Vector2i = e["pos"]
	var best := -1
	var best_d := 0
	for f in w.ids_with("Foundation"):
		if int(w.entities[f]["owner"]) != int(e["owner"]):
			continue
		var d := GatherSystem._rect_dist(pos, GatherSystem._rect(sim, f))
		if d <= NEXT_R and (best < 0 or d < best_d):
			best = f
			best_d = d
	if best >= 0:
		order_build(sim, id, best)
		return
	if not w.entities.has(done) or not w.has_ability(done, "DropSite") or w.has_ability(done, "Train"):
		return
	if not w.has_ability(id, "Gather"):
		return
	var accepts: Array = w.comp(done, "DropSite")["params"]["accepts"]
	var rates: Dictionary = w.comp(id, "Gather")["params"]["rates"]
	var res := -1
	var res_d := 0
	for c in w.spatial.query_radius(pos, GatherSystem.RETARGET_R):
		var src: Dictionary = w.comp(c, "ResourceSource")
		if src.is_empty():
			continue
		var p: Dictionary = src["params"]
		if not accepts.has(str(p["resource"])) or not rates.has(str(p["rate_key"])):
			continue
		if bool(p.get("requires_kill", false)) or bool(p.get("water", false)):
			continue
		var d := FP.dist(pos, w.entities[c]["pos"])
		if res < 0 or d < res_d:
			res = c
			res_d = d
	if res >= 0:
		GatherSystem.order_gather(sim, id, res)

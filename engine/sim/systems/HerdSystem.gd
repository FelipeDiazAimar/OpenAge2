extends RefCounted
## Ovejas estilo AoE2: una oveja viva (tame) pertenece al jugador que la ve.
## Si su dueño no tiene unidades cerca y otro jugador sí, pasa a ese jugador
## (la unidad más cercana; desempate por id).

const FP := preload("res://engine/sim/FixedPoint.gd")

const RADIUS := 4000
const EVERY := 5


static func step(sim) -> void:
	var w = sim.world
	if w.tick % EVERY != 0:
		return
	for id in w.ids_with("ResourceSource"):
		var src: Dictionary = w.comp(id, "ResourceSource")
		if not bool(src["params"].get("tame", false)) or not w.has_ability(id, "Hitpoints"):
			continue
		var e: Dictionary = w.entities[id]
		var owner := int(e["owner"])
		var best := -1
		var best_d := 0
		var owner_near := false
		for c in w.spatial.query_radius(e["pos"], RADIUS):
			var ce: Dictionary = w.entities[c]
			if str(ce["type"]) != "unit" or int(ce["owner"]) < 0:
				continue
			if int(ce["owner"]) == owner:
				owner_near = true
				break
			var d := FP.dist(e["pos"], ce["pos"])
			if best < 0 or d < best_d:
				best = c
				best_d = d
		if not owner_near and best >= 0:
			e["owner"] = w.entities[best]["owner"]

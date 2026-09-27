extends RefCounted
## Separación: las entidades móviles (unidades y animales) superpuestas se
## apartan la mitad del solapamiento cada una, sin entrar en casillas
## bloqueadas. Determinista: pares (a < b) en orden de id.

const FP := preload("res://engine/sim/FixedPoint.gd")
const Grid := preload("res://engine/sim/Grid.gd")

const SEP := 400


static func step(sim) -> void:
	var w = sim.world
	for id in w.ids_with("Move"):
		if not w.entities.has(id):
			continue
		for o in w.spatial.query_radius(w.entities[id]["pos"], SEP - 1):
			if o <= id or not w.has_ability(o, "Move"):
				continue
			var p: Vector2i = w.entities[id]["pos"]
			var q: Vector2i = w.entities[o]["pos"]
			var d := q - p
			var dist := FP.length(d.x, d.y)
			if dist >= SEP:
				continue
			var dir := Vector2i(1000, 0)
			if dist > 0:
				dir = Vector2i(d.x * 1000 / dist, d.y * 1000 / dist)
			else:
				# Encimadas: dirección fija por id (determinista).
				var dirs := [Vector2i(1000, 0), Vector2i(0, 1000), Vector2i(-1000, 0), Vector2i(0, -1000),
					Vector2i(707, 707), Vector2i(-707, 707), Vector2i(-707, -707), Vector2i(707, -707)]
				dir = dirs[(id * 3 + o) % dirs.size()]
			var push := (SEP - dist + 1) / 2
			var off := Vector2i(dir.x * push / 1000, dir.y * push / 1000)
			_try_move(sim, o, q + off)
			_try_move(sim, id, p - off)


static func _try_move(sim, id: int, to: Vector2i) -> void:
	if sim.grid.is_walkable(Grid.tile_of(to)):
		sim.world.set_pos(id, to)

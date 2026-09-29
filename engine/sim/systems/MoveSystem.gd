extends RefCounted
## Movimiento: órdenes (camino A* -> waypoints en milésimas) y avance por tick.

const FP := preload("res://engine/sim/FixedPoint.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const Pathfinder := preload("res://engine/sim/Pathfinder.gd")


static func order_move(world, grid, id: int, dest: Vector2i) -> void:
	var m: Dictionary = world.comp(id, "Move")
	if m.is_empty():
		return
	if world.has_ability(id, "Naval") and grid.naval != null:
		grid = grid.naval # los barcos solo navegan por agua
	var pos: Vector2i = world.entities[id]["pos"]
	var start := Grid.tile_of(pos)
	var dest_tile := Grid.tile_of(dest)
	var pts: Array[Vector2i] = []
	if dest_tile == start and grid.is_walkable(dest_tile):
		pts.append(dest)
	else:
		for t in Pathfinder.find_path(grid, start, dest_tile):
			pts.append(Grid.center_of(t))
		if not pts.is_empty() and Grid.tile_of(pts[pts.size() - 1]) == dest_tile:
			pts[pts.size() - 1] = dest
	m["waypoints"] = pts
	m["moving"] = not pts.is_empty()


static func step(world) -> void:
	for id in world.ids_with("Move"):
		var m: Dictionary = world.comp(id, "Move")
		if not m["moving"]:
			continue
		var budget: int = m["step"]
		var pos: Vector2i = world.entities[id]["pos"]
		var wps: Array = m["waypoints"]
		while budget > 0 and not wps.is_empty():
			var t: Vector2i = wps[0]
			var d := t - pos
			var dist := FP.length(d.x, d.y)
			if dist <= budget:
				pos = t
				budget -= dist
				wps.pop_front()
				if dist > 0:
					m["facing"] = d
			else:
				pos += Vector2i(d.x * budget / dist, d.y * budget / dist)
				m["facing"] = d
				budget = 0
		world.set_pos(id, pos)
		if wps.is_empty():
			m["moving"] = false

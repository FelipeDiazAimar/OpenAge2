extends RefCounted
## Separación: las entidades móviles (unidades y animales) quietas y
## superpuestas se apartan la mitad del solapamiento cada una; una quieta se
## aparta del todo de la que pasa; dos en marcha no se empujan. Nunca entra
## en casillas bloqueadas. Determinista: pares (a < b) en orden de id.

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
			# Dos en marcha no se empujan (se cruzan, como en AoE2): si no, el de
			# atrás retrocede cada tick y la fila avanza "arrastrada". Si solo uno
			# camina, se aparta el que está quieto.
			var mi := bool(w.comp(id, "Move")["moving"])
			var mo := bool(w.comp(o, "Move")["moving"])
			if mi and mo:
				continue
			if mi or mo:
				var full := SEP - dist
				var o2 := Vector2i(dir.x * full / 1000, dir.y * full / 1000)
				if mi:
					_try_move(sim, o, q + o2)
				else:
					_try_move(sim, id, p - o2)
				continue
			var push := (SEP - dist + 1) / 2
			var off := Vector2i(dir.x * push / 1000, dir.y * push / 1000)
			_try_move(sim, o, q + off)
			_try_move(sim, id, p - off)


## Solo a casillas transitables; un cambio diagonal de casilla exige ambas
## ortogonales libres (no cruzar esquinas de muros o edificios).
static func _try_move(sim, id: int, to: Vector2i) -> void:
	var g = sim.grid
	var a := Grid.tile_of(sim.world.entities[id]["pos"])
	var b := Grid.tile_of(to)
	if not g.is_walkable(b):
		return
	if a.x != b.x and a.y != b.y:
		if not g.is_walkable(Vector2i(b.x, a.y)) or not g.is_walkable(Vector2i(a.x, b.y)):
			return
	sim.world.set_pos(id, to)

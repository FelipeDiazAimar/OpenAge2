extends RefCounted
## Grilla de celdas para consultas por radio. Posiciones en punto fijo.

const FP := preload("res://engine/sim/FixedPoint.gd")
const CELL := 4 * FP.SCALE

var _cells: Dictionary = {}
var _pos: Dictionary = {}


static func cell_of(p: Vector2i) -> Vector2i:
	return Vector2i(FP.floordiv(p.x, CELL), FP.floordiv(p.y, CELL))


func insert(id: int, p: Vector2i) -> void:
	_pos[id] = p
	var c := cell_of(p)
	if not _cells.has(c):
		_cells[c] = []
	_cells[c].append(id)


func remove(id: int) -> void:
	if not _pos.has(id):
		return
	var c := cell_of(_pos[id])
	_cells[c].erase(id)
	if _cells[c].is_empty():
		_cells.erase(c)
	_pos.erase(id)


func move(id: int, p: Vector2i) -> void:
	if _pos.has(id) and cell_of(_pos[id]) == cell_of(p):
		_pos[id] = p
		return
	remove(id)
	insert(id, p)


func query_radius(center: Vector2i, radius: int) -> Array[int]:
	var out: Array[int] = []
	var lo := cell_of(center - Vector2i(radius, radius))
	var hi := cell_of(center + Vector2i(radius, radius))
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var c := Vector2i(cx, cy)
			if not _cells.has(c):
				continue
			for id in _cells[c]:
				if FP.dist(center, _pos[id]) <= radius:
					out.append(id)
	out.sort()
	return out


func count() -> int:
	return _pos.size()

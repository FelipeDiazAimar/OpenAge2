extends RefCounted
## Grilla de casillas: caminabilidad y conversiones casilla <-> milésimas.

const FP := preload("res://engine/sim/FixedPoint.gd")

var width := 0
var height := 0
var _blocked := PackedByteArray()


func _init(w: int, h: int) -> void:
	width = w
	height = h
	_blocked.resize(w * h)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and _blocked[c.y * width + c.x] == 0


func set_blocked(c: Vector2i, v: bool) -> void:
	if in_bounds(c):
		_blocked[c.y * width + c.x] = 1 if v else 0


func block_rect(origin: Vector2i, size: Vector2i, v: bool = true) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			set_blocked(Vector2i(x, y), v)


func clamp_tile(c: Vector2i) -> Vector2i:
	return Vector2i(clampi(c.x, 0, width - 1), clampi(c.y, 0, height - 1))


static func tile_of(p: Vector2i) -> Vector2i:
	return Vector2i(FP.floordiv(p.x, FP.SCALE), FP.floordiv(p.y, FP.SCALE))


static func center_of(c: Vector2i) -> Vector2i:
	return c * FP.SCALE + Vector2i(FP.SCALE / 2, FP.SCALE / 2)

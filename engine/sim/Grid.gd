extends RefCounted
## Grilla de casillas: caminabilidad y conversiones casilla <-> milésimas.

const FP := preload("res://engine/sim/FixedPoint.gd")

var width := 0
var height := 0
var _blocked := PackedByteArray()
var _region := PackedInt32Array()
var _regions_dirty := true


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
		var nv := 1 if v else 0
		if _blocked[c.y * width + c.x] != nv:
			_blocked[c.y * width + c.x] = nv
			_regions_dirty = true


func block_rect(origin: Vector2i, size: Vector2i, v: bool = true) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			set_blocked(Vector2i(x, y), v)


## Región conectada (4-vecinos) de una casilla caminable; -1 si está
## bloqueada o fuera del mapa. Se recalcula perezosamente tras cambios.
func region_of(c: Vector2i) -> int:
	if not in_bounds(c):
		return -1
	if _regions_dirty:
		_label_regions()
	return _region[c.y * width + c.x]


func _label_regions() -> void:
	var n := width * height
	_region.resize(n)
	_region.fill(-1)
	var next := 0
	var stack := PackedInt32Array()
	for start in n:
		if _blocked[start] != 0 or _region[start] != -1:
			continue
		_region[start] = next
		stack.append(start)
		while stack.size() > 0:
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x := i % width
			var y := i / width
			for nb in [i - 1 if x > 0 else -1, i + 1 if x < width - 1 else -1, i - width if y > 0 else -1, i + width if y < height - 1 else -1]:
				if nb >= 0 and _blocked[nb] == 0 and _region[nb] == -1:
					_region[nb] = next
					stack.append(nb)
		next += 1
	_regions_dirty = false


## Celdas bloqueadas (1) / libres (0), índice y*width+x. Solo lectura.
func cells() -> PackedByteArray:
	return _blocked


func clamp_tile(c: Vector2i) -> Vector2i:
	return Vector2i(clampi(c.x, 0, width - 1), clampi(c.y, 0, height - 1))


static func tile_of(p: Vector2i) -> Vector2i:
	return Vector2i(FP.floordiv(p.x, FP.SCALE), FP.floordiv(p.y, FP.SCALE))


static func center_of(c: Vector2i) -> Vector2i:
	return c * FP.SCALE + Vector2i(FP.SCALE / 2, FP.SCALE / 2)

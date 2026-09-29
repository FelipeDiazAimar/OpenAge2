extends RefCounted
## Grilla de casillas: caminabilidad y conversiones casilla <-> milésimas.
## La grilla de tierra tiene una hermana `naval` (misma medida) para los
## barcos: el agua bloquea la de tierra y es lo único libre en la naval.

const FP := preload("res://engine/sim/FixedPoint.gd")

var width := 0
var height := 0
var _blocked := PackedByteArray()
var _region := PackedInt32Array()
var _regions_dirty := true
var _next_label := 0
## Cuántas veces se re-etiquetó el mapa completo (para tests de rendimiento).
var relabel_count := 0
## Grilla de los barcos (null en la propia grilla naval).
var naval = null
var _water := PackedByteArray()


func _init(w: int, h: int) -> void:
	width = w
	height = h
	_blocked.resize(w * h)


## Crea la grilla naval (todo bloqueado hasta que haya agua).
func with_naval():
	naval = get_script().new(width, height)
	naval._blocked.fill(1)
	naval._regions_dirty = true
	_water.resize(width * height)
	return self


func is_water(c: Vector2i) -> bool:
	return in_bounds(c) and not _water.is_empty() and _water[c.y * width + c.x] == 1


## Agua: bloquea la tierra y abre el paso a los barcos.
func set_water(c: Vector2i, v: bool = true) -> void:
	if not in_bounds(c) or naval == null:
		return
	_water[c.y * width + c.x] = 1 if v else 0
	set_blocked(c, v)
	naval.set_blocked(c, not v)


## Grilla de un dominio: la naval para barcos, esta para el resto.
func for_unit(is_naval: bool):
	return naval if is_naval and naval != null else self


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and _blocked[c.y * width + c.x] == 0


func set_blocked(c: Vector2i, v: bool) -> void:
	if in_bounds(c):
		var i := c.y * width + c.x
		var nv := 1 if v else 0
		if _blocked[i] == nv:
			return
		_blocked[i] = nv
		if v or _regions_dirty:
			_regions_dirty = true # bloquear puede partir una región
		else:
			_unblock_region(c, i)


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


## Casilla liberada con las regiones al día (p. ej. árbol talado): si sus
## vecinos caminables son todos de una región, se une a ella; si no tiene
## vecinos, región nueva. Solo si une regiones distintas se re-etiqueta todo.
func _unblock_region(c: Vector2i, i: int) -> void:
	var label := -1
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if not is_walkable(n):
			continue
		var r := _region[n.y * width + n.x]
		if label < 0:
			label = r
		elif r != label:
			_regions_dirty = true
			return
	if label < 0:
		label = _next_label
		_next_label += 1
	_region[i] = label


func _label_regions() -> void:
	relabel_count += 1
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
	_next_label = next
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

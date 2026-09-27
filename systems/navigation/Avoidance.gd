class_name Avoidance
extends Node
## Separation steering determinista para hasta 500 unidades (tick 10 Hz).
## Reglas core/API.md: sin randf/randi/Time/fisica. Desempate solo por id.
## Uso: register() cada tick con la pos actual (hace upsert), luego
## update_all(0.1) y sumar el ajuste (m/s) a la velocidad deseada:
##   pos += (vel_deseada + ajuste[id]) * delta

const CELL_SIZE := 2.0 ## Celda del hash espacial (m).
const TICK_DELTA := 0.1 ## Delta del lockstep a 10 Hz.
const EPSILON := 0.0001 ## Distancia minima para normalizar sin dividir por cero.

## Fraccion del solape que se resuelve por tick (1.0 = separa del todo en 1 tick).
var separation_strength := 1.0
## Tope del ajuste devuelto (m/s), evita explosiones al apilar unidades.
var max_push_speed := 6.0

var _positions: Dictionary = {} # id (int) -> Vector3
var _radii: Dictionary = {} # id (int) -> float
var _grid: Dictionary = {} # Vector3i -> Array[int] (ordenada por id)


func register(id: int, pos: Vector3, radius: float = 0.4) -> void:
	## Inserta o actualiza una unidad. Llamar cada tick con la pos actual.
	_positions[id] = pos
	_radii[id] = maxf(0.01, radius)


func unregister(id: int) -> void:
	_positions.erase(id)
	_radii.erase(id)


func clear() -> void:
	_positions.clear()
	_radii.clear()
	_grid.clear()


func count() -> int:
	return _positions.size()


func update_all(delta: float) -> Dictionary:
	## Reconstruye el hash y devuelve Dictionary id (int) -> ajuste Vector3 (m/s).
	## Orden de iteracion fijo (ids ordenados, celdas vecinas fijas) para
	## resultado bit-identico en todos los peers del lockstep.
	var dt: float = delta if delta > 0.0 else TICK_DELTA
	_rebuild_grid()
	var ids: Array = _positions.keys()
	ids.sort()
	var offsets: Dictionary = {}
	for id in ids:
		offsets[id] = Vector3.ZERO
	for a in ids:
		var pa: Vector3 = _positions[a]
		var ra: float = _radii[a]
		var cell: Vector3i = _cell_of(pa)
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				for oz in range(-1, 2):
					var key := Vector3i(cell.x + ox, cell.y + oy, cell.z + oz)
					if not _grid.has(key):
						continue
					var cell_ids: Array = _grid[key] # ya ordenada por id
					for b in cell_ids:
						if int(b) <= int(a):
							continue # cada par no ordenado se resuelve una sola vez
						_resolve_pair(a, b, offsets)
	var out: Dictionary = {}
	var max_step: float = max_push_speed * dt
	for id in ids:
		var cur: Vector3 = offsets[id]
		var step: Vector3 = cur * separation_strength
		var l2: float = step.length_squared()
		if l2 > max_step * max_step:
			step = (step / sqrt(l2)) * max_step
		out[id] = step / dt
	return out


func _resolve_pair(a: int, b: int, offsets: Dictionary) -> void:
	var pa: Vector3 = _positions[a]
	var pb: Vector3 = _positions[b]
	var ra: float = _radii[a]
	var rb: float = _radii[b]
	var min_dist: float = ra + rb
	var diff: Vector3 = pa - pb
	var d2: float = diff.length_squared()
	if d2 >= min_dist * min_dist:
		return
	var dist: float = sqrt(maxf(d2, 0.0))
	var dir: Vector3
	if dist > EPSILON:
		dir = diff / dist
	else:
		dir = _fallback_dir(a, b) # solape total: desempate determinista por id
	var overlap: float = min_dist - dist
	var total: float = ra + rb
	var wa := 0.5
	var wb := 0.5
	if total > EPSILON:
		wa = rb / total # la unidad grande empuja mas a la pequena
		wb = ra / total
	var off_a: Vector3 = offsets[a]
	var off_b: Vector3 = offsets[b]
	offsets[a] = off_a + dir * (overlap * wa)
	offsets[b] = off_b - dir * (overlap * wb)


func _rebuild_grid() -> void:
	_grid.clear()
	var ids: Array = _positions.keys()
	ids.sort() # insercion en orden => cada celda queda ordenada por id
	for id in ids:
		var p: Vector3 = _positions[id]
		var key := _cell_of(p)
		if not _grid.has(key):
			_grid[key] = []
		var bucket: Array = _grid[key]
		bucket.append(id)


func _cell_of(p: Vector3) -> Vector3i:
	return Vector3i(
		floori(p.x / CELL_SIZE),
		floori(p.y / CELL_SIZE),
		floori(p.z / CELL_SIZE)
	)


func _fallback_dir(a: int, b: int) -> Vector3:
	## Direccion determinista sin trigonometria ni RNG: 8 rumbos fijos
	## elegidos por hash entero de los ids (conmutativo: vale para (a,b) o (b,a)).
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	var h: int = absi((lo * 73856093) ^ (hi * 19349663)) % 8
	match h:
		0:
			return Vector3(1, 0, 0)
		1:
			return Vector3(0.70710678, 0, 0.70710678)
		2:
			return Vector3(0, 0, 1)
		3:
			return Vector3(-0.70710678, 0, 0.70710678)
		4:
			return Vector3(-1, 0, 0)
		5:
			return Vector3(-0.70710678, 0, -0.70710678)
		6:
			return Vector3(0, 0, -1)
		_:
			return Vector3(0.70710678, 0, -0.70710678)

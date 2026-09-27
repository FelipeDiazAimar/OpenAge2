extends Node
# Pathfinding - A* determinista sobre grid 144x144 (celda 1m).
# Costes: hierba 1, bosque 3, agua/edificio bloqueado, diagonal 1.4 sin cortar esquinas.

enum Tile { GRASS, FOREST, WATER }

const GRID_W := 144
const GRID_H := 144
const CELL_SIZE := 1.0
const COST_GRASS := 1.0
const COST_FOREST := 3.0
const COST_DIAG := 1.4
const INF := 1.0e30
# Semilla fija solo para desempates del heap. Nunca cambia en partida (lockstep).
const TIE_SEED := 20260926

# Orden fijo de vecinos (determinista): 4 ortogonales + 4 diagonales.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _terrain: PackedByteArray # Tile por celda, size GRID_W * GRID_H
var _blocked: PackedByteArray # 1 = edificio/obstaculo, 0 = libre
var _tie: PackedFloat32Array # desempate fijo por celda, generado con SimRNG

# Estado de busqueda con versionado (evita limpiar 20k celdas por query).
var _g: PackedFloat32Array
var _came: PackedInt32Array
var _state: PackedByteArray # 0 = nada, 1 = open, 2 = closed
var _gen: PackedInt32Array
var _gen_cur: int = 0
var _goal_idx: int = -1

var _heap: Array[int] = []


func _ready() -> void:
	var n := GRID_W * GRID_H
	_terrain = PackedByteArray()
	_terrain.resize(n) # 0 = GRASS por defecto
	_blocked = PackedByteArray()
	_blocked.resize(n)
	_tie = PackedFloat32Array()
	_tie.resize(n)
	_g = PackedFloat32Array()
	_g.resize(n)
	_came = PackedInt32Array()
	_came.resize(n)
	_state = PackedByteArray()
	_state.resize(n)
	_gen = PackedInt32Array()
	_gen.resize(n)
	_build_tiebreak()


func _build_tiebreak() -> void:
	var rng = load("res://core/SimRNG.gd").new()
	rng.set_seed(TIE_SEED)
	for i in GRID_W * GRID_H:
		_tie[i] = rng.next_float()
	rng.free()


# --- Edicion del grid ---

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < GRID_W and y < GRID_H


func idx_of(x: int, y: int) -> int:
	return y * GRID_W + x


func cell_of(idx: int) -> Vector2i:
	return Vector2i(idx % GRID_W, idx / GRID_W)


func set_terrain(x: int, y: int, tile: int) -> void:
	if not in_bounds(x, y):
		return
	_terrain[idx_of(x, y)] = tile


func get_terrain(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Tile.WATER
	return _terrain[idx_of(x, y)]


func set_obstacle(x: int, y: int, blocked: bool) -> void:
	if not in_bounds(x, y):
		return
	_blocked[idx_of(x, y)] = 1 if blocked else 0


func clear_obstacles() -> void:
	_blocked.fill(0)


func is_walkable(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var i := idx_of(x, y)
	if _blocked[i] == 1:
		return false
	return _terrain[i] != Tile.WATER


func terrain_cost(x: int, y: int) -> float:
	return COST_FOREST if _terrain[idx_of(x, y)] == Tile.FOREST else COST_GRASS


func world_to_cell(w: Vector3) -> Vector2i:
	return Vector2i(floori(w.x / CELL_SIZE), floori(w.z / CELL_SIZE))


func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3((float(c.x) + 0.5) * CELL_SIZE, 0.0, (float(c.y) + 0.5) * CELL_SIZE)


# --- A* ---

func _heuristic(ax: int, ay: int, bx: int, by: int) -> float:
	# Octile admisible con coste minimo 1.0 (diagonal 1.4, recto 1.0).
	var dx := absi(ax - bx)
	var dy := absi(ay - by)
	return float(maxi(dx, dy)) + (COST_DIAG - 1.0) * float(mini(dx, dy))


func _heap_less(a: int, b: int) -> bool:
	# Compara f = g + h; desempate fijo via SimRNG precalculado, luego indice.
	var ca := cell_of(a)
	var cb := cell_of(b)
	var cg := cell_of(_goal_idx)
	var fa := _g[a] + _heuristic(ca.x, ca.y, cg.x, cg.y)
	var fb := _g[b] + _heuristic(cb.x, cb.y, cg.x, cg.y)
	if fa != fb:
		return fa < fb
	var ha := _heuristic(ca.x, ca.y, cg.x, cg.y)
	var hb := _heuristic(cb.x, cb.y, cg.x, cg.y)
	if ha != hb:
		return ha < hb
	if _tie[a] != _tie[b]:
		return _tie[a] < _tie[b]
	return a < b


func _heap_push(v: int) -> void:
	_heap.append(v)
	var i := _heap.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if _heap_less(_heap[i], _heap[p]):
			var t := _heap[i]
			_heap[i] = _heap[p]
			_heap[p] = t
			i = p
		else:
			break


func _heap_pop() -> int:
	var top: int = _heap[0]
	var last: int = _heap.pop_back()
	if not _heap.is_empty():
		_heap[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < _heap.size() and _heap_less(_heap[l], _heap[m]):
				m = l
			if r < _heap.size() and _heap_less(_heap[r], _heap[m]):
				m = r
			if m == i:
				break
			var t := _heap[i]
			_heap[i] = _heap[m]
			_heap[m] = t
			i = m
	return top


func find_path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not is_walkable(from.x, from.y) or not is_walkable(to.x, to.y):
		return out
	var start := idx_of(from.x, from.y)
	var goal := idx_of(to.x, to.y)
	if start == goal:
		out.append(from)
		return out
	_gen_cur += 1
	if _gen_cur > 1000000000:
		_gen.fill(0)
		_gen_cur = 1
	_goal_idx = goal
	_heap.clear()
	_g[start] = 0.0
	_came[start] = -1
	_gen[start] = _gen_cur
	_state[start] = 1
	_heap_push(start)
	var found := false
	var guard := GRID_W * GRID_H + 1
	while not _heap.is_empty() and guard > 0:
		guard -= 1
		var cur: int = _heap_pop()
		if _gen[cur] != _gen_cur or _state[cur] == 2:
			continue # duplicado stale del heap lazy
		_state[cur] = 2
		if cur == goal:
			found = true
			break
		var cx := cur % GRID_W
		var cy := cur / GRID_W
		for d in DIRS:
			var nx := cx + d.x
			var ny := cy + d.y
			if not is_walkable(nx, ny):
				continue
			if d.x != 0 and d.y != 0:
				# Sin cortar esquinas: ambas ortogonales adyacentes libres.
				if not is_walkable(cx + d.x, cy) or not is_walkable(cx, cy + d.y):
					continue
			var ni := ny * GRID_W + nx
			var step := terrain_cost(nx, ny) * (COST_DIAG if (d.x != 0 and d.y != 0) else 1.0)
			var ng := _g[cur] + step
			if _gen[ni] != _gen_cur or ng < _g[ni] - 0.000001:
				_g[ni] = ng
				_came[ni] = cur
				_gen[ni] = _gen_cur
				_state[ni] = 1
				_heap_push(ni)
	if not found:
		return out
	# Reconstruir de goal a start y revertir.
	var rev: Array[int] = []
	var c := goal
	while c != -1:
		rev.append(c)
		if c == start:
			break
		c = _came[c] if _gen[c] == _gen_cur else -1
	for i in range(rev.size() - 1, -1, -1):
		out.append(cell_of(rev[i]))
	return out


# --- Suavizado ---

func has_los(a: Vector2i, b: Vector2i) -> bool:
	# Bresenham: toda celda pisada debe ser caminable; en pasos
	# diagonales se exige la misma regla de no cortar esquinas.
	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	var px := x0
	var py := y0
	if not is_walkable(px, py):
		return false
	while not (px == x1 and py == y1):
		var e2 := err * 2
		var nx := px
		var ny := py
		if e2 > -dy:
			err -= dy
			nx += sx
		if e2 < dx:
			err += dx
			ny += sy
		if nx != px and ny != py:
			if not is_walkable(nx, py) or not is_walkable(px, ny):
				return false
		if not is_walkable(nx, ny):
			return false
		px = nx
		py = ny
	return true


func smooth_path(path: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if path.size() < 3:
		return path.duplicate() if path.size() > 0 else out
	out.append(path[0])
	var anchor := 0
	for i in range(1, path.size()):
		if not has_los(path[anchor], path[i]):
			out.append(path[i - 1])
			anchor = i - 1
	out.append(path[path.size() - 1])
	return out


func find_path_smooth(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	return smooth_path(find_path(from, to))

extends RefCounted
## A* determinista sobre Grid con costos enteros (10 recto, 14 diagonal).
## No corta esquinas. Si el objetivo no es alcanzable, va a la casilla
## expandida más cercana a él.

const STRAIGHT := 10
const DIAG := 14
const MAX_EXPANSIONS := 30000
const INF_COST := 0x3FFFFFFF
const IDX_BITS := 20
const H_BITS := 22
const IDX_MASK := (1 << IDX_BITS) - 1
const H_MASK := (1 << H_BITS) - 1
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


static func find_path(grid, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not grid.in_bounds(start):
		return out
	var target := nearest_walkable(grid, goal, _start_region(grid, start))
	if target == Vector2i(-1, -1) or target == start:
		return out
	var w: int = grid.width
	var hgt: int = grid.height
	var n := w * hgt
	var blocked: PackedByteArray = grid.cells()
	var sidx := start.y * w + start.x
	var tidx := target.y * w + target.x
	var g := PackedInt32Array()
	g.resize(n)
	g.fill(INF_COST)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	# Heap binario de claves enteras (f, h, idx) empaquetadas: mismo orden
	# lexicográfico que antes, sin arrays por nodo.
	var heap := PackedInt64Array()
	var h0 := _h(start, target)
	g[sidx] = 0
	heap.append(_key(h0, h0, sidx))
	var best := sidx
	var best_h := h0
	var expansions := 0
	while heap.size() > 0:
		var k: int = heap[0]
		var last: int = heap[heap.size() - 1]
		heap.resize(heap.size() - 1)
		var hn := heap.size()
		if hn > 0:
			var i := 0
			while true:
				var l := 2 * i + 1
				if l >= hn:
					break
				var m := l
				if l + 1 < hn and heap[l + 1] < heap[l]:
					m = l + 1
				if heap[m] >= last:
					break
				heap[i] = heap[m]
				i = m
			heap[i] = last
		var ci := k & IDX_MASK
		if closed[ci] == 1:
			continue
		closed[ci] = 1
		if ci == tidx:
			best = ci
			break
		var ch := (k >> IDX_BITS) & H_MASK
		if ch < best_h:
			best_h = ch
			best = ci
		expansions += 1
		if expansions > MAX_EXPANSIONS:
			break
		var cx := ci % w
		var cy := ci / w
		for d in DIRS:
			var nx := cx + d.x
			var ny := cy + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= hgt:
				continue
			var ni := ny * w + nx
			if blocked[ni] != 0 or closed[ni] == 1:
				continue
			var diag := d.x != 0 and d.y != 0
			if diag and (blocked[cy * w + nx] != 0 or blocked[ny * w + cx] != 0):
				continue
			var ng := g[ci] + (DIAG if diag else STRAIGHT)
			if ng < g[ni]:
				g[ni] = ng
				parent[ni] = ci
				var hh := _h(Vector2i(nx, ny), target)
				var nk := _key(ng + hh, hh, ni)
				var j := heap.size()
				heap.append(nk)
				while j > 0:
					var pj := (j - 1) / 2
					if heap[pj] <= nk:
						break
					heap[j] = heap[pj]
					j = pj
				heap[j] = nk
	var node := best
	while node != sidx:
		out.push_front(Vector2i(node % w, node / w))
		node = parent[node]
	return out


static func _key(f: int, h: int, idx: int) -> int:
	return (f << (IDX_BITS + H_BITS)) | (h << IDX_BITS) | idx


## Región desde la que parte la unidad (si la casilla de inicio está
## bloqueada, la del primer vecino caminable). -1 = sin restricción.
static func _start_region(grid, start: Vector2i) -> int:
	var r: int = grid.region_of(start)
	if r >= 0:
		return r
	for d in DIRS:
		r = grid.region_of(start + d)
		if r >= 0:
			return r
	return -1


## Casilla caminable más cercana a goal (goal recortado al mapa); con
## region >= 0 solo acepta casillas de esa región (destino alcanzable).
## (-1,-1) si no hay.
static func nearest_walkable(grid, goal: Vector2i, region: int = -1) -> Vector2i:
	var c: Vector2i = grid.clamp_tile(goal)
	if grid.is_walkable(c) and (region < 0 or grid.region_of(c) == region):
		return c
	var max_r: int = maxi(grid.width, grid.height)
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_key := []
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				if maxi(absi(x - c.x), absi(y - c.y)) != r:
					continue
				var p := Vector2i(x, y)
				if not grid.is_walkable(p) or (region >= 0 and grid.region_of(p) != region):
					continue
				var key := [(x - c.x) * (x - c.x) + (y - c.y) * (y - c.y), y, x]
				if best_key.is_empty() or _less(key, best_key):
					best_key = key
					best = p
		if best != Vector2i(-1, -1):
			return best
	return Vector2i(-1, -1)


static func _h(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return STRAIGHT * (dx + dy) + (DIAG - 2 * STRAIGHT) * mini(dx, dy)


static func _less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false

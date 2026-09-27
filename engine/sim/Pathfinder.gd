extends RefCounted
## A* determinista sobre Grid con costos enteros (10 recto, 14 diagonal).
## No corta esquinas. Si el objetivo no es alcanzable, va a la casilla
## expandida más cercana a él.

const STRAIGHT := 10
const DIAG := 14
const MAX_EXPANSIONS := 30000
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


static func find_path(grid, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not grid.in_bounds(start):
		return out
	var target := nearest_walkable(grid, goal)
	if target == Vector2i(-1, -1) or target == start:
		return out
	var w: int = grid.width
	var sidx := start.y * w + start.x
	var tidx := target.y * w + target.x
	var g := {sidx: 0}
	var parent := {}
	var closed := {}
	var heap: Array = []
	var h0 := _h(start, target)
	_push(heap, [h0, h0, sidx])
	var best := sidx
	var best_h := h0
	var expansions := 0
	while not heap.is_empty():
		var cur: Array = _pop(heap)
		var ci: int = cur[2]
		if closed.has(ci):
			continue
		closed[ci] = true
		if ci == tidx:
			best = ci
			break
		if cur[1] < best_h:
			best_h = cur[1]
			best = ci
		expansions += 1
		if expansions > MAX_EXPANSIONS:
			break
		var c := Vector2i(ci % w, ci / w)
		for d in DIRS:
			var n: Vector2i = c + d
			if not grid.is_walkable(n):
				continue
			var diag := d.x != 0 and d.y != 0
			if diag and (not grid.is_walkable(Vector2i(c.x + d.x, c.y)) or not grid.is_walkable(Vector2i(c.x, c.y + d.y))):
				continue
			var ni := n.y * w + n.x
			if closed.has(ni):
				continue
			var ng: int = g[ci] + (DIAG if diag else STRAIGHT)
			if not g.has(ni) or ng < g[ni]:
				g[ni] = ng
				parent[ni] = ci
				var h := _h(n, target)
				_push(heap, [ng + h, h, ni])
	var node := best
	while node != sidx:
		out.push_front(Vector2i(node % w, node / w))
		node = parent[node]
	return out


## Casilla caminable más cercana a goal (goal recortado al mapa). (-1,-1) si no hay.
static func nearest_walkable(grid, goal: Vector2i) -> Vector2i:
	var c: Vector2i = grid.clamp_tile(goal)
	if grid.is_walkable(c):
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
				if not grid.is_walkable(p):
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


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if not _less(heap[i], heap[p]):
			break
		var tmp: Array = heap[i]
		heap[i] = heap[p]
		heap[p] = tmp
		i = p


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	var n := heap.size()
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < n and _less(heap[l], heap[m]):
			m = l
		if r < n and _less(heap[r], heap[m]):
			m = r
		if m == i:
			break
		var tmp: Array = heap[i]
		heap[i] = heap[m]
		heap[m] = tmp
		i = m
	return top

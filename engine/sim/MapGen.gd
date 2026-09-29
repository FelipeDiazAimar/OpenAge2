extends RefCounted
## Generación determinista de recursos (estilo Arabia): por jugador, oro,
## piedra, bayas y un bosque cercano; además bosques y minas sueltas por el
## mapa. Deja un claro alrededor de cada centro urbano.

const Rng := preload("res://engine/sim/Rng.gd")
const Grid := preload("res://engine/sim/Grid.gd")

const CLEAR_R := 7
const PER_PLAYER := [["gold_mine", 10, 7], ["stone_mine", 11, 5], ["berry_bush", 9, 6], ["tree", 15, 45]]
## Animales por jugador: [id, distancia, cantidad, propio]. AoE2: 4 ovejas
## propias junto al TC, 2 jabalíes y una manada de ciervos más lejos.
const ANIMALS := [["sheep", 5, 4, true], ["boar", 15, 2, false], ["deer", 19, 4, false]]
const FORESTS := 16
const LOOSE_GOLD := 6
const LOOSE_STONE := 4
const LOOSE_MIN_DIST := 20 # minas sueltas lejos de los inicios (como Arabia)
const RELICS := 5 # reliquias lejos de los inicios
## Lago en el centro del mapa (muelles y pesca) con peces de orilla y de altamar.
const LAKE_R := 7
const SHORE_FISH := 6
const DEEP_FISH := 4


static func generate(sim, p_seed: int, starts: Array[Vector2i], lake: bool = true) -> void:
	var rng := Rng.new(p_seed)
	# El azar de la partida (conversiones) sale de la semilla del mapa.
	sim.rng = Rng.new(p_seed ^ 0x5EED1234)
	if lake:
		_lake(sim, rng, Vector2i(sim.grid.width / 2, sim.grid.height / 2), LAKE_R, starts)
	var reserved := {}
	for s in starts:
		for dy in range(-CLEAR_R - 1, CLEAR_R + 2):
			for dx in range(-CLEAR_R - 1, CLEAR_R + 2):
				reserved[s + Vector2i(dx, dy)] = true
	for s in starts:
		for spec in PER_PLAYER:
			_cluster(sim, rng, reserved, s, int(spec[1]), str(spec[0]), int(spec[2]))
	var w: int = sim.grid.width
	var h: int = sim.grid.height
	for i in FORESTS:
		_blob(sim, rng, reserved, Vector2i(rng.range_i(3, w - 4), rng.range_i(3, h - 4)), "tree", rng.range_i(30, 70))
	for spec in [["gold_mine", LOOSE_GOLD], ["stone_mine", LOOSE_STONE]]:
		for i in int(spec[1]):
			var t := Vector2i(rng.range_i(5, w - 6), rng.range_i(5, h - 6))
			if _far_from_starts(t, starts):
				_blob(sim, rng, reserved, t, str(spec[0]), 4)
	# Animales al final (no bloquean casillas; así no quedan bajo árboles).
	var used := {}
	for i in starts.size():
		for spec in ANIMALS:
			var owner := i if bool(spec[3]) else -1
			_herd(sim, rng, used, starts[i], int(spec[1]), str(spec[0]), int(spec[2]), owner)
	var placed := 0
	for attempt in 400:
		if placed >= RELICS:
			break
		var t := Vector2i(rng.range_i(4, w - 5), rng.range_i(4, h - 5))
		if used.has(t) or not sim.grid.is_walkable(t) or not _far_from_starts(t, starts):
			continue
		if sim.spawn("reliquia", -1, t) >= 0:
			used[t] = true
			placed += 1


## Lago circular de radio r en c; peces de orilla junto a la costa y de
## altamar en el centro. Va antes que el resto: nada de tierra cae en el agua.
static func _lake(sim, rng, c: Vector2i, r: int, starts: Array[Vector2i]) -> void:
	var g = sim.grid
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			var t := Vector2i(x, y)
			var d := t - c
			if d.x * d.x + d.y * d.y > r * r or not _far_from_starts(t, starts, CLEAR_R + 2):
				continue # nunca en el claro de un inicio
			if sim.world.spatial.query_radius(Grid.center_of(t), 700).size() > 0:
				continue # ni bajo unidades o edificios ya colocados
			g.set_water(t)
	var shore: Array[Vector2i] = []
	var deep: Array[Vector2i] = []
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			var t := Vector2i(x, y)
			if not g.is_water(t):
				continue
			var coast := false
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				coast = coast or (g.in_bounds(t + n) and not g.is_water(t + n))
			var d := t - c
			if coast:
				shore.append(t)
			elif d.x * d.x + d.y * d.y <= (r - 3) * (r - 3):
				deep.append(t)
	for spec in [[shore, "shore_fish", SHORE_FISH], [deep, "deep_fish", DEEP_FISH]]:
		var tiles: Array = spec[0]
		for i in int(spec[2]):
			if tiles.is_empty():
				break
			var t: Vector2i = tiles[rng.range_i(0, tiles.size() - 1)]
			tiles.erase(t)
			sim.spawn(str(spec[1]), -1, t)


## Grupo de n animales alrededor de un punto a `dist` casillas de c (±2).
static func _herd(sim, rng, used: Dictionary, c: Vector2i, dist: int, def_id: String, n: int, owner: int) -> void:
	var g = sim.grid
	var placed := 0
	for attempt in 30:
		var t: int = rng.range_i(-dist, dist)
		var anchor: Vector2i
		match rng.range_i(0, 3):
			0:
				anchor = c + Vector2i(t, -dist)
			1:
				anchor = c + Vector2i(dist, t)
			2:
				anchor = c + Vector2i(t, dist)
			_:
				anchor = c + Vector2i(-dist, t)
		if not g.is_walkable(anchor):
			continue
		for k in 40:
			if placed >= n:
				break
			var spread := 1 if dist <= 6 else 2
			var tile := anchor + Vector2i(rng.range_i(-spread, spread), rng.range_i(-spread, spread))
			if used.has(tile) or not g.is_walkable(tile):
				continue
			if sim.spawn(def_id, owner, tile) >= 0:
				used[tile] = true
				placed += 1
		if placed >= n:
			return # si el ancla quedó junto a un bosque, se completa con otra


static func _far_from_starts(t: Vector2i, starts: Array[Vector2i], min_dist: int = LOOSE_MIN_DIST) -> bool:
	for s in starts:
		if maxi(absi(t.x - s.x), absi(t.y - s.y)) < min_dist:
			return false
	return true


## Grupo de n recursos cuyo núcleo está a `dist` casillas (Chebyshev) de c.
static func _cluster(sim, rng, reserved: Dictionary, c: Vector2i, dist: int, def_id: String, n: int) -> void:
	for attempt in 24:
		var t: int = rng.range_i(-dist, dist)
		var seed_tile: Vector2i
		match rng.range_i(0, 3):
			0:
				seed_tile = c + Vector2i(t, -dist)
			1:
				seed_tile = c + Vector2i(dist, t)
			2:
				seed_tile = c + Vector2i(t, dist)
			_:
				seed_tile = c + Vector2i(-dist, t)
		if _can_place(sim, reserved, seed_tile):
			_blob(sim, rng, reserved, seed_tile, def_id, n)
			return


## Crecimiento desde seed_tile hasta colocar n recursos. Los bosques crecen
## al azar (formas orgánicas); minas y bayas eligen la casilla libre más
## cercana a la semilla (montón compacto, como en AoE2).
static func _blob(sim, rng, reserved: Dictionary, seed_tile: Vector2i, def_id: String, n: int) -> int:
	var compact := def_id != "tree"
	var frontier: Array[Vector2i] = [seed_tile]
	var queued := {seed_tile: true}
	var placed := 0
	while placed < n and not frontier.is_empty():
		var i: int = _closest_index(rng, frontier, seed_tile) if compact else rng.range_i(0, frontier.size() - 1)
		var t: Vector2i = frontier[i]
		frontier.remove_at(i)
		if not _can_place(sim, reserved, t):
			continue
		sim.spawn(def_id, -1, t)
		placed += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nt: Vector2i = t + d
			if not queued.has(nt):
				queued[nt] = true
				frontier.append(nt)
	return placed


## Índice del elemento de la frontera más cercano a c (empates al azar).
static func _closest_index(rng, frontier: Array[Vector2i], c: Vector2i) -> int:
	var best_d := -1
	var ties: Array[int] = []
	for i in frontier.size():
		var d: Vector2i = frontier[i] - c
		var dd := d.x * d.x + d.y * d.y
		if best_d < 0 or dd < best_d:
			best_d = dd
			ties = [i]
		elif dd == best_d:
			ties.append(i)
	return ties[rng.range_i(0, ties.size() - 1)]


static func _can_place(sim, reserved: Dictionary, t: Vector2i) -> bool:
	var g = sim.grid
	if t.x < 1 or t.y < 1 or t.x >= g.width - 1 or t.y >= g.height - 1:
		return false
	return not reserved.has(t) and g.is_walkable(t)

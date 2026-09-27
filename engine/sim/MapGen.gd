extends RefCounted
## Generación determinista de recursos (estilo Arabia): por jugador, oro,
## piedra, bayas y un bosque cercano; además bosques y minas sueltas por el
## mapa. Deja un claro alrededor de cada centro urbano.

const Rng := preload("res://engine/sim/Rng.gd")

const CLEAR_R := 7
const PER_PLAYER := [["gold_mine", 10, 7], ["stone_mine", 11, 5], ["berry_bush", 9, 6], ["tree", 15, 45]]
const FORESTS := 16
const LOOSE_GOLD := 6
const LOOSE_STONE := 4


static func generate(sim, p_seed: int, starts: Array[Vector2i]) -> void:
	var rng := Rng.new(p_seed)
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
	for i in LOOSE_GOLD:
		_blob(sim, rng, reserved, Vector2i(rng.range_i(5, w - 6), rng.range_i(5, h - 6)), "gold_mine", 4)
	for i in LOOSE_STONE:
		_blob(sim, rng, reserved, Vector2i(rng.range_i(5, w - 6), rng.range_i(5, h - 6)), "stone_mine", 4)


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


## Crecimiento aleatorio desde seed_tile hasta colocar n recursos.
static func _blob(sim, rng, reserved: Dictionary, seed_tile: Vector2i, def_id: String, n: int) -> int:
	var frontier: Array[Vector2i] = [seed_tile]
	var queued := {seed_tile: true}
	var placed := 0
	while placed < n and not frontier.is_empty():
		var i: int = rng.range_i(0, frontier.size() - 1)
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


static func _can_place(sim, reserved: Dictionary, t: Vector2i) -> bool:
	var g = sim.grid
	if t.x < 1 or t.y < 1 or t.x >= g.width - 1 or t.y >= g.height - 1:
		return false
	return not reserved.has(t) and g.is_walkable(t)

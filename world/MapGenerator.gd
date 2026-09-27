extends RefCounted
class_name MapGenerator
## world/MapGenerator.gd — Generador determinista de mapas (lógica, SÍ afecta a la sim).
##
## Mapas: Arabia (abierto), Arena (murallas), Islas (agua + pesca), Bosque Negro (denso).
## Tamaño fijo 144x144 (igual que data/maps/arabia.json).
## - TCs equidistantes en anillo (1..8 jugadores, fair por construcción).
## - Recursos balanceados por jugador: 8 madera, 6 oro, 4 piedra, 4 bayas,
##   2 jabalíes (cantidades de data/maps/resource_defs.json) + 5 reliquias al centro.
## - Islas añade 6 bancos de pesca (shore_fish, infinitos) por jugador.
## - Determinista lockstep: TODA la aleatoriedad sale de SimRNG (core/SimRNG.gd).
##   PROHIBIDO randf()/randi()/RandomNumberGenerator/Time aquí.
## API:
##   var m := MapGenerator.generate("arabia", 1234, 8)  # -> {terrain, resources, spawns, ...}
##   MapGenerator.save_map(m, "res://data/maps/generated_arabia_1234.json")
## Formato:
##   terrain: Array[144] de Array[144] int (y=tile_y, x=tile_x). Leyenda en T_*.
##   resources: Array de {type:String, pos:Vector2i, amount:int}.
##   spawns: Array de Vector2i (TC del jugador i en spawns[i]).

const MAP_W := 144
const MAP_H := 144
const CX := 72
const CY := 72
const SPAWN_R := 50.0
const SPAWN_MARGIN := 14
const RELICS_CENTER := 5

# Leyenda de terrain (int, serializable a JSON).
const T_GRASS := 0    # hierba, transitable
const T_DESERT := 1   # desierto/hierba seca (arabia), transitable
const T_FOREST := 2   # suelo de bosque, transitable (bloquea visión, no paso)
const T_WATER := 3    # agua profunda, NO transitable
const T_SHALLOW := 4  # vado/costa: transitable + pesca (puentes de Islas)
const T_WALL := 5     # muralla de piedra (Arena), NO transitable

# Balance por jugador (arabia.json: wood 8, gold 6, stone 4, forage 4, boars 2).
const N_WOOD := 8
const N_GOLD := 6
const N_STONE := 4
const N_BERRY := 4
const N_BOAR := 2
const N_FISH_ISLAS := 6  # bancos de pesca extra por jugador en Islas

# Cantidades por nodo (espejo de data/maps/resource_defs.json).
const AMT_TREE := 100
const AMT_BERRY := 125
const AMT_BOAR := 340
const AMT_GOLD := 800
const AMT_STONE := 800
const AMT_FISH := -1  # infinito, como shore_fish
const AMT_RELIC := 1

const CTRL_STEP := 12  # rejilla de ruido gruesa cada 12 tiles (13x13)


# ------------------------------------------------------------------ API --
static func generate(p_map_name: String, p_seed: int, p_num_players: int) -> Dictionary:
	var map_id := normalise_map_name(p_map_name)
	var n := clampi(p_num_players, 1, 8)
	var rng := SimRNG.new()
	rng.set_seed(int((p_seed ^ _salt_for(map_id)) & 0xFFFFFFFF))
	var spawns := _gen_spawns(rng, n)
	var terrain := _gen_terrain(map_id, rng, spawns)
	var resources := _gen_resources(map_id, rng, terrain, spawns)
	var walls := _collect_walls(terrain)
	rng.free()
	return {
		"map": map_id,
		"seed": p_seed,
		"w": MAP_W,
		"h": MAP_H,
		"terrain": terrain,
		"resources": resources,
		"spawns": spawns,
		"walls": walls,
		"legend": {"0": "grass", "1": "desert", "2": "forest", "3": "water", "4": "shallow", "5": "wall"},
	}


static func generate_and_save(p_map_name: String, p_seed: int, p_num_players: int, p_path: String = "") -> Dictionary:
	var result := generate(p_map_name, p_seed, p_num_players)
	var path := p_path
	if path.is_empty():
		path = "res://data/maps/generated_%s_%d.json" % [String(result["map"]), p_seed]
	save_map(result, path)
	return result


## Serializa a JSON (Vector2i -> [x, y]) y escribe en path. Devuelve true si OK.
static func save_map(p_result: Dictionary, p_path: String) -> bool:
	var serial := {
		"map": String(p_result.get("map", "arabia")),
		"seed": int(p_result.get("seed", 0)),
		"w": MAP_W,
		"h": MAP_H,
		"legend": p_result.get("legend", {}),
		"terrain": p_result.get("terrain", []),
		"resources": [],
		"spawns": [],
		"walls": [],
	}
	for r in p_result.get("resources", []):
		var pos: Vector2i = r["pos"]
		serial["resources"].append({"type": String(r["type"]), "pos": [pos.x, pos.y], "amount": int(r["amount"])})
	for s in p_result.get("spawns", []):
		var sp: Vector2i = s
		serial["spawns"].append([sp.x, sp.y])
	for wpos in p_result.get("walls", []):
		var wp: Vector2i = wpos
		serial["walls"].append([wp.x, wp.y])
	var f := FileAccess.open(p_path, FileAccess.WRITE)
	if f == null:
		push_error("[MapGenerator] no se pudo escribir %s" % p_path)
		return false
	f.store_string(JSON.stringify(serial, "  "))
	f.close()
	return true


static func normalise_map_name(p_name: String) -> String:
	var k := p_name.to_lower().strip_edges().replace(" ", "_")
	match k:
		"arena":
			return "arena"
		"isla", "islas", "island", "islands", "agua":
			return "islas"
		"bosque", "bosque_negro", "bosquenegro", "black_forest", "blackforest", "negro":
			return "bosque_negro"
		_:
			return "arabia"


static func _salt_for(p_map_id: String) -> int:
	match p_map_id:
		"arena":
			return 0xA2E9A1
		"islas":
			return 0x15A45
		"bosque_negro":
			return 0xB05C4E
		_:
			return 0xA6AB1A


# ---------------------------------------------------------------- spawns --
## TCs equidistantes en anillo de radio SPAWN_R. 1 draw de RNG (offset angular).
static func _gen_spawns(rng: SimRNG, n: int) -> Array:
	var out: Array = []
	var a0: float = rng.next_float() * TAU
	for i in n:
		var a: float = a0 + TAU * float(i) / float(n)
		var x := int(round(float(CX) + cos(a) * SPAWN_R))
		var y := int(round(float(CY) + sin(a) * SPAWN_R))
		out.append(Vector2i(clampi(x, SPAWN_MARGIN, MAP_W - 1 - SPAWN_MARGIN), clampi(y, SPAWN_MARGIN, MAP_H - 1 - SPAWN_MARGIN)))
	return out


# ---------------------------------------------------------------- terreno --
static func _gen_terrain(p_map_id: String, rng: SimRNG, spawns: Array) -> Array:
	# Dos rejillas gruesas de ruido (orden fijo de draws: primero altura, luego parche).
	var ctrl_n := MAP_W / CTRL_STEP + 1  # 13
	var grid_h: PackedFloat32Array = PackedFloat32Array()
	var grid_p: PackedFloat32Array = PackedFloat32Array()
	grid_h.resize(ctrl_n * ctrl_n)
	grid_p.resize(ctrl_n * ctrl_n)
	for i in grid_h.size():
		grid_h[i] = rng.next_float()
	for i in grid_p.size():
		grid_p[i] = rng.next_float()

	# Centros de bosquete por mapa (draws en orden fijo).
	var groves: Array = []  # Array de [Vector2(float), radio]
	match p_map_id:
		"arabia":
			for i in 10:
				groves.append([Vector2(rng.next_float_range(10.0, 134.0), rng.next_float_range(10.0, 134.0)), 9.0])
		"arena":
			for i in 8:
				groves.append([Vector2(rng.next_float_range(14.0, 130.0), rng.next_float_range(14.0, 130.0)), 8.0])
		"islas":
			for s in spawns:
				var sp: Vector2i = s
				for i in 2:
					groves.append([Vector2(sp) + Vector2(rng.next_float_range(-10.0, 10.0), rng.next_float_range(-10.0, 10.0)), 7.0])
		_:
			pass  # bosque_negro no usa bosquetes (relleno total)

	var terrain: Array = []
	if p_map_id == "islas":
		for y in MAP_H:
			var row := PackedInt32Array()
			row.resize(MAP_W)
			row.fill(T_WATER)
			terrain.append(Array(row))
	else:
		var forest_p := 0.55 if p_map_id == "bosque_negro" else 0.75
		for y in MAP_H:
			var row: Array = []
			row.resize(MAP_W)
			for x in MAP_W:
				var patch: float = _sample_noise(grid_p, ctrl_n, float(x) + 61.0, float(y) + 37.0)
				var base := T_GRASS if patch > 0.45 else T_DESERT
				if p_map_id == "bosque_negro":
					base = T_FOREST
				elif _inside_grove(groves, x, y) and rng.next_float() < forest_p:
					base = T_FOREST
				row[x] = base
			terrain.append(row)

	match p_map_id:
		"arena":
			_carve_arena_walls(terrain, spawns)
		"islas":
			_carve_islands(terrain, spawns)
		"bosque_negro":
			_carve_blackforest_clearings(terrain, spawns)
		_:
			# Arabia abierto: solo garantiza TCs sobre hierba (radio 4).
			for s in spawns:
				_stamp_circle(terrain, s, 4.0, T_GRASS)
			_stamp_circle(terrain, Vector2i(CX, CY), 6.0, T_GRASS)
	return terrain


static func _sample_noise(grid: PackedFloat32Array, n: int, fx: float, fz: float) -> float:
	var gx: float = clampf(fx / float(CTRL_STEP), 0.0, float(n - 1) - 0.001)
	var gz: float = clampf(fz / float(CTRL_STEP), 0.0, float(n - 1) - 0.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var tx := _smoother(gx - float(x0))
	var tz := _smoother(gz - float(z0))
	var a: float = grid[z0 * n + x0]
	var b: float = grid[z0 * n + x0 + 1]
	var c: float = grid[(z0 + 1) * n + x0]
	var d: float = grid[(z0 + 1) * n + x0 + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


static func _smoother(t: float) -> float:
	var t2: float = clampf(t, 0.0, 1.0)
	return t2 * t2 * t2 * (t2 * (t2 * 6.0 - 15.0) + 10.0)


static func _inside_grove(groves: Array, x: int, y: int) -> bool:
	for g in groves:
		var c: Vector2 = g[0]
		var r: float = g[1]
		var dx := float(x) - c.x
		var dy := float(y) - c.y
		if dx * dx + dy * dy <= r * r:
			return true
	return false


## Arena: anillo de muralla 13x13 por TC con 1 puerta hacia el centro.
static func _carve_arena_walls(terrain: Array, spawns: Array) -> void:
	var half := 6
	for s in spawns:
		var sp: Vector2i = s
		# Interior limpio a hierba.
		for dy in range(-half + 1, half):
			for dx in range(-half + 1, half):
				_set_tile(terrain, sp.x + dx, sp.y + dy, T_GRASS)
		# Puerta: lado del muro que mira al centro.
		var to_c := Vector2(CX - sp.x, CY - sp.y)
		var gate := Vector2i(sp.x + half * signi(to_c.x), sp.y) if absf(to_c.x) > absf(to_c.y) else Vector2i(sp.x, sp.y + half * signi(to_c.y))
		for dy in range(-half, half + 1):
			for dx in range(-half, half + 1):
				if absi(dx) == half or absi(dy) == half:
					var p := Vector2i(sp.x + dx, sp.y + dy)
					if p == gate:
						_set_tile(terrain, p.x, p.y, T_GRASS)
					else:
						_set_tile(terrain, p.x, p.y, T_WALL)


## Islas: isla circular (r=18) por spawn + isla central (r=15), anillo
## shallow (r 18..22) para pesca y 2 vados-puente (ancho 3) hacia el centro.
static func _carve_islands(terrain: Array, spawns: Array) -> void:
	for s in spawns:
		var sp: Vector2i = s
		_stamp_circle(terrain, sp, 18.0, T_GRASS)
		_stamp_ring(terrain, sp, 18.0, 22.0, T_SHALLOW)
		_stamp_causeway(terrain, sp, Vector2i(CX, CY), 1)  # vado principal
		_stamp_causeway(terrain, sp, Vector2i(CX, CY), -1)  # vado secundario (offset)
	_stamp_circle(terrain, Vector2i(CX, CY), 15.0, T_GRASS)
	_stamp_ring(terrain, Vector2i(CX, CY), 15.0, 18.0, T_SHALLOW)


## Bosque Negro: todo bosque salvo claros en TCs (r=11), centro (r=14)
## y caminos (ancho 3) de cada TC al centro.
static func _carve_blackforest_clearings(terrain: Array, spawns: Array) -> void:
	for s in spawns:
		var sp: Vector2i = s
		_stamp_circle(terrain, sp, 11.0, T_GRASS)
		_stamp_causeway(terrain, sp, Vector2i(CX, CY), 0, T_GRASS)
	_stamp_circle(terrain, Vector2i(CX, CY), 14.0, T_GRASS)


static func _stamp_circle(terrain: Array, c: Vector2i, r: float, tile: int) -> void:
	var r2 := r * r
	for dy in range(-int(ceil(r)) - 1, int(ceil(r)) + 2):
		for dx in range(-int(ceil(r)) - 1, int(ceil(r)) + 2):
			if float(dx * dx + dy * dy) <= r2:
				_set_tile(terrain, c.x + dx, c.y + dy, tile)


static func _stamp_ring(terrain: Array, c: Vector2i, r0: float, r1: float, tile: int) -> void:
	var rr := int(ceil(r1)) + 1
	for dy in range(-rr, rr + 1):
		for dx in range(-rr, rr + 1):
			var d := sqrt(float(dx * dx + dy * dy))
			if d > r0 and d <= r1:
				var p := Vector2i(c.x + dx, c.y + dy)
				if _in_bounds(p.x, p.y) and int(terrain[p.y][p.x]) == T_WATER:
					terrain[p.y][p.x] = tile


## Vado-puente: línea de shallow (o tile dado) de `from` a `to`, desplazada
## lateralmente por `lane` (-1/0/1) para no solapar. Ancho 3.
static func _stamp_causeway(terrain: Array, from: Vector2i, to: Vector2i, lane: int, tile: int = T_SHALLOW) -> void:
	var dir := Vector2(to - from)
	var length := dir.length()
	if length < 1.0:
		return
	dir /= length
	var perp := Vector2(-dir.y, dir.x)
	var offset := perp * (float(lane) * 3.0)
	var steps := int(length)
	for i in range(1, steps):
		var base := Vector2(from) + dir * float(i) + offset
		for w in range(-1, 2):
			var p := Vector2i(int(round(base.x + perp.x * float(w))), int(round(base.y + perp.y * float(w))))
			if _in_bounds(p.x, p.y) and tile == T_SHALLOW and int(terrain[p.y][p.x]) != T_WATER:
				continue  # el vado solo pisa agua
			_set_tile(terrain, p.x, p.y, tile)


static func _collect_walls(terrain: Array) -> Array:
	var out: Array = []
	for y in MAP_H:
		for x in MAP_W:
			if int(terrain[y][x]) == T_WALL:
				out.append(Vector2i(x, y))
	return out


# --------------------------------------------------------------- recursos --
static func _gen_resources(p_map_id: String, rng: SimRNG, terrain: Array, spawns: Array) -> Array:
	var out: Array = []
	var occupied := {}  # "x,y" -> true
	for s in spawns:
		var sp: Vector2i = s
		_claim(occupied, sp, 2)  # huella del TC
		# Bayas muy cerca (3..5), jabalíes cerca (5..7).
		for i in N_BERRY:
			var p := _try_spot(rng, terrain, occupied, spawns, sp, 3.0, 5.0)
			_place(out, occupied, "berry_bush", p, AMT_BERRY)
		for i in N_BOAR:
			var p := _try_spot(rng, terrain, occupied, spawns, sp, 5.0, 7.0)
			_place(out, occupied, "boar", p, AMT_BOAR)
		# Madera en anillo medio (6..16).
		for i in N_WOOD:
			var p := _try_spot(rng, terrain, occupied, spawns, sp, 6.0, 16.0)
			_place(out, occupied, "tree", p, AMT_TREE)
		# Oro: 3 cerca (5..9) + 3 medio (14..24). Piedra: 2 cerca (6..10) + 2 medio (15..26).
		for i in 3:
			var p := _try_spot(rng, terrain, occupied, spawns, sp, 5.0, 9.0)
			_place(out, occupied, "gold_mine", p, AMT_GOLD)
		for i in 3:
			var p := _try_spot(rng, terrain, occupied, spawns, sp, 14.0, 24.0)
			_place(out, occupied, "gold_mine", p, AMT_GOLD)
		for i in 2:
			var p := _try_spot(rng, terrain, occupied, spawns, sp, 6.0, 10.0)
			_place(out, occupied, "stone_mine", p, AMT_STONE)
		for i in 2:
			var p := _try_spot(rng, terrain, occupied, spawns, sp, 15.0, 26.0)
			_place(out, occupied, "stone_mine", p, AMT_STONE)
		if p_map_id == "islas":
			for i in N_FISH_ISLAS:
				var p := _try_fish_spot(rng, terrain, occupied, sp, 26.0)
				_place(out, occupied, "shore_fish", p, AMT_FISH)
	# 5 reliquias al centro (4..18 del centro, orden fijo).
	for i in RELICS_CENTER:
		var p := _try_spot(rng, terrain, occupied, spawns, Vector2i(CX, CY), 4.0, 18.0)
		_place(out, occupied, "relic", p, AMT_RELIC)
	return out


static func _place(out: Array, occupied: Dictionary, type: String, p: Vector2i, amount: int) -> void:
	if p.x < 0:
		push_warning("[MapGenerator] sin sitio libre para %s (mapa saturado)" % type)
		return
	out.append({"type": type, "pos": p, "amount": amount})
	_claim(occupied, p, 1)


## 24 intentos con RNG (ángulo+radio) y fallback determinista por barrido.
static func _try_spot(rng: SimRNG, terrain: Array, occupied: Dictionary, spawns: Array, center: Vector2i, rmin: float, rmax: float) -> Vector2i:
	for t in 24:
		var a: float = rng.next_float() * TAU
		var r: float = rng.next_float_range(rmin, rmax)
		var p := Vector2i(int(round(float(center.x) + cos(a) * r)), int(round(float(center.y) + sin(a) * r)))
		if _spot_free(terrain, occupied, spawns, p):
			return p
	return _fallback_spot(terrain, occupied, spawns, center, rmin, rmax)


## Pesca: solo sobre shallow cerca de la isla del jugador.
static func _try_fish_spot(rng: SimRNG, terrain: Array, occupied: Dictionary, center: Vector2i, rmax: float) -> Vector2i:
	for t in 24:
		var a: float = rng.next_float() * TAU
		var r: float = rng.next_float_range(16.0, rmax)
		var p := Vector2i(int(round(float(center.x) + cos(a) * r)), int(round(float(center.y) + sin(a) * r)))
		if _in_bounds(p.x, p.y) and int(terrain[p.y][p.x]) == T_SHALLOW and not occupied.has(_key(p)):
			return p
	for dy in range(-int(rmax) - 1, int(rmax) + 2):
		for dx in range(-int(rmax) - 1, int(rmax) + 2):
			var p := Vector2i(center.x + dx, center.y + dy)
			if _in_bounds(p.x, p.y) and int(terrain[p.y][p.x]) == T_SHALLOW and not occupied.has(_key(p)):
				return p
	return Vector2i(-1, -1)


static func _fallback_spot(terrain: Array, occupied: Dictionary, spawns: Array, center: Vector2i, rmin: float, rmax: float) -> Vector2i:
	for r in range(int(rmin), int(rmax) + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue  # solo perímetro: barrido exterior determinista
				var p := Vector2i(center.x + dx, center.y + dy)
				if _spot_free(terrain, occupied, spawns, p):
					return p
	return Vector2i(-1, -1)


static func _spot_free(terrain: Array, occupied: Dictionary, spawns: Array, p: Vector2i) -> bool:
	if not _in_bounds(p.x, p.y, 2):
		return false
	if not _is_walkable(int(terrain[p.y][p.x])):
		return false
	if occupied.has(_key(p)):
		return false
	for s in spawns:
		var sp: Vector2i = s
		if absi(sp.x - p.x) + absi(sp.y - p.y) < 3:
			return false  # no pisar el TC
	return true


static func _claim(occupied: Dictionary, p: Vector2i, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			occupied[_key(Vector2i(p.x + dx, p.y + dy))] = true


# ------------------------------------------------------------------ utils --
static func _key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]


static func _in_bounds(x: int, y: int, margin: int = 0) -> bool:
	return x >= margin and y >= margin and x < MAP_W - margin and y < MAP_H - margin


static func _set_tile(terrain: Array, x: int, y: int, tile: int) -> void:
	if _in_bounds(x, y):
		terrain[y][x] = tile


static func _is_walkable(tile: int) -> bool:
	return tile == T_GRASS or tile == T_DESERT or tile == T_FOREST or tile == T_SHALLOW


static func signi(v: float) -> int:
	return 1 if v >= 0.0 else -1


## Auto-verify: misma (mapa, seed, jugadores) => mismo resultado; conteos por
## jugador y 5 reliquias. Llamar en boot: assert(MapGenerator.self_test()).
static func self_test() -> bool:
	for map_id in ["arabia", "arena", "islas", "bosque_negro"]:
		var a := generate(map_id, 1234, 8)
		var b := generate(map_id, 1234, 8)
		if JSON.stringify(_serialisable(a)) != JSON.stringify(_serialisable(b)):
			push_error("[MapGenerator] self_test FAIL no-determinista en %s" % map_id)
			return false
		var counts := count_resources(a)
		if int(counts.get("tree", 0)) != 64 or int(counts.get("gold_mine", 0)) != 48 \
				or int(counts.get("stone_mine", 0)) != 32 or int(counts.get("berry_bush", 0)) != 32 \
				or int(counts.get("boar", 0)) != 16 or int(counts.get("relic", 0)) != 5:
			push_error("[MapGenerator] self_test FAIL conteos en %s: %s" % [map_id, str(counts)])
			return false
		if (a["spawns"] as Array).size() != 8:
			push_error("[MapGenerator] self_test FAIL spawns en %s" % map_id)
			return false
		if map_id == "islas" and int(counts.get("shore_fish", 0)) != 48:
			push_error("[MapGenerator] self_test FAIL pesca en islas: %s" % str(counts))
			return false
	print("[MapGenerator] self_test OK 4 mapas x8p deterministas + conteos")
	return true


static func count_resources(p_result: Dictionary) -> Dictionary:
	var counts := {}
	for r in p_result.get("resources", []):
		var t := String(r["type"])
		counts[t] = int(counts.get(t, 0)) + 1
	return counts


static func _serialisable(p_result: Dictionary) -> Dictionary:
	var out := {
		"map": String(p_result["map"]),
		"terrain": p_result["terrain"],
		"resources": [],
		"spawns": [],
	}
	for r in p_result["resources"]:
		var pos: Vector2i = r["pos"]
		out["resources"].append([String(r["type"]), pos.x, pos.y])
	for s in p_result["spawns"]:
		var sp: Vector2i = s
		out["spawns"].append([sp.x, sp.y])
	return out

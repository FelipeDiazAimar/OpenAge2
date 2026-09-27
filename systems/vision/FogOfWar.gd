extends Node
class_name FogOfWar
## FogOfWar — niebla de guerra AoE2 para OpenAge-LAN (Godot 4.4, GDScript).
##
## Grid 144x144 por jugador con estados:
##   0 = no explorado (negro opaco)
##   1 = explorado pero oscurecido (memoria, se ve terreno atenuado)
##   2 = visible ahora mismo (sin atenuar)
##
## DETERMINISMO (lockstep 10 Hz):
##   - NADA de randf/Time aquí. Solo matemática entera.
##   - La sim llama a [method add_viewer] cada tick por cada unidad/edificio
##     con visión, y a [method rebuild_tick] cada tick; el rebuild real solo
##     ocurre cuando `tick % 5 == 0`, con iteración ordenada por player_id
##     y viewers ordenados por (x, y, radius). Mismo input = mismo grid.
##   - Las funciones `get_fog_*` / `make_*` con ImageTexture son SOLO CLIENTE
##     (minimapa/HUD). Nunca llamarlas dentro del tick de simulación ni en
##     servidor headless: rompen determinismo y gastan CPU.
##
## Uso típico en sim (servidor + todos los peers):
##   Fog.add_viewer(0, Vector2i(72, 72), 8)
##   Fog.rebuild_tick()  # o Fog.rebuild_tick(SimAPI.tick)
##   if Fog.is_visible(0, 73, 72): ...
##
## Uso típico solo cliente (minimapa/HUD):
##   var tex: ImageTexture = Fog.get_fog_texture(my_pid)

const GRID_W := 144
const GRID_H := 144
const GRID_SIZE := GRID_W * GRID_H # 20736
const REBUILD_EVERY := 5
const MAX_RADIUS := 72

enum Cell { UNEXPLORED = 0, EXPLORED = 1, VISIBLE = 2 }

## Overlay pensado para dibujarse ENCIMA del minimapa/terreno del HUD.
const COL_UNEXPLORED := Color(0, 0, 0, 1.0) # negro total
const COL_EXPLORED := Color(0, 0, 0, 0.55) # velo: se intuye terreno
const COL_VISIBLE := Color(0, 0, 0, 0.0) # transparente = visión total

## player_id -> PackedByteArray(GRID_SIZE) con valores Cell.
var _grids: Dictionary = {}
## player_id -> Array[Dictionary] {x:int, y:int, r:int}. Se re-registra cada tick.
var _viewers: Dictionary = {}
## Último tick en el que se reconstruyó (evita doble rebuild mismo tick).
var _last_rebuild_tick := -1

## Caché SOLO CLIENTE: player_id -> ImageTexture de 144x144.
var _fog_textures: Dictionary = {}


signal fog_rebuilt(tick: int)


# ---------------------------------------------------------------- sim helpers

static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < GRID_W and y < GRID_H


static func idx(x: int, y: int) -> int:
	return y * GRID_W + x


func _ensure_player(player_id: int) -> PackedByteArray:
	if not _grids.has(player_id):
		var g := PackedByteArray()
		g.resize(GRID_SIZE)
		g.fill(Cell.UNEXPLORED)
		_grids[player_id] = g
		_viewers[player_id] = []
	return _grids[player_id]


func reset_player(player_id: int) -> void:
	var g := PackedByteArray()
	g.resize(GRID_SIZE)
	g.fill(Cell.UNEXPLORED)
	_grids[player_id] = g
	_viewers[player_id] = []
	_fog_textures.erase(player_id)


func reset_all() -> void:
	_grids.clear()
	_viewers.clear()
	_fog_textures.clear()
	_last_rebuild_tick = -1


# ---------------------------------------------------------------- API sim

## Registra un observador. `pos` en COORDENADAS DE CELDA (0..143).
## Acepta Vector2i (celdas) o Vector2 (se trunca a celda con floor).
## `radius` en celdas (unidades AoE2 típicas: aldeano 4, explorador 8-10, edificio 6-8).
## Determinista: el orden de inserción no importa, rebuild ordena antes de pintar.
func add_viewer(player_id: int, pos, radius: int) -> void:
	_ensure_player(player_id)
	var cx := 0
	var cy := 0
	if pos is Vector2i:
		cx = pos.x
		cy = pos.y
	elif pos is Vector2:
		cx = int(floor(pos.x))
		cy = int(floor(pos.y))
	else:
		push_error("FogOfWar.add_viewer: pos debe ser Vector2i/Vector2, recibido %s" % typeof(pos))
		return
	var r := clampi(radius, 0, MAX_RADIUS)
	(_viewers[player_id] as Array).append({"x": cx, "y": cy, "r": r})


## Limpia los viewers de un jugador (llamar al inicio de cada tick antes de re-registrar).
func clear_viewers(player_id: int) -> void:
	_viewers[player_id] = []


## Limpia viewers de todos (inicio de tick en GameManager/NetManager).
func clear_all_viewers() -> void:
	for pid in _viewers.keys():
		_viewers[pid] = []


## Reconstruye niebla si `tick % 5 == 0`. Si se omite `tick`, usa SimAPI.tick.
## Devuelve true solo cuando reconstruyó. Determinista por construcción.
func rebuild_tick(tick: int = -1) -> bool:
	var t := tick
	if t < 0:
		t = _last_rebuild_tick + 1
		if is_inside_tree():
			var sim := get_node_or_null("/root/SimAPI")
			if sim != null:
				t = int(sim.get("tick"))
	if t % REBUILD_EVERY != 0:
		return false
	if t == _last_rebuild_tick:
		return false # ya reconstruido este tick
	_rebuild_all()
	_last_rebuild_tick = t
	fog_rebuilt.emit(t)
	return true


## Fuerza rebuild inmediato (init de partida, tests, carga). Determinista.
func force_rebuild() -> void:
	_rebuild_all()
	_fog_textures.clear() # invalida caché visual


func _rebuild_all() -> void:
	# Orden determinista de jugadores.
	var pids := _grids.keys()
	pids.sort()
	for pid in pids:
		var grid: PackedByteArray = _grids[pid]
		# 1) Lo visible pasa a explorado (memoria). Lo explorado se conserva.
		for i in GRID_SIZE:
			if grid[i] == Cell.VISIBLE:
				grid[i] = Cell.EXPLORED
		# 2) Pinta viewers ordenados por (x, y, r).
		var list: Array = _viewers.get(pid, [])
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["x"] != b["x"]:
				return int(a["x"]) < int(b["x"])
			if a["y"] != b["y"]:
				return int(a["y"]) < int(b["y"])
			return int(a["r"]) < int(b["r"]))
		for v in list:
			_paint_disc(grid, int(v["x"]), int(v["y"]), int(v["r"]))


## Pinta disco entero en celdas (dx*dx+dy*dy <= r*r). Solo enteros -> determinista.
func _paint_disc(grid: PackedByteArray, cx: int, cy: int, r: int) -> void:
	if r <= 0:
		if in_bounds(cx, cy):
			grid[idx(cx, cy)] = Cell.VISIBLE
		return
	var r2 := r * r
	var x0 := maxi(cx - r, 0)
	var x1 := mini(cx + r, GRID_W - 1)
	var y0 := maxi(cy - r, 0)
	var y1 := mini(cy + r, GRID_H - 1)
	for y in range(y0, y1 + 1):
		var dy := y - cy
		for x in range(x0, x1 + 1):
			var dx := x - cx
			if dx * dx + dy * dy <= r2:
				grid[idx(x, y)] = Cell.VISIBLE


## ¿La celda es visible AHORA para player_id? Fuera de bounds = false.
func is_visible(player_id: int, x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	if not _grids.has(player_id):
		return false
	return (_grids[player_id] as PackedByteArray)[idx(x, y)] == Cell.VISIBLE


## ¿La celda fue explorada alguna vez? (visible o memoria). Fuera de bounds = false.
func explored(player_id: int, x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	if not _grids.has(player_id):
		return false
	return (_grids[player_id] as PackedByteArray)[idx(x, y)] != Cell.UNEXPLORED


## Estado crudo 0/1/2. -1 si fuera de bounds o jugador desconocido.
func get_state(player_id: int, x: int, y: int) -> int:
	if not in_bounds(x, y):
		return -1
	if not _grids.has(player_id):
		return -1
	return (_grids[player_id] as PackedByteArray)[idx(x, y)]


## % de mapa explorado (0.0..100.0). Útil para marcador/logros. O(n) pero barato.
func explored_percent(player_id: int) -> float:
	if not _grids.has(player_id):
		return 0.0
	var n := 0
	var grid: PackedByteArray = _grids[player_id]
	for i in GRID_SIZE:
		if grid[i] != Cell.UNEXPLORED:
			n += 1
	return 100.0 * float(n) / float(GRID_SIZE)


## Conversión mundo->celda si el mapa mide `world_size` unidades de lado.
## Ej: mapa 288x288 m con 144 celdas -> celda de 2 m.
static func world_to_cell(world_pos: Vector2, world_size: float = 288.0) -> Vector2i:
	var fx := clampf(world_pos.x / world_size, 0.0, 0.9999)
	var fy := clampf(world_pos.y / world_size, 0.0, 0.9999)
	return Vector2i(int(floor(fx * GRID_W)), int(floor(fy * GRID_H)))


static func cell_to_world(cell: Vector2i, world_size: float = 288.0) -> Vector2:
	var cs := world_size / float(GRID_W)
	return Vector2((float(cell.x) + 0.5) * cs, (float(cell.y) + 0.5) * cs)


# ------------------------------------------------- visual SOLO CLIENTE
## Todo lo de abajo NO es sim: no llamar en servidor/headless ni dentro del tick.
## Genera overlay 144x144 para minimapa/HUD: negro=sin explorar,
## semitransparente=explorado, transparente=visible.

func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Image 144x144 RGBA8 del overlay de niebla. Recién creada en cada llamada.
func get_fog_image(player_id: int) -> Image:
	var img := Image.create(GRID_W, GRID_H, false, Image.FORMAT_RGBA8)
	if not _grids.has(player_id):
		img.fill(COL_UNEXPLORED)
		return img
	var grid: PackedByteArray = _grids[player_id]
	for y in GRID_H:
		for x in GRID_W:
			match grid[idx(x, y)]:
				Cell.VISIBLE:
					img.set_pixel(x, y, COL_VISIBLE)
				Cell.EXPLORED:
					img.set_pixel(x, y, COL_EXPLORED)
				_:
					img.set_pixel(x, y, COL_UNEXPLORED)
	return img


## ImageTexture cacheada para TextureRect del minimapa/HUD. Invalidar con
## `invalidate_visual(pid)` tras cada rebuild visible en cliente.
func get_fog_texture(player_id: int) -> ImageTexture:
	if _is_headless():
		push_warning("FogOfWar.get_fog_texture en headless: devuelve null (solo cliente).")
		return null
	if _fog_textures.has(player_id):
		return _fog_textures[player_id] as ImageTexture
	var tex := ImageTexture.create_from_image(get_fog_image(player_id))
	_fog_textures[player_id] = tex
	return tex


## Re-crea la textura cacheada (llamar desde HUD tras fog_rebuilt o cada 5 ticks).
func refresh_visual(player_id: int) -> ImageTexture:
	if _is_headless():
		return null
	_fog_textures.erase(player_id)
	return get_fog_texture(player_id)


func invalidate_visual(player_id: int = -1) -> void:
	if player_id < 0:
		_fog_textures.clear()
	else:
		_fog_textures.erase(player_id)


## Combina terreno del minimapa con niebla: devuelve imagen lista para HUD.
## `terrain` debe ser Image 144x144 (si no, se redimensiona; no toca la original).
## explorado = terreno * 0.45, sin explorar = negro, visible = terreno intacto.
static func make_minimap_image(grid: PackedByteArray, terrain: Image) -> Image:
	var src := terrain
	if src.get_width() != GRID_W or src.get_height() != GRID_H:
		src = terrain.duplicate() as Image
		src.resize(GRID_W, GRID_H, Image.INTERPOLATE_NEAREST)
	var out := src.duplicate() as Image
	out.convert(Image.FORMAT_RGBA8)
	for y in GRID_H:
		for x in GRID_W:
			var st := int(grid[idx(x, y)]) if idx(x, y) < grid.size() else Cell.UNEXPLORED
			match st:
				Cell.VISIBLE:
					pass # terreno intacto
				Cell.EXPLORED:
					var c := src.get_pixel(x, y)
					out.set_pixel(x, y, Color(c.r * 0.45, c.g * 0.45, c.b * 0.45, 1.0))
				_:
					out.set_pixel(x, y, Color(0, 0, 0, 1))
	return out


## Atajo instancia: minimapa combinado para un jugador (solo cliente).
func get_minimap_image(player_id: int, terrain: Image) -> Image:
	_ensure_player(player_id)
	return make_minimap_image(_grids[player_id] as PackedByteArray, terrain)


func get_minimap_texture(player_id: int, terrain: Image) -> ImageTexture:
	if _is_headless():
		push_warning("FogOfWar.get_minimap_texture en headless: devuelve null (solo cliente).")
		return null
	return ImageTexture.create_from_image(get_minimap_image(player_id, terrain))

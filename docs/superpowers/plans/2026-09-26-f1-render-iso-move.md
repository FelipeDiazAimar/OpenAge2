# F1 — Render 2D isométrico + movimiento: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Una escena nueva "Partida (nuevo motor)" donde, en vista isométrica 2D estilo AoE2, se ven los centros urbanos y aldeanos (sprites AoE2 extraídos, con color de jugador), se seleccionan con el ratón y caminan con su animación hacia donde se hace clic derecho, todo movido por la simulación determinista de F0.

**Architecture:** La simulación (`engine/sim`) gana `Grid`, `Pathfinder` (A* entero), `MoveSystem` y `Sim` (jugadores, cola de comandos con retardo, tick a 10 Hz). El render (`engine/render2d`) solo lee `Sim.world`: `Iso` (proyección 2:1), `TerrainLayer`, `EntityLayer` + `EntityView` (y-sort, interpolación entre ticks, 16 direcciones, shader de color de jugador), `IsoCamera`, `SelectionOverlay`. `engine/assets/AssetLocator` resuelve `"sprite:<pack>/<anim>"` a texturas. `game/scenes/Match` une todo; el menú principal gana un botón. El juego viejo sigue intacto.

**Tech Stack:** Godot 4.4 GDScript (headless para tests), shaders canvas_item.

**Spec:** `docs/superpowers/specs/2026-09-26-reestructura-aoe2-design.md` (secciones 3, 5.1, 5.5, 6, 7, 10-F1). Base: F0 (`docs/superpowers/plans/2026-09-26-f0-registry-world.md`).

## Global Constraints

- Godot **4.4**; tests con `GODOT=<ruta> sh tests/engine/run.sh [test_x]` (falla ante `SCRIPT ERROR`). Ruta local: `/c/Users/Asus/AppData/Local/Temp/opencode/godot44/Godot_v4.4-stable_win64_console.exe`.
- `engine/sim` y `engine/data`: sin APIs visuales/tiempo/azar (lint `test_architecture`); solo enteros en estado mutable; posiciones en milésimas de casilla (`FixedPoint.SCALE = 1000`).
- `engine/render2d`, `engine/assets` y `game/` pueden leer `Sim` pero **nunca** mutar `Sim.world`; toda orden va por `Sim.queue_command(pid, type, payload)`.
- Sin `class_name` en código nuevo; referencias con `preload`.
- Proyección isométrica 2:1 con casilla de **96×48 px** (tamaño de los sprites `x1` del AoE2 DE: el TC de 4×4 mide 399 px de ancho).
- Direcciones de sprite: 16 slots, orden del archivo DE: W=0, antihorario (SW=2, S=4, SE=6, E=8, NE=10, N=12, NW=14).
- Tick de simulación 10 Hz (`World.TICK_RATE = 10`), retardo de entrada `Sim.INPUT_DELAY = 2` ticks.
- Assets extraídos del AoE2 no se versionan (ya en `.gitignore`); sin assets el juego se ve con placeholders y funciona igual.
- Comentarios y mensajes en español. Commits terminan con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Desviaciones conscientes respecto a la spec (para revisión)

- **Terreno con texturas del AoE2 DE**: F1 dibuja terreno procedural (rombos de hierba con variación). Extraer/decodificar texturas de terreno del DE (formato distinto al SLD) va a un plan propio "F1b: importador + terreno" junto con el **importador dentro del juego**. En F1, `AssetLocator` lee los sprites ya extraídos con `tools/extract_aoe2_sprites.py` (`res://assets/sprites`) y `user://aoe2_assets/sprites`.
- **Colisión entre unidades**: F1 no separa unidades (pueden superponerse al caminar); los grupos reciben destinos repartidos en espiral. Separación/formaciones van en F3.

## Review Focus

1. **Destino bloqueado o fuera del mapa** (clic derecho sobre el TC o fuera del rombo): la unidad debe ir a la casilla caminable más cercana, nunca quedarse congelada ni crashear. → Task 2 `test_blocked_goal_goes_to_nearest`, Task 4 `test_move_outside_map_clamps`.
2. **Destino inalcanzable** (zona encerrada): camina hasta el punto alcanzable más cercano sin colgarse (límite de expansiones). → Task 2 `test_unreachable_goes_closest`.
3. **Órdenes a unidades ajenas o ids inexistentes/duplicados** (LAN futura, payload JSON con floats): se ignoran/normalizan sin error. → Task 4 `test_commands_validate_owner_and_ids`.
4. **Sin sprites extraídos** (PC de un amigo sin AoE2): la partida se ve con placeholders, sin errores. → Task 6 `test_missing_pack_returns_empty`, Task 9 `test_view_without_sprites_draws_placeholder`.
5. **Rumbo en ángulos negativos** (NW/N/NE): el slot de dirección debe quedar en 0..15 (el `SpriteUnit` viejo daba -2 y dejaba la unidad invisible). → Task 5 `test_dir16_cardinals_and_negative_angles`.

---

## File Structure

```
engine/sim/
  World.gd           (modificar) estado inicial del componente Move; TICK_RATE
  Grid.gd            caminabilidad por casilla + conversiones casilla<->milésimas
  Pathfinder.gd      A* entero determinista (octil, sin cortar esquinas, casilla más cercana)
  systems/MoveSystem.gd  órdenes de movimiento y avance por tick
  Sim.gd             jugadores + PlayerDefs, spawn, cola de comandos, step()
engine/assets/
  AssetLocator.gd    "sprite:<pack>/<anim>" -> {dirs, per_dir, frames[{tex, mask, hotspot}]}
engine/render2d/
  Iso.gd             proyección 2:1, inversa, dir16
  player_color.gdshader
  TerrainLayer.gd    rombos de terreno procedural
  EntityView.gd      una entidad: animación, dirección, color, selección, placeholder
  EntityLayer.gd     sincroniza vistas con Sim.world, interpola, picking
  IsoCamera.gd       pan (flechas, borde, botón medio), zoom con rueda
  SelectionOverlay.gd  rectángulo de selección
game/scenes/
  Match.gd, Match.tscn  partida local con el motor nuevo
ui/menus/MainMenu.gd (modificar) botón "Partida (nuevo motor, beta)"
tests/engine/
  test_grid_pathfinder.gd, test_move_system.gd, test_sim.gd, test_iso.gd,
  test_asset_locator.gd, test_entity_view.gd, test_match_smoke.gd
```

---

### Task 1: Grid + estado de Move en World

**Files:**
- Create: `engine/sim/Grid.gd`
- Modify: `engine/sim/World.gd` (añadir `TICK_RATE` y caso `"Move"` en `_init_component`)
- Test: `tests/engine/test_grid_pathfinder.gd` (parte Grid), `tests/engine/test_world.gd` (añadir caso)

**Interfaces:**
- Consumes: `FixedPoint.SCALE`, `FixedPoint.floordiv`, `FixedPoint.from_data` (F0).
- Produces:
  - `Grid.new(w: int, h: int)`; campos `width`, `height`; `in_bounds(c: Vector2i) -> bool`; `is_walkable(c: Vector2i) -> bool`; `set_blocked(c: Vector2i, v: bool)`; `block_rect(origin: Vector2i, size: Vector2i, v: bool = true)`; `clamp_tile(c: Vector2i) -> Vector2i`; estáticos `tile_of(p: Vector2i) -> Vector2i`, `center_of(c: Vector2i) -> Vector2i`.
  - `World.TICK_RATE := 10`; componente Move = `{params, step: int (milésimas por tick), waypoints: Array[Vector2i], moving: bool, facing: Vector2i}` con `facing` inicial `Vector2i(1000, 1000)`.

- [ ] **Step 1: Test que falla** — crear `tests/engine/test_grid_pathfinder.gd`:

```gdscript
extends "res://tests/engine/TestCase.gd"

const Grid := preload("res://engine/sim/Grid.gd")


func test_grid_bounds_and_blocking() -> void:
	var g := Grid.new(10, 8)
	assert_true(g.in_bounds(Vector2i(9, 7)))
	assert_false(g.in_bounds(Vector2i(10, 0)))
	assert_false(g.in_bounds(Vector2i(0, -1)))
	assert_true(g.is_walkable(Vector2i(3, 3)))
	g.block_rect(Vector2i(2, 2), Vector2i(2, 3))
	assert_false(g.is_walkable(Vector2i(3, 4)))
	assert_true(g.is_walkable(Vector2i(4, 4)))
	g.set_blocked(Vector2i(3, 4), false)
	assert_true(g.is_walkable(Vector2i(3, 4)))
	assert_false(g.is_walkable(Vector2i(-1, 0)), "fuera del mapa no es caminable")
	assert_eq(g.clamp_tile(Vector2i(-5, 20)), Vector2i(0, 7))


func test_tile_conversions() -> void:
	assert_eq(Grid.tile_of(Vector2i(2999, 1000)), Vector2i(2, 1))
	assert_eq(Grid.tile_of(Vector2i(-1, -1000)), Vector2i(-1, -1))
	assert_eq(Grid.center_of(Vector2i(3, 4)), Vector2i(3500, 4500))
```

y añadir a `tests/engine/test_world.gd`:

```gdscript


func test_move_component_initial_state() -> void:
	var w := World.new()
	var a := w.spawn(SOLDADO, 0, Vector2i(0, 0))
	var m := w.comp(a, "Move")
	assert_eq(m["step"], 90, "0.9 casillas/s a 10 Hz = 90 milésimas por tick")
	assert_eq(m["waypoints"], [])
	assert_false(m["moving"])
	assert_eq(m["facing"], Vector2i(1000, 1000))
	assert_eq(World.TICK_RATE, 10)
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_grid_pathfinder` → Expected: FAIL (Grid.gd no existe). `sh tests/engine/run.sh test_world` → Expected: FAIL en `test_move_component_initial_state`.

- [ ] **Step 3: Implementar** — `engine/sim/Grid.gd`

```gdscript
extends RefCounted
## Grilla de casillas: caminabilidad y conversiones casilla <-> milésimas.

const FP := preload("res://engine/sim/FixedPoint.gd")

var width := 0
var height := 0
var _blocked := PackedByteArray()


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
		_blocked[c.y * width + c.x] = 1 if v else 0


func block_rect(origin: Vector2i, size: Vector2i, v: bool = true) -> void:
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			set_blocked(Vector2i(x, y), v)


func clamp_tile(c: Vector2i) -> Vector2i:
	return Vector2i(clampi(c.x, 0, width - 1), clampi(c.y, 0, height - 1))


static func tile_of(p: Vector2i) -> Vector2i:
	return Vector2i(FP.floordiv(p.x, FP.SCALE), FP.floordiv(p.y, FP.SCALE))


static func center_of(c: Vector2i) -> Vector2i:
	return c * FP.SCALE + Vector2i(FP.SCALE / 2, FP.SCALE / 2)
```

Modificar `engine/sim/World.gd`: añadir bajo los `preload`:

```gdscript
const TICK_RATE := 10
```

y en `_init_component`, dentro del `match ability:`, añadir el caso:

```gdscript
		"Move":
			c["step"] = FP.from_data(float(params["speed"])) / TICK_RATE
			c["waypoints"] = [] as Array[Vector2i]
			c["moving"] = false
			c["facing"] = Vector2i(1000, 1000)
```

- [ ] **Step 4: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_grid_pathfinder` → `2 tests, 0 fallos`. `sh tests/engine/run.sh test_world` → `6 tests, 0 fallos`.

- [ ] **Step 5: Commit**

```bash
git add engine/sim/Grid.gd engine/sim/World.gd tests/engine/test_grid_pathfinder.gd tests/engine/test_world.gd
git commit -m "F1: Grid de casillas y estado del componente Move

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Pathfinder A* entero

**Files:**
- Create: `engine/sim/Pathfinder.gd`
- Test: `tests/engine/test_grid_pathfinder.gd` (añadir casos)

**Interfaces:**
- Consumes: `Grid` (Task 1).
- Produces: estáticos `find_path(grid, start: Vector2i, goal: Vector2i) -> Array[Vector2i]` (casillas, **sin** la de inicio; `[]` si ya está o no hay destino caminable), `nearest_walkable(grid, goal: Vector2i) -> Vector2i` (`Vector2i(-1, -1)` si no hay ninguna); constantes `STRAIGHT := 10`, `DIAG := 14`, `MAX_EXPANSIONS := 30000`.
- Reglas: costo octil entero; diagonal solo si ambas ortogonales son caminables; la casilla de inicio puede estar bloqueada (unidad dentro de un footprint); si el objetivo es inalcanzable devuelve el camino a la casilla expandida con menor heurística; desempates deterministas por `(f, h, índice)`.

- [ ] **Step 1: Test que falla** — añadir a `tests/engine/test_grid_pathfinder.gd`:

```gdscript
const Pathfinder := preload("res://engine/sim/Pathfinder.gd")


func test_straight_path() -> void:
	var g := Grid.new(10, 10)
	var p := Pathfinder.find_path(g, Vector2i(1, 1), Vector2i(4, 1))
	assert_eq(p, [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)])
	assert_eq(Pathfinder.find_path(g, Vector2i(1, 1), Vector2i(1, 1)), [])


func test_path_around_wall_without_corner_cutting() -> void:
	var g := Grid.new(10, 10)
	g.block_rect(Vector2i(3, 0), Vector2i(1, 6))
	var p := Pathfinder.find_path(g, Vector2i(1, 2), Vector2i(5, 2))
	assert_eq(p[p.size() - 1], Vector2i(5, 2))
	var prev := Vector2i(1, 2)
	for c in p:
		assert_true(g.is_walkable(c), "pisa bloqueada: %s" % c)
		var d: Vector2i = c - prev
		if d.x != 0 and d.y != 0:
			assert_true(g.is_walkable(Vector2i(prev.x + d.x, prev.y)) and g.is_walkable(Vector2i(prev.x, prev.y + d.y)), "corta esquina en %s" % c)
		prev = c


func test_blocked_goal_goes_to_nearest() -> void:
	var g := Grid.new(10, 10)
	g.block_rect(Vector2i(4, 4), Vector2i(3, 3))
	assert_eq(Pathfinder.nearest_walkable(g, Vector2i(5, 5)), Vector2i(5, 3))
	var p := Pathfinder.find_path(g, Vector2i(0, 5), Vector2i(5, 5))
	assert_true(g.is_walkable(p[p.size() - 1]))
	assert_eq(p[p.size() - 1], Pathfinder.nearest_walkable(g, Vector2i(5, 5)))
	var full := Grid.new(2, 2)
	full.block_rect(Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(Pathfinder.nearest_walkable(full, Vector2i(0, 0)), Vector2i(-1, -1))


func test_start_on_blocked_edge_can_leave() -> void:
	var g := Grid.new(10, 10)
	g.block_rect(Vector2i(2, 2), Vector2i(3, 3))
	var p := Pathfinder.find_path(g, Vector2i(4, 3), Vector2i(8, 3))
	assert_eq(p[p.size() - 1], Vector2i(8, 3))


func test_unreachable_goes_closest() -> void:
	var g := Grid.new(12, 12)
	# anillo cerrado alrededor de (8,8)
	for x in range(6, 11):
		g.set_blocked(Vector2i(x, 6), true)
		g.set_blocked(Vector2i(x, 10), true)
	for y in range(6, 11):
		g.set_blocked(Vector2i(6, y), true)
		g.set_blocked(Vector2i(10, y), true)
	var p := Pathfinder.find_path(g, Vector2i(1, 1), Vector2i(8, 8))
	assert_false(p.is_empty())
	var end: Vector2i = p[p.size() - 1]
	assert_true(g.is_walkable(end))
	assert_true(absi(end.x - 8) + absi(end.y - 8) <= 4, "termina pegado al anillo: %s" % end)


func test_path_is_deterministic() -> void:
	var g := Grid.new(30, 30)
	g.block_rect(Vector2i(10, 5), Vector2i(2, 20))
	assert_eq(Pathfinder.find_path(g, Vector2i(2, 15), Vector2i(25, 15)), Pathfinder.find_path(g, Vector2i(2, 15), Vector2i(25, 15)))
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_grid_pathfinder` → Expected: FAIL (Pathfinder.gd no existe).

- [ ] **Step 3: Implementar** — `engine/sim/Pathfinder.gd`

```gdscript
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
```

- [ ] **Step 4: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_grid_pathfinder` → `8 tests, 0 fallos`. Si `test_blocked_goal_goes_to_nearest` falla en el valor exacto `(5,3)`: con goal `(5,5)` y bloque 4..6, el anillo r=2 tiene `(5,3)` y `(5,7)`, `(3,5)`, `(7,5)` a distancia 4; el desempate `(dist, y, x)` elige `(5,3)`. No cambiar el test: revisar `_less`/orden del anillo.

- [ ] **Step 5: Commit**

```bash
git add engine/sim/Pathfinder.gd tests/engine/test_grid_pathfinder.gd
git commit -m "F1: Pathfinder A* entero determinista

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: MoveSystem

**Files:**
- Create: `engine/sim/systems/MoveSystem.gd`
- Test: `tests/engine/test_move_system.gd`

**Interfaces:**
- Consumes: `World.comp/set_pos/ids_with/entities` (F0 + Task 1), `Grid.tile_of/center_of` (Task 1), `Pathfinder.find_path` (Task 2), `FixedPoint.length` (F0).
- Produces: estáticos `order_move(world, grid, id: int, dest: Vector2i) -> void` (calcula waypoints en milésimas: centros de casilla del camino, y el último = `dest` exacto si su casilla es la final), `step(world) -> void` (avanza `step` milésimas por tick siguiendo waypoints; actualiza `facing` con el último delta no nulo; `moving=false` al terminar).

- [ ] **Step 1: Test que falla** — `tests/engine/test_move_system.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const World := preload("res://engine/sim/World.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")

const ALDEANO := {"id": "aldeano", "type": "unit",
	"abilities": {"Hitpoints": {"max": 25}, "Move": {"speed": 0.8}}}


func _setup() -> Array:
	var w := World.new()
	var g := Grid.new(40, 40)
	var id := w.spawn(ALDEANO, 0, Grid.center_of(Vector2i(5, 5)))
	return [w, g, id]


func test_walks_straight_at_speed() -> void:
	var s := _setup()
	var w: World = s[0]
	var id: int = s[2]
	MoveSystem.order_move(w, s[1], id, Grid.center_of(Vector2i(15, 5)))
	assert_true(w.comp(id, "Move")["moving"])
	for i in 124:
		MoveSystem.step(w)
	assert_eq(w.entities[id]["pos"], Vector2i(5500 + 124 * 80, 5500))
	MoveSystem.step(w)
	assert_eq(w.entities[id]["pos"], Vector2i(15500, 5500), "10 casillas a 80 milésimas/tick = 125 ticks")
	assert_false(w.comp(id, "Move")["moving"])
	assert_eq(w.comp(id, "Move")["facing"], Vector2i(80, 0), "último tramo: 80 milésimas hacia +x")


func test_exact_destination_inside_tile() -> void:
	var s := _setup()
	var w: World = s[0]
	var id: int = s[2]
	MoveSystem.order_move(w, s[1], id, Vector2i(8200, 5900))
	for i in 200:
		MoveSystem.step(w)
	assert_eq(w.entities[id]["pos"], Vector2i(8200, 5900))


func test_same_tile_order_moves_inside_tile() -> void:
	var s := _setup()
	var w: World = s[0]
	var id: int = s[2]
	MoveSystem.order_move(w, s[1], id, Vector2i(5900, 5100))
	for i in 20:
		MoveSystem.step(w)
	assert_eq(w.entities[id]["pos"], Vector2i(5900, 5100))


func test_new_order_replaces_old() -> void:
	var s := _setup()
	var w: World = s[0]
	var id: int = s[2]
	MoveSystem.order_move(w, s[1], id, Grid.center_of(Vector2i(30, 5)))
	for i in 10:
		MoveSystem.step(w)
	MoveSystem.order_move(w, s[1], id, Grid.center_of(Vector2i(5, 20)))
	for i in 400:
		MoveSystem.step(w)
	assert_eq(w.entities[id]["pos"], Grid.center_of(Vector2i(5, 20)))
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_move_system` → Expected: FAIL (MoveSystem.gd no existe).

- [ ] **Step 3: Implementar** — `engine/sim/systems/MoveSystem.gd`

```gdscript
extends RefCounted
## Movimiento: órdenes (camino A* -> waypoints en milésimas) y avance por tick.

const FP := preload("res://engine/sim/FixedPoint.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const Pathfinder := preload("res://engine/sim/Pathfinder.gd")


static func order_move(world, grid, id: int, dest: Vector2i) -> void:
	var m: Dictionary = world.comp(id, "Move")
	if m.is_empty():
		return
	var pos: Vector2i = world.entities[id]["pos"]
	var start := Grid.tile_of(pos)
	var dest_tile := Grid.tile_of(dest)
	var pts: Array[Vector2i] = []
	if dest_tile == start and grid.is_walkable(dest_tile):
		pts.append(dest)
	else:
		for t in Pathfinder.find_path(grid, start, dest_tile):
			pts.append(Grid.center_of(t))
		if not pts.is_empty() and Grid.tile_of(pts[pts.size() - 1]) == dest_tile:
			pts[pts.size() - 1] = dest
	m["waypoints"] = pts
	m["moving"] = not pts.is_empty()


static func step(world) -> void:
	for id in world.ids_with("Move"):
		var m: Dictionary = world.comp(id, "Move")
		if not m["moving"]:
			continue
		var budget: int = m["step"]
		var pos: Vector2i = world.entities[id]["pos"]
		var wps: Array = m["waypoints"]
		while budget > 0 and not wps.is_empty():
			var t: Vector2i = wps[0]
			var d := t - pos
			var dist := FP.length(d.x, d.y)
			if dist <= budget:
				pos = t
				budget -= dist
				wps.pop_front()
				if dist > 0:
					m["facing"] = d
			else:
				pos += Vector2i(d.x * budget / dist, d.y * budget / dist)
				m["facing"] = d
				budget = 0
		world.set_pos(id, pos)
		if wps.is_empty():
			m["moving"] = false
```

Nota: `facing` guarda el delta crudo del último tramo recorrido (en el test, los 80 finales hacia +x); el render solo usa su dirección.

- [ ] **Step 4: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_move_system` → `4 tests, 0 fallos`.

- [ ] **Step 5: Commit**

```bash
git add engine/sim/systems/MoveSystem.gd tests/engine/test_move_system.gd
git commit -m "F1: MoveSystem (órdenes y avance por tick)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Sim (jugadores, spawn, cola de comandos, step)

**Files:**
- Create: `engine/sim/Sim.gd`
- Test: `tests/engine/test_sim.gd`

**Interfaces:**
- Consumes: `Registry` (F0: `defs`, `get_def`), `PlayerDefs` (F0), `World`, `Grid`, `MoveSystem`.
- Produces:
  - `Sim.new(registry, map_w: int, map_h: int)`; `const INPUT_DELAY := 2`; campos `world`, `grid`, `registry`, `players: Array[Dictionary]` (`{id, civ, team, defs: PlayerDefs}`).
  - `add_player(pid: int, civ: String, team: int) -> void` (pids consecutivos desde 0).
  - `spawn(def_id: String, owner: int, tile: Vector2i) -> int`: edificio → `tile` = esquina del footprint, pos = centro del footprint, bloquea la grilla; unidad → pos = centro de `tile`. Devuelve id o `-1` si el id no existe.
  - `def_for(id: int) -> Dictionary` (definición del dueño, o del registry si `owner < 0`).
  - `queue_command(pid: int, type: String, payload: Dictionary) -> void` (se ejecuta en `world.tick + INPUT_DELAY`).
  - `step() -> void`: `tick += 1`, aplica comandos del tick ordenados por `(pid, seq)`, corre `MoveSystem.step`.
  - Comando `"move"`: `payload = {"ids": [int...], "pos": [x_milli, y_milli]}` (acepta floats de JSON); ignora ids ajenos/inexistentes/sin Move y duplicados; ids ordenados; cada unidad recibe `pos + spread_offsets(n)[i]` recortado al mapa.
  - `static spread_offsets(n: int) -> Array[Vector2i]` (milésimas; el primero es `(0,0)`; casillas en espiral por distancia, deterministas).

- [ ] **Step 1: Test que falla** — `tests/engine/test_sim.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const Grid := preload("res://engine/sim/Grid.gd")


func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 60, 60)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	return s


func test_spawn_building_blocks_footprint() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	assert_eq(s.world.entities[tc]["pos"], Vector2i(12000, 12000), "centro del footprint 4x4")
	assert_false(s.grid.is_walkable(Vector2i(13, 13)))
	assert_true(s.grid.is_walkable(Vector2i(14, 13)))
	assert_eq(s.spawn("no_existe", 0, Vector2i(1, 1)), -1)
	var v := s.spawn("aldeano", 0, Vector2i(15, 12))
	assert_eq(s.world.entities[v]["pos"], Vector2i(15500, 12500))
	assert_eq(s.def_for(v)["id"], "aldeano")


func test_move_command_respects_input_delay() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(5, 5))
	s.queue_command(0, "move", {"ids": [v], "pos": [15500, 5500]})
	s.step()
	assert_false(s.world.comp(v, "Move")["moving"], "tick 1: todavía no")
	s.step()
	assert_true(s.world.comp(v, "Move")["moving"], "tick 2: aplicada")
	for i in 124:
		s.step()
	assert_eq(s.world.entities[v]["pos"], Vector2i(15500, 5500))


func test_commands_validate_owner_and_ids() -> void:
	var s := _sim()
	var mine := s.spawn("aldeano", 0, Vector2i(5, 5))
	var theirs := s.spawn("aldeano", 1, Vector2i(8, 8))
	var tc := s.spawn("centro_urbano", 0, Vector2i(20, 20))
	s.queue_command(0, "move", {"ids": [theirs, 9999, tc, float(mine), mine], "pos": [10500.0, 5500.0]})
	for i in 3:
		s.step()
	assert_true(s.world.comp(mine, "Move")["moving"])
	assert_false(s.world.comp(theirs, "Move")["moving"])
	s.queue_command(0, "volar", {})
	s.step()
	s.step()
	assert_eq(s.world.tick, 5, "un tipo desconocido se ignora sin error")


func test_move_outside_map_clamps() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(5, 5))
	s.queue_command(0, "move", {"ids": [v], "pos": [-50000, 999999]})
	for i in 1500:
		s.step()
	var p: Vector2i = s.world.entities[v]["pos"]
	assert_true(s.grid.in_bounds(Grid.tile_of(p)), "quedó dentro del mapa: %s" % p)
	assert_false(s.world.comp(v, "Move")["moving"])


func test_group_move_spreads_units() -> void:
	var s := _sim()
	var ids: Array = []
	for i in 5:
		ids.append(s.spawn("aldeano", 0, Vector2i(5 + i, 5)))
	s.queue_command(0, "move", {"ids": ids, "pos": [30500, 30500]})
	for i in 600:
		s.step()
	var seen := {}
	for id in ids:
		seen[s.world.entities[id]["pos"]] = true
	assert_eq(seen.size(), 5, "cada aldeano en un punto distinto")
	assert_eq(Sim.spread_offsets(3), [Vector2i(0, 0), Vector2i(0, -1000), Vector2i(-1000, 0)])


func test_same_commands_same_hash() -> void:
	var hashes := []
	for run in 2:
		var s := _sim()
		var a := s.spawn("aldeano", 0, Vector2i(5, 5))
		var b := s.spawn("aldeano", 1, Vector2i(40, 40))
		s.spawn("centro_urbano", 0, Vector2i(20, 20))
		s.queue_command(0, "move", {"ids": [a], "pos": [45500, 45500]})
		s.queue_command(1, "move", {"ids": [b], "pos": [2500, 2500]})
		for i in 300:
			s.step()
		hashes.append(s.world.state_hash())
	assert_eq(hashes[0], hashes[1])
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_sim` → Expected: FAIL (Sim.gd no existe).

- [ ] **Step 3: Implementar** — `engine/sim/Sim.gd`

```gdscript
extends RefCounted
## Simulación de una partida: jugadores, spawn, cola de comandos con retardo
## de entrada y tick determinista. El render solo lee `world`.

const World := preload("res://engine/sim/World.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const FP := preload("res://engine/sim/FixedPoint.gd")
const PlayerDefs := preload("res://engine/data/PlayerDefs.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")

const INPUT_DELAY := 2

var registry
var world := World.new()
var grid
var players: Array[Dictionary] = []
var _pending: Dictionary = {}
var _seq := 0


func _init(p_registry, map_w: int, map_h: int) -> void:
	registry = p_registry
	grid = Grid.new(map_w, map_h)


func add_player(pid: int, civ: String, team: int) -> void:
	players.append({"id": pid, "civ": civ, "team": team, "defs": PlayerDefs.new(registry.defs, civ)})


func def_for(id: int) -> Dictionary:
	if not world.entities.has(id):
		return {}
	var e: Dictionary = world.entities[id]
	var owner: int = e["owner"]
	if owner >= 0 and owner < players.size():
		return players[owner]["defs"].get_def(e["def_id"])
	return registry.get_def(e["def_id"])


func spawn(def_id: String, owner: int, tile: Vector2i) -> int:
	var def: Dictionary
	if owner >= 0 and owner < players.size():
		def = players[owner]["defs"].get_def(def_id)
	else:
		def = registry.get_def(def_id)
	if def.is_empty():
		return -1
	if str(def["type"]) == "building":
		var size := Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
		grid.block_rect(tile, size)
		return world.spawn(def, owner, tile * FP.SCALE + size * (FP.SCALE / 2))
	return world.spawn(def, owner, Grid.center_of(tile))


func queue_command(pid: int, type: String, payload: Dictionary) -> void:
	var t := world.tick + INPUT_DELAY
	if not _pending.has(t):
		_pending[t] = []
	_pending[t].append({"pid": pid, "seq": _seq, "type": type, "payload": payload})
	_seq += 1


func step() -> void:
	world.tick += 1
	var cmds: Array = _pending.get(world.tick, [])
	_pending.erase(world.tick)
	cmds.sort_custom(func(a, b): return a["pid"] < b["pid"] or (a["pid"] == b["pid"] and a["seq"] < b["seq"]))
	for c in cmds:
		_apply(c)
	MoveSystem.step(world)


## Desplazamientos (milésimas) para repartir un grupo: casillas en espiral
## ordenadas por (distancia², y, x). El primero es (0,0).
static func spread_offsets(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := 0
	while out.size() < n:
		var ring: Array = []
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(y)) == r:
					ring.append([x * x + y * y, y, x])
		ring.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
		for k in ring:
			if out.size() < n:
				out.append(Vector2i(k[2], k[1]) * FP.SCALE)
		r += 1
	return out


func _apply(c: Dictionary) -> void:
	match str(c["type"]):
		"move":
			_cmd_move(int(c["pid"]), c["payload"])


func _cmd_move(pid: int, payload: Dictionary) -> void:
	var pos: Array = payload.get("pos", [])
	if pos.size() != 2:
		return
	var target := Vector2i(int(pos[0]), int(pos[1]))
	var ids: Array[int] = []
	for raw in payload.get("ids", []):
		var id := int(raw)
		if ids.has(id) or not world.entities.has(id):
			continue
		if int(world.entities[id]["owner"]) != pid or not world.has_ability(id, "Move"):
			continue
		ids.append(id)
	ids.sort()
	var offs := spread_offsets(ids.size())
	var lo := Vector2i(0, 0)
	var hi := Vector2i(grid.width * FP.SCALE - 1, grid.height * FP.SCALE - 1)
	for i in ids.size():
		var dest := (target + offs[i]).clamp(lo, hi)
		MoveSystem.order_move(world, grid, ids[i], dest)
```

Nota: `test_group_move_spreads_units` espera `spread_offsets(3) == [(0,0), (0,-1000), (-1000,0)]`: en el anillo r=1, las 4 casillas a distancia 1 ordenadas por `(y, x)` son `(0,-1)`, `(-1,0)`, `(1,0)`, `(0,1)`.

- [ ] **Step 4: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_sim` → `6 tests, 0 fallos`.

- [ ] **Step 5: Commit**

```bash
git add engine/sim/Sim.gd tests/engine/test_sim.gd
git commit -m "F1: Sim con jugadores, spawn y cola de comandos

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Iso (proyección y direcciones)

**Files:**
- Create: `engine/render2d/Iso.gd`
- Test: `tests/engine/test_iso.gd`

**Interfaces:**
- Produces: `const TILE_W := 96.0`, `const TILE_H := 48.0`; estáticos `to_screen(tiles: Vector2) -> Vector2`, `milli_to_screen(p: Vector2i) -> Vector2`, `to_tiles(screen: Vector2) -> Vector2`, `dir16(screen_delta: Vector2) -> int` (0..15, W=0 antihorario).

- [ ] **Step 1: Test que falla** — `tests/engine/test_iso.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const Iso := preload("res://engine/render2d/Iso.gd")


func test_projection_roundtrip() -> void:
	assert_eq(Iso.to_screen(Vector2(0, 0)), Vector2(0, 0))
	assert_eq(Iso.to_screen(Vector2(1, 0)), Vector2(48, 24))
	assert_eq(Iso.to_screen(Vector2(0, 1)), Vector2(-48, 24))
	assert_eq(Iso.milli_to_screen(Vector2i(2000, 2000)), Vector2(0, 96))
	var t := Vector2(12.25, 40.5)
	assert_true(Iso.to_tiles(Iso.to_screen(t)).is_equal_approx(t))


func test_dir16_cardinals_and_negative_angles() -> void:
	assert_eq(Iso.dir16(Vector2(-1, 0)), 0, "W")
	assert_eq(Iso.dir16(Vector2(-1, 1)), 2, "SW")
	assert_eq(Iso.dir16(Vector2(0, 1)), 4, "S")
	assert_eq(Iso.dir16(Vector2(1, 1)), 6, "SE")
	assert_eq(Iso.dir16(Vector2(1, 0)), 8, "E")
	assert_eq(Iso.dir16(Vector2(1, -1)), 10, "NE")
	assert_eq(Iso.dir16(Vector2(0, -1)), 12, "N")
	assert_eq(Iso.dir16(Vector2(-1, -1)), 14, "NW")
	assert_eq(Iso.dir16(Vector2(-10, -1)), 0, "casi W por arriba no da negativo")
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_iso` → Expected: FAIL.

- [ ] **Step 3: Implementar** — `engine/render2d/Iso.gd`

```gdscript
extends RefCounted
## Proyección isométrica 2:1 (casilla 96x48, como los sprites x1 del AoE2 DE).
## Solo cliente: floats permitidos.

const TILE_W := 96.0
const TILE_H := 48.0


static func to_screen(tiles: Vector2) -> Vector2:
	return Vector2((tiles.x - tiles.y) * TILE_W * 0.5, (tiles.x + tiles.y) * TILE_H * 0.5)


static func milli_to_screen(p: Vector2i) -> Vector2:
	return to_screen(Vector2(p) / 1000.0)


static func to_tiles(screen: Vector2) -> Vector2:
	var a := screen.x / (TILE_W * 0.5)
	var b := screen.y / (TILE_H * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


## Slot de sprite (0..15) para un rumbo en pantalla. Orden del archivo DE:
## W=0 y antihorario (S=4, E=8, N=12).
static func dir16(screen_delta: Vector2) -> int:
	var compass := rad_to_deg(atan2(screen_delta.x, -screen_delta.y))
	return posmod(int(round((270.0 - compass) / 22.5)), 16)
```

- [ ] **Step 4: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_iso` → `2 tests, 0 fallos`.

- [ ] **Step 5: Commit**

```bash
git add engine/render2d/Iso.gd tests/engine/test_iso.gd
git commit -m "F1: proyección isométrica y direcciones de sprite

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: AssetLocator

**Files:**
- Create: `engine/assets/AssetLocator.gd`
- Test: `tests/engine/test_asset_locator.gd`

**Interfaces:**
- Produces: `AssetLocator.new(roots: Array = DEFAULT_ROOTS)`; `const DEFAULT_ROOTS := ["user://aoe2_assets/sprites", "res://assets/sprites"]`; `sprite(ref: String) -> Dictionary` → `{}` si falta, o `{"dirs": int, "per_dir": int, "frames": Array}` con `frames[dir * per_dir + sub] = {"tex": Texture2D, "mask": Texture2D|null, "hotspot": Vector2}`. Cachea por ref. Carga PNG con `ResourceLoader` si están importados, si no con `Image.load_from_file`.
- Formato de entrada (`manifest.pack.json` de `tools/extract_aoe2_sprites.py --pack`): `{"dirs", "kept_per_dir", "size", "frames": [{"png", "mask"?, "dir", "sub", "hotspot": [x, y]}]}`.

- [ ] **Step 1: Test que falla** — `tests/engine/test_asset_locator.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const AssetLocator := preload("res://engine/assets/AssetLocator.gd")
const ROOT := "user://test_assets/sprites"


func _make_pack() -> void:
	var dir := ROOT + "/foo/walk"
	DirAccess.make_dir_recursive_absolute(dir)
	var frames := []
	for d in 2:
		var img := Image.create(4 + d, 6, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 0, 0, 1))
		img.save_png("%s/p_%03d.png" % [dir, d])
		frames.append({"png": "p_%03d.png" % d, "dir": d, "sub": 0, "hotspot": [2, 5]})
	var m := Image.create(4, 6, false, Image.FORMAT_RGBA8)
	m.fill(Color(1, 1, 1, 1))
	m.save_png(dir + "/m_000.png")
	frames[0]["mask"] = "m_000.png"
	var man := {"dirs": 2, "kept_per_dir": 1, "size": [4, 6], "frames": frames}
	var f := FileAccess.open(dir + "/manifest.pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(man))
	f.close()


func test_loads_pack_with_mask_and_hotspot() -> void:
	_make_pack()
	var loc := AssetLocator.new([ROOT])
	var pk := loc.sprite("sprite:foo/walk")
	assert_eq(pk["dirs"], 2)
	assert_eq(pk["per_dir"], 1)
	assert_eq(pk["frames"].size(), 2)
	assert_eq(pk["frames"][1]["tex"].get_size(), Vector2(5, 6))
	assert_eq(pk["frames"][0]["hotspot"], Vector2(2, 5))
	assert_true(pk["frames"][0]["mask"] != null)
	assert_true(pk["frames"][1]["mask"] == null)
	assert_true(is_same(loc.sprite("sprite:foo/walk"), pk), "cacheado")


func test_missing_pack_returns_empty() -> void:
	var loc := AssetLocator.new([ROOT])
	assert_eq(loc.sprite("sprite:nada/walk"), {})
	assert_eq(loc.sprite("icon:x"), {})
	assert_eq(loc.sprite(""), {})
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_asset_locator` → Expected: FAIL.

- [ ] **Step 3: Implementar** — `engine/assets/AssetLocator.gd`

```gdscript
extends RefCounted
## Resuelve referencias de assets de las definiciones ("sprite:<pack>/<anim>")
## a animaciones cargadas desde carpetas de sprites extraídos (primero
## user://aoe2_assets, luego res://assets/sprites). Sin assets -> {} y el
## render dibuja un placeholder.

const DEFAULT_ROOTS := ["user://aoe2_assets/sprites", "res://assets/sprites"]

var roots: Array[String] = []
var _cache: Dictionary = {}


func _init(p_roots: Array = DEFAULT_ROOTS) -> void:
	roots.assign(p_roots)


func sprite(ref: String) -> Dictionary:
	if not ref.begins_with("sprite:"):
		return {}
	if _cache.has(ref):
		return _cache[ref]
	var rel := ref.substr(7)
	var result := {}
	for r in roots:
		var dir := "%s/%s" % [r, rel]
		if FileAccess.file_exists(dir + "/manifest.pack.json"):
			result = _load_pack(dir)
			if not result.is_empty():
				break
	_cache[ref] = result
	return result


func _load_pack(dir: String) -> Dictionary:
	var man: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/manifest.pack.json"))
	if not (man is Dictionary) or not man.has("frames"):
		return {}
	var dirs := int(man.get("dirs", 1))
	var per_dir := int(man.get("kept_per_dir", 1))
	var frames: Array = []
	frames.resize(dirs * per_dir)
	for e in man["frames"]:
		var i := int(e["dir"]) * per_dir + int(e["sub"])
		if i < 0 or i >= frames.size():
			continue
		var tex := _texture("%s/%s" % [dir, e["png"]])
		if tex == null:
			return {}
		var mask: Texture2D = null
		if e.get("mask") is String:
			mask = _texture("%s/%s" % [dir, e["mask"]])
		frames[i] = {"tex": tex, "mask": mask, "hotspot": Vector2(float(e["hotspot"][0]), float(e["hotspot"][1]))}
	for f in frames:
		if f == null:
			return {}
	return {"dirs": dirs, "per_dir": per_dir, "frames": frames}


static func _texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)
```

- [ ] **Step 4: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_asset_locator` → `2 tests, 0 fallos`.

- [ ] **Step 5: Commit**

```bash
git add engine/assets/AssetLocator.gd tests/engine/test_asset_locator.gd
git commit -m "F1: AssetLocator para packs de sprites extraídos

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Shader de color de jugador + EntityView

**Files:**
- Create: `engine/render2d/player_color.gdshader`, `engine/render2d/EntityView.gd`
- Test: `tests/engine/test_entity_view.gd`

**Interfaces:**
- Consumes: `Iso.dir16/to_screen/TILE_W` (Task 5), `AssetLocator.sprite` (Task 6).
- Produces: `EntityView` (Node2D): `setup(id: int, def: Dictionary, color: Color, locator) -> void`; campos `entity_id`, `kind` ("unit"/"building"/...), `footprint: Vector2i`, `selected: bool`, `hp_ratio: float`; `update_view(moving: bool, facing_screen: Vector2, delta: float) -> void`; `has_sprite() -> bool`; `current_anim() -> String`; `current_slot() -> int`; `pick_radius() -> float`. La posición del nodo es el punto del suelo (pie de la unidad / centro del footprint); el sprite se dibuja con `offset = -hotspot`.

- [ ] **Step 1: Test que falla** — `tests/engine/test_entity_view.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const EntityView := preload("res://engine/render2d/EntityView.gd")
const AssetLocator := preload("res://engine/assets/AssetLocator.gd")
const ROOT := "user://test_assets_ev/sprites"


func _make_pack(anim: String, dirs: int) -> void:
	var dir := "%s/bar/%s" % [ROOT, anim]
	DirAccess.make_dir_recursive_absolute(dir)
	var frames := []
	for d in dirs:
		for s in 2:
			var name := "p_%03d.png" % (d * 2 + s)
			var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.5, 0.5, 0.5, 1))
			img.save_png(dir + "/" + name)
			frames.append({"png": name, "dir": d, "sub": s, "hotspot": [4, 7]})
	var f := FileAccess.open(dir + "/manifest.pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"dirs": dirs, "kept_per_dir": 2, "size": [8, 8], "frames": frames}))
	f.close()


func _unit_def() -> Dictionary:
	return {"id": "bar", "type": "unit", "graphics": {"idle": "sprite:bar/idle", "walk": "sprite:bar/walk"}}


func test_walk_and_idle_pick_direction() -> void:
	_make_pack("idle", 16)
	_make_pack("walk", 16)
	var v := EntityView.new()
	v.setup(7, _unit_def(), Color.RED, AssetLocator.new([ROOT]))
	assert_true(v.has_sprite())
	v.update_view(true, Vector2(1, 0), 0.016)
	assert_eq(v.current_anim(), "walk")
	assert_eq(v.current_slot(), 8)
	v.update_view(false, Vector2.ZERO, 0.016)
	assert_eq(v.current_anim(), "idle")
	assert_eq(v.current_slot(), 8, "quieto conserva el rumbo")
	v.free()


func test_view_without_sprites_draws_placeholder() -> void:
	var v := EntityView.new()
	v.setup(1, {"id": "casa", "type": "building", "footprint": [2, 2], "graphics": {"idle": "sprite:nada/idle"}}, Color.BLUE, AssetLocator.new([ROOT]))
	v.update_view(false, Vector2.ZERO, 0.016)
	assert_false(v.has_sprite())
	assert_eq(v.current_anim(), "")
	assert_eq(v.footprint, Vector2i(2, 2))
	assert_true(v.pick_radius() > 40.0)
	v.free()
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_entity_view` → Expected: FAIL.

- [ ] **Step 3: Implementar el shader** — `engine/render2d/player_color.gdshader`

```glsl
shader_type canvas_item;
// Tiñe con el color del jugador los píxeles marcados en la máscara del AoE2
// (m_*.png: alpha > 0 = zona teñible), conservando el sombreado del sprite.

uniform sampler2D mask_tex : filter_nearest;
uniform vec4 player_color : source_color = vec4(0.16, 0.29, 1.0, 1.0);
uniform bool has_mask = false;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (has_mask) {
		float m = texture(mask_tex, UV).a;
		float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		vec3 tinted = player_color.rgb * (lum * 1.5 + 0.2);
		c.rgb = mix(c.rgb, tinted, m);
	}
	COLOR = c;
}
```

- [ ] **Step 4: Implementar** — `engine/render2d/EntityView.gd`

```gdscript
extends Node2D
## Vista de una entidad (solo cliente): elige animación según el estado de la
## simulación, dirección por rumbo en pantalla (16 slots), tiñe con el color
## del jugador y dibuja selección / placeholder. La posición del nodo es el
## punto del suelo; el EntityLayer ordena por y.

const Iso := preload("res://engine/render2d/Iso.gd")
const PLAYER_SHADER := preload("res://engine/render2d/player_color.gdshader")
const FPS := {"walk": 10.0, "idle": 6.0, "task": 8.0, "attack": 10.0, "death": 8.0}

var entity_id := 0
var kind := "unit"
var footprint := Vector2i.ONE
var color := Color.WHITE
var selected := false:
	set(v):
		if v != selected:
			selected = v
			queue_redraw()
var hp_ratio := 1.0

var _graphics: Dictionary = {}
var _locator
var _anims: Dictionary = {}
var _anim := ""
var _t := 0.0
var _slot := 4
var _sprite: Sprite2D
var _mat: ShaderMaterial


func setup(id: int, def: Dictionary, p_color: Color, locator) -> void:
	entity_id = id
	kind = str(def.get("type", "unit"))
	color = p_color
	_locator = locator
	_graphics = def.get("graphics", {})
	if def.get("footprint") is Array:
		footprint = Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.visible = false
	_mat = ShaderMaterial.new()
	_mat.shader = PLAYER_SHADER
	_mat.set_shader_parameter("player_color", p_color)
	_sprite.material = _mat
	add_child(_sprite)


func has_sprite() -> bool:
	return not _pack("idle").is_empty() or not _pack("walk").is_empty()


func current_anim() -> String:
	return _anim


func current_slot() -> int:
	return _slot


func pick_radius() -> float:
	if kind == "building":
		return footprint.x * Iso.TILE_W * 0.35
	return 18.0


func update_view(moving: bool, facing_screen: Vector2, delta: float) -> void:
	if facing_screen.length_squared() > 0.0001:
		_slot = Iso.dir16(facing_screen)
	var want := "walk" if moving else "idle"
	if _pack(want).is_empty():
		want = "idle" if not _pack("idle").is_empty() else "walk"
	var pk := _pack(want)
	if pk.is_empty():
		_anim = ""
		if _sprite.visible:
			_sprite.visible = false
			queue_redraw()
		return
	if want != _anim:
		_anim = want
		_t = 0.0
	_t += delta
	var per_dir: int = pk["per_dir"]
	var dirs: int = pk["dirs"]
	var sub := int(_t * float(FPS.get(want, 8.0))) % maxi(1, per_dir)
	var d := (_slot * dirs) / 16 if dirs > 1 else 0
	var fr: Dictionary = pk["frames"][d * per_dir + sub]
	if not _sprite.visible:
		_sprite.visible = true
		queue_redraw()
	_sprite.texture = fr["tex"]
	_sprite.offset = -fr["hotspot"]
	_mat.set_shader_parameter("has_mask", fr["mask"] != null)
	if fr["mask"] != null:
		_mat.set_shader_parameter("mask_tex", fr["mask"])


func _pack(anim: String) -> Dictionary:
	if not _anims.has(anim):
		_anims[anim] = _locator.sprite(str(_graphics[anim])) if _graphics.has(anim) else {}
	return _anims[anim]


func _draw() -> void:
	var r := pick_radius()
	if selected:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not _sprite.visible:
		if kind == "building":
			var hw := footprint.x * 0.5
			var hh := footprint.y * 0.5
			var pts := PackedVector2Array([
				Iso.to_screen(Vector2(-hw, -hh)), Iso.to_screen(Vector2(hw, -hh)),
				Iso.to_screen(Vector2(hw, hh)), Iso.to_screen(Vector2(-hw, hh))])
			draw_colored_polygon(pts, color.darkened(0.35))
			pts.append(pts[0])
			draw_polyline(pts, color.lightened(0.3), 2.0)
		else:
			draw_circle(Vector2(0, -14), 9.0, color)
			draw_arc(Vector2(0, -14), 9.0, 0.0, TAU, 20, Color.BLACK, 1.5)
	if selected:
		var top := -(footprint.y * Iso.TILE_H + 60.0) if kind == "building" else -70.0
		draw_rect(Rect2(-16, top, 32, 4), Color(0.6, 0.0, 0.0))
		draw_rect(Rect2(-16, top, 32 * clampf(hp_ratio, 0.0, 1.0), 4), Color(0.1, 0.9, 0.1))
```

- [ ] **Step 5: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_entity_view` → `2 tests, 0 fallos`.

- [ ] **Step 6: Commit**

```bash
git add engine/render2d/player_color.gdshader engine/render2d/EntityView.gd tests/engine/test_entity_view.gd
git commit -m "F1: EntityView con animación, 16 direcciones y color de jugador

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: TerrainLayer, IsoCamera, SelectionOverlay, EntityLayer

**Files:**
- Create: `engine/render2d/TerrainLayer.gd`, `engine/render2d/IsoCamera.gd`, `engine/render2d/SelectionOverlay.gd`, `engine/render2d/EntityLayer.gd`
- Test: cubierto por `tests/engine/test_match_smoke.gd` (Task 9); este task se verifica con un test propio de EntityLayer.
- Test: `tests/engine/test_entity_layer.gd`

**Interfaces:**
- Consumes: `Sim` (Task 4: `world`, `def_for`), `EntityView` (Task 7), `Iso` (Task 5), `AssetLocator` (Task 6).
- Produces:
  - `TerrainLayer.setup(w: int, h: int)`.
  - `IsoCamera` (Camera2D): `bounds: Rect2`, `focus(screen_pos: Vector2)`.
  - `SelectionOverlay`: `show_rect(r: Rect2)`, `hide_rect()`.
  - `EntityLayer` (Node2D, `y_sort_enabled`): `bind(sim, locator, colors: Dictionary)`, `snapshot()`, `sync(alpha: float, delta: float)`, `views: Dictionary` (id → EntityView), `pick(world_pos: Vector2) -> int` (-1 si nada; prioriza unidades), `ids_in_rect(r: Rect2, owner: int) -> Array[int]` (unidades con Move del dueño cuyo punto de suelo está en el rect), `set_selected(ids: Array)`.

- [ ] **Step 1: Test que falla** — `tests/engine/test_entity_layer.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const EntityLayer := preload("res://engine/render2d/EntityLayer.gd")
const AssetLocator := preload("res://engine/assets/AssetLocator.gd")
const Iso := preload("res://engine/render2d/Iso.gd")


func _world() -> Array:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	var v := s.spawn("aldeano", 0, Vector2i(16, 16))
	var e := s.spawn("aldeano", 1, Vector2i(30, 30))
	var layer := EntityLayer.new()
	layer.bind(s, AssetLocator.new(["user://no_hay_sprites"]), {0: Color.BLUE, 1: Color.RED})
	layer.snapshot()
	layer.sync(1.0, 0.0)
	return [s, layer, tc, v, e]


func test_views_follow_sim_with_interpolation() -> void:
	var w := _world()
	var s: Sim = w[0]
	var layer = w[1]
	var v: int = w[3]
	assert_eq(layer.views.size(), 3)
	assert_eq(layer.views[v].position, Iso.milli_to_screen(Vector2i(16500, 16500)))
	s.queue_command(0, "move", {"ids": [v], "pos": [26500, 16500]})
	for i in 3:
		layer.snapshot()
		s.step()
	var prev: Vector2i = Vector2i(16500 + 80, 16500)
	var cur: Vector2i = s.world.entities[v]["pos"]
	layer.sync(0.5, 0.05)
	assert_true(layer.views[v].position.is_equal_approx(Iso.to_screen((Vector2(prev) + Vector2(cur)) / 2000.0)))
	assert_eq(layer.views[v].current_slot(), Iso.dir16(Iso.to_screen(Vector2(1, 0))))
	layer.free()


func test_pick_and_rect_selection() -> void:
	var w := _world()
	var layer = w[1]
	var tc: int = w[2]
	var v: int = w[3]
	var e: int = w[4]
	assert_eq(layer.pick(layer.views[v].position + Vector2(2, -10)), v)
	assert_eq(layer.pick(layer.views[tc].position), tc)
	assert_eq(layer.pick(Vector2(-5000, -5000)), -1)
	var all := Rect2(Vector2(-10000, -10000), Vector2(20000, 20000))
	assert_eq(layer.ids_in_rect(all, 0), [v], "solo unidades propias con Move")
	assert_eq(layer.ids_in_rect(all, 1), [e])
	layer.set_selected([v])
	assert_true(layer.views[v].selected)
	assert_false(layer.views[tc].selected)
	layer.free()


func test_despawned_entities_lose_view() -> void:
	var w := _world()
	var s: Sim = w[0]
	var layer = w[1]
	var e: int = w[4]
	s.world.despawn(e)
	layer.sync(1.0, 0.0)
	assert_false(layer.views.has(e))
	layer.free()
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_entity_layer` → Expected: FAIL.

- [ ] **Step 3: Implementar** — `engine/render2d/EntityLayer.gd`

```gdscript
extends Node2D
## Sincroniza una EntityView por entidad de Sim.world (solo lectura),
## interpola posiciones entre ticks y resuelve picking/selección.

const Iso := preload("res://engine/render2d/Iso.gd")
const EntityView := preload("res://engine/render2d/EntityView.gd")

var sim
var locator
var colors: Dictionary = {}
var views: Dictionary = {}
var _prev: Dictionary = {}


func _init() -> void:
	y_sort_enabled = true


func bind(p_sim, p_locator, p_colors: Dictionary) -> void:
	sim = p_sim
	locator = p_locator
	colors = p_colors


func snapshot() -> void:
	_prev.clear()
	for id in sim.world.entities:
		_prev[id] = sim.world.entities[id]["pos"]


func sync(alpha: float, delta: float) -> void:
	var w = sim.world
	for id in views.keys():
		if not w.entities.has(id):
			views[id].queue_free()
			views.erase(id)
	var ids: Array = w.entities.keys()
	ids.sort()
	var a := clampf(alpha, 0.0, 1.0)
	for id in ids:
		var e: Dictionary = w.entities[id]
		var v = views.get(id)
		if v == null:
			v = EntityView.new()
			v.setup(id, sim.def_for(id), colors.get(e["owner"], Color(0.6, 0.6, 0.6)), locator)
			add_child(v)
			views[id] = v
		var cur: Vector2i = e["pos"]
		var prev: Vector2i = _prev.get(id, cur)
		v.position = Iso.to_screen(Vector2(prev).lerp(Vector2(cur), a) / 1000.0)
		var m: Dictionary = w.comp(id, "Move")
		var moving := false
		var facing := Vector2.ZERO
		if not m.is_empty():
			moving = m["moving"] or prev != cur
			facing = Iso.to_screen(Vector2(m["facing"]))
		var hp: Dictionary = w.comp(id, "Hitpoints")
		if not hp.is_empty() and int(hp["max"]) > 0:
			v.hp_ratio = float(hp["hp"]) / float(hp["max"])
		v.update_view(moving, facing, delta)


## Entidad bajo el punto (coordenadas de mundo del canvas). Prioriza unidades.
func pick(world_pos: Vector2) -> int:
	var best := -1
	var best_score := INF
	for id in views:
		var v = views[id]
		var local: Vector2 = world_pos - v.position
		var d: float
		if v.kind == "building":
			d = Vector2(local.x, local.y * 2.0).length()
		else:
			d = Vector2(local.x, local.y + 28.0).length() * 0.5
		if d <= v.pick_radius() * (1.0 if v.kind == "building" else 1.5) and d < best_score:
			best_score = d
			best = id
	return best


func ids_in_rect(r: Rect2, owner: int) -> Array[int]:
	var out: Array[int] = []
	var box := r.abs()
	for id in views:
		var e: Dictionary = sim.world.entities.get(id, {})
		if e.is_empty() or int(e["owner"]) != owner or not sim.world.has_ability(id, "Move"):
			continue
		if box.has_point(views[id].position):
			out.append(id)
	out.sort()
	return out


func set_selected(ids: Array) -> void:
	for id in views:
		views[id].selected = ids.has(id)
```

- [ ] **Step 4: Implementar** — `engine/render2d/TerrainLayer.gd`

```gdscript
extends Node2D
## Terreno procedural (placeholder hasta F1b): rombos de hierba con variación
## suave. Se dibuja una vez (Godot cachea el _draw).

const Iso := preload("res://engine/render2d/Iso.gd")
const GRASS_A := Color(0.36, 0.52, 0.22)
const GRASS_B := Color(0.30, 0.45, 0.19)
const DRY := Color(0.52, 0.50, 0.30)

var width := 0
var height := 0


func setup(w: int, h: int) -> void:
	width = w
	height = h
	z_index = -100
	queue_redraw()


func _draw() -> void:
	for y in height:
		for x in width:
			var coarse := float(absi(hash(Vector2i(x / 6, y / 6))) % 100) / 100.0
			var fine := float(absi(hash(Vector2i(x, y))) % 100) / 100.0
			var c := GRASS_A.lerp(GRASS_B, fine * 0.6).lerp(DRY, coarse * coarse * 0.35)
			var pts := PackedVector2Array([
				Iso.to_screen(Vector2(x, y)), Iso.to_screen(Vector2(x + 1, y)),
				Iso.to_screen(Vector2(x + 1, y + 1)), Iso.to_screen(Vector2(x, y + 1))])
			draw_colored_polygon(pts, c)
```

- [ ] **Step 5: Implementar** — `engine/render2d/IsoCamera.gd`

```gdscript
extends Camera2D
## Cámara estilo AoE2: flechas y borde de pantalla para desplazar, botón
## medio para arrastrar, rueda para zoom. (WASD queda libre para atajos.)

const PAN_SPEED := 900.0
const EDGE := 12.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0

var bounds := Rect2()
var edge_scroll := true
var _drag := false
var _target_zoom := 1.0


func focus(screen_pos: Vector2) -> void:
	position = screen_pos


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if edge_scroll and DisplayServer.window_is_focused():
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		if mp.x < EDGE:
			dir.x -= 1
		elif mp.x > vs.x - EDGE:
			dir.x += 1
		if mp.y < EDGE:
			dir.y -= 1
		elif mp.y > vs.y - EDGE:
			dir.y += 1
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * delta / zoom.x
	zoom = zoom.lerp(Vector2.ONE * _target_zoom, clampf(delta * 10.0, 0.0, 1.0))
	if bounds.has_area():
		position = position.clamp(bounds.position, bounds.end)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_target_zoom = clampf(_target_zoom * 1.1, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_target_zoom = clampf(_target_zoom / 1.1, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = event.pressed
	elif event is InputEventMouseMotion and _drag:
		position -= event.relative / zoom.x
```

- [ ] **Step 6: Implementar** — `engine/render2d/SelectionOverlay.gd`

```gdscript
extends Node2D
## Rectángulo de selección por arrastre (coordenadas de mundo del canvas).

var _rect := Rect2()
var _active := false


func _init() -> void:
	z_index = 100


func show_rect(r: Rect2) -> void:
	_rect = r.abs()
	_active = true
	queue_redraw()


func hide_rect() -> void:
	_active = false
	queue_redraw()


func _draw() -> void:
	if _active:
		draw_rect(_rect, Color(1, 1, 1, 0.08), true)
		draw_rect(_rect, Color(1, 1, 1, 0.9), false, 1.5)
```

- [ ] **Step 7: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_entity_layer` → `3 tests, 0 fallos`.

- [ ] **Step 8: Commit**

```bash
git add engine/render2d/EntityLayer.gd engine/render2d/TerrainLayer.gd engine/render2d/IsoCamera.gd engine/render2d/SelectionOverlay.gd tests/engine/test_entity_layer.gd
git commit -m "F1: EntityLayer, terreno, cámara iso y overlay de selección

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Escena Match + botón en el menú

**Files:**
- Create: `game/scenes/Match.gd`, `game/scenes/Match.tscn`
- Modify: `ui/menus/MainMenu.gd` (botón y handler)
- Test: `tests/engine/test_match_smoke.gd`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: escena `res://game/scenes/Match.tscn` (root Node2D con `Match.gd`); API de prueba: `sim`, `layer`, `local_pid`, `selected: Array[int]`, `tick_once()`, `issue_move(tiles: Vector2)`, `select(ids: Array)`; argumentos de usuario `--screenshot=<ruta.png> --frames=<n>` guardan captura y salen (para verificación visual).

- [ ] **Step 1: Test que falla** — `tests/engine/test_match_smoke.gd`

```gdscript
extends "res://tests/engine/TestCase.gd"

const MATCH := "res://game/scenes/Match.tscn"


func test_match_spawns_and_moves() -> void:
	var m = load(MATCH).instantiate()
	Engine.get_main_loop().root.add_child(m)
	assert_eq(m.sim.players.size(), 2)
	var villagers: Array = []
	var tcs := 0
	for id in m.sim.world.entities:
		var d: String = m.sim.world.entities[id]["def_id"]
		if d == "aldeano" and m.sim.world.entities[id]["owner"] == m.local_pid:
			villagers.append(id)
		elif d == "centro_urbano":
			tcs += 1
	assert_eq(tcs, 2)
	assert_eq(villagers.size(), 3)
	villagers.sort()
	m.select([villagers[0]])
	assert_true(m.layer.views[villagers[0]].selected)
	var start: Vector2i = m.sim.world.entities[villagers[0]]["pos"]
	var goal := Vector2(start) / 1000.0 + Vector2(6, 0)
	m.issue_move(goal)
	for i in 120:
		m.tick_once()
	var end: Vector2i = m.sim.world.entities[villagers[0]]["pos"]
	assert_true(Vector2(end).distance_to(goal * 1000.0) < 2.0, "llegó: %s" % end)
	m.queue_free()
```

- [ ] **Step 2: Correr y ver que falla**

Run: `sh tests/engine/run.sh test_match_smoke` → Expected: FAIL (escena no existe).

- [ ] **Step 3: Implementar** — `game/scenes/Match.gd`

```gdscript
extends Node2D
## Partida local con el motor nuevo (F1): terreno iso, centros urbanos y
## aldeanos; selección con clic/arrastre y movimiento con clic derecho.
## Simulación a 10 Hz; el render interpola entre ticks.

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const World := preload("res://engine/sim/World.gd")
const AssetLocator := preload("res://engine/assets/AssetLocator.gd")
const Iso := preload("res://engine/render2d/Iso.gd")
const TerrainLayer := preload("res://engine/render2d/TerrainLayer.gd")
const EntityLayer := preload("res://engine/render2d/EntityLayer.gd")
const IsoCamera := preload("res://engine/render2d/IsoCamera.gd")
const SelectionOverlay := preload("res://engine/render2d/SelectionOverlay.gd")

const MAP_SIZE := 144
const START_OFFSETS: Array[Vector2i] = [
	Vector2i(-33, -33), Vector2i(33, 33), Vector2i(33, -33), Vector2i(-33, 33),
	Vector2i(0, -46), Vector2i(0, 46), Vector2i(-46, 0), Vector2i(46, 0),
]
const VILLAGER_OFFSETS: Array[Vector2i] = [Vector2i(3, -1), Vector2i(-1, 3), Vector2i(3, 3)]
const SLOTS := [{"civ": "britones", "team": 0}, {"civ": "francos", "team": 1}]
const PLAYER_COLORS: Array[Color] = [
	Color("#2a4bff"), Color("#ff2020"), Color("#20c020"), Color("#ffe020"),
	Color("#00c8ff"), Color("#c800ff"), Color("#969696"), Color("#ff8c00"),
]
const DRAG_MIN := 6.0

var local_pid := 0
var registry
var sim
var layer
var cam
var overlay
var selected: Array[int] = []

var _acc := 0.0
var _press_pos := Vector2.ZERO
var _pressing := false
var _shot_path := ""
var _shot_frames := 0
var _frames := 0


func _ready() -> void:
	registry = Registry.new()
	if not registry.load_mods("res://mods"):
		_show_error("Error cargando mods:\n" + "\n".join(PackedStringArray(registry.errors.slice(0, 8))))
		return
	sim = Sim.new(registry, MAP_SIZE, MAP_SIZE)
	for i in SLOTS.size():
		sim.add_player(i, SLOTS[i]["civ"], SLOTS[i]["team"])
	_spawn_start()

	var terrain := TerrainLayer.new()
	add_child(terrain)
	terrain.setup(MAP_SIZE, MAP_SIZE)
	layer = EntityLayer.new()
	add_child(layer)
	var colors := {}
	for i in sim.players.size():
		colors[i] = PLAYER_COLORS[i % PLAYER_COLORS.size()]
	layer.bind(sim, AssetLocator.new(), colors)
	overlay = SelectionOverlay.new()
	add_child(overlay)

	cam = IsoCamera.new()
	add_child(cam)
	var left := Iso.to_screen(Vector2(0, MAP_SIZE))
	var right := Iso.to_screen(Vector2(MAP_SIZE, 0))
	var bottom := Iso.to_screen(Vector2(MAP_SIZE, MAP_SIZE))
	cam.bounds = Rect2(Vector2(left.x, 0), Vector2(right.x - left.x, bottom.y))
	cam.focus(Iso.to_screen(Vector2(_start_tile(local_pid))))
	cam.make_current()

	_build_help()
	layer.snapshot()
	layer.sync(1.0, 0.0)
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--screenshot="):
			_shot_path = s.get_slice("=", 1)
		elif s.begins_with("--frames="):
			_shot_frames = int(s.get_slice("=", 1))


func tick_once() -> void:
	layer.snapshot()
	sim.step()
	layer.sync(1.0, 0.0)


func select(ids: Array) -> void:
	selected.clear()
	for id in ids:
		selected.append(int(id))
	layer.set_selected(selected)


func issue_move(tiles: Vector2) -> void:
	if selected.is_empty():
		return
	sim.queue_command(local_pid, "move", {"ids": selected.duplicate(), "pos": [int(round(tiles.x * 1000.0)), int(round(tiles.y * 1000.0))]})


func _process(delta: float) -> void:
	if sim == null:
		return
	var dt := 1.0 / World.TICK_RATE
	_acc += delta
	while _acc >= dt:
		layer.snapshot()
		sim.step()
		_acc -= dt
	layer.sync(_acc / dt, delta)
	_frames += 1
	if _shot_path != "" and _frames >= maxi(1, _shot_frames):
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("[Match] captura guardada en ", ProjectSettings.globalize_path(_shot_path))
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://ui/menus/MainMenu.tscn")
		return
	if event is InputEventMouseButton:
		var wp := get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressing = true
				_press_pos = wp
			elif _pressing:
				_pressing = false
				overlay.hide_rect()
				if wp.distance_to(_press_pos) < DRAG_MIN:
					var id: int = layer.pick(wp)
					if id >= 0 and int(sim.world.entities[id]["owner"]) == local_pid:
						select([id])
					else:
						select([])
				else:
					select(layer.ids_in_rect(Rect2(_press_pos, wp - _press_pos), local_pid))
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			issue_move(Iso.to_tiles(wp))
	elif event is InputEventMouseMotion and _pressing:
		var wp2 := get_global_mouse_position()
		if wp2.distance_to(_press_pos) >= DRAG_MIN:
			overlay.show_rect(Rect2(_press_pos, wp2 - _press_pos))


func _start_tile(pid: int) -> Vector2i:
	return Vector2i(MAP_SIZE / 2, MAP_SIZE / 2) + START_OFFSETS[pid % START_OFFSETS.size()]


func _spawn_start() -> void:
	for i in sim.players.size():
		var c := _start_tile(i)
		sim.spawn("centro_urbano", i, c - Vector2i(2, 2))
		for off in VILLAGER_OFFSETS:
			sim.spawn("aldeano", i, c + off)


func _build_help() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var l := Label.new()
	l.text = "Motor nuevo (F1) — clic izq: seleccionar / arrastrar · clic der: mover · flechas/borde/botón medio: cámara · rueda: zoom · Esc: menú"
	l.position = Vector2(12, 8)
	l.add_theme_color_override("font_color", Color(1, 0.92, 0.7))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	ui.add_child(l)


func _show_error(msg: String) -> void:
	push_error(msg)
	var ui := CanvasLayer.new()
	add_child(ui)
	var l := Label.new()
	l.text = msg
	l.position = Vector2(20, 20)
	ui.add_child(l)
```

`game/scenes/Match.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://game/scenes/Match.gd" id="1"]

[node name="Match" type="Node2D"]
script = ExtResource("1")
```

Nota: en `_spawn_start` el TC ocupa `c-2 .. c+1`; los aldeanos en `c+(3,-1)`, `c+(-1,3)`, `c+(3,3)` quedan fuera del footprint.

- [ ] **Step 4: Botón en el menú** — en `ui/menus/MainMenu.gd`, después de `_add_btn(vb, "Opciones", _on_options)` añadir:

```gdscript
	_add_btn(vb, "Partida (nuevo motor, beta)", _on_new_engine)
```

y al final del archivo:

```gdscript
func _on_new_engine() -> void:
	get_tree().change_scene_to_file("res://game/scenes/Match.tscn")
```

- [ ] **Step 5: Correr y ver que pasa**

Run: `sh tests/engine/run.sh test_match_smoke` → `1 tests, 0 fallos`.
Run: `sh tests/engine/run.sh` → todos en verde.

- [ ] **Step 6: Verificación visual**

Run (ventana, no headless; sin `_console` también sirve):

```bash
"$GODOT" --path . res://game/scenes/Match.tscn -- --screenshot=user://f1_match.png --frames=90
```

Expected: imprime `[Match] captura guardada en .../f1_match.png`. Abrir la imagen: terreno isométrico verde, el TC azul del jugador 0 centrado con 3 aldeanos (sprites AoE2 con ropa azul si hay packs extraídos; círculos azules si no). Si los sprites salen sin tinte, verificar que `m_*.png` existe en el pack (solo lo traen los edificios hoy; el aldeano del pack actual no trae máscara: queda sin tinte y es esperado).

- [ ] **Step 7: Commit**

```bash
git add game/scenes/Match.gd game/scenes/Match.tscn ui/menus/MainMenu.gd tests/engine/test_match_smoke.gd
git commit -m "F1: escena Match con el motor nuevo y botón en el menú

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Suite completa y documentación

**Files:**
- Modify: `docs/SPRITES.md` (sección "Motor nuevo"), `README.md` (línea en "Estado")

- [ ] **Step 1: Documentar** — añadir al final de `docs/SPRITES.md`:

```markdown
## Motor nuevo (F1)

- Las definiciones en `mods/aoe2_base` referencian sprites como `"sprite:<pack>/<anim>"`
  (p. ej. `"sprite:villager/walk"`). `engine/assets/AssetLocator.gd` los busca en
  `user://aoe2_assets/sprites/<pack>/<anim>/` y luego en `res://assets/sprites/<pack>/<anim>/`.
- Formato: el mismo `manifest.pack.json` + `p_*.png` (+ `m_*.png` máscara) de `--pack`.
- Proyección isométrica 2:1 con casilla de 96×48 (sprites `x1`). Direcciones: 16 slots,
  W=0 antihorario (S=4, E=8, N=12). Sin pack, el render dibuja un placeholder.
- Probar: menú → "Partida (nuevo motor, beta)", o
  `godot --path . res://game/scenes/Match.tscn -- --screenshot=user://f1.png --frames=90`.
```

y en `README.md`, bajo "## Estado final — qué está implementado", añadir como primera línea:

```markdown
> **Reestructura en curso** (`docs/superpowers/`): motor nuevo por habilidades (`engine/`, `mods/aoe2_base`) con render 2D isométrico — menú "Partida (nuevo motor, beta)". El juego descrito abajo sigue siendo el modo por defecto hasta la fase F5.
```

- [ ] **Step 2: Suite completa**

Run: `sh tests/run_all.sh 600` → Expected: `Motor nuevo: PASS`, `Lan8Bots: PASS`, `BalanceTester: PASS`, `RESULTADO: PASS`.
Run: `python -m unittest discover -s tools/tests` → `OK`.

- [ ] **Step 3: Commit**

```bash
git add docs/SPRITES.md README.md
git commit -m "F1: documentación del motor nuevo y sprites

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Qué queda para después

- **F1b**: importador dentro del juego (detectar la instalación del AoE2 DE, extraer a `user://aoe2_assets`), texturas de terreno del DE, packs faltantes (edificios de todas las edades, más unidades).
- **F2**: recolección (Gather/DropSite/ResourceSource), árboles/minas en el mapa, barra superior de recursos.

extends Control
class_name Minimap
## Minimap — minimapa AoE2 para OpenAge-LAN (Godot 4.4, GDScript).
##
## Control de 200x200 anclado abajo-izquierda. Todo el dibujado se hace en
## [_draw] (una sola pasada, ~30 fps SOLO CLIENTE):
##   1. Terreno de fondo (textura si hay, si no color base Arabia).
##   2. Recursos: blanco genérico, amarillo oro, gris piedra, verde bosque,
##      azul agua.
##   3. Unidades 2px / edificios 4px con color de jugador (SimAPI).
##   4. Ataques: rojo parpadeante (solo cliente, con Time).
##   5. Niebla vía FogOfWar: negro opaco no explorado, velo oscuro explorado.
##   6. Marco vista de cámara + pings.
##
## Interacción:
##   - Click izq / arrastrar: mueve la cámara (XZ mundo).
##   - Alt+Click izq: ping -> EventBus.minimap_ping(pid, world_pos).
##
## SOLO CLIENTE: en headless (servidor dedicado) desactiva refresco e input.
## Nunca toca SimAPI/GameManager en lógica: solo lee colores/posiciones para
## pintar. Los datos se inyectan con setters o se autodetectan por grupos:
##   "minimap_units" (Node3D/Node2D o dicts), "minimap_buildings", "fog_of_war".
##
## Uso mínimo desde HUD:
##   var mm := Minimap.new()
##   mm.local_player_id = 0
##   minimap_slot.add_child(mm)

const MINIMAP_SIZE := Vector2(200, 200)
const GRID_W := 144
const GRID_H := 144
const REFRESH_FPS := 30.0
const FOG_REFRESH_SEC := 0.5
const ATTACK_LIFETIME_SEC := 5.0
const PING_LIFETIME_SEC := 5.0
const BLINK_PERIOD_SEC := 1.0 # rojo visible 0.5s / oculto 0.5s

# Terreno base Arabia (desierto_hierba) cuando no hay textura inyectada.
const COL_TERRAIN := Color(0.42, 0.44, 0.22, 1.0)
const COL_RESOURCE := Color(1, 1, 1, 1) # genérico (bayas/caza/pesca/comida)
const COL_GOLD := Color(1.0, 0.84, 0.0, 1.0) # oro
const COL_STONE := Color(0.62, 0.62, 0.62, 1.0) # piedra
const COL_FOREST := Color(0.08, 0.55, 0.18, 1.0) # bosque / madera
const COL_WATER := Color(0.15, 0.35, 0.85, 1.0) # agua
const COL_ATTACK := Color(1, 0, 0, 1) # ataque (parpadeante)
const COL_VIEWPORT := Color(1, 1, 1, 0.9) # marco de cámara
const COL_PING := Color(1.0, 0.9, 0.0, 1.0) # ping propio/aliado
const COL_FOG_EXPLORED := Color(0, 0, 0, 0.55) # velo memoria
const COL_FOG_UNEXPLORED := Color(0, 0, 0, 1.0) # negro total
const FALLBACK_COLORS := ["#2a4bff", "#ff0000", "#00ff00", "#ffff00",
	"#00c8ff", "#c800ff", "#969696", "#ff8c00"]

## Jugador local (niebla + color ping). Se lee de NetManager si < 0.
@export var local_player_id := 0
## Lado del mundo en unidades (debe coincidir con FogOfWar.world_size).
@export var world_size := 288.0
## Nodo FogOfWar (si vacío se busca en grupo "fog_of_war").
@export var fog_node: Node
## Cámara a mover (si vacío: viewport.get_camera_3d()).
@export var camera_node: Camera3D
## Textura de terreno opcional (estirada a 200x200). Alternativa a color plano.
@export var terrain_texture: Texture2D

# Datos inyectables (solo lectura visual). Formatos aceptados por entrada:
# {pos: Vector2(XZ mundo), player_id: int} para unidades/edificios.
# {pos: Vector2(XZ mundo), kind: String} para recursos.
var units: Array = []
var buildings: Array = []
var resources: Array = []
# Celdas opcionales de agua/bosque en coords 0..143: [Vector2i, ...].
var water_cells: Array = []
var forest_cells: Array = []

var _attacks: Array = [] # [{pos: Vector2 mundo, until_msec: int}]
var _pings: Array = [] # [{pos: Vector2 mundo, color: Color, until_msec: int}]
var _fog_tex: Texture2D
var _refresh_accum := 0.0
var _fog_accum := 0.0
var _dragging := false
var _is_headless := false


func _ready() -> void:
	_is_headless = DisplayServer.get_name() == "headless"
	custom_minimum_size = MINIMAP_SIZE
	size = MINIMAP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Arriba-izquierda del padre. GameWorld lo mete en un SubViewport 200x200
	# (ahi debe empezar en 0,0); si se usa suelto en el HUD, el slot lo coloca.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	_resolve_refs()
	if _is_headless:
		set_process(false)
		set_process_input(false)
	else:
		# Pings remotos también se dibujan aquí.
		var eb := get_node_or_null("/root/EventBus")
		if eb != null and not eb.minimap_ping.is_connected(_on_remote_ping):
			eb.minimap_ping.connect(_on_remote_ping)


func _resolve_refs() -> void:
	if fog_node == null:
		var f := get_tree().get_first_node_in_group("fog_of_war")
		if f != null:
			fog_node = f
		else:
			fog_node = get_node_or_null("../FogOfWar")
	if fog_node != null and fog_node.has_signal("fog_rebuilt"):
		if not fog_node.fog_rebuilt.is_connected(_on_fog_rebuilt):
			fog_node.fog_rebuilt.connect(_on_fog_rebuilt)
	if camera_node == null:
		camera_node = get_viewport().get_camera_3d()


func _process(delta: float) -> void:
	if _is_headless:
		return
	_refresh_accum += delta
	_fog_accum += delta
	if _fog_accum >= FOG_REFRESH_SEC:
		_fog_accum = 0.0
		_refresh_fog_texture()
	if _refresh_accum >= 1.0 / REFRESH_FPS:
		_refresh_accum = 0.0
		_prune_expired()
		queue_redraw()


# ------------------------------------------------------------- setters ---

func set_units(arr: Array) -> void:
	units = arr

func set_buildings(arr: Array) -> void:
	buildings = arr

func set_resources(arr: Array) -> void:
	resources = arr

func set_terrain_texture(tex: Texture2D) -> void:
	terrain_texture = tex
	queue_redraw()

func set_local_player(pid: int) -> void:
	local_player_id = pid
	_fog_tex = null
	_refresh_fog_texture()
	queue_redraw()

func set_fog(p_fog: Node) -> void:
	fog_node = p_fog
	_fog_tex = null
	_refresh_fog_texture()
	queue_redraw()


## Aviso de ataque (punto rojo parpadeante `ATTACK_LIFETIME_SEC`).
## `world_pos`: XZ del mundo como Vector2.
func notify_attack(world_pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	_attacks.append({"pos": world_pos, "until_msec": now + int(ATTACK_LIFETIME_SEC * 1000.0)})
	queue_redraw()


func clear_attacks() -> void:
	_attacks.clear()
	queue_redraw()


func clear_pings() -> void:
	_pings.clear()
	queue_redraw()


# ---------------------------------------------------------- conversión ---

func world_to_map(world_pos: Vector2) -> Vector2:
	var fx := clampf(world_pos.x / world_size, 0.0, 1.0)
	var fy := clampf(world_pos.y / world_size, 0.0, 1.0)
	return Vector2(fx * size.x, fy * size.y)


func map_to_world(map_pos: Vector2) -> Vector2:
	var fx := clampf(map_pos.x / maxf(1.0, size.x), 0.0, 1.0)
	var fy := clampf(map_pos.y / maxf(1.0, size.y), 0.0, 1.0)
	return Vector2(fx * world_size, fy * world_size)


func _world_pos_of(entry) -> Vector2:
	# Acepta Dictionary {pos} o Node2D/Node3D (usa XZ en 3D).
	if entry is Dictionary:
		var p = (entry as Dictionary).get("pos", Vector2.ZERO)
		if p is Vector2:
			return p
		if p is Vector3:
			return Vector2((p as Vector3).x, (p as Vector3).z)
		if p is Vector2i:
			return Vector2(p)
		return Vector2.ZERO
	if entry is Node3D:
		var gp := (entry as Node3D).global_position
		return Vector2(gp.x, gp.z)
	if entry is Node2D:
		return (entry as Node2D).global_position
	if entry is Vector2:
		return entry
	return Vector2.ZERO


func get_player_color(pid: int) -> Color:
	var sim := get_node_or_null("/root/SimAPI")
	if sim != null and sim.has_method("get_player_color"):
		return sim.get_player_color(pid) as Color
	return Color(FALLBACK_COLORS[abs(pid) % FALLBACK_COLORS.size()])


func _resource_color(kind: String) -> Color:
	var k := kind.to_lower().strip_edges()
	match k:
		"gold", "oro", "gold_mine", "gold_pile":
			return COL_GOLD
		"stone", "piedra", "stone_mine", "stone_pile":
			return COL_STONE
		"wood", "madera", "tree", "trees", "forest", "bosque", "wood_patch":
			return COL_FOREST
		"water", "agua", "shore_fish", "fish", "deep_fish":
			return COL_WATER
	return COL_RESOURCE


# ---------------------------------------------------------------- _draw ---

func _draw() -> void:
	# 1) Terreno de fondo.
	if terrain_texture != null:
		draw_texture_rect(terrain_texture, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), COL_TERRAIN)
	# Agua/bosque base (cuando no hay textura de terreno).
	var cell_px := Vector2(size.x / float(GRID_W), size.y / float(GRID_H))
	for c in water_cells:
		if c is Vector2i:
			draw_rect(Rect2(Vector2(float(c.x) * cell_px.x, float(c.y) * cell_px.y), cell_px), COL_WATER)
	for c in forest_cells:
		if c is Vector2i:
			draw_rect(Rect2(Vector2(float(c.x) * cell_px.x, float(c.y) * cell_px.y), cell_px), COL_FOREST)
	# 2) Recursos.
	for r in resources + _auto_resources():
		var pos := _world_pos_of(r)
		var kind := str((r as Dictionary).get("kind", (r as Dictionary).get("resource", (r as Dictionary).get("def_id", "")))) if r is Dictionary else ""
		draw_rect(Rect2(world_to_map(pos) - Vector2(1, 1), Vector2(2, 2)), _resource_color(kind))
	# 3) Unidades 2px + edificios 4px con color de jugador.
	for u in units + _auto_group_entries("minimap_units"):
		var pid := int((u as Dictionary).get("player_id", (u as Dictionary).get("owner", 0))) if u is Dictionary else _owner_of(u)
		draw_rect(Rect2(world_to_map(_world_pos_of(u)) - Vector2(1, 1), Vector2(2, 2)), get_player_color(pid))
	for b in buildings + _auto_group_entries("minimap_buildings"):
		var pid := int((b as Dictionary).get("player_id", (b as Dictionary).get("owner", 0))) if b is Dictionary else _owner_of(b)
		draw_rect(Rect2(world_to_map(_world_pos_of(b)) - Vector2(2, 2), Vector2(4, 4)), get_player_color(pid))
	# 4) Ataques: rojo parpadeante (solo cliente; Time permitido en visual).
	if not _is_headless:
		var phase := fmod(Time.get_ticks_msec() / 1000.0, BLINK_PERIOD_SEC) < BLINK_PERIOD_SEC * 0.5
		if phase:
			var now := Time.get_ticks_msec()
			for a in _attacks:
				if int((a as Dictionary).get("until_msec", 0)) < now:
					continue
				var mp := world_to_map((a as Dictionary).get("pos", Vector2.ZERO))
				draw_rect(Rect2(mp - Vector2(2, 2), Vector2(4, 4)), COL_ATTACK)
	# 5) Pings (amarillos, con borde para verse sobre niebla).
	for p in _pings:
		var mp := world_to_map((p as Dictionary).get("pos", Vector2.ZERO))
		var col: Color = (p as Dictionary).get("color", COL_PING)
		draw_arc(mp, 5.0, 0.0, TAU, 16, col, 2.0)
		draw_circle(mp, 1.5, col)
	# 6) Niebla encima de todo lo anterior (no tapa pings/ataques si hay
	# textura; con fallback por celda se dibuja antes que pings... aquí va
	# encima del terreno y debajo de los marcadores ya pintados arriba, pero
	# el orden elegido prioriza ver amenazas/pings sobre la niebla).
	_draw_fog()
	# 7) Marco de vista de cámara + borde.
	_draw_viewport_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 1), false, 1.0)


func _draw_fog() -> void:
	if fog_node == null:
		return
	var pid := _effective_pid()
	# Vía rápida: overlay 144x144 cacheado como textura (1 draw call).
	if _fog_tex != null:
		draw_texture_rect(_fog_tex, Rect2(Vector2.ZERO, size), false)
		return
	if not fog_node.has_method("get_state"):
		return
	# Fallback: rect por celda no-visible (mapas pequeños / sin Image).
	var cell_px := Vector2(size.x / float(GRID_W), size.y / float(GRID_H))
	for y in GRID_H:
		for x in GRID_W:
			var st := int(fog_node.get_state(pid, x, y))
			if st == 2: # visible
				continue
			elif st == 1: # explorado: velo
				draw_rect(Rect2(Vector2(float(x) * cell_px.x, float(y) * cell_px.y), cell_px), COL_FOG_EXPLORED)
			else: # 0 / -1: negro
				draw_rect(Rect2(Vector2(float(x) * cell_px.x, float(y) * cell_px.y), cell_px), COL_FOG_UNEXPLORED)


func _draw_viewport_rect() -> void:
	var cam := camera_node
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	# Aproxima el área visible con el tamaño ortográfico (XZ mundo -> mapa).
	var half := 11.0
	if cam is Camera3D:
		half = float((cam as Camera3D).size) * 0.5
	var cp := Vector2(cam.global_position.x, cam.global_position.z)
	var top_left := world_to_map(cp - Vector2(half, half))
	var rect_size := Vector2(half * 2.0 / world_size * size.x, half * 2.0 / world_size * size.y)
	draw_rect(Rect2(top_left, rect_size), COL_VIEWPORT, false, 1.0)


# --------------------------------------------------------------- niebla ---

func _effective_pid() -> int:
	if local_player_id >= 0:
		return local_player_id
	var net := get_node_or_null("/root/NetManager")
	if net != null:
		return int(net.get("my_id")) - 1 # NetManager.my_id es 1-based (host=1)
	return 0


func _refresh_fog_texture() -> void:
	if _is_headless or fog_node == null or not fog_node.has_method("get_fog_texture"):
		return
	_fog_tex = fog_node.get_fog_texture(_effective_pid()) as Texture2D


func _on_fog_rebuilt(_tick: int) -> void:
	if fog_node != null and fog_node.has_method("refresh_visual"):
		_fog_tex = fog_node.refresh_visual(_effective_pid()) as Texture2D
	else:
		_refresh_fog_texture()


func _prune_expired() -> void:
	var now := Time.get_ticks_msec()
	for i in range(_attacks.size() - 1, -1, -1):
		if int((_attacks[i] as Dictionary).get("until_msec", 0)) < now:
			_attacks.remove_at(i)
	for i in range(_pings.size() - 1, -1, -1):
		if int((_pings[i] as Dictionary).get("until_msec", 0)) < now:
			_pings.remove_at(i)


# --------------------------------------------------------------- grupos ---

func _owner_of(n: Node) -> int:
	if n != null and n.get("player_id") != null:
		return int(n.get("player_id"))
	if n != null and n.get("owner_id") != null:
		return int(n.get("owner_id"))
	return 0


func _auto_group_entries(group: String) -> Array:
	if units.is_empty() and buildings.is_empty():
		pass # igual consultamos grupos: sirven como fuente por defecto
	var out: Array = []
	var tree := get_tree()
	if tree == null:
		return out
	for n in tree.get_nodes_in_group(group):
		out.append(n)
	return out


func _auto_resources() -> Array:
	var tree := get_tree()
	if tree == null or not resources.is_empty():
		return []
	var out: Array = []
	for n in tree.get_nodes_in_group("minimap_resources"):
		out.append(n)
	return out


# ---------------------------------------------------------------- input ---

func _gui_input(event: InputEvent) -> void:
	if _is_headless:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_handle_minimap_click(mb.position, mb.alt_pressed)
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var alt := Input.is_key_pressed(KEY_ALT)
		_handle_minimap_click(mm.position, alt)


func _handle_minimap_click(map_pos: Vector2, alt_pressed: bool) -> void:
	var world_pos := map_to_world(map_pos)
	if alt_pressed:
		# Alt+Click: ping para el equipo (no mueve cámara).
		_add_local_ping(world_pos)
		var eb := get_node_or_null("/root/EventBus")
		if eb != null and eb.has_signal("minimap_ping"):
			eb.emit_signal("minimap_ping", _effective_pid(), world_pos)
	else:
		_move_camera_to(world_pos)


func _move_camera_to(world_pos: Vector2) -> void:
	var cam := camera_node
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	var wx := clampf(world_pos.x, 0.0, world_size)
	var wz := clampf(world_pos.y, 0.0, world_size)
	# Mantiene altura/yaw AoE2: solo traslada XZ.
	cam.global_position = Vector3(wx, cam.global_position.y, wz)


func _add_local_ping(world_pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	_pings.append({"pos": world_pos, "color": COL_PING,
		"until_msec": now + int(PING_LIFETIME_SEC * 1000.0)})
	queue_redraw()


func _on_remote_ping(pid: int, world_pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	_pings.append({"pos": world_pos, "color": get_player_color(pid),
		"until_msec": now + int(PING_LIFETIME_SEC * 1000.0)})
	queue_redraw()

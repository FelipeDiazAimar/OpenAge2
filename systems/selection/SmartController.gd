extends Control
# SmartController - click derecho inteligente estilo AoE2 (SOLO CLIENTE).
# - Sin pending_action: enemigo cerca -> atacar; recurso cerca -> recolectar; si no -> mover.
# - Con pending_action del HUD (attack_move/patrol/build:X): click derecho fija el objetivo.
# Las órdenes salen por SimAPI.queue_command (lockstep). Nunca toca la sim directamente.

var combat: Node = null
var selection: Control = null
var hud: Control = null
var terrain: Node3D = null
var construction: Node = null
var garrison: Node = null
var resources: Array = []
var local_pid := 0

const ENEMY_PICK_R := 1.5 # tiles para enganchar enemigo con click derecho
const RES_PICK_R := 3.0 # tiles para ordenar recolectar (generoso al clickar)
const GROUND_Y := 2.0 # altura aprox para el primer rayo (se refina con el terreno)


func setup(p_combat: Node, p_selection: Control, p_hud: Control, p_terrain: Node3D, p_pid: int, p_resources: Array, p_construction: Node = null, p_garrison: Node = null) -> void:
	combat = p_combat
	selection = p_selection
	hud = p_hud
	terrain = p_terrain
	local_pid = p_pid
	resources = p_resources
	construction = p_construction
	garrison = p_garrison


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("smart_action"): # click derecho (project.godot)
		_smart_order(get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()


func _selected_ids() -> Array:
	if selection == null or not selection.has_method("get_selected"):
		return []
	return selection.get_selected()


## Pantalla -> tile de mapa (coords de sim). Vector2(-1,-1) si no hay cámara.
func _ground_tile(screen_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(-1, -1)
	var origin := cam.project_ray_origin(screen_pos)
	var normal := cam.project_ray_normal(screen_pos)
	if absf(normal.y) < 0.0001:
		return Vector2(-1, -1)
	var t := (GROUND_Y - origin.y) / normal.y
	if t < 0.0:
		return Vector2(-1, -1)
	var p: Vector3 = origin + normal * t
	if terrain != null and terrain.has_method("ground_height"):
		var h: float = terrain.ground_height(p.x / 2.0, p.z / 2.0)
		t = (h - origin.y) / normal.y
		if t < 0.0:
			return Vector2(-1, -1)
		p = origin + normal * t
	return Vector2(p.x / 2.0, p.z / 2.0)


func _smart_order(screen_pos: Vector2) -> void:
	if combat == null or selection == null:
		return
	var ids: Array = _selected_ids()
	if ids.is_empty():
		return
	var tile := _ground_tile(screen_pos)
	if tile.x < 0.0:
		return
	tile.x = clampf(tile.x, 0.0, 143.0)
	tile.y = clampf(tile.y, 0.0, 143.0)
	var pending := ""
	if hud != null:
		pending = str(hud.get("pending_action"))
	if pending == "attack_move":
		_send("attack_move", {"unit_ids": ids, "pos": [tile.x, tile.y]})
		_clear_pending("¡Ataque en marcha!")
		return
	if pending == "patrol":
		_send("patrol", {"unit_ids": ids, "pos": [tile.x, tile.y]})
		_clear_pending("Patrulla asignada.")
		return
	if pending.begins_with("build:"):
		var bid := pending.get_slice(":", 1)
		_send("build", {"unit_ids": ids, "building": bid, "pos": [tile.x, tile.y]})
		_send("move", {"unit_ids": ids, "pos": [tile.x, tile.y]})
		_clear_pending("Construyendo " + bid + "... (aldeanos en camino)")
		return
	if pending == "garrison":
		var b := _nearest_garrison(tile)
		if b >= 0:
			_send("garrison", {"unit_ids": ids, "building": b})
			_clear_pending("Guarecidos.")
		else:
			_send("move", {"unit_ids": ids, "pos": [tile.x, tile.y]})
			_clear_pending("Sin refugio cercano: moviendo.")
		return
	if pending == "repair":
		var site := _nearest_damaged_site(tile)
		if site >= 0:
			_send("repair", {"unit_ids": ids, "site_id": site})
			_send("move", {"unit_ids": ids, "pos": [tile.x, tile.y]})
			_clear_pending("A reparar.")
		else:
			_clear_pending("Sin edificios dañados cerca.")
		return
	# Sin pending: orden inteligente (igual que AoE2).
	var enemy := -1
	if combat.has_method("nearest_enemy"):
		enemy = int(combat.nearest_enemy(tile, ENEMY_PICK_R, local_pid))
	if enemy >= 0:
		_send("attack", {"unit_ids": ids, "target_id": enemy})
		_hint("¡Atacad!")
		return
	var node := _nearest_resource(tile)
	if node >= 0:
		_send("gather", {"unit_ids": ids, "node_id": node})
		_hint("A recolectar.")
		return
	_send("move", {"unit_ids": ids, "pos": [tile.x, tile.y]})


func _nearest_resource(tile: Vector2) -> int:
	var best := -1
	var best_d := RES_PICK_R + 0.001
	for r in resources:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var t: Vector2i = r.get("tile", Vector2i(-999, -999))
		var d := tile.distance_to(Vector2(t))
		if d < best_d:
			best_d = d
			best = int(r.get("id", -1))
	return best


## Obra aliada dañada más cercana (Construction): {sites: id -> {pos, player_id, hp, hp_max}}.
func _nearest_damaged_site(tile: Vector2) -> int:
	if construction == null:
		return -1
	var sites: Dictionary = construction.get("sites")
	if typeof(sites) != TYPE_DICTIONARY:
		return -1
	var best := -1
	var best_d := 5.0
	for sid in sites.keys():
		var s = sites[sid]
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if int(s.get("player_id", -1)) != local_pid:
			continue
		if float(s.get("hp", 0.0)) >= float(s.get("hp_max", 0.0)) - 1.0:
			continue
		var d := tile.distance_to(s.get("pos", Vector2(-999, -999)))
		if d < best_d:
			best_d = d
			best = int(sid)
	return best


## Edificio propio con hueco cercano (Garrison): usa can_garrison si existe.
func _nearest_garrison(tile: Vector2) -> int:
	if garrison == null:
		return -1
	var all: Dictionary = garrison.get("buildings")
	if typeof(all) != TYPE_DICTIONARY:
		return -1
	var ids: Array = _selected_ids()
	if ids.is_empty():
		return -1
	var best := -1
	var best_d := 6.0
	var bids: Array = all.keys()
	bids.sort()
	for bid in bids:
		var b = all[bid]
		if typeof(b) != TYPE_DICTIONARY:
			continue
		if int(b.get("owner", -1)) != local_pid or not bool(b.get("alive", false)):
			continue
		var d := tile.distance_to(b.get("pos", Vector2(-999, -999)))
		if d > best_d:
			continue
		if garrison.has_method("can_garrison"):
			var chk: Dictionary = garrison.can_garrison(int(ids[0]), int(bid))
			if not bool(chk.get("ok", false)):
				continue
		best_d = d
		best = int(bid)
	return best


func _send(cmd_type: String, payload: Dictionary) -> void:
	SimAPI.queue_command(local_pid, cmd_type, payload)


func _hint(text: String) -> void:
	if hud != null:
		var lbl = hud.get("lbl_hint")
		if lbl is Label:
			(lbl as Label).text = text


func _clear_pending(text: String) -> void:
	if hud != null:
		hud.set("pending_action", "")
		hud.set("in_build_submenu", false)
		if hud.has_method("_refresh_commands"):
			hud.call("_refresh_commands")
	_hint(text)

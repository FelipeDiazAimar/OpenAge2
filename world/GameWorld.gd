extends Node3D
## world/GameWorld.gd — Bootstrap de partida OpenAge-LAN.
##
## Escena: res://ui/hud/Game.tscn (root Node3D "Game" con este script).
## El Lobby la abre al pulsar Iniciar: Lobby._launch_game() hace
## GameManager.setup_lobby(cfgs) + change_scene_to_file("res://ui/hud/Game.tscn").
##
## Hace en _ready (orden):
##   1. Sistemas sim (logica lockstep 10 Hz): Production, Combat, Economy.
##   2. Niebla: FogOfWar (grupo "fog_of_war" para autodeteccion del Minimap).
##   3. Mapa visual: Terrain.build(map_seed) — 144x144, SOLO CLIENTE, no sim.
##   4. Luz: DirectionalLight3D calida con sombras + WorldEnvironment (cielo dia).
##   5. Camara: AoeCamera (orto fija AoE2) centrada en el TC del jugador local.
##   6. Spawn: 1 TC + 3 aldeanos por jugador via ModelFactory, layout determinista
##      en circulo (misma seed = mismo layout en todos los peers).
##      Registro sim: Production (TC), Economy (aldeanos + TC como dropoff),
##      Combat (aldeanos + TC), Selection (todo).
##   7. UI: CanvasLayer "UILayer" con SelectionSystem + HUD; Minimap incrustado
##      en el slot del HUD (SubViewport 200x200 dentro de MinimapSlot).
##   8. Cableado: tick_finished (niebla + censo + minimap + spawns de Production),
##      unit_died (ocultar visual + ping), command_issued (fallbacks go_tc/idle),
##      focus_camera (si EventBus expone la señal).
##
## Ticks: en red los genera NetManager (lockstep 10 Hz). Sin peer multijugador
## (prueba local / menu) GameWorld avanza GameManager._on_tick a 10 Hz.
## Determinismo: ninguna logica sim usa randf/randi/Time aqui; el layout usa
## solo seed + trigonometria. _process solo mueve visuales (cliente).

const AoeCameraScript := preload("res://core/AoeCamera.gd")
const HUDScript := preload("res://ui/hud/HUD.gd")
const ProductionScript := preload("res://systems/production/Production.gd")
const CombatScript := preload("res://systems/combat/Combat.gd")
const EconomyScript := preload("res://systems/economy/Economy.gd")
const ConstructionScript := preload("res://systems/construction/Construction.gd")
const GarrisonScript := preload("res://systems/combat/Garrison.gd")
const SmartControllerScript := preload("res://systems/selection/SmartController.gd")
const EnemyAIScript := preload("res://systems/ai/EnemyAI.gd")
const SelectionMarkersScript := preload("res://systems/selection/SelectionMarkers.gd")

const WORLD_SIZE := 288.0 # 144 tiles x 2.0 (Terrain.MAP_W x Terrain.TILE)
const CENTER_TILE := Vector2(72.0, 72.0)
const SPAWN_RADIUS_TILES := 46.0
const SPAWN_MARGIN := 6 # tiles de margen al borde
const VILLAGER_OFFSETS: Array[Vector2i] = [Vector2i(2, 1), Vector2i(-2, 1), Vector2i(0, -2)]
const VILLAGER_SIGHT := 4 # celdas (doc FogOfWar: aldeano 4)
const TC_SIGHT := 8 # celdas (doc FogOfWar: edificio 6-8)
const TC_HP := 1500.0
const TC_SIZE := Vector2i(4, 4)
const UNIT_BASE := 500000 # uids visuales iniciales (Production usa 1,2,3...; sin colision real)
const BUILDING_BASE := 800000 # uids edificios (Combat pide espacio unico; >= 100000)
const SOLO_TICK_DT := 0.1 # 10 Hz, igual que SimAPI.TICK_RATE

var local_pid := 0
var map_seed := 1234

var terrain: Terrain
var cam: Camera3D
var fog: FogOfWar
var minimap: Minimap
var selection: SelectionSystem
var hud # HUD.gd sin class_name: sin tipar para acceso dinamico
var production # idem (Production.gd sin class_name)
var combat # idem
var economy # idem
var construction # Construction.gd: obra, HP, reparación (comandos build/cancel/repair)
var garrison # Garrison.gd: guarecer/desguarecer (comandos garrison/ungarrison/bell)
var smart # SmartController.gd: click derecho inteligente (solo cliente)
var enemy_ai # EnemyAI.gd: bot enemigo (solo anfitrión)
var markers # SelectionMarkers.gd: anillos verdes (solo cliente)
var units_root: Node3D

# uid -> {node: Node3D, pid: int, kind: String, dead: bool}
var units := {}
# uid -> {node: Node3D, pid: int, type: String, tile: Vector2i, dead: bool}
var buildings := {}
# Nodos de recurso del mapa: [{id, kind, tile: Vector2i, node: Node3D}]
var resources: Array = []
# Tiles de TC por jugador (calculados antes de construir el terreno).
var _spawn_tiles: Array = []
var _bld_counter := 0

var _solo_accum := 0.0
var _solo_tick := 0
var _over_shown := false
var _dump_frames := 0


func _ready() -> void:
	_resolve_local_player()
	SimAPI.reset()
	_ensure_players()
	map_seed = int(GameManager.map_seed)
	_build_systems()
	_build_map()
	_build_light_env()
	_build_camera()
	_spawn_all()
	_build_ui()
	_connect_bus()
	_fog_initial()
	_center_on_local_tc()
	print("GameWorld: %d jugadores, seed %d, local pid %d." % [GameManager.players.size(), map_seed, local_pid])


## Punto de entrada alternativo para el Lobby/tests:
## configura GameManager y recarga la escena ya con los slots listos.
func start_match(slots: Array, seed: int = -1) -> void:
	if seed >= 0:
		GameManager.map_seed = seed
	GameManager.setup_lobby(slots)
	SimAPI.reset()
	get_tree().reload_current_scene()


# ------------------------------------------------------------- setup ---

func _resolve_local_player() -> void:
	# NetManager.my_id es 1-based (host = 1 -> pid 0). Sin red: pid 0.
	if NetManager.my_id > 0:
		local_pid = clampi(NetManager.my_id - 1, 0, 7)
	else:
		local_pid = 0


func _ensure_players() -> void:
	if GameManager.players.is_empty():
		GameManager.setup_lobby([
			{"civ": "britones", "team": 0},
			{"civ": "francos", "team": 1},
		])
	local_pid = clampi(local_pid, 0, maxi(0, GameManager.players.size() - 1))


func _build_systems() -> void:
	production = ProductionScript.new()
	production.name = "Production"
	add_child(production)
	combat = CombatScript.new()
	combat.name = "Combat"
	add_child(combat)
	economy = EconomyScript.new()
	economy.name = "Economy"
	add_child(economy)
	construction = ConstructionScript.new()
	construction.name = "Construction"
	add_child(construction)
	garrison = GarrisonScript.new()
	garrison.name = "Garrison"
	add_child(garrison)
	enemy_ai = EnemyAIScript.new()
	enemy_ai.name = "EnemyAI"
	add_child(enemy_ai)
	fog = FogOfWar.new()
	fog.name = "FogOfWar"
	fog.add_to_group("fog_of_war")
	add_child(fog)
	fog.reset_all()
	units_root = Node3D.new()
	units_root.name = "Units"
	add_child(units_root)


func _build_map() -> void:
	# Spawns primero: el terreno aplana una meseta en cada uno (nada en agua).
	var n: int = GameManager.players.size()
	_spawn_tiles.clear()
	for pid in n:
		_spawn_tiles.append(_tc_tile_for(pid, n))
	terrain = Terrain.new()
	terrain.auto_build = false # construimos a mano con la seed de la partida
	var spots: Array[Vector2] = []
	for t in _spawn_tiles:
		spots.append(Vector2(t))
	terrain.flatten_spots = spots
	add_child(terrain)
	terrain.build(map_seed, _load_map_dict("res://data/maps/arabia.json"))


func _build_light_env() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.93, 0.80) # calida mediodia AoE2
	sun.light_energy = 1.0
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.90)
	sky_mat.ground_bottom_color = Color(0.25, 0.22, 0.18)
	sky_mat.ground_horizon_color = Color(0.95, 0.85, 0.70) # horizonte calido
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.ssao_enabled = false
	e.glow_enabled = false
	env.environment = e
	add_child(env)


func _build_camera() -> void:
	cam = AoeCameraScript.new()
	cam.name = "AoeCamera"
	add_child(cam) # su _ready fija orto/size/rotacion/current


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UILayer"
	ui.layer = 10
	add_child(ui)
	selection = SelectionSystem.new()
	selection.name = "Selection"
	selection.local_player_id = local_pid
	ui.add_child(selection)
	hud = HUDScript.new()
	hud.name = "HUD"
	hud.local_player_id = local_pid
	hud.selection_ref = selection
	ui.add_child(hud)
	# Click derecho inteligente (mover/atacar/recolectar/construir).
	smart = SmartControllerScript.new()
	smart.name = "SmartController"
	ui.add_child(smart)
	smart.setup(combat, selection, hud, terrain, local_pid, resources, construction, garrison)
	# Anillos verdes bajo lo seleccionado.
	markers = SelectionMarkersScript.new()
	markers.name = "SelectionMarkers"
	add_child(markers)
	markers.setup(selection, units, buildings)
	# Registro de seleccion (todo el mundo; Selection filtra por local_pid).
	for uid in units.keys():
		selection.register_unit(int(uid), units[uid]["node"], int(units[uid]["pid"]), "aldeano",
			{"military": false, "idle": true})
	for uid in buildings.keys():
		selection.register_unit(int(uid), buildings[uid]["node"], int(buildings[uid]["pid"]),
			"centro_urbano", {"military": false, "idle": false})
	# Minimap dentro del slot del HUD (SubViewportContainer "MinimapSlot").
	minimap = Minimap.new()
	minimap.name = "Minimap"
	minimap.local_player_id = local_pid
	minimap.world_size = WORLD_SIZE
	minimap.fog_node = fog
	minimap.camera_node = cam
	var slot: Node = hud.find_child("MinimapSlot", true, false)
	if slot is SubViewportContainer:
		var sv := SubViewport.new()
		sv.name = "MinimapView"
		sv.size = Vector2i(200, 200)
		sv.transparent_bg = true
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		slot.add_child(sv)
		sv.add_child(minimap)
	else:
		push_warning("GameWorld: MinimapSlot no encontrado, Minimap como hijo del HUD.")
		hud.add_child(minimap)
	_feed_minimap()


func _connect_bus() -> void:
	EventBus.tick_finished.connect(_on_tick)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.command_issued.connect(_on_command)
	EventBus.building_placed.connect(_on_building_placed)
	garrison.unit_garrisoned.connect(_on_garrisoned)
	garrison.unit_ungarrisoned.connect(_on_ungarrisoned)
	garrison.building_evacuated.connect(_on_evacuated)
	if EventBus.has_signal("focus_camera"):
		# Conexion por nombre: la señal no existe en EventBus.gd base
		# (Selection la emite con guardia); el acceso por punto no compilaria.
		EventBus.connect("focus_camera", _on_focus_camera)


# ---------------------------------------------------------------- spawn ---

## Posicion de TC determinista: circulo alrededor del centro, radio fijo.
func _tc_tile_for(pid: int, n: int) -> Vector2i:
	var ang := TAU * float(pid) / float(maxi(n, 1)) - PI * 0.5
	var p := CENTER_TILE + Vector2(cos(ang), sin(ang)) * SPAWN_RADIUS_TILES
	var lo := SPAWN_MARGIN
	var hi := 143 - SPAWN_MARGIN
	return Vector2i(clampi(floori(p.x), lo, hi), clampi(floori(p.y), lo, hi))


func _spawn_all() -> void:
	var n: int = GameManager.players.size()
	for pid in n:
		_spawn_player(pid, _spawn_tiles[pid] if pid < _spawn_tiles.size() else _tc_tile_for(pid, n))
	_setup_ai(n)


## IA enemiga: todos los pids menos el local juegan solos (en LAN nadie:
## todos son humanos y el bot se queda quieto salvo que sea host... en LAN
## el host también la ejecuta solo si hay pids sin humano: aquí todos los
## slots son humanos, así que en red ai_pids queda vacío y no hace nada).
func _setup_ai(n: int) -> void:
	var ai_pids: Array = []
	var tiles := {}
	var uids := {}
	for pid in n:
		if pid < _spawn_tiles.size():
			tiles[pid] = _spawn_tiles[pid]
		uids[pid] = BUILDING_BASE + pid * 100
	if not multiplayer.has_multiplayer_peer():
		for pid in n:
			if pid != local_pid:
				ai_pids.append(pid)
	enemy_ai.setup(economy, production, combat, ai_pids, tiles, uids)


## Recurso del mapa: nodo sim (Economy) + visual 3D. Click derecho lo recolecta.
func _add_resource_node(node_id: int, kind: String, amount: float, tile: Vector2i, model: String) -> void:
	var t := Vector2i(clampi(tile.x, SPAWN_MARGIN, 143 - SPAWN_MARGIN), clampi(tile.y, SPAWN_MARGIN, 143 - SPAWN_MARGIN))
	economy.register_node(node_id, kind, amount, Vector2(t))
	var visual: Node3D = ModelFactory.spawn_building(model, 0, Color.WHITE)
	visual.position = terrain.tile_to_world(Vector2(t))
	units_root.add_child(visual)
	resources.append({"id": node_id, "kind": kind, "tile": t, "node": visual})


func _spawn_player(pid: int, tc_tile: Vector2i) -> void:
	var color: Color = SimAPI.get_player_color(pid)
	# --- Centro Urbano ---
	var tc_uid := BUILDING_BASE + pid * 100
	var tc_node: Node3D = ModelFactory.spawn_building("centro_urbano", 0, color)
	tc_node.position = terrain.tile_to_world(Vector2(tc_tile))
	tc_node.set_meta("unit_id", tc_uid)
	tc_node.set_meta("player_id", pid)
	tc_node.set_meta("unit_type", "centro_urbano")
	units_root.add_child(tc_node)
	buildings[tc_uid] = {"node": tc_node, "pid": pid, "type": "centro_urbano",
		"tile": tc_tile, "dead": false}
	production.register_building(tc_uid, pid, "centro_urbano", tc_tile, TC_SIZE)
	economy.register_dropoff(tc_uid, pid, Vector2(tc_tile), "centro_urbano", [])
	combat.register_building(tc_uid, pid, Vector2(tc_tile), TC_HP, 0.0, 0.0, "centro_urbano")
	garrison.register_building(tc_uid, "centro_urbano", Vector2(tc_tile), pid)
	# --- Recursos iniciales alrededor del TC (madera/oro/piedra) ---
	var nid := 10000 + pid * 100
	_add_resource_node(nid + 0, "wood", 100.0, tc_tile + Vector2i(4, 1), "arbol")
	_add_resource_node(nid + 1, "wood", 100.0, tc_tile + Vector2i(-4, 2), "arbol")
	_add_resource_node(nid + 2, "wood", 100.0, tc_tile + Vector2i(1, -5), "arbol")
	_add_resource_node(nid + 3, "gold", 800.0, tc_tile + Vector2i(6, -2), "mina_oro")
	_add_resource_node(nid + 4, "stone", 800.0, tc_tile + Vector2i(-5, -4), "mina_piedra")
	# --- 3 aldeanos alrededor del TC ---
	for i in VILLAGER_OFFSETS.size():
		var vtile := Vector2i(
			clampi(tc_tile.x + VILLAGER_OFFSETS[i].x, SPAWN_MARGIN, 143 - SPAWN_MARGIN),
			clampi(tc_tile.y + VILLAGER_OFFSETS[i].y, SPAWN_MARGIN, 143 - SPAWN_MARGIN))
		_spawn_villager(UNIT_BASE + pid * 100 + i, pid, "aldeano", vtile, color)


## Spawnea el visual + registra en Combat/Economy/Selection. Reusado por
## el tick para las unidades que produce Production (uid de Production).
func _spawn_villager(uid: int, pid: int, kind: String, vtile: Vector2i, color: Color) -> void:
	# Sprites 2D del AoE2 si están extraídos (assets/sprites/), si no 3D propio.
	var node: Node3D = SpriteFactory.spawn(kind, color)
	node.position = terrain.tile_to_world(Vector2(vtile))
	node.set_meta("unit_id", uid)
	node.set_meta("player_id", pid)
	node.set_meta("unit_type", kind)
	units_root.add_child(node)
	units[uid] = {"node": node, "pid": pid, "kind": kind, "dead": false}
	combat.register_unit(uid, pid, kind, Vector2(vtile), {})
	economy.register_villager(uid, pid, Vector2(vtile))
	construction.register_villager(uid, pid, Vector2(vtile))
	garrison.register_unit(uid, kind, Vector2(vtile), pid)
	if is_instance_valid(selection):
		selection.register_unit(uid, node, pid, kind, {"military": kind != "aldeano", "idle": kind == "aldeano"})


# ----------------------------------------------------------------- tick ---

func _process(delta: float) -> void:
	_sync_visuals()
	_drive_solo_tick(delta)
	# Diagnóstico: -- --dump-ui vuelca rects del HUD a user://hud_debug.txt.
	if "--dump-ui" in OS.get_cmdline_user_args():
		_dump_frames += 1
		if _dump_frames == 90 and is_instance_valid(hud) and hud.has_method("_dump_debug"):
			hud.call("_dump_debug")


## Cliente: copia posiciones sim (tiles) -> visuales 3D. Sin peer no hay sim.
func _sync_visuals() -> void:
	if terrain == null or combat == null:
		return
	for uid in units.keys():
		var u: Dictionary = units[uid]
		if bool(u.get("dead", false)):
			continue
		if combat.has_unit(int(uid)):
			var p2: Vector2 = combat.get_pos(int(uid))
			(u["node"] as Node3D).global_position = terrain.tile_to_world(p2)


## Sin peer multijugador NetManager no tickea: avanzamos el lockstep en local.
func _drive_solo_tick(delta: float) -> void:
	if multiplayer.has_multiplayer_peer():
		return # en red manda NetManager
	_solo_accum += delta
	while _solo_accum >= SOLO_TICK_DT:
		_solo_accum -= SOLO_TICK_DT
		_solo_tick += 1
		GameManager._on_tick(_solo_tick)


func _on_tick(t: int) -> void:
	_sync_production_spawns()
	_sync_construction_workers()
	_fog_rebuild(t)
	_feed_minimap()
	_report_census()
	SimAPI.discard_ticks_older_than(t)
	_check_game_over_banner()


## Construction comprueba distancia aldeano-obra con su propio registro
## y Economy mueve a los recolectores con el suyo: sincronizamos posiciones
## cada tick desde/hacia Combat (que mueve las órdenes de movimiento/ataque).
## - Aldeano recolectando (goto/gather/return/dropoff): Economy manda -> Combat.
## - Aldeano en otras tareas: Combat manda -> Economy y Construction.
func _sync_construction_workers() -> void:
	if combat == null or economy == null:
		return
	var cunits: Dictionary = combat.get("_units")
	var evills: Dictionary = economy.get("_villagers")
	if typeof(cunits) != TYPE_DICTIONARY or typeof(evills) != TYPE_DICTIONARY:
		return
	for uid in units.keys():
		var u: Dictionary = units[uid]
		if bool(u.get("dead", false)) or str(u.get("kind", "")) != "aldeano":
			continue
		var id := int(uid)
		if evills.has(id):
			var ev: Dictionary = evills[id]
			if str(ev.get("state", "idle")) in ["goto", "gather", "return", "dropoff"]:
				if cunits.has(id):
					(cunits[id] as Dictionary)["pos"] = (ev.get("pos", Vector2.ZERO) as Vector2)
				continue
		if combat.has_unit(id):
			var cp: Vector2 = combat.get_pos(id)
			if evills.has(id):
				(evills[id] as Dictionary)["pos"] = cp
			if construction != null:
				construction.update_villager_pos(id, cp)


## Unidades terminadas por Production -> visual + registro sim.
func _sync_production_spawns() -> void:
	if production == null:
		return
	for rec in production.get_spawned():
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var uid := int(rec.get("uid", -1))
		if uid < 0 or units.has(uid):
			continue
		var pid := int(rec.get("player_id", 0))
		var cell: Vector2i = rec.get("cell", Vector2i(72, 72))
		var kind := str(rec.get("unit_id", "aldeano"))
		_spawn_villager(uid, pid, kind, cell, SimAPI.get_player_color(pid))
		var rally: Vector2i = rec.get("rally", cell)
		if rally != cell and combat.has_unit(uid):
			combat.order_move(uid, Vector2(rally))


func _fog_rebuild(t: int) -> void:
	if fog == null or combat == null:
		return
	fog.clear_all_viewers()
	for uid in units.keys():
		var u: Dictionary = units[uid]
		if bool(u.get("dead", false)) or not combat.is_alive(int(uid)):
			continue
		fog.add_viewer(int(u["pid"]), _cell_of(combat.get_pos(int(uid))), VILLAGER_SIGHT)
	for uid in buildings.keys():
		var b: Dictionary = buildings[uid]
		if bool(b.get("dead", false)) or not combat.is_alive(int(uid)):
			continue
		fog.add_viewer(int(b["pid"]), _cell_of(Vector2(b["tile"])), TC_SIGHT)
	fog.rebuild_tick(t)


func _fog_initial() -> void:
	if fog == null or combat == null:
		return
	fog.clear_all_viewers()
	for uid in units.keys():
		var u: Dictionary = units[uid]
		var tile_pos := _world_xz_of(u["node"])
		if combat != null and combat.has_unit(int(uid)):
			tile_pos = combat.get_pos(int(uid))
		fog.add_viewer(int(u["pid"]), _cell_of(tile_pos), VILLAGER_SIGHT)
	for uid in buildings.keys():
		var b: Dictionary = buildings[uid]
		fog.add_viewer(int(b["pid"]), _cell_of(Vector2(b["tile"])), TC_SIGHT)
	fog.force_rebuild()


static func _cell_of(tile_pos: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(tile_pos.x), 0, 143), clampi(floori(tile_pos.y), 0, 143))


## Nodo 3D -> coords de tile (mundo 288 / celda 2.0). Solo visual/fog/minimap.
func _world_xz_of(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x / 2.0, node.global_position.z / 2.0)


func _report_census() -> void:
	var n: int = GameManager.players.size()
	for pid in n:
		var tc := 0
		var vill := 0
		var mil := 0
		for uid in buildings.keys():
			var b: Dictionary = buildings[uid]
			if int(b["pid"]) != pid or bool(b.get("dead", false)):
				continue
			if not combat.is_alive(int(uid)):
				continue
			if str(b.get("type", "")) == "centro_urbano":
				tc += 1
		for uid in units.keys():
			var u: Dictionary = units[uid]
			if int(u["pid"]) != pid or bool(u.get("dead", false)):
				continue
			if not combat.is_alive(int(uid)):
				continue
			if str(u.get("kind", "aldeano")) == "aldeano":
				vill += 1
			else:
				mil += 1
		GameManager.report_census(pid, tc, vill, mil)


func _check_game_over_banner() -> void:
	if _over_shown or not GameManager.is_game_over():
		return
	_over_shown = true
	var w := GameManager.get_winner_team()
	var msg := "¡Victoria del equipo %d!" % (w + 1) if w >= 0 else "Empate: todos eliminados."
	print("GameWorld: %s" % msg)
	if is_instance_valid(hud):
		hud.lbl_hint.text = msg


func _feed_minimap() -> void:
	if minimap == null:
		return
	var um: Array = []
	var bm: Array = []
	for uid in units.keys():
		var u: Dictionary = units[uid]
		if bool(u.get("dead", false)):
			continue
		um.append({"pos": _minimap_pos(int(uid), u), "player_id": int(u["pid"])})
	for uid in buildings.keys():
		var b: Dictionary = buildings[uid]
		if bool(b.get("dead", false)):
			continue
		var n3d: Node3D = b["node"]
		bm.append({"pos": Vector2(n3d.global_position.x, n3d.global_position.z),
			"player_id": int(b["pid"])})
	minimap.set_units(um)
	minimap.set_buildings(bm)


func _minimap_pos(uid: int, u: Dictionary) -> Vector2:
	if combat != null and combat.has_unit(uid):
		var p2: Vector2 = combat.get_pos(uid)
		return p2 * 2.0 # tiles -> mundo XZ
	var n3d: Node3D = u["node"]
	return Vector2(n3d.global_position.x, n3d.global_position.z)


# ---------------------------------------------------------------- eventos ---

func _on_unit_died(uid: int, _killer_id: int) -> void:
	var pid := -1
	var wpos := Vector2.ZERO
	if units.has(int(uid)):
		var u: Dictionary = units[int(uid)]
		u["dead"] = true
		pid = int(u["pid"])
		var n3d: Node3D = u["node"]
		wpos = Vector2(n3d.global_position.x, n3d.global_position.z)
		n3d.visible = false
	elif buildings.has(int(uid)):
		var b: Dictionary = buildings[int(uid)]
		b["dead"] = true
		pid = int(b["pid"])
		var bn: Node3D = b["node"]
		wpos = Vector2(bn.global_position.x, bn.global_position.z)
		bn.visible = false
	else:
		return
	if is_instance_valid(selection):
		selection.unregister_unit(int(uid))
	if minimap != null and pid == local_pid:
		minimap.notify_attack(wpos)


func _on_command(cmd: Dictionary) -> void:
	if typeof(cmd) != TYPE_DICTIONARY:
		return
	match str(cmd.get("type", "")):
		"go_tc":
			_center_on_local_tc()
		"idle_villager":
			# Fallback por si VillagerAI no esta en escena: selecciona + centra.
			if is_instance_valid(selection):
				selection.select_next_idle_villager(local_pid)


func _on_focus_camera(world_pos: Vector3) -> void:
	if cam == null:
		return
	cam.global_position = Vector3(
		clampf(world_pos.x, 0.0, WORLD_SIZE),
		cam.global_position.y,
		clampf(world_pos.z, 0.0, WORLD_SIZE))


## Obra terminada por Construction -> visual 3D + registro en los sistemas.
func _on_building_placed(pid: int, building: String, pos: Vector3) -> void:
	var tile := Vector2i(clampi(floori(pos.x / 2.0), 0, 143), clampi(floori(pos.z / 2.0), 0, 143))
	_bld_counter += 1
	var uid := 820000 + _bld_counter
	var color: Color = SimAPI.get_player_color(pid)
	var age_idx := 0
	if GameManager.has_method("get_age_index"):
		age_idx = maxi(0, GameManager.get_age_index(str(GameManager.get_player(pid).get("age", ""))))
	var node: Node3D = ModelFactory.spawn_building(building, age_idx, color)
	node.position = terrain.tile_to_world(Vector2(tile))
	node.set_meta("unit_id", uid)
	node.set_meta("player_id", pid)
	node.set_meta("unit_type", building)
	units_root.add_child(node)
	buildings[uid] = {"node": node, "pid": pid, "type": building, "tile": tile, "dead": false}
	var def := _building_json(building)
	var size := Vector2i(3, 3)
	if def.has("size_tiles") and (def["size_tiles"] as Array).size() >= 2:
		size = Vector2i(maxi(1, int(def["size_tiles"][0])), maxi(1, int(def["size_tiles"][1])))
	production.register_building(uid, pid, building, tile, size)
	combat.register_building(uid, pid, Vector2(tile), float(def.get("hp", 500.0)), 0.0, 0.0, building)
	selection.register_unit(uid, node, pid, building, {"military": false, "idle": false})
	garrison.register_building(uid, building, Vector2(tile), pid)
	if building in ["centro_urbano", "campamento_maderero", "molino", "campamento_minero"]:
		economy.register_dropoff(uid, pid, Vector2(tile), building, [])


## Lee data/buildings/<id>.json (solo cliente, al completar cada edificio).
func _building_json(building_id: String) -> Dictionary:
	var f := FileAccess.open("res://data/buildings/%s.json" % building_id.to_lower(), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


## Guarnición: ocultar/mostrar visuales al entrar/salir de edificios.
func _on_garrisoned(uid: int, _bid: int) -> void:
	if units.has(int(uid)):
		(units[int(uid)]["node"] as Node3D).visible = false


func _on_ungarrisoned(uid: int, bid: int) -> void:
	if not units.has(int(uid)):
		return
	var n3d: Node3D = units[int(uid)]["node"]
	n3d.visible = true
	if buildings.has(int(bid)):
		n3d.global_position = terrain.tile_to_world(Vector2(buildings[int(bid)]["tile"]))


func _on_evacuated(bid: int, unit_ids: Array) -> void:
	for uid in unit_ids:
		_on_ungarrisoned(int(uid), int(bid))


func _center_on_local_tc() -> void:
	if cam == null:
		return
	for uid in buildings.keys():
		var b: Dictionary = buildings[uid]
		if int(b["pid"]) != local_pid or bool(b.get("dead", false)):
			continue
		if str(b.get("type", "")) != "centro_urbano":
			continue
		var tp: Vector3 = (b["node"] as Node3D).global_position
		cam.global_position = tp + Vector3(20.0, 20.0, 20.0) # offset vista AoeCamera
		return


# ----------------------------------------------------------------- ayuda ---

func _load_map_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}

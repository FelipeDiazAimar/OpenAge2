extends Node2D
## Partida local con el motor nuevo: terreno iso, centros urbanos, aldeanos
## y recursos generados; selección con clic/arrastre y clic derecho
## inteligente (recolectar o mover). Simulación a 10 Hz; el render interpola.

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const World := preload("res://engine/sim/World.gd")
const AssetLocator := preload("res://engine/assets/AssetLocator.gd")
const Iso := preload("res://engine/render2d/Iso.gd")
const TerrainLayer := preload("res://engine/render2d/TerrainLayer.gd")
const EntityLayer := preload("res://engine/render2d/EntityLayer.gd")
const IsoCamera := preload("res://engine/render2d/IsoCamera.gd")
const SelectionOverlay := preload("res://engine/render2d/SelectionOverlay.gd")
const MapGen := preload("res://engine/sim/MapGen.gd")
const ResourceBar := preload("res://engine/ui/ResourceBar.gd")

const MAP_SIZE := 144
const MAP_SEED := 1234
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
var bar
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
		elif s.begins_with("--zoom="):
			cam.set_zoom_now(float(s.get_slice("=", 1)))
	if _shot_path != "":
		cam.edge_scroll = false


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


## Clic derecho estilo AoE2: sobre un recurso, los aldeanos seleccionados lo
## recolectan; en otro caso, mover.
func smart_command(world_pos: Vector2) -> void:
	if selected.is_empty():
		return
	var id: int = layer.pick(world_pos)
	if id >= 0 and sim.world.has_ability(id, "ResourceSource"):
		var gatherers: Array = selected.filter(func(s): return sim.world.has_ability(s, "Gather"))
		if not gatherers.is_empty():
			sim.queue_command(local_pid, "gather", {"ids": gatherers, "target": id})
			return
	issue_move(Iso.to_tiles(world_pos))


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
	bar.refresh()
	_frames += 1
	if _shot_path != "" and _frames >= maxi(1, _shot_frames):
		_save_screenshot(_shot_path)
		_shot_path = ""


## Espera a que el frame termine de dibujarse: leer la textura antes
## devuelve la imagen del frame anterior (o vacía).
func _save_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[Match] captura guardada en ", ProjectSettings.globalize_path(path))
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
			smart_command(wp)
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
	var starts: Array[Vector2i] = []
	for i in sim.players.size():
		starts.append(_start_tile(i))
	MapGen.generate(sim, MAP_SEED, starts)


func _build_help() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	bar = ResourceBar.new()
	bar.setup(sim, local_pid)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ui.add_child(bar)
	var l := Label.new()
	l.text = "Motor nuevo — clic izq: seleccionar / arrastrar · clic der: recolectar / mover · flechas/borde/botón medio: cámara · rueda: zoom · Esc: menú"
	l.position = Vector2(12, 40)
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

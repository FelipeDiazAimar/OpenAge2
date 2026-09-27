extends Control
class_name MapEditor
## tools/MapEditor.gd — Editor de mapas .oamap.json (SOLO EDITOR, no afecta a la sim).
##
## - NO toca SimAPI / GameManager / EventBus / NetManager / SimRNG.
## - Sin randf/Time/OS en pintado: todo determinista y local.
## - Uso: crea una escena con un Control raíz, adjunta este script y ejecuta
##   la escena (o instánciala como herramienta). Toda la UI se construye en
##   _ready() por código, no necesita .tscn.
## - Formato .oamap.json (oamap-v1), compatible hacia atrás con
##   data/maps/arabia.json (si falta "terrain_rows", el generador usa el
##   procedural + "start_resources"):
##     {
##       "format": "oamap-v1", "name": "...", "size_tiles": [W, H],
##       "seed": 1234, "terrain": "custom", "water": bool,
##       "terrain_rows": ["GG...", ...],   # G=hierba F=bosque W=agua, H filas x W cols
##       "resources": [{"kind":"tree|gold|stone|berry","x":int,"y":int,"amount":int}],
##       "buildings": [{"id":"centro_urbano","x":int,"y":int,"player":int}],
##       "start_resources": {"wood_patches":n,"gold_piles":n,"stone_piles":n,"forage":n},
##       "relics": int
##     }

# ---------------------------------------------------------------- constantes --
const FORMAT_VERSION := "oamap-v1"
const DEFAULT_PATH := "res://data/maps/custom.oamap.json"
const MIN_SIZE := 16
const MAX_SIZE := 144
const DEFAULT_W := 64
const DEFAULT_H := 64

# Terreno (valores guardados en _terrain).
const T_GRASS := 0
const T_FOREST := 1
const T_WATER := 2

# Herramientas.
const TOOL_GRASS := 0
const TOOL_FOREST := 1
const TOOL_WATER := 2
const TOOL_TREE := 3
const TOOL_GOLD := 4
const TOOL_STONE := 5
const TOOL_BERRY := 6
const TOOL_BUILDING := 7
const TOOL_ERASE := 8

const TOOL_NAMES := {
	TOOL_GRASS: "Hierba",
	TOOL_FOREST: "Bosque",
	TOOL_WATER: "Agua",
	TOOL_TREE: "Recurso: árbol",
	TOOL_GOLD: "Recurso: oro",
	TOOL_STONE: "Recurso: piedra",
	TOOL_BERRY: "Recurso: bayas",
	TOOL_BUILDING: "Edificio",
	TOOL_ERASE: "Borrar",
}

# kind de recurso <-> fichas de resource_defs.json.
const RES_KINDS := ["tree", "gold", "stone", "berry"]
const RES_DEFAULT_AMOUNT := {"tree": 100, "gold": 800, "stone": 800, "berry": 125}

# Ids existentes en data/buildings/*.json (lista para el desplegable).
const BUILDING_IDS := [
	"centro_urbano", "casa", "molino", "granja", "campamento_maderero",
	"campamento_minero", "cuartel", "arqueria", "establo", "herreria",
	"torre_vigia", "muro", "puerta", "castillo", "monasterio",
	"universidad", "mercado", "muelle", "taller_asedio",
]

const COL_GRASS := Color("6da34f")
const COL_FOREST := Color("2f6b2a")
const COL_WATER := Color("3a7bd5")
const COL_GRID := Color(0, 0, 0, 0.18)
const COL_TREE := Color("2e7d32")
const COL_GOLD := Color("e8c33a")
const COL_STONE := Color("9a9a9a")
const COL_BERRY := Color("c0392b")
const COL_BLDG := Color("f5f5f5")
# Copia local de los colores de jugador solo para el preview (no usa SimAPI).
const PLAYER_COLORS := [
	Color("#2a4bff"), Color("#ff0000"), Color("#00ff00"), Color("#ffff00"),
	Color("#00c8ff"), Color("#c800ff"), Color("#969696"), Color("#ff8c00"),
]

# ------------------------------------------------------------------- estado --
var map_name := "Personalizado"
var map_w := DEFAULT_W
var map_h := DEFAULT_H
var map_seed := 1234
var relics := 0
var brush_size := 2          # radio en tiles (1 = 1 tile)
var current_tool := TOOL_GRASS
var current_building := "centro_urbano"
var current_player := 0

var _terrain := PackedByteArray()  # W*H, valores T_*
var _resources: Array = []         # Array[Dictionary] {kind,x,y,amount}
var _buildings: Array = []         # Array[Dictionary] {id,x,y,player}
var _dirty_preview := true

# UI (construidas en _ready).
var _canvas: Canvas
var _preview_rect: TextureRect
var _status: Label
var _counts: Label
var _path_edit: LineEdit
var _tool_selector: OptionButton
var _building_selector: OptionButton
var _player_spin: SpinBox
var _brush_spin: SpinBox
var _name_edit: LineEdit
var _seed_spin: SpinBox
var _relics_spin: SpinBox
var _size_w_spin: SpinBox
var _size_h_spin: SpinBox


# ============================================================ lienzo (hijo) ==
class Canvas extends Control:
	# Control de pintado. Toda la lógica vive en el MapEditor (editor.*);
	# aquí solo dibujo + reenvío de ratón. No toca la sim.
	var editor: MapEditor

	func _init(p_editor: MapEditor) -> void:
		editor = p_editor
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		clip_contents = true

	func _gui_input(event: InputEvent) -> void:
		if editor == null:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				editor.paint_at(get_local_mouse_position())
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				editor.erase_at(get_local_mouse_position())
				accept_event()
		elif event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				editor.paint_at(get_local_mouse_position())
				accept_event()
			elif (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
				editor.erase_at(get_local_mouse_position())
				accept_event()

	func _draw() -> void:
		if editor == null or not editor.has_terrain():
			draw_rect(Rect2(Vector2.ZERO, size), Color("1a1a1a"))
			return
		var cell := editor.canvas_cell()
		if cell.x <= 0.0 or cell.y <= 0.0:
			return
		# Tiles.
		for y in editor.map_h:
			for x in editor.map_w:
				var r := Rect2(Vector2(x * cell.x, y * cell.y), cell)
				draw_rect(r, editor.terrain_color(editor.get_tile(x, y)))
		# Rejilla tenue (solo si el tile es legible).
		if cell.x >= 6.0 and cell.y >= 6.0:
			for y in editor.map_h + 1:
				draw_line(Vector2(0, y * cell.y), Vector2(editor.map_w * cell.x, y * cell.y), MapEditor.COL_GRID, 1.0)
			for x in editor.map_w + 1:
				draw_line(Vector2(x * cell.x, 0), Vector2(x * cell.x, editor.map_h * cell.y), MapEditor.COL_GRID, 1.0)
		# Recursos (círculos).
		var rad: float = minf(cell.x, cell.y) * 0.32
		for r in editor._resources:
			var c := Vector2((float(r["x"]) + 0.5) * cell.x, (float(r["y"]) + 0.5) * cell.y)
			draw_circle(c, maxf(rad, 2.0), editor.resource_color(str(r["kind"])))
		# Edificios (cuadrado + borde de color de jugador).
		for b in editor._buildings:
			var rect := Rect2(Vector2(float(b["x"]) * cell.x, float(b["y"]) * cell.y), cell)
			draw_rect(rect, MapEditor.COL_BLDG)
			var pid: int = clampi(int(b["player"]), 0, 7)
			draw_rect(rect, MapEditor.PLAYER_COLORS[pid], false, 2.0)


# ==================================================================== _ready ==
func _ready() -> void:
	_new_map(map_w, map_h, false)
	_build_ui()
	refresh()


func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# ---- Panel izquierdo (herramientas). ----
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(290, 0)
	side.add_theme_constant_override("separation", 6)
	root.add_child(side)

	side.add_child(_section("Mapa"))
	side.add_child(_row("Nombre:", _mk_name_edit()))
	side.add_child(_row("Semilla:", _mk_seed_spin()))
	side.add_child(_row("Reliquias:", _mk_relics_spin()))
	side.add_child(_row("Ancho:", _mk_size_w_spin()))
	side.add_child(_row("Alto:", _mk_size_h_spin()))
	var resize_btn := Button.new()
	resize_btn.text = "Redimensionar / Nuevo"
	resize_btn.tooltip_text = "Redimensiona conservando lo que quepa."
	resize_btn.pressed.connect(_on_resize)
	side.add_child(resize_btn)
	var fill_btn := Button.new()
	fill_btn.text = "Rellenar de hierba"
	fill_btn.pressed.connect(_on_fill_grass)
	side.add_child(fill_btn)

	side.add_child(_section("Pincel"))
	side.add_child(_row("Herramienta:", _mk_tool_selector()))
	side.add_child(_row("Tamaño:", _mk_brush_spin()))
	var hint := Label.new()
	hint.text = "Click izq: pintar/colocar (arrastrar). Click der: borrar."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(hint)

	side.add_child(_section("Edificio inicial"))
	side.add_child(_row("Edificio:", _mk_building_selector()))
	side.add_child(_row("Jugador (0-7):", _mk_player_spin()))
	var del_bldg := Button.new()
	del_bldg.text = "Eliminar edificios (modo borrar)"
	del_bldg.pressed.connect(func() -> void: _tool_selector.select(_tool_selector.get_item_index(TOOL_ERASE)); _on_tool_selected(_tool_selector.get_item_index(TOOL_ERASE)))
	side.add_child(del_bldg)
	var clear_res := Button.new()
	clear_res.text = "Limpiar recursos"
	clear_res.pressed.connect(_on_clear_resources)
	side.add_child(clear_res)
	var clear_bldg := Button.new()
	clear_bldg.text = "Limpiar edificios"
	clear_bldg.pressed.connect(_on_clear_buildings)
	side.add_child(clear_bldg)

	side.add_child(_section("Archivo .oamap.json"))
	_path_edit = LineEdit.new()
	_path_edit.text = DEFAULT_PATH
	_path_edit.tooltip_text = "Ruta de guardado/carga. res:// funciona en editor; en juego usa user://."
	side.add_child(_path_edit)
	var save_btn := Button.new()
	save_btn.text = "Guardar mapa"
	save_btn.pressed.connect(_on_save)
	side.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "Cargar mapa"
	load_btn.pressed.connect(_on_load)
	side.add_child(load_btn)

	_counts = Label.new()
	_counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_counts)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_status)

	# ---- Derecha: lienzo + preview. ----
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	root.add_child(right)

	_canvas = Canvas.new(self)
	right.add_child(_canvas)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	right.add_child(bottom)

	_preview_rect = TextureRect.new()
	_preview_rect.custom_minimum_size = Vector2(192, 144)
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_rect.tooltip_text = "Mini-preview (no es la sim, solo editor)."
	bottom.add_child(_preview_rect)

	var pv_label := Label.new()
	pv_label.text = "Mini-preview (editor): verde=hierba, verde oscuro=bosque, azul=agua, puntos=recursos, cuadros=edificios."
	pv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(pv_label)


func _section(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	return l


func _row(label_text: String, ctrl: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(100, 0)
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	return h


func _mk_name_edit() -> LineEdit:
	_name_edit = LineEdit.new()
	_name_edit.text = map_name
	_name_edit.text_changed.connect(func(t: String) -> void: map_name = t.strip_edges())
	return _name_edit


func _mk_seed_spin() -> SpinBox:
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 999999999
	_seed_spin.step = 1
	_seed_spin.value = map_seed
	_seed_spin.value_changed.connect(func(v: float) -> void: map_seed = int(v))
	return _seed_spin


func _mk_relics_spin() -> SpinBox:
	_relics_spin = SpinBox.new()
	_relics_spin.min_value = 0
	_relics_spin.max_value = 20
	_relics_spin.step = 1
	_relics_spin.value = relics
	_relics_spin.value_changed.connect(func(v: float) -> void: relics = int(v); refresh())
	return _relics_spin


func _mk_size_w_spin() -> SpinBox:
	_size_w_spin = SpinBox.new()
	_size_w_spin.min_value = MIN_SIZE
	_size_w_spin.max_value = MAX_SIZE
	_size_w_spin.step = 1
	_size_w_spin.value = map_w
	return _size_w_spin


func _mk_size_h_spin() -> SpinBox:
	_size_h_spin = SpinBox.new()
	_size_h_spin.min_value = MIN_SIZE
	_size_h_spin.max_value = MAX_SIZE
	_size_h_spin.step = 1
	_size_h_spin.value = map_h
	return _size_h_spin


func _mk_tool_selector() -> OptionButton:
	_tool_selector = OptionButton.new()
	for id in TOOL_NAMES.keys():
		_tool_selector.add_item(str(TOOL_NAMES[id]), int(id))
	_tool_selector.selected = 0
	_tool_selector.item_selected.connect(_on_tool_selected)
	return _tool_selector


func _mk_brush_spin() -> SpinBox:
	_brush_spin = SpinBox.new()
	_brush_spin.min_value = 1
	_brush_spin.max_value = 8
	_brush_spin.step = 1
	_brush_spin.value = brush_size
	_brush_spin.tooltip_text = "Radio del pincel de terreno en tiles."
	_brush_spin.value_changed.connect(func(v: float) -> void: brush_size = int(v))
	return _brush_spin


func _mk_building_selector() -> OptionButton:
	_building_selector = OptionButton.new()
	for i in BUILDING_IDS.size():
		_building_selector.add_item(BUILDING_IDS[i], i)
	_building_selector.selected = 0
	_building_selector.item_selected.connect(
		func(idx: int) -> void: current_building = BUILDING_IDS[idx])
	return _building_selector


func _mk_player_spin() -> SpinBox:
	_player_spin = SpinBox.new()
	_player_spin.min_value = 0
	_player_spin.max_value = 7
	_player_spin.step = 1
	_player_spin.value = current_player
	_player_spin.value_changed.connect(func(v: float) -> void: current_player = int(v))
	return _player_spin


# ============================================================== datos/mapa ==
func has_terrain() -> bool:
	return _terrain.size() == map_w * map_h


func get_tile(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= map_w or y >= map_h:
		return T_GRASS
	return _terrain[y * map_w + x]


func set_tile(x: int, y: int, t: int) -> void:
	if x < 0 or y < 0 or x >= map_w or y >= map_h:
		return
	_terrain[y * map_w + x] = clampi(t, T_GRASS, T_WATER) as int


func terrain_color(t: int) -> Color:
	match t:
		T_FOREST:
			return COL_FOREST
		T_WATER:
			return COL_WATER
		_:
			return COL_GRASS


func resource_color(kind: String) -> Color:
	match kind:
		"gold":
			return COL_GOLD
		"stone":
			return COL_STONE
		"berry":
			return COL_BERRY
		_:
			return COL_TREE


func canvas_cell() -> Vector2:
	if _canvas == null or map_w <= 0 or map_h <= 0:
		return Vector2.ZERO
	return Vector2(_canvas.size.x / float(map_w), _canvas.size.y / float(map_h))


func screen_to_tile(pos: Vector2) -> Vector2i:
	var cell := canvas_cell()
	if cell.x <= 0.0 or cell.y <= 0.0:
		return Vector2i(-1, -1)
	return Vector2i(clampi(int(pos.x / cell.x), 0, map_w - 1), clampi(int(pos.y / cell.y), 0, map_h - 1))


func paint_at(pos: Vector2) -> void:
	var c := screen_to_tile(pos)
	if c.x < 0:
		return
	match current_tool:
		TOOL_GRASS, TOOL_FOREST, TOOL_WATER:
			_paint_disc(c, brush_size, current_tool)
		TOOL_TREE, TOOL_GOLD, TOOL_STONE, TOOL_BERRY:
			_place_resource(c, current_tool)
		TOOL_BUILDING:
			_place_building(c)
		TOOL_ERASE:
			erase_at(pos)
			return
	refresh()


func erase_at(pos: Vector2) -> void:
	var c := screen_to_tile(pos)
	if c.x < 0:
		return
	# Borra recursos/edificios en el radio del pincel y devuelve el terreno a hierba.
	var r := maxi(brush_size, 1) - 1
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if x < 0 or y < 0 or x >= map_w or y >= map_h:
				continue
			var dx := x - c.x
			var dy := y - c.y
			if dx * dx + dy * dy > r * r and r > 0:
				continue
			set_tile(x, y, T_GRASS)
	_remove_resource_at_rect(c, r)
	_remove_building_at_rect(c, r)
	refresh()


func _paint_disc(center: Vector2i, radius: int, terrain: int) -> void:
	var t := T_GRASS
	match terrain:
		TOOL_FOREST:
			t = T_FOREST
		TOOL_WATER:
			t = T_WATER
	var r := maxi(radius, 1) - 1
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			if x < 0 or y < 0 or x >= map_w or y >= map_h:
				continue
			var dx := x - center.x
			var dy := y - center.y
			if dx * dx + dy * dy > r * r and r > 0:
				continue
			set_tile(x, y, t)


func _tool_to_res_kind(tool: int) -> String:
	match tool:
		TOOL_GOLD:
			return "gold"
		TOOL_STONE:
			return "stone"
		TOOL_BERRY:
			return "berry"
		_:
			return "tree"


func _place_resource(c: Vector2i, tool: int) -> void:
	var kind := _tool_to_res_kind(tool)
	# Un recurso por tile: sustituye el que hubiera.
	for i in range(_resources.size() - 1, -1, -1):
		var e: Dictionary = _resources[i]
		if int(e["x"]) == c.x and int(e["y"]) == c.y:
			_resources.remove_at(i)
	_resources.append({"kind": kind, "x": c.x, "y": c.y,
		"amount": int(RES_DEFAULT_AMOUNT.get(kind, 100))})


func _place_building(c: Vector2i) -> void:
	# Un edificio por tile: sustituye el que hubiera en ese tile.
	for i in range(_buildings.size() - 1, -1, -1):
		var e: Dictionary = _buildings[i]
		if int(e["x"]) == c.x and int(e["y"]) == c.y:
			_buildings.remove_at(i)
	_buildings.append({"id": current_building, "x": c.x, "y": c.y, "player": current_player})


func _remove_resource_at_rect(c: Vector2i, r: int) -> void:
	for i in range(_resources.size() - 1, -1, -1):
		var e: Dictionary = _resources[i]
		if absi(int(e["x"]) - c.x) <= r and absi(int(e["y"]) - c.y) <= r:
			_resources.remove_at(i)


func _remove_building_at_rect(c: Vector2i, r: int) -> void:
	for i in range(_buildings.size() - 1, -1, -1):
		var e: Dictionary = _buildings[i]
		if absi(int(e["x"]) - c.x) <= r and absi(int(e["y"]) - c.y) <= r:
			_buildings.remove_at(i)


func _new_map(w: int, h: int, keep_refresh := true) -> void:
	map_w = clampi(w, MIN_SIZE, MAX_SIZE)
	map_h = clampi(h, MIN_SIZE, MAX_SIZE)
	_terrain.resize(map_w * map_h)
	_terrain.fill(T_GRASS)
	if keep_refresh:
		refresh()


func _on_resize() -> void:
	var nw := int(_size_w_spin.value)
	var nh := int(_size_h_spin.value)
	var old := _terrain.duplicate()
	var ow := map_w
	var oh := map_h
	_new_map(nw, nh, false)
	for y in mini(nh, oh):
		for x in mini(nw, ow):
			_terrain[y * map_w + x] = old[y * ow + x] if y * ow + x < old.size() else T_GRASS
	# Poda lo que quede fuera.
	for i in range(_resources.size() - 1, -1, -1):
		var e: Dictionary = _resources[i]
		if int(e["x"]) >= map_w or int(e["y"]) >= map_h:
			_resources.remove_at(i)
	for i in range(_buildings.size() - 1, -1, -1):
		var b: Dictionary = _buildings[i]
		if int(b["x"]) >= map_w or int(b["y"]) >= map_h:
			_buildings.remove_at(i)
	_set_status("Mapa %dx%d (se conservó lo que cabía)." % [map_w, map_h])
	refresh()


func _on_fill_grass() -> void:
	_terrain.fill(T_GRASS)
	refresh()


func _on_clear_resources() -> void:
	_resources.clear()
	refresh()


func _on_clear_buildings() -> void:
	_buildings.clear()
	refresh()


func _on_tool_selected(idx: int) -> void:
	current_tool = _tool_selector.get_item_id(idx)
	if current_tool == TOOL_BUILDING:
		_set_status("Click para colocar '%s' (jugador %d). Click der para borrar." % [current_building, current_player])


# ============================================================== refresco ====
func refresh() -> void:
	if _canvas != null:
		_canvas.queue_redraw()
	_update_preview()
	_update_counts()
	if is_node_ready():
		_dirty_preview = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _canvas != null:
		_canvas.queue_redraw()


func _update_counts() -> void:
	if _counts == null:
		return
	var grass := 0
	var forest := 0
	var water := 0
	for t in _terrain:
		match t:
			T_FOREST:
				forest += 1
			T_WATER:
				water += 1
			_:
				grass += 1
	var trees := 0
	var gold := 0
	var stone := 0
	var berry := 0
	for e in _resources:
		match str(e.get("kind", "tree")):
			"gold":
				gold += 1
			"stone":
				stone += 1
			"berry":
				berry += 1
			_:
				trees += 1
	_counts.text = "Terreno %dx%d — hierba:%d bosque:%d agua:%d\nRecursos: árbol:%d oro:%d piedra:%d bayas:%d\nEdificios: %d  Reliquias: %d  Semilla: %d" % [
		map_w, map_h, grass, forest, water, trees, gold, stone, berry,
		_buildings.size(), relics, map_seed]


func _set_status(t: String) -> void:
	if _status != null:
		_status.text = t


# ============================================================== mini-preview =
func _update_preview() -> void:
	if _preview_rect == null or not has_terrain():
		return
	var img := Image.create(map_w, map_h, false, Image.FORMAT_RGB8)
	for y in map_h:
		for x in map_w:
			img.set_pixel(x, y, terrain_color(get_tile(x, y)))
	for e in _resources:
		var ex := clampi(int(e.get("x", 0)), 0, map_w - 1)
		var ey := clampi(int(e.get("y", 0)), 0, map_h - 1)
		img.set_pixel(ex, ey, resource_color(str(e.get("kind", "tree"))))
	for b in _buildings:
		var bx := clampi(int(b.get("x", 0)), 0, map_w - 1)
		var by := clampi(int(b.get("y", 0)), 0, map_h - 1)
		var pid: int = clampi(int(b.get("player", 0)), 0, 7)
		img.set_pixel(bx, by, PLAYER_COLORS[pid])
	_preview_rect.texture = ImageTexture.create_from_image(img)


# ============================================================== guardar/cargar
func to_dict() -> Dictionary:
	var rows: Array = []
	for y in map_h:
		var sb := ""
		for x in map_w:
			match get_tile(x, y):
				T_FOREST:
					sb += "F"
				T_WATER:
					sb += "W"
				_:
					sb += "G"
		rows.append(sb)
	var trees := 0
	var gold := 0
	var stone := 0
	var forage := 0
	for e in _resources:
		match str(e.get("kind", "tree")):
			"gold":
				gold += 1
			"stone":
				stone += 1
			"berry":
				forage += 1
			_:
				trees += 1
	return {
		"format": FORMAT_VERSION,
		"name": map_name,
		"size_tiles": [map_w, map_h],
		"seed": map_seed,
		"terrain": "custom",
		"water": _terrain.has(T_WATER),
		"terrain_rows": rows,
		"resources": _resources.duplicate(true),
		"buildings": _buildings.duplicate(true),
		"start_resources": {
			"wood_patches": maxi(trees / 8, mini(trees, 1) if trees > 0 else 0),
			"gold_piles": gold,
			"stone_piles": stone,
			"forage": forage,
		},
		"relics": relics,
	}


func load_dict(d: Dictionary) -> bool:
	if typeof(d) != TYPE_DICTIONARY or d.is_empty():
		return false
	map_name = str(d.get("name", "Personalizado"))
	var st: Array = d.get("size_tiles", [DEFAULT_W, DEFAULT_H])
	var w := clampi(int(st[0]) if st.size() > 0 else DEFAULT_W, MIN_SIZE, MAX_SIZE)
	var h := clampi(int(st[1]) if st.size() > 1 else DEFAULT_H, MIN_SIZE, MAX_SIZE)
	map_seed = int(d.get("seed", 1234))
	relics = clampi(int(d.get("relics", 0)), 0, 20)
	_new_map(w, h, false)
	# Terreno: filas compactas "GFW" si existen; si no, hierba.
	var rows: Array = d.get("terrain_rows", [])
	if rows.size() == map_h:
		for y in map_h:
			var row := str(rows[y])
			for x in mini(map_w, row.length()):
				match row[x]:
					"F":
						set_tile(x, y, T_FOREST)
					"W":
						set_tile(x, y, T_WATER)
					_:
						set_tile(x, y, T_GRASS)
	# Recursos: acepta formato editor {kind,x,y,amount} y legacy {id,pos}.
	_resources.clear()
	for e in d.get("resources", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var kind := str(e.get("kind", e.get("id", "tree")))
		if kind == "berry_bush":
			kind = "berry"
		elif kind == "gold_mine":
			kind = "gold"
		elif kind == "stone_mine":
			kind = "stone"
		elif kind not in RES_KINDS:
			kind = "tree"
		var pos: Array = e.get("pos", [])
		var ex := int(e.get("x", pos[0] if pos.size() > 0 else 0))
		var ey := int(e.get("y", pos[1] if pos.size() > 1 else 0))
		if ex < 0 or ey < 0 or ex >= map_w or ey >= map_h:
			continue
		_resources.append({"kind": kind, "x": ex, "y": ey,
			"amount": int(e.get("amount", RES_DEFAULT_AMOUNT.get(kind, 100)))})
	# Edificios: acepta {id,x,y,player} y legacy {id,pos,player}.
	_buildings.clear()
	for b in d.get("buildings", []):
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var bid := str(b.get("id", "casa"))
		if bid not in BUILDING_IDS:
			continue
		var bpos: Array = b.get("pos", [])
		var bx := int(b.get("x", bpos[0] if bpos.size() > 0 else 0))
		var by := int(b.get("y", bpos[1] if bpos.size() > 1 else 0))
		if bx < 0 or by < 0 or bx >= map_w or by >= map_h:
			continue
		_buildings.append({"id": bid, "x": bx, "y": by,
			"player": clampi(int(b.get("player", 0)), 0, 7)})
	_sync_spins()
	refresh()
	return true


func _sync_spins() -> void:
	if _name_edit != null:
		_name_edit.text = map_name
	if _seed_spin != null:
		_seed_spin.value = map_seed
	if _relics_spin != null:
		_relics_spin.value = relics
	if _size_w_spin != null:
		_size_w_spin.value = map_w
	if _size_h_spin != null:
		_size_h_spin.value = map_h


func _on_save() -> void:
	var path := _path_edit.text.strip_edges()
	if path.is_empty():
		path = DEFAULT_PATH
	var data := to_dict()
	var txt := JSON.stringify(data, "  ")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_set_status("ERROR al guardar '%s' (¿ruta válida? en juego usa user://)." % path)
		return
	f.store_string(txt)
	f.close()
	_set_status("Guardado %dx%d, %d recursos, %d edificios -> %s" % [
		map_w, map_h, _resources.size(), _buildings.size(), path])


func _on_load() -> void:
	var path := _path_edit.text.strip_edges()
	if path.is_empty():
		path = DEFAULT_PATH
	if not FileAccess.file_exists(path):
		_set_status("No existe '%s'." % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_set_status("ERROR al abrir '%s'." % path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_status("JSON inválido en '%s'." % path)
		return
	if load_dict(parsed):
		_set_status("Cargado '%s' (%dx%d)." % [path, map_w, map_h])
	else:
		_set_status("No se pudo interpretar '%s'." % path)


## Carga estática sin instanciar (para el generador/partida, sigue sin sim).
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

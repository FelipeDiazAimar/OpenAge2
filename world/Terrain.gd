extends Node3D
class_name Terrain
## world/Terrain.gd — Terreno VISUAL 144x144 (cliente, NO afecta a la sim).
##
## - MeshInstance3D plano con colinas suaves (ruido de valor determinista
##   sembrado con SimRNG: instancia LOCAL, nunca toca SimAPI.SimRNGNode).
## - Textura procedural (Image generada en codigo): moteado sobre el que
##   multiplican los vertex colors hierba #6da34f / tierra #b0925c.
## - Agua: plano aparte a WATER_Y con world/Water.gdshader (solo TIME+math).
## - 500 arboles low-poly procedurales en 2 MultiMeshInstance3D
##   (troncos CylinderMesh + copas cono), agrupados en bosquetes segun
##   "wood_patches" de data/maps/arabia.json.
## - arabia.json declara 144x144 y "water": false: el plano de agua solo
##   asoma en hondonadas (charcas); el resto queda seco.
## Uso: Terrain.new() -> add_child -> build(map_seed, map_dict).

const MAP_W := 144
const MAP_H := 144
const TILE := 2.0
const WATER_Y := 0.35
const BASE_H := 2.00
const HILL_AMP := 1.70      # relieve suave: charcas lejos, spawns siempre secos
const DETAIL_AMP := 0.25    # detalle fino visual
const CTRL_STEP := 12       # rejilla gruesa cada 12 tiles (13x13 puntos)
const TEX_TILING := 8.0     # 1 repeticion de textura cada 8 tiles

# Aplanado en spawns (lo fija GameWorld antes de build): meseta a SAFE_H.
const FLATTEN_R := 7.0
const FLATTEN_FULL := 4.0
const SAFE_H := 2.30

const GRASS_ARABIA := Color(0.42, 0.58, 0.28)
const DIRT_ARABIA := Color(0.62, 0.53, 0.35)
const GRASS_FOREST := Color(0.24, 0.44, 0.22)
const DIRT_FOREST := Color(0.38, 0.33, 0.24)
const GRASS_TROPICAL := Color(0.30, 0.62, 0.30)
const DIRT_TROPICAL := Color(0.66, 0.56, 0.36)
const TRUNK_COL := Color(0.42, 0.30, 0.19)
const LEAF_COL := Color(0.24, 0.47, 0.20)

const _TREE_XOR := 0x2B7A17C5

@export var map_seed := 1234
@export var tree_count := 500
@export var auto_build := true   # construye en _ready (pantallazo rapido)

var _ctrl: PackedFloat32Array = PackedFloat32Array()  # rejilla (CN*CN)
var _ctrl_n := 0
var _heights: PackedFloat32Array = PackedFloat32Array() # (MAP_W+1)*(MAP_H+1)
## Tiles de spawn a aplanar (los fija GameWorld antes de build()). Solo visual.
var flatten_spots: Array[Vector2] = []
var _ground: MeshInstance3D
## Paleta del bioma (la fija build() según el mapa). Solo visual.
var GRASS := GRASS_ARABIA
var DIRT := DIRT_ARABIA
var _water: MeshInstance3D
var _trunks: MultiMeshInstance3D
var _leaves: MultiMeshInstance3D
var _built := false


func _ready() -> void:
	if auto_build:
		var md := _load_map_dict("res://data/maps/arabia.json")
		build(map_seed, md)


func build(p_seed: int = 1234, p_map: Dictionary = {}) -> void:
	clear()
	map_seed = p_seed
	_apply_biome(str(p_map.get("biome", p_map.get("terrain", ""))))
	_gen_control_grid(p_seed)
	_build_ground(p_seed)
	_build_water()
	_build_trees(p_seed, p_map)
	_built = true


func clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_ground = null
	_water = null
	_trunks = null
	_leaves = null
	_heights = PackedFloat32Array()
	_ctrl = PackedFloat32Array()
	_built = false


# ---------------------------------------------------------------- biomas --
func _apply_biome(key: String) -> void:
	# Paleta por bioma: arabia (base), bosque (oscuro), tropical/islas (vivo).
	var k := key.to_lower()
	if "bosque" in k or "forest" in k or "negro" in k:
		GRASS = GRASS_FOREST
		DIRT = DIRT_FOREST
	elif "isla" in k or "trop" in k or "island" in k:
		GRASS = GRASS_TROPICAL
		DIRT = DIRT_TROPICAL
	else:
		GRASS = GRASS_ARABIA
		DIRT = DIRT_ARABIA


# ---------------------------------------------------------------- alturas --
func _gen_control_grid(p_seed: int) -> void:
	# Rejilla gruesa aleatoria via SimRNG local (determinista, no toca la sim).
	var rng := SimRNG.new()
	rng.set_seed(p_seed)
	_ctrl_n = MAP_W / CTRL_STEP + 1  # 13
	_ctrl.resize(_ctrl_n * _ctrl_n)
	for i in _ctrl.size():
		_ctrl[i] = rng.next_float()  # [0,1)
	rng.free()


static func _smoother(t: float) -> float:
	var t2: float = clampf(t, 0.0, 1.0)
	return t2 * t2 * t2 * (t2 * (t2 * 6.0 - 15.0) + 10.0)


func _coarse_noise(fx: float, fz: float) -> float:
	# Ruido de valor [0,1] por interpolacion smootherstep de _ctrl.
	var gx: float = clampf(fx / float(CTRL_STEP), 0.0, float(_ctrl_n - 1) - 0.001)
	var gz: float = clampf(fz / float(CTRL_STEP), 0.0, float(_ctrl_n - 1) - 0.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var tx := _smoother(gx - float(x0))
	var tz := _smoother(gz - float(z0))
	var a: float = _ctrl[z0 * _ctrl_n + x0]
	var b: float = _ctrl[z0 * _ctrl_n + x0 + 1]
	var c: float = _ctrl[(z0 + 1) * _ctrl_n + x0]
	var d: float = _ctrl[(z0 + 1) * _ctrl_n + x0 + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func _height_at_float(fx: float, fz: float) -> float:
	# Colinas suaves: 1 octava gruesa + detalle fino determinista (sin estado).
	var n: float = _coarse_noise(fx, fz) * 2.0 - 1.0            # [-1,1]
	var det: float = sin(fx * 1.7 + float(map_seed % 97)) * sin(fz * 1.3 + float(map_seed % 53))
	return BASE_H + n * HILL_AMP + det * DETAIL_AMP


func ground_height(tx: float, tz: float) -> float:
	# Altura visual por coords de tile (float). Solo cliente.
	if _heights.is_empty():
		return _height_at_float(tx, tz)
	var cx: float = clampf(tx, 0.0, float(MAP_W) - 0.001)
	var cz: float = clampf(tz, 0.0, float(MAP_H) - 0.001)
	var x0 := int(cx)
	var z0 := int(cz)
	var txf: float = cx - float(x0)
	var tzf: float = cz - float(z0)
	var w := MAP_W + 1
	var a: float = _heights[z0 * w + x0]
	var b: float = _heights[z0 * w + x0 + 1]
	var c: float = _heights[(z0 + 1) * w + x0]
	var d: float = _heights[(z0 + 1) * w + x0 + 1]
	return lerpf(lerpf(a, b, txf), lerpf(c, d, txf), tzf)


func tile_to_world(t: Vector2) -> Vector3:
	return Vector3(t.x * TILE, ground_height(t.x, t.y), t.y * TILE)


func world_to_tile(w: Vector3) -> Vector2:
	return Vector2(w.x / TILE, w.z / TILE)


func get_map_center_world() -> Vector3:
	# Para centrar AoeCamera (orto -32,-45): cam.position = centro + offset.
	return Vector3(float(MAP_W) * TILE * 0.5, 0.0, float(MAP_H) * TILE * 0.5)


# ------------------------------------------------------------------ suelo --
func _build_ground(p_seed: int) -> void:
	_heights.resize((MAP_W + 1) * (MAP_H + 1))
	for gz in MAP_H + 1:
		for gx in MAP_W + 1:
			_heights[gz * (MAP_W + 1) + gx] = _height_at_float(float(gx), float(gz))
	_apply_flatten()

	# Malla INDEXADA con vértices compartidos: normales y colores suaves
	# (antes cada quad tenía sus 4 vértices -> facetas cuadradas).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := MAP_W + 1
	for gz in MAP_H + 1:
		for gx in MAP_W + 1:
			st.set_color(_color_for(gx, gz))
			st.set_uv(Vector2(float(gx) / TEX_TILING, float(gz) / TEX_TILING))
			st.add_vertex(Vector3(gx * TILE, _heights[gz * w + gx], gz * TILE))
	for gz in MAP_H:
		for gx in MAP_W:
			var i0 := gz * w + gx
			var i1 := i0 + 1
			var i2 := i0 + w
			var i3 := i2 + 1
			# Mismo winding que antes: normal +Y (visto desde arriba).
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)
	st.generate_normals()
	_ground = MeshInstance3D.new()
	_ground.name = "Ground"
	_ground.mesh = st.commit()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _make_detail_texture(p_seed)
	mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ground.material_override = mat
	add_child(_ground)


func _apply_flatten() -> void:
	# Meseta suave en cada spawn: plano a SAFE_H en FLATTEN_FULL,
	# fundido hasta FLATTEN_R. Asi el TC nunca queda en agua ni en pendiente.
	if flatten_spots.is_empty():
		return
	var w := MAP_W + 1
	for s in flatten_spots:
		var x0 := maxi(0, floori(s.x - FLATTEN_R))
		var x1 := mini(MAP_W, ceili(s.x + FLATTEN_R))
		var z0 := maxi(0, floori(s.y - FLATTEN_R))
		var z1 := mini(MAP_H, ceili(s.y + FLATTEN_R))
		for gz in range(z0, z1 + 1):
			for gx in range(x0, x1 + 1):
				var d := Vector2(float(gx) - s.x, float(gz) - s.y).length()
				if d >= FLATTEN_R:
					continue
				var k := 1.0
				if d > FLATTEN_FULL:
					k = 1.0 - _smoother((d - FLATTEN_FULL) / (FLATTEN_R - FLATTEN_FULL))
				var i := gz * w + gx
				_heights[i] = lerpf(_heights[i], SAFE_H, k)


func _add_vert(st: SurfaceTool, v: Vector3, c: Color, tx: int, tz: int) -> void:
	st.set_color(c)
	st.set_uv(Vector2(float(tx) / TEX_TILING, float(tz) / TEX_TILING))
	st.add_vertex(v)


func _near_spawn(px: float, pz: float, radius: float) -> bool:
	for s in flatten_spots:
		if Vector2(px - s.x, pz - s.y).length() < radius:
			return true
	return false


func _color_for(tx: int, tz: int) -> Color:
	# Por vértice compartido: degradado suave (sin bandas por quad).
	# Manchas tierra/hierba via el mismo ruido grueso + tinte de altura.
	var h: float = _heights[tz * (MAP_W + 1) + tx]
	var patch: float = _coarse_noise(float(tx) + 61.0, float(tz) + 37.0)
	var t: float = clampf(0.55 + (patch - 0.5) * 1.1 - (h - BASE_H) * 0.15, 0.0, 1.0)
	return DIRT.lerp(GRASS, t)


func _make_detail_texture(p_seed: int) -> ImageTexture:
	# Moteado 128x128 determinista (SimRNG local): multiplica al vertex color.
	var rng := SimRNG.new()
	rng.set_seed(p_seed ^ 0x51F15EED)
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	img.fill(Color(0.93, 0.93, 0.93))
	for i in 4200:
		var x: int = rng.next_int(0, 127)
		var y: int = rng.next_int(0, 127)
		var s: float = rng.next_float()  # [0,1)
		var v := 0.78 + s * 0.30         # mota oscura..clara
		img.set_pixel(x, y, Color(v, v, v))
	rng.free()
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------- agua --
func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(float(MAP_W) * TILE, float(MAP_H) * TILE)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.mesh = plane
	# Centrado bajo el suelo (suelo va de 0..MAP*TILE en XZ).
	_water.position = Vector3(float(MAP_W) * TILE * 0.5, WATER_Y, float(MAP_H) * TILE * 0.5)
	var smat := ShaderMaterial.new()
	smat.shader = load("res://world/Water.gdshader") as Shader
	_water.material_override = smat
	add_child(_water)


# ----------------------------------------------------------------- arboles --
func _build_trees(p_seed: int, p_map: Dictionary) -> void:
	var patches := 8
	var sr: Dictionary = p_map.get("start_resources", {})
	if sr.has("wood_patches"):
		patches = maxi(1, int(sr["wood_patches"]))

	var rng := SimRNG.new()
	rng.set_seed((p_seed ^ _TREE_XOR) & 0xFFFFFFFF)
	# Centros de bosquete.
	var centers: Array[Vector2] = []
	for i in patches:
		centers.append(Vector2(
			rng.next_float_range(10.0, float(MAP_W) - 10.0),
			rng.next_float_range(10.0, float(MAP_H) - 10.0)))
	# Candidatos con reintentos acotados (determinista).
	var xforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	var guard := 0
	while xforms.size() < tree_count and guard < tree_count * 20:
		guard += 1
		var c: Vector2 = centers[rng.next_int(0, centers.size() - 1)]
		var px: float = c.x + rng.next_float_range(-9.0, 9.0) + rng.next_float_range(-4.0, 4.0)
		var pz: float = c.y + rng.next_float_range(-9.0, 9.0) + rng.next_float_range(-4.0, 4.0)
		if px < 3.0 or pz < 3.0 or px > float(MAP_W) - 3.0 or pz > float(MAP_H) - 3.0:
			continue
		if _near_spawn(px, pz, 9.0):
			continue  # sin arboles dentro del pueblo inicial
		var h: float = _height_at_float(px, pz)
		if h < WATER_Y + 0.15:
			continue  # no plantar en agua/charcas
		var s: float = rng.next_float_range(0.8, 1.35)
		var rot := Basis(Vector3.UP, rng.next_float_range(0.0, TAU))
		var basis: Basis = (rot * Basis.from_scale(Vector3(s, s, s)))
		xforms.append(Transform3D(basis, Vector3(px * TILE, h - 0.1, pz * TILE)))
		tints.append(LEAF_COL.lerp(Color("7fae4e"), rng.next_float() * 0.6))
	rng.free()

	var n := xforms.size()
	_trunks = _make_forest_mmi(_make_trunk_mesh(), TRUNK_COL, Color.WHITE, xforms, n, false)
	_trunks.name = "Trunks"
	_leaves = _make_forest_mmi(_make_leaves_mesh(), LEAF_COL, Color.WHITE, xforms, n, true)
	_leaves.name = "Leaves"
	# La copa va elevada sobre el tronco (offset en Y local por instancia).
	for i in n:
		var t: Transform3D = _leaves.multimesh.get_instance_transform(i)
		var sc: Vector3 = t.basis.get_scale()
		t.origin.y += 1.55 * sc.y
		_leaves.multimesh.set_instance_transform(i, t)
		_leaves.multimesh.set_instance_color(i, tints[i])
	add_child(_trunks)
	add_child(_leaves)


func _make_forest_mmi(mesh: Mesh, base: Color, _unused: Color, xforms: Array, n: int, use_colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_colors
	mm.mesh = mesh
	mm.instance_count = maxi(1, n)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base
	mat.roughness = 0.9
	if use_colors:
		mat.vertex_color_use_as_albedo = true  # habilita color por instancia
	mmi.material_override = mat
	for i in n:
		mm.set_instance_transform(i, xforms[i])
		if use_colors:
			mm.set_instance_color(i, Color.WHITE)  # se retinta despues
	return mmi


func _make_trunk_mesh() -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.12
	m.bottom_radius = 0.18
	m.height = 1.2
	m.radial_segments = 5
	m.rings = 1
	return m


func _make_leaves_mesh() -> CylinderMesh:
	# Cono low-poly (copa). Todo procedural, sin assets.
	var m := CylinderMesh.new()
	m.top_radius = 0.02
	m.bottom_radius = 1.05
	m.height = 2.1
	m.radial_segments = 8
	m.rings = 2
	return m


# ------------------------------------------------------------------ ayuda --
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

class_name ModelFactory
extends RefCounted
## ModelFactory: mallas 3D procedurales low-poly, 100% gratis (sin assets externos).
## Todo usa BoxMesh / CapsuleMesh / CylinderMesh / SphereMesh / PrismMesh / TorusMesh
## + StandardMaterial3D plano (roughness alto, sin texturas).
##
## API:
##   ModelFactory.spawn_unit(kind: String, civ_color: Color) -> Node3D
##     kind: "aldeano" | "milicia" | "arquero" (alias: villager, militia, archer)
##   ModelFactory.spawn_building(id: String, age: int, civ_color: Color) -> Node3D
##     id: "casa" | "centro_urbano"/"tc" | "cuartel" | "castillo"
##       | "arbol" | "mina_oro" | "mina_piedra" | "granja" (+ alias ES/EN)

static var _mat_cache: Dictionary = {}


# ---------------------------------------------------------------- materiales --
static func mat(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%0.2f" % [color.to_html(), metallic]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	m.metallic = metallic
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var sm := m as StandardMaterial3D
	_mat_cache[key] = sm
	return sm


static func _roof_color(civ_color: Color, age: int) -> Color:
	# El techo tiñe con color de civ y se oscurece por edad (0..3+).
	var f := clampf(1.0 - float(maxi(age, 0)) * 0.12, 0.55, 1.0)
	return Color(civ_color.r * f, civ_color.g * f, civ_color.b * f)


# ------------------------------------------------------------------ piezas ---
static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, metallic: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat(color, metallic)
	parent.add_child(mi)
	return mi


static func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat(color)
	parent.add_child(mi)
	return mi


static func _cylinder(parent: Node3D, r_top: float, r_bot: float, height: float, pos: Vector3, color: Color, sides: int = 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = height
	mesh.radial_segments = sides
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat(color)
	parent.add_child(mi)
	return mi


static func _sphere(parent: Node3D, radius: float, pos: Vector3, color: Color, squash_y: float = 1.0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0 * squash_y
	mesh.radial_segments = 8
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat(color)
	parent.add_child(mi)
	return mi


static func _prism(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	# Techo a dos aguas low-poly.
	var mesh := PrismMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat(color)
	parent.add_child(mi)
	return mi


static func _torus_bow(parent: Node3D, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.03
	mesh.outer_radius = 0.35
	mesh.rings = 8
	mesh.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = PI * 0.5
	mi.material_override = mat(color)
	parent.add_child(mi)
	return mi


static func _flag(parent: Node3D, pos: Vector3, civ_color: Color, pole_h: float = 1.2) -> void:
	_cylinder(parent, 0.03, 0.03, pole_h, pos + Vector3(0, pole_h * 0.5, 0), Color(0.25, 0.2, 0.15), 6)
	_box(parent, Vector3(0.06, 0.3, 0.5), pos + Vector3(0, pole_h - 0.2, 0.28), civ_color)


# ================================================================== UNIDADES =
static func spawn_unit(kind: String, civ_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Unit_" + kind
	match kind.to_lower().strip_edges():
		"aldeano", "villager", "vill":
			_build_villager(root, civ_color)
		"milicia", "militia", "espadachin", "hombre_armas", "espadachin_mandoble", "campeon":
			_build_militia(root, civ_color)
		"arquero", "archer", "guerrillero", "ballestero", "arquero_tiro_largo":
			_build_archer(root, civ_color)
		"lancero", "piquero", "huscarle":
			_build_spearman(root, civ_color)
		"monje", "monk":
			_build_monk(root, civ_color)
		_:
			_build_villager(root, civ_color)
	return root


## Bicho de caza (oveja/jabalí/ciervo): cuerpo + cabeza + patas. Solo visual.
static func spawn_critter(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Crit_" + kind
	match kind.to_lower().strip_edges():
		"jabali":
			_build_critter(root, Color(0.35, 0.24, 0.16), true)
		"ciervo":
			_build_critter(root, Color(0.65, 0.48, 0.3), false)
		_:
			_build_critter(root, Color(0.88, 0.86, 0.8), false)
	return root


static func _build_critter(root: Node3D, piel: Color, colmillos: bool) -> void:
	_sphere(root, 0.42, Vector3(0, 0.55, 0), piel) # cuerpo
	_sphere(root, 0.22, Vector3(0, 0.95, 0.35), piel) # cabeza
	for sx in [-0.18, 0.18]:
		for sz in [-0.2, 0.2]:
			_box(root, Vector3(0.1, 0.35, 0.1), Vector3(sx, 0.18, sz), piel.darkened(0.25))
	if colmillos:
		_box(root, Vector3(0.05, 0.05, 0.18), Vector3(-0.12, 0.85, 0.55), Color(0.9, 0.88, 0.8))
		_box(root, Vector3(0.05, 0.05, 0.18), Vector3(0.12, 0.85, 0.55), Color(0.9, 0.88, 0.8))


static func _common_head(parent: Node3D, y: float) -> void:
	_sphere(parent, 0.22, Vector3(0, y, 0), Color(0.9, 0.72, 0.55)) # piel


static func _legs(parent: Node3D, color: Color) -> void:
	# Dos piernas low-poly (ya no flota la cápsula).
	_box(parent, Vector3(0.16, 0.35, 0.18), Vector3(-0.11, 0.18, 0), color)
	_box(parent, Vector3(0.16, 0.35, 0.18), Vector3(0.11, 0.18, 0), color)


static func _arms(parent: Node3D, color: Color, y: float, spread: float = 0.34) -> void:
	# Brazos caídos a los lados, ligeramente separados.
	_box(parent, Vector3(0.12, 0.5, 0.14), Vector3(-spread, y, 0), color)
	_box(parent, Vector3(0.12, 0.5, 0.14), Vector3(spread, y, 0), color)


static func _build_villager(root: Node3D, civ: Color) -> void:
	# Aldeano: piernas + túnica con faja civ + brazos + cabeza + sombrero paja.
	var tunic := Color(0.72, 0.62, 0.48)
	_legs(root, Color(0.4, 0.33, 0.25))
	_capsule(root, 0.28, 0.85, Vector3(0, 0.72, 0), tunic)
	_box(root, Vector3(0.5, 0.1, 0.36), Vector3(0, 0.62, 0), civ) # faja civ
	_arms(root, tunic, 0.78)
	_common_head(root, 1.32)
	_cylinder(root, 0.3, 0.32, 0.06, Vector3(0, 1.5, 0), Color(0.85, 0.72, 0.4), 10) # sombrero
	_cylinder(root, 0.14, 0.2, 0.12, Vector3(0, 1.58, 0), Color(0.8, 0.66, 0.35), 10)


static func _build_militia(root: Node3D, civ: Color) -> void:
	# Milicia: piernas + cota + cinturón + brazos + yelmo con nasal + espada + escudo.
	var steel := Color(0.55, 0.57, 0.6)
	_legs(root, Color(0.32, 0.28, 0.24))
	_box(root, Vector3(0.56, 0.62, 0.36), Vector3(0, 0.66, 0), steel) # cota
	_box(root, Vector3(0.58, 0.1, 0.38), Vector3(0, 0.4, 0), Color(0.35, 0.25, 0.15)) # cinturón
	_box(root, Vector3(0.14, 0.42, 0.16), Vector3(-0.36, 0.72, 0), steel) # brazo izq
	_box(root, Vector3(0.14, 0.42, 0.16), Vector3(0.36, 0.72, 0), steel) # brazo der
	_common_head(root, 1.22)
	_sphere(root, 0.24, Vector3(0, 1.3, 0), steel) # yelmo redondo
	_box(root, Vector3(0.06, 0.18, 0.05), Vector3(0, 1.22, 0.2), steel) # nasal
	# Espada en mano derecha: hoja + guarda + empuñadura.
	_box(root, Vector3(0.07, 0.62, 0.03), Vector3(0.44, 0.62, 0.12), Color(0.88, 0.9, 0.93), 0.7)
	_box(root, Vector3(0.18, 0.05, 0.05), Vector3(0.44, 0.32, 0.12), Color(0.4, 0.3, 0.15))
	_box(root, Vector3(0.05, 0.12, 0.05), Vector3(0.44, 0.24, 0.12), Color(0.3, 0.22, 0.12))
	# Escudo cometa civ con umbo.
	_box(root, Vector3(0.08, 0.6, 0.42), Vector3(-0.44, 0.7, 0), civ)
	_sphere(root, 0.09, Vector3(-0.49, 0.7, 0), steel)


static func _build_archer(root: Node3D, civ: Color) -> void:
	# Arquero: piernas + túnica verde + carcaj con flechas + arco + capucha.
	var cloth := Color(0.32, 0.5, 0.3)
	_legs(root, Color(0.35, 0.3, 0.24))
	_capsule(root, 0.27, 0.8, Vector3(0, 0.68, 0), cloth)
	_arms(root, cloth, 0.74)
	_common_head(root, 1.3)
	_sphere(root, 0.25, Vector3(0, 1.34, -0.03), civ) # capucha civ
	_torus_bow(root, Vector3(0.42, 0.9, 0), Color(0.45, 0.32, 0.18)) # arco
	_box(root, Vector3(0.04, 0.6, 0.04), Vector3(0.42, 0.9, 0), Color(0.9, 0.88, 0.8)) # cuerda
	_cylinder(root, 0.09, 0.09, 0.5, Vector3(-0.28, 0.95, -0.22), Color(0.4, 0.28, 0.15), 8) # carcaj
	for i in 3:
		_box(root, Vector3(0.03, 0.3, 0.03), Vector3(-0.31 + float(i) * 0.035, 1.25, -0.22), Color(0.85, 0.8, 0.7))


static func _build_spearman(root: Node3D, civ: Color) -> void:
	# Lancero/piquero: como milicia + lanza larga con punta + escudo redondo.
	_build_militia(root, civ)
	_cylinder(root, 0.035, 0.035, 2.2, Vector3(0.46, 1.3, 0.1), Color(0.45, 0.33, 0.2), 6) # asta
	_cylinder(root, 0.001, 0.07, 0.3, Vector3(0.46, 2.5, 0.1), Color(0.85, 0.87, 0.9), 6) # punta
	_cylinder(root, 0.3, 0.3, 0.08, Vector3(-0.46, 0.72, 0), civ, 12) # rodela civ


static func _build_monk(root: Node3D, civ: Color) -> void:
	# Monje: hábito túnica larga + capucha + cordón + cruz civ al pecho.
	var robe := Color(0.45, 0.36, 0.26)
	_cylinder(root, 0.26, 0.4, 1.1, Vector3(0, 0.55, 0), robe, 10) # hábito
	_sphere(root, 0.24, Vector3(0, 1.22, -0.02), robe) # capucha
	_common_head(root, 1.2)
	_box(root, Vector3(0.5, 0.07, 0.4), Vector3(0, 0.72, 0), Color(0.85, 0.78, 0.6)) # cordón
	_box(root, Vector3(0.08, 0.22, 0.04), Vector3(0, 0.95, 0.24), civ) # cruz vertical civ
	_box(root, Vector3(0.16, 0.07, 0.04), Vector3(0, 0.98, 0.24), civ) # cruz horizontal


# ================================================================ EDIFICIOS ==
static func spawn_building(id: String, age: int, civ_color: Color) -> Node3D:
	var root := Node3D.new()
	var key := id.to_lower().strip_edges()
	root.name = "Bld_" + key
	match key:
		"casa", "house":
			_build_house(root, age, civ_color)
		"centro_urbano", "tc", "town_center", "centro urbano":
			_build_tc(root, age, civ_color)
		"cuartel", "barracks":
			_build_barracks(root, age, civ_color)
		"castillo", "castle":
			_build_castle(root, age, civ_color)
		"arbol", "tree", "pino":
			_build_tree(root)
		"mina_oro", "mina oro", "gold", "oro":
			_build_gold_mine(root)
		"mina_piedra", "mina piedra", "stone", "piedra":
			_build_stone_mine(root)
		"granja", "farm", "molino":
			_build_farm(root)
		_:
			_build_house(root, age, civ_color)
	return root


static func _build_house(root: Node3D, age: int, civ: Color) -> void:
	# Casa: cubo + techo prisma color civ.
	_box(root, Vector3(3.0, 2.0, 3.0), Vector3(0, 1.0, 0), Color(0.82, 0.74, 0.6)) # muros
	_prism(root, Vector3(3.4, 1.4, 3.4), Vector3(0, 2.7, 0), _roof_color(civ, age)) # techo
	_box(root, Vector3(0.8, 1.2, 0.1), Vector3(0, 0.6, 1.51), Color(0.3, 0.22, 0.15)) # puerta
	_box(root, Vector3(0.6, 0.6, 0.1), Vector3(-0.9, 1.3, 1.51), Color(0.2, 0.25, 0.35)) # ventana


static func _build_tc(root: Node3D, age: int, civ: Color) -> void:
	# TC: base grande + piso alto + techo.
	_box(root, Vector3(6.0, 2.5, 6.0), Vector3(0, 1.25, 0), Color(0.8, 0.72, 0.58))
	_box(root, Vector3(4.5, 2.0, 4.5), Vector3(0, 3.5, 0), Color(0.75, 0.66, 0.52))
	_prism(root, Vector3(5.2, 1.8, 5.2), Vector3(0, 5.4, 0), _roof_color(civ, age))
	# Soportes madera + puerta + bandera civ.
	for sx in [-2.6, 2.6]:
		for sz in [-2.6, 2.6]:
			_box(root, Vector3(0.4, 2.5, 0.4), Vector3(sx, 1.25, sz), Color(0.45, 0.33, 0.2))
	_box(root, Vector3(1.2, 1.6, 0.12), Vector3(0, 0.8, 3.01), Color(0.28, 0.2, 0.13))
	_flag(root, Vector3(0, 6.0, 0), civ)


static func _build_barracks(root: Node3D, age: int, civ: Color) -> void:
	# Cuartel: nave larga + techo gris + estandarte civ.
	_box(root, Vector3(5.0, 2.2, 3.2), Vector3(0, 1.1, 0), Color(0.7, 0.62, 0.5))
	_prism(root, Vector3(5.4, 1.3, 3.6), Vector3(0, 2.85, 0), Color(0.45, 0.45, 0.48))
	_box(root, Vector3(1.0, 1.5, 0.12), Vector3(0, 0.75, 1.61), Color(0.25, 0.18, 0.12))
	_box(root, Vector3(0.5, 0.9, 0.06), Vector3(1.8, 1.4, 1.62), civ) # estandarte civ
	for i in 3:
		_box(root, Vector3(0.5, 0.7, 0.08), Vector3(-1.6 + float(i) * 0.9, 1.2, 1.61), Color(0.2, 0.24, 0.32))


static func _build_castle(root: Node3D, age: int, civ: Color) -> void:
	# Castillo: cuerpo central + 4 torres cilindricas + almenas + bandera civ.
	var stone := Color(0.62, 0.62, 0.65)
	var dark := Color(0.5, 0.5, 0.53)
	_box(root, Vector3(5.0, 3.5, 5.0), Vector3(0, 1.75, 0), stone)
	# Almenas del cuerpo.
	for ix in range(-2, 3):
		_box(root, Vector3(0.5, 0.5, 0.4), Vector3(float(ix) * 1.1, 3.75, 2.4), dark)
		_box(root, Vector3(0.5, 0.5, 0.4), Vector3(float(ix) * 1.1, 3.75, -2.4), dark)
	# 4 torres.
	for sx in [-2.8, 2.8]:
		for sz in [-2.8, 2.8]:
			_cylinder(root, 1.0, 1.1, 5.0, Vector3(sx, 2.5, sz), stone, 8)
			_cylinder(root, 1.2, 1.2, 0.5, Vector3(sx, 5.2, sz), dark, 8)
	_box(root, Vector3(1.4, 2.0, 0.15), Vector3(0, 1.0, 2.51), Color(0.3, 0.22, 0.14)) # porton
	_flag(root, Vector3(0, 3.9, 0), civ, 1.8)


static func _build_tree(root: Node3D) -> void:
	# Arbol: tronco cilindro + 2 copas esferas achatadas.
	_cylinder(root, 0.18, 0.25, 1.2, Vector3(0, 0.6, 0), Color(0.42, 0.3, 0.18), 7)
	_sphere(root, 1.0, Vector3(0, 1.9, 0), Color(0.2, 0.45, 0.2))
	_sphere(root, 0.65, Vector3(0, 2.7, 0), Color(0.25, 0.52, 0.24))


static func _build_gold_mine(root: Node3D) -> void:
	# Mina oro: monticulo amarillo achatado + rocas.
	_sphere(root, 1.4, Vector3(0, 0.3, 0), Color(0.85, 0.7, 0.25), 0.45)
	_sphere(root, 0.8, Vector3(0.9, 0.35, 0.4), Color(0.9, 0.75, 0.3), 0.6)
	_box(root, Vector3(0.4, 0.3, 0.4), Vector3(-0.8, 0.35, 0.5), Color(0.95, 0.82, 0.35))
	_box(root, Vector3(0.3, 0.25, 0.3), Vector3(0.2, 0.5, -0.7), Color(0.7, 0.55, 0.2))


static func _build_stone_mine(root: Node3D) -> void:
	# Mina piedra: monticulo gris + rocas.
	_sphere(root, 1.4, Vector3(0, 0.3, 0), Color(0.55, 0.56, 0.58), 0.45)
	_sphere(root, 0.8, Vector3(-0.9, 0.35, -0.3), Color(0.62, 0.63, 0.65), 0.6)
	_box(root, Vector3(0.45, 0.35, 0.45), Vector3(0.8, 0.35, 0.5), Color(0.48, 0.49, 0.51))
	_box(root, Vector3(0.3, 0.25, 0.3), Vector3(0.1, 0.5, 0.8), Color(0.66, 0.67, 0.69))


static func _build_farm(root: Node3D) -> void:
	# Granja: plano verde fino + 4 filas de cultivo.
	_box(root, Vector3(4.0, 0.12, 4.0), Vector3(0, 0.06, 0), Color(0.35, 0.55, 0.25))
	for i in 4:
		var z := -1.5 + float(i) * 1.0
		_box(root, Vector3(3.6, 0.22, 0.45), Vector3(0, 0.2, z), Color(0.45, 0.65, 0.28))
		for j in 4:
			_sphere(root, 0.16, Vector3(-1.3 + float(j) * 0.85, 0.42, z), Color(0.55, 0.72, 0.3))

extends Node3D
# SelectionMarkers - anillo verde bajo unidades/edificios seleccionados (SOLO CLIENTE).
# Lee Selection.get_selected() cada frame y posiciona anillos del pool.
# Verde propio. Sin lógica sim: nunca entra en el hash.

var selection: Control = null
var units: Dictionary = {}
var buildings: Dictionary = {}

var _rings := {} # uid -> MeshInstance3D
var _mesh: TorusMesh = null
var _mat: StandardMaterial3D = null

const UNIT_SCALE := 1.35
const BUILDING_SCALE := 4.2


func setup(p_selection: Control, p_units: Dictionary, p_buildings: Dictionary) -> void:
	selection = p_selection
	units = p_units
	buildings = p_buildings


func _ready() -> void:
	_mesh = TorusMesh.new()
	_mesh.inner_radius = 0.55
	_mesh.outer_radius = 0.72
	_mesh.rings = 16
	_mesh.ring_segments = 8
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.25, 1.0, 0.3)


func _process(_delta: float) -> void:
	if selection == null or not selection.has_method("get_selected"):
		return
	var want := {}
	var ids: Array = selection.get_selected()
	for uid in ids:
		want[int(uid)] = true
	for uid in _rings.keys():
		if not want.has(int(uid)):
			(_rings[uid] as MeshInstance3D).visible = false
	for uid in ids:
		_show_ring(int(uid))


func _show_ring(uid: int) -> void:
	var node3d: Node3D = null
	var big := false
	if units.has(uid):
		if bool((units[uid] as Dictionary).get("dead", false)):
			return
		node3d = (units[uid] as Dictionary)["node"] as Node3D
	elif buildings.has(uid):
		if bool((buildings[uid] as Dictionary).get("dead", false)):
			return
		node3d = (buildings[uid] as Dictionary)["node"] as Node3D
		big = true
	else:
		return
	if node3d == null or not is_instance_valid(node3d) or not node3d.visible:
		return
	var ring: MeshInstance3D = _rings.get(uid)
	if ring == null or not is_instance_valid(ring):
		ring = MeshInstance3D.new()
		ring.mesh = _mesh
		ring.material_override = _mat
		add_child(ring)
		_rings[uid] = ring
	ring.visible = true
	ring.global_position = node3d.global_position + Vector3(0, 0.25, 0)
	var s := BUILDING_SCALE if big else UNIT_SCALE
	ring.scale = Vector3(s, 1.0, s)

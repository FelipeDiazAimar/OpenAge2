extends Camera3D
# Cámara fija estilo AoE2: ortográfica, sin rotación libre. Solo pan + zoom.
# Ángulo AoE2: elevación ~32º, yaw 45º.

func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = 22.0
	rotation_degrees = Vector3(-32, -45, 0)
	position = Vector3(20, 20, 20)
	current = true

var pan_speed := 18.0
var zoom_min := 10.0
var zoom_max := 40.0
var _dragging := false

func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	# Edge-pan
	var vp := get_viewport().get_visible_rect().size
	var mp := get_viewport().get_mouse_position()
	if mp.x <= 4: dir.x -= 1
	if mp.x >= vp.x - 4: dir.x += 1
	if mp.y <= 4: dir.y -= 1
	if mp.y >= vp.y - 4: dir.y += 1
	if dir != Vector2.ZERO:
		# Mover en plano XZ relativo a yaw 45º
		var fwd := -global_transform.basis.z
		fwd.y = 0; fwd = fwd.normalized()
		var right := global_transform.basis.x
		right.y = 0; right = right.normalized()
		position += (right * dir.x + fwd * -dir.y) * pan_speed * delta * (size / 22.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			size = clampf(size - 2.0, zoom_min, zoom_max)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			size = clampf(size + 2.0, zoom_min, zoom_max)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var right := global_transform.basis.x; right.y = 0; right = right.normalized()
		var fwd := -global_transform.basis.z; fwd.y = 0; fwd = fwd.normalized()
		position -= (right * -mm.relative.x + fwd * mm.relative.y) * 0.02 * (size / 22.0)
	elif event.is_action_pressed("go_tc"):
		center_on_tc()

func center_on_tc() -> void:
	# TODO: buscar TC del jugador local y centrar
	pass

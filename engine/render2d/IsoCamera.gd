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


## Zoom inmediato (sin suavizado), dentro de los límites.
func set_zoom_now(z: float) -> void:
	_target_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2.ONE * _target_zoom


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
		dir += edge_dir(get_viewport().get_mouse_position(), get_viewport_rect().size)
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * delta / zoom.x
	zoom = zoom.lerp(Vector2.ONE * _target_zoom, clampf(delta * 10.0, 0.0, 1.0))
	if bounds.has_area():
		position = position.clamp(bounds.position, bounds.end)


## Dirección de scroll por borde; cero si el cursor está fuera de la ventana.
static func edge_dir(mp: Vector2, vs: Vector2) -> Vector2:
	if not Rect2(Vector2.ZERO, vs).has_point(mp):
		return Vector2.ZERO
	var d := Vector2.ZERO
	if mp.x < EDGE:
		d.x = -1
	elif mp.x > vs.x - EDGE:
		d.x = 1
	if mp.y < EDGE:
		d.y = -1
	elif mp.y > vs.y - EDGE:
		d.y = 1
	return d


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

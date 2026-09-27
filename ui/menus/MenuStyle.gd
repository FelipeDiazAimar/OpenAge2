class_name MenuStyle
extends RefCounted
# Helpers medievales 100% procedurales para el menú principal.
# Sin assets de pago: todo con StyleBoxFlat, ColorRect y Labels.
# Paleta compartida para madera, piedra, oro, carmesí y hierro.

const ORO := Color(1.0, 0.84, 0.42)
const MADERA := Color(0.28, 0.19, 0.11)
const PIEDRA := Color(0.55, 0.52, 0.47)
const CARMESI := Color(0.55, 0.10, 0.13)
const HIERRO := Color(0.25, 0.26, 0.29)


static func panel_madera() -> StyleBoxFlat:
	# Marco de madera para el panel central del menú.
	var marco := StyleBoxFlat.new()
	marco.bg_color = Color(0.13, 0.09, 0.06, 0.95)
	marco.border_width_left = 3
	marco.border_width_top = 3
	marco.border_width_right = 3
	marco.border_width_bottom = 3
	marco.border_color = Color(0.72, 0.58, 0.30)
	marco.corner_radius_top_left = 10
	marco.corner_radius_top_right = 10
	marco.corner_radius_bottom_right = 10
	marco.corner_radius_bottom_left = 10
	marco.shadow_color = Color(0, 0, 0, 0.6)
	marco.shadow_size = 18
	return marco


static func marco_piedra() -> StyleBoxFlat:
	# Borde de piedra clara para recuadros secundarios.
	var marco := StyleBoxFlat.new()
	marco.bg_color = Color(0.16, 0.15, 0.13, 0.95)
	marco.border_width_left = 2
	marco.border_width_top = 2
	marco.border_width_right = 2
	marco.border_width_bottom = 2
	marco.border_color = PIEDRA
	marco.corner_radius_top_left = 8
	marco.corner_radius_top_right = 8
	marco.corner_radius_bottom_right = 8
	marco.corner_radius_bottom_left = 8
	marco.shadow_color = Color(0, 0, 0, 0.55)
	marco.shadow_size = 12
	return marco


static func pergamino() -> StyleBoxFlat:
	# Fondo pergamino para subtítulos o carteles.
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = Color(0.85, 0.78, 0.62, 0.96)
	fondo.border_width_left = 2
	fondo.border_width_top = 2
	fondo.border_width_right = 2
	fondo.border_width_bottom = 2
	fondo.border_color = MADERA
	fondo.corner_radius_top_left = 6
	fondo.corner_radius_top_right = 6
	fondo.corner_radius_bottom_right = 6
	fondo.corner_radius_bottom_left = 6
	fondo.shadow_color = Color(0, 0, 0, 0.45)
	fondo.shadow_size = 8
	return fondo


static func aplicar_boton(btn: Button) -> void:
	# Viste un botón existente con borde hierro y hover dorado.
	btn.custom_minimum_size = Vector2(460, 54)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.70))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.88, 0.55))
	btn.add_theme_color_override("font_focus_color", Color(1.0, 0.95, 0.70))
	# Estado normal: madera oscura con borde hierro.
	var normal := StyleBoxFlat.new()
	normal.bg_color = MADERA
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = HIERRO
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_right = 6
	normal.corner_radius_bottom_left = 6
	normal.shadow_color = Color(0, 0, 0, 0.5)
	normal.shadow_size = 8
	btn.add_theme_stylebox_override("normal", normal)
	# Hover brillante: fondo cálido, borde oro y resplandor dorado.
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.52, 0.36, 0.18)
	hover.border_color = ORO
	hover.shadow_color = Color(1.0, 0.80, 0.35, 0.35)
	hover.shadow_size = 12
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", hover)
	# Pulsado: madera quemada más oscura.
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.18, 0.12, 0.07)
	pressed.border_color = Color(0.85, 0.68, 0.35)
	btn.add_theme_stylebox_override("pressed", pressed)
	# Deshabilitado: gris piedra apagado.
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.16, 0.15, 0.13)
	disabled.border_color = Color(0.35, 0.33, 0.30)
	btn.add_theme_stylebox_override("disabled", disabled)


static func boton_medieval(texto: String) -> Button:
	# Crea un botón nuevo ya estilizado con hover dorado.
	var btn := Button.new()
	btn.text = texto
	aplicar_boton(btn)
	return btn


static func aplicar_titulo(titulo: Label, tamano: int = 68) -> void:
	# Título dorado centrado con sombra de antorcha.
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", tamano)
	titulo.add_theme_color_override("font_color", ORO)
	titulo.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.05))
	titulo.add_theme_constant_override("outline_size", 8)
	titulo.add_theme_color_override("font_shadow_color", Color(1.0, 0.55, 0.20, 0.55))
	titulo.add_theme_constant_override("shadow_offset_x", 3)
	titulo.add_theme_constant_override("shadow_offset_y", 3)


static func titulo_medieval(texto: String, tamano: int = 68) -> Label:
	# Crea un título nuevo con estilo dorado y sombra de antorcha.
	var titulo := Label.new()
	titulo.text = texto
	aplicar_titulo(titulo, tamano)
	return titulo


static func banner_carmesi(color_civ: Color = CARMESI, ancho: float = 72.0) -> ColorRect:
	# Estandarte lateral carmesí teñido con el color de la civ.
	var paño := ColorRect.new()
	paño.name = "BannerCarmesi"
	paño.color = color_civ
	paño.custom_minimum_size = Vector2(ancho, 0)
	paño.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return paño

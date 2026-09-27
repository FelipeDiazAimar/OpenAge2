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

# Caché de texturas de madera por variante (se generan una vez).
static var _madera_cache := {}


static func madera_textura(variante: String = "normal") -> Texture2D:
	# Tablón de madera procedural 128x64: vetas, nudos, marco de hierro y
	# remaches en las esquinas. Sin assets externos.
	if _madera_cache.has(variante):
		return _madera_cache[variante]
	var base := Color(0.30, 0.20, 0.12)
	var hierro := Color(0.22, 0.23, 0.26)
	var borde := HIERRO
	if variante == "hover":
		base = Color(0.45, 0.31, 0.16)
		borde = ORO
	elif variante == "pressed":
		base = Color(0.19, 0.12, 0.07)
		borde = Color(0.85, 0.68, 0.35)
	elif variante == "disabled":
		base = Color(0.16, 0.15, 0.13)
		borde = Color(0.35, 0.33, 0.30)
	var img := Image.create(128, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 128:
			var v := base
			# Veta horizontal ondulada + tablones cada 16 px.
			var veta: float = 0.86 + 0.14 * sin(float(x) * 0.25 + float(y) * 0.9 + float(y / 16) * 2.1)
			v = Color(v.r * veta, v.g * veta, v.b * veta)
			if y % 16 == 0:
				v = v.darkened(0.45) # junta entre tablones
			# Nudos: dos elipses oscuras fijas.
			var n1: float = Vector2(float(x) - 34.0, (float(y) - 20.0) * 1.6).length()
			var n2: float = Vector2(float(x) - 96.0, (float(y) - 44.0) * 1.6).length()
			if n1 < 5.0 or n2 < 4.0:
				v = v.darkened(0.5)
			# Marco de hierro de 6 px con remaches en las esquinas.
			if x < 6 or y < 6 or x >= 122 or y >= 58:
				v = hierro * (0.85 + 0.3 * veta)
			var ex := mini(x, 127 - x)
			var ey := mini(y, 63 - y)
			if ex < 6 and ey < 6:
				var dc: float = Vector2(float(ex) - 3.0, float(ey) - 3.0).length()
				if dc < 2.6:
					v = Color(0.55, 0.57, 0.62) if dc < 1.4 else hierro
			img.set_pixel(x, y, v)
	var tex := ImageTexture.create_from_image(img)
	_madera_cache[variante] = tex
	return tex


static func _caja_madera(variante: String) -> StyleBoxTexture:
	# Caja 9-patch sobre la textura: se estira sin deformar marco ni remaches.
	var caja := StyleBoxTexture.new()
	caja.texture = madera_textura(variante)
	caja.texture_margin_left = 14.0
	caja.texture_margin_top = 14.0
	caja.texture_margin_right = 14.0
	caja.texture_margin_bottom = 14.0
	caja.content_margin_left = 18.0
	caja.content_margin_top = 10.0
	caja.content_margin_right = 18.0
	caja.content_margin_bottom = 10.0
	return caja


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
	# Estado normal: tablón de madera con marco de hierro y remaches.
	btn.add_theme_stylebox_override("normal", _caja_madera("normal"))
	# Hover brillante: madera cálida con marco de oro.
	btn.add_theme_stylebox_override("hover", _caja_madera("hover"))
	btn.add_theme_stylebox_override("focus", _caja_madera("hover"))
	# Pulsado: madera quemada más oscura.
	btn.add_theme_stylebox_override("pressed", _caja_madera("pressed"))
	# Deshabilitado: gris piedra apagado.
	btn.add_theme_stylebox_override("disabled", _caja_madera("disabled"))


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

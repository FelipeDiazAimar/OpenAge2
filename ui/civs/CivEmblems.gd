class_name CivEmblems
extends RefCounted
# Escudos heráldicos 100 % procedurales para las 6 facciones.
# Escudo calentador + símbolo distinto por civ, dibujado por píxel en Image.
# Sin assets externos; el fondo usa el roof_color de data/factions/*.json.
# Paleta de borde y tintas coordinada con ui/menus/MenuStyle.gd.

const ORO := Color(1.0, 0.84, 0.42)
const HUESO := Color(0.93, 0.89, 0.78)
const PLATA := Color(0.78, 0.80, 0.84)
const SOMBRA := Color(0.12, 0.08, 0.05)

# Caché por civ + tamaño para no regenerar la Image en cada llamada.
static var _cache := {}


static func color_de(civ: String) -> Color:
	# Color de fondo del escudo, igual que el roof_color de cada facción.
	match civ.to_lower().strip_edges():
		"britones":
			return Color("#5a6a7a")
		"francos":
			return Color("#2a4bff")
		"godos":
			return Color("#8a2a2a")
		"bizantinos":
			return Color("#c8a02a")
		"vikingos":
			return Color("#0e6e5a")
		_:
			return Color(0.45, 0.44, 0.42)


static func emblem(civ: String, size: int) -> Texture2D:
	# Devuelve el escudo de la civ al tamaño pedido; lo cachea por civ + size.
	var clave_civ := civ.to_lower().strip_edges()
	var lado := clampi(size, 16, 256)
	var clave := clave_civ + "_" + str(lado)
	if _cache.has(clave):
		return _cache[clave]
	var fondo := color_de(clave_civ)
	var tinta := _tinta_de(clave_civ)
	var img := Image.create(lado, lado, false, Image.FORMAT_RGBA8)
	for y in lado:
		for x in lado:
			var nx := (float(x) + 0.5) / float(lado)
			var ny := (float(y) + 0.5) / float(lado)
			if not _en_escudo(nx, ny):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Sombreado vertical con luz arriba y brillo lateral izquierdo.
			var v := fondo.lightened(0.18 * (1.0 - ny))
			v = v.darkened(0.30 * ny)
			if nx < 0.32:
				v = v.lightened(0.10 * (1.0 - nx / 0.32))
			if _es_borde(nx, ny):
				img.set_pixel(x, y, ORO)
				continue
			if _es_hueco(clave_civ, nx, ny):
				img.set_pixel(x, y, SOMBRA)
				continue
			if _es_simbolo(clave_civ, nx, ny):
				img.set_pixel(x, y, tinta)
				continue
			img.set_pixel(x, y, v)
	var tex := ImageTexture.create_from_image(img)
	_cache[clave] = tex
	return tex


static func limpiar_cache() -> void:
	# Libera los escudos generados; se regeneran bajo demanda.
	_cache.clear()


static func _tinta_de(clave_civ: String) -> Color:
	# Tinta del símbolo con contraste sobre el fondo de cada civ.
	match clave_civ:
		"britones":
			return ORO
		"francos":
			return HUESO
		"godos":
			return PLATA
		"bizantinos":
			return Color(0.29, 0.06, 0.08)
		"vikingos":
			return HUESO
		_:
			return Color(0.15, 0.15, 0.16)


static func _en_escudo(nx: float, ny: float) -> bool:
	# Silueta calentadora: rectángulo arriba y punta abajo centrada.
	if nx < 0.06 or nx > 0.94 or ny < 0.06 or ny > 0.96:
		return false
	if ny <= 0.62:
		return absf(nx - 0.5) <= 0.44
	var t := (ny - 0.62) / 0.34
	return absf(nx - 0.5) <= 0.44 * (1.0 - t)


static func _es_borde(nx: float, ny: float) -> bool:
	# Marco dorado: dentro del escudo pero fuera de su versión interior.
	if not _en_escudo(nx, ny):
		return false
	if nx < 0.10 or nx > 0.90 or ny < 0.10:
		return true
	if ny <= 0.60:
		return absf(nx - 0.5) > 0.40
	var t := (ny - 0.60) / 0.32
	return absf(nx - 0.5) > 0.40 * (1.0 - t)


static func _es_simbolo(clave_civ: String, nx: float, ny: float) -> bool:
	# Reparte un símbolo distinto por civ: león, lis, hacha, cruz, cuervo, torre.
	match clave_civ:
		"britones":
			return _leon(nx, ny)
		"francos":
			return _lis(nx, ny)
		"godos":
			return _hacha_corona(nx, ny)
		"bizantinos":
			return _cruz(nx, ny)
		"vikingos":
			return _cuervo(nx, ny)
		_:
			return _torre(nx, ny)


static func _es_hueco(clave_civ: String, nx: float, ny: float) -> bool:
	# Puerta y ventana recortadas en oscuro sobre la torre neutral.
	if clave_civ == "neutral" or clave_civ == "neutrales":
		if _en_rect(nx, ny, 0.45, 0.55, 0.55, 0.70):
			return true
		if _en_disco(nx, ny, 0.5, 0.55, 0.05):
			return true
		if _en_disco(nx, ny, 0.5, 0.45, 0.035):
			return true
	return false


static func _leon(nx: float, ny: float) -> bool:
	# León rampante de los britones, simplificado en discos y rectas.
	if _en_disco(nx, ny, 0.5, 0.32, 0.09):
		return true
	if _en_rect(nx, ny, 0.44, 0.38, 0.56, 0.68):
		return true
	if _en_rect(nx, ny, 0.36, 0.42, 0.44, 0.55):
		return true
	if _en_rect(nx, ny, 0.56, 0.42, 0.64, 0.55):
		return true
	if _en_rect(nx, ny, 0.36, 0.55, 0.44, 0.72):
		return true
	if _en_rect(nx, ny, 0.56, 0.55, 0.64, 0.72):
		return true
	if _en_disco(nx, ny, 0.62, 0.60, 0.03):
		return true
	if _en_disco(nx, ny, 0.65, 0.52, 0.03):
		return true
	if _en_disco(nx, ny, 0.63, 0.44, 0.03):
		return true
	return false


static func _lis(nx: float, ny: float) -> bool:
	# Flor de lis de los francos: pétalo central, laterales, banda y base.
	if _en_tri(nx, ny, 0.5, 0.22, 0.44, 0.48, 0.56, 0.48):
		return true
	if _en_rect(nx, ny, 0.47, 0.30, 0.53, 0.60):
		return true
	if _en_disco(nx, ny, 0.38, 0.48, 0.07):
		return true
	if _en_disco(nx, ny, 0.62, 0.48, 0.07):
		return true
	if _en_tri(nx, ny, 0.38, 0.36, 0.33, 0.50, 0.43, 0.50):
		return true
	if _en_tri(nx, ny, 0.62, 0.36, 0.57, 0.50, 0.67, 0.50):
		return true
	if _en_rect(nx, ny, 0.36, 0.58, 0.64, 0.63):
		return true
	if _en_tri(nx, ny, 0.44, 0.63, 0.56, 0.63, 0.5, 0.74):
		return true
	return false


static func _hacha_corona(nx: float, ny: float) -> bool:
	# Hacha doble sobre corona de los godos.
	if _en_rect(nx, ny, 0.485, 0.24, 0.515, 0.62):
		return true
	if _en_tri(nx, ny, 0.485, 0.28, 0.30, 0.36, 0.485, 0.46):
		return true
	if _en_tri(nx, ny, 0.515, 0.28, 0.70, 0.36, 0.515, 0.46):
		return true
	if _en_rect(nx, ny, 0.34, 0.60, 0.66, 0.70):
		return true
	if _en_tri(nx, ny, 0.34, 0.60, 0.39, 0.60, 0.365, 0.52):
		return true
	if _en_tri(nx, ny, 0.475, 0.60, 0.525, 0.60, 0.5, 0.52):
		return true
	if _en_tri(nx, ny, 0.61, 0.60, 0.66, 0.60, 0.635, 0.52):
		return true
	return false


static func _cruz(nx: float, ny: float) -> bool:
	# Cruz griega con bezantes de los bizantinos.
	if _en_rect(nx, ny, 0.45, 0.28, 0.55, 0.72):
		return true
	if _en_rect(nx, ny, 0.30, 0.43, 0.70, 0.53):
		return true
	if _en_disco(nx, ny, 0.5, 0.48, 0.08):
		return true
	if _en_disco(nx, ny, 0.36, 0.32, 0.04):
		return true
	if _en_disco(nx, ny, 0.64, 0.32, 0.04):
		return true
	if _en_disco(nx, ny, 0.36, 0.62, 0.04):
		return true
	if _en_disco(nx, ny, 0.64, 0.62, 0.04):
		return true
	return false


static func _cuervo(nx: float, ny: float) -> bool:
	# Cuervo en vuelo de los vikingos: alas, cuerpo, cabeza y cola.
	if _en_tri(nx, ny, 0.5, 0.45, 0.24, 0.34, 0.30, 0.52):
		return true
	if _en_tri(nx, ny, 0.5, 0.45, 0.76, 0.34, 0.70, 0.52):
		return true
	if _en_rect(nx, ny, 0.47, 0.38, 0.53, 0.62):
		return true
	if _en_disco(nx, ny, 0.5, 0.36, 0.06):
		return true
	if _en_tri(nx, ny, 0.46, 0.62, 0.54, 0.62, 0.5, 0.72):
		return true
	return false


static func _torre(nx: float, ny: float) -> bool:
	# Torre almenada de los neutrales.
	if _en_rect(nx, ny, 0.38, 0.35, 0.62, 0.70):
		return true
	if _en_rect(nx, ny, 0.38, 0.28, 0.44, 0.35):
		return true
	if _en_rect(nx, ny, 0.47, 0.28, 0.53, 0.35):
		return true
	if _en_rect(nx, ny, 0.56, 0.28, 0.62, 0.35):
		return true
	return false


static func _en_rect(nx: float, ny: float, x0: float, y0: float, x1: float, y1: float) -> bool:
	return nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1


static func _en_disco(nx: float, ny: float, cx: float, cy: float, r: float) -> bool:
	var dx := nx - cx
	var dy := ny - cy
	return dx * dx + dy * dy <= r * r


static func _signo(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	return (px - bx) * (ay - by) - (ax - bx) * (py - by)


static func _en_tri(nx: float, ny: float, ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> bool:
	# Punto dentro del triángulo por el signo de las tres aristas.
	var d1 := _signo(nx, ny, ax, ay, bx, by)
	var d2 := _signo(nx, ny, bx, by, cx, cy)
	var d3 := _signo(nx, ny, cx, cy, ax, ay)
	var tiene_neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var tiene_pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (tiene_neg and tiene_pos)

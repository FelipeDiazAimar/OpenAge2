class_name CardArt
extends RefCounted
# Arte 100% procedural para cartas de mazos, sin assets externos.
# Cohherente con ui/menus/MenuStyle.gd: madera, hierro y ribete dorado.
# Todo con StyleBoxFlat, Color y simbolos unicode.

const ORO := Color(1.0, 0.84, 0.42)
const MADERA := Color(0.28, 0.19, 0.11)
const HIERRO := Color(0.25, 0.26, 0.29)
const BRONCE := Color(0.71, 0.45, 0.22)
const PLATA := Color(0.78, 0.80, 0.84)


static func card_frame(edad: int) -> StyleBoxFlat:
	# Marco de madera con ribete segun edad: I hierro, II bronce, III plata, IV oro.
	var ribete := HIERRO
	match edad:
		1:
			ribete = HIERRO
		2:
			ribete = BRONCE
		3:
			ribete = PLATA
		4:
			ribete = ORO
		_:
			ribete = HIERRO
	var marco := StyleBoxFlat.new()
	marco.bg_color = Color(0.13, 0.09, 0.06, 0.95)
	marco.border_width_left = 3
	marco.border_width_top = 3
	marco.border_width_right = 3
	marco.border_width_bottom = 3
	marco.border_color = ribete
	marco.corner_radius_top_left = 10
	marco.corner_radius_top_right = 10
	marco.corner_radius_bottom_right = 10
	marco.corner_radius_bottom_left = 10
	marco.shadow_color = Color(0, 0, 0, 0.6)
	marco.shadow_size = 12
	return marco


static func icon_for(nombre: String) -> String:
	# Devuelve emoji o simbolo unicode segun el id del icono.
	var clave := nombre.strip_edges().to_lower()
	match clave:
		"arco", "arquero":
			return "🏹"
		"caballo", "caballeria", "jinete":
			return "🐎"
		"espada", "infanteria", "milicia":
			return "⚔"
		"escudo", "defensa", "muralla":
			return "🛡"
		"hacha", "leñador":
			return "🪓"
		"madera", "wood":
			return "🪵"
		"oro", "gold", "moneda":
			return "🪙"
		"comida", "food", "granja", "baya":
			return "🍖"
		"piedra", "stone":
			return "🪨"
		"aldeano", "villager":
			return "🧑‍🌾"
		"lanza", "piquero":
			return "🔱"
		"torre", "castillo":
			return "🏰"
		"barco", "pesca":
			return "⛵"
		"asedio", "catapulta", "ariete":
			return "💣"
		"monje", "cura":
			return "✝"
		"corona", "rey", "heroe":
			return "👑"
		"fuego", "antorcha":
			return "🔥"
		"alabarda", "daga", "pica":
			return "🗡"
		"alimento", "trigo":
			return "🌾"
		"ancla", "muelle":
			return "⚓"
		"arco_largo", "arquero_tiro_largo", "arqueria", "guerrillero":
			return "🏹"
		"armadura", "buff_defensa", "defensa_buff":
			return "🛡"
		"balistica", "diana":
			return "🎯"
		"bota", "botas", "buff_velocidad", "velocidad_buff":
			return "🥾"
		"camello":
			return "🐪"
		"campeon":
			return "🏆"
		"carne":
			return "🍖"
		"carreta", "carretilla":
			return "🛞"
		"catafracta", "paladin_franco", "establo":
			return "🐎"
		"cesta":
			return "🧺"
		"comercio":
			return "💰"
		"cruz":
			return "✝"
		"cuartel", "herreria":
			return "⚒"
		"dragon":
			return "🐉"
		"drakkar", "vela":
			return "⛵"
		"espadachin_mandoble":
			return "⚔"
		"estandarte":
			return "🚩"
		"flecha":
			return "➶"
		"herradura":
			return "🐴"
		"huscarle", "invasor_nordico":
			return "🪓"
		"jabali":
			return "🐗"
		"maravilla":
			return "🌟"
		"molino":
			return "⚙"
		"ojo":
			return "👁"
		"oveja":
			return "🐑"
		"quimica":
			return "⚗"
		"red":
			return "🕸"
		"reloj":
			return "⏳"
		"telar":
			return "🧵"
		"trabuquete", "trebuchet":
			return "💣"
		"tridente":
			return "🔱"
		"yelmo":
			return "🪖"
		"envio_madera", "enviar_madera", "send_wood":
			return "🪵"
		"envio_alimento", "envio_comida", "enviar_alimento", "send_food":
			return "🌾"
		"envio_oro", "enviar_oro", "send_gold":
			return "🪙"
		"envio_piedra", "enviar_piedra", "send_stone":
			return "🪨"
		"jugar_carta", "jugar", "play_card":
			return "🃏"
		"bloqueada_edad", "req_edad", "edad_bloqueada":
			return "🔒"
		"bloqueada_oro", "req_oro", "sin_oro":
			return "💰"
		"buff_ataque", "ataque_buff":
			return "💪"
		_:
			return "◆"


static func rarity_color(r) -> Color:
	# Color por rareza: comun gris, rara azul, epica morada.
	var clave := str(r).strip_edges().to_lower()
	match clave:
		"comun", "común", "common", "0":
			return Color(0.70, 0.70, 0.72)
		"rara", "rare", "1":
			return Color(0.30, 0.55, 1.0)
		"epica", "épica", "epic", "2":
			return Color(0.70, 0.35, 1.0)
		_:
			return Color(0.70, 0.70, 0.72)


static func cost_text(cost: Dictionary) -> String:
	# Texto corto de coste tipo "200O 100M" (oro, madera, comida, piedra).
	var oro := _recurso(cost, ["oro", "gold", "o"])
	var madera := _recurso(cost, ["madera", "wood", "m"])
	var comida := _recurso(cost, ["comida", "food", "alimento", "c"])
	var piedra := _recurso(cost, ["piedra", "stone", "p", "s"])
	var partes: Array[String] = []
	if oro > 0:
		partes.append("%dO" % oro)
	if madera > 0:
		partes.append("%dM" % madera)
	if comida > 0:
		partes.append("%dC" % comida)
	if piedra > 0:
		partes.append("%dP" % piedra)
	if partes.is_empty():
		return "Gratis"
	return " ".join(partes)


static func _recurso(cost: Dictionary, claves: Array) -> int:
	# Busca el primer valor > 0 entre las claves aceptadas.
	for clave in claves:
		if cost.has(clave):
			return int(cost[clave])
	return 0

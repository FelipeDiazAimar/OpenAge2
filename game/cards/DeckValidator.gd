extends RefCounted
## Validador de mazos de cartas (20 cartas) para OpenAge-LAN.
## Referencia de ops (diseno 4.3): set/add/mul/append/remove/replace_entity/enable/disable.
## Formato carta: {id, name, civ, age 1-4, type, cost, effect{target,op,path,value}, icon, rarity, desc}.
## Sin class_name: usar con preload relativo desde el llamante.
## Ej: const DeckValidator := preload("../cards/DeckValidator.gd")

# Tipos de carta permitidos.
const TIPOS_VALIDOS: Array[String] = ["unidad", "mejora", "recurso", "edificio"]
# Ops validas segun spec 4.3 (incluye replace_entity).
const OPS_VALIDAS: Array[String] = ["set", "add", "mul", "append", "remove", "replace_entity", "enable", "disable"]
# Recursos validos para el coste.
const RECURSOS_VALIDOS: Array[String] = ["madera", "alimento", "oro", "piedra"]
# Tamano exacto del mazo.
const TAMANO_MAZO: int = 20
# Carpeta con los JSON de cartas del mod base.
const CARDS_DIR: String = "res://mods/aoe2_base/cards"


## Valida un mazo y devuelve la lista de errores (vacia si es valido).
static func validate_deck(cartas: Array, civ: String) -> Array[String]:
	var errores: Array[String] = []
	# Regla: el mazo debe tener exactamente 20 cartas.
	if cartas.size() != TAMANO_MAZO:
		errores.append("Mazo debe tener exactamente %d cartas (tiene %d)." % [TAMANO_MAZO, cartas.size()])
	var vistos := {}
	# Revisa cada carta una por una.
	for i in cartas.size():
		var carta: Variant = cartas[i]
		if not (carta is Dictionary):
			errores.append("Carta %d: no es un Diccionario." % i)
			continue
		var d: Dictionary = carta
		var etiqueta: String = str(d.get("id", "#%d" % i))
		# Campos obligatorios presentes y no vacios.
		for campo in ["id", "name", "icon", "desc"]:
			if not d.has(campo) or str(d[campo]).strip_edges().is_empty():
				errores.append("Carta %s: falta campo obligatorio '%s'." % [etiqueta, campo])
		# Ids unicos en todo el mazo.
		var id_str: String = str(d.get("id", ""))
		if not id_str.is_empty():
			if vistos.has(id_str):
				errores.append("Carta %s: id duplicado." % id_str)
			else:
				vistos[id_str] = true
		# La civ debe coincidir con la del mazo o ser "todas".
		var cciv: String = str(d.get("civ", ""))
		if cciv != civ and cciv != "todas":
			errores.append("Carta %s: civ '%s' no valida para mazo '%s'." % [etiqueta, cciv, civ])
		# Edad entre 1 y 4.
		var age: Variant = d.get("age", 0)
		if not ((age is int or age is float) and float(age) == float(int(age)) and int(age) >= 1 and int(age) <= 4):
			errores.append("Carta %s: age debe ser entero 1-4." % etiqueta)
		# Tipo de carta valido.
		if not TIPOS_VALIDOS.has(str(d.get("type", ""))):
			errores.append("Carta %s: type '%s' no valido." % [etiqueta, str(d.get("type", ""))])
		# Op del efecto valida.
		var effect: Variant = d.get("effect", null)
		if not (effect is Dictionary) or not (effect as Dictionary).has("op"):
			errores.append("Carta %s: falta effect.op." % etiqueta)
		elif not OPS_VALIDAS.has(str((effect as Dictionary)["op"])):
			errores.append("Carta %s: effect.op '%s' no valido." % [etiqueta, str((effect as Dictionary)["op"])])
		# Paths res.* son envios directos al jugador (validos).
		if effect is Dictionary and (effect as Dictionary).has("path"):
			var _epath: String = str((effect as Dictionary)["path"])
			if _epath.begins_with("res."):
				pass
		# Coste: solo recursos conocidos, numericos y >= 0.
		if d.has("cost"):
			var cost: Variant = d["cost"]
			if not (cost is Dictionary):
				errores.append("Carta %s: cost debe ser Diccionario." % etiqueta)
			else:
				for clave in (cost as Dictionary).keys():
					var k: String = str(clave)
					if not RECURSOS_VALIDOS.has(k):
						errores.append("Carta %s: recurso '%s' no valido en cost." % [etiqueta, k])
						continue
					var v: Variant = (cost as Dictionary)[clave]
					if not (v is int or v is float) or float(v) < 0.0:
						errores.append("Carta %s: cost.%s debe ser numerico >= 0." % [etiqueta, k])
	return errores


## Lee todos los *.json de la carpeta de cartas, ordenados por nombre.
## Cada archivo puede contener un Diccionario o un Array de cartas.
static func load_all_cards() -> Array:
	var resultado: Array = []
	var dir := DirAccess.open(CARDS_DIR)
	# Si no hay carpeta, devuelve lista vacia sin romper.
	if dir == null:
		return resultado
	var archivos: Array[String] = []
	# Recoge solo ficheros .json.
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			archivos.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	archivos.sort()
	# Carga cada fichero en orden.
	for nombre in archivos:
		var ruta: String = CARDS_DIR + "/" + nombre
		var texto: String = FileAccess.get_file_as_string(ruta)
		if texto.strip_edges().is_empty():
			continue
		var parsed: Variant = JSON.parse_string(texto)
		if parsed is Array:
			for c in (parsed as Array):
				resultado.append(c)
		elif parsed is Dictionary:
			resultado.append(parsed)
	return resultado


## Filtra las cartas jugables por una civ (las propias mas las de "todas").
static func cards_for_civ(cartas: Array, civ: String) -> Array:
	var salida: Array = []
	for c in cartas:
		if not (c is Dictionary):
			continue
		var cciv: String = str((c as Dictionary).get("civ", ""))
		if cciv == civ or cciv == "todas":
			salida.append(c)
	return salida


# Prefijo de envios directos de recursos al jugador.
const RES_PATH_PREFIX: String = "res."

## Paths que empiecen por "res." son validos (envios al jugador).
static func is_effect_path_valido(path: String) -> bool:
	if path.begins_with(RES_PATH_PREFIX):
		return true
	if path.begins_with("abilities.") or path.begins_with("cost.") or path == "enabled" or path.is_empty():
		return true
	return false

extends RefCounted
## Deck: mazo de cartas para OpenAge-LAN (Godot 4.4).
## Guarda civ y lista de ids (máx. 20). Delega la validación
## profunda en DeckValidator.validate_deck(cartas, civ).
## Sin class_name: usar con load("res://game/cards/Deck.gd").

# Número máximo de cartas del mazo (estilo Age 3; puede ir con menos).
const MAX_CARDS: int = 25
# Carpeta de guardado en user://.
const DECKS_DIR: String = "user://decks"
# Validador externo (estático).
const DeckValidator := preload("res://game/cards/DeckValidator.gd")

# Civilización del mazo.
var civ: String = ""
# Ids de cartas en el mazo.
var card_ids: Array[String] = []


## Añade una carta por id. Devuelve "" si ok o el motivo del fallo.
func add_card(id: String) -> String:
	var nid: String = id.strip_edges()
	# Rechaza ids vacíos.
	if nid.is_empty():
		return "id vacía"
	# Respeta el máximo de 20.
	if card_ids.size() >= MAX_CARDS:
		return "mazo lleno (máx %d)" % MAX_CARDS
	# Evita duplicados (el validador exige ids únicos).
	if card_ids.has(nid):
		return "carta duplicada: %s" % nid
	card_ids.append(nid)
	return ""


## Quita una carta por id. Devuelve true si la ha quitado.
func remove_card(id: String) -> bool:
	# Busca exacta y luego sin espacios por robustez.
	if card_ids.has(id):
		card_ids.erase(id)
		return true
	var nid: String = id.strip_edges()
	if card_ids.has(nid):
		card_ids.erase(nid)
		return true
	return false


## Número actual de cartas.
func count() -> int:
	return card_ids.size()


## True cuando el mazo tiene al menos 1 carta (listo para guardar/jugar).
func is_complete() -> bool:
	return card_ids.size() >= 1 and card_ids.size() <= MAX_CARDS


## Valida el mazo con DeckValidator. Acepta Array (de load_all_cards)
## o Dictionary {id: ficha}. Devuelve lista de errores (vacía si ok).
func validate(all_cards) -> Array[String]:
	var errores: Array[String] = []
	# Índice id -> ficha completa.
	var por_id := {}
	if all_cards is Dictionary:
		por_id = all_cards
	elif all_cards is Array:
		for c in (all_cards as Array):
			if c is Dictionary and (c as Dictionary).has("id"):
				por_id[str((c as Dictionary)["id"])] = c
	# Construye las fichas para el validador.
	var cartas: Array = []
	for cid in card_ids:
		if por_id.has(cid):
			cartas.append(por_id[cid])
		else:
			# Avisa y mete ficha mínima para que el validador la marque.
			errores.append("Carta desconocida: %s." % cid)
			cartas.append({"id": cid})
	# Delega la regla profunda (tamaño, campos, civ, edad, tipo, efecto, coste).
	errores.append_array(DeckValidator.validate_deck(cartas, civ))
	return errores


## Resuelve el nombre/ruta a user://decks/*.json.
static func _resolve_deck_path(path: String) -> String:
	var p: String = path.strip_edges().replace("\\", "/")
	# Ruta vacía no vale.
	if p.is_empty():
		return ""
	# Si no es user://, quédate con el nombre base en user://decks/.
	if not p.begins_with("user://"):
		p = DECKS_DIR + "/" + p.get_file()
	# Asegura extensión .json.
	if not p.to_lower().ends_with(".json"):
		p += ".json"
	return p


## Guarda el mazo como JSON {civ, card_ids} en user://decks/. True si ok.
func save(path: String) -> bool:
	var ruta: String = _resolve_deck_path(path)
	if ruta.is_empty():
		return false
	# Crea la carpeta si falta.
	DirAccess.make_dir_recursive_absolute(DECKS_DIR)
	var datos := {"civ": civ, "card_ids": Array(card_ids)}
	var f := FileAccess.open(ruta, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(datos))
	return true


## Carga el mazo desde user://decks/. True si ok (sustituye civ y card_ids).
func load_deck(path: String) -> bool:
	var ruta: String = _resolve_deck_path(path)
	if ruta.is_empty():
		return false
	if not FileAccess.file_exists(ruta):
		return false
	var f := FileAccess.open(ruta, FileAccess.READ)
	if f == null:
		return false
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		return false
	var datos: Variant = j.data
	if not (datos is Dictionary):
		return false
	var d: Dictionary = datos as Dictionary
	if not (d.get("civ") is String) or not (d.get("card_ids") is Array):
		return false
	# Asigna valores limpios y tipados.
	civ = str(d["civ"])
	var lista: Array[String] = []
	for v in (d["card_ids"] as Array):
		lista.append(str(v))
	card_ids = lista
	return true


## Nombres de mazos guardados en user://decks/ (sin extensión), ordenados.
static func list_decks() -> Array[String]:
	var salida: Array[String] = []
	# Crea la carpeta si falta para no fallar en limpio.
	DirAccess.make_dir_recursive_absolute(DECKS_DIR)
	var dir := DirAccess.open(DECKS_DIR)
	if dir == null:
		return salida
	# Recoge solo .json.
	for f in dir.get_files():
		if f.to_lower().ends_with(".json"):
			salida.append(f.get_basename())
	salida.sort()
	return salida

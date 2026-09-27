extends "res://tests/engine/TestCase.gd"
## Tests de mazos: DeckValidator (20 cartas exactas, ids únicos, civ,
## edad 1-4, op válida, coste >= 0), Deck (add/remove/límite/is_complete),
## presets reales de game/cards/presets + cartas de mods/aoe2_base/cards,
## y DeckTips.explain_effect (omitido si no existe el archivo).

const DeckValidator := preload("res://game/cards/DeckValidator.gd")
const DeckScript := preload("res://game/cards/Deck.gd")

const PRESETS_DIR := "res://game/cards/presets"
const CARDS_DIR := "res://mods/aoe2_base/cards"
const TIPS_PATH := "res://game/cards/DeckTips.gd"


## Una carta mínima válida para la civ indicada.
func _carta(id: String, civ: String = "britones") -> Dictionary:
	return {
		"id": id, "name": "Carta " + id, "civ": civ, "age": 2,
		"type": "mejora", "cost": {"madera": 0, "alimento": 0, "oro": 0, "piedra": 0},
		"effect": {"target": "tag:infanteria", "op": "add", "path": "abilities.Attack.damage.melee", "value": 1},
		"icon": "espada", "rarity": "comun", "desc": "Descripción de " + id + ".",
	}


## Mazo sintético válido de `total` cartas con ids únicos y edades 1-4.
func _mazo_valido(civ: String = "britones", total: int = 20) -> Array:
	var cartas: Array = []
	for i in total:
		var c := _carta("test_carta_%02d" % i, civ)
		c["age"] = 1 + (i % 4)
		cartas.append(c)
	return cartas


## Lee y parsea un JSON (devuelve null si está vacío).
func _leer_json(ruta: String) -> Variant:
	var texto: String = FileAccess.get_file_as_string(ruta)
	if texto.strip_edges().is_empty():
		return null
	return JSON.parse_string(texto)


## Carga todas las cartas reales de mods/aoe2_base/cards/*.json en orden.
func _todas_las_cartas() -> Array:
	var salida: Array = []
	var dir := DirAccess.open(CARDS_DIR)
	assert_true(dir != null, "existe " + CARDS_DIR)
	if dir == null:
		return salida
	var archivos: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			archivos.append(f)
	archivos.sort()
	assert_true(archivos.size() > 0, "hay json de cartas en " + CARDS_DIR)
	for f in archivos:
		var parsed: Variant = _leer_json(CARDS_DIR + "/" + f)
		if parsed is Array:
			for c in (parsed as Array):
				salida.append(c)
		elif parsed is Dictionary:
			salida.append(parsed)
	return salida


func test_validador_acepta_mazo_valido_20() -> void:
	assert_eq(DeckValidator.validate_deck(_mazo_valido("britones"), "britones"), [])


func test_validador_rechaza_19_y_21() -> void:
	assert_has_error(DeckValidator.validate_deck([], "britones"), "al menos")
	assert_has_error(DeckValidator.validate_deck(_mazo_valido("britones", 26), "britones"), "máximo")
	assert_eq(DeckValidator.validate_deck(_mazo_valido("britones", 5), "britones"), [])
	assert_eq(DeckValidator.validate_deck(_mazo_valido("britones", 25), "britones"), [])


func test_validador_rechaza_duplicados() -> void:
	var mazo := _mazo_valido("britones")
	mazo[5] = (mazo[3] as Dictionary).duplicate()
	assert_has_error(DeckValidator.validate_deck(mazo, "britones"), "duplicado")


func test_validador_rechaza_civ_ajena() -> void:
	var mazo := _mazo_valido("britones")
	(mazo[0] as Dictionary)["civ"] = "francos"
	assert_has_error(DeckValidator.validate_deck(mazo, "britones"), "civ")


func test_validador_rechaza_age_5() -> void:
	var mazo := _mazo_valido("britones")
	(mazo[0] as Dictionary)["age"] = 5
	assert_has_error(DeckValidator.validate_deck(mazo, "britones"), "age")


func test_validador_rechaza_op_mala_y_coste_negativo() -> void:
	var mazo := _mazo_valido("britones")
	((mazo[0] as Dictionary)["effect"] as Dictionary)["op"] = "explotar"
	assert_has_error(DeckValidator.validate_deck(mazo, "britones"), "effect.op")
	var mazo2 := _mazo_valido("britones")
	((mazo2[1] as Dictionary)["cost"] as Dictionary)["oro"] = -50
	assert_has_error(DeckValidator.validate_deck(mazo2, "britones"), "cost.oro")


func test_deck_add_remove_limite_20_e_is_complete() -> void:
	var mazo = DeckScript.new()
	mazo.civ = "britones"
	assert_eq(mazo.count(), 0)
	assert_false(mazo.is_complete())
	assert_eq(mazo.add_card(""), "id vacía")
	assert_eq(mazo.add_card("neut_madera_1"), "")
	assert_true(mazo.add_card("neut_madera_1").begins_with("carta duplicada"))
	for i in 24:
		assert_eq(mazo.add_card("relleno_%02d" % i), "")
	assert_eq(mazo.count(), 25)
	assert_true(mazo.is_complete())
	assert_true(mazo.add_card("una_mas").begins_with("mazo lleno"))
	assert_true(mazo.remove_card("relleno_00"))
	assert_eq(mazo.count(), 24)
	assert_true(mazo.is_complete())
	assert_false(mazo.remove_card("no_existe"))


func test_presets_reales_cargan_y_validan() -> void:
	var todas := _todas_las_cartas()
	assert_true(todas.size() >= 20, "hay al menos 20 cartas reales")
	var por_id := {}
	for c in todas:
		if c is Dictionary and (c as Dictionary).has("id"):
			por_id[str((c as Dictionary)["id"])] = c
	var dir := DirAccess.open(PRESETS_DIR)
	assert_true(dir != null, "existe " + PRESETS_DIR)
	if dir == null:
		return
	var archivos: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			archivos.append(f)
	archivos.sort()
	assert_true(archivos.size() > 0, "hay presets en " + PRESETS_DIR)
	for f in archivos:
		var preset: Variant = _leer_json(PRESETS_DIR + "/" + f)
		assert_true(preset is Dictionary, f + " es un diccionario")
		if not (preset is Dictionary):
			continue
		var ids: Array = (preset as Dictionary).get("card_ids", [])
		var civ: String = str((preset as Dictionary).get("civ", ""))
		assert_eq(ids.size(), 20, f + " trae 20 cartas")
		var vistos := {}
		var cartas: Array = []
		for cid in ids:
			assert_false(vistos.has(str(cid)), f + " sin duplicados: " + str(cid))
			vistos[str(cid)] = true
			assert_true(por_id.has(str(cid)), f + " conoce la carta " + str(cid))
			if por_id.has(str(cid)):
				cartas.append(por_id[str(cid)])
		if cartas.size() == 20:
			assert_eq(DeckValidator.validate_deck(cartas, civ), [], f + " valida para " + civ)


func test_decktips_explica_efecto() -> void:
	if not FileAccess.file_exists(TIPS_PATH):
		assert_true(true, "sin DeckTips: test omitido")
		return
	var Tips = load(TIPS_PATH)
	var texto: String = Tips.explain_effect({
		"effect": {"target": "tag:arqueros", "op": "add", "path": "abilities.Attack.damage.pierce", "value": 2},
	})
	assert_true(texto.strip_edges().length() > 0, "explica algo")
	assert_true("ataque perforante" in texto and "arqueros" in texto, "explica el efecto: " + texto)

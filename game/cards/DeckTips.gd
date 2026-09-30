extends RefCounted
## DeckTips: textos de ayuda en español para mazos (docs/MAZOS.md).
## Solo datos de ayuda, sin lógica de juego. Sin class_name:
## usar con load("res://game/cards/DeckTips.gd").
## Mazo = 20 cartas (5/6/5/4 en I/II/III/IV). Efectos = parches §4.3.


## Qué buscar en cada edad (1-4). Devuelve una línea de consejo.
static func tip_for(age: int) -> String:
	match age:
		1:
			return "Edad I: busca economía (aldeanos, madera y alimento). Tienes 5 huecos: no gastes envíos en ejército aún."
		2:
			return "Edad II: busca mejoras baratas que escalan (forja +1, armaduras, telar, carretilla). Tienes 6 huecos para vestir infantería y arqueros."
		3:
			return "Edad III: busca tu bonus de civ (alcance, unidad única, comercio, balística). Tienes 5 huecos para tomar Castillos."
		4:
			return "Edad IV: busca remates de élite (campeones, asedio, Maravilla). Solo 4 huecos: cada envío debe cerrar la partida."
	return "Edad desconocida: usa 1-4 (I-IV); revisa el reparto 5/6/5/4 de tu mazo."


## Traduce el effect/effects de una carta a frase legible.
## Ej: {"target":"tag:arqueros","op":"add","path":"abilities.Attack.damage.pierce","value":2}
## -> "+2 al ataque perforante de arqueros."
static func explain_effect(card: Dictionary) -> String:
	if card.has("effects"):
		var arr: Variant = card["effects"]
		if arr is Array:
			var lista: Array = arr as Array
			if lista.is_empty():
				return "Carta sin efectos."
			if lista.size() == 1 and lista[0] is Dictionary:
				return _explain_one(lista[0] as Dictionary)
			var partes: Array[String] = []
			for e in lista:
				if e is Dictionary:
					partes.append(_explain_one(e as Dictionary))
			if partes.is_empty():
				return "Efecto desconocido."
			return "; ".join(PackedStringArray(partes))
		if arr is Dictionary:
			return _explain_one(arr as Dictionary)
		return "Efecto desconocido."
	if card.has("effect"):
		var uno: Variant = card["effect"]
		if uno is Dictionary:
			return _explain_one(uno as Dictionary)
		return "Efecto desconocido."
	return "Carta sin efecto."


## Dos líneas de consejo inicial por civ (separadas por "\n").
static func starter_advice(civ: String) -> String:
	match civ.strip_edges().to_lower():
		"britones":
			return "Arqueros un 10% más baratos y +alcance en III/IV: llena el mazo de daño perforante.\nProtege la masa con armadura antiproyectil y madera extra para arquerías."
		"francos":
			return "Caballería con +20% de vida y granjas gratis: prioriza jinetes y paladines.\nCastillos un 25% más baratos: guarda un envío III/IV para caballerosidad y presión."
		"godos":
			return "Infantería un 20% más barata (35% en Imperial) y telar gratis: juega a espamear cuartel.\nSin murallas fuertes: usa perfusión y anarquía para cerrar rápido en III/IV."
		"vikingos":
			return "Infantería con +10/+15/+20% de vida por edad y carretilla gratis: juega agresivo a pie.\nBarcos más baratos por edad: en agua mete drakkar y jefatura en III/IV."
		"bizantinos":
			return "Edificios con +20% de vida y contra-unidades un 25% más baratas: aguanta y contraataca.\nMonjes que curan el doble: lleva logística y fuego griego para sostener el asedio."
	return "Mazo de 20 cartas (5/6/5/4): mezcla economía en I/II y ejército en III/IV.\nSolo tu civ o neutrales, sin duplicados: revisa los envíos en F5."


## Explica un único parche {target, op, path, value}.
static func _explain_one(e: Dictionary) -> String:
	var target: String = str(e.get("target", "")).strip_edges()
	var op: String = str(e.get("op", "")).strip_edges().to_lower()
	var path: String = str(e.get("path", "")).strip_edges()
	var value: Variant = e.get("value", null)
	var quien: String = _pretty_target(target)
	var que: String = _pretty_path(path)
	match op:
		"add":
			if path.to_lower().begins_with("recursos."):
				return "+%s de %s." % [_format_num(value), que]
			if path.to_lower() == "cantidad":
				return "+%s %s." % [_format_num(value), _plural(quien, value)]
			return "+%s %s de %s." % [_format_num(value), _con_articulo(que), quien]
		"mul":
			var pct: int = _as_percent(value)
			if pct == 0:
				return "Modifica %s de %s." % [que, quien]
			if _is_cost(path):
				if pct < 0:
					return "%d%% más barato el %s de %s." % [abs(pct), que, quien]
				return "+%d%% al %s de %s." % [pct, que, quien]
			if pct > 0:
				return "+%d%% %s de %s." % [pct, _con_articulo(que), quien]
			return "%d%% %s de %s." % [pct, _con_articulo(que), quien]
		"set":
			return "Fija %s de %s a %s." % [_con_articulo(que), quien, _format_num(value)]
		"append":
			if path.to_lower().ends_with("train.units"):
				return "%s puede entrenar %s." % [_cap(quien), _pretty_target("id:" + str(value))]
			return "Añade %s a %s de %s." % [str(value), que, quien]
		"remove":
			return "Quita %s de %s." % [_con_articulo(que), quien]
		"enable":
			return "Desbloquea %s." % quien
		"disable":
			return "Bloquea %s." % quien
		"replace_entity":
			return "Mejora %s y lo sustituye por %s." % [quien, _pretty_target("id:" + str(value))]
	return "Efecto %s sobre %s." % [op if not op.is_empty() else "desconocido", quien]


## "tag:arqueros | id:x & ..." -> "arqueros", "aldeanos", "tus reservas".
static func _pretty_target(t: String) -> String:
	var s: String = t.strip_edges()
	if s.is_empty():
		return "tus tropas"
	if s.to_lower() == "id:jugador":
		return "tus reservas"
	if s.contains("|"):
		var union: Array[String] = []
		for p in s.split("|"):
			union.append(_pretty_target(p))
		return " o ".join(PackedStringArray(union))
	if s.contains("&"):
		var inter: Array[String] = []
		for p in s.split("&"):
			inter.append(_pretty_target(p))
		return " y ".join(PackedStringArray(inter))
	var nombre: String = s
	var idx: int = s.find(":")
	if idx >= 0:
		nombre = s.substr(idx + 1).strip_edges()
		if nombre.is_empty():
			return "tus tropas"
	return _humanize(nombre)


## "abilities.Attack.damage.pierce" -> "ataque perforante", etc.
static func _pretty_path(p: String) -> String:
	var s: String = p.strip_edges()
	if s.is_empty():
		return "efecto"
	var low: String = s.to_lower()
	match low:
		"abilities.attack.damage.melee":
			return "ataque cuerpo a cuerpo"
		"abilities.attack.damage.pierce":
			return "ataque perforante"
		"abilities.attack.damage.edificio":
			return "bonus contra edificios"
		"abilities.attack.range":
			return "alcance"
		"abilities.attack.accuracy":
			return "precisión"
		"abilities.attack.min_range":
			return "restricción de rango mínimo"
		"abilities.armor.classes.melee":
			return "armadura cuerpo a cuerpo"
		"abilities.armor.classes.pierce":
			return "armadura antiproyectil"
		"abilities.hitpoints.max":
			return "vida máxima"
		"abilities.gather.capacity":
			return "capacidad de carga"
		"abilities.move.speed":
			return "velocidad de movimiento"
		"abilities.vision.sight":
			return "línea de visión"
		"abilities.train.units":
			return "unidades entrenables"
		"abilities.trade.gold_per_distance":
			return "oro generado por comercio"
		"cantidad":
			return "cantidad"
	if low.begins_with("abilities.gather.rates."):
		return "recolección de " + _resource(s.substr(s.rfind(".") + 1))
	if low.begins_with("recursos."):
		return _resource(s.substr(s.rfind(".") + 1))
	if low.begins_with("cost."):
		return "coste de " + _resource(s.substr(s.rfind(".") + 1))
	if low.ends_with(".damage.melee"):
		return "ataque cuerpo a cuerpo"
	if low.ends_with(".damage.pierce"):
		return "ataque perforante"
	if low.ends_with(".sight"):
		return "línea de visión"
	if s.contains("."):
		return _humanize(s.substr(s.rfind(".") + 1))
	return _humanize(s)


## "cost.wood" / "madera" -> "madera". Traduce wood/gold/food/stone.
static func _resource(r: String) -> String:
	match r.strip_edges().to_lower():
		"wood", "madera":
			return "madera"
		"food", "alimento", "comida":
			return "alimento"
		"gold", "oro":
			return "oro"
		"stone", "piedra":
			return "piedra"
	return _humanize(r)


## True si el path es un coste (cost.*).
static func _is_cost(p: String) -> bool:
	return p.strip_edges().to_lower().begins_with("cost.")


## "arquero_tiro_largo" -> "arquero tiro largo"; "infanteria" -> "infantería".
static func _humanize(s: String) -> String:
	var t: String = s.strip_edges().replace("_", " ").to_lower()
	match t:
		"infanteria":
			return "infantería"
		"arquero":
			return "arqueros"
		"aldeano":
			return "aldeanos"
		"vision":
			return "visión"
	return t


## "ataque perforante" -> "al ataque perforante"; "vida máxima" -> "a la vida máxima".
static func _con_articulo(que: String) -> String:
	var q: String = que.strip_edges().to_lower()
	if q.begins_with("ataque") or q.begins_with("alcance") or q.begins_with("bonus") or q.begins_with("oro") or q.begins_with("coste"):
		return "al " + que
	if q.begins_with("vida") or q.begins_with("armadura") or q.begins_with("velocidad") or q.begins_with("capacidad") or q.begins_with("línea") or q.begins_with("linea") or q.begins_with("precisión") or q.begins_with("precision") or q.begins_with("recolección") or q.begins_with("recoleccion") or q.begins_with("restricción") or q.begins_with("restriccion"):
		return "a la " + que
	return "a " + que


## 2 -> "2"; 1.25 -> "1.25"; "invasor_nordico" tal cual.
static func _format_num(v: Variant) -> String:
	if v is int:
		return str(v)
	if v is float:
		var f: float = v as float
		if f == floor(f):
			return str(int(f))
		return str(f)
	if v == null:
		return "?"
	return str(v)


## 1.15 -> +15; 0.9 -> -10. Devuelve 0 si no es número.
static func _as_percent(v: Variant) -> int:
	if v is int or v is float:
		return int(round((float(v) - 1.0) * 100.0))
	return 0


## Plural simple para "cantidad": "aldeano" + 2 -> "aldeanos".
static func _plural(quien: String, v: Variant) -> String:
	if v is int or v is float:
		if float(v) > 1.0 and not quien.ends_with("s") and not quien.ends_with("es"):
			return quien + "s"
	return quien


## Primera letra en mayúsculas para inicios de frase.
static func _cap(s: String) -> String:
	if s.is_empty():
		return s
	return s.substr(0, 1).to_upper() + s.substr(1)
## Ayuda runtime: coste/edad al jugar y envío (recursos o buff por edad).
static func play_hint(card: Dictionary) -> String:
	var edad: int = int(card.get("age", card.get("edad", 0)))
	var coste: String = str(card.get("cost", card.get("coste", ""))).strip_edges()
	var base: String = explain_effect(card)
	if edad > 0 and coste != "" and coste != "<null>":
		return "%s Cuesta %s y pide edad %d." % [base, coste, edad]
	if edad > 0:
		return "%s Pide edad %d." % [base, edad]
	if coste != "" and coste != "<null>":
		return "%s Cuesta %s." % [base, coste]
	return base
## Error típico al jugar: "sin_oro", "edad_insuficiente".
static func error_tip(code: String) -> String:
	match code.strip_edges().to_lower():
		"sin_oro", "sin oro":
			return "Sin oro: pide un envío de oro o ahorra antes de jugar."
		"edad_insuficiente", "edad":
			return "Edad insuficiente: avanza de edad antes de jugarla."
	return "No se puede jugar: revisa coste y edad."

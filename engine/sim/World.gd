extends RefCounted
## Estado único de la simulación. Estado mutable solo en enteros; los
## parámetros de cada habilidad ("params") apuntan a la definición y son
## de solo lectura. Iteración siempre por id ascendente.

const FP := preload("res://engine/sim/FixedPoint.gd")
const SpatialHash := preload("res://engine/sim/SpatialHash.gd")

const TICK_RATE := 10

var tick := 0
var entities: Dictionary = {}
var components: Dictionary = {}
var spatial := SpatialHash.new()
var _next_id := 1


func spawn(def: Dictionary, owner: int, pos: Vector2i) -> int:
	var id := _next_id
	_next_id += 1
	entities[id] = {"id": id, "def_id": str(def["id"]), "type": str(def["type"]), "owner": owner, "pos": pos}
	var ab: Dictionary = def.get("abilities", {})
	var names: Array = ab.keys()
	names.sort()
	for a in names:
		if not components.has(a):
			components[a] = {}
		components[a][id] = _init_component(str(a), ab[a])
	spatial.insert(id, pos)
	return id


func despawn(id: int) -> void:
	for a in components:
		components[a].erase(id)
	entities.erase(id)
	spatial.remove(id)


## Componente de estado de ejecución (Foundation, Queue): no viene de la definición.
func add_component(id: int, ability: String, c: Dictionary) -> void:
	if not components.has(ability):
		components[ability] = {}
	components[ability][id] = c


## Quita una habilidad de una entidad viva (p. ej. animal muerto -> carcasa).
func remove_component(id: int, ability: String) -> void:
	if components.has(ability):
		components[ability].erase(id)


func has_ability(id: int, ability: String) -> bool:
	return components.has(ability) and components[ability].has(id)


func comp(id: int, ability: String) -> Dictionary:
	if not has_ability(id, ability):
		return {}
	return components[ability][id]


func ids_with(ability: String) -> Array[int]:
	var out: Array[int] = []
	if components.has(ability):
		out.assign(components[ability].keys())
	out.sort()
	return out


func set_pos(id: int, p: Vector2i) -> void:
	entities[id]["pos"] = p
	spatial.move(id, p)


## Hash SHA-256 del estado relevante para detectar desync.
func state_hash() -> String:
	var ids: Array = entities.keys()
	ids.sort()
	var parts := PackedStringArray([str(tick)])
	for id in ids:
		var e: Dictionary = entities[id]
		var hp := -1
		if has_ability(id, "Hitpoints"):
			hp = components["Hitpoints"][id]["hp"]
		var mv := "-"
		if has_ability(id, "Move"):
			var m: Dictionary = components["Move"][id]
			mv = "%d:%d" % [1 if m["moving"] else 0, (m["waypoints"] as Array).size()]
		var extra := -1
		var st := ""
		if has_ability(id, "Gather"):
			extra = components["Gather"][id]["carry"]
			st = "%s:%d" % [components["Gather"][id]["state"], components["Gather"][id]["target"]]
		elif has_ability(id, "ResourceSource"):
			extra = components["ResourceSource"][id]["amount"]
			st = "k" if components["ResourceSource"][id]["killed"] else ""
		if has_ability(id, "Attack"):
			st += "@%d" % components["Attack"][id]["target"]
		if has_ability(id, "Build"):
			st += "B%s:%d" % [components["Build"][id]["state"], components["Build"][id]["target"]]
		if has_ability(id, "Foundation"):
			st += "F%d" % components["Foundation"][id]["progress"]
		if has_ability(id, "Queue"):
			var q: Dictionary = components["Queue"][id]
			st += "Q%d:%d:%s" % [(q["items"] as Array).size(), q["progress"], q["rally"]]
		parts.append("%d|%s|%d|%d|%d|%d|%s|%d|%s" % [id, e["def_id"], e["owner"], e["pos"].x, e["pos"].y, hp, mv, extra, st])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(parts).to_utf8_buffer())
	return ctx.finish().hex_encode()


static func _init_component(ability: String, params: Dictionary) -> Dictionary:
	var c := {"params": params}
	match ability:
		"Hitpoints":
			var mx := int(round(float(params["max"])))
			c["max"] = mx
			c["hp"] = mx
		"ResourceSource":
			c["amount"] = FP.from_data(float(params["amount"]))
			c["killed"] = false # animales: carcasa tras morir
		"Attack":
			c["target"] = -1
			c["explicit"] = false
			c["cooldown"] = 0
			c["windup"] = -1
			c["attacking"] = false
			c["repath"] = 0
			c["aim"] = Vector2i(-1000000, -1000000)
			c["stuck"] = 0
			c["ignore"] = -1
			c["ignore_until"] = 0
		"Build":
			c["state"] = "idle"
			c["target"] = -1
		"Gather":
			c["state"] = "idle"
			c["target"] = -1
			c["carry"] = 0
			c["carry_res"] = ""
			c["kind"] = ""
			c["dropsite"] = -1
		"Move":
			c["step"] = FP.from_data(float(params["speed"])) / TICK_RATE
			c["waypoints"] = [] as Array[Vector2i]
			c["moving"] = false
			c["facing"] = Vector2i(1000, 1000)
	return c

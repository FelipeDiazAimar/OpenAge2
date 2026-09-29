extends Node2D
## Suelo bajo los edificios (solo cliente): como en AoE2, cada edificio se
## asienta sobre tierra pisada con los bordes difuminados hacia el pasto.
## Va entre el terreno y las entidades. Usa la textura de tierra del DE si
## está exportada (terrain:g_ds3); si no, un color de tierra.

const Iso := preload("res://engine/render2d/Iso.gd")

const TEXTURE_REF := "terrain:g_ds3"
const FALLBACK := Color("#8a6a44")
## Margen (en casillas) alrededor de la huella: sólido y difuminado.
const SOLID_PAD := 0.15
const FADE_PAD := 0.75
## Casillas de textura por repetición (la del DE cubre ~4×4 casillas).
const TEX_TILES := 4.0

var sim
var _tex: Texture2D
var _sig := ""


func setup(p_sim, locator) -> void:
	sim = p_sim
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if locator != null and locator.has_method("terrain"):
		_tex = locator.terrain(TEXTURE_REF)
	z_index = -2
	refresh()


## Redibuja si cambió el conjunto de edificios (llamar por tick).
func refresh() -> void:
	var ids: Array = []
	for id in sim.world.ids_with("Hitpoints"):
		if _grounded(id):
			ids.append(id)
	var sig := ",".join(ids.map(func(i): return str(i)))
	if sig != _sig:
		_sig = sig
		queue_redraw()


func _grounded(id: int) -> bool:
	var w = sim.world
	var e: Dictionary = w.entities[id]
	if str(e["type"]) != "building":
		return false
	# La granja ya es tierra; el muelle va en el agua.
	return not w.has_ability(id, "Farm") and not w.has_ability(id, "Dock")


func _draw() -> void:
	if sim == null:
		return
	for id in sim.world.ids_with("Hitpoints"):
		if not _grounded(id):
			continue
		var def: Dictionary = sim.def_for(id)
		var fp := Vector2(1, 1)
		if def.get("footprint") is Array:
			fp = Vector2(float(def["footprint"][0]), float(def["footprint"][1]))
		var c := Vector2(sim.world.entities[id]["pos"]) / 1000.0
		_patch(c, fp)


## Rombo sólido de la huella y un anillo que se desvanece hacia afuera.
func _patch(center: Vector2, fp: Vector2) -> void:
	var inner := _diamond(center, fp * 0.5 + Vector2(SOLID_PAD, SOLID_PAD))
	var outer := _diamond(center, fp * 0.5 + Vector2(FADE_PAD, FADE_PAD))
	var solid := Color(1, 1, 1, 0.95)
	var clear := Color(1, 1, 1, 0.0)
	if _tex == null:
		solid = Color(FALLBACK, 0.95)
		clear = Color(FALLBACK, 0.0)
	draw_polygon(inner, PackedColorArray([solid, solid, solid, solid]), _uvs(inner), _tex)
	for i in 4:
		var j := (i + 1) % 4
		var quad := PackedVector2Array([inner[i], inner[j], outer[j], outer[i]])
		draw_polygon(quad, PackedColorArray([solid, solid, clear, clear]), _uvs(quad), _tex)


func _diamond(center: Vector2, half: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Iso.to_screen(center + Vector2(-half.x, -half.y)), Iso.to_screen(center + Vector2(half.x, -half.y)),
		Iso.to_screen(center + Vector2(half.x, half.y)), Iso.to_screen(center + Vector2(-half.x, half.y))])


## UV por posición en el mundo: la textura queda continua entre edificios.
func _uvs(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var span := Vector2(Iso.TILE_W, Iso.TILE_H) * TEX_TILES
	for p in pts:
		out.append(p / span)
	return out

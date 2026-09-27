class_name SpriteFactory
extends RefCounted
## SpriteFactory: unidades 2D del AoE2 (extract_aoe2_sprites.py) con fallback
## a ModelFactory 3D si aún no hay PNGs extraídos. API idéntica a ModelFactory.

const PACKS := {
	"aldeano": "res://assets/sprites/villager",
	"milicia": "res://assets/sprites/militia",
	"arquero": "res://assets/sprites/archer",
	"scout": "res://assets/sprites/scout",
	"monje": "res://assets/sprites/monk",
}


static func has_sprites(kind: String) -> bool:
	var k := kind.to_lower().strip_edges()
	if not PACKS.has(k):
		return false
	var base := str(PACKS[k])
	return FileAccess.file_exists(base + "/walk/manifest.pack.json") and FileAccess.file_exists(base + "/idle/manifest.pack.json")


static func spawn(kind: String, civ_color: Color) -> Node3D:
	if has_sprites(kind):
		var u := SpriteUnit.with_pack(str(PACKS[kind.to_lower().strip_edges()]))
		u.name = "Unit_" + kind
		return u
	return ModelFactory.spawn_unit(kind, civ_color)

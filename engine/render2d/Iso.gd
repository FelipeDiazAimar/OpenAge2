extends RefCounted
## Proyección isométrica 2:1 (casilla 96x48, como los sprites x1 del AoE2 DE).
## Solo cliente: floats permitidos.

const TILE_W := 96.0
const TILE_H := 48.0


static func to_screen(tiles: Vector2) -> Vector2:
	return Vector2((tiles.x - tiles.y) * TILE_W * 0.5, (tiles.x + tiles.y) * TILE_H * 0.5)


static func milli_to_screen(p: Vector2i) -> Vector2:
	return to_screen(Vector2(p) / 1000.0)


static func to_tiles(screen: Vector2) -> Vector2:
	var a := screen.x / (TILE_W * 0.5)
	var b := screen.y / (TILE_H * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


## Slot de sprite (0..15) para un rumbo en pantalla. Orden del archivo DE:
## W=0 y antihorario (S=4, E=8, N=12).
static func dir16(screen_delta: Vector2) -> int:
	var compass := rad_to_deg(atan2(screen_delta.x, -screen_delta.y))
	return posmod(int(round((270.0 - compass) / 22.5)), 16)

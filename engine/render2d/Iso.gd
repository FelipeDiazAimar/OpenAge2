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


## Slot de sprite (0..15) para un rumbo en pantalla. Orden de los .sld del DE
## (comprobado con los sprites): E=0 y en sentido horario (SE=2, S=4, SW=6,
## W=8, NW=10, N=12, NE=14).
static func dir16(screen_delta: Vector2) -> int:
	var compass := rad_to_deg(atan2(screen_delta.x, -screen_delta.y)) # 0=N, 90=E
	return posmod(int(round((compass - 90.0) / 22.5)), 16)

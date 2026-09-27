extends RefCounted
## Aritmética de punto fijo determinista: 1 casilla = SCALE unidades.
## Todo el estado mutable de la simulación usa estos enteros; los float
## solo aparecen al leer datos (from_data), nunca dentro del tick.

const SCALE := 1000


static func from_tiles(tiles: int) -> int:
	return tiles * SCALE


## Convierte un valor de datos (float de JSON) a punto fijo, redondeando a milésimas.
static func from_data(v: float) -> int:
	return int(round(v * SCALE))


static func mul(a: int, b: int) -> int:
	return _div_round(a * b, SCALE)


static func div(a: int, b: int) -> int:
	assert(b != 0, "FixedPoint.div: división por cero")
	return _div_round(a * SCALE, b)


## División entera redondeando hacia -infinito (celdas con coordenadas negativas).
static func floordiv(a: int, b: int) -> int:
	var q := a / b
	if a % b != 0 and ((a < 0) != (b < 0)):
		q -= 1
	return q


## Raíz cuadrada entera (piso) por Newton.
static func isqrt(n: int) -> int:
	if n < 2:
		return maxi(n, 0)
	var x := n
	var y := (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x


static func length(dx: int, dy: int) -> int:
	return isqrt(dx * dx + dy * dy)


static func dist(a: Vector2i, b: Vector2i) -> int:
	return length(b.x - a.x, b.y - a.y)


## n / d redondeando la mitad lejos de cero.
static func _div_round(n: int, d: int) -> int:
	var q := n / d
	var r := n % d
	if absi(r) * 2 >= absi(d):
		q += 1 if (n < 0) == (d < 0) else -1
	return q

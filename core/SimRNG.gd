extends Node
class_name SimRNG
## SimRNG — RNG determinista para lockstep (Godot 4.4, GDScript).
## PROHIBIDO randf()/randi()/RandomNumberGenerator/Time en lógica. Usar solo esto.
##
## Algoritmo:
##  - Semilla por partida: set_seed(map_seed) -> splitmix32 una vez.
##  - Re-semilla por tick: reseed_per_tick(tick) -> splitmix32(base_seed + tick*GOLDEN).
##  - Stream por tick: xorshift32 puro.
## Todo el estado cabe en 32 bits (MASK32). Tick 10Hz según core/API.md.
## Uso lockstep:
##   rng.set_seed(map_seed)
##   # cada tick, antes de simular:
##   rng.reseed_per_tick(tick)
##   var v := rng.next_int(0, 100)
##   var f := rng.next_float()   # [0, 1)
##   var d := rng.next_dir()     # Vector2i, una de 8 direcciones

const MASK32: int = 0xFFFFFFFF
const GOLDEN32: int = 0x9E3779B9 # 2654435769
const FALLBACK_STATE: int = 0x6C078965 # 1812433253, evita lock en 0
const INV_2POW32: float = 1.0 / 4294967296.0 # 2^-32, para [0,1)

# 8 direcciones (E, NE, N, NW, W, SW, S, SE). Orden fijo = parte del protocolo.
const DIRS8 := [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]

var _base_seed: int = FALLBACK_STATE
var _state: int = FALLBACK_STATE
var _tick: int = 0


## Fija la semilla de la partida (map_seed). Resetea tick a 0.
func set_seed(map_seed: int) -> void:
	_base_seed = map_seed & MASK32
	if _base_seed == 0:
		_base_seed = FALLBACK_STATE
	_tick = 0
	_state = _splitmix32(_base_seed)
	if _state == 0:
		_state = FALLBACK_STATE


## Re-semilla determinista al inicio de cada tick lockstep.
## Misma (map_seed, tick) => mismo _state inicial => misma secuencia.
func reseed_per_tick(tick: int) -> void:
	_tick = tick
	var tick_part: int = ((tick & MASK32) * GOLDEN32) & MASK32
	var combined: int = (_base_seed + tick_part) & MASK32
	_state = _splitmix32(combined)
	if _state == 0:
		_state = FALLBACK_STATE


## splitmix32 (stateless): mezcla un entero de 32 bits en otro.
static func _splitmix32(seed: int) -> int:
	var z: int = ((seed & MASK32) + GOLDEN32) & MASK32
	z = (((z ^ (z >> 15)) * 0x85EBCA6B) & MASK32)
	z = (((z ^ (z >> 13)) * 0xC2B2AE35) & MASK32)
	z = ((z ^ (z >> 16)) & MASK32)
	return z


## Un paso xorshift32. Avanza el stream. Nunca devuelve estado bloqueado en 0.
func _next_u32() -> int:
	var x: int = _state
	x = (x ^ ((x << 13) & MASK32)) & MASK32
	x = (x ^ (x >> 17)) & MASK32
	x = (x ^ ((x << 5) & MASK32)) & MASK32
	if x == 0:
		x = FALLBACK_STATE
	_state = x
	return x


## Entero inclusivo en [min_v, max_v]. Sin sesgo de módulo (escala por 2^-32).
func next_int(min_v: int, max_v: int) -> int:
	if max_v < min_v:
		var t: int = min_v
		min_v = max_v
		max_v = t
	var span: int = max_v - min_v + 1
	if span <= 1:
		return min_v
	var r: int = _next_u32()
	var scaled: int = int(float(r) * INV_2POW32 * float(span))
	# clamp por seguridad de redondeo float (no debería pasar, pero determinista)
	if scaled < 0:
		scaled = 0
	elif scaled >= span:
		scaled = span - 1
	return min_v + scaled


## Float en [0, 1). Determinista bit a bit para misma semilla.
func next_float() -> float:
	return float(_next_u32()) * INV_2POW32


## Float en [min_v, max_v).
func next_float_range(min_v: float, max_v: float) -> float:
	return min_v + next_float() * (max_v - min_v)


## Una de las 8 direcciones. Consume exactamente 1 paso del stream.
func next_dir() -> Vector2i:
	return DIRS8[next_int(0, 7)]


## Compat con versión anterior (core/API.md: no romper). null si vacío.
func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[next_int(0, arr.size() - 1)]


func get_seed() -> int:
	return _base_seed


func get_tick() -> int:
	return _tick


func get_state() -> int:
	return _state


## Auto-verify: misma seed + mismo tick => misma secuencia de 100 valores
## (next_int + next_float + next_dir por iteración). Además chequea rangos
## y que reseed con mismo tick reinicia la secuencia.
## Devuelve true si OK, false si FAIL (más push_error). Llamar en boot:
##   assert(SimRNG.self_test())
static func self_test(p_map_seed: int = 987654321, p_tick: int = 1234) -> bool:
	var a := SimRNG.new()
	var b := SimRNG.new()
	a.set_seed(p_map_seed)
	b.set_seed(p_map_seed)
	a.reseed_per_tick(p_tick)
	b.reseed_per_tick(p_tick)
	for i in range(100):
		var ia: int = a.next_int(-50, 50)
		var ib: int = b.next_int(-50, 50)
		if ia != ib:
			push_error("[SimRNG] self_test FAIL int i=%d %d != %d" % [i, ia, ib])
			a.free()
			b.free()
			return false
		if ia < -50 or ia > 50:
			push_error("[SimRNG] self_test FAIL rango int i=%d v=%d" % [i, ia])
			a.free()
			b.free()
			return false
		var fa: float = a.next_float()
		var fb: float = b.next_float()
		if fa != fb:
			push_error("[SimRNG] self_test FAIL float i=%d %f != %f" % [i, fa, fb])
			a.free()
			b.free()
			return false
		if fa < 0.0 or fa >= 1.0:
			push_error("[SimRNG] self_test FAIL rango float i=%d v=%f" % [i, fa])
			a.free()
			b.free()
			return false
		var da: Vector2i = a.next_dir()
		var db: Vector2i = b.next_dir()
		if da != db:
			push_error("[SimRNG] self_test FAIL dir i=%d %s != %s" % [i, str(da), str(db)])
			a.free()
			b.free()
			return false
		if not (da in DIRS8):
			push_error("[SimRNG] self_test FAIL dir inválida i=%d v=%s" % [i, str(da)])
			a.free()
			b.free()
			return false
	# reseed con el mismo tick debe reiniciar la secuencia (replay determinista)
	a.reseed_per_tick(p_tick)
	var check: int = a.next_int(-50, 50)
	b.set_seed(p_map_seed)
	b.reseed_per_tick(p_tick)
	var expected: int = b.next_int(-50, 50)
	if check != expected:
		push_error("[SimRNG] self_test FAIL reseed %d != %d" % [check, expected])
		a.free()
		b.free()
		return false
	# sanity: tick distinto => secuencia distinta (casi seguro; si colisiona, avisa)
	a.reseed_per_tick(p_tick + 1)
	var other: int = a.next_int(-50, 50)
	if other == expected:
		push_warning("[SimRNG] self_test WARN tick+1 dio mismo primer int (colisión rara, revisar)")
	print("[SimRNG] self_test OK seed=%d tick=%d x100 (int+float+dir)" % [p_map_seed, p_tick])
	a.free()
	b.free()
	return true


## Auto-verify en debug al instanciarse en escena. En release no hace nada.
func _ready() -> void:
	if OS.has_feature("debug"):
		var ok: bool = SimRNG.self_test()
		assert(ok, "[SimRNG] auto-verify FAILED en _ready()")

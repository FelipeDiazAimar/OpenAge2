extends RefCounted
## PRNG determinista de la simulación (xorshift32). Mismo resultado en todas
## las PCs de la LAN; nunca usar randf/randi en engine/sim.

var _s := 0


func _init(p_seed: int) -> void:
	_s = p_seed & 0xFFFFFFFF
	if _s == 0:
		_s = 0x9E3779B9


func next_u32() -> int:
	var x := _s
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	_s = x & 0xFFFFFFFF
	return _s


func range_i(lo: int, hi: int) -> int:
	return lo + next_u32() % (hi - lo + 1)

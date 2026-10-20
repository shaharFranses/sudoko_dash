## Deterministic xorshift32 PRNG (portable: only shifts/xors on 32-bit values).
extends RefCounted

var state: int

func _init(seed_value: int) -> void:
	state = (seed_value ^ 0x9E3779B9) & 0xFFFFFFFF
	if state == 0:
		state = 0x6D2B79F5
	for i in 4:
		next_u32()

func next_u32() -> int:
	var x = state
	x = (x ^ (x << 13)) & 0xFFFFFFFF
	x = x ^ (x >> 17)
	x = (x ^ (x << 5)) & 0xFFFFFFFF
	state = x
	return x

## Uniform-ish int in [0, n).
func below(n: int) -> int:
	return next_u32() % n

## Fisher-Yates shuffle in place.
func shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j = below(i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

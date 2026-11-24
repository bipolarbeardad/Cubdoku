extends RefCounted
## Samples each legal row/column placement with equal probability before terrain.

var _counts := {}


func count(side: int) -> int:
	if side not in [8, 9, 10]:
		return 0
	return _completions((1 << side) - 1, -2)


func sample(side: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	if side not in [8, 9, 10]:
		return PackedInt32Array()
	var remaining := (1 << side) - 1
	var previous := -2
	var columns := PackedInt32Array()
	while remaining:
		var rank := rng.randi_range(0, _completions(remaining, previous) - 1)
		for column in side:
			var bit := 1 << column
			if not (remaining & bit) or absi(previous - column) <= 1:
				continue
			var ways := _completions(remaining ^ bit, column)
			if rank < ways:
				columns.append(column)
				remaining ^= bit
				previous = column
				break
			rank -= ways
	return columns


func _completions(remaining: int, previous: int) -> int:
	if remaining == 0:
		return 1
	# The first call uses a sentinel column outside all set bits.
	var key := Vector2i(remaining, previous)
	if _counts.has(key):
		return _counts[key]
	var total := 0
	var index := 0
	var bits := remaining
	while bits:
		if bits & 1 and absi(previous - index) > 1:
			total += _completions(remaining ^ (1 << index), index)
		index += 1
		bits >>= 1
	_counts[key] = total
	return total

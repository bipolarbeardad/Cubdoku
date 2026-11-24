extends RefCounted
## Explainable Hall reservations beyond the existing pair and triple rules.
## Opt-in for research. Production difficulty masks are unchanged.

const Analyzer := preload("res://scripts/difficulty_analyzer.gd")


static func extend(board: PackedInt32Array, prefix: Dictionary, families: int) -> Dictionary:
	assert(prefix.status == Analyzer.Status.STUCK)
	return Analyzer._analyze(board, families, prefix, [], moves)


static func moves(groups: Array[PackedInt32Array], _board: PackedInt32Array,
	side: int, _candidates: PackedByteArray) -> Array[Dictionary]:
	# A matching between regions and lines is required by every valid solution.
	# Enumerating region subsets provides a compact witness for each elimination.
	var limit := 1 << side
	for columns in [false, true]:
		var masks := PackedInt32Array()
		var line_for := PackedInt32Array()
		for cell in side * side:
			@warning_ignore("integer_division")
			line_for.append(cell % side if columns else cell / side)
		for region in side:
			var mask := 0
			for cell in groups[region]:
				mask |= 1 << line_for[cell]
			masks.append(mask)
		var unions := PackedInt32Array()
		unions.resize(limit)
		var indices := {}
		for region in side:
			indices[1 << region] = region
		for subset in range(1, limit - 1):
			var least := subset & -subset
			unions[subset] = unions[subset ^ least] | masks[indices[least]]
			var count := _count_bits(subset)
			var lines := unions[subset]
			if count < 4 or _count_bits(lines) != count:
				continue
			var sources := []
			var eliminated := PackedInt32Array()
			for region in side:
				if subset & (1 << region):
					sources.append(region)
				else:
					for cell in groups[region]:
						if lines & (1 << line_for[cell]):
							eliminated.append(cell)
			if not eliminated.is_empty():
				return [{"technique": Analyzer.Technique.REGION_HALL_SET, "groups": sources,
					"eliminated": eliminated, "column_reservation": columns, "line_mask": lines}]
	return []


static func _count_bits(mask: int) -> int:
	var count := 0
	while mask:
		mask &= mask - 1
		count += 1
	return count

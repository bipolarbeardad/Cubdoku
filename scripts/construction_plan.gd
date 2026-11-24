extends RefCounted
## Construction-side geometry. The proof engine sees only the completed layout.

const Validator := preload("res://scripts/puzzle_validator.gd")

static func swaps(columns: PackedInt32Array) -> Array[Vector4i]:
	var size := columns.size()
	var result: Array[Vector4i] = []
	for first in size:
		for second in range(first + 1, size):
			var valid := true
			for row in [first, second]:
				var exchanged := second if row == first else first
				for adjacent in [row - 1, row + 1]:
					if adjacent < 0 or adjacent >= size:
						continue
					var other_column := columns[row] if adjacent == exchanged else columns[adjacent]
					if absi(columns[exchanged] - other_column) <= 1:
						valid = false
			if valid:
				result.append(Vector4i(first * size + columns[second], second * size + columns[first], first, second))
	return result


static func live_witnesses(board: PackedInt32Array, anchors: PackedInt32Array, pairs: Array[Vector4i]) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for pair in pairs:
		var a := board[pair.x]
		var b := board[pair.y]
		if (a == pair.z and b == pair.w) or (a == pair.w and b == pair.z):
			var alternative := anchors.duplicate()
			alternative[pair.z] = pair.x
			alternative[pair.w] = pair.y
			result.append(alternative)
	return result


static func swap_penalty(board: PackedInt32Array, cell: int, region: int, endpoints: Dictionary) -> int:
	if not endpoints.has(cell):
		return 0
	var target: Vector3i = endpoints[cell]
	# A crossed cell participates in at most one two-row swap of these columns.
	if region == target.y and board[target.x] == target.z:
		return 1
	if region == target.z and board[target.x] == target.y:
		return 1
	return 0


static func endpoints(pairs: Array[Vector4i]) -> Dictionary:
	var result := {}
	for pair in pairs:
		result[pair.x] = Vector3i(pair.y, pair.z, pair.w)
		result[pair.y] = Vector3i(pair.x, pair.z, pair.w)
	return result


## Plan two exactly-two-cell regions supporting x→¬a→b→¬c→d→¬x.
static func chain_motif(board: PackedInt32Array, columns: PackedInt32Array, rng: RandomNumberGenerator) -> Dictionary:
	var side := columns.size()
	var dominoes: Array[Vector3i] = []
	for row in side:
		var anchor := row * side + columns[row]
		for neighbor in Validator.orthogonal_neighbors(anchor, side):
			if board[neighbor] < 0:
				dominoes.append(Vector3i(anchor, neighbor, row))
	for attempt in 32:
		var first := dominoes[rng.randi_range(0, dominoes.size() - 1)]
		var second := dominoes[rng.randi_range(0, dominoes.size() - 1)]
		if first.z == second.z or first.y == second.y:
			continue
		var a := first.x
		var b := first.y
		var c := second.x
		var d := second.y
		if rng.randi_range(0, 1) == 0:
			a = first.y
			b = first.x
		if rng.randi_range(0, 1) == 0:
			c = second.y
			d = second.x
		if not _conflicts(b, c, side):
			continue
		var start := rng.randi_range(0, board.size() - 1)
		for offset in board.size():
			var x := (start + offset) % board.size()
			if board[x] < 0 and x != first.y and x != second.y and _conflicts(x, a, side) and _conflicts(x, d, side) and not _conflicts(x, b, side) and not _conflicts(x, c, side):
				return {"first": first, "second": second, "path": [x, a, b, c, d, x]}
	return {}


static func _conflicts(a: int, b: int, size: int) -> bool:
	@warning_ignore("integer_division")
	var rows := absi(a / size - b / size)
	var columns := absi(a % size - b % size)
	return rows == 0 or columns == 0 or (rows == 1 and columns == 1)

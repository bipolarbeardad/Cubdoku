extends RefCounted
## Exhaustively searches row by row. Two matches are enough to reject uniqueness.

const Validator := preload("res://scripts/puzzle_validator.gd")


static func find_solutions(regions: PackedInt32Array, limit: int = 2) -> Array[PackedInt32Array]:
	var solutions: Array[PackedInt32Array] = []
	if limit > 0 and Validator.is_valid_terrain(regions):
		return search_connected_board(regions, Validator.board_size(regions), limit)
	return solutions


## Entry point for callers that have already checked structural validity.
static func search_connected_board(regions: PackedInt32Array, size: int, limit: int = 2) -> Array[PackedInt32Array]:
	var solutions: Array[PackedInt32Array] = []
	var row_suffix := PackedInt32Array()
	row_suffix.resize(size + 1)
	for row in range(size - 1, -1, -1):
		row_suffix[row] = row_suffix[row + 1]
		for column in size:
			row_suffix[row] |= 1 << regions[row * size + column]
	_search(regions, size, 0, -2, 0, 0, PackedInt32Array(), solutions, limit, row_suffix, {})
	return solutions


static func _search(
	regions: PackedInt32Array,
	size: int,
	row: int,
	previous_column: int,
	used_columns: int,
	used_regions: int,
	cells: PackedInt32Array,
	solutions: Array[PackedInt32Array],
	limit: int,
	row_suffix: PackedInt32Array,
	dead: Dictionary,
) -> void:
	if row == size:
		solutions.append(cells.duplicate())
		return
	if (used_regions | row_suffix[row]) != (1 << size) - 1:
		return
	# The column mask determines the row. Cache only dead states so counts and order are unchanged.
	var key := used_columns | (used_regions << size) | ((previous_column + 2) << (2 * size))
	if size >= 8 and dead.has(key):
		return
	var before := solutions.size()

	for column in size:
		var cell := row * size + column
		var column_bit := 1 << column
		var region_bit := 1 << regions[cell]
		# Unique columns handle vertical contact and only adjacent rows can touch.
		if (used_columns & column_bit) or (used_regions & region_bit):
			continue
		if absi(column - previous_column) <= 1:
			continue

		cells.append(cell)
		_search(
			regions, size, row + 1, column, used_columns | column_bit,
			used_regions | region_bit, cells, solutions, limit, row_suffix, dead,
		)
		cells.remove_at(cells.size() - 1)
		if solutions.size() >= limit:
			return
	if size >= 8 and solutions.size() == before:
		dead[key] = true

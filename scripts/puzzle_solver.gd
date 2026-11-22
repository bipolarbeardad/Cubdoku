extends RefCounted
## Exhaustively searches row by row. Two matches are enough to reject uniqueness.

const Validator := preload("res://scripts/puzzle_validator.gd")


static func find_solutions(regions: PackedInt32Array) -> Array[PackedInt32Array]:
	var solutions: Array[PackedInt32Array] = []
	if Validator.is_valid_terrain(regions):
		_search(regions, 0, -2, 0, 0, PackedInt32Array(), solutions)
	return solutions


static func _search(
	regions: PackedInt32Array,
	row: int,
	previous_column: int,
	used_columns: int,
	used_regions: int,
	cells: PackedInt32Array,
	solutions: Array[PackedInt32Array],
) -> void:
	if row == Validator.SIZE:
		solutions.append(cells.duplicate())
		return

	for column in Validator.SIZE:
		var cell := row * Validator.SIZE + column
		var column_bit := 1 << column
		var region_bit := 1 << regions[cell]
		# Unique columns handle vertical contact and only adjacent rows can touch.
		if (used_columns & column_bit) or (used_regions & region_bit):
			continue
		if absi(column - previous_column) <= 1:
			continue

		cells.append(cell)
		_search(
			regions, row + 1, column, used_columns | column_bit,
			used_regions | region_bit, cells, solutions
		)
		cells.remove_at(cells.size() - 1)
		if solutions.size() >= 2:
			return

extends RefCounted
## Validates the terrain partition independently of any bear arrangement.

const SIZE := 4
const CELL_COUNT := SIZE * SIZE
# Existing playable BASE sizes and renderer limits are separate from validation.
const MAX_SIZE := 7
const ENGINE_MAX_SIZE := 10
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func supports_size(size: int) -> bool:
	return size >= SIZE and size <= ENGINE_MAX_SIZE


static func board_size(regions: PackedInt32Array) -> int:
	var size := int(sqrt(regions.size()))
	return size if supports_size(size) and size * size == regions.size() else 0


static func orthogonal_neighbors(cell: int, size: int = SIZE) -> PackedInt32Array:
	@warning_ignore("integer_division")
	var position := Vector2i(cell % size, cell / size)
	var neighbors := PackedInt32Array()
	for direction: Vector2i in DIRECTIONS:
		var neighbor := position + direction
		if Rect2i(0, 0, size, size).has_point(neighbor):
			neighbors.append(neighbor.y * size + neighbor.x)
	return neighbors


static func is_valid_terrain(regions: PackedInt32Array) -> bool:
	var size := board_size(regions)
	if size == 0:
		return false

	var seen_regions := {}
	var visited := {}
	for cell in regions.size():
		var region := regions[cell]
		if region < 0 or region >= size:
			return false
		if visited.has(cell):
			continue
		if seen_regions.has(region):
			return false

		seen_regions[region] = true
		visited[cell] = true
		var pending := PackedInt32Array([cell])
		while not pending.is_empty():
			var current := pending[pending.size() - 1]
			pending.remove_at(pending.size() - 1)
			for neighbor in orthogonal_neighbors(current, size):
				if regions[neighbor] == region and not visited.has(neighbor):
					visited[neighbor] = true
					pending.append(neighbor)

	return seen_regions.size() == size

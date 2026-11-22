extends RefCounted
## Validates the terrain partition independently of any bear arrangement.

const SIZE := 4
const CELL_COUNT := SIZE * SIZE
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func orthogonal_neighbors(cell: int) -> PackedInt32Array:
	@warning_ignore("integer_division")
	var position := Vector2i(cell % SIZE, cell / SIZE)
	var neighbors := PackedInt32Array()
	for direction: Vector2i in DIRECTIONS:
		var neighbor := position + direction
		if Rect2i(0, 0, SIZE, SIZE).has_point(neighbor):
			neighbors.append(neighbor.y * SIZE + neighbor.x)
	return neighbors


static func is_valid_terrain(regions: PackedInt32Array) -> bool:
	if regions.size() != CELL_COUNT:
		return false

	var seen_regions := {}
	var visited := {}
	for cell in CELL_COUNT:
		var region := regions[cell]
		if region < 0 or region >= SIZE:
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
			for neighbor in orthogonal_neighbors(current):
				if regions[neighbor] == region and not visited.has(neighbor):
					visited[neighbor] = true
					pending.append(neighbor)

	return seen_regions.size() == SIZE

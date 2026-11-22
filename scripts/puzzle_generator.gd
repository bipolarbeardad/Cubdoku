extends RefCounted
## Grows each terrain from a seed bear, then verifies uniqueness independently.

const Validator := preload("res://scripts/puzzle_validator.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const DEFAULT_ATTEMPTS := 32
const BEAR_COLUMNS := [1, 3, 0, 2]
const FALLBACK := [
	1, 0, 1, 1,
	1, 1, 1, 1,
	2, 2, 2, 2,
	3, 3, 3, 3,
]

var rejected_attempts := 0
var used_fallback := false


func generate(seed_value: int, max_attempts: int = DEFAULT_ATTEMPTS) -> PackedInt32Array:
	rejected_attempts = 0
	used_fallback = false
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for attempt in maxi(max_attempts, 0):
		var regions := _grow_regions(rng)
		if Solver.find_solutions(regions).size() == 1:
			return regions
		rejected_attempts += 1

	used_fallback = true
	var fallback := PackedInt32Array(FALLBACK)
	if Solver.find_solutions(fallback).size() == 1:
		return fallback
	return PackedInt32Array()


func _grow_regions(rng: RandomNumberGenerator) -> PackedInt32Array:
	var regions := PackedInt32Array()
	regions.resize(Validator.CELL_COUNT)
	regions.fill(-1)
	# Mirroring switches between the two non-touching 4-by-4 row/column patterns.
	var mirrored := rng.randi_range(0, 1) == 1
	for row in Validator.SIZE:
		var column: int = BEAR_COLUMNS[row]
		if mirrored:
			column = Validator.SIZE - 1 - column
		regions[row * Validator.SIZE + column] = row

	for step in Validator.CELL_COUNT - Validator.SIZE:
		var frontier_cells := PackedInt32Array()
		var frontier_regions := PackedInt32Array()
		for cell in Validator.CELL_COUNT:
			if regions[cell] < 0:
				continue
			for neighbor in Validator.orthogonal_neighbors(cell):
				if regions[neighbor] < 0:
					frontier_cells.append(neighbor)
					frontier_regions.append(regions[cell])
		var pick := rng.randi_range(0, frontier_cells.size() - 1)
		regions[frontier_cells[pick]] = frontier_regions[pick]

	return regions

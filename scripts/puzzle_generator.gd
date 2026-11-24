extends RefCounted
## Grows connected terrain around seed bears and checks uniqueness and difficulty.

const Validator := preload("res://scripts/puzzle_validator.gd")
const Construction := preload("res://scripts/construction_plan.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const Difficulty := preload("res://scripts/puzzle_difficulty.gd")
const DEFAULT_ATTEMPTS := 32
const FALLBACK := [
	1, 0, 1, 1,
	1, 1, 1, 1,
	2, 2, 2, 2,
	3, 3, 3, 3,
]
# Curated layouts are independent of the current seeded generation algorithm.
const FALLBACKS := {
	4: FALLBACK,
	5: [
		1, 1, 1, 0, 0,
		1, 1, 1, 1, 0,
		4, 4, 4, 4, 2,
		3, 4, 4, 2, 2,
		4, 4, 4, 4, 4,
	],
	6: [
		1, 1, 1, 0, 0, 0,
		1, 1, 1, 1, 1, 0,
		2, 2, 2, 1, 1, 1,
		2, 2, 3, 4, 4, 4,
		2, 2, 5, 5, 4, 5,
		5, 5, 5, 5, 5, 5,
	],
	7: [
		1, 1, 1, 1, 0, 0, 0,
		1, 1, 1, 1, 0, 0, 0,
		1, 1, 1, 1, 3, 0, 2,
		1, 1, 3, 3, 3, 0, 2,
		4, 3, 3, 3, 2, 2, 2,
		4, 3, 5, 5, 2, 2, 2,
		4, 4, 5, 5, 6, 2, 2,
	],
}

var rejected_attempts := 0
var used_fallback := false


func generate(
	seed_value: int, max_attempts: int = DEFAULT_ATTEMPTS, difficulty: String = Difficulty.BASE,
	size: int = Validator.SIZE,
) -> PackedInt32Array:
	rejected_attempts = 0
	used_fallback = false
	if not Difficulty.supports(difficulty) or not Difficulty.is_size_eligible(difficulty, size):
		return PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for attempt in maxi(max_attempts, 0):
		var regions := _grow_regions(rng, size)
		if _accepts(regions, difficulty):
			return regions
		rejected_attempts += 1

	var fallback := PackedInt32Array(FALLBACKS.get(size, []))
	if _accepts(fallback, difficulty):
		used_fallback = true
		return fallback
	return PackedInt32Array()


func _accepts(regions: PackedInt32Array, difficulty: String) -> bool:
	return Solver.find_solutions(regions).size() == 1 and Difficulty.matches(difficulty, regions)


func _grow_regions(rng: RandomNumberGenerator, size: int, bears := PackedInt32Array()) -> PackedInt32Array:
	bears.clear()
	var regions := _seed_terrain(rng, size, bears)
	if regions.is_empty():
		return regions

	# Start every other region with a second cell eliminated by an earlier bear.
	var singleton := rng.randi_range(0, size - 1)
	var order := PackedInt32Array()
	order.resize(size)
	order.fill(-1)
	order[singleton] = 0
	var blocked_at := PackedInt32Array()
	blocked_at.resize(regions.size())
	blocked_at.fill(size)
	_note_eliminations(blocked_at, size, singleton, bears[singleton], 0)
	for rank in range(1, size):
		var extensions: Array[Vector2i] = []
		for row in size:
			if order[row] != -1:
				continue
			for adjacent in Validator.orthogonal_neighbors(row * size + bears[row], size):
				if regions[adjacent] == -1 and blocked_at[adjacent] < rank:
					extensions.append(Vector2i(adjacent, row))
		if extensions.is_empty():
			return PackedInt32Array()
		var extension := extensions[rng.randi_range(0, extensions.size() - 1)]
		regions[extension.x] = extension.y
		order[extension.y] = rank
		_note_eliminations(blocked_at, size, extension.y, bears[extension.y], rank)

	var frontier: Array[Vector2i] = []
	# Grow only through cells ruled out before the region's bear is forced.
	for cell in regions.size():
		if regions[cell] >= 0 and regions[cell] != singleton:
			_add_frontier(regions, size, cell, frontier, order, blocked_at)
	return _finish_growth(rng, regions, size, frontier, regions.size() - (2 * size - 1), order, blocked_at)


## Gives the campaign generator a solvable starting structure before mutation.
func grow_proof_candidate(rng: RandomNumberGenerator, size: int, bears: PackedInt32Array) -> PackedInt32Array:
	return _grow_regions(rng, size, bears)


## Connected candidate without the BASE proof-order construction.
func grow_candidate(rng: RandomNumberGenerator, size: int, reserve_singleton: bool) -> PackedInt32Array:
	var bears := PackedInt32Array()
	return grow_seeded_candidate(rng, size, reserve_singleton, bears)


## Writes one seed column per row into bears for generation-side boundary repair.
func grow_seeded_candidate(
	rng: RandomNumberGenerator, size: int, reserve_singleton: bool, bears: PackedInt32Array,
	extend_seeds: bool = false, plan: Dictionary = {}, seed_columns := PackedInt32Array(),
) -> PackedInt32Array:
	# Explicit anchors may originate from the same packed array used as output.
	var requested := seed_columns.duplicate()
	bears.clear()
	var regions := _seed_terrain(rng, size, bears, requested)
	if regions.is_empty():
		return regions
	var reserved := rng.randi_range(0, size - 1) if reserve_singleton else -1
	var frontier: Array[Vector2i] = []
	var unassigned := regions.size() - size
	var fixed := {}
	var swap_endpoints := {}
	if not plan.is_empty():
		swap_endpoints = Construction.endpoints(Construction.swaps(bears))
		if plan.get("chain", false):
			var motif := Construction.chain_motif(regions, bears, rng)
			if not motif.is_empty():
				plan.motif = motif
				for domino: Vector3i in [motif.first, motif.second]:
					regions[domino.y] = domino.z
					fixed[domino.z] = true
					unassigned -= 1
	if extend_seeds:
		for row in size:
			if row == reserved or fixed.has(row):
				continue
			var adjacent := Validator.orthogonal_neighbors(row * size + bears[row], size)
			var empty := PackedInt32Array()
			var preferred := PackedInt32Array()
			for cell in adjacent:
				if regions[cell] < 0:
					empty.append(cell)
					if not swap_endpoints.is_empty() and Construction.swap_penalty(regions, cell, row, swap_endpoints) == 0:
						preferred.append(cell)
			if empty.is_empty():
				return PackedInt32Array()
			if not preferred.is_empty():
				empty = preferred
			var second := empty[rng.randi_range(0, empty.size() - 1)]
			regions[second] = row
			unassigned -= 1
			_add_frontier(regions, size, second, frontier)
	for row in size:
		if row != reserved and not fixed.has(row):
			_add_frontier(regions, size, row * size + bears[row], frontier)
	return _finish_growth(rng, regions, size, frontier, unassigned, PackedInt32Array(), PackedInt32Array(), swap_endpoints)


func _seed_terrain(rng: RandomNumberGenerator, size: int, bears: PackedInt32Array,
	seed_columns := PackedInt32Array()) -> PackedInt32Array:
	var regions := PackedInt32Array()
	if not seed_columns.is_empty():
		if seed_columns.size() != size:
			return regions
		var seen := {}
		var previous := -2
		for column in seed_columns:
			if column < 0 or column >= size or seen.has(column) or absi(previous - column) < 2:
				return regions
			seen[column] = true
			previous = column
		bears.append_array(seed_columns)
	elif not _place_seed_bears(rng, size, 0, -2, bears):
		return regions
	regions.resize(size * size)
	regions.fill(-1)
	for row in size:
		regions[row * size + bears[row]] = row
	return regions


func _finish_growth(
	rng: RandomNumberGenerator, regions: PackedInt32Array, size: int,
	frontier: Array[Vector2i], unassigned: int,
	order := PackedInt32Array(), blocked_at := PackedInt32Array(),
	swap_endpoints: Dictionary = {},
) -> PackedInt32Array:
	var deferred: Array[Vector2i] = []
	while unassigned > 0:
		var prefer := not frontier.is_empty()
		var source := frontier if prefer else deferred
		if source.is_empty():
			break
		var pick := rng.randi_range(0, source.size() - 1)
		var edge := source[pick]
		source[pick] = source.back()
		source.pop_back()
		if regions[edge.x] >= 0:
			continue
		if prefer and not swap_endpoints.is_empty() and Construction.swap_penalty(regions, edge.x, edge.y, swap_endpoints):
			deferred.append(edge)
			continue
		regions[edge.x] = edge.y
		unassigned -= 1
		_add_frontier(regions, size, edge.x, frontier, order, blocked_at)
	if unassigned > 0:
		return PackedInt32Array()
	return regions


func _add_frontier(
	regions: PackedInt32Array, size: int, cell: int, frontier: Array[Vector2i],
	order := PackedInt32Array(), blocked_at := PackedInt32Array(),
) -> void:
	var region := regions[cell]
	for neighbor in Validator.orthogonal_neighbors(cell, size):
		if regions[neighbor] < 0 and (order.is_empty() or blocked_at[neighbor] < order[region]):
			frontier.append(Vector2i(neighbor, region))


func _note_eliminations(blocked_at: PackedInt32Array, size: int, row: int, column: int, rank: int) -> void:
	for index in blocked_at.size():
		@warning_ignore("integer_division")
		var row_gap := absi(index / size - row)
		var column_gap := absi(index % size - column)
		if row_gap == 0 or column_gap == 0 or (row_gap == 1 and column_gap == 1):
			blocked_at[index] = mini(blocked_at[index], rank)


# Select a valid seed permutation using a randomized search bounded by board size.
func _place_seed_bears(
	rng: RandomNumberGenerator, size: int, used_columns: int, previous_column: int,
	bears: PackedInt32Array,
) -> bool:
	if bears.size() == size:
		return true
	var columns: Array[int] = []
	for column in size:
		if not (used_columns & (1 << column)) and absi(column - previous_column) > 1:
			columns.append(column)
	while not columns.is_empty():
		var pick := rng.randi_range(0, columns.size() - 1)
		var column := columns[pick]
		columns.remove_at(pick)
		bears.append(column)
		if _place_seed_bears(rng, size, used_columns | (1 << column), column, bears):
			return true
		bears.remove_at(bears.size() - 1)
	return false

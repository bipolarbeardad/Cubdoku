extends RefCounted
## Proof-guided NIGHTMARES construction, separate from campaign assignment.

const Generation := preload("res://scripts/campaign_generation.gd")
const Validator := preload("res://scripts/puzzle_validator.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")

# Each attempt evaluates at most one boundary edit.
const ATTEMPTS := 8


static func verify(board: PackedInt32Array, side: int, stats: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	if side not in [8, 9, 10] or Validator.board_size(board) != side or not Validator.is_valid_terrain(board):
		_time_phase(stats, "structure", started)
		stats.structure += 1
		return {}
	for region in side:
		if board.count(region) < 2:
			_time_phase(stats, "structure", started)
			stats.structure += 1
			return {}
	_time_phase(stats, "structure", started)
	started = Time.get_ticks_usec()
	var solutions := Solver.search_connected_board(board, side)
	_time_phase(stats, "uniqueness", started)
	if solutions.size() != 1:
		stats.uniqueness += 1
		return {}
	started = Time.get_ticks_usec()
	var gate := Generation.assess_profile("NIGHTMARES", board)
	_time_phase(stats, "proof", started)
	if not gate.has("report") or gate.report.bears != solutions[0]:
		var reason: String = gate.get("reason", "proof_mismatch")
		stats.gates[reason] = stats.gates.get(reason, 0) + 1
		return {}
	return {"regions": board, "solution": solutions[0], "report": gate.report}


static func _time_phase(stats: Dictionary, phase: String, started: int) -> void:
	if stats.has("timing"):
		stats.timing[phase] += Time.get_ticks_usec() - started


static func new_stats() -> Dictionary:
	return {"structure": 0, "uniqueness": 0, "gates": {}, "repeated": 0,
		"fresh_exhausted": 0, "reserve_exhausted": 0}


## Ignore terrain labels and dihedral symmetries when tracking variety.
static func layout_key(board: PackedInt32Array, side: int) -> String:
	var best := ""
	for variant in 8:
		var labels := {}
		var key := ""
		for y in side:
			for x in side:
				var a := side - 1 - x if variant & 1 else x
				var b := side - 1 - y if variant & 2 else y
				var region := board[a * side + b if variant & 4 else b * side + a]
				if not labels.has(region):
					labels[region] = str(labels.size())
				key += labels[region]
		if best.is_empty() or key < best:
			best = key
	return best


## Keep the intended bears and the two-cell regions used as strong links.
static func edits(parent: Dictionary, side: int, protect_strong_links := true) -> Array[Vector2i]:
	var board: PackedInt32Array = parent.regions
	var counts := PackedInt32Array()
	counts.resize(side)
	for region in board:
		counts[region] += 1
	var protected := {}
	for step in parent.report.deductions:
		if not step.has("implication_path"):
			continue
		for group in step.groups:
			if group < side and counts[group] == 2:
				protected[group] = true
	var result: Array[Vector2i] = []
	for cell in board.size():
		if counts[board[cell]] <= 2 or parent.solution.has(cell):
			continue
		var seen := {}
		for neighbor in Validator.orthogonal_neighbors(cell, side):
			var region := board[neighbor]
			if region != board[cell] and (not protect_strong_links or not protected.has(region)) and not seen.has(region):
				seen[region] = true
				result.append(Vector2i(cell, region))
	return result


static func try_edit(parent: Dictionary, edit: Vector2i, side: int, used: Dictionary, stats: Dictionary) -> Dictionary:
	var board: PackedInt32Array = parent.regions.duplicate()
	board[edit.x] = edit.y
	var key := layout_key(board, side)
	if used.has(key):
		stats.repeated += 1
		return {}
	var result := verify(board, side, stats)
	if not result.is_empty():
		result.key = key
	return result


## A failed fresh search can draw an unused, independently verified reserve.
## The caller owns the set of previous assignments and stores the returned board.
static func request(side: int, seed_value: int, roots: Array[Dictionary],
	reserve: Array[Dictionary], used: Dictionary, stats: Dictionary) -> Dictionary:
	if side not in [8, 9, 10]:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for attempt in ATTEMPTS if not roots.is_empty() else 0:
		var parent := roots[rng.randi_range(0, roots.size() - 1)]
		if parent.regions.size() != side * side:
			continue
		var moves := edits(parent, side)
		if moves.is_empty():
			continue
		var result := try_edit(parent, moves[rng.randi_range(0, moves.size() - 1)], side, used, stats)
		if not result.is_empty():
			result.source = "fresh"
			return result
	stats.fresh_exhausted += 1
	if not reserve.is_empty():
		var offset := rng.randi_range(0, reserve.size() - 1)
		for index in reserve.size():
			var entry := reserve[(offset + index) % reserve.size()]
			if entry.regions.size() == side * side and not used.has(entry.key):
				var result := entry.duplicate(true)
				result.regions = entry.regions.duplicate()
				result.solution = entry.solution.duplicate()
				result.source = "reserve"
				return result
	stats.reserve_exhausted += 1
	return {}

extends RefCounted
## Generator-side repair. Alternate solutions guide edits but never enter the analyzer.

const Validator := preload("res://scripts/puzzle_validator.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")

var _neighbors: Array[PackedInt32Array] = []
var _size: int


func _init(size: int) -> void:
	_size = size
	for cell in size * size:
		_neighbors.append(Validator.orthogonal_neighbors(cell, size))


## Enumerates anchor-preserving moves from an independently validated two-cell-minimum root.
static func root_edits(board: PackedInt32Array, answer: PackedInt32Array, side: int) -> Array[Vector2i]:
	var counts := PackedInt32Array()
	counts.resize(side)
	for region in board:
		counts[region] += 1
	var moves: Array[Vector2i] = []
	for cell in board.size():
		if counts[board[cell]] <= 2 or answer.has(cell):
			continue
		var seen := {}
		for neighbor in Validator.orthogonal_neighbors(cell, side):
			var target := board[neighbor]
			if target != board[cell] and not seen.has(target):
				seen[target] = true
				moves.append(Vector2i(cell, target))
	return moves


## Removes a proof seed's singleton without moving either region's intended bear.
func expand_singleton(board: PackedInt32Array, anchors: PackedInt32Array, rng: RandomNumberGenerator) -> bool:
	for id in _size:
		if board.count(id) != 1:
			continue
		var donors := PackedInt32Array()
		for cell in _neighbors[anchors[id]]:
			var donor := board[cell]
			var count := board.count(donor)
			if cell != anchors[donor] and count > 2 and _donor_connected(board, cell, count):
				donors.append(cell)
		if donors.is_empty():
			return false
		board[donors[rng.randi_range(0, donors.size() - 1)]] = id
	return true


func apply_move(
	board: PackedInt32Array, anchors: PackedInt32Array, alternate: PackedInt32Array,
	rng: RandomNumberGenerator, previous_cell: int, earlier_proof: Dictionary,
) -> int:
	var counts := PackedInt32Array()
	counts.resize(_size)
	for id in board:
		counts[id] += 1
	var guided: Array[Vector2i] = []
	var disrupt: Array[Vector2i] = []
	var others: Array[Vector2i] = []
	var pressure := _proof_pressure(board, earlier_proof)
	var occupied := {}
	for bear in alternate:
		occupied[board[bear]] = true
	for cell in board.size():
		var source := board[cell]
		if cell == previous_cell or counts[source] <= 2 or anchors[source] == cell:
			continue
		var targets := 0
		for neighbor in _neighbors[cell]:
			var target := board[neighbor]
			if target == source or counts[target] == 1 or (targets & (1 << target)):
				continue
			targets |= 1 << target
			if alternate.has(cell) and occupied.has(target):
				guided.append(Vector2i(cell, target))
			elif pressure.has(Vector2i(cell, target)):
				disrupt.append(Vector2i(cell, target))
			else:
				others.append(Vector2i(cell, target))
	for pool in [guided, disrupt, others]:
		for trial in mini(pool.size(), 8):
			var index := rng.randi_range(0, pool.size() - 1)
			var move: Vector2i = pool[index]
			pool[index] = pool.back()
			pool.pop_back()
			if _donor_connected(board, move.x, counts[board[move.x]]):
				board[move.x] = move.y
				return move.x
	return -1


## Select a boundary edit against a bounded history of full alternate arrangements.
func apply_scored_move(
	board: PackedInt32Array, anchors: PackedInt32Array, witnesses: Array[PackedInt32Array],
	rng: RandomNumberGenerator, previous_cell: int, earlier_proof: Dictionary, plan: Dictionary = {},
	preserve_advanced: bool = false,
) -> int:
	if witnesses.is_empty() and plan.is_empty() and not preserve_advanced:
		return apply_move(board, anchors, PackedInt32Array(), rng, previous_cell, earlier_proof)
	var counts := PackedInt32Array()
	counts.resize(_size)
	for id in board:
		counts[id] += 1
	var witness_counts: Array[PackedInt32Array] = []
	var occupied: Array[PackedInt32Array] = []
	for cell in board.size():
		occupied.append(PackedInt32Array())
	var collisions := PackedInt32Array()
	for index in witnesses.size():
		var seen := PackedInt32Array()
		seen.resize(_size)
		var overlap := 0
		for bear in witnesses[index]:
			var region := board[bear]
			overlap += int(seen[region] > 0)
			seen[region] += 1
			occupied[bear].append(index)
		witness_counts.append(seen)
		collisions.append(overlap)
	var scores := {}
	var pressure := _proof_pressure(board, earlier_proof)
	if not plan.is_empty():
		pressure.merge(_advanced_pressure(board, earlier_proof))
	if preserve_advanced:
		pressure.merge(_shortcut_pressure(board, earlier_proof))
	var fixed := {}
	if plan.has("motif"):
		fixed[plan.motif.first.z] = true
		fixed[plan.motif.second.z] = true
	for cell in board.size():
		var source := board[cell]
		if cell == previous_cell or counts[source] <= 2 or anchors[source] == cell:
			continue
		var targets := 0
		for neighbor in _neighbors[cell]:
			var target := board[neighbor]
			if target == source or counts[target] == 1 or (targets & (1 << target)):
				continue
			if preserve_advanced and fixed.has(target):
				continue
			targets |= 1 << target
			var move := Vector2i(cell, target)
			var score := int(pressure.has(move)) - 3 * int(fixed.has(target))
			for index in occupied[cell]:
				var seen := witness_counts[index]
				var after := collisions[index] + int(seen[source] == 1) - int(seen[target] == 0)
				if collisions[index] == 0 and after > 0:
					score += 4
				elif collisions[index] > 0 and after == 0:
					score -= 6
			if not scores.has(score):
				scores[score] = []
			scores[score].append(move)
	var ranking := scores.keys()
	ranking.sort()
	ranking.reverse()
	var trials := 0
	for score in ranking:
		var pool: Array = scores[score]
		while not pool.is_empty() and trials < 16:
			var index := rng.randi_range(0, pool.size() - 1)
			var move: Vector2i = pool[index]
			pool[index] = pool.back()
			pool.pop_back()
			trials += 1
			if _donor_connected(board, move.x, counts[board[move.x]]):
				board[move.x] = move.y
				return move.x
	return -1


## Add an alternative that breaks an early shared conflict or reservation in a simpler proof.
func _shortcut_pressure(board: PackedInt32Array, proof: Dictionary) -> Dictionary:
	var moves := {}
	var eliminated := {}
	for step: Dictionary in proof.get("deductions", []):
		var targets: PackedInt32Array = step.get("target_groups", PackedInt32Array())
		if step.technique in [Analyzer.Technique.COMMON_CONFLICT, Analyzer.Technique.CANDIDATE_PAIR,
				Analyzer.Technique.GROUP_TRIPLE]:
			for region: int in step.groups:
				if region >= _size:
					continue
				for cell in board.size():
					if board[cell] == region or eliminated.has(cell):
						continue
					if not Array(_neighbors[cell]).any(func(neighbor: int) -> bool: return board[neighbor] == region):
						continue
					if targets.is_empty():
						for candidate in step.eliminated:
							var conflict := Analyzer._conflict_mask(board, _size, cell, candidate)
							# The edit replaces the existing region conflict.
							if (conflict == 0 or conflict == 4) and board[candidate] != region:
								moves[Vector2i(cell, region)] = true
								break
					elif not Array(targets).any(func(group: int) -> bool: return _in_group(board, cell, group)):
						moves[Vector2i(cell, region)] = true
			if not moves.is_empty():
				return moves
		for cell in step.eliminated:
			eliminated[cell] = true
	return moves

## Add live alternatives near a source region of an easier triple proof.
func _advanced_pressure(board: PackedInt32Array, proof: Dictionary) -> Dictionary:
	var changes := {}
	var eliminated := {}
	for step: Dictionary in proof.get("deductions", []):
		if step.groups.size() == 3:
			for source: int in step.groups:
				if source >= _size:
					continue
				for cell in board.size():
					if board[cell] == source or eliminated.has(cell):
						continue
					for neighbor in _neighbors[cell]:
						if board[neighbor] == source:
							changes[Vector2i(cell, source)] = true
							break
			if not changes.is_empty():
				return changes
		for cell in step.eliminated:
			eliminated[cell] = true
	return changes


## Prefer edits that break an early restriction of a proof below the target.
func _proof_pressure(board: PackedInt32Array, proof: Dictionary) -> Dictionary:
	var moves := {}
	var eliminated := {}
	var measured := 0
	for step: Dictionary in proof.get("deductions", []):
		var targets: PackedInt32Array = step.get("target_groups", PackedInt32Array())
		if step.groups.size() == 1 and targets.size() == 1:
			var source: int = step.groups[0]
			var target := targets[0]
			if source < _size:
				for cell in board.size():
					if board[cell] == source or eliminated.has(cell) or _in_group(board, cell, target):
						continue
					for neighbor in _neighbors[cell]:
						if board[neighbor] == source:
							moves[Vector2i(cell, source)] = true
							break
			elif target < _size:
				for cell in step.cells:
					for neighbor in _neighbors[cell]:
						if board[neighbor] != target:
							moves[Vector2i(cell, board[neighbor])] = true
			measured += 1
			if measured == 3:
				break
		for cell in step.eliminated:
			eliminated[cell] = true
	return moves


func _in_group(board: PackedInt32Array, cell: int, group: int) -> bool:
	if group < _size:
		return board[cell] == group
	if group < 2 * _size:
		@warning_ignore("integer_division")
		return cell / _size == group - _size
	return cell % _size == group - 2 * _size


func _donor_connected(board: PackedInt32Array, removed: int, prior_count: int) -> bool:
	var id := board[removed]
	var same := PackedInt32Array()
	for neighbor in _neighbors[removed]:
		if board[neighbor] == id:
			same.append(neighbor)
	if same.size() == 1:
		return true
	var seen := {removed: true, same[0]: true}
	var stack := PackedInt32Array([same[0]])
	while not stack.is_empty():
		var current := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		for neighbor in _neighbors[current]:
			if board[neighbor] == id and not seen.has(neighbor):
				seen[neighbor] = true
				stack.append(neighbor)
	return seen.size() == prior_count

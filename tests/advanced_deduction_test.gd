extends SceneTree

const Advanced := preload("res://scripts/difficulty_advanced_patterns.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Generation := preload("res://scripts/campaign_generation.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")

var _failures := 0


func _initialize() -> void:
	_test_group_triple()
	_test_adjacency_triple()
	_test_chain()
	_test_generated_fixtures()
	_test_ten_cell_engine()
	print("Advanced deduction test failures: %d" % _failures)
	quit(0 if _failures == 0 else 1)


func _test_group_triple() -> void:
	var groups := _groups(5, [[0, 2], [7, 9], [10, 14], [15, 16, 17, 19], [21, 23]])
	var moves := Advanced.group_triples(groups, 5, Analyzer.Technique.GROUP_TRIPLE)
	_expect(moves.any(func(move: Dictionary) -> bool:
		return (move.groups == [5, 6, 7] and move.target_groups == PackedInt32Array([10, 12, 14])
			and move.eliminated == PackedInt32Array([15, 17, 19]))
	), "Three rows reserve three columns")


func _test_adjacency_triple() -> void:
	var groups := _groups(5, [[0, 1], [7, 8], [10, 11], [15, 16], [21, 24]])
	var conflicts: Array[PackedInt32Array] = []
	var regions := PackedInt32Array()
	for cell in 25:
		@warning_ignore("integer_division")
		regions.append(cell / 5)
	for first in 25:
		var adjacent := PackedInt32Array()
		for second in 25:
			if first != second and Analyzer._conflict_mask(regions, 5, first, second):
				adjacent.append(second)
		conflicts.append(adjacent)
	var moves := Advanced.adjacency_triples(groups, conflicts, 5, Analyzer.Technique.ADJACENCY_TRIPLE)
	_expect(moves.any(func(move: Dictionary) -> bool:
		return (move.groups == [5, 6, 7] and move.eliminated == PackedInt32Array([7])
			and move.compatible_triples == [Vector3i(0, 8, 11), Vector3i(1, 8, 10)])
	), "A candidate with pairwise support can lack any compatible triple")


func _test_chain() -> void:
	var groups: Array[PackedInt32Array] = [PackedInt32Array([1, 2]), PackedInt32Array([3, 4])]
	var conflicts: Array[PackedInt32Array] = [PackedInt32Array([1, 4]), PackedInt32Array([0]),
		PackedInt32Array([3]), PackedInt32Array([2]), PackedInt32Array([0])]
	var moves := Advanced.implication_chains(groups, conflicts, PackedByteArray([1, 1, 1, 1, 1]), Analyzer.Technique.IMPLICATION_CHAIN)
	_expect(moves.any(func(move: Dictionary) -> bool:
		return move.eliminated == PackedInt32Array([0]) and move.implication_path == PackedInt32Array([0, 3, 4, 7, 8, 1])
	), "Record a five-link path from a bear to its own exclusion")
	groups = [PackedInt32Array([1, 2])]
	conflicts = [PackedInt32Array([1, 2]), PackedInt32Array([0]), PackedInt32Array([0])]
	_expect(Advanced.implication_chains(groups, conflicts, PackedByteArray([1, 1, 1]), Analyzer.Technique.IMPLICATION_CHAIN).is_empty(),
		"A three-link shared conflict does not qualify as an advanced chain")


func _test_generated_fixtures() -> void:
	var generation := Generation.new()
	var extra := generation.generate({"difficulty": "EXTRA HARD", "size": 9, "locked_bear": false}, 51402, Generation.HIGHER_BUDGET, true, false)
	_expect(extra.status == "success", "Reproduce the 9×9 EXTRA HARD stage 1402")
	if extra.status == "success":
		_expect(Analyzer.analyze_with_families(extra.regions, Generation.CLASSIC).status == Analyzer.Status.STUCK,
			"The 9×9 fixture needs more than the classic techniques")
		_expect(extra.report.technique_counts.has(Analyzer.Technique.GROUP_TRIPLE), "The fixture uses a three-group deduction")
	var nightmare := generation.generate({"difficulty": "NIGHTMARES", "size": 8, "locked_bear": false}, 52560, Generation.HIGHER_BUDGET, true, false)
	_expect(nightmare.status == "success", "Reproduce the NIGHTMARES stage 2560")
	if nightmare.status == "success":
		_test_proof_continuation(nightmare.regions)
		var solutions := Solver.find_solutions(nightmare.regions)
		_expect(solutions == [nightmare.solution] and nightmare.report.bears == nightmare.solution,
			"The NIGHTMARES proof agrees with the independent solver")
		for mask in range((Generation.CLASSIC | Generation.T) + 1):
			_expect(Analyzer.analyze_with_families(nightmare.regions, mask).status == Analyzer.Status.STUCK,
				"The NIGHTMARES fixture stalls without implications")
		var groups := Analyzer._make_groups(nightmare.regions, 8)
		var eliminated := {}
		var chain_count := 0
		for step: Dictionary in nightmare.report.deductions:
			if step.technique == Analyzer.Technique.IMPLICATION_CHAIN:
				_verify_chain(step, nightmare.regions, groups, eliminated)
				chain_count += 1
			for cell in step.eliminated:
				_expect(not nightmare.solution.has(cell), "No proof step removes a solution bear")
				eliminated[cell] = true
		_expect(chain_count > 0, "The NIGHTMARES proof includes an explicit implication chain")


func _test_proof_continuation(board: PackedInt32Array) -> void:
	var graph: Array[PackedInt32Array] = []
	for mask in range(Analyzer.EXTENDED_FAMILIES + 1):
		_expect(Analyzer.analyze_with_families(board, mask, graph) == Analyzer.analyze_with_families(board, mask),
			"Reusing the layout conflict graph preserves the trace under every mask")
	for masks in [[0, Generation.R], [Generation.R, Generation.P], [Generation.R, Generation.C],
			[Generation.R | Generation.P, Generation.C], [Generation.CLASSIC, Generation.T],
			[Generation.CLASSIC | Generation.T, Generation.I]]:
		var prefix := Analyzer.analyze_with_families(board, masks[0])
		_expect(prefix.status == Analyzer.Status.STUCK, "Restricted fixture produces a stalled prefix")
		if prefix.status == Analyzer.Status.STUCK:
			var resumed := Analyzer.extend_stalled_proof(board, prefix, masks[0], masks[1])
			_expect(resumed == Analyzer.analyze_with_families(board, masks[0] | masks[1]),
				"Resuming preserves the full deduction trace and metrics")
			_expect(prefix == Analyzer.analyze_with_families(board, masks[0]), "Resuming leaves the prefix intact")


func _verify_chain(step: Dictionary, regions: PackedInt32Array, groups: Array[PackedInt32Array], eliminated: Dictionary) -> void:
	var path: PackedInt32Array = step.implication_path
	_expect(path.size() >= 5 and path[0] == 2 * step.eliminated[0] and path[-1] == path[0] + 1,
		"The path proves its starting candidate false")
	for index in range(1, path.size()):
		var from := path[index - 1]
		var to := path[index]
		var a := from >> 1
		var b := to >> 1
		_expect(not eliminated.has(a) and not eliminated.has(b), "Implication uses live candidates")
		if (from & 1) == 0:
			_expect((to & 1) == 1 and Analyzer._conflict_mask(regions, 8, a, b) != 0, "Positive link uses a bear conflict")
		else:
			var witnessed := false
			for group in groups:
				if group.has(a) and group.has(b):
					var live := 0
					for member in group:
						live += int(not eliminated.has(member))
					witnessed = witnessed or live == 2
			_expect((to & 1) == 0 and witnessed, "Negative link uses a group with exactly two live candidates")


func _test_ten_cell_engine() -> void:
	# Nine isolated seed cells leave one connected remainder. This tests engine size,
	# independently of the NIGHTMARES profile's zero-singleton requirement.
	var columns := [0, 2, 4, 6, 8, 1, 3, 5, 7, 9]
	var board := PackedInt32Array()
	board.resize(100)
	board.fill(9)
	var bears := PackedInt32Array()
	for row in 10:
		var cell: int = row * 10 + columns[row]
		board[cell] = row
		bears.append(cell)
	var report := Analyzer.analyze(board)
	_expect(Solver.find_solutions(board) == [bears] and report.status == Analyzer.Status.SOLVED and report.bears == bears,
		"The 10×10 engine validates a unique constructive proof")


func _groups(side: int, rows: Array) -> Array[PackedInt32Array]:
	var groups: Array[PackedInt32Array] = []
	for index in side * 3:
		groups.append(PackedInt32Array())
	for row in side:
		for cell in rows[row]:
			groups[row].append(cell) # Region stripes for these local candidate fixtures.
			groups[side + row].append(cell)
			groups[2 * side + cell % side].append(cell)
	return groups


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

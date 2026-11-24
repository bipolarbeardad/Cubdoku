extends SceneTree

const Plan := preload("res://scripts/construction_plan.gd")
const Generator := preload("res://scripts/puzzle_generator.gd")
const Validator := preload("res://scripts/puzzle_validator.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const Generation := preload("res://scripts/campaign_generation.gd")
const Schedule := preload("res://scripts/campaign_schedule.gd")

var _failures := 0

func _initialize() -> void:
	_test_swaps()
	_test_cycle_partitions()
	_test_chain_motif()
	_compare_construction()
	_test_ten_cell_profile()
	print("Construction plan test failures: %d" % _failures)
	quit(0 if _failures == 0 else 1)

func _test_swaps() -> void:
	var columns := PackedInt32Array([0, 2, 4, 1, 3, 5])
	var size := columns.size()
	var anchors := PackedInt32Array()
	var stripes := PackedInt32Array()
	for row in size:
		anchors.append(row * size + columns[row])
		for column in size:
			stripes.append(row)
	var pairs := Plan.swaps(columns)
	var witnesses := Plan.live_witnesses(stripes, anchors, pairs)
	var independently_counted := 0
	for first in size:
		for second in range(first + 1, size):
			var permutation := columns.duplicate()
			permutation[first] = columns[second]
			permutation[second] = columns[first]
			var legal := true
			for row in range(1, size):
				legal = legal and absi(permutation[row] - permutation[row - 1]) > 1
			independently_counted += int(legal)
	_expect(not witnesses.is_empty() and witnesses.size() == independently_counted, "Detect all legal two-row swaps")
	var pair: Vector4i = pairs[0]
	var part := stripes.duplicate()
	part[pair.x] = -1
	var ends := Plan.endpoints(pairs)
	_expect(Plan.swap_penalty(part, pair.x, pair.z, ends) == 1, "Detect a growth edge that completes a swap")
	_expect(Plan.swap_penalty(part, pair.x, pair.w, ends) == 0, "Permit a growth edge that breaks the witness")


func _test_cycle_partitions() -> void:
	var anchors := PackedInt32Array([0, 5, 10, 15])
	_expect(Generation._cycle_pattern(anchors, PackedInt32Array([1, 6, 8, 15]), 4) == "3",
		"Count a single three-row rotation")
	_expect(Generation._cycle_pattern(anchors, PackedInt32Array([1, 4, 11, 14]), 4) == "2+2",
		"Distinguish independent swaps from a four-row cycle")
	_expect(Generation._cycle_pattern(anchors, PackedInt32Array([1, 6, 11, 12]), 4) == "4",
		"Count a single four-row rotation")

func _test_chain_motif() -> void:
	var generator := Generator.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7429
	for attempt in 40:
		var plan := {"chain": true}
		var columns := PackedInt32Array()
		var board := generator.grow_seeded_candidate(rng, 10, false, columns, true, plan)
		if board.is_empty() or not plan.has("motif"):
			continue
		_expect(Validator.is_valid_terrain(board), "A planned 10×10 seed remains structurally valid")
		var path: Array = plan.motif.path
		for index in [1, 3, 5]:
			_expect(Analyzer._conflict_mask(board, 10, path[index - 1], path[index]) != 0, "Record a visible conflict link")
		for index in [2, 4]:
			var region := board[path[index]]
			_expect(board[path[index - 1]] == region and board.count(region) == 2, "Reserve an exact two-cell group for the strong link")
		return
	_expect(false, "Produce a valid planned implication motif within the test budget")

func _compare_construction() -> void:
	var generator := Generator.new()
	for side in [6, 8, 10]:
		var counts := PackedInt32Array([0, 0, 0, 0, 0, 0])
		var rng := RandomNumberGenerator.new()
		for seed_value in 40:
			var reference := PackedInt32Array()
			for mode in 2:
				rng.seed = 27500 + seed_value
				var columns := PackedInt32Array()
				var board := generator.grow_seeded_candidate(rng, side, false, columns, true, {} if mode == 0 else {"chain": false})
				if mode == 0:
					reference = columns.duplicate()
				else:
					_expect(columns == reference, "Compare the same intended bear placement")
				if board.is_empty():
					continue
				_expect(Validator.is_valid_terrain(board), "Construct a connected candidate in either mode")
				counts[mode] += 1
				var anchors := PackedInt32Array()
				for row in side:
					anchors.append(row * side + columns[row])
				counts[2 + mode] += Plan.live_witnesses(board, anchors, Plan.swaps(columns)).size()
				counts[4 + mode] += int(Solver.find_solutions(board, 12).size() == 12)
		print("side %d, ordinary/planned: valid %d/%d, surviving swaps %d/%d, capped ambiguity %d/%d" % [
			side, counts[0], counts[1], counts[2], counts[3], counts[4], counts[5],
		])

func _test_ten_cell_profile() -> void:
	var request := Schedule.new().request(161)
	var result := Generation.new().generate(request, 50161)
	_expect(request.size == 10 and request.difficulty == "NIGHTMARES" and result.status == "success",
		"Reproduce the planned 10×10 NIGHTMARES candidate")
	if result.status != "success":
		return
	_expect(Solver.find_solutions(result.regions) == [result.solution], "The nightmare has exactly one solution")
	for mask in (Analyzer.ALL_FAMILIES | Analyzer.Family.TRIPLES) + 1:
		_expect(Analyzer.analyze_with_families(result.regions, mask).status != Analyzer.Status.SOLVED,
			"The 10×10 candidate stalls under every chain-free subset")
	_expect(result.report.bears == result.solution and result.report.technique_counts.has(Analyzer.Technique.IMPLICATION_CHAIN),
		"The layout-only proof uses a chain and agrees with the solver")

func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

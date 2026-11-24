extends SceneTree
## Experimental deductions run only after the production proof stalls.

const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Generator := preload("res://scripts/puzzle_generator.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const Hall := preload("res://scripts/nightmares_hall_reasoning.gd")
const Repair := preload("res://scripts/candidate_boundary_repair.gd")
const FAMILIES := Analyzer.EXTENDED_FAMILIES
const Elimination := preload("res://scripts/nightmares_elimination.gd")
const STARTS_PER_SIZE := 1024

var _failures := 0
var _probe_count := 0
var _reasoning := Elimination.new()


func _initialize() -> void:
	var groups: Array[PackedInt32Array] = []
	for group in [[0, 5], [6, 11], [12, 17], [3, 18], [4, 24]]:
		groups.append(PackedInt32Array(group))
	var quartet := _quartet(groups, 5)
	_check(not quartet.is_empty() and quartet[0].eliminated == PackedInt32Array([4]),
		"Four regions reserve four rows without a smaller confined subset")
	for region in groups.size():
		for index in groups[region].size():
			var cell := groups[region][index]
			@warning_ignore("integer_division")
			groups[region][index] = (cell % 5) * 5 + cell / 5
	quartet = _quartet(groups, 5)
	_check(not quartet.is_empty() and quartet[0].column_reservation
		and quartet[0].eliminated == PackedInt32Array([20]), "The transposed fixture reserves four columns")
	var five: Array[PackedInt32Array] = []
	for region in 5:
		five.append(PackedInt32Array([region * 6 + region, ((region + 1) % 5) * 6 + region]))
	five.append(PackedInt32Array([5, 35]))
	var reservation := Hall.moves(five, PackedInt32Array(), 6, PackedByteArray())
	_check(not reservation.is_empty() and reservation[0].groups.size() == 5
		and reservation[0].eliminated == PackedInt32Array([5]), "Five cyclic regions consume five lines")
	_test_contradiction()

	var generator := Generator.new()
	for size in range(5, 11):
		var repair := Repair.new(size)
		var counts := {"unique": 0, "old_solved": 0, "quartet_solved": 0,
			"contradiction_solved": 0, "combined_solved": 0}
		var probes := Vector2i.ZERO
		for seed_offset in STARTS_PER_SIZE:
			var rng := RandomNumberGenerator.new()
			rng.seed = size * 10000 + seed_offset
			var anchors := PackedInt32Array()
			var board := generator.grow_proof_candidate(rng, size, anchors)
			for row in anchors.size():
				anchors[row] += row * size
			if board.is_empty() or not repair.expand_singleton(board, anchors, rng):
				continue
			var previous := -1
			for edit in 5:
				previous = repair.apply_move(board, anchors, PackedInt32Array(), rng, previous, {})
				if previous < 0:
					break
			var solutions := Solver.find_solutions(board)
			if solutions.size() != 1:
				continue
			counts.unique += 1
			var baseline := Analyzer.analyze_with_families(board, FAMILIES)
			if baseline.status == Analyzer.Status.SOLVED:
				counts.old_solved += 1
				continue
			_check(baseline.status == Analyzer.Status.STUCK, "A unique fixture stalls or solves")
			var quartet_report := _continue(board, baseline, _quartet_only)
			var row_major := _continue(board, baseline, _trial.bind(false, false))
			var old_probes := _probe_count
			var tight_first := _continue(board, baseline, _trial.bind(true, false))
			probes += Vector2i(old_probes, _probe_count)
			var combined := _continue(board, baseline, _trial.bind(true, true))
			for report in [quartet_report, row_major, tight_first, combined]:
				for step in report.deductions:
					for cell in step.eliminated:
						_check(not solutions[0].has(cell), "A deduction must preserve the independently verified solution")
				if report.status == Analyzer.Status.SOLVED:
					_check(report.bears == solutions[0], "Experimental proof agrees with the independent solution")
			counts.quartet_solved += int(quartet_report.status == Analyzer.Status.SOLVED)
			counts.contradiction_solved += int(tight_first.status == Analyzer.Status.SOLVED)
			counts.combined_solved += int(combined.status == Analyzer.Status.SOLVED)
			if combined.status == Analyzer.Status.SOLVED and counts.combined_solved == 1:
				print("size ", size, " witness seed ", rng.seed, " board ", board)
		print(size, "x", size, " ", counts, " trial probes row-major/tight-first ", probes)
	print("Logical audit failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _continue(board: PackedInt32Array, prefix: Dictionary, rule: Callable) -> Dictionary:
	_probe_count = 0
	_reasoning.probes = 0
	return Analyzer._analyze(board, FAMILIES, prefix, [], rule)


func _test_contradiction() -> void:
	var board := PackedInt32Array()
	for digit in "1100010003112334123344223":
		board.append(int(digit))
	var baseline := Analyzer.analyze_with_families(board, FAMILIES)
	var solution := Solver.find_solutions(board)
	_check(solution.size() == 1 and baseline.status == Analyzer.Status.STUCK, "Calibration fixture is unique and stalls")
	if baseline.status != Analyzer.Status.STUCK or solution.size() != 1:
		return
	_check(_continue(board, baseline, _quartet_only).status == Analyzer.Status.STUCK,
		"The calibration fixture still stalls with quartet confinement")
	for tight_first in [false, true]:
		var report := _continue(board, baseline, _trial.bind(tight_first, false))
		_check(report.status == Analyzer.Status.SOLVED and report.bears == solution[0], "Bounded contradiction closes the fixture")
		_check(report == _continue(board, baseline, _trial.bind(tight_first, false)), "Contradiction trace is reproducible")
		print("Calibration fixture, tight first ", tight_first, " probes ", _probe_count)
		for step in report.deductions.slice(baseline.total_steps):
			for cell in step.eliminated:
				_check(not solution[0].has(cell), "Fixture proof keeps all independently verified bears")
			if step.technique == Analyzer.Technique.BOUNDED_CONTRADICTION:
				var expected := PackedInt32Array([1, 8] if tight_first else [0, 21, 12])
				_check(step.hypothetical_bears == expected and step.groups == [7 if tight_first else 0]
					and step.eliminated == PackedInt32Array([expected[0]]) and step.confirmed.is_empty(),
					"Recorded hypothetical path proves only the assumed candidate impossible")
				print("  branch ", step.hypothetical_bears, " empties group ", step.groups[0])


func _quartet_only(groups: Array[PackedInt32Array], _board: PackedInt32Array,
	size: int, _candidates: PackedByteArray) -> Array[Dictionary]:
	return _quartet(groups, size)


func _quartet(groups: Array[PackedInt32Array], size: int) -> Array[Dictionary]:
	return Hall.moves(groups, PackedInt32Array(), size, PackedByteArray())


func _trial(groups: Array[PackedInt32Array], board: PackedInt32Array, size: int,
	candidates: PackedByteArray, tight_first: bool, include_quartet: bool) -> Array[Dictionary]:
	var move := _reasoning.moves(groups, board, size, candidates, tight_first, include_quartet)
	_probe_count = _reasoning.probes
	return move


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)

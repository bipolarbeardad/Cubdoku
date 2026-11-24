extends SceneTree
## Run with godot --headless --path . --script res://tests/prototype_test.gd.

const Validator := preload("res://scripts/puzzle_validator.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const Generator := preload("res://scripts/puzzle_generator.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const PuzzleAnalysis := preload("res://scripts/puzzle_analysis.gd")
const Difficulty := preload("res://scripts/puzzle_difficulty.gd")
const GameState := preload("res://scripts/puzzle_game_state.gd")
const Catalog := preload("res://scripts/campaign_catalog.gd")
const Session := preload("res://scripts/puzzle_session.gd")
const Save := preload("res://scripts/campaign_save.gd")
const BoardScene := preload("res://scenes/puzzle_board.tscn")
const BoardTerrain := preload("res://scripts/board_terrain.gd")
const TerrainFixture := preload("res://tests/terrain_visual_test.gd")
const FreePlay := preload("res://scripts/free_play_generation.gd")
const BATCH_COUNT := 1024

var _failures := 0
var _test_profiles: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_solver()
	_test_analyzer_expansion()
	_test_difficulty_sizes()
	_test_game_state()
	_test_puzzle_modes()
	_test_legacy_assignment()
	_test_unsupported_save()
	for size in range(Validator.SIZE, Validator.MAX_SIZE + 1):
		_test_batch(size)
	_test_terrain_mapping()
	_test_free_play_reserve()
	await _test_scene()
	for path in _test_profiles:
		DirAccess.remove_absolute(path)
		if FileAccess.file_exists(path + ".tmp"):
			DirAccess.remove_absolute(path + ".tmp")
	print("Prototype test failures: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_solver() -> void:
	var missing_region := PackedInt32Array([
		0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2,
	])
	var disconnected := PackedInt32Array([
		0, 1, 1, 1, 2, 0, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
	])
	var impossible := PackedInt32Array([
		0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
	])
	var ambiguous := PackedInt32Array([
		0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
	])
	_expect(not Validator.is_valid_terrain(PackedInt32Array()), "Reject an empty board")
	_expect(not Validator.is_valid_terrain(missing_region), "Reject a missing terrain")
	_expect(not Validator.is_valid_terrain(disconnected), "Reject diagonal-only terrain contact")
	_expect(Validator.is_valid_terrain(impossible), "Recognize four connected regions")
	_expect(Solver.find_solutions(impossible).is_empty(), "Detect a puzzle with zero solutions")
	_expect(Solver.find_solutions(ambiguous).size() == 2, "Detect a puzzle with two solutions")
	_expect(Analyzer.analyze(disconnected).status == Analyzer.Status.INVALID, "Reject disconnected terrain in the analyzer")
	var conflicting_singletons := PackedInt32Array([
		0, 1, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3,
	])
	_expect(Analyzer.analyze(conflicting_singletons).status == Analyzer.Status.CONTRADICTION, "Detect two forced bears in the same row")
	var legacy: PackedInt32Array = Catalog.load_path(1).regions
	_expect(Solver.find_solutions(legacy).size() == 1, "Legacy fixture is uniquely solvable")
	var stalled := Analyzer.analyze(legacy)
	_expect(stalled.status == Analyzer.Status.STUCK and stalled.deductions.is_empty(), "Report a unique board with no basic opening as stuck")
	_expect(not Difficulty.matches(Difficulty.BASE, legacy), "Reject a board without a singleton for BASE")
	var two_singletons := PackedInt32Array([
		0, 0, 0, 0, 2, 1, 0, 2, 2, 2, 3, 3, 3, 2, 2,
		3, 3, 3, 2, 2, 3, 3, 3, 4, 2,
	])
	_expect(Solver.find_solutions(two_singletons).size() == 1, "The multi-singleton fixture has one solution")
	_expect(Analyzer.analyze(two_singletons).status == Analyzer.Status.SOLVED, "The multi-singleton fixture is logically solvable")
	_expect(not Difficulty.matches(Difficulty.BASE, two_singletons), "Reject a solvable board with two singleton regions for BASE")
	var row_single := PackedInt32Array([1, 0, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 2, 1, 3, 3])
	var column_single := PackedInt32Array([0, 0, 0, 1, 0, 0, 3, 1, 2, 3, 3, 1, 3, 3, 3, 1])
	_expect(Analyzer.analyze(row_single).deductions.any(func(step: Dictionary) -> bool:
		return step.technique == Analyzer.Technique.ROW_SINGLE
	), "Recognize a forced row placement")
	_expect(Analyzer.analyze(column_single).deductions.any(func(step: Dictionary) -> bool:
		return step.technique == Analyzer.Technique.COLUMN_SINGLE
	), "Recognize a forced column placement")

	var generator := Generator.new()
	var fallback := generator.generate(0, 0)
	_expect(generator.used_fallback, "Use fallback when the attempt budget is zero")
	var solutions := Solver.find_solutions(fallback)
	_expect(solutions == [PackedInt32Array([1, 7, 8, 14])], "Verify the fallback solution")
	_expect(Difficulty.matches(Difficulty.BASE, fallback), "Fallback meets the new BASE rules")
	var first: Dictionary = Analyzer.analyze(fallback).deductions[0]
	_expect(first.technique == Analyzer.Technique.SINGLE_CELL_REGION and first.cell == 1, "Deduce the singleton bear immediately")
	_expect(first.eliminated.has(4) and first.eliminated.has(6), "Eliminate diagonally adjacent cells")
	for tag: String in Difficulty.THRESHOLDS:
		if tag != Difficulty.BASE:
			_expect(generator.generate(0, 0, tag).is_empty() and not generator.used_fallback, "Reject uncalibrated difficulty %s" % tag)
	_expect(generator.generate(1234) == generator.generate(1234), "Generation is deterministic")
	for size in [3, 8]:
		_expect(generator.generate(0, 0, Difficulty.BASE, size).is_empty(), "Reject unsupported board size")


func _test_analyzer_expansion() -> void:
	var restrictions := PackedInt32Array([1, 0, 0, 2, 1, 1, 1, 2, 3, 1, 1, 2, 3, 3, 3, 3])
	var column := PackedInt32Array([1, 1, 0, 0, 1, 2, 0, 0, 1, 2, 2, 2, 1, 3, 3, 2])
	var pair := PackedInt32Array([0, 0, 0, 1, 0, 1, 1, 1, 2, 2, 3, 1, 2, 2, 3, 3])
	var stuck := PackedInt32Array([
		1, 1, 0, 0, 0,
		1, 0, 0, 0, 3,
		1, 1, 2, 3, 3,
		4, 1, 2, 3, 3,
		4, 4, 2, 2, 3,
	])
	_expect(Analyzer.analyze(restrictions).status == Analyzer.Status.STUCK, "BASE cannot use advanced moves")
	var report := Analyzer.analyze(restrictions, true)
	_expect(report == Analyzer.analyze(restrictions, true), "Advanced deduction traces are reproducible")
	_expect(report.highest_technique == Analyzer.Technique.COMMON_CONFLICT and report.highest_complexity == 4, "Identify the highest technique used")
	_expect(report.total_steps == report.rounds and report.rounds == report.deductions.size(), "Report the number of applied rounds")
	_expect(report.choices_per_round[0] == 3 and report.deductions[2].chain_depth == 3, "Measure distinct choices and a dependent chain")
	_expect(report.longest_chain >= 3 and report.longest_chain <= report.rounds, "Bound the longest chain by the trace length")
	_expect(report.forced_placements == 4 and report.candidate_eliminations == 12, "Count confirmed bears and unique eliminations")
	_expect(report.deductions[0].cells == PackedInt32Array([1, 2]), "Record visible cells that support a deduction")
	_expect(report.deductions[0].confirmed.is_empty(), "Elimination steps do not claim confirmed bears")
	_expect(report.deductions[0].target_groups == PackedInt32Array([4]), "Record the target of a restriction")
	_verify_deduction(report, Analyzer.Technique.REGION_TO_ROW, [0, 3])
	_verify_deduction(report, Analyzer.Technique.REGION_TO_COLUMN, [15])
	_verify_deduction(report, Analyzer.Technique.ROW_TO_REGION, [8])
	_verify_deduction(report, Analyzer.Technique.COMMON_CONFLICT, [5, 6])
	_verify_deduction(Analyzer.analyze(column, true), Analyzer.Technique.COLUMN_TO_REGION, [1])
	_verify_deduction(Analyzer.analyze(pair, true), Analyzer.Technique.CANDIDATE_PAIR, [11])
	for regions in [restrictions, column, pair]:
		var result := PuzzleAnalysis.assess(regions)
		var solution := Solver.find_solutions(regions)[0]
		_expect(result.status == Analyzer.Status.SOLVED and result.solution_count == 1, "Advanced fixture is logically solved and unique")
		_expect(result.logical.bears == solution, "Logical proof agrees with the independent solution")
		for step: Dictionary in result.logical.deductions:
			for removed in step.eliminated:
				_expect(not solution.has(removed), "A logical step never eliminates a solution bear")
	var base := Analyzer.analyze(PackedInt32Array(Generator.FALLBACK))
	var reasons: Dictionary = base.deductions[0].eliminations_by_technique
	_expect(reasons[Analyzer.Technique.ROW_ELIMINATION] == PackedInt32Array([0, 2, 3]), "Track row exclusions individually")
	_expect(reasons[Analyzer.Technique.COLUMN_ELIMINATION] == PackedInt32Array([5, 9, 13]), "Track column exclusions individually")
	_expect(reasons[Analyzer.Technique.DIAGONAL_EXCLUSION] == PackedInt32Array([4, 6]), "Track diagonal exclusions individually")
	var row_forced := PackedInt32Array([1, 0, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 2, 1, 3, 3])
	var region_exclusions: Dictionary = Analyzer.analyze(row_forced).deductions[1].eliminations_by_technique
	_expect(region_exclusions[Analyzer.Technique.REGION_ELIMINATION] == PackedInt32Array([10, 11]), "Track same-region exclusions individually")
	var multiple := PackedInt32Array([0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3])
	_expect(PuzzleAnalysis.assess(multiple).status == Analyzer.Status.MULTIPLE_SOLUTIONS, "Distinguish multiple solutions from a logical dead end")
	var dead_end := PuzzleAnalysis.assess(stuck)
	_expect(dead_end.status == Analyzer.Status.STUCK and dead_end.solution_count == 1, "A unique solution does not turn a logical dead end into a proof")
	var impossible := PackedInt32Array([0, 1, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3])
	_expect(PuzzleAnalysis.assess(impossible).status == Analyzer.Status.INVALID, "Distinguish a contradiction from a logical dead end")


func _verify_deduction(report: Dictionary, technique: int, eliminated: Array) -> void:
	_expect(report.deductions.any(func(step: Dictionary) -> bool:
		return step.technique == technique and step.eliminated == PackedInt32Array(eliminated)
	), "Trace contains the expected %s deduction" % Analyzer.Technique.keys()[technique])


func _test_difficulty_sizes() -> void:
	var expected := {
		"BASE": [4, 5, 6, 7], "EASY": [4, 5, 6, 7], "MEDIUM": [5, 6, 7],
		"HARD": [6, 7], "EXTRA HARD": [6, 7], "NIGHTMARES": [7],
	}
	for tag: String in expected:
		for side in range(3, 9):
			_expect(Difficulty.is_size_eligible(tag, side) == expected[tag].has(side), "Enforce the configured size range for %s" % tag)
	_expect(not Difficulty.is_size_eligible("UNKNOWN", 7), "Unknown difficulty has no eligible sizes")


func _test_game_state() -> void:
	var game := GameState.new()
	_expect(game.mark_at(0) == GameState.Mark.CLEAR, "Read a mark before loading safely")
	_expect(not game.load_puzzle(PackedInt32Array()), "Reject invalid puzzle loading")
	_expect(game.load_puzzle(PackedInt32Array(Generator.FALLBACK)), "Load a validated puzzle")
	_expect(game.mark_at(-1) == GameState.Mark.CLEAR, "Read a negative index safely")
	_expect(game.mark_at(Validator.CELL_COUNT) == GameState.Mark.CLEAR, "Read past the board safely")
	var result := game.toggle_mark(1, GameState.Mark.X)
	_expect(result == GameState.Result.INCORRECT_X and game.hearts == 2, "A wrong X costs exactly one heart")
	_expect(game.mark_at(1) == GameState.Mark.CLEAR and not game.is_locked(1), "Wrong X leaves the cell empty")
	_expect(game.toggle_mark(1, GameState.Mark.BEAR) == GameState.Result.CHANGED, "A wrong X does not block a later bear")
	_expect(game.toggle_mark(1, GameState.Mark.X) == GameState.Result.IGNORED and game.hearts == 2, "Locked bear ignores a wrong X")
	game.restart()
	result = game.toggle_mark(0, GameState.Mark.BEAR)
	_expect(result == GameState.Result.INCORRECT_BEAR and game.hearts == 2, "A wrong bear deducts one heart")
	_expect(game.mark_at(0) == GameState.Mark.X and game.is_locked(0), "A wrong bear leaves a locked X")
	_expect(game.toggle_mark(0, GameState.Mark.BEAR) == GameState.Result.IGNORED and game.hearts == 2, "A locked X cannot cost more hearts")
	for cell in [2, 3]:
		game.toggle_mark(cell, GameState.Mark.BEAR)
	_expect(game.hearts == 0 and game.status == GameState.Status.FAILED, "Fail at zero hearts")
	_expect(game.toggle_mark(1, GameState.Mark.BEAR) == GameState.Result.IGNORED, "Ignore moves after failure")

	var given := PackedInt32Array([1])
	_expect(game.load_puzzle(PackedInt32Array(Generator.FALLBACK), PackedInt32Array(), given), "Load a validated tutorial given")
	game.restart()
	_expect(game.hearts == 3 and game.status == GameState.Status.PLAYING, "Restore play on restart")
	_expect(game.mark_at(0) == GameState.Mark.CLEAR, "Restart clears player marks")
	_expect(game.mark_at(1) == GameState.Mark.BEAR and game.is_locked(1), "Restart restores the locked given")
	_expect(game.toggle_mark(1, GameState.Mark.X) == GameState.Result.IGNORED, "Given ignores edits")
	for cell in [7, 8, 14]:
		_expect(game.status == GameState.Status.PLAYING, "Do not complete early")
		game.toggle_mark(cell, GameState.Mark.BEAR)
	_expect(game.status == GameState.Status.COMPLETE, "Count the given toward completion")


func _test_batch(size: int) -> void:
	var row_regions := PackedInt32Array()
	for row in size:
		for column in size:
			row_regions.append(row)
	_expect(Solver.find_solutions(row_regions).size() == 2, "Reject nonunique row-region boards at every size")
	_expect(Analyzer.analyze(row_regions).status == Analyzer.Status.STUCK, "Report no forced opening at every size")
	row_regions[0] = size - 1
	row_regions[row_regions.size() - 1] = 0
	_expect(not Validator.is_valid_terrain(row_regions), "Reject disconnected duplicate terrain at every size")
	_expect(Solver.find_solutions(row_regions).is_empty(), "Skip search for invalid terrain at every size")
	var generator := Generator.new()
	var fallback := generator.generate(0, 0, Difficulty.BASE, size)
	_expect(generator.used_fallback and fallback.size() == size * size, "Use a size-specific fallback")
	_expect(_is_verified_base(fallback, Solver.find_solutions(fallback), Analyzer.analyze(fallback), size), "Verify fallback as BASE")
	_expect(generator.generate(42, Generator.DEFAULT_ATTEMPTS, Difficulty.BASE, size) == generator.generate(42, Generator.DEFAULT_ATTEMPTS, Difficulty.BASE, size), "Reproduce each board size from the same seed")
	var game := GameState.new()
	_expect(game.load_puzzle(fallback), "Load a BASE board into gameplay state")
	for cell in game.solution_snapshot():
		_expect(game.status == GameState.Status.PLAYING, "Larger boards only complete after all required bears")
		game.toggle_mark(cell, GameState.Mark.BEAR)
	_expect(game.status == GameState.Status.COMPLETE, "Detect completion at the selected size")
	var accepted := 0
	var rejected := 0
	var failed := 0
	var fallbacks := 0
	var longest_usec := 0
	var generation_usec := 0
	var layouts := {}
	var size_patterns := {}
	var region_sizes := {}
	var singleton_counts := {}
	var deduction_counts := {}
	var solutions_seen := {}
	var techniques_seen := {}
	for seed_value in BATCH_COUNT:
		var generation_start := Time.get_ticks_usec()
		var regions := generator.generate(seed_value, Generator.DEFAULT_ATTEMPTS, Difficulty.BASE, size)
		var duration := Time.get_ticks_usec() - generation_start
		longest_usec = maxi(longest_usec, duration)
		generation_usec += duration
		rejected += generator.rejected_attempts
		if generator.used_fallback:
			fallbacks += 1
		var solutions := Solver.find_solutions(regions)
		var logical := Analyzer.analyze(regions)
		_expect(Analyzer.analyze(regions, true) == logical, "Advanced mode preserves the BASE proof and trace")
		if not _is_verified_base(regions, solutions, logical, size):
			failed += 1
			continue
		if not generator.used_fallback:
			accepted += 1
		var labels := {}
		var shape := PackedInt32Array()
		var sizes := PackedInt32Array()
		for region in regions:
			if not labels.has(region):
				labels[region] = labels.size()
				var region_size := regions.count(region)
				sizes.append(region_size)
				region_sizes[region_size] = region_sizes.get(region_size, 0) + 1
			shape.append(labels[region])
		layouts[shape.to_byte_array().hex_encode()] = true
		sizes.sort()
		size_patterns[sizes.to_byte_array().hex_encode()] = true
		var singleton_count := sizes.count(1)
		singleton_counts[singleton_count] = singleton_counts.get(singleton_count, 0) + 1
		var deduction_count: int = logical.deductions.size()
		deduction_counts[deduction_count] = deduction_counts.get(deduction_count, 0) + 1
		solutions_seen[solutions[0].to_byte_array().hex_encode()] = true
		for deduction: Dictionary in logical.deductions:
			var technique := Analyzer.Technique.keys()[deduction.technique] as String
			techniques_seen[technique] = techniques_seen.get(technique, 0) + 1
	var summary := (
		"%dx%d BASE batch: %d requests, %d accepted candidates, %d rejected candidates, "
		+ "%d failures, %d fallbacks, %.2f%% candidate acceptance, "
		+ "%d layouts ignoring labels, %d size patterns, %d solutions, %.3f ms mean, %.3f ms worst"
	)
	print(summary % [
		size, size, BATCH_COUNT, accepted, rejected, failed, fallbacks, 100.0 * accepted / maxi(1, accepted + rejected),
		layouts.size(), size_patterns.size(), solutions_seen.size(),
		generation_usec / (BATCH_COUNT * 1000.0), longest_usec / 1000.0,
	])
	region_sizes.sort()
	singleton_counts.sort()
	print("  region cells: %s; singleton regions per board: %s" % [region_sizes, singleton_counts])
	print("  deductions per board: %s; technique totals: %s" % [deduction_counts, techniques_seen])
	_expect(failed == 0, "Every batch board is connected, unique, non-touching, and solvable by basic deductions")
	_expect(accepted >= 1000, "Generate at least 1,000 fresh BASE boards at each size")
	_expect(layouts.size() > 100 and size_patterns.size() > 1, "Batch produces varied terrain shapes and sizes")
	_expect(solutions_seen.size() >= 2, "Batch uses multiple non-touching bear arrangements")
	_expect(singleton_counts == {1: BATCH_COUNT}, "Every generated board has exactly one singleton region")
	_expect(longest_usec < 1000000, "Each BASE generation finishes within one second")


func _is_verified_base(regions: PackedInt32Array, solutions: Array[PackedInt32Array], logical: Dictionary, size: int) -> bool:
	if regions.size() != size * size or not Validator.is_valid_terrain(regions) or solutions.size() != 1:
		return false
	var bears := solutions[0]
	if logical.status != Analyzer.Status.SOLVED or logical.bears != bears:
		return false
	if logical.deductions.size() != size or logical.deductions[0].technique != Analyzer.Technique.SINGLE_CELL_REGION:
		return false
	var singletons := 0
	for region in size:
		singletons += int(regions.count(region) == 1)
	if singletons != 1 or regions.count(regions[logical.deductions[0].cell]) != 1 or not Difficulty.matches(Difficulty.BASE, regions):
		return false
	for first in bears.size():
		for second in range(first + 1, bears.size()):
			@warning_ignore("integer_division")
			var row_gap := absi(bears[first] / size - bears[second] / size)
			var column_gap := absi(bears[first] % size - bears[second] % size)
			if row_gap == 0 or column_gap == 0 or (row_gap == 1 and column_gap == 1) or regions[bears[first]] == regions[bears[second]]:
				return false
	return true


func _test_puzzle_modes() -> void:
	var path_eight := {
		"id": "cubdoku-0008", "size": 4, "difficulty": "BASE",
		"regions": PackedInt32Array([1, 0, 0, 0, 1, 1, 0, 0, 3, 3, 2, 2, 3, 3, 3, 2]),
		"solution": PackedInt32Array([2, 4, 11, 13]),
	}
	_expect(Catalog.load_path(8) == path_eight, "Path #8 matches its permanent definition")
	_expect(Catalog.load_path(7).id != path_eight.id, "Different paths have different IDs")
	_expect(Catalog.load_path(7).regions != path_eight.regions, "Different paths have different layouts")
	_expect(Catalog.load_path(9).is_empty(), "An undefined path has no generated substitute")
	for number in range(1, 9):
		var fixture := Catalog.load_path(number)
		_expect(Solver.find_solutions(fixture.regions) == [fixture.solution], "Validate legacy fixture")

	var path_a := _profile_path()
	var path_b := _profile_path()
	var session := Session.new(path_a)
	var second := Session.new(path_b)
	# Fixed distinct RNG streams make the independent assignments reproducible.
	session.get("_rng").seed = 1
	second.get("_rng").seed = 2
	if not session.load_campaign() or not second.load_campaign():
		_expect(false, "Create and save two campaign profiles")
		return
	var assigned := session.definition_snapshot()
	var other := second.definition_snapshot()
	_expect(assigned.level_id == other.level_id, "Profiles share a permanent level ID")
	_expect(assigned.difficulty == other.difficulty, "Profiles share the assigned difficulty")
	_expect(assigned.id != other.id and assigned.regions != other.regions, "Profiles receive personal instances and boards")
	_expect(Solver.find_solutions(assigned.regions) == [assigned.solution], "Validate the first assigned board")
	_expect(Solver.find_solutions(other.regions) == [other.solution], "Validate the second assigned board")
	_expect(Difficulty.matches(Difficulty.BASE, assigned.regions), "New campaign puzzles meet BASE calibration")
	_expect(session.load_campaign(), "Reopen campaign screen")
	_expect(session.attempt_summary().attempts_started == 1, "Opening the screen keeps Attempt 1")

	session.tick(2.5)
	session.toggle_mark(0, GameState.Mark.BEAR)
	session = Session.new(path_a)
	session.get("_rng").seed = 999
	_expect(session.load_campaign(), "Load saved unfinished attempt")
	_expect(session.definition_snapshot() == assigned, "A changed random stream cannot replace an assignment")
	_expect(session.game.mark_at(0) == GameState.Mark.X and session.game.hearts == 2, "Resume saved marks and hearts")
	_expect(is_equal_approx(session.elapsed, 2.5), "Resume saved timer")
	_expect(session.attempt_summary().attempts_started == 1, "Resume does not start a new attempt")
	for cell in range(1, assigned.regions.size()):
		if not assigned.solution.has(cell):
			session.toggle_mark(cell, GameState.Mark.BEAR)
		if session.game.hearts == 0:
			break
	_expect(session.game.status == GameState.Status.FAILED, "Record failure at zero hearts")
	_expect(session.attempt_summary().failed_attempts == 1, "Count failure separately")
	session = Session.new(path_a)
	_expect(session.load_campaign(), "Reload the failed attempt")
	_expect(session.game.status == GameState.Status.FAILED, "Reload preserves failure status")
	_expect(session.attempt_summary().failed_attempts == 1, "Reload does not recount failure")
	_expect(session.restart(), "Explicit restart saves a new attempt")
	_expect(session.attempt_summary().attempts_started == 2, "Restart starts Attempt 2")
	_expect(session.definition_snapshot() == assigned, "Restart keeps the assigned definition")
	_expect(session.game.hearts == 3 and session.elapsed == 0.0, "Restart resets hearts and time")

	session.tick(8.0)
	session.toggle_mark(0, GameState.Mark.BEAR)
	_solve_active(session)
	var first_success := session.attempt_summary()
	_expect(first_success.completed and first_success.hearts_at_completion == 2, "Record success and remaining hearts")
	_expect(first_success.best_completion_seconds == 8.0, "Record first success time")
	_expect(session.restart(), "Start a replay of the same puzzle")
	session.tick(4.0)
	_solve_active(session)
	_expect(session.attempt_summary().best_completion_seconds == 4.0, "A faster replay updates the best time")
	_expect(session.attempt_summary().attempts_started == 3, "Count replay as a new attempt")
	_expect(session.attempt_summary().failed_attempts == 1, "Replay does not add a failure")

	var stats := session.statistics_snapshot()
	_expect(stats.completed_total == 1 and stats.completed_by_difficulty == {"BASE": 1}, "Count each completed level once")
	_expect(stats.fastest_completion_seconds == 4.0 and stats.highest_level_reached == 1, "Record fastest time and highest level")
	var saved_summary := session.attempt_summary()
	var layouts := {}
	for attempt in 20:
		_expect(session.load_free_play(), "Load a randomized Free Play board")
		var definition := session.definition_snapshot()
		layouts[definition.regions.to_byte_array().hex_encode()] = true
		_expect(Solver.find_solutions(definition.regions) == [definition.solution], "Validate Free Play")
		_expect(Difficulty.matches(Difficulty.BASE, definition.regions), "Free Play meets BASE calibration")
		_solve_active(session)
		_expect(not session.advance(), "Free Play cannot advance when the next campaign level exists")
		_expect(session.restart(), "Restart Free Play")
		_expect(session.definition_snapshot() == definition, "Free Play restart keeps the same puzzle")
	_expect(layouts.size() > 1, "Free Play generates varied layouts")
	_expect(session.statistics_snapshot() == stats, "Free Play leaves campaign statistics unchanged")
	_expect(session.attempt_summary() == saved_summary, "Free Play leaves campaign attempts unchanged")
	_expect(session.load_campaign(), "Return to the saved campaign attempt")
	_expect(session.definition_snapshot() == assigned, "Return restores the assigned puzzle")
	_expect(session.game.status == GameState.Status.COMPLETE, "Return restores the completed attempt")

	session = Session.new(path_a)
	_expect(session.load_campaign(), "Reload completed campaign")
	_expect(session.definition_snapshot() == assigned and session.statistics_snapshot() == stats, "Reload preserves identity and statistics")
	_expect(session.attempt_summary() == saved_summary, "Reload preserves all attempt totals")
	_expect(session.advance(), "Advance after reloading the completed attempt")
	_expect(session.campaign_number() == 2 and session.statistics_snapshot().highest_level_reached == 2, "Advance records highest level")
	var next_board := session.definition_snapshot()
	session = Session.new(path_a)
	_expect(session.load_campaign(), "Load saved campaign progress")
	_expect(session.campaign_number() == 2 and session.definition_snapshot() == next_board, "Resume the current level and its identity")
	_expect(session.attempt_summary().attempts_started == 1, "Next assigned puzzle begins at Attempt 1")
	_expect(session.restart(), "Restart an unfinished attempt")
	_expect(session.attempt_summary().attempts_started == 2, "Restarting unfinished play counts a new attempt")
	_expect(session.attempt_summary().failed_attempts == 0, "Restarting unfinished play is not a failure")
	_expect(session.definition_snapshot() == next_board, "Restarting unfinished play preserves identity")
	_expect(Catalog.load_path(8) == path_eight, "Personal campaign play leaves legacy data unchanged")


func _solve_active(session: Session) -> void:
	for cell in session.definition_snapshot().solution:
		session.toggle_mark(cell, GameState.Mark.BEAR)


func _test_legacy_assignment() -> void:
	var path := _profile_path()
	var session := Session.new(path)
	if not session.load_campaign():
		_expect(false, "Create a save for the legacy assignment regression")
		return
	var profile := Save.read(path)
	var legacy := Catalog.load_path(1)
	legacy.id = "previously-assigned-instance"
	legacy.level_id = Catalog.level(1).id
	profile.assignments[1].definition = legacy
	_expect(Save.write(path, profile), "Write a previously assigned BASE board with no singleton")
	var saved_bytes := FileAccess.get_file_as_bytes(path)
	session = Session.new(path)
	_expect(session.load_campaign(), "Load a previous assignment despite the new BASE requirements")
	_expect(session.definition_snapshot() == legacy, "Preserve the legacy ID, terrain, solution, and difficulty")
	_expect(FileAccess.get_file_as_bytes(path) == saved_bytes, "Opening the old assignment leaves its save untouched")
	_expect(session.restart() and session.definition_snapshot() == legacy, "Restart does not reroll a legacy assignment")
	_expect(session.load_free_play() and session.load_campaign(), "Return to a legacy assignment from Free Play")
	_expect(Save.read(path).assignments[1].definition == legacy, "Keep the original definition on disk after retrying")
	profile = Save.read(path)
	var given: int = legacy.solution[0]
	profile.assignments[1].definition.locked_bears = PackedInt32Array([given])
	profile.assignments[1].attempt.marks[given] = GameState.Mark.BEAR
	_expect(Save.write(path, profile), "Write an assignment carrying a tutorial bear")
	session = Session.new(path)
	_expect(session.load_campaign() and session.game.is_locked(given), "Restore the saved tutorial bear")
	_expect(session.restart() and session.game.mark_at(given) == GameState.Mark.BEAR, "Campaign restart keeps the tutorial bear")


func _test_unsupported_save() -> void:
	var path := _profile_path()
	var future_profile := {"version": Save.VERSION + 1, "assignments": {1: "future data"}}
	_expect(Save.write(path, future_profile), "Write a future-version test save")
	var original_bytes := FileAccess.get_file_as_bytes(path)
	var session := Session.new(path)
	_expect(not session.load_campaign(), "Refuse to load an unsupported save version")
	_expect(session.load_free_play(), "Free Play remains available with an unsupported save")
	_expect(FileAccess.get_file_as_bytes(path) == original_bytes, "Preserve the unsupported save byte-for-byte")


func _profile_path() -> String:
	var path := "user://test-profile-%s.save" % Crypto.new().generate_random_bytes(12).hex_encode()
	_test_profiles.append(path)
	return path


func _test_terrain_mapping() -> void:
	var board := BoardTerrain.new()
	var side := TerrainFixture.SIDE
	var regions := PackedInt32Array(TerrainFixture.REGIONS)
	board.set_board(side, regions)
	_expect(board.terrain_layer.get_used_cells().size() == side * side, "Render every fixture cell")
	_expect(board.terrain_layer.tile_set.get_source_count() == 7, "Render all seven materials")
	_verify_terrain_edges(board, side, regions)
	board.set_board(1, PackedInt32Array([6]))
	_expect(board.terrain_layer.get_used_cells().size() == 1, "Redrawing clears previous terrain tiles")
	_expect(board.region_edges().is_empty(), "Redrawing clears previous internal edges")
	board.free()


func _test_free_play_reserve() -> void:
	var service := FreePlay.new()
	_expect(service.generate("EASY", 4, 19).has("error"), "Reject an ineligible exact size")
	var roots: Dictionary = service.get("_roots")
	var reserve: Dictionary = service.get("_reserve")
	var rows: Array = reserve["10"]
	reserve["10"] = rows.slice(0, 2)
	var no_roots: Array[Dictionary] = []
	roots["_verified_10"] = no_roots
	var first := service.generate("NIGHTMARES", 10, 42)
	var second := service.generate("NIGHTMARES", 10, 42)
	if first.has("error") or second.has("error"):
		_expect(false, "Serve both independently validated reserve entries")
		return
	_expect(first.source == "Validated reserve" and second.source == first.source and first.id != second.id,
		"Report the reserve source without reusing a served layout")
	_expect(service.generate("NIGHTMARES", 10, 42).get("error", "").contains("No unused"),
		"Report exhaustion after the finite reserve runs out")
	var rolling := FreePlay.new(1, false)
	var rolling_roots: Dictionary = rolling.get("_roots")
	var rolling_reserve: Dictionary = rolling.get("_reserve")
	rolling_roots["_verified_10"] = no_roots
	rolling_reserve["10"] = rows.slice(0, 2)
	_expect(rolling.generate("NIGHTMARES", 10, 42).get("id") == first.id
		and rolling.generate("NIGHTMARES", 10, 42).get("id") == second.id
		and rolling.generate("NIGHTMARES", 10, 42).get("id") == first.id,
		"Keep the latest layout excluded and allow the older one after eviction")
	var slot := _profile_path()
	_expect(FreePlay.save_slot(first, slot), "Save a complete playtest definition")
	var reopened := FreePlay.reopen_slot(slot)
	_expect(reopened.get("id") == first.id and reopened.get("regions") == first.regions
		and reopened.get("solution") == first.solution, "Reopen and revalidate the exact definition")


func _verify_terrain_edges(board: BoardTerrain, side: int, regions: PackedInt32Array) -> void:
	var edges := board.region_edges()
	var expected_count := 0
	for y in side:
		for x in side:
			var cell := Vector2i(x, y)
			var index := y * side + x
			var region := regions[index]
			_expect(board.terrain_layer.get_cell_source_id(cell) == region, "Match tile material to region ID")
			_expect(board.terrain_layer.get_cell_atlas_coords(cell) == cell, "Sample the sheet in board coordinates")
			var origin := Vector2(cell) * BoardTerrain.CELL_SIZE
			for step in [Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + step
				if neighbor.x >= side or neighbor.y >= side:
					continue
				var different := region != regions[neighbor.y * side + neighbor.x]
				var start := origin + Vector2(step) * BoardTerrain.CELL_SIZE
				var end := start + Vector2(step.y, step.x) * BoardTerrain.CELL_SIZE
				var found := false
				for segment in range(0, edges.size(), 2):
					if edges[segment] == start and edges[segment + 1] == end:
						found = true
				_expect(found == different, "Only neighboring unlike regions receive thick internal edges")
				expected_count += int(different)
	_expect(edges.size() == expected_count * 2, "Draw each internal region edge once")


func _verify_button_alignment(grid: GridContainer, side: int) -> void:
	var terrain := grid.get_parent() as BoardTerrain
	_expect(grid.columns == side and grid.get_child_count() == side * side, "Render a square grid at the selected size")
	_expect(terrain.terrain_layer.get_used_cells().size() == side * side, "Render one tile per playable cell")
	for index in grid.get_child_count():
		@warning_ignore("integer_division")
		var tile := Vector2i(index % side, index / side)
		var button := grid.get_child(index) as Button
		var button_center := button.get_global_transform() * (button.size * 0.5)
		var tile_center := terrain.terrain_layer.to_global(terrain.terrain_layer.map_to_local(tile))
		_expect(button_center.is_equal_approx(tile_center), "Buttons align with terrain tile centers")
		_expect(button.size == Vector2.ONE * BoardTerrain.CELL_SIZE, "Button covers exactly one terrain tile")
	var span := side * BoardTerrain.CELL_SIZE
	var transform := terrain.get_global_transform()
	var footprint := Rect2(transform.origin, transform.basis_xform(Vector2.ONE * span))
	_expect(is_equal_approx(footprint.size.x, footprint.size.y), "Keep the displayed board square")
	_expect(root.get_visible_rect().encloses(footprint), "Keep the whole board in the viewport")


func _test_scene() -> void:
	var board := BoardScene.instantiate()
	var profile_path := _profile_path()
	var session := Session.new(profile_path)
	board.set("_session", session)
	board.set("enable_developer_tools", true)
	root.add_child(board)
	var rendered_grid := board.find_children("*", "GridContainer", true, false)[0] as GridContainer
	_expect(rendered_grid.get_child_count() == 16, "Render sixteen cells in the main scene")
	var labels := board.find_children("*", "Label", true, false)
	var cell := rendered_grid.get_child(0) as Button
	var next := board.get("_next_button") as Button
	var restart := next.get_parent().get_child(0) as Button
	var generate := next.get_parent().get_child(1) as Button
	var campaign := board.get("_campaign_button") as Button
	var selector := board.get("_free_play_difficulty") as OptionButton
	var feedback := board.get("_feedback") as Label
	_expect(not selector.is_visible_in_tree(), "Difficulty control belongs to Free Play")
	_expect(labels[0].text == "Campaign Path #1 · BASE", "Show the campaign path and difficulty")
	_expect(next.disabled, "Disable advance during play")
	next.pressed.emit()
	_expect(labels[0].text == "Campaign Path #1 · BASE", "Reject advance during play")
	_expect(labels[1].text == "Hearts  ♥♥♥", "Show three starting hearts")
	await create_timer(1.1).timeout
	_expect(labels[2].text != "Time  00:00", "Update the elapsed time")
	_verify_button_alignment(rendered_grid, Validator.SIZE)
	var solution := session.game.solution_snapshot()
	var bear_cell := rendered_grid.get_child(solution[0]) as Button
	_mouse_button(bear_cell, MOUSE_BUTTON_LEFT, true)
	await create_timer(0.1).timeout
	var progress := board.get("_hold_indicator") as ProgressBar
	_expect(progress.visible and progress.value > 0 and bear_cell.text.is_empty(), "Show hold progress without placing early")
	_mouse_button(bear_cell, MOUSE_BUTTON_LEFT, false)
	await create_timer(0.42).timeout
	_expect(bear_cell.text.is_empty() and not progress.visible, "Early release cancels placement")
	_mouse_button(bear_cell, MOUSE_BUTTON_LEFT, true)
	var outside := InputEventMouseMotion.new()
	outside.position = Vector2.ONE
	root.push_input(outside, true)
	await create_timer(0.42).timeout
	_expect(bear_cell.text.is_empty() and not progress.visible, "Pointer exit cancels placement")
	_mouse_button(bear_cell, MOUSE_BUTTON_LEFT, false)
	_click_x(bear_cell)
	_expect(bear_cell.text.is_empty() and not bear_cell.disabled and session.game.hearts == 2, "Wrong right-click costs one heart and leaves the cell empty")
	_expect(board.get("_error_flash").visible and board.get("_warning").playing, "Wrong X flashes red and plays a warning")
	restart.pressed.emit()
	_mouse_button(bear_cell, MOUSE_BUTTON_LEFT, true)
	await create_timer(0.45).timeout
	_mouse_button(bear_cell, MOUSE_BUTTON_LEFT, false)
	_expect(bear_cell.text == "🐻" and bear_cell.disabled, "A sustained hold commits and locks a bear")
	var chime := board.get("_line_chime") as AudioStreamPlayer
	_expect(not chime.playing, "A partially marked line does not chime")
	var intro_side := Validator.SIZE
	@warning_ignore("integer_division")
	var row_start := (solution[0] / intro_side) * intro_side
	for index in range(row_start, row_start + intro_side):
		if index != solution[0]:
			_click_x(rendered_grid.get_child(index) as Button)
	_expect(chime.playing, "Completing a row plays the chime")
	chime.stop()
	_click_x(bear_cell)
	_expect(not chime.playing, "Clicking a locked cell does not replay the chime")
	var column := solution[0] % intro_side
	for offset in range(1, intro_side):
		_click_x(rendered_grid.get_child(offset * intro_side + column) as Button)
	_expect(chime.playing, "Completing a column also plays the chime")
	chime.stop()
	restart.pressed.emit()
	for offset in intro_side:
		if offset != column:
			_click_x(rendered_grid.get_child(row_start + offset) as Button)
		if offset != 0:
			_click_x(rendered_grid.get_child(offset * intro_side + column) as Button)
	_expect(not chime.playing, "Neither line chimes before its shared missing bear")
	_commit_hold(board, bear_cell)
	_expect(chime.playing, "One chime plays when a bear completes a row and column together")
	chime.stop()
	restart.pressed.emit()
	var wrong_cells := PackedInt32Array()
	for index in range(intro_side * intro_side):
		if not solution.has(index):
			wrong_cells.append(index)
	for index in wrong_cells.slice(0, 3):
		_commit_hold(board, rendered_grid.get_child(index) as Button)
		if index == wrong_cells[0]:
			_expect((rendered_grid.get_child(index) as Button).text == "X" and session.game.hearts == 2, "Wrong bear becomes X and costs one heart")
			_expect(feedback.text.contains("Incorrect bear"), "Show immediate incorrect placement feedback")
	_expect(cell.disabled and feedback.text.contains("No hearts"), "Lock the board after failure")

	_expect(next.disabled, "Disable advance after failure")
	next.pressed.emit()
	_expect(cell.disabled and labels[0].text == "Campaign Path #1 · BASE", "Reject advance after failure")
	var original_regions: PackedInt32Array = board.get("_regions")
	restart.pressed.emit()
	_expect(labels[0].text == "Campaign Path #1 · BASE", "Restart keeps the puzzle number")
	_expect(board.get("_regions") == original_regions, "Restart keeps the terrain layout")
	_expect(labels[2].text == "Time  00:00", "Restart resets the displayed time")
	_expect(not cell.disabled and labels[1].text == "Hearts  ♥♥♥", "Restart unlocks the board")
	_click_x(cell)
	_expect(session.flush_attempt(), "Checkpoint the campaign before entering Free Play")
	var saved_campaign := FileAccess.get_file_as_bytes(profile_path)
	var campaign_definition := session.definition_snapshot()
	var campaign_attempt := session.game.attempt_snapshot()
	var campaign_history := session.attempt_summary()
	var campaign_stats := session.statistics_snapshot()
	generate.pressed.emit()
	await _wait_for_generation(board)
	_expect(labels[0].text == "Free Play · BASE", "Test generation enters Free Play")
	_expect(cell.text.is_empty(), "Test generation loads a fresh board")
	_expect(selector.is_visible_in_tree() and selector.item_count == 6, "Free Play offers all six difficulties")
	_expect(session.definition_snapshot().size in [4, 5, 6, 7], "Ordinary BASE chooses an eligible size")
	var panel = board.get("_developer")
	_expect(not panel.visible, "Developer panel starts hidden")
	panel.difficulty.select(5)
	panel.difficulty.item_selected.emit(5)
	_expect(panel.size_override.item_count == 4 and panel.size_override.get_item_id(1) == 8
		and panel.size_override.get_item_id(3) == 10, "Developer size override exposes only eligible NIGHTMARES sizes")
	if DisplayServer.get_name() != "headless":
		panel.popup_centered()
		await process_frame
		_expect(panel.visible, "Developer panel can be opened in the windowed game")
		panel.hide()
		await process_frame
	var requests := [
		["BASE", 4, "42"], ["BASE", 5, "42"], ["BASE", 6, "42"], ["BASE", 7, "42"],
		["EASY", 5, "50006"], ["MEDIUM", 6, "50008"], ["HARD", 8, "50009"],
		["EXTRA HARD", 8, "4308000"], ["NIGHTMARES", 8, "50161"],
		["NIGHTMARES", 9, "50161"], ["NIGHTMARES", 10, "50161"],
	]
	for request in requests:
		var side: int = request[1]
		panel.generate_requested.emit(request[0], side, request[2])
		await _wait_for_generation(board)
		await process_frame
		var definition := session.definition_snapshot()
		var free_regions: PackedInt32Array = definition.regions
		var free_solutions := Solver.find_solutions(free_regions)
		var logical := Analyzer.analyze(free_regions)
		_expect(definition.size == side and definition.difficulty == request[0] and free_solutions == [definition.solution],
			"The requested difficulty and exact size load a uniquely validated board")
		if request[0] == "BASE":
			_expect(_is_verified_base(free_regions, free_solutions, logical, side), "Check BASE proof")
		var before_diagnostics := session.game.attempt_snapshot()
		panel.diagnostics_requested.emit()
		_expect(panel.trace.text.contains("Logical proof") and session.game.attempt_snapshot() == before_diagnostics, "Proof viewer leaves marks and hearts untouched")
		_verify_button_alignment(rendered_grid, side)
		_verify_terrain_edges(rendered_grid.get_parent() as BoardTerrain, side, free_regions)
		var last_index := side * side - 1
		var last := rendered_grid.get_child(last_index) as Button
		_click_x(last)
		if definition.solution.has(last_index):
			_expect(last.text.is_empty() and session.game.hearts == 2, "Bottom-right wrong X maps correctly")
		else:
			_expect(last.text == "X" and last.disabled and session.game.hearts == 3, "Correct X locks at every size")
		restart.pressed.emit()
		var wrong_index := side * side - 2
		while definition.solution.has(wrong_index):
			wrong_index -= 1
		var wrong := rendered_grid.get_child(wrong_index) as Button
		_commit_hold(board, wrong)
		_expect(wrong.text == "X" and session.game.hearts == 2, "Reject incorrect bears at every size")
		session.tick(2.0)
		restart.pressed.emit()
		_expect(session.definition_snapshot() == definition, "Restart preserves layout and size")
		_expect(last.text.is_empty() and session.game.hearts == 3 and session.elapsed == 0.0, "Restart resets marks, hearts and timer")
		for bear in definition.solution:
			_expect(session.game.status == GameState.Status.PLAYING, "Wait for all bears before completing")
			var button := rendered_grid.get_child(bear) as Button
			_commit_hold(board, button)
			_expect(button.text == "🐻", "Place a bear through the resized button grid")
		_expect(session.game.status == GameState.Status.COMPLETE and next.disabled, "Complete Free Play without advancing the campaign")
		_expect(feedback.text == "Puzzle complete!", "Show completion feedback at the selected size")
	_expect(session.attempt_summary() == campaign_history and session.statistics_snapshot() == campaign_stats, "Free Play leaves campaign history and statistics unchanged")
	_expect(FileAccess.get_file_as_bytes(profile_path) == saved_campaign, "Free Play leaves the campaign save byte-for-byte intact")
	campaign.pressed.emit()
	_expect(labels[0].text == "Campaign Path #1 · BASE", "Free Play preserves the campaign number")
	_expect(board.get("_regions") == original_regions, "Return to the original campaign board")
	_expect(cell.text == "X", "Return resumes the campaign markings")
	_expect(session.definition_snapshot() == campaign_definition and session.game.attempt_snapshot() == campaign_attempt, "Return preserves the campaign puzzle ID, solution and attempt")
	await process_frame
	await process_frame
	_verify_button_alignment(rendered_grid, Validator.SIZE)

	var regions: PackedInt32Array = board.get("_regions")
	var solutions := Solver.find_solutions(regions)
	_expect(solutions.size() == 1, "Present a unique campaign puzzle")
	if solutions.size() == 1:
		for solved_cell in solutions[0]:
			var bear_button := rendered_grid.get_child(solved_cell) as Button
			_commit_hold(board, bear_button)
			_expect(bear_button.text == "🐻", "Show a correctly placed bear")
		_expect(cell.disabled and feedback.text == "Puzzle complete!", "Show puzzle completion")
		_expect(labels[0].text == "Campaign Path #1 · BASE", "Completion keeps the puzzle number")
		_expect(not next.disabled, "Enable advance after completion")
		next.pressed.emit()
		_expect(labels[0].text == "Campaign Path #2 · BASE", "Explicit advance increments the path")
		regions = board.get("_regions")
		_expect(Solver.find_solutions(regions).size() == 1, "Advance loads a unique puzzle")
		_expect(not cell.disabled and next.disabled, "Advance starts a new attempt")
		next.pressed.emit()
		_expect(labels[0].text == "Campaign Path #2 · BASE", "Advance requires another completion")
		restart.pressed.emit()
		_expect(labels[0].text == "Campaign Path #2 · BASE", "Restart preserves an advanced number")
		generate.pressed.emit()
		await _wait_for_generation(board)
		campaign.pressed.emit()
		_expect(labels[0].text == "Campaign Path #2 · BASE", "Free Play preserves an advanced number")
	board.free()


func _wait_for_generation(board: Control) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while board.get("_generation") != null and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(board.get("_generation") == null, "Free Play worker finishes within the test deadline")
	await process_frame


func _mouse_button(button: Button, index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = button.get_global_transform_with_canvas() * (button.size / 2.0)
	root.push_input(event, true)


func _click_x(button: Button) -> void:
	_mouse_button(button, MOUSE_BUTTON_RIGHT, true)
	_mouse_button(button, MOUSE_BUTTON_RIGHT, false)


func _commit_hold(board: Control, button: Button) -> void:
	_mouse_button(button, MOUSE_BUTTON_LEFT, true)
	board.set("_hold_started", Time.get_ticks_msec() - 400)
	_mouse_button(button, MOUSE_BUTTON_LEFT, false)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)


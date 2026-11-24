extends SceneTree
## Runs the planned schedule without instantiating a campaign session or save.

const Schedule := preload("res://scripts/campaign_schedule.gd")
const Generation := preload("res://scripts/campaign_generation.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Validator := preload("res://scripts/puzzle_validator.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const FreePlay := preload("res://scripts/free_play_generation.gd")
const Elimination := preload("res://scripts/nightmares_elimination.gd")
const Hall := preload("res://scripts/nightmares_hall_reasoning.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var count := clampi(int(args[0]), 1, Schedule.STAGE_COUNT) if not args.is_empty() else 5000
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	var isolation_root := ProjectSettings.globalize_path("res://.godot/").replace("\\", "/")
	if not expected.begins_with(isolation_root + "isolated-") or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		push_error("Run the benchmark with tests/run_isolated.ps1.")
		quit(1)
		return
	var filename := args[1] if args.size() > 1 else "campaign-simulation.jsonl"
	if filename != filename.get_file() or not filename.is_valid_filename() or filename.get_extension() != "jsonl":
		push_error("Use a .jsonl filename in the isolated user directory.")
		quit(1)
		return
	var path := "user://" + filename
	var policy := args[2] if args.size() > 2 else "advanced"
	var current := policy == "current"
	if policy not in ["unguided", "legacy", "optimized", "planned", "multi_row", "advanced", "current"]:
		push_error("Unknown generation policy: " + policy)
		quit(1)
		return
	var guided := policy != "unguided"
	var optimized := current or policy in ["optimized", "planned", "multi_row", "advanced"]
	var planned := current or policy in ["planned", "multi_row", "advanced"]
	var multi_row := current or policy in ["multi_row", "advanced"]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write simulation report: " + path)
		quit(1)
		return
	var schedule := Schedule.new()
	var generator := Generation.new(current)
	var nightmares := FreePlay.new() if current else null
	print("Writing ", ProjectSettings.globalize_path(path))
	var invalid := 0
	for stage in range(1, count + 1):
		var request := schedule.request(stage)
		var seed_value := stage + 50000
		var started := Time.get_ticks_usec()
		var row := request.duplicate()
		if current and request.difficulty == "NIGHTMARES":
			var timing := {}
			var definition := nightmares.generate("NIGHTMARES", request.size, seed_value, timing)
			row.merge({"seed": seed_value, "usec": Time.get_ticks_usec() - started, "timing": timing,
				"status": "failed" if definition.has("error") else "success",
				"reason": "budget_and_reserve_exhausted" if definition.has("error") else "",
				"source": definition.get("source", "unfulfilled"), "fallback": false, "rejections": {}})
			if row.status == "success":
				var result := {"regions": definition.regions, "solution": definition.solution,
					"report": Analyzer.analyze_with_families(definition.regions, Analyzer.EXTENDED_FAMILIES),
					"locked_bears": PackedInt32Array()}
				_record_proof(row, result, current)
				invalid += int(not (row.rules and row.unique and row.logical and row.profile_verified))
			file.store_line(JSON.stringify(row))
			if stage % 100 == 0:
				file.flush()
			if stage % 500 == 0:
				print("Recorded stages through %d" % stage)
			continue
		var result := generator.generate(request, seed_value, Generation.HIGHER_BUDGET, guided, optimized, stage % 5 == 0, planned, multi_row, current or policy == "advanced")
		row.merge({
			"seed": seed_value, "usec": Time.get_ticks_usec() - started - result.phase_usec.diagnostic, "status": result.status,
			"reason": result.reason, "rejections": result.rejections, "fallback": result.fallback,
			"phase_usec": result.phase_usec, "repairs": result.repairs,
			"plans": result.plans, "repair_gate_rejections": result.repair_gate_rejections,
			"construction_source": result.get("construction_source", "ordinary"),
			"source": ("Validated BASE fallback" if result.fallback else "Fresh") if result.status == "success" else "unfulfilled",
		})
		if result.has("ambiguity_sample"):
			row.ambiguity_sample = result.ambiguity_sample
		if result.status == "success":
			_record_proof(row, result, current)
			if not row.rules or not row.unique or not row.logical or not row.profile_verified:
				invalid += 1
		file.store_line(JSON.stringify(row))
		if stage % 100 == 0:
			file.flush()
		if stage % 500 == 0:
			print("Recorded stages through %d" % stage)
	file.flush()
	var complete := file.get_error() == OK
	file.close()
	print("Recorded %d requests, %d invalid acceptances: %s" % [count, invalid, ProjectSettings.globalize_path(path)])
	quit(0 if invalid == 0 and complete else 1)


func _record_proof(row: Dictionary, result: Dictionary, current := false) -> void:
	var board: PackedInt32Array = result.regions
	var solution: PackedInt32Array = result.solution
	var trace: Dictionary = result.report
	var solved_by: Array[int] = []
	var highest_mask := Analyzer.EXTENDED_FAMILIES if row.difficulty in ["EXTRA HARD", "NIGHTMARES"] else Analyzer.ALL_FAMILIES
	for mask in range(highest_mask + 1):
		var proof := Analyzer.analyze_with_families(board, mask)
		if proof.status == Analyzer.Status.SOLVED and proof.bears == solution:
			solved_by.append(mask)
	var minimal: Array[int] = []
	for mask in solved_by:
		if not solved_by.any(func(other: int) -> bool: return mask != other and (mask & other) == other):
			minimal.append(mask)
	var solutions := Solver.find_solutions(board)
	var verified := false
	match row.difficulty:
		"BASE":
			verified = solved_by.has(0)
		"EASY":
			verified = not solved_by.has(0) and solved_by.has(Generation.R)
		"MEDIUM":
			verified = not solved_by.has(Generation.R) and (solved_by.has(Generation.R | Generation.P) != solved_by.has(Generation.R | Generation.C))
		"HARD":
			verified = solved_by.has(Analyzer.ALL_FAMILIES) and not solved_by.has(Generation.R | Generation.P) and not solved_by.has(Generation.R | Generation.C)
		"EXTRA HARD", "NIGHTMARES":
			var classic_solves := solved_by.any(func(mask: int) -> bool: return mask <= Analyzer.ALL_FAMILIES)
			var no_chains := Analyzer.ALL_FAMILIES | Analyzer.Family.TRIPLES
			var chains_needed := not solved_by.any(func(mask: int) -> bool: return (mask & Analyzer.Family.CHAINS) == 0)
			verified = not classic_solves and (solved_by.has(no_chains) if row.difficulty == "EXTRA HARD"
				else chains_needed and solved_by.has(Analyzer.EXTENDED_FAMILIES))
	row.merge({
		"rules": _valid_placement(board, solution, row.size), "unique": solutions == [solution],
		"logical": trace.status == Analyzer.Status.SOLVED and trace.bears == solution, "profile_verified": verified,
		"regions": Array(board), "solution": Array(solution), "locked_bears": Array(result.locked_bears),
		"solved_by": solved_by, "minimal_masks": minimal, "steps": trace.total_steps,
		"chain": trace.longest_chain, "choices": trace.choices_per_round,
		"techniques": trace.deductions.map(func(step: Dictionary) -> int: return step.technique),
	})
	if current:
		_calibration(row, board, trace, highest_mask)


func _calibration(row: Dictionary, board: PackedInt32Array, trace: Dictionary, families: int) -> void:
	var opening := []
	var chain_lengths := []
	var first_placement := false
	for step in trace.deductions:
		first_placement = first_placement or not step.confirmed.is_empty()
		if not first_placement:
			opening.append(step.eliminated.size())
		if step.has("implication_path"):
			chain_lengths.append(step.implication_path.size() - 1)
	var side: int = row.size
	var reflected := PackedInt32Array()
	for y in side:
		for x in range(side - 1, -1, -1):
			reflected.append(side - 1 - board[y * side + x])
	var trace_mask := families
	match row.difficulty:
		"BASE":
			trace_mask = 0
		"EASY":
			trace_mask = Generation.R
		"MEDIUM":
			trace_mask = (Generation.R | Generation.P) if row.solved_by.has(Generation.R | Generation.P) else (Generation.R | Generation.C)
		"EXTRA HARD":
			trace_mask = Generation.CLASSIC | Generation.T
	var mirrored := Analyzer.analyze_with_families(reflected, trace_mask)
	var lower := mirrored if row.difficulty != "NIGHTMARES" else Analyzer.analyze_with_families(reflected, families & ~Analyzer.Family.CHAINS)
	var reflected_answer := PackedInt32Array()
	for cell: int in row.solution:
		@warning_ignore("integer_division")
		reflected_answer.append((cell / side) * side + side - 1 - cell % side)
	row.merge({"opening_eliminations": opening, "eliminations": trace.candidate_eliminations,
		"placements": trace.forced_placements, "highest_complexity": trace.highest_complexity,
		"technique_counts": trace.technique_counts, "chain_lengths": chain_lengths,
		"reflected_solved": mirrored.status == Analyzer.Status.SOLVED and mirrored.bears == reflected_answer,
		"reflected_chain_free": lower.status == Analyzer.Status.SOLVED and lower.bears == reflected_answer,
		"reflected_order": mirrored.deductions.map(func(step: Dictionary) -> int: return step.technique)})
	if row.difficulty == "NIGHTMARES":
		var chain_free: int = families & ~Analyzer.Family.CHAINS
		var prefix := Analyzer.analyze_with_families(board, chain_free)
		var hall := Hall.extend(board, prefix, chain_free)
		var reasoner := Elimination.new()
		var alternative := Analyzer._analyze(board, chain_free, prefix, [], reasoner.moves.bind(true, false))
		row.hall_solved = hall.status == Analyzer.Status.SOLVED and hall.bears == PackedInt32Array(row.solution)
		row.contradiction_solved = alternative.status == Analyzer.Status.SOLVED and alternative.bears == PackedInt32Array(row.solution)
		row.hall_moves = hall.technique_counts.get(Analyzer.Technique.REGION_HALL_SET, 0)
		row.contradiction_moves = alternative.technique_counts.get(Analyzer.Technique.BOUNDED_CONTRADICTION, 0)


func _valid_placement(board: PackedInt32Array, solution: PackedInt32Array, side: int) -> bool:
	if Validator.board_size(board) != side or not Validator.is_valid_terrain(board) or solution.size() != side:
		return false
	var columns := {}
	var regions := {}
	var prior_column := -2
	for index in side:
		var bear := solution[index]
		var column := bear % side
		if bear < index * side or bear >= (index + 1) * side:
			return false
		if columns.has(column) or regions.has(board[bear]) or absi(column - prior_column) <= 1:
			return false
		columns[column] = true
		regions[board[bear]] = true
		prior_column = column
	return true

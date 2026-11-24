extends SceneTree

const Generation := preload("res://scripts/campaign_generation.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Construction := preload("res://scripts/nightmares_construction.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const Validator := preload("res://scripts/puzzle_validator.gd")
const DIFFICULTY := "EXTRA HARD"

var generation := Generation.new(false)


func _initialize() -> void:
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	var prefix := ProjectSettings.globalize_path("res://.godot/").replace("\\", "/") + "isolated-"
	if not expected.begins_with(prefix) or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "production":
		_check_production(args[1])
		return
	var holdout := args.size() == 2 and args[0] == "holdout"
	if holdout:
		_run_holdout(int(args[1]))
		return
	var input := FileAccess.open(args[0], FileAccess.READ) if args.size() == 1 else null
	var output := FileAccess.open("user://extra-hard-trial.jsonl", FileAccess.WRITE)
	if input == null or output == null:
		quit(1)
		return
	var roots := {7: [], 8: [], 9: []}
	var requests := {7: [], 8: [], 9: []}
	while input.get_position() < input.get_length():
		var row: Dictionary = JSON.parse_string(input.get_line())
		if row.difficulty != DIFFICULTY:
			continue
		if row.stage <= 5000 and row.status == "success":
			roots[int(row.size)].append({"regions": PackedInt32Array(row.regions), "solution": PackedInt32Array(row.solution), "report": {"deductions": []}})
		elif row.stage > 5000 and requests[int(row.size)].size() < 50:
			requests[int(row.size)].append(row)
	print("Writing ", ProjectSettings.globalize_path("user://extra-hard-trial.jsonl"))
	var invalid := 0
	for side: int in requests:
		if roots[side].is_empty() or requests[side].size() != 50:
			quit(1)
			return
		for row: Dictionary in requests[side]:
			for arm: String in ["control", "root_edit"]:
				var trial := _run(row, roots[side], arm)
				if trial.status == "success":
					invalid += int(not _audit(trial))
				output.store_line(JSON.stringify(trial))
			output.flush()
		print("Matched size ", side)
	print("EXTRA HARD invalid acceptances: ", invalid)
	quit(int(output.get_error() != OK or invalid != 0))


func _run(row: Dictionary, roots: Array, arm: String) -> Dictionary:
	var start := Time.get_ticks_usec()
	var budget := Generation.HIGHER_BUDGET
	var request := {"stage": int(row.stage), "size": int(row.size), "difficulty": DIFFICULTY}
	var result := generation.generate(request, int(row.seed), budget if arm == "control" else budget - Construction.ATTEMPTS)
	var entry := {"size": request.size, "stage": request.stage, "seed": int(row.seed), "arm": arm,
		"status": result.status, "source": "ordinary", "rejections": result.rejections, "parents": []}
	if result.status != "success" and arm != "control" and not roots.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(row.seed) + 170003
		entry.source = "root_edit"
		for attempt in Construction.ATTEMPTS:
			var root: Dictionary = roots[rng.randi_range(0, roots.size() - 1)]
			if root.has("id"):
				entry.parents.append(root.id)
			var moves := Construction.edits(root, request.size, false)
			if moves.is_empty():
				entry.rejections.no_edit = entry.rejections.get("no_edit", 0) + 1
				continue
			var edit := moves[rng.randi_range(0, moves.size() - 1)]
			var board: PackedInt32Array = root.regions.duplicate()
			board[edit.x] = edit.y
			var candidate := _verify(board, request.size, entry.rejections)
			if not candidate.is_empty():
				result = candidate
				entry.status = "success"
				entry.parent = root.get("id", "")
				break
	entry.usec = Time.get_ticks_usec() - start
	if entry.status == "success":
		entry.regions = Array(result.regions)
		entry.solution = Array(result.solution)
	return entry


func _verify(board: PackedInt32Array, size: int, rejections: Dictionary) -> Dictionary:
	var reason := "edit_structure"
	if Validator.is_valid_terrain(board):
		var solutions := Solver.search_connected_board(board, size)
		reason = "edit_multiple_solutions" if solutions.size() > 1 else "edit_no_solution"
		if solutions.size() == 1:
			var gate := Generation.assess_profile(DIFFICULTY, board)
			if gate.has("report") and gate.report.bears == solutions[0]:
				return {"regions": board, "solution": solutions[0]}
			reason = "edit_" + gate.get("reason", "proof_mismatch")
	rejections[reason] = rejections.get(reason, 0) + 1
	return {}


func _audit(entry: Dictionary) -> bool:
	var board := PackedInt32Array(entry.regions)
	var answer := PackedInt32Array(entry.solution)
	if Solver.find_solutions(board) != [answer]:
		return false
	for region in int(entry.size):
		if board.count(region) < 2:
			return false
	var solved := []
	var standard := Analyzer.ALL_FAMILIES | Analyzer.Family.TRIPLES
	for mask in range(Analyzer.EXTENDED_FAMILIES + 1):
		var proof := Analyzer.analyze_with_families(board, mask)
		if proof.status == Analyzer.Status.SOLVED:
			if proof.bears != answer or mask <= Analyzer.ALL_FAMILIES:
				return false
			solved.append(mask)
			if mask == standard:
				entry.trace = proof.deductions.map(func(step: Dictionary) -> int: return step.technique)
				entry.depth = proof.longest_chain
	entry.solved_masks = solved
	return solved.has(Analyzer.ALL_FAMILIES | Analyzer.Family.TRIPLES)



## A separately seeded catalog models shipping roots without a player's campaign archive.
## The empty arm starts a session with no catalog and promotes only ordinary successes.
func _run_holdout(side: int) -> void:
	var output := FileAccess.open("user://extra-hard-holdout.jsonl", FileAccess.WRITE)
	if output == null or side not in [7, 8, 9]:
		quit(1)
		return
	print(ProjectSettings.globalize_path("user://extra-hard-holdout.jsonl"))
	var roots: Array = []
	var empty_roots: Array = []
	var invalid := 0
	var catalog_start := Time.get_ticks_usec()
	for index in 240:
		var request := {"difficulty": DIFFICULTY, "size": side}
		var root := generation.generate(request, 2200000 + 1000 * side + index)
		if root.status == "success":
			invalid += int(not _add_root(roots, output, root, side, "catalog", index))
	output.store_line(JSON.stringify({"kind": "catalog_timing", "usec": Time.get_ticks_usec() - catalog_start, "count": roots.size()}))
	if roots.is_empty() or invalid:
		quit(1)
		return
	for index in 300:
		var row := {"stage": index, "size": side, "seed": 4300000 + 1000 * side + index}
		for arm: String in ["control", "root_edit", "empty_start"]:
			var pool := empty_roots if arm == "empty_start" else roots
			# With no roots available, spend the full budget on ordinary construction.
			var trial := _run(row, pool, "control" if pool.is_empty() else arm)
			trial.arm = arm
			trial.pool_size = pool.size()
			if trial.status == "success":
				invalid += int(not _audit(trial))
				if arm == "empty_start" and trial.source == "ordinary":
					invalid += int(not _add_root(empty_roots, output, trial, side, "earned", index))
			output.store_line(JSON.stringify(trial))
		if index % 25 == 24:
			output.flush()
			print("Size ", side, " requests ", index + 1)
	output.flush()
	print("Invalid proofs: ", invalid)
	quit(int(output.get_error() != OK or invalid != 0))


func _add_root(pool: Array, output: FileAccess, result: Dictionary, side: int, source: String, index: int) -> bool:
	var id := "%s-%d-%d" % [source, side, index]
	var entry := {"kind": "root", "id": id, "size": side, "source": source,
		"regions": Array(result.regions), "solution": Array(result.solution)}
	if not result.has("trace") and not _audit(entry):
		return false
	if result.has("trace"):
		entry.trace = result.trace
		entry.depth = result.depth
		entry.solved_masks = result.solved_masks
	output.store_line(JSON.stringify(entry))
	pool.append({"id": id, "regions": PackedInt32Array(entry.regions),
		"solution": PackedInt32Array(entry.solution), "report": {"deductions": []}})
	return true


func _check_production(path: String) -> void:
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		quit(1)
		return
	var warm := Generation.new()
	var checked := 0
	var edited := 0
	while input.get_position() < input.get_length():
		var row: Dictionary = JSON.parse_string(input.get_line())
		if row.get("arm") != "root_edit":
			continue
		var request := {"difficulty": DIFFICULTY, "size": int(row.size)}
		for service: RefCounted in [warm, Generation.new()]:
			var result: Dictionary = service.generate(request, int(row.seed))
			if result.status != row.status:
				push_error("Production status differs at seed %d." % int(row.seed))
				quit(1)
				return
			if result.status == "success" and (result.regions != PackedInt32Array(row.regions)
				or result.solution != PackedInt32Array(row.solution)):
				push_error("Production board differs at seed %d." % int(row.seed))
				quit(1)
				return
		checked += 1
		edited += int(row.has("parent"))
	print("Production parity requests: ", checked, ", root edits: ", edited)
	quit(int(checked != 300 or edited == 0))

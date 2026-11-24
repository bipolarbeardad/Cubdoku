extends SceneTree

const Gen := preload("res://scripts/campaign_generation.gd")
const Grow := preload("res://scripts/puzzle_generator.gd")
const Repair := preload("res://scripts/candidate_boundary_repair.gd")
const Check := preload("res://scripts/puzzle_validator.gd")
const Solve := preload("res://scripts/puzzle_solver.gd")
const Logic := preload("res://scripts/difficulty_analyzer.gd")

var grower := Grow.new()
var invalid := 0


func _initialize() -> void:
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	var prefix := ProjectSettings.globalize_path("res://.godot/").replace("\\", "/") + "isolated-"
	var args := OS.get_cmdline_user_args()
	var side := int(args[0]) if args.size() == 1 else 0
	if not expected.begins_with(prefix) or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected or side not in [7, 8, 9]:
		quit(1)
		return
	var out := FileAccess.open("user://terrain-construction.jsonl", FileAccess.WRITE)
	if out == null:
		quit(1)
		return
	print(ProjectSettings.globalize_path("user://terrain-construction.jsonl"))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Gen.EXTRA_HARD_CATALOG))
	var roots: Array = catalog[str(side)]
	var production := Gen.new()
	for request in 12:
		var seed_value := 6180000 + side * 1000 + request
		var chooser := RandomNumberGenerator.new()
		chooser.seed = seed_value
		# Sample without replacement within size to avoid repeatedly conditioning on one parent.
		var parent := (request * 17 + int(roots.size() / 2.0)) % roots.size()
		var columns := PackedInt32Array()
		if not grower._place_seed_bears(chooser, side, 0, -2, columns):
			quit(1)
			return
		for arm in ["bear_first", "terrain_first", "joint", "root_edit", "root_regrow"]:
			_experiment(out, side, request, seed_value, arm, columns, roots[parent], parent)
		var r := _record(side, request, -1, "production")
		var start := Time.get_ticks_usec()
		var result := production.generate({"difficulty": "EXTRA HARD", "size": side}, seed_value)
		r.usec = Time.get_ticks_usec() - start
		r.unique_usec = result.phase_usec.uniqueness
		r.proof_usec = result.phase_usec.difficulty
		r.status = "accepted" if result.status == "success" else "exhausted"
		r.rejections = result.rejections
		r.edited = result.get("construction_source") == "root_edit"
		if r.status == "accepted":
			r.regions = Array(result.regions)
			r.witnessed = Array(result.solution)
			_audit(r, result.regions, result.solution, result.report)
		out.store_line(JSON.stringify(r))
		out.flush()
		print("Completed ", side, " request ", request + 1)
	print("Verification failures: ", invalid)
	quit(int(out.get_error() != OK or invalid != 0))


func _record(side: int, request: int, attempt: int, arm: String) -> Dictionary:
	return {"side": side, "request": request, "attempt": attempt, "arm": arm, "status": "construction",
		"anchor": [], "witnessed": [], "regions": [], "usec": 0, "unique_usec": 0, "proof_usec": 0,
		"edited": false, "reanchored": false, "trace": [], "opening": 0, "masks": [], "parent": -1}


func _experiment(out: FileAccess, side: int, request: int, seed_value: int, arm: String,
	columns: PackedInt32Array, root: Dictionary, parent: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 110003
	var repair := Repair.new(side)
	var fixed := PackedInt32Array()
	if arm == "bear_first":
		for row in side:
			fixed.append(row * side + columns[row])
	elif arm in ["root_edit", "root_regrow"]:
		fixed = PackedInt32Array(root.solution)
	var growth_columns := PackedInt32Array()
	for cell in fixed:
		growth_columns.append(cell % side)
	var board := PackedInt32Array()
	var witnesses: Array[PackedInt32Array] = []
	var previous := -1
	var last_anchor := PackedInt32Array()
	for attempt in Gen.HIGHER_BUDGET:
		var rec := _record(side, request, attempt, arm)
		var start := Time.get_ticks_usec()
		rec.anchor = Array(fixed)
		if arm in ["root_edit", "root_regrow"]:
			rec.parent = parent
		var move := -1
		if arm == "root_edit":
			board = PackedInt32Array(root.regions)
			move = _random_edit(board, fixed, side, rng)
			if move < 0:
				board.clear()
			rec.edited = move >= 0
		elif arm == "root_regrow":
			board = _grow_around(rng, side, growth_columns)
		else:
			if attempt % 4 != 0 and witnesses.size() == 2:
				if arm == "terrain_first":
					move = _random_edit(board, PackedInt32Array(), side, rng)
				else:
					var chosen := fixed
					if arm == "joint":
						chosen = witnesses[1] if witnesses[0] == last_anchor else witnesses[0]
					var alternatives: Array[PackedInt32Array] = []
					for witness in witnesses:
						if witness != chosen:
							alternatives.append(witness)
					move = repair.apply_scored_move(board, _anchors_by_region(board, chosen, side),
						alternatives, rng, previous, {})
					if move >= 0:
						rec.anchor = Array(chosen)
						rec.reanchored = arm == "joint" and not last_anchor.is_empty() and chosen != last_anchor
						last_anchor = chosen
				rec.edited = move >= 0
			if move < 0:
				board = _grow_around(rng, side, growth_columns) if arm == "bear_first" else _terrain(rng, side)
				last_anchor = PackedInt32Array()
		previous = move
		witnesses = _evaluate(rec, board, side)
		rec.usec = Time.get_ticks_usec() - start
		if rec.status == "accepted":
			_audit(rec, board, witnesses[0], rec.proof)
			rec.erase("proof")
		out.store_line(JSON.stringify(rec))


func _grow_around(rng: RandomNumberGenerator, side: int, columns: PackedInt32Array) -> PackedInt32Array:
	return grower.grow_seeded_candidate(rng, side, false, PackedInt32Array(), true, {"chain": false}, columns)


func _anchors_by_region(board: PackedInt32Array, bears: PackedInt32Array, side: int) -> PackedInt32Array:
	var anchors := PackedInt32Array()
	anchors.resize(side)
	for cell in bears:
		anchors[board[cell]] = cell
	return anchors


func _random_edit(board: PackedInt32Array, fixed: PackedInt32Array, side: int, rng: RandomNumberGenerator) -> int:
	var moves := Repair.root_edits(board, fixed, side)
	if moves.is_empty():
		return -1
	var edit := moves[rng.randi_range(0, moves.size() - 1)]
	board[edit.x] = edit.y
	return edit.x


func _terrain(rng: RandomNumberGenerator, side: int) -> PackedInt32Array:
	var board := PackedInt32Array()
	board.resize(side * side)
	board.fill(-1)
	var frontier := PackedInt32Array()
	for region in side:
		var cell := rng.randi_range(0, board.size() - 1)
		while board[cell] >= 0:
			cell = (cell + 1) % board.size()
		board[cell] = region
		frontier.append(cell)
	var remaining := board.size() - side
	while remaining > 0:
		var index := rng.randi_range(0, frontier.size() - 1)
		var cell := frontier[index]
		var open := PackedInt32Array()
		for other in Check.orthogonal_neighbors(cell, side):
			if board[other] == -1:
				open.append(other)
		if open.is_empty():
			frontier.remove_at(index)
			continue
		var neighbor := open[rng.randi_range(0, open.size() - 1)]
		board[neighbor] = board[cell]
		frontier.append(neighbor)
		remaining -= 1
	return board


func _evaluate(rec: Dictionary, board: PackedInt32Array, side: int) -> Array[PackedInt32Array]:
	rec.regions = Array(board)
	if board.is_empty():
		return []
	if not Check.is_valid_terrain(board):
		rec.status = "structure"
		return []
	for region in side:
		if board.count(region) < 2:
			rec.status = "singleton"
			return []
	var start := Time.get_ticks_usec()
	var solutions := Solve.search_connected_board(board, side)
	rec.unique_usec = Time.get_ticks_usec() - start
	if solutions.is_empty():
		rec.status = "no_solution"
	elif solutions.size() > 1:
		rec.witnessed = Array(solutions[0])
		rec.status = "multiple"
	else:
		rec.witnessed = Array(solutions[0])
		start = Time.get_ticks_usec()
		var gate := Gen.assess_profile("EXTRA HARD", board)
		rec.proof_usec = Time.get_ticks_usec() - start
		rec.status = gate.get("reason", "accepted")
		if rec.status == "accepted":
			rec.proof = gate.report
	return solutions


func _audit(rec: Dictionary, board: PackedInt32Array, answer: PackedInt32Array, proof: Dictionary) -> void:
	invalid += int(Solve.find_solutions(board) != [answer] or proof.bears != answer)
	var first := false
	for step: Dictionary in proof.deductions:
		rec.trace.append(step.technique)
		first = first or not step.confirmed.is_empty()
		if not first:
			rec.opening += step.eliminated.size()
		for cell: int in step.eliminated:
			invalid += int(answer.has(cell))
	for mask in 16:
		var alternate := Logic.analyze_with_families(board, mask)
		if alternate.status == Logic.Status.SOLVED:
			rec.masks.append(mask)
			invalid += int(mask < 8 or alternate.bears != answer)
	invalid += int(not rec.masks.has(15))
	# A relabeling also changes logical group scan order; the visual-only map never enters either solver.
	var remapped := PackedInt32Array()
	var side: int = rec.side
	for region in board:
		remapped.append(side - 1 - region)
	var gate := Gen.assess_profile("EXTRA HARD", remapped)
	rec.relabel_gate = gate.get("reason", "accepted")
	rec.relabel_trace_changed = gate.has("report") and gate.report.deductions.map(func(step: Dictionary) -> int: return step.technique) != rec.trace
	invalid += int(Solve.find_solutions(remapped) != [answer])

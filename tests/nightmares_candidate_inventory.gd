extends SceneTree

const Service := preload("res://scripts/free_play_generation.gd")
const Layout := preload("res://scripts/nightmares_construction.gd")
const Validator := preload("res://scripts/puzzle_validator.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const Generator := preload("res://scripts/puzzle_generator.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Reasoning := preload("res://scripts/nightmares_elimination.gd")
const Hall := preload("res://scripts/nightmares_hall_reasoning.gd")
const CHAIN_FREE := Analyzer.EXTENDED_FAMILIES & ~Analyzer.Family.CHAINS

func _initialize() -> void:
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	if not expected.begins_with(ProjectSettings.globalize_path("res://.godot/") + "isolated-") or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		quit(1)
		return
	var service := Service.new(-1, false)
	var roots: Dictionary = service.get("_roots")
	var reserve: Dictionary = service.get("_reserve")
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var stream := FileAccess.open(args[0], FileAccess.READ)
	if not stream:
		quit(1)
		return
	var served := {}
	while stream.get_position() < stream.get_length():
		var row: Dictionary = JSON.parse_string(stream.get_line())
		if row.source != "unfulfilled":
			var keys: Dictionary = served.get_or_add(int(row.size), {})
			keys[Layout.layout_key(PackedInt32Array(row.regions), int(row.size))] = true
	for size in [8, 9, 10]:
		_audit(size, roots[str(size)], reserve[str(size)], served.get(size, {}))
	quit()


func _audit(size: int, roots: Array, reserve: Array, served: Dictionary) -> void:
	var stats := Layout.new_stats()
	var keys := {}
	var in_reserve := {}
	var alternate_counters := {}
	for raw in reserve:
		in_reserve[Layout.layout_key(PackedInt32Array(raw), size)] = true
	var proposals := 0
	var overlap := 0
	var misses := []
	var not_seen := 0
	var examined := {}
	var fixed_columns := PackedInt32Array()
	for raw in roots:
		var root := Layout.verify(PackedInt32Array(raw), size, Layout.new_stats())
		if fixed_columns.is_empty():
			for cell in root.solution:
				fixed_columns.append(cell % size)
		for edit in Layout.edits(root, size):
			proposals += 1
			var board: PackedInt32Array = root.regions.duplicate()
			board[edit.x] = edit.y
			var result := Layout.verify(board, size, stats)
			if not result.is_empty():
				keys[Layout.layout_key(board, size)] = true
				continue
			if Validator.is_valid_terrain(board) and examined.size() < 36:
				var identity := str(board)
				if examined.has(identity):
					continue
				var answers := Solver.search_connected_board(board, size)
				if answers.size() == 1:
					examined[identity] = true
					_gate_sample(board, size, answers[0], alternate_counters)
	overlap = keys.keys().filter(func(key: String) -> bool: return in_reserve.has(key)).size()
	for key in keys:
		if not served.has(key):
			not_seen += 1
			misses.append(key)
	var union := in_reserve.duplicate()
	union.merge(keys)
	var unserved_union := union.keys().filter(func(key: String) -> bool: return not served.has(key))
	var outside_union := served.keys().filter(func(key: String) -> bool: return not union.has(key))
	assert(unserved_union.is_empty() and outside_union.is_empty(), "Benchmark served exactly the validated inventory")
	print(size, " proposals ", proposals, " accepted unique layout keys ", keys.size(), " overlap ", overlap,
		" reserve ", in_reserve.size(), " union ", union.size(), " served ", served.size(), " eligible never served ", not_seen,
		" counters ", stats, " missing fresh ", misses, " missing union ", unserved_union, " outside union ", outside_union)
	print(size, " unique rejection sample ", alternate_counters)
	_compare_growth(size, fixed_columns)


func _gate_sample(board: PackedInt32Array, side: int, solution: PackedInt32Array, counts: Dictionary) -> void:
	var reason: String = Layout.Generation.assess_profile("NIGHTMARES", board).get("reason", "accepted")
	counts[reason] = counts.get(reason, 0) + 1
	if reason == "chain_stall":
		var proof := Reasoning.new().analyze(board, Analyzer.EXTENDED_FAMILIES)
		if proof.status == Analyzer.Status.SOLVED and proof.bears == solution:
			counts["chain_stall_rescued_by_opt_in"] = counts.get("chain_stall_rescued_by_opt_in", 0) + 1
			var lower := false
			for mask in range(CHAIN_FREE + 1):
				lower = lower or Analyzer.analyze_with_families(board, mask).status == Analyzer.Status.SOLVED
			var simple := Analyzer.analyze_with_families(board, CHAIN_FREE)
			var hall_only := Hall.extend(board, simple, CHAIN_FREE)
			var sound := true
			for step in proof.deductions:
				for cell in step.eliminated:
					sound = sound and not solution.has(cell)
			var qualifies: bool = not lower and hall_only.status != Analyzer.Status.SOLVED and sound and proof.technique_counts.has(
				Analyzer.Technique.BOUNDED_CONTRADICTION)
			counts["contradiction_required_in_tested_schedule"] = counts.get("contradiction_required_in_tested_schedule", 0) + int(qualifies)
			counts["contradiction_steps"] = counts.get("contradiction_steps", 0) + proof.technique_counts.get(
				Analyzer.Technique.BOUNDED_CONTRADICTION, 0)
	var mirror := PackedInt32Array()
	for row in side:
		for column in range(side - 1, -1, -1):
			mirror.append(side - 1 - board[row * side + column])
	var other: String = Layout.Generation.assess_profile("NIGHTMARES", mirror).get("reason", "accepted")
	if other != reason:
		var key := reason + " -> " + other
		counts[key] = counts.get(key, 0) + 1


func _compare_growth(side: int, columns: PackedInt32Array) -> void:
	var generator := Generator.new()
	for mode in ["ordinary", "swap_guided", "chain_guided"]:
		var stats := Layout.new_stats()
		var accepted := 0
		for offset in 24:
			var random := RandomNumberGenerator.new()
			random.seed = 606000 + side * 100 + offset
			var plan := {} if mode == "ordinary" else {"chain": mode == "chain_guided"}
			var board := generator.grow_seeded_candidate(random, side, false, PackedInt32Array(), true, plan, columns)
			accepted += int(not Layout.verify(board, side, stats).is_empty())
		print(side, " same anchors ", mode, " accepted ", accepted, "/24 ", stats)

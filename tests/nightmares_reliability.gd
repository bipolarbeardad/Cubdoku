extends SceneTree

const Construction := preload("res://scripts/nightmares_construction.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Hall := preload("res://scripts/nightmares_hall_reasoning.gd")
const Generation := preload("res://scripts/campaign_generation.gd")
const GameState := preload("res://scripts/puzzle_game_state.gd")
const TARGET := 120
const MAX_POOL_EDITS := 8000

var failures := 0


func _initialize() -> void:
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	var isolation := ProjectSettings.globalize_path("res://.godot/").replace("\\", "/")
	if not expected.begins_with(isolation + "isolated-") or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		push_error("Use tests/run_isolated.ps1")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--quality":
		_audit_quality(args[1])
		quit(0 if failures == 0 else 1)
		return
	if args.size() == 2 and args[0] == "--verify-reserve":
		_recheck_reserve_proofs(args[1])
		quit(0 if failures == 0 else 1)
		return
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/nightmares_seeds.json"))
	var output := {}
	for side in [8, 9, 10]:
		var roots: Array[Dictionary] = []
		var stats := Construction.new_stats()
		var excluded := {}
		for raw in source[str(side)]:
			var board := PackedInt32Array(raw)
			var entry := Construction.verify(board, side, stats)
			if entry.is_empty():
				failures += 1
				continue
			entry.key = Construction.layout_key(board, side)
			if not excluded.has(entry.key):
				roots.append(entry)
				excluded[entry.key] = true
		if roots.is_empty():
			failures += 1
			continue
		if "--diversity" in args:
			var existing: Array[Dictionary] = roots.duplicate()
			var control_excluded := excluded.duplicate()
			_add_procedural_roots(side, roots, excluded)
			var control_reserve := _build_reserve(side, existing, control_excluded)
			output["control_" + str(side)] = _benchmark(side, existing, control_reserve)
		var reserve := _build_reserve(side, roots, excluded)
		output[str(side)] = _benchmark(side, roots, reserve)
		if "--diversity" in args:
			output[str(side)].reserve_audit = _audit_reserve(side, reserve)
		if "--control" in OS.get_cmdline_user_args():
			_compare_control(side)
	var file := FileAccess.open("user://nightmares-results.json", FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(output))
		print("Results: ", ProjectSettings.globalize_path("user://nightmares-results.json"))
	else:
		failures += 1
	print("NIGHTMARES test failures: ", failures)
	quit(0 if failures == 0 else 1)


func _build_reserve(side: int, roots: Array[Dictionary], excluded: Dictionary) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var queue: Array[Dictionary] = roots.duplicate()
	var tried := 0
	var index := 0
	var stats := Construction.new_stats()
	while index < queue.size() and pool.size() < TARGET and tried < MAX_POOL_EDITS:
		var parent := queue[index]
		index += 1
		for edit in Construction.edits(parent, side):
			if pool.size() >= TARGET or tried >= MAX_POOL_EDITS:
				break
			tried += 1
			var entry := Construction.try_edit(parent, edit, side, excluded, stats)
			if not entry.is_empty():
				excluded[entry.key] = true
				queue.append(entry)
				pool.append(entry)
	print(side, " reserve ", pool.size(), " from ", roots.size(), " roots and ", tried, " evaluated edits ", stats)
	return pool


func _add_procedural_roots(side: int, roots: Array[Dictionary], excluded: Dictionary) -> void:
	var generator := Generation.new()
	var stats := Construction.new_stats()
	var start := roots.size()
	for index in 48:
		var result := generator.generate({"difficulty": "NIGHTMARES", "size": side}, 922001 + side * 1000 + index)
		if result.status != "success":
			continue
		var entry := Construction.verify(result.regions, side, stats)
		if entry.is_empty():
			failures += 1
			continue
		entry.key = Construction.layout_key(entry.regions, side)
		if not excluded.has(entry.key):
			roots.append(entry)
			excluded[entry.key] = true
	print(side, " procedural root search added ", roots.size() - start, "/48")


func _audit_reserve(side: int, reserve: Array[Dictionary]) -> Dictionary:
	var used := {}
	var stats := Construction.new_stats()
	var boards := []
	var worst := 0
	var sum_usec := 0
	var started := Time.get_ticks_usec()
	for entry in reserve:
		var verified := Construction.verify(entry.regions, side, Construction.new_stats())
		if verified.is_empty() or verified.solution != entry.solution or verified.report != entry.report:
			failures += 1
		boards.append({"size": side, "regions": Array(entry.regions), "solution": Array(entry.solution)})
	var verification_ms := (Time.get_ticks_usec() - started) / 1000.0
	for index in reserve.size():
		started = Time.get_ticks_usec()
		var result := Construction.request(side, 881000 + index, [], reserve, used, stats)
		var usec := Time.get_ticks_usec() - started
		sum_usec += usec
		worst = maxi(worst, usec)
		if result.get("source") != "reserve" or used.has(result.key):
			failures += 1
			continue
		used[result.key] = true
	for index in 10:
		if not Construction.request(side, index, [], reserve, used, stats).is_empty():
			failures += 1
	if stats.reserve_exhausted != 10 or used.size() != reserve.size():
		failures += 1
	print(side, " reserve drain ", used.size(), " served, ", stats.reserve_exhausted,
		" explicit exhaustion events, lookup mean/worst us ", float(sum_usec) / maxi(1, used.size()), "/", worst)
	return {"boards": boards, "exhausted": stats.reserve_exhausted, "verification_ms": verification_ms,
		"mean_lookup_usec": float(sum_usec) / maxi(1, used.size()), "worst_lookup_usec": worst}


func _recheck_reserve_proofs(path: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		failures += 1
		return
	for side in [8, 9, 10]:
		var boards: Array = data[str(side)].reserve_audit.boards
		for entry in boards:
			var board := PackedInt32Array(entry.regions)
			var proof := Analyzer.analyze_with_families(board, Analyzer.EXTENDED_FAMILIES)
			if proof.status != Analyzer.Status.SOLVED or proof.bears != PackedInt32Array(entry.solution):
				failures += 1
			for mask in range((Generation.CLASSIC | Generation.T) + 1):
				if Analyzer.analyze_with_families(board, mask).status != Analyzer.Status.STUCK:
					failures += 1
		print(side, " independently reran full and all chain-free proofs for ", boards.size(), " reserve boards")
	print("NIGHTMARES reserve proof failures: ", failures)


func _benchmark(side: int, roots: Array[Dictionary], reserve: Array[Dictionary]) -> Dictionary:
	var used := {}
	var stats := Construction.new_stats()
	var outcomes := {"fresh": 0, "reserve": 0, "failed": 0}
	var solutions := {}
	var longest_path := 0
	var min_depth := 999
	var max_depth := 0
	var total_usec := 0
	var worst_usec := 0
	var representatives := {}
	var mirror_shortcuts := 0
	var hall_substitutions := 0
	var boards := []
	for index in TARGET:
		var started := Time.get_ticks_usec()
		var result := Construction.request(side, 730001 + side * 1000 + index, roots, reserve, used, stats)
		var usec := Time.get_ticks_usec() - started
		total_usec += usec
		worst_usec = maxi(worst_usec, usec)
		if result.is_empty():
			outcomes.failed += 1
			continue
		var checked := Construction.verify(result.regions, side, Construction.new_stats())
		if checked.is_empty() or checked.solution != result.solution or checked.report != result.report or used.has(result.key):
			failures += 1
		outcomes[result.source] += 1
		used[result.key] = true
		solutions[str(result.solution)] = true
		var path_edges := 0
		var chain_moves := 0
		for step in result.report.deductions:
			if step.has("implication_path"):
				path_edges = maxi(path_edges, step.implication_path.size() - 1)
				chain_moves += 1
		longest_path = maxi(longest_path, path_edges)
		min_depth = mini(min_depth, result.report.longest_chain)
		max_depth = maxi(max_depth, result.report.longest_chain)
		var signature := "%d links / %d chain moves" % [path_edges, chain_moves]
		if not representatives.has(signature):
			var reflected := PackedInt32Array()
			for row in side:
				for column in range(side - 1, -1, -1):
					reflected.append(result.regions[row * side + column])
			mirror_shortcuts += int(Generation.assess_profile("NIGHTMARES", reflected).get("reason", "") in [
				"easier_classic", "easier_extra_hard", "easier_without_chains"])
			var simpler := Analyzer.analyze_with_families(result.regions, Generation.CLASSIC | Generation.T)
			if simpler.status == Analyzer.Status.STUCK:
				var with_hall := Hall.extend(result.regions, simpler, Generation.CLASSIC | Generation.T)
				if with_hall.status == Analyzer.Status.SOLVED:
					hall_substitutions += 1
					failures += int(with_hall.bears != result.solution)
			representatives[signature] = {"regions": Array(result.regions), "solution": Array(result.solution),
				"dependency_depth": result.report.longest_chain}
		boards.append({"regions": Array(result.regions), "solution": Array(result.solution), "size": side})
	var metrics := {"outcomes": outcomes, "attempts": stats, "unique_layouts": used.size(),
		"bear_arrangements": solutions.size(), "mean_ms": float(total_usec) / TARGET / 1000,
		"worst_ms": float(worst_usec) / 1000, "longest_implication": longest_path,
		"dependency_range": [min_depth, max_depth], "representatives": representatives, "boards": boards,
		"mirror_shortcuts": mirror_shortcuts, "hall_substitutions": hall_substitutions}
	print(side, " runtime ", outcomes, " stats ", stats, " layouts ", used.size(), " solutions ", solutions.size(),
		" mean/worst ms ", metrics.mean_ms, "/", metrics.worst_ms, " proof signatures ", representatives.keys())
	if outcomes.failed:
		failures += outcomes.failed
	for entry in reserve:
		used[entry.key] = true
	if not Construction.request(side, 0, [], reserve, used, Construction.new_stats()).is_empty():
		failures += 1
	return metrics


func _compare_control(side: int) -> void:
	var generator := Generation.new()
	var successes := 0
	var multiple := 0
	var start := Time.get_ticks_msec()
	for index in 24:
		var result := generator.generate({"difficulty": "NIGHTMARES", "size": side}, 730001 + side * 1000 + index)
		successes += int(result.status == "success")
		multiple += result.rejections.get("multiple_solutions", 0)
	print(side, " legacy control ", successes, "/24 at 64 candidates, ambiguous rejects ", multiple,
		", wall time ms ", Time.get_ticks_msec() - start)


func _audit_quality(path: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		failures += 1
		return
	for side in [8, 9, 10]:
		var link_interactions := {}
		var followthrough := Vector2i(side, 0)
		var representatives: Dictionary = data[str(side)].representatives
		for example: Dictionary in representatives.values():
			var board := PackedInt32Array(example.regions)
			var checked := Construction.verify(board, side, Construction.new_stats())
			if checked.is_empty():
				failures += 1
				continue
			var game := GameState.new()
			var solution: PackedInt32Array = checked.solution.duplicate()
			if not game.load_puzzle(board, solution):
				failures += 1
				continue
			solution.reverse()
			for bear in solution:
				failures += int(game.toggle_mark(bear, GameState.Mark.BEAR) != GameState.Result.CHANGED)
			failures += int(game.status != GameState.Status.COMPLETE)
			var after_chain := false
			var forced_after := 0
			var weak_constraints := 0
			for step in checked.report.deductions:
				if step.has("implication_path"):
					after_chain = true
					var literals: PackedInt32Array = step.implication_path
					for index in range(1, literals.size()):
						if literals[index - 1] % 2 == 0:
							weak_constraints |= Analyzer._conflict_mask(board, side, literals[index - 1] >> 1, literals[index] >> 1)
				elif after_chain:
					forced_after += step.confirmed.size()
			link_interactions[weak_constraints] = link_interactions.get(weak_constraints, 0) + 1
			followthrough.x = mini(followthrough.x, forced_after)
			followthrough.y = maxi(followthrough.y, forced_after)
		print(side, " quality: ", representatives.size(), " representatives, weak-link masks (row=1,column=2,region=4,diagonal=8) ",
			link_interactions, ", bears confirmed after first chain range ", followthrough)
	print("NIGHTMARES quality failures: ", failures)

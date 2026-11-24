extends SceneTree
## Proof analysis sees only the layout. The solution is compared afterward.

const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Hall := preload("res://scripts/nightmares_hall_reasoning.gd")
const Elimination := preload("res://scripts/nightmares_elimination.gd")
const Advanced := preload("res://scripts/difficulty_advanced_patterns.gd")
const CHAIN_FREE := Analyzer.EXTENDED_FAMILIES & ~Analyzer.Family.CHAINS

var failures := 0


func _initialize() -> void:
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	var sandbox := ProjectSettings.globalize_path("res://.godot/").replace("\\", "/") + "isolated-"
	if not expected.begins_with(sandbox) or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		push_error("Use tests/run_isolated.ps1")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args.size() > 3 or (args.size() >= 2 and args[1] != "--production"):
		quit(1)
		return
	var shard := int(args[2]) if args.size() == 3 else 0
	if shard not in [0, 8, 9, 10]:
		quit(1)
		return
	var input := FileAccess.open(args[0], FileAccess.READ)
	var output := FileAccess.open("user://nightmares-proofs.jsonl", FileAccess.WRITE)
	if not input or not output:
		quit(1)
		return
	print("Writing ", ProjectSettings.globalize_path("user://nightmares-proofs.jsonl"))
	var verified := 0
	var request_count := 0
	var cached := {}
	while input.get_position() < input.get_length():
		var row: Variant = JSON.parse_string(input.get_line())
		if not row is Dictionary:
			failures += 1
			continue
		request_count += 1
		if row.source == "unfulfilled" or (shard and row.size != shard):
			continue
		var started := Time.get_ticks_usec()
		# Exact repeats share an audit only when the claimed answer also matches.
		var key := str(row.regions) + ":" + str(row.solution)
		if not cached.has(key):
			cached[key] = _audit(PackedInt32Array(row.regions), int(row.size), PackedInt32Array(row.solution), args.size() >= 2)
		var proof: Dictionary = cached[key].duplicate()
		proof.usec = Time.get_ticks_usec() - started
		proof.index = int(row.index)
		output.store_line(JSON.stringify(proof))
		verified += 1
		if verified % 50 == 0:
			output.flush()
			print("Proofs checked: ", verified)
	output.flush()
	failures += int(output.get_error() != OK or request_count != 5000)
	output.close()
	print("NIGHTMARES proof audit failures: ", failures, " across ", verified, " accepted boards and ", cached.size(), " distinct audits")
	quit(int(failures != 0))


func _audit(board: PackedInt32Array, side: int, independent_solution: PackedInt32Array, production_only: bool) -> Dictionary:
	var proof := Elimination.new().analyze(board, Analyzer.EXTENDED_FAMILIES, PackedInt32Array(), PackedInt32Array(), true)
	var production := Analyzer.analyze_with_families(board, Analyzer.EXTENDED_FAMILIES)
	failures += int(production.status != Analyzer.Status.SOLVED or production.bears != independent_solution
		or production.deductions != proof.deductions)
	var overlap := _lower_shortcuts(board)
	failures += int(not overlap.is_empty())
	var phases := [{}, {}, {}]
	var steps := []
	var placements := 0
	var early_x := 0
	var chains := []
	for step in production.deductions:
		var phase := 0 if placements == 0 and step.confirmed.is_empty() else (1 if placements < side / 2.0 else 2)
		var key := Analyzer.Technique.keys()[step.technique] as String
		phases[phase][key] = phases[phase].get(key, 0) + 1
		if phase == 0:
			early_x += step.eliminated.size()
		placements += step.confirmed.size()
		steps.append([step.technique, Array(step.eliminated), Array(step.confirmed)])
		if step.has("implication_path"):
			chains.append(step.implication_path.size() - 1)
		for cell in step.eliminated:
			failures += int(independent_solution.has(cell))
	var initial := {}
	var initial_cells := {}
	var options: Array = proof.get("opening_options", [])
	for option in options:
		initial[str(option.eliminated) + ":" + str(option.get("confirmed", []))] = true
		for cell in option.eliminated:
			initial_cells[cell] = true
			failures += int(independent_solution.has(cell))
	var untouched := _untouched_moves(board, side)
	for cell in untouched.cells:
		failures += int(independent_solution.has(cell))
	var metrics := {"opening_x": early_x, "initial_moves": initial.size(), "initial_x_cells": initial_cells.size(),
		"untouched_moves": untouched.count, "untouched_cells": untouched.cells.size(),
		"untouched_families": untouched.families, "phases": phases, "trace": steps,
		"max_depth": production.longest_chain, "chains": chains, "lower_masks": overlap}
	if production_only:
		return metrics
	var chain_free := Analyzer.analyze_with_families(board, CHAIN_FREE)
	var hall := Hall.extend(board, chain_free, CHAIN_FREE) if chain_free.status == Analyzer.Status.STUCK else chain_free
	var branch := Elimination.new()
	var alternate := Analyzer._analyze(board, CHAIN_FREE, chain_free, [], branch.moves.bind(true, false)) if chain_free.status == Analyzer.Status.STUCK else chain_free
	for report in [hall, alternate]:
		failures += int(report.status == Analyzer.Status.SOLVED and report.bears != independent_solution)
		for step in report.deductions:
			for cell in step.eliminated:
				failures += int(independent_solution.has(cell))
	var reflected := PackedInt32Array()
	for y in side:
		for x in range(side - 1, -1, -1):
			reflected.append(side - 1 - board[y * side + x])
	var mirror := Analyzer.analyze_with_families(reflected, Analyzer.EXTENDED_FAMILIES)
	var reflected_answer := PackedInt32Array()
	for cell in independent_solution:
		@warning_ignore("integer_division")
		reflected_answer.append((cell / side) * side + side - 1 - cell % side)
	failures += int(mirror.status == Analyzer.Status.SOLVED and mirror.bears != reflected_answer)
	var mirror_signature := []
	for step in mirror.deductions:
		mirror_signature.append(step.technique)
	metrics.merge({"mirror_solved": mirror.status == Analyzer.Status.SOLVED,
		"mirror_shortcuts": _lower_shortcuts(reflected), "mirror_signature": mirror_signature,
		"hall_solved": hall.status == Analyzer.Status.SOLVED,
		"hall_moves": hall.technique_counts.get(Analyzer.Technique.REGION_HALL_SET, 0),
		"contradiction_solved": alternate.status == Analyzer.Status.SOLVED,
		"contradiction_moves": alternate.technique_counts.get(Analyzer.Technique.BOUNDED_CONTRADICTION, 0),
		"contradiction_probes": branch.probes})
	return metrics


func _untouched_moves(board: PackedInt32Array, side: int) -> Dictionary:
	var groups := Analyzer._make_groups(board, side)
	var candidates := PackedByteArray()
	candidates.resize(board.size())
	candidates.fill(1)
	var graph: Array[PackedInt32Array] = []
	var options: Array[Dictionary] = []
	for family in [1, 2, 4, 8, 16]:
		options.append_array(Analyzer._advanced_moves(groups, board, side, candidates, family, graph))
	options.append_array(Advanced.adjacency_triples(groups, graph, side, Analyzer.Technique.ADJACENCY_TRIPLE))
	options.append_array(Hall.moves(groups, board, side, candidates))
	var distinct := {}
	var cells := {}
	var families := {}
	for move in options:
		var eliminated: PackedInt32Array = move.eliminated.duplicate()
		eliminated.sort()
		distinct[str(eliminated)] = true
		var name: String = Analyzer.Technique.keys()[move.technique]
		families[name] = families.get(name, 0) + 1
		for cell in eliminated:
			cells[cell] = true
	return {"count": distinct.size(), "cells": cells, "families": families}


func _lower_shortcuts(board: PackedInt32Array) -> Array[int]:
	var found: Array[int] = []
	var graph: Array[PackedInt32Array] = []
	for mask in range(CHAIN_FREE + 1):
		if Analyzer.analyze_with_families(board, mask, graph).status == Analyzer.Status.SOLVED:
			found.append(mask)
	return found

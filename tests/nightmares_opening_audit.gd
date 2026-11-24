extends SceneTree
## Paired eight-attempt NIGHTMARES-only comparison. No reserve or campaign state.

const Construction := preload("res://scripts/nightmares_construction.gd")
const Sampler := preload("res://scripts/nightmares_bear_sampler.gd")
const Generator := preload("res://scripts/puzzle_generator.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Elimination := preload("res://scripts/nightmares_elimination.gd")
const Hall := preload("res://scripts/nightmares_hall_reasoning.gd")
const Validator := preload("res://scripts/puzzle_validator.gd")
const REQUESTS := 32
const CHAIN_FREE := Analyzer.EXTENDED_FAMILIES & ~Analyzer.Family.CHAINS

var failures := 0


func _initialize() -> void:
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	var isolation := ProjectSettings.globalize_path("res://.godot/").replace("\\", "/")
	if not expected.begins_with(isolation + "isolated-") or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		push_error("Use tests/run_isolated.ps1")
		quit(1)
		return
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/nightmares_seeds.json"))
	var summary := {}
	var sampler := Sampler.new()
	for side in [8, 9, 10]:
		var roots: Array[Dictionary] = []
		for raw in source[str(side)]:
			var entry := Construction.verify(PackedInt32Array(raw), side, Construction.new_stats())
			if entry.is_empty():
				failures += 1
			else:
				roots.append(entry)
		var count := sampler.count(side)
		failures += int(count != {8: 5242, 9: 47622, 10: 479306}[side])
		summary[str(side)] = {
			"legal_arrangements": count,
			"current": _measure(side, roots, sampler, "current"),
			"geometry_only": _measure(side, roots, sampler, "geometry_only"),
			"expanded": _measure(side, roots, sampler, "expanded"),
		}
	var file := FileAccess.open("user://nightmares-opening.json", FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(summary))
		print("Results: ", ProjectSettings.globalize_path("user://nightmares-opening.json"))
	else:
		failures += 1
	print("NIGHTMARES opening audit failures: ", failures)
	quit(0 if failures == 0 else 1)


func _measure(side: int, roots: Array[Dictionary], sampler: RefCounted, policy: String) -> Dictionary:
	var generator := Generator.new()
	var used := {}
	var anchors := {}
	var broad_stats := Construction.new_stats()
	var stats := Construction.new_stats()
	var boards := []
	var total_usec := 0
	var worst_usec := 0
	var broad_attempts := 0
	for index in REQUESTS:
		var seed_value := 481000 + side * 1000 + index
		var started := Time.get_ticks_usec()
		var result := {}
		if policy != "current":
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			for attempt in Construction.ATTEMPTS:
				if policy == "expanded" and attempt < 2:
					broad_attempts += 1
					var columns: PackedInt32Array = sampler.sample(side, rng)
					anchors[str(columns)] = true
					var placed := PackedInt32Array()
					var plan := {"chain": attempt == 0}
					var candidate := generator.grow_seeded_candidate(rng, side, false, placed, true, plan, columns)
					result = Construction.verify(candidate, side, broad_stats)
					if not result.is_empty():
						result.key = Construction.layout_key(candidate, side)
						if used.has(result.key):
							broad_stats.repeated += 1
							result = {}
						else:
							result.source = "new_arrangement"
				else:
					var parent := roots[rng.randi_range(0, roots.size() - 1)]
					var edits := Construction.edits(parent, side, false)
					if not edits.is_empty():
						result = Construction.try_edit(parent, edits[rng.randi_range(0, edits.size() - 1)], side, used, stats)
						if not result.is_empty():
							result.source = "loose_edit"
				if not result.is_empty():
					break
		else:
			result = Construction.request(side, seed_value, roots, [], used, stats)
		var elapsed := Time.get_ticks_usec() - started
		total_usec += elapsed
		worst_usec = maxi(worst_usec, elapsed)
		if result.is_empty():
			continue
		used[result.key] = true
		var opening := _opening(result, side)
		opening["size"] = side
		opening["regions"] = Array(result.regions)
		opening["solution"] = Array(result.solution)
		opening["source"] = result.source
		boards.append(opening)
	var result_summary := {"fulfilled": boards.size(), "requests": REQUESTS,
		"distinct_sampled_columns": anchors.size(), "broad_attempts": broad_attempts,
		"broad_rejections": broad_stats, "rejections": stats, "mean_usec": float(total_usec) / REQUESTS,
		"worst_usec": worst_usec, "boards": boards}
	print(side, " ", policy, " verified ", boards.size(), "/", REQUESTS,
		", sampled ", anchors.size(), "/", broad_attempts, " broad arrangements")
	return result_summary


func _opening(entry: Dictionary, side: int) -> Dictionary:
	var board: PackedInt32Array = entry.regions
	var solution: PackedInt32Array = entry.solution
	var groups := Analyzer._make_groups(board, side)
	var candidates := PackedByteArray()
	candidates.resize(board.size())
	candidates.fill(1)
	var untouched := {}
	for family in [1, 2, 4, 8, 16]:
		var moves := Analyzer._advanced_moves(groups, board, side, candidates, family, [])
		var cells := {}
		for move in moves:
			for cell in move.eliminated:
				cells[cell] = true
				failures += int(solution.has(cell))
		untouched[str(family)] = cells.keys()
	var hall := Hall.moves(groups, board, side, candidates)
	untouched["hall"] = [] if hall.is_empty() else Array(hall[0].eliminated)
	for cell in untouched.hall:
		failures += int(solution.has(cell))
	var production := _prefix(entry.report, solution)
	var classic := _prefix(Analyzer.analyze_with_families(board, Analyzer.ALL_FAMILIES), solution)
	var chain_free := Analyzer.analyze_with_families(board, CHAIN_FREE)
	var experimental := Elimination.new().analyze(board, CHAIN_FREE)
	failures += int(chain_free.status != Analyzer.Status.STUCK)
	var hall_only := Hall.extend(board, chain_free, CHAIN_FREE)
	var reasoning := Elimination.new()
	var contradiction_only := Analyzer._analyze(board, CHAIN_FREE, chain_free, [], reasoning.moves.bind(true, false))
	for report in [experimental, hall_only, contradiction_only]:
		for step in report.deductions:
			for cell in step.eliminated:
				failures += int(solution.has(cell))
		failures += int(report.status == Analyzer.Status.SOLVED and report.bears != solution)
	return {"untouched": untouched, "production": production, "classic": classic,
		"chain_free_opening": _prefix(chain_free, solution),
		"without_triples_opening": _prefix(Analyzer.analyze_with_families(
			board, Analyzer.EXTENDED_FAMILIES & ~Analyzer.Family.TRIPLES), solution),
		"experimental_solved": experimental.status == Analyzer.Status.SOLVED,
		"experimental_opening": _prefix(experimental, solution),
		"hall_only_solved": hall_only.status == Analyzer.Status.SOLVED,
		"contradiction_only_solved": contradiction_only.status == Analyzer.Status.SOLVED,
		"geometry": _geometry(board, groups, side)}


func _prefix(report: Dictionary, solution: PackedInt32Array) -> Dictionary:
	var cells := {}
	var techniques := []
	var max_depth := 0
	var first_bear := false
	for step in report.deductions:
		if not step.confirmed.is_empty():
			first_bear = true
			break
		techniques.append(step.technique)
		max_depth = maxi(max_depth, step.chain_depth)
		for cell in step.eliminated:
			cells[cell] = true
			failures += int(solution.has(cell))
	return {"steps": techniques.size(), "eliminations": cells.size(), "techniques": techniques,
		"dependency": max_depth, "first_bear": first_bear}


func _geometry(board: PackedInt32Array, groups: Array[PackedInt32Array], side: int) -> Dictionary:
	var spanning := 0
	var branches := 0
	var max_area := 0
	for region in side:
		var edges := 0
		max_area = maxi(max_area, groups[region].size())
		for cell in groups[region]:
			edges |= int(cell % side == 0) | (int(cell % side == side - 1) << 1)
			edges |= (int(cell < side) << 2) | (int(cell >= side * (side - 1)) << 3)
			var degree := 0
			for neighbor in Validator.orthogonal_neighbors(cell, side):
				degree += int(board[neighbor] == region)
			branches += int(degree >= 3)
		spanning += int((edges & 3) == 3 or (edges & 12) == 12)
	return {"spanning": spanning, "branch_cells": branches, "max_area": max_area}

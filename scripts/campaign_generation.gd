extends RefCounted
## Generates isolated campaign requests. The live campaign session does not use this service yet.

const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Difficulty := preload("res://scripts/puzzle_difficulty.gd")
const Generator := preload("res://scripts/puzzle_generator.gd")
const Schedule := preload("res://scripts/campaign_schedule.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const Validator := preload("res://scripts/puzzle_validator.gd")
const BoundaryRepair := preload("res://scripts/candidate_boundary_repair.gd")
const Construction := preload("res://scripts/construction_plan.gd")
const HIGHER_BUDGET := 64
const EXTRA_HARD_EDIT_BUDGET := 8
const EXTRA_HARD_CATALOG := "res://data/extra_hard_roots.json"
const WITNESS_LIMIT := 8
const AMBIGUITY_SAMPLE_LIMIT := 12
const R := Analyzer.Family.RESTRICTIONS
const P := Analyzer.Family.PAIRS
const C := Analyzer.Family.COMMON_CONFLICTS
const T := Analyzer.Family.TRIPLES
const I := Analyzer.Family.CHAINS
const CLASSIC := R | P | C

var _generator := Generator.new()
var _extra_hard_enabled: bool
var _extra_hard_catalog: Variant


func _init(extra_hard_enabled := true) -> void:
	_extra_hard_enabled = extra_hard_enabled


func generate(
	request: Dictionary, seed_value: int, higher_budget: int = HIGHER_BUDGET,
	guided: bool = true, optimized: bool = true, sample_ambiguity: bool = false,
	planned: bool = true, multi_row: bool = true, advanced_repair: bool = true,
) -> Dictionary:
	var result := {"status": "unsupported", "reason": "", "rejections": {}, "fallback": false,
		"phase_usec": {"construction": 0, "structure": 0, "uniqueness": 0, "repair": 0, "difficulty": 0, "diagnostic": 0},
		"repairs": {"ambiguity_attempts": 0, "no_edit": 0, "still_ambiguous": 0, "resolved": 0, "structural_failure": 0, "profile_pass": 0},
		"repair_gate_rejections": {}, "plans": {"starts": 0, "motifs": 0, "initial_swaps": 0, "checked_seeds": 0}}
	var difficulty: String = request.difficulty
	var side: int = request.size
	if not Schedule.SIZES.has(difficulty):
		result.reason = "unknown_difficulty"
		return result
	var range_for_difficulty: Vector2i = Schedule.SIZES[difficulty]
	if side < range_for_difficulty.x or side > range_for_difficulty.y:
		result.reason = "size_ineligible"
		return result
	if not Validator.supports_size(side):
		result.reason = "size_unsupported"
		return result

	if difficulty == Difficulty.BASE:
		var board := _generator.generate(seed_value, Generator.DEFAULT_ATTEMPTS, difficulty, side)
		result.rejections = {"base_constraints": _generator.rejected_attempts}
		result.fallback = _generator.used_fallback
		if not board.is_empty():
			return _accepted(result, request, board, Solver.find_solutions(board)[0], Analyzer.analyze(board))
	else:
		var roots: Array = []
		if _extra_hard_enabled and difficulty == "EXTRA HARD" and higher_budget > EXTRA_HARD_EDIT_BUDGET:
			roots = _extra_hard_roots(side)
		var edit_budget := 0 if roots.is_empty() else EXTRA_HARD_EDIT_BUDGET
		_generate_higher(result, request, seed_value, higher_budget - edit_budget, guided, optimized, sample_ambiguity,
			planned and optimized and guided, multi_row, advanced_repair)
		if result.status != "success" and edit_budget:
			_edit_extra_hard_roots(result, request, seed_value, roots)
		if result.status == "success":
			return result
	result.status = "failed"
	result.reason = "budget_exhausted"
	return result


func _extra_hard_roots(side: int) -> Array:
	if _extra_hard_catalog == null:
		var decoded: Variant = null
		if FileAccess.file_exists(EXTRA_HARD_CATALOG):
			decoded = JSON.parse_string(FileAccess.get_file_as_string(EXTRA_HARD_CATALOG))
		_extra_hard_catalog = decoded if decoded is Dictionary else {}
	var roots: Variant = _extra_hard_catalog.get(str(side), [])
	return roots if roots is Array else []


func _edit_extra_hard_roots(result: Dictionary, request: Dictionary, seed_value: int, roots: Array) -> void:
	var side: int = request.size
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 170003
	for attempt in EXTRA_HARD_EDIT_BUDGET:
		var started := Time.get_ticks_usec()
		var root: Variant = roots[rng.randi_range(0, roots.size() - 1)]
		if not root is Dictionary or not root.get("regions") is Array or not root.get("solution") is Array:
			_reject(result, "edit_invalid_root")
			continue
		var board := PackedInt32Array(root.regions)
		var answer := PackedInt32Array(root.solution)
		if Validator.board_size(board) != side or not Validator.is_valid_terrain(board) or answer.size() != side:
			_reject(result, "edit_invalid_root")
			continue
		var moves := BoundaryRepair.root_edits(board, answer, side)
		result.phase_usec.construction += Time.get_ticks_usec() - started
		if moves.is_empty():
			_reject(result, "edit_no_move")
			continue
		var edit := moves[rng.randi_range(0, moves.size() - 1)]
		board[edit.x] = edit.y
		started = Time.get_ticks_usec()
		var valid := Validator.is_valid_terrain(board) and not range(side).any(func(region: int) -> bool: return board.count(region) < 2)
		result.phase_usec.structure += Time.get_ticks_usec() - started
		if not valid:
			_reject(result, "edit_structure")
			continue
		started = Time.get_ticks_usec()
		var solutions := Solver.search_connected_board(board, side)
		result.phase_usec.uniqueness += Time.get_ticks_usec() - started
		if solutions.size() != 1 or solutions[0] != answer:
			_reject(result, "edit_multiple_solutions" if solutions.size() > 1 else "edit_solution_mismatch")
			continue
		started = Time.get_ticks_usec()
		var proof := assess_profile("EXTRA HARD", board)
		result.phase_usec.difficulty += Time.get_ticks_usec() - started
		if not proof.has("report") or proof.report.bears != answer:
			_reject(result, "edit_" + proof.get("reason", "proof_mismatch"))
			continue
		result.construction_source = "root_edit"
		_accepted(result, request, board, answer, proof.report)
		return


func _generate_higher(
	result: Dictionary, request: Dictionary, seed_value: int, budget: int,
	guided: bool, optimized: bool, sample_ambiguity: bool, planned: bool, multi_row: bool, advanced_repair: bool,
) -> void:
	var difficulty: String = request.difficulty
	var side: int = request.size
	planned = planned and difficulty in ["HARD", "EXTRA HARD", "NIGHTMARES"]
	advanced_repair = advanced_repair and planned and difficulty == "NIGHTMARES"
	# The matched pilot favored sampling for HARD. Keep the existing advanced
	# construction for EXTRA HARD and NIGHTMARES, where sampling reduced yield.
	multi_row = multi_row and planned and difficulty == "HARD"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var repair := BoundaryRepair.new(side)
	var anchors := PackedInt32Array()
	var alternate := PackedInt32Array()
	var witnesses: Array[PackedInt32Array] = []
	var board := PackedInt32Array()
	var earlier_proof := {}
	var witness_move := -1
	var starts := 0
	var plan := {}
	var swap_pairs: Array[Vector4i] = []
	var sampled_lineage := false
	var max_singletons: int = Difficulty.THRESHOLDS[difficulty].max_singletons
	var restart_interval := 16 if difficulty in ["EXTRA HARD", "NIGHTMARES"] else 8
	if optimized and side >= 8:
		restart_interval += 8
	for attempt in maxi(0, budget):
		var ambiguity_edit := false
		if guided and not board.is_empty() and attempt % restart_interval != 0:
			var repair_started := Time.get_ticks_usec()
			ambiguity_edit = not alternate.is_empty()
			if ambiguity_edit:
				result.repairs.ambiguity_attempts += 1
			if optimized:
				witness_move = repair.apply_scored_move(board, anchors, witnesses, rng, witness_move,
					earlier_proof, plan, advanced_repair)
			else:
				witness_move = repair.apply_move(board, anchors, alternate, rng, witness_move, earlier_proof)
			result.phase_usec.repair += Time.get_ticks_usec() - repair_started
			if ambiguity_edit and witness_move < 0:
				result.repairs.no_edit += 1
				ambiguity_edit = false
		else:
			witness_move = -1
		if witness_move < 0:
			var construction_started := Time.get_ticks_usec()
			witnesses.clear()
			sampled_lineage = false
			earlier_proof = {}
			plan = {"chain": difficulty == "NIGHTMARES"} if planned else {}
			var reserve := difficulty == "EASY" and starts % 2 == 0
			board = PackedInt32Array()
			if guided and (starts % 3 == 0 if advanced_repair else starts % 3 != (1 if planned else 2)):
				board = _generator.grow_proof_candidate(rng, side, anchors)
				_to_cells(anchors, side)
				if not board.is_empty() and (not reserve or rng.randi_range(0, 1) == 0):
					if not repair.expand_singleton(board, anchors, rng):
						board = PackedInt32Array()
			if board.is_empty():
				board = _generator.grow_seeded_candidate(rng, side, reserve, anchors, guided, plan)
				_to_cells(anchors, side)
				if planned:
					result.plans.starts += 1
					result.plans.motifs += int(plan.has("motif") and not board.is_empty())
			if sample_ambiguity or planned:
				var columns := PackedInt32Array()
				for anchor in anchors:
					columns.append(anchor % side)
				swap_pairs = Construction.swaps(columns)
				if not board.is_empty():
					result.plans.checked_seeds += 1
					result.plans.initial_swaps += Construction.live_witnesses(board, anchors, swap_pairs).size()
			starts += 1
			result.phase_usec.construction += Time.get_ticks_usec() - construction_started
		alternate = PackedInt32Array()
		# Retain the last easier proof as a scoring hint within this lineage.
		# The changed board still goes through fresh structural and proof checks.
		if not multi_row:
			earlier_proof = {}
		if board.is_empty():
			_reject(result, "construction")
			continue
		var structure_started := Time.get_ticks_usec()
		var valid := Validator.is_valid_terrain(board)
		var singletons := 0
		if valid:
			for region in side:
				singletons += int(board.count(region) == 1)
		result.phase_usec.structure += Time.get_ticks_usec() - structure_started
		if not valid:
			_reject(result, "terrain")
			if ambiguity_edit:
				result.repairs.structural_failure += 1
			board = PackedInt32Array()
			continue
		if singletons > max_singletons:
			_reject(result, "singleton_limit")
			if ambiguity_edit:
				result.repairs.structural_failure += 1
			board = PackedInt32Array()
			continue
		var uniqueness_started := Time.get_ticks_usec()
		var solutions := Solver.search_connected_board(board, side) if optimized else Solver.find_solutions(board)
		result.phase_usec.uniqueness += Time.get_ticks_usec() - uniqueness_started
		if solutions.size() != 1:
			_reject(result, "no_solution" if solutions.is_empty() else "multiple_solutions")
			if ambiguity_edit:
				if solutions.is_empty():
					result.repairs.structural_failure += 1
				else:
					result.repairs.still_ambiguous += 1
			if not solutions.is_empty():
				alternate = solutions[1] if solutions[0] == anchors else solutions[0]
				if optimized:
					var possible := solutions.duplicate()
					if planned:
						possible.append_array(Construction.live_witnesses(board, anchors, swap_pairs))
					# Sample once per seed lineage, while the normal uniqueness check
					# continues to stop after two solutions.
					if multi_row and not sampled_lineage and _changed_rows(anchors, alternate) >= 3:
						sampled_lineage = true
						var started := Time.get_ticks_usec()
						var expanded := Solver.search_connected_board(board, side, WITNESS_LIMIT)
						for witness in expanded:
							if _changed_rows(anchors, witness) >= 3:
								possible.append(witness)
						result.phase_usec.repair += Time.get_ticks_usec() - started
					for solution in possible:
						if solution != anchors and not witnesses.has(solution):
							if witnesses.size() == WITNESS_LIMIT:
								witnesses.pop_front()
							witnesses.append(solution)
				if sample_ambiguity and not result.has("ambiguity_sample"):
					_sample_ambiguity(result, board, side, anchors)
			continue
		if ambiguity_edit:
			result.repairs.resolved += 1
		var difficulty_started := Time.get_ticks_usec()
		var proof := assess_profile(difficulty, board)
		result.phase_usec.difficulty += Time.get_ticks_usec() - difficulty_started
		if proof.has("report"):
			if ambiguity_edit:
				result.repairs.profile_pass += 1
			_accepted(result, request, board, solutions[0], proof.report)
			return
		earlier_proof = proof.get("earlier_proof", proof.get("feedback", {}) if planned else {})
		if ambiguity_edit:
			result.repair_gate_rejections[proof.reason] = result.repair_gate_rejections.get(proof.reason, 0) + 1
		_reject(result, proof.reason)


static func _sample_ambiguity(result: Dictionary, board: PackedInt32Array, side: int, anchors: PackedInt32Array) -> void:
	var started := Time.get_ticks_usec()
	var sample := Solver.search_connected_board(board, side, AMBIGUITY_SAMPLE_LIMIT)
	var nearest := side
	var cycle_patterns := {}
	var nearest_witness := PackedInt32Array()
	for arrangement in sample:
		if arrangement == anchors:
			continue
		var changed := _changed_rows(anchors, arrangement)
		var pattern := _cycle_pattern(anchors, arrangement, side)
		cycle_patterns[pattern] = cycle_patterns.get(pattern, 0) + 1
		if changed < nearest or nearest_witness.is_empty():
			nearest = changed
			nearest_witness = arrangement
	var same_terrain := 0
	var boundary := 0
	if not nearest_witness.is_empty():
		for row in side:
			var cell := nearest_witness[row]
			if cell == anchors[row]:
				continue
			same_terrain += int(board[cell] == board[anchors[row]])
			for neighbor in Validator.orthogonal_neighbors(cell, side):
				if board[neighbor] != board[cell]:
					boundary += 1
					break
	result.ambiguity_sample = {"count": sample.size(), "cap": AMBIGUITY_SAMPLE_LIMIT,
		"nearest_rows_changed": nearest, "same_terrain_changes": same_terrain, "boundary_changes": boundary,
		"cycle_patterns": cycle_patterns}
	result.phase_usec.diagnostic += Time.get_ticks_usec() - started


static func _changed_rows(anchors: PackedInt32Array, alternate: PackedInt32Array) -> int:
	var changed := 0
	for row in anchors.size():
		changed += int(anchors[row] != alternate[row])
	return changed


static func _cycle_pattern(anchors: PackedInt32Array, alternate: PackedInt32Array, side: int) -> String:
	var owners := PackedInt32Array()
	owners.resize(side)
	for row in side:
		owners[anchors[row] % side] = row
	var visited := PackedByteArray()
	visited.resize(side)
	var lengths := PackedInt32Array()
	for row in side:
		var current := row
		var length := 0
		while not visited[current]:
			visited[current] = 1
			length += 1
			current = owners[alternate[current] % side]
		if length > 1:
			lengths.append(length)
	lengths.sort()
	var labels := PackedStringArray()
	for length in lengths:
		labels.append(str(length))
	return "+".join(labels)


static func _to_cells(columns: PackedInt32Array, side: int) -> void:
	for row in columns.size():
		columns[row] += row * side


## Checks proof necessity using restricted runs, even if the full trace uses stronger moves.
static func assess_profile(difficulty: String, board: PackedInt32Array) -> Dictionary:
	if difficulty in ["EXTRA HARD", "NIGHTMARES"]:
		return _assess_extended(difficulty, board)
	if difficulty not in ["EASY", "MEDIUM", "HARD"]:
		return {"reason": "unsupported_profile"}
	var basic := Analyzer.analyze(board)
	if basic.status == Analyzer.Status.SOLVED:
		return {"reason": "easier_base"}
	if basic.status != Analyzer.Status.STUCK:
		return {"reason": "invalid_proof"}
	var restrictions := Analyzer.extend_stalled_proof(board, basic, 0, R)
	if restrictions.status == Analyzer.Status.SOLVED:
		return {"report": restrictions} if difficulty == "EASY" else {"reason": "easier_easy", "feedback": restrictions}
	if difficulty == "EASY":
		return {"reason": "restriction_stall"}
	var pairs := Analyzer.extend_stalled_proof(board, restrictions, R, P)
	var conflicts := Analyzer.extend_stalled_proof(board, restrictions, R, C)
	var pair_solves: bool = pairs.status == Analyzer.Status.SOLVED
	var conflict_solves: bool = conflicts.status == Analyzer.Status.SOLVED
	if pair_solves and conflict_solves:
		return {"reason": "overlapping_single_family_proofs"}
	if pair_solves or conflict_solves:
		if difficulty == "MEDIUM":
			return {"report": pairs if pair_solves else conflicts}
		return {"reason": "easier_medium", "feedback": pairs if pair_solves else conflicts}
	if difficulty != "HARD":
		return {"reason": "single_family_stall"}
	var full := Analyzer.extend_stalled_proof(board, pairs, R | P, C)
	return {"report": full} if full.status == Analyzer.Status.SOLVED else {"reason": "full_stall"}


static func _assess_extended(difficulty: String, board: PackedInt32Array) -> Dictionary:
	# The graph contains only layout conflicts and is identical under every mask.
	var conflict_graph: Array[PackedInt32Array] = []
	var classic := Analyzer.analyze_with_families(board, CLASSIC, conflict_graph)
	if classic.status == Analyzer.Status.SOLVED:
		return {"reason": "easier_classic", "earlier_proof": classic}
	if classic.status != Analyzer.Status.STUCK:
		return {"reason": "invalid_proof"}
	for mask in [R | P, R | C]:
		var earlier := Analyzer.analyze_with_families(board, mask, conflict_graph)
		if earlier.status == Analyzer.Status.SOLVED:
			return {"reason": "easier_classic", "earlier_proof": earlier}
	var triples := Analyzer.extend_stalled_proof(board, classic, CLASSIC, T, conflict_graph)
	if triples.status == Analyzer.Status.SOLVED:
		if difficulty == "EXTRA HARD":
			for mask in [0, R, P, C, P | C]:
				if Analyzer.analyze_with_families(board, mask, conflict_graph).status == Analyzer.Status.SOLVED:
					return {"reason": "easier_classic"}
			return {"report": triples}
		return {"reason": "easier_extra_hard", "earlier_proof": triples}
	if difficulty == "EXTRA HARD":
		return {"reason": "triple_stall"}
	var extended := Analyzer.extend_stalled_proof(board, triples, CLASSIC | T, I, conflict_graph)
	if extended.status != Analyzer.Status.SOLVED:
		return {"reason": "chain_stall"}
	for mask in range(CLASSIC | T):
		if Analyzer.analyze_with_families(board, mask, conflict_graph).status == Analyzer.Status.SOLVED:
			return {"reason": "easier_without_chains"}
	return {"report": extended}


static func _reject(result: Dictionary, reason: String) -> void:
	result.rejections[reason] = result.rejections.get(reason, 0) + 1


static func _accepted(
	result: Dictionary, request: Dictionary, board: PackedInt32Array,
	solution: PackedInt32Array, report: Dictionary,
) -> Dictionary:
	result.status = "success"
	result.regions = board
	result.solution = solution
	result.report = report
	# The stage-one preview includes the first proved bear as a locked given.
	result.locked_bears = PackedInt32Array([report.deductions[0].confirmed[0]]) if request.get("locked_bear", false) else PackedInt32Array()
	return result

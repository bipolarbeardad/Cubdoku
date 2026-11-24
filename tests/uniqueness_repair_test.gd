extends SceneTree

const Repair := preload("res://scripts/candidate_boundary_repair.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const Validator := preload("res://scripts/puzzle_validator.gd")
const Schedule := preload("res://scripts/campaign_schedule.gd")
const Generation := preload("res://scripts/campaign_generation.gd")

var _failures := 0


func _initialize() -> void:
	_test_multiple_witnesses()
	_test_count_limit()
	_test_profile_and_budget()
	print("Uniqueness repair test failures: %d" % _failures)
	quit(0 if _failures == 0 else 1)


func _test_multiple_witnesses() -> void:
	var side := 6
	var board := _striped_board(side)
	var anchor := _cells([0, 2, 4, 1, 3, 5], side)
	var first := _cells([5, 0, 2, 4, 1, 3], side)
	var second := _cells([5, 0, 3, 1, 4, 2], side)
	var witnesses: Array[PackedInt32Array] = [first, second]
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var edited := Repair.new(side).apply_scored_move(board, anchor, witnesses, rng, -1, {})
	_expect(edited >= 0 and not anchor.has(edited), "A scored edit leaves the intended bears in place")
	_expect(Validator.is_valid_terrain(board), "A scored edit keeps all six regions connected")
	_expect(_distinct_terrain(board, anchor), "The intended placement still covers all six terrain regions")
	_expect(not _distinct_terrain(board, first) and not _distinct_terrain(board, second),
		"One edit can invalidate both recorded alternative solutions")
	for region in side:
		_expect(board.count(region) >= 2, "The edit does not introduce a singleton")


func _test_count_limit() -> void:
	var board := _striped_board(10)
	var results := Solver.find_solutions(board, 12)
	_expect(results.size() == 12, "A high-ambiguity 10×10 diagnostic stops at its cap")
	_expect(Solver.find_solutions(board) == results.slice(0, 2), "The production limit preserves the witness order")
	_expect(Solver.find_solutions(board, 0).is_empty(), "A zero diagnostic cap does not enumerate")


func _test_profile_and_budget() -> void:
	var request := Schedule.new().request(8)
	var generator := Generation.new()
	var result := generator.generate(request, 50008, Generation.HIGHER_BUDGET, true, true, true)
	_expect(result.status == "success" and result.repairs.profile_pass == 1, "Reproduce a repaired MEDIUM acceptance")
	if result.status == "success":
		_expect(Solver.find_solutions(result.regions) == [result.solution], "The final repair has one solution")
		_expect(Generation.assess_profile("EASY", result.regions).has("reason"), "The accepted edit does not pass an easier gate")
	var no_budget := generator.generate(request, 50008, 0)
	_expect(no_budget.status == "failed" and no_budget.rejections.is_empty(), "A zero budget performs no candidate trials")


func _striped_board(side: int) -> PackedInt32Array:
	var board := PackedInt32Array()
	for row in side:
		for column in side:
			board.append(row)
	return board


func _cells(columns: Array, side: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for row in columns.size():
		cells.append(row * side + columns[row])
	return cells


func _distinct_terrain(board: PackedInt32Array, bears: PackedInt32Array) -> bool:
	var terrain := {}
	for bear in bears:
		terrain[board[bear]] = true
	return terrain.size() == bears.size()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

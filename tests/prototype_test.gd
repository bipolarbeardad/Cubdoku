extends SceneTree
## Run with godot --headless --path . --script res://tests/prototype_test.gd.

const Validator := preload("res://scripts/puzzle_validator.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const Generator := preload("res://scripts/puzzle_generator.gd")
const GameState := preload("res://scripts/puzzle_game_state.gd")
const Catalog := preload("res://scripts/campaign_catalog.gd")
const Session := preload("res://scripts/puzzle_session.gd")
const Save := preload("res://scripts/campaign_save.gd")
const BoardScene := preload("res://scenes/puzzle_board.tscn")
const BoardTerrain := preload("res://scripts/board_terrain.gd")
const TerrainFixture := preload("res://tests/terrain_visual_test.gd")
const BATCH_COUNT := 1000

var _failures := 0
var _test_profiles: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_solver()
	_test_game_state()
	_test_puzzle_modes()
	_test_unsupported_save()
	_test_batch()
	_test_terrain_mapping()
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

	var generator := Generator.new()
	var fallback := generator.generate(0, 0)
	_expect(generator.used_fallback, "Use fallback when the attempt budget is zero")
	var solutions := Solver.find_solutions(fallback)
	_expect(solutions == [PackedInt32Array([1, 7, 8, 14])], "Verify the fallback solution")
	_expect(generator.generate(1234) == generator.generate(1234), "Generation is deterministic")


func _test_game_state() -> void:
	var game := GameState.new()
	_expect(game.mark_at(0) == GameState.Mark.CLEAR, "Read a mark before loading safely")
	_expect(not game.load_puzzle(PackedInt32Array()), "Reject invalid puzzle loading")
	_expect(game.load_puzzle(PackedInt32Array(Generator.FALLBACK)), "Load a validated puzzle")
	_expect(game.mark_at(-1) == GameState.Mark.CLEAR, "Read a negative index safely")
	_expect(game.mark_at(Validator.CELL_COUNT) == GameState.Mark.CLEAR, "Read past the board safely")
	var result = game.toggle_mark(0, GameState.Mark.X)
	_expect(result == GameState.Result.CHANGED and game.hearts == 3, "X uses no hearts")
	_expect(game.mark_at(0) == GameState.Mark.X, "Record an X")
	result = game.toggle_mark(0, GameState.Mark.BEAR)
	_expect(result == GameState.Result.INCORRECT_BEAR and game.hearts == 2, "Reject a wrong bear")
	_expect(game.mark_at(0) == GameState.Mark.X, "Preserve the previous mark after rejection")
	for attempt in 2:
		game.toggle_mark(0, GameState.Mark.BEAR)
	_expect(game.hearts == 0 and game.status == GameState.Status.FAILED, "Fail at zero hearts")
	result = game.toggle_mark(1, GameState.Mark.BEAR)
	_expect(result == GameState.Result.IGNORED, "Ignore moves after failure")

	game.restart()
	_expect(game.hearts == 3 and game.status == GameState.Status.PLAYING, "Restore play on restart")
	_expect(game.mark_at(0) == GameState.Mark.CLEAR, "Restart clears marks")
	game.toggle_mark(1, GameState.Mark.BEAR)
	game.toggle_mark(1, GameState.Mark.BEAR)
	_expect(game.mark_at(1) == GameState.Mark.CLEAR, "Allow removing confirmed bears")
	game.toggle_mark(1, GameState.Mark.X)
	for cell in [1, 7, 8, 14]:
		_expect(game.status == GameState.Status.PLAYING, "Do not complete early")
		game.toggle_mark(cell, GameState.Mark.BEAR)
	_expect(game.status == GameState.Status.COMPLETE, "Complete after all four bears")


func _test_batch() -> void:
	var generator := Generator.new()
	var accepted := 0
	var rejected := 0
	var failed := 0
	var fallbacks := 0
	var longest_usec := 0
	var layouts := {}
	var started := Time.get_ticks_usec()
	for seed_value in BATCH_COUNT:
		var generation_start := Time.get_ticks_usec()
		var regions := generator.generate(seed_value)
		longest_usec = maxi(longest_usec, Time.get_ticks_usec() - generation_start)
		rejected += generator.rejected_attempts
		if generator.used_fallback:
			fallbacks += 1
		if Solver.find_solutions(regions).size() != 1:
			failed += 1
			continue
		if not generator.used_fallback:
			accepted += 1
		layouts[regions.to_byte_array().hex_encode()] = true
	var total_ms := (Time.get_ticks_usec() - started) / 1000.0
	var summary := (
		"4x4 BASE batch: %d requests, %d accepted candidates, %d rejected candidates, "
		+ "%d failures, %d fallbacks, %d distinct layouts, %.1f ms total, %.3f ms slowest generation"
	)
	print(summary % [
		BATCH_COUNT, accepted, rejected, failed, fallbacks, layouts.size(),
		total_ms, longest_usec / 1000.0,
	])
	_expect(failed == 0, "Batch produces a connected, uniquely solvable board every time")
	_expect(layouts.size() > 1, "Batch produces varied terrain layouts")
	_expect(longest_usec < 1000000, "Each 4x4 generation finishes within one second")


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
	_expect(session.load_campaign(), "Reopen campaign screen")
	_expect(session.attempt_summary().attempts_started == 1, "Opening the screen keeps Attempt 1")

	session.tick(2.5)
	session.toggle_mark(0, GameState.Mark.X)
	session.toggle_mark(0, GameState.Mark.BEAR)
	session = Session.new(path_a)
	session.get("_rng").seed = 999
	_expect(session.load_campaign(), "Load saved unfinished attempt")
	_expect(session.definition_snapshot() == assigned, "A changed random stream cannot replace an assignment")
	_expect(session.game.mark_at(0) == GameState.Mark.X and session.game.hearts == 2, "Resume saved marks and hearts")
	_expect(is_equal_approx(session.elapsed, 2.5), "Resume saved timer")
	_expect(session.attempt_summary().attempts_started == 1, "Resume does not start a new attempt")
	for miss in 2:
		session.toggle_mark(0, GameState.Mark.BEAR)
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
	board.set_board(1, PackedInt32Array([6]))
	_expect(board.terrain_layer.get_used_cells().size() == 1, "Redrawing clears previous terrain tiles")
	_expect(board.region_edges().is_empty(), "Redrawing clears previous internal edges")
	board.free()


func _test_scene() -> void:
	var board := BoardScene.instantiate()
	board.set("_session", Session.new(_profile_path()))
	root.add_child(board)
	var rendered_grid := board.find_children("*", "GridContainer", true, false)[0] as GridContainer
	_expect(rendered_grid.get_child_count() == 16, "Render sixteen cells in the main scene")
	var labels := board.find_children("*", "Label", true, false)
	var mode := board.find_children("*", "OptionButton", true, false)[0] as OptionButton
	var cell := rendered_grid.get_child(0) as Button
	var controls := mode.get_parent()
	var restart := controls.get_child(1) as Button
	var generate := controls.get_child(2) as Button
	var next := controls.get_child(3) as Button
	var campaign := board.get("_campaign_button") as Button
	_expect(labels[0].text == "Campaign Path #1 · BASE", "Show the campaign path and difficulty")
	_expect(next.disabled, "Disable advance during play")
	next.pressed.emit()
	_expect(labels[0].text == "Campaign Path #1 · BASE", "Reject advance during play")
	_expect(labels[1].text == "Hearts  ♥♥♥", "Show three starting hearts")
	await create_timer(1.1).timeout
	_expect(labels[2].text != "Time  00:00", "Update the elapsed time")
	var terrain := rendered_grid.get_parent() as BoardTerrain
	for index in Validator.CELL_COUNT:
		@warning_ignore("integer_division")
		var tile := Vector2i(index % Validator.SIZE, index / Validator.SIZE)
		var button := rendered_grid.get_child(index) as Button
		var button_center := button.global_position + button.size * 0.5
		var tile_center := terrain.terrain_layer.to_global(terrain.terrain_layer.map_to_local(tile))
		_expect(button_center.is_equal_approx(tile_center), "Buttons align with terrain tile centers")
		_expect(button.size == Vector2.ONE * BoardTerrain.CELL_SIZE, "Button covers exactly one terrain tile")
	mode.select(1)
	cell.pressed.emit()
	_expect(cell.text == "X", "Route the X control to the visible cell")
	cell.pressed.emit()
	_expect(cell.text.is_empty(), "Remove an X from the visible cell")
	mode.select(0)
	cell.pressed.emit()
	_expect(cell.text.is_empty(), "Keep an incorrect bear off the visible board")
	_expect(labels[1].text == "Hearts  ♥♥♡", "Show one heart lost")
	_expect(labels[4].text.contains("Incorrect bear"), "Show immediate incorrect placement feedback")
	cell.pressed.emit()
	cell.pressed.emit()
	_expect(cell.disabled and labels[4].text.contains("No hearts"), "Lock the board after failure")

	_expect(next.disabled, "Disable advance after failure")
	next.pressed.emit()
	_expect(cell.disabled and labels[0].text == "Campaign Path #1 · BASE", "Reject advance after failure")
	var original_regions: PackedInt32Array = board.get("_regions")
	restart.pressed.emit()
	_expect(labels[0].text == "Campaign Path #1 · BASE", "Restart keeps the puzzle number")
	_expect(board.get("_regions") == original_regions, "Restart keeps the terrain layout")
	_expect(labels[2].text == "Time  00:00", "Restart resets the displayed time")
	_expect(not cell.disabled and labels[1].text == "Hearts  ♥♥♥", "Restart unlocks the board")
	mode.select(1)
	cell.pressed.emit()
	generate.pressed.emit()
	_expect(labels[0].text == "Free Play · BASE", "Test generation enters Free Play")
	_expect(cell.text.is_empty(), "Test generation loads a fresh board")
	campaign.pressed.emit()
	_expect(labels[0].text == "Campaign Path #1 · BASE", "Free Play preserves the campaign number")
	_expect(board.get("_regions") == original_regions, "Return to the original campaign board")
	_expect(cell.text == "X", "Return resumes the campaign markings")

	var regions: PackedInt32Array = board.get("_regions")
	var solutions := Solver.find_solutions(regions)
	_expect(solutions.size() == 1, "Present a unique campaign puzzle")
	if solutions.size() == 1:
		for solved_cell in solutions[0]:
			var bear_button := rendered_grid.get_child(solved_cell) as Button
			bear_button.pressed.emit()
			_expect(bear_button.text == "Bear", "Show a correctly placed bear")
		_expect(cell.disabled and labels[4].text == "Puzzle complete!", "Show puzzle completion")
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
		campaign.pressed.emit()
		_expect(labels[0].text == "Campaign Path #2 · BASE", "Free Play preserves an advanced number")
	board.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)


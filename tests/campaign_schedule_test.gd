extends SceneTree

const Schedule := preload("res://scripts/campaign_schedule.gd")
const Generation := preload("res://scripts/campaign_generation.gd")
const Generator := preload("res://scripts/puzzle_generator.gd")
const Validator := preload("res://scripts/puzzle_validator.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")

var _failures := 0


func _initialize() -> void:
	var schedule := Schedule.new()
	var replay := Schedule.new()
	var generation := Generation.new()
	var existing_base := Generator.new()
	_expect(schedule.request(0).is_empty() and schedule.request(10001).is_empty(), "Reject out-of-range stages")
	_expect(schedule.request(10000) == replay.request(10000), "Direct stage lookup is reproducible")
	for stage in range(1, Schedule.INTRO_SIZES.size() + 1):
		var request := schedule.request(stage)
		var result := generation.generate(request, stage)
		_expect(request.difficulty == "BASE" and request.size == Schedule.INTRO_SIZES[stage - 1], "Introductory assignment")
		_expect(result.status == "success", "Generate each introductory BASE request")
		_expect(result.get("regions") == existing_base.generate(stage, Generator.DEFAULT_ATTEMPTS, "BASE", request.size), "Use the existing seeded BASE path")
		if result.status == "success":
			var locked: PackedInt32Array = result.locked_bears
			_expect(locked.size() == int(stage == 1), "Stage 1 alone includes a locked bear")
			if not locked.is_empty():
				_expect(result.solution.has(locked[0]), "The locked bear belongs to the solution")
	var alternate := Schedule.OPENING_BLOCK.duplicate()
	alternate.reverse()
	var custom := Schedule.new(alternate)
	var block: Array = []
	var previous := "BASE"
	var opening := ["EASY", "EASY", "MEDIUM", "HARD", "EASY", "MEDIUM", "EXTRA HARD", "EASY", "MEDIUM", "HARD",
		"NIGHTMARES", "EASY", "MEDIUM", "HARD", "EASY", "EXTRA HARD", "MEDIUM", "HARD", "EASY", "NIGHTMARES"]
	var seen_blocks := {}
	for stage in range(6, Schedule.STAGE_COUNT + 1):
		var request := schedule.request(stage)
		var difficulty: String = request.difficulty
		var sides: Vector2i = Schedule.SIZES[difficulty]
		_expect(request == replay.request(stage), "Stable request at stage %d" % stage)
		_expect(request.size >= sides.x and request.size <= sides.y, "Eligible size at stage %d" % stage)
		_expect(stage == 7 or difficulty != previous, "Only the preferred opening repeats consecutive difficulties")
		previous = difficulty
		block.append(difficulty)
		if stage <= 25:
			_expect(difficulty == opening[stage - 6], "Use the supplied opening sequence")
			_expect(custom.request(stage).difficulty == alternate[stage - 6], "Honor a configured opening order")
		if block.size() == 20:
			_expect(Schedule.valid_opening(block), "Every complete block carries the requested quotas")
			seen_blocks[str(block)] = true
			block.clear()
	_expect(seen_blocks.size() > 10, "Later block ordering varies")
	for request in [
		{"difficulty": "EASY", "size": 4}, {"difficulty": "HARD", "size": 9},
		{"difficulty": "EXTRA HARD", "size": 6}, {"difficulty": "NIGHTMARES", "size": 7},
	]:
		var result := generation.generate(request, 1)
		_expect(result.status == "unsupported" and not result.has("regions"), "Unsupported stages return no substitute")
	for size in range(8, 11):
		var regions := PackedInt32Array()
		for row in size:
			for column in size:
				regions.append(row)
		_expect(Validator.board_size(regions) == size and Validator.is_valid_terrain(regions), "Accept valid terrain on larger sides")
		_expect(Solver.find_solutions(regions).size() == 2, "Detect ambiguity on larger sides")
		regions[0] = size - 1
		_expect(not Validator.is_valid_terrain(regions), "Reject a disconnected larger region")
	for request in [{"difficulty": "HARD", "size": 8}, {"difficulty": "EXTRA HARD", "size": 9}, {"difficulty": "NIGHTMARES", "size": 10}]:
		_expect(generation.generate(request, 1, 0).status == "failed", "Large in-profile requests reach the bounded search")
	var exhausted := generation.generate({"difficulty": "EASY", "size": 5}, 1, 0)
	_expect(exhausted.status == "failed" and not exhausted.has("regions"), "A bounded search reports exhaustion")
	print("Campaign schedule test failures: %d" % _failures)
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

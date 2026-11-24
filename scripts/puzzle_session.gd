extends RefCounted
## Owns the active attempt and the persistent campaign profile.

const Catalog := preload("res://scripts/campaign_catalog.gd")
const Save := preload("res://scripts/campaign_save.gd")
const GameState := preload("res://scripts/puzzle_game_state.gd")
const Generator := preload("res://scripts/puzzle_generator.gd")
const Validator := preload("res://scripts/puzzle_validator.gd")
const Difficulty := preload("res://scripts/puzzle_difficulty.gd")

enum Mode { CAMPAIGN_PATH, FREE_PLAY }

var game := GameState.new()
var elapsed := 0.0
var save_error := false
var _path: String
var _profile: Dictionary
var _mode := Mode.CAMPAIGN_PATH
var _definition := {}
var _suspended_campaign := {}
var _generator := Generator.new()
var _rng := RandomNumberGenerator.new()


func _init(save_path: String = Save.DEFAULT_PATH) -> void:
	_path = save_path
	_profile = Save.read(_path)
	_rng.randomize()


func campaign_number() -> int:
	return _profile.get("current_level", 1)


func mode() -> Mode:
	return _mode


func definition_snapshot() -> Dictionary:
	var snapshot := _definition.duplicate()
	if not snapshot.is_empty():
		snapshot.regions = _definition.regions.duplicate()
		snapshot.solution = _definition.solution.duplicate()
		if snapshot.has("locked_bears"):
			snapshot.locked_bears = _definition.locked_bears.duplicate()
	return snapshot


func statistics_snapshot() -> Dictionary:
	return _profile.get("statistics", {}).duplicate(true)


func attempt_summary() -> Dictionary:
	var record: Dictionary = _profile.get("assignments", {}).get(campaign_number(), {})
	if record.is_empty():
		return {}
	return {
		"attempts_started": record.attempts_started,
		"failed_attempts": record.failed_attempts,
		"completed": record.completed,
		"best_completion_seconds": record.best_completion_seconds,
		"hearts_at_completion": record.hearts_at_completion,
		"consumables_used": record.consumables_used.duplicate(true),
	}


func load_campaign() -> bool:
	if _mode == Mode.FREE_PLAY and not _suspended_campaign.is_empty():
		game = _suspended_campaign.game
		_definition = _suspended_campaign.definition
		elapsed = _suspended_campaign.elapsed
		save_error = _suspended_campaign.save_error
		_mode = Mode.CAMPAIGN_PATH
		_suspended_campaign.clear()
		return true
	if _mode == Mode.CAMPAIGN_PATH and not _definition.is_empty():
		return true
	return _load_campaign_level(campaign_number())


func load_free_play(size: int = Validator.SIZE) -> bool:
	if not Difficulty.is_size_eligible(Difficulty.BASE, size):
		return false
	var regions := _generator.generate(_rng.randi(), Generator.DEFAULT_ATTEMPTS, Difficulty.BASE, size)
	return install_free_play({
		"size": size,
		"difficulty": Difficulty.BASE,
		"regions": regions,
		"solution": PackedInt32Array(),
	})


## The provisioning service has already checked the difficulty gate.
func install_free_play(definition: Dictionary) -> bool:
	if definition.has("error"):
		return false
	var next_game := GameState.new()
	if not next_game.load_puzzle(definition.regions, definition.solution):
		return false
	if _mode == Mode.CAMPAIGN_PATH and not _definition.is_empty():
		_suspended_campaign = {"game": game, "definition": _definition, "elapsed": elapsed, "save_error": save_error}
	game = next_game
	_definition = definition.duplicate(true)
	_definition.solution = game.solution_snapshot()
	elapsed = 0.0
	_mode = Mode.FREE_PLAY
	save_error = false
	return true


func can_advance() -> bool:
	return (
		_mode == Mode.CAMPAIGN_PATH
		and game.status == GameState.Status.COMPLETE
		and Catalog.has_level(campaign_number() + 1)
	)


func advance() -> bool:
	return can_advance() and _load_campaign_level(campaign_number() + 1)


func restart() -> bool:
	if _definition.is_empty():
		return false
	var previous := game.attempt_snapshot()
	var previous_elapsed := elapsed
	game.restart()
	elapsed = 0.0
	if _mode == Mode.FREE_PLAY or _save_attempt(true):
		return true
	game.restore_attempt(previous)
	elapsed = previous_elapsed
	return false


func toggle_mark(cell: int, mark: GameState.Mark) -> GameState.Result:
	if _mode == Mode.FREE_PLAY:
		return game.toggle_mark(cell, mark)
	var previous := game.attempt_snapshot()
	var result := game.toggle_mark(cell, mark)
	if result != GameState.Result.IGNORED and not _save_attempt(false, true):
		game.restore_attempt(previous)
		return GameState.Result.IGNORED
	return result


func tick(delta: float) -> void:
	if _definition.is_empty() or game.status != GameState.Status.PLAYING:
		return
	elapsed += delta
	if _mode == Mode.CAMPAIGN_PATH and not save_error:
		var saved_elapsed: float = _profile.assignments[campaign_number()].attempt.elapsed
		if elapsed - saved_elapsed >= 1.0:
			flush_attempt()


func flush_attempt() -> bool:
	if _mode == Mode.FREE_PLAY or _definition.is_empty():
		return true
	var saved_elapsed: float = _profile.assignments[campaign_number()].attempt.elapsed
	return elapsed == saved_elapsed or _save_attempt()


func _load_campaign_level(number: int) -> bool:
	var level := Catalog.level(number)
	if _profile.is_empty() or level.is_empty():
		return false

	var next_game := GameState.new()
	var record: Variant = _profile.assignments.get(number)
	var next_elapsed := 0.0
	if _profile.assignments.has(number):
		if not record is Dictionary or not record.get("definition") is Dictionary:
			return false
		var definition: Dictionary = record.definition
		var attempt: Variant = record.get("attempt")
		if not attempt is Dictionary or not attempt.get("elapsed") is float:
			return false
		if not _load_assignment(next_game, definition, level.id) or not next_game.restore_attempt(attempt):
			return false
		next_elapsed = attempt.elapsed
	else:
		var regions := _generator.generate(_rng.randi(), Generator.DEFAULT_ATTEMPTS, level.difficulty)
		if not next_game.load_puzzle(regions):
			return false
		var random_id := Crypto.new().generate_random_bytes(16)
		if random_id.size() != 16:
			return false
		var attempt := next_game.attempt_snapshot()
		attempt.elapsed = 0.0
		record = {
			"definition": {
				"id": random_id.hex_encode(),
				"level_id": level.id,
				"size": Validator.SIZE,
				"difficulty": level.difficulty,
				"regions": regions,
				"solution": next_game.solution_snapshot(),
			},
			"attempt": attempt,
			"attempts_started": 1,
			"failed_attempts": 0,
			"completed": false,
			"best_completion_seconds": null,
			"hearts_at_completion": null,
			"consumables_used": {},
		}

	if not _profile.assignments.has(number) or number != campaign_number():
		var candidate := _profile.duplicate(true)
		candidate.assignments[number] = record
		candidate.current_level = number
		candidate.statistics.highest_level_reached = maxi(candidate.statistics.highest_level_reached, number)
		if not _commit(candidate):
			return false
	game = next_game
	_definition = record.definition
	elapsed = next_elapsed
	_mode = Mode.CAMPAIGN_PATH
	save_error = false
	return true


func _load_assignment(target: RefCounted, definition: Dictionary, level_id: String) -> bool:
	var regions: Variant = definition.get("regions")
	var solution: Variant = definition.get("solution")
	var locked_bears: Variant = definition.get("locked_bears", PackedInt32Array())
	return (
		definition.get("level_id") == level_id
		and definition.get("id") is String
		and definition.get("difficulty") is String
		and definition.get("size") == Validator.SIZE
		and regions is PackedInt32Array
		and solution is PackedInt32Array
		and solution.size() == Validator.SIZE
		and locked_bears is PackedInt32Array
		and target.load_puzzle(regions, solution, locked_bears)
	)


func _save_attempt(starting: bool = false, record_outcome: bool = false) -> bool:
	var candidate := _profile.duplicate(true)
	var record: Dictionary = candidate.assignments[campaign_number()]
	record.attempt = game.attempt_snapshot()
	record.attempt.elapsed = elapsed
	if starting:
		record.attempts_started += 1
	elif record_outcome and game.status == GameState.Status.FAILED:
		record.failed_attempts += 1
	elif record_outcome and game.status == GameState.Status.COMPLETE:
		_record_completion(record, candidate.statistics)
	return _commit(candidate)


func _record_completion(record: Dictionary, statistics: Dictionary) -> void:
	if not record.completed:
		var difficulty: String = record.definition.difficulty
		statistics.completed_total += 1
		statistics.completed_by_difficulty[difficulty] = (
			statistics.completed_by_difficulty.get(difficulty, 0) + 1
		)
	record.completed = true
	record.hearts_at_completion = game.hearts
	if record.best_completion_seconds == null or elapsed < record.best_completion_seconds:
		record.best_completion_seconds = elapsed
	if statistics.fastest_completion_seconds == null or elapsed < statistics.fastest_completion_seconds:
		statistics.fastest_completion_seconds = elapsed


func _commit(candidate: Dictionary) -> bool:
	save_error = not Save.write(_path, candidate)
	if save_error:
		return false
	_profile = candidate
	return true

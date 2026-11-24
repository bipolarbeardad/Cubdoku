extends RefCounted
## Free Play provisioning. Campaign saves and attempt state are outside this service.

const Schedule := preload("res://scripts/campaign_schedule.gd")
const Generation := preload("res://scripts/campaign_generation.gd")
const Nightmares := preload("res://scripts/nightmares_construction.gd")
const Validator := preload("res://scripts/puzzle_validator.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const Difficulty := preload("res://scripts/puzzle_difficulty.gd")
const DIFFICULTIES := ["BASE", "EASY", "MEDIUM", "HARD", "EXTRA HARD", "NIGHTMARES"]
const SLOT := "user://cubdoku-playtest.json"
const NIGHTMARES_WINDOW := 32
const PROMOTED_ROOT_LIMIT := 8

var _used := {}
var _reserve: Dictionary
var _roots: Dictionary
var _window: int
var _expand: bool
var _promoted := {}
var _reserve_keys := {}


## The window counts successfully served boards of the same size. -1 is the legacy control.
func _init(window := NIGHTMARES_WINDOW, expand := true) -> void:
	_window = maxi(-1, window)
	_expand = expand
	_reserve = _read_catalog("res://data/nightmares_reserve.json")
	_roots = _read_catalog("res://data/nightmares_seeds.json")
	if _expand:
		var extra := _read_catalog("res://data/nightmares_expanded_roots.json")
		for size in extra:
			for entry in extra[size]:
				_roots[size].append(entry.regions)


static func _read_catalog(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return decoded if decoded is Dictionary else {}


func remember(definition: Dictionary) -> void:
	if definition.difficulty == "NIGHTMARES":
		_remember_layout(definition.size, Nightmares.layout_key(definition.regions, definition.size))


func _remember_layout(size: int, key: String) -> void:
	var used: Dictionary = _used.get_or_add(size, {})
	used.erase(key)
	used[key] = true
	if _window >= 0 and used.size() > _window:
		used.erase(used.keys()[0])


func generate(difficulty: String, requested_size: int, seed_value: int, telemetry := {}) -> Dictionary:
	var limits: Vector2i = Schedule.SIZES.get(difficulty, Vector2i.ZERO)
	if limits == Vector2i.ZERO or (requested_size != 0 and (requested_size < limits.x or requested_size > limits.y)):
		return {"error": "This board size is unavailable for the selected difficulty."}
	var started := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var size := rng.randi_range(limits.x, limits.y) if requested_size == 0 else requested_size
	var result := {}
	var source := "Fresh"
	if difficulty == "NIGHTMARES":
		result = _nightmares(size, seed_value, rng, telemetry)
		if result.has("error"):
			return result
		source = result.source
	else:
		var generator := Generation.new()
		for attempt in 3:
			var candidate := generator.generate({"difficulty": difficulty, "size": size},
				seed_value if attempt == 0 else rng.randi())
			if candidate.status == "success":
				result = candidate
				source = "Validated BASE fallback" if candidate.fallback else source
				break
		if result.is_empty():
			return {"error": "No validated %s %dx%d puzzle found. Try another seed." % [difficulty, size, size]}
	return _definition(result, difficulty, size, seed_value, source, started)


func _nightmares(size: int, seed_value: int, rng: RandomNumberGenerator, telemetry: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var roots: Array[Dictionary] = []
	if not _roots.has("_verified_" + str(size)):
		for raw in _roots.get(str(size), []):
			var root := Nightmares.verify(PackedInt32Array(raw), size, Nightmares.new_stats())
			if not root.is_empty():
				roots.append(root)
		_roots["_verified_" + str(size)] = roots
	else:
		roots = _roots["_verified_" + str(size)]
	if _expand:
		roots = roots.duplicate()
		roots.append_array(_promoted.get(size, []))
	var used: Dictionary = _used.get_or_add(size, {})
	telemetry.root_usec = Time.get_ticks_usec() - started
	var fresh := Nightmares.new_stats()
	fresh.timing = {"structure": 0, "uniqueness": 0, "proof": 0}
	started = Time.get_ticks_usec()
	var result := Nightmares.request(size, seed_value, roots, [], used, fresh)
	telemetry.fresh_usec = Time.get_ticks_usec() - started
	telemetry.fresh = fresh
	if not result.is_empty():
		_remember_layout(size, result.key)
		if _expand:
			var promoted: Array = _promoted.get_or_add(size, [])
			if not promoted.any(func(entry: Dictionary) -> bool: return entry.key == result.key):
				var parent := result.duplicate(true)
				parent.regions = result.regions.duplicate()
				parent.solution = result.solution.duplicate()
				promoted.append(parent)
				if promoted.size() > PROMOTED_ROOT_LIMIT:
					promoted.pop_front()
		result.source = "Fresh"
		return result
	var inventory: Array = _reserve.get(str(size), [])
	started = Time.get_ticks_usec()
	var reserve_stats := Nightmares.new_stats()
	reserve_stats.timing = {"structure": 0, "uniqueness": 0, "proof": 0}
	telemetry.reserve = reserve_stats
	if not inventory.is_empty():
		if not _reserve_keys.has(size):
			var keys := PackedStringArray()
			for raw in inventory:
				keys.append(Nightmares.layout_key(PackedInt32Array(raw), size))
			_reserve_keys[size] = keys
		var keys: PackedStringArray = _reserve_keys[size]
		var offset := rng.randi_range(0, inventory.size() - 1)
		for index in inventory.size():
			var position := (index + offset) % inventory.size()
			var key := keys[position]
			if used.has(key):
				reserve_stats.repeated += 1
				continue
			result = Nightmares.verify(PackedInt32Array(inventory[position]), size, reserve_stats)
			if not result.is_empty():
				telemetry.reserve_usec = Time.get_ticks_usec() - started
				_remember_layout(size, key)
				result.source = "Validated reserve"
				return result
	telemetry.reserve_usec = Time.get_ticks_usec() - started
	reserve_stats.reserve_exhausted += 1
	return {"error": "Fresh NIGHTMARES search exhausted. No unused validated %dx%d reserve remains outside the repeat window." % [size, size]}


static func _definition(result: Dictionary, difficulty: String, size: int, seed_value: int,
	source: String, started: int) -> Dictionary:
	return {"id": (difficulty + ":" + str(result.regions)).sha256_text().left(16),
		"difficulty": difficulty, "size": size, "regions": result.regions, "solution": result.solution,
		"seed": str(seed_value), "source": source, "generation_ms": (Time.get_ticks_usec() - started) / 1000.0}


static func save_slot(definition: Dictionary, path := SLOT) -> bool:
	if definition.is_empty():
		return false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "difficulty": definition.difficulty,
		"regions": Array(definition.regions), "solution": Array(definition.solution),
		"seed": definition.get("seed", "")}))
	file.flush()
	var written := file.get_error() == OK
	file.close()
	return written and DirAccess.rename_absolute(temporary, path) == OK


static func reopen_slot(path := SLOT) -> Dictionary:
	var started := Time.get_ticks_usec()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or raw.get("version") != 1 or not raw.get("regions") is Array or not raw.get("solution") is Array:
		return {"error": "No readable playtest definition is saved."}
	for entry in raw.regions + raw.solution:
		if not (entry is float or entry is int) or entry != int(entry) or entry < 0 or entry > 99:
			return {"error": "The saved playtest definition is invalid."}
	var board := PackedInt32Array(raw.regions)
	var size := Validator.board_size(board)
	var difficulty: String = str(raw.get("difficulty", ""))
	var limits: Vector2i = Schedule.SIZES.get(difficulty, Vector2i.ZERO)
	if size == 0 or size < limits.x or size > limits.y or not Validator.is_valid_terrain(board):
		return {"error": "The saved playtest layout is invalid."}
	var solution := PackedInt32Array(raw.solution)
	var singleton_count := 0
	for region in size:
		singleton_count += int(board.count(region) == 1)
	var gate_ok: bool = Difficulty.matches(difficulty, board) if difficulty == "BASE" else (
		singleton_count <= Difficulty.THRESHOLDS[difficulty].max_singletons
		and Generation.assess_profile(difficulty, board).has("report"))
	if not gate_ok or Solver.find_solutions(board) != [solution]:
		return {"error": "The saved playtest definition did not pass validation."}
	return _definition({"regions": board, "solution": solution}, difficulty, size,
		str(raw.get("seed", "")).to_int(), "Reopened definition", started)

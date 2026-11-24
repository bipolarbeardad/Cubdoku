extends SceneTree

const Service := preload("res://scripts/free_play_generation.gd")
const Construction := preload("res://scripts/nightmares_construction.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const REQUESTS := 144

func _initialize() -> void:
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	if not expected.begins_with(ProjectSettings.globalize_path("res://.godot/") + "isolated-") or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() == 3 and args[2] == "proofs":
		_compare_proofs(args[0], args[1])
		return
	var log := FileAccess.open(args[0], FileAccess.READ) if args.size() == 2 else null
	if not log or args[1] not in ["legacy", "rolling", "expanded"]:
		quit(1)
		return
	var old := {}
	while log.get_position() < log.get_length():
		var entry: Dictionary = JSON.parse_string(log.get_line())
		if entry.source != "unfulfilled":
			old[Construction.layout_key(PackedInt32Array(entry.regions), int(entry.size))] = true
	var arm: String = args[1]
	var service := Service.new(-1 if arm == "legacy" else Service.NIGHTMARES_WINDOW, arm == "expanded")
	var path := "user://nightmares-window-" + arm + ".jsonl"
	var output := FileAccess.open(path, FileAccess.WRITE)
	if not output:
		quit(1)
		return
	for side in [8, 9, 10]:
		for index in REQUESTS:
			var started := Time.get_ticks_usec()
			var result := service.generate("NIGHTMARES", side, 67000 + side * 1000 + index)
			var row := {"size": side, "index": index + 1, "usec": Time.get_ticks_usec() - started,
				"source": result.get("source", "unfulfilled")}
			if not result.has("error"):
				row.regions = Array(result.regions)
				row.solution = Array(result.solution)
				row.new_layout = not old.has(Construction.layout_key(result.regions, side))
			output.store_line(JSON.stringify(row))
		output.flush()
		print(arm, " completed ", side, " x ", side)
	print(ProjectSettings.globalize_path(path))
	quit(int(output.get_error() != OK))


func _compare_proofs(previous_path: String, expanded_path: String) -> void:
	var signatures := {}
	var failures := 0
	for path in [previous_path, expanded_path]:
		var file := FileAccess.open(path, FileAccess.READ)
		if not file:
			quit(1)
			return
		while file.get_position() < file.get_length():
			var row: Dictionary = JSON.parse_string(file.get_line())
			if row.source == "unfulfilled" or (path == expanded_path and not row.new_layout):
				continue
			var proof := Analyzer.analyze_with_families(PackedInt32Array(row.regions), Analyzer.EXTENDED_FAMILIES)
			if proof.status != Analyzer.Status.SOLVED or proof.bears != PackedInt32Array(row.solution):
				failures += 1
			var technique_order := []
			for move in proof.deductions:
				technique_order.append(move.technique)
			var sizes: Dictionary = signatures.get_or_add(path, {})
			var orders: Dictionary = sizes.get_or_add(int(row.size), {})
			orders[str(technique_order)] = true
	for side in [8, 9, 10]:
		var old: Dictionary = signatures[previous_path].get(side, {})
		var expanded: Dictionary = signatures[expanded_path].get(side, {})
		var novel := expanded.keys().filter(func(key: String) -> bool: return not old.has(key))
		print(side, " prior technique signatures ", old.size(), " expanded novel-layout signatures ",
			expanded.size(), " new signatures ", novel.size())
	print("Window proof audit failures: ", failures)
	quit(int(failures != 0))

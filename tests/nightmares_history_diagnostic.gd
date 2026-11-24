extends SceneTree

const Service := preload("res://scripts/free_play_generation.gd")
const Layout := preload("res://scripts/nightmares_construction.gd")

func _initialize() -> void:
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	if not expected.begins_with(ProjectSettings.globalize_path("res://.godot/") + "isolated-") or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var file := FileAccess.open(args[0], FileAccess.READ)
	if not file:
		quit(1)
		return
	var history := {}
	var samples := {}
	var ids := [1, 2, 3, 358, 361, 365, 368, 603, 612, 900, 903, 904, 905, 906, 1200, 4998, 4999, 5000]
	while file.get_position() < file.get_length():
		var row: Dictionary = JSON.parse_string(file.get_line())
		if int(row.index) in ids:
			samples[int(row.index)] = {"row": row, "history": history.duplicate(true)}
		if row.source != "unfulfilled":
			var keys: Dictionary = history.get_or_add(int(row.size), {})
			keys[Layout.layout_key(PackedInt32Array(row.regions), int(row.size))] = true
	if args.size() > 1:
		var isolated: Dictionary = samples[int(args[1])].row
		print("separate process ", _run(Service.new(-1, false), isolated))
		quit()
		return
	var failed := 0
	for index in ids:
		var sample: Dictionary = samples[index]
		var row: Dictionary = sample.row
		var replay := Service.new(-1, false)
		replay.set("_used", sample.history.duplicate(true))
		var actual := _run(replay, row)
		failed += int(actual.source != row.source or actual.id != row.get("id", ""))
		var fresh := _run(Service.new(-1, false), row)
		var no_reserve := Service.new(-1, false)
		no_reserve.set("_reserve", {})
		var historical_no_reserve := Service.new(-1, false)
		historical_no_reserve.set("_used", sample.history.duplicate(true))
		historical_no_reserve.set("_reserve", {})
		print(index, " logged ", actual, " fresh ", fresh, " fresh_no_reserve ", _run(no_reserve, row),
			" recorded_history_no_reserve ", _run(historical_no_reserve, row).source)
	var late := [904, 905, 906, 1200, 4998, 4999, 5000]
	for policy in ["forward", "reverse", "reset_each", "full_history", "shifted_seed", "shifted_full_history"]:
		var service := Service.new(-1, false)
		var order := late.duplicate()
		if policy == "reverse":
			order.reverse()
		if policy in ["full_history", "shifted_full_history"]:
			service.set("_used", history.duplicate(true))
		var results := {}
		for index in order:
			if policy == "reset_each":
				service.set("_used", {})
			var row: Dictionary = samples[index].row.duplicate()
			if policy.begins_with("shifted"):
				row.seed += 730000
			results[str(index)] = _run(service, row).source
		print(policy, " ", results)
	print("History replay mismatches: ", failed)
	quit(int(failed != 0))


func _run(service: Service, row: Dictionary) -> Dictionary:
	var timing := {}
	var started := Time.get_ticks_usec()
	var result := service.generate("NIGHTMARES", int(row.size), int(row.seed), timing)
	var fresh: Dictionary = timing.fresh
	var gates := 0
	for count in fresh.gates.values():
		gates += int(count)
	var source: String = result.get("source", "unfulfilled")
	return {"source": source, "id": result.get("id", ""), "proposals": fresh.structure + fresh.uniqueness
		+ fresh.repeated + gates + int(source == "Fresh"), "structure": fresh.structure,
		"multiple_or_zero": fresh.uniqueness, "gates": fresh.gates, "history_skips": fresh.repeated,
		"fresh_exhausted": fresh.fresh_exhausted, "reserve_exhausted": timing.get("reserve", {}).get("reserve_exhausted", 0),
		"usec": Time.get_ticks_usec() - started}


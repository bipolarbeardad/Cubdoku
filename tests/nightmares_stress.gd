extends SceneTree
## One uninterrupted Free Play exclusion set across the full benchmark.

const FreePlay := preload("res://scripts/free_play_generation.gd")
const TOTAL := 5000
const SEED_BASE := 850000

func _initialize() -> void:
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	var sandbox := ProjectSettings.globalize_path("res://.godot/").replace("\\", "/") + "isolated-"
	if not expected.begins_with(sandbox) or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		push_error("Use tests/run_isolated.ps1")
		quit(1)
		return
	var path := "user://nightmares-stress.jsonl"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		quit(1)
		return
	print("Writing ", ProjectSettings.globalize_path(path))
	var service := FreePlay.new(-1, false) if "--legacy" in OS.get_cmdline_user_args() else FreePlay.new()
	for index in TOTAL:
		var side := 8 + index % 3
		var request_seed := SEED_BASE + index
		var telemetry := {}
		var started := Time.get_ticks_usec()
		var result := service.generate("NIGHTMARES", side, request_seed, telemetry)
		var row := {"index": index + 1, "size": side, "seed": request_seed,
			"usec": Time.get_ticks_usec() - started, "timing": telemetry}
		if result.has("error"):
			row.source = "unfulfilled"
		else:
			if result.size != side or result.difficulty != "NIGHTMARES":
				push_error("Unexpected puzzle size or difficulty")
				quit(1)
				return
			row.source = result.source
			row.id = result.id
			row.regions = Array(result.regions)
			row.solution = Array(result.solution)
		file.store_line(JSON.stringify(row))
		if (index + 1) % 100 == 0:
			file.flush()
			print("Recorded ", index + 1, "/", TOTAL)
	file.flush()
	var failed := file.get_error() != OK
	file.close()
	quit(int(failed))

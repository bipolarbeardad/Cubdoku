extends SceneTree
const Generation := preload("res://scripts/campaign_generation.gd")
const Construction := preload("res://scripts/nightmares_construction.gd")

func _initialize() -> void:
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	if expected.is_empty() or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		quit(1)
		return
	var generator := Generation.new()
	var roots := {}
	for side in [8, 9, 10]:
		var boards := []
		var keys := {}
		for index in 96:
			var seed_value: int = 1830001 + side * 1000 + index
			var result := generator.generate({"difficulty": "NIGHTMARES", "size": side}, seed_value)
			if result.status == "success":
				var key := Construction.layout_key(result.regions, side)
				if not keys.has(key):
					keys[key] = true
					boards.append({"seed": seed_value, "regions": Array(result.regions)})
		roots[str(side)] = boards
		print(side, " independent root seeds: ", boards.map(func(entry: Dictionary) -> int: return entry.seed))
	var file := FileAccess.open("user://nightmares-new-roots.json", FileAccess.WRITE)
	if not file:
		quit(1)
		return
	file.store_string(JSON.stringify(roots))
	print(ProjectSettings.globalize_path("user://nightmares-new-roots.json"))
	quit()

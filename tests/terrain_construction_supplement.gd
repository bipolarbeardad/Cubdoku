extends SceneTree

const Gen := preload("res://scripts/campaign_generation.gd")
const Grow := preload("res://scripts/puzzle_generator.gd")
const Night := preload("res://scripts/nightmares_construction.gd")
const Repair := preload("res://scripts/candidate_boundary_repair.gd")
const Check := preload("res://scripts/puzzle_validator.gd")
const Solve := preload("res://scripts/puzzle_solver.gd")
const Logic := preload("res://scripts/difficulty_analyzer.gd")
const Advanced := preload("res://scripts/difficulty_advanced_patterns.gd")
const Terrain := preload("res://scripts/board_terrain.gd")
const Surfaces := preload("res://scripts/terrain_surfaces.gd")


func _initialize() -> void:
	var expected := OS.get_environment("CUBDOKU_TEST_USER_DIR").replace("\\", "/").simplify_path()
	var prefix := ProjectSettings.globalize_path("res://.godot/").replace("\\", "/") + "isolated-"
	if not expected.begins_with(prefix) or OS.get_user_data_dir().replace("\\", "/").simplify_path() != expected:
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var failures := 0
	for path in args:
		failures += _audit_opening(path)
	failures += int(not _material_mapping())
	print("Supplemental failures: ", failures)
	quit(int(failures != 0))


func _audit_opening(path: String) -> int:
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		return 1
	var recorded := {}
	var errors := 0
	var side := 0
	while input.get_position() < input.get_length():
		var row: Dictionary = JSON.parse_string(input.get_line())
		if row.status != "accepted":
			continue
		side = int(row.side)
		var board := PackedInt32Array(row.regions)
		var answer := PackedInt32Array(row.witnessed)
		var candidates := PackedByteArray()
		candidates.resize(board.size())
		candidates.fill(1)
		var groups := Logic._make_groups(board, side)
		var graph: Array[PackedInt32Array] = []
		var cells := {}
		for family in [1, 2, 4, 8]:
			for step: Dictionary in Logic._advanced_moves(groups, board, side, candidates, family, graph):
				for cell: int in step.eliminated:
					cells[cell] = true
		for step: Dictionary in Advanced.adjacency_triples(groups, graph, side, Logic.Technique.ADJACENCY_TRIPLE):
			for cell: int in step.eliminated:
				cells[cell] = true
		for cell: int in cells:
			errors += int(answer.has(cell))
		var sample: Array = recorded.get_or_add(row.arm, [])
		sample.append(cells.size())
	for arm in recorded:
		var sample: Array = recorded[arm]
		sample.sort()
		print("Opening ", side, " ", arm, " count/min/median/max ", [sample.size(), sample[0], sample[sample.size() >> 1], sample.back()])
	return errors


func _material_mapping() -> bool:
	var roots: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/nightmares_seeds.json"))
	var board := PackedInt32Array(roots["10"][0])
	var solution := Solve.find_solutions(board)
	var proof := Gen.assess_profile("NIGHTMARES", board)
	var service := Gen.new()
	var request := {"size": 9, "difficulty": "EXTRA HARD"}
	var before := service.generate(request, 6189000)
	var first := Terrain.new()
	var second := Terrain.new()
	var sheets: Array[Texture2D] = []
	for material in 10:
		var image := Image.create_empty(Surfaces.SHEET_SIZE, Surfaces.SHEET_SIZE, false, Image.FORMAT_RGB8)
		image.fill(Surfaces.BASE_COLORS[material])
		sheets.append(ImageTexture.create_from_image(image))
	first.material_sheets = sheets.duplicate()
	sheets.reverse()
	second.material_sheets = sheets
	first.set_board(10, board)
	second.set_board(10, board)
	var mapping_changed := true
	for region in 10:
		var a := first.terrain_layer.tile_set.get_source(region) as TileSetAtlasSource
		var b := second.terrain_layer.tile_set.get_source(region) as TileSetAtlasSource
		mapping_changed = mapping_changed and a.texture != b.texture
	var regions_unchanged := first.region_edges() == second.region_edges() and board == PackedInt32Array(roots["10"][0])
	var after := service.generate(request, 6189000)
	var proof_after := Gen.assess_profile("NIGHTMARES", board)
	first.free()
	second.free()
	var okay: bool = mapping_changed and regions_unchanged and solution.size() == 1 and solution == Solve.find_solutions(board)
	okay = okay and proof.has("report") and proof_after.has("report") and proof.report.deductions == proof_after.report.deductions
	okay = okay and before.status == "success" and after.status == "success" and before.regions == after.regions and before.solution == after.solution
	print("Ten-material texture permutation, fixed-seed generator and unchanged NIGHTMARES proof: ", okay)
	_nightmares_regrowth(roots["10"])
	return okay


func _nightmares_regrowth(roots: Array) -> void:
	var grower := Grow.new()
	var stats := {"root_edit": {}, "root_regrow": {}}
	var journal := FileAccess.open("user://nightmares-terrain-probes.jsonl", FileAccess.WRITE)
	if journal == null:
		push_error("Could not write NIGHTMARES validation journal")
		return
	for index in 6:
		var parent := Night.verify(PackedInt32Array(roots[index]), 10, Night.new_stats())
		if parent.is_empty():
			push_error("Invalid NIGHTMARES diagnostic root")
			return
		var columns := PackedInt32Array()
		for cell: int in parent.solution:
			columns.append(cell % 10)
		for arm: String in stats:
			var rng := RandomNumberGenerator.new()
			rng.seed = 6190000 + index
			for attempt in 8:
				var board := PackedInt32Array()
				if arm == "root_edit":
					var options := Night.edits(parent, 10)
					var move := options[rng.randi_range(0, options.size() - 1)]
					board = parent.regions.duplicate()
					board[move.x] = move.y
				else:
					board = grower.grow_seeded_candidate(rng, 10, false, PackedInt32Array(), true, {"chain": true}, columns)
				var status := _nightmare_status(board)
				stats[arm][status] = stats[arm].get(status, 0) + 1
				if status == "accepted":
					var solution := Solve.find_solutions(board)[0]
					journal.store_line(JSON.stringify({"size": 10, "regions": Array(board),
						"solution": Array(solution)}))
	journal.flush()
	if journal.get_error() != OK:
		push_error("Could not flush NIGHTMARES validation journal")
	print("NIGHTMARES validation journal: ", ProjectSettings.globalize_path("user://nightmares-terrain-probes.jsonl"))
	print("10x10 NIGHTMARES matched roots, 48 proposals per arm: ", stats)


func _nightmare_status(board: PackedInt32Array) -> String:
	if not Check.is_valid_terrain(board):
		return "structure"
	var answers := Solve.find_solutions(board)
	if answers.size() != 1:
		return "multiple" if answers.size() > 1 else "no_solution"
	var proof := Gen.assess_profile("NIGHTMARES", board)
	if proof.has("report") and (proof.report.bears != answers[0] or range(10).any(func(r: int) -> bool: return board.count(r) < 2)):
		push_error("Invalid NIGHTMARES diagnostic acceptance")
	return proof.get("reason", "accepted")

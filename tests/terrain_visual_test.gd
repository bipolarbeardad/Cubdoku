extends CenterContainer
## Run with --ten-materials to include the three additional placeholders.

const BoardTerrain := preload("res://scripts/board_terrain.gd")
const SIDE := 7
const REGIONS := [
	0, 0, 0, 1, 1, 2, 2,
	0, 0, 0, 0, 1, 2, 2,
	0, 0, 0, 1, 1, 2, 3,
	0, 0, 1, 1, 4, 2, 3,
	0, 0, 1, 4, 4, 2, 3,
	5, 5, 1, 1, 4, 6, 6,
	5, 5, 5, 1, 6, 6, 6,
]


var _fixture_side := SIDE
var _fixture_regions := PackedInt32Array(REGIONS)


func _ready() -> void:
	get_window().title = "Cubdoku · Terrain test"
	if "--ten-materials" in OS.get_cmdline_user_args():
		_fixture_side = 10
		_fixture_regions.clear()
		for region in _fixture_side:
			for column in _fixture_side:
				_fixture_regions.append(region)
	get_window().content_scale_size = Vector2i(900, 900) if _fixture_side == 10 else Vector2i(680, 660)
	get_window().size = get_window().content_scale_size
	var board := BoardTerrain.new()
	add_child(board)
	board.set_board(_fixture_side, _fixture_regions)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := "user://terrain-preview.png"
		var saved := image.save_png(path) == OK
		var verified := _verify_pixels(image, board)
		print("Terrain screenshot: %s" % ProjectSettings.globalize_path(path))
		print("Terrain pixel checks: %s" % ("passed" if verified else "failed"))
		get_tree().quit(0 if saved and verified else 1)


func _verify_pixels(image: Image, board: BoardTerrain) -> bool:
	var origin := Vector2i(board.get_global_transform_with_canvas().origin)
	var span := _fixture_side * BoardTerrain.CELL_SIZE
	var samples: Array[Image] = []
	for material in _fixture_side:
		var atlas := board.terrain_layer.tile_set.get_source(material) as TileSetAtlasSource
		samples.append(atlas.texture.get_image())

	# Compare the placed art on both sides of each border to its board-space source.
	var cell_size := BoardTerrain.CELL_SIZE
	var middle := cell_size >> 1
	var inset := BoardTerrain.REGION_WIDTH - 1
	var offsets := [
		Vector2i(inset, middle), Vector2i(middle, inset),
		Vector2i(cell_size - inset, middle), Vector2i(middle, cell_size - inset),
		Vector2i(middle, middle),
	]
	var outer := BoardTerrain.REGION_WIDTH
	var interior := Rect2i(outer, outer, span - 2 * outer, span - 2 * outer)
	for y in _fixture_side:
		for x in _fixture_side:
			var cell_origin := Vector2i(x, y) * cell_size
			var id: int = _fixture_regions[y * _fixture_side + x]
			for offset in offsets:
				var point: Vector2i = cell_origin + offset
				if not interior.has_point(point):
					continue # The outer border occupies these pixels.
				if not _matches(image.get_pixelv(origin + point), samples[id].get_pixelv(point)):
					push_error("Terrain surface mismatch at %s" % point)
					return false
			if x > 0 and not _verify_border(image, origin, cell_origin + Vector2i(0, middle), id, y * _fixture_side + x - 1, samples):
				return false
			if y > 0 and not _verify_border(image, origin, cell_origin + Vector2i(middle, 0), id, (y - 1) * _fixture_side + x, samples):
				return false
	var center := span >> 1
	for offset in [Vector2i(center, 0), Vector2i(0, center), Vector2i(center, span - 1), Vector2i(span - 1, center)]:
		if not _matches(image.get_pixelv(origin + offset), Color.BLACK):
			push_error("Outer terrain border mismatch at %s" % offset)
			return false
	return true


func _verify_border(image: Image, origin: Vector2i, point: Vector2i, id: int, neighbor: int, samples: Array[Image]) -> bool:
	var expected := Color.BLACK
	if id == _fixture_regions[neighbor]:
		expected = samples[id].get_pixelv(point).blend(BoardTerrain.GRID_COLOR)
	if _matches(image.get_pixelv(origin + point), expected):
		return true
	push_error("Terrain border mismatch at %s" % point)
	return false


func _matches(actual: Color, expected: Color) -> bool:
	return absf(actual.r - expected.r) + absf(actual.g - expected.g) + absf(actual.b - expected.b) < 0.035

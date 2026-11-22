extends Control
## Displays a puzzle definition without participating in puzzle state or input.

const Surfaces := preload("res://scripts/terrain_surfaces.gd")
const CELL_SIZE := Surfaces.CELL_SIZE
const GRID_COLOR := Color(0.025, 0.023, 0.018, 0.48)
const REGION_WIDTH := 4

## Optional full, square board-space texture sheets in Surfaces.MATERIALS order.
@export var material_sheets: Array[Texture2D] = []

static var _default_tileset: TileSet

var terrain_layer := TileMapLayer.new()
var _borders := Node2D.new()
var _edges := PackedVector2Array()
var _side := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	terrain_layer.name = "TerrainTiles"
	terrain_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(terrain_layer)
	_borders.name = "BoardBorders"
	_borders.z_index = 1
	_borders.draw.connect(_draw_borders)
	add_child(_borders)


func set_board(side: int, regions: PackedInt32Array) -> void:
	assert(side > 0 and side <= Surfaces.BOARD_CAPACITY and regions.size() == side * side)
	_side = side
	custom_minimum_size = Vector2.ONE * side * CELL_SIZE
	if terrain_layer.tile_set == null:
		if material_sheets.is_empty():
			if _default_tileset == null:
				_default_tileset = _new_tileset()
			terrain_layer.tile_set = _default_tileset
		else:
			terrain_layer.tile_set = _new_tileset()
	terrain_layer.clear()
	_edges.clear()
	for y in side:
		for x in side:
			var cell := Vector2i(x, y)
			var index := y * side + x
			var region := regions[index]
			_ensure_atlas(region)
			# The atlas coordinate is the board coordinate, preserving the phase
			# of every detail across adjacent tiles from the same sheet.
			terrain_layer.set_cell(cell, region, cell)
			var corner := Vector2(x, y) * CELL_SIZE
			if x > 0 and region != regions[index - 1]:
				_edges.append(corner)
				_edges.append(corner + Vector2(0, CELL_SIZE))
			if y > 0 and region != regions[index - side]:
				_edges.append(corner)
				_edges.append(corner + Vector2(CELL_SIZE, 0))
	_borders.queue_redraw()


## Internal region edges, stored as endpoint pairs in board pixels.
func region_edges() -> PackedVector2Array:
	return _edges.duplicate()


func _new_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i.ONE * CELL_SIZE
	return tileset


func _ensure_atlas(region: int) -> void:
	var tileset := terrain_layer.tile_set
	if tileset.has_source(region):
		return
	var texture: Texture2D
	if region < material_sheets.size():
		texture = material_sheets[region]
		if texture != null and texture.get_size() != Vector2.ONE * Surfaces.SHEET_SIZE:
			push_warning("Terrain sheets must be %d × %d pixels." % [Surfaces.SHEET_SIZE, Surfaces.SHEET_SIZE])
			texture = null
	var atlas := TileSetAtlasSource.new()
	atlas.texture_region_size = tileset.tile_size
	atlas.texture = texture if texture != null else Surfaces.make_texture(region)
	tileset.add_source(atlas, region)
	for y in Surfaces.BOARD_CAPACITY:
		for x in Surfaces.BOARD_CAPACITY:
			atlas.create_tile(Vector2i(x, y))


func _draw_borders() -> void:
	var span := _side * CELL_SIZE
	for index in range(1, _side):
		var offset := index * CELL_SIZE
		_borders.draw_rect(Rect2(offset, 0, 1, span), GRID_COLOR)
		_borders.draw_rect(Rect2(0, offset, span, 1), GRID_COLOR)

	var bounds := Rect2(0, 0, span, span)
	var join_offset := Vector2.ONE * (REGION_WIDTH * 0.5)
	for index in range(0, _edges.size(), 2):
		var start := _edges[index] - join_offset
		var end := _edges[index + 1] + join_offset
		_borders.draw_rect(Rect2(start, end - start).intersection(bounds), Color.BLACK)

	_borders.draw_rect(Rect2(0, 0, span, REGION_WIDTH), Color.BLACK)
	_borders.draw_rect(Rect2(0, span - REGION_WIDTH, span, REGION_WIDTH), Color.BLACK)
	_borders.draw_rect(Rect2(0, 0, REGION_WIDTH, span), Color.BLACK)
	_borders.draw_rect(Rect2(span - REGION_WIDTH, 0, REGION_WIDTH, span), Color.BLACK)

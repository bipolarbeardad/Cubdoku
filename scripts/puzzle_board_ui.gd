extends CenterContainer
## Presents the prototype board and forwards input to the game state.

const Validator := preload("res://scripts/puzzle_validator.gd")
const GameState := preload("res://scripts/puzzle_game_state.gd")
const Session := preload("res://scripts/puzzle_session.gd")
const BoardTerrain := preload("res://scripts/board_terrain.gd")

@export var terrain_sheets: Array[Texture2D] = []

var _session: Session
var _regions := PackedInt32Array()
var _header := Label.new()
var _hearts := Label.new()
var _timer := Label.new()
var _feedback := Label.new()
var _mode := OptionButton.new()
var _next_button := Button.new()
var _campaign_button := Button.new()
var _cells: Array[Button] = []
var _terrain := BoardTerrain.new()


func _ready() -> void:
	if _session == null:
		_session = Session.new()
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	add_child(layout)

	_header.add_theme_font_size_override("font_size", 26)
	layout.add_child(_header)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 20)
	layout.add_child(stats)
	stats.add_child(_hearts)
	stats.add_child(_timer)

	var board_center := CenterContainer.new()
	layout.add_child(board_center)
	_terrain.material_sheets = terrain_sheets
	board_center.add_child(_terrain)
	var grid := GridContainer.new()
	grid.columns = Validator.SIZE
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	grid.z_index = 2
	_terrain.add_child(grid)
	var empty := StyleBoxEmpty.new()
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.11)
	hover.set_expand_margin_all(-BoardTerrain.REGION_WIDTH)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(1, 1, 1, 0.85)
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(-BoardTerrain.REGION_WIDTH)
	for cell in Validator.CELL_COUNT:
		var button := Button.new()
		button.custom_minimum_size = Vector2.ONE * BoardTerrain.CELL_SIZE
		button.add_theme_font_size_override("font_size", 24)
		button.add_theme_color_override("font_disabled_color", Color.WHITE)
		button.add_theme_color_override("font_outline_color", Color.BLACK)
		button.add_theme_constant_override("outline_size", 5)
		button.add_theme_stylebox_override("normal", empty)
		button.add_theme_stylebox_override("disabled", empty)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.add_theme_stylebox_override("focus", focus)
		button.pressed.connect(_mark_cell.bind(cell))
		grid.add_child(button)
		_cells.append(button)

	var controls := HBoxContainer.new()
	layout.add_child(controls)
	_mode.add_item("Place bear", GameState.Mark.BEAR)
	_mode.add_item("Mark X", GameState.Mark.X)
	controls.add_child(_mode)

	var restart_button := Button.new()
	restart_button.text = "Restart"
	restart_button.pressed.connect(_restart)
	controls.add_child(restart_button)
	var generate_button := Button.new()
	generate_button.text = "Generate test puzzle"
	generate_button.pressed.connect(_new_puzzle)
	controls.add_child(generate_button)
	_next_button.text = "Next puzzle"
	_next_button.disabled = true
	_next_button.pressed.connect(_advance)
	controls.add_child(_next_button)
	_campaign_button.text = "Return to Campaign Path"
	_campaign_button.pressed.connect(_open_campaign)
	layout.add_child(_campaign_button)

	var instructions := Label.new()
	instructions.text = "One bear per row, column and color. Bears cannot touch."
	layout.add_child(instructions)
	_feedback.custom_minimum_size.y = 26
	layout.add_child(_feedback)
	_open_campaign()


func _process(delta: float) -> void:
	var had_save_error := _session.save_error
	_session.tick(delta)
	if _session.save_error and not had_save_error:
		_feedback.text = "Could not save campaign progress."
	_update_timer()


func _exit_tree() -> void:
	if _session != null:
		_session.flush_attempt()


func _new_puzzle() -> void:
	_show_loaded_puzzle(_session.load_free_play())


func _open_campaign() -> void:
	_show_loaded_puzzle(_session.load_campaign())


func _advance() -> void:
	if _session.can_advance():
		_show_loaded_puzzle(_session.advance())


func _show_loaded_puzzle(loaded: bool) -> void:
	if not loaded:
		_feedback.text = "Could not load or save the puzzle."
		return

	var definition := _session.definition_snapshot()
	_regions = definition.regions
	if _session.mode() == Session.Mode.CAMPAIGN_PATH:
		_header.text = "Campaign Path #%d · %s" % [_session.campaign_number(), definition.difficulty]
	else:
		_header.text = "Free Play · %s" % definition.difficulty
	_campaign_button.visible = _session.mode() == Session.Mode.FREE_PLAY
	_terrain.set_board(definition.size, _regions)
	_reset_display()


func _restart() -> void:
	if _regions.is_empty():
		return
	if _session.restart():
		_reset_display()
	else:
		_feedback.text = "Could not save campaign progress."


func _reset_display() -> void:
	_mode.select(0)
	match _session.game.status:
		GameState.Status.COMPLETE:
			_feedback.text = "Puzzle complete!"
		GameState.Status.FAILED:
			_feedback.text = "No hearts left. Restart to try again."
		_:
			_feedback.text = ""
	_update_timer()
	_update_board()


func _mark_cell(cell: int) -> void:
	var mark := _mode.get_selected_id() as GameState.Mark
	var result := _session.toggle_mark(cell, mark)
	if _session.save_error:
		_feedback.text = "Could not save campaign progress."
		return
	match _session.game.status:
		GameState.Status.COMPLETE:
			_feedback.text = "Puzzle complete!"
		GameState.Status.FAILED:
			_feedback.text = "No hearts left. Restart to try again."
		_:
			_feedback.text = "Incorrect bear. One heart lost." if (
				result == GameState.Result.INCORRECT_BEAR
			) else ""
	_update_board()


func _update_board() -> void:
	_next_button.disabled = not _session.can_advance()
	var symbols := ["", "Bear", "X"]
	for cell in _cells.size():
		_cells[cell].text = symbols[_session.game.mark_at(cell)]
		_cells[cell].disabled = _session.game.status != GameState.Status.PLAYING
	_hearts.text = "Hearts  " + "♥".repeat(_session.game.hearts) + "♡".repeat(
		GameState.MAX_HEARTS - _session.game.hearts
	)


func _update_timer() -> void:
	var seconds := int(_session.elapsed)
	@warning_ignore("integer_division")
	_timer.text = "Time  %02d:%02d" % [seconds / 60, seconds % 60]

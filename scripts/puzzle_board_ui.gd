extends CenterContainer
## Presents the prototype board and forwards input to the game state.

const Validator := preload("res://scripts/puzzle_validator.gd")
const GameState := preload("res://scripts/puzzle_game_state.gd")
const Session := preload("res://scripts/puzzle_session.gd")
const BoardTerrain := preload("res://scripts/board_terrain.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const FreePlay := preload("res://scripts/free_play_generation.gd")
const DeveloperPanel := preload("res://scripts/free_play_developer.gd")
const Elimination := preload("res://scripts/nightmares_elimination.gd")
const MAX_BOARD_SPAN := 378
const HOLD_MSEC := 400
const BEAR_SYMBOL := "🐻"

@export var terrain_sheets: Array[Texture2D] = []
@export var enable_developer_tools := false

var _session: Session
var _regions := PackedInt32Array()
var _header := Label.new()
var _hearts := Label.new()
var _timer := Label.new()
var _feedback := Label.new()
var _next_button := Button.new()
var _campaign_button := Button.new()
var _free_play_controls := HBoxContainer.new()
var _free_play_difficulty := OptionButton.new()
var _generate_button := Button.new()
var _provisioner: FreePlay
var _developer: DeveloperPanel
var _generation: Thread
var _cells: Array[Button] = []
var _terrain := BoardTerrain.new()
var _board_frame := Control.new()
var _grid := GridContainer.new()
var _hold_indicator := ProgressBar.new()
var _hold_cell := -1
var _hold_started := 0
var _line_chime := AudioStreamPlayer.new()
var _warning := AudioStreamPlayer.new()
var _error_flash := ColorRect.new()
var _flash_tween: Tween


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
	board_center.add_child(_board_frame)
	_board_frame.add_child(_terrain)
	_configure_grid()
	_configure_feedback()

	var controls := HBoxContainer.new()
	layout.add_child(controls)

	var restart_button := Button.new()
	restart_button.text = "Restart"
	restart_button.pressed.connect(_restart)
	controls.add_child(restart_button)
	_generate_button.text = "Free Play"
	_generate_button.pressed.connect(func() -> void: _new_puzzle())
	controls.add_child(_generate_button)
	_next_button.text = "Next puzzle"
	_next_button.disabled = true
	_next_button.pressed.connect(_advance)
	controls.add_child(_next_button)
	_campaign_button.text = "Return to Campaign Path"
	_campaign_button.pressed.connect(_open_campaign)
	_free_play_controls.visible = false
	layout.add_child(_free_play_controls)
	var size_label := Label.new()
	size_label.text = "Difficulty"
	_free_play_controls.add_child(size_label)
	for difficulty in FreePlay.DIFFICULTIES:
		_free_play_difficulty.add_item(difficulty)
	_free_play_difficulty.select(0)
	_free_play_difficulty.item_selected.connect(func(_index: int) -> void: _new_puzzle())
	_free_play_controls.add_child(_free_play_difficulty)
	_free_play_controls.add_child(_campaign_button)
	if enable_developer_tools or "--free-play-dev" in OS.get_cmdline_user_args():
		_configure_developer(controls)

	var instructions := Label.new()
	instructions.text = "Hold left click for a bear. Right click for an X.\nOne bear per row, column and color. Bears cannot touch."
	layout.add_child(instructions)
	_feedback.custom_minimum_size.y = 26
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_feedback)
	_open_campaign()


func _configure_grid() -> void:
	_grid.add_theme_constant_override("h_separation", 0)
	_grid.add_theme_constant_override("v_separation", 0)
	_grid.z_index = 2
	_terrain.add_child(_grid)
	var empty := StyleBoxEmpty.new()
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.11)
	hover.set_expand_margin_all(-BoardTerrain.REGION_WIDTH)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(1, 1, 1, 0.85)
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(-BoardTerrain.REGION_WIDTH)
	var styles := Theme.new()
	styles.set_font_size("font_size", "Button", 24)
	styles.set_color("font_disabled_color", "Button", Color.WHITE)
	styles.set_color("font_outline_color", "Button", Color.BLACK)
	styles.set_constant("outline_size", "Button", 5)
	styles.set_stylebox("normal", "Button", empty)
	styles.set_stylebox("disabled", "Button", empty)
	styles.set_stylebox("hover", "Button", hover)
	styles.set_stylebox("pressed", "Button", hover)
	styles.set_stylebox("focus", "Button", focus)
	_grid.theme = styles


func _resize_grid(side: int) -> void:
	_grid.columns = side
	var cell_count := side * side
	while _cells.size() > cell_count:
		var extra: Button = _cells.pop_back()
		_grid.remove_child(extra)
		extra.queue_free()
	for cell in range(_cells.size(), cell_count):
		var button := Button.new()
		button.custom_minimum_size = Vector2.ONE * BoardTerrain.CELL_SIZE
		button.focus_mode = Control.FOCUS_NONE
		_grid.add_child(button)
		_cells.append(button)
	for button in _cells:
		button.add_theme_font_size_override("font_size", maxi(24, side * 4))
	# Keep both native layers at atlas scale and apply one uniform transform.
	@warning_ignore("integer_division")
	var display_cell_size := mini(BoardTerrain.CELL_SIZE, MAX_BOARD_SPAN / side)
	_board_frame.custom_minimum_size = Vector2.ONE * display_cell_size * side
	_terrain.scale = Vector2.ONE * (float(display_cell_size) / BoardTerrain.CELL_SIZE)
	_grid.size = Vector2.ONE * BoardTerrain.CELL_SIZE * side


func _process(delta: float) -> void:
	if _generation != null:
		if not _generation.is_alive():
			var definition: Dictionary = _generation.wait_to_finish()
			_generation = null
			_generate_button.disabled = false
			_free_play_difficulty.disabled = false
			_apply_free_play(definition)
		return
	_update_hold()
	var had_save_error := _session.save_error
	_session.tick(delta)
	if _session.save_error and not had_save_error:
		_feedback.text = "Could not save campaign progress."
	_update_timer()


func _exit_tree() -> void:
	if _generation != null:
		_generation.wait_to_finish()
	if _session != null:
		_session.flush_attempt()


func _new_puzzle(difficulty := "", side := 0, seed_text := "") -> void:
	if _generation != null:
		return
	if not seed_text.is_empty() and not seed_text.is_valid_int():
		_feedback.text = "Enter an integer seed or leave it blank."
		return
	if difficulty.is_empty():
		difficulty = _free_play_difficulty.get_item_text(_free_play_difficulty.selected)
	if _provisioner == null:
		_provisioner = FreePlay.new()
	var seed_value := randi() if seed_text.is_empty() else seed_text.to_int()
	_cancel_hold()
	_feedback.text = "Generating %s…" % difficulty
	if _developer != null:
		_developer.details.text = _feedback.text
	_generate_button.disabled = true
	_free_play_difficulty.disabled = true
	_generation = Thread.new()
	if _generation.start(_provisioner.generate.bind(difficulty, side, seed_value)) != OK:
		_generation = null
		_generate_button.disabled = false
		_free_play_difficulty.disabled = false
		_feedback.text = "Could not start puzzle generation."


func _apply_free_play(definition: Dictionary) -> void:
	if definition.has("error"):
		_feedback.text = definition.error
		var active := _session.definition_snapshot()
		if _session.mode() == Session.Mode.FREE_PLAY:
			_free_play_difficulty.select(FreePlay.DIFFICULTIES.find(active.difficulty))
		if _developer != null:
			_developer.details.text = definition.error
		return
	if _session.install_free_play(definition):
		if definition.source == "Reopened definition":
			if _provisioner == null:
				_provisioner = FreePlay.new()
			_provisioner.remember(definition)
		_free_play_difficulty.select(FreePlay.DIFFICULTIES.find(definition.difficulty))
		_show_loaded_puzzle(true)
		_feedback.text = "Loaded %s." % definition.source.to_lower()
		if _developer != null:
			_developer.details.text = "%s  |  %dx%d  |  %s  |  %.1f ms\nValidated  |  Seed %s" % [
				definition.id, definition.size, definition.size, definition.source,
				definition.generation_ms, definition.seed]
			_developer.trace.clear()
	else:
		_feedback.text = "Could not load the validated Free Play definition."


func _open_campaign() -> void:
	if _generation != null:
		return
	_show_loaded_puzzle(_session.load_campaign())


func _advance() -> void:
	if _generation == null and _session.can_advance():
		_show_loaded_puzzle(_session.advance())


func _show_loaded_puzzle(loaded: bool) -> void:
	_cancel_hold()
	if not loaded:
		_feedback.text = "Could not load or save the puzzle."
		return

	var definition := _session.definition_snapshot()
	_regions = definition.regions
	if _session.mode() == Session.Mode.CAMPAIGN_PATH:
		_header.text = "Campaign Path #%d · %s" % [_session.campaign_number(), definition.difficulty]
	else:
		_header.text = "Free Play · %s" % definition.difficulty
	_free_play_controls.visible = _session.mode() == Session.Mode.FREE_PLAY
	_generate_button.text = "Generate New Puzzle" if _free_play_controls.visible else "Free Play"
	_terrain.set_board(definition.size, _regions)
	_resize_grid(definition.size)
	if "--puzzle-diagnostics" in OS.get_cmdline_user_args():
		var analysis := Analyzer.analyze(_regions)
		var singleton_count := 0
		for region in int(definition.size):
			singleton_count += int(_regions.count(region) == 1)
		print("Puzzle %d×%d: %d logical deductions, %d singleton regions (%s)" % [
			definition.size, definition.size, analysis.deductions.size(), singleton_count,
			Analyzer.Status.keys()[analysis.status],
		])
	_reset_display()


func _restart() -> void:
	_cancel_hold()
	if _regions.is_empty() or _generation != null:
		return
	if _session.restart():
		_reset_display()
	else:
		_feedback.text = "Could not save campaign progress."


func _reset_display() -> void:
	_line_chime.stop()
	_warning.stop()
	_error_flash.hide()
	match _session.game.status:
		GameState.Status.COMPLETE:
			_feedback.text = "Puzzle complete!"
		GameState.Status.FAILED:
			_feedback.text = "No hearts left. Restart to try again."
		_:
			_feedback.text = ""
	_update_timer()
	_update_board()


func _mark_cell(cell: int, mark: GameState.Mark) -> void:
	var result := _session.toggle_mark(cell, mark)
	if _session.save_error:
		_feedback.text = "Could not save campaign progress."
		return
	if result == GameState.Result.IGNORED:
		return
	if result == GameState.Result.INCORRECT_X:
		_flash_wrong_x(cell)
	if _session.game.completes_line_at(cell, _grid.columns):
		_line_chime.play()
	match _session.game.status:
		GameState.Status.COMPLETE:
			_feedback.text = "Puzzle complete!"
		GameState.Status.FAILED:
			_feedback.text = "No hearts left. Restart to try again."
		_:
			_feedback.text = ""
			if result == GameState.Result.INCORRECT_BEAR:
				_feedback.text = "Incorrect bear. One heart lost."
			elif result == GameState.Result.INCORRECT_X:
				_feedback.text = "Incorrect X. One heart lost."
	_update_board()


func _update_board() -> void:
	_next_button.disabled = not _session.can_advance()
	var symbols := ["", BEAR_SYMBOL, "X"]
	for cell in _cells.size():
		_cells[cell].text = symbols[_session.game.mark_at(cell)]
		_cells[cell].disabled = _session.game.status != GameState.Status.PLAYING or _session.game.is_locked(cell)
	_hearts.text = "Hearts  " + "♥".repeat(_session.game.hearts) + "♡".repeat(
		GameState.MAX_HEARTS - _session.game.hearts
	)


func _update_timer() -> void:
	var seconds := int(_session.elapsed)
	@warning_ignore("integer_division")
	_timer.text = "Time  %02d:%02d" % [seconds / 60, seconds % 60]


func _press_cell(button: MouseButton, cell: int) -> void:
	get_viewport().set_input_as_handled()
	if _cells[cell].disabled:
		return
	if button == MOUSE_BUTTON_RIGHT:
		_cancel_hold()
		_mark_cell(cell, GameState.Mark.X)
	elif _hold_cell < 0:
		_hold_cell = cell
		_hold_started = Time.get_ticks_msec()
		_hold_indicator.position = _cells[cell].position + Vector2(12, BoardTerrain.CELL_SIZE - 16)
		_hold_indicator.value = 0.0
		_hold_indicator.show()


func _input(event: InputEvent) -> void:
	if _generation != null or not event is InputEventMouse or _cells.is_empty() or not is_visible_in_tree():
		return
	var local: Vector2 = _grid.get_global_transform_with_canvas().affine_inverse() * event.position
	var cell := -1
	var span := _grid.columns * BoardTerrain.CELL_SIZE
	if Rect2(Vector2.ZERO, Vector2.ONE * span).has_point(local):
		cell = floori(local.y / BoardTerrain.CELL_SIZE) * _grid.columns + floori(local.x / BoardTerrain.CELL_SIZE)
	if _hold_cell >= 0:
		if cell != _hold_cell:
			_cancel_hold()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_update_hold()
			_cancel_hold()
	if cell >= 0 and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_press_cell(event.button_index, cell)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_WM_MOUSE_EXIT:
		_cancel_hold()


func _update_hold() -> void:
	if _hold_cell < 0:
		return
	var elapsed := Time.get_ticks_msec() - _hold_started
	_hold_indicator.value = elapsed
	if elapsed >= HOLD_MSEC:
		var cell := _hold_cell
		_cancel_hold()
		_mark_cell(cell, GameState.Mark.BEAR)


func _cancel_hold() -> void:
	_hold_cell = -1
	_hold_indicator.hide()


func _configure_feedback() -> void:
	_hold_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_indicator.show_percentage = false
	_hold_indicator.max_value = HOLD_MSEC
	_hold_indicator.size = Vector2(BoardTerrain.CELL_SIZE - 24, 6)
	_hold_indicator.z_index = 3
	_hold_indicator.hide()
	_terrain.add_child(_hold_indicator)
	_error_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_error_flash.z_index = 3
	_error_flash.size = Vector2.ONE * BoardTerrain.CELL_SIZE
	_error_flash.hide()
	_terrain.add_child(_error_flash)
	_line_chime.stream = _tone(false)
	_warning.stream = _tone(true)
	add_child(_line_chime)
	add_child(_warning)


static func _tone(warning: bool) -> AudioStreamWAV:
	var chime := AudioStreamWAV.new()
	chime.format = AudioStreamWAV.FORMAT_16_BITS
	chime.mix_rate = 22050
	var samples := PackedByteArray()
	var frame_count := int(chime.mix_rate * 0.24)
	samples.resize(frame_count * 2)
	for frame in frame_count:
		var seconds := float(frame) / chime.mix_rate
		var envelope := minf(seconds / 0.012, 1.0) * pow(1.0 - float(frame) / frame_count, 2)
		var wave := sin(TAU * (420.0 - 620.0 * seconds) * seconds) if warning else (
			sin(TAU * 660.0 * seconds) + 0.35 * sin(TAU * 880.0 * seconds))
		samples.encode_s16(frame * 2, int(3500 * envelope * wave))
	chime.data = samples
	return chime


func _flash_wrong_x(cell: int) -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_error_flash.position = _cells[cell].position
	_error_flash.color = Color(0.95, 0.10, 0.12, 0.66)
	_error_flash.show()
	_warning.play()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_error_flash, "color:a", 0.0, 0.27)
	_flash_tween.tween_callback(_error_flash.hide)


func _configure_developer(controls: HBoxContainer) -> void:
	_developer = DeveloperPanel.new()
	_developer.hide()
	add_child(_developer)
	_developer.generate_requested.connect(_new_puzzle)
	_developer.restart_requested.connect(func() -> void:
		if _session.mode() == Session.Mode.FREE_PLAY:
			_restart())
	_developer.save_requested.connect(func() -> void:
		if _session.mode() == Session.Mode.FREE_PLAY:
			_developer.details.text = "Definition saved." if FreePlay.save_slot(_session.definition_snapshot()) else "Could not save the definition.")
	_developer.reopen_requested.connect(func() -> void:
		if _generation == null:
			_apply_free_play(FreePlay.reopen_slot()))
	_developer.diagnostics_requested.connect(_show_diagnostics)
	var toggle := Button.new()
	toggle.text = "Developer"
	toggle.pressed.connect(func() -> void:
		if _developer.visible:
			_developer.hide()
		else:
			_developer.popup_centered())
	controls.add_child(toggle)


func _show_diagnostics() -> void:
	if _developer == null or _session.mode() != Session.Mode.FREE_PLAY:
		return
	var bears := PackedInt32Array()
	var excluded := PackedInt32Array()
	for cell in _regions.size():
		match _session.game.mark_at(cell):
			GameState.Mark.BEAR: bears.append(cell)
			GameState.Mark.X: excluded.append(cell)
	var side := _grid.columns
	var families := Analyzer.EXTENDED_FAMILIES
	if _developer.alternate_proof.button_pressed:
		families &= ~Analyzer.Family.CHAINS
	var proof := Elimination.new().analyze(_regions, families, bears, excluded, true)
	var lines := PackedStringArray(["Logical proof from visible rules and current marks. Cells are r<row>c<column>.",
		"Available moves in the first applicable deduction tier:"])
	for step in proof.get("opening_options", []):
		lines.append(_describe_step(step, side))
	lines.append("\nProof trace (%s):" % Analyzer.Status.keys()[proof.status])
	for step in proof.deductions:
		lines.append(_describe_step(step, side))
	_developer.trace.text = "\n".join(lines)


static func _describe_step(step: Dictionary, side: int) -> String:
	var text := "%s | bears %s | X %s" % [Analyzer.Technique.keys()[step.technique],
		_cell_list(step.get("confirmed", []), side), _cell_list(step.eliminated, side)]
	var groups := PackedStringArray()
	for group: int in step.groups:
		groups.append("%s %d" % [["region", "row", "column"][floori(float(group) / side)], group % side + 1])
	if not groups.is_empty():
		text += " | " + ", ".join(groups)
	if step.has("target_groups"):
		var targets := PackedStringArray()
		for group: int in step.target_groups:
			targets.append("%s %d" % [["region", "row", "column"][floori(float(group) / side)], group % side + 1])
		if not targets.is_empty():
			text += " | targets " + ", ".join(targets)
	if step.has("line_mask"):
		var reserved := PackedStringArray()
		for index in side:
			if step.line_mask & (1 << index):
				reserved.append(str(index + 1))
		text += " | reserved %s %s" % ["columns" if step.column_reservation else "rows", ", ".join(reserved)]
	for field in ["cells", "hypothetical_bears"]:
		if step.has(field):
			text += " | %s %s" % [field, _cell_list(step[field], side)]
	if step.has("implication_path"):
		var path := PackedStringArray()
		for literal: int in step.implication_path:
			path.append(("%s " % ("X" if literal & 1 else "bear")) + _cell_list([literal >> 1], side))
		text += " | " + " → ".join(path)
	return text


static func _cell_list(cells: Variant, side: int) -> String:
	var labels := PackedStringArray()
	for cell: int in cells:
		labels.append("r%dc%d" % [floori(float(cell) / side) + 1, cell % side + 1])
	return ", ".join(labels)

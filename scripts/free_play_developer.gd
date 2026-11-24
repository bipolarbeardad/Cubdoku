extends Window

signal generate_requested(difficulty: String, side: int, seed_text: String)
signal restart_requested
signal save_requested
signal reopen_requested
signal diagnostics_requested

const FreePlay := preload("res://scripts/free_play_generation.gd")
const Schedule := preload("res://scripts/campaign_schedule.gd")

var difficulty := OptionButton.new()
var size_override := OptionButton.new()
var seed_field := LineEdit.new()
var details := Label.new()
var trace := TextEdit.new()
var alternate_proof := CheckButton.new()


func _ready() -> void:
	title = "Free Play developer tools"
	size = Vector2i(510, 380)
	min_size = Vector2i(460, 300)
	transient = true
	exclusive = false
	close_requested.connect(hide)
	var layout := VBoxContainer.new()
	add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	var options := HBoxContainer.new()
	layout.add_child(options)
	for label in FreePlay.DIFFICULTIES:
		difficulty.add_item(label)
	options.add_child(difficulty)
	options.add_child(size_override)
	seed_field.placeholder_text = "Seed (blank = random)"
	seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_child(seed_field)
	difficulty.item_selected.connect(func(_index: int) -> void: _update_sizes())
	_update_sizes()
	var actions := HBoxContainer.new()
	layout.add_child(actions)
	_add_button(actions, "Generate New Puzzle", func() -> void:
		generate_requested.emit(difficulty.get_item_text(difficulty.selected), size_override.get_selected_id(), seed_field.text))
	_add_button(actions, "Restart Current Puzzle", func() -> void: restart_requested.emit())
	_add_button(actions, "Show deduction proof", func() -> void: diagnostics_requested.emit())
	var files := HBoxContainer.new()
	layout.add_child(files)
	_add_button(files, "Save definition", func() -> void: save_requested.emit())
	_add_button(files, "Reopen definition", func() -> void: reopen_requested.emit())
	layout.add_child(details)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	alternate_proof.text = "Explore Hall and contradiction proofs without chains"
	layout.add_child(alternate_proof)
	trace.editable = false
	trace.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	trace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	trace.placeholder_text = "Proofs use visible rules and current marks. No stored solution hints."
	layout.add_child(trace)


func _update_sizes() -> void:
	var limits: Vector2i = Schedule.SIZES[difficulty.get_item_text(difficulty.selected)]
	size_override.clear()
	size_override.add_item("Auto size", 0)
	for side in range(limits.x, limits.y + 1):
		size_override.add_item("%d x %d" % [side, side], side)
	size_override.select(0)


func _add_button(row: HBoxContainer, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	row.add_child(button)

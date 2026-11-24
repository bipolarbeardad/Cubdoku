extends RefCounted
## Applies actions to one validated puzzle without any UI dependencies.

const Validator := preload("res://scripts/puzzle_validator.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const MAX_HEARTS := 3

enum Mark { CLEAR, BEAR, X }
enum Status { PLAYING, COMPLETE, FAILED }
enum Result { IGNORED, CHANGED, INCORRECT_BEAR, INCORRECT_X }

var hearts := MAX_HEARTS
var status := Status.PLAYING
var _marks := PackedInt32Array()
var _solution := PackedInt32Array()
var _locked_bears := PackedInt32Array()
var _bear_count := 0
var _cell_count := Validator.CELL_COUNT


func load_puzzle(regions: PackedInt32Array, expected_solution := PackedInt32Array(),
	locked_bears := PackedInt32Array()) -> bool:
	var solutions := Solver.find_solutions(regions)
	if solutions.size() != 1:
		return false
	if not expected_solution.is_empty() and solutions[0] != expected_solution:
		return false
	var givens := PackedInt32Array()
	for cell in locked_bears:
		if not solutions[0].has(cell) or givens.has(cell):
			return false
		givens.append(cell)
	_locked_bears = givens
	_solution = solutions[0]
	_cell_count = regions.size()
	restart()
	return true


func solution_snapshot() -> PackedInt32Array:
	return _solution.duplicate()


func restart() -> void:
	_marks.resize(_cell_count)
	_marks.fill(Mark.CLEAR)
	for cell in _locked_bears:
		_marks[cell] = Mark.BEAR
	_bear_count = _locked_bears.size()
	hearts = MAX_HEARTS
	status = Status.COMPLETE if not _solution.is_empty() and _bear_count == _solution.size() else Status.PLAYING


func attempt_snapshot() -> Dictionary:
	return {"marks": _marks.duplicate(), "hearts": hearts}


func restore_attempt(snapshot: Dictionary) -> bool:
	var marks: Variant = snapshot.get("marks")
	var remaining: Variant = snapshot.get("hearts")
	if not marks is PackedInt32Array or marks.size() != _cell_count:
		return false
	if not remaining is int or remaining < 0 or remaining > MAX_HEARTS:
		return false
	var bears := 0
	for cell in _locked_bears:
		if marks[cell] != Mark.BEAR:
			return false
	for cell in marks.size():
		if marks[cell] == Mark.BEAR and _solution.has(cell):
			bears += 1
		elif marks[cell] != Mark.CLEAR and marks[cell] != Mark.X:
			return false
	if remaining == 0 and bears == _solution.size():
		return false
	_marks = marks.duplicate()
	hearts = remaining
	_bear_count = bears
	status = Status.PLAYING
	if hearts == 0:
		status = Status.FAILED
	elif _bear_count == _solution.size() and not _solution.is_empty():
		status = Status.COMPLETE
	return true


func mark_at(cell: int) -> Mark:
	if cell < 0 or cell >= _marks.size():
		return Mark.CLEAR
	return _marks[cell] as Mark


func is_locked(cell: int) -> bool:
	var mark := mark_at(cell)
	return mark == Mark.BEAR or (mark == Mark.X and not _solution.has(cell))


func completes_line_at(cell: int, side: int) -> bool:
	if not is_locked(cell):
		return false
	@warning_ignore("integer_division")
	var row_start := (cell / side) * side
	var column := cell % side
	var row_complete := true
	var column_complete := true
	for offset in side:
		row_complete = row_complete and is_locked(row_start + offset)
		column_complete = column_complete and is_locked(offset * side + column)
	return row_complete or column_complete


func toggle_mark(cell: int, mark: Mark) -> Result:
	if _solution.is_empty() or status != Status.PLAYING or cell < 0 or cell >= _marks.size():
		return Result.IGNORED
	if is_locked(cell) or mark == Mark.CLEAR:
		return Result.IGNORED

	var previous := mark_at(cell)
	var next_mark := Mark.CLEAR if previous == mark else mark
	if mark == Mark.X and _solution.has(cell):
		_marks[cell] = Mark.CLEAR
		hearts -= 1
		if hearts == 0:
			status = Status.FAILED
		return Result.INCORRECT_X
	if next_mark == Mark.BEAR and not _solution.has(cell):
		_marks[cell] = Mark.X
		hearts -= 1
		if hearts == 0:
			status = Status.FAILED
		return Result.INCORRECT_BEAR

	_marks[cell] = next_mark
	if next_mark == Mark.BEAR:
		_bear_count += 1
	if _bear_count == _solution.size():
		status = Status.COMPLETE
	return Result.CHANGED

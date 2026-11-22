extends RefCounted
## Applies actions to one validated puzzle without any UI dependencies.

const Validator := preload("res://scripts/puzzle_validator.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")
const MAX_HEARTS := 3

enum Mark { CLEAR, BEAR, X }
enum Status { PLAYING, COMPLETE, FAILED }
enum Result { IGNORED, CHANGED, INCORRECT_BEAR }

var hearts := MAX_HEARTS
var status := Status.PLAYING
var _marks := PackedInt32Array()
var _solution := PackedInt32Array()
var _bear_count := 0


func load_puzzle(regions: PackedInt32Array, expected_solution := PackedInt32Array()) -> bool:
	var solutions := Solver.find_solutions(regions)
	if solutions.size() != 1:
		return false
	if not expected_solution.is_empty() and solutions[0] != expected_solution:
		return false
	_solution = solutions[0]
	restart()
	return true


func solution_snapshot() -> PackedInt32Array:
	return _solution.duplicate()


func restart() -> void:
	_marks.resize(Validator.CELL_COUNT)
	_marks.fill(Mark.CLEAR)
	_bear_count = 0
	hearts = MAX_HEARTS
	status = Status.PLAYING


func attempt_snapshot() -> Dictionary:
	return {"marks": _marks.duplicate(), "hearts": hearts}


func restore_attempt(snapshot: Dictionary) -> bool:
	var marks: Variant = snapshot.get("marks")
	var remaining: Variant = snapshot.get("hearts")
	if not marks is PackedInt32Array or marks.size() != Validator.CELL_COUNT:
		return false
	if not remaining is int or remaining < 0 or remaining > MAX_HEARTS:
		return false
	var bears := 0
	for cell in marks.size():
		if marks[cell] == Mark.BEAR and _solution.has(cell):
			bears += 1
		elif marks[cell] != Mark.CLEAR and marks[cell] != Mark.X:
			return false
	if remaining == 0 and bears == Validator.SIZE:
		return false
	_marks = marks.duplicate()
	hearts = remaining
	_bear_count = bears
	status = Status.PLAYING
	if hearts == 0:
		status = Status.FAILED
	elif _bear_count == Validator.SIZE:
		status = Status.COMPLETE
	return true


func mark_at(cell: int) -> Mark:
	if cell < 0 or cell >= _marks.size():
		return Mark.CLEAR
	return _marks[cell] as Mark


func toggle_mark(cell: int, mark: Mark) -> Result:
	if _solution.is_empty() or status != Status.PLAYING or cell < 0 or cell >= _marks.size():
		return Result.IGNORED

	var previous := mark_at(cell)
	var next_mark := Mark.CLEAR if previous == mark else mark
	if next_mark == Mark.BEAR and not _solution.has(cell):
		hearts -= 1
		if hearts == 0:
			status = Status.FAILED
		return Result.INCORRECT_BEAR

	_marks[cell] = next_mark
	if previous == Mark.BEAR:
		_bear_count -= 1
	if next_mark == Mark.BEAR:
		_bear_count += 1
	if _bear_count == Validator.SIZE:
		status = Status.COMPLETE
	return Result.CHANGED

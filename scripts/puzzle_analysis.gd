extends RefCounted
## Combines independent reports so a logical dead end can be distinguished from ambiguity.

const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")

static func assess(regions: PackedInt32Array, advanced: bool = true) -> Dictionary:
	var logical := Analyzer.analyze(regions, advanced)
	var count := Solver.find_solutions(regions).size()
	var status: int = logical.status
	if count == 0:
		status = Analyzer.Status.INVALID
	elif count > 1:
		status = Analyzer.Status.MULTIPLE_SOLUTIONS
	return {"status": status, "solution_count": count, "logical": logical}

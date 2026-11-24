extends SceneTree
## Runs controlled technique ablations without invoking puzzle generation.

const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Patterns := preload("res://scripts/difficulty_patterns.gd")
const Solver := preload("res://scripts/puzzle_solver.gd")

const RESTRICTIONS := 1
const PAIRS := 2
const COMMON_CONFLICTS := 4
const ALL := RESTRICTIONS | PAIRS | COMMON_CONFLICTS

# The booleans cover BASE, R, P, R+P, C, R+C, P+C and R+P+C in that order.
const FIXTURES := {
	"base_5": [["11100", "11110", "44442", "34422", "44444"], "11111111"],
	"restriction_5": [["22000", "22011", "22333", "22333", "42233"], "01011111"],
	"conflict_5": [["11000", "11112", "34442", "34442", "44444"], "00001111"],
	"pair_7": [["0000111", "3330111", "3332241", "3333444", "5333444", "5554444", "5564444"], "00110011"],
	"conflict_7": [["0033331", "0233341", "0233344", "5333344", "5333646", "5555666", "5556666"], "00001111"],
	"pair_and_conflict_7": [["1000003", "1110003", "1140233", "4146633", "4444633", "4445666", "4446666"], "00000011"],
	"stuck_5": [["11000", "10003", "11233", "41233", "44223"], "00000000"],
}

var _failures := 0


func _initialize() -> void:
	for name: String in FIXTURES:
		var fixture: Array = FIXTURES[name]
		var regions := PackedInt32Array()
		for digit in "".join(fixture[0]):
			regions.append(int(digit))
		var side: int = fixture[0].size()
		var solutions := Solver.find_solutions(regions)
		_check(solutions.size() == 1, "%s has one solution" % name)
		for mask in range(ALL + 1):
			var report := _analyze_with_mask(regions, side, mask)
			var solved: bool = report.status == Analyzer.Status.SOLVED
			_check(report.status in [Analyzer.Status.SOLVED, Analyzer.Status.STUCK], "%s mask %d has a valid trace" % [name, mask])
			_check(solved == (fixture[1][mask] == "1"), "%s mask %d matches the expected outcome" % [name, mask])
			if solutions.size() == 1:
				if solved:
					_check(report.bears == solutions[0], "%s mask %d proves the solution" % [name, mask])
				for step: Dictionary in report.deductions:
					for removed in step.eliminated:
						_check(not solutions[0].has(removed), "%s mask %d retains every solution bear" % [name, mask])
			if mask in [0, ALL]:
				_check(report == Analyzer.analyze(regions, mask == ALL), "%s agrees with the production scheduler" % name)
			_print_result(name, mask, report)
	print("Difficulty study failures: %d" % _failures)
	quit(0 if _failures == 0 else 1)


func _analyze_with_mask(regions: PackedInt32Array, side: int, mask: int) -> Dictionary:
	# Reuse production moves and telemetry while selecting which patterns to offer.
	var report := Analyzer.analyze(PackedInt32Array())
	var groups := Analyzer._make_groups(regions, side)
	var candidates := PackedByteArray()
	candidates.resize(regions.size())
	candidates.fill(1)
	var depths := PackedInt32Array()
	depths.resize(regions.size())
	var bears := PackedInt32Array()
	while true:
		var remaining: Array[PackedInt32Array] = []
		var forced := {}
		for group in groups.size():
			var live := PackedInt32Array()
			for cell in groups[group]:
				if candidates[cell]:
					live.append(cell)
			if live.is_empty():
				report.status = Analyzer.Status.CONTRADICTION
				return report
			remaining.append(live)
			if live.size() == 1 and not bears.has(live[0]) and not forced.has(live[0]):
				forced[live[0]] = group
		if bears.size() == side:
			bears.sort()
			report.status = Analyzer.Status.SOLVED
			report.bears = bears
			return report
		if not forced.is_empty():
			var bear: int = forced.keys()[0]
			var group: int = forced[bear]
			bears.append(bear)
			var placement := Analyzer._placement(regions, candidates, side, bear, group, groups[group].size())
			Analyzer._record(report, placement, forced.size(), groups, candidates, depths)
			continue
		var options := _moves(remaining, regions, side, candidates, mask)
		if options.is_empty():
			report.status = Analyzer.Status.STUCK
			report.bears = bears
			return report
		var choices := {}
		for move in options:
			choices[move.eliminated] = true
		Analyzer._record(report, options[0], choices.size(), groups, candidates, depths)
	return report


func _moves(
	groups: Array[PackedInt32Array], regions: PackedInt32Array, side: int,
	candidates: PackedByteArray, mask: int,
) -> Array[Dictionary]:
	if mask & RESTRICTIONS:
		var restrictions := Patterns.restrictions(groups, 0, side, side, Analyzer.Technique.REGION_TO_ROW)
		restrictions.append_array(Patterns.restrictions(groups, 0, 2 * side, side, Analyzer.Technique.REGION_TO_COLUMN))
		restrictions.append_array(Patterns.restrictions(groups, side, 0, side, Analyzer.Technique.ROW_TO_REGION))
		restrictions.append_array(Patterns.restrictions(groups, 2 * side, 0, side, Analyzer.Technique.COLUMN_TO_REGION))
		if not restrictions.is_empty():
			return restrictions
	if mask & PAIRS:
		var pairs := Patterns.pairs(groups, side, Analyzer.Technique.CANDIDATE_PAIR)
		if not pairs.is_empty():
			return pairs
	if mask & COMMON_CONFLICTS:
		var conflicts: Array[PackedInt32Array] = []
		for first in candidates.size():
			var related := PackedInt32Array()
			if candidates[first]:
				for second in candidates.size():
					if second != first and candidates[second] and Analyzer._conflict_mask(regions, side, first, second):
						related.append(second)
			conflicts.append(related)
		return Patterns.common_conflicts(groups, candidates, conflicts, Analyzer.Technique.COMMON_CONFLICT)
	return []


func _print_result(name: String, mask: int, report: Dictionary) -> void:
	var highest: String = Analyzer.Technique.keys()[report.highest_technique] if report.highest_technique >= 0 else "NONE"
	print("%s mask=%d %s highest=%s steps=%d eliminated=%d chain=%d placed=%d" % [
		name, mask, Analyzer.Status.keys()[report.status], highest, report.total_steps,
		report.candidate_eliminations, report.longest_chain, report.forced_placements,
	])


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

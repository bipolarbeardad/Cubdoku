extends RefCounted
## Opt-in visible-candidate reasoning. No nested assumptions or committed branch placements.

const Analyzer := preload("res://scripts/difficulty_analyzer.gd")
const Hall := preload("res://scripts/nightmares_hall_reasoning.gd")
const MAX_FORCED := 8

var probes := 0


func analyze(board: PackedInt32Array, families: int, bears := PackedInt32Array(),
	excluded := PackedInt32Array(), include_options := false) -> Dictionary:
	probes = 0
	return Analyzer._analyze(board, families, {}, [], moves.bind(true, true), bears, excluded, include_options)


func moves(groups: Array[PackedInt32Array], board: PackedInt32Array, size: int,
	candidates: PackedByteArray, tight_first: bool, include_hall: bool) -> Array[Dictionary]:
	if include_hall:
		var reservation := Hall.moves(groups, board, size, candidates)
		if not reservation.is_empty():
			return reservation
	var order: Array[int] = []
	var widths := PackedInt32Array()
	widths.resize(board.size())
	widths.fill(board.size())
	for group in groups:
		for cell in group:
			widths[cell] = mini(widths[cell], group.size())
	for cell in candidates.size():
		if candidates[cell]:
			order.append(cell)
	if tight_first:
		order.sort_custom(func(a: int, b: int) -> bool:
			return a < b if widths[a] == widths[b] else widths[a] < widths[b])
	for assumed in order:
		probes += 1
		var branch := candidates.duplicate()
		var placements := PackedInt32Array([assumed])
		_assume(board, size, branch, assumed)
		for round_index in range(MAX_FORCED + 1):
			var forced := -1
			for index in groups.size():
				var live_count := 0
				var last := -1
				for cell in groups[index]:
					if branch[cell]:
						live_count += 1
						last = cell
				if live_count == 0:
					return [{"technique": Analyzer.Technique.BOUNDED_CONTRADICTION, "groups": [index],
						"eliminated": PackedInt32Array([assumed]), "hypothetical_bears": placements}]
				if live_count == 1 and not placements.has(last) and forced == -1:
					forced = last
			if forced == -1 or round_index == MAX_FORCED:
				break
			placements.append(forced)
			_assume(board, size, branch, forced)
	return []


static func _assume(board: PackedInt32Array, size: int, branch: PackedByteArray, bear: int) -> void:
	for cell in branch.size():
		if cell != bear and branch[cell] and Analyzer._conflict_mask(board, size, bear, cell):
			branch[cell] = 0


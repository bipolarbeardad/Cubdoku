extends RefCounted
## Derives bears from visible terrain and the candidates left by earlier deductions.

const Validator := preload("res://scripts/puzzle_validator.gd")
const Patterns := preload("res://scripts/difficulty_patterns.gd")
const AdvancedPatterns := preload("res://scripts/difficulty_advanced_patterns.gd")

enum Status { INVALID, CONTRADICTION, STUCK, SOLVED, MULTIPLE_SOLUTIONS }
enum Technique {
	SINGLE_CELL_REGION, REGION_SINGLE, ROW_SINGLE, COLUMN_SINGLE,
	ROW_ELIMINATION, COLUMN_ELIMINATION, REGION_ELIMINATION, DIAGONAL_EXCLUSION,
	REGION_TO_ROW, REGION_TO_COLUMN, ROW_TO_REGION, COLUMN_TO_REGION,
	CANDIDATE_PAIR, COMMON_CONFLICT,
	GROUP_TRIPLE, ADJACENCY_TRIPLE, IMPLICATION_CHAIN,
	REGION_HALL_SET, BOUNDED_CONTRADICTION,
}

# In the same order as the bits returned by _conflict_mask.
const ELIMINATION_TECHNIQUES := [
	Technique.ROW_ELIMINATION, Technique.COLUMN_ELIMINATION,
	Technique.REGION_ELIMINATION, Technique.DIAGONAL_EXCLUSION,
]
enum Family { RESTRICTIONS = 1, PAIRS = 2, COMMON_CONFLICTS = 4, TRIPLES = 8, CHAINS = 16 }
const ALL_FAMILIES := Family.RESTRICTIONS | Family.PAIRS | Family.COMMON_CONFLICTS
const EXTENDED_FAMILIES := ALL_FAMILIES | Family.TRIPLES | Family.CHAINS

static func analyze(regions: PackedInt32Array, advanced: bool = false) -> Dictionary:
	return analyze_with_families(regions, ALL_FAMILIES if advanced else 0)


static func analyze_with_families(regions: PackedInt32Array, families: int,
	conflict_graph: Array[PackedInt32Array] = []) -> Dictionary:
	return _analyze(regions, families, {}, conflict_graph)


## A stalled proof is an exact prefix only when added families have lower priority.
static func extend_stalled_proof(regions: PackedInt32Array, previous: Dictionary, prior: int, added: int,
	conflict_graph: Array[PackedInt32Array] = []) -> Dictionary:
	assert(previous.status == Status.STUCK and (prior & added) == 0 and prior < (added & -added))
	return _analyze(regions, prior | added, previous, conflict_graph)


static func _analyze(regions: PackedInt32Array, families: int, prefix: Dictionary,
	conflict_graph: Array[PackedInt32Array], stalled_rule := Callable(),
	initial_bears := PackedInt32Array(), initial_excluded := PackedInt32Array(),
	include_options := false) -> Dictionary:
	var report := {
		"status": Status.INVALID, "bears": PackedInt32Array(), "deductions": [],
		"rounds": 0, "total_steps": 0, "candidate_eliminations": 0, "forced_placements": 0,
		"longest_chain": 0, "highest_complexity": 0, "highest_technique": -1,
		"choices_per_round": [], "technique_counts": {},
	}
	if not Validator.is_valid_terrain(regions):
		return report
	var size := Validator.board_size(regions)
	var groups := _make_groups(regions, size)
	var candidates := PackedByteArray()
	candidates.resize(regions.size())
	candidates.fill(1)
	var depths := PackedInt32Array()
	depths.resize(regions.size())
	var bears := PackedInt32Array()
	for cell in initial_excluded:
		candidates[cell] = 0
	for bear in initial_bears:
		if not candidates[bear]:
			report.status = Status.CONTRADICTION
			return report
		bears.append(bear)
		for cell in candidates.size():
			if cell != bear and _conflict_mask(regions, size, bear, cell):
				candidates[cell] = 0
	if not prefix.is_empty():
		report = prefix.duplicate()
		report.deductions = prefix.deductions.duplicate()
		report.choices_per_round = prefix.choices_per_round.duplicate()
		report.technique_counts = prefix.technique_counts.duplicate()
		bears = prefix.bears.duplicate()
		for step in prefix.deductions:
			for cell in step.eliminated:
				candidates[cell] = 0
				depths[cell] = step.chain_depth

	while true:
		var remaining: Array[PackedInt32Array] = []
		var forced := {}
		for index in groups.size():
			var live := PackedInt32Array()
			for cell in groups[index]:
				if candidates[cell]:
					live.append(cell)
			if live.is_empty():
				report.status = Status.CONTRADICTION
				return report
			remaining.append(live)
			if live.size() == 1 and not bears.has(live[0]) and not forced.has(live[0]):
				forced[live[0]] = index
		if bears.size() == size:
			bears.sort()
			report.bears = bears
			report.status = Status.SOLVED
			return report

		var move: Dictionary
		var choices: int
		if not forced.is_empty():
			choices = forced.size()
			var bear: int = forced.keys()[0]
			var group: int = forced[bear]
			move = _placement(regions, candidates, size, bear, group, groups[group].size())
			if include_options and report.deductions.is_empty():
				report.opening_options = []
				for candidate: int in forced:
					var source: int = forced[candidate]
					report.opening_options.append(_placement(regions, candidates, size, candidate, source, groups[source].size()))
			bears.append(bear)
		else:
			var options: Array[Dictionary] = []
			if families != 0:
				options = _advanced_moves(remaining, regions, size, candidates, families, conflict_graph)
			if options.is_empty() and stalled_rule.is_valid():
				options = stalled_rule.call(remaining, regions, size, candidates)
			if options.is_empty():
				report.bears = bears
				report.status = Status.STUCK
				return report
			if include_options and report.deductions.is_empty():
				report.opening_options = options.duplicate(true)
			move = options[0]
			var distinct := {}
			for option in options:
				distinct[option.eliminated] = true
			choices = distinct.size()
		_record(report, move, choices, groups, candidates, depths)
	return report


static func _make_groups(regions: PackedInt32Array, size: int) -> Array[PackedInt32Array]:
	var groups: Array[PackedInt32Array] = []
	for index in size * 3:
		groups.append(PackedInt32Array())
	for cell in regions.size():
		@warning_ignore("integer_division")
		var row := cell / size
		var column := cell % size
		groups[regions[cell]].append(cell)
		groups[size + row].append(cell)
		groups[2 * size + column].append(cell)
	return groups


static func _placement(
	regions: PackedInt32Array, candidates: PackedByteArray, size: int,
	bear: int, group: int, original_size: int,
) -> Dictionary:
	var technique := Technique.COLUMN_SINGLE
	if group < size:
		technique = Technique.SINGLE_CELL_REGION if original_size == 1 else Technique.REGION_SINGLE
	elif group < 2 * size:
		technique = Technique.ROW_SINGLE
	var eliminated := PackedInt32Array()
	var reasons := {}
	for cell in regions.size():
		if cell == bear or not candidates[cell]:
			continue
		var conflicts := _conflict_mask(regions, size, bear, cell)
		if conflicts == 0:
			continue
		eliminated.append(cell)
		for reason in ELIMINATION_TECHNIQUES.size():
			if conflicts & (1 << reason):
				var key: int = ELIMINATION_TECHNIQUES[reason]
				if not reasons.has(key):
					reasons[key] = PackedInt32Array()
				reasons[key].append(cell)
	return {
		"technique": technique, "cell": bear, "cells": PackedInt32Array([bear]),
		"groups": [group], "confirmed": PackedInt32Array([bear]),
		"eliminated": eliminated, "eliminations_by_technique": reasons,
	}


static func _conflict_mask(regions: PackedInt32Array, size: int, first: int, second: int) -> int:
	@warning_ignore("integer_division")
	var row_gap := absi(first / size - second / size)
	var column_gap := absi(first % size - second % size)
	return (int(row_gap == 0)
		| (int(column_gap == 0) << 1)
		| (int(regions[first] == regions[second]) << 2)
		| (int(row_gap == 1 and column_gap == 1) << 3))


static func _advanced_moves(
	groups: Array[PackedInt32Array], regions: PackedInt32Array, size: int, candidates: PackedByteArray,
	families: int, conflict_graph: Array[PackedInt32Array],
) -> Array[Dictionary]:
	if families & Family.RESTRICTIONS:
		var restrictions := Patterns.restrictions(groups, 0, size, size, Technique.REGION_TO_ROW)
		restrictions.append_array(Patterns.restrictions(groups, 0, 2 * size, size, Technique.REGION_TO_COLUMN))
		restrictions.append_array(Patterns.restrictions(groups, size, 0, size, Technique.ROW_TO_REGION))
		restrictions.append_array(Patterns.restrictions(groups, 2 * size, 0, size, Technique.COLUMN_TO_REGION))
		if not restrictions.is_empty():
			return restrictions
	if families & Family.PAIRS:
		var pairs := Patterns.pairs(groups, size, Technique.CANDIDATE_PAIR)
		if not pairs.is_empty():
			return pairs
	if not (families & (Family.COMMON_CONFLICTS | Family.TRIPLES | Family.CHAINS)):
		return []
	if conflict_graph.is_empty():
		for first in regions.size():
			conflict_graph.append(PackedInt32Array())
			for second in first:
				if _conflict_mask(regions, size, first, second):
					conflict_graph[first].append(second)
					conflict_graph[second].append(first)
	var conflicts: Array[PackedInt32Array] = []
	for first in candidates.size():
		var related := PackedInt32Array()
		if candidates[first]:
			for second in conflict_graph[first]:
				if candidates[second]:
					related.append(second)
		conflicts.append(related)
	if families & Family.COMMON_CONFLICTS:
		var common := Patterns.common_conflicts(groups, candidates, conflicts, Technique.COMMON_CONFLICT)
		if not common.is_empty():
			return common
	if families & Family.TRIPLES:
		var triples := AdvancedPatterns.group_triples(groups, size, Technique.GROUP_TRIPLE)
		if not triples.is_empty():
			return triples
		var adjacency := AdvancedPatterns.adjacency_triples(groups, conflicts, size, Technique.ADJACENCY_TRIPLE)
		if not adjacency.is_empty():
			return adjacency
	if families & Family.CHAINS:
		return AdvancedPatterns.implication_chains(groups, conflicts, candidates, Technique.IMPLICATION_CHAIN)
	return []


static func _record(
	report: Dictionary, move: Dictionary, choices: int, groups: Array[PackedInt32Array],
	candidates: PackedByteArray, depths: PackedInt32Array,
) -> void:
	var technique: int = move.technique
	var complexity := 1
	match technique:
		Technique.REGION_TO_ROW, Technique.REGION_TO_COLUMN, Technique.ROW_TO_REGION, Technique.COLUMN_TO_REGION:
			complexity = 2
		Technique.CANDIDATE_PAIR:
			complexity = 3
		Technique.COMMON_CONFLICT:
			complexity = 4
		Technique.GROUP_TRIPLE, Technique.ADJACENCY_TRIPLE:
			complexity = 5
		Technique.IMPLICATION_CHAIN:
			complexity = 6
		Technique.REGION_HALL_SET, Technique.BOUNDED_CONTRADICTION:
			complexity = 7 # Audit-only techniques have no production difficulty classification.
	var depth := 1
	for group in move.groups:
		for cell in groups[group]:
			depth = maxi(depth, depths[cell] + 1)
	for cell in move.eliminated:
		candidates[cell] = 0
		depths[cell] = depth
	move["confirmed"] = move.get("confirmed", PackedInt32Array())
	move["eliminations_by_technique"] = move.get("eliminations_by_technique", {technique: move.eliminated})
	report.rounds += 1
	report.total_steps += 1
	report.candidate_eliminations += move.eliminated.size()
	report.forced_placements += move.confirmed.size()
	report.longest_chain = maxi(report.longest_chain, depth)
	if complexity > report.highest_complexity:
		report.highest_complexity = complexity
		report.highest_technique = technique
	report.technique_counts[technique] = report.technique_counts.get(technique, 0) + 1
	for reason in move.eliminations_by_technique:
		if reason != technique:
			report.technique_counts[reason] = report.technique_counts.get(reason, 0) + 1
	move["round"] = report.rounds
	move["chain_depth"] = depth
	move["complexity"] = complexity
	move["available_choices"] = choices
	report.choices_per_round.append(choices)
	report.deductions.append(move)

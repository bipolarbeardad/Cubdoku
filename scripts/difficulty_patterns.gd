extends RefCounted
## Candidate-only patterns over disjoint families of exactly-one groups.


static func restrictions(groups: Array[PackedInt32Array], source: int, target: int, size: int, technique: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for first in range(source, source + size):
		var involved := groups[first]
		if involved.size() < 2:
			continue
		for second in range(target, target + size):
			var destination := groups[second]
			if not _difference(involved, destination).is_empty():
				continue
			var eliminated := _difference(destination, involved)
			if not eliminated.is_empty():
				moves.append(_move(technique, [first], involved, eliminated, PackedInt32Array([second])))
	return moves


## Two groups confined to the same two groups of another family reserve both.
static func pairs(groups: Array[PackedInt32Array], size: int, technique: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for source in [0, size, 2 * size]:
		for target in [0, size, 2 * size]:
			if source == target:
				continue
			var masks := PackedInt32Array()
			for first in range(source, source + size):
				var mask := 0
				for second in size:
					for cell in groups[first]:
						if groups[target + second].has(cell):
							mask |= 1 << second
							break
				masks.append(mask)
			for first in size:
				if groups[source + first].size() < 2:
					continue
				var mask := masks[first]
				var targets := PackedInt32Array()
				for second in size:
					if mask & (1 << second):
						targets.append(target + second)
				if targets.size() != 2:
					continue
				for other in range(first + 1, size):
					if groups[source + other].size() < 2 or masks[other] != mask:
						continue
					var involved := groups[source + first] + groups[source + other]
					var eliminated := _difference(groups[targets[0]] + groups[targets[1]], involved)
					if not eliminated.is_empty():
						moves.append(_move(technique, [source + first, source + other], involved, eliminated, targets))
	return moves


## An outside candidate loses if it conflicts with every placement in a group.
static func common_conflicts(
	groups: Array[PackedInt32Array], candidates: PackedByteArray,
	conflicts: Array[PackedInt32Array], technique: int,
) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for group in groups.size():
		var involved := groups[group]
		if involved.size() < 2:
			continue
		var eliminated := PackedInt32Array()
		for cell in conflicts[involved[0]]:
			if not candidates[cell]:
				continue
			var conflicts_with_all := true
			for possible in involved:
				if not conflicts[possible].has(cell):
					conflicts_with_all = false
					break
			if conflicts_with_all:
				eliminated.append(cell)
		if not eliminated.is_empty():
			moves.append(_move(technique, [group], involved, eliminated))
	return moves


static func _difference(cells: PackedInt32Array, kept: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for cell in cells:
		if not kept.has(cell):
			result.append(cell)
	return result


static func _move(
	technique: int, sources: Array, involved: PackedInt32Array, eliminated: PackedInt32Array,
	targets := PackedInt32Array(),
) -> Dictionary:
	eliminated.sort()
	return {
		"technique": technique, "groups": sources, "target_groups": targets,
		"cells": involved, "eliminated": eliminated,
	}

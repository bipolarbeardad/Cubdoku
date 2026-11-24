extends RefCounted
## Bounded local proofs over visible candidates. No whole-board search.

static func group_triples(groups: Array[PackedInt32Array], size: int, technique: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for source in [0, size, 2 * size]:
		for target in [0, size, 2 * size]:
			if source == target:
				continue
			var membership := {}
			for index in size:
				for cell in groups[target + index]:
					membership[cell] = 1 << index
			var masks := PackedInt32Array()
			for index in size:
				var mask := 0
				for cell in groups[source + index]:
					mask |= membership[cell]
				masks.append(mask if groups[source + index].size() > 1 and _bit_count(mask) <= 3 else 0)
			for first in size:
				if masks[first] == 0:
					continue
				for second in range(first + 1, size):
					if masks[second] == 0:
						continue
					for third in range(second + 1, size):
						var union := masks[first] | masks[second] | masks[third]
						if masks[third] == 0 or _bit_count(union) != 3:
							continue
						var sources := [source + first, source + second, source + third]
						var involved := groups[sources[0]] + groups[sources[1]] + groups[sources[2]]
						var eliminated := PackedInt32Array()
						var targets := PackedInt32Array()
						for index in size:
							if union & (1 << index):
								targets.append(target + index)
								for cell in groups[target + index]:
									if not involved.has(cell):
										eliminated.append(cell)
						if not eliminated.is_empty():
							eliminated.sort()
							moves.append({"technique": technique, "groups": sources, "target_groups": targets,
								"cells": involved, "eliminated": eliminated})
	return moves


## Every live bear in any three disjoint obligations must have a compatible local triple.
static func adjacency_triples(
	groups: Array[PackedInt32Array], conflicts: Array[PackedInt32Array], size: int, technique: int,
) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for family in [0, size, 2 * size]:
		var small := PackedInt32Array()
		for group in range(family, family + size):
			if groups[group].size() >= 2 and groups[group].size() <= 4:
				small.append(group)
		for first in small.size():
			for second in range(first + 1, small.size()):
				for third in range(second + 1, small.size()):
					var sources := [small[first], small[second], small[third]]
					var allowed := {}
					var tuples: Array[Vector3i] = []
					for a in groups[sources[0]]:
						for b in groups[sources[1]]:
							if conflicts[a].has(b):
								continue
							for c in groups[sources[2]]:
								if not conflicts[a].has(c) and not conflicts[b].has(c):
									allowed[a] = true
									allowed[b] = true
									allowed[c] = true
									tuples.append(Vector3i(a, b, c))
					var involved := groups[sources[0]] + groups[sources[1]] + groups[sources[2]]
					var eliminated := PackedInt32Array()
					for cell in involved:
						if not allowed.has(cell):
							eliminated.append(cell)
					if not eliminated.is_empty():
						eliminated.sort()
						moves.append({"technique": technique, "groups": sources, "cells": involved,
							"eliminated": eliminated, "compatible_triples": tuples})
	return moves


## Graph literals encode cell*2 for a bear and cell*2+1 for no bear.
static func implication_chains(
	groups: Array[PackedInt32Array], conflicts: Array[PackedInt32Array],
	candidates: PackedByteArray, technique: int,
) -> Array[Dictionary]:
	var graph: Array[PackedInt32Array] = []
	var strong_groups := {}
	for cell in candidates.size():
		var weak := PackedInt32Array()
		for other in conflicts[cell]:
			weak.append(other * 2 + 1)
		graph.append(weak)
		graph.append(PackedInt32Array())
	for group in groups.size():
		if groups[group].size() == 2:
			var a := groups[group][0] * 2
			var b := groups[group][1] * 2
			graph[a + 1].append(b)
			graph[b + 1].append(a)
			strong_groups[Vector2i(a + 1, b)] = group
			strong_groups[Vector2i(b + 1, a)] = group
	var moves: Array[Dictionary] = []
	for cell in candidates.size():
		if not candidates[cell] or graph[cell * 2].is_empty():
			continue
		var path := _shortest_path(graph, cell * 2, cell * 2 + 1)
		if path.size() < 5:
			continue
		var used_groups: Array[int] = []
		var involved := PackedInt32Array()
		for index in path.size():
			var member := path[index] >> 1
			if not involved.has(member):
				involved.append(member)
			if index > 0:
				var edge := Vector2i(path[index - 1], path[index])
				if strong_groups.has(edge) and not used_groups.has(strong_groups[edge]):
					used_groups.append(strong_groups[edge])
		moves.append({"technique": technique, "groups": used_groups, "cells": involved,
			"eliminated": PackedInt32Array([cell]), "implication_path": path})
	return moves


static func _shortest_path(graph: Array[PackedInt32Array], start: int, end: int) -> PackedInt32Array:
	var parents := PackedInt32Array()
	parents.resize(graph.size())
	parents.fill(-1)
	parents[start] = start
	var queue := PackedInt32Array([start])
	var head := 0
	while head < queue.size() and parents[end] < 0:
		var current := queue[head]
		head += 1
		for next in graph[current]:
			if parents[next] < 0:
				parents[next] = current
				queue.append(next)
	var path := PackedInt32Array()
	if parents[end] >= 0:
		var current := end
		while current != start:
			path.append(current)
			current = parents[current]
		path.append(start)
		path.reverse()
	return path


static func _bit_count(value: int) -> int:
	var count := 0
	while value:
		value &= value - 1
		count += 1
	return count

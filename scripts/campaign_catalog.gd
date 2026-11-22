extends RefCounted
## Permanent campaign level metadata and fixed legacy puzzle fixtures.
## Cell arrays use zero-based indices in row-major order.

const _LEVEL_DIFFICULTIES := ["BASE", "BASE", "BASE", "BASE", "BASE", "BASE", "BASE", "BASE"]

# Each entry contains the permanent ID, size, difficulty, regions and solution.
const _PATHS := {
	1: ["cubdoku-0001", 4, "BASE", [0, 0, 0, 1, 0, 0, 0, 1, 2, 0, 0, 1, 2, 3, 3, 3], [1, 7, 8, 14]],
	2: ["cubdoku-0002", 4, "BASE", [1, 1, 0, 0, 1, 1, 1, 2, 1, 1, 2, 2, 3, 3, 2, 2], [2, 4, 11, 13]],
	3: ["cubdoku-0003", 4, "BASE", [0, 0, 3, 1, 2, 2, 3, 1, 2, 2, 3, 3, 3, 3, 3, 3], [1, 7, 8, 14]],
	4: ["cubdoku-0004", 4, "BASE", [1, 1, 0, 2, 1, 1, 1, 2, 1, 1, 2, 2, 3, 3, 3, 3], [2, 4, 11, 13]],
	5: ["cubdoku-0005", 4, "BASE", [0, 0, 0, 1, 2, 2, 0, 1, 2, 2, 3, 3, 2, 2, 3, 3], [1, 7, 8, 14]],
	6: ["cubdoku-0006", 4, "BASE", [1, 0, 0, 0, 1, 1, 3, 2, 3, 3, 3, 2, 3, 3, 3, 2], [2, 4, 11, 13]],
	7: ["cubdoku-0007", 4, "BASE", [1, 0, 1, 1, 1, 1, 1, 1, 2, 1, 3, 1, 2, 3, 3, 1], [1, 7, 8, 14]],
	8: ["cubdoku-0008", 4, "BASE", [1, 0, 0, 0, 1, 1, 0, 0, 3, 3, 2, 2, 3, 3, 3, 2], [2, 4, 11, 13]],
}


static func has_path(number: int) -> bool:
	return _PATHS.has(number)


static func level(number: int) -> Dictionary:
	if not has_level(number):
		return {}
	return {"id": "cubdoku-level-%04d" % number, "difficulty": _LEVEL_DIFFICULTIES[number - 1]}


static func has_level(number: int) -> bool:
	return number >= 1 and number <= _LEVEL_DIFFICULTIES.size()


static func load_path(number: int) -> Dictionary:
	if not has_path(number):
		return {}
	var entry: Array = _PATHS[number]
	return {
		"id": entry[0],
		"size": entry[1],
		"difficulty": entry[2],
		"regions": PackedInt32Array(entry[3]),
		"solution": PackedInt32Array(entry[4]),
	}

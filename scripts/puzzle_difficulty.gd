extends RefCounted
## Provisional structural limits. Only BASE has a logical classification.

const Validator := preload("res://scripts/puzzle_validator.gd")
const Analyzer := preload("res://scripts/difficulty_analyzer.gd")

const BASE := "BASE"
const THRESHOLDS := {
	BASE: {"sizes": [4, 5, 6, 7], "min_singletons": 1, "max_singletons": 1, "min_irregular_regions": 1},
	"EASY": {"sizes": [4, 5, 6, 7], "min_singletons": 0, "max_singletons": 1},
	"MEDIUM": {"sizes": [5, 6, 7], "min_singletons": 0, "max_singletons": 0},
	"HARD": {"sizes": [6, 7], "min_singletons": 0, "max_singletons": 0},
	"EXTRA HARD": {"sizes": [6, 7], "min_singletons": 0, "max_singletons": 0},
	"NIGHTMARES": {"sizes": [7], "min_singletons": 0, "max_singletons": 0},
}


static func supports(difficulty: String) -> bool:
	return difficulty == BASE


static func is_size_eligible(difficulty: String, size: int) -> bool:
	return Validator.supports_size(size) and THRESHOLDS.get(difficulty, {}).get("sizes", []).has(size)


static func matches(difficulty: String, regions: PackedInt32Array) -> bool:
	if not supports(difficulty) or not Validator.is_valid_terrain(regions):
		return false
	var size := Validator.board_size(regions)
	if not is_size_eligible(difficulty, size):
		return false
	var thresholds: Dictionary = THRESHOLDS[difficulty]
	var counts := PackedInt32Array()
	counts.resize(size)
	var bounds: Array[Rect2i] = []
	bounds.resize(size)
	for index in regions.size():
		var region := regions[index]
		@warning_ignore("integer_division")
		var cell := Rect2i(Vector2i(index % size, index / size), Vector2i.ONE)
		bounds[region] = cell if counts[region] == 0 else bounds[region].merge(cell)
		counts[region] += 1
	var irregular := 0
	for region in size:
		irregular += int(counts[region] != bounds[region].get_area())
	var singletons := counts.count(1)
	return (
		singletons >= thresholds.min_singletons and singletons <= thresholds.max_singletons
		and irregular >= thresholds.min_irregular_regions
		and Analyzer.analyze(regions, false).status == Analyzer.Status.SOLVED
	)

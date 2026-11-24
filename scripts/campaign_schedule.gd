extends RefCounted
## Deterministic allocation for the planned campaign, independent of saved campaigns.

const STAGE_COUNT := 10000
const SECTION_SIZE := 50
const INTRO_SIZES := [4, 4, 5, 6, 7]
const COUNTS := {"EASY": 7, "MEDIUM": 5, "HARD": 4, "EXTRA HARD": 2, "NIGHTMARES": 2}
const SIZES := {
	"BASE": Vector2i(4, 7), "EASY": Vector2i(5, 7), "MEDIUM": Vector2i(5, 7),
	"HARD": Vector2i(6, 8), "EXTRA HARD": Vector2i(7, 9), "NIGHTMARES": Vector2i(8, 10),
}
const OPENING_BLOCK := [
	"EASY", "EASY", "MEDIUM", "HARD", "EASY", "MEDIUM", "EXTRA HARD", "EASY", "MEDIUM", "HARD",
	"NIGHTMARES", "EASY", "MEDIUM", "HARD", "EASY", "EXTRA HARD", "MEDIUM", "HARD", "EASY", "NIGHTMARES",
]
const LATER_BLOCK := [
	"EASY", "MEDIUM", "EASY", "HARD", "NIGHTMARES", "EASY", "MEDIUM", "HARD", "EASY", "EXTRA HARD",
	"MEDIUM", "EASY", "HARD", "NIGHTMARES", "MEDIUM", "EASY", "EXTRA HARD", "HARD", "EASY", "MEDIUM",
]

var _seed: int
var _blocks: Array[Array] = []


func _init(opening_block: Array = OPENING_BLOCK, schedule_seed: int = 2601) -> void:
	_seed = schedule_seed
	_blocks.append(opening_block.duplicate() if valid_opening(opening_block) else OPENING_BLOCK.duplicate())


static func valid_opening(block: Array) -> bool:
	if block.size() != 20:
		return false
	for difficulty: String in COUNTS:
		if block.count(difficulty) != COUNTS[difficulty]:
			return false
	return true


func request(stage: int) -> Dictionary:
	if stage < 1 or stage > STAGE_COUNT:
		return {}
	if stage <= INTRO_SIZES.size():
		return {"stage": stage, "difficulty": "BASE", "size": INTRO_SIZES[stage - 1], "locked_bear": stage == 1}
	var offset := stage - INTRO_SIZES.size() - 1
	@warning_ignore("integer_division")
	var block_index := offset / OPENING_BLOCK.size()
	while _blocks.size() <= block_index:
		_blocks.append(_next_block(_blocks.size(), _blocks.back().back()))
	var difficulty: String = _blocks[block_index][offset % OPENING_BLOCK.size()]
	var bounds: Vector2i = SIZES[difficulty]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + stage * 104729
	return {"stage": stage, "difficulty": difficulty, "size": rng.randi_range(bounds.x, bounds.y), "locked_bear": false}


func _next_block(index: int, previous: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + index * 65537
	var start := rng.randi_range(0, LATER_BLOCK.size() - 1)
	while LATER_BLOCK[start] == previous:
		start = (start + 1) % LATER_BLOCK.size()
	var block := LATER_BLOCK.slice(start) + LATER_BLOCK.slice(0, start)
	for attempt in block.size() * 2:
		var first := rng.randi_range(1, block.size() - 1)
		var second := rng.randi_range(1, block.size() - 1)
		var saved: String = block[first]
		block[first] = block[second]
		block[second] = saved
		if _has_neighbors(block, first) or _has_neighbors(block, second):
			block[second] = block[first]
			block[first] = saved
	return block


func _has_neighbors(block: Array, index: int) -> bool:
	return (block[index] == block[index - 1]
		or (index + 1 < block.size() and block[index] == block[index + 1]))

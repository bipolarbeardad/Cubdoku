extends RefCounted
## Versioned local profile storage. Only replace the live file after a complete write.

const VERSION := 1
const DEFAULT_PATH := "user://campaign.save"


static func new_profile() -> Dictionary:
	return {
		"version": VERSION,
		"current_level": 1,
		"assignments": {},
		"statistics": {
			"completed_total": 0,
			"completed_by_difficulty": {},
			"fastest_completion_seconds": null,
			"highest_level_reached": 0,
		},
	}


static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return new_profile()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = file.get_var()
	if not data is Dictionary or data.get("version") != VERSION:
		return {}
	if not data.get("current_level") is int or not data.get("assignments") is Dictionary:
		return {}
	var stats: Variant = data.get("statistics")
	if (
		not stats is Dictionary
		or not stats.get("completed_total") is int
		or not stats.get("completed_by_difficulty") is Dictionary
		or not stats.has("fastest_completion_seconds")
		or not stats.get("highest_level_reached") is int
	):
		return {}
	return data


static func write(path: String, data: Dictionary) -> bool:
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(data)
	file.flush()
	var written := file.get_error() == OK
	file.close()
	return written and DirAccess.rename_absolute(temporary_path, path) == OK

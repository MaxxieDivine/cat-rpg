extends RefCounted
## Reads JSON files from data/. Returns an empty Dictionary (and warns) on error.
## preload() this script; no class_name (see CLAUDE.md).


static func load_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("json_data: missing file %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("json_data: %s is not a JSON object" % path)
	return {}

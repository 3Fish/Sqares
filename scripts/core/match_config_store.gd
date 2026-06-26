extends RefCounted
class_name MatchConfigStore

## Persists saved match configurations (#135) to and from `user://configs/` as
## JSON files, one config per file.
##
## A saved config is a reusable match *template* — the game mode plus the general
## and mode-specific options (see `MatchConfig.to_dict` for the schema). The host
## saves a preferred setup from the match-setup screen and reloads it later; the
## file initialises the game locally and is deliberately NOT shared between
## players (maintainer A4). This is the on-disk side of save/load; the schema and
## load-time normalisation live in `MatchConfig`.
##
## A config is keyed by its host-chosen display name. The file is named by a slug
## derived from that name (so two names that slugify the same collide on disk,
## which is exactly the overwrite case A3 prompts for), and the display name is
## stored inside the JSON so it round-trips. All methods are static — the
## filesystem is the single source of truth (mirrors `ArenaStore`).

const DIR: String = "user://configs/"
const EXT: String = ".json"


## Ensure the storage directory exists. Returns OK or a DirAccess error code.
static func ensure_dir() -> Error:
	if DirAccess.dir_exists_absolute(DIR):
		return OK
	return DirAccess.make_dir_recursive_absolute(DIR)


## Normalise a display name into a safe file-name slug: lower-case, alphanumeric
## plus `-`/`_`, with everything else collapsed to `_` (mirrors
## `ArenaStore.sanitize_id`).
static func sanitize_name(name: String) -> String:
	var out := ""
	for c in name.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-" or c == "_":
			out += c
		else:
			out += "_"
	return out


## Absolute `user://` path for a config display name.
static func path_for(name: String) -> String:
	return DIR + sanitize_name(name) + EXT


## True if a config file already exists for `name` (the A3 overwrite check).
static func exists(name: String) -> bool:
	var slug := sanitize_name(name)
	if slug.is_empty():
		return false
	return FileAccess.file_exists(path_for(name))


## Write a config under the given display name. `data` is the serialised template
## (`MatchConfig.to_dict`); the display name is stored alongside it so listing and
## loading can present it verbatim. Rejects a blank/slug-empty name. Returns OK or
## an error code.
static func save(name: String, data: Dictionary) -> Error:
	var slug := sanitize_name(name)
	if slug.is_empty():
		push_error("MatchConfigStore: cannot save a config with an empty name.")
		return ERR_INVALID_PARAMETER

	var dir_err := ensure_dir()
	if dir_err != OK:
		push_error("MatchConfigStore: could not create '%s' (error %d)." % [DIR, dir_err])
		return dir_err

	var record := data.duplicate(true)
	record["name"] = name.strip_edges()

	var path := path_for(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var open_err := FileAccess.get_open_error()
		push_error("MatchConfigStore: could not open '%s' for writing (error %d)." % [path, open_err])
		return open_err

	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	return OK


## Load a config by display name. Returns an empty dictionary if the file is
## missing or does not parse to a JSON object (so callers can treat `{}` as "no
## config" without a null check); the returned dict carries the stored `name`.
static func load_config(name: String) -> Dictionary:
	var path := path_for(name)
	if not FileAccess.file_exists(path):
		push_warning("MatchConfigStore: no config at '%s'." % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MatchConfigStore: could not open '%s' for reading (error %d)." % [path, FileAccess.get_open_error()])
		return {}

	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("MatchConfigStore: '%s' is not a JSON object." % path)
		return {}
	return parsed


## Delete a config file. Returns OK, or ERR_DOES_NOT_EXIST if there was nothing to
## delete.
static func delete(name: String) -> Error:
	var path := path_for(name)
	if not FileAccess.file_exists(path):
		return ERR_DOES_NOT_EXIST
	return DirAccess.remove_absolute(path)


## The display names of all stored configs, sorted. Reads each file's stored
## `name` (falling back to the slug for a file that lacks one), so the host sees
## the names they typed rather than the on-disk slugs.
static func list_names() -> Array[String]:
	var names: Array[String] = []
	if not DirAccess.dir_exists_absolute(DIR):
		return names
	for file_name in DirAccess.get_files_at(DIR):
		if not file_name.ends_with(EXT):
			continue
		var slug := file_name.substr(0, file_name.length() - EXT.length())
		var loaded := load_config(slug)
		var display := String(loaded.get("name", slug)) if not loaded.is_empty() else slug
		names.append(display)
	names.sort()
	return names

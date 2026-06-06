extends RefCounted
class_name ArenaStore

## Persists `ArenaData` to and from `user://arenas/` as JSON files.
##
## One arena per file, named `<id>.json`. This is the on-disk side of the arena
## editor: the editor (#34/#35) saves through here, the load path (#33) reads
## custom arenas back and feeds them to `LevelRegistry`.
##
## All methods are static — there is no per-instance state, the filesystem is the
## single source of truth.

const DIR: String = "user://arenas/"
const EXT: String = ".json"


## Ensure the storage directory exists. Returns OK or a DirAccess error code.
static func ensure_dir() -> Error:
	if DirAccess.dir_exists_absolute(DIR):
		return OK
	return DirAccess.make_dir_recursive_absolute(DIR)


## Absolute `user://` path for a given arena id.
static func path_for(id: String) -> String:
	return DIR + sanitize_id(id) + EXT


## Normalise an id into a safe file-name slug: lower-case, alphanumeric plus
## `-`/`_`, with everything else collapsed to `_`.
static func sanitize_id(id: String) -> String:
	var out := ""
	for c in id.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-" or c == "_":
			out += c
		else:
			out += "_"
	return out


## True if an arena file exists for `id`.
static func exists(id: String) -> bool:
	return FileAccess.file_exists(path_for(id))


## Write an arena to disk. Falls back to `display_name` (or "arena") for the file
## name when `id` is empty, and back-fills `arena.id` so the in-memory object
## matches what was saved. Returns OK or an error code.
static func save(arena: ArenaData) -> Error:
	if arena == null:
		push_error("ArenaStore: cannot save a null arena.")
		return ERR_INVALID_PARAMETER

	var slug := sanitize_id(arena.id)
	if slug.is_empty():
		slug = sanitize_id(arena.display_name)
	if slug.is_empty():
		slug = "arena"
	arena.id = slug

	var dir_err := ensure_dir()
	if dir_err != OK:
		push_error("ArenaStore: could not create '%s' (error %d)." % [DIR, dir_err])
		return dir_err

	var path := path_for(slug)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var open_err := FileAccess.get_open_error()
		push_error("ArenaStore: could not open '%s' for writing (error %d)." % [path, open_err])
		return open_err

	file.store_string(arena.to_json())
	file.close()
	return OK


## Load an arena by id. Returns null if missing or unparseable.
static func load_arena(id: String) -> ArenaData:
	var path := path_for(id)
	if not FileAccess.file_exists(path):
		push_warning("ArenaStore: no arena at '%s'." % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ArenaStore: could not open '%s' for reading (error %d)." % [path, FileAccess.get_open_error()])
		return null

	var text := file.get_as_text()
	file.close()
	return ArenaData.from_json(text)


## Delete an arena file. Returns OK, or ERR_DOES_NOT_EXIST if there was nothing
## to delete.
static func delete(id: String) -> Error:
	var path := path_for(id)
	if not FileAccess.file_exists(path):
		return ERR_DOES_NOT_EXIST
	return DirAccess.remove_absolute(path)


## List the ids of all stored arenas (file names without the extension), sorted.
static func list_ids() -> Array[String]:
	var ids: Array[String] = []
	if not DirAccess.dir_exists_absolute(DIR):
		return ids
	for name in DirAccess.get_files_at(DIR):
		if name.ends_with(EXT):
			ids.append(name.substr(0, name.length() - EXT.length()))
	ids.sort()
	return ids


## Load every stored arena. Files that fail to parse are skipped (with a warning).
static func load_all() -> Array[ArenaData]:
	var arenas: Array[ArenaData] = []
	for id in list_ids():
		var arena := load_arena(id)
		if arena != null:
			arenas.append(arena)
	return arenas

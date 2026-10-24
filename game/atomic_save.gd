extends RefCounted
## Checked local atomic replacement. Failed steps never report a successful save.
var path: String

func _init(destination: String = "user://neighborhoods_v1.json") -> void:
	path = destination

func write(data: Dictionary) -> bool:
	var temporary := path+".tmp"
	var payload := JSON.stringify(data)
	var file := _open(temporary)
	if file == null: return false
	var error := _write_payload(file,payload)
	file.close()
	if error != OK or _read(temporary) != payload: return false
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) and _copy(absolute,absolute+".bak") != OK: return false
	if _rename(ProjectSettings.globalize_path(temporary),absolute) != OK: return false
	return _read(path) == payload

# Small overridable filesystem boundaries allow isolated deterministic fault
# tests without changing permissions, global settings or genuine profile paths.
func _open(temporary: String) -> FileAccess:
	return FileAccess.open(temporary,FileAccess.WRITE)

func _write_payload(file: FileAccess,payload: String) -> Error:
	file.store_string(payload)
	file.flush()
	return file.get_error()

func _read(source: String) -> String:
	return FileAccess.get_file_as_string(source)

func _copy(source: String,destination: String) -> Error:
	return DirAccess.copy_absolute(source,destination)

func _rename(source: String,destination: String) -> Error:
	return DirAccess.rename_absolute(source,destination)

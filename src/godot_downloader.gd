class_name GodotDownloader
extends Node

signal started(release: GodotRelease, build: GodotDownload)
signal progress_changed(downloaded_bytes: int, total_bytes: int)
signal finished(release: GodotRelease, install_path: String)
signal failed(message: String)
signal launch_failed(release: GodotRelease, message: String)

const ROOT_DIR := "user://godot"
const MARKER_FILE := ".installed"
const ENGINE_DIR := "engine"
const EXTRACTORS := [
	["bsdtar", ["-xf"], "-C"],
	["unzip", ["-o", "-q"], "-d"],
	["tar", ["-xf"], "-C"],
]
const NOT_A_BINARY := [".pck", ".txt", ".zip", ".console.exe"]

var _http: HTTPRequest
var _release: GodotRelease = null
var _build: GodotDownload = null
var _archive_path: String = ""
var _queued: Array = []


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = false
	_http.timeout = 60.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


static func install_dir(release: GodotRelease) -> String:
	return ROOT_DIR.path_join(release.slug())


static func engine_dir(release: GodotRelease) -> String:
	return install_dir(release).path_join(ENGINE_DIR)


static func is_installed(release: GodotRelease) -> bool:
	return FileAccess.file_exists(install_dir(release).path_join(MARKER_FILE))


static func forget(release: GodotRelease) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(install_dir(release).path_join(MARKER_FILE)))


static func archive_name(release: GodotRelease, build: GodotDownload) -> String:
	var file_slug := build.file_slug if not build.file_slug.is_empty() else build.platform
	if not file_slug.ends_with(".zip"):
		file_slug += ".zip"
	return "Godot_v%s_%s" % [release.slug(), file_slug]


static func binary_name(release: GodotRelease, build: GodotDownload) -> String:
	var file_slug := build.file_slug
	if file_slug.ends_with(".zip"):
		file_slug = file_slug.substr(0, file_slug.length() - 4)
	if file_slug.is_empty():
		return ""
	return "Godot_v%s_%s" % [release.slug(), file_slug]


static func read_marker(release: GodotRelease) -> Dictionary:
	var data: Dictionary = {}
	var file := FileAccess.open(install_dir(release).path_join(MARKER_FILE), FileAccess.READ)
	if file == null:
		return data

	while not file.eof_reached():
		var line := file.get_line()
		var assign := line.find("=")
		if assign != -1:
			data[line.substr(0, assign)] = line.substr(assign + 1)
	file.close()
	return data


static func find_binary(release: GodotRelease) -> String:
	var dir_path := engine_dir(release)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""

	if OS.get_name() == "macOS":
		for bundle in dir.get_directories():
			if bundle.ends_with(".app"):
				return dir_path.path_join(bundle)

	var expected: String = read_marker(release).get("binary", "")
	if not expected.is_empty() and FileAccess.file_exists(dir_path.path_join(expected)):
		return dir_path.path_join(expected)

	for file_name in dir.get_files():
		if not file_name.begins_with("Godot_v%s" % release.slug()):
			continue
		var skip := false
		for suffix in NOT_A_BINARY:
			if file_name.ends_with(suffix):
				skip = true
		if not skip:
			return dir_path.path_join(file_name)

	return ""


func is_busy() -> bool:
	return _release != null


func current_platform() -> String:
	match OS.get_name():
		"Linux":
			if OS.has_feature("x86_64"):
				return "linux.64"
			if OS.has_feature("x86_32"):
				return "linux.32"
			if OS.has_feature("arm64"):
				return "linux.arm64"
			if OS.has_feature("arm32"):
				return "linux.arm32"
		"Windows":
			if OS.has_feature("x86_64"):
				return "windows.64"
			if OS.has_feature("x86_32"):
				return "windows.32"
			if OS.has_feature("arm64"):
				return "windows.arm64"
		"macOS":
			return "macos.universal"
		"Android":
			return "android.apk"
		"Web":
			return "web"
	return ""


func pick_build(release: GodotRelease) -> GodotDownload:
	if release == null or OS.has_feature("web"):
		return null

	var preferred := current_platform()
	if preferred.is_empty():
		return null

	for build in release.downloads:
		if not build.is_dotnet and build.platform == preferred:
			return build

	return null


func download(release: GodotRelease, build: GodotDownload) -> void:
	if build == null:
		failed.emit("No build for this system")
		return

	if is_busy() or _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_queued = [release, build]
		return

	_start(release, build)


func launch(release: GodotRelease) -> void:
	var binary := find_binary(release)
	if binary.is_empty():
		launch_failed.emit(release, "Engine binary not found in %s" % engine_dir(release))
		return

	if binary.ends_with(".app"):
		OS.shell_open(binary)
		return

	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", ProjectSettings.globalize_path(binary)], [], false)

	var pid := OS.create_process(ProjectSettings.globalize_path(binary), PackedStringArray(), false)
	if pid < 0:
		launch_failed.emit(release, "Could not start the editor")


func _process(_delta: float) -> void:
	if _release != null:
		var total := _http.get_body_size()
		progress_changed.emit(_http.get_downloaded_bytes(), max(total, 0))
	elif not _queued.is_empty() and _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		var release: GodotRelease = _queued[0]
		var build: GodotDownload = _queued[1]
		_queued.clear()
		_start(release, build)


func _start(release: GodotRelease, build: GodotDownload) -> void:
	var dir := install_dir(release)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		failed.emit("Cannot create %s" % dir)
		return

	_release = release
	_build = build
	_archive_path = dir.path_join(archive_name(release, build))

	if FileAccess.file_exists(_archive_path):
		_unpack(release, build, _archive_path)
		return

	_clear_archive()
	_http.download_file = _archive_path
	var err := _http.request(build.url, PackedStringArray(["User-Agent: " + GodotArchiveClient.USER_AGENT]))
	if err != OK:
		_reset()
		failed.emit("Could not start download: %s" % error_string(err))
		return

	started.emit(release, build)


func _on_request_completed(result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var release := _release
	var build := _build
	var archive := _archive_path

	if release == null:
		return

	_reset()

	if result != HTTPRequest.RESULT_SUCCESS:
		_remove_file(archive)
		failed.emit("Download failed: %s" % error_string(result))
		return

	_unpack(release, build, archive)


func _unpack(release: GodotRelease, build: GodotDownload, archive: String) -> void:
	var report := _extract(release, build, archive)
	if report.is_empty():
		_remove_file(archive)
	_reset()
	if report.is_empty():
		finished.emit(release, install_dir(release))
	else:
		failed.emit(report)


func _extract(release: GodotRelease, build: GodotDownload, archive: String) -> String:
	var engine_path := ProjectSettings.globalize_path(engine_dir(release))
	DirAccess.make_dir_recursive_absolute(engine_path)

	var archive_path := ProjectSettings.globalize_path(archive)
	var report := ""

	for candidate in EXTRACTORS:
		var program: String = candidate[0]
		var args := PackedStringArray(candidate[1])
		args.append(candidate[2])
		args.append(engine_path)
		args.append(archive_path)

		var output: Array = []
		if OS.execute(program, args, output, true) == 0 and _has_files(engine_path):
			_write_marker(release, build)
			return ""

		if report.is_empty():
			report = "%s failed: %s" % [program, str(output)]

	return "%s (archive kept at %s)" % [report, archive]


func _has_files(dir_path: String) -> bool:
	var dir := DirAccess.open(dir_path)
	return dir != null and (dir.get_files().size() > 0 or dir.get_directories().size() > 0)


func _write_marker(release: GodotRelease, build: GodotDownload) -> void:
	var marker := FileAccess.open(install_dir(release).path_join(MARKER_FILE), FileAccess.WRITE)
	if marker == null:
		return
	marker.store_line("version=%s" % release.slug())
	marker.store_line("platform=%s" % build.platform)
	marker.store_line("binary=%s" % binary_name(release, build))
	marker.store_line("date=%s" % release.date)
	marker.store_line("installed_at=%s" % Time.get_datetime_string_from_system())
	marker.close()


func _clear_archive() -> void:
	if not _archive_path.is_empty():
		_remove_file(_archive_path)


func _remove_file(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _reset() -> void:
	_release = null
	_build = null
	_archive_path = ""
	_http.download_file = ""

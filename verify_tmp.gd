extends SceneTree

var _scene: Control
var _step := 0
var _timer := 0.0


func _initialize() -> void:
	_scene = load("res://main.tscn").instantiate()
	root.add_child(_scene)


func _process(delta: float) -> bool:
	_timer += delta

	if _step == 0 and _timer > 6.0:
		_step = 1
		_timer = 0.0
		print("--- selected=", _scene._selected.slug(), " installed=", GodotDownloader.is_installed(_scene._selected))
		_scene._on_download_pressed()

	elif _step == 1 and _timer > 50.0:
		_step = 2
		_timer = 0.0
		var release: GodotRelease = _scene._selected
		print("--- installed=", GodotDownloader.is_installed(release))
		print("--- marker: ", GodotDownloader.read_marker(release))
		print("--- binary Launch would start: ", GodotDownloader.find_binary(release))
		print("--- version dir:")
		_dump(GodotDownloader.install_dir(release))
		print("--- engine dir:")
		_dump(GodotDownloader.engine_dir(release))
		print("--- buttons: launch.disabled=", _scene._launch_button.disabled,
			" download='", _scene._download_button.text, "'/disabled=", _scene._download_button.disabled,
			" delete.disabled=", _scene._delete_button.disabled)
		quit()

	return false


func _dump(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		print("      (missing) ", path)
		return
	print("      ", path, "/")
	for file_name in dir.get_files():
		print("         file: ", file_name)
	for sub in dir.get_directories():
		print("         dir : ", sub)

extends Control

const PREFIX_FILTERS := ["", "stable", "rc", "beta", "dev", "alpha"]

@onready var _status: Label = %StatusLabel
@onready var _search: LineEdit = %Search
@onready var _filter: OptionButton = %PrefixFilter
@onready var _refresh_button: Button = %Refresh
@onready var _list: ItemList = %ReleaseList
@onready var _version_label: Label = %VersionLabel
@onready var _prefix_label: Label = %PrefixLabel
@onready var _date_label: Label = %DateLabel
@onready var _launch_button: Button = %LaunchButton
@onready var _download_button: Button = %DownloadButton
@onready var _delete_button: Button = %DeleteButton
@onready var _page_button: Button = %ReleasePageButton
@onready var _progress: ProgressBar = %Progress
@onready var _links: ItemList = %LinksList
@onready var _delete_confirm: ConfirmationDialog = %DeleteConfirm

var _client: GodotArchiveClient
var _downloader: GodotDownloader
var _releases: Array[GodotRelease] = []
var _selected: GodotRelease = null
var _delete_pending: GodotRelease = null
var _rows: Array = []
var _link_urls: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_client = GodotArchiveClient.new()
	add_child(_client)
	_client.archive_loaded.connect(_on_archive_loaded)
	_client.downloads_loaded.connect(_on_downloads_loaded)
	_client.failed.connect(_on_client_failed)

	_downloader = GodotDownloader.new()
	add_child(_downloader)
	_downloader.started.connect(_on_download_started)
	_downloader.progress_changed.connect(_on_download_progress)
	_downloader.finished.connect(_on_download_finished)
	_downloader.failed.connect(_on_download_failed)
	_downloader.launch_failed.connect(_on_launch_failed)

	_list.item_selected.connect(_on_list_selected)
	_links.item_activated.connect(_on_link_activated)
	_refresh_button.pressed.connect(refresh)
	_search.text_changed.connect(_apply_filter)
	_filter.item_selected.connect(_apply_filter)
	_launch_button.pressed.connect(_on_launch_pressed)
	_download_button.pressed.connect(_on_download_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)
	_delete_confirm.confirmed.connect(_on_delete_confirmed)
	_page_button.pressed.connect(_on_page_pressed)

	refresh()


func refresh() -> void:
	_status.text = "Loading..."
	_client.fetch_archive()


func _on_archive_loaded(releases: Array[GodotRelease]) -> void:
	_releases = releases
	_apply_filter()

	for index in _rows.size():
		if _rows[index] != null:
			_list.select(index)
			_select_release(_rows[index])
			break


func _apply_filter(_arg: Variant = null) -> void:
	var query := _search.text.strip_edges().to_lower()
	var prefix_filter: String = PREFIX_FILTERS[_filter.selected] if _filter.selected >= 0 else ""

	var installed: Array[GodotRelease] = []
	var available: Array[GodotRelease] = []
	for release in _releases:
		if not _matches(release, prefix_filter, query):
			continue
		if GodotDownloader.is_installed(release):
			installed.append(release)
		else:
			available.append(release)

	_rows.clear()
	_list.clear()

	_add_header("Downloaded (%d)" % installed.size())
	for release in installed:
		_add_row(release)
	_add_header("Not downloaded (%d)" % available.size())
	for release in available:
		_add_row(release)

	_status.text = "%d shown, %d downloaded, %d total" % [
		installed.size() + available.size(), installed.size(), _releases.size()
	]

	if installed.size() + available.size() == 0:
		_clear_details()


func _matches(release: GodotRelease, prefix_filter: String, query: String) -> bool:
	if prefix_filter != "" and not release.prefix.begins_with(prefix_filter):
		return false
	return query == "" or release.slug().to_lower().contains(query)


func _add_header(text: String) -> void:
	_rows.append(null)
	_list.add_item(text)
	_list.set_item_selectable(_rows.size() - 1, false)


func _add_row(release: GodotRelease) -> void:
	_rows.append(release)
	_list.add_item("  %s    %s    %s" % [release.version, release.prefix, release.date])
	_list.set_item_tooltip(_rows.size() - 1, release.page_url)


func _on_list_selected(index: int) -> void:
	if index >= 0 and index < _rows.size() and _rows[index] != null:
		_select_release(_rows[index])


func _select_release(release: GodotRelease) -> void:
	if release == _selected:
		return
	_selected = release

	_version_label.text = release.version
	_prefix_label.text = release.prefix
	_date_label.text = "Released %s" % release.date
	_fill_links()

	if release.downloads_loaded:
		_update_buttons(release)
	else:
		_download_button.disabled = true
		_client.fetch_downloads(release)


func _on_downloads_loaded(release: GodotRelease) -> void:
	if release != _selected:
		return
	_fill_links()
	_update_buttons(release)


func _fill_links() -> void:
	_link_urls = PackedStringArray()
	_links.clear()

	for build in _selected.downloads:
		var index := _links.item_count
		_link_urls.append(build.url)
		_links.add_item("  %s    %s%s" % [build.platform, build.title, "  [.NET]" if build.is_dotnet else ""])
		_links.set_item_tooltip(index, build.url)


func _update_buttons(release: GodotRelease) -> void:
	var installed := GodotDownloader.is_installed(release)
	var build := _downloader.pick_build(release)

	_launch_button.disabled = not installed
	_delete_button.disabled = not installed
	_download_button.text = "Downloaded" if installed else "Download"
	_download_button.disabled = installed or build == null


func _clear_details() -> void:
	_selected = null
	_version_label.text = "-"
	_prefix_label.text = ""
	_date_label.text = ""
	_links.clear()
	_link_urls = PackedStringArray()
	_launch_button.disabled = true
	_download_button.disabled = true
	_delete_button.disabled = true


func _on_launch_pressed() -> void:
	if _selected != null and GodotDownloader.is_installed(_selected):
		_downloader.launch(_selected)
		get_tree().quit(0)


func _on_launch_failed(_release: GodotRelease, message: String) -> void:
	_status.text = message
	push_warning(message)


func _on_download_pressed() -> void:
	if _selected == null:
		return
	var build := _downloader.pick_build(_selected)
	if build == null:
		return
	_download_button.disabled = true
	_delete_button.disabled = true
	_progress.value = 0.0
	_progress.visible = true
	_downloader.download(_selected, build)


func _on_delete_pressed() -> void:
	if _selected == null or not GodotDownloader.is_installed(_selected):
		return

	_delete_pending = _selected
	_delete_confirm.dialog_text = "Delete Godot %s (%s)?\n\n%s" % [
		_selected.version, _selected.prefix, GodotDownloader.install_dir(_selected)
	]
	_delete_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	if _delete_pending == null:
		return

	var release := _delete_pending
	_delete_pending = null

	var path := GodotDownloader.install_dir(release)
	GodotDownloader.forget(release)
	_remove_tree(path)

	_delete_button.disabled = true
	release.downloads.clear()
	release.downloads_loaded = false
	_selected = null

	_apply_filter()
	_select_release(release)
	_status.text = "Deleted %s" % path


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var entry_path := path.path_join(entry)
			if dir.current_is_dir():
				_remove_tree(entry_path)
			else:
				dir.remove(entry_path)
		entry = dir.get_next()
	dir.list_dir_end()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _on_download_started(release: GodotRelease, build: GodotDownload) -> void:
	_status.text = "Downloading %s %s" % [release.slug(), build.title]


func _on_download_progress(downloaded_bytes: int, total_bytes: int) -> void:
	if total_bytes > 0:
		_progress.max_value = total_bytes
		_progress.value = downloaded_bytes
		_status.text = "Downloading %d MB of %d MB" % [downloaded_bytes / 1048576, total_bytes / 1048576]
	else:
		_progress.value = 0.0


func _on_download_finished(release: GodotRelease, install_path: String) -> void:
	_progress.visible = false
	_download_button.disabled = true
	_status.text = "Installed to %s" % install_path
	_selected = null
	_apply_filter()
	_select_release(release)


func _on_client_failed(message: String) -> void:
	_status.text = message
	push_warning(message)


func _on_download_failed(message: String) -> void:
	_progress.visible = false
	_status.text = message
	push_warning(message)
	if _selected != null and _selected.downloads_loaded:
		_update_buttons(_selected)


func _on_page_pressed() -> void:
	if _selected != null:
		OS.shell_open(_selected.page_url)


func _on_link_activated(index: int) -> void:
	if index >= 0 and index < _link_urls.size():
		OS.shell_open(_link_urls[index])


func _debug_print_table(releases: Array[GodotRelease]) -> void:
	print("%-9s %-8s %-20s %s" % ["VERSION", "PREFIX", "DATE", "URL"])
	for release in releases:
		print("%-9s %-8s %-20s %s" % [release.version, release.prefix, release.date, release.page_url])

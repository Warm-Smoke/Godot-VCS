class_name GodotArchiveClient
extends Node

signal archive_loaded(releases: Array[GodotRelease])
signal downloads_loaded(release: GodotRelease)
signal failed(message: String)

const ARCHIVE_URL := "https://godotengine.org/download/archive/"
const USER_AGENT := "Mozilla/5.0 (compatible; GodotVSC/1.0)"

var releases: Array[GodotRelease] = []

var _http: HTTPRequest
var _pending: GodotRelease = null
var _queued: Array = []


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func fetch_archive() -> void:
	_request(ARCHIVE_URL, null)


func fetch_downloads(release: GodotRelease) -> void:
	if release == null:
		return
	if release.downloads_loaded:
		downloads_loaded.emit(release)
		return
	_request(release.page_url, release)


func _request(url: String, target: GodotRelease) -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_queued = [url, target]
		return
	_send(url, target)


func _send(url: String, target: GodotRelease) -> void:
	_pending = target
	var err := _http.request(url, PackedStringArray(["User-Agent: " + USER_AGENT]))
	if err != OK:
		_pending = null
		failed.emit("Could not start request: %s" % error_string(err))


func _send_queued() -> void:
	if _queued.is_empty():
		return
	var url: String = _queued[0]
	var target: GodotRelease = _queued[1]
	_queued = []
	_send(url, target)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var target := _pending
	_pending = null

	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("Network error: %s" % error_string(result))
	elif response_code != 200:
		failed.emit("Server answered %d" % response_code)
	elif target == null:
		var releases := GodotArchiveParser.parse_archive(body.get_string_from_utf8())
		if releases.is_empty():
			failed.emit("Nothing parsed from the archive page")
		else:
			self.releases = releases
			archive_loaded.emit(releases)
	else:
		target.downloads = GodotArchiveParser.parse_downloads(body.get_string_from_utf8())
		target.downloads_loaded = true
		downloads_loaded.emit(target)

	_send_queued()

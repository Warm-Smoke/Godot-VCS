class_name GodotArchiveParser
extends RefCounted

const BASE_URL := "https://godotengine.org"

const ARCHIVE_ITEM_PATTERN := '<a class="archive-version" href="([^"]+)"[^>]*><h4 id="([^"]+)">[^<]*</h4><p class="archive-download-meta"><span>([^<]+)</span>'
const SLUG_PATTERN := "^(.+?)-((?:stable|patch|dev|beta|rc|alpha|mono|unofficial)\\d*)$"
const DOWNLOADS_TAIL_MARKER := '<div class="preview-download-links">'
const DOWNLOAD_LINK_PATTERN := '(?s)<a href="(https://downloads\\.godotengine\\.org/[^"]+)"[^>]*>(.*?)</a>'


static func parse_archive(html: String) -> Array[GodotRelease]:
	var releases: Array[GodotRelease] = []
	var re := RegEx.new()
	if re.compile(ARCHIVE_ITEM_PATTERN) != OK:
		return releases

	var slug_re := RegEx.new()
	slug_re.compile(SLUG_PATTERN)

	for match in re.search_all(html):
		var slug: String = match.get_string(2)
		var release := GodotRelease.new()

		var parts := slug_re.search(slug)
		if parts != null:
			release.version = parts.get_string(1)
			release.prefix = parts.get_string(2)
		else:
			var cut := slug.rfind("-")
			release.version = slug.substr(0, cut) if cut != -1 else slug
			release.prefix = slug.substr(cut + 1) if cut != -1 else ""

		release.date = match.get_string(3)
		release.page_url = BASE_URL + match.get_string(1)
		releases.append(release)

	return releases


static func split_slug(slug: String) -> Array:
	var re := RegEx.new()
	re.compile(SLUG_PATTERN)
	var parts := re.search(slug)
	if parts != null:
		return [parts.get_string(1), parts.get_string(2)]

	var cut := slug.rfind("-")
	if cut == -1:
		return [slug, ""]
	return [slug.substr(0, cut), slug.substr(cut + 1)]


static func parse_downloads(html: String) -> Array[GodotDownload]:
	var downloads: Array[GodotDownload] = []
	var marker := html.find(DOWNLOADS_TAIL_MARKER)
	var scope := html.substr(marker) if marker != -1 else html

	var re := RegEx.new()
	if re.compile(DOWNLOAD_LINK_PATTERN) != OK:
		return downloads

	var seen: Dictionary = {}
	for match in re.search_all(scope):
		var url: String = match.get_string(1).replace("&amp;", "&")
		var params := parse_query(url)
		var platform: String = params.get("platform", "")
		var slug: String = params.get("slug", "")
		if platform.is_empty() or slug.is_empty() or seen.has(url):
			continue

		seen[url] = true
		var download := GodotDownload.new(
			platform,
			clean_text(match.get_string(2)),
			url,
			slug.begins_with("mono")
		)
		download.file_slug = slug
		downloads.append(download)

	return downloads


static func clean_text(text: String) -> String:
	var tags := RegEx.new()
	tags.compile("<[^>]*>")
	var whitespace := RegEx.new()
	whitespace.compile("\\s+")
	return whitespace.sub(tags.sub(text, "", true), " ", true).strip_edges()


static func parse_query(url: String) -> Dictionary:
	var params: Dictionary = {}
	var query := url.find("?")
	if query == -1:
		return params

	for pair in url.substr(query + 1).split("&", false):
		var assign := pair.find("=")
		if assign == -1:
			params[pair] = ""
		else:
			params[pair.substr(0, assign)] = pair.substr(assign + 1)

	return params


static func latest_stable(releases: Array[GodotRelease]) -> GodotRelease:
	for release in releases:
		if release.prefix == "stable":
			return release
	return null

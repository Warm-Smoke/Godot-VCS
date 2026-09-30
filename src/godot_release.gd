class_name GodotRelease
extends RefCounted

var version: String = ""
var prefix: String = ""
var date: String = ""
var page_url: String = ""
var downloads: Array[GodotDownload] = []
var downloads_loaded: bool = false


func slug() -> String:
	if prefix.is_empty():
		return version
	return "%s-%s" % [version, prefix]


func to_dict() -> Dictionary:
	return {
		"version": version,
		"prefix": prefix,
		"date": date,
		"url": page_url,
	}

class_name GodotDownload
extends RefCounted

var platform: String = ""
var title: String = ""
var url: String = ""
var file_slug: String = ""
var is_dotnet: bool = false


func _init(p_platform: String, p_title: String, p_url: String, p_is_dotnet: bool) -> void:
	platform = p_platform
	title = p_title
	url = p_url
	is_dotnet = p_is_dotnet

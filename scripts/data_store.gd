class_name DataStore
extends RefCounted
## 统一从 res://data/ 读取 JSON。所有内容数据化，改内容不需要改代码（需求案 FR-09）。

const DATA_DIR := "res://data/"

static func _read_json(file_name: String) -> Variant:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("[DataStore] 找不到数据文件：%s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("[DataStore] JSON 解析失败：%s" % path)
	return parsed

static func load_config() -> Dictionary:
	var data: Variant = _read_json("config.json")
	if data is Dictionary:
		return data
	return {}

static func load_applications() -> Array:
	var data: Variant = _read_json("applications.json")
	if data is Dictionary and data.has("applications"):
		var list: Variant = data["applications"]
		if list is Array:
			return list
	return []

static func load_rules() -> Dictionary:
	var data: Variant = _read_json("rules.json")
	if data is Dictionary:
		return data
	return {}

static func load_directives() -> Array:
	var data: Variant = _read_json("directives.json")
	if data is Dictionary and data.has("directives"):
		var list: Variant = data["directives"]
		if list is Array:
			return list
	return []

static func load_events() -> Array:
	var data: Variant = _read_json("events.json")
	if data is Dictionary and data.has("events"):
		var list: Variant = data["events"]
		if list is Array:
			return list
	return []

static func load_endings() -> Array:
	var data: Variant = _read_json("endings.json")
	if data is Dictionary and data.has("endings"):
		var list: Variant = data["endings"]
		if list is Array:
			return list
	return []

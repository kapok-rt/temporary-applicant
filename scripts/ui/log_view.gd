class_name LogView
extends PanelContainer
## 日志面板（右侧中部）：裁定结果、Captain 消息、事件卡摘要。

var _body: RichTextLabel


func _ready() -> void:
	custom_minimum_size = Vector2(0, 150)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var title := Label.new()
	title.text = "▌ 值班日志"
	title.add_theme_color_override("font_color", Palette.LINK)
	box.add_child(title)

	box.add_child(HSeparator.new())

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = true
	_body.scroll_following = true
	_body.selection_enabled = false
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_body)


func clear() -> void:
	_body.text = "[color=%s]终端已就绪。[/color]" % Palette.hex(Palette.DIM)


func add_entry(tag: String, text: String, kind: String = "info") -> void:
	var color := Palette.TEXT
	match kind:
		"ok":
			color = Palette.OK
		"bad":
			color = Palette.BAD
		"batch":
			color = Palette.ACCENT
		"info":
			color = Palette.MUTED
	var line := "[color=%s][%s][/color] [color=%s]%s[/color]" % [
		Palette.hex(color), tag, Palette.hex(Palette.TEXT), text,
	]
	if _body.text.length() > 0:
		_body.append_text("\n")
	_body.append_text(line)

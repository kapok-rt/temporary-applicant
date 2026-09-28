class_name DocumentView
extends PanelContainer
## 橱窗：申请人递交的文书原件展示区（界面左侧上半部）。

const KEY_WIDTH := 12

var _body: RichTextLabel


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var title := Label.new()
	title.text = "▌ 橱窗 · 文书原件"
	title.add_theme_color_override("font_color", Palette.ACCENT)
	box.add_child(title)

	box.add_child(HSeparator.new())

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = true
	_body.selection_enabled = false
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_body)

	clear_document()


func clear_document() -> void:
	_body.text = "[color=%s]（终端空闲）等待申请人递交下一份文书……[/color]" % Palette.hex(Palette.DIM)


func show_document(app: Dictionary) -> void:
	if app.is_empty():
		clear_document()
		return

	var signed_ok := bool(app.get("signed", false))
	var lines: Array[String] = []
	lines.append(_kv("文书类型", String(app.get("doc_type", "无"))))
	lines.append(_kv("文书编号", String(app.get("form_no", "无"))))
	lines.append(_kv("申请人", String(app.get("applicant", "无"))))
	lines.append(_kv("职务", String(app.get("role", "无"))))
	lines.append(_kv("签名", "[ 已签署 ]" if signed_ok else "[ 未签署 ]", Palette.OK if signed_ok else Palette.BAD))
	lines.append(_kv("部门章", _stamp_text(app), _stamp_color(app)))
	if ShiftRules.is_weapon(app):
		var hos_ok := bool(app.get("hos_prestamp", false))
		lines.append(_kv("HoS 预盖章", "有（已核验）" if hos_ok else "无", Palette.OK if hos_ok else Palette.BAD))

	lines.append("")
	lines.append(_section("请求事项"))
	lines.append(_paragraph(String(app.get("request", "无"))))
	lines.append("")
	lines.append(_section("申请理由"))
	lines.append(_paragraph(String(app.get("reason", "无"))))
	lines.append("")
	lines.append(_section("安全记录"))
	lines.append(_security_paragraph(String(app.get("security_note", "无"))))

	lines.append("")
	lines.append("[color=%s]签核栏[/color]   [color=%s]待临时人事官裁定 · 仅本值班周期有效[/color]" % [
		Palette.hex(Palette.MUTED), Palette.hex(Palette.WARN),
	])

	_body.text = "\n".join(lines)


func _stamp_text(app: Dictionary) -> String:
	var stamp := String(app.get("dept_stamp", "无"))
	return stamp if stamp != "" else "无"


func _stamp_color(app: Dictionary) -> Color:
	var stamp := _stamp_text(app)
	if stamp == "无" or stamp.contains("无 HoS"):
		return Palette.BAD
	return Palette.OK


func _kv(key: String, value: String, value_color: Color = Palette.TEXT) -> String:
	return "[color=%s]%s[/color][color=%s]%s[/color]" % [
		Palette.hex(Palette.MUTED), Palette.pad(key, KEY_WIDTH), Palette.hex(value_color), value,
	]


func _section(title: String) -> String:
	return "[color=%s]── %s ────────────────────[/color]" % [Palette.hex(Palette.DIM), title]


func _paragraph(text: String) -> String:
	return "[color=%s]%s[/color]" % [Palette.hex(Palette.TEXT), text]


func _security_paragraph(text: String) -> String:
	# 「可疑」标注用琥珀色高亮，方便阅读，但不提示该走哪条规定。
	var color := Palette.WARN if text.contains(ShiftRules.SUSPICIOUS_MARK) else Palette.TEXT
	return "[color=%s]%s[/color]" % [Palette.hex(color), text]

class_name RulesView
extends PanelContainer
## 审核规则面板（界面右侧上半部）：硬规则 + 生效中的 Captain 临时指令 + 软线索提示。

var _body: RichTextLabel


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var title := Label.new()
	title.text = "▌ 审核规则 · 本周期有效"
	title.add_theme_color_override("font_color", Palette.WARN)
	box.add_child(title)

	box.add_child(HSeparator.new())

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = true
	_body.selection_enabled = false
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_body)

	refresh()


func refresh() -> void:
	var lines: Array[String] = []

	var hard_rules: Array = GameState.rules.get("hard_rules", [])
	for rule in hard_rules:
		if not rule is Dictionary:
			continue
		lines.append("[color=%s]%s[/color]  %s  [color=%s]→ %s[/color]" % [
			Palette.hex(Palette.ACCENT),
			Palette.pad(String(rule.get("code", "?")), 4),
			String(rule.get("text", "")),
			Palette.hex(Palette.DIM),
			ShiftRules.action_label(String(rule.get("action", ""))),
		])

	lines.append("")
	lines.append("[color=%s]── Captain 临时指令（优先于上列规则）──[/color]" % Palette.hex(Palette.WARN))
	if GameState.active_directives.is_empty():
		lines.append("[color=%s]（本批次尚无临时指令）[/color]" % Palette.hex(Palette.DIM))
	else:
		for directive in GameState.active_directives:
			if not directive is Dictionary:
				continue
			var change: Dictionary = directive.get("rule_change", {})
			lines.append("[color=%s]%s[/color]  [color=%s]%s → %s[/color]" % [
				Palette.hex(Palette.BAD),
				Palette.pad(String(directive.get("id", "?")), 6),
				Palette.hex(Palette.TEXT),
				String(change.get("summary", "")),
				ShiftRules.action_label(String(change.get("action", ""))),
			])

	lines.append("")
	lines.append("[color=%s]── 软线索（不构成硬性判定）──[/color]" % Palette.hex(Palette.DIM))
	var hints: Array = GameState.rules.get("soft_hints", [])
	for hint in hints:
		lines.append("[color=%s] · %s[/color]" % [Palette.hex(Palette.MUTED), String(hint)])

	lines.append("")
	lines.append("[color=%s]── 操作说明 ──[/color]" % Palette.hex(Palette.DIM))
	var ops: Array = GameState.rules.get("ops_notes", [])
	for op in ops:
		lines.append("[color=%s] · %s[/color]" % [Palette.hex(Palette.MUTED), String(op)])

	_body.text = "\n".join(lines)

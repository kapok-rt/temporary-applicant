class_name CounterView
extends PanelContainer
## 柜台：当前申请人（纯色块立绘）+ 等待槽状态（界面左侧下半部）。

const SLOT_SIZE := Vector2(16, 16)

var _portrait: Panel
var _initial: Label
var _portrait_style: StyleBoxFlat

var _name_value: Label
var _role_value: Label
var _status_value: Label

var _slot_box: HBoxContainer
var _slot_count: Label
var _pending: Label

var _slots: Array[Panel] = []


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var title := Label.new()
	title.text = "▌ 柜台 · 当前申请人"
	title.add_theme_color_override("font_color", Palette.WARN)
	box.add_child(title)

	# ---- 立绘 + 资料 ----
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	box.add_child(top)

	_portrait_style = StyleBoxFlat.new()
	_portrait_style.bg_color = Palette.DIM
	_portrait_style.border_width_left = 2
	_portrait_style.border_width_top = 2
	_portrait_style.border_width_right = 2
	_portrait_style.border_width_bottom = 2
	_portrait_style.border_color = Palette.DIM

	_portrait = Panel.new()
	_portrait.custom_minimum_size = Vector2(76, 76)
	_portrait.add_theme_stylebox_override("panel", _portrait_style)
	top.add_child(_portrait)

	_initial = Label.new()
	_initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initial.add_theme_font_size_override("font_size", 28)
	_initial.add_theme_color_override("font_color", Color(0.06, 0.07, 0.08))
	_portrait.add_child(_initial)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	top.add_child(grid)

	_name_value = _add_row(grid, "姓名")
	_role_value = _add_row(grid, "职务")
	_status_value = _add_row(grid, "状态")

	# ---- 柜台线 + 等待槽 ----
	box.add_child(HSeparator.new())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	box.add_child(bottom)

	var slot_label := Label.new()
	slot_label.text = "等待槽"
	slot_label.add_theme_color_override("font_color", Palette.MUTED)
	bottom.add_child(slot_label)

	_slot_box = HBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", 4)
	bottom.add_child(_slot_box)

	_slot_count = Label.new()
	_slot_count.add_theme_color_override("font_color", Palette.TEXT)
	bottom.add_child(_slot_count)

	_pending = Label.new()
	_pending.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pending.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pending.add_theme_color_override("font_color", Palette.MUTED)
	bottom.add_child(_pending)

	_rebuild_slots()
	clear_view()


func _add_row(grid: GridContainer, key: String) -> Label:
	var key_label := Label.new()
	key_label.text = key
	key_label.add_theme_color_override("font_color", Palette.MUTED)
	grid.add_child(key_label)

	var value := Label.new()
	value.text = "——"
	value.add_theme_color_override("font_color", Palette.TEXT)
	grid.add_child(value)
	return value


func _rebuild_slots() -> void:
	for child in _slot_box.get_children():
		child.queue_free()
	_slots.clear()
	var total := GameState.wait_slots_total()
	for index in total:
		var slot := Panel.new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.add_theme_stylebox_override("panel", _slot_style(false))
		_slot_box.add_child(slot)
		_slots.append(slot)


func _slot_style(filled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.WARN if filled else Color(0.09, 0.10, 0.11)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Palette.WARN if filled else Palette.DIM
	return style


func clear_view() -> void:
	_initial.text = "—"
	_portrait_style.bg_color = Palette.DIM
	_portrait_style.border_color = Palette.DIM
	_name_value.text = "（柜台空闲）"
	_name_value.add_theme_color_override("font_color", Palette.DIM)
	_role_value.text = "——"
	_status_value.text = "——"
	_status_value.add_theme_color_override("font_color", Palette.DIM)
	refresh_slots()


func refresh() -> void:
	var app: Dictionary = GameState.current
	if app.is_empty():
		clear_view()
		return

	var role := String(app.get("role", ""))
	var color := Palette.dept_color(role)
	var applicant := String(app.get("applicant", "?"))

	_portrait_style.bg_color = color
	_portrait_style.border_color = color.lightened(0.25)
	_initial.text = _initial_char(applicant)

	_name_value.text = applicant
	_name_value.add_theme_color_override("font_color", Palette.TEXT)
	_role_value.text = role
	_status_value.text = "已缴交文书 · 等待裁定"
	_status_value.add_theme_color_override("font_color", Palette.WARN)

	refresh_slots()


func refresh_slots() -> void:
	var used := GameState.wait_slots_used
	var total := GameState.wait_slots_total()
	while _slots.size() < total:
		var slot := Panel.new()
		slot.custom_minimum_size = SLOT_SIZE
		_slot_box.add_child(slot)
		_slots.append(slot)
	for index in _slots.size():
		var filled := index < used
		_slots[index].add_theme_stylebox_override("panel", _slot_style(filled))
	_slot_count.text = "%d / %d" % [used, total]

	var parts: Array[String] = []
	for item in GameState.pending_transfers:
		if not item is Dictionary:
			continue
		var app: Dictionary = item.get("app", {})
		var release := int(item.get("release_batch", 0))
		var when := "值班结束后" if release > GameState.batch_count() else "第 %d 批返回" % release
		parts.append("%s（%s）" % [String(app.get("id", "?")), when])
	_pending.text = "在队回执：" + "、".join(parts) if not parts.is_empty() else ""


func _initial_char(applicant: String) -> String:
	var trimmed := applicant.strip_edges()
	if trimmed.begins_with("D-"):
		return "D"
	var first := trimmed.substr(0, 1)
	return first if first != "" else "?"

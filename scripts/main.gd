extends Control
## 主场景控制器：把 GameState 映射到界面，并驱动状态机。
## 布局：左侧 = 橱窗（文书原件）+ 柜台（申请人 / 等待槽）；右侧 = 审核规则 + 审核按钮。

const ACTION_APPROVE := ShiftRules.ACTION_APPROVE
const ACTION_REJECT := ShiftRules.ACTION_REJECT
const ACTION_TRANSFER := ShiftRules.ACTION_TRANSFER

const STATE_INTRO := "intro"
const STATE_REVIEW := "review"
const STATE_MODAL := "modal"
const STATE_SETTLE := "settle"

const MODAL_WIDTH := 780.0

@onready var _countdown: Label = %CountdownLabel
@onready var _batch_label: Label = %BatchLabel
@onready var _stamp_label: Label = %StampLabel
@onready var _slot_label: Label = %SlotLabel
@onready var _trust_label: Label = %TrustLabel
@onready var _showcase: DocumentView = %Showcase
@onready var _counter: CounterView = %Counter
@onready var _rules: RulesView = %Rules
@onready var _log: LogView = %Log
@onready var _approve_button: Button = %ApproveButton
@onready var _reject_button: Button = %RejectButton
@onready var _transfer_button: Button = %TransferButton
@onready var _hint: Label = %ActionHint
@onready var _overlay: Control = %Overlay

var _state := STATE_INTRO
var _last_seconds := 480.0
var _modal_queue: Array = []
var _modal_live: Array = []
var _modal_active := false
var _modal_primary_callback: Callable = Callable()


func _ready() -> void:
	GameState.ensure_loaded()
	_apply_optional_font()

	_overlay.visible = false
	_approve_button.pressed.connect(_on_action_pressed.bind(ACTION_APPROVE))
	_reject_button.pressed.connect(_on_action_pressed.bind(ACTION_REJECT))
	_transfer_button.pressed.connect(_on_action_pressed.bind(ACTION_TRANSFER))
	GameState.note.connect(_log.add_entry)
	GameState.changed.connect(_update_hud)

	_log.clear()
	_update_hud()
	_update_actions()
	_show_intro()


func _process(delta: float) -> void:
	if _state != STATE_REVIEW or _modal_active:
		return
	if GameState.tick(delta):
		_finish("值班倒计时耗尽")
	else:
		_update_countdown()


# ------------------------------------------------------------------ 流程

func _show_intro() -> void:
	_state = STATE_INTRO
	var body := "[color=%s]Captain 已离舰。离舰原因未在通告中说明。[/color]\n\n" % Palette.hex(Palette.MUTED)
	body += "中央 AI 依据《临时职务代理条例》第 4 条，临时指派你担任人事官（HOP），权限有效期至本值班周期结束。本周期内无人复核，所有裁定一经签署即刻生效。\n\n"
	body += "[color=%s]本周期待处理文书[/color]  %d 份 · 分 %d 批送达\n" % [Palette.hex(Palette.ACCENT), GameState.applications.size(), GameState.batch_count()]
	body += "[color=%s]印章耐久[/color]  %d 点（批准消耗 %d 点）\n" % [Palette.hex(Palette.ACCENT), GameState.stamp_durability(), GameState.stamp_cost()]
	body += "[color=%s]等待槽[/color]  %d 格（转交占用 1 格，延迟 %d 批返回回执）" % [Palette.hex(Palette.ACCENT), GameState.wait_slots_total(), GameState.transfer_delay()]
	_open_static_modal("临时人事官 · HOP TERMINAL", body, Palette.WARN, [
		{"text": "开始值班  [ 8:00 ]", "callback": Callable(self, "_start_standard")},
		{"text": "宽松模式  [ 15:00 ]", "callback": Callable(self, "_start_relaxed")},
	])


func _start_standard() -> void:
	_start(GameState.standard_seconds())


func _start_relaxed() -> void:
	_start(GameState.relaxed_seconds())


func _start(seconds: float) -> void:
	_reset_modals()
	_last_seconds = seconds
	GameState.start_shift(seconds)
	_log.clear()
	_log.add_entry("系统", "值班开始。倒计时 %s。" % _format_time(seconds), "batch")
	_showcase.clear_document()
	_counter.clear_view()
	_rules.refresh()
	_hint.text = "文书已送达。请对照右侧审核规则作出裁定。"
	_update_hud()
	_update_actions()
	_begin_batch(1)


func _begin_batch(index: int) -> void:
	var fresh: Array = GameState.begin_batch(index)
	_rules.refresh()
	_counter.refresh_slots()
	_update_hud()
	_update_actions()

	if fresh.is_empty():
		_enter_reviewing()
		return

	_state = STATE_MODAL
	for i in fresh.size():
		var directive: Dictionary = fresh[i]
		var on_close := Callable()
		if i == fresh.size() - 1:
			on_close = Callable(self, "_enter_reviewing")
		_queue_modal(
			"Captain 临时指令 · %s" % String(directive.get("id", "")),
			_directive_body(directive),
			Palette.BAD,
			on_close
		)


func _begin_next_batch() -> void:
	_begin_batch(GameState.batch + 1)


func _enter_reviewing() -> void:
	_state = STATE_REVIEW
	_next_application()


func _next_application() -> void:
	if not GameState.take_next():
		_end_batch()
		return
	_showcase.show_document(GameState.current)
	_counter.refresh()
	_update_hud()
	_update_actions()


func _on_action_pressed(action: String) -> void:
	if _state != STATE_REVIEW or _modal_active:
		return
	if action == ACTION_APPROVE and not GameState.can_approve():
		return
	if action == ACTION_TRANSFER and not GameState.can_transfer():
		return

	var result := GameState.submit(action)
	if result.is_empty():
		return

	_hint.text = _result_hint(result)
	_update_hud()
	_update_actions()
	_next_application()


func _end_batch() -> void:
	_state = STATE_MODAL
	var fired: Array = GameState.check_events()
	_update_hud()
	_update_actions()

	var is_last_batch := GameState.batch >= GameState.batch_count()
	var next_step: Callable = Callable(self, "_finish_shift") if is_last_batch else Callable(self, "_begin_next_batch")

	if fired.is_empty():
		next_step.call()
		return

	for i in fired.size():
		var event: Dictionary = fired[i]
		var on_close := Callable()
		if i == fired.size() - 1:
			on_close = next_step
		_queue_modal(
			"事件 · %s" % String(event.get("title", "")),
			_event_body(event),
			Palette.BAD,
			on_close
		)


func _finish_shift() -> void:
	_finish("全部批次处理完毕")


func _finish(reason: String) -> void:
	_state = STATE_SETTLE
	GameState.check_events()  # 兜底：把已满足条件但还没弹出的事件并入结算列表
	var report: Dictionary = GameState.build_report(reason)
	_log.add_entry("系统", "值班结束：%s" % reason, "batch")
	_update_hud()
	_update_actions()
	_open_static_modal("值班报告 · SHIFT REPORT", _report_body(report), Palette.WARN, [
		{"text": "重新值班", "callback": Callable(self, "_start_last")},
	], 330.0)


func _start_last() -> void:
	_start(_last_seconds)


# ------------------------------------------------------------------ 文案

func _result_hint(result: Dictionary) -> String:
	var text := "上一条：" + GameState.verdict_line(result)
	if not bool(result.get("correct", false)):
		text += "　｜　应为：%s" % ShiftRules.action_label(String(result.get("expected", "")))
	return text


func _directive_body(directive: Dictionary) -> String:
	var change: Dictionary = directive.get("rule_change", {})
	return "[color=%s]发信人：%s[/color]\n\n[color=%s]%s[/color]\n\n[color=%s]▸ 即刻生效：%s → %s[/color]" % [
		Palette.hex(Palette.MUTED), String(directive.get("sender", "Captain")),
		Palette.hex(Palette.TEXT), String(directive.get("text", "")),
		Palette.hex(Palette.WARN),
		String(change.get("summary", "")),
		ShiftRules.action_label(String(change.get("action", ""))),
	]


func _event_body(event: Dictionary) -> String:
	var delta := float(event.get("trust_delta", 0.0))
	var delta_text := "信任值无变化"
	if not is_zero_approx(delta):
		delta_text = "信任值 %s" % _signed(delta)
	return "[color=%s]%s[/color]\n\n[color=%s]%s[/color]\n\n[color=%s]%s[/color]" % [
		Palette.hex(Palette.MUTED), String(event.get("id", "")),
		Palette.hex(Palette.TEXT), String(event.get("text", "")),
		Palette.hex(Palette.DIM), delta_text,
	]


func _report_body(report: Dictionary) -> String:
	var stats: Dictionary = report.get("stats", {})
	var ending: Dictionary = report.get("ending", {})
	var lines: Array[String] = []
	lines.append("[color=%s]结束原因[/color]  %s" % [Palette.hex(Palette.MUTED), String(report.get("reason", ""))])
	lines.append("[color=%s]处理文书[/color]  %d / %d" % [Palette.hex(Palette.MUTED), int(report.get("handled", 0)), int(report.get("total", 0))])
	lines.append("[color=%s]判定正确[/color]  %d 份（%.1f%%）" % [Palette.hex(Palette.MUTED), int(report.get("correct", 0)), float(report.get("accuracy", 0.0))])
	lines.append("[color=%s]裁定分布[/color]  批准 %d · 驳回 %d · 转交 %d" % [
		Palette.hex(Palette.MUTED),
		int(stats.get("approve", 0)), int(stats.get("reject", 0)), int(stats.get("transfer", 0)),
	])
	lines.append("[color=%s]印章消耗[/color]  %d / %d" % [Palette.hex(Palette.MUTED), int(report.get("stamp_used", 0)), GameState.stamp_durability()])
	lines.append("[color=%s]信任值[/color]    %s" % [Palette.hex(Palette.MUTED), _signed(float(report.get("trust", 0.0)))])
	lines.append("")
	lines.append("[color=%s]── 触发事件 ──[/color]" % Palette.hex(Palette.DIM))
	var fired: Array = report.get("events", [])
	if fired.is_empty():
		lines.append("[color=%s]（本班次未触发任何事件）[/color]" % Palette.hex(Palette.DIM))
	else:
		for event in fired:
			lines.append("[color=%s]· %s[/color]  [color=%s]%s[/color]" % [
				Palette.hex(Palette.BAD), String(event.get("title", "")),
				Palette.hex(Palette.MUTED), String(event.get("text", "")),
			])
	lines.append("")
	lines.append("[color=%s]── 结局 · %s ──[/color]" % [Palette.hex(Palette.WARN), String(ending.get("title", ""))])
	lines.append("[color=%s]%s[/color]" % [Palette.hex(Palette.TEXT), String(ending.get("body", ""))])
	return "\n".join(lines)


func _signed(value: float) -> String:
	var prefix := "+" if value >= 0.0 else "-"
	return "%s%.1f" % [prefix, absf(value)]


# ------------------------------------------------------------------ HUD

func _update_hud() -> void:
	_batch_label.text = "批次 %d / %d" % [GameState.batch, GameState.batch_count()]
	_stamp_label.text = "印章耐久 %d / %d" % [GameState.stamp_left, GameState.stamp_durability()]
	_slot_label.text = "等待槽 %d / %d" % [GameState.wait_slots_used, GameState.wait_slots_total()]
	_trust_label.text = "信任值 %s" % _signed(GameState.trust)
	if GameState.trust >= 8.0:
		_trust_label.add_theme_color_override("font_color", Palette.OK)
	elif GameState.trust >= 2.0:
		_trust_label.add_theme_color_override("font_color", Palette.WARN)
	else:
		_trust_label.add_theme_color_override("font_color", Palette.BAD)
	_update_countdown()


func _update_countdown() -> void:
	_countdown.text = "倒计时 %s" % _format_time(GameState.time_left)
	if GameState.time_left <= 60.0:
		_countdown.add_theme_color_override("font_color", Palette.BAD)
	elif GameState.time_left <= 150.0:
		_countdown.add_theme_color_override("font_color", Palette.WARN)
	else:
		_countdown.add_theme_color_override("font_color", Palette.ACCENT)


func _update_actions() -> void:
	var reviewing := _state == STATE_REVIEW and not _modal_active
	_approve_button.text = "批准  （印章 -%d）" % GameState.stamp_cost()
	_reject_button.text = "驳回"
	_transfer_button.text = "转交 Captain  （等待槽 %d/%d）" % [GameState.wait_slots_used, GameState.wait_slots_total()]
	_approve_button.disabled = not (reviewing and GameState.can_approve())
	_reject_button.disabled = not (reviewing and GameState.can_reject())
	_transfer_button.disabled = not (reviewing and GameState.can_transfer())


func _format_time(seconds: float) -> String:
	var total := int(ceil(maxf(0.0, seconds)))
	return "%02d:%02d" % [total / 60, total % 60]


func _apply_optional_font() -> void:
	# 若要打包字体（Web 导出时系统字体不可用），把 ttf/otf 放进 res://theme/fonts/ 即可自动生效。
	var dir_path := "res://theme/fonts"
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file_name in DirAccess.get_files_at(dir_path):
		var lower := file_name.to_lower()
		if not (lower.ends_with(".ttf") or lower.ends_with(".otf") or lower.ends_with(".ttc")):
			continue
		var font: Font = load(dir_path + "/" + file_name)
		if font != null:
			var custom := Theme.new()
			custom.default_font = font
			theme = custom
		return


# ------------------------------------------------------------------ 弹窗

func _open_static_modal(title: String, body: String, accent: Color, buttons: Array, body_min_height: float = 0.0) -> void:
	_modal_queue.clear()
	_modal_active = false
	_build_modal(title, body, accent, buttons, body_min_height)


func _queue_modal(title: String, body: String, accent: Color, on_close: Callable) -> void:
	_modal_queue.append({"title": title, "body": body, "accent": accent, "on_close": on_close})
	_drain_modals()


func _drain_modals() -> void:
	if _modal_active or _modal_queue.is_empty():
		return
	var item: Dictionary = _modal_queue.pop_front()
	_build_modal(
		String(item.get("title", "")),
		String(item.get("body", "")),
		item.get("accent", Palette.WARN),
		[{"text": "继续  ▸", "callback": item.get("on_close", Callable())}],
		0.0
	)


func _build_modal(title: String, body: String, accent: Color, buttons: Array, body_min_height: float) -> void:
	_modal_active = true
	_overlay.visible = true

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	_modal_live.append(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	_modal_live.append(center)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.066, 0.078)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = accent
	style.content_margin_left = 22.0
	style.content_margin_top = 18.0
	style.content_margin_right = 22.0
	style.content_margin_bottom = 18.0

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(MODAL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", accent)
	title_label.add_theme_font_size_override("font_size", 18)
	box.add_child(title_label)

	box.add_child(HSeparator.new())

	var body_label := RichTextLabel.new()
	body_label.bbcode_enabled = true
	body_label.selection_enabled = false
	body_label.text = body
	if body_min_height > 0.0:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, body_min_height)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(body_label)
		box.add_child(scroll)
	else:
		body_label.fit_content = true
		box.add_child(body_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	var specs: Array = buttons
	if specs.is_empty():
		specs = [{"text": "继续  ▸", "callback": Callable()}]
	_modal_primary_callback = Callable()
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var callback: Callable = spec.get("callback", Callable())
		if i == 0:
			_modal_primary_callback = callback
		var button := Button.new()
		button.text = String(spec.get("text", "确定"))
		button.custom_minimum_size = Vector2(210, 0)
		button.pressed.connect(_on_modal_button.bind(callback))
		row.add_child(button)


func _on_modal_button(callback: Callable) -> void:
	_finish_modal()
	if callback.is_valid():
		callback.call()
	_drain_modals()


func _finish_modal() -> void:
	_modal_active = false
	for node in _modal_live:
		if is_instance_valid(node):
			_overlay.remove_child(node)
			node.queue_free()
	_modal_live.clear()
	_overlay.visible = false


func _reset_modals() -> void:
	_modal_queue.clear()
	_finish_modal()


# ------------------------------------------------------------------ 开发工具（可整段删除）

## 自动按“正确裁定”推进，用于快速跑到结算界面做冒烟测试。
func dev_auto_play(count: int, wrong_count: int = 0, stop_at_modal: bool = false) -> void:
	if _state == STATE_INTRO:
		_start(GameState.relaxed_seconds())
	if count <= 0:
		return
	var guard := 0
	var done := 0
	while done < count and guard < 500:
		guard += 1
		if _state == STATE_SETTLE:
			break
		if _modal_active:
			if stop_at_modal:
				break
			_on_modal_button(_modal_primary_callback)
			continue
		if _state != STATE_REVIEW:
			break
		var verdict := GameState.current_verdict()
		if verdict.is_empty():
			break
		var action := String(verdict.get("action", ACTION_REJECT))
		if done < wrong_count:
			# 轮流换错法，保证错判批准 / 错判驳回 / 错判转交三条路径都被走到，
			# 同时顺带验证资源不足时按钮禁用（选项里会跳过不可用动作）。
			var options: Array[String] = []
			for candidate in [ACTION_APPROVE, ACTION_REJECT, ACTION_TRANSFER]:
				if candidate == action:
					continue
				if candidate == ACTION_APPROVE and not GameState.can_approve():
					continue
				if candidate == ACTION_TRANSFER and not GameState.can_transfer():
					continue
				options.append(candidate)
			if not options.is_empty():
				action = options[done % options.size()]
		_on_action_pressed(action)
		done += 1

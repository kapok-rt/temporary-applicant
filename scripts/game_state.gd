extends Node
## GameState（Autoload）：值班运行时状态 + 结算。所有数值来自 data/config.json。
##
## 状态机（需求案 §6）：Boot → Intro → BatchStart → Reviewing → BatchResolve
##                      → Directive/EventCheck → NextBatch → ShiftEnd → Settlement → Restart

signal note(tag: String, text: String, kind: String)
signal changed()

const ACTION_APPROVE := ShiftRules.ACTION_APPROVE
const ACTION_REJECT := ShiftRules.ACTION_REJECT
const ACTION_TRANSFER := ShiftRules.ACTION_TRANSFER

const TOTAL_ERROR_KEY := "__total__"
const MISHANDLED_KEY := "mishandled"

# ---- 静态内容（JSON） ----
var config: Dictionary = {}
var applications: Array = []
var rules: Dictionary = {}
var directives: Array = []
var events: Array = []
var endings: Array = []

# ---- 运行时状态 ----
var batch: int = 1
var queue: Array = []
var current: Dictionary = {}
var active_directives: Array = []
var used_directive_ids: Array = []
var pending_transfers: Array = []

var stamp_left: int = 0
var wait_slots_used: int = 0
var trust: float = 0.0
var time_left: float = 0.0
var running: bool = false
var last_seconds: float = 480.0

var stats: Dictionary = {}
var error_counts: Dictionary = {}
var fired_event_ids: Array = []


func _ready() -> void:
	load_content()


func ensure_loaded() -> void:
	if applications.is_empty() or config.is_empty():
		load_content()


func load_content() -> void:
	config = DataStore.load_config()
	applications = DataStore.load_applications()
	rules = DataStore.load_rules()
	directives = DataStore.load_directives()
	events = DataStore.load_events()
	endings = DataStore.load_endings()
	if time_left <= 0.0:
		time_left = standard_seconds()  # 开场界面先显示标准值班时长


# ---------------------------------------------------------------- 配置读取

func cfg(key: String, fallback: Variant) -> Variant:
	return config.get(key, fallback)

func standard_seconds() -> float:
	return float(cfg("shift_seconds", 480))

func relaxed_seconds() -> float:
	return float(cfg("relaxed_seconds", 900))

func batch_count() -> int:
	return int(cfg("batches", 3))

func stamp_durability() -> int:
	return int(cfg("stamp_durability", 15))

func stamp_cost() -> int:
	return int(cfg("stamp_cost_approve", 1))

func wait_slots_total() -> int:
	return int(cfg("wait_slots", 3))

func transfer_delay() -> int:
	return int(cfg("transfer_delay_batches", 1))

## 转交回执落在哪个批次；若超出总批次，则本班次内不会返回。
func transfer_release_batch() -> int:
	return batch + transfer_delay()

func transfer_release_label() -> String:
	var target := transfer_release_batch()
	if target > batch_count():
		return "值班结束后"
	return "第 %d 批" % target


# ---------------------------------------------------------------- 生命周期

func start_shift(seconds: float) -> void:
	last_seconds = seconds
	batch = 1
	queue.clear()
	current = {}
	active_directives.clear()
	used_directive_ids.clear()
	pending_transfers.clear()
	stamp_left = stamp_durability()
	wait_slots_used = 0
	trust = 0.0
	time_left = seconds
	running = true
	error_counts.clear()
	fired_event_ids.clear()
	stats = {
		"handled": 0,
		"approve": 0,
		"reject": 0,
		"transfer": 0,
		"correct": 0,
		"wrong": 0,
	}
	changed.emit()

## 进入某个批次。返回本批次新生效的临时指令（可能为空）。
func begin_batch(index: int) -> Array:
	batch = index
	_release_transfers()

	queue.clear()
	for app in applications:
		if app is Dictionary and int(app.get("batch", 0)) == index:
			queue.append(app)

	var fresh: Array = []
	for directive in directives:
		if not directive is Dictionary:
			continue
		var did := String(directive.get("id", ""))
		if int(directive.get("trigger_batch", -1)) != index:
			continue
		if used_directive_ids.has(did):
			continue
		used_directive_ids.append(did)
		active_directives.append(directive)
		fresh.append(directive)
		var change: Dictionary = directive.get("rule_change", {})
		note.emit("指令", "Captain 临时指令 %s 生效：%s。" % [did, String(change.get("summary", ""))], "bad")

	current = {}
	note.emit("批次", "第 %d / %d 批文书已送达，共 %d 份。" % [index, batch_count(), queue.size()], "batch")
	changed.emit()
	return fresh

func take_next() -> bool:
	if queue.is_empty():
		current = {}
		changed.emit()
		return false
	current = queue.pop_front()
	changed.emit()
	return true

func queue_remaining() -> int:
	return queue.size()

## 倒计时推进。返回 true 表示本帧耗尽（应触发结算）。
func tick(delta: float) -> bool:
	if not running:
		return false
	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		running = false
		return true
	return false


func _release_transfers() -> void:
	var still_waiting: Array = []
	for item in pending_transfers:
		if not item is Dictionary:
			continue
		if int(item.get("release_batch", 0)) <= batch:
			wait_slots_used = maxi(0, wait_slots_used - 1)
			var app: Dictionary = item.get("app", {})
			note.emit("回执", "%s 的文书已由 Captain 复核完毕，等待槽释放。" % String(app.get("applicant", "?")), "ok")
		else:
			still_waiting.append(item)
	pending_transfers = still_waiting


# ---------------------------------------------------------------- 判定与提交

func can_approve() -> bool:
	return running and not current.is_empty() and stamp_left >= stamp_cost()

func can_reject() -> bool:
	return running and not current.is_empty()

func can_transfer() -> bool:
	return running and not current.is_empty() and wait_slots_used < wait_slots_total()

func wait_slots_free() -> int:
	return maxi(0, wait_slots_total() - wait_slots_used)

func current_verdict() -> Dictionary:
	if current.is_empty():
		return {}
	return ShiftRules.resolve(current, active_directives)

## 提交一次裁定。返回 {app_id, applicant, chosen, expected, correct, delta, verdict}
func submit(action: String) -> Dictionary:
	if current.is_empty():
		return {}

	var verdict := current_verdict()
	var expected := String(verdict.get("action", ACTION_REJECT))
	var correct := action == expected

	stats["handled"] = int(stats.get("handled", 0)) + 1
	stats[action] = int(stats.get(action, 0)) + 1

	if action == ACTION_APPROVE:
		stamp_left = maxi(0, stamp_left - stamp_cost())
	elif action == ACTION_TRANSFER:
		wait_slots_used += 1
		pending_transfers.append({
			"app": current.duplicate(true),
			"release_batch": transfer_release_batch(),
		})

	var delta := 0.0
	if correct:
		if action == ACTION_TRANSFER:
			delta = float(cfg("trust_transfer_correct", 0.5))
		else:
			delta = float(cfg("trust_correct", 1.0))
		stats["correct"] = int(stats.get("correct", 0)) + 1
	else:
		delta = float(cfg("trust_wrong", -1.0))
		stats["wrong"] = int(stats.get("wrong", 0)) + 1
		var error_type := String(verdict.get("error_type", ""))
		if error_type == "":
			error_type = MISHANDLED_KEY
		error_counts[error_type] = int(error_counts.get(error_type, 0)) + 1
	trust += delta

	var result := {
		"app_id": String(current.get("id", "")),
		"applicant": String(current.get("applicant", "")),
		"doc_type": String(current.get("doc_type", "")),
		"chosen": action,
		"expected": expected,
		"correct": correct,
		"delta": delta,
		"verdict": verdict,
	}
	note.emit("裁定", verdict_line(result), "ok" if correct else "bad")
	if action == ACTION_TRANSFER:
		note.emit("等待槽", "占用 1 格等待槽，Captain 回执预计于%s送达。" % transfer_release_label(), "info")
	changed.emit()
	return result


func verdict_line(result: Dictionary) -> String:
	var verdict: Dictionary = result.get("verdict", {})
	var source := ShiftRules.source_label(String(verdict.get("source", "")))
	var outcome := "判定正确" if bool(result.get("correct", false)) else "判定偏差"
	return "%s %s · %s → %s（%s %s：%s）" % [
		String(result.get("app_id", "?")),
		String(result.get("applicant", "?")),
		ShiftRules.action_label(String(result.get("chosen", ""))),
		outcome,
		source,
		String(verdict.get("code", "")),
		String(verdict.get("reason", "")),
	]


# ---------------------------------------------------------------- 事件

## 检查并触发事件卡。返回本批新触发的事件列表。
func check_events() -> Array:
	var fired: Array = []
	var total_wrong := int(stats.get("wrong", 0))
	for event in events:
		if not event is Dictionary:
			continue
		var eid := String(event.get("id", ""))
		if fired_event_ids.has(eid):
			continue
		var key := String(event.get("trigger_error_type", ""))
		var count := total_wrong if key == TOTAL_ERROR_KEY else int(error_counts.get(key, 0))
		if count < int(event.get("min_count", 1)):
			continue
		fired_event_ids.append(eid)
		trust += float(event.get("trust_delta", 0.0))
		fired.append(event)
		note.emit("事件", "%s —— %s" % [String(event.get("title", "")), String(event.get("text", ""))], "bad")
	if not fired.is_empty():
		changed.emit()
	return fired


func fired_events() -> Array:
	var list: Array = []
	for event in events:
		if event is Dictionary and fired_event_ids.has(String(event.get("id", ""))):
			list.append(event)
	return list


# ---------------------------------------------------------------- 结算

func pick_ending(value: float) -> Dictionary:
	for ending in endings:
		if not ending is Dictionary:
			continue
		var low := float(ending.get("min_trust", -9999.0))
		var high := float(ending.get("max_trust", 9999.0))
		if value >= low and value <= high:
			return ending
	return {"id": "END-NONE", "title": "未定义结局", "body": "没有匹配的结算档位，请检查 data/endings.json。"}


func build_report(reason: String) -> Dictionary:
	running = false
	var handled := int(stats.get("handled", 0))
	var correct := int(stats.get("correct", 0))
	return {
		"reason": reason,
		"trust": trust,
		"ending": pick_ending(trust),
		"events": fired_events(),
		"stats": stats.duplicate(),
		"handled": handled,
		"correct": correct,
		"accuracy": (float(correct) / float(handled) * 100.0) if handled > 0 else 0.0,
		"stamp_left": stamp_left,
		"stamp_used": stamp_durability() - stamp_left,
		"batch": batch,
		"total": applications.size(),
		"pending": pending_transfers.size(),
	}

class_name ShiftRules
extends RefCounted
## 判定核心（需求案 FR-05）。优先级：Captain 临时指令 > 硬规则 > 文书预置判定（软线索）。
##
## 这个类不依赖场景树，因此可以被 tests/rules_test.gd 直接调用做全量校验。

const ACTION_APPROVE := "approve"
const ACTION_REJECT := "reject"
const ACTION_TRANSFER := "transfer"

const SOURCE_DIRECTIVE := "directive"
const SOURCE_HARD := "hard"
const SOURCE_PRESET := "preset"

const WEAPON_TAG := "武器"
const SUSPICIOUS_MARK := "可疑"

static func action_label(action: String) -> String:
	match action:
		ACTION_APPROVE:
			return "批准"
		ACTION_REJECT:
			return "驳回"
		ACTION_TRANSFER:
			return "转交"
		_:
			return action

static func source_label(source: String) -> String:
	match source:
		SOURCE_DIRECTIVE:
			return "临时指令"
		SOURCE_HARD:
			return "硬规则"
		SOURCE_PRESET:
			return "阅读判断"
		_:
			return "判定"

static func is_weapon(app: Dictionary) -> bool:
	var tags: Array = app.get("tags", [])
	if tags.has(WEAPON_TAG):
		return true
	return String(app.get("doc_type", "")).contains(WEAPON_TAG)

static func shows_suspicious_mark(app: Dictionary) -> bool:
	return String(app.get("security_note", "")).contains(SUSPICIOUS_MARK)

static func directive_matches(app: Dictionary, directive: Dictionary) -> bool:
	var change: Dictionary = directive.get("rule_change", {})
	var tag := String(change.get("match_tag", ""))
	if tag == "":
		return false
	var tags: Array = app.get("tags", [])
	return tags.has(tag)

static func _verdict(action: String, source: String, code: String, reason: String, error_type: String) -> Dictionary:
	return {
		"action": action,
		"source": source,
		"code": code,
		"reason": reason,
		"error_type": error_type,
	}

## 返回 {action, source, code, reason, error_type}
static func resolve(app: Dictionary, active_directives: Array) -> Dictionary:
	# 1) Captain 临时指令覆盖一切
	for directive in active_directives:
		if directive is Dictionary and directive_matches(app, directive):
			var change: Dictionary = directive.get("rule_change", {})
			return _verdict(
				String(change.get("action", ACTION_TRANSFER)),
				SOURCE_DIRECTIVE,
				String(directive.get("id", "")),
				String(change.get("summary", "Captain 临时指令")),
				String(change.get("error_type", ""))
			)
	# 2) 硬规则
	if not bool(app.get("signed", false)):
		return _verdict(ACTION_REJECT, SOURCE_HARD, "R1", "文书未签名", "unsigned")
	if is_weapon(app) and not bool(app.get("hos_prestamp", false)):
		return _verdict(ACTION_REJECT, SOURCE_HARD, "R2", "武器类许可缺少 HoS 预盖章", "missing_hos_stamp")
	if shows_suspicious_mark(app):
		return _verdict(ACTION_TRANSFER, SOURCE_HARD, "R3", "安全记录标注「可疑」", "suspicious_record")
	# 3) 预置判定（软线索：理由与职务是否相符、申请范围是否越权、记录细节是否对得上）
	return _verdict(
		String(app.get("ideal_action", ACTION_REJECT)),
		SOURCE_PRESET,
		"S1",
		"阅读判断：理由与职务是否相符、范围是否越权、记录细节是否对得上",
		String(app.get("error_type", ""))
	)

## 校验：所有申请按规则解析的结果必须与预置 ideal_action 一致（需求案 FR-05 验收：通过率 100%）。
static func validate(applications: Array, directives: Array) -> Array:
	var problems: Array = []
	for app in applications:
		if not app is Dictionary:
			continue
		var batch := int(app.get("batch", 0))
		var active: Array = []
		for directive in directives:
			if directive is Dictionary and int(directive.get("trigger_batch", -1)) <= batch:
				active.append(directive)
		var verdict := resolve(app, active)
		var expected := String(app.get("ideal_action", ""))
		var got := String(verdict.get("action", ""))
		if got != expected:
			problems.append(
				"%s（批次 %d）：规则解析=%s，预置 ideal_action=%s，来源=%s %s" % [
					String(app.get("id", "?")), batch, got, expected,
					String(verdict.get("source", "")), String(verdict.get("code", "")),
				]
			)
	return problems

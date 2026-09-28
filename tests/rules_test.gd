extends SceneTree
## 数据与判定规则自检。
## 运行：godot --headless --path . --script res://tests/rules_test.gd
## 退出码 0 = 全部通过，1 = 有失败项。

var _failures: Array[String] = []


func _initialize() -> void:
	var applications := DataStore.load_applications()
	var directives := DataStore.load_directives()
	var endings := DataStore.load_endings()
	var config := DataStore.load_config()

	print("=== 临时人事官 · 数据自检 ===")
	print("申请单 %d 份 / 临时指令 %d 条 / 事件 %d 个 / 结局 %d 档" % [
		applications.size(), directives.size(), DataStore.load_events().size(), endings.size(),
	])

	_check_ids(applications)
	_check_batches(applications, int(config.get("batches", 3)))
	_check_actions(applications)
	_check_endings(endings)
	_check_resolution(applications, directives)

	print("")
	if _failures.is_empty():
		print("全部检查通过。判定一致率 100%。")
		quit(0)
	else:
		print("失败项 %d：" % _failures.size())
		for item in _failures:
			print("  ✗ ", item)
		quit(1)


func _check_ids(applications: Array) -> void:
	var seen := {}
	for app in applications:
		var id := String(app.get("id", ""))
		if id == "":
			_failures.append("存在缺少 id 的申请单")
		elif seen.has(id):
			_failures.append("id 重复：%s" % id)
		seen[id] = true


func _check_batches(applications: Array, batches: int) -> void:
	var per_batch := {}
	for app in applications:
		var batch := int(app.get("batch", 0))
		per_batch[batch] = int(per_batch.get(batch, 0)) + 1
		if batch < 1 or batch > batches:
			_failures.append("%s 的 batch=%d 超出 1..%d" % [String(app.get("id", "?")), batch, batches])
	for index in range(1, batches + 1):
		if int(per_batch.get(index, 0)) == 0:
			_failures.append("批次 %d 没有任何申请单" % index)
	print("批次分布：", per_batch)


func _check_actions(applications: Array) -> void:
	for app in applications:
		var action := String(app.get("ideal_action", ""))
		if not [ShiftRules.ACTION_APPROVE, ShiftRules.ACTION_REJECT, ShiftRules.ACTION_TRANSFER].has(action):
			_failures.append("%s 的 ideal_action 非法：%s" % [String(app.get("id", "?")), action])


func _check_endings(endings: Array) -> void:
	if endings.is_empty():
		_failures.append("endings.json 为空")
	for value in [-5.0, 0.0, 5.0, 10.0, 40.0]:
		var ending := GameStateEndingProbe.pick(endings, value)
		if ending.is_empty():
			_failures.append("信任值 %.1f 没有匹配的结局档位" % value)
		else:
			print("信任值 %5.1f → %s" % [value, String(ending.get("title", "?"))])


func _check_resolution(applications: Array, directives: Array) -> void:
	var problems := ShiftRules.validate(applications, directives)
	if problems.is_empty():
		print("判定一致性：%d / %d 通过" % [applications.size(), applications.size()])
	else:
		for problem in problems:
			_failures.append(problem)


## 结算档位匹配探针（避免依赖 Autoload）。
class GameStateEndingProbe:
	static func pick(endings: Array, value: float) -> Dictionary:
		for ending in endings:
			if not ending is Dictionary:
				continue
			if value >= float(ending.get("min_trust", -9999.0)) and value <= float(ending.get("max_trust", 9999.0)):
				return ending
		return {}

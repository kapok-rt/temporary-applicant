extends Node
## 开发工具（与游戏逻辑无关，可直接删除本节点）。
##
## 用法（注意 -- 之后是传给游戏的参数）：
##   godot --path . -- --shot=intro
##   godot --path . -- --shot=review --dev-start
##   godot --path . -- --shot=settle --dev-start --dev-auto=99
##
## 参数：
##   --shot=名字        第 N 帧后截图到 res://screenshots/名字.png，然后退出
##   --shot-frames=N    截图前的等待帧数（默认 45）
##   --dev-start        跳过开场，直接开始值班
##   --dev-auto=N       自动作答 N 次（用于快速跑到结算界面）
##   --dev-wrong=N      前 N 次故意错判（用于触发事件卡）
##   --dev-stop         遇到弹窗就停下（配合 --shot 截图弹窗）
##   --dev-trace        把每一步裁定 / 批次 / 事件打印到终端（无需 --shot）

const SHOT_DIR := "res://screenshots"

var _shot_name := ""
var _frames := 45
var _dev_start := false
var _dev_auto := 0
var _dev_wrong := 0
var _dev_stop := false
var _dev_trace := false
var _elapsed := 0
var _done := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_name = arg.substr("--shot=".length())
		elif arg.begins_with("--shot-frames="):
			_frames = int(arg.substr("--shot-frames=".length()))
		elif arg == "--dev-start":
			_dev_start = true
		elif arg.begins_with("--dev-auto="):
			_dev_auto = int(arg.substr("--dev-auto=".length()))
		elif arg.begins_with("--dev-wrong="):
			_dev_wrong = int(arg.substr("--dev-wrong=".length()))
		elif arg == "--dev-stop":
			_dev_stop = true
		elif arg == "--dev-trace":
			_dev_trace = true
	if _dev_trace:
		GameState.note.connect(_trace_note)
	if _shot_name == "" and not _dev_start and _dev_auto <= 0:
		set_process(false)

func _process(_delta: float) -> void:
	if _done:
		return
	_elapsed += 1
	var target := _frames
	if _dev_start or _dev_auto > 0:
		target = _frames + 30
	if _elapsed == 20 and (_dev_start or _dev_auto > 0):
		var main := get_parent()
		if main != null and main.has_method("dev_auto_play"):
			main.call("dev_auto_play", _dev_auto, _dev_wrong, _dev_stop)
		if _dev_trace:
			_trace_summary()
	if _elapsed < target:
		return
	_done = true
	if _shot_name != "":
		await _capture(_shot_name)
	get_tree().quit(0)

func _trace_note(tag: String, text: String, kind: String) -> void:
	print("    [%s] %s" % [tag, text])


func _trace_summary() -> void:
	var stats: Dictionary = GameState.stats
	var handled := int(stats.get("handled", 0))
	print("")
	print("--- 自动推进结束 ---")
	print("批次 %d/%d · 印章 %d/%d · 等待槽 %d/%d · 信任值 %s" % [
		GameState.batch, GameState.batch_count(),
		GameState.stamp_left, GameState.stamp_durability(),
		GameState.wait_slots_used, GameState.wait_slots_total(),
		_signed(GameState.trust),
	])
	print("统计：处理 %d/%d · 正确 %d · 偏差 %d · 批准 %d · 驳回 %d · 转交 %d" % [
		handled, GameState.applications.size(),
		int(stats.get("correct", 0)), int(stats.get("wrong", 0)),
		int(stats.get("approve", 0)), int(stats.get("reject", 0)), int(stats.get("transfer", 0)),
	])
	if handled >= GameState.applications.size():
		print("结局档位：%s" % String(GameState.pick_ending(GameState.trust).get("title", "?")))
	if not GameState.error_counts.is_empty():
		print("错判归类：", GameState.error_counts)
	print("已触发事件：%d 张" % GameState.fired_events().size())


func _signed(value: float) -> String:
	var prefix := "+" if value >= 0.0 else "-"
	return "%s%.1f" % [prefix, absf(value)]


func _capture(shot_name: String) -> void:
	# 必须等到本帧绘制完成，否则拿到的是空纹理。
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dir := DirAccess.open("res://")
	if dir != null and not dir.dir_exists("screenshots"):
		dir.make_dir_recursive("screenshots")
	var path := "%s/%s.png" % [SHOT_DIR, shot_name]
	var err := image.save_png(path)
	if err != OK:
		printerr("[DevShot] 截图失败：%s (%d)" % [path, err])
	else:
		print("[DevShot] 已保存 ", ProjectSettings.globalize_path(path))

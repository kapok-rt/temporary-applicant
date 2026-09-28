class_name Palette
extends RefCounted
## SS13 终端配色。做丑即对。

const BG := Color(0.043, 0.051, 0.063)
const PANEL := Color(0.063, 0.078, 0.094)
const TEXT := Color(0.784, 0.843, 0.871)
const MUTED := Color(0.435, 0.486, 0.514)
const DIM := Color(0.278, 0.318, 0.349)
const OK := Color(0.482, 0.847, 0.561)
const WARN := Color(0.878, 0.702, 0.290)
const BAD := Color(0.878, 0.424, 0.353)
const ACCENT := Color(0.561, 0.839, 0.753)
const LINK := Color(0.549, 0.749, 0.898)

static func hex(color: Color) -> String:
	return "#" + color.to_html(false)

## 近似显示宽度：全角字符按 2 列计算，用于等宽对齐。
static func display_width(text: String) -> int:
	var width := 0
	for index in text.length():
		width += 2 if is_wide(text.unicode_at(index)) else 1
	return width

static func is_wide(code: int) -> bool:
	if code >= 0x1100 and code <= 0x115F:
		return true
	if code >= 0x2E80 and code <= 0xA4CF:
		return true
	if code >= 0xAC00 and code <= 0xD7A3:
		return true
	if code >= 0xF900 and code <= 0xFAFF:
		return true
	if code >= 0xFE30 and code <= 0xFE6F:
		return true
	if code >= 0xFF00 and code <= 0xFF60:
		return true
	if code >= 0xFFE0 and code <= 0xFFE6:
		return true
	return false

static func pad(text: String, width: int) -> String:
	var gap := width - display_width(text)
	if gap <= 0:
		return text
	return text + " ".repeat(gap)

## 按部门给立绘色块取色。
static func dept_color(role: String) -> Color:
	if role.contains("医疗"):
		return Color(0.298, 0.702, 0.478)
	if role.contains("安全"):
		return Color(0.749, 0.325, 0.286)
	if role.contains("工程"):
		return Color(0.784, 0.62, 0.267)
	if role.contains("科研"):
		return Color(0.353, 0.663, 0.769)
	if role.contains("服务"):
		return Color(0.643, 0.443, 0.749)
	if role.contains("供应"):
		return Color(0.416, 0.522, 0.741)
	if role.contains("指挥"):
		return Color(0.745, 0.745, 0.702)
	if role.contains("D 级") or role.contains("D级"):
		return Color(0.475, 0.475, 0.475)
	if role.contains("情报"):
		return Color(0.706, 0.573, 0.353)
	return Color(0.51, 0.561, 0.588)

# 临时人事官 / Temporary Applicant

> a gamejam entry.

SS13 背景的文书审查解谜原型。你是被中央 AI 临时指派的 HOP（人事官），
在值班倒计时内审核一批临时文书，每一次批准 / 驳回 / 转交都会以事件卡的形式
落到空间站上。

- 引擎：**Godot 4.7.2**（Compatibility 渲染，便于 Web 导出）
- 单局：3 批 × 6 份 = 18 份申请，8 分钟（或 15 分钟宽松模式）
- 纯 UI，无移动 / 无战斗 / 无模拟
- 全部内容走 JSON，改文案不用改代码

---

## 一、跑起来

直接用 Godot 打开本目录（`project.godot`），按 F5。

命令行（Windows，Godot 换成你自己的路径）：

```powershell
& "C:\路径\Godot_v4.7.2-stable_win64_console.exe" --path "C:\temporary applicant"
```

第一次跑之前如果报 `Identifier "DataStore" not declared`，说明全局类缓存还没生成，
先执行一次导入：

```powershell
& "C:\路径\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\temporary applicant" --import
```

---

## 二、界面（对应本次交付要求）

```
┌───────────────────────────────────────────────────────────────┐
│ 顶部：倒计时 · 批次 · 印章耐久 · 等待槽 · 信任值               │
├───────────────────────────────┬───────────────────────────────┤
│ ▌ 橱窗 · 文书原件              │ ▌ 审核规则 · 本周期有效        │
│   文书类型 / 编号 / 申请人 /    │   R1 R2 R3 硬规则             │
│   职务 / 签名 / 部门章 /        │   Captain 临时指令（覆盖）     │
│   请求事项 / 申请理由 / 安全记录 │   软线索提示 / 操作说明        │
│   （「可疑」标注琥珀色高亮）    ├───────────────────────────────┤
├───────────────────────────────┤ ▌ 值班日志                    │
│ ▌ 柜台 · 当前申请人            │   裁定结果 / 回执 / 事件摘要   │
│   部门色块立绘 + 姓名职务状态   ├───────────────────────────────┤
│   等待槽 [■][■][□]  在队回执    │ ▌ 审核按钮                    │
│                               │   批准 / 驳回 / 转交 Captain   │
└───────────────────────────────┴───────────────────────────────┘
```

- **左边**是橱窗（申请人递交的文书原件）和柜台（申请人 + 等待槽）。
- **右边**是审核规则和审核按钮，裁定结果回显在按钮下方。
- 角色立绘用部门配色的纯色块 + 姓名首字，符合"纯色块 + 等宽字体"的美术方向。

截图在 `screenshots/`：`intro` 开场、`review` 审核中、`directive` Captain 临时指令、
`events` 事件卡、`settle` 结算。

---

## 三、目录

```
project.godot            主场景 / Autoload / 主题 / 窗口设置
scenes/Main.tscn         主场景骨架（左橱窗+柜台、右规则+按钮）
scripts/
  main.gd                状态机 + 界面接线 + 弹窗
  game_state.gd          Autoload：运行时状态、资源、事件、结算
  shift_rules.gd         判定核心（指令 > 硬规则 > 阅读判断）
  data_store.gd          JSON 读取
  dev_screenshot.gd      开发工具（截图 / 自动跑），可整个删掉
  ui/                    palette / document_view / counter_view / rules_view / log_view
data/                    applications · directives · events · endings · rules · config
docs/临时权限申请文书_样例.md   交付要求之二：文书样例 + 空白模板 + 字段对照
tests/rules_test.gd      数据与判定自检
theme/ui_theme.tres      终端配色主题（系统字体，含中文字形回退）
```

---

## 四、改内容：加一份申请

只要往 `data/applications.json` 的数组里加一条，什么都不用改：

```json
{
  "id": "A-107", "batch": 1,
  "doc_type": "临时权限申请书", "form_no": "NT-HOP-0120",
  "applicant": "Nia Pell", "role": "工程部 · 电工",
  "request": "申请开通配电间临时权限，有效期至本周期结束。",
  "reason": "本班次配电间三次跳闸，需要现场排查。",
  "signed": true, "dept_stamp": "工程部 · CE 章（清晰）",
  "security_note": "在册 6 年，无违规记录。",
  "ideal_action": "approve", "error_type": "", "tags": ["常规"]
}
```

改完跑一次自检，确认规则和预置判定没打架：

```powershell
& "C:\路径\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\temporary applicant" --script res://tests/rules_test.gd
```

自检会检查：id 唯一、批次分布、ideal_action 合法、结局档位无空洞、
以及 **每一条申请的规则解析结果是否等于 ideal_action**（当前 18/18 通过）。

### 判定优先级（`scripts/shift_rules.gd`）

1. **Captain 临时指令**：按 `tags` 命中 `match_tag` 就改判，覆盖下面所有规则。
2. **硬规则 R1**：未签名 → 驳回。
3. **硬规则 R2**：`tags` 含"武器"且没有 `hos_prestamp` → 驳回。
4. **硬规则 R3**：`security_note` 含"可疑" → 转交 Captain。
5. **阅读判断**：其余按 `ideal_action` 走，也就是靠软线索读出来的结论。

### 其余数据文件

- `directives.json`：`trigger_batch` 指定在第几批前弹窗，`rule_change` 指定改判口径。
- `events.json`：`trigger_error_type` + `min_count`，错判次数够了就弹事件卡，同一条只弹一次；
  用 `__total__` 可以统计错判总数。
- `endings.json`：按 `min_trust` / `max_trust` 分档，当前 4 档。

---

## 五、调参（`data/config.json`）

| 键 | 当前值 | 说明 |
|---|---|---|
| `shift_seconds` | 480 | 标准值班 8:00 |
| `relaxed_seconds` | 900 | 开场界面第二个按钮，15:00 |
| `batches` | 3 | 批次数 |
| `stamp_durability` | 15 | 印章耐久，批准 -1 |
| `wait_slots` | 3 | 等待槽数量，转交占 1 |
| `transfer_delay_batches` | 1 | 转交后几批返回回执 |
| `trust_correct` / `trust_wrong` / `trust_transfer_correct` | 1 / -1 / 0.5 | 信任值增减 |

> **一处需要你知道的取舍**：需求案给的印章耐久是 15（对应 20–25 份申请的内容量）。
> 当前原型的 18 份里有 5 份应当批准，印章只会掉到 10，**不会真正卡住手**。
> 想让印章变成硬约束，把 `stamp_durability` 改成 6 左右就会立刻有感；
> 或者按策划案把申请扩到 20–25 份。

---

## 六、开发工具

`scripts/dev_screenshot.gd` 挂在主场景的 DevShot 节点上，不需要时直接删掉。
`--` 之后的参数才会传给游戏：

```powershell
# 开场界面截图
& $godot --path . -- --shot=intro

# 跳过开场，直接进审核界面
& $godot --path . -- --shot=review --dev-start

# 自动按正确裁定跑完整局，停在结算界面
& $godot --path . -- --shot=settle --dev-start --dev-auto=25

# 前 4 次故意错判，遇到弹窗就停下（用来截事件卡）
& $godot --path . -- --shot=events --dev-start --dev-auto=12 --dev-wrong=4 --dev-stop
```

截图输出到 `screenshots/<名字>.png`。

### 终端冒烟测试（不需要开窗口）

加 `--dev-trace` 会把每一步裁定 / 批次 / 指令 / 事件打到 stdout，并在自动推进结束后
打印小结，可以直接拿来验证状态机：

```powershell
# 什么都不做，只看开局状态
& $godot --headless --path . -- --dev-start --dev-trace

# 走完第一批 6 份，看批次切换和转交回执
& $godot --headless --path . -- --dev-start --dev-auto=6 --dev-trace

# 全部答对 → 看能否走到结算与结局档位
& $godot --headless --path . -- --dev-start --dev-auto=18 --dev-trace

# 全错 18 次 → 看事件卡连锁与「终止」结局
& $godot --headless --path . -- --dev-start --dev-auto=18 --dev-wrong=18 --dev-trace
```

`--dev-wrong=N` 会轮流使用「错判批准 / 错判驳回 / 错判转交」三种错法，并自动跳过
资源不足的选项（比如印章耗尽时就无法再错判批准），所以顺带验证了按钮禁用逻辑。

---

## 七、需求案覆盖情况

| 编号 | 需求 | 状态 |
|---|---|---|
| FR-01 | 开场与初始化 | ✅ 开场弹窗 + 开始值班，状态完全重置 |
| FR-02 | 值班循环 | ✅ 倒计时 / 3 批 / 每批 6 份 / 批间指令与事件检查 |
| FR-03 | 申请单展示 | ✅ 7 个字段全部展示，缺失显示"无"；当前 18 份（目标 20–25，加 JSON 即可） |
| FR-04 | 玩家操作与资源 | ✅ 批准 / 驳回 / 转交；印章、等待槽、按钮禁用均已实现 |
| FR-05 | 判定与规则 | ✅ 指令 > 硬规则 > 阅读判断；自检 18/18 通过 |
| FR-06 | Captain 临时指令 | ✅ 第 2、3 批前弹窗，规则面板同步更新，判定随之变化 |
| FR-07 | 事件与信任值 | ✅ +1 / -1 / +0.5；按 error_type 累计触发，9 张事件卡不重复 |
| FR-08 | 结算与结局 | ✅ 4 档结局 + 值班报告 + 事件列表 + 重开 |
| FR-09 | 数据配置 | ✅ 6 个 JSON 全驱动，加内容不改代码 |
| FR-10 | 反馈与音效 | ⚠️ 按钮悬停 / 按下 / 禁用有样式反馈；**音效未做** |
| FR-11 | 暂停 / 重开 | ⚠️ 结算可重开；**ESC 暂停未做** |
| FR-12 | AI 提示侧栏 | ❌ 未做（右侧目前是规则面板 + 值班日志） |
| FR-13 / 14 | 设置 / 成就 | ❌ 未做 |

非功能项：纯鼠标可完成全部操作 ✅、深色等宽终端风 ✅、逻辑与数据分离 ✅、无网络依赖 ✅。

---

## 八、Web 导出注意

项目已把渲染方式设为 `gl_compatibility`（Web 平台只支持这个）。

**但系统字体在浏览器里拿不到**，中文会变成方块。导出 Web 前把一个中文字体丢进
`res://theme/fonts/`（`main.gd` 会自动把它设为主题默认字体，无需改代码）：

```
theme/fonts/NotoSansSC-Regular.ttf
```

字体记得确认授权（Noto 系列是 OFL，可以随包分发）。

---

## 九、下一步可以做的

1. 把申请补到 20–25 份，顺便把印章耐久调紧。
2. 音效：一个环境循环 + 批准 / 驳回 / 事件卡三个音。
3. ESC 暂停面板（复用现有的弹窗构建函数即可）。
4. 右侧加一条 AI 提示栏，部分提示故意给错——这块是策划案里"重复感"的主要解药。
5. 结局文本目前是每档一段，可以按触发的事件卡组合出变体。

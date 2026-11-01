# UI 问题清单与交接提示词（2026-10-30）

> 用途：把当前「相机手势展陈」界面的 4 个问题梳理清楚，供队友接手。
> 阅读顺序：先 `CODE_HANDOFF.md`，再本文件。

## 0. 当前状态

| 项 | 值 |
|---|---|
| 分支 | `codex/gesture/vertical-roi-20261029` |
| 最新 bit | `phase6_gallery/build/gesture_full/museum_phase6_gallery.bit`，SHA256 `efcfa87c…7b0`，17:43 生成 |
| 时序 | 已签核 PASS：`PASS ORIGINAL-SDC SIGNOFF … SWNS +0.167ns / HWNS +0.042ns` |
| 屏幕叠加实现 | `camera/rtl/camera_pose_overlay.v`（参数 `INTEGRATED_STYLE=1, SWIPE_MODE=1, MIRROR_X=1`） |

关键信号/导线（便于定位）：
- `KEY4` → `toggle_view` → `inspect_view` 取反；`calibration_mode = gesture_enabled && (!background_ready || inspect_view)`（`camera_gesture_engine.v:106`）
- `SW1`=时钟、`SW2`=preview_enable、`SW3`=gesture_enable、`SW4`=会场（`museum_phase6_unified_top.v`）
- `fault = source_fault || overflow`（`camera_gesture_engine.v:107`）
- `source_fault = fault_sync[1] || read_fault`（`camera_source_stream.v:37`，源流缓冲写/读错误）
- `overflow` = 导航事件队列溢出（`camera_nav_adapter.v`）

---

## 1. 问题清单（4 条）

### 问题 1 —— 摄像头画面内容错：KEY4 前后视图顺序反了
- **用户要求**：不按 KEY4 时 = 普通视频（接近人眼所见）；按 KEY4 后才是"黑绿"（诊断/前景）视图。
- **现状**：`calibration_mode` 由 `!background_ready || inspect_view` 决定，KEY4 只是其中一个触发。背景没就绪时也会进"黑绿"（mask 绿 `24'h90d0a0` / 近黑 `24'h101820`）。普通模式的"视频"来自 `preview_color`（RGB332 8bit，发暗）或近黑占位 `24'h101820`。
- **待办**：理顺「普通视频」与「KEY4 黑绿诊断」两种视图的显示优先级，达到"默认普通视频、KEY4 才黑绿"。

### 问题 2 —— 整块黑框要上移，现在遮挡主内容
- **用户要求**：黑框整体上移、不遮挡；**先画 2–3 张排版图，用户确认"合适"后再改码**。
- **现状**：`camera_pose_overlay.v` 里多处暗色/框（近黑占位 `24'h101820`，框线 `304860`/`405b43`/`b0d8e8` 等）：
  - 校准大窗 `x160..480 / y160..400`
  - 小窗 `x464..624 / y344..464`
  - 集成态顶部窗 `x456..616 / y20..152`（内 `x472..600 / y48..144`）
- **待办**：确认"黑框"具体是哪个矩形 → 出排版图 → 定上移目标坐标。

### 问题 3 —— 一直显示"摄像头异常"
- **现象**：故障提示常亮。RTL 文案是英文 `STREAM FAULT - RESET BOARD`（TEXT 第 4 行，`panel_ink` 红色 `24'hff8080`）。
- **对应关系**：
  - 屏上"异常" = overlay 的 `fault` 输入 = 引擎 `source_fault || overflow`
  - `source_fault` = 相机源流缓冲写/读错误（`camera_source_stream.v:37`）
  - `overflow` = 导航事件队列溢出（`camera_nav_adapter.v`）
- **定位方法**：串口 `K` 位2=fault、位1=overflow（或 LED 最高位 = fault）。看两位谁为 1，区分是"相机源流故障"还是"导航溢出"，再进对应模块修根因。
- **待办**：抓一组串口定位 → 修根因 → （文案中文化见问题 4）。不要直接消掉提示。

### 问题 4 —— 底部手势动作提示必须中文 + 排版问题
- **现状**：提示文字在 `camera_pose_overlay.v` 的 `TEXT` 常量（`SWIPE_MODE` 分支，约 683–699 行），是英文短句，例如：
  - `CENTER HAND - HOLD STILL TO ARM`
  - `ARMED - SWIPE WHOLE HAND`
  - `LEFT RIGHT SELECT - UP BACK - DOWN ENTER`
  - 字形函数只有 `A-Z / 0-9 / -`（约 90–109 行），无中文字模。
- **用户要求**：动作提示**必须是中文**，且排版有问题。
- **待办**：换中文文案 + 中文字库（可复用 `rtl/museum_phase5_font.v` 或 `camera/rtl/museum_phase6_font_compact.v` 的 hex 方案），重排提示区（当前 `y<16` 顶部状态行 + `y16..48` 提示行 + 校准区 `64..160` 分区）。

---

## 2. 交接提示词（可直接复制粘贴给队友 AI）

```
你是 Phase6 相机手势展陈（Anlogic EG4S20）的接续开发助手。
先读 phase6_gallery/camera/CODE_HANDOFF.md，再读本文件 UI_ISSUES_HANDOFF_20261030.md。

当前分支 codex/gesture/vertical-roi-20261029。屏幕叠加全部在
camera/rtl/camera_pose_overlay.v（INTEGRATED_STYLE=1, SWIPE_MODE=1, MIRROR_X=1）。
当前 bit museum_phase6_gallery.bit（SHA256 efcfa87c…）已时序签核 PASS（SWNS +0.167ns）。

要处理 4 个问题（见上文问题 1–4）。请先规格后编码：

【确认门，必须遵守】先出整体方案：把 4 个问题各自要改哪一行、改成什么逐条列出，
问题 2 必须附 2–3 张 ASCII 排版图。整体方案发给用户确认，每一项逻辑更改都要用户
逐一确认；全部确认后，再询问"是否可以开始改码"，得到明确确认后才动手。
开始改码后，一路到 bit 生成前无需再逐项询问。

1. 问题 2 必须先画 2–3 张 ASCII 排版图（黑框位置、状态字位置、视频窗位置、
   四向提示位置逐张标注坐标），发用户确认"合适"后再改 RTL。
2. 问题 4 的提示必须是中文；先给出中文文案清单和排版方案，经确认再改。
3. 问题 3 先定位 fault 是 source_fault 还是 overflow（串口 K 位2/位1，或 LED 最高位），
   再修根因，不要直接把提示消掉或写死。
4. 问题 1 把"普通视频"与"KEY4 黑绿诊断"两种视图的显示优先级按用户要求理顺。

行为约束：
- 改动集中在 camera_pose_overlay.v，必要时 museum_phase6_unified_top.v 或
  camera_gesture_engine.v；deps/ 保持原样。
- 每次改动跑 camera/sim/ 相关 testbench（run_full_baseline_overlay.do 等）。
- 改完用本机 TD 重新综合 + 时序签核（允许；失败则修复后继续编译），出 bit 后
  交用户上板实测，不擅自 JTAG/烧 Flash。
- 中文、bit 命名、资源/时序回执记录到 phase6_gallery/camera/PROGRESS.md。
- 禁止强推、禁止删除分支。

验收：4 条问题逐条回执——改了什么文件/行、仿真结果、时序结果、是否上板。
```

---

## 3. 文件索引（本文档涉及）

| 文件 | 作用 |
|---|---|
| `camera/rtl/camera_pose_overlay.v` | 屏幕叠加（视频/黑框/状态字/动作提示）—— 4 个问题主战场 |
| `camera/rtl/camera_gesture_engine.v` | 手势引擎：KEY4→inspect_view、fault 汇总、overlay 接线 |
| `camera/rtl/museum_phase6_unified_top.v` | 集成顶层：SW1–SW4、按键路由 |
| `camera/rtl/camera_source_stream.v` | 相机源流；`source_fault` 来源（问题 3） |
| `camera/rtl/camera_nav_adapter.v` | 导航事件队列；`overflow` 来源（问题 3） |
| `camera/rtl/museum_phase6_font_compact.v` / `rtl/museum_phase5_font.v` | 可复用的中文字库（问题 4） |
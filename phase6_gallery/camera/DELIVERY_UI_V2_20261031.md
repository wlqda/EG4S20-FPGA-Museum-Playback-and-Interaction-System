# 博物馆手势交互 UI V2 — 2026-10-31 实板验收交付版

## 交付内容
`museum_gesture_ui_v2.bit` 为 EG4S20BG256 当前完整工程生成的 bit。未执行 JTAG 下载或 Flash 固化；尚未完成实板验收。

四项修改：默认 RGB 摄像头画面、KEY4 切换诊断；右上角 128×112 ROI 预览与下方中文提示；故障和无画面等状态分别处理；各页面中文操作提示。预览位置 x=[504,632)、y=[8,120)，状态行 y=124..139，保持原页面主体布局。视频来自中心 ROI（x=64..575、y=16..463），不是完整传感器视野。

额外修复：准备/重新标定时持续读取 FIFO 并保留视频预览，避免生产端持续写入而消费端暂停导致溢出。旧代码相同激励可复现故障，新代码通过。回中后需连续 5 帧稳定，并检查步长及整体位移，再以最后稳定位置建立滑动起点。触边/动作完成后提示“请向中央收手”，回中稳定后显示“可以滑动了”。极慢且低于阈值的移动仍可能被视为稳定，真实光照和人体动作需实测。

## 验证结果
- 32 组 ModelSim 回归全部通过，日志及哈希见 evidence/TEST_RESULTS.json。
- 29 个显示场景、8,908,800 个 RGB 像素校验通过，包括 ROI、页面主体保持、模式切换和故障状态。
- 完整数据源、FILTER5、提取器集成准备流程通过；SW3 启用和重复 KEY2 准备期间持续输出预览，无 FIFO 故障。
- TD 综合、布局布线、bit 生成、独立时序签核完成。Setup WNS +0.167 ns，Hold WNS +0.076 ns，覆盖率 99.95%。
- 布局后资源：LUT 17013/19600、REG 10842/19600、BRAM9K 59/64、BRAM32K 16/16、DSP 15/29。
- 编译输入哈希与交付源码逐项一致；算法基线审计记录见 evidence/FULL_FEATURE_AUDIT.json。

限制：TD 仍报告历史约束 `get_regs key_modes/sync1*` 未匹配导致对应 false_path 无效。当前时序报告在现有约束下通过，不代表已完成全部 CDC 或电气验证。已修复可复现的准备期 FIFO 溢出，不能据此排除实机摄像头接线、供电、时钟或其他故障。

## 文件使用
bit SHA256: `F1B1AFF2295376E136B98C0DE708C27FF3870AC7FB49EB20BB3DD41E5942BE7D`

source/ 保存本次源码快照；evidence/ 保存当前报告和回归日志；evidence/before/ 仅保存旧代码故障复现日志，其中失败是预期对照；previews/ 是 RTL 仿真真实输出，摄像头输入是合成测试图案，并非实板照片。飘动时间是已有 SW1 功能。

沿用现有配套 TF 卡资源。verification_materials/TF_CARD 仅含四段音频测试素材，不是完整可启动 TF 卡镜像。不要用该测试目录替换现有卡内容。

## 复现
需要 Python 3 + Pillow、ModelSim（本次 18.1）、Anlogic TD（本次本机安装版，布局 seed 43）。在 source/ 下运行，下列工具路径按本机安装调整。所有输出生成在 source/phase6_gallery/build/。

```powershell
python -B phase6_gallery/camera/tools/prepare_verification.py --materials ../verification_materials
python -B phase6_gallery/camera/tools/audit_full_camera.py
python -B phase6_gallery/camera/tools/run_unified_tests.py --vsim F:/intelFPGA_lite/18.1/modelsim_ase/win32aloem/vsim.exe --previews
python -B phase6_gallery/camera/tools/prepare_unified_project.py
python -B phase6_gallery/camera/tools/build_full.py --td D:/anlogic/bin/td_commands_prompt.exe
```

重新生成项目可更新 .al 中的本机路径。工具版本/路径变化可能使重新生成 bit 的二进制哈希不同，需重新核对报告。当前交付 bit 对应 evidence/BUILD_INPUTS.json 所列原始输入。

## 上板验收步骤
使用现有硬件与 TF 卡加载 bit 后，检查首页、列表、设置和讲解页；启用 SW3 后移开手完成背景准备；重复 KEY2 准备应始终有画面且不出现数据故障。KEY4 检查 RGB/诊断切换。四方向滑动每次仅触发一次，触边后回中稳定再滑动；检查快速回穿、慢速回中和握手停留。最后验证展品切换、音频暂停继续、亮度音量、视频与自动轮播。记录实测光照、距离和异常提示后再决定固化。

# SW1、无操作返回与首页选中框更新

基于队友提交 `cc24cec0c350e84f9fe5ad0ab6e11ccc60a6f769`，工作分支
`codex/integration/test-teammate-20261028`。本次按用户要求由集成侧修改。

## 使用行为

- SW1 开启显示浮动时间，关闭隐藏。消抖后在场消隐时应用，隐藏期间继续计时，再开启不会重置时间。
- SW3 开启手势模式时，禁用无操作自动返回轮播；关闭后从零开始计满 40 秒。
- 按键模式原来 20 秒的无操作返回改为 40 秒，操作会重新计时。原有讲解页不自动返回的行为保留。
- SW2 继续控制摄像头小窗，SW4 继续控制轮播。
- 首页三个选中框按用户照片对应的参考背景对齐。边界采用半开区间：
  `[27,217) × [165,412)`、`[227,413) × [165,412)`、`[423,615) × [165,412)`，线宽 2 像素。

SW1 接线经本机板卡原理图核对：`6_EX_DEVICE.pdf` 中 SW1 / SW_1 经 RN38
接 SWKEY_1，`2_FPGA.pdf` 中 SWKEY_1 对应 C8。使用与其他拨码开关一致的
LVCMOS33/PULLDOWN、双级同步及 20 ms 消抖；只增加引脚到同步器的异步时序例外。

## 背景资源

用户照片对应本机原有 `anlogic-phase6-current/phase6_gallery/assets/ui_reference/pages/IMG00005.png`，
已将相同字节保存在本工程 `assets/ui_reference/pages/IMG00005.png` 作为对齐验证输入。
这张图片与交接包原 V3 首页不同，不能用旧首页验证新边框。
本次不需要更换用户当前照片所示 TF 首页。未重新写入 TF 卡。
其他页面、音轨、照片和视频没有在本次修改中重新生成。

## 重现验证

在仓库根目录运行：

```powershell
python -B phase6_gallery/camera/tools/prepare_verification.py --materials .
python -B phase6_gallery/camera/tools/audit_full_camera.py
python -B phase6_gallery/camera/tools/run_unified_tests.py --vsim F:/intelFPGA_lite/18.1/modelsim_ase/win32aloem/vsim.exe --previews
python -B phase6_gallery/camera/tools/prepare_unified_project.py
python -B phase6_gallery/camera/tools/build_full.py --td D:/anlogic/bin/td_commands_prompt.exe --seed 44
```

回归入口增加 `run_idle_policy` 与 `run_home_alignment`：26 组回归加 1 组完整预览。
前者验证实际默认 40 秒、手势模式长时间停留、关闭后的完整 40 秒、到期等待消隐时
开启手势的取消行为和操作重计时；后者验证三个焦点共 921,600 个像素，边框以外保持背景原样。
浮动时钟测试增加场消隐切换、隐藏期间持续计时与底图透传。
开关测试覆盖 SW1～SW4 接线、独立控制与短暂抖动。
历史渲染参考文件保持原样，流水线测试仅为有意更改的首页边框指定当前几何期望。

新结果位于 `build/gesture_full/`，实际运行结果以 `TEST_RESULTS.json`、`final.ts`、
`final.area`、`signoff.log` 与 `BOARD_DOWNLOAD_RESULT.json` 为准。
`home_focus_0.png`～`home_focus_2.png` 是 RTL 仿真效果，不是实板照片。
新发布摘要保存为 `build/gesture_full/RELEASE_MANIFEST.json`。

## 基线保留与验收

上一次成功 SRAM 下载的原始编译目录已完整保存在
`build/baseline_cc24cec_20261028/`，原 bit SHA256：
`cb59b39ad1cc8490822620dd486bd3e233134715baf8e8dde8bab066915efb15`。
本次新 bit 与旧 bit 分别保存；未删除文件。

实板请检查 SW1 显隐、SW3 开启后停留超过 40 秒、关闭后的 40 秒返回，以及三个首页
焦点的四边对齐。TD 时序与 SRAM 下载成功不代替这些实板功能反馈。

## 本机执行结果

2026-10-28：27 项 ModelSim 验证全部通过；14 个识别核心文件与原始基线逐字节一致。
seed43 在 hold 修复后的增量布线阶段发生 PHY-8023 / RUN-8102，日志保存在
`build/gesture_full/physical_seed43_failed.log`。保持源码和时序要求，使用同一综合数据库
以 seed44 重做布局布线，完成独立原始 SDC 签核与 bit 生成。

- 时序：8 个时钟、STA 覆盖率 99.95%，SWNS +0.502 ns、HWNS +0.041 ns，STNS/HTNS 为 0。
- 最终资源：LUT 16881/19600，寄存器 10555/19600，9K RAM 56/64，32K RAM 16/16，DSP 15/29。
- 2026-10-28 18:57，JTAG 检测到 EG4S20BG256 并完成 SRAM 下载。
- 新 bit SHA256：`174fcaa567a071fe3bcefd7583d02fa270b19a77bc04d011f1e8335534adb790`。
- 未写 Flash，实板功能效果等待用户反馈。

签核日志仍存在上一版已有的 `key_modes/sync1*` 寄存器选择器未匹配告警，导致这一条
按键异步入口 false-path 未应用；上一版日志也包含相同告警。本次没有扩大时序例外来
掩盖该告警，也没有将结果描述为零告警。SW1 新增约束未出现未匹配告警。
最终报告和关键验证日志归档在 `integration_validation/controls_20261028/`。

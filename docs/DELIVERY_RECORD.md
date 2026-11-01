# 加宽小窗口流动文字版（约25像素／秒）

基于43A60B9A…D43D3B48小窗口流动文字版，仅加宽文字视窗并调整内部滚动速度，底层沿用B429C314故障修复版。显示文字保持：

**基于安路EG4S20的FPGA博物馆播放与交互系统**

外框195×32像素、透明文字视窗179×24像素（128×1.4=179.2，取最近整数179），字模高24像素。中文24像素宽，英文/数字12像素宽。黑色文字、透明背景。使用帧相位累加器，每60个显示帧向左滚动25像素（约25像素／秒），句首停留60帧（60Hz下约1秒）；句尾留24像素空隙后循环。整句480列，含空隙循环504列。

保留原外框初始位置(173,107)、每3帧移动1像素、原垂直反弹边界；右侧水平边界调整为x=445，适应加宽后的外框、SW1显隐。显示开关在消隐期发布。关闭时运动仍继续，与原时间层保持一致。画面层级保持原状，进入ROI覆盖范围时仍遵循既有叠加顺序，不增加避让或其他界面调整。

原时间层使用七段数字，现改为固定点阵字模。全部字模列数据随源码保存，编译及仿真不依赖开发机字体。保留原模块接口及兼容参数；参数INITIAL_HOUR/MINUTE/SECOND对新文字显示不再生效。

## 修改边界

本次功能源码仅修改rtl/museum_floating_clock.v的视窗宽度、相应水平边界及内部滚动相位；原museum_slide_switch模块逐字保持。手势、四角框、图像流准备故障修复、按键、声音、亮度、视频、资源素材和其他界面保持基准版。新增文字字模资产和专项测试文件；museum_phase6_unified.al仅更新本机路径。所有原编译输入对照见evidence/CHANGES_FROM_PREVIOUS_TEXT.json。

## 实际验证

与调整过水平边界的旧时间层比较外框运动、方向和SW1显隐；逐帧验证600帧内250像素位移、60帧停留和504列循环；四个滚动偏移、右下边界及隐藏状态共1843200像素逐项校验，通过且无窗口外像素变化。专项ModelSim日志零错误、零警告。

TD综合、布局布线、bit生成及原约束独立时序签核通过。实际时序及资源见evidence/。历史key_modes/sync1* false_path未匹配和物理位置迁移告警保留。此版本未上板，不以仿真图替代实机验收。

validation/中的PNG是文字模块叠加原始首页素材的实际RTL仿真输出，不是整个系统的实板截图；仿真仅隔离验证文字层，没有额外绘制摄像头ROI。

## 使用与复现

加载museum_floating_text_wide.bit，沿用现有TF卡，SW1控制流动文字显隐。没有执行硬件下载、Flash写入或GitHub发布。

在source/下运行：

```powershell
python -B phase6_gallery/tools/prepare_floating_text_test.py
Push-Location phase6_gallery/build
& F:/intelFPGA_lite/18.1/modelsim_ase/win32aloem/vsim.exe -c -do 'do ../sim/run_floating_text.do'
Pop-Location
python -B phase6_gallery/camera/tools/prepare_unified_project.py
python -B phase6_gallery/camera/tools/build_full.py --td D:/anlogic/bin/td_commands_prompt.exe --seed 43
```

仿真素材准备需要Python和Pillow；ModelSim/TD路径按本机安装调整。工具版本变化需要重新审查结果。旧的时间计数测试仍为历史文件，不再适用于文字模块；不宣称工程内所有历史测试均已执行。

bit SHA256：c1a76ac26426a4ef0cb347de6bd700fa8333693d77a09bffd91e3ba34d053755

SWNS: 0.250ns, STNS: 0.000ns.
HWNS: 0.041ns, HTNS: 0.000ns.

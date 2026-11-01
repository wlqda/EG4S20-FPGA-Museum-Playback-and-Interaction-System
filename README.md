# 基于安路EG4S20的FPGA博物馆播放与交互系统

基于 Anlogic EG4S20（EG4S20BG256）的数字博物馆多媒体互动导览终端，集成展品图文浏览、音视频讲解、按键与四方向手势交互。

本项目保存 **179×24 像素流动文字窗口、约25像素／秒内部滚动**的交付版本。底层保留图像流启动故障修复和手势四角判定框。

## 固件下载

- [v1.0.0 Release：完整交付 ZIP、bit 与校验文件](../../releases/tag/v1.0.0)
- [最终固件 museum_floating_text_wide.bit](firmware/museum_floating_text_wide.bit)

```text
SHA-256: C1A76AC26426A4EF0CB347DE6BD700FA8333693D77A09BFFD91E3BA34D053755
```

此文件为本次加宽、调速版，请勿混用之前的128像素文字版或仅故障修复版。沿用已有配套TF卡；本仓库不是完整TF卡镜像。

## 本版流动文字

显示内容固定为：

> 基于安路EG4S20的FPGA博物馆播放与交互系统

| 项目 | 行为 |
|---|---|
| 文字视窗 | **179×24像素**，约为原128像素长度的1.4倍 |
| 外框 | 195×32像素，含原有四周留白 |
| 字形 | 24像素高，黑色，背景透明，字模数据固定随源码保存 |
| 内部滚动 | 向左，每60个显示帧移动25像素；标称60Hz下约25像素／秒 |
| 句首停留 | 60帧，约1秒 |
| 句尾 | 24像素空隙后循环，循环总宽504像素 |
| 整窗飘动 | 每3帧移动1像素，保留初始位置、垂直运动与SW1开关 |
| 水平边界 | 为容纳加宽窗口，右侧反弹位置调整为x=445 |

本次功能源码只调整 `rtl/museum_floating_clock.v`。其他手势、四角框、图像流修复、音视频、界面及按键功能沿用前版；字模本身保持不变。[编译输入对照](evidence/CHANGES_FROM_PREVIOUS_TEXT.json)记录了修改边界。

下图是文字层叠加原始首页素材的实际RTL仿真输出。此专项仿真没有绘制摄像头等其他叠加层，不是实板截图。

![加宽流动文字 RTL 仿真](validation/text_start.png)

## 验证结果

| 项目 | 结果 |
|---|---|
| 功能仿真 | 字高、179像素视窗、滚动节奏、暂停、循环、SW1及边界检查通过 |
| 逐像素检查 | **1,843,200像素**，包括隐藏状态、四个滚动偏移和右下边界 |
| ModelSim日志 | 零错误、零警告：[test.log](validation/test.log) |
| 综合、布局布线、bit生成 | 通过：[物理实现日志](evidence/physical_build.log) |
| 独立Setup WNS | **+0.250ns** |
| 独立Hold WNS | **+0.041ns** |
| 输入追溯 | [BUILD_INPUTS.json](evidence/BUILD_INPUTS.json) |

新版尚未上板验收。TD保留历史 `key_modes/sync1*` false_path未匹配及物理位置迁移告警，详见日志；时序检查通过不替代实机功能验证。工程内历史测试并非全部适用本版，只将本次实际执行项目列为通过。

## 目录

| 目录 | 内容 |
|---|---|
| `phase6_gallery/` | 完整工程源码、界面素材、约束、测试和构建工具 |
| `firmware/` | 本次交付bit |
| `validation/` | 专项仿真记录及输出图 |
| `evidence/` | 综合、物理实现、时序报告及哈希记录 |
| `docs/DELIVERY_RECORD.md` | 完整交付说明与复现步骤 |
| `delivery/` | 原始交付包清单、发布资产校验值 |

## 编译和仿真

需要Python 3、Pillow、ModelSim、Anlogic TD 6.2及对应器件/IP库。本次使用seed43。请根据本机安装调整工具路径。

在仓库根目录运行：

```powershell
python -B phase6_gallery/tools/prepare_floating_text_test.py
Push-Location phase6_gallery/build
& F:/intelFPGA_lite/18.1/modelsim_ase/win32aloem/vsim.exe -c -do 'do ../sim/run_floating_text.do'
Pop-Location
python -B phase6_gallery/camera/tools/prepare_unified_project.py
python -B phase6_gallery/camera/tools/build_full.py --td D:/anlogic/bin/td_commands_prompt.exe --seed 43
```

构建输出为 `phase6_gallery/build/gesture_full/museum_phase6_gallery.bit`。工程文件保留交付时的本机绝对路径；先运行 `prepare_unified_project.py` 更新路径。重新构建后应重新审查哈希和时序报告。

## 手势与串口

SW3开启手势模式；KEY2重新准备背景、KEY3重新起手、KEY4切换RGB与诊断视图，诊断视图暂停手势控制。左右选择、下滑执行当前页的进入或播放/暂停、上滑返回。

遥测接口：115200 / 8N1 / 无流控，FPGA D12 UART_TX 接兼容3.3V TTL的USB串口RXD并共地。标志和数据格式见 [camera_telemetry_uart.v](phase6_gallery/camera/rtl/camera_telemetry_uart.v)。

原有文件的版权与许可声明保持原样；本项目未为第三方模块重新授予许可。

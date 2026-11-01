> 2026-10-29 更新：本分支已扩大竖直ROI并完成TD编译与SRAM下载，实板候选失效仍未解决。最新范围、证据和限制见 [VERTICAL_ROI_UPDATE_20261029.md](VERTICAL_ROI_UPDATE_20261029.md)。下文2026-10-28的“未修改RTL/未编译”仅代表历史交付。

# 手势与音频整机代码交接

更新：2026-10-28。本地完成代码整合和ModelSim验证后上传GitHub；队长执行TD编译、时序签核和烧录。本地无需安装TD。

## 版本与范围

整机源码接续PR #13的c9092200090732d15e7b62741379519e474b2542，合并交接分支e83ac528db6dab240409b95d5bd522582f27e65f，保留handoff/两套原始对照、bit和历史证据。根目录phase6_gallery/现在是完整手势与音频整机源码，handoff/audio_visualization/是无手势V3对照，二者不可互换。手势核心14文件保持3939bd6原始字节。

本轮消除旧F盘依赖、补齐干净克隆缺少的真实WAV/显示夹具、增加明确的工具参数及完整验证入口；未修改RTL、识别阈值或硬件约束。历史TD报告与bit只对应历史输入，新机器需要队长重新生成和签核。

## 本地或队长：源码与仿真检查

以下命令均在仓库根目录执行，Python需3.10以上及Pillow、NumPy。把python和ModelSim路径换成本机实际安装位置；也可通过VSIM_EXE或PATH指定ModelSim。

```powershell
python -B handoff/verify_handoff.py --index
python -B phase6_gallery/camera/tools/audit_full_camera.py
python -B phase6_gallery/camera/tools/prepare_verification.py --materials .
python -B phase6_gallery/camera/tools/run_unified_tests.py --vsim "D:/intelFPGA_lite/18.1/modelsim_ase/win32aloem/vsim.exe" --previews
```

算法审核默认读取仓库内handoff/gesture_3939bd6；也支持--baseline和GESTURE_BASELINE，接受项目根目录、快照目录、handoff目录或含handoff的仓库。它核对真实快照与14项历史哈希，并检查身份参考实现和提取参数，避免只拿两份相同的错误文件相互比较。

prepare_verification.py校验四份WAV的原始哈希及48kHz/16bit/单声道格式，保留不一致的已有音轨并报错，仅在build/生成仿真输入；不会重新合成语音、覆盖原素材或写TF卡。--materials也接受交接目录、audio_visualization包或TF_CARD。仿真不需要AVVIDEO.BIN或TD。

回归串行执行24组，避免ModelSim共享库映射冲突。--previews追加29场景、8908800像素的显示检查；相机RGB/掩码为合成测试输入，非实拍。缺夹具、仿真错误/警告、超时或检查失败均返回非零；单组默认超时600秒，可用--timeout调整。日志、输入哈希、TEST_RESULTS.json和PREVIEW_MANIFEST.json输出到phase6_gallery/build/gesture_full/。

## 队长：TD编译与时序

在装有支持EG4S20BG256的TD6.2环境执行：

```powershell
python -B phase6_gallery/camera/tools/prepare_unified_project.py
python -B phase6_gallery/camera/tools/build_full.py --td "实际TD安装目录/bin/td_commands_prompt.exe"
```

可用TD_EXE或PATH代替--td。prepare_unified_project.py自动创建build/gesture_full、核对所有源码路径、重定位museum_phase6_unified.al并生成67项BUILD_INPUTS.json。它不再从外部旧目录提取字库或改写RTL。运行后.al的Path会变为本机绝对路径，这是本机生成配置，不要将本机路径当成硬件功能改动提交。

build_full.py先综合检查容量，再布局布线，最后启动独立TD进程按原始SDC签核。入口museum_phase6_unified.al，顶层museum_phase6_unified_top，输出隔离在build/gesture_full/；不使用无手势museum_phase6_gallery.al烧录整机。保持现有seed43和TimingUltra，32K RAM历史已16/16，重新检查8个时钟、覆盖率、setup/hold、资源、例外和DRC。--resource-only仅检查综合容量；--resume仅用于输入哈希完全一致的现有综合数据库。

队长发布时记录精确源码、综合输入、工具版本、bit和TF素材哈希。本轮源码交付不附带新的TD时序、bit、下载或实板结论。自动下载脚本仍含历史机器配置，队长应使用自己核实的工具与连接配置；本交付验证流程不会调用它。

## TF资源与实板验收

仓库内handoff/audio_visualization/TF_CARD有29张BMP、4个WAV及说明；补入原匹配AVVIDEO.BIN后才是完整媒体卡。视频210816000字节，SHA256为b27cf3e75911c6e02d24de08d0d311be7439f2bbece9c5932091260a02732312。不要重新生成同名视频冒充原流。

SW2独立控制摄像头小窗；SW3控制手势识别与导航；SW4控制轮播。SW3开时KEY2采空背景、KEY3重启跟踪、KEY4切换掩码校准；SW3关时恢复菜单按键，切换时先松开按键。换卡或修改目录后按KEY1重新挂载。完整预览、光标、掩码、状态字与73字节G1遥测保持。

队长先做JTAG SRAM验证：背景就绪后手在中央等S2/A1，核对左右选择、下进入、上返回及加载中事件；再逐项检查四段讲解/真实波形/暂停/换件/重播、图片、缩放、视频、三个开关与长期运行。事件N/V变化不等于页面已响应。Flash固化和断电自启动需另行记录，不能用JTAG下载成功代替。

本轮本地验证结果见../integration_validation/portable_20261028/；此前full_camera_20261027目录保留历史证据，不修改其结论。

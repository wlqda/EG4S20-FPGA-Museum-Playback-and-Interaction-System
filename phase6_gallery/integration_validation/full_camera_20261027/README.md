# 完整摄像头整机验收

最终实现日期：2026-10-28。目录名称沿用本轮开始日期。

- `BUILD_INPUTS.json`：全部67项综合/约束/构建输入的原始字节SHA256。
- `FULL_FEATURE_AUDIT.json`：上传3939bd6的14份算法源码一致，身份关联和提取参数保持。
- `TEST_RESULTS.json`：24组回归及29场景显示检查，共25项；完整日志在本机 `phase6_gallery/build/gesture_full/`，重要新增回归随本目录保留。
- `final.ts`、`final.timing`、`final.area`、`final.exceptions`、`signoff.log`：独立TD进程重新读取原始SDC，setup +0.266ns、hold +0.041ns、覆盖99.95%，最终LUT16917、FF10538、9K RAM56、32K RAM16、DSP15。
- `BOARD_DOWNLOAD_RESULT.json`、`download.log`：实际Anlogic JTAG SRAM下载，目标EG4S20BG256。未写Flash，未声明实板手势效果通过。
- `PREVIEW_MANIFEST.json`：29帧、8908800像素RTL仿真；摄像头及掩码输入为合成激励，非实拍。

bit SHA256：`b42e3ff2b5849ea5061ae0325a665bd2fece3405f89888a9957a9d50fbdac39c`。

SW3开：KEY2采背景、KEY3重启跟踪、KEY4切换校准。SW3关：恢复菜单按键，先等按键全部释放。SW2独立控制视频窗，SW4保留轮播。共享目录索引，换卡或更新TF后按KEY1重新挂载。

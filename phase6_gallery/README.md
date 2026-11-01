# Phase6 文物照片轮播

当前分支 `codex/phase6-gallery`。本工程可以独立准备资源、运行仿真和构建，不依赖其他阶段目录。提取自 `e8ccea1`，只移动必要文件并调整路径，编译RTL及约束字节保持原发布哈希；本次未重新编译bit。

## 文件布局

| 目录 | 内容 |
|---|---|
| rtl/ | 当前Phase6控制、缩放、渲染、资源索引、标题和Logo |
| deps/core/ | 当前运行必需的SD、SDRAM桥接、媒体控制等共享模块 |
| deps/av/ | 当前运行必需的音视频、PLL、HDMI厂商模块 |
| deps/gui/ | 当前使用的按键模块 |
| constraints/ | 当前引脚与时序约束 |
| sim/ | 当前版本的4项回归及SD块服务模型 |
| source_photos/ | 13张轮播输入照片 |
| assets/base_pages/ | 16张基础界面无损PNG及清单、来源说明 |
| tools/ | 工程重定位、资源准备、仿真和打包工具 |

部分必要模块文件名仍有phase1/phase2/phase5前缀，以保持已验证编译源码；这些文件均是当前版本的依赖。`RELEASE_MANIFEST.json`列明精确路径及SHA256。

## 行为与操作

开机轮播13张单件文物照片，默认每张8秒，可设5—60秒。FPGA实时叠加标题、安路官网Logo与计数，切图采用淡出、完整加载、淡入。

| 状态 | KEY2 | KEY3 | KEY4短按 | KEY4长按 |
|---|---|---|---|---|
| 照片轮播 | 下一张 | 上一张 | 放大2× | 首页 |
| 放大查看 | 增大至4× | 减小至2× | 退出并恢复轮播 | 首页 |

手动切图重新计时；放大时停轮播，5秒无操作或退出放大后恢复。其他页面20秒无操作回轮播。既有展品列表/详情/文稿、固定短片播放/暂停/继续、音量/亮度设置保留。

## 准备与构建

需要Python和Pillow、TD6.2、ModelSim。生成字体/Logo的RTL已经提交，不必重生成；可选重生成依赖Windows宋体、Playwright及Edge。

从仓库根目录执行（将AV路径换成原配套发布包或TF卡文件的实际路径）：

```powershell
python phase6_gallery/tools/create_project.py
python phase6_gallery/tools/prepare_gallery_assets.py --av-file F:/媒体/AVVIDEO.BIN
python phase6_gallery/tools/run_tests.py
python phase6_gallery/tools/build_integration.py
```

`run_tests.py`默认ModelSim路径为 `F:/intelFPGA_lite/18.1/modelsim_ase/win32aloem/vsim.exe`，其他电脑可调整工具路径。`create_project.py`核对所有源码都在本工程内并设置当前Project Path。

AVVIDEO.BIN为配套210816000字节AV流，脚本核对SHA256；不接受任意同名视频。已放在build/TF_CARD中时可以省略--av-file。16张无损PNG恢复BMP后逐张核对原清单，13张照片生成640×480/24位无压缩BMP。输出29张BMP、1个AV流和3份说明，写入FAT32 TF卡。缺少必需BMP报25，按文件名索引不依赖复制顺序。

bit输出为 `build/museum_phase6_gallery.bit`。原r3配套bit SHA256为 `b6c738e28f0e6afba66a5d13952ccbcc67ead0c5a30fe68bdc86a7f24fd12776`。bit/ZIP/大AV流和工具输出不在Git中。

## 验证与限制

原TD setup +0.122ns、hold +0.004ns。当前移动路径后再次执行UI、29图FAT、缩放取址、叠层/淡变回归，并核对全部硬件输入哈希及媒体文件。具体状态见[交接](TEAM_HANDOFF.md)。加密HDMI/PLL/PHY未做完整包级仿真，最新版画面、声音、Flash固化、断电启动和长期稳定性仍待实板验收。

新版已接入独立讲解与PCM波形、SW4控制轮播和飘动数字时间，实际验证与交付状态见[集成进度](INTEGRATION_PROGRESS.md)。旧bit及上述历史时序不代表新版结果。[照片来源](GALLERY_SOURCES.md)、[资源清单](ASSETS.json)随工程保留。


## 2026-10-26 V1 音频与飘动时间

本轮状态以 [集成进度](INTEGRATION_PROGRESS.md) 和 `INTEGRATION_RELEASE_MANIFEST.json` 为准，原 `RELEASE_MANIFEST.json` 保留作历史记录。

- SW4是板载滑动开关（SWKEY_4，FPGA C5），高电平允许自动轮播，低电平停止自动切图；菜单轮播设置也须开启。关闭仍能手动切图、放大，重新开启从完整间隔开始计时。正在执行的切图会完成。
- 时间以任意选定的13:47:26起步，每秒递增，24小时回绕。数字框每3帧移动1像素，碰边反弹，各页持续显示；这是演示时间，无需RTC。
- 四件文物分别读取根目录 `AUD00001.WAV` 至 `AUD00004.WAV`，讲解页进入即播放；KEY2/3换件，KEY4短按暂停/继续或结束重播，长按返回并停止。讲解页禁用20秒自动返回。
- 讲解页右上角波形使用实际音量缩放后的PCM，暂停冻结、换件清空，短片页隐藏波形；飘动时间继续移动。
- TF卡必须保留原29张BMP与匹配的AVVIDEO.BIN，再加入四个WAV。完整配套文件在本机 `build/TF_CARD/`，不支持用四WAV增量包替代整套卡。

构建前运行 `python phase6_gallery/audio/tools/prepare_sim_fixtures.py` 和 `python phase6_gallery/audio/tools/run_audio_tests.py --vsim F:/intelFPGA_lite/18.1/modelsim_ase/win32aloem/vsim.exe`，后者包含15组回归。字库改动后可运行 `tools/generate_compact_render_font.py` 重新生成紧凑ROM，随后必须重新编译并运行像素等价测试。

新版构建脚本先运行物理实现，再启动独立TD进程载入布线数据库，按原始SDC复核五个时钟、STA覆盖率和setup/hold；任一负裕量（含报告中的负零）均停止，不生成发布bit。布局布线阶段额外加入0.4ns setup、0.02ns hold优化裕量，最终验收只使用原始约束。

2026-10-26 V1已通过独立原始SDC复核并生成bit：setup +0.421ns、hold +0.030ns、STA覆盖率99.96%；最终LUT79.97%。15组功能回归通过。Flash/断电启动及板上画面、声音、SW4和飘动时间验收仍待实板。

## 2026-10-26 V2 界面调整

首页只保留展品浏览、影像展示、系统设置三个入口；讲解从展品详情进入。首页图片由tools/refine_home_assets.py生成，保留原四项首页PNG。飘动时间采用黑字透明背景，BCD计数，消除逐像素除法/取模及底框；波形移到简介下方，底色与页面相同，无面板边框。16×16宋体根据实际字形边界居中，修复原先上移2像素造成的顶端笔画裁切；主字库和状态字库同步生成。

资源准备先运行python phase6_gallery/tools/refine_home_assets.py，再按准备步骤生成完整TF资源。V1发布包与bit保留于build/release_v1_20261026及原ZIP。新版验证和实板状态见INTEGRATION_PROGRESS.md。

V2最终发布：setup +0.502ns、hold +0.032ns，STA99.96%，LUT15578（79.48%）、FF9324、9k RAM40、32k RAM14、DSP11。完整包museum_clean_menu_black_clock_20261026_v2.zip；已具备当天V1完整TF资源时可用对应_update.zip，只替换5张BMP并下载同包bit。V2未做实板验收。

## 2026-10-26 V3 全展品界面

正式页面生成：python phase6_gallery/tools/generate_full_bleed_ui.py；随后按资源准备步骤生成BMP/WAV。原4:3轮播照片保持，必要的四张扩展背景；全部详情/讲解/列表仅显示小主体。所有图片仍是640×480/24bit BMP，29文件名与索引不变。生成素材的提示词、来源与衍生标记见assets/ui_v3/GENERATION_MANIFEST.json。

RTL移除旧轮播固定上下色条和重复标题，选中框统一内收。保留原按键、音视频、缩放、轮播和飘动时间。15组回归以及25帧7680000像素显示检查通过；独立时序setup +0.100ns、hold +0.020ns。最终LUT14938（76.21%）、FF9301、9k RAM40、32k RAM14、DSP11。模拟图和RTL帧不代表实板验收，Flash/断电等仍待实板。

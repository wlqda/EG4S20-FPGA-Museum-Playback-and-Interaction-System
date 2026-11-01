# 给组长：独立音频与实时波形交接

2026-10-23。目标基线：codex/phase6-gallery（f796343）。本组交付源码与仿真结果，由组长统一TD编译、生成bit、烧录和实板验收。

## 变更与位置
- audio/rtl/：四文件FAT索引、单扇区读取、WAV解析、PCM跨域FIFO、播放控制。
- visualization/rtl/：右上角192×80真实波形，使用实际HDMI音量缩放后的PCM；旧图片占位文字由RTL覆盖。
- rtl/museum_phase5_top.v：接入SD服务B端和音源选择，保持原HDMI流水线级数；声明顺序整理以支持ModelSim。
- rtl/museum_phase5_ui.v：进入讲解页播放、换件、暂停/继续、结束重播、返回停止；讲解页不再20秒自动退出。
- museum_phase6_gallery.al：已加入新增源文件。顶层模块名仍是museum_phase6_top。
- [接口与限制](INTERFACES.md)、[实际进度](PROGRESS.md)、[仿真与源码哈希](validation/checks.json)。

原AV、SD、SDRAM、HDMI依赖模块未修改；旧工程、原照片、PNG和历史发布清单保留。
此PR合入当前Phase6分支，不要把旧museum_terminal路径复制过来覆盖本目录。

## 音频交付
当前使用Huihui合成的四段WAV，命名AUD00001.WAV至AUD00004.WAV，48kHz/16bit/单声道。
源码仓库保存文稿、工具和[音频哈希](manifest.json)，不提交生成的WAV/大AV流/bit/ZIP。
精确音频包由本组另行传递：本机phase6_gallery/build/narration/narration_20261022.zip。组长拿到后，将其中TF_CARD里的四个WAV置于phase6_gallery/build/narration/TF_CARD/。
没有收到音频包时，可在有Microsoft Huihui Desktop声音的Windows上运行：
```powershell
./phase6_gallery/audio/tools/generate_narration.ps1
python phase6_gallery/audio/tools/verify_narration.py
```
不同Windows语音版本可能改变时长/哈希；复现文件应另存并重新核对。不要用原哈希声称新文件完全相同。
生成器拒绝覆盖文件。已有文件保持不动；需要换音轨时，用--source指定新目录并选择新的输出目录。

## 本地验证
在仓库根目录执行：
```powershell
python phase6_gallery/audio/tools/prepare_sim_fixtures.py
python phase6_gallery/audio/tools/run_audio_tests.py --vsim "D:/intelFPGA_lite/18.1/modelsim_ase/win32aloem/vsim.exe"
python phase6_gallery/audio/tools/prepare_audio_assets.py
```
最后一步只准备4个WAV增量和AUDIO_MANIFEST.json；TF卡根目录还必须有原配套29张BMP和AVVIDEO.BIN。
原完整TF资源可按phase6_gallery/README.md准备，AVVIDEO.BIN仍须使用原发布包的匹配文件。
所有音频从根目录按8.3文件名寻找，不支持放入子文件夹。

## TD编译（组长执行）
工程记录TD6.2.168116与EG4S20BG256；先确认本机TD版本和EG4器件支持。以下TD路径按实际安装修改：
```powershell
python phase6_gallery/tools/create_project.py
& 'D:/Anlogic/TD6.2/bin/td_commands_prompt.exe' './phase6_gallery/build.tcl'
```
create_project.py会将工程路径重定位到本机。build.tcl已有综合、布局布线、面积、时序检查及bit生成流程。
检查build/final.area和build/final.ts，尤其新增FIFO/扇区缓存/波形RAM及跨域路径；如果不满足资源或时序，不烧录。
通过后记录本次源码、TF资源和新bit SHA256。原RELEASE_MANIFEST.json只描述历史版本，不代表本次交付的编译结果。

## 实板验收
1. 首页/照片轮播/缩放/短片音视频保持正常。
2. 四件文物分别播放对应讲解，讲解期间图像稳定且超过20秒不中断。
3. KEY2/3切换文物无旧音轨串入；KEY4短按暂停/继续，结束后可重播；长按返回后静音。
4. 右上角波形随实际声音和音量变化；暂停冻结、换件清空，短片页面不显示。
5. 缺WAV和不支持格式提示正确；物理SD故障可能需要复位，暂不支持热插拔自动恢复。
6. 连续运行至少30分钟，记录声音中断、欠载、画面异常及按键响应；试听停止/音量变化边沿是否需要后续淡入淡出。

现阶段：7组仿真通过，音频组内16项场景检查通过；没有TD编译结果，没有新bit，没有实板结论。组长审核后再合并，不自动合并PR。

# 四件文物独立讲解音频

生成日期：2026-10-22。使用 Windows SAPI / Microsoft Huihui Desktop 普通话合成女声，Rate=-1。这是合成语音，不是真人录音。

| 展品ID | 文物 | TF文件名 | 时长 |
|---|---|---|---|
| 0 | 青铜方鼎 | AUD00001.WAV | 44.51秒 |
| 1 | 青花瓷瓶 | AUD00002.WAV | 44.10秒 |
| 2 | 汉代玉璧 | AUD00003.WAV | 45.60秒 |
| 3 | 唐代陶俑 | AUD00004.WAV | 46.68秒 |

四文件均为 RIFF/WAVE、非压缩PCM、48,000Hz、16位有符号小端、单声道。运行时可复制到HDMI左右声道。不要把整个WAV文件直接当裸PCM，需解析data chunk，按data长度结束。

输出目录：../build/narration/TF_CARD/。打包文件：../build/narration/narration_20261022.zip。
narrations.json保存展品映射和实际朗读文本；manifest.json保存时长、信号电平、样本数和SHA256。文稿取自原项目 assets/base_pages/EXHIBITS.md，仅将“7世纪”规范为“七世纪”便于朗读；原文稿及其馆藏来源保留不变。

复现（从仓库根目录，在有Huihui语音的Windows PowerShell/PowerShell中执行）：
```powershell
./phase6_gallery/audio/tools/generate_narration.ps1 -OutputDirectory D:/code/narration-regenerated
python phase6_gallery/audio/tools/verify_narration.py D:/code/narration-regenerated
```
生成器拒绝覆盖同名音频；重新生成请指定新的输出目录。不同Windows语音组件版本可能导致时长/哈希变化，必须重新校验。

已完成：四段合成、格式/样本长度/非静音/零削波检查及哈希记录。
读取/播放及波形RTL已实现并通过仿真，见[进度](PROGRESS.md)和[组长接入步骤](HANDOFF.md)。待完成：组长TD编译与实板声音、可视化验证。
现有Phase6 bit尚不能读取这些独立音轨，复制到TF卡不会自动开启讲解功能。
WAV和ZIP位于已忽略的build目录；源文稿、工具和清单可纳入版本控制。

# 讲解实时波形

实现：rtl/museum_audio_waveform.v。使用实际HDMI音量缩放后的PCM，在右上角显示192×80波形。不是频谱。
协议与控制详见[音频接口](../audio/INTERFACES.md)，当前验证状态详见[任务进度](../audio/PROGRESS.md)。
暂停冻结，完整快照在消隐交换，短片模式隐藏。
原背景PNG保持不变，旧装饰波形与待录制文字由RTL状态区域覆盖。

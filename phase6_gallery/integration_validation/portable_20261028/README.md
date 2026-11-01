# 本机代码整合验证（2026-10-28）

来源：整机候选c909220与最新交接分支e83ac528。当前分支完成两者合并，保留原始资料；本轮修复工具路径及干净克隆复现，不修改候选RTL或硬件约束。

- TEST_RESULTS.json与25份同名.log：24组功能回归及29场景显示检查全部通过；日志SHA256逐项匹配。
- PREVIEW_MANIFEST.json：29帧、8908800个对齐像素；13张轮播保留。RGB/掩码为合成相机激励，非现场画面；帧PNG留在本地build/，可按CODE_HANDOFF.md重跑生成。
- FULL_FEATURE_AUDIT.json：3939bd6原始14份识别核心、身份参考实现及提取参数一致。
- FIXTURE_INPUTS.json：四份真实WAV和页面输入哈希；这是仿真夹具，不是完整媒体卡。
- PORTABILITY_CHECKS.json：缺基线、缺ModelSim、缺TD均给出明确非零报错；重复准备的67项工程输入字节一致，支持仓库根目录基线参数。
- SIMULATION_SOURCES.json：本地验证对应的源码/测试/约束/页面哈希及验证边界。新工具固定LF，硬件原始字节保留。
- handoff/verify_handoff.py --index通过457个Git原始字节检查、390个手势包文件、37个TF文件、V3 bit、ZIP CRC和46项原V3构建输入。

本轮没有运行TD、生成新bit或烧录。历史full_camera_20261027报告只对应其原始输入，不能冒充本轮重新签核。工程重定位验证后已恢复.al原模板的机器路径；队长必须先运行prepare_unified_project.py，再以自己的TD路径编译。完整命令见../../camera/CODE_HANDOFF.md。

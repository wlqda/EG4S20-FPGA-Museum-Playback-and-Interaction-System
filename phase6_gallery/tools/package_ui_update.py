"""Package only files changed from the verified previous TF set, plus the matching bit."""
from pathlib import Path
import argparse, hashlib, json, zipfile
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument("--previous",type=Path,default=ROOT/"build/release_v2_20261026/INTEGRATION_RELEASE_MANIFEST.json")
a=p.parse_args()
previous=json.loads(a.previous.read_text(encoding="utf-8"))
current=json.loads((ROOT/"INTEGRATION_RELEASE_MANIFEST.json").read_text(encoding="utf-8"))
if set(previous["tf_files"])-set(current["tf_files"]):raise ValueError("Update must not require deleting card files")
changed=[n for n,h in current["tf_files"].items() if previous["tf_files"].get(n)!=h]
bit=ROOT/"build/museum_phase6_gallery.bit"
assert hashlib.sha256(bit.read_bytes()).hexdigest()==current["bit_sha256"]
notes="""V3界面更新包（适用于已写入2026-10-26 V2完整资源的TF卡）

1. 将TF_CARD文件夹内的文件复制到TF卡根目录，替换同名文件。
2. 同时向开发板下载本包museum_phase6_gallery.bit。
3. 四份讲解WAV、29图中的其余图片及AVVIDEO.BIN保持原配套版本。

首页改为展品浏览/影像展示/系统设置三个入口；讲解由详情进入。
轮播全屏显示并对必要照片扩展背景；列表/详情/讲解统一使用小主体。飘动时间黑字透明底，波形位于简介下方且与页面同底色。
首页、列表和设置的选中框按新版坐标绘制。完整文件校验值见发布清单。
本包不包含尚未做过的实板、Flash、断电及长期稳定性验证结论。
"""
notes_path=ROOT/"build/UI_V3_UPDATE_NOTES.txt"
notes_path.write_text(notes,encoding="utf-8")
out=ROOT/"build"/(current["version"]+"_update.zip")
with zipfile.ZipFile(out,"x",zipfile.ZIP_DEFLATED,compresslevel=1) as z:
 z.write(bit,bit.name)
 z.write(notes_path,"UPDATE_NOTES.txt")
 z.write(ROOT/"INTEGRATION_RELEASE_MANIFEST.json","INTEGRATION_RELEASE_MANIFEST.json")
 for n in changed:
  path=ROOT/"build/TF_CARD"/n
  assert hashlib.sha256(path.read_bytes()).hexdigest()==current["tf_files"][n]
  z.write(path,"TF_CARD/"+n)
with zipfile.ZipFile(out) as z:assert z.testzip() is None
print("Update files:",changed)
print("Packaged",out,"bytes",out.stat().st_size)

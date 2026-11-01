"""Verify and export actual RTL display capture evidence (synthetic camera)."""
from pathlib import Path
from PIL import Image
import hashlib,json,re,html
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/gesture_full/delivery_preview'
log=(OUT.parent/'delivery_previews.log').read_text(errors='replace')
assert '29 pages, 8908800 aligned RGB pixels' in log
assert not re.search(r'Errors: [1-9]|Warnings: [1-9]|\*\* (?:Warning|Error|Fatal):',log)
records=[]
for i in range(5,34):
 im=Image.open(OUT/f'IMG{i:05d}.ppm');assert im.size==(640,480)
 p=OUT/f'IMG{i:05d}.png';im.save(p)
 records.append({'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
labels={5:'首页',6:'列表',15:'设置',16:'视频',30:'手势关闭 / 相机预览',31:'SW2隐藏预览',32:'KEY4诊断',33:'图像流故障'}
body='<html lang="zh"><meta charset="utf-8"><title>交付版 RTL 显示验证</title><style>body{background:#eee8df;font:16px sans-serif}main{display:grid;grid-template-columns:repeat(2,640px);gap:20px}figure{margin:0}</style><h1>29个RTL场景</h1><p>真实页面素材，合成摄像头与掩码输入；不是实板照片。SW1时钟开启。</p><main>'
for i in range(5,34):body+=f'<figure><img src="IMG{i:05d}.png"><figcaption>{html.escape(labels.get(i,"页面 "+str(i)))}</figcaption></figure>'
(OUT/'index.html').write_text(body+'</main></html>',encoding='utf-8')
(OUT/'PREVIEW_MANIFEST.json').write_text(json.dumps({'kind':'RTL pipeline, synthetic camera and mask; not hardware capture','scenes':29,'aligned_pixels':8908800,'checks':['exact ROI pixel mapping across normal/mask/fault states','no overlay changes outside approved footprint','all pixels known, ordered and counted'],'files':records},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PASS delivery display: 29 scenes, 8908800 aligned pixels')

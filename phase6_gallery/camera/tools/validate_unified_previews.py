"""Validate full display captures and publish clearly labelled simulation pages."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import numpy as np,json,hashlib,html
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/gesture_unified/preview'
log=(OUT.parent/'run_unified_previews.log').read_text(encoding='utf-8',errors='replace')
assert '25 pages, 7680000 aligned RGB pixels' in log and 'Errors: 0, Warnings: 0' in log
labels={5:'首页',6:'展品列表',15:'系统设置',16:'影像展示'}
names=['青铜方鼎','青花瓷瓶','汉代玉璧','唐代陶俑']
for k,n in enumerate(names):labels[7+k]=n+' · 详情';labels[11+k]=n+' · 讲解'
records=[]
for i in range(5,30):
    p=OUT/f'IMG{i:05d}.png';im=Image.open(OUT/f'IMG{i:05d}.ppm').convert('RGB');assert im.size==(640,480);im.save(p)
    if i>=17:
        labels[i]=f'轮播 {i-16:02d} / 13'
        original=np.asarray(Image.open(ROOT/f'assets/ui_v3/pages/IMG{i:05d}.png').convert('RGB'))
        capture=np.asarray(im);difference=np.any(original!=capture,axis=2)
        difference[60:76,488:616]=False
        clock=np.zeros((480,640),dtype=bool);clock[107:139,173:317]=True
        assert not np.any(difference & ~clock),(i,'unintended slideshow change')
        assert np.all(capture[difference]==0),(i,'non-black clock')
    records.append({'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
def sheet(ids,name,cols=2,width=640):
    height=round(width*.75);board=Image.new('RGB',(16+cols*(width+16),16+((len(ids)+cols-1)//cols)*(height+48)),'#e5dfd3');d=ImageDraw.Draw(board)
    for k,i in enumerate(ids):
        x=16+(k%cols)*(width+16);y=16+(k//cols)*(height+48)
        d.text((x,y),labels[i]+' · RTL仿真',font=font,fill='#343d38')
        board.paste(Image.open(OUT/f'IMG{i:05d}.png').resize((width,height)),(x,y+32))
    board.save(OUT/name)
sheet(range(7,11),'details.png');sheet(range(11,15),'narration.png');sheet(range(5,30),'all_25.png',5,320)
markup='<!doctype html><html lang="zh"><meta charset="utf-8"><title>统一工程25页仿真</title><style>body{font:16px sans-serif;background:#f4eee4;color:#343d38;margin:24px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:24px}figure{margin:0}img{width:100%}</style><h1>统一工程 · 25页RTL仿真</h1><p>真实页面资源、PCM、飘动时间与摄像头状态叠层。CAM ARMED为仿真输入；非实拍、非实机识别证据。</p><main>'
for i in range(5,30):markup+=f'<figure><img src="IMG{i:05d}.png"><figcaption>{html.escape(labels[i])}</figcaption></figure>'
(OUT/'index.html').write_text(markup+'</main></html>',encoding='utf-8')
(OUT/'PREVIEW_MANIFEST.json').write_text(json.dumps({'kind':'RTL simulation, not hardware capture','camera_status':'simulated ARMED input',
 'aligned_pixels':7680000,'slideshow_pixels':'unchanged except black clock and compact camera status','files':records},ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS: all 25 frames; full-bleed slideshow unchanged except black clock and compact camera status')

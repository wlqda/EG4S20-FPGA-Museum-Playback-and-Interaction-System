"""Validate original full overlay and independent switch presentation captures."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import numpy as np,json,hashlib,html,re
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/gesture_full/preview'
log=(OUT.parent/'run_full_previews.log').read_text(encoding='utf-8',errors='replace')
assert '29 pages, 8908800 aligned RGB pixels' in log and not re.search(r'Errors: [1-9]|Warnings: [1-9]|\*\* (?:Error|Fatal):',log)
labels={5:'首页',6:'展品列表',15:'系统设置',16:'影像展示',30:'SW3开 / SW2开 · 合成视频测试图',
31:'SW3关 / SW2开 · 小窗独立显示',32:'SW3开 / SW2关 · 正常观展',33:'KEY4校准 · 原版掩码与完整诊断'}
for k,n in enumerate(['青铜方鼎','青花瓷瓶','汉代玉璧','唐代陶俑']):labels[7+k]=n+' · 详情';labels[11+k]=n+' · 讲解'
records=[]
for i in range(5,34):
    im=Image.open(OUT/f'IMG{i:05d}.ppm').convert('RGB');assert im.size==(640,480);p=OUT/f'IMG{i:05d}.png';im.save(p)
    if 17<=i<30:
        labels[i]=f'轮播 {i-16:02d} / 13';base=np.asarray(Image.open(ROOT/f'assets/ui_v3/pages/IMG{i:05d}.png').convert('RGB'))
        a=np.asarray(im);diff=np.any(a!=base,axis=2);diff[60:76,488:616]=False
        clock=np.zeros((480,640),dtype=bool);clock[107:139,173:317]=True
        assert not np.any(diff & ~clock) and np.all(a[diff]==0),i
    records.append({'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
sheet=Image.new('RGB',(1328,1072),'#e5dfd3');d=ImageDraw.Draw(sheet)
for k,i in enumerate(range(30,34)):
    x=16+(k%2)*656;y=16+(k//2)*528;d.text((x,y),labels[i]+' · RTL仿真，非实拍',font=font,fill='#343d38');sheet.paste(Image.open(OUT/f'IMG{i:05d}.png'),(x,y+32))
sheet.save(OUT/'switch_and_calibration.png')
page='<!doctype html><html lang="zh"><meta charset="utf-8"><title>完整手势版RTL预览</title><style>body{background:#f4eee4;color:#343d38;font:16px sans-serif;margin:24px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:24px}figure{margin:0}img{width:100%}</style><h1>完整手势版 · 29个场景</h1><p>RTL仿真，非实机拍摄。摄像头RGB和掩码采用合成测试激励，非现场摄像头影像。</p><main>'
for i in range(5,34):page+=f'<figure><img src="IMG{i:05d}.png"><figcaption>{html.escape(labels[i])}</figcaption></figure>'
(OUT/'index.html').write_text(page+'</main></html>',encoding='utf-8')
(OUT/'PREVIEW_MANIFEST.json').write_text(json.dumps({'kind':'RTL simulation, synthetic camera/mask inputs, not board capture','aligned_pixels':8908800,'frames':29,'files':records},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
tests=json.loads((OUT.parent/'TEST_RESULTS.json').read_text(encoding='utf-8'))
for name in list(tests)+['run_full_previews']:
    p=OUT.parent/(name+'.log');s=p.read_text(encoding='utf-8',errors='replace')
    assert 'PASS' in s and not re.search(r'Errors: [1-9]|Warnings: [1-9]|\*\* (?:Error|Fatal):',s),name
    tests[name]={'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'pass_messages':re.findall(r'^# .*PASS.*$',s,re.M)}
(OUT.parent/'TEST_RESULTS.json').write_text(json.dumps(tests,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PASS full display:',len(tests),'suites, 29 frames, 8908800 aligned pixels; 13 slides preserved')

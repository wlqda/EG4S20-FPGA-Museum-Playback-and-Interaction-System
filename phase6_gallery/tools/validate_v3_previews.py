"""Check and package actual HDL-composited frame captures (not board photographs)."""
from pathlib import Path
from PIL import Image
import json,hashlib,re,zipfile,html
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/"build/v3_preview"
log=(ROOT/"build/v3_previews.log").read_text(encoding="utf-8",errors="replace")
assert "PASS V3 previews: 25 pages, 7680000 aligned RGB pixels" in log
assert not re.search(r"Warnings: [1-9]|Errors: [1-9]|\*\* (Warning|Error|Fatal):",log)
records=[]
for i in range(5,30):
 p=OUT/f"IMG{i:05d}.png";Image.open(OUT/f"IMG{i:05d}.ppm").save(p)
 im=Image.open(p).convert("RGB");assert im.size==(640,480)
 if i in [5,6,15]:
  x,y,w,h={5:(26,160,186,240),6:(26,141,132,264),15:(26,141,588,54)}[i]
  for xx in range(x,x+w):
   for yy in [y,y+1,y+h-2,y+h-1]:assert im.getpixel((xx,yy))==(166,56,38),(i,xx,yy)
  for yy in range(y,y+h):
   for xx in [x,x+1,x+w-2,x+w-1]:assert im.getpixel((xx,yy))==(166,56,38),(i,xx,yy)
 if i>=17:
  base=Image.open(ROOT/"build/TF_CARD"/f"IMG{i:05d}.BMP").convert("RGB")
  for y in range(480):
   for x in range(640):
    a=im.getpixel((x,y));b=base.getpixel((x,y))
    if a!=b:assert a==(0,0,0) and 173<=x<317 and 107<=y<139,(i,x,y,a,b)
 records.append({"index":i-1,"file":p.name,"sha256":hashlib.sha256(p.read_bytes()).hexdigest()})
manifest={"kind":"HDL simulated pixels; not board capture","images":records,"pixels_checked":7680000,"checks":["25 frame sizes and raster-coordinate alignment","No unknown RGB pixels","Inset home/list/settings borders match native layout","All 13 full-bleed photos pass through except black transparent clock"]}
(OUT/"PREVIEW_MANIFEST.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
labels={5:"首页",6:"展品列表",15:"系统设置",16:"影像展示"}
for i,n in enumerate(["青铜方鼎","青花瓷瓶","汉代玉璧","唐代陶俑"]):labels[7+i]=n+" · 详情";labels[11+i]=n+" · 讲解"
for i in range(17,30):labels[i]=f"轮播 {i-16:02d} / 13"
markup='<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>V3全部25页 · RTL仿真</title><style>body{font:16px sans-serif;background:#f4eee4;color:#343d38;margin:24px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:24px}figure{margin:0}img{width:100%}figcaption{padding:8px}</style><h1>V3 全部25页</h1><p>使用实际TF资源和HDL显示流水线生成。RTL仿真，非实机拍摄。</p><main>'
for i in range(5,30):markup+=f'<figure><a href="IMG{i:05d}.png"><img src="IMG{i:05d}.png"></a><figcaption>{html.escape(labels[i])}</figcaption></figure>'
markup+='</main></html>';(OUT/"index.html").write_text(markup,encoding="utf-8")
from PIL import ImageDraw,ImageFont
font=ImageFont.truetype("C:/Windows/Fonts/msyh.ttc",15)
def sheet(ids,name,cols=4,width=320):
 rows=(len(ids)+cols-1)//cols;cellh=round(width*.75)+28;out=Image.new("RGB",(cols*(width+16)+16,rows*(cellh+16)+16),"#e5dfd3");d=ImageDraw.Draw(out)
 for n,i in enumerate(ids):
  x=16+n%cols*(width+16);y=16+n//cols*(cellh+16);d.text((x,y),labels[i],font=font,fill="#343d38");out.paste(Image.open(OUT/f"IMG{i:05d}.png").resize((width,round(width*.75)),Image.Resampling.LANCZOS),(x,y+28))
 out.save(OUT/name)
sheet(list(range(5,30)),"all_25_runtime.png",5,320)
sheet([17,20,23,27],"four_carousels.png",2,640)
sheet([7,8,9,10,11,12,13,14],"all_subject_pages.png",2,640)
with zipfile.ZipFile(OUT/"museum_v3_all_25_runtime_previews.zip","w",zipfile.ZIP_DEFLATED) as z:
 for p in [OUT/"index.html",OUT/"PREVIEW_MANIFEST.json",OUT/"all_25_runtime.png",OUT/"four_carousels.png",OUT/"all_subject_pages.png"]+[OUT/r["file"] for r in records]:z.write(p,p.name)
print("PASS V3 previews: borders, full-bleed RGB, black transparent clock, 25 pages")

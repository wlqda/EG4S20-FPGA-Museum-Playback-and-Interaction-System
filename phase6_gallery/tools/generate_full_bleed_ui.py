from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageOps
import math, json, re
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/ui_v3/pages';OUT.mkdir(parents=True,exist_ok=True)
S=3;PAPER='#f4eee4';CARD='#faf7f1';INK='#343d38';MUTED='#877e70';RED='#a63826';RULE='#d9d0c2'
F={}
def font(n,latin=False):
 k=(n,latin)
 if k not in F:F[k]=ImageFont.truetype('C:/Windows/Fonts/arial.ttf' if latin else 'C:/Windows/Fonts/msyh.ttc',n*S)
 return F[k]
def page(label):
 im=Image.new('RGB',(640*S,480*S),PAPER);d=ImageDraw.Draw(im)
 return im,d

def text(d,x,y,t,n=12,c=INK,latin=False):d.text((x*S,y*S),t,font=font(n,latin),fill=c,anchor='lt')
def rect(d,b,c=CARD,edge=None,w=1):d.rectangle(tuple(int(v*S) for v in b),fill=c,outline=edge,width=w*S)
def line(d,ps,c=RULE,w=1):d.line([(int(x*S),int(y*S)) for x,y in ps],fill=c,width=w*S)
def center(d,cx,y,t,n=12,c=INK,latin=False):
 f=font(n,latin);text(d,cx-d.textlength(t,font=f)/(2*S),y,t,n,c,latin)
def header(d,label):
 rect(d,(24,19,43,38),RED);text(d,27,21,'博',13,'white');text(d,52,19,'数字博物馆',12);text(d,52,35,'DIGITAL MUSEUM',6,MUTED,True);text(d,540,24,label,10,MUTED)
def footer(d,left='KEY2 / KEY3 选择',middle='KEY4 确认',right='长按 KEY4 返回'):
 line(d,[(24,432),(616,432)]);text(d,24,450,left,10,RED);center(d,335,450,middle,10,RED);text(d,531,453,right,8,MUTED)
def title(d,kicker,t,desc=None):
 text(d,24,65,kicker,8,MUTED,True);text(d,24,85,t,26)
 if desc:text(d,25,121,desc,11,MUTED)
def photo(im,path,box):
 x,y,x1,y1=box;tile=Image.new('RGB',((x1-x)*S,(y1-y)*S),'#eeeae2')
 p=Image.open(ROOT/'source_photos'/path).convert('RGB');p=ImageOps.contain(p,(tile.width-12*S,tile.height-12*S),Image.Resampling.LANCZOS)
 tile.paste(p,((tile.width-p.width)//2,(tile.height-p.height)//2));im.paste(tile,(x*S,y*S))
def save(im,name):im.resize((640,480),Image.Resampling.LANCZOS).save(OUT/(name+'.png'))
photos=['01_bronze/01_original.jpg','02_porcelain/01_original.jpg','03_jade/01_original.jpg','04_figurine/01_original.jpg']
names=['青铜方鼎','青花瓷瓶','汉代玉璧','唐代陶俑'];dates=['商代晚期','明代 · 永乐','西汉','唐代']

GEN=ROOT/"assets/ui_v3/generated"
CUT_NAMES=["bronze","porcelain","jade","figurine"]
SUBJECTS=[]
for name in CUT_NAMES:
 p=Image.open(GEN/(name+"_cutout.png")).convert("RGBA")
 a=p.getchannel("A");assert a.getextrema()==(0,255),name
 bbox=a.point(lambda v:255 if v>=32 else 0).getbbox();assert bbox
 SUBJECTS.append(p.crop(bbox))
def subject(im,owner,box):
 x0,y0,x1,y1=box
 p=ImageOps.contain(SUBJECTS[owner],((x1-x0)*S,(y1-y0)*S),Image.Resampling.LANCZOS)
 im.paste(p,(round((x0+x1)*S/2-p.width/2),round((y0+y1)*S/2-p.height/2)),p)
def save_page(im,index):save(im,f"IMG{index:05d}")
# HOME: bitmap carries only static geometry; the selected frame is RTL.
im,d=page("home");header(d,"");title(d,"A JOURNEY THROUGH TIME","数字博物馆","在器物与细节之间，发现文明的回响。")
line(d,[(526,82),(526,126)],RED);text(d,540,86,"穿越时空",11);text(d,540,109,"遇见文明",11)
for i,left in enumerate([24,225,426]):
 right=left+190;cx=left+95;rect(d,(left,158,right-1,401),CARD,RULE);text(d,left+18,175,f"0{i+1}",9,RED,True)
 if i==0:
  line(d,[(cx-36,225),(cx,206),(cx+36,225),(cx-36,225)],INK,2)
  line(d,[(cx-39,280),(cx+39,280)],INK,2);line(d,[(cx-33,274),(cx+33,274)],INK,2)
  for dx in [-23,0,23]:
   line(d,[(cx+dx-4,233),(cx+dx-4,265)],INK,2);line(d,[(cx+dx+4,233),(cx+dx+4,265)],INK,2)
  line(d,[(cx-4,214),(cx,212),(cx+4,214)],RED,2)
 elif i==1:
  rect(d,(cx-36,215,cx+36,272),None,INK,2);line(d,[(cx-36,227),(cx+36,227)],INK,2)
  for dx in [-24,-8,8,24]:line(d,[(cx+dx-4,215),(cx+dx+2,225)],INK,2)
  d.polygon([((cx-7)*S,237*S),((cx-7)*S,260*S),((cx+13)*S,248*S)],fill=RED)
 else:
  for j,dx in enumerate([-25,0,25]):
   line(d,[(cx+dx,215),(cx+dx,276)],INK,2);yy=[233,259,240][j];rect(d,(cx+dx-6,yy-5,cx+dx+6,yy+5),CARD,RED,2)
 line(d,[(left+18,306),(right-18,306)])
 center(d,cx,324,["展品浏览","影像展示","系统设置"][i],21)
 center(d,cx,355,["COLLECTION","FILM","SETTINGS"][i],7,MUTED,True)
 center(d,cx,377,["器物 · 细节 · 讲解","聆听历史，看见文明","音量 · 亮度 · 轮播"][i],10,MUTED)
footer(d);save_page(im,5)
names=["青铜方鼎","青花瓷瓶","汉代玉璧","唐代陶俑"]
dates=["商代晚期","明代 · 永乐","西汉","唐代"]
im,d=page("list");header(d,"展品浏览");title(d,"THE COLLECTION","四件器物，四段故事")
for i,x in enumerate([24,176,328,480]):
 rect(d,(x,139,x+135,407),CARD,RULE);subject(im,i,(x+18,160,x+118,321))
 text(d,x+12,341,names[i],15);text(d,x+12,367,dates[i],10,MUTED);text(d,x+12,390,f"0{i+1} / 04",7,MUTED,True)
footer(d,middle="KEY4 查看详情");save_page(im,6)
parts=re.split(r"^## \d+ ",(ROOT/"assets/base_pages/EXHIBITS.md").read_text(encoding="utf-8"),flags=re.M)[1:]
meta=[("商代晚期","青铜","高 22.9 厘米"),("明代 · 永乐","青花瓷","景德镇窑"),("西汉","软玉","直径 13.8 厘米"),("唐代","彩绘陶","高 29.8 厘米")]
def wrap(draw,body,size,width):
 lines=[];s=""
 for c in body:
  if draw.textlength(s+c,font=font(size))>width*S and s:
   if c in "，。、；：！？）" and len(s)>1:lines.append(s[:-1]);s=s[-1]
   else:lines.append(s);s=""
  s+=c
 if s:lines.append(s)
 return lines
excerpts=["双耳挺立，四足承托。兽面纹饰与对称的结构，呈现商代青铜艺术的秩序与力量。","白釉映衬蓝色纹饰。沿瓶口、肩部到腹部，观察器形与装饰带的节奏变化。","外缘与中央圆孔构成环形结构。观察有序排列的纹饰，感受材质与几何的秩序。","高髻与长裙，勾勒出修长的身姿。细看衣褶与彩绘，走近唐代人物造型的审美。"]
THEMES=[('#405b43','#dce3cc','#edf0e3'),('#245d88','#d6e6ef','#eaf1f5'),('#617451','#dfe7d0','#edf1e5'),('#a4482f','#efd6bd','#f7e7d8')]

def themed_header(d,owner,label):
 accent,tint,soft=THEMES[owner]
 rect(d,(0,0,639,55),tint)
 # Restrained geometric ornament stays in the header, away from readable text.
 for x in range(330,520,24):
  line(d,[(x,7),(x+15,7),(x+15,19),(x+5,19),(x+5,31),(x+20,31),(x+20,47)],soft,2)
 line(d,[(24,55),(616,55)],accent,2)
 header(d,label)

for i,part in enumerate(parts):
 paras=part.split("\n\n");body=next(t.strip() for t in paras if not t.startswith(("**","观看提示","###","图片")) and "\n" not in t and len(t)>40);tip=re.search(r"观看提示：(.*)",part)[1]
 accent,tint,soft=THEMES[i]
 im,d=page("detail");themed_header(d,i,"展品详情");title(d,f"COLLECTION / 0{i+1}",names[i]);text(d,530,101,f"0{i+1} / 04",9,accent,True)
 rect(d,(249,139,616,204),soft);rect(d,(249,214,616,359),soft);rect(d,(249,365,616,417),soft)
 line(d,[(249,139),(249,204)],accent,3)
 subject(im,i,(48,161,212,375));center(d,130,397,dates[i]+" · "+meta[i][1],9,MUTED)
 line(d,[(260,139),(616,139)])
 for x,label,value in zip([260,376,484],["年代","材质","窑口" if i==1 else "尺寸"],meta[i]):text(d,x,154,label,10,MUTED);text(d,x,176,value,13)
 line(d,[(260,203),(616,203)]);text(d,260,222,"器物与细节",15)
 lines=wrap(d,body,12,352);assert len(lines)<=6
 for j,t in enumerate(lines):text(d,260,249+j*18,t,12)
 line(d,[(260,365),(260,407)],accent,2);text(d,272,368,"观看提示",10,accent)
 for j,t in enumerate(wrap(d,tip,10,340)):text(d,272,385+j*14,t,10,MUTED)
 footer(d,"KEY2 / KEY3 切换展品","KEY4 聆听讲解");save_page(im,7+i)
 im,d=page("audio");themed_header(d,i,"音频讲解");title(d,"LISTEN TO THE COLLECTION",names[i])
 rect(d,(249,139,616,263),soft);line(d,[(249,139),(249,263)],accent,3)
 subject(im,i,(48,172,212,375));center(d,130,397,dates[i]+" · "+meta[i][1],9,MUTED)
 text(d,260,147,f"0{i+1} / 04 · "+dates[i],9,accent);text(d,260,174,"音频讲解",21)
 for j,t in enumerate(wrap(d,excerpts[i],12,350)):text(d,260,213+j*22,t,12)
 # Empty paper at 336..528 / 276..352 is reserved for actual PCM, not fake bars.
 rect(d,(260,354,263,365),RED);rect(d,(267,354,270,365),RED)
 text(d,260,385,"KEY4 暂停 / 继续",10,MUTED);footer(d,"KEY2 / KEY3 切换文物","KEY4 暂停 / 继续");save_page(im,11+i)
im,d=page("settings");header(d,"系统设置");title(d,"MAKE YOURSELF COMFORTABLE","舒适地观看与聆听")
for i,(label,en) in enumerate([("讲解音量","AUDIO VOLUME"),("屏幕亮度","BRIGHTNESS"),("轮播间隔","SLIDE INTERVAL"),("自动轮播","AUTO PLAY")]):
 y=139+i*66;rect(d,(24,y,615,y+57),CARD,RULE);text(d,43,y+12,label,16);text(d,43,y+37,en,7,MUTED,True)
footer(d,"KEY2 / KEY3 选择","KEY4 进入 / 完成");save_page(im,15)
im,d=page("video");header(d,"影像展示");rect(d,(24,84,615,416),"#26302b");text(d,44,101,"FILM / DIGITAL MUSEUM",8,"#b7b8ac",True)
cx,cy=320,234;d.ellipse(((cx-29)*S,(cy-29)*S,(cx+29)*S,(cy+29)*S),outline=RULE,width=S);d.polygon([((cx-6)*S,(cy-13)*S),((cx-6)*S,(cy+13)*S),((cx+15)*S,cy*S)],fill=PAPER)
center(d,320,285,"影像展示",20,PAPER);center(d,320,323,"按 KEY4 开始播放",11,"#b7b8ac");footer(d,"","KEY4 播放 / 暂停");save_page(im,16)
assets=json.loads((ROOT/"ASSETS.json").read_text(encoding="utf-8"));gallery=[a for a in assets["images"] if a.get("page")=="gallery"]
for i,a in enumerate(gallery):
 generated=GEN/f"gallery_{i+1:02d}.png";path=generated if generated.exists() else ROOT/"source_photos"/a["photo"]
 image=Image.open(path).convert("RGB");assert abs(image.width/image.height-4/3)<.01,(a["file"],image.size)
 im=ImageOps.fit(image,(640*S,480*S),Image.Resampling.LANCZOS);d=ImageDraw.Draw(im)
 lum=sum(im.getpixel((30*S,30*S)))/3;ink=INK if lum>125 else "#f5f1e8"
 rect(d,(24,19,43,38),RED);text(d,27,21,"博",13,"white");text(d,52,21,"数字博物馆",12,ink);text(d,555,24,"展品轮播",9,ink)
 lum=sum(im.getpixel((24*S,435*S)))/3;ink=INK if lum>130 else "#fff9ee"
 owner=0 if i<3 else 1 if i<6 else 2 if i<10 else 3
 text(d,24,416,names[owner],18,ink);text(d,25,443,dates[owner]+" · "+meta[owner][1],10,ink);text(d,569,443,f"{i+1:02d} / 13",9,ink,True)
 text(d,24,466,"KEY2 / KEY3 切换图片",8,ink);text(d,282,466,"KEY4 放大 / 还原",8,ink);text(d,537,466,"长按 KEY4 返回",7,ink)
 save_page(im,17+i)
(OUT.parent/"UI_LAYOUT.json").write_text(json.dumps({"version":"full-bleed-ui-v3","size":[640,480],"home_cards":[[24,158,190,244],[225,158,190,244],[426,158,190,244]],"home_focus":[26,160,186,240],"list_focus":[26,141,132,264],"list_step":152,"settings_step":66,"settings_value_y":[160,226,292,358],"waveform":[336,276,192,76],"wave_center_y":316,"audio_status":[284,354,144,16]},ensure_ascii=False,indent=2),encoding="utf-8")
print("Rendered 25 native V3 page PNGs:",OUT)

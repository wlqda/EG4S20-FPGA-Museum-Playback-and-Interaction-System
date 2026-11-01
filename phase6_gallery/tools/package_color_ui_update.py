"""Validate simulated color pages and package the eight replacement bitmaps."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib, json, zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/color_ui_update'
log=(OUT/'simulation.log').read_text(encoding='utf-8',errors='replace')
assert '8 pages, 2457600 aligned RGB pixels' in log
assert '# Errors: 0, Warnings: 0' in log
names=['青铜方鼎','青花瓷瓶','汉代玉璧','唐代陶俑']
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',19)
for start,label in [(7,'详情'),(11,'讲解')]:
    board=Image.new('RGB',(1328,1072),'#e5dfd3');draw=ImageDraw.Draw(board)
    for k in range(4):
        name=f'IMG{start+k:05d}'
        im=Image.open(OUT/(name+'.ppm')).convert('RGB')
        assert im.size==(640,480)
        im.save(OUT/(name+'.png'))
        x=16+(k%2)*656;y=16+(k//2)*528
        draw.text((x,y),names[k]+' · '+label+'（RTL仿真，非实拍）',font=font,fill='#343d38')
        board.paste(im,(x,y+32))
    board.save(OUT/('details.png' if start==7 else 'narration.png'))
notes='''展品详情与讲解配色更新（仅8张BMP）

适用于 museum_full_bleed_all_exhibits_20261026_v3 配套工程和资源。
将 TF_CARD 中8张BMP复制到TF卡根目录并替换同名文件即可。
无需更换bit；不需要删除或格式化TF卡。
保留原轮播、首页、列表、设置、音视频和按键功能。
四组主题色：青铜绿、青花蓝、玉石绿、陶土红。
音频波形继续使用真实PCM与统一朱红色，背景与页面相同。
没有添加虚构的播放进度或时长；GPT概念图的纹样改为简洁几何装饰。
8帧2457600像素经过实际HDL显示流水线仿真，17张其余可进入页面逐像素未变。
未写卡、未上板验证。预览为RTL仿真像素，非实拍。
'''
(OUT/'UPDATE_NOTES.txt').write_text(notes,encoding='utf-8')
manifest=json.loads((OUT/'COLOR_UI_MANIFEST.json').read_text(encoding='utf-8'))
for n,h in manifest['tf_files'].items():assert hashlib.sha256((OUT/'TF_CARD'/n).read_bytes()).hexdigest()==h
manifest['simulation']={'pages':8,'aligned_pixels':2457600,'errors':0,'warnings':0}
(OUT/'COLOR_UI_MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
target=ROOT/'build/museum_color_ui_bitmap_update.zip'
with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:
    for n in manifest['tf_files']:z.write(OUT/'TF_CARD'/n,'TF_CARD/'+n)
    for n in ['UPDATE_NOTES.txt','COLOR_UI_MANIFEST.json','details.png','narration.png']:z.write(OUT/n,n)
with zipfile.ZipFile(target) as z:assert z.testzip() is None
print('PASS',target,'SHA256',hashlib.sha256(target.read_bytes()).hexdigest())

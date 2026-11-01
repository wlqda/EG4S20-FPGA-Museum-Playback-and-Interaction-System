"""Render the three-entry home page; preserve the original four-entry PNG."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
ROOT=Path(__file__).resolve().parents[1]
source=Image.open(ROOT/"assets/base_pages/IMG00005.png").convert("RGB")
scale=3
canvas=source.resize((640*scale,480*scale),Image.Resampling.NEAREST)
draw=ImageDraw.Draw(canvas)
# The cards are opaque; the thin spacing keeps the original page background.
font=ImageFont.truetype("C:/Windows/Fonts/simsun.ttc",22*scale)
small=ImageFont.truetype("C:/Windows/Fonts/arial.ttf",8*scale)
for left,crop,title,subtitle in [
 (24,(24,151,165,402),"展品浏览","COLLECTION"),
 (225,(174,151,315,402),"影像展示","FILM"),
 (426,(474,151,616,402),"系统设置","SETTINGS")]:
 tile=ImageOps.fit(source.crop(crop),(190*scale,251*scale),method=Image.Resampling.LANCZOS)
 canvas.paste(tile,(left*scale,151*scale))
 draw.rectangle((left*scale,332*scale,(left+190)*scale,402*scale),fill=(39,36,31))
 draw.text(((left+12)*scale,343*scale),subtitle,font=small,fill=(208,202,189))
 draw.text(((left+12)*scale,360*scale),title,font=font,fill=(255,255,255))
 draw.line(((left+12)*scale,387*scale,(left+43)*scale,387*scale),fill=(180,172,156),width=scale)
# Clear the two old narrow gaps now covered by wider cards and new gaps.
for a,b in [(214,225),(415,426)]:
 patch=source.crop((316,151,325,402)).resize(((b-a)*scale,251*scale))
 canvas.paste(patch,(a*scale,151*scale))
canvas.resize((640,480),Image.Resampling.LANCZOS).save(ROOT/"assets/home_three_entries.png")
print("Rendered three-entry home page")

# Rebuild the guide-page paper background; waveform/status now overlay the page.
def paper_rect(image, box, anchors):
    x0,y0,x1,y1=box
    for y in range(y0,y1):
        left=image.getpixel((anchors[0],y));right=image.getpixel((anchors[1],y))
        for x in range(x0,x1):
            t=(x-anchors[0])/(anchors[1]-anchors[0])
            image.putpixel((x,y),tuple(round(a+(b-a)*t) for a,b in zip(left,right)))
variants=ROOT/"assets/ui_v2"
variants.mkdir(exist_ok=True)
for index in range(11,15):
    page=Image.open(ROOT/f"assets/base_pages/IMG{index:05d}.png").convert("RGB")
    paper_rect(page,(264,250,610,354),(264,610))
    paper_rect(page,(280,450,416,472),(260,430))
    # The original subtitle overlapped the photograph's top edge.
    paper_rect(page,(24,112,240,125),(0,260))
    subtitle=ImageFont.truetype("C:/Windows/Fonts/simsun.ttc",10)
    ImageDraw.Draw(page).text((24,112),"聆听文物故事",font=subtitle,fill=(124,111,91))
    page.save(variants/f"IMG{index:05d}.png")
print("Rendered four clean guide-page backgrounds")

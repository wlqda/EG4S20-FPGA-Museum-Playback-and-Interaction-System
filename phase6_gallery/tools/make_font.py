"""Generate the small synthesized glyph ROM used by the photo overlays."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
GLYPHS = set(" 0123456789ABCDEF%TF加载中请检查卡资源影像展示播放暂停开启关闭秒")
GLYPHS.update("GILNOX/青铜方鼎花瓷瓶玉璧陶侍女俑")
font = ImageFont.truetype("C:/Windows/Fonts/simsun.ttc", 16)
lines = ["module museum_phase6_font(input [15:0] glyph,input [3:0] row,output reg [15:0] bits);",
         "always @* begin case({glyph,row})"]
for ch in sorted(GLYPHS):
    image = Image.new("1", (16, 16))
    left, top, right, bottom = font.getbbox(ch)
    assert right-left <= 16 and bottom-top <= 16, ch
    ImageDraw.Draw(image).text(((16-(right-left))//2-left, (16-(bottom-top))//2-top), ch, font=font, fill=1)
    for y in range(16):
        value = sum(1 << (15-x) for x in range(16) if image.getpixel((x, y)))
        if value:
            lines.append(f"20'd{ord(ch)*16+y}:bits=16'h{value:04x};")
lines += ["default:bits=0;endcase end", "endmodule"]
(ROOT / "rtl" / "museum_phase5_font.v").write_text("\n".join(lines)+"\n", encoding="utf-8")
print(f"Wrote {len(GLYPHS)} glyphs")

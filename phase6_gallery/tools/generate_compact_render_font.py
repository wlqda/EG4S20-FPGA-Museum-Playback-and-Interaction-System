"""Regenerate the renderer ROM from the preserved font and used character literals."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/"rtl/museum_phase5_render.v"
head=p.read_text().split("// Compact, synchronous block-ROM")[0]
chars=set(int(h,16) for h in re.findall(r"16'h([0-9a-fA-F]+)",head))
chars.update(range(48,58));chars.update(range(65,71));chars.update([32,37])
chars.update(ord(c) for c in re.findall(r'"(.)"',head));chars=sorted(chars)
assert len(chars)<=64
font=(ROOT/"rtl/museum_phase5_font.v").read_text()
rows={int(k):int(v,16) for k,v in re.findall(r"20'd(\d+):bits=16'h([0-9a-fA-F]+);",font)}
s="""// Compact, synchronous block-ROM for only glyphs used by this compositor.
module museum_render_font_sync(input clk,input [15:0] glyph,input [3:0] row,output reg [15:0] bits);
 (* ram_style="block" *) reg [15:0] memory[0:1023];
 reg [5:0] slot;
 always @* begin case(glyph)
"""
for n,ch in enumerate(chars):s+=f"16'd{ch}:slot=6'd{n};\n"
s+="default:slot=0;\nendcase end\n initial begin\n"
for n in range(1024):
    value=rows.get((chars[n//16]<<4)|(n%16),0) if n//16<len(chars) else 0
    s+=f"memory[{n}]=16'h{value:04x};\n"
s+="end\n always @(posedge clk)bits<=memory[{slot,row}];\nendmodule\n"
p.write_text(head+s)
print(f"Generated {len(chars)} glyphs, synchronous 1024x16 ROM")

# Keep the separately prefetched status ROM in sync with the same unclipped font.
status_path=ROOT/"visualization/rtl/museum_audio_waveform.v"
status=status_path.read_text()
slots={int(slot):int(char) for char,slot in re.findall(r"16'd(\d+):slot=5'd(\d+);",status)}
status=re.sub(r"memory\[(\d+)\]=16'h[0-9a-fA-F]+;", lambda m: "memory[%s]=16'h%04x;" % (m[1], rows.get((slots.get(int(m[1])//16,32)<<4)|(int(m[1])%16),0)),status)
status_path.write_text(status)

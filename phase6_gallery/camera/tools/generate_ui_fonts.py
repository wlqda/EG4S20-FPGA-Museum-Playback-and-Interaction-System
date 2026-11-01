"""Rebuild compact synchronous 9K glyph ROMs from checked-in bitmap data."""
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[2]
data=json.loads((ROOT/'camera/assets/ui_glyphs_v2.json').read_text())
def rom(name,values):
 chars=sorted(set(values)|{32});bits=(len(chars)-1).bit_length();depth=1<<(bits+4)
 t=[f'module {name}(input clk,input [15:0] glyph,input [3:0] row,output reg [15:0] bits);',f' (* ram_style="bram_9k" *) reg [15:0] memory[0:{depth-1}];',f' reg [{bits-1}:0] slot;', ' integer i;', ' always @* begin case(glyph)']
 t += [f"16'd{c}:slot={bits}'d{i};" for i,c in enumerate(chars)]
 t += [f"default:slot={bits}'d{chars.index(32)};",' endcase end',f' initial begin for(i=0;i<{depth};i=i+1)memory[i]=0;']
 for i,c in enumerate(chars):
  t += [f"memory[{i*16+r}]=16'h{v:04x};" for r,v in enumerate(values.get(c,[0]*16)) if v]
 t += [' end',' always @(posedge clk)bits<=memory[{slot,row}];','endmodule\n']
 return '\n'.join(t)
for kind,rel,module in [('panel','camera/rtl/camera_pose_overlay.v','museum_panel_font_sync'),('render','rtl/museum_phase5_render.v','museum_render_font_sync')]:
 p=ROOT/rel;s=p.read_text();values={int(k):v for k,v in data[kind].items()}
 if kind=='panel':
  used={int(c,16) for c in re.findall(r"panel_char=16'h([0-9a-f]{4})",s)}
  values={k:v for k,v in values.items() if k in used}
 s=s[:s.index('module '+module)]+rom(module,values)
 p.write_text(s)
 print(module,len(values),'glyphs')

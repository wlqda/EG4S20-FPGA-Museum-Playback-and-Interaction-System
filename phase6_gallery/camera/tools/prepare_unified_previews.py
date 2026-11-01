"""Exercise actual museum PCM/clock pipeline plus the new compact status overlay."""
from pathlib import Path
from PIL import Image
import shutil
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/gesture_unified/preview';OUT.mkdir(exist_ok=True)
for i in range(5,30):
    im=Image.open(ROOT/f'assets/ui_v3/pages/IMG{i:05d}.png').convert('RGB')
    pixels=im.get_flattened_data() if hasattr(im,'get_flattened_data') else im.getdata()
    (OUT/f'IMG{i:05d}.hex').write_text(''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in pixels),encoding='ascii')
for i in range(4):shutil.copy2(ROOT/f'build/v3_preview/wave_{i}.hex',OUT/f'wave_{i}.hex')
text=(ROOT/'sim/tb_v3_previews.v').read_text(encoding='utf-8')
text=text.replace('tb_v3_previews','tb_unified_previews').replace('v3_preview/','gesture_unified/preview/')
text=text.replace('gui_rgb,wave_rgb,rgb;','gui_rgb,wave_rgb,rgb,clock_rgb;')
text=text.replace('.out_rgb(rgb));','.out_rgb(clock_rgb));')
instance=''' museum_camera_overlay camera_overlay(.clk(clk),.rst(rst),.de(gui_de2),.x(clock_x),.y(clock_y),.base_rgb(clock_rgb),
 .maintenance(1'b0),.preview_visible(1'b0),.recognition_enabled(1'b1),.background_ready(1'b1),.fault(1'b0),.stage(3'd2),.armed(1'b1),
 .preview_de(1'b0),.preview_clear(1'b0),.preview_x(10'd0),.preview_y(10'd0),.preview_rgb(24'd0),.nav_ready(1'b1),.rgb(rgb));
'''
text=text.replace(' string basename;',instance+' string basename;')
(OUT/'tb_unified_previews.sv').write_text(text,encoding='utf-8')
print('Prepared 25 full-pipeline frames; camera ARMED is a simulated input')

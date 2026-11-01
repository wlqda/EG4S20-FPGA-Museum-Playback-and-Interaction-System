"""Capture full uploaded RGB/mask/cursor overlay with simulated switch states."""
from pathlib import Path
from PIL import Image
import shutil
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/gesture_full/preview';OUT.mkdir(parents=True,exist_ok=True)
for i in range(5,34):
    source=i if i<30 else 11
    asset=ROOT/f'assets/ui_v3/pages/IMG{source:05d}.png'
    if source==5:asset=ROOT/'assets/ui_reference/pages/IMG00005.png'
    im=Image.open(asset).convert('RGB')
    pixels=im.get_flattened_data() if hasattr(im,'get_flattened_data') else im.getdata()
    (OUT/f'IMG{i:05d}.hex').write_text(''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in pixels),encoding='ascii')
for i in range(4):shutil.copy2(ROOT/f'build/v3_preview/wave_{i}.hex',OUT/f'wave_{i}.hex')
text=(ROOT/'sim/tb_v3_previews.v').read_text(encoding='utf-8')
text=text.replace('tb_v3_previews','tb_full_previews').replace('v3_preview/','gesture_full/preview/')
text=text.replace('gui_rgb,wave_rgb,rgb;','gui_rgb,wave_rgb,rgb,clock_rgb,pose_rgb;').replace('.out_rgb(rgb));','.out_rgb(clock_rgb));')
text=text.replace('integer fd,count=0,idx,i,xx,yy;', 'integer fd,count=0,i,xx,yy;')
text=text.replace('idx<=29','idx<=33').replace('page=idx==5','page=idx>=30 ? 4 : idx==5')
text=text.replace('photo=idx>=17 ? idx-17 : 0;','photo=idx>=30 ? 0 : idx>=17 ? idx-17 : 0;')
text=text.replace('idx-11),samples','idx>=30 ? 0 : idx-11),samples')
text=text.replace('25 pages, 7680000','29 pages, 8908800')
instance='''
 integer idx;
 reg camera_de=0,mask_valid=0,skin=0;
 reg [9:0] camera_x=0,camera_y=0;reg [23:0] camera_rgb=0;
 reg [6:0] mask_x=0;reg [5:0] mask_y=0;
 wire show_camera=idx==30 || idx==31;
 wire maintenance=idx==33;
 wire enabled=idx!=31;
 wire is_armed=enabled && !maintenance;
 camera_pose_overlay #(.SWIPE_MODE(1),.MIRROR_X(1),.INTEGRATED_STYLE(1)) full_overlay(
  .clk(clk),.rst(rst),.de(gui_de2),.x(clock_x),.y(clock_y),.base_rgb(clock_rgb),
  .calibration(maintenance),.background_ready(1'b1),.fault(1'b0),.stage(is_armed ? 3'd2 : 3'd0),
  .error(3'd0),.pose(3'd0),.collecting(1'b0),.armed(is_armed),.event_sequence(32'd1),
  .mask_valid(mask_valid),.mask_x(mask_x),.mask_y(mask_y),.skin(skin),
  .preview_de(camera_de),.preview_clear(rst),.preview_x(camera_x),.preview_y(camera_y),.preview_rgb(camera_rgb),
  .nav_ready(1'b1),.target_visible(idx==30),.target_x(10'd352),.target_y(10'd256),
  .preview_enable(show_camera),.diagnostics(maintenance),.rgb(pose_rgb));
 museum_camera_overlay #(.EXTERNAL_ENABLE(1)) status_overlay(.clk(clk),.rst(rst),.de(gui_de2),.x(clock_x),.y(clock_y),
  .base_rgb(pose_rgb),.maintenance(maintenance),.preview_visible(1'b0),.recognition_enabled(enabled),
  .background_ready(1'b1),.fault(1'b0),.stage(is_armed ? 3'd2 : 3'd0),.armed(is_armed),
  .preview_de(1'b0),.preview_clear(1'b0),.preview_x(10'd0),.preview_y(10'd0),.preview_rgb(24'd0),.nav_ready(1'b1),.rgb(rgb));
 task seed_camera;integer cx,cy;begin
  for(cy=0;cy<60;cy=cy+1)for(cx=0;cx<80;cx=cx+1)begin
   camera_de=1;camera_x=cx*8;camera_y=cy*8;camera_rgb={cx[4:0],3'b000,cy[4:0],3'b000,8'h80};
   mask_valid=1;mask_x=cx;mask_y=cy;skin=cx>=30 && cx<50 && cy>=20 && cy<40;
   @(negedge clk);
  end
  mask_valid=0;camera_x=639;camera_y=479;@(negedge clk);camera_de=0;
 end endtask
'''
text=text.replace(' string basename;',instance+' string basename;')
text=text.replace('   fd=$fopen','   if(idx>=30)seed_camera();\n   fd=$fopen')
(OUT/'tb_full_previews.sv').write_text(text,encoding='utf-8')
print('Prepared 29 display frames: 25 museum pages + 4 simulated switch/calibration scenarios')

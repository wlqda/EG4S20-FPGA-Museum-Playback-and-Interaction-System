"""Render 25 actual gallery pages and four gesture view states through the real pipeline."""
from pathlib import Path
from PIL import Image
import shutil
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/gesture_full/delivery_preview';OUT.mkdir(parents=True,exist_ok=True)
for i in range(5,34):
 source=i if i<30 else 11
 asset=ROOT/f'assets/ui_v3/pages/IMG{source:05d}.png'
 if source==5:asset=ROOT/'assets/ui_reference/pages/IMG00005.png'
 im=Image.open(asset).convert('RGB');assert im.size==(640,480)
 (OUT/f'IMG{i:05d}.hex').write_text(''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in im.get_flattened_data()))
for i in range(4):shutil.copy2(ROOT/f'build/v3_preview/wave_{i}.hex',OUT/f'wave_{i}.hex')
s=(ROOT/'sim/tb_v3_previews.v').read_text().replace('tb_v3_previews','tb_delivery_previews').replace('v3_preview/','gesture_full/delivery_preview/')
s=s.replace('gui_rgb,wave_rgb,rgb;','gui_rgb,wave_rgb,rgb,clock_rgb;').replace('.out_rgb(rgb));','.out_rgb(clock_rgb));')
s=s.replace('.gesture_enabled(1\'b0)', '.gesture_enabled(idx!=30)')
s=s.replace('integer fd,count=0,idx,i,xx,yy;', 'integer fd,count=0,i,xx,yy;')
s=s.replace('idx<=29','idx<=33').replace('page=idx==5','page=idx>=30 ? 4 : idx==5').replace('photo=idx>=17 ? idx-17 : 0;','photo=idx>=30 ? 0 : idx>=17 ? idx-17 : 0;').replace('idx-11),samples','idx>=30 ? 0 : idx-11),samples')
s=s.replace('25 pages, 7680000','29 pages, 8908800')
instance="""
 reg camera_de=0,mask_valid=0,skin=0;
 reg [9:0] camera_x=0,camera_y=0;reg [23:0] camera_rgb=0;
 reg [6:0] mask_x=0;reg [5:0] mask_y=0;
 wire show_camera=idx!=31;
 wire mask_view=idx==32;
 camera_pose_overlay #(.SWIPE_MODE(1),.MIRROR_X(1),.INTEGRATED_STYLE(1),.ROI_Y0(16),.ROI_Y1(464)) full_overlay(
  .clk(clk),.rst(rst),.de(gui_de2),.x(clock_x),.y(clock_y),.base_rgb(clock_rgb),
  .calibration(mask_view),.background_ready(1'b1),.fault(idx==33),.stage(3'd2),
  .error(3'd0),.pose(3'd0),.collecting(1'b0),.armed(1'b1),.event_sequence(32'd1),
  .mask_valid(mask_valid),.mask_x(mask_x),.mask_y(mask_y),.skin(skin),
  .preview_de(camera_de),.preview_clear(rst || idx==33),.preview_x(camera_x),.preview_y(camera_y),.preview_rgb(camera_rgb),
  .nav_ready(1'b1),.target_visible(1'b0),.target_x(10'd320),.target_y(10'd240),
  .preview_enable(show_camera),.diagnostics(mask_view),.recognition_enabled(idx!=30),
  .preparing(1'b0),.source_fault(idx==33),.nav_overflow(1'b0),.rgb(rgb));
 function [23:0] camera_pattern(input integer xx,yy);begin camera_pattern={8'(xx*3),8'(yy*4),8'((xx+yy)*2)};end endfunction
 function [23:0] quant(input [23:0] c);begin quant={{c[23:21],c[23:21],c[23:22]},{c[15:13],c[15:13],c[15:14]},{c[7:6],c[7:6],c[7:6],c[7:6]}};end endfunction
 integer source_col,source_row;reg [23:0] expected;
 task seed_camera;integer cx,cy;begin
  for(cy=0;cy<60;cy=cy+1)for(cx=0;cx<80;cx=cx+1)begin
   camera_de=1;camera_x=cx*8;camera_y=cy*8;camera_rgb=camera_pattern(cx,cy);
   mask_valid=1;mask_x=cx;mask_y=cy;skin=cx>=30 && cx<50 && cy>=20 && cy<40;
   @(negedge clk);
  end
  mask_valid=0;camera_x=639;camera_y=479;@(negedge clk);camera_de=0;
 end endtask
"""
s=s.replace('module tb_delivery_previews;', 'module tb_delivery_previews;\n integer idx;')
s=s.replace(' string basename;',instance+' string basename;').replace('   fd=$fopen','   seed_camera();\n   fd=$fopen')
checks="""
   if(!show_camera || !((clock_x>=503 && clock_x<=632 && clock_y>=7 && clock_y<=120) || (clock_x>=504 && clock_x<632 && clock_y>=124 && clock_y<140)))begin
    if(rgb!==clock_rgb)$fatal(1,"overlay touched page outside footprint idx=%0d x=%0d y=%0d",idx,clock_x,clock_y);
   end
   if(show_camera && clock_x>=504 && clock_x<632 && clock_y>=8 && clock_y<120)begin
    source_col=71-((clock_x-504)>>1);source_row=2+((clock_y-8)>>1);
    expected=idx==33 ? 24'he4eadc : mask_view ? ((source_col>=30 && source_col<50 && source_row>=20 && source_row<40) ? 24'h90d0a0 : 24'h101820) : quant(camera_pattern(source_col,source_row));
    if(rgb!==expected)$fatal(1,"ROI pixel idx=%0d x=%0d y=%0d got=%h expected=%h",idx,clock_x,clock_y,rgb,expected);
   end
"""
s=s.replace('   $fwrite(fd,',checks+'   $fwrite(fd,')
(OUT/'tb_delivery_previews.sv').write_text(s)
print('Prepared 29 actual pipeline scenes; synthetic camera and masks')

`timescale 1ns/1ps
module tb_museum_camera_overlay;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,de=0,maintenance=0,preview_visible=1,bg=1,fault=0,armed=1,nav_ready=1;
 reg [2:0] stage=2;reg [9:0] x=0,y=0,px=0,py=0;reg pd=0,clear=0;
 reg [23:0] base=24'hf4eee4,prgb=24'hf08040;wire [23:0] rgb;
 museum_camera_overlay #(.STALE_CYCLES(1000000)) dut(.clk(clk),.rst(rst),.de(de),.x(x),.y(y),.base_rgb(base),
 .maintenance(maintenance),.preview_visible(preview_visible),.recognition_enabled(1'b1),.background_ready(bg),.fault(fault),.stage(stage),.armed(armed),
 .preview_de(pd),.preview_clear(clear),.preview_x(px),.preview_y(py),.preview_rgb(prgb),.nav_ready(nav_ready),.rgb(rgb));
 reg [23:0] pixels[0:307199];integer fd,xx,yy,k;reg passed=0;
 task preview_frame;begin
  for(yy=0;yy<60;yy=yy+1)for(xx=0;xx<80;xx=xx+1)begin
   pd=1;px=xx*8;py=yy*8;
   prgb={xx[4:0],3'b000,yy[4:0],3'b000,8'h40};@(negedge clk);
  end
  px=639;py=479;pd=1;@(negedge clk);pd=0;
 end endtask
 task check_preview(input integer sx,sy);reg [7:0] r,g,b,q;reg [23:0] expected;begin
  r=(((79-((sx-456)/2))%32)<<3);g=((((sy-288)/2)%32)<<3);b=8'h40;
  q={r[7:5],g[7:5],b[7:6]};
  expected={{q[7:5],q[7:5],q[7:6]},{q[4:2],q[4:2],q[4:3]},{q[1:0],q[1:0],q[1:0],q[1:0]}};
  x=sx-1;y=sy;de=1;@(negedge clk);x=sx;#1;
  if(rgb!==expected)$fatal(1,"mirrored preview mismatch xy%0d,%0d got%h want%h",sx,sy,rgb,expected);
 end endtask
 task raster(input integer mode);reg chip,window;begin
  fd=$fopen(mode==0 ? "gesture_unified/normal.ppm" : "gesture_unified/maintenance.ppm","w");
  $fwrite(fd,"P3\n640 480\n255\n");
  for(yy=0;yy<525;yy=yy+1)for(xx=0;xx<800;xx=xx+1)begin
   x=xx;y=yy;de=xx<640 && yy<480;base=de ? pixels[yy*640+xx] : 0;#1;
   chip=xx>=488 && xx<616 && yy>=60 && yy<76;
   window=mode==1 && xx>=456 && xx<616 && yy>=288 && yy<408;
   if(de)begin
    if(^rgb===1'bx)$fatal(1,"unknown overlay pixel mode%0d xy%0d,%0d",mode,xx,yy);
    if(!chip && !window && rgb!==base)$fatal(1,"overlay clobbered museum pixel %0d,%0d",xx,yy);
    $fwrite(fd,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
   end else if(rgb!==0)$fatal(1,"nonzero blanking");
   @(negedge clk);
  end
  $fclose(fd);
 end endtask
 initial begin
  $readmemh("color_ui_update/IMG00011.hex",pixels);
  repeat(5)@(negedge clk);rst=0;
  raster(0);preview_frame();maintenance=1;raster(1);
  check_preview(458,290);check_preview(614,406);check_preview(458,398);
  repeat(1000002)@(negedge clk);x=500;y=350;de=1;#1;
  if(rgb!==24'he4eadc)$fatal(1,"stale preview remained visible");
  // Reset/abort invalidates the cached image immediately, without a black fill.
  clear=1;@(negedge clk);clear=0;x=500;y=350;de=1;#1;
  if(rgb!==24'he4eadc)$fatal(1,"cleared preview did not show paper fallback");
  preview_visible=0;#1;if(rgb!==base)$fatal(1,"hidden preview clobbered base");
  passed=1;$display("PASS museum camera overlay: 614400 known pixels, isolated chip, mirrored head/tail RAM, stale/clear and blanking");$finish;
 end
 initial begin #30000000;$fatal(1,"overlay watchdog");end
endmodule

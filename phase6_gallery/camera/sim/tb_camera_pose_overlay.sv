`timescale 1ns/1ps
module tb_camera_pose_overlay #(parameter SWIPE=0,parameter MIRROR=0,parameter INTEGRATED=0,parameter ROI_Y0=48,ROI_Y1=432);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,scan=0;reg [9:0] x=799,y=524;wire de=x<640 && y<480;
 reg [23:0] base_rgb=24'h432187;reg calibration=1,background_ready=1,fault=0;
 reg [2:0] stage=0,error=0,pose=1;reg collecting=0,armed=1;reg [31:0] event_sequence=32'h12345678;
 reg mask_valid=0,skin=0;reg [6:0] mask_x=0;reg [5:0] mask_y=0;
 reg nav_ready=1;wire target_visible=SWIPE;wire [9:0] target_x=352,target_y=256;
 reg preview_de=0,preview_clear=0;reg [9:0] preview_x=0,preview_y=0;
 reg [23:0] preview_rgb=0;
 reg preparing=0,source_fault=0,nav_overflow=0;reg recognition_enabled=1'b1;reg preview_enable=1'b1,diagnostics=1'b1;
 localparam [23:0] EMPTY_COLOR=INTEGRATED ? 24'he4eadc : 24'h050809;
 wire [23:0] rgb;reg passed=0;integer f,ink=0;
 function [23:0] pattern(input integer xx,yy);
  reg [7:0] r,g,b;begin r=xx*3;g=yy*4;b=(xx+yy)*2;pattern={r,g,b};end
 endfunction
 function [23:0] quantized(input integer xx,yy);
  reg [23:0] c;begin c=pattern(xx,yy);
   quantized={{c[23:21],c[23:21],c[23:22]},
              {c[15:13],c[15:13],c[15:14]},
              {c[7:6],c[7:6],c[7:6],c[7:6]}};
  end
 endfunction
 reg [23:0] expected;integer inset_pixels=0,collision,row_test;
 camera_pose_overlay #(.SWIPE_MODE(SWIPE),.MIRROR_X(MIRROR),.INTEGRATED_STYLE(INTEGRATED),.ROI_Y0(ROI_Y0),.ROI_Y1(ROI_Y1)) dut(.*);
 wire [23:0] stale_rgb;
 camera_pose_overlay #(.PREVIEW_STALE_CYCLES(32),.SWIPE_MODE(SWIPE),.INTEGRATED_STYLE(INTEGRATED)) stale_dut(
  .x(10'd512),.y(10'd384),.de(1'b1),.rgb(stale_rgb),.*);
 always @(posedge clk)if(scan)begin
  if(x==799)begin x<=0;y<=y==524 ? 0 : y+1'b1;end else x<=x+1'b1;
 end
 initial begin
  repeat(3)@(negedge clk);
  if(dut.text_rom[0] !== (SWIPE ? 8'd83 : 8'd71) || dut.text_rom[64] !== 8'd75)
   $fatal(1,"Status ROM line alignment");
  rst=0;mask_valid=1;
  for(integer yy=0;yy<60;yy=yy+1)for(integer xx=0;xx<80;xx=xx+1)begin
   mask_x=xx;mask_y=yy;skin=(xx>=30 && xx<50 && yy>=20 && yy<40) || (xx==10 && yy==10);@(negedge clk);
   preview_de=1;preview_x=xx*8;preview_y=yy*8;preview_rgb=pattern(xx,yy);
  end
  // Flush the final preview sample before disabling its write enable.
  @(negedge clk);preview_de=0;
  mask_valid=0;scan=1;f=$fopen("gesture_calibration.ppm","w");$fwrite(f,"P3\n640 480\n255\n");
  repeat(420000)begin
   @(negedge clk);
   if(de)begin
    if(^rgb===1'bx)$fatal(1,"Uninitialized overlay pixel %d %d",x,y);
    $fwrite(f,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
   end
   if(y<16 && rgb==24'he0e8f0)ink=ink+1;
   if(x==279 && y==240 && rgb!=EMPTY_COLOR)$fatal(1,"Mask preceding cell leaked");
   if(x==280 && y==240 && rgb!=24'h90d0a0)$fatal(1,"Synchronous mask first pixel misaligned");
   if(x==200 && y==200 && rgb!==(MIRROR ? EMPTY_COLOR : 24'h90d0a0))$fatal(1,"Asymmetric mask orientation wrong");
   if(x==436 && y==200 && rgb!==(MIRROR ? 24'h90d0a0 : EMPTY_COLOR))$fatal(1,"Mirrored mask orientation wrong");
   if(x==320 && y==280 && rgb!=24'hffcc00)$fatal(1,"Wrist reticle missing");
  end
  $fclose(f);
  if(SWIPE)begin
   while(!(x==352 && y==252))@(negedge clk);
   if(rgb!=24'hffcc00)$fatal(1,"Start zone missing");
   while(!(x==(MIRROR ? 301 : 338) && y==288))@(negedge clk);
   if(rgb!=24'h20ff60)$fatal(1,"Measured target cursor missing");
  end
  if(ink<100)$fatal(1,"Status text missing");
  calibration=0;
  while(!(x==300 && y==240))@(negedge clk);
  if(rgb!=base_rgb)$fatal(1,"Run mode did not preserve real Gallery pixels");
  while(!(x==470 && y==350))@(negedge clk);
  if(rgb!=EMPTY_COLOR)$fatal(1,"Preview visible before complete good source frame");
  preview_de=1;preview_x=639;preview_y=479;
  @(negedge clk);preview_de=0;
  f=$fopen("gesture_gallery_preview.ppm","w");$fwrite(f,"P3\n640 480\n255\n");
  // Begin the image at the top left for a valid standalone PPM.
  while(!(x==0 && y==0))@(negedge clk);
  repeat(420000)begin
   if(de)begin
    if(^rgb===1'bx)$fatal(1,"Unknown Gallery inset pixel %d %d",x,y);
    $fwrite(f,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
    if(x>=464 && x<624 && y>=344 && y<464)begin
     expected=quantized(MIRROR ? 79-((x-464)>>1) : (x-464)>>1,(y-344)>>1);
     if(x==464 || x==623 || y==344 || y==463)expected=24'h60b8c8;
     if(((x==480 || x==607) && y>=344+ROI_Y0/4 && y<=344+ROI_Y1/4-1) ||
        ((y==344+ROI_Y0/4 || y==344+ROI_Y1/4-1) && x>=480 && x<=607))expected=24'h304860;
     if((x>=538 && x<=550 && (y==403 || y==404)) ||
        (y>=398 && y<=410 && (x==543 || x==544)))expected=24'hffcc00;
     if(SWIPE && (((x==528 || x==560) && y>=390 && y<=418) ||
                      ((y==390 || y==418) && x>=528 && x<=560)))expected=24'hffcc00;
     if(SWIPE && ((x>=(MIRROR ? 532 : 551) && x<=(MIRROR ? 536 : 555) && y==408) ||
                  (y>=406 && y<=410 && x==(MIRROR ? 534 : 553))))expected=24'h20ff60;
     if(rgb!==expected)$fatal(1,"Inset color/address mismatch %d %d got %h expected %h",x,y,rgb,expected);
     inset_pixels=inset_pixels+1;
    end else if(y>=(SWIPE ? 48 : 16) && rgb!==base_rgb)$fatal(1,"Inset overwrote Gallery outside its window");
   end
   @(negedge clk);
  end
  $fclose(f);if(inset_pixels!=19200)$fatal(1,"Incomplete inset coverage");
  if(stale_rgb!==EMPTY_COLOR)$fatal(1,"Missing source samples did not hide stale RGB");
  // Both RAMs: collision forwards the new sample; an unrelated write must not
  // replace the currently displayed camera cell.
  for(collision=0;collision<2;collision=collision+1)begin
   row_test=collision ? 54 : 48;
   while(!(x==500 && y==344+row_test*2))@(negedge clk);
   preview_de=1;preview_x=(MIRROR ? 61 : 18)*8;preview_y=row_test*8;preview_rgb=24'hff0000;
   @(negedge clk);
   if(rgb!==24'hff0000)$fatal(1,"Preview collision did not forward new RGB");
   preview_x=0;preview_y=collision ? 52*8 : 0;preview_rgb=24'h0000ff;
   @(negedge clk);preview_de=0;
   if(rgb!==quantized(MIRROR ? 60 : 19,row_test))$fatal(1,"Unrelated camera write corrupted display RGB");
  end
  preview_clear=1;@(negedge clk);preview_clear=0;
  while(!(x==470 && y==350))@(negedge clk);
  if(rgb!=EMPTY_COLOR)$fatal(1,"Aborted source left stale RGB visible");
  if(INTEGRATED)begin
   preview_enable=0;diagnostics=0;
   repeat(420000)begin
    @(negedge clk);
    if(de && rgb!==base_rgb)$fatal(1,"SW2 off left a window/cursor/text pixel");
   end
   preview_enable=1;diagnostics=1;
  end
  fault=1;@(negedge clk);calibration=1;background_ready=0;
  while(!(x==280 && y==240))@(negedge clk);
  if(rgb!=EMPTY_COLOR)$fatal(1,"Invalid background displayed old mask");
  passed=1;$display("PASS pose overlay: 19200 RGB inset pixels, RAM split/collisions, invalidation, wrist reticle, text, Gallery passthrough");$finish;
 end
 initial begin #(INTEGRATED ? 45000000 : 30000000);$fatal(1,"watchdog");end
endmodule

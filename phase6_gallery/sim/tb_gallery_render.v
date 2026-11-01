`timescale 1ns/1ps
module tb_gallery_render;
 reg clk=0;always #5 clk=~clk;
 reg [9:0] x=0,y=0;reg [23:0] base=24'h804020;
 reg [4:0] fade=16;reg [3:0] photo=0;reg [1:0] zoom=0;
 reg active=1,visible=1,valid=1;wire [23:0] rgb;reg passed=0;
 integer i,j,title_ink=0,logo_ink=0,zoom_ink=0;
 museum_phase6_render dut(.clk(clk),.rst(1'b0),.x(x),.y(y),.active(active),
  .base_rgb(base),.page(4'd7),.focus(2'd0),.gesture_enabled(1'b0),.editing(1'b0),.autoplay(1'b1),
  .photo_index(photo),.zoom(zoom),.fade_level(fade),.interval_seconds(6'd8),
  .volume(9'd256),.brightness(9'd256),.image_mode(1'b1),.playing(1'b0),.paused(1'b0),
  .screen_visible(visible),.frame_valid(valid),.media_error(8'd0),.out_rgb(rgb));
 task sample;input [9:0] px,py;begin @(negedge clk);x=px;y=py;repeat(2)@(posedge clk);#1;end endtask
 initial begin
  sample(200,200);if(rgb!=base)$fatal(1,"full-opacity photo pixel");
  fade=8;sample(200,200);if(rgb!=24'h402010)$fatal(1,"half-opacity photo pixel %h",rgb);
  fade=0;sample(200,200);if(rgb!=24'h000000)$fatal(1,"fade-to-black photo pixel");
  fade=16;
  for(i=0;i<640;i=i+1)begin
   sample(i,0);if(rgb!=base)$fatal(1,"top edge masked at %0d",i);
   sample(i,479);if(rgb!=base)$fatal(1,"bottom edge masked at %0d",i);
  end
  for(j=1;j<479;j=j+1)begin
   sample(0,j);if(rgb!=base)$fatal(1,"left edge masked");
   sample(639,j);if(rgb!=base)$fatal(1,"right edge masked");
  end
  fade=8;sample(12,12);if(rgb!=24'h402010)$fatal(1,"header must fade with full photo");
  sample(560,440);if(rgb!=24'h402010)$fatal(1,"footer must fade with full photo");fade=16;
  zoom=2;
  for(j=22;j<38;j=j+1)for(i=560;i<592;i=i+1)begin
   sample(i,j);if(rgb!=base)zoom_ink=zoom_ink+1;
  end
  if(zoom_ink<8)$fatal(1,"zoom indicator missing");
  passed=1;$display("PASS gallery render: full-bleed edges, header/footer fade and zoom indicator");$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule

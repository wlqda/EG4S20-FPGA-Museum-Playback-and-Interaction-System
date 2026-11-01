`timescale 1ns/1ps
module tb_home_alignment;
 reg clk=0;always #5 clk=~clk;
 reg rst=1;reg [9:0] x=0,y=0;reg [1:0] focus=0;
 reg [23:0] pixels[0:307199];reg [23:0] base=0,expected;
 wire [23:0] rgb;integer i,j,f,l,r,fd,count=0;reg passed=0;
 museum_phase6_render dut(.clk(clk),.rst(rst),.x(x),.y(y),.active(1'b1),
  .base_rgb(base),.page(4'd0),.focus(focus),.photo_index(4'd0),.zoom(2'd0),.fade_level(5'd16),
  .gesture_enabled(1'b0),.editing(1'b0),.autoplay(1'b1),.interval_seconds(6'd8),.volume(9'd256),.brightness(9'd256),
  .image_mode(1'b1),.playing(1'b0),.paused(1'b0),.screen_visible(1'b1),.frame_valid(1'b1),
  .media_error(8'd0),.out_rgb(rgb));
 initial begin
  $readmemh("gesture_full/home_background.hex",pixels);
  repeat(3)@(negedge clk);rst=0;
  for(f=0;f<3;f=f+1)begin
   focus=f;l=f==0 ? 27 : f==1 ? 227 : 423;r=f==0 ? 217 : f==1 ? 413 : 615;
   fd=$fopen($sformatf("gesture_full/home_focus_%0d.ppm",f),"w");
   $fwrite(fd,"P3\n640 480\n255\n");
   for(j=0;j<480;j=j+1)for(i=0;i<640;i=i+1)begin
    @(negedge clk);x=i;y=j;base=pixels[j*640+i];
    expected=((i>=l && i<r && (j==165 || j==166 || j==410 || j==411)) ||
     (j>=165 && j<412 && (i==l || i==l+1 || i==r-2 || i==r-1))) ? 24'ha63826 : base;
    repeat(2)@(posedge clk);#1;
    if(rgb!==expected)$fatal(1,"focus %0d pixel (%0d,%0d): %h != %h",f,i,j,rgb,expected);
    $fwrite(fd,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);count=count+1;
   end
   $fclose(fd);
  end
  passed=1;$display("PASS home alignment: three selections, %0d pixels, exact current bitmap; all non-border pixels preserved",count);$finish;
 end
 initial begin #30000000;$fatal(1,"home alignment watchdog");end
endmodule

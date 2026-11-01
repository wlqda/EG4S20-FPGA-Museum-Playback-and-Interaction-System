`timescale 1ns/1ps
module tb_render_pipeline;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,active=0,editing=0,image_mode=1,paused=0;
 reg [9:0] x=0,y=0;reg [23:0] base=0,previous=0;
 reg [3:0] page=0,photo=0;reg [1:0] focus=0;reg [4:0] fade=16;reg [7:0] error=0;
 wire [23:0] reference_rgb,rgb;integer f,xx,yy,checks=0;reg passed=0;
 museum_render_reference reference(.clk(clk),.rst(rst),.x(x),.y(y),.active(active),.base_rgb(base),
 .page(page),.focus(focus),.editing(editing),.autoplay(1'b1),.photo_index(photo),.zoom(2'd2),
 .fade_level(fade),.interval_seconds(6'd37),.volume(9'd143),.brightness(9'd209),
 .image_mode(image_mode),.playing(1'b1),.paused(paused),.screen_visible(1'b1),
 .frame_valid(1'b1),.media_error(error),.out_rgb(reference_rgb));
 museum_phase6_render dut(.clk(clk),.rst(rst),.x(x),.y(y),.active(active),.base_rgb(base),
 .page(page),.focus(focus),.gesture_enabled(1'b0),.editing(editing),.autoplay(1'b1),.photo_index(photo),.zoom(2'd2),
 .fade_level(fade),.interval_seconds(6'd37),.volume(9'd143),.brightness(9'd209),
 .image_mode(image_mode),.playing(1'b1),.paused(paused),.screen_visible(1'b1),
 .frame_valid(1'b1),.media_error(error),.out_rgb(rgb));
 integer home_l,home_r;
 reg [23:0] home_expected_q;
 always @(posedge clk)begin
  home_l=focus==0 ? 27 : focus==1 ? 227 : 423;
  home_r=focus==0 ? 217 : focus==1 ? 413 : 615;
  home_expected_q<=!active ? 0 :
   ((x>=home_l && x<home_r && (y==165 || y==166 || y==410 || y==411)) ||
    (y>=165 && y<412 && (x==home_l || x==home_l+1 || x==home_r-2 || x==home_r-1))) ? 24'ha63826 : base;
 end
 task pixel;begin
  @(posedge clk);#1;
  if(!rst && checks>2 && rgb!==previous)$fatal(1,"pipeline pixel mismatch frame=%0d xy=%0d,%0d got=%h expected=%h",f,x,y,rgb,previous);
  previous=page==0 && image_mode && error==0 ? home_expected_q : reference_rgb;checks=checks+1;@(negedge clk);
 end endtask
 initial begin
  pixel;pixel;rst=0;
  for(f=0;f<12;f=f+1)begin
   page=f<8 ? f : 7;photo=f;focus=f%4;editing=f%2;image_mode=f!=8;
   paused=f%2;fade=f==9 ? 8 : f==10 ? 0 : 16;error=f==11 ? 8'h92 : 0;
   for(yy=0;yy<481;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin
    x=xx;y=yy;active=yy<480;base={xx[7:0],yy[7:0],8'h5a};pixel;
   end
  end
  passed=1;$display("PASS render pipeline: %0d consecutive pixels, all pages, video, error, fade, blanking",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule

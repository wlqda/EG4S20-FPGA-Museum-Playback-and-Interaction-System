`timescale 1ns/1ps
module tb_status_rom;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,active=0,paused=0,loading=0,ended=0;
 reg [9:0] x=0,y=0;reg [23:0] base=24'h123456;reg [7:0] error=0;
 wire [23:0] reference_rgb,rgb;integer f,xx,yy,checks=0;reg passed=0;
 museum_waveform_reference reference(.clk(clk),.rst(rst),.x(x),.y(y),.active(active),.base_rgb(base),.enabled(1'b1),
 .paused(paused),.loading(loading),.ended(ended),.error(error),.sample_valid(1'b0),.sample_data(24'd0),.clear(1'b0),.out_rgb(reference_rgb));
 museum_audio_waveform dut(.clk(clk),.rst(rst),.x(x),.y(y),.active(active),.base_rgb(base),.enabled(1'b1),
 .paused(paused),.loading(loading),.ended(ended),.error(error),.sample_valid(1'b0),.sample_data(24'd0),.clear(1'b0),.out_rgb(rgb));
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(f=0;f<6;f=f+1)begin
   paused=f==1;loading=f==2;ended=f==3;error=f==4 ? 8'h92 : f==5 ? 8'hAF : 0;
   for(yy=0;yy<481;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin
    x=xx;y=yy;active=yy<480;
    @(posedge clk);#1;
    if(rgb!==reference_rgb)$fatal(1,"status ROM mismatch f=%0d xy=%0d,%0d got=%h expected=%h",f,xx,yy,rgb,reference_rgb);
    checks=checks+1;@(negedge clk);
   end
  end
  passed=1;$display("PASS status ROM: %0d pixels, playing/pause/loading/EOF/numeric and hex errors",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule

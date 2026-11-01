`timescale 1ns/1ps
module tb_audio_waveform;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [9:0] x=0,y=0;reg active=1,enabled=1,paused=0,loading=0,ended=0,sv=0,clear=0;
 reg [23:0] sample=0;wire [23:0] rgb;reg passed=0;integer i;
 museum_audio_waveform dut(.clk(clk),.rst(rst),.x(x),.y(y),.active(active),
  .base_rgb(24'h112233),.enabled(enabled),.paused(paused),.loading(loading),.ended(ended),
  .error(8'd0),.sample_valid(sv),.sample_data(sample),.clear(clear),.out_rgb(rgb));
 task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
 task pixel;input integer px,py;input [23:0] expected;begin
  x=px-1;y=py;cycles(1);x=px;cycles(1);
  if(rgb!==expected)$fatal(1,"wave pixel %d,%d got %h expected %h",px,py,rgb,expected);
 end endtask
 initial begin
  cycles(3);rst=0;
  for(i=0;i<1536;i=i+1)begin sv=1;sample=i%2 ? 24'h400000 : 24'hc00000;cycles(1);end
  sv=0;
  if(!dut.pending || dut.trace_valid)$fatal(1,"snapshot published before frame boundary");
  x=0;y=480;cycles(1);
  if(!dut.trace_valid || !dut.bank)$fatal(1,"snapshot missing");
  pixel(354,300,24'ha63826);pixel(354,332,24'ha63826);pixel(354,299,24'h112233);
  pixel(330,240,24'h112233);pixel(450,40,24'h112233);
  paused=1;sv=1;sample=0;cycles(50);sv=0;
  if(dut.column!=0 || dut.n!=0)$fatal(1,"pause did not freeze capture");
  pixel(354,300,24'ha63826);
  clear=1;cycles(1);clear=0;if(dut.trace_valid)$fatal(1,"clear retained trace");
  enabled=0;pixel(354,300,24'h112233);
  passed=1;$display("PASS waveform: real min/max, atomic frame swap, pixel coordinates, pause, clear, hidden");$finish;
 end
 initial begin #100000;$fatal(1,"watchdog");end
endmodule

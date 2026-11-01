`timescale 1ns/1ps
module tb_slide_switch;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,sw=0;wire enabled;reg passed=0;
 museum_slide_switch #(.STABLE_CYCLES(8)) dut(.clk(clk),.rst(rst),.switch_in(sw),.enabled(enabled));
 task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
 initial begin
  cycles(2);rst=0;sw=1;cycles(4);sw=0;cycles(10);
  if(enabled)$fatal(1,"bounce changed switch");
  sw=1;cycles(9);if(enabled)$fatal(1,"enabled before stable interval");
  cycles(2);if(!enabled)$fatal(1,"stable high ignored");
  sw=0;cycles(4);sw=1;cycles(10);if(!enabled)$fatal(1,"low bounce changed switch");
  sw=0;cycles(11);if(enabled)$fatal(1,"stable low ignored");
  rst=1;cycles(1);if(enabled)$fatal(1,"reset");
  passed=1;$display("PASS slide switch: synchronizer, bounce rejection, stable high/low, reset");$finish;
 end
endmodule
